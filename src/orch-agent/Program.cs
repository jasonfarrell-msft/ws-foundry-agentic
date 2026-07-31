using Azure.AI.Projects;
using Azure.Identity;
using Azure.AI.AgentServer.Core;
using Azure.AI.AgentServer.Responses;
using Azure.AI.AgentServer.Responses.Models;
using DotNetEnv;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;
using Microsoft.Extensions.AI;

Env.NoClobber().TraversePath().Load();

var configPath = Environment.GetEnvironmentVariable("ORCH_AGENT_CONFIG_PATH") ?? "orchestrator-agent.json";
var config = OrchestratorAgentConfig.Load(configPath);
config.Validate();

var projectEndpoint = new Uri(
    Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT")
    ?? throw new InvalidOperationException("FOUNDRY_PROJECT_ENDPOINT environment variable is not set."));

var projectClient = new AIProjectClient(projectEndpoint, new DefaultAzureCredential());

// ---------------------------------------------------------------------------
// A2A tools (Section 2): for each configured connection name, resolve the
// connection and create an A2APreviewTool ready for agent wiring.
// ---------------------------------------------------------------------------
var a2aTools = new List<A2APreviewTool>();
if (config.A2aConnectionNames is { Count: > 0 })
{
    foreach (var connName in config.A2aConnectionNames)
    {
        var conn = projectClient.Connections.GetConnection(connName);
        a2aTools.Add(new A2APreviewTool { ProjectConnectionId = conn.Id });
    }
}

AIAgent agent = projectClient.AsAIAgent(
    model: config.ModelDeploymentName,
    instructions: config.Instructions,
    name: config.Name,
    description: config.Description);

var builder = WebApplication.CreateBuilder(args);

#pragma warning disable MAAI001
builder.Services.AddSingleton<HostedSessionIsolationKeyProvider, LocalDevSessionIsolationKeyProvider>();
#pragma warning restore MAAI001

#pragma warning disable MAAI001
builder.Services.AddFoundryResponses(agent, new InMemoryAgentSessionStore());
#pragma warning restore MAAI001

var app = builder.Build();
app.MapFoundryResponses("/responses");
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));
app.Run();

internal sealed record OrchestratorAgentConfig
{
    public const string Placeholder = "__FILL_ME__";

    public string Name { get; init; } = Placeholder;

    public string Description { get; init; } = Placeholder;

    public string ModelDeploymentName { get; init; } = Placeholder;

    public string Instructions { get; init; } = Placeholder;

    /// <summary>Optional. One or more RemoteA2A connection names created by enable-a2a.ps1.</summary>
    public IReadOnlyList<string>? A2aConnectionNames { get; init; }

    public static OrchestratorAgentConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new InvalidOperationException($"Missing config file: {path}");
        }

        var json = File.ReadAllText(path);
        return System.Text.Json.JsonSerializer.Deserialize<OrchestratorAgentConfig>(
            json,
            new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException($"Could not parse {path}.");
    }

    public void Validate()
    {
        RequireValue(Name, nameof(Name));
        RequireValue(Description, nameof(Description));
        RequireValue(ModelDeploymentName, nameof(ModelDeploymentName));
        RequireValue(Instructions, nameof(Instructions));
        // A2aConnectionNames is optional; validate only when provided
        if (A2aConnectionNames is not null)
            foreach (var name in A2aConnectionNames)
                RequireValue(name, nameof(A2aConnectionNames));
    }

    private static void RequireValue(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value) || string.Equals(value, Placeholder, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Fill in {name} before publishing the agent.");
        }
    }
}

#pragma warning disable MAAI001
sealed class LocalDevSessionIsolationKeyProvider : HostedSessionIsolationKeyProvider
#pragma warning restore MAAI001
{
    private const string LocalDevUserId = "local-dev-user";

#pragma warning disable MAAI001
    public override ValueTask<HostedSessionContext?> GetKeysAsync(
        ResponseContext context,
        CreateResponse request,
        CancellationToken cancellationToken)
    {
        var userId = context.PlatformContext?.UserIdKey;
        if (!string.IsNullOrWhiteSpace(userId))
        {
            return ValueTask.FromResult<HostedSessionContext?>(new HostedSessionContext(userId));
        }

        return ValueTask.FromResult<HostedSessionContext?>(new HostedSessionContext(LocalDevUserId));
    }
#pragma warning restore MAAI001
}
