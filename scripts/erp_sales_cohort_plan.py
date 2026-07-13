#!/usr/bin/env python3
"""Compile a reviewed sales/receivables map into a native migration plan.

The plan exercises customer, subscription, sales-agreement, mortgage, refund,
and receivable state machines. Revenue is retained as explicitly marked source
evidence; it never authorizes cash receipt, revenue recognition, or a journal.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("sales map is not an object")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PlanError(f"{label} must be an integer >= {minimum}")
    return value


def obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PlanError(f"{label} must be an object")
    return value


def reject_secrets(value: Any, path: str = "mapping") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise PlanError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.sales-cohort-map.v1":
            raise PlanError("unexpected sales map format")
        if config.get("reviewed") is not True:
            raise PlanError("sales map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")

        customer = obj(config.get("customer"), "customer")
        customer_id = string(customer.get("customer_id"), "customer.customer_id")
        principal_id = string(customer.get("principal_id"), "customer.principal_id")
        project_scope = string(customer.get("project_scope"), "customer.project_scope")
        if string(customer.get("expected_state"), "customer.expected_state") != "active":
            raise PlanError("customer.expected_state must be active")

        subscription = obj(config.get("subscription"), "subscription")
        if string(subscription.get("expected_state"), "subscription.expected_state") != "converted":
            raise PlanError("subscription.expected_state must be converted")
        subscription_amount = integer(
            subscription.get("amount_minor"), "subscription.amount_minor", 1
        )
        subscription_currency = string(subscription.get("currency"), "subscription.currency")
        agreement = obj(config.get("agreement"), "agreement")
        if string(agreement.get("expected_state"), "agreement.expected_state") != "fulfilled":
            raise PlanError("agreement.expected_state must be fulfilled")
        agreement_amount = integer(agreement.get("amount_minor"), "agreement.amount_minor", 1)
        agreement_currency = string(agreement.get("currency"), "agreement.currency")
        if agreement_amount != subscription_amount or agreement_currency != subscription_currency:
            raise PlanError("agreement amount/currency differs from subscription")
        if string(agreement.get("receivable_id"), "agreement.receivable_id") == "":
            raise PlanError("agreement.receivable_id is required")

        mortgage = obj(config.get("mortgage"), "mortgage")
        if string(mortgage.get("expected_state"), "mortgage.expected_state") != "released":
            raise PlanError("mortgage.expected_state must be released")
        loan_amount = integer(mortgage.get("loan_amount_minor"), "mortgage.loan_amount_minor", 1)
        if loan_amount > agreement_amount:
            raise PlanError("mortgage.loan_amount_minor exceeds agreement amount")
        annual_rate = integer(mortgage.get("annual_rate_bps"), "mortgage.annual_rate_bps")
        if annual_rate > 10000:
            raise PlanError("mortgage.annual_rate_bps exceeds 10000")

        refund = obj(config.get("refund"), "refund")
        if string(refund.get("expected_state"), "refund.expected_state") != "paid":
            raise PlanError("refund.expected_state must be paid")
        refund_amount = integer(refund.get("amount_minor"), "refund.amount_minor", 1)
        if refund_amount > agreement_amount:
            raise PlanError("refund.amount_minor exceeds agreement amount")

        revenue = obj(config.get("revenue"), "revenue")
        if string(revenue.get("evidence_state"), "revenue.evidence_state") != "source_evidence_only":
            raise PlanError("revenue must remain source_evidence_only")
        revenue_amount = integer(revenue.get("amount_minor"), "revenue.amount_minor", 1)
        revenue_currency = string(revenue.get("currency"), "revenue.currency")
        if revenue_amount != agreement_amount or revenue_currency != agreement_currency:
            raise PlanError("revenue amount/currency differs from agreement")
        if string(revenue.get("contract_code"), "revenue.contract_code") != string(
            agreement.get("agreement_id"), "agreement.agreement_id"
        ):
            raise PlanError("revenue.contract_code does not identify agreement")

        plan = {
            "format": "moonproj.erp.sales-cohort-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "customer": {
                "source_table": string(customer.get("source_table"), "customer.source_table"),
                "source_id": string(customer.get("source_id"), "customer.source_id"),
                "customer_id": customer_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "customer_code": string(customer.get("customer_code"), "customer.customer_code"),
                "name": string(customer.get("name"), "customer.name"),
                "contact_reference": string(customer.get("contact_reference"), "customer.contact_reference"),
            },
            "subscription": {
                "source_table": string(subscription.get("source_table"), "subscription.source_table"),
                "source_id": string(subscription.get("source_id"), "subscription.source_id"),
                "subscription_id": string(subscription.get("subscription_id"), "subscription.subscription_id"),
                "unit_reference": string(subscription.get("unit_reference"), "subscription.unit_reference"),
                "amount_minor": subscription_amount,
                "currency": subscription_currency,
            },
            "agreement": {
                "source_table": string(agreement.get("source_table"), "agreement.source_table"),
                "source_id": string(agreement.get("source_id"), "agreement.source_id"),
                "agreement_id": string(agreement.get("agreement_id"), "agreement.agreement_id"),
                "receivable_id": string(agreement.get("receivable_id"), "agreement.receivable_id"),
                "amount_minor": agreement_amount,
                "currency": agreement_currency,
            },
            "mortgage": {
                "source_table": string(mortgage.get("source_table"), "mortgage.source_table"),
                "source_id": string(mortgage.get("source_id"), "mortgage.source_id"),
                "mortgage_id": string(mortgage.get("mortgage_id"), "mortgage.mortgage_id"),
                "bank_reference": string(mortgage.get("bank_reference"), "mortgage.bank_reference"),
                "loan_amount_minor": loan_amount,
                "annual_rate_bps": annual_rate,
            },
            "refund": {
                "source_table": string(refund.get("source_table"), "refund.source_table"),
                "source_id": string(refund.get("source_id"), "refund.source_id"),
                "refund_id": string(refund.get("refund_id"), "refund.refund_id"),
                "reason": string(refund.get("reason"), "refund.reason"),
                "amount_minor": refund_amount,
            },
            "revenue": {
                "source_table": string(revenue.get("source_table"), "revenue.source_table"),
                "source_id": string(revenue.get("source_id"), "revenue.source_id"),
                "revenue_id": string(revenue.get("revenue_id"), "revenue.revenue_id"),
                "revenue_code": string(revenue.get("revenue_code"), "revenue.revenue_code"),
                "amount_minor": revenue_amount,
                "currency": revenue_currency,
                "status": string(revenue.get("status"), "revenue.status"),
                "contract_code": string(revenue.get("contract_code"), "revenue.contract_code"),
                "evidence_state": "source_evidence_only",
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "items": 7}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"sales cohort plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
