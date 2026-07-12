#!/usr/bin/env python3
"""Build an explicit promotion plan for the first ERP cohort.

This tool reads only the credential-safe export produced by
erp_snapshot_export.sh. It does not write target aggregates. Every item is
either `ready_for_domain_import` (after explicit mappings and money policy) or
`quarantined` with reasons that a migration owner must resolve.
"""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path
from typing import Any


MAPPED_TABLES = (
    "mu_business_unit",
    "ep_project",
    "cb_contract",
    "cb_cost",
    "vcb_loan_simple",
)
PRIMARY_KEYS = {
    "mu_business_unit": "bu_guid",
    "ep_project": "proj_guid",
    "cb_contract": "contract_guid",
    "cb_cost": "cost_guid",
    "vcb_loan_simple": "loan_guid",
}


class PlanError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read JSON: {path}") from error


def load_export(export_dir: Path) -> tuple[dict[str, Any], dict[str, list[dict[str, Any]]]]:
    manifest_path = export_dir / "manifest.json"
    manifest = load_json(manifest_path)
    source_hash = manifest.get("source_sha256")
    if not isinstance(source_hash, str) or len(source_hash) != 64:
        raise PlanError("export manifest has no valid source hash")
    tables: dict[str, list[dict[str, Any]]] = {}
    for table in MAPPED_TABLES:
        path = export_dir / "tables" / f"{table}.json"
        rows = load_json(path)
        if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
            raise PlanError(f"export table is not an object array: {table}")
        tables[table] = rows
    return manifest, tables


def mapping(config: dict[str, Any], key: str) -> dict[str, str]:
    value = config.get(key, {})
    if not isinstance(value, dict):
        raise PlanError(f"mapping {key} must be an object")
    return {str(k): str(v) for k, v in value.items()}


def money_minor(value: Any, currency: str, money_policy: dict[str, Any]) -> int:
    if not currency or len(currency) != 3:
        raise PlanError(f"invalid currency for amount {value!r}: {currency!r}")
    try:
        decimal = Decimal(str(value))
    except InvalidOperation as error:
        raise PlanError(f"invalid monetary value: {value!r}") from error
    scale = int(money_policy.get("minor_units_per_unit", 100))
    if scale <= 0:
        raise PlanError("minor_units_per_unit must be positive")
    scaled = decimal * scale
    rounding = money_policy.get("rounding", "half_even")
    if rounding != "half_even":
        raise PlanError("only half_even rounding is supported by this plan tool")
    rounded = scaled.quantize(Decimal("1"), rounding=ROUND_HALF_EVEN)
    if rounded != scaled and not bool(money_policy.get("allow_rounding", False)):
        raise PlanError(f"amount requires rounding under the declared policy: {value!r}")
    if rounded < 0:
        raise PlanError(f"negative monetary value: {value!r}")
    return int(rounded)


def item(
    table: str,
    source_id: str,
    target_type: str,
    target_id: str,
    transformed: dict[str, Any] | None,
    reasons: list[str],
    warnings: list[str] | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "source_table": table,
        "source_id": source_id,
        "target_type": target_type,
        "target_id": target_id,
        "disposition": "ready_for_domain_import" if not reasons else "quarantined",
        "reasons": reasons,
        "warnings": warnings or [],
    }
    if transformed is not None and not reasons:
        result["target_candidate"] = transformed
    return result


def build_plan(manifest: dict[str, Any], tables: dict[str, list[dict[str, Any]]], config: dict[str, Any]) -> dict[str, Any]:
    principal_by_bu = mapping(config, "principal_by_bu")
    counterparty_by_provider = mapping(config, "counterparty_by_provider")
    employee_by_user = mapping(config, "employee_by_user")
    currency_by_bu = mapping(config, "currency_by_bu")
    money_policy = config.get("money_policy", {})
    if not isinstance(money_policy, dict):
        raise PlanError("money_policy must be an object")
    cost_map = config.get("cost_component_map", {})
    if not isinstance(cost_map, dict):
        raise PlanError("cost_component_map must be an object")
    required_cost_fields = ("direct", "indirect", "contingency", "other")
    if any(field not in cost_map for field in required_cost_fields):
        raise PlanError("cost_component_map must name direct/indirect/contingency/other")

    rows_out: list[dict[str, Any]] = []

    bu_ids = {row["bu_guid"] for row in tables["mu_business_unit"]}
    for row in tables["mu_business_unit"]:
        bu_id = str(row.get("bu_guid", ""))
        principal = principal_by_bu.get(bu_id)
        reasons: list[str] = []
        if not principal:
            reasons.append("missing_principal_by_bu")
        parent = row.get("parent_guid")
        if parent and parent not in bu_ids:
            reasons.append("missing_parent_business_unit")
        candidate = {
            "unit_id": bu_id,
            "principal_id": principal,
            "authority_scope": f"organization:{bu_id}",
            "parent_id": parent,
            "code": row.get("bu_code"),
            "name": row.get("bu_name"),
            "kind": str(row.get("bu_type", "")).lower(),
        } if principal else None
        rows_out.append(item("mu_business_unit", bu_id, "organization_unit", bu_id, candidate, reasons))

    project_ids = {row["proj_guid"] for row in tables["ep_project"]}
    for row in tables["ep_project"]:
        project_id = str(row.get("proj_guid", ""))
        bu_id = str(row.get("bu_guid", ""))
        principal = principal_by_bu.get(bu_id)
        reasons = []
        if not principal:
            reasons.append("missing_principal_by_bu")
        candidate = {
            "project_id": project_id,
            "principal_id": principal,
            "authority_scope": f"project:{project_id}",
            "code": row.get("proj_code"),
            "name": row.get("proj_name"),
            "business_unit_id": bu_id,
        } if principal else None
        rows_out.append(item("ep_project", project_id, "project", project_id, candidate, reasons))

    for row in tables["cb_contract"]:
        contract_id = str(row.get("contract_guid", ""))
        bu_id = str(row.get("bu_guid", ""))
        project_id = str(row.get("proj_guid", ""))
        provider_name = str(row.get("yf_provider_name") or "")
        principal = principal_by_bu.get(bu_id)
        counterparty = counterparty_by_provider.get(provider_name)
        currency = currency_by_bu.get(bu_id)
        reasons = []
        if not principal:
            reasons.append("missing_principal_by_bu")
        if project_id not in project_ids:
            reasons.append("missing_project")
        if not counterparty:
            reasons.append("missing_counterparty_by_provider_name")
        if not currency:
            reasons.append("missing_currency_by_bu")
        amount_minor: int | None = None
        if currency:
            try:
                amount_minor = money_minor(row.get("ht_amount"), currency, money_policy)
            except PlanError as error:
                reasons.append(str(error))
        candidate = {
            "commitment_id": contract_id,
            "principal_id": principal,
            "project_scope": f"project:{project_id}",
            "business_unit_id": bu_id,
            "counterparty_id": counterparty,
            "amount_minor": amount_minor,
            "currency": currency,
        } if not reasons else None
        rows_out.append(item("cb_contract", contract_id, "commitment", contract_id, candidate, reasons))

    for row in tables["cb_cost"]:
        cost_id = str(row.get("cost_guid", ""))
        bu_id = str(row.get("bu_guid", ""))
        project_id = str(row.get("proj_guid", ""))
        currency = currency_by_bu.get(bu_id)
        reasons = []
        if project_id not in project_ids:
            reasons.append("missing_project")
        if not currency:
            reasons.append("missing_currency_by_bu")
        components: dict[str, int] = {}
        if currency:
            for target_name in required_cost_fields:
                source_name = str(cost_map[target_name])
                try:
                    components[target_name] = money_minor(row.get(source_name), currency, money_policy)
                except PlanError as error:
                    reasons.append(f"{target_name}: {error}")
        candidate = {
            "cost_id": cost_id,
            "project_scope": f"project:{project_id}",
            "currency": currency,
            "components_minor": components,
        } if not reasons else None
        rows_out.append(item("cb_cost", cost_id, "dynamic_cost", cost_id, candidate, reasons))

    for row in tables["vcb_loan_simple"]:
        loan_id = str(row.get("loan_guid", ""))
        bu_id = str(row.get("bu_guid", ""))
        source_user = str(row.get("applied_by", ""))
        principal = principal_by_bu.get(bu_id)
        employee = employee_by_user.get(source_user)
        currency = currency_by_bu.get(bu_id)
        reasons = []
        warnings: list[str] = []
        if not principal:
            reasons.append("missing_principal_by_bu")
        if not employee:
            reasons.append("missing_employee_by_user")
        if not currency:
            reasons.append("missing_currency_by_bu")
        amount_minor: int | None = None
        if currency:
            try:
                amount_minor = money_minor(row.get("loan_amount"), currency, money_policy)
            except PlanError as error:
                reasons.append(str(error))
        balance = row.get("balance_amount", 0)
        if balance not in (None, 0, 0.0, "0", "0.0"):
            warnings.append("source_balance_requires_explicit_offset_event")
        candidate = {
            "advance_id": loan_id,
            "principal_id": principal,
            "employee_id": employee,
            "business_unit_id": bu_id,
            "authority_scope": f"employee:{employee}" if employee else None,
            "amount_minor": amount_minor,
            "currency": currency,
        } if not reasons else None
        rows_out.append(item("vcb_loan_simple", loan_id, "employee_advance", loan_id, candidate, reasons, warnings))

    ready = sum(row["disposition"] == "ready_for_domain_import" for row in rows_out)
    quarantined = len(rows_out) - ready
    return {
        "format": "moonproj.erp.promotion-plan.v1",
        "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
        "source_sha256": manifest["source_sha256"],
        "mapping_version": config.get("mapping_version", "unversioned-explicit-map"),
        "money_policy": money_policy,
        "cost_component_map": cost_map,
        "cohort": "mapped-economic-v1",
        "summary": {"items": len(rows_out), "ready": ready, "quarantined": quarantined},
        "items": rows_out,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="credential-safe export directory")
    parser.add_argument("mapping", type=Path, help="explicit promotion mapping JSON")
    parser.add_argument("output", type=Path, help="promotion plan JSON")
    args = parser.parse_args()
    try:
        manifest, tables = load_export(args.export)
        config = load_json(args.mapping)
        if not isinstance(config, dict):
            raise PlanError("promotion mapping must be a JSON object")
        plan = build_plan(manifest, tables, config)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError) as error:
        print(f"promotion plan failed: {error}", file=__import__("sys").stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
