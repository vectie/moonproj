#!/usr/bin/env python3
"""Compile a reviewed supplier/tender/commitment map into a native plan."""

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
        raise PlanError("procurement map is not an object")
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.procurement-cohort-map.v1":
            raise PlanError("unexpected procurement map format")
        if config.get("reviewed") is not True:
            raise PlanError("procurement map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        suppliers = config.get("suppliers")
        tenders = config.get("tenders")
        if not isinstance(suppliers, list) or not suppliers:
            raise PlanError("suppliers must be a non-empty array")
        if not isinstance(tenders, list) or not tenders:
            raise PlanError("tenders must be a non-empty array")
        supplier_ids: set[str] = set()
        normalized_suppliers: list[dict[str, Any]] = []
        for index, supplier in enumerate(suppliers):
            if not isinstance(supplier, dict):
                raise PlanError(f"suppliers[{index}] is not an object")
            prefix = f"suppliers[{index}]"
            source_table = string(supplier.get("source_table"), f"{prefix}.source_table")
            source_id = string(supplier.get("source_id"), f"{prefix}.source_id")
            supplier_id = string(supplier.get("supplier_id"), f"{prefix}.supplier_id")
            principal_id = string(supplier.get("principal_id"), f"{prefix}.principal_id")
            scope = string(supplier.get("scope"), f"{prefix}.scope")
            supplier_code = string(supplier.get("supplier_code"), f"{prefix}.supplier_code")
            name = string(supplier.get("name"), f"{prefix}.name")
            category_code = string(supplier.get("category_code"), f"{prefix}.category_code")
            evaluation = string(supplier.get("expected_evaluation"), f"{prefix}.expected_evaluation")
            expected_state = string(supplier.get("expected_state"), f"{prefix}.expected_state")
            if supplier_id in supplier_ids:
                raise PlanError(f"duplicate supplier_id: {supplier_id}")
            if evaluation not in {"qualified", "strategic"}:
                raise PlanError(f"{prefix}.expected_evaluation must be qualified or strategic")
            if expected_state != "active":
                raise PlanError(f"{prefix}.expected_state must be active")
            supplier_ids.add(supplier_id)
            normalized_suppliers.append({
                "source_table": source_table,
                "source_id": source_id,
                "supplier_id": supplier_id,
                "principal_id": principal_id,
                "scope": scope,
                "supplier_code": supplier_code,
                "name": name,
                "category_code": category_code,
                "expected_evaluation": evaluation,
                "expected_state": expected_state,
            })
        tender_ids: set[str] = set()
        commitment_ids: set[str] = set()
        normalized_tenders: list[dict[str, Any]] = []
        for index, tender in enumerate(tenders):
            if not isinstance(tender, dict):
                raise PlanError(f"tenders[{index}] is not an object")
            prefix = f"tenders[{index}]"
            source_table = string(tender.get("source_table"), f"{prefix}.source_table")
            source_id = string(tender.get("source_id"), f"{prefix}.source_id")
            tender_id = string(tender.get("tender_id"), f"{prefix}.tender_id")
            principal_id = string(tender.get("principal_id"), f"{prefix}.principal_id")
            project_scope = string(tender.get("project_scope"), f"{prefix}.project_scope")
            name = string(tender.get("name"), f"{prefix}.name")
            category = string(tender.get("category"), f"{prefix}.category")
            currency = string(tender.get("currency"), f"{prefix}.currency")
            estimated = integer(tender.get("estimated_amount_minor"), f"{prefix}.estimated_amount_minor", 1)
            bids = tender.get("bids")
            awarded_supplier_id = string(tender.get("awarded_supplier_id"), f"{prefix}.awarded_supplier_id")
            awarded_amount = integer(tender.get("awarded_amount_minor"), f"{prefix}.awarded_amount_minor", 1)
            commitment_id = string(tender.get("commitment_id"), f"{prefix}.commitment_id")
            expected_tender_state = string(tender.get("expected_tender_state"), f"{prefix}.expected_tender_state")
            expected_commitment_state = string(tender.get("expected_commitment_state"), f"{prefix}.expected_commitment_state")
            if tender_id in tender_ids:
                raise PlanError(f"duplicate tender_id: {tender_id}")
            if commitment_id in commitment_ids:
                raise PlanError(f"duplicate commitment_id: {commitment_id}")
            if awarded_supplier_id not in supplier_ids:
                raise PlanError(f"{prefix}.awarded_supplier_id is not a mapped supplier")
            if expected_tender_state != "awarded":
                raise PlanError(f"{prefix}.expected_tender_state must be awarded")
            if expected_commitment_state != "performed":
                raise PlanError(f"{prefix}.expected_commitment_state must be performed")
            if awarded_amount > estimated:
                raise PlanError(f"{prefix}.awarded_amount_minor exceeds estimate")
            if not isinstance(bids, list) or len(bids) < 2:
                raise PlanError(f"{prefix}.bids must contain at least two bids")
            bid_supplier_ids: set[str] = set()
            normalized_bids: list[dict[str, Any]] = []
            awarded_match = False
            for bid_index, bid in enumerate(bids):
                if not isinstance(bid, dict):
                    raise PlanError(f"{prefix}.bids[{bid_index}] is not an object")
                bid_prefix = f"{prefix}.bids[{bid_index}]"
                supplier_id = string(bid.get("supplier_id"), f"{bid_prefix}.supplier_id")
                bid_id = string(bid.get("bid_id"), f"{bid_prefix}.bid_id")
                amount = integer(bid.get("amount_minor"), f"{bid_prefix}.amount_minor", 1)
                bid_currency = string(bid.get("currency", currency), f"{bid_prefix}.currency")
                if supplier_id not in supplier_ids:
                    raise PlanError(f"{bid_prefix}.supplier_id is not a mapped supplier")
                if supplier_id in bid_supplier_ids:
                    raise PlanError(f"duplicate bid supplier: {supplier_id}")
                if bid_currency != currency:
                    raise PlanError(f"{bid_prefix}.currency differs from tender")
                if amount > estimated:
                    raise PlanError(f"{bid_prefix}.amount_minor exceeds estimate")
                if supplier_id == awarded_supplier_id:
                    if amount != awarded_amount:
                        raise PlanError(f"{prefix}.awarded_amount_minor differs from awarded bid")
                    awarded_match = True
                bid_supplier_ids.add(supplier_id)
                normalized_bids.append({
                    "supplier_id": supplier_id,
                    "bid_id": bid_id,
                    "amount_minor": amount,
                    "currency": bid_currency,
                })
            if not awarded_match:
                raise PlanError(f"{prefix}.awarded_supplier_id has no matching bid")
            tender_ids.add(tender_id)
            commitment_ids.add(commitment_id)
            normalized_tenders.append({
                "source_table": source_table,
                "source_id": source_id,
                "tender_id": tender_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "name": name,
                "category": category,
                "currency": currency,
                "estimated_amount_minor": estimated,
                "bids": normalized_bids,
                "awarded_supplier_id": awarded_supplier_id,
                "awarded_amount_minor": awarded_amount,
                "commitment_id": commitment_id,
                "expected_tender_state": expected_tender_state,
                "expected_commitment_state": expected_commitment_state,
            })
        plan = {
            "format": "moonproj.erp.procurement-cohort-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {
                "suppliers": len(normalized_suppliers),
                "tenders": len(normalized_tenders),
                "commitments": len(normalized_tenders),
            },
            "suppliers": normalized_suppliers,
            "tenders": normalized_tenders,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"procurement cohort plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
