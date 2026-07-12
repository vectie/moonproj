#!/usr/bin/env python3
"""Audit known ERP relationships in a read-only SQLite snapshot.

The source initializer does not declare foreign keys, so migration cannot rely
on SQLite's constraint checker. This report makes the reviewed relationship
map executable and records orphaned references before any target promotion.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any


class RelationshipError(RuntimeError):
    pass


# These are semantic relationships reviewed from the ERP routes, schema names,
# and the available fixture. Nullable/empty values are intentionally ignored.
RELATIONSHIPS: tuple[tuple[str, str, str, str], ...] = (
    ("audit_log", "user_id", "sys_user", "user_id"),
    ("cb_contract", "bu_guid", "mu_business_unit", "bu_guid"),
    ("cb_contract", "proj_guid", "ep_project", "proj_guid"),
    ("cb_cost", "proj_guid", "ep_project", "proj_guid"),
    ("cb_cost", "bu_guid", "mu_business_unit", "bu_guid"),
    ("cb_cost", "parent_cost_guid", "cb_cost", "cost_guid"),
    ("cb_htfk_apply", "contract_guid", "cb_contract", "contract_guid"),
    ("cb_htfk_apply", "htfk_plan_guid", "cb_htfkplan", "htfk_plan_guid"),
    ("cb_htfk_apply", "apply_dept_guid", "mu_business_unit", "bu_guid"),
    ("cb_htfk_apply", "applied_by", "sys_user", "user_id"),
    ("cb_htfk_apply", "proj_guid", "ep_project", "proj_guid"),
    ("cb_htfk_apply", "bu_guid", "mu_business_unit", "bu_guid"),
    ("cb_htfk_apply", "process_instance_guid", "wf_process_instance", "process_instance_guid"),
    ("cb_htfkplan", "contract_guid", "cb_contract", "contract_guid"),
    ("cb_htfkplan", "bu_guid", "mu_business_unit", "bu_guid"),
    ("cb_htfkplan", "jbr_guid", "sys_user", "user_id"),
    ("cb_loan_offset", "loan_guid", "vcb_loan_simple", "loan_guid"),
    ("cb_loan_offset", "related_expense_guid", "vcb_expense", "expense_guid"),
    ("cb_loan_offset", "operator_guid", "sys_user", "user_id"),
    ("ep_project", "bu_guid", "mu_business_unit", "bu_guid"),
    ("jd_task", "proj_guid", "ep_project", "proj_guid"),
    ("jd_task", "bu_guid", "mu_business_unit", "bu_guid"),
    ("jd_task", "parent_task_guid", "jd_task", "task_guid"),
    ("jd_task", "owner_guid", "sys_user", "user_id"),
    ("jd_task_report", "task_guid", "jd_task", "task_guid"),
    ("jd_task_report", "operator_guid", "sys_user", "user_id"),
    ("mu_business_unit", "parent_guid", "mu_business_unit", "bu_guid"),
    ("proj_lifecycle_instance", "proj_guid", "ep_project", "proj_guid"),
    ("proj_lifecycle_instance", "stage_code", "proj_lifecycle_stage", "stage_code"),
    ("sys_user", "bu_guid", "mu_business_unit", "bu_guid"),
    ("sys_user", "dept_guid", "mu_business_unit", "bu_guid"),
    ("tzsy_plan_index", "version_guid", "tzsy_version", "version_guid"),
    ("tzsy_plan_index", "proj_guid", "ep_project", "proj_guid"),
    ("tzsy_version", "proj_guid", "ep_project", "proj_guid"),
    ("tzsy_version", "bu_guid", "mu_business_unit", "bu_guid"),
    ("tzsy_version", "created_by", "sys_user", "user_id"),
    ("vcb_expense", "apply_dept_guid", "mu_business_unit", "bu_guid"),
    ("vcb_expense", "applied_by", "sys_user", "user_id"),
    ("vcb_expense", "bu_guid", "mu_business_unit", "bu_guid"),
    ("vcb_expense", "process_instance_guid", "wf_process_instance", "process_instance_guid"),
    ("vcb_loan_simple", "apply_dept_guid", "mu_business_unit", "bu_guid"),
    ("vcb_loan_simple", "applied_by", "sys_user", "user_id"),
    ("vcb_loan_simple", "bu_guid", "mu_business_unit", "bu_guid"),
    ("vcb_loan_simple", "proj_guid", "ep_project", "proj_guid"),
    ("vcb_loan_simple", "process_instance_guid", "wf_process_instance", "process_instance_guid"),
    ("wf_process_def", "bu_guid", "mu_business_unit", "bu_guid"),
    ("wf_process_instance", "process_guid", "wf_process_def", "process_guid"),
    ("wf_process_instance", "initiator_guid", "sys_user", "user_id"),
    ("wf_process_instance", "bu_guid", "mu_business_unit", "bu_guid"),
    ("wf_step_action", "process_instance_guid", "wf_process_instance", "process_instance_guid"),
    ("wf_step_action", "step_guid", "wf_step_def", "step_guid"),
    ("wf_step_action", "assignee_user_guid", "sys_user", "user_id"),
    ("wf_step_assignee", "step_guid", "wf_step_def", "step_guid"),
    ("wf_step_assignee", "assignee_user_guid", "sys_user", "user_id"),
    ("wf_step_def", "process_guid", "wf_process_def", "process_guid"),
    ("cb_expense_detail", "expense_guid", "vcb_expense", "expense_guid"),
    ("cb_expense_split", "expense_guid", "vcb_expense", "expense_guid"),
    ("cb_expense_split", "user_guid", "sys_user", "user_id"),
    ("cb_expense_split", "dept_guid", "mu_business_unit", "bu_guid"),
    ("cb_expense_split", "proceeding_guid", "vys_proceeding", "proceeding_guid"),
)


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RelationshipError(f"cannot read export manifest: {path}") from error
    if not isinstance(value, dict) or not isinstance(value.get("source_sha256"), str):
        raise RelationshipError("export manifest has no source_sha256")
    return value


def quote(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def schema_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {str(row[1]) for row in connection.execute(f"PRAGMA table_info({quote(table)})")}


def run(database: Path, manifest_path: Path, output: Path) -> dict[str, Any]:
    manifest = load_manifest(manifest_path)
    connection = sqlite3.connect(database)
    try:
        table_names = {
            str(row[0])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        reports: list[dict[str, Any]] = []
        orphan_count = 0
        reference_count = 0
        for source_table, source_column, target_table, target_column in RELATIONSHIPS:
            if source_table not in table_names or target_table not in table_names:
                raise RelationshipError(
                    f"relationship table missing: {source_table}->{target_table}"
                )
            if source_column not in schema_columns(connection, source_table):
                raise RelationshipError(f"relationship source column missing: {source_table}.{source_column}")
            if target_column not in schema_columns(connection, target_table):
                raise RelationshipError(f"relationship target column missing: {target_table}.{target_column}")
            source_ref = f"CAST(s.{quote(source_column)} AS TEXT)"
            target_ref = f"CAST(t.{quote(target_column)} AS TEXT)"
            nonempty = (
                f"s.{quote(source_column)} IS NOT NULL AND "
                f"TRIM({source_ref}) <> ''"
            )
            reference_count += int(
                connection.execute(
                    f"SELECT count(*) FROM {quote(source_table)} s WHERE {nonempty}"
                ).fetchone()[0]
            )
            rows = connection.execute(
                f"SELECT DISTINCT {source_ref} FROM {quote(source_table)} s "
                f"LEFT JOIN {quote(target_table)} t ON {target_ref} = {source_ref} "
                f"WHERE {nonempty} AND t.{quote(target_column)} IS NULL "
                "ORDER BY 1"
            ).fetchall()
            orphans = [str(row[0]) for row in rows]
            orphan_count += len(orphans)
            reports.append(
                {
                    "source_table": source_table,
                    "source_column": source_column,
                    "target_table": target_table,
                    "target_column": target_column,
                    "references_checked": int(
                        connection.execute(
                            f"SELECT count(*) FROM {quote(source_table)} s WHERE {nonempty}"
                        ).fetchone()[0]
                    ),
                    "orphan_values": orphans,
                    "state": "ok" if not orphans else "orphaned",
                }
            )
    finally:
        connection.close()

    report = {
        "format": "moonproj.erp.relationship-audit.v1",
        "database": str(database),
        "export_manifest": str(manifest_path),
        "source_snapshot_id": "erp-snapshot:" + manifest["source_sha256"],
        "relationship_count": len(RELATIONSHIPS),
        "reference_count": reference_count,
        "orphan_count": orphan_count,
        "relationships": reports,
        "state": "relationship_integrity_verified" if orphan_count == 0 else "orphaned_references_found",
        "cutover_authorized": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("export_manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = run(args.database, args.export_manifest, args.output)
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "relationship_count": report["relationship_count"],
                    "reference_count": report["reference_count"],
                    "orphan_count": report["orphan_count"],
                    "state": report["state"],
                },
                sort_keys=True,
            )
        )
        return 0 if report["orphan_count"] == 0 else 1
    except (OSError, RelationshipError, sqlite3.Error) as error:
        print(f"ERP relationship audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
