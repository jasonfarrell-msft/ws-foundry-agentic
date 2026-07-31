using Azure.AI.Projects.Agents;
using Azure.Identity;
using System.Text.Json;

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: --project-endpoint <uri> --package-path <path>");
    return 1;
}

var projectEndpoint = GetArg("--project-endpoint");
var packagePath = GetArg("--package-path");

if (string.IsNullOrWhiteSpace(projectEndpoint))
{
    Console.Error.WriteLine("Missing --project-endpoint.");
    return 1;
}

if (string.IsNullOrWhiteSpace(packagePath))
{
    Console.Error.WriteLine("Missing --package-path.");
    return 1;
}

var configPath = Path.Combine(packagePath, "orchestrator-agent.json");
if (!File.Exists(configPath))
{
    Console.Error.WriteLine($"Missing published config file: {configPath}");
    return 1;
}

var config = OrchestratorAgentConfig.Load(configPath);
config.Validate();

#pragma warning disable AAIP001
var definition = new HostedAgentDefinition("1", "2Gi")
{
    CodeConfiguration = new CodeConfiguration(
        "dotnet_10",
        ["dotnet", "orch-agent.dll"],
        CodeDependencyResolution.Bundled)
};

definition.Versions.Add(new ProtocolVersionRecord(ProjectsAgentProtocol.Responses, "1.0.0"));

var metadata = new CreateAgentVersionFromCodeMetadata(definition)
{
    Description = config.Description
};
if (metadata.Metadata is null)
{
    Console.Error.WriteLine("Agent metadata bag was not initialized.");
    return 1;
}

metadata.Metadata["agentName"] = config.Name;
metadata.Metadata["modelDeploymentName"] = config.ModelDeploymentName;
metadata.Metadata["runtime"] = "dotnet_10";
metadata.Metadata["dependencyResolution"] = "bundled";
#pragma warning restore AAIP001

var client = new AgentAdministrationClient(new Uri(projectEndpoint), new DefaultAzureCredential());
var version = client.CreateAgentVersionFromCode(config.Name, packagePath, metadata).Value;

WriteStatus(version);

while (version.Status != AgentVersionStatus.Active && version.Status != AgentVersionStatus.Failed)
{
    Thread.Sleep(500);
    version = client.GetAgentVersion(config.Name, version.Version).Value;
    WriteStatus(version);
}

if (version.Status != AgentVersionStatus.Active)
{
    Console.Error.WriteLine($"Publishing failed for agent '{config.Name}' version '{version.Version}'.");
    return 1;
}

Console.WriteLine($"Published agent '{config.Name}' version '{version.Version}'.");
return 0;

static void WriteStatus(ProjectsAgentVersion version)
{
    Console.WriteLine($"Status: {version.Status}");
}

string GetArg(string name)
{
    var index = Array.FindIndex(args, value => string.Equals(value, name, StringComparison.OrdinalIgnoreCase));
    if (index < 0 || index + 1 >= args.Length)
    {
        return string.Empty;
    }

    return args[index + 1];
}

internal sealed record OrchestratorAgentConfig
{
    public const string Placeholder = "__FILL_ME__";

    public string Name { get; init; } = Placeholder;

    public string Description { get; init; } = Placeholder;

    public string ModelDeploymentName { get; init; } = Placeholder;

    public string Instructions { get; init; } = Placeholder;

    public static OrchestratorAgentConfig Load(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<OrchestratorAgentConfig>(
            json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException($"Could not parse {path}.");
    }

    public void Validate()
    {
        RequireValue(Name, nameof(Name));
        RequireValue(Description, nameof(Description));
        RequireValue(ModelDeploymentName, nameof(ModelDeploymentName));
        RequireValue(Instructions, nameof(Instructions));
    }

    private static void RequireValue(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value) || string.Equals(value, Placeholder, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Fill in {name} before publishing the agent.");
        }
    }
}
