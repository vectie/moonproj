#!/usr/bin/env python3
"""Build an explicit source-to-journal link plan from a domain receipt."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


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
        supported_types = {
            "commitment",
            "employee_advance",
            "employee_advance_offset",
            "payment_application",
        }
        configured_types = config.get("target_types")
        if configured_types is None:
            target_types = supported_types
        elif isinstance(configured_types, list) and all(isinstance(value, str) for value in configured_types):
            target_types = set(configured_types)
            if not target_types or not target_types.issubset(supported_types):
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
            expected_amount = candidate.get("amount_minor")
            if target_type == "payment_application":
                application = candidate.get("application")
                expected_amount = application.get("amount_minor") if isinstance(application, dict) else None
            if mapping.get("amount_minor") != expected_amount:
                reasons.append("accounting_amount_mismatch")
            expected_currency = candidate.get("currency")
            if mapping.get("currency") != expected_currency:
                reasons.append("accounting_currency_mismatch")
            source_type = {
                "commitment": source_table,
                "employee_advance": "employee_advance",
                "employee_advance_offset": "employee_advance_offset",
                "payment_application": "payment_application",
            }[target_type]
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
