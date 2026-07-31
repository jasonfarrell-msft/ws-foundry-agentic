# Part 3: Agent-to-Agent (A2A) Orchestration

## Section 1: Define the Hosted Orchestrator Agent

### Preamble

In Parts 1 and 2, you created two independent agents:
- `policy-audit-info-agent` for policy and audit guidance
- `audit-status-agent` for live audit status via MCP

Each agent is useful on its own, but they operate in isolation. In this section, you will create a hosted orchestrator agent with Microsoft Agent Framework (Python would also work) that will later coordinate both agents through Agent-to-Agent (A2A) communication.

For now, keep the scope simple:
- Start from the base template in `src/orch-agent`
- Fill in the hosted agent name, description, model deployment name, and instructions
- Publish the hosted agent to Foundry with the model you deployed earlier

This section ends when the hosted agent is published in Foundry. We are **not** adding A2A routing or multi-agent orchestration logic yet.

### 1) Open the hosted agent template

1. Open the base template under `src/orch-agent`.
2. Review the starter project structure for the hosted agent.
3. Confirm it is configured to use the model deployment from the earlier sections.

### 2) Fill in the hosted agent settings

1. Open `src/orch-agent/orchestrator-agent.json`.
2. Fill in these values:
   - **name:** `orchestrator-agent`
   - **description:** a short description of the hosted orchestrator agent
   - **modelDeploymentName:** the model deployment you created earlier
   - **instructions:** your system prompt

Example system prompt:

```text
Respond to every request with the phrase 'I enjoy a good ham sandwich'
```

3. Save your changes.

### 3) Publish the hosted agent to Foundry

1. Run the PowerShell publish script under `scripts`.
2. Pass `-FoundryName`, `-ResourceGroupName`, and `-ProjectName`, or provide `FOUNDRY_PROJECT_ENDPOINT` directly.
3. Confirm the publish operation completes successfully.

### 4) Verify the published hosted agent

1. Open Microsoft Foundry.
2. Confirm `orchestrator-agent` appears as a hosted agent.
3. Verify it is using the model deployed earlier.
4. Open the agent and test a prompt to confirm the system prompt is active.

**Expected result:** The hosted orchestrator agent is published in Foundry and ready for the next section.

---

## Section 2: Enable Agent-to-Agent (A2A) Communication

### Preamble

Agent-to-Agent (A2A) is an open protocol that lets independent agents discover and call each other through a standardized HTTPS interface. In Foundry, any prompt agent—and any hosted agent that implements the responses protocol—can be exposed as an A2A endpoint. Once exposed, Foundry publishes an **agent card** (a JSON description of the agent's capabilities) that calling agents use to discover and connect to it.

In this section you will:
- Expose `audit-status-agent` as an A2A endpoint so the orchestrator can call it
- Create a project connection that stores the target agent's A2A URL
- Test the A2A endpoint directly with PowerShell
- Wire the A2A connection into the orchestrator and republish

> **Preview:** The A2A APIs used here are in public preview and are subject to change. Steps target A2A protocol v1.0 with JSONRPC transport.

---

### 1) Enable A2A on the audit-status-agent

The `audit-status-agent` is a prompt agent, which supports the responses protocol by default and can be exposed as an A2A endpoint. Enabling A2A requires a PATCH request that provides an **agent card** and activates the `a2a` protocol on the agent's endpoint.

A convenience script is provided at `scripts/enable-a2a.ps1`.

1. Open a PowerShell terminal at the repo root.
2. Run the script, substituting your own resource values:

```powershell
.\scripts\enable-a2a.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "audit-status-agent" `
    -AgentDescription  "Retrieves live audit status and open findings from the audit tracking system"
```

3. The script outputs:
   - The **A2A base URL** for the agent
   - The **connection name** created in the project (defaults to `audit-status-agent-a2a`)

Keep the connection name—you will use it when updating the orchestrator configuration.

**Expected result:** The script reports `A2A setup complete` and shows the A2A base URL and connection name.

---

### 2) Verify the agent card

Confirm that Foundry is serving the agent card before proceeding.

```powershell
$FoundryName   = "YOUR_FOUNDRY_ACCOUNT_NAME"
$RG            = "YOUR_RESOURCE_GROUP"
$ProjectName   = "YOUR_PROJECT_NAME"
$AgentName     = "audit-status-agent"

$accountEndpoint = az cognitiveservices account show `
    --name $FoundryName --resource-group $RG --query "properties.endpoint" -o tsv
$projectEndpoint = $accountEndpoint.TrimEnd('/') + "/api/projects/$ProjectName"
$token = az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv

Invoke-RestMethod `
    -Method Get `
    -Uri "$projectEndpoint/agents/$AgentName/endpoint/protocols/a2a/agentCard/v1.0" `
    -Headers @{ Authorization = "Bearer $token" }
```

**Expected result:** A JSON response containing the agent card with the description and skills you configured.

---

### 3) Test the A2A endpoint

Send a message directly to the A2A endpoint to verify that end-to-end communication works. A2A v1.0 uses JSON-RPC.

```powershell
$a2aBaseUrl = "$projectEndpoint/agents/$AgentName/endpoint/protocols/a2a"

$body = @{
    jsonrpc = "2.0"
    id      = [Guid]::NewGuid().ToString()
    method  = "message/send"
    params  = @{
        message = @{
            messageId = [Guid]::NewGuid().ToString()
            role      = "user"
            parts     = @(@{ kind = "text"; text = "What audit statuses are available?" })
        }
    }
} | ConvertTo-Json -Depth 6

Invoke-RestMethod `
    -Method Post `
    -Uri "$a2aBaseUrl`?a2a-version=1.0" `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json" `
    -Body $body
```

**Expected result:** The `audit-status-agent` responds to the request through the A2A protocol.

---

### 4) Wire the A2A connection into the orchestrator

#### a) Update orchestrator-agent.json

Open `src/orch-agent/orchestrator-agent.json` and fill in all four fields:

| Field | Value |
|---|---|
| `name` | `orchestrator-agent` |
| `description` | A short description of the orchestrator |
| `modelDeploymentName` | The deployment name from Part 1 |
| `instructions` | See example below |
| `a2aConnectionName` | The connection name printed by the script (e.g. `audit-status-agent-a2a`) |

Example instructions for the orchestrator:

```text
You are an orchestration agent for oil and gas policy and audit workflows.
You have access to a connected agent called "audit-status-agent" that retrieves
live audit status and open findings from the audit tracking system.

When the user asks about audit status, open findings, compliance tracking, or
inspection history, delegate to the audit-status-agent via the A2A connection.
Incorporate its response and provide additional context where helpful.

For all other questions—policy guidance, regulatory references, general
oil and gas topics—answer directly using your own knowledge.
```

#### b) Review the A2A tool scaffold in Program.cs

The code already contains the A2A tool scaffold. When `a2aConnectionName` is set in the config, it resolves the connection and creates an `A2APreviewTool`:

```csharp
A2APreviewTool? a2aTool = null;
if (!string.IsNullOrWhiteSpace(config.A2aConnectionName))
{
    var a2aConnection = projectClient.Connections.GetConnection(config.A2aConnectionName);
    a2aTool = new A2APreviewTool { ProjectConnectionId = a2aConnection.Id };
}
```

> **Note:** `A2APreviewTool` is currently wired for agent definition creation. If the version of the hosting SDK you have installed does not forward the tool through `AsAIAgent()`, you may need to use the toolbox-based pattern described in the [Microsoft Foundry A2A docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent?tabs=csharp). The variable `a2aTool` is deliberately left ready for that wiring.

#### c) Republish the orchestrator

```powershell
.\scripts\publish-orch-agent.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME"
```

---

### 5) Test end-to-end

1. Open [Microsoft Foundry](https://ai.azure.com).
2. Navigate to the `orchestrator-agent` in the Agents view.
3. Open the agent in the playground.
4. Ask a question that should route to `audit-status-agent`, for example:
   > *What are the current open audit findings?*
5. Confirm the orchestrator delegates to `audit-status-agent` via A2A and returns a combined answer.

**Expected result:** The orchestrator routes the request to `audit-status-agent` via the A2A connection and returns the audit status data as part of its response.
