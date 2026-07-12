#!/usr/bin/env python3
"""Validate the credential-free managed-production deployment contract.

This check validates the operational shape required to promote the local SQL
and backup rehearsals to a managed service. It deliberately accepts only an
environment-variable reference for the database DSN and never reads or emits
the secret value. A structurally complete manifest is still not deployment
authorization until the named owners approve it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class DeploymentError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private[_-]?key|credential", re.IGNORECASE)
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,127}$")
REQUIRED_APPROVAL_ROLES = {"operations", "security", "finance"}


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DeploymentError(f"cannot read deployment manifest: {path}") from error


def object_value(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DeploymentError(f"{name} must be an object")
    return value


def required_string(obj: dict[str, Any], key: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        raise DeploymentError(f"missing non-empty string: {key}")
    return value.strip()


def positive_int(obj: dict[str, Any], key: str, *, allow_zero: bool = False) -> int:
    value = obj.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise DeploymentError(f"{key} must be an integer")
    if value < 0 or (value == 0 and not allow_zero):
        raise DeploymentError(f"{key} must be positive")
    return value


def reject_secrets(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise DeploymentError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")
    elif isinstance(value, str):
        lowered = value.lower()
        if "postgres://" in lowered or "postgresql://" in lowered or "mysql://" in lowered:
            raise DeploymentError(f"raw database DSN is not allowed at {path}")


def validate(manifest: Any) -> dict[str, Any]:
    root = object_value(manifest, "manifest")
    reject_secrets(root)
    if root.get("format") != "moonproj.company.production-deployment.v1":
        raise DeploymentError("unsupported deployment manifest format")
    if root.get("environment") != "production":
        raise DeploymentError("environment must be production")

    database = object_value(root.get("database"), "database")
    engine = required_string(database, "engine").lower()
    if engine != "postgresql":
        raise DeploymentError("Moonproj production engine must be postgresql")
    dsn_env = required_string(database, "dsn_env")
    if not ENV_NAME.fullmatch(dsn_env):
        raise DeploymentError("dsn_env must be an uppercase environment-variable name")
    pool = object_value(database.get("pool"), "database.pool")
    pool_min = positive_int(pool, "min", allow_zero=True)
    pool_max = positive_int(pool, "max")
    if pool_max < pool_min:
        raise DeploymentError("database.pool.max must be >= database.pool.min")
    acquire_timeout = positive_int(pool, "acquire_timeout_seconds")
    if acquire_timeout > 300:
        raise DeploymentError("database.pool.acquire_timeout_seconds exceeds 300")
    tls = object_value(database.get("tls"), "database.tls")
    if tls.get("required") is not True or tls.get("verify_server_certificate") is not True:
        raise DeploymentError("database TLS must be required with certificate verification")
    encryption = object_value(database.get("encryption_at_rest"), "database.encryption_at_rest")
    required_string(encryption, "provider")
    required_string(encryption, "key_management")

    backup = object_value(root.get("backup"), "backup")
    required_string(backup, "schedule")
    retention_days = positive_int(backup, "retention_days")
    required_string(backup, "destination")
    required_string(backup, "encryption")
    if backup.get("cross_region") is not True:
        raise DeploymentError("backup.cross_region must be true")

    restore = object_value(root.get("restore"), "restore")
    rpo_minutes = positive_int(restore, "rpo_minutes", allow_zero=True)
    rto_minutes = positive_int(restore, "rto_minutes")
    required_string(restore, "verification_command")
    required_string(restore, "runbook")

    operations = object_value(root.get("operations"), "operations")
    required_string(operations, "migration_lock")
    required_string(operations, "rollback_runbook")
    observability = object_value(operations.get("observability"), "operations.observability")
    required_string(observability, "metrics")
    required_string(observability, "audit_log")
    required_string(observability, "alerts")

    approvals = object_value(root.get("approvals"), "approvals")
    required_roles = REQUIRED_APPROVAL_ROLES
    approved_roles_value = approvals.get("approved_roles", [])
    if not isinstance(approved_roles_value, list) or any(
        not isinstance(role, str) for role in approved_roles_value
    ):
        raise DeploymentError("approvals.approved_roles must be an array of strings")
    if any(role not in required_roles for role in approved_roles_value):
        raise DeploymentError("approvals.approved_roles contains an unknown role")
    records = approvals.get("records", [])
    if not isinstance(records, list):
        raise DeploymentError("approvals.records must be an array")
    record_roles: set[str] = set()
    approved_roles: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            raise DeploymentError("approval record must be an object")
        role = required_string(record, "role")
        if role not in required_roles:
            raise DeploymentError(f"approval record has unknown role: {role}")
        if role in record_roles:
            raise DeploymentError(f"duplicate approval record: {role}")
        record_roles.add(role)
        decision = required_string(record, "decision")
        if decision != "approve":
            continue
        for field in ("actor_id", "decided_at", "rationale"):
            required_string(record, field)
        evidence_refs = record.get("evidence_refs")
        if not isinstance(evidence_refs, list) or not evidence_refs or any(
            not isinstance(ref, str) or not ref.strip() for ref in evidence_refs
        ):
            raise DeploymentError(f"approval record requires evidence_refs: {role}")
        approved_roles.add(role)
    # A role-name list is retained for backwards-readable manifests but cannot
    # authorize anything unless the structured records corroborate it.
    if set(approved_roles_value) - record_roles:
        raise DeploymentError("approved_roles must be backed by approval records")
    missing_roles = sorted(required_roles - approved_roles)

    return {
        "format": "moonproj.company.production-deployment-gate.v1",
        "environment": "production",
        "engine": engine,
        "dsn_env": dsn_env,
        "pool": {"min": pool_min, "max": pool_max, "acquire_timeout_seconds": acquire_timeout},
        "backup": {"retention_days": retention_days, "cross_region": True},
        "restore": {"rpo_minutes": rpo_minutes, "rto_minutes": rto_minutes},
        "required_approval_roles": sorted(required_roles),
        "missing_approval_roles": missing_roles,
        "approval_record_roles": sorted(record_roles),
        "deployment_authorized": not missing_roles,
        "state": "ready_for_managed_deployment" if not missing_roles else "ready_for_owner_review",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = validate(load(args.manifest))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, DeploymentError, TypeError, ValueError) as error:
        print(f"production deployment check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
