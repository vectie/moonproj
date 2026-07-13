#!/usr/bin/env python3
"""Build a fail-closed plan for reviewed delivery-recognition links.

The source ERP task-report cohort is draft evidence only. A recognition plan
therefore requires a separately reviewed acceptance record, acceptance
evidence, a positive measured amount, and explicit ledger accounts. The
planner never treats progress percentage or a draft report as acceptance.
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
        raise PlanError(f"cannot read JSON: {path}") from error


def non_empty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def progress_bps(value: Any) -> int:
    try:
        parsed = Decimal(str(value))
        result = int(
            (parsed * Decimal("100")).to_integral_value(rounding=ROUND_HALF_EVEN)
        )
    except (InvalidOperation, ValueError) as error:
        raise PlanError(f"invalid progress percentage: {value!r}") from error
    if result < 0 or result > 10000:
        raise PlanError(f"progress outside 0..10000 bps: {result}")
    return result


def evidence_list(value: Any) -> bool:
    return isinstance(value, list) and bool(value) and all(non_empty(item) for item in value)


def build_plan(export: Path, mapping_path: Path) -> dict[str, Any]:
    manifest = load(export / "manifest.json")
    source_sha256 = manifest.get("source_sha256")
    if not isinstance(source_sha256, str) or len(source_sha256) != 64:
        raise PlanError("export manifest has no valid source hash")
    config = load(mapping_path)
    if not isinstance(config, dict):
        raise PlanError("mapping must be an object")
    mappings = config.get("recognition_by_report", {})
    if not isinstance(mappings, dict):
        raise PlanError("recognition_by_report must be an object")
    reports = load(export / "tables" / "jd_task_report.json")
    tasks = load(export / "tables" / "jd_task.json")
    projects = load(export / "tables" / "ep_project.json")
    if not all(isinstance(value, list) for value in (reports, tasks, projects)):
        raise PlanError("report, task, and project exports must be arrays")
    task_by_id = {
        str(row.get("task_guid", "")): row
        for row in tasks
        if isinstance(row, dict)
    }
    project_ids = {
        str(row.get("proj_guid", "")) for row in projects if isinstance(row, dict)
    }
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
        mapping = mappings.get(report_id)
        if not isinstance(mapping, dict):
            reasons.append("missing_recognition_mapping")
            mapping = {}
        task_id = str(row.get("task_guid", ""))
        task = task_by_id.get(task_id)
        if task is None:
            reasons.append("missing_task")
        source_project_id = str(task.get("proj_guid", "")) if task else ""
        project_id = mapping.get("project_id")
        if not non_empty(project_id):
            reasons.append("missing_target_project")
        elif project_id not in project_ids:
            reasons.append("unknown_target_project")
        elif source_project_id != project_id:
            reasons.append("task_project_mismatch")
        if mapping.get("review_state") != "accepted":
            reasons.append("missing_reviewed_acceptance")
        if mapping.get("amount_basis") != "reviewed_measurement":
            reasons.append("missing_reviewed_amount_basis")
        principal_id = mapping.get("principal_id")
        project_scope = mapping.get("project_scope")
        if not non_empty(principal_id) or not non_empty(project_scope):
            reasons.append("incomplete_principal_or_scope_mapping")
        currency = mapping.get("currency")
        if not non_empty(currency) or len(currency) != 3:
            reasons.append("invalid_currency_mapping")
        amount = mapping.get("completed_value_minor")
        if isinstance(amount, bool) or not isinstance(amount, int) or amount <= 0:
            reasons.append("missing_or_non_positive_completed_value")
        evidence_ids = mapping.get("evidence_ids")
        if not evidence_list(evidence_ids):
            reasons.append("missing_progress_evidence_mapping")
        acceptance_evidence_ids = mapping.get("acceptance_evidence_ids")
        if not evidence_list(acceptance_evidence_ids):
            reasons.append("missing_acceptance_evidence_mapping")
        for key in (
            "recognition_id",
            "acceptance_id",
            "accepted_by",
            "created_by",
            "contract_asset_account",
            "revenue_account",
        ):
            if not non_empty(mapping.get(key)):
                reasons.append(f"missing_{key}")
        try:
            bps = progress_bps(row.get("progress_pct"))
        except PlanError as error:
            reasons.append(str(error))
            bps = 0
        candidate = {
            "recognition_id": mapping.get("recognition_id"),
            "report_id": report_id,
            "task_id": task_id,
            "project_id": project_id,
            "principal_id": principal_id,
            "project_scope": project_scope,
            "progress_bps": bps,
            "completed_value_minor": amount,
            "amount_basis": mapping.get("amount_basis"),
            "currency": currency,
            "evidence_ids": evidence_ids,
            "acceptance_id": mapping.get("acceptance_id"),
            "acceptance_evidence_ids": acceptance_evidence_ids,
            "accepted_by": mapping.get("accepted_by"),
            "created_by": mapping.get("created_by"),
            "contract_asset_account": mapping.get("contract_asset_account"),
            "revenue_account": mapping.get("revenue_account"),
            "review_state": mapping.get("review_state"),
            "reported_on": row.get("report_date"),
            "summary": row.get("summary"),
            "source_operator_id": row.get("operator_guid"),
        }
        ready = not reasons
        items.append(
            {
                "source_table": "jd_task_report",
                "source_id": report_id,
                "target_type": "delivery_recognition",
                "target_id": mapping.get("recognition_id", "delivery-recognition:" + report_id),
                "disposition": "ready_for_domain_import" if ready else "quarantined",
                "reasons": sorted(set(reasons)),
                "warnings": [
                    "recognition requires separately reviewed acceptance evidence",
                    "native import creates a pending-posting source-to-journal link; it does not post, release cash, determine tax, or close a period",
                ],
                "target_candidate": candidate if ready else None,
            }
        )
    ready_count = sum(item["disposition"] == "ready_for_domain_import" for item in items)
    return {
        "format": "moonproj.erp.delivery-recognition-promotion-plan.v1",
        "source_snapshot_id": f"erp-snapshot:{source_sha256}",
        "source_sha256": source_sha256,
        "mapping_version": config.get(
            "mapping_version", "unversioned-delivery-recognition-map"
        ),
        "cohort": "delivery-recognition-v1",
        "summary": {
            "items": len(items),
            "ready": ready_count,
            "quarantined": len(items) - ready_count,
        },
        "items": items,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        plan = build_plan(args.export, args.mapping)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"delivery-recognition plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
