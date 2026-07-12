#!/usr/bin/env python3
"""Build an explicit employee-advance and loan-offset promotion plan.

The plan is separate from the first economic cohort because a source loan
balance is not permission to mutate a target advance. It requires an explicit
offset mapping and makes the target importer replay the offset against an
already-created advance under amount-bounded authority.
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


def minor_units(value: Any, policy: dict[str, Any]) -> int:
    try:
        amount = Decimal(str(value))
        scale = Decimal(str(policy.get("minor_units_per_unit", 100)))
        scaled = amount * scale
        rounded = scaled.to_integral_value(rounding=ROUND_HALF_EVEN)
    except (InvalidOperation, ValueError) as error:
        raise PlanError(f"invalid monetary value: {value!r}") from error
    if scaled != rounded and not policy.get("allow_rounding", False):
        raise PlanError(f"rounding required for monetary value: {value!r}")
    result = int(rounded)
    if result <= 0:
        raise PlanError(f"non-positive monetary value: {value!r}")
    return result


def item(
    source_table: str,
    source_id: str,
    target_type: str,
    target_id: str,
    candidate: dict[str, Any] | None,
    reasons: list[str],
    warnings: list[str] | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "source_table": source_table,
        "source_id": source_id,
        "target_type": target_type,
        "target_id": target_id,
        "disposition": "ready_for_domain_import" if not reasons else "quarantined",
        "reasons": sorted(set(reasons)),
        "warnings": warnings or [],
    }
    if candidate is not None and not reasons:
        result["target_candidate"] = candidate
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
        if not isinstance(config, dict):
            raise PlanError("mapping must be an object")
        principal_by_bu = config.get("principal_by_bu", {})
        employee_by_user = config.get("employee_by_user", {})
        currency_by_bu = config.get("currency_by_bu", {})
        offset_mappings = config.get("advance_offset_by_id", {})
        policy = config.get("money_policy", {})
        if not all(
            isinstance(value, dict)
            for value in (
                principal_by_bu,
                employee_by_user,
                currency_by_bu,
                offset_mappings,
                policy,
            )
        ):
            raise PlanError("advance-offset mapping objects are invalid")
        loans = load(args.export / "tables" / "vcb_loan_simple.json")
        offsets = load(args.export / "tables" / "cb_loan_offset.json")
        if not isinstance(loans, list) or not isinstance(offsets, list):
            raise PlanError("loan and offset exports must be arrays")

        loans_by_id = {str(row.get("loan_guid", "")): row for row in loans}
        items: list[dict[str, Any]] = []
        for row in loans:
            loan_id = str(row.get("loan_guid", ""))
            bu_id = str(row.get("bu_guid", ""))
            source_user = str(row.get("applied_by", ""))
            principal = principal_by_bu.get(bu_id)
            employee = employee_by_user.get(source_user)
            currency = currency_by_bu.get(bu_id)
            reasons: list[str] = []
            if not loan_id:
                reasons.append("missing_advance_id")
            if not principal:
                reasons.append("missing_principal_by_bu")
            if not employee:
                reasons.append("missing_employee_by_user")
            if not currency:
                reasons.append("missing_currency_by_bu")
            amount_minor: int | None = None
            if currency:
                try:
                    amount_minor = minor_units(row.get("loan_amount"), policy)
                except PlanError as error:
                    reasons.append(str(error))
            candidate = {
                "advance_id": loan_id,
                "principal_id": principal,
                "employee_id": employee,
                "business_unit_id": bu_id,
                "authority_scope": f"employee:{employee}" if employee else None,
                "amount_minor": amount_minor,
                "currency": currency,
            }
            items.append(
                item(
                    "vcb_loan_simple",
                    loan_id,
                    "employee_advance",
                    loan_id,
                    candidate,
                    reasons,
                    [
                        "source balance is replayed only through explicit offset items"
                    ],
                )
            )

        for row in offsets:
            offset_id = str(row.get("offset_guid", ""))
            loan_id = str(row.get("loan_guid", ""))
            loan = loans_by_id.get(loan_id)
            mapping = offset_mappings.get(offset_id)
            reasons: list[str] = []
            if not offset_id or not loan_id:
                reasons.append("missing_offset_or_loan_id")
            if loan is None:
                reasons.append("missing_advance")
            if not isinstance(mapping, dict):
                reasons.append("missing_advance_offset_mapping")
                mapping = {}
            bu_id = str(loan.get("bu_guid", "")) if loan else ""
            derived_principal = principal_by_bu.get(bu_id)
            derived_employee = employee_by_user.get(str(loan.get("applied_by", ""))) if loan else None
            derived_currency = currency_by_bu.get(bu_id)
            principal = mapping.get("principal_id")
            employee = mapping.get("employee_id")
            currency = mapping.get("currency")
            scope = mapping.get("scope")
            for field, value in (
                ("principal_id", principal),
                ("employee_id", employee),
                ("currency", currency),
                ("scope", scope),
            ):
                if not value:
                    reasons.append(f"missing_advance_offset_field:{field}")
            if principal != derived_principal:
                reasons.append("offset_principal_mismatch")
            if employee != derived_employee:
                reasons.append("offset_employee_mismatch")
            if currency != derived_currency:
                reasons.append("offset_currency_mismatch")
            if scope != (f"employee:{employee}" if employee else ""):
                reasons.append("offset_scope_mismatch")
            amount_minor: int | None = None
            if currency:
                try:
                    amount_minor = minor_units(row.get("offset_amount"), policy)
                except PlanError as error:
                    reasons.append(str(error))
            if loan is not None and amount_minor is not None:
                try:
                    loan_amount = minor_units(loan.get("loan_amount"), policy)
                    if amount_minor > loan_amount:
                        reasons.append("offset_exceeds_advance")
                except PlanError as error:
                    reasons.append(str(error))
            candidate = {
                "offset_id": offset_id,
                "advance_id": loan_id,
                "principal_id": principal,
                "employee_id": employee,
                "authority_scope": scope,
                "amount_minor": amount_minor,
                "currency": currency,
                "offset_date": row.get("offset_date"),
                "operator_id": row.get("operator_guid"),
                "related_expense_id": row.get("related_expense_guid"),
            }
            items.append(
                item(
                    "cb_loan_offset",
                    offset_id,
                    "employee_advance_offset",
                    offset_id,
                    candidate,
                    reasons,
                    [
                        "offset mutates only the imported advance balance; cash and accounting recognition remain separate events"
                    ],
                )
            )

        ready = sum(value["disposition"] == "ready_for_domain_import" for value in items)
        plan = {
            "format": "moonproj.erp.advance-offset-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-advance-offset-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"advance-offset promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
