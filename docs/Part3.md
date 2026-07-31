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

### 1) Enable A2A on both sub-agents

Both `audit-status-agent` and `policy-audit-info-agent` are prompt agents. Prompt agents support the responses protocol by default, so either can be exposed as an A2A endpoint. Enabling A2A requires a PATCH that provides an **agent card** and activates the `a2a` protocol on the endpoint.

The agent card's `AgentDescription` is what the orchestrator's model reads to decide when to delegate — write it with the orchestrator's routing logic in mind, not just as a human-readable label.

A convenience script is provided at `scripts/enable-a2a.ps1`. You will run it once per sub-agent.

1. Open a PowerShell terminal at the repo root.
2. Run the script for `audit-status-agent`:

```powershell
.\scripts\enable-a2a.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "audit-status-agent" `
    -AgentDescription  "Provides live compliance scorecard ratings across 7 audit areas and identifies root-cause violations within specific areas. Use for questions about current compliance status, non-compliant areas, or what is driving audit findings."
```

3. Run it again for `policy-audit-info-agent`:

```powershell
.\scripts\enable-a2a.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "policy-audit-info-agent" `
    -AgentDescription  "Answers policy and audit questions grounded exclusively in the connected knowledge base corpus. Returns citations and confidence ratings. Use for questions about regulatory requirements, required audit evidence, or specific policy clauses — not for live compliance status."
```

4. Each script run outputs:
   - The **A2A base URL** for the agent
   - The **connection name** created in the project (defaults to `<agent-name>-a2a`)

Note both connection names — you will reference them when updating the orchestrator configuration.

**Expected result:** Both script runs report `A2A setup complete`. You now have two RemoteA2A connections in your Foundry project.

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

Open `src/orch-agent/orchestrator-agent.json` and fill in all fields:

| Field | Value |
|---|---|
| `name` | `orchestrator-agent` |
| `description` | A short description of the orchestrator |
| `modelDeploymentName` | The deployment name from Part 1 |
| `instructions` | See example below |
| `a2aConnectionNames[0]` | `audit-status-agent-a2a` (printed by the first script run) |
| `a2aConnectionNames[1]` | `policy-audit-info-agent-a2a` (printed by the second script run) |

Example instructions for the orchestrator:

```text
You are an orchestration agent for oil and gas policy and audit workflows.

You have access to two specialized agents:
- "audit-status-agent": provides live compliance scorecard ratings and root-cause violations across 7 audit areas. Use for questions about current compliance posture, what is non-compliant, or what is driving a finding.
- "policy-audit-info-agent": answers regulatory and policy questions grounded exclusively in its knowledge base corpus, with citations. Use for questions about what a regulation requires, what evidence is needed for an audit, or what a specific policy clause says. It cannot answer from general knowledge.

Routing rules:
1. Questions about live status, scores, or findings → audit-status-agent
2. Questions about policy, regulations, or required evidence → policy-audit-info-agent
3. Questions that require both (e.g. "what is driving this finding and what does the regulation say about it?") → call both agents and synthesize the response
4. If neither agent can answer, say so directly — do not speculate
```

#### b) Review the A2A tool scaffold in Program.cs

The code iterates `a2aConnectionNames` and creates an `A2APreviewTool` for each:

```csharp
var a2aTools = new List<A2APreviewTool>();
if (config.A2aConnectionNames is { Count: > 0 })
{
    foreach (var connName in config.A2aConnectionNames)
    {
        var conn = projectClient.Connections.GetConnection(connName);
        a2aTools.Add(new A2APreviewTool { ProjectConnectionId = conn.Id });
    }
}
```

> **Note:** `A2APreviewTool` is currently wired for agent definition creation. If the version of the hosting SDK you have installed does not forward tools through `AsAIAgent()`, you may need to use the toolbox-based pattern described in the [Microsoft Foundry A2A docs](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent?tabs=csharp). The `a2aTools` list is deliberately left ready for that wiring.

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
4. Test a question that should route to `audit-status-agent`:
   > *What areas are currently non-compliant and what is driving those findings?*
5. Test a question that should route to `policy-audit-info-agent`:
   > *What audit evidence is required to demonstrate SPCC compliance at a compressor station?*
6. Test a question that should route to both:
   > *Our Subpart-W area is non-compliant — what does the regulation require and what evidence should we be collecting?*
7. Confirm the orchestrator delegates appropriately in each case and synthesizes the responses.

**Expected result:** The orchestrator routes each question to the correct sub-agent (or both), and returns a coherent answer that reflects the sub-agent's response. Routing decisions should be visible in the playground's tool call trace.
