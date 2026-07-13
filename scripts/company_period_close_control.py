#!/usr/bin/env python3
"""Build a fail-closed period-close control from reconciled cohorts.

This is a readiness artifact, not a posting command. A target accounting book
must still call the native `AccountingBook.close_reconciled` API under local
authority after the named period owner accepts the report.
"""

from __future__ import annotations

import argparse
import hashlib
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
    if not period_id.strip():
        raise PeriodCloseError("period_id must be non-empty")
    paths = sorted(work_dir.glob("*-reconciliation.json"))
    if not paths:
        raise PeriodCloseError("no accounting reconciliation cohorts found")
    cohorts_by_identity: dict[tuple[str, str], dict[str, Any]] = {}
    source_snapshots: set[str] = set()
    mapping_versions: set[str] = set()
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
        source_snapshot_id = value.get("source_snapshot_id")
        mapping_version = value.get("mapping_version")
        if not isinstance(source_snapshot_id, str) or not source_snapshot_id.strip():
            raise PeriodCloseError(f"reconciliation has no source snapshot: {path}")
        if not isinstance(mapping_version, str) or not mapping_version.strip():
            raise PeriodCloseError(f"reconciliation has no mapping version: {path}")
        link_count = int(value.get("link_count", 0))
        if link_count <= 0:
            raise PeriodCloseError(f"empty reconciliation cohort: {path}")
        source_snapshots.add(source_snapshot_id)
        mapping_versions.add(mapping_version)
        identity = (source_snapshot_id, mapping_version)
        backend = value.get("backend", "sqlite")
        if not isinstance(backend, str) or not backend.strip():
            raise PeriodCloseError(f"reconciliation has no backend: {path}")
        existing = cohorts_by_identity.get(identity)
        if existing is None:
            cohorts_by_identity[identity] = {
                "file": str(path),
                "files": [str(path)],
                "backends": [backend],
                "source_snapshot_id": source_snapshot_id,
                "mapping_version": mapping_version,
                "link_count": link_count,
                "state": value.get("state"),
            }
        else:
            if existing["link_count"] != link_count or existing["state"] != value.get("state"):
                raise PeriodCloseError(
                    "duplicate backend reconciliation disagrees at "
                    f"{source_snapshot_id}:{mapping_version}"
                )
            existing["files"].append(str(path))
            if backend not in existing["backends"]:
                existing["backends"].append(backend)
    cohorts = list(cohorts_by_identity.values())
    total_links = sum(int(cohort["link_count"]) for cohort in cohorts)
    if len(source_snapshots) != 1:
        raise PeriodCloseError("reconciliation cohorts come from different source snapshots")
    evidence = json.dumps(
        [
            {
                "source_snapshot_id": cohort["source_snapshot_id"],
                "mapping_version": cohort["mapping_version"],
                "link_count": cohort["link_count"],
                "state": cohort["state"],
                "backends": sorted(cohort["backends"]),
            }
            for cohort in cohorts
        ],
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    evidence_hash = "sha256:" + hashlib.sha256(evidence).hexdigest()
    report = {
        "format": "moonproj.erp.period-close-control.v1",
        "period_id": period_id,
        "source_snapshot_id": next(iter(source_snapshots)),
        "mapping_versions": sorted(mapping_versions),
        "cohort_count": len(cohorts),
        "link_count": total_links,
        "evidence_hash": evidence_hash,
        "cohorts": cohorts,
        "state": "ready_for_reconciled_close",
        "close_authorized": False,
        "cash_released": False,
        "period_posted": False,
        "close_requires": [
            "named period owner approval",
            "native AccountingBook.close_reconciled",
            "rollback evidence retained",
        ],
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
                    "evidence_hash": report["evidence_hash"],
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
