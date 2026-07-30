# Part 2: Model Context Protocol (MCP) & Agent Integration

## Objective

Create a **prompt agent in Foundry that leverages the Model Context Protocol (MCP)** to communicate with an audit API. The agent uses MCP tools to query compliance state and drill into specific audit areas, demonstrating how agents interact with external services through a standardized protocol.

This part covers:
- Running a deployment script to set up the audit API
- Building an MCP server that wraps the API with three discoverable tools
- Creating the **audit-status-agent** that uses MCP for external queries
- Testing agent-to-MCP-to-API integration

### Prerequisites & Assumptions

**Assumption: Part 1 is complete.**
- Foundry is deployed and running
- A Foundry project exists with a model deployed
- PowerShell 7+ is available on your workstation

If you need to set up Part 1 first, refer to `docs/Part1.md`.

---

## 1) Deploy the Audit API

Run the `scripts/setup-part2.ps1` script to deploy the audit API. The script handles all infrastructure provisioning and outputs the API URL you'll need for MCP configuration.

1. Open PowerShell and navigate to the repository root.
2. Run the deployment script with your initials and resource group name:

   ```powershell
   pwsh scripts/setup-part2.ps1 -Initials "jf" -ResourceGroupName "rg-workshop"
   ```

   **Note:** All resources (container registry, container environment, container app) will be created in the same location as the resource group.

3. At the end of the script output, you will see:

   ```
   ════════════════════════════════════════════════════════════
   AUDIT API URL (copy and paste into MCP configuration):
   ════════════════════════════════════════════════════════════

   https://aca-agentws-api-<initials>-<region>.azurecontainerapps.io

   ════════════════════════════════════════════════════════════
   ```

4. **Copy this URL** — you'll use it when configuring the MCP server.

---

## 2) Configure and Build the MCP Server

The MCP server is a C# application that exposes three tools to agents. Before building and deploying, you need to copy the tool descriptions into the MCP server source code.

### Tool Descriptions

The three audit tools are:

**Tool 1: get_audit_scorecard**
- **Description:** Retrieve the complete audit scorecard with all 7 audit areas and their current compliance status (Compliant, At Risk, or Non-compliant)
- **Input:** No parameters required

**Tool 2: get_audit_area_detail**
- **Description:** Retrieve detailed information about a specific audit area, including its current rating and the root causes of any violations
- **Input:** 
  - `area_id` (string, required) — The unique identifier for the audit area (e.g., 'spcc_compliance', 'psm_program', 'subpart_w_reporting')

**Tool 3: update_audit_area**
- **Description:** Update an audit area's compliance rating and violation causes (used for tracking remediation progress)
- **Input:**
  - `area_id` (string, required) — The unique identifier for the audit area
  - `rating` (string, required) — The new compliance rating (Compliant, At Risk, or Non-compliant)
  - `violation_causes` (array, required) — Updated list of violation causes

### Deploy the MCP Server

Now deploy the MCP server to Azure Container Apps and capture its endpoint URL.

1. Open PowerShell and run the deployment script:

   ```powershell
   pwsh scripts/deploy-mcp.ps1 -Initials "jf" -ResourceGroupName "rg-workshop" -ApiUrl "https://aca-agentws-api-jf-eastus.azurecontainerapps.io"
   ```

   Replace:
   - `jf` with your actual initials
   - `rg-workshop` with your resource group name
   - Use the **Audit API URL** from the `setup-part2.ps1` script output

   **Note:** All resources will be created in the same location as your resource group.

2. At the end of the script output, you will see:

   ```
   ════════════════════════════════════════════════════════════
   MCP SERVER URL (copy and paste into Foundry Tools config):
   ════════════════════════════════════════════════════════════

   https://aca-agentws-mcp-<initials>-<region>.azurecontainerapps.io

   ════════════════════════════════════════════════════════════
   ```

3. **Copy this URL** — you'll use it when adding the MCP server connection in Foundry.

---

## 3) Create the audit-status-agent

Now you'll create a prompt agent in Foundry that uses the MCP server's three tools.

In Foundry:

1. Select the **Build** tab, then click **Agents** in the navigation.
2. Click **New Agent**, then select **Build an agent**.
3. Fill in **Name** with `audit-status-agent`, then click **Create**.

4. In the UI, verify the selected **Model** matches the model you expect for this lab.

5. In **System Instructions**, enter:

   ```
   You are an audit status agent responsible for helping compliance teams understand their current audit posture.

   You have access to audit tools that allow you to:
   - Retrieve a complete audit scorecard with all 7 audit areas and their compliance ratings
   - Drill into specific audit areas to identify the root causes of violations
   - Track audit area ratings and statuses

   When users ask about compliance status:
   1. First, retrieve the full audit scorecard to give them an overview
   2. If they ask about a specific area, query the area detail to provide violation causes
   3. Present findings clearly, highlighting areas that are Non-compliant (critical) vs. At Risk (needs attention)

   Be concise and factual. Always cite which audit area and the specific violation causes.
   ```

6. In **Tools**, remove **Web Search**.
7. In **Tools**, click **Add**, then **Add Tools**.
8. Select the **Custom** tab.
9. Choose **Model Context Protocol (MCP)**, then click **Create**.
10. Enter the tool connection details:

| Field | Value |
|-------|-------|
| **Name** | `audit-api-mcp` |
| **Server** | Paste your endpoint URL from the `deploy-mcp.ps1` script output |
| **Authentication** | Unauthenticated |

11. Click **Connect**.
12. **Save** the agent.

**Expected result:** The MCP server is connected using your server URL, and **Web Search** is no longer present.

---

## 4) Test the audit-status-agent

Open the agent in Foundry's chat interface and test the following queries.

> **Note:** When the agent calls an MCP tool for the first time, the playground will prompt you for permission to execute the tool call. Click **Allow** to proceed.

**Query 1: Get the scorecard**
```
What audit areas are we being evaluated on, and what's our current status?
```

Expected: Agent calls `get_audit_scorecard`, returns all 7 areas with their ratings (Compliant, At Risk, Non-compliant).

**Query 2: Drill into a specific area**
```
Why is the PSM Program Controls area marked as Non-compliant?
```

Expected: Agent calls `get_audit_area_detail` with `area_id = "psm_program"`, returns the current rating and specific violation causes (e.g., "PHA overdue", "MOC pre-startup safety review missing").

**Query 3: Another area**
```
Tell me about the SPCC Compliance audit area.
```

Expected: Agent calls `get_audit_area_detail` with `area_id = "spcc_compliance"`, returns rating and violation causes.

---

## 5) Audit Areas Reference

The audit API manages 7 compliance audit areas. Here's what each covers:

| Area ID | Name | Default Status | Sample Violation Causes |
|---------|------|-----------------|------------------------|
| `spcc_compliance` | SPCC Compliance | At Risk | Containment inspection overdue, training incomplete, plan not updated |
| `psm_program` | PSM Program Controls | Non-compliant | PHA overdue, MOC pre-startup safety review missing, MI logs missing |
| `subpart_w_reporting` | Subpart-W GHG Reporting | Compliant | None |
| `rcra_hazardous` | RCRA Hazardous Waste | At Risk | Classification docs missing, training at 60%, inspection records incomplete |
| `pipeline_safety` | Pipeline Safety 49-CFR-192/195 | Compliant | None |
| `environmental_controls` | Environmental Controls CWA/CAA | At Risk | Air monitoring calibration overdue, wastewater sampling gaps, SWPPP not reviewed since 2022 |
| `incident_corrective` | Incident & Corrective Actions | Non-compliant | Incidents lacking RCA, CAPA closed without effectiveness verification, overdue items |

---

## 6) Customizing Audit State

### Modify Initial Audit Configuration

If you want to change the default audit area ratings and violation causes before deployment:

Edit `src/api/audit_config.json`:

```json
{
  "audit_areas": [
    {
      "area_id": "spcc_compliance",
      "name": "SPCC Compliance",
      "rating": "At Risk",
      "violation_causes": [
        "Containment inspection overdue",
        "Training incomplete",
        "Plan not updated"
      ]
    },
    ...
  ]
}
```

Then redeploy by running the `setup-part2.ps1` script again.

### Update Audit State via API

Once the API is running, you can update audit state by calling the PUT endpoint directly:

```powershell
$apiUrl = "https://aca-agentws-api-<initials>-<region>.azurecontainerapps.io"
$body = @{
    rating = "Compliant"
    violation_causes = @()
} | ConvertTo-Json

Invoke-RestMethod -Uri "$apiUrl/audit/spcc_compliance" -Method Put -Body $body -ContentType "application/json"
```

Or let the agent do it (Part 3) by calling `update_audit_area`.

---

## 7) Troubleshooting

**MCP Server doesn't connect**
- Verify the `AUDIT_API_URL` environment variable is set correctly in the MCP server configuration.
- Confirm the API URL is reachable from your network.
- Check MCP server logs for connection errors.

**Agent calls tool but no response**
- Verify the MCP server is running and connected to Foundry.
- Check that the `AUDIT_API_URL` is reachable from the MCP server.
- Review the API server logs in Azure Portal (Container Apps → Logs).

**Audit area detail returns empty causes**
- The audit state may have been reset (container restart loads default config).
- Check `src/api/audit_config.json` for the area's violation causes.
- Call the PUT endpoint to update if needed.

---

## Next Steps: Part 3

Part 3 will introduce:
- **Agent-to-Agent (A2A) Communication** — The audit-status-agent will coordinate with a policy-audit-info-agent
- **Orchestrator Agent** — Handles complex workflows (assess → provide remediation suggestions → mark complete)
- **Policy Integration** — Fetch remediation advice from the policy KB (Part 1)
- **Multi-step Workflows** — Chain MCP tool calls across agents

For now, the audit-status-agent is a standalone **query agent** that passively reports on audit state. In Part 3, it will become part of a larger orchestration loop.

---

## Summary

You've successfully:
✅ Deployed the audit API to Azure Container Apps  
✅ Built the MCP server that wraps the API  
✅ Created the audit-status-agent in Foundry  
✅ Verified agent-to-MCP-to-API integration  

The audit-status-agent can now retrieve compliance audits and drill into violations. Next stop: Part 3 orchestration!
