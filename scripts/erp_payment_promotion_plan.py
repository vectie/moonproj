#!/usr/bin/env python3
"""Build an explicit commitment-state/payment-application plan.

The plan never treats a legacy approval or payment flag as cash release. A
reviewed state map may replay a contract to ``performed``; each application
then becomes only a requested settlement through the native importer.
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
        units = Decimal(str(policy.get("minor_units_per_unit", 100)))
        result = amount * units
        rounded = result.to_integral_value(rounding=ROUND_HALF_EVEN)
    except (InvalidOperation, ValueError) as error:
        raise PlanError(f"invalid monetary value: {value!r}") from error
    if result != rounded and not policy.get("allow_rounding", False):
        raise PlanError(f"rounding required for monetary value: {value!r}")
    value_minor = int(rounded)
    if value_minor <= 0:
        raise PlanError(f"non-positive monetary value: {value!r}")
    return value_minor


def contract_candidate(
    contract: dict[str, Any],
    principal: str | None,
    counterparty: str | None,
    currency: str | None,
    amount_minor: int | None,
    reasons: list[str],
) -> dict[str, Any] | None:
    if reasons:
        return None
    contract_id = str(contract.get("contract_guid", ""))
    project_id = str(contract.get("proj_guid", ""))
    return {
        "commitment_id": contract_id,
        "business_unit_id": str(contract.get("bu_guid", "")),
        "project_scope": f"project:{project_id}",
        "principal_id": principal,
        "counterparty_id": counterparty,
        "amount_minor": amount_minor,
        "currency": currency,
    }


def percentage_bps(amount_minor: int, commitment_minor: int) -> int:
    if commitment_minor <= 0 or amount_minor <= 0 or amount_minor > commitment_minor:
        raise PlanError("payment-plan amount is outside commitment")
    value = (Decimal(amount_minor) / Decimal(commitment_minor)) * Decimal("10000")
    return int(value.to_integral_value(rounding=ROUND_HALF_EVEN))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        principal_by_bu = config.get("principal_by_bu", {})
        counterparty_by_provider = config.get("counterparty_by_provider", {})
        currency_by_bu = config.get("currency_by_bu", {})
        state_by_contract = config.get("commitment_state_by_contract", {})
        policy = config.get("money_policy", {})
        if not all(
            isinstance(value, dict)
            for value in (
                principal_by_bu,
                counterparty_by_provider,
                currency_by_bu,
                state_by_contract,
                policy,
            )
        ):
            raise PlanError("payment mapping objects are invalid")
        contracts = load(args.export / "tables" / "cb_contract.json")
        payment_plans = load(args.export / "tables" / "cb_htfkplan.json")
        applications = load(args.export / "tables" / "cb_htfk_apply.json")
        if (
            not isinstance(contracts, list)
            or not isinstance(payment_plans, list)
            or not isinstance(applications, list)
        ):
            raise PlanError("contract/payment exports must be arrays")

        items: list[dict[str, Any]] = []
        contract_info: dict[str, dict[str, Any]] = {}
        for contract in contracts:
            contract_id = str(contract.get("contract_guid", ""))
            bu_id = str(contract.get("bu_guid", ""))
            provider = str(contract.get("yf_provider_name", ""))
            reasons: list[str] = []
            principal = principal_by_bu.get(bu_id)
            counterparty = counterparty_by_provider.get(provider)
            currency = currency_by_bu.get(bu_id)
            if not principal:
                reasons.append("missing_principal_by_bu")
            if not counterparty:
                reasons.append("missing_counterparty_by_provider")
            if not currency:
                reasons.append("missing_currency_by_bu")
            try:
                amount_minor = minor_units(contract.get("ht_amount"), policy)
            except PlanError as error:
                reasons.append(str(error))
                amount_minor = None
            candidate = contract_candidate(
                contract,
                principal,
                counterparty,
                currency,
                amount_minor,
                reasons,
            )
            items.append(
                {
                    "source_table": "cb_contract",
                    "source_id": contract_id,
                    "target_type": "commitment",
                    "target_id": contract_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [],
                    "target_candidate": candidate,
                }
            )
            contract_info[contract_id] = {
                "contract": contract,
                "principal": principal,
                "currency": currency,
                "amount_minor": amount_minor,
                "reasons": reasons,
            }
            target_state = state_by_contract.get(contract_id)
            state_reasons = [] if candidate is not None else ["commitment_mapping_unresolved"]
            if target_state not in {"draft", "submitted", "approved", "performed", "settled", "cancelled"}:
                state_reasons.append("missing_or_invalid_commitment_state_mapping")
            items.append(
                {
                    "source_table": "cb_contract_state",
                    "source_id": f"state:{contract_id}",
                    "target_type": "commitment_state",
                    "target_id": contract_id,
                    "disposition": "ready_for_domain_import" if not state_reasons else "quarantined",
                    "reasons": sorted(set(state_reasons)),
                    "warnings": [
                        "legacy contract status is replayed only through the explicit target-state map"
                    ],
                    "target_candidate": {
                        "commitment_id": contract_id,
                        "target_state": target_state,
                    }
                    if not state_reasons
                    else None,
                }
            )

        plans_by_contract: dict[str, list[dict[str, Any]]] = {}
        for row in payment_plans:
            plans_by_contract.setdefault(str(row.get("contract_guid", "")), []).append(row)
        for contract_id, rows in plans_by_contract.items():
            info = contract_info.get(contract_id)
            rows.sort(
                key=lambda row: (
                    str(row.get("jhfk_date", "")),
                    str(row.get("htfk_plan_guid", "")),
                )
            )
            for sequence, row in enumerate(rows, start=1):
                plan_id = str(row.get("htfk_plan_guid", ""))
                reasons: list[str] = []
                if info is None:
                    reasons.append("missing_contract")
                    contract_amount = None
                else:
                    reasons.extend(info["reasons"])
                    contract_amount = info["amount_minor"]
                try:
                    amount_minor = minor_units(row.get("jhfk_amount"), policy)
                except PlanError as error:
                    reasons.append(str(error))
                    amount_minor = None
                pct_bps = None
                if amount_minor is not None and contract_amount is not None:
                    try:
                        pct_bps = percentage_bps(amount_minor, contract_amount)
                    except PlanError as error:
                        reasons.append(str(error))
                candidate = {
                    "commitment_id": contract_id,
                    "principal_id": info.get("principal") if info else None,
                    "authority_scope": (
                        f"project:{info['contract'].get('proj_guid')}" if info else None
                    ),
                    "currency": info.get("currency") if info else None,
                    "milestone": {
                        "milestone_guid": plan_id,
                        "contract_guid": contract_id,
                        "sequence": sequence,
                        "node_name": row.get("plan_period"),
                        "trigger_type": "time",
                        "plan_amount_minor": amount_minor,
                        "plan_pct_bps": pct_bps,
                    },
                }
                items.append(
                    {
                        "source_table": "cb_htfkplan",
                        "source_id": plan_id,
                        "target_type": "contract_milestone",
                        "target_id": plan_id,
                        "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                        "reasons": sorted(set(reasons)),
                        "warnings": [
                            "source approval/confirmation flags remain evidence; only the planned milestone is promoted"
                        ],
                        "target_candidate": candidate if not reasons else None,
                    }
                )

        for application in applications:
            application_id = str(application.get("htfk_apply_guid", ""))
            contract_id = str(application.get("contract_guid", ""))
            info = contract_info.get(contract_id)
            reasons: list[str] = []
            if info is None:
                reasons.append("missing_contract")
            else:
                reasons.extend(info["reasons"])
            currency = info.get("currency") if info else None
            try:
                amount_minor = minor_units(application.get("apply_amount"), policy)
            except PlanError as error:
                reasons.append(str(error))
                amount_minor = None
            try:
                amount_bz_minor = minor_units(application.get("apply_amount_bz"), policy)
            except PlanError as error:
                reasons.append(str(error))
                amount_bz_minor = None
            if info and amount_minor is not None and info["amount_minor"] is not None:
                if amount_minor > info["amount_minor"]:
                    reasons.append("application_exceeds_commitment")
            candidate = {
                "application": {
                    "apply_guid": application_id,
                    "apply_code": application.get("apply_code"),
                    "contract_guid": contract_id,
                    "plan_guid": application.get("htfk_plan_guid"),
                    "apply_class": int(application.get("apply_class", 0)),
                    "apply_type_code": application.get("apply_type_code"),
                    "apply_state": application.get("apply_state"),
                    "pay_state": application.get("pay_state"),
                    "subject": application.get("subject"),
                    "apply_dept_guid": application.get("apply_dept_guid"),
                    "applied_by": application.get("applied_by"),
                    "apply_date": application.get("apply_date"),
                    "amount_minor": amount_minor,
                    "amount_bz_minor": amount_bz_minor,
                    "proj_guid": application.get("proj_guid"),
                    "proj_type": application.get("proj_type"),
                    "contract_class": application.get("ht_class"),
                    "bu_guid": application.get("bu_guid"),
                },
                "commitment_id": contract_id,
                "currency": currency,
                "principal_id": info.get("principal") if info else None,
                "authority_scope": f"project:{application.get('proj_guid')}",
            }
            items.append(
                {
                    "source_table": "cb_htfk_apply",
                    "source_id": application_id,
                    "target_type": "payment_application",
                    "target_id": application_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "source approval/payment flags remain evidence; promotion creates a requested settlement only"
                    ],
                    "target_candidate": candidate if not reasons else None,
                }
            )

        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.payment-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-payment-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"payment promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
