# Microsoft Foundry + MCP + A2A Workshop — Phase 3 Agent Blueprint

## Goal

Deliver a **zero-input**, medium-complexity multi-agent lab where attendees only run workshop commands and prompts.

> Phase 3 intentionally promotes the Phase 2 stretch scenario (audit readiness) into a core implementation lab.

## Agent topology

## Agent 1 — Orchestrator / Harness (A2A Hub)
- Entry point for attendee prompts.
- Connected to Agent 2, Agent 3, and Agent 4 using Agent-to-Agent protocol.
- Owns run state and workflow stage:
  - `audit_check`
  - `policy_lookup`
  - `approval_pending`
  - `remediation_applied`
  - `retest_complete`
- Exposes MCP-mediated actions only (no direct/manual backend changes).
- Performs the **critic/reviewer pass** before final responses are returned to attendees.

## Agent 2 — Audit Readiness + Scorecard
- Defines and evaluates at least **4 audit targets**.
- Returns target-level pass/fail + rationale + evidence pointer.
- Generates a consolidated scorecard.
- If failures exist, proposes remediation options and requests approval via MCP.
- Agent 2 proposes remediation; Agent 1 executes the approval gate and remediation calls.

### Required audit targets (minimum 4)
1. **Control Ownership Coverage**  
   Every control has an assigned owner and review cadence.
2. **Evidence Freshness**  
   Evidence timestamp is within policy window.
3. **Policy Citation Completeness**  
   Each control maps to at least one policy clause ID.
4. **Exception Closure Status**  
   Open high-risk exceptions have mitigation owner + due date.

### Scorecard output shape
- `audit_run_id`
- `overall_score` (0-100)
- `targets[]` with:
  - `target_id`
  - `status` (`pass` | `fail`)
  - `score`
  - `reason`
  - `evidence_ref`
- `recommended_actions[]`

## Agent 3 — Policy Q&A (Microsoft Foundry IQ-aligned)
- Answers policy questions with citations and confidence.
- Supports retrieval over a **bounded workshop policy corpus**.
- Used by Agent 1 and Agent 2 when policy interpretation is needed.

## Agent 4 — Remediation Agent
- Executes approved remediation plans for failed audit targets.
- Accepts structured remediation instructions from Agent 1.
- Applies deterministic workshop-safe changes through MCP operations only.
- Returns remediation result payload with:
  - `remediation_id`
  - `target_id`
  - `change_summary`
  - `status`
  - `updated_evidence_ref`

## Policy corpus (substantive but bounded)

Use **8-10 markdown policy documents** (not PDFs) with stable clause IDs:

1. Ethics and Standards of Conduct  
2. Conflict of Interest and Recusal  
3. Gifts, Travel, and Outside Activities  
4. Financial Disclosure and Reporting Timelines  
5. Procurement Integrity and Vendor Interaction  
6. Records Retention and Audit Trail Requirements  
7. Access Control and Least Privilege  
8. Exception Management and Escalation  
9. Incident Reporting and Corrective Action (optional)  
10. Training and Annual Attestation (optional)

Recommended size: ~2-4 pages each equivalent (or 1,000-2,000 words each) to stay substantive without overload.

## MCP-only interaction model

All cross-component actions are mediated through MCP tools.

## Core MCP operations
- `run_audit_targets` (Agent 2)
- `generate_scorecard` (Agent 2)
- `query_policy` (Agent 3)
- `request_human_approval` (approval gate)
- `apply_remediation_plan` (Agent 4)
- `rerun_audit_targets` (Agent 2)

> Remediation is executed by Agent 4 via MCP after Agent 1 records human approval. Attendees do not need to supply data or manually patch files.

## Required fail -> approve -> fix -> pass loop

1. Agent 1 triggers Agent 2 audit run.
2. Agent 2 returns scorecard with at least one failed target.
3. Agent 2 proposes remediation plan.
4. Agent 1 calls MCP `request_human_approval`.
5. On approval, Agent 1 invokes Agent 4, which calls MCP `apply_remediation_plan`.
6. Agent 1 triggers Agent 2 re-test (`rerun_audit_targets`).
7. Updated scorecard shows previously failing target now passing.

### Deterministic workshop rule
- Seed data must include one known failing control (`CTRL-003`) at lab start.
- `apply_remediation_plan` must deterministically update `CTRL-003` evidence state.
- Re-test must flip only that target from `fail` to `pass` unless attendees choose additional fixes.

## A2A availability fallback

If A2A preview endpoints are unavailable in the selected region, keep the same logical topology but route Agent 2/3/4 calls through MCP wrappers exposed to Agent 1. This preserves the workshop flow (orchestrate -> audit/policy -> approval -> remediation -> re-test) without blocking on preview availability.

## Lab acceptance criteria

- A2A routing occurs between Agent 1 -> Agent 2, Agent 1 -> Agent 3, and Agent 1 -> Agent 4.
- At least 4 audit targets are interrogated.
- Scorecard is generated before and after remediation.
- Human approval gate is captured in run output.
- Remediation is invoked through MCP and changes re-test outcome to pass.
- No attendee-provided files or records are required.
