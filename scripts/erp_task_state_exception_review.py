#!/usr/bin/env python3
"""Create a fail-closed review artifact for quarantined task-state rows."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class ReviewError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReviewError(f"cannot read {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        plan = load(args.plan)
        if not isinstance(plan, dict) or plan.get("format") != "moonproj.erp.task-state-promotion-plan.v1":
            raise ReviewError("unexpected task-state plan format")
        items = plan.get("items")
        if not isinstance(items, list):
            raise ReviewError("task-state plan items must be an array")
        exceptions: list[dict[str, Any]] = []
        for item in items:
            if not isinstance(item, dict):
                raise ReviewError("task-state item must be an object")
            if item.get("target_type") != "project_task_state" or item.get("disposition") != "quarantined":
                continue
            candidate = item.get("target_candidate")
            rows = item.get("observed_rows")
            if not isinstance(rows, list):
                rows = candidate.get("rows", []) if isinstance(candidate, dict) else []
            conflicts = []
            for reason in item.get("reasons", []):
                if isinstance(reason, str) and reason.startswith("dependency_not_completed:"):
                    parts = reason.split(":", 2)
                    conflicts.append(
                        {
                            "task_id": parts[1] if len(parts) > 1 else "",
                            "parent_task_id": parts[2] if len(parts) > 2 else "",
                            "reason": reason,
                        }
                    )
            exceptions.append(
                {
                    "project_id": item.get("target_id"),
                    "source_id": item.get("source_id"),
                    "reasons": item.get("reasons", []),
                    "dependency_conflicts": conflicts,
                    "observed_rows": rows,
                    "decision": None,
                    "decision_owner": None,
                    "decision_at": None,
                    "decision_notes": None,
                }
            )
        if not exceptions:
            raise ReviewError("task-state plan contains no quarantined exceptions")
        report = {
            "format": "moonproj.erp.task-state-exception-review.v1",
            "source_snapshot_id": plan.get("source_snapshot_id"),
            "mapping_version": plan.get("mapping_version"),
            "state": "review_required",
            "cutover_authorized": False,
            "allowed_decisions": [
                "retain_source_evidence",
                "approve_dependency_repair",
                "map_state_as_observed_only",
                "exclude_from_target",
            ],
            "exceptions": exceptions,
            "warning": "No decision is inferred; target task state remains unchanged until a named owner approves one decision per exception.",
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "exceptions": len(exceptions), "state": report["state"]}, sort_keys=True))
    except (OSError, ReviewError, TypeError, ValueError, KeyError) as error:
        print(f"task-state exception review failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
