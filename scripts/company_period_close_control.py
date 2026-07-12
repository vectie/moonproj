#!/usr/bin/env python3
"""Build a fail-closed period-close control from reconciled cohorts.

This is a readiness artifact, not a posting command. A target accounting book
must still call the native `AccountingBook.close_reconciled` API under local
authority after the named period owner accepts the report.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PeriodCloseError(RuntimeError):
    pass


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PeriodCloseError(f"cannot read reconciliation evidence: {path}") from error
    if not isinstance(value, dict):
        raise PeriodCloseError(f"reconciliation evidence is not an object: {path}")
    return value


def run(work_dir: Path, output: Path, period_id: str) -> dict[str, Any]:
    paths = sorted(work_dir.glob("*-reconciliation.json"))
    if not paths:
        raise PeriodCloseError("no accounting reconciliation cohorts found")
    cohorts: list[dict[str, Any]] = []
    total_links = 0
    for path in paths:
        value = load(path)
        if value.get("format") != "moonproj.erp.accounting-reconciliation.v1":
            raise PeriodCloseError(f"unexpected reconciliation format: {path}")
        if value.get("state") != "reconciled":
            raise PeriodCloseError(f"unreconciled cohort: {path}")
        if value.get("integrity") != "ok":
            raise PeriodCloseError(f"unhealthy cohort: {path}")
        if value.get("cash_released") is not False or value.get("period_posted") is not False:
            raise PeriodCloseError(f"economic side effect already asserted: {path}")
        link_count = int(value.get("link_count", 0))
        if link_count <= 0:
            raise PeriodCloseError(f"empty reconciliation cohort: {path}")
        total_links += link_count
        cohorts.append(
            {
                "file": str(path),
                "mapping_version": value.get("mapping_version"),
                "link_count": link_count,
                "state": value.get("state"),
            }
        )
    report = {
        "format": "moonproj.erp.period-close-control.v1",
        "period_id": period_id,
        "cohort_count": len(cohorts),
        "link_count": total_links,
        "cohorts": cohorts,
        "state": "ready_for_reconciled_close",
        "close_authorized": False,
        "cash_released": False,
        "period_posted": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--period-id", default="migration-opening")
    args = parser.parse_args()
    try:
        report = run(args.work_dir, args.output, args.period_id)
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "state": report["state"],
                    "cohort_count": report["cohort_count"],
                    "link_count": report["link_count"],
                },
                sort_keys=True,
            )
        )
        return 0
    except (OSError, PeriodCloseError, TypeError, ValueError) as error:
        print(f"period close control failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
