using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.AI.Projects;
using Azure.Core;
using Azure.Identity;
using Azure.AI.AgentServer.Responses;
using DotNetEnv;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry;
using Microsoft.Agents.AI.Foundry.Hosting;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

Env.NoClobber().TraversePath().Load();

var configPath = Environment.GetEnvironmentVariable("REMEDIATION_AGENT_CONFIG_PATH") ?? "remediation-agent.json";
var config = RemediationAgentConfig.Load(configPath);
config.Validate();
Console.WriteLine("[BOOT] Remediation agent startup marker: v26-a2a-auth-fix");
Console.WriteLine($"[BOOT] FOUNDRY_HOSTING_ENVIRONMENT={Environment.GetEnvironmentVariable("FOUNDRY_HOSTING_ENVIRONMENT") ?? "(null)"}");
Console.WriteLine($"[BOOT] FOUNDRY_AGENT_NAME={Environment.GetEnvironmentVariable("FOUNDRY_AGENT_NAME") ?? "(null)"}");
Console.WriteLine($"[BOOT] FOUNDRY_AGENT_VERSION={Environment.GetEnvironmentVariable("FOUNDRY_AGENT_VERSION") ?? "(null)"}");
var diagnosticsEnabled = string.Equals(Environment.GetEnvironmentVariable("ORCH_DIAGNOSTICS"), "1", StringComparison.OrdinalIgnoreCase);

var projectEndpointStr =
    Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT")
    ?? Environment.GetEnvironmentVariable("AZURE_AI_PROJECT_ENDPOINT")
    ?? config.ProjectEndpoint;
if (string.IsNullOrWhiteSpace(projectEndpointStr))
{
    Console.WriteLine("[WARNING] No project endpoint available from env or config.");
    Console.WriteLine("[WARNING] Set FOUNDRY_PROJECT_ENDPOINT or AZURE_AI_PROJECT_ENDPOINT, or add projectEndpoint in remediation-agent.json.");
}

AIProjectClient? projectClient = null;
if (!string.IsNullOrWhiteSpace(projectEndpointStr))
{
    var projectEndpoint = new Uri(projectEndpointStr);
    projectClient = new AIProjectClient(projectEndpoint, new DefaultAzureCredential());
}

// ---------------------------------------------------------------------------
// A2A tools: authenticated function tools that call sub-agents via the A2A
// protocol (JSON-RPC 2.0 over HTTPS).
//
// FoundryAITool.CreateA2ATool has no credential parameter — it makes
// unauthenticated HTTP requests and fails with 401 when calling Foundry
// prompt agents. Instead we create standard AIFunction tools that:
//   1. Acquire a bearer token for https://ai.azure.com using DefaultAzureCredential
//      (picks up ManagedIdentityCredential automatically in a hosted container).
//   2. POST the A2A message/send JSON-RPC request with the Authorization header.
//   3. Extract and return the agent's text response.
// ---------------------------------------------------------------------------
var a2aCredential = new DefaultAzureCredential();
var a2aTools = new List<AITool>();
var mcpServerUrl =
    Environment.GetEnvironmentVariable("AUDIT_MCP_SERVER_URL")
    ?? config.McpServerUrl;
var mcpTools = new List<AITool>();
McpClient? mcpClient = null;
HttpClientTransport? mcpTransport = null;
var allowedAuditAreas = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
{
    "spcc-compliance",
    "psm-program",
    "subpart-w-ghg",
    "rcra-waste",
    "pipeline-safety",
    "environmental-controls",
    "incident-corrective"
};

// The orchestrator sometimes sends the human-readable audit area name instead of
// the canonical ID, so accept either form and normalize to the canonical ID.
var auditAreaAliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
{
    ["SPCC Compliance"] = "spcc-compliance",
    ["PSM Program Controls"] = "psm-program",
    ["Subpart-W GHG Reporting"] = "subpart-w-ghg",
    ["RCRA Hazardous Waste"] = "rcra-waste",
    ["Pipeline Safety (49-CFR-192/195)"] = "pipeline-safety",
    ["Pipeline Safety"] = "pipeline-safety",
    ["Environmental Controls (CWA/CAA)"] = "environmental-controls",
    ["Environmental Controls"] = "environmental-controls",
    ["Incident & Corrective Actions"] = "incident-corrective"
};

string NormalizeAuditAreaId(string value)
{
    var trimmed = (value ?? string.Empty).Trim();
    if (allowedAuditAreas.Contains(trimmed))
    {
        return trimmed;
    }

    if (auditAreaAliases.TryGetValue(trimmed, out var canonical))
    {
        return canonical;
    }

    var collapsed = trimmed.Replace('_', '-');
    if (allowedAuditAreas.Contains(collapsed))
    {
        return collapsed;
    }

    throw new InvalidOperationException(
        $"Audit area '{trimmed}' is not allowlisted. Use a canonical audit area ID such as psm-program.");
}

if (!string.IsNullOrWhiteSpace(mcpServerUrl))
{
    if (!Uri.TryCreate(mcpServerUrl, UriKind.Absolute, out var mcpEndpoint)
        || mcpEndpoint.Scheme is not ("http" or "https"))
    {
        throw new InvalidOperationException("McpServerUrl must be an absolute HTTP or HTTPS URL.");
    }

    for (var attempt = 1; attempt <= 3; attempt++)
    {
        var candidateTransport = new HttpClientTransport(new HttpClientTransportOptions
        {
            Endpoint = mcpEndpoint,
            TransportMode = HttpTransportMode.StreamableHttp
        });

        try
        {
            mcpClient = await McpClient.CreateAsync(candidateTransport);
            mcpTransport = candidateTransport;
            break;
        }
        catch when (attempt < 3)
        {
            await candidateTransport.DisposeAsync();
            await Task.Delay(TimeSpan.FromSeconds(attempt * 2));
        }
    }

    if (mcpClient is null || mcpTransport is null)
        throw new InvalidOperationException("Could not connect to the audit MCP server after three attempts.");

    Console.WriteLine($"[MCP] Connected to audit server at {mcpEndpoint}");

    var capturedMcpClient = mcpClient;
    var remediationTool = AIFunctionFactory.Create(
        async ([System.ComponentModel.Description("Canonical audit area ID such as psm-program, spcc-compliance, or incident-corrective. Always use the hyphenated ID, never the display name.")] string area_id,
               [System.ComponentModel.Description("Target simulated rating. Use Compliant only for this workshop remediation.")] string rating,
               [System.ComponentModel.Description("The updated list of remaining violation causes.")] string[] violation_causes,
               [System.ComponentModel.Description("The plan ID returned by the orchestrator.")] string plan_id,
               [System.ComponentModel.Description("The policy and audit context from the approved plan.")] string remediation_context,
               [System.ComponentModel.Description("Must be exactly Approved.")] string approval_confirmation,
               CancellationToken ct) =>
        {
            if (!string.Equals(approval_confirmation.Trim(), "Approved", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Remediation requires explicit approval.");
            if (string.IsNullOrWhiteSpace(plan_id))
                throw new InvalidOperationException("Remediation requires a non-empty plan ID.");
            if (string.IsNullOrWhiteSpace(remediation_context))
                throw new InvalidOperationException("Remediation requires policy and audit context.");
            if (!string.Equals(rating.Trim(), "Compliant", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("This workshop tool only supports the target rating Compliant.");
            var canonicalAreaId = NormalizeAuditAreaId(area_id);
            if (violation_causes.Length != 0)
                throw new InvalidOperationException("A Compliant audit area must have an empty violation_causes list.");

            var result = await capturedMcpClient.CallToolAsync(
                "update_audit_area",
                new Dictionary<string, object?>
                {
                    ["area_id"] = canonicalAreaId,
                    ["rating"] = "Compliant",
                    ["violation_causes"] = violation_causes
                },
                cancellationToken: ct);

            var responseText = string.Join(
                "\n",
                result.Content.OfType<TextContentBlock>().Select(content => content.Text));

            if (result.IsError == true)
                throw new InvalidOperationException(
                    $"MCP remediation failed for plan '{plan_id}' on area '{canonicalAreaId}': {responseText}");

            return $"Plan {plan_id} applied to {canonicalAreaId}. MCP result: {responseText}";
        },
        name: "apply_approved_remediation",
        description: "Apply one explicitly approved, bounded remediation to the simulated audit service.");
    mcpTools.Add(remediationTool);
}
else
{
    throw new InvalidOperationException(
        "No audit MCP server URL configured. Set mcpServerUrl in remediation-agent.json before publishing the remediation agent.");
}

if (!string.IsNullOrWhiteSpace(projectEndpointStr))
{
    var connectionNames = config.A2aConnectionNames is { Count: > 0 }
        ? config.A2aConnectionNames
        : config.A2aConnectionIds?
            .Select(id => id.Split('/').LastOrDefault())
            .Where(n => n != null)
            .Select(n => n!)
            .ToList();

    if (connectionNames is { Count: > 0 })
    {
        foreach (var connName in connectionNames)
        {
            var agentName = connName.EndsWith("-a2a", StringComparison.OrdinalIgnoreCase)
                ? connName[..^4]
                : connName;
            var a2aEndpointUrl = $"{projectEndpointStr.TrimEnd('/')}/agents/{agentName}/endpoint/protocols/a2a";

            // Capture loop variables for the closure.
            var capturedAgentName = agentName;
            var capturedEndpointUrl = a2aEndpointUrl;
            var capturedCredential = a2aCredential;

            // Function name must be a valid identifier (no hyphens).
            var fnName = capturedAgentName.Replace("-", "_");

            var tool = AIFunctionFactory.Create(
                async ([System.ComponentModel.Description("The task or question to send to this sub-agent.")] string task,
                       CancellationToken ct) =>
                {
                    var tokenResult = await capturedCredential.GetTokenAsync(
                        new TokenRequestContext(["https://ai.azure.com/.default"]), ct);

                    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
                    http.DefaultRequestHeaders.Authorization =
                        new AuthenticationHeaderValue("Bearer", tokenResult.Token);
                    http.DefaultRequestHeaders.Accept.Add(
                        new MediaTypeWithQualityHeaderValue("application/json"));

                    var messageId = Guid.NewGuid().ToString("N");
                    var payload = JsonSerializer.Serialize(new
                    {
                        jsonrpc = "2.0",
                        id = messageId,
                        method = "message/send",
                        @params = new
                        {
                            message = new
                            {
                                messageId,
                                kind = "message",
                                role = "user",
                                parts = new[] { new { kind = "text", text = task } }
                            }
                        }
                    });

                    Console.WriteLine($"[A2A] → {capturedAgentName}: {task[..Math.Min(80, task.Length)]}...");
                    var response = await http.PostAsync(
                        capturedEndpointUrl,
                        new StringContent(payload, Encoding.UTF8, "application/json"),
                        ct);

                    response.EnsureSuccessStatusCode();
                    var responseBody = await response.Content.ReadAsStringAsync(ct);
                    Console.WriteLine($"[A2A] ← {capturedAgentName}: {responseBody[..Math.Min(200, responseBody.Length)]}");

                    // Extract text parts from A2A JSON-RPC 2.0 response.
                    try
                    {
                        using var doc = JsonDocument.Parse(responseBody);
                        if (doc.RootElement.TryGetProperty("result", out var result))
                        {
                            if (result.TryGetProperty("parts", out var parts))
                            {
                                var texts = parts.EnumerateArray()
                                    .Where(p => p.TryGetProperty("kind", out var k) && k.GetString() == "text"
                                             && p.TryGetProperty("text", out _))
                                    .Select(p => p.GetProperty("text").GetString() ?? string.Empty);
                                var joined = string.Join("\n", texts);
                                if (!string.IsNullOrWhiteSpace(joined)) return joined;
                            }
                            // Fallback: return the whole result as JSON.
                            return result.ToString();
                        }
                    }
                    catch (JsonException) { /* fall through to raw response */ }

                    return responseBody;
                },
                name: fnName,
                description: $"Invoke the {capturedAgentName} sub-agent for specialized audit assistance. Send it a specific task or question.");

            a2aTools.Add(tool);
            Console.WriteLine($"[A2A] Registered sub-agent tool '{agentName}': {a2aEndpointUrl}");
        }
    }
}
else if (config.A2aConnectionNames is { Count: > 0 })
{
    Console.WriteLine("[WARNING] A2A connections configured but FOUNDRY_PROJECT_ENDPOINT is not set. Skipping A2A initialization.");
}

AIAgent? agent = null;
try
{
    if (projectClient != null)
    {
        var allTools = a2aTools.Concat(mcpTools).ToList();
        IList<AITool>? tools = allTools.Count > 0 ? allTools : null;
        agent = projectClient.AsAIAgent(
            model: config.ModelDeploymentName,
            instructions: config.Instructions,
            name: config.Name,
            description: config.Description,
            tools: tools);
        var toolSummary = $" ({a2aTools.Count} A2A tool(s), {mcpTools.Count} MCP tool(s))";
        Console.WriteLine($"[OK] Agent initialized with Foundry context{toolSummary}.");
    }
    else
    {
        Console.WriteLine("[WARNING] No Foundry project context available. Attempting fallback initialization...");
        // In Foundry hosted environment, the platform might provide the agent context differently
        // For now, we'll log and continue—the actual agent initialization happens via the platform
        Console.WriteLine("[OK] Proceeding with hosted agent initialization (platform-managed).");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"[ERROR] Agent initialization failed: {ex.Message}");
    Console.WriteLine("[ERROR] Stack trace: " + ex.StackTrace);
    throw;
}

if (agent == null && projectClient == null)
{
    // In Foundry hosted environment, projectClient may be unavailable, but that's OK
    // The platform will handle agent initialization through responses protocol
    Console.WriteLine("[INFO] Running in Foundry hosted mode (projectClient not available).");
    Console.WriteLine("[INFO] Agent will be initialized by the platform.");
}

var builder = WebApplication.CreateBuilder(args);
var listenUrls = Environment.GetEnvironmentVariable("ASPNETCORE_URLS");
if (string.IsNullOrWhiteSpace(listenUrls))
{
    builder.WebHost.UseUrls("http://0.0.0.0:80", "http://0.0.0.0:8080");
}

var responsesReady = agent is not null;
if (agent is { } initializedAgent)
{
    // Pass null for session store → SDK default (FileSystemAgentSessionStore at /.checkpoints
    // in hosted mode, {cwd}/.checkpoints locally). InMemoryAgentSessionStore is not suitable
    // for multi-step hosted sessions where platform may expect filesystem session state.
    // Note: AddFoundryResponses (1.16.0+) internally calls ConfigureFoundryListenPort, which
    // binds Kestrel to port 8088 (the Foundry probe port) instead of port 80 (base image default).
    #pragma warning disable MAAI001
    builder.Services.AddFoundryResponses(initializedAgent, null);
    #pragma warning restore MAAI001
}
else
{
    Console.WriteLine("[WARNING] Agent is null. Foundry responses will not be available.");
}

var app = builder.Build();

if (diagnosticsEnabled)
{
    app.Use(async (context, next) =>
    {
        var selfProbe = context.Request.Headers.TryGetValue("x-orch-self-probe", out var selfProbeValue)
            ? selfProbeValue.ToString()
            : "0";
        var callId = context.Request.Headers.TryGetValue("x-agent-foundry-call-id", out var callIdValue)
            ? callIdValue.ToString()
            : "(none)";
        var userAgent = context.Request.Headers.TryGetValue("User-Agent", out var uaValue)
            ? uaValue.ToString()
            : "(none)";

        Console.WriteLine($"[REQ] {context.Request.Method} {context.Request.Path} callId={callId} selfProbe={selfProbe} ua={userAgent}");

        // For non-self-probe POSTs, dump all headers and body so we can see exactly what Foundry sends
        if (selfProbe == "0" && context.Request.Method == "POST")
        {
            foreach (var header in context.Request.Headers)
                Console.WriteLine($"[HDR] {header.Key}: {header.Value}");

            context.Request.EnableBuffering();
            using var reader = new System.IO.StreamReader(context.Request.Body, leaveOpen: true);
            var body = await reader.ReadToEndAsync();
            context.Request.Body.Position = 0;
            var preview = body.Length > 1000 ? body[..1000] + "...[truncated]" : body;
            Console.WriteLine($"[BODY] {preview}");
        }

        await next();
        Console.WriteLine($"[RES] {context.Request.Method} {context.Request.Path} => {context.Response.StatusCode} selfProbe={selfProbe}");
    });
}

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

if (responsesReady)
{
    // Single MapFoundryResponses() call — dual mapping causes conflicting response handler
    // pipeline registrations. Foundry strips the external /protocols/openai prefix and routes
    // internally to /responses.
    app.MapFoundryResponses();
}

if (diagnosticsEnabled)
{
    foreach (var endpoint in app.Services.GetRequiredService<EndpointDataSource>().Endpoints)
    {
        Console.WriteLine($"[ROUTE] {endpoint.DisplayName}");
    }

    app.Lifetime.ApplicationStarted.Register(() =>
    {
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(1200);
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };

                var probeBaseUrl = Environment.GetEnvironmentVariable("ORCH_SELF_PROBE_BASE_URL");
                if (string.IsNullOrWhiteSpace(probeBaseUrl))
                {
                    var aspnetUrls = Environment.GetEnvironmentVariable("ASPNETCORE_URLS");
                    var firstUrl = aspnetUrls?
                        .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                        .FirstOrDefault(u => u.StartsWith("http://", StringComparison.OrdinalIgnoreCase));
                    probeBaseUrl = firstUrl ?? "http://127.0.0.1:80";
                }

                probeBaseUrl = probeBaseUrl.Replace("://+", "://127.0.0.1").Replace("://*", "://127.0.0.1");
                probeBaseUrl = probeBaseUrl.TrimEnd('/');

                foreach (var path in new[] { "/readiness", "/health" })
                {
                    var url = $"{probeBaseUrl}{path}";
                    var request = new HttpRequestMessage(HttpMethod.Get, url);
                    request.Headers.Add("x-orch-self-probe", "1");
                    request.Headers.UserAgent.ParseAdd("remediation-agent-self-probe");
                    var res = await http.SendAsync(request);
                    Console.WriteLine($"[SELF-PROBE] GET {path} => {(int)res.StatusCode} {res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SELF-PROBE] Failed: {ex.Message}");
            }
        });
    });
}

app.Run();

internal sealed record RemediationAgentConfig
{
    public const string Placeholder = "__FILL_ME__";

    public string Name { get; init; } = Placeholder;

    public string Description { get; init; } = Placeholder;

    public string ModelDeploymentName { get; init; } = Placeholder;

    public string Instructions { get; init; } = Placeholder;

    /// <summary>Optional. One or more RemoteA2A connection names created by enable-a2a.ps1.</summary>
    public IReadOnlyList<string>? A2aConnectionNames { get; init; }

    public string? McpServerUrl { get; init; }

    /// <summary>
    /// Optional. Pre-resolved ARM resource IDs for RemoteA2A connections, injected by
    /// publish-agent.ps1 at publish time. When present, the runtime skips the
    /// GetConnection API call (which requires elevated permissions) and uses these IDs directly.
    /// </summary>
    public IReadOnlyList<string>? A2aConnectionIds { get; init; }

    /// <summary>Optional fallback when env vars do not provide a project endpoint.</summary>
    public string? ProjectEndpoint { get; init; }

    public static RemediationAgentConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new InvalidOperationException($"Missing config file: {path}");
        }


        var json = File.ReadAllText(path);
        return System.Text.Json.JsonSerializer.Deserialize<RemediationAgentConfig>(
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
