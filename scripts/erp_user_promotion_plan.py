#!/usr/bin/env python3
"""Build a credential-free ERP user-directory promotion plan."""

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
        principal_by_bu = config.get("principal_by_bu", {})
        if not isinstance(principal_by_bu, dict):
            raise PlanError("principal_by_bu must be an object")
        users = load(args.export / "tables" / "sys_user.json")
        if not isinstance(users, list):
            raise PlanError("user export must be an array")

        items: list[dict[str, Any]] = []
        for row in users:
            user_id = str(row.get("user_id", ""))
            bu_id = str(row.get("bu_guid", ""))
            principal = principal_by_bu.get(bu_id)
            reasons: list[str] = []
            if not user_id or not row.get("user_code"):
                reasons.append("missing_user_identity")
            if not bu_id:
                reasons.append("missing_business_unit")
            if not principal:
                reasons.append("missing_principal_by_bu")
            display_name = row.get("emp_name") or row.get("user_name")
            if not display_name:
                reasons.append("missing_display_name")
            candidate = {
                "user_id": user_id,
                "user_code": row.get("user_code"),
                "display_name": display_name,
                "principal_id": principal,
                "business_unit_id": bu_id,
                "department_id": row.get("dept_guid"),
                "enabled": bool(row.get("enabled", 0)),
                "source_super_user": bool(row.get("is_super_user", 0)),
                "authority_scope": f"organization:{bu_id}",
            }
            warnings = [
                "password_hash, login IP, and authentication timestamps are not imported"
            ]
            if row.get("is_super_user"):
                warnings.append("legacy super_user is evidence only; no target privilege is granted")
            items.append(
                {
                    "source_table": "sys_user",
                    "source_id": user_id,
                    "target_type": "user_account",
                    "target_id": user_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": warnings,
                    "target_candidate": candidate if not reasons else None,
                }
            )

        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.user-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-user-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"user promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
