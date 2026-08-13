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

    [McpServerTool(Name = "get_audit_scorecard"), Description("")]
    public async Task<string> GetAuditScorecard()
    {
        using var client = _httpClientFactory.CreateClient();
        using var response = await client.GetAsync($"{_options.BaseUrl}/scorecard");
        var content = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();
        return content;
    }

    [McpServerTool(Name = "get_audit_area_detail"), Description("")]
    public async Task<string> GetAuditAreaDetail([Description("")] string area_id)
    {
        using var client = _httpClientFactory.CreateClient();
        using var response = await client.GetAsync($"{_options.BaseUrl}/audit/{area_id}");
        var content = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();
        return content;
    }

    [McpServerTool(Name = "update_audit_area"), Description("")]
    public async Task<string> UpdateAuditArea(
        [Description("")] string area_id,
        [Description("")] string rating,
        [Description("")] string[] violation_causes)
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
