#!/usr/bin/env python3
"""Evaluate migration evidence before any ownership transfer is authorized.

This is a fail-closed decision artifact, not a cutover command. A passing
technical gate produces ``ready_for_business_acceptance`` while leaving
``cutover_authorized`` false until named owners accept the remaining
exceptions and a separate deployment runbook is approved.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any


class GateError(RuntimeError):
    pass


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateError(f"cannot read JSON evidence: {path}") from error
    if not isinstance(value, dict):
        raise GateError(f"evidence is not an object: {path}")
    return value


def check_file(work_dir: Path, name: str) -> dict[str, Any]:
    path = work_dir / name
    value = load(path)
    return {"file": str(path), "state": value.get("state", "unknown"), "value": value}


def database_counts(path: Path) -> dict[str, Any]:
    connection = sqlite3.connect(path)
    try:
        integrity = str(connection.execute("PRAGMA integrity_check").fetchone()[0])
        counts = {
            table: int(connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0])
            for table in (
                "company_record",
                "company_aggregate_projection",
                "company_accounting_event_link",
                "company_migration_receipt",
            )
        }
        schema_version = int(connection.execute("SELECT max(version) FROM company_schema").fetchone()[0])
    finally:
        connection.close()
    return {"integrity": integrity, "schema_version": schema_version, "counts": counts}


def run(
    work_dir: Path,
    output: Path,
    expected_raw: int | None,
    expected_projections: int | None,
    expected_links: int | None,
) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    staging = load(work_dir / "raw-staging.ndjson.manifest.json")
    staged_rows = sum(int(table.get("rows", 0)) for table in staging.get("tables", []))
    checks.append(
        {
            "name": "source_staging",
            "passed": staging.get("format") == "moonproj.erp.raw-staging.v1" and staged_rows > 0,
            "source_sha256": staging.get("source_sha256"),
            "staged_rows": staged_rows,
        }
    )

    schema_gap = load(work_dir / "schema-gap.json")
    checks.append(
        {
            "name": "schema_scope",
            "passed": schema_gap.get("format") == "moonproj.erp.schema-gap.v1"
            and schema_gap.get("schema_tables") == 75
            and schema_gap.get("present_tables") == 26
            and schema_gap.get("schema_only_tables") == 49,
            "state": schema_gap.get("state"),
            "schema_tables": schema_gap.get("schema_tables"),
            "present_tables": schema_gap.get("present_tables"),
            "schema_only_tables": schema_gap.get("schema_only_tables"),
        }
    )

    export_contract_path = work_dir / "source-export-contract.json"
    if export_contract_path.is_file():
        export_contract = load(export_contract_path)
        checks.append(
            {
                "name": "source_export_contract",
                "passed": export_contract.get("format") == "moonproj.erp.export-contract.v1"
                and export_contract.get("content_verified") is True
                and export_contract.get("schema_tables") == 75
                and export_contract.get("export_tables") == 26
                and export_contract.get("present_tables") == 26
                and len(export_contract.get("missing_tables", [])) == 49
                and export_contract.get("promotion_authorized") is False,
                "state": export_contract.get("state"),
                "schema_tables": export_contract.get("schema_tables"),
                "export_tables": export_contract.get("export_tables"),
                "missing_tables": len(export_contract.get("missing_tables", [])),
                "verified_rows": export_contract.get("verified_rows"),
            }
        )

    source_request_path = work_dir / "source-export-request.json"
    if source_request_path.is_file():
        source_request = load(source_request_path)
        requested_tables = source_request.get("tables", [])
        checks.append(
            {
                "name": "source_export_request",
                "passed": source_request.get("format") == "moonproj.erp.source-export-request.v1"
                and source_request.get("state") == "awaiting_source_export"
                and source_request.get("schema_tables") == 75
                and source_request.get("present_tables") == 26
                and source_request.get("requested_tables") == 49
                and source_request.get("cutover_authorized") is False
                and source_request.get("promotion_authorized") is False
                and isinstance(requested_tables, list)
                and len(requested_tables) == 49,
                "state": source_request.get("state"),
                "requested_tables": source_request.get("requested_tables"),
                "schema_tables": source_request.get("schema_tables"),
                "present_tables": source_request.get("present_tables"),
            }
        )

    schema_cohort_path = work_dir / "schema-cohort-plan.json"
    if schema_cohort_path.is_file():
        schema_cohort = load(schema_cohort_path)
        waves = schema_cohort.get("waves", [])
        checks.append(
            {
                "name": "schema_cohort_plan",
                "passed": schema_cohort.get("format") == "moonproj.erp.schema-cohort-plan.v1"
                and schema_cohort.get("schema_only_tables") == 49
                and isinstance(waves, list)
                and len(waves) == 7
                and schema_cohort.get("cutover_authorized") is False,
                "state": schema_cohort.get("state"),
                "schema_only_tables": schema_cohort.get("schema_only_tables"),
                "wave_count": len(waves) if isinstance(waves, list) else 0,
            }
        )

    foundation_schema_path = work_dir / "schema-foundation-security.json"
    if foundation_schema_path.is_file():
        foundation_schema = load(foundation_schema_path)
        foundation_tables = foundation_schema.get("tables", [])
        checks.append(
            {
                "name": "foundation_security_schema_mapping",
                "passed": foundation_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and foundation_schema.get("wave") == "foundation-security"
                and foundation_schema.get("state") == "mapped_scope_only"
                and foundation_schema.get("mapped_tables") == 6
                and foundation_schema.get("source_rows_available") == 0
                and foundation_schema.get("promotion_authorized") is False
                and isinstance(foundation_tables, list)
                and len(foundation_tables) == 6
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in foundation_tables
                ),
                "state": foundation_schema.get("state"),
                "mapped_tables": foundation_schema.get("mapped_tables"),
                "source_rows_available": foundation_schema.get("source_rows_available"),
                "promotion_authorized": foundation_schema.get("promotion_authorized"),
            }
        )

    workflow_schema_path = work_dir / "schema-workflow-control.json"
    if workflow_schema_path.is_file():
        workflow_schema = load(workflow_schema_path)
        workflow_tables = workflow_schema.get("tables", [])
        checks.append(
            {
                "name": "workflow_control_schema_mapping",
                "passed": workflow_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and workflow_schema.get("wave") == "workflow-control"
                and workflow_schema.get("state") == "mapped_scope_only"
                and workflow_schema.get("mapped_tables") == 7
                and workflow_schema.get("source_rows_available") == 0
                and workflow_schema.get("promotion_authorized") is False
                and isinstance(workflow_tables, list)
                and len(workflow_tables) == 7
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in workflow_tables
                ),
                "state": workflow_schema.get("state"),
                "mapped_tables": workflow_schema.get("mapped_tables"),
                "source_rows_available": workflow_schema.get("source_rows_available"),
                "promotion_authorized": workflow_schema.get("promotion_authorized"),
            }
        )

    cost_schema_path = work_dir / "schema-cost-investment.json"
    if cost_schema_path.is_file():
        cost_schema = load(cost_schema_path)
        cost_tables = cost_schema.get("tables", [])
        checks.append(
            {
                "name": "cost_investment_schema_mapping",
                "passed": cost_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and cost_schema.get("wave") == "cost-investment"
                and cost_schema.get("state") == "mapped_scope_only"
                and cost_schema.get("mapped_tables") == 9
                and cost_schema.get("source_rows_available") == 0
                and cost_schema.get("promotion_authorized") is False
                and isinstance(cost_tables, list)
                and len(cost_tables) == 9
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in cost_tables
                ),
                "state": cost_schema.get("state"),
                "mapped_tables": cost_schema.get("mapped_tables"),
                "source_rows_available": cost_schema.get("source_rows_available"),
                "promotion_authorized": cost_schema.get("promotion_authorized"),
            }
        )

    procurement_schema_path = work_dir / "schema-procurement-contract.json"
    if procurement_schema_path.is_file():
        procurement_schema = load(procurement_schema_path)
        procurement_tables = procurement_schema.get("tables", [])
        checks.append(
            {
                "name": "procurement_contract_schema_mapping",
                "passed": procurement_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and procurement_schema.get("wave") == "procurement-contract"
                and procurement_schema.get("state") == "mapped_scope_only"
                and procurement_schema.get("mapped_tables") == 7
                and procurement_schema.get("source_rows_available") == 0
                and procurement_schema.get("promotion_authorized") is False
                and isinstance(procurement_tables, list)
                and len(procurement_tables) == 7
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in procurement_tables
                ),
                "state": procurement_schema.get("state"),
                "mapped_tables": procurement_schema.get("mapped_tables"),
                "source_rows_available": procurement_schema.get("source_rows_available"),
                "promotion_authorized": procurement_schema.get("promotion_authorized"),
            }
        )

    sales_schema_path = work_dir / "schema-sales-receivables.json"
    if sales_schema_path.is_file():
        sales_schema = load(sales_schema_path)
        sales_tables = sales_schema.get("tables", [])
        checks.append(
            {
                "name": "sales_receivables_schema_mapping",
                "passed": sales_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and sales_schema.get("wave") == "sales-receivables"
                and sales_schema.get("state") == "mapped_scope_only"
                and sales_schema.get("mapped_tables") == 8
                and sales_schema.get("source_rows_available") == 0
                and sales_schema.get("promotion_authorized") is False
                and isinstance(sales_tables, list)
                and len(sales_tables) == 8
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in sales_tables
                ),
                "state": sales_schema.get("state"),
                "mapped_tables": sales_schema.get("mapped_tables"),
                "source_rows_available": sales_schema.get("source_rows_available"),
                "promotion_authorized": sales_schema.get("promotion_authorized"),
            }
        )

    delivery_schema_path = work_dir / "schema-delivery-treasury.json"
    if delivery_schema_path.is_file():
        delivery_schema = load(delivery_schema_path)
        delivery_tables = delivery_schema.get("tables", [])
        checks.append(
            {
                "name": "delivery_treasury_schema_mapping",
                "passed": delivery_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and delivery_schema.get("wave") == "delivery-treasury"
                and delivery_schema.get("state") == "mapped_scope_only"
                and delivery_schema.get("mapped_tables") == 8
                and delivery_schema.get("source_rows_available") == 0
                and delivery_schema.get("promotion_authorized") is False
                and isinstance(delivery_tables, list)
                and len(delivery_tables) == 8
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in delivery_tables
                ),
                "state": delivery_schema.get("state"),
                "mapped_tables": delivery_schema.get("mapped_tables"),
                "source_rows_available": delivery_schema.get("source_rows_available"),
                "promotion_authorized": delivery_schema.get("promotion_authorized"),
            }
        )

    reporting_schema_path = work_dir / "schema-reporting-notification.json"
    if reporting_schema_path.is_file():
        reporting_schema = load(reporting_schema_path)
        reporting_tables = reporting_schema.get("tables", [])
        checks.append(
            {
                "name": "reporting_notification_schema_mapping",
                "passed": reporting_schema.get("format") ==
                "moonproj.erp.schema-cohort-mapping-result.v1"
                and reporting_schema.get("wave") == "reporting-notification"
                and reporting_schema.get("state") == "mapped_scope_only"
                and reporting_schema.get("mapped_tables") == 4
                and reporting_schema.get("source_rows_available") == 0
                and reporting_schema.get("promotion_authorized") is False
                and isinstance(reporting_tables, list)
                and len(reporting_tables) == 4
                and all(
                    isinstance(item, dict) and item.get("promotion_authorized") is False
                    for item in reporting_tables
                ),
                "state": reporting_schema.get("state"),
                "mapped_tables": reporting_schema.get("mapped_tables"),
                "source_rows_available": reporting_schema.get("source_rows_available"),
                "promotion_authorized": reporting_schema.get("promotion_authorized"),
            }
        )

    relationship_audit = load(work_dir / "relationship-audit.json")
    checks.append(
        {
            "name": "relationship_integrity",
            "passed": relationship_audit.get("format") == "moonproj.erp.relationship-audit.v1"
            and relationship_audit.get("state") == "relationship_integrity_verified"
            and relationship_audit.get("relationship_count", 0) > 0
            and relationship_audit.get("orphan_count") == 0,
            "state": relationship_audit.get("state"),
            "relationship_count": relationship_audit.get("relationship_count"),
            "reference_count": relationship_audit.get("reference_count"),
            "orphan_count": relationship_audit.get("orphan_count"),
        }
    )

    route_inventory = load(work_dir / "route-inventory.json")
    checks.append(
        {
            "name": "route_surface_inventory",
            "passed": route_inventory.get("format") == "moonproj.erp.route-inventory.v1"
            and route_inventory.get("state") == "route_surface_inventory_verified"
            and route_inventory.get("route_file_count") == 30
            and route_inventory.get("handler_count") == 338
            and route_inventory.get("middleware_count") == 28,
            "state": route_inventory.get("state"),
            "route_file_count": route_inventory.get("route_file_count"),
            "handler_count": route_inventory.get("handler_count"),
            "middleware_count": route_inventory.get("middleware_count"),
        }
    )

    period_close_path = work_dir / "period-close-control.json"
    if period_close_path.is_file():
        period_close = load(period_close_path)
        checks.append(
            {
                "name": "period_close_control",
                "passed": period_close.get("format") == "moonproj.erp.period-close-control.v1"
                and period_close.get("state") == "ready_for_reconciled_close"
                and isinstance(period_close.get("source_snapshot_id"), str)
                and bool(period_close.get("source_snapshot_id"))
                and isinstance(period_close.get("mapping_versions"), list)
                and bool(period_close.get("mapping_versions"))
                and isinstance(period_close.get("evidence_hash"), str)
                and period_close.get("evidence_hash", "").startswith("sha256:")
                and period_close.get("close_authorized") is False
                and period_close.get("cash_released") is False
                and period_close.get("period_posted") is False
                and period_close.get("link_count", 0) > 0,
                "state": period_close.get("state"),
                "cohort_count": period_close.get("cohort_count"),
                "link_count": period_close.get("link_count"),
                "source_snapshot_id": period_close.get("source_snapshot_id"),
                "evidence_hash": period_close.get("evidence_hash"),
                "close_authorized": period_close.get("close_authorized"),
            }
        )

    database = work_dir / "company.sqlite3"
    counts = database_counts(database)
    count_checks = {
        "company_record": expected_raw,
        "company_aggregate_projection": expected_projections,
        "company_accounting_event_link": expected_links,
    }
    counts_passed = counts["integrity"] == "ok" and counts["schema_version"] == 4
    for table, expected in count_checks.items():
        if expected is not None:
            counts_passed = counts_passed and counts["counts"][table] == expected
    checks.append({"name": "target_database", "passed": counts_passed, **counts})

    backup = check_file(work_dir, "backup-restore.json")
    checks.append({
        "name": "backup_restore",
        "passed": backup["state"] == "backup_restore_verified",
        "state": backup["state"],
    })
    driver = check_file(work_dir, "driver-smoke.json")
    driver_value = driver["value"]
    checks.append({
        "name": "sql_driver",
        "passed": driver["state"] == "driver_transaction_verified" and
        driver_value.get("sql_command_verified") is True and
        driver_value.get("duplicate_rejected") is True,
        "state": driver["state"],
    })

    deployment_path = work_dir / "production-deployment-gate.json"
    if deployment_path.is_file():
        deployment = load(deployment_path)
        deployment_contract_valid = (
            deployment.get("format") == "moonproj.company.production-deployment-gate.v1"
            and deployment.get("state") in {"ready_for_owner_review", "ready_for_managed_deployment"}
        )
        deployment_authorized = deployment.get("deployment_authorized") is True
        checks.append(
            {
                "name": "production_deployment_contract",
                "passed": deployment_contract_valid,
                "state": deployment.get("state"),
                "deployment_authorized": deployment_authorized,
                "missing_approval_roles": deployment.get("missing_approval_roles", []),
            }
        )
    else:
        deployment = None

    service_path = work_dir / "production-service-gate.json"
    if service_path.is_file():
        service = load(service_path)
        service_contract_valid = (
            service.get("format") == "moonproj.company.production-service-gate.v1"
            and service.get("state") in {
                "ready_for_service_review",
                "ready_for_production_service",
            }
            and service.get("arbitrary_sql") is False
            and service.get("mutation_endpoints") == []
        )
        checks.append(
            {
                "name": "production_service_contract",
                "passed": service_contract_valid,
                "state": service.get("state"),
                "service_authorized": service.get("service_authorized") is True,
                "deployment_authorized": service.get("deployment_authorized") is True,
                "read_endpoints": service.get("read_endpoints", []),
            }
        )

    row_coverage_path = work_dir / "row-coverage.json"
    if row_coverage_path.is_file():
        row_coverage = load(row_coverage_path)
        checks.append(
            {
                "name": "row_coverage",
                "passed": row_coverage.get("format") == "moonproj.erp.row-coverage.v1"
                and row_coverage.get("state") == "row_coverage_verified"
                and row_coverage.get("source_rows") == 120
                and row_coverage.get("covered_rows") == 120
                and row_coverage.get("uncovered_rows") == 0
                and not row_coverage.get("uncovered_tables")
                and row_coverage.get("promotion_authorized") is False,
                "state": row_coverage.get("state"),
                "source_rows": row_coverage.get("source_rows"),
                "covered_rows": row_coverage.get("covered_rows"),
                "uncovered_rows": row_coverage.get("uncovered_rows"),
                "uncovered_tables": row_coverage.get("uncovered_tables", []),
            }
        )

    acceptance_path = work_dir / "business-acceptance.json"
    acceptance = None
    if acceptance_path.is_file():
        acceptance = load(acceptance_path)
        checks.append(
            {
                "name": "business_acceptance_packet",
                "passed": acceptance.get("format") == "moonproj.erp.business-acceptance-result.v1"
                and acceptance.get("state") in {"acceptance_pending", "ready_for_shadow"}
                and acceptance.get("required_decisions") == 5
                and acceptance.get("cutover_authorized") is False,
                "state": acceptance.get("state"),
                "required_decisions": acceptance.get("required_decisions"),
                "pending_decisions": acceptance.get("pending_decisions", []),
                "deferred_decisions": acceptance.get("deferred_decisions", []),
                "acceptance_authorized": acceptance.get("acceptance_authorized"),
                "shadow_authorized": acceptance.get("shadow_authorized"),
            }
        )

    shadow_path = work_dir / "shadow-period.json"
    shadow = None
    if shadow_path.is_file():
        shadow = load(shadow_path)
        checks.append(
            {
                "name": "shadow_period_contract",
                "passed": shadow.get("format") == "moonproj.company.shadow-period-result.v1"
                and shadow.get("state") in {"shadow_pending_owner", "shadow_ready"}
                and shadow.get("legacy_authoritative") is True
                and shadow.get("target_mode") == "read_only_shadow"
                and shadow.get("target_mutations_allowed") is False
                and shadow.get("cutover_authorized") is False
                and shadow.get("parity_report_count", 0) > 0
                and shadow.get("source_rows") == shadow.get("covered_rows"),
                "state": shadow.get("state"),
                "period_id": shadow.get("period_id"),
                "legacy_authoritative": shadow.get("legacy_authoritative"),
                "target_mutations_allowed": shadow.get("target_mutations_allowed"),
                "shadow_authorized": shadow.get("shadow_authorized"),
                "parity_report_count": shadow.get("parity_report_count"),
            }
        )

    parity_paths = sorted(work_dir.glob("*-parity.json"))
    parity_paths.extend(sorted((work_dir / "typed-cohorts").glob("*-parity.json")))
    parity_paths = sorted(set(parity_paths))
    parity_reports: list[dict[str, Any]] = []
    for path in parity_paths:
        report = load(path)
        parity_reports.append({
            "file": str(path),
            "mapping_version": report.get("mapping_version"),
            "state": report.get("state"),
            "expected_items": report.get("expected_items"),
            "actual_items": report.get("actual_items"),
        })
    checks.append({
        "name": "projection_parity",
        "passed": bool(parity_reports) and all(item["state"] == "shadow_verified" for item in parity_reports),
        "reports": parity_reports,
    })

    exception_review_path = work_dir / "typed-cohorts" / "task-state-exception-review.json"
    if exception_review_path.is_file():
        exception_review = load(exception_review_path)
        review_exceptions = exception_review.get("exceptions", [])
        checks.append(
            {
                "name": "task_state_exception_review",
                "passed": exception_review.get("format") == "moonproj.erp.task-state-exception-review.v1"
                and exception_review.get("state") == "review_required"
                and isinstance(review_exceptions, list)
                and bool(review_exceptions)
                and all(item.get("decision") is None for item in review_exceptions if isinstance(item, dict)),
                "state": exception_review.get("state"),
                "exception_count": len(review_exceptions) if isinstance(review_exceptions, list) else 0,
            }
        )

    replay_paths = [
        work_dir / "projection-replay.json",
        work_dir / "advance-offset-projection-replay.json",
        work_dir / "accounting-link-replay.json",
        work_dir / "advance-offset-accounting-link-replay.json",
        work_dir / "payment-accounting-link-replay.json",
        work_dir / "cbs-cost-link-replay.json",
        work_dir / "workflow-assignment-replay.json",
        work_dir / "delivery-progress-replay.json",
    ]
    replay_paths.extend(sorted((work_dir / "typed-cohorts").glob("*-projection-replay.json")))
    replay_values: list[dict[str, Any]] = []
    for path in replay_paths:
        if not path.is_file():
            continue
        value = load(path)
        replay_values.append({
            "file": str(path),
            "inserted_projections": value.get("inserted_projections", 0),
            "inserted_accounting_links": value.get("inserted_accounting_links", 0),
            "receipt_inserted": value.get("receipt_inserted"),
        })
    checks.append({
        "name": "replay_idempotency",
        "passed": bool(replay_values) and all(
            value.get("inserted_projections", 0) == 0 and
            value.get("inserted_accounting_links", 0) == 0 and
            value.get("receipt_inserted") is False
            for value in replay_values
        ),
        "evidence": replay_values,
    })

    reconciliation_paths = [
        work_dir / "accounting-reconciliation.json",
        work_dir / "advance-offset-accounting-reconciliation.json",
        work_dir / "payment-accounting-reconciliation.json",
    ]
    reconciliation_values: list[dict[str, Any]] = []
    for path in reconciliation_paths:
        if not path.is_file():
            continue
        value = load(path)
        reconciliation_values.append({
            "file": str(path),
            "state": value.get("state"),
            "link_count": value.get("link_count"),
            "cash_released": value.get("cash_released"),
            "period_posted": value.get("period_posted"),
        })
    checks.append({
        "name": "accounting_reconciliation",
        "passed": bool(reconciliation_values) and all(
            value["state"] == "reconciled" and
            value["cash_released"] is False and
            value["period_posted"] is False
            for value in reconciliation_values
        ),
        "evidence": reconciliation_values,
    })

    deployment_reason = (
        "managed deployment contract is not owner-approved"
        if deployment is not None
        else "managed pooling, encryption, retention, and restore runbook are not approved"
    )
    exceptions = [
        {
            "id": "task-state-proj-0001",
            "severity": "business_review",
            "state": "quarantined",
            "reason": "two child task states conflict with the parent dependency invariant",
        },
        {
            "id": "production-database-deployment",
            "severity": "operational",
            "state": "open",
            "reason": deployment_reason,
        },
        {
            "id": "erp-schema-coverage",
            "severity": "scope",
            "state": "open",
            "reason": "the fixture contains 26 of 75 ERP schema tables; 49 schema-only tables require later cohorts",
        },
    ]
    if acceptance is None or acceptance.get("state") != "ready_for_shadow":
        exceptions.append(
            {
                "id": "business-acceptance",
                "severity": "owner_review",
                "state": "open",
                "reason": "required business, finance, migration-owner, and operations decisions are not complete",
            }
        )
    if shadow is None or shadow.get("state") != "shadow_ready":
        exceptions.append(
            {
                "id": "shadow-period",
                "severity": "owner_review",
                "state": "open",
                "reason": "read-only shadow contract is defined but operations has not authorized the shadow period",
            }
        )
    technical_passed = all(bool(check.get("passed")) for check in checks)
    report = {
        "format": "moonproj.erp.cutover-gate.v1",
        "work_dir": str(work_dir),
        "state": "ready_for_business_acceptance" if technical_passed else "blocked_by_technical_checks",
        "technical_checks_passed": technical_passed,
        "cutover_authorized": False,
        "checks": checks,
        "exceptions": exceptions,
        "next_actions": [
            "obtain named business, accounting, and operations acceptance",
            "resolve or explicitly waive the proj-0001 task-state exception",
            "approve managed database deployment and rollback runbook",
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--expected-raw", type=int, default=None)
    parser.add_argument("--expected-projections", type=int, default=None)
    parser.add_argument("--expected-links", type=int, default=None)
    args = parser.parse_args()
    try:
        report = run(
            args.work_dir,
            args.output,
            args.expected_raw,
            args.expected_projections,
            args.expected_links,
        )
        print(json.dumps({"output": str(args.output), "state": report["state"], "technical_checks_passed": report["technical_checks_passed"]}, sort_keys=True))
        return 0 if report["technical_checks_passed"] else 1
    except (OSError, GateError, sqlite3.Error) as error:
        print(f"company cutover gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
