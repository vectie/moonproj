#!/usr/bin/env python3
"""Produce a machine-readable ERP schema-versus-fixture migration gap plan."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class GapError(RuntimeError):
    pass


CAPABILITY_PREFIXES = (
    ("sale_", "SAL"),
    ("mkt_", "SAL"),
    ("srm_", "SRM"),
    ("tender_", "SRM"),
    ("fund_", "FIN"),
    ("bank_", "FIN"),
    ("tax_", "FIN"),
    ("invoice", "CTR/FIN"),
    ("wf_", "WF"),
    ("proj_", "PRJ"),
    ("jd_", "PRJ"),
    ("tzsy_", "INV"),
    ("sys_", "FND"),
    ("mu_", "FND"),
    ("my_", "FND"),
    ("vys_", "EXP"),
    ("vcb_", "EXP"),
    ("cb_", "CTR/CST"),
)


CAPABILITY_BY_TABLE = {
    "attachment": "FND-05",
    "cb_change_apply": "CTR-05",
    "cb_contract_milestone": "CTR-02",
    "cb_plan_version": "CST-01",
    "cb_r_master": "CST-01",
    "cb_subject_dict": "CST-01",
    "contract_split": "CTR-05",
    "fund_dispatch": "FIN-09",
    "fund_plan": "FIN-09",
    "invoice_in": "FIN-03",
    "invoice_out": "SAL-05",
    "mkt_campaign": "SAL-02",
    "mkt_channel": "SAL-02",
    "mkt_material": "SAL-02",
    "mkt_placement": "SAL-02",
    "proj_output": "PRJ-05",
    "proj_progress": "PRJ-03",
    "report_share_link": "RPT-03",
    "sale_contract": "SAL-04",
    "sale_customer": "SAL-01",
    "sale_mortgage": "SAL-06",
    "sale_refund": "SAL-03",
    "sale_revenue": "SAL-05",
    "sale_subscription": "SAL-03",
    "srm_category": "SRM-01",
    "srm_provider": "SRM-01",
    "srm_provider_bu": "SRM-01",
    "sys_email_outbox": "FND-07",
    "sys_message": "FND-07",
    "sys_param": "FND-04",
    "sys_password_history": "FND-02",
    "sys_report_template": "RPT-02",
    "sys_role": "FND-03",
    "sys_user_pref": "FND-08",
    "sys_user_role": "FND-03",
    "sys_warning": "RPT-04",
    "sys_warning_rule_custom": "RPT-04",
    "sys_warning_scan": "RPT-04",
    "sys_warning_subscription": "RPT-04",
    "sys_warning_ticket": "RPT-04",
    "tender_award": "SRM-04",
    "tender_plan": "SRM-04",
    "tzsy_excel_import": "INV-02",
    "tzsy_excel_sheet": "INV-02",
    "tzsy_plan_line": "INV-01",
    "tzsy_profit_table": "INV-04",
    "tzsy_subject_mapping": "INV-02",
    "wf_approval_rule": "WF-03",
    "wf_runtime_assignee": "WF-04",
}


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GapError(f"cannot read {path}") from error


def capability(table: str) -> str:
    for prefix, value in CAPABILITY_PREFIXES:
        if table.startswith(prefix):
            return value
    return "RPT/FND"


def capability_id(table: str) -> str:
    if table in CAPABILITY_BY_TABLE:
        return CAPABILITY_BY_TABLE[table]
    family = capability(table)
    return {
        "FND": "FND-08",
        "WF": "WF-01",
        "PRJ": "PRJ-01",
        "INV": "INV-01",
        "CST": "CST-04",
        "SRM": "SRM-01",
        "CTR/CST": "CTR-01",
        "CTR/FIN": "FIN-03",
        "FIN": "FIN-09",
        "SAL": "SAL-01",
        "EXP": "EXP-01",
        "RPT/FND": "RPT-01",
    }.get(family, "RPT-01")


def migration_action(table: str, present: bool) -> str:
    if present:
        return "reconcile_fixture"
    if table == "sys_password_history":
        return "security_review_exclude_credentials"
    return "specify_then_implement_then_import"


def run(schema_path: Path, export_manifest_path: Path, output_path: Path) -> dict[str, Any]:
    try:
        schema_text = schema_path.read_text(encoding="utf-8")
    except OSError as error:
        raise GapError(f"cannot read schema initializer: {schema_path}") from error
    schema_tables = sorted(
        set(re.findall(r"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+([A-Za-z0-9_]+)", schema_text, re.IGNORECASE))
    )
    manifest = load(export_manifest_path)
    source_tables = {
        str(item.get("table")): int(item.get("rows", 0))
        for item in manifest.get("tables", [])
        if isinstance(item, dict) and item.get("table")
    }
    if not schema_tables:
        raise GapError("schema initializer contains no CREATE TABLE definitions")
    entries = []
    for table in schema_tables:
        present = table in source_tables
        entries.append(
            {
                "table": table,
                "capability_family": capability(table),
                "capability_id": capability_id(table),
                "state": "present_in_snapshot" if present else "schema_only",
                "snapshot_rows": source_tables.get(table, 0),
                "migration_action": migration_action(table, present),
            }
        )
    report = {
        "format": "moonproj.erp.schema-gap.v1",
        "schema_path": str(schema_path),
        "export_manifest": str(export_manifest_path),
        "schema_tables": len(schema_tables),
        "present_tables": sum(entry["state"] == "present_in_snapshot" for entry in entries),
        "schema_only_tables": sum(entry["state"] == "schema_only" for entry in entries),
        "source_snapshot_id": "erp-snapshot:" + str(manifest.get("source_sha256", "")),
        "entries": entries,
        "state": "scope_gap_recorded",
        "cutover_authorized": False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path)
    parser.add_argument("export_manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = run(args.schema, args.export_manifest, args.output)
        print(json.dumps({"output": str(args.output), "schema_tables": report["schema_tables"], "present_tables": report["present_tables"], "schema_only_tables": report["schema_only_tables"], "state": report["state"]}, sort_keys=True))
        return 0
    except (OSError, GapError, TypeError, ValueError) as error:
        print(f"ERP schema gap report failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
