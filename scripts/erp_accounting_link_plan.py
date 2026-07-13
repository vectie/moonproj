#!/usr/bin/env python3
"""Build an explicit source-to-journal link plan from a domain receipt.

Only the allow-listed target/source domains in ``SUPPORTED_TARGET_SOURCE_TYPES``
may cross this boundary.  The planner never infers a journal or amount from
source metadata; the native candidate and reviewed mapping must agree on
principal, amount, and currency before a link can be accepted.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


SUPPORTED_TARGET_SOURCE_TYPES = {
    "commitment": None,
    "employee_advance": "employee_advance",
    "employee_advance_offset": "employee_advance_offset",
    "payment_application": "payment_application",
    "settlement": "settlement",
    "expense_claim": "expense_claim",
    "delivery_progress": "delivery_progress",
    "delivery_recognition": "delivery_progress",
    "asset_depreciation": "asset_depreciation",
    "receivable": "receivable",
    "payable": "payable",
    "tax_obligation": "tax_obligation",
    "tax_filing": "tax_filing",
    "financing_facility": "financing_facility",
    "investment_position": "investment_position",
    "investment_valuation": "investment_valuation",
    "asset_disposal": "asset_disposal",
    "cash_movement": "cash_movement",
    "bank_statement": "bank_statement",
}


def candidate_amount(candidate: dict[str, Any], target_type: str) -> Any:
    """Read only explicitly named monetary fields from a native candidate."""
    if target_type == "payment_application":
        application = candidate.get("application")
        return application.get("amount_minor") if isinstance(application, dict) else None
    for field in (
        "amount_minor",
        "tax_amount_minor",
        "reported_tax_amount_minor",
        "notional_minor",
        "actual_amount_minor",
        "completed_value_minor",
    ):
        if field in candidate:
            return candidate[field]
    return None


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError(f"JSON root is not an object: {path}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("domain_receipt", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        receipt = load(args.domain_receipt)
        config = load(args.mapping)
        if receipt.get("format") != "moonproj.erp.domain-promotion.v1":
            raise PlanError("unexpected domain receipt format")
        accepted = receipt.get("accepted_items")
        if not isinstance(accepted, list):
            raise PlanError("domain receipt has no accepted items")
        mappings = config.get("accounting_by_source", {})
        if not isinstance(mappings, dict):
            raise PlanError("accounting_by_source must be an object")

        items: list[dict[str, Any]] = []
        configured_types = config.get("target_types")
        if configured_types is None:
            target_types = set(SUPPORTED_TARGET_SOURCE_TYPES)
        elif isinstance(configured_types, list) and all(isinstance(value, str) for value in configured_types):
            target_types = set(configured_types)
            if not target_types or not target_types.issubset(SUPPORTED_TARGET_SOURCE_TYPES):
                raise PlanError("target_types contains an unsupported or empty target type")
        else:
            raise PlanError("target_types must be a non-empty string array")
        for source in accepted:
            if not isinstance(source, dict) or source.get("target_type") not in target_types:
                continue
            target_type = str(source["target_type"])
            source_table = str(source.get("source_table", ""))
            source_id = str(source.get("source_id", ""))
            key = source_table + ":" + source_id
            candidate = source.get("target_candidate")
            reasons: list[str] = []
            if not isinstance(candidate, dict):
                reasons.append("domain_receipt_missing_candidate")
                candidate = {}
            mapping = mappings.get(key)
            if not isinstance(mapping, dict):
                reasons.append("missing_accounting_mapping")
                mapping = {}
            for field in (
                "event_id",
                "event_type",
                "journal_id",
                "description",
                "debit_account",
                "credit_account",
                "principal_id",
                "scope",
                "amount_minor",
                "currency",
            ):
                if field not in mapping or mapping[field] in (None, ""):
                    reasons.append(f"missing_accounting_field:{field}")
            if mapping.get("principal_id") != candidate.get("principal_id"):
                reasons.append("accounting_principal_mismatch")
            expected_amount = candidate_amount(candidate, target_type)
            if expected_amount is None:
                reasons.append("domain_candidate_missing_amount")
            if mapping.get("amount_minor") != expected_amount:
                reasons.append("accounting_amount_mismatch")
            expected_currency = candidate.get("currency") or candidate.get("base_currency")
            if not isinstance(expected_currency, str) or not expected_currency:
                reasons.append("domain_candidate_missing_currency")
            if mapping.get("currency") != expected_currency:
                reasons.append("accounting_currency_mismatch")
            source_type = SUPPORTED_TARGET_SOURCE_TYPES[target_type] or source_table
            target_candidate = {
                "source_target_type": target_type,
                "event_id": mapping.get("event_id"),
                "principal_id": mapping.get("principal_id"),
                "source_type": source_type,
                "source_id": source_id,
                "event_type": mapping.get("event_type"),
                "scope": mapping.get("scope"),
                "journal": {
                    "entry_id": mapping.get("journal_id"),
                    "description": mapping.get("description"),
                    "debit_account": mapping.get("debit_account"),
                    "credit_account": mapping.get("credit_account"),
                    "amount_minor": mapping.get("amount_minor"),
                    "currency": mapping.get("currency"),
                },
            }
            items.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "target_type": "accounting_event_link",
                    "target_id": str(mapping.get("event_id", source_id)),
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "this link validates an explicit journal; it does not post cash or infer accounting policy"
                    ],
                    "target_candidate": target_candidate if not reasons else None,
                }
            )
        if not items:
            raise PlanError("domain receipt contains no supported accounting events to map")
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.accounting-link-plan.v1",
            "source_snapshot_id": receipt["source_snapshot_id"],
            "source_sha256": receipt["source_snapshot_id"].split(":", 1)[-1],
            "mapping_version": config.get("mapping_version", "unversioned-accounting-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"accounting-link plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
