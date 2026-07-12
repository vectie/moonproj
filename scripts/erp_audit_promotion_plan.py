#!/usr/bin/env python3
"""Build an explicit, credential-safe audit-record promotion plan."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        audit_by_id = config.get("audit_by_id", {})
        principal_by_bu = config.get("principal_by_bu", {})
        if not isinstance(audit_by_id, dict) or not isinstance(principal_by_bu, dict):
            raise PlanError("audit_by_id and principal_by_bu must be objects")
        rows = load(args.export / "tables" / "audit_log.json")
        if not isinstance(rows, list):
            raise PlanError("audit export must be an array")

        items: list[dict[str, Any]] = []
        for row in rows:
            audit_id = str(row.get("log_id", ""))
            source_mapping = audit_by_id.get(audit_id)
            reasons: list[str] = []
            if not audit_id or not row.get("user_id"):
                reasons.append("missing_audit_or_actor_identity")
            if not isinstance(source_mapping, dict):
                reasons.append("missing_audit_target_mapping")
                source_mapping = {}
            bu_id = str(source_mapping.get("business_unit_id", ""))
            principal = source_mapping.get("principal_id") or principal_by_bu.get(bu_id)
            if not principal:
                reasons.append("missing_principal_mapping")
            scope = source_mapping.get("scope") or (f"organization:{bu_id}" if bu_id else "")
            target_type = source_mapping.get("target_type")
            target_id = source_mapping.get("target_id")
            outcome = source_mapping.get("outcome")
            if not scope or not target_type or not target_id or not outcome:
                reasons.append("incomplete_audit_target_mapping")
            candidate = {
                "audit_id": audit_id,
                "user_id": row.get("user_id"),
                "action": row.get("action"),
                "created_at": row.get("created_at"),
                "principal_id": principal,
                "scope": scope,
                "target_type": target_type,
                "target_id": target_id,
                "outcome": outcome,
            }
            items.append(
                {
                    "source_table": "audit_log",
                    "source_id": audit_id,
                    "target_type": "audit_record",
                    "target_id": audit_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "redacted network fields remain outside the target audit record"
                    ],
                    "target_candidate": candidate if not reasons else None,
                }
            )

        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.audit-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-audit-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"audit promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
