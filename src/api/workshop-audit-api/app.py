import json
import os
from copy import deepcopy
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from uuid import uuid4

HOST = "0.0.0.0"
PORT = int(os.getenv("PORT", "8080"))
POLICY_WINDOW_DAYS = 90
ROLE_API_KEY_ENV = {
    "agent-1-orchestrator": "MCP_API_KEY_AGENT_1",
    "agent-2-audit-readiness": "MCP_API_KEY_AGENT_2",
    "agent-4-remediation": "MCP_API_KEY_AGENT_4",
    "human-approver": "MCP_API_KEY_HUMAN_APPROVER",
}

INITIAL_CONTROLS = [
    {
        "controlId": "CTRL-001",
        "owner": "ops-lead",
        "reviewCadenceDays": 30,
        "evidenceAgeDays": 21,
        "policyClauses": ["OGE-RET-01", "OGE-AUD-03"],
        "highRiskException": None,
    },
    {
        "controlId": "CTRL-002",
        "owner": "security-lead",
        "reviewCadenceDays": 45,
        "evidenceAgeDays": 17,
        "policyClauses": ["OGE-ACC-02"],
        "highRiskException": {"mitigationOwner": "security-lead", "dueDate": "2026-12-31"},
    },
    {
        "controlId": "CTRL-003",
        "owner": "audit-lead",
        "reviewCadenceDays": 30,
        "evidenceAgeDays": 120,
        "policyClauses": ["OGE-EVD-04"],
        "highRiskException": None,
    },
    {
        "controlId": "CTRL-004",
        "owner": "governance-lead",
        "reviewCadenceDays": 60,
        "evidenceAgeDays": 24,
        "policyClauses": ["OGE-GOV-07"],
        "highRiskException": None,
    },
]

STATE = {
    "controls": deepcopy(INITIAL_CONTROLS),
    "approvalRequests": {},
    "remediationPlans": {},
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def to_percent(passed: int, total: int) -> int:
    if total == 0:
        return 0
    return round((passed / total) * 100)


def normalize_target_payload(reason: str, evidence_ref: str) -> dict:
    return {
        "reason": reason,
        "evidence_ref": evidence_ref,
        "rationale": reason,
        "evidence_pointer": evidence_ref,
    }


def evaluate_targets() -> dict:
    controls = STATE["controls"]
    ownership_failures = [
        c
        for c in controls
        if not c.get("owner")
        or not isinstance(c.get("reviewCadenceDays"), (int, float))
        or c["reviewCadenceDays"] <= 0
    ]
    evidence_failures = [c for c in controls if c["evidenceAgeDays"] > POLICY_WINDOW_DAYS]
    citation_failures = [c for c in controls if not c.get("policyClauses")]
    exception_failures = [
        c
        for c in controls
        if c.get("highRiskException")
        and (
            not c["highRiskException"].get("mitigationOwner")
            or not c["highRiskException"].get("dueDate")
        )
    ]

    ownership_reason = (
        "All controls have owner and review cadence."
        if len(ownership_failures) == 0
        else f"{len(ownership_failures)} control(s) are missing owner or cadence."
    )
    ownership_evidence = (
        "dataset://controls?check=ownership"
        if len(ownership_failures) == 0
        else f"dataset://controls/{','.join(c['controlId'] for c in ownership_failures)}?check=ownership"
    )

    evidence_reason = (
        f"All control evidence is within {POLICY_WINDOW_DAYS} days."
        if len(evidence_failures) == 0
        else f"{len(evidence_failures)} control(s) have stale evidence older than {POLICY_WINDOW_DAYS} days."
    )
    evidence_ref = (
        "dataset://controls?check=evidence-freshness"
        if len(evidence_failures) == 0
        else f"dataset://controls/{','.join(c['controlId'] for c in evidence_failures)}?check=evidence-freshness"
    )

    citation_reason = (
        "All controls map to at least one policy clause."
        if len(citation_failures) == 0
        else f"{len(citation_failures)} control(s) have no policy clause mapping."
    )
    citation_evidence = (
        "dataset://controls?check=policy-citation"
        if len(citation_failures) == 0
        else f"dataset://controls/{','.join(c['controlId'] for c in citation_failures)}?check=policy-citation"
    )

    exception_reason = (
        "All high-risk exceptions have mitigation owner and due date."
        if len(exception_failures) == 0
        else f"{len(exception_failures)} high-risk exception(s) are missing closure metadata."
    )
    exception_evidence = (
        "dataset://exceptions?check=closure"
        if len(exception_failures) == 0
        else f"dataset://controls/{','.join(c['controlId'] for c in exception_failures)}?check=exception-closure"
    )

    targets = [
        {
            "target_id": "control-ownership-coverage",
            "status": "pass" if len(ownership_failures) == 0 else "fail",
            "score": to_percent(len(controls) - len(ownership_failures), len(controls)),
            **normalize_target_payload(ownership_reason, ownership_evidence),
        },
        {
            "target_id": "evidence-freshness",
            "status": "pass" if len(evidence_failures) == 0 else "fail",
            "score": to_percent(len(controls) - len(evidence_failures), len(controls)),
            **normalize_target_payload(evidence_reason, evidence_ref),
        },
        {
            "target_id": "policy-citation-completeness",
            "status": "pass" if len(citation_failures) == 0 else "fail",
            "score": to_percent(len(controls) - len(citation_failures), len(controls)),
            **normalize_target_payload(citation_reason, citation_evidence),
        },
        {
            "target_id": "exception-closure-status",
            "status": "pass" if len(exception_failures) == 0 else "fail",
            "score": to_percent(len(controls) - len(exception_failures), len(controls)),
            **normalize_target_payload(exception_reason, exception_evidence),
        },
    ]

    failed_targets = [t for t in targets if t["status"] == "fail"]
    overall_score = round(sum(t["score"] for t in targets) / len(targets))
    return {
        "audit_run_id": f"audit-{uuid4()}",
        "overall_score": overall_score,
        "targets": targets,
        "recommended_actions": [
            {
                "target_id": t["target_id"],
                "action": f"Remediate failed target {t['target_id']}",
                "rationale": t["reason"],
                "evidence_ref": t["evidence_ref"],
            }
            for t in failed_targets
        ],
    }


def build_remediation_plan(audit_result: dict) -> dict:
    failing_target_ids = [t["target_id"] for t in audit_result["targets"] if t["status"] == "fail"]
    options = []
    if "evidence-freshness" in failing_target_ids:
        options.append(
            {
                "remediation_id": f"remed-{uuid4()}",
                "target_id": "evidence-freshness",
                "title": "Refresh evidence for CTRL-003",
                "change_summary": "Update evidence artifact timestamp and link for CTRL-003.",
                "expected_outcome": "Target evidence-freshness moves from fail to pass.",
            }
        )
    if not options:
        options.append(
            {
                "remediation_id": f"remed-{uuid4()}",
                "target_id": "none",
                "title": "No remediation required",
                "change_summary": "All targets are passing.",
                "expected_outcome": "No change.",
            }
        )

    plan = {
        "proposal_id": f"proposal-{uuid4()}",
        "from_agent": "agent-2-audit-readiness",
        "for_agent": "agent-1-orchestrator",
        "status": "approval-required" if failing_target_ids else "not-required",
        "failing_targets": failing_target_ids,
        "remediation_options": options,
    }
    STATE["remediationPlans"][plan["proposal_id"]] = plan
    return plan


class Handler(BaseHTTPRequestHandler):
    server_version = "workshop-audit-api/1.0"

    def _respond(self, status_code: int, body: dict):
        payload = json.dumps(body, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _read_json(self):
        raw_length = self.headers.get("Content-Length", "0")
        try:
            content_length = int(raw_length)
        except ValueError:
            self._respond(400, {"error": "invalid_content_length"})
            return None
        if content_length > 1_000_000:
            self._respond(413, {"error": "request_too_large"})
            return None
        if content_length == 0:
            return {}
        raw = self.rfile.read(content_length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self._respond(400, {"error": "invalid_json", "message": "Invalid JSON body"})
            return None

    def _authorize(self, allowed_roles):
        role = self.headers.get("x-mcp-role")
        if role not in allowed_roles:
            self._respond(403, {"error": "forbidden", "message": f"Caller role must be one of: {', '.join(allowed_roles)}"})
            return False

        env_name = ROLE_API_KEY_ENV.get(role)
        expected_key = os.getenv(env_name) if env_name else None
        if not expected_key:
            self._respond(
                503,
                {
                    "error": "service_not_configured",
                    "message": f"API key is not configured for role '{role}'.",
                },
            )
            return False

        provided_key = self.headers.get("x-mcp-api-key")
        if provided_key != expected_key:
            self._respond(401, {"error": "unauthorized", "message": "Missing or invalid MCP API key."})
            return False

        return True

    def do_GET(self):
        if self.path == "/health":
            self._respond(200, {"status": "ok", "service": "workshop-audit-api"})
            return
        self._respond(404, {"error": "not_found", "path": self.path})

    def do_POST(self):
        try:
            if self.path == "/mcp/audit/run":
                if not self._authorize(["agent-1-orchestrator", "agent-2-audit-readiness"]):
                    return
                audit = evaluate_targets()
                remediation = build_remediation_plan(audit)
                self._respond(200, {**audit, "remediation": remediation})
                return

            if self.path == "/mcp/remediation/propose":
                if not self._authorize(["agent-1-orchestrator", "agent-2-audit-readiness"]):
                    return
                body = self._read_json()
                if body is None:
                    return
                proposal_id = body.get("proposal_id")
                if not proposal_id:
                    self._respond(400, {"error": "proposal_id is required", "message": "Use the proposal_id returned by /mcp/audit/run."})
                    return
                plan = STATE["remediationPlans"].get(proposal_id)
                if not plan:
                    self._respond(404, {"error": "proposal_not_found", "proposal_id": proposal_id})
                    return
                self._respond(200, plan)
                return

            if self.path == "/mcp/approval/request":
                if not self._authorize(["agent-1-orchestrator"]):
                    return
                body = self._read_json()
                if body is None:
                    return
                proposal_id = body.get("proposal_id")
                requested_by = body.get("requested_by")
                if not proposal_id or not requested_by:
                    self._respond(400, {"error": "proposal_id and requested_by are required"})
                    return
                proposal = STATE["remediationPlans"].get(proposal_id)
                if not proposal:
                    self._respond(404, {"error": "proposal_not_found", "proposal_id": proposal_id})
                    return
                if proposal["status"] != "approval-required" or len(proposal["failing_targets"]) == 0:
                    self._respond(409, {"error": "approval_not_required", "proposal_id": proposal_id})
                    return
                request = {
                    "approval_request_id": f"approve-{uuid4()}",
                    "proposal_id": proposal_id,
                    "requested_by": requested_by,
                    "approver": body.get("approver", "human-reviewer"),
                    "status": "pending",
                    "created_at": now_iso(),
                }
                STATE["approvalRequests"][request["approval_request_id"]] = request
                self._respond(201, request)
                return

            if self.path == "/mcp/approval/decide":
                if not self._authorize(["human-approver"]):
                    return
                body = self._read_json()
                if body is None:
                    return
                approval_request_id = body.get("approval_request_id")
                decision = body.get("decision")
                if not approval_request_id or not decision:
                    self._respond(400, {"error": "approval_request_id and decision are required"})
                    return
                request = STATE["approvalRequests"].get(approval_request_id)
                if not request:
                    self._respond(404, {"error": "approval_request_not_found", "approval_request_id": approval_request_id})
                    return
                if request["status"] != "pending":
                    self._respond(409, {"error": "approval_already_decided", "approval_request_id": approval_request_id, "status": request["status"]})
                    return
                if decision not in ("approved", "rejected"):
                    self._respond(400, {"error": "decision must be approved or rejected"})
                    return

                selected_remediation_id = body.get("selected_remediation_id")
                target_id = body.get("target_id")
                if decision == "approved" and (not selected_remediation_id or not target_id):
                    self._respond(400, {"error": "selected_remediation_id and target_id are required for approved decisions"})
                    return

                proposal = STATE["remediationPlans"].get(request["proposal_id"])
                if not proposal:
                    self._respond(404, {"error": "proposal_not_found", "proposal_id": request["proposal_id"]})
                    return

                if decision == "approved":
                    selected = next(
                        (
                            option
                            for option in proposal["remediation_options"]
                            if option["remediation_id"] == selected_remediation_id and option["target_id"] == target_id
                        ),
                        None,
                    )
                    if selected is None:
                        self._respond(
                            400,
                            {
                                "error": "invalid_remediation_selection",
                                "message": "selected_remediation_id and target_id must match a proposal remediation option.",
                            },
                        )
                        return
                    request["selected_remediation_id"] = selected_remediation_id
                    request["target_id"] = target_id
                    request["consumed"] = False

                request["status"] = decision
                request["decided_at"] = now_iso()
                request["decided_by"] = body.get("decided_by", "human-reviewer")
                STATE["approvalRequests"][approval_request_id] = request
                self._respond(200, request)
                return

            if self.path == "/mcp/remediation/apply":
                if not self._authorize(["agent-1-orchestrator", "agent-4-remediation"]):
                    return
                body = self._read_json()
                if body is None:
                    return
                approval_request_id = body.get("approval_request_id")
                remediation_id = body.get("remediation_id")
                target_id = body.get("target_id")
                if not approval_request_id or not remediation_id or not target_id:
                    self._respond(400, {"error": "approval_request_id, remediation_id, and target_id are required"})
                    return
                approval = STATE["approvalRequests"].get(approval_request_id)
                if not approval:
                    self._respond(404, {"error": "approval_request_not_found", "approval_request_id": approval_request_id})
                    return
                if approval["status"] != "approved":
                    self._respond(409, {"error": "approval_not_granted", "approval_request_id": approval_request_id, "status": approval["status"]})
                    return
                if approval.get("consumed"):
                    self._respond(409, {"error": "approval_already_consumed", "approval_request_id": approval_request_id})
                    return
                if approval.get("selected_remediation_id") != remediation_id or approval.get("target_id") != target_id:
                    self._respond(
                        409,
                        {
                            "error": "approval_scope_mismatch",
                            "message": "Approved remediation_id and target_id do not match this apply request.",
                        },
                    )
                    return
                if target_id != "evidence-freshness":
                    self._respond(
                        400,
                        {
                            "error": "unsupported_target",
                            "message": "This workshop API currently supports remediation for evidence-freshness only.",
                        },
                    )
                    return

                ctrl003 = next((control for control in STATE["controls"] if control["controlId"] == "CTRL-003"), None)
                if ctrl003 is None:
                    self._respond(500, {"error": "internal_error", "message": "CTRL-003 not found"})
                    return

                ctrl003["evidenceAgeDays"] = 7
                approval["consumed"] = True
                STATE["approvalRequests"][approval_request_id] = approval
                self._respond(
                    200,
                    {
                        "remediation_id": remediation_id,
                        "target_id": target_id,
                        "change_summary": "Updated CTRL-003 evidence age from 120 days to 7 days.",
                        "status": "applied",
                        "updated_evidence_ref": "dataset://controls/CTRL-003?check=evidence-freshness",
                    },
                )
                return

            self._respond(404, {"error": "not_found", "path": self.path})
        except Exception as exc:
            self._respond(500, {"error": "internal_error", "message": str(exc)})


if __name__ == "__main__":
    server = HTTPServer((HOST, PORT), Handler)
    print(f"workshop-audit-api listening on http://{HOST}:{PORT}")
    server.serve_forever()
