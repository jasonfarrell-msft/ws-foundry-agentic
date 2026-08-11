using ModelContextProtocol.Server;
using System.ComponentModel;
using System.Text;
using System.Text.Json;

var apiBaseUrl = Environment.GetEnvironmentVariable("AUDIT_API_URL") ?? "http://localhost:8000";
var port = Environment.GetEnvironmentVariable("PORT") ?? "8001";

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

builder.Services.AddLogging(logging => logging.AddConsole());
builder.Services.AddSingleton(new AuditApiOptions(apiBaseUrl));
builder.Services.AddHttpClient();
builder.Services.AddMcpServer()
    .WithHttpTransport(options => options.Stateless = true)
    .WithTools<AuditTools>();

var app = builder.Build();

app.MapMcp();
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();

internal sealed record AuditApiOptions(string BaseUrl);

[McpServerToolType]
internal sealed class AuditTools
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly AuditApiOptions _options;

    public AuditTools(IHttpClientFactory httpClientFactory, AuditApiOptions options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options;
    }

    [McpServerTool(Name = "get_audit_scorecard"), Description("Retrieve the complete audit scorecard with all 7 audit areas and their current compliance status (Compliant, At Risk, or Non-compliant)")]
    public async Task<string> GetAuditScorecard()
    {
        using var client = _httpClientFactory.CreateClient();
        using var response = await client.GetAsync($"{_options.BaseUrl}/scorecard");
        var content = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();
        return content;
    }

    [McpServerTool(Name = "get_audit_area_detail"), Description("Retrieve detailed information about a specific audit area, including its current rating and the root causes of any violations")]
    public async Task<string> GetAuditAreaDetail([Description("The unique identifier for the audit area (e.g., 'spcc_compliance', 'psm_program', 'subpart_w_reporting')")] string area_id)
    {
        using var client = _httpClientFactory.CreateClient();
        using var response = await client.GetAsync($"{_options.BaseUrl}/audit/{area_id}");
        var content = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();
        return content;
    }

    [McpServerTool(Name = "update_audit_area"), Description("Update an audit area's compliance rating and violation causes (used for tracking remediation progress)")]
    public async Task<string> UpdateAuditArea(
        [Description("The unique identifier for the audit area")] string area_id,
        [Description("The new compliance rating (Compliant, At Risk, or Non-compliant)")] string rating,
        [Description("Updated list of violation causes")] string[] violation_causes)
    {
        using var client = _httpClientFactory.CreateClient();

        var payload = JsonSerializer.Serialize(new
        {
            rating,
            violation_causes
        });

        using var requestContent = new StringContent(payload, Encoding.UTF8, "application/json");
        using var response = await client.PutAsync($"{_options.BaseUrl}/audit/{area_id}", requestContent);
        var content = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();
        return content;
    }
}
