#!/usr/bin/env python3
"""Build an investment-model/index promotion plan from the safe ERP export."""

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


def value_repr(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


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
        versions = load(args.export / "tables" / "tzsy_version.json")
        indexes = load(args.export / "tables" / "tzsy_plan_index.json")
        if not isinstance(versions, list) or not isinstance(indexes, list):
            raise PlanError("investment version/index exports must be arrays")

        items: list[dict[str, Any]] = []
        version_ids = {str(version.get("version_guid", "")) for version in versions}
        for version in versions:
            version_id = str(version.get("version_guid", ""))
            project_id = str(version.get("proj_guid", ""))
            bu_id = str(version.get("bu_guid", ""))
            principal = principal_by_bu.get(bu_id)
            reasons: list[str] = []
            if not principal:
                reasons.append("missing_principal_by_bu")
            if not version_id or not project_id:
                reasons.append("missing_version_or_project_id")
            version_indexes = [
                row for row in indexes if str(row.get("version_guid", "")) == version_id
            ]
            version_indexes.sort(
                key=lambda row: (int(row.get("sort_order", 0)), str(row.get("index_guid", "")))
            )
            if not version_indexes:
                reasons.append("missing_indexes")
            seen_codes: set[str] = set()
            candidate_indexes: list[dict[str, Any]] = []
            for row in version_indexes:
                index_id = str(row.get("index_guid", ""))
                full_code = str(row.get("full_code", ""))
                if not index_id or not full_code:
                    reasons.append("missing_index_identity")
                if full_code in seen_codes:
                    reasons.append(f"duplicate_index_code:{full_code}")
                seen_codes.add(full_code)
                candidate_indexes.append(
                    {
                        "index_guid": index_id,
                        "version_guid": version_id,
                        "proj_guid": project_id,
                        "dimension": row.get("dimension"),
                        "full_code": full_code,
                        "index_name": row.get("index_name"),
                        "parent_code": row.get("parent_code"),
                        "unit": row.get("unit"),
                        "value_repr": value_repr(row.get("index_value")),
                        "remark": row.get("remark"),
                        "sort_order": int(row.get("sort_order", 0)),
                    }
                )
            candidate = {
                "version": {
                    "version_guid": version_id,
                    "proj_guid": project_id,
                    "bu_guid": bu_id,
                    "version_name": version.get("version_name"),
                    "version_no": int(version.get("version_no", 0)),
                    "current": bool(version.get("is_current", 0)),
                    "created_by": version.get("created_by"),
                    "created_at": version.get("created_at"),
                    "remark": version.get("remark"),
                },
                "indexes": candidate_indexes,
                "principal_id": principal,
                "authority_scope": f"project:{project_id}",
            }
            items.append(
                {
                    "source_table": "tzsy_version",
                    "source_id": version_id,
                    "target_type": "investment_model",
                    "target_id": version_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "index values remain source representations; formula and accounting semantics require later approval"
                    ],
                    "target_candidate": candidate if not reasons else None,
                }
            )

        for row in indexes:
            version_id = str(row.get("version_guid", ""))
            if version_id not in version_ids:
                index_id = str(row.get("index_guid", ""))
                items.append(
                    {
                        "source_table": "tzsy_plan_index",
                        "source_id": index_id,
                        "target_type": "investment_model",
                        "target_id": version_id,
                        "disposition": "quarantined",
                        "reasons": ["stray_index_without_version"],
                        "warnings": [],
                        "target_candidate": None,
                    }
                )

        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.investment-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-investment-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"investment promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
