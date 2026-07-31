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
