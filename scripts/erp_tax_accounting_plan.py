#!/usr/bin/env python3
"""Compile explicit accounting maps for reviewed tax obligations."""

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
        raise PlanError(f"JSON root is not an object: {path}")
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


def tax_amount(base: int, rate_bps: int) -> int:
    return (base * rate_bps + 5000) // 10000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tax_plan", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        tax_plan = load(args.tax_plan)
        config = load(args.mapping)
        reject_secrets(config)
        if tax_plan.get("format") != "moonproj.erp.tax-filing-plan.v1" or tax_plan.get("reviewed") is not True:
            raise PlanError("tax plan is not reviewed")
        if config.get("format") != "moonproj.erp.tax-accounting-map.v1" or config.get("reviewed") is not True:
            raise PlanError("tax accounting map is not reviewed")
        source_snapshot_id = string(tax_plan.get("source_snapshot_id"), "tax_plan.source_snapshot_id")
        if string(config.get("source_snapshot_id"), "source_snapshot_id") != source_snapshot_id:
            raise PlanError("tax accounting map source snapshot differs from tax plan")
        mappings = config.get("accounting_by_source")
        if not isinstance(mappings, dict):
            raise PlanError("accounting_by_source must be an object")
        items: list[dict[str, Any]] = []
        seen: set[str] = set()
        for index, filing in enumerate(tax_plan.get("filings", [])):
            if not isinstance(filing, dict):
                raise PlanError(f"filings[{index}] is not an object")
            tax_id = string(filing.get("tax_id"), f"filings[{index}].tax_id")
            if tax_id in seen:
                raise PlanError(f"duplicate tax_id: {tax_id}")
            seen.add(tax_id)
            mapping = mappings.get("tax_obligation:" + tax_id)
            if not isinstance(mapping, dict):
                raise PlanError(f"missing accounting map for tax_obligation:{tax_id}")
            principal_id = string(filing.get("principal_id"), f"filings[{index}].principal_id")
            project_scope = string(filing.get("project_scope"), f"filings[{index}].project_scope")
            currency = string(filing.get("currency"), f"filings[{index}].currency")
            amount = tax_amount(
                integer(filing.get("base_amount_minor"), f"filings[{index}].base_amount_minor", 1),
                integer(filing.get("tax_rate_bps"), f"filings[{index}].tax_rate_bps"),
            )
            for field in ("event_id", "event_type", "tax_expense_account", "tax_payable_account", "journal_id", "description", "scope", "principal_id", "amount_minor", "currency"):
                if field not in mapping or mapping[field] in (None, ""):
                    raise PlanError(f"tax_obligation:{tax_id} missing {field}")
            if mapping["principal_id"] != principal_id or mapping["scope"] != project_scope or mapping["currency"] != currency or mapping["amount_minor"] != amount:
                raise PlanError(f"tax accounting identity/amount mismatch: {tax_id}")
            if mapping["journal_id"] != "tax/" + tax_id + "/recognition":
                raise PlanError(f"tax journal identity mismatch: {tax_id}")
            items.append({
                "source_table": "tax_obligation",
                "source_id": tax_id,
                "tax_id": tax_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "source_reference": string(filing.get("source_reference"), f"filings[{index}].source_reference"),
                "jurisdiction": string(filing.get("jurisdiction"), f"filings[{index}].jurisdiction"),
                "category": string(filing.get("category"), f"filings[{index}].category"),
                "currency": currency,
                "base_amount_minor": integer(filing.get("base_amount_minor"), f"filings[{index}].base_amount_minor", 1),
                "tax_rate_bps": integer(filing.get("tax_rate_bps"), f"filings[{index}].tax_rate_bps"),
                "withholding_rate_bps": integer(filing.get("withholding_rate_bps"), f"filings[{index}].withholding_rate_bps"),
                "accounting": {
                    "event_id": string(mapping["event_id"], f"tax_obligation:{tax_id}.event_id"),
                    "event_type": string(mapping["event_type"], f"tax_obligation:{tax_id}.event_type"),
                    "journal_id": string(mapping["journal_id"], f"tax_obligation:{tax_id}.journal_id"),
                    "description": string(mapping["description"], f"tax_obligation:{tax_id}.description"),
                    "scope": project_scope,
                    "tax_expense_account": string(mapping["tax_expense_account"], f"tax_obligation:{tax_id}.tax_expense_account"),
                    "tax_payable_account": string(mapping["tax_payable_account"], f"tax_obligation:{tax_id}.tax_payable_account"),
                    "debit_account": string(mapping["debit_account"], f"tax_obligation:{tax_id}.debit_account"),
                    "credit_account": string(mapping["credit_account"], f"tax_obligation:{tax_id}.credit_account"),
                    "amount_minor": amount,
                },
            })
        if not items:
            raise PlanError("tax plan has no filings")
        plan = {
            "format": "moonproj.erp.tax-accounting-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": string(config.get("mapping_version"), "mapping_version"),
            "run_id": string(config.get("run_id"), "run_id"),
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "items": len(items)}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"tax accounting plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
