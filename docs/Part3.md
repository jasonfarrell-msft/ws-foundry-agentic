# Part 3: Agent-to-Agent (A2A) Orchestration with a Prompt Orchestrator

## Objective

Create a **prompt orchestrator agent in Foundry** that routes requests to two specialized sub-agents using **A2A**:

- `audit-status-agent` for live compliance status
- `policy-audit-info-agent` for policy and audit requirements

This part focuses on prompt-agent orchestration only.
**Hosted remediation-agent deployment is intentionally deferred to Part 4 (next module).**

### Prerequisites & Assumptions

**Assumption: Parts 1 and 2 are complete.**

- Foundry project exists and has a working model deployment
- `audit-status-agent` and `policy-audit-info-agent` already exist
- PowerShell 7+ is available

---

## 1) Confirm both sub-agents are A2A-enabled

If you already completed this step earlier, rerun it to ensure configuration is still correct.

1. Open PowerShell at the repo root.
2. Enable A2A for `audit-status-agent`:

   ```powershell
   .\scripts\enable-a2a.ps1 `
       -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
       -ResourceGroupName "YOUR_RESOURCE_GROUP" `
       -ProjectName       "YOUR_PROJECT_NAME" `
       -AgentName         "audit-status-agent" `
       -AgentDescription  "Provides live compliance scorecard ratings across 7 audit areas and identifies root-cause violations within specific areas. Use for questions about current compliance status, non-compliant areas, or what is driving audit findings."
   ```

   **Note the "Agent A2A base URL" printed in the output.** You'll paste this into the orchestrator's A2A Tool configuration in Step 3. The agent card URL is for verification only; do not paste it into the A2A Tool form.

3. Enable A2A for `policy-audit-info-agent`:

   ```powershell
   .\scripts\enable-a2a.ps1 `
       -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
       -ResourceGroupName "YOUR_RESOURCE_GROUP" `
       -ProjectName       "YOUR_PROJECT_NAME" `
       -AgentName         "policy-audit-info-agent" `
       -AgentDescription  "Answers policy and audit questions grounded exclusively in the connected knowledge base corpus. Returns citations and confidence ratings. Use for questions about regulatory requirements, required audit evidence, or specific policy clauses — not for live compliance status."
   ```

   **Again, note the "Agent A2A base URL" printed in the output.** The agent card URL is for verification only.

4. **Record both Agent A2A base URLs** for use in Step 3. The pattern is:
   ```
   https://{foundry-account}.services.ai.azure.com/api/projects/{project}/agents/{agent}/endpoint/protocols/a2a
   ```

**Expected result:** Both runs report A2A setup complete and output the base A2A endpoint and agent card URL.

---

## 2) Verify both agent cards before wiring orchestration

Verify that each sub-agent is discoverable through its agent card:

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

Check each card for:

- Correct `name`
- Clear routing-oriented `description`
- Skills metadata present

> Do not continue until both agent cards resolve successfully.

The portal does not provide a reliable connected/ready indicator for this step. The actual A2A call is validated in the orchestrator playground in Section 4.

---

## 3) Create the Prompt Orchestrator agent in Foundry

1. In the Foundry portal, select **New agent** → **Build your agent**.
2. Create a **Prompt Agent** named `orchestrator-prompt-agent`.
3. Use your model deployment from Part 1.
4. Set the system instructions similar to:

```text
You are an orchestration prompt agent for oil and gas policy and audit workflows.

You have access to two specialized agents:
- audit-status-agent: live compliance scorecard ratings and root-cause violations.
- policy-audit-info-agent: policy/regulatory requirements and required audit evidence, grounded in its knowledge base with citations.

Routing rules:
Before selecting a tool, apply this scope gate:
1. Treat a request as in scope only when it concerns oil-and-gas policy, compliance, audits, controls, evidence, findings, scores, status, remediation, or regulatory interpretation.
2. Treat software, coding, web-server setup, infrastructure, math, finance, and other non-audit or non-policy requests as out of scope.
3. If a request mixes an in-scope subject with an out-of-scope task, classify the entire request as out of scope.
4. For an out-of-scope request, do not call any tool or A2A agent. Reply exactly: `I only handle oil-and-gas policy, compliance, and audit questions.`

After the scope gate passes:
5. Questions about live status, scores, findings, or remediation status -> `audit-status-agent`
6. Questions about policy, regulations, controls, or required evidence -> `policy-audit-info-agent`
7. Questions requiring both operational status and regulatory interpretation -> call both and synthesize
8. When using policy content, preserve citations
```

### Grant the orchestrator identity A2A access

The A2A tool authenticates with the orchestrator's **Agent Identity**. That identity must have the **Foundry Agent Consumer** role on the target project before the tool can fetch an agent card or call a sub-agent.

After creating `orchestrator-prompt-agent`, retrieve its instance identity. Run this from PowerShell after replacing the placeholders:

```powershell
$agent = az rest `
    --method get `
    --url "https://YOUR_FOUNDRY_ACCOUNT_NAME.services.ai.azure.com/api/projects/YOUR_PROJECT_NAME/agents/orchestrator-prompt-agent?api-version=v1" `
    --resource https://ai.azure.com |
    ConvertFrom-Json

$principalId = $agent.instance_identity.principal_id
$subscriptionId = az account show --query id -o tsv
$projectScope = "/subscriptions/$subscriptionId/resourceGroups/YOUR_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/YOUR_FOUNDRY_ACCOUNT_NAME/projects/YOUR_PROJECT_NAME"

az role assignment create `
    --role "Foundry Agent Consumer" `
    --assignee $principalId `
    --scope $projectScope
```

If `instance_identity.principal_id` is not available yet, publish or activate the agent version, then retrieve the agent details again. Role assignment changes can take several minutes to propagate.

### Attach A2A Tools and Connections

#### Step 1: Open the Tools Panel
In the Foundry agent editor:
1. Click **Tools** in the left navigation menu
2. Review the default tools listed — you should see **Web Search** enabled by default

#### Step 2: Remove Web Search Tool
Web Search is enabled by default on new prompt agents but is not needed for this workshop:
1. Find **Web Search** in the Tools list
2. Click the **X** or **Remove** icon next to it
3. Confirm removal when prompted
4. Verify that Web Search no longer appears in the Tools list

#### Step 3: Add A2A Project Connections
The A2A tool accepts the target agent's **base A2A endpoint**. Do not append the agent-card path to the endpoint URL. If the dialog exposes a card-path field, enter `agentCard/v1.0` there.

1. Click the **Add** button to open the tools picker/menu
2. Select **Add Tools**
3. Navigate to the **Custom** tab
4. Select **A2A**
5. A form appears. Fill in the following:
   - **A2A Agent Endpoint:** Paste the first **base A2A URL** (saved from Step 1):
     ```
     https://{foundry-account}.services.ai.azure.com/api/projects/{project}/agents/audit-status-agent/endpoint/protocols/a2a
     ```
   - **Auth type:** Select **Agent Identity**
   - **Audience:** `https://ai.azure.com`
   - **Agent card path:** `agentCard/v1.0`
6. Click **Add** or **Confirm**
7. Repeat steps 1–4, then fill in:
   - **A2A Agent Endpoint:** Paste the second **base A2A URL**:
     ```
     https://{foundry-account}.services.ai.azure.com/api/projects/{project}/agents/policy-audit-info-agent/endpoint/protocols/a2a
     ```
   - **Auth type:** Select **Agent Identity**
   - **Audience:** `https://ai.azure.com`
   - **Agent card path:** `agentCard/v1.0`
8. Click **Add** or **Confirm**

**Note:** Replace `{foundry-account}` and `{project}` with your actual Foundry account name and project name. Use the canonical `services.ai.azure.com` host. Paste the base endpoint in the endpoint field and enter `agentCard/v1.0` in the card-path field; do not append the card path to the endpoint or use `/.well-known/agent-card.json`. **Agent Identity** uses the orchestrator agent's managed identity to authenticate to the sub-agent endpoints. Use `https://ai.azure.com` as the audience.

Before testing, ensure the orchestrator's agent identity has **Foundry Agent Consumer** on `main-project`. The identity is created when the orchestrator is created and may be visible only after publishing. If you receive a 401 while fetching an agent card, treat it as an Entra/RBAC or endpoint-configuration issue, not a routing issue.

> **Scope boundary:** In this part, the orchestrator is a prompt agent. Do not publish a hosted orchestrator in Part 3. Prompt agents are designed for development and testing in the Foundry portal—hosted orchestrators require additional configuration and are outside the scope of this workshop.

---

## 4) Validate routing behavior in the playground

Use these prompts to confirm routing decisions and synthesis behavior.

For every test, use run traces/tool invocation logs to confirm which A2A connection(s) were called.
Response text alone is not sufficient to verify routing.

### Prompt A: Live Compliance Status Query

**Expected primary routing:** `audit-status-agent` (verify in trace)

```text
What are our current compliance scores across all audit areas? Which areas are non-compliant?
```

Validation:

- Response reflects live scorecard status
- Non-compliant areas are identified
- No policy-citation-only answer pattern

### Prompt B: Regulatory Requirements Query

**Expected primary routing:** `policy-audit-info-agent` (verify in trace)

```text
According to the corpus, what SPCC plan maintenance, secondary containment, and training requirements apply to a compressor station, and what audit evidence should we collect?
```

Validation:

- Response is grounded in the corpus and includes citations
- SPCC plan maintenance, secondary containment, and training requirements are addressed
- Evidence includes signed SPCC plans, containment inspection records, and training rosters
- No live scorecard or rating data is fabricated

### Prompt C: Combined Status + Regulation Query

**Expected primary routing:** Both agents (verify in trace)

```text
Our PSM Program Controls area is currently Non-compliant. What root-cause violations are driving that rating, and according to the corpus what PSM-1910.119 audit evidence should we gather?
```

Validation:

- `audit-status-agent` supplies the current rating and root causes
- `policy-audit-info-agent` supplies corpus-grounded PSM-1910.119 evidence with citations
- The response connects the status findings to evidence such as PHA reports, MOC packets, and mechanical-integrity work orders or inspection records
- No fuel-quality or unsupported regulatory claims are introduced

### Prompt D: Out-of-scope Query

**Expected primary routing:** Neither agent (refusal; verify no A2A tool call)

```text
How do I set up a Python Flask web server?
```

Validation:

- The request fails the scope gate before any routing decision
- Neither A2A agent is called
- The response is exactly: `I only handle oil-and-gas policy, compliance, and audit questions.`
- No setup steps, code, speculation, or additional text is returned

### Prompt E: Complex Compliance Validation

**Expected primary routing:** Both agents (verify in trace)

```text
We have a finding in an environmental control area. What root-cause violations are driving this finding, and what corpus-grounded audit evidence should we gather to demonstrate remediation?
```

Validation:

- Root causes come from status context
- Audit evidence comes from policy context with citations

---

## 5) Troubleshooting

If routing is incorrect:

1. Re-verify both agent cards with `verify-agent-card.ps1`.
2. Confirm each A2A tool uses the base endpoint ending in `/endpoint/protocols/a2a`.
3. Confirm the host is `services.ai.azure.com`, authentication is **Agent Identity**, and audience is `https://ai.azure.com`.
4. Confirm the orchestrator identity has **Foundry Agent Consumer** on the target project.
5. Tighten sub-agent descriptions to be routing-intent-aware.
6. Simplify orchestrator instructions so each routing rule maps to one clear intent.
7. Re-test with the same five prompts and inspect traces/tool invocations.

If you hit hosted-runtime identity or container issues, you are in Part 4 scope; stop this part here.

---

## Expected result

You have a working **Prompt Orchestrator** that calls both sub-agents through **A2A** and routes/synthesizes correctly for status-only, policy-only, mixed, and out-of-scope prompts.
