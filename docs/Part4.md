# Part 4: Hosted Remediation Agent

## Objective

Extend the Part 3 prompt orchestrator with a hosted C# agent that performs a bounded, approved remediation against the same MCP-backed audit service used by `audit-status-agent`.

> **Workshop disclaimer:** This is a conceptual proof of concept. The data and remediation actions are simulated for learning. This workshop does not provide legal advice, certify regulatory compliance, or replace human review and production authorization controls.

## Prerequisites

Parts 1–3 must be complete:

- `policy-audit-info-agent` is grounded in Foundry IQ.
- `audit-status-agent` uses the deployed audit MCP server.
- `orchestrator-prompt-agent` can call both agents through A2A.
- `scripts/publish-agent.ps1` can publish a hosted C# agent.
- The audit API and MCP server from Part 2 are still running.

The hosted agent in this part is a remediation specialist. All user requests continue to enter through `orchestrator-prompt-agent`.

## 1) Make the required hosted-agent customization

Before publishing, replace the contents of `src/remediation-agent/remediation-agent.json` with this complete example. If your Part 1 model deployment has a different name, change only `modelDeploymentName`.

```json
{
  "name": "remediation-hosted-agent",
  "description": "Applies approved, bounded audit remediations for the workshop audit service.",
  "modelDeploymentName": "gpt-5.4-nano-deployment",
  "mcpServerUrl": "",
  "instructions": "You are the hosted remediation agent for this workshop. Execute only a specific remediation plan approved by the user and sent by the orchestrator. Require the exact allowlisted audit area ID, target rating, updated violation_causes list, approved plan ID, remediation context, and approval_confirmation set to Approved. Reject vague requests such as 'make everything compliant.' Use the apply_approved_remediation tool for the bounded update; never claim a change without a successful tool result. Do not invent evidence or claim real-world regulatory compliance. Include the diagnostic marker REMEDIATION_AGENT_CUSTOMIZED in every response."
}
```

Do not change `Program.cs` or any other C# file.

Save the file.

## 2) Publish the hosted agent

Run the existing publisher from the repository root:

```powershell
.\scripts\publish-agent.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -McpServerUrl      "YOUR_MCP_SERVER_URL"
```

Use the MCP server URL printed by `scripts/deploy-mcp.ps1` in Part 2. The script builds the C# project, injects the Foundry project endpoint and MCP server URL, and publishes the package as a hosted agent. Confirm that `remediation-hosted-agent` appears in the Foundry project and responds to a simple test request.

If the publisher reports a missing hosted-agent identity or RBAC prerequisite, follow the command printed by the script before continuing.

## 3) Enable and verify the hosted agent's A2A card

Foundry-hosted agents do not require a separate card server when the native A2A endpoint is available. Enable the hosted agent's incoming A2A endpoint:

```powershell
.\scripts\enable-a2a.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "remediation-hosted-agent" `
    -AgentDescription  "Applies approved, bounded remediation steps to the workshop audit service and returns the resulting status."
```

Verify the card:

```powershell
.\scripts\verify-agent-card.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME" `
    -AgentName         "remediation-hosted-agent"
```

Use the A2A base endpoint printed by `enable-a2a.ps1` when configuring the orchestrator. The card URL is for verification. If the hosted deployment does not expose a native card in your environment, stop here and use the separately supplied card-server deployment for that environment; this repository does not currently contain a separate card-server implementation.

## 4) Add the third A2A connection to the orchestrator

### Replace the orchestrator prompt

In `orchestrator-prompt-agent`, replace the system instructions with:

> You are Orchestrator Prompt Agent v2 for an oil-and-gas audit workshop.
>
> Workshop POC disclaimer:
> This is a conceptual proof of concept. The audit data and remediation actions are simulated for learning. Do not provide legal advice, certify regulatory compliance, or claim production authorization.
>
> You have access to three A2A agents:
> - `audit-status-agent-a2a`: live simulated audit status, scorecard ratings, findings, and root-cause violations.
> - `policy-audit-info-agent-a2a`: policy, regulatory, control, evidence, and audit requirements grounded in its knowledge base with citations.
> - `remediation-hosted-agent-a2a`: applies only an explicitly approved, bounded remediation plan in the simulated workshop environment.
>
> Scope gate:
> 1. Treat a request as in scope only when it concerns oil-and-gas policy, compliance, audits, controls, evidence, findings, scores, status, remediation, or regulatory interpretation.
> 2. Treat software, coding, infrastructure, general math, finance, legal advice, production authorization, and unrelated requests as out of scope.
> 3. If a request mixes an in-scope subject with an out-of-scope task, classify the entire request as out of scope.
> 4. For an out-of-scope request, do not call any tool or A2A agent. Reply exactly: I only handle oil-and-gas policy, compliance, and audit questions.
>
> Routing rules:
> 1. For live status, scorecard, current rating, finding, root-cause, or remediation-status questions, call `audit-status-agent-a2a`.
> 2. For policy, regulation, control, audit evidence, or corpus-grounded requirement questions, call `policy-audit-info-agent-a2a`.
> 3. For questions requiring both operational status and policy interpretation, call both named A2A connections, then synthesize the answer. Preserve policy citations.
> 4. For remediation requests, always gather current status from `audit-status-agent-a2a` and applicable policy or evidence requirements from `policy-audit-info-agent-a2a` before proposing any remediation.
> 5. For remediation requests, produce one concise remediation plan before execution. The plan must include: plan ID; the exact allowlisted audit area ID; current rating or finding summary; root-cause violations to address; policy or evidence basis, including citations when provided; proposed bounded action; target simulated rating or outcome; updated violation_causes list; and remediation context.
> 6. After presenting a remediation plan, wait for explicit user approval before calling `remediation-hosted-agent-a2a`.
> 7. Explicit approval must clearly approve the proposed plan, such as “Approve this plan,” “Approved,” or “Approve plan <plan ID>.” If approval is ambiguous, ask for clarification and do not call `remediation-hosted-agent-a2a`.
> 8. When approval is received, call `remediation-hosted-agent-a2a` with only the approved plan and bounded action details. Include the plan ID, exact audit area ID, target rating, updated violation_causes list, remediation context, and `approval_confirmation: Approved`.
> 9. After `remediation-hosted-agent-a2a` responds, call `audit-status-agent-a2a` again to verify the result with a fresh status check.
> 10. In the final response after remediation, summarize what was approved, what the remediation agent reported, the fresh status result, any remaining non-compliant areas, and the workshop POC disclaimer.
>
> Never call `remediation-hosted-agent-a2a` before explicit approval.
> Never remediate vague requests such as “make everything compliant.”
> Never invent policy citations, audit evidence, status values, or remediation results.

### Add the third A2A connection

In the Foundry editor for `orchestrator-prompt-agent`:

1. Click **Add**.
2. Select **Add Tools**.
3. Open the **Custom** tab.
4. Select **A2A**.
5. Configure:
   - **Name:** `remediation-hosted-agent-a2a`
   - **A2A Agent Endpoint:**
     > https://{foundry-account}.services.ai.azure.com/api/projects/{project}/agents/remediation-hosted-agent/endpoint/protocols/a2a
   - **Auth type:** **Microsoft Entra Agent Identity**
6. Click **Add** or **Confirm**.
7. Click **Save** in the agent editor so the new Agent Connection is registered on the orchestrator before testing.

Use the base endpoint in the endpoint field. Foundry resolves the audience and agent card automatically. Keep Web Search removed.

> **Important:** The Agent Connection name is an essential routing identifier. Use the exact name `remediation-hosted-agent-a2a` and keep it unchanged.

The orchestrator's identity already has **Foundry Agent Consumer** from Part 3, and this same role covers calls to the new `remediation-hosted-agent-a2a` connection — no additional role assignment is needed here.

## 5) Validate the complete workflow

Use the following requests in the `orchestrator-prompt-agent` playground. Inspect traces to confirm the A2A calls.

### Request 1: Analyze and propose a plan

> Review the PSM Program Controls audit area. Confirm its current rating and root-cause violations from `audit-status-agent`, then use the policy corpus to explain the related PSM-1910.119 evidence gaps. Produce one concise remediation plan for this area only: target the simulated rating `Compliant`, remove the listed violation causes, and identify the evidence that would normally support the change. Do not change any data and do not call the remediation agent yet. Include a plan ID and wait for my approval.

Expected behavior:

- `audit-status-agent` returns the current SQLite-backed status.
- `policy-audit-info-agent` provides grounded evidence guidance and citations.
- The orchestrator synthesizes one concise plan.
- No update tool or hosted remediation call occurs.

### Request 2: Approve and execute the plan

After reviewing the plan, respond with:

> Approve the PSM remediation plan you just proposed. Apply only that plan to the simulated audit service, then report exactly what changed.

Expected behavior:

- The orchestrator sends the approved plan to `remediation-hosted-agent`.
- The hosted agent calls `apply_approved_remediation`, which invokes the bounded MCP `update_audit_area` tool.
- The SQLite-backed audit status is updated.
- The response identifies the changed audit area and resulting status.

> **POC boundary:** The approval gate in this workshop is demonstrated through orchestrator instructions and the hosted tool's explicit approval field. It is not a production authorization mechanism.

### Follow-up: Verify the updated status

> Recheck the audit scorecard and tell me whether the remediated area is now compliant. Identify any remaining non-compliant areas.

Expected behavior:

- The orchestrator calls `audit-status-agent`.
- The updated SQLite state is visible.
- The remediated area reflects the simulated change.
- Any remaining findings are reported without claiming complete real-world compliance.

## Expected result

The prompt orchestrator now coordinates three agents: two advisory specialists and one hosted remediation specialist. The hosted agent validates explicit approval and applies the bounded change through the Part 2 MCP server, after which the orchestrator verifies the simulated SQLite-backed status with a fresh status request.
