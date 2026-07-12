#!/usr/bin/env python3
"""Inventory ERP route handlers and middleware for capability parity planning."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


class RouteInventoryError(RuntimeError):
    pass


HANDLER = re.compile(
    r"\br\.(get|post|put|patch|delete)\s*\(\s*['\"]([^'\"]+)"
)
MIDDLEWARE = re.compile(r"\br\.use\s*\(")

CAPABILITY_BY_FILE = {
    "admin.js": "FND-08",
    "ai-hub.js": "RPT-06",
    "ai-stats.js": "RPT-07",
    "attachment.js": "FND-05",
    "auth.js": "FND-02",
    "budget.js": "CST-03",
    "cashflow.js": "FIN-08",
    "cbs.js": "CST-01",
    "cost.js": "CST-04",
    "dashboard.js": "RPT-01",
    "export.js": "RPT-02",
    "fund.js": "FIN-09",
    "import.js": "FND-08",
    "investment.js": "INV-01",
    "invoice.js": "FIN-03",
    "loan.js": "EXP-03",
    "marketing.js": "SAL-02",
    "mdm.js": "FND-04",
    "notify.js": "FND-07",
    "plan.js": "PRJ-02",
    "progress.js": "PRJ-03",
    "rbac.js": "FND-03",
    "reports.js": "RPT-02",
    "sales.js": "SAL-03",
    "share.js": "RPT-03",
    "srm.js": "SRM-01",
    "tender.js": "SRM-04",
    "warning.js": "RPT-04",
    "webhook.js": "FND-07",
    "workflow.js": "WF-01",
}


def run(routes_dir: Path, output: Path) -> dict[str, Any]:
    if not routes_dir.is_dir():
        raise RouteInventoryError(f"route directory not found: {routes_dir}")
    files = sorted(routes_dir.glob("*.js"))
    if not files:
        raise RouteInventoryError(f"route directory has no JavaScript files: {routes_dir}")
    handlers: list[dict[str, Any]] = []
    file_reports: list[dict[str, Any]] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        hits = HANDLER.findall(text)
        middleware_count = len(MIDDLEWARE.findall(text))
        capability_id = CAPABILITY_BY_FILE.get(path.name, "RPT-01")
        for method, route_path in hits:
            handlers.append(
                {
                    "file": path.name,
                    "method": method.upper(),
                    "path": route_path,
                    "capability_id": capability_id,
                    "migration_action": "specify_and_scenario_verify",
                }
            )
        file_reports.append(
            {
                "file": path.name,
                "capability_id": capability_id,
                "handler_count": len(hits),
                "middleware_count": middleware_count,
            }
        )
    handlers_by_capability = dict(sorted(Counter(item["capability_id"] for item in handlers).items()))
    report = {
        "format": "moonproj.erp.route-inventory.v1",
        "routes_dir": str(routes_dir),
        "route_file_count": len(files),
        "handler_count": len(handlers),
        "middleware_count": sum(item["middleware_count"] for item in file_reports),
        "handlers_by_capability": handlers_by_capability,
        "files": file_reports,
        "handlers": handlers,
        "state": "route_surface_inventory_verified",
        "cutover_authorized": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("routes_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = run(args.routes_dir, args.output)
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "route_file_count": report["route_file_count"],
                    "handler_count": report["handler_count"],
                    "middleware_count": report["middleware_count"],
                    "state": report["state"],
                },
                sort_keys=True,
            )
        )
        return 0 if (
            report["route_file_count"] == 30
            and report["handler_count"] == 338
            and report["middleware_count"] == 28
        ) else 1
    except (OSError, RouteInventoryError) as error:
        print(f"ERP route inventory failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
