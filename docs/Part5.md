# Part 5: Observability with Application Insights Agent Monitoring

[Final Architecture Diagram](./final-architecture.svg)

## Objective

Use the Application Insights **Agents (Preview)** blade on `appi-agentapp-<initials>-mx01` to inspect the telemetry produced by everything you built in Parts 1–4 and turn the telemetry wiring from Part 1 into practical insight. You will review agent runs, tool calls, model usage, token consumption, and errors, then drill into an individual end-to-end transaction to follow a single orchestrated request across the orchestrator, the A2A sub-agents, the MCP server, and the audit API. By the end of this part you should be able to answer, from Application Insights alone:

- Which agents ran, how often, and how many failed
- Which tools each agent called and what those calls returned
- Which model deployment was used and how many tokens each run consumed
- Where latency and cost concentrate across a multi-agent request
- What the orchestrator actually did during A2A routing, rather than what it claimed it did

> **Workshop disclaimer:** The audit data and remediation actions are simulated. Observability findings in this part describe the workshop proof of concept only.

**Why this matters:** A multi-agent system is opaque by default — a fluent answer looks identical whether the agent consulted the system of record or fabricated the result from memory, and that ambiguity is precisely what makes stakeholders reluctant to rely on it. Traces replace trust with evidence: you can see which tool was called, which source was consulted, what the model cost, and where the request slowed down. That matters commercially, because token consumption is the cost model and multi-agent requests multiply it, so knowing where spend concentrates is what turns a pilot into a budget you can justify. In a compliance context, this kind of end-to-end trace is the raw material any future audit-grade evidence system would need to be built on. The workshop does not itself produce audit evidence; it shows you the substrate.

**Diagram color:** see note — this part spans all four colors (Purple, Green, Blue, Orange) because it observes the components built in Parts 1–4 rather than adding new ones.

## Prerequisites

Parts 1–4 must be complete:

- Application Insights `appi-agentapp-<initials>-mx01` exists and is connected to the Foundry project.
- `policy-audit-info-agent`, `audit-status-agent`, `orchestrator-prompt-agent`, and `remediation-hosted-agent` all exist.
- The audit API and MCP server container apps are running and have `APPLICATIONINSIGHTS_CONNECTION_STRING` set.
- You have run at least the Part 3 and Part 4 validation prompts, so there is telemetry to inspect.

> **Telemetry is based on OpenTelemetry GenAI semantic conventions.** Foundry emits agent, tool, and model spans automatically once Application Insights is connected — you do not add instrumentation code for this workshop.

---

## 1) Generate telemetry to inspect

Telemetry only appears after agents run. Before opening the blade, produce a representative mix of successful runs, multi-agent runs, and a refusal.

Open the `orchestrator-prompt-agent` playground and run these in order:

```text
What is our current audit scorecard?
```

```text
Our PSM Program Controls area is currently Non-compliant. What root-cause violations are driving that rating, and according to the corpus what PSM-1910.119 audit evidence should we gather?
```

```text
How do I set up a Python Flask web server?
```

Each request exercises a different path: a single A2A hop, a two-agent hop with MCP and Foundry IQ retrieval, and a scope-gate refusal with no tool call at all.

> **Ingestion delay:** Telemetry typically appears within one to three minutes. If the blade looks empty, wait and refresh before assuming the connection is broken.

---

## 2) Open the Agents (Preview) blade

1. Open the [Azure portal](https://portal.azure.com).
2. Navigate to resource group **`rg-agent-ws-mx01`**.
3. Open the Application Insights resource **`appi-agentapp-<initials>-mx01`**.
4. In the left navigation, select **Agents (Preview)**.

> You can also reach this view from Foundry. Open an agent, go to the **Monitoring** tab, and select **View in Azure Monitor**.

If the blade reports no agent data, confirm the Foundry project still shows Application Insights as connected (Part 1, Section 2) and that you ran the prompts in Section 1.

---

## 3) Read the agent overview

The Agents view consolidates telemetry across sources into a single monitoring surface. Work through the tiles and record what you observe.

### Agent runs

Identify how many runs occurred and how many failed. Compare this against the three prompts you ran in Section 1.

**Look for:** the orchestrator run count should be lower than the total agent run count, because a single orchestrator run fans out into A2A calls to the specialist agents.

### Tool calls

The **Tool Calls** tile lists the tools invoked across your runs.

**Look for:** the MCP tools exposed in Part 2 — `get_audit_scorecard`, `get_audit_area_detail`, and, if you executed the Part 4 remediation, `update_audit_area` via `apply_approved_remediation`.

**Interpretation:** This tile is the fastest way to prove that the orchestrator actually called a tool instead of answering from memory. A status question that produced no `get_audit_scorecard` call is a routing failure, no matter how confident the response text sounded.

### Models

The **Models** tile shows which model deployments served the runs and their token consumption.

**Look for:** the deployment you created in Part 1, such as `gpt-5.4-mini-deployment`.

**Interpretation:** Token counts here are the cost signal for the workshop. Multi-agent requests cost noticeably more than single-agent requests because the orchestrator, each sub-agent, and any retrieval step each consume context.

### Errors

**Look for:** any Gen AI errors surfaced in the view, particularly failed A2A calls or MCP tool failures.

**Interpretation:** A2A authorization problems from Part 3 and Part 4 often surface as generic server errors in the playground. This view is where you confirm whether the failure was an authorization error, a tool timeout, or a model error.

---

## 4) Investigate traces

From the Agents view, open filtered trace lists:

1. Select **View Traces with Agent Runs** to see all agent executions.
2. Select **View Traces with Gen AI Errors** to isolate failed or problematic runs.
3. Alternatively, select any individual entry in the **Tool Calls** or **Models** tiles to see only traces involving that tool or model.

The **Search** overlay opens with traces filtered to your selection.

Within Search:

- Sort by **Most tokens used** to find the most expensive operations.
- Filter by time range to isolate a specific validation prompt you ran.
- Search prompt content, if sensitive data logging is enabled for your environment.

**Workshop exercise:** Sort by **Most tokens used** and confirm that the combined status-plus-policy prompt from Section 1 ranks above the single-agent scorecard prompt.

> **Sensitive data:** Prompt and response content is only searchable when content logging is enabled. Prompts in this workshop contain simulated audit data, but in a real oil-and-gas compliance deployment, prompt content can include regulated or confidential operational data. Treat content logging as a deliberate governance decision, not a default.

---

## 5) Follow one request end to end

Select any trace to open the **End-to-end transaction details** view.

The **simple view** presents the agent's steps in a clear, sequential story: the invoked agent, the underlying model, the executed tools, and the results of each step. Select **Leave simple view** in the top action bar if you want the traditional transaction view instead.

Open the trace for the combined status-plus-policy prompt and walk the sequence:

1. The `orchestrator-prompt-agent` run begins.
2. An A2A call reaches `audit-status-agent`.
3. `audit-status-agent` calls the MCP tool, which calls the audit API container app.
4. An A2A call reaches `policy-audit-info-agent`.
5. `policy-audit-info-agent` performs Foundry IQ retrieval against the knowledge base.
6. The orchestrator synthesizes and returns the final response.

**Validation questions to answer from the trace:**

- Did the orchestrator call `audit-status-agent` before `policy-audit-info-agent`, as its instructions require?
- Which step contributed the most latency?
- Which step consumed the most tokens?
- Does the refusal trace for the Flask prompt show zero tool calls and zero A2A hops?

The last question matters most. The Part 3 validation instructions state that response text alone is not sufficient to verify routing. This view is the trace-level proof.

---

## 6) Optional: customize with Grafana

For deeper analysis, select **Explore in Grafana** from the top navigation bar of the Agents view.

Azure Monitor ships prebuilt Gen AI dashboards, including:

- **Agent Framework** — agent execution and performance
- **Agent Framework workflow** — workflow patterns and dependencies
- **Foundry** — Foundry-specific metrics and telemetry

Use **Save as** to create a tailored copy rather than editing a prebuilt dashboard in place.

---

## 7) Connect observability back to the audit story

Observability is not a side quest in a compliance proof of concept. The same telemetry that helps you debug also produces the operational evidence an auditor would expect.

Consider how each signal maps to an audit concern:

| Telemetry signal | Audit-relevant question it helps answer |
|---|---|
| Agent run history | Was the workflow actually executed, and when? |
| Tool call records | Which system of record was consulted, and what did it return? |
| A2A trace sequence | Did the request follow the intended, documented routing path? |
| Remediation tool calls | What bounded change was applied, by which identity, and after which approval step? |
| Error traces | Where did the process fail, and was a failure silently substituted with unverified content? |

> **Boundary:** These traces are workshop telemetry, not a validated audit trail. A production compliance system would require tamper-evident retention, defined retention periods, access controls on prompt content, and a documented evidence chain. Treat this section as a design discussion, not a control implementation.

---

## Expected result

You can locate the Agents (Preview) blade for `appi-agentapp-<initials>-mx01`, interpret agent run, tool call, model, and error tiles, filter traces by tool and token usage, and read a single end-to-end transaction to verify multi-agent routing behavior at the trace level rather than trusting response text.
