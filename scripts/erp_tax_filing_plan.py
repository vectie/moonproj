#!/usr/bin/env python3
"""Compile a reviewed tax-filing map into a native migration plan.

Tax rows are accepted only when the migration reviewer supplies the source
identity, amount/rate policy, filing period, and authority reference. The
planner never derives tax obligations from operational rows and never grants
payment, ledger-posting, or cash authority.
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
FINAL_STATES = {"submitted", "accepted", "rejected"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("tax filing mapping is not an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def require_int(value: Any, label: str, *, minimum: int = 0, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlanError(f"{label} must be an integer")
    if value < minimum or maximum is not None and value > maximum:
        bound = f" in [{minimum}, {maximum}]" if maximum is not None else f" >= {minimum}"
        raise PlanError(f"{label} must be{bound}")
    return value


def reject_secret_keys(value: Any, path: str = "mapping") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise PlanError(f"secret-shaped key at {path}.{key}")
            reject_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_keys(child, f"{path}[{index}]")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secret_keys(config)
        if config.get("format") != "moonproj.erp.tax-filing-map.v1":
            raise PlanError("unexpected tax-filing map format")
        if config.get("reviewed") is not True:
            raise PlanError("tax-filing map is not reviewed")
        source_snapshot_id = require_string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = require_string(config.get("mapping_version"), "mapping_version")
        run_id = require_string(config.get("run_id"), "run_id")
        filings = config.get("filings")
        if not isinstance(filings, list) or not filings:
            raise PlanError("filings must be a non-empty array")
        seen_filing_ids: set[str] = set()
        seen_source_ids: set[str] = set()
        normalized: list[dict[str, Any]] = []
        for index, filing in enumerate(filings):
            if not isinstance(filing, dict):
                raise PlanError(f"filings[{index}] is not an object")
            source_table = require_string(filing.get("source_table"), f"filings[{index}].source_table")
            source_id = require_string(filing.get("source_id"), f"filings[{index}].source_id")
            tax_id = require_string(filing.get("tax_id"), f"filings[{index}].tax_id")
            filing_id = require_string(filing.get("filing_id"), f"filings[{index}].filing_id")
            principal_id = require_string(filing.get("principal_id"), f"filings[{index}].principal_id")
            project_scope = require_string(filing.get("project_scope"), f"filings[{index}].project_scope")
            source_reference = require_string(
                filing.get("source_reference"), f"filings[{index}].source_reference"
            )
            jurisdiction = require_string(filing.get("jurisdiction"), f"filings[{index}].jurisdiction")
            category = require_string(filing.get("category"), f"filings[{index}].category")
            currency = require_string(filing.get("currency"), f"filings[{index}].currency")
            filing_period = require_string(filing.get("filing_period"), f"filings[{index}].filing_period")
            authority_reference = require_string(
                filing.get("authority_reference"), f"filings[{index}].authority_reference"
            )
            base_amount_minor = require_int(
                filing.get("base_amount_minor"), f"filings[{index}].base_amount_minor", minimum=1
            )
            tax_rate_bps = require_int(
                filing.get("tax_rate_bps"), f"filings[{index}].tax_rate_bps", maximum=10000
            )
            withholding_rate_bps = require_int(
                filing.get("withholding_rate_bps"),
                f"filings[{index}].withholding_rate_bps",
                maximum=10000,
            )
            final_state = require_string(filing.get("final_state"), f"filings[{index}].final_state")
            if final_state not in FINAL_STATES:
                raise PlanError(
                    f"filings[{index}].final_state must be one of {sorted(FINAL_STATES)}"
                )
            if filing_id in seen_filing_ids:
                raise PlanError(f"duplicate filing_id: {filing_id}")
            if source_id in seen_source_ids:
                raise PlanError(f"duplicate source_id: {source_id}")
            seen_filing_ids.add(filing_id)
            seen_source_ids.add(source_id)
            normalized.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "tax_id": tax_id,
                    "filing_id": filing_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "source_reference": source_reference,
                    "jurisdiction": jurisdiction,
                    "category": category,
                    "currency": currency,
                    "base_amount_minor": base_amount_minor,
                    "tax_rate_bps": tax_rate_bps,
                    "withholding_rate_bps": withholding_rate_bps,
                    "filing_period": filing_period,
                    "authority_reference": authority_reference,
                    "final_state": final_state,
                }
            )
        plan = {
            "format": "moonproj.erp.tax-filing-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {"filings": len(normalized)},
            "filings": normalized,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"tax-filing plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
