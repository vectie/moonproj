#!/usr/bin/env python3
"""Validate the read-only shadow-period contract for a migration rehearsal.

The contract makes legacy ownership explicit and permits no target business
mutations. It is a readiness artifact; an owner decision can authorize shadow
observation, but never authorizes cutover.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
from pathlib import Path
from typing import Any


class ShadowError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private|credential", re.IGNORECASE)


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ShadowError(f"cannot read JSON evidence: {path}") from error


def reject_secrets(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise ShadowError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def positive_int(value: Any, name: str, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ShadowError(f"{name} must be a positive integer")
    if maximum is not None and value > maximum:
        raise ShadowError(f"{name} exceeds {maximum}")
    return value


def validate(work_dir: Path, manifest: Any) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise ShadowError("shadow manifest must be an object")
    reject_secrets(manifest)
    if manifest.get("format") != "moonproj.company.shadow-period.v1":
        raise ShadowError("unsupported shadow-period format")
    for field in ("period_id", "owner_role", "rollback_runbook"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ShadowError(f"missing non-empty field: {field}")
    if manifest.get("legacy_authoritative") is not True:
        raise ShadowError("legacy_authoritative must remain true during shadow")
    if manifest.get("target_mode") != "read_only_shadow":
        raise ShadowError("target_mode must be read_only_shadow")
    if manifest.get("target_mutations_allowed") is not False:
        raise ShadowError("target mutations must be disabled during shadow")
    duration_days = positive_int(manifest.get("duration_days"), "duration_days", maximum=90)
    comparison_interval_hours = positive_int(
        manifest.get("comparison_interval_hours"),
        "comparison_interval_hours",
        maximum=168,
    )
    dimensions = manifest.get("comparison_dimensions")
    if not isinstance(dimensions, list) or not dimensions or any(not isinstance(item, str) for item in dimensions):
        raise ShadowError("comparison_dimensions must be a non-empty string array")
    parity_paths = sorted(Path(path) for path in glob.glob(str(work_dir / "*-parity.json")))
    parity_paths.extend(Path(path) for path in glob.glob(str(work_dir / "typed-cohorts" / "*-parity.json")))
    parity_reports = [load(path) for path in sorted(set(parity_paths))]
    if not parity_reports or any(report.get("state") != "shadow_verified" for report in parity_reports):
        raise ShadowError("all projection parity reports must be shadow_verified")
    row_coverage = load(work_dir / "row-coverage.json")
    if row_coverage.get("state") != "row_coverage_verified":
        raise ShadowError("row coverage is not verified")
    reconciliation_paths = sorted(Path(path) for path in glob.glob(str(work_dir / "*-reconciliation.json")))
    reconciliations = [load(path) for path in reconciliation_paths]
    if not reconciliations or any(
        item.get("state") != "reconciled"
        or item.get("cash_released") is not False
        or item.get("period_posted") is not False
        for item in reconciliations
    ):
        raise ShadowError("accounting reconciliation evidence is missing or has external effects")
    acceptance = load(work_dir / "business-acceptance.json")
    if acceptance.get("format") != "moonproj.erp.business-acceptance-result.v1":
        raise ShadowError("business acceptance packet is missing or invalid")
    shadow_decision = None
    for decision in acceptance.get("decisions", []):
        if isinstance(decision, dict) and decision.get("id") == "shadow-period":
            shadow_decision = decision.get("decision")
    shadow_authorized = shadow_decision == "accept_for_shadow"
    return {
        "format": "moonproj.company.shadow-period-result.v1",
        "period_id": manifest["period_id"],
        "state": "shadow_ready" if shadow_authorized else "shadow_pending_owner",
        "legacy_authoritative": True,
        "target_mode": "read_only_shadow",
        "target_mutations_allowed": False,
        "duration_days": duration_days,
        "comparison_interval_hours": comparison_interval_hours,
        "comparison_dimensions": dimensions,
        "parity_report_count": len(parity_reports),
        "reconciliation_report_count": len(reconciliations),
        "source_rows": row_coverage.get("source_rows"),
        "covered_rows": row_coverage.get("covered_rows"),
        "owner_role": manifest["owner_role"],
        "rollback_runbook": manifest["rollback_runbook"],
        "shadow_authorized": shadow_authorized,
        "cutover_authorized": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.work_dir, load(args.manifest))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "state": result["state"],
            "shadow_authorized": result["shadow_authorized"],
            "target_mutations_allowed": result["target_mutations_allowed"],
        }, sort_keys=True))
        return 0
    except (OSError, ShadowError, TypeError, ValueError) as error:
        print(f"shadow-period check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
