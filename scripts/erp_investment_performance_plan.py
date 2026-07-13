#!/usr/bin/env python3
"""Compile a reviewed portfolio/quote/benchmark map into a native plan."""

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
        raise PlanError("investment performance map is not an object")
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
        if config.get("format") != "moonproj.erp.investment-performance-map.v1":
            raise PlanError("unexpected investment performance map format")
        if config.get("reviewed") is not True:
            raise PlanError("investment performance map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        portfolio = config.get("portfolio")
        if not isinstance(portfolio, dict):
            raise PlanError("portfolio must be an object")
        prefix = "portfolio"
        source_table = string(portfolio.get("source_table"), f"{prefix}.source_table")
        source_id = string(portfolio.get("source_id"), f"{prefix}.source_id")
        portfolio_id = string(portfolio.get("portfolio_id"), f"{prefix}.portfolio_id")
        mandate_id = string(portfolio.get("mandate_id"), f"{prefix}.mandate_id")
        principal_id = string(portfolio.get("principal_id"), f"{prefix}.principal_id")
        project_scope = string(portfolio.get("project_scope"), f"{prefix}.project_scope")
        currency = string(portfolio.get("currency"), f"{prefix}.currency")
        max_exposure = integer(portfolio.get("max_exposure_minor"), f"{prefix}.max_exposure_minor", 1)
        max_single_position = integer(portfolio.get("max_single_position_minor"), f"{prefix}.max_single_position_minor", 1)
        if max_single_position > max_exposure:
            raise PlanError("portfolio max_single_position_minor exceeds max_exposure_minor")
        positions = portfolio.get("positions")
        if not isinstance(positions, list) or not positions:
            raise PlanError("portfolio.positions must be a non-empty array")
        position_ids: set[str] = set()
        instruments: set[str] = set()
        normalized_positions: list[dict[str, Any]] = []
        for index, position in enumerate(positions):
            if not isinstance(position, dict):
                raise PlanError(f"portfolio.positions[{index}] is not an object")
            position_prefix = f"portfolio.positions[{index}]"
            position_id = string(position.get("position_id"), f"{position_prefix}.position_id")
            instrument = string(position.get("instrument"), f"{position_prefix}.instrument")
            quantity = integer(position.get("quantity"), f"{position_prefix}.quantity", 1)
            cost_basis = integer(position.get("cost_basis_minor"), f"{position_prefix}.cost_basis_minor", 1)
            position_currency = string(position.get("currency", currency), f"{position_prefix}.currency")
            if position_id in position_ids:
                raise PlanError(f"duplicate position_id: {position_id}")
            if instrument in instruments:
                raise PlanError(f"duplicate instrument: {instrument}")
            if position_currency != currency:
                raise PlanError(f"{position_prefix}.currency differs from portfolio")
            if cost_basis > max_single_position:
                raise PlanError(f"{position_prefix}.cost_basis_minor exceeds max single position")
            position_ids.add(position_id)
            instruments.add(instrument)
            normalized_positions.append({
                "position_id": position_id,
                "instrument": instrument,
                "quantity": quantity,
                "cost_basis_minor": cost_basis,
                "currency": position_currency,
            })
        quotes = portfolio.get("quotes")
        if not isinstance(quotes, list) or len(quotes) != len(normalized_positions):
            raise PlanError("portfolio.quotes must contain one quote per position")
        quote_instruments: set[str] = set()
        normalized_quotes: list[dict[str, Any]] = []
        for index, quote in enumerate(quotes):
            if not isinstance(quote, dict):
                raise PlanError(f"portfolio.quotes[{index}] is not an object")
            quote_prefix = f"portfolio.quotes[{index}]"
            instrument = string(quote.get("instrument"), f"{quote_prefix}.instrument")
            price = integer(quote.get("price_minor"), f"{quote_prefix}.price_minor", 1)
            quote_currency = string(quote.get("currency", currency), f"{quote_prefix}.currency")
            if instrument not in instruments:
                raise PlanError(f"{quote_prefix}.instrument has no position")
            if instrument in quote_instruments:
                raise PlanError(f"duplicate quote instrument: {instrument}")
            if quote_currency != currency:
                raise PlanError(f"{quote_prefix}.currency differs from portfolio")
            quote_instruments.add(instrument)
            normalized_quotes.append({
                "instrument": instrument,
                "price_minor": price,
                "currency": quote_currency,
            })
        benchmark = config.get("benchmark")
        if not isinstance(benchmark, dict):
            raise PlanError("benchmark must be an object")
        benchmark_prefix = "benchmark"
        benchmark_source_table = string(benchmark.get("source_table"), f"{benchmark_prefix}.source_table")
        benchmark_source_id = string(benchmark.get("source_id"), f"{benchmark_prefix}.source_id")
        period_id = string(benchmark.get("period_id"), f"{benchmark_prefix}.period_id")
        benchmark_id = string(benchmark.get("benchmark_id"), f"{benchmark_prefix}.benchmark_id")
        observation_id = string(benchmark.get("observation_id"), f"{benchmark_prefix}.observation_id")
        evidence_id = string(benchmark.get("evidence_id"), f"{benchmark_prefix}.evidence_id")
        benchmark_return = integer(benchmark.get("benchmark_return_bps"), f"{benchmark_prefix}.benchmark_return_bps")
        observed_return = integer(benchmark.get("observed_return_bps"), f"{benchmark_prefix}.observed_return_bps")
        tolerance = integer(benchmark.get("tolerance_bps"), f"{benchmark_prefix}.tolerance_bps")
        if benchmark_source_id != observation_id:
            raise PlanError("benchmark.source_id must equal observation_id")
        if not isinstance(benchmark.get("expected_within_mandate"), bool):
            raise PlanError("benchmark.expected_within_mandate must be boolean")
        if not isinstance(benchmark.get("expected_reconciled"), bool):
            raise PlanError("benchmark.expected_reconciled must be boolean")
        plan = {
            "format": "moonproj.erp.investment-performance-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "portfolio": {
                "source_table": source_table,
                "source_id": source_id,
                "portfolio_id": portfolio_id,
                "mandate_id": mandate_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "currency": currency,
                "max_exposure_minor": max_exposure,
                "max_single_position_minor": max_single_position,
                "positions": normalized_positions,
                "quotes": normalized_quotes,
            },
            "benchmark": {
                "source_table": benchmark_source_table,
                "source_id": benchmark_source_id,
                "period_id": period_id,
                "benchmark_id": benchmark_id,
                "observation_id": observation_id,
                "evidence_id": evidence_id,
                "benchmark_return_bps": benchmark_return,
                "observed_return_bps": observed_return,
                "tolerance_bps": tolerance,
                "expected_within_mandate": benchmark["expected_within_mandate"],
                "expected_reconciled": benchmark["expected_reconciled"],
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "positions": len(normalized_positions), "quotes": len(normalized_quotes)}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"investment performance plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
