#!/usr/bin/env python3
"""Plan task-state replay only when ERP dependencies satisfy target rules."""

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


def task_row(row: dict[str, Any], project_id: str) -> dict[str, Any]:
    return {
        "task_guid": str(row.get("task_guid", "")),
        "proj_guid": project_id,
        "bu_guid": str(row.get("bu_guid", "")),
        "parent_task_guid": row.get("parent_task_guid"),
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--project-id", default=None)
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
        if args.project_id is not None:
            projects = [
                project
                for project in projects
                if str(project.get("proj_guid", "")) == args.project_id
            ]
            if not projects:
                raise PlanError(f"project not found: {args.project_id}")

        project_items: list[dict[str, Any]] = []
        structure_items: list[dict[str, Any]] = []
        state_items: list[dict[str, Any]] = []
        for project in projects:
            project_id = str(project.get("proj_guid", ""))
            bu_id = str(project.get("bu_guid", ""))
            principal = principal_by_bu.get(bu_id)
            project_reasons = [] if principal else ["missing_principal_by_bu"]
            project_items.append(
                {
                    "source_table": "ep_project",
                    "source_id": project_id,
                    "target_type": "project",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import"
                    if not project_reasons
                    else "quarantined",
                    "reasons": project_reasons,
                    "warnings": [],
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "code": project.get("proj_code"),
                        "name": project.get("proj_name"),
                        "business_unit_id": bu_id,
                    }
                    if not project_reasons
                    else None,
                }
            )
            rows = [row for row in tasks if str(row.get("proj_guid", "")) == project_id]
            rows.sort(key=lambda row: (int(row.get("sort_order", 0)), str(row.get("task_guid", ""))))
            candidate_rows = [task_row(row, project_id) for row in rows]
            structure_reasons = list(project_reasons)
            if not rows:
                structure_reasons.append("missing_tasks")
            ids = {row["task_guid"] for row in candidate_rows}
            for row in candidate_rows:
                parent = row["parent_task_guid"]
                if parent not in (None, "") and parent not in ids:
                    structure_reasons.append(f"missing_parent_task:{parent}")
            structure_items.append(
                {
                    "source_table": "jd_task",
                    "source_id": project_id,
                    "target_type": "project_task_plan",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import"
                    if not structure_reasons
                    else "quarantined",
                    "reasons": sorted(set(structure_reasons)),
                    "warnings": [
                        "task state is replayed by a separate dependency gate"
                    ],
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "rows": candidate_rows,
                    }
                    if not structure_reasons
                    else None,
                }
            )

            state_reasons = list(project_reasons)
            completed: set[str] = set()
            seen: set[str] = set()
            for row in candidate_rows:
                task_id = row["task_guid"]
                if task_id in seen or not task_id:
                    state_reasons.append(f"duplicate_or_missing_task:{task_id}")
                seen.add(task_id)
                parent = row["parent_task_guid"]
                if parent not in (None, "") and parent not in ids:
                    state_reasons.append(f"missing_parent_task:{parent}")
                status = row["status"]
                progress = row["progress_bps"]
                if status == "pending":
                    if progress != 0:
                        state_reasons.append(f"pending_task_has_progress:{task_id}")
                elif status in {"in_progress", "done", "blocked"}:
                    if parent not in (None, "") and parent not in completed:
                        state_reasons.append(
                            f"dependency_not_completed:{task_id}:{parent}"
                        )
                    if status == "done":
                        if progress != 10000:
                            state_reasons.append(f"done_task_not_complete:{task_id}")
                        else:
                            completed.add(task_id)
                    elif status == "in_progress":
                        if progress >= 10000:
                            state_reasons.append(f"in_progress_task_complete:{task_id}")
                    elif status == "blocked" and progress >= 10000:
                        state_reasons.append(f"blocked_task_complete:{task_id}")
                else:
                    state_reasons.append(f"invalid_task_status:{task_id}:{status}")
            state_items.append(
                {
                    "source_table": "jd_task",
                    "source_id": f"state:{project_id}",
                    "target_type": "project_task_state",
                    "target_id": project_id,
                    "disposition": "ready_for_domain_import"
                    if not state_reasons
                    else "quarantined",
                    "reasons": sorted(set(state_reasons)),
                    "warnings": [
                        "state replay is accepted only when dependencies are completed in target order"
                    ],
                    "observed_rows": candidate_rows,
                    "target_candidate": {
                        "project_id": project_id,
                        "principal_id": principal,
                        "authority_scope": f"project:{project_id}",
                        "rows": candidate_rows,
                    }
                    if not state_reasons
                    else None,
                }
            )

        items = project_items + structure_items + state_items
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.task-state-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-task-state-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"task-state promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
