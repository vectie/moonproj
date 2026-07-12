#!/usr/bin/env python3
"""Build a project/lifecycle promotion plan from the safe ERP export."""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


def progress_bps(value: Any) -> int:
    try:
        parsed = Decimal(str(value if value is not None else 0))
        result = int((parsed * Decimal("100")).to_integral_value(rounding=ROUND_HALF_EVEN))
    except (InvalidOperation, ValueError):
        raise PlanError(f"invalid lifecycle progress: {value!r}")
    if result < 0 or result > 10000:
        raise PlanError(f"lifecycle progress outside 0..10000 bps: {result}")
    return result


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
        stage_map = config.get("lifecycle_stage_by_code", {})
        if not isinstance(principal_by_bu, dict) or not isinstance(stage_map, dict):
            raise PlanError("principal_by_bu and lifecycle_stage_by_code must be objects")
        projects = load(args.export / "tables" / "ep_project.json")
        instances = load(args.export / "tables" / "proj_lifecycle_instance.json")
        if not isinstance(projects, list) or not isinstance(instances, list):
            raise PlanError("project/lifecycle exports must be arrays")
        project_items: list[dict[str, Any]] = []
        lifecycle_items: list[dict[str, Any]] = []
        for project in projects:
            project_id = str(project.get("proj_guid", ""))
            bu_id = str(project.get("bu_guid", ""))
            principal = principal_by_bu.get(bu_id)
            reasons = [] if principal else ["missing_principal_by_bu"]
            project_items.append(
                {
                    "source_table": "ep_project",
                    "source_id": project_id,
                    "target_type": "project",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": reasons,
                    "warnings": [],
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "code": project.get("proj_code"),
                        "name": project.get("proj_name"),
                        "business_unit_id": bu_id,
                    } if not reasons else None,
                }
            )
            project_rows = [row for row in instances if row.get("proj_guid") == project_id]
            project_rows.sort(key=lambda row: int(row.get("instance_id", 0)))
            lifecycle_reasons: list[str] = []
            if not principal:
                lifecycle_reasons.append("missing_principal_by_bu")
            candidate_rows: list[dict[str, Any]] = []
            for row in project_rows:
                source_code = str(row.get("stage_code", ""))
                if source_code not in stage_map:
                    lifecycle_reasons.append(f"missing_stage_mapping:{source_code}")
                candidate_rows.append(
                    {
                        "instance_id": str(row.get("instance_id", "")),
                        "proj_guid": project_id,
                        "stage_code": source_code,
                        "planned_start": row.get("planned_start"),
                        "planned_end": row.get("planned_end"),
                        "actual_start": row.get("actual_start"),
                        "actual_end": row.get("actual_end"),
                        "status": row.get("status"),
                        "progress_bps": progress_bps(row.get("progress_pct", 0.0)),
                    }
                )
            if not project_rows:
                lifecycle_reasons.append("missing_lifecycle_instances")
            lifecycle_items.append(
                {
                    "source_table": "proj_lifecycle_instance",
                    "source_id": project_id,
                    "target_type": "project_lifecycle",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import" if not lifecycle_reasons else "quarantined",
                    "reasons": lifecycle_reasons,
                    "warnings": [],
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "rows": candidate_rows,
                        "stage_mappings": [
                            {"source_code": source, "target_stage": target}
                            for source, target in stage_map.items()
                        ],
                    } if not lifecycle_reasons and principal else None,
                }
            )
        items = project_items + lifecycle_items
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.lifecycle-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-lifecycle-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError) as error:
        print(f"lifecycle promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
