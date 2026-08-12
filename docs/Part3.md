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
       -ResourceGroupName "rg-agent-ws-mx01" `
       -ProjectName       "main-project" `
       -AgentName         "audit-status-agent" `
       -AgentDescription  "Provides live compliance scorecard ratings across 7 audit areas and identifies root-cause violations within specific areas. Use for questions about current compliance status, non-compliant areas, or what is driving audit findings."
   ```

   **Note the "Agent A2A base URL" printed in the output.** You'll paste this into the orchestrator's A2A Tool configuration in Section 3.

3. Enable A2A for `policy-audit-info-agent`:

   ```powershell
   .\scripts\enable-a2a.ps1 `
       -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
       -ResourceGroupName "rg-agent-ws-mx01" `
       -ProjectName       "main-project" `
       -AgentName         "policy-audit-info-agent" `
       -AgentDescription  "Answers policy and audit questions grounded exclusively in the connected knowledge base corpus. Returns citations and confidence ratings. Use for questions about regulatory requirements, required audit evidence, or specific policy clauses — not for live compliance status."
   ```

   **Again, note the "Agent A2A base URL" printed in the output.**

4. **Record both Agent A2A base URLs** for use in Section 3. The pattern is:
   ```
   https://{foundry-account}.services.ai.azure.com/api/projects/main-project/agents/{agent}/endpoint/protocols/a2a
   ```

**Expected result:** Both runs report A2A setup complete and output the base A2A endpoint.

---

## 2) Verify both agent cards before wiring orchestration

Verify that each sub-agent is discoverable through its agent card:

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project" `
    -AgentName         "audit-status-agent"
```

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project" `
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
4. Set the system instructions to:

   > **Important:** The Agent Connection names are essential routing identifiers. Use the exact names `audit-status-agent-a2a-v1` (25 characters) and `policy-audit-info-at-a2av1` (26 characters) when you register the connections, and keep those names unchanged. All Agent Connection names must be 27 characters or fewer.

```text
You are an orchestration prompt agent for oil and gas policy and audit workflows.

You have access to two specialized agents:
- audit-status-agent-a2a-v1: live compliance scorecard ratings and root-cause violations.
- policy-audit-info-at-a2av1: policy/regulatory requirements and required audit evidence, grounded in its knowledge base with citations.

Routing rules:
Before selecting a tool, apply this scope gate:
1. Treat a request as in scope only when it concerns oil-and-gas policy, compliance, audits, controls, evidence, findings, scores, status, remediation, or regulatory interpretation.
2. Treat software, coding, web-server setup, infrastructure, math, finance, and other non-audit or non-policy requests as out of scope.
3. If a request mixes an in-scope subject with an out-of-scope task, classify the entire request as out of scope.
4. For an out-of-scope request, do not call any tool or A2A agent. Reply exactly: I only handle oil-and-gas policy, compliance, and audit questions.

After the scope gate passes:
5. For any in-scope question containing current, live, score, rating, finding, non-compliant, or remediation-status language, you must call the audit-status-agent-a2a-v1 tool. This is mandatory - never answer from memory, from the policy corpus, or from Foundry IQ, and never skip the call based on your own prediction of whether it will succeed.
6. Only after you have actually attempted the audit-status-agent-a2a-v1 call: if it returned a usable result, use that result as the authoritative source for current status. If it failed or returned no result, report that live status could not be retrieved - do not substitute corpus content in either case.
7. Questions about policy, regulations, controls, or required evidence -> call policy-audit-info-at-a2av1.
8. Questions requiring both operational status and regulatory interpretation -> call audit-status-agent-a2a-v1 first, then policy-audit-info-at-a2av1, and clearly separate current status from policy interpretation.
9. When using policy content, preserve citations.
```

### Required: grant the orchestrator identity A2A access

Incoming A2A requires the calling identity to have the **Foundry Agent Consumer** role (or higher) on the Foundry project that hosts the target agent — even when every agent lives in the same project. This is a token-authorization requirement for A2A calls, not a cross-project-only rule. Without this role assignment, A2A calls fail (often surfacing as a generic server error rather than a clear 401/403).

**Foundry Agent Consumer may not appear in the Azure portal's role-assignment picker yet**, even though the role definition exists in the tenant. Use the script below, which assigns the role directly through the Azure CLI:

```powershell
.\scripts\grant-a2a-access.ps1 `
    -FoundryName "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName "main-project" `
    -AgentName "orchestrator-prompt-agent"
```

If the script reports that the identity is not available, publish or activate the agent version and run the script again. Role assignment changes can take several minutes to propagate.

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

#### Step 3: Add Agent Connections
The A2A tool accepts the target agent's **base A2A endpoint**. Do not append an agent-card path to the endpoint URL. Foundry resolves the audience and agent card automatically.

1. Click the **Add** button to open the tools picker/menu
2. Select **Add Tools**
3. Navigate to the **Custom** tab
4. Select **A2A**
5. A form appears. Fill in the following:
   - **Name:** `audit-status-agent-a2a-v1`
   - **A2A Agent Endpoint:** Paste the first **base A2A URL** (saved from Step 1):
     > https://{foundry-account}.services.ai.azure.com/api/projects/main-project/agents/audit-status-agent/endpoint/protocols/a2a
   - **Auth type:** Select **Microsoft Entra Agent Identity**
6. Click **Connect**
7. Repeat steps 1–4, then fill in:
   - **Name:** `policy-audit-info-at-a2av1`
   - **A2A Agent Endpoint:** Paste the second **base A2A URL**:
     > https://{foundry-account}.services.ai.azure.com/api/projects/main-project/agents/policy-audit-info-agent/endpoint/protocols/a2a
   - **Auth type:** Select **Microsoft Entra Agent Identity**
8. Click **Connect**
9. Click **Save**.

**Note:** Replace `{foundry-account}` with your actual Foundry account name. Use the canonical `services.ai.azure.com` host and paste the base endpoint in the endpoint field. **Microsoft Entra Agent Identity** authenticates the orchestrator to the specialist endpoints.

Before testing, confirm that both specialist agents and the orchestrator are in the same Foundry project, and that the role assignment above completed successfully. If you receive a server error or a 401 while calling an A2A agent, re-run the grant script and confirm the role assignment exists before checking anything else.

> **Scope boundary:** In this part, the orchestrator is a prompt agent. Do not publish a hosted orchestrator in Part 3. Prompt agents are designed for development and testing in the Foundry portal—hosted orchestrators require additional configuration and are outside the scope of this workshop.

---

## 4) Validate routing behavior in the playground

Use these prompts to confirm routing decisions and synthesis behavior.

For every test, use run traces/tool invocation logs to confirm which A2A connection(s) were called.
Response text alone is not sufficient to verify routing.

### Prompt A: Live Compliance Status Query

**Expected primary routing:** `audit-status-agent` (verify in trace)

```text
What is our current audit scorecard?
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

## Expected result

You have a working **Prompt Orchestrator** that calls both sub-agents through **A2A** and routes/synthesizes correctly for status-only, policy-only, mixed, and out-of-scope prompts.
