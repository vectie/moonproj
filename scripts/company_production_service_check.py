#!/usr/bin/env python3
"""Validate the credential-free production company-service boundary.

The PostgreSQL adapters and read-model server are development/rehearsal
components. This check validates the service contract that must sit in front of
the managed database: bounded pool reuse, authenticated HTTPS termination,
fixed read endpoints, no arbitrary SQL, and operational telemetry. It never
reads a DSN or secret and it cannot authorize deployment without the separate
database deployment gate.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class ServiceError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private[_-]?key|credential", re.IGNORECASE)
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,127}$")
READ_ENDPOINTS = {
    "/api/health",
    "/api/company/summary",
    "/api/company/receipts",
    "/api/company/projections",
}


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ServiceError(f"cannot read JSON: {path}") from error


def obj(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ServiceError(f"{name} must be an object")
    return value


def required(value: dict[str, Any], key: str) -> str:
    item = value.get(key)
    if not isinstance(item, str) or not item.strip():
        raise ServiceError(f"missing non-empty string: {key}")
    return item.strip()


def positive_int(value: dict[str, Any], key: str, *, maximum: int) -> int:
    item = value.get(key)
    if isinstance(item, bool) or not isinstance(item, int) or item <= 0:
        raise ServiceError(f"{key} must be a positive integer")
    if item > maximum:
        raise ServiceError(f"{key} exceeds {maximum}")
    return item


def reject_secrets(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)) and key not in {"token_env"}:
                raise ServiceError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")
    elif isinstance(value, str):
        lowered = value.lower()
        if "postgres://" in lowered or "postgresql://" in lowered or "mysql://" in lowered:
            raise ServiceError(f"raw database DSN is not allowed at {path}")


def validate(service: Any, deployment_gate: Any) -> dict[str, Any]:
    root = obj(service, "service manifest")
    reject_secrets(root)
    if root.get("format") != "moonproj.company.production-service.v1":
        raise ServiceError("unsupported service manifest format")
    if root.get("environment") != "production":
        raise ServiceError("service environment must be production")

    database = obj(root.get("database"), "database")
    if database.get("engine") != "postgresql":
        raise ServiceError("service database engine must be postgresql")
    required(database, "deployment_gate_artifact")
    pool = obj(database.get("pool"), "database.pool")
    if pool.get("reuse_connections") is not True:
        raise ServiceError("database.pool.reuse_connections must be true")
    max_in_flight = positive_int(pool, "max_in_flight", maximum=256)
    acquire_timeout = positive_int(pool, "acquire_timeout_seconds", maximum=300)
    if pool.get("fail_closed_on_exhaustion") is not True:
        raise ServiceError("pool exhaustion must fail closed")
    health = obj(database.get("health"), "database.health")
    required(health, "readiness_query_name")
    required(health, "migration_schema_version")
    if health.get("readiness_requires_schema_match") is not True:
        raise ServiceError("readiness must require schema-version match")

    http = obj(root.get("http"), "http")
    bind = required(http, "bind_host")
    if bind in {"0.0.0.0", "::", "[::]"}:
        raise ServiceError("service must bind privately behind its gateway")
    required(http, "tls_terminated_by")
    if http.get("forwarded_tls_required") is not True:
        raise ServiceError("forwarded TLS must be required")
    positive_int(http, "request_timeout_seconds", maximum=300)
    positive_int(http, "max_response_rows", maximum=10000)

    auth = obj(http.get("auth"), "http.auth")
    if auth.get("required") is not True:
        raise ServiceError("HTTP authentication must be required")
    token_env = required(auth, "token_env")
    if not ENV_NAME.fullmatch(token_env):
        raise ServiceError("auth.token_env must be an uppercase environment name")
    required(auth, "issuer")
    required(auth, "audience")

    origins = http.get("cors_origins")
    if not isinstance(origins, list) or not origins or any(
        not isinstance(origin, str) or not origin.startswith("https://") or origin == "*"
        for origin in origins
    ):
        raise ServiceError("cors_origins must contain only explicit HTTPS origins")

    endpoints = obj(root.get("endpoints"), "endpoints")
    read_endpoints = endpoints.get("read")
    if not isinstance(read_endpoints, list) or set(read_endpoints) != READ_ENDPOINTS:
        raise ServiceError("read endpoints must match the fixed read-model allow-list")
    mutation_endpoints = endpoints.get("mutation", [])
    if mutation_endpoints != []:
        raise ServiceError("mutation endpoints require a separate command gateway")
    if endpoints.get("arbitrary_sql") is not False:
        raise ServiceError("arbitrary SQL must be disabled")

    observability = obj(root.get("observability"), "observability")
    for key in ("metrics", "audit_log", "alerts", "request_trace"):
        required(observability, key)

    deployment = obj(deployment_gate, "deployment gate")
    if deployment.get("format") != "moonproj.company.production-deployment-gate.v1":
        raise ServiceError("unexpected deployment gate format")
    deployment_authorized = deployment.get("deployment_authorized") is True
    service_authorized = deployment_authorized
    return {
        "format": "moonproj.company.production-service-gate.v1",
        "environment": "production",
        "database_engine": "postgresql",
        "pool": {
            "max_in_flight": max_in_flight,
            "acquire_timeout_seconds": acquire_timeout,
            "fail_closed_on_exhaustion": True,
        },
        "auth_token_env": token_env,
        "read_endpoints": sorted(READ_ENDPOINTS),
        "mutation_endpoints": [],
        "arbitrary_sql": False,
        "deployment_authorized": deployment_authorized,
        "service_authorized": service_authorized,
        "state": "ready_for_production_service"
        if service_authorized
        else "ready_for_service_review",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("service_manifest", type=Path)
    parser.add_argument("deployment_gate", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = validate(load(args.service_manifest), load(args.deployment_gate))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, ServiceError, TypeError, ValueError) as error:
        print(f"production service check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
