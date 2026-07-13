#!/usr/bin/env python3
"""Compile a reviewed opening-control map into a native migration plan.

Opening controls are approved control totals, not inferred balances. The
planner preserves each metric, dimension, value, tolerance, and unit so the
native migration command can validate the set and durable adapters can compare
the exact reviewed candidate after reopen.
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
        raise PlanError("opening-control mapping is not an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
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
        if config.get("format") != "moonproj.erp.opening-control-map.v1":
            raise PlanError("unexpected opening-control map format")
        if config.get("reviewed") is not True:
            raise PlanError("opening-control map is not reviewed")
        source_snapshot_id = require_string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = require_string(config.get("mapping_version"), "mapping_version")
        run_id = require_string(config.get("run_id"), "run_id")
        controls = config.get("controls")
        if not isinstance(controls, list) or not controls:
            raise PlanError("controls must be a non-empty array")
        seen: set[str] = set()
        normalized: list[dict[str, Any]] = []
        for index, control in enumerate(controls):
            if not isinstance(control, dict):
                raise PlanError(f"controls[{index}] is not an object")
            metric_id = require_string(control.get("metric_id"), f"controls[{index}].metric_id")
            domain = require_string(control.get("domain"), f"controls[{index}].domain")
            dimension = require_string(control.get("dimension"), f"controls[{index}].dimension")
            unit = require_string(control.get("unit"), f"controls[{index}].unit")
            value = control.get("value")
            tolerance = control.get("tolerance")
            if not isinstance(value, int) or value < 0:
                raise PlanError(f"controls[{index}].value must be non-negative integer")
            if not isinstance(tolerance, int) or tolerance < 0:
                raise PlanError(f"controls[{index}].tolerance must be non-negative integer")
            if metric_id in seen:
                raise PlanError(f"duplicate metric_id: {metric_id}")
            seen.add(metric_id)
            normalized.append(
                {
                    "metric_id": metric_id,
                    "domain": domain,
                    "dimension": dimension,
                    "value": value,
                    "tolerance": tolerance,
                    "unit": unit,
                }
            )
        plan = {
            "format": "moonproj.erp.opening-control-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {"controls": len(normalized)},
            "controls": normalized,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"opening-control plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
