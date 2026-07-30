# MCP Server for Audit API

C# MCP server that wraps the FastAPI audit API, exposing three tools:

- `get_audit_scorecard` — GET /scorecard endpoint, returns all 7 audit areas with ratings
- `get_audit_area_detail` — GET /audit/{area_id} endpoint, returns specific area detail with violation causes
- `update_audit_area` — PUT /audit/{area_id} endpoint, updates area rating and violation causes

## Configuration

Set the `AUDIT_API_URL` environment variable to point to the deployed audit API:

```powershell
$env:AUDIT_API_URL = "https://aca-agentws-api-<initials>-lx01.<region>.azurecontainerapps.io"
```

Default: `http://localhost:8000`

## Local Build & Run

```bash
dotnet restore
dotnet run
```

The server listens on stdio (standard input/output) for MCP protocol messages.

## Docker Build

```bash
docker build -t audit-mcp-server:latest .
docker run -e AUDIT_API_URL=http://audit-api:8000 audit-mcp-server:latest
```

## Integration with Foundry Agents

In Foundry, configure the MCP server connection and add the three tools to your agent's capabilities. The agent can then:
1. Call `get_audit_scorecard` to retrieve the full audit state
2. Call `get_audit_area_detail` to drill into specific areas
3. Call `update_audit_area` to mark areas as remediated (Part 3)
