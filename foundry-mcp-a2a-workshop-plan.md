# Microsoft Foundry + MCP + Agent-to-Agent Workshop Plan

## Recommended approach

Design this as a **pre-provisioned, lab-first workshop** with a short concept intro and progressive build steps. The fastest path to success is:

1. **Preflight first** (access, RBAC, quota, region, tooling) before any coding.
2. Start with **one working hosted agent** in Microsoft Foundry, then layer capability.
3. Add **observability early** (logs/traces/run IDs) before MCP and A2A complexity.
4. Introduce MCP as **contract-first integration** (schema, auth boundary, retries, errors).
5. Build A2A as a **small orchestration pattern** (orchestrator + specialists + critic) with explicit handoff rules.
6. Close with an **evaluate → improve → redeploy** loop and minimal production controls.

This reduces setup failures and keeps the workshop centered on learning outcomes, not environment debugging.

---

## Audience and outcome

**Audience:** Engineers/architects with cloud development experience (mixed Microsoft Foundry familiarity).  
**Primary outcome:** Attendees leave with a deployed Microsoft Foundry agent system that uses MCP tools and a basic A2A orchestration pattern, plus an operational checklist for production hardening.

---

## Phase 2: Workshop use-case slate

For this workshop, treat **OGE** as **Oversight, Governance, and Efficiency** and use a **zero-input slate** that requires no attendee-provided data.

Primary use cases:
- **Policy Navigator & Control Mapper** (core #1)
- **Access Anomaly Triage Simulator** (core #2)
- **Audit Readiness Scorecard Generator** (stretch only)

Detailed definitions and the ready-to-share attendee data pack are documented in:
**`foundry-mcp-a2a-phase-2-use-cases.md`**

---

## Phase 3: Multi-agent blueprint

Phase 3 will implement a concrete 4-agent pattern:
- **Agent 1:** Orchestrator / Harness (A2A hub)
- **Agent 2:** Audit Readiness + Scorecard (4+ audit targets, scorecard, fail->fix->retest loop)
- **Agent 3:** Policy Q&A with bounded OGE-relevant policy corpus
- **Agent 4:** Remediation Agent (executes approved fixes through MCP)

MCP is the interaction plane for audit, approval, remediation, and retest actions.
In this phase, audit readiness is intentionally promoted from Phase 2 stretch to core.

Detailed design is documented in:
**`foundry-mcp-a2a-phase-3-agent-blueprint.md`**

---

## Day-0 readiness checklist (required before workshop)

- Azure access validated (subscription/tenant + required RBAC already assigned)
- Microsoft Foundry project and approved region confirmed
- Model quota validated (plus one fallback model/region)
- Tooling installed and tested (`az`, `azd`, language runtime, package manager)
- Workshop repo cloned and dependencies restored
- Managed identity/federated identity flow verified (no secrets in code)
- Network constraints checked (VPN/proxy/firewall/private endpoint considerations)
- Budget guardrails enabled (budget + cost alerts)
- Break-glass fallback prepared (prebuilt environment/codespace)

---

## Full workshop sequence (recommended: 1 day)

## Module 0 — Architecture framing (30 min)
- Microsoft Foundry building blocks: project, model deployment, prompt vs hosted agents
- MCP mental model: tools as contracts, trust boundaries, protocol selection
- A2A mental model: orchestration, specialization, critic/reviewer loop
- Security defaults: managed identity, least privilege RBAC, no secret embedding

## Module 1 — Environment and Microsoft Foundry bootstrap (45 min)
- Preflight script/checklist run
- Create or connect to Microsoft Foundry project
- Confirm model deployment and endpoint connectivity
- Verify baseline invoke works

## Module 2 — First hosted agent (60 min)
- Scaffold hosted agent
- Configure environment-aware auth (dev vs prod credential behavior)
- Deploy and run smoke invocation

## Module 3 — Observability first (30 min)
- Add/confirm structured logs and trace correlation IDs
- Inspect run traces and identify failure signals

## Module 4 — MCP tool integration (75 min)
- Add Tool 1 (read-oriented tool: retrieval/query)
- Add Tool 2 (action-oriented tool: controlled mutation/workflow trigger)
- Validate input/output schema, timeout/retry strategy, explicit error behavior

## Module 5 — Agent-to-Agent composition (75 min)
- Implement orchestrator + two specialists
- Add critic/reviewer agent to challenge outputs
- Define handoff contract: routing rules, retry policy, escalation/fallback
- Run scenario-driven end-to-end lab

## Module 6 — Evaluate and iterate (45 min)
- Run smoke/regression evaluations
- Review traces + evaluation outcomes
- Tune instructions/prompts and compare before/after behavior

## Module 7 — Production essentials (30 min)
- CI/CD gates (quality/security checks)
- Rollback/version strategy
- Policy/compliance controls
- Cost/quota controls and incident runbook starter

---

## Half-day cut-down option (4 hours)

1. Preflight + bootstrap (30–45 min)  
2. Single hosted agent deploy/invoke (60 min)  
3. One MCP integration lab (60 min)  
4. Lightweight A2A demo (orchestrator + 1 specialist + critic) (45 min)  
5. Eval/trace walkthrough + production checklist (30 min)

---

## Lab design principles

- Every module ends with a **checkpoint artifact** (running invoke, trace screenshot, passing eval, etc.)
- Keep exercises in **small increments**; avoid multi-service leaps in one step
- Provide an **advanced track** for faster attendees (extra tool, deeper critic policy, richer eval suite)
- Treat failures as teachable moments with explicit troubleshooting playcards

---

## Deliverables to prepare

- Instructor guide with timing, commands, and fallback paths
- Participant lab manual with copy/paste scripts and expected outputs
- Preflight script + environment validation matrix
- Starter repository with module branches/tags
- Troubleshooting catalog (RBAC, quota, network, deployment, invoke)
- Post-workshop production checklist (security, reliability, cost)
