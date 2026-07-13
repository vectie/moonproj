#!/usr/bin/env python3
"""Compile a reviewed invoice/receivable/payable map into a native plan.

The plan preserves subledger lifecycle evidence without releasing collection or
payment cash and without posting the accounting book.
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
INVOICE_STATES = {"accepted", "partially_paid", "paid"}
RECEIVABLE_STATES = {"open", "partially_collected", "collected"}
PAYABLE_STATES = {"open", "partially_paid", "paid"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("invoice subledger map is not an object")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PlanError(f"{label} must be an integer >= {minimum}")
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


def validate_payment(
    payment: int,
    amount: int,
    state: str,
    state_set: set[str],
    label: str,
) -> None:
    if state not in state_set:
        raise PlanError(f"{label} is invalid")
    if payment > amount:
        raise PlanError(f"{label} payment exceeds amount")
    if state in {"accepted", "open"} and payment != 0:
        raise PlanError(f"{label} open state requires zero payment")
    if state in {"partially_paid", "partially_collected"} and not 0 < payment < amount:
        raise PlanError(f"{label} partial state requires payment between zero and amount")
    if state in {"paid", "collected"} and payment != amount:
        raise PlanError(f"{label} closed state requires full payment")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.invoice-subledger-map.v1":
            raise PlanError("unexpected invoice subledger map format")
        if config.get("reviewed") is not True:
            raise PlanError("invoice subledger map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        invoices = config.get("customer_invoices")
        payables = config.get("supplier_payables")
        if not isinstance(invoices, list) or not invoices:
            raise PlanError("customer_invoices must be a non-empty array")
        if not isinstance(payables, list) or not payables:
            raise PlanError("supplier_payables must be a non-empty array")
        invoice_ids: set[str] = set()
        receivable_ids: set[str] = set()
        normalized_invoices: list[dict[str, Any]] = []
        for index, invoice in enumerate(invoices):
            if not isinstance(invoice, dict):
                raise PlanError(f"customer_invoices[{index}] is not an object")
            prefix = f"customer_invoices[{index}]"
            source_table = string(invoice.get("source_table"), f"{prefix}.source_table")
            source_id = string(invoice.get("source_id"), f"{prefix}.source_id")
            invoice_id = string(invoice.get("invoice_id"), f"{prefix}.invoice_id")
            receivable_id = string(invoice.get("receivable_id"), f"{prefix}.receivable_id")
            principal_id = string(invoice.get("principal_id"), f"{prefix}.principal_id")
            customer_id = string(invoice.get("customer_id"), f"{prefix}.customer_id")
            currency = string(invoice.get("currency"), f"{prefix}.currency")
            amount = integer(invoice.get("amount_minor"), f"{prefix}.amount_minor", 1)
            payment = integer(invoice.get("payment_minor"), f"{prefix}.payment_minor")
            invoice_state = string(invoice.get("expected_invoice_state"), f"{prefix}.expected_invoice_state")
            receivable_state = string(invoice.get("expected_receivable_state"), f"{prefix}.expected_receivable_state")
            validate_payment(payment, amount, invoice_state, INVOICE_STATES, f"{prefix}.expected_invoice_state")
            validate_payment(payment, amount, receivable_state, RECEIVABLE_STATES, f"{prefix}.expected_receivable_state")
            if invoice_id in invoice_ids:
                raise PlanError(f"duplicate invoice_id: {invoice_id}")
            if receivable_id in receivable_ids:
                raise PlanError(f"duplicate receivable_id: {receivable_id}")
            invoice_ids.add(invoice_id)
            receivable_ids.add(receivable_id)
            normalized_invoices.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "invoice_id": invoice_id,
                    "receivable_id": receivable_id,
                    "principal_id": principal_id,
                    "customer_id": customer_id,
                    "currency": currency,
                    "amount_minor": amount,
                    "payment_minor": payment,
                    "expected_invoice_state": invoice_state,
                    "expected_receivable_state": receivable_state,
                }
            )
        payable_ids: set[str] = set()
        normalized_payables: list[dict[str, Any]] = []
        for index, payable in enumerate(payables):
            if not isinstance(payable, dict):
                raise PlanError(f"supplier_payables[{index}] is not an object")
            prefix = f"supplier_payables[{index}]"
            source_table = string(payable.get("source_table"), f"{prefix}.source_table")
            source_id = string(payable.get("source_id"), f"{prefix}.source_id")
            payable_id = string(payable.get("payable_id"), f"{prefix}.payable_id")
            principal_id = string(payable.get("principal_id"), f"{prefix}.principal_id")
            project_scope = string(payable.get("project_scope"), f"{prefix}.project_scope")
            supplier_id = string(payable.get("supplier_id"), f"{prefix}.supplier_id")
            source_reference = string(payable.get("source_reference"), f"{prefix}.source_reference")
            currency = string(payable.get("currency"), f"{prefix}.currency")
            amount = integer(payable.get("amount_minor"), f"{prefix}.amount_minor", 1)
            payment = integer(payable.get("payment_minor"), f"{prefix}.payment_minor")
            state = string(payable.get("expected_state"), f"{prefix}.expected_state")
            validate_payment(payment, amount, state, PAYABLE_STATES, f"{prefix}.expected_state")
            if payable_id in payable_ids:
                raise PlanError(f"duplicate payable_id: {payable_id}")
            payable_ids.add(payable_id)
            normalized_payables.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "payable_id": payable_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "supplier_id": supplier_id,
                    "source_reference": source_reference,
                    "currency": currency,
                    "amount_minor": amount,
                    "payment_minor": payment,
                    "expected_state": state,
                }
            )
        plan = {
            "format": "moonproj.erp.invoice-subledger-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {
                "invoices": len(normalized_invoices),
                "receivables": len(normalized_invoices),
                "payables": len(normalized_payables),
            },
            "customer_invoices": normalized_invoices,
            "supplier_payables": normalized_payables,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"invoice subledger plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
