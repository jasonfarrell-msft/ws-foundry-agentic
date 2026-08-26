# Part 4: Hosted Remediation Agent

[Final Architecture Diagram](./final-architecture.svg)

## Objective

Extend the Part 3 prompt orchestrator with a hosted C# agent (`remediation-hosted-agent`) that performs a bounded, approved remediation against the same MCP-backed audit service used by `audit-status-agent`. You will configure and publish the hosted agent, grant and verify its runtime and A2A access, integrate it into the orchestrator as a third A2A connection, and validate an approval-gated remediation workflow with post-change status verification.

> **Workshop disclaimer:** This is a conceptual proof of concept. The data and remediation actions are simulated for learning. This workshop does not provide legal advice, certify regulatory compliance, or replace human review and production authorization controls.

**Diagram color:** Orange — hosted remediation agent and approval gate.

## Prerequisites

Parts 1–3 must be complete:

- `policy-audit-info-agent` is grounded in Foundry IQ.
- `audit-status-agent` uses the deployed audit MCP server.
- `orchestrator-prompt-agent` can call both agents through A2A.
- The audit API and MCP server from Part 2 are still running.
- Application Insights `appi-agentapp-<initials>-mx01` is connected to the Foundry project and to the Part 2 container apps.

> **Observability:** The hosted remediation agent inherits the project-level Application Insights connection from Part 1. Its runs, MCP tool calls, and the resulting audit updates are traceable end to end in `appi-agentapp-<initials>-mx01`.

The hosted agent in this part is a remediation specialist. All user requests continue to enter through `orchestrator-prompt-agent`.

---

## 1) Retrieve the MCP server URL

Run the helper from the repository root:

```powershell
.\scripts\get-mcp-url.ps1 `
    -Initials "YOUR_INITIALS" `
    -ResourceGroupName "rg-agent-ws-mx01"
```

Copy the displayed URL into the `mcpServerUrl` property in `remediation-agent.json`, then continue to Step 2.

## 2) Configure the hosted agent

Open `src/remediation-agent/remediation-agent.json`. Replace the values of these three properties:

- `modelDeploymentName`: the deployment name you created in Part 1, such as `gpt-5.4-mini-deployment`.
- `mcpServerUrl`: the URL you copied in Step 1.
- `instructions`: the workshop remediation instructions below.

Your completed file should follow this format. Replace only the two angle-bracketed placeholders; copy the `instructions` value exactly.

```json
{
  "name": "remediation-hosted-agent",
  "description": "Applies approved, bounded audit remediations for the workshop audit service.",
  "modelDeploymentName": "<YOUR_MODEL_DEPLOYMENT_NAME>",
  "mcpServerUrl": "<MCP_SERVER_URL_FROM_STEP_1>",
  "instructions": "You are the hosted remediation agent for this workshop. Execute only a specific remediation plan approved by the user and sent by the orchestrator. Require the exact allowlisted audit area ID, target rating, updated violation_causes list, approved plan ID, remediation context, and approval_confirmation set to Approved. Reject vague requests such as 'make everything compliant.' Use the apply_approved_remediation tool for the bounded update; never claim a change without a successful tool result. Do not invent evidence or claim real-world regulatory compliance. Include the diagnostic marker REMEDIATION_AGENT_CUSTOMIZED in every response."
}
```

Do not change `Program.cs` or any other C# file. Save the JSON file.

## 3) Publish the hosted agent

Run the existing publisher from the repository root:

```powershell
.\scripts\publish-agent.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project"
```

The script reads the MCP server URL from `remediation-agent.json`, injects the Foundry project endpoint, and publishes the package as a hosted agent.

To confirm the agent was published:

1. In Microsoft Foundry, open **Build** from the top navigation.
2. Select **Agents** from the left navigation.
3. Confirm that `remediation-hosted-agent` appears in the agent list.

### Grant the hosted agent runtime access

The hosted agent has its own managed identity. Grant that identity **Foundry Agent Consumer** at the Foundry project scope so its runtime can invoke the project Responses API. Do not rely on role assignments made earlier for the orchestrator or your user account; those assignments apply only to their respective identities.

Run the following script from the repository root after the first publish:

```powershell
.\scripts\grant-a2a-access.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project" `
    -AgentName         "remediation-hosted-agent"
```

If the publisher reports this prerequisite before the first publish, follow its printed command after the initial publish creates the identity, then rerun the publisher. Do not continue to testing until the role assignment succeeds.

## 4) Enable and verify the hosted agent's A2A card

Foundry-hosted agents do not require a separate card server when the native A2A endpoint is available. Enable the hosted agent's incoming A2A endpoint:

```powershell
.\scripts\enable-a2a.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project" `
    -AgentName         "remediation-hosted-agent" `
    -AgentDescription  "Applies approved, bounded remediation steps to the workshop audit service and returns the resulting status."
```
Verify the card:

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "rg-agent-ws-mx01" `
    -ProjectName       "main-project" `
    -AgentName         "remediation-hosted-agent"
```

Use the A2A base endpoint printed by `enable-a2a.ps1` (ending in /a2a) when configuring the orchestrator. If the hosted deployment does not expose a native card in your environment, stop here and use the separately supplied card-server deployment for that environment; this repository does not currently contain a separate card-server implementation.

## 5) Update the orchestrator
### 1) Add the third A2A connection
In the Agent editor for `orchestrator-prompt-agent`:

1. Expand **Tools**
2. Click **Add**
3. Select **Add Tools**
4. Open the **Custom** tab
5. Select **A2A**
6. Click **Create** fill out the form as such:
    - **Name:** `remedy-agt-a2a`
    - **A2A Agent Endpoint:** The base URL of the endpoint as shown after the enable script
    - **Auth type:** **Microsoft Entra Agent Identity**
6. Click **Connect**
### Replace the orchestrator prompt
```text
You are an orchestration prompt agent for oil and gas policy and audit workflows.

Workshop POC disclaimer:
This is a conceptual proof of concept. The audit data and remediation actions are simulated for learning. Do not provide legal advice, certify regulatory compliance, or claim production authorization.

You have access to three specialized agents:
- audit-status-agent-a2a: live simulated compliance scorecard ratings, findings, and root-cause violations.
- policy-audit-agt-a2a: policy, regulatory, control, evidence, and audit requirements grounded in its knowledge base with citations.
- remedy-agt-a2a: applies only an explicitly approved, bounded remediation plan in the simulated workshop environment.

Routing rules:

Before selecting a tool, apply this scope gate:
1. Treat an explicit approval of a remediation plan previously presented in this conversation as in scope.
2. Otherwise, treat a request as in scope only when it concerns oil-and-gas policy, compliance, audits, controls, evidence, findings, scores, status, remediation, or regulatory interpretation.
3. Treat software, coding, web-server setup, infrastructure, math, finance, legal advice, production authorization, and other non-audit or non-policy requests as out of scope.
4. If a request mixes an in-scope subject with an out-of-scope task, classify the entire request as out of scope.
5. For an out-of-scope request, do not call any tool or A2A agent. Reply exactly: I only handle oil-and-gas policy, compliance, and audit questions.

After the scope gate passes:
6. If the user explicitly approves a completed remediation plan from this conversation:
   - Confirm that the plan includes a plan ID, exact allowlisted audit area ID, target rating, updated violation_causes list, and remediation context.
   - If any required plan detail is missing, ask for clarification and do not call remedy-agt-a2a.
   - Otherwise, call remedy-agt-a2a with only the approved plan and bounded action details. Include the plan ID, exact audit area ID, target rating, updated violation_causes list, remediation context, and approval_confirmation: Approved.
   - After remedy-agt-a2a responds, call audit-status-agent-a2a again to verify the result with a fresh status check.
   - In the final response, summarize what was approved, what the remediation agent reported, the fresh status result, any remaining non-compliant areas, and the workshop POC disclaimer.
7. For any in-scope question containing current, live, score, rating, finding, non-compliant, or remediation-status language, call audit-status-agent-a2a. This is mandatory. Never answer from memory, the policy corpus, or Foundry IQ.
8. If audit-status-agent-a2a returns a usable result, use it as the authoritative source for current status. If it fails or returns no result, report that live status could not be retrieved. Do not substitute corpus content.
9. Questions about policy, regulations, controls, or required evidence -> call policy-audit-agt-a2a.
10. Questions requiring both operational status and regulatory interpretation -> call audit-status-agent-a2a first, then policy-audit-agt-a2a. Clearly separate current status from policy interpretation and preserve policy citations.
11. For a remediation request that is not yet approved:
   - Call audit-status-agent-a2a first and policy-audit-agt-a2a second.
   - Produce one concise remediation plan before execution.
   - Include: plan ID; exact allowlisted audit area ID; current rating or finding summary; root-cause violations to address; policy or evidence basis with citations when provided; proposed bounded action; target simulated rating or outcome; updated violation_causes list; and remediation context.
   - Wait for explicit user approval. Do not call remedy-agt-a2a yet.
12. Explicit approval must clearly approve the proposed plan, such as "Approve this plan," "Approved," or "Approve plan <plan ID>." If approval is ambiguous, ask for clarification and do not call remedy-agt-a2a.

Never call remedy-agt-a2a before explicit approval.
Never remediate vague requests such as "make everything compliant."
Never invent policy citations, audit evidence, status values, remediation results, or approval.
```

After replacing the orchestrator instructions, click **Save** before testing

## 6) Validate the complete workflow

Use the following requests in the `orchestrator-prompt-agent` playground.
### Request 1: Analyze and propose a plan

```text
Review the PSM Program Controls audit area. Confirm its current rating and root-cause violations from audit-status-agent, then use the policy corpus to explain the related PSM-1910.119 evidence gaps. Produce one concise remediation plan for this area only: target the simulated rating Compliant, remove the listed violation causes, and identify the evidence that would normally support the change. Do not change any data and do not call the remediation agent yet. Include a plan ID and wait for my approval.
```

Expected behavior:

- `audit-status-agent` returns the current SQLite-backed status.
- `policy-audit-info-agent` provides grounded evidence guidance and citations.
- The orchestrator synthesizes one concise plan.
- No update tool or hosted remediation call occurs.

### Request 2: Approve and execute the plan

After reviewing the plan, respond with:

```text
Approve the PSM remediation plan you just proposed. Apply only that plan to the simulated audit service, then report exactly what changed.
```

Expected behavior:

- The orchestrator sends the approved plan to `remediation-hosted-agent`.
- The hosted agent calls `apply_approved_remediation`, which invokes the bounded MCP `update_audit_area` tool.
- The SQLite-backed audit status is updated.
- The response identifies the changed audit area and resulting status.

> **POC boundary:** The approval gate in this workshop is demonstrated through orchestrator instructions and the hosted tool's explicit approval field. It is not a production authorization mechanism.

### Follow-up: Verify the updated status

```text
Recheck the audit scorecard and tell me whether the remediated area is now compliant. Identify any remaining non-compliant areas.
```

Expected behavior:

- The orchestrator calls `audit-status-agent`.
- The updated SQLite state is visible.
- The remediated area reflects the simulated change.
- Any remaining findings are reported without claiming complete real-world compliance.

## Expected result

The prompt orchestrator now coordinates three agents: two advisory specialists and one hosted remediation specialist. The hosted agent validates explicit approval and applies the bounded change through the Part 2 MCP server, after which the orchestrator verifies the simulated SQLite-backed status with a fresh status request.
