#!/usr/bin/env python3
"""Compile a reviewed asset lifecycle map into a native migration plan.

The plan preserves capitalization, depreciation, impairment, and disposal
evidence. It does not authorize journal posting, cash settlement, or period
close.
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
STATES = {"active", "impaired", "disposed"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("asset lifecycle map is not an object")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlanError(f"{label} must be an integer")
    if value < minimum or maximum is not None and value > maximum:
        raise PlanError(f"{label} is outside the allowed range")
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


def account_map(value: Any, label: str) -> dict[str, str]:
    if not isinstance(value, dict):
        raise PlanError(f"{label} must be an object")
    result: dict[str, str] = {}
    for key in (
        "depreciation_expense_account",
        "accumulated_depreciation_account",
        "cash_or_receivable_account",
        "asset_account",
        "gain_account",
        "loss_account",
    ):
        result[key] = string(value.get(key), f"{label}.{key}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.asset-lifecycle-map.v1":
            raise PlanError("unexpected asset lifecycle map format")
        if config.get("reviewed") is not True:
            raise PlanError("asset lifecycle map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        assets = config.get("assets")
        if not isinstance(assets, list) or not assets:
            raise PlanError("assets must be a non-empty array")
        seen: set[str] = set()
        normalized: list[dict[str, Any]] = []
        for index, asset in enumerate(assets):
            if not isinstance(asset, dict):
                raise PlanError(f"assets[{index}] is not an object")
            prefix = f"assets[{index}]"
            source_table = string(asset.get("source_table"), f"{prefix}.source_table")
            source_id = string(asset.get("source_id"), f"{prefix}.source_id")
            asset_id = string(asset.get("asset_id"), f"{prefix}.asset_id")
            principal_id = string(asset.get("principal_id"), f"{prefix}.principal_id")
            project_scope = string(asset.get("project_scope"), f"{prefix}.project_scope")
            description = string(asset.get("description"), f"{prefix}.description")
            currency = string(asset.get("currency"), f"{prefix}.currency")
            acquisition = integer(asset.get("acquisition_cost_minor"), f"{prefix}.acquisition_cost_minor", 1)
            residual = integer(asset.get("residual_value_minor"), f"{prefix}.residual_value_minor")
            useful_life = integer(asset.get("useful_life_months"), f"{prefix}.useful_life_months", 1)
            expected_state = string(asset.get("expected_state"), f"{prefix}.expected_state")
            if expected_state not in STATES:
                raise PlanError(f"{prefix}.expected_state is invalid")
            if residual > acquisition:
                raise PlanError(f"{prefix}.residual_value_minor exceeds acquisition cost")
            impair_before_disposal = asset.get("impair_before_disposal", False)
            if not isinstance(impair_before_disposal, bool):
                raise PlanError(f"{prefix}.impair_before_disposal must be a boolean")
            if expected_state == "impaired" and not impair_before_disposal:
                raise PlanError(f"{prefix}.impaired state requires impairment evidence")
            if expected_state != "disposed" and impair_before_disposal and expected_state != "impaired":
                raise PlanError(f"{prefix}.impair_before_disposal is inconsistent with expected state")
            periods = asset.get("depreciation_periods")
            if not isinstance(periods, list):
                raise PlanError(f"{prefix}.depreciation_periods must be an array")
            period_ids: set[str] = set()
            normalized_periods: list[dict[str, str]] = []
            for period_index, period in enumerate(periods):
                if not isinstance(period, dict):
                    raise PlanError(f"{prefix}.depreciation_periods[{period_index}] is not an object")
                period_id = string(period.get("period_id"), f"{prefix}.depreciation_periods[{period_index}].period_id")
                if period_id in period_ids:
                    raise PlanError(f"duplicate depreciation period: {period_id}")
                period_ids.add(period_id)
                normalized_periods.append({"period_id": period_id})
            proceeds = integer(asset.get("disposal_proceeds_minor"), f"{prefix}.disposal_proceeds_minor")
            if expected_state == "disposed" and not asset.get("disposal_proceeds_minor") and proceeds != 0:
                raise PlanError(f"{prefix}.disposal_proceeds_minor is invalid")
            if expected_state != "disposed" and proceeds != 0:
                raise PlanError(f"{prefix}.disposal_proceeds_minor requires disposed state")
            if asset_id in seen:
                raise PlanError(f"duplicate asset_id: {asset_id}")
            seen.add(asset_id)
            normalized.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "asset_id": asset_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "description": description,
                    "currency": currency,
                    "acquisition_cost_minor": acquisition,
                    "residual_value_minor": residual,
                    "useful_life_months": useful_life,
                    "expected_state": expected_state,
                    "impair_before_disposal": impair_before_disposal,
                    "depreciation_periods": normalized_periods,
                    "disposal_proceeds_minor": proceeds,
                    "accounts": account_map(asset.get("accounts"), f"{prefix}.accounts"),
                }
            )
        plan = {
            "format": "moonproj.erp.asset-lifecycle-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {
                "assets": len(normalized),
                "depreciation_periods": sum(len(item["depreciation_periods"]) for item in normalized),
                "disposals": sum(item["expected_state"] == "disposed" for item in normalized),
            },
            "assets": normalized,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"asset lifecycle plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
