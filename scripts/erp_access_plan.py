#!/usr/bin/env python3
"""Compile a reviewed source role export into an access-import plan.

The source ERP stores permissions as a legacy text field and keeps user-role
assignments in a separate table. This planner refuses to interpret either
shape implicitly: every permission, source data scope, user identity, actor,
assignment cap, and system-role decision must be present in the reviewed map.
Missing schema-only tables are reported as scope-only evidence rather than
invented rows.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)


class AccessPlanError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AccessPlanError(f"cannot read {path}") from error


def reject_secrets(value: Any, path: str = "row") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise AccessPlanError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def rows(export: Path, table: str) -> tuple[list[dict[str, Any]], bool]:
    path = export / "tables" / f"{table}.json"
    if not path.is_file():
        return [], False
    value = load(path)
    if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
        raise AccessPlanError(f"source table is not an object array: {table}")
    return value, True


def text(row: dict[str, Any], key: str) -> str:
    value = row.get(key)
    return value.strip() if isinstance(value, str) else "" if value is None else str(value).strip()


def bool_value(row: dict[str, Any], key: str) -> bool:
    value = row.get(key)
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y"}
    return False


def permission_names(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        result: list[str] = []
        for child in value:
            if isinstance(child, str):
                result.append(child.strip())
            elif isinstance(child, dict):
                for key in ("code", "permission", "name", "capability"):
                    if isinstance(child.get(key), str) and child[key].strip():
                        result.append(child[key].strip())
                        break
        return [item for item in result if item]
    if isinstance(value, dict):
        return [str(key).strip() for key in value if str(key).strip()]
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return []
        try:
            return permission_names(json.loads(raw))
        except json.JSONDecodeError:
            return [item for item in re.split(r"[,;\s]+", raw) if item]
    return []


def permission_candidate(
    source_name: str,
    permission_map: dict[str, Any],
    role_scope: str,
) -> tuple[dict[str, Any] | None, str | None]:
    mapped = permission_map.get(source_name)
    if not isinstance(mapped, dict):
        return None, f"missing_permission_mapping:{source_name}"
    capability = mapped.get("capability")
    scope = mapped.get("scope")
    amount = mapped.get("max_amount_minor")
    if not isinstance(capability, str) or not capability.strip():
        return None, f"missing_permission_capability:{source_name}"
    if scope == "$role_scope":
        scope = role_scope
    if not isinstance(scope, str) or not scope.strip():
        return None, f"missing_permission_scope:{source_name}"
    if isinstance(amount, bool) or not isinstance(amount, int) or amount < 0:
        return None, f"invalid_permission_cap:{source_name}"
    return {
        "capability": capability.strip(),
        "scope": scope.strip(),
        "max_amount_minor": amount,
    }, None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        if not isinstance(manifest, dict) or not isinstance(config, dict):
            raise AccessPlanError("manifest and mapping must be objects")
        if config.get("format") != "moonproj.erp.access-mapping.v1":
            raise AccessPlanError("unsupported access mapping format")
        source_hash = manifest.get("source_sha256")
        if not isinstance(source_hash, str) or not source_hash:
            raise AccessPlanError("source manifest has no source hash")
        role_rows, roles_present = rows(args.export, "sys_role")
        assignment_rows, assignments_present = rows(args.export, "sys_user_role")
        permission_map = config.get("permission_map", {})
        scope_by_role = config.get("scope_by_role", {})
        principal_by_user = config.get("principal_by_user", {})
        actor_by_user = config.get("actor_by_user", {})
        assignment_cap_by_role = config.get("assignment_cap_by_role", {})
        if not all(isinstance(value, dict) for value in (permission_map, scope_by_role, principal_by_user, actor_by_user, assignment_cap_by_role)):
            raise AccessPlanError("access mapping dictionaries are invalid")

        roles: list[dict[str, Any]] = []
        role_reasons: dict[str, list[str]] = {}
        role_scopes: dict[str, str] = {}
        for row in role_rows:
            reject_secrets(row, "sys_role")
            role_code = text(row, "role_code")
            role_name = text(row, "role_name")
            reasons: list[str] = []
            if not role_code or not role_name:
                reasons.append("missing_role_identity")
            role_scope = scope_by_role.get(role_code)
            if not isinstance(role_scope, str) or not role_scope.strip():
                reasons.append("missing_role_scope")
                role_scope = ""
            role_scopes[role_code] = role_scope
            if bool_value(row, "is_system") and config.get("allow_system_roles") is not True:
                reasons.append("system_role_requires_explicit_review")
            permissions: list[dict[str, Any]] = []
            for source_name in permission_names(row.get("permissions")):
                candidate, reason = permission_candidate(source_name, permission_map, role_scope)
                if candidate is None:
                    reasons.append(reason or "invalid_permission")
                else:
                    permissions.append(candidate)
            if not permissions:
                reasons.append("role_has_no_reviewed_permissions")
            if role_code:
                role_reasons[role_code] = reasons
            roles.append({"role_id": role_code, "name": role_name, "permissions": permissions})

        assignments: list[dict[str, Any]] = []
        assignment_reasons: list[str] = []
        for row in assignment_rows:
            reject_secrets(row, "sys_user_role")
            user_id = text(row, "user_id")
            role_code = text(row, "role_code")
            reasons: list[str] = []
            principal_id = principal_by_user.get(user_id)
            actor_id = actor_by_user.get(user_id)
            scope = role_scopes.get(role_code, scope_by_role.get(role_code))
            cap = assignment_cap_by_role.get(role_code)
            if not isinstance(principal_id, str) or not principal_id.strip():
                reasons.append("missing_principal_mapping")
                principal_id = ""
            if not isinstance(actor_id, str) or not actor_id.strip():
                reasons.append("missing_actor_mapping")
                actor_id = ""
            if not isinstance(scope, str) or not scope.strip():
                reasons.append("missing_assignment_scope")
                scope = ""
            if isinstance(cap, bool) or not isinstance(cap, int) or cap < 0:
                reasons.append("missing_assignment_cap")
                cap = 0
            reasons.extend(role_reasons.get(role_code, ["unknown_role_mapping"]))
            if reasons:
                assignment_reasons.extend(f"{user_id}:{role_code}:{reason}" for reason in sorted(set(reasons)))
            assignments.append({
                "assignment_id": f"{user_id}:{role_code}",
                "role_id": role_code,
                "principal_id": principal_id,
                "actor_id": actor_id,
                "scope": scope,
                "max_amount_minor": cap,
                "active": True,
            })
        reasons = sorted(set(assignment_reasons + [reason for values in role_reasons.values() for reason in values]))
        source_rows_available = bool(role_rows or assignment_rows)
        source_tables_present = roles_present or assignments_present
        reviewed = config.get("reviewed") is True and not reasons and source_rows_available
        if not source_rows_available:
            state = "scope_only"
        elif reviewed:
            state = "ready_for_native_import"
        else:
            state = "review_required"
        root_scope = config.get("scope")
        principal_id = config.get("principal_id")
        if not isinstance(root_scope, str) or not root_scope.strip() or not isinstance(principal_id, str) or not principal_id.strip():
            raise AccessPlanError("mapping requires principal_id and scope")
        plan = {
            "format": "moonproj.company.access-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{source_hash}",
            "mapping_version": config.get("mapping_version", "unversioned-access-map"),
            "source_table": "sys_role",
            "source_id": "access-bundle:" + hashlib.sha256(source_hash.encode("utf-8")).hexdigest()[:16],
            "principal_id": principal_id,
            "scope": root_scope,
            "reviewed": reviewed,
            "roles": roles,
            "separation_rules": config.get("separation_rules", []),
            "assignments": assignments,
            "summary": {
                "state": state,
                "roles": len(roles),
                "assignments": len(assignments),
                "quarantine_reasons": reasons,
                "source_rows_available": source_rows_available,
                "source_tables_present": source_tables_present,
                "promotion_authorized": False,
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, AccessPlanError, TypeError, ValueError, KeyError) as error:
        print(f"access promotion plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
