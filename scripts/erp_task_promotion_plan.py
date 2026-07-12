#!/usr/bin/env python3
"""Build a project/task-structure promotion plan from the safe ERP export.

Task status and progress are intentionally retained in the typed source
envelope.  This plan promotes only the dependency-checked task structure; a
separate state replay must pass the target dependency invariant.
"""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error


def progress_bps(value: Any) -> int:
    try:
        parsed = Decimal(str(value if value is not None else 0))
        result = int(
            (parsed * Decimal("100")).to_integral_value(rounding=ROUND_HALF_EVEN)
        )
    except (InvalidOperation, ValueError):
        raise PlanError(f"invalid task progress: {value!r}")
    if result < 0 or result > 10000:
        raise PlanError(f"task progress outside 0..10000 bps: {result}")
    return result


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
        projects = load(args.export / "tables" / "ep_project.json")
        tasks = load(args.export / "tables" / "jd_task.json")
        if not isinstance(projects, list) or not isinstance(tasks, list):
            raise PlanError("project/task exports must be arrays")

        project_items: list[dict[str, Any]] = []
        task_items: list[dict[str, Any]] = []
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
                    }
                    if not reasons
                    else None,
                }
            )

            project_tasks = [
                row for row in tasks if str(row.get("proj_guid", "")) == project_id
            ]
            project_tasks.sort(
                key=lambda row: (int(row.get("sort_order", 0)), str(row.get("task_guid", "")))
            )
            task_reasons: list[str] = []
            if not principal:
                task_reasons.append("missing_principal_by_bu")
            if not project_tasks:
                task_reasons.append("missing_tasks")
            seen_ids: set[str] = set()
            candidate_rows: list[dict[str, Any]] = []
            for row in project_tasks:
                task_id = str(row.get("task_guid", ""))
                if not task_id or task_id in seen_ids:
                    task_reasons.append(f"duplicate_task_id:{task_id}")
                seen_ids.add(task_id)
                parent = row.get("parent_task_guid")
                parent_id = None if parent in (None, "") else str(parent)
                candidate_rows.append(
                    {
                        "task_guid": task_id,
                        "proj_guid": project_id,
                        "bu_guid": str(row.get("bu_guid", "")),
                        "parent_task_guid": parent_id,
                        "task_code": row.get("task_code"),
                        "task_name": row.get("task_name"),
                        "task_type": row.get("task_type"),
                        "plan_begin_date": row.get("plan_begin_date"),
                        "plan_end_date": row.get("plan_end_date"),
                        "actual_begin_date": row.get("actual_begin_date"),
                        "actual_end_date": row.get("actual_end_date"),
                        "progress_bps": progress_bps(row.get("progress_pct", 0.0)),
                        "owner_guid": row.get("owner_guid"),
                        "status": row.get("status"),
                        "sort_order": int(row.get("sort_order", 0)),
                    }
                )
            for row in candidate_rows:
                parent_id = row["parent_task_guid"]
                if parent_id is not None and parent_id not in seen_ids:
                    task_reasons.append(f"missing_parent_task:{parent_id}")
            task_items.append(
                {
                    "source_table": "jd_task",
                    "source_id": project_id,
                    "target_type": "project_task_plan",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import"
                    if not task_reasons
                    else "quarantined",
                    "reasons": sorted(set(task_reasons)),
                    "warnings": [
                        "source status/progress remains in the typed envelope; only structure is promoted"
                    ],
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "rows": candidate_rows,
                    }
                    if not task_reasons
                    else None,
                }
            )

        items = project_items + task_items
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.task-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-task-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"task promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
