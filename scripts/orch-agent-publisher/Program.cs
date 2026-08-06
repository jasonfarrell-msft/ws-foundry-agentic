using Azure.AI.Projects.Agents;
using Azure.Identity;
using System.ClientModel;
using System.Collections.Generic;
using System.Reflection;
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
var responsesProtocol = new ProtocolVersionRecord(ProjectsAgentProtocol.Responses, "2.0.0");
var definition = new HostedAgentDefinition([responsesProtocol], "1", "2Gi")
{
    CodeConfiguration = new CodeConfiguration(
        "dotnet_10",
        ["dotnet", "orch-agent.dll"],
        CodeDependencyResolution.Bundled)
};

// The SDK's Versions property serializes to protocol_versions (external caller protocol).
// Foundry also requires container_protocol_versions (internal container routing protocol).
// The SDK doesn't expose a public property for this field, so we inject it via reflection.
SetContainerProtocolVersions(definition, [responsesProtocol]);

var metadata = new AgentVersionFromCodeMetadata(definition)
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

// Use AzureCliCredential directly — most reliable on local dev machines
var credential = new AzureCliCredential();
var client = new AgentAdministrationClient(new Uri(projectEndpoint), credential);
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

#pragma warning disable AAIP001
static void SetContainerProtocolVersions(HostedAgentDefinition definition, IEnumerable<ProtocolVersionRecord> versions)
{
    // The SDK serializes Versions → protocol_versions (external callers).
    // Foundry needs container_protocol_versions (internal container routing) which has no public property.
    // Inject it via the _additionalBinaryDataProperties backing field used by the SDK serializer.
    var addlPropsField = typeof(HostedAgentDefinition)
        .GetField("_additionalBinaryDataProperties", BindingFlags.NonPublic | BindingFlags.Instance)
        ?? throw new InvalidOperationException("SDK internals changed: _additionalBinaryDataProperties field not found on HostedAgentDefinition.");

    var dict = addlPropsField.GetValue(definition) as IDictionary<string, BinaryData>
               ?? new Dictionary<string, BinaryData>();
    if (addlPropsField.GetValue(definition) is null)
        addlPropsField.SetValue(definition, dict);

    var versionsJson = System.Text.Json.JsonSerializer.Serialize(
        versions.Select(v => new { protocol = v.Protocol.ToString(), version = v.Version }));
    dict["container_protocol_versions"] = BinaryData.FromString(versionsJson);
}
#pragma warning restore AAIP001

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
