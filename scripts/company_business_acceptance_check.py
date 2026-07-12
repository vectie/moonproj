#!/usr/bin/env python3
"""Validate the owner-decision packet for migration and shadow operation.

The packet is intentionally separate from technical parity. Empty decisions
are valid evidence of pending review, but never authorize shadow ownership or
cutover. A deferred scope exception may permit a bounded shadow period; it
does not waive the exception.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class AcceptanceError(RuntimeError):
    pass


REQUIRED_DECISIONS = {
    "task-state-proj-0001": "business",
    "erp-schema-coverage": "migration-owner",
    "production-database-deployment": "operations",
    "accounting-reconciliation": "finance",
    "shadow-period": "operations",
}
ALLOWED = {"accept_for_shadow", "defer", "reject"}
SHADOW_REQUIRED_DECISIONS = {
    "production-database-deployment",
    "accounting-reconciliation",
    "shadow-period",
}
SECRET_KEY = re.compile(r"password|secret|token|private|credential", re.IGNORECASE)


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AcceptanceError(f"cannot read JSON: {path}") from error


def reject_secrets(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise AcceptanceError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def validate(work_dir: Path, manifest: Any) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise AcceptanceError("acceptance manifest must be an object")
    reject_secrets(manifest)
    if manifest.get("format") != "moonproj.erp.business-acceptance.v1":
        raise AcceptanceError("unsupported business-acceptance format")
    source_contract = load(work_dir / "source-export-contract.json")
    row_coverage = load(work_dir / "row-coverage.json")
    if source_contract.get("format") != "moonproj.erp.export-contract.v1":
        raise AcceptanceError("source export contract is missing or invalid")
    if row_coverage.get("format") != "moonproj.erp.row-coverage.v1":
        raise AcceptanceError("row coverage evidence is missing or invalid")
    source_snapshot_id = manifest.get("source_snapshot_id")
    expected_snapshot = "erp-snapshot:" + str(source_contract.get("source_sha256", ""))
    if source_snapshot_id == "from-source-export-evidence":
        source_snapshot_id = expected_snapshot
    if source_snapshot_id != expected_snapshot:
        raise AcceptanceError("acceptance source snapshot does not match export evidence")
    decisions = manifest.get("decisions")
    if not isinstance(decisions, list):
        raise AcceptanceError("decisions must be an array")
    by_id: dict[str, dict[str, Any]] = {}
    for decision in decisions:
        if not isinstance(decision, dict):
            raise AcceptanceError("decision entry is not an object")
        decision_id = decision.get("id")
        if not isinstance(decision_id, str) or decision_id in by_id:
            raise AcceptanceError("decision IDs must be unique non-empty strings")
        if decision_id not in REQUIRED_DECISIONS:
            raise AcceptanceError(f"unexpected decision ID: {decision_id}")
        if decision.get("owner_role") != REQUIRED_DECISIONS[decision_id]:
            raise AcceptanceError(f"wrong owner role for {decision_id}")
        value = decision.get("decision")
        if value is not None and value not in ALLOWED:
            raise AcceptanceError(f"unsupported decision for {decision_id}: {value}")
        if value is not None:
            for field in ("decided_by", "decided_at", "rationale"):
                if not isinstance(decision.get(field), str) or not decision[field].strip():
                    raise AcceptanceError(f"{decision_id} requires {field}")
            refs = decision.get("evidence_refs")
            if not isinstance(refs, list) or not refs or any(not isinstance(ref, str) for ref in refs):
                raise AcceptanceError(f"{decision_id} requires evidence_refs")
        by_id[decision_id] = decision
    missing = sorted(set(REQUIRED_DECISIONS) - set(by_id))
    if missing:
        raise AcceptanceError("required decisions missing: " + ",".join(missing))
    pending = sorted(decision_id for decision_id, value in by_id.items() if value.get("decision") is None)
    rejected = sorted(decision_id for decision_id, value in by_id.items() if value.get("decision") == "reject")
    deferred = sorted(decision_id for decision_id, value in by_id.items() if value.get("decision") == "defer")
    accepted = sorted(decision_id for decision_id, value in by_id.items() if value.get("decision") == "accept_for_shadow")
    authorized = (
        not pending
        and not rejected
        and all(
            by_id[decision_id].get("decision") == "accept_for_shadow"
            for decision_id in SHADOW_REQUIRED_DECISIONS
        )
    )
    return {
        "format": "moonproj.erp.business-acceptance-result.v1",
        "source_snapshot_id": source_snapshot_id,
        "state": "acceptance_pending" if pending or rejected else "ready_for_shadow",
        "acceptance_authorized": authorized,
        "shadow_authorized": authorized,
        "cutover_authorized": False,
        "required_decisions": len(REQUIRED_DECISIONS),
        "pending_decisions": pending,
        "rejected_decisions": rejected,
        "deferred_decisions": deferred,
        "accepted_for_shadow": accepted,
        "technical_evidence": {
            "source_export_state": source_contract.get("state"),
            "source_rows": row_coverage.get("source_rows"),
            "covered_rows": row_coverage.get("covered_rows"),
            "uncovered_rows": row_coverage.get("uncovered_rows"),
        },
        "decisions": decisions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.work_dir, load(args.manifest))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "state": result["state"],
            "acceptance_authorized": result["acceptance_authorized"],
            "pending_decisions": len(result["pending_decisions"]),
            "deferred_decisions": len(result["deferred_decisions"]),
        }, sort_keys=True))
        return 0
    except (OSError, AcceptanceError, TypeError, ValueError) as error:
        print(f"business acceptance check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
