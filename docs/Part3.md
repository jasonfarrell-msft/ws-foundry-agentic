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

A2A is an open protocol for agent-to-agent communication over HTTPS. When you enable A2A on an agent in Foundry, it publishes an **agent card** — a JSON document describing the agent's capabilities. The orchestrator reads that card to decide which sub-agent to call.

In this section you will:
- Expose both sub-agents as A2A endpoints
- Create project connections that store each agent's A2A URL
- Wire the A2A connections into the orchestrator and republish

> **Preview:** The A2A APIs used here are in public preview and are subject to change. Steps target A2A protocol v1.0 with JSONRPC transport.

---

### 1) Enable A2A on both sub-agents

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

> **Note:** The `-AgentDescription` value is what the orchestrator reads when deciding which agent to call. Write it from the orchestrator's perspective, not just as a human-readable label.

**Expected result:** Both script runs report `A2A setup complete`. You now have two RemoteA2A connections in your Foundry project.

---

### 2) Verify the agent card

Confirm that Foundry is serving the agent card for both agents before proceeding.

Run `scripts/verify-agent-card.ps1` once per agent:

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "audit-status-agent"
```

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "policy-audit-info-agent"
```

**Expected result:** Each run prints the agent's name, description, version, and skills. Confirm the `description` field matches what you passed to `enable-a2a.ps1` — this is what the orchestrator will read when deciding how to route requests.

---

### 3) Update the Orchestrator

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

Sample JSON:

```json
{
  "name": "orchestrator-agent",
  "description": "Coordinates audit and policy workflows across connected sub-agents",
  "modelDeploymentName": "gpt-5.4-mini-deployment",
  "instructions": "You are an orchestration agent for oil and gas policy and audit workflows.\n\nYou have access to two specialized agents:\n- \"audit-status-agent\": provides live compliance scorecard ratings and root-cause violations across 7 audit areas. Use for questions about current compliance posture, what is non-compliant, or what is driving a finding.\n- \"policy-audit-info-agent\": answers regulatory and policy questions grounded exclusively in its knowledge base corpus, with citations. Use for questions about what a regulation requires, what evidence is needed for an audit, or what a specific policy clause says. It cannot answer from general knowledge.\n\nRouting rules:\n1. Questions about live status, scores, or findings -> audit-status-agent\n2. Questions about policy, regulations, or required evidence -> policy-audit-info-agent\n3. Questions that require both -> call both agents and synthesize the response\n4. If neither agent can answer, say so directly — do not speculate",
  "a2aConnectionNames": [
    "audit-status-agent-a2a",
    "policy-audit-info-agent-a2a"
  ]
}
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

## Section 3: Validate A2A Communication

### Preamble

Now that the orchestrator is published with A2A connections, test the routing logic in the Foundry playground. The orchestrator should:
- Route status/compliance queries to `audit-status-agent`
- Route policy/regulatory queries to `policy-audit-info-agent`
- Call both agents when questions require both status and policy context
- Refuse questions outside the audit/policy domain

Use these 5 prompts to validate correct routing behavior.

---

### 1) Prompt: Live Compliance Status Query

**Category:** Live compliance status  
**Expected routing:** `audit-status-agent` only

```
What are our current compliance scores across all audit areas? Which areas are non-compliant?
```

**Validation checklist:**
- ✅ Orchestrator routes to `audit-status-agent`
- ✅ Response includes scorecard ratings across 7 audit areas
- ✅ Response identifies non-compliant areas
- ✅ No citations to knowledge base (those come from policy-audit-info-agent)

---

### 2) Prompt: Regulatory Requirements Query

**Category:** Regulatory requirements and audit evidence  
**Expected routing:** `policy-audit-info-agent` only

```
What does 40 CFR Part 80 require for fuel quality testing, and what evidence do we need for an audit?
```

**Validation checklist:**
- ✅ Orchestrator routes to `policy-audit-info-agent`
- ✅ Response includes citations from the knowledge base
- ✅ Response describes required audit evidence
- ✅ No live scorecard data (that comes from audit-status-agent)

---

### 3) Prompt: Combined Status + Regulation Query

**Category:** Finding plus regulation explanation  
**Expected routing:** Both agents

```
Our compliance score for fuel quality testing is red. What specific regulation requirement are we failing to meet, and what evidence should we gather to close this gap?
```

**Validation checklist:**
- ✅ Orchestrator calls both agents
- ✅ Response includes current status from `audit-status-agent` (red compliance score)
- ✅ Response includes regulatory requirement from `policy-audit-info-agent` (with citations)
- ✅ Response synthesizes both into actionable remediation steps

---

### 4) Prompt: Out of Scope Query

**Category:** Question outside audit/policy domain  
**Expected routing:** Neither agent (refusal)

```
How do I set up a Python Flask web server?
```

**Validation checklist:**
- ✅ Orchestrator recognizes this is outside the audit/policy domain
- ✅ Response is "I cannot answer this question" or equivalent
- ✅ No hallucinated answers from either sub-agent
- ✅ No speculative technical content

---

### 5) Prompt: Complex Compliance Validation

**Category:** Multi-step compliance finding + regulatory burden  
**Expected routing:** Both agents

```
We have a finding in the Environmental Compliance area. What root-cause violations are driving this finding, and per EPA regulations, what documentation must we submit to demonstrate remediation?
```

**Validation checklist:**
- ✅ Orchestrator calls `audit-status-agent` (root-cause violations in Environmental Compliance)
- ✅ Orchestrator calls `policy-audit-info-agent` (EPA regulatory documentation requirements)
- ✅ Response connects the finding to the specific regulatory burden
- ✅ Response is grounded in real data, not speculation

---

### Troubleshooting

If a prompt does not route correctly:

1. **Verify both A2A connections are active:**

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "audit-status-agent"

.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "policy-audit-info-agent"
```

2. **Verify connection names in `orchestrator-agent.json` match the names printed by `enable-a2a.ps1`** (defaults to `<agent-name>-a2a`).

3. **Check the orchestrator routing instructions in Foundry:**
   - Open the orchestrator agent
   - Confirm the system prompt contains the routing rules
   - If instructions are unclear, simplify and republish

4. **Review sub-agent card descriptions:**
   - Run `verify-agent-card.ps1` to see what descriptions the orchestrator reads
   - Descriptions should be routing-intent-aware

---

**Expected result:** All 5 prompts validate correctly, demonstrating A2A communication between the orchestrator and both sub-agents.
