# Part 4: Hosted Remediation Agent

## Objective

Extend the Part 3 prompt orchestrator with a hosted C# agent that performs a bounded, approved remediation against the same MCP-backed audit service used by `audit-status-agent`.

> **Workshop disclaimer:** This is a conceptual proof of concept. The data and remediation actions are simulated for learning. This workshop does not provide legal advice, certify regulatory compliance, or replace human review and production authorization controls.

## Prerequisites

Parts 1–3 must be complete:

- `policy-audit-info-agent` is grounded in Foundry IQ.
- `audit-status-agent` uses the deployed audit MCP server.
- `orchestrator-prompt-agent` can call both agents through A2A.
- `scripts/publish-orch-agent.ps1` can publish a hosted C# agent.
- The audit API and MCP server from Part 2 are still running.

The hosted agent in this part is a remediation specialist. All user requests continue to enter through `orchestrator-prompt-agent`.

## 1) Tailor the hosted-agent source

Copy or adapt the C# source under `src/orch-agent` for the remediation agent. Use a distinct name, such as `remediation-hosted-agent`.

Update `src/orch-agent/orchestrator-agent.json`:

- `name`: `remediation-hosted-agent`
- `description`: Explain that the agent applies approved, bounded audit remediations.
- `modelDeploymentName`: Use the deployment from Part 1.
- `instructions`: Tell the agent to execute only the approved plan it receives from the orchestrator.

The existing C# template is an A2A-enabled hosted-agent sample, not a finished remediation agent. Before publishing, update `src/orch-agent/Program.cs` to add the MCP client connection and a bounded function that invokes `update_audit_area`. Pass the MCP endpoint from configuration or an environment variable; do not hard-code an endpoint or credential. Remove any unused outbound A2A connection names from the hosted-agent configuration.

The hosted agent must:

- Use the existing audit MCP server and its `update_audit_area` capability.
- Accept a specific control or audit-area identifier, target status, and approved remediation context.
- Reject vague requests such as “make everything compliant.”
- Never invent evidence or claim that a real regulatory obligation has been satisfied.
- Return the operation performed and the resulting status.

The current `src/orch-agent` template contains hosted-agent and A2A plumbing, but it does not yet contain a dedicated MCP client configuration for remediation. Treat adding that MCP connection and tool invocation as part of tailoring the C# source before publishing; do not assume that changing the JSON instructions alone adds MCP access.

The Part 2 MCP server exposes both read and update capabilities. This reuse is intentional: the status agent reads the service, while the hosted agent performs the approved update. In a production system, these capabilities would require separate authorization and stronger controls.

Because the workshop MCP server exposes all three tools, update `audit-status-agent` instructions before testing:

```text
Use the MCP server only to read audit status and area details. Never call update_audit_area. Remediation is performed only by the approved hosted remediation agent.
```

This is a workshop-level behavioral boundary, not a production authorization boundary.

## 2) Publish the hosted agent

Run the existing publisher from the repository root:

```powershell
.\scripts\publish-orch-agent.ps1 `
    -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
    -ResourceGroupName "YOUR_RESOURCE_GROUP" `
    -ProjectName       "YOUR_PROJECT_NAME"
```

The script builds the C# project, injects the Foundry project endpoint, and publishes the package as a hosted agent. Confirm that `remediation-hosted-agent` appears in the Foundry project and responds to a simple test request.

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

Open `orchestrator-prompt-agent` in Foundry and add a third tool using **Add → Add Tools → Custom → A2A**.

Configure:

- **Endpoint:** The hosted agent's base endpoint ending in `/endpoint/protocols/a2a`
- **Authentication:** Agent Identity
- **Audience:** `https://ai.azure.com`
- **Card path:** `agentCard/v1.0` when the dialog exposes a card-path field

The orchestrator must now have exactly three A2A connections:

1. `audit-status-agent`
2. `policy-audit-info-agent`
3. `remediation-hosted-agent`

Keep Web Search removed. Confirm that the orchestrator identity can consume all three target agents before testing.

Update the orchestrator instructions so that:

- Status questions call `audit-status-agent`.
- Policy and evidence questions call `policy-audit-info-agent`.
- Remediation requests call the status and policy agents first.
- The orchestrator creates a concise plan and asks for approval before calling `remediation-hosted-agent`.
- The hosted agent receives only the approved plan and bounded action details.
- The orchestrator reruns the status check after remediation.
- Out-of-scope requests do not call any agent.

## 5) Validate the complete workflow

Use the following requests in the `orchestrator-prompt-agent` playground. Inspect traces to confirm the A2A calls.

### Request 1: Analyze and propose a plan

```text
Review our current audit scorecard and identify the non-compliant areas. Use the policy corpus to explain the relevant evidence gaps, then produce a concise remediation plan for the highest-priority area. Do not change any data and do not call the remediation agent yet. Include a plan ID and wait for my approval.
```

Expected behavior:

- `audit-status-agent` returns the current SQLite-backed status.
- `policy-audit-info-agent` provides grounded evidence guidance and citations.
- The orchestrator synthesizes one concise plan.
- No update tool or hosted remediation call occurs.

### Request 2: Approve and execute the plan

After reviewing the plan, respond with:

```text
Approve the remediation plan you just proposed. Apply only the listed remediation step, then report exactly what changed.
```

Expected behavior:

- The orchestrator sends the approved plan to `remediation-hosted-agent`.
- The hosted agent calls the bounded MCP update capability.
- The SQLite-backed audit status is updated.
- The response identifies the changed audit area and resulting status.

### Follow-up: Verify the updated status

```text
Recheck the audit scorecard and tell me whether the remediated area is now compliant. Identify any remaining non-compliant areas.
```

Expected behavior:

- The orchestrator calls `audit-status-agent`.
- The updated SQLite state is visible.
- The remediated area reflects the simulated change.
- Any remaining findings are reported without claiming complete real-world compliance.

## 6) Troubleshooting

- **401 or 404 when adding the hosted agent:** verify A2A is enabled, use the `services.ai.azure.com` base endpoint, set the card path to `agentCard/v1.0`, and verify Agent Identity RBAC.
- **The hosted agent is called before approval:** strengthen the orchestrator instructions and retest Request 1.
- **The hosted agent changes the wrong area:** require an explicit allowlisted area ID and approved plan ID.
- **The follow-up status is unchanged:** inspect the hosted-agent trace, MCP update call, and audit API logs.
- **The hosted agent claims compliance without an update:** treat the result as a failure; the final status must come from a fresh `audit-status-agent` query.

## Expected result

The prompt orchestrator now coordinates three agents: two advisory specialists and one hosted remediation specialist. It can analyze a simulated compliance issue, obtain approval, apply one bounded MCP-backed update, and verify the resulting SQLite-backed status.
