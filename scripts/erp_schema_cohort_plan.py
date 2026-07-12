#!/usr/bin/env python3
"""Compile the 49 schema-only ERP tables into ordered migration cohorts.

The artifact is a planning and scope-control contract. It contains table
definitions, declared references, capability IDs, wave ownership, and explicit
security actions; it does not import absent rows or authorize a cutover.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class CohortError(RuntimeError):
    pass


WAVE_ORDER = [
    "foundation-security",
    "workflow-control",
    "cost-investment",
    "procurement-contract",
    "sales-receivables",
    "delivery-treasury",
    "reporting-notification",
]

TABLE_WAVE = {
    "attachment": "foundation-security",
    "sys_role": "foundation-security",
    "sys_user_role": "foundation-security",
    "sys_password_history": "foundation-security",
    "sys_user_pref": "foundation-security",
    "sys_param": "foundation-security",
    "wf_approval_rule": "workflow-control",
    "wf_runtime_assignee": "workflow-control",
    "sys_warning": "workflow-control",
    "sys_warning_scan": "workflow-control",
    "sys_warning_subscription": "workflow-control",
    "sys_warning_rule_custom": "workflow-control",
    "sys_warning_ticket": "workflow-control",
    "cb_r_master": "cost-investment",
    "cb_subject_dict": "cost-investment",
    "cb_plan_version": "cost-investment",
    "tzsy_excel_import": "cost-investment",
    "tzsy_excel_sheet": "cost-investment",
    "tzsy_profit_table": "cost-investment",
    "tzsy_plan_line": "cost-investment",
    "tzsy_subject_mapping": "cost-investment",
    "cb_change_apply": "cost-investment",
    "cb_contract_milestone": "procurement-contract",
    "contract_split": "procurement-contract",
    "tender_plan": "procurement-contract",
    "tender_award": "procurement-contract",
    "srm_provider": "procurement-contract",
    "srm_provider_bu": "procurement-contract",
    "srm_category": "procurement-contract",
    "sale_customer": "sales-receivables",
    "sale_subscription": "sales-receivables",
    "sale_contract": "sales-receivables",
    "sale_mortgage": "sales-receivables",
    "sale_refund": "sales-receivables",
    "sale_revenue": "sales-receivables",
    "invoice_in": "sales-receivables",
    "invoice_out": "sales-receivables",
    "proj_progress": "delivery-treasury",
    "proj_output": "delivery-treasury",
    "fund_plan": "delivery-treasury",
    "fund_dispatch": "delivery-treasury",
    "mkt_campaign": "delivery-treasury",
    "mkt_placement": "delivery-treasury",
    "mkt_channel": "delivery-treasury",
    "mkt_material": "delivery-treasury",
    "sys_message": "reporting-notification",
    "sys_email_outbox": "reporting-notification",
    "sys_report_template": "reporting-notification",
    "report_share_link": "reporting-notification",
}

SPECIAL_ACTION = {
    "sys_password_history": "security_review_exclude_credentials",
    "report_share_link": "security_review_redact_tokens",
    "attachment": "content_hash_and_retention_review",
    "sys_email_outbox": "redact_network_and_message_secrets",
}

WAVE_DEPENDENCIES = {
    "foundation-security": [],
    "workflow-control": ["foundation-security"],
    "cost-investment": ["foundation-security"],
    "procurement-contract": ["foundation-security", "cost-investment"],
    "sales-receivables": ["foundation-security", "workflow-control", "procurement-contract"],
    "delivery-treasury": ["foundation-security", "workflow-control", "cost-investment", "procurement-contract"],
    "reporting-notification": ["foundation-security", "workflow-control"],
}


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CohortError(f"cannot read {path}") from error


def schema_statements(text: str) -> dict[str, str]:
    matches = re.finditer(
        r"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+([A-Za-z0-9_]+)\s*\((.*?)\);",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    return {match.group(1): match.group(2) for match in matches}


def references(body: str) -> list[str]:
    return sorted(
        set(
            match.group(1)
            for match in re.finditer(r"REFERENCES\s+([A-Za-z0-9_]+)", body, re.IGNORECASE)
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path)
    parser.add_argument("schema_gap", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        text = args.schema.read_text(encoding="utf-8")
        statements = schema_statements(text)
        gap = load(args.schema_gap)
        entries = gap.get("entries")
        if not isinstance(entries, list):
            raise CohortError("schema gap entries must be an array")
        schema_only = [
            entry for entry in entries
            if isinstance(entry, dict) and entry.get("state") == "schema_only"
        ]
        missing = sorted(set(entry.get("table") for entry in schema_only) - set(TABLE_WAVE))
        if missing:
            raise CohortError("schema-only tables lack an assigned wave: " + ",".join(missing))
        table_set = {entry.get("table") for entry in schema_only}
        cohort_entries: list[dict[str, Any]] = []
        for entry in sorted(schema_only, key=lambda item: (WAVE_ORDER.index(TABLE_WAVE[item["table"]]), item["table"])):
            table = str(entry["table"])
            declared = [ref for ref in references(statements.get(table, "")) if ref in table_set]
            action = SPECIAL_ACTION.get(table, "specify_then_implement_then_import")
            cohort_entries.append(
                {
                    "table": table,
                    "capability_id": entry.get("capability_id"),
                    "wave": TABLE_WAVE[table],
                    "state": "schema_only",
                    "snapshot_rows": entry.get("snapshot_rows", 0),
                    "declared_schema_dependencies": declared,
                    "migration_action": action,
                    "cutover_authorized": False,
                }
            )
        waves = []
        for wave in WAVE_ORDER:
            tables = [item for item in cohort_entries if item["wave"] == wave]
            if not tables:
                continue
            dependencies = sorted(
                set(WAVE_DEPENDENCIES[wave])
                | {
                    TABLE_WAVE[dependency]
                    for item in tables
                    for dependency in item["declared_schema_dependencies"]
                    if dependency in TABLE_WAVE and TABLE_WAVE[dependency] != wave
                },
                key=WAVE_ORDER.index,
            )
            waves.append(
                {
                    "wave": wave,
                    "sequence": WAVE_ORDER.index(wave) + 1,
                    "tables": [item["table"] for item in tables],
                    "depends_on_waves": dependencies,
                    "requires": [
                        "credential-safe export",
                        "row-level relationship audit",
                        "explicit principal/identity mappings",
                        "domain importer and exact parity/replay evidence",
                    ],
                }
            )
        report = {
            "format": "moonproj.erp.schema-cohort-plan.v1",
            "schema_gap_format": gap.get("format"),
            "schema_tables": gap.get("schema_tables"),
            "present_tables": gap.get("present_tables"),
            "schema_only_tables": len(cohort_entries),
            "state": "schema_cohorts_planned",
            "cutover_authorized": False,
            "waves": waves,
            "entries": cohort_entries,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "schema_only_tables": len(cohort_entries), "waves": len(waves), "state": report["state"]}, sort_keys=True))
    except (OSError, CohortError, TypeError, ValueError, KeyError) as error:
        print(f"ERP schema cohort plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
