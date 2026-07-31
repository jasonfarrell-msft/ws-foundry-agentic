# Part 3: A2A Communication Validation Prompts

After republishing the orchestrator agent with A2A connections, use these 5 prompts in the Foundry playground to validate that the orchestrator correctly routes requests to the appropriate sub-agents.

## Routing Rules (from orchestrator-agent.json)

The orchestrator follows these rules:
1. **Live status, scores, findings** → `audit-status-agent`
2. **Policy, regulations, required evidence** → `policy-audit-info-agent`
3. **Both needed** (e.g., "what is driving this finding AND what does the regulation say?") → call both and synthesize
4. **Neither can answer** → say so directly, do not speculate

---

## Prompt 1: Route to audit-status-agent (Status Query)

**Category:** Live compliance status  
**Expected:** Orchestrator calls `audit-status-agent` only

```
What are our current compliance scores across all audit areas? Which areas are non-compliant?
```

**Validation checklist:**
- ✅ Orchestrator routes to `audit-status-agent`
- ✅ Response includes scorecard ratings across 7 audit areas
- ✅ Response identifies non-compliant areas
- ✅ No citations to knowledge base (those come from policy-audit-info-agent)

---

## Prompt 2: Route to policy-audit-info-agent (Policy Query)

**Category:** Regulatory requirements  
**Expected:** Orchestrator calls `policy-audit-info-agent` only

```
What does 40 CFR Part 80 require for fuel quality testing, and what evidence do we need for an audit?
```

**Validation checklist:**
- ✅ Orchestrator routes to `policy-audit-info-agent`
- ✅ Response includes citations from the knowledge base
- ✅ Response describes required audit evidence
- ✅ No live scorecard data (that comes from audit-status-agent)

---

## Prompt 3: Route to Both Agents (Synthesis Query)

**Category:** Finding + regulation explanation  
**Expected:** Orchestrator calls both agents and synthesizes

```
Our compliance score for fuel quality testing is red. What specific regulation requirement are we failing to meet, and what evidence should we gather to close this gap?
```

**Validation checklist:**
- ✅ Orchestrator calls both agents
- ✅ Response includes current status from `audit-status-agent` (red compliance score)
- ✅ Response includes regulatory requirement from `policy-audit-info-agent` (with citations)
- ✅ Response synthesizes both into actionable remediation steps

---

## Prompt 4: Edge Case - Neither Agent (Out of Scope)

**Category:** Question outside audit/policy domain  
**Expected:** Orchestrator says it cannot answer

```
How do I set up a Python Flask web server?
```

**Validation checklist:**
- ✅ Orchestrator recognizes this is outside the audit/policy domain
- ✅ Response is "I cannot answer this question" or equivalent
- ✅ No hallucinated answers from either sub-agent
- ✅ No speculative technical content

---

## Prompt 5: Complex Routing (Status + Evidence)

**Category:** Multi-step compliance validation  
**Expected:** Orchestrator calls both agents

```
We have a finding in the Environmental Compliance area. What root-cause violations are driving this finding, and per EPA regulations, what documentation must we submit to demonstrate remediation?
```

**Validation checklist:**
- ✅ Orchestrator calls `audit-status-agent` first (root-cause violations in Environmental Compliance)
- ✅ Orchestrator calls `policy-audit-info-agent` (EPA regulatory documentation requirements)
- ✅ Response connects the finding to the specific regulatory burden
- ✅ Response is grounded in real data, not speculation

---

## Troubleshooting

If a prompt does not route correctly:

1. **Check that both A2A connections are active:**
   ```powershell
   .\scripts\verify-agent-card.ps1 `
       -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
       -ResourceGroupName "YOUR_RESOURCE_GROUP" `
       -ProjectName       "YOUR_PROJECT_NAME" `
       -AgentName         "audit-status-agent"
   
   .\scripts\verify-agent-card.ps1 `
       -FoundryName       "YOUR_FOUNDRY_ACCOUNT_NAME" `
       -ResourceGroupName "YOUR_RESOURCE_GROUP" `
       -ProjectName       "YOUR_PROJECT_NAME" `
       -AgentName         "policy-audit-info-agent"
   ```

2. **Verify the connection names are correct in `orchestrator-agent.json`:**
   - Should match the names printed by `enable-a2a.ps1`
   - Defaults to `<agent-name>-a2a`

3. **Check the orchestrator routing instructions:**
   - Open the orchestrator agent in Foundry
   - Confirm the system prompt contains the routing rules
   - If instructions are unclear, simplify them and republish

4. **Review sub-agent descriptions:**
   - Each agent's card description should be routing-intent-aware
   - Run `verify-agent-card.ps1` to see what descriptions the orchestrator reads

---

## Next Steps

- [ ] Republish orchestrator with A2A connections
- [ ] Test Prompt 1 in Foundry playground
- [ ] Test Prompt 2 in Foundry playground
- [ ] Test Prompt 3 in Foundry playground
- [ ] Test Prompt 4 in Foundry playground
- [ ] Test Prompt 5 in Foundry playground
- [ ] Document any routing issues found
- [ ] Refine orchestrator instructions if needed
- [ ] Commit validation results to `docs/` or session state
