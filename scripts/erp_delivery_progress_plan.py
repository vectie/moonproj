#!/usr/bin/env python3
"""Build a fail-closed plan for draft delivery-progress intake.

ERP task reports describe observed progress, but they do not prove delivery
acceptance or an economic amount. The mapping therefore must explicitly supply
the target project/principal/scope, evidence references, currency, and value.
The native importer creates draft progress reports only; source operator/date/
summary remain attached to the candidate as provenance.
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
        parsed = Decimal(str(value))
        result = int((parsed * Decimal("100")).to_integral_value(rounding=ROUND_HALF_EVEN))
    except (InvalidOperation, ValueError):
        raise PlanError(f"invalid progress percentage: {value!r}")
    if result < 0 or result > 10000:
        raise PlanError(f"progress outside 0..10000 bps: {result}")
    return result


def non_empty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        if not isinstance(config, dict):
            raise PlanError("mapping must be an object")
        report_mappings = config.get("report_by_id", {})
        if not isinstance(report_mappings, dict):
            raise PlanError("report_by_id must be an object")
        reports = load(args.export / "tables" / "jd_task_report.json")
        tasks = load(args.export / "tables" / "jd_task.json")
        projects = load(args.export / "tables" / "ep_project.json")
        if not isinstance(reports, list) or not isinstance(tasks, list) or not isinstance(projects, list):
            raise PlanError("report, task, and project exports must be arrays")
        task_by_id = {str(row.get("task_guid", "")): row for row in tasks if isinstance(row, dict)}
        project_ids = {str(row.get("proj_guid", "")) for row in projects if isinstance(row, dict)}

        items: list[dict[str, Any]] = []
        seen: set[str] = set()
        for row in reports:
            if not isinstance(row, dict):
                raise PlanError("task report row must be an object")
            report_id = str(row.get("report_guid", ""))
            reasons: list[str] = []
            if not report_id or report_id in seen:
                reasons.append("missing_or_duplicate_report_id")
            seen.add(report_id)
            mapping = report_mappings.get(report_id)
            if not isinstance(mapping, dict):
                reasons.append("missing_report_mapping")
                mapping = {}
            task_id = str(row.get("task_guid", ""))
            task = task_by_id.get(task_id)
            if task is None:
                reasons.append("missing_task")
            source_project_id = str(task.get("proj_guid", "")) if task is not None else ""
            project_id = mapping.get("project_id")
            if not non_empty(project_id):
                reasons.append("missing_target_project")
            elif project_id not in project_ids:
                reasons.append("unknown_target_project")
            elif source_project_id != project_id:
                reasons.append("task_project_mismatch")
            principal_id = mapping.get("principal_id")
            project_scope = mapping.get("project_scope")
            if not non_empty(principal_id) or not non_empty(project_scope):
                reasons.append("incomplete_principal_or_scope_mapping")
            currency = mapping.get("currency")
            if not non_empty(currency) or len(currency) != 3:
                reasons.append("invalid_currency_mapping")
            amount = mapping.get("completed_value_minor")
            if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
                reasons.append("missing_or_negative_completed_value")
            evidence_ids = mapping.get("evidence_ids")
            if not isinstance(evidence_ids, list) or not evidence_ids or any(
                not non_empty(value) for value in evidence_ids
            ):
                reasons.append("missing_evidence_mapping")
            actor_id = mapping.get("actor_id", "migration")
            if not non_empty(actor_id):
                reasons.append("missing_migration_actor")
            try:
                bps = progress_bps(row.get("progress_pct"))
            except PlanError as error:
                reasons.append(str(error))
                bps = 0
            candidate = {
                "report_id": report_id,
                "task_id": task_id,
                "project_id": project_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "progress_bps": bps,
                "completed_value_minor": amount,
                "currency": currency,
                "evidence_ids": evidence_ids,
                "actor_id": actor_id,
                "reported_on": row.get("report_date"),
                "summary": row.get("summary"),
                "source_operator_id": row.get("operator_guid"),
                "state_policy": "draft_only",
            }
            items.append(
                {
                    "source_table": "jd_task_report",
                    "source_id": report_id,
                    "target_type": "progress_report",
                    "target_id": report_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "native import creates Draft only; source report does not prove submission or acceptance",
                        "accounting recognition, cash, cost consumption, and task-state mutation remain separate gates",
                    ],
                    "target_candidate": candidate if not reasons else None,
                }
            )
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.delivery-progress-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-delivery-progress-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"delivery-progress promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
