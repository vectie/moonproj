#!/usr/bin/env python3
"""Compile a reviewed contract-milestone/settlement map into a native plan.

This boundary exercises the target lifecycle after source translation has been
reviewed.  It preserves commitment, milestone, and settlement identities while
refusing to infer payment approval, cash release, accounting, or period close.
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
        raise PlanError("contract milestone map is not an object")
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


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PlanError(f"{label} must be an integer >= {minimum}")
    return value


def obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PlanError(f"{label} must be an object")
    return value


def source_fields(value: dict[str, Any], label: str, expected_table: str) -> dict[str, str]:
    table = string(value.get("source_table"), f"{label}.source_table")
    if table != expected_table:
        raise PlanError(f"{label}.source_table must be {expected_table}")
    return {
        "source_table": table,
        "source_id": string(value.get("source_id"), f"{label}.source_id"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.contract-milestone-cohort-map.v1":
            raise PlanError("unexpected contract milestone map format")
        if config.get("reviewed") is not True:
            raise PlanError("contract milestone map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")

        commitment = obj(config.get("commitment"), "commitment")
        milestone = obj(config.get("milestone"), "milestone")
        settlement = obj(config.get("settlement"), "settlement")
        commitment_source = source_fields(commitment, "commitment", "cb_contract")
        milestone_source = source_fields(milestone, "milestone", "cb_htfkplan")
        settlement_source = source_fields(settlement, "settlement", "cb_htfk_apply")

        commitment_id = string(commitment.get("commitment_id"), "commitment.commitment_id")
        principal_id = string(commitment.get("principal_id"), "commitment.principal_id")
        project_scope = string(commitment.get("project_scope"), "commitment.project_scope")
        counterparty_id = string(commitment.get("counterparty_id"), "commitment.counterparty_id")
        commitment_amount = integer(
            commitment.get("amount_minor"), "commitment.amount_minor", 1
        )
        currency = string(commitment.get("currency"), "commitment.currency")
        if string(commitment.get("expected_state"), "commitment.expected_state") != "performed":
            raise PlanError("commitment.expected_state must be performed")

        if string(milestone.get("expected_state"), "milestone.expected_state") != "reached":
            raise PlanError("milestone.expected_state must be reached")
        milestone_id = string(milestone.get("milestone_id"), "milestone.milestone_id")
        if string(milestone.get("commitment_id"), "milestone.commitment_id") != commitment_id:
            raise PlanError("milestone.commitment_id differs from commitment")
        sequence = integer(milestone.get("sequence"), "milestone.sequence", 1)
        node_name = string(milestone.get("node_name"), "milestone.node_name")
        trigger = string(milestone.get("trigger"), "milestone.trigger")
        if trigger not in {"time", "progress", "event"}:
            raise PlanError("milestone.trigger must be time, progress, or event")
        plan_amount = integer(milestone.get("plan_amount_minor"), "milestone.plan_amount_minor", 1)
        actual_amount = integer(
            milestone.get("actual_amount_minor"), "milestone.actual_amount_minor", 1
        )
        plan_pct_bps = integer(milestone.get("plan_pct_bps"), "milestone.plan_pct_bps")
        if plan_pct_bps > 10000:
            raise PlanError("milestone.plan_pct_bps must be <= 10000")
        if plan_amount > commitment_amount:
            raise PlanError("milestone plan exceeds commitment")
        if actual_amount > plan_amount:
            raise PlanError("milestone actual exceeds plan")
        if string(milestone.get("currency", currency), "milestone.currency") != currency:
            raise PlanError("milestone currency differs from commitment")

        if string(settlement.get("expected_state"), "settlement.expected_state") != "requested":
            raise PlanError("settlement.expected_state must be requested")
        settlement_id = string(settlement.get("settlement_id"), "settlement.settlement_id")
        if string(settlement.get("commitment_id"), "settlement.commitment_id") != commitment_id:
            raise PlanError("settlement.commitment_id differs from commitment")
        if string(settlement.get("milestone_id"), "settlement.milestone_id") != milestone_id:
            raise PlanError("settlement.milestone_id differs from milestone")
        if integer(settlement.get("amount_minor"), "settlement.amount_minor", 1) != actual_amount:
            raise PlanError("settlement amount must equal reached milestone actual")
        if string(settlement.get("currency", currency), "settlement.currency") != currency:
            raise PlanError("settlement currency differs from commitment")

        identities = [
            (commitment_source["source_table"], commitment_source["source_id"]),
            (milestone_source["source_table"], milestone_source["source_id"]),
            (settlement_source["source_table"], settlement_source["source_id"]),
        ]
        if len(set(identities)) != len(identities):
            raise PlanError("source identities must be unique")
        targets = [commitment_id, milestone_id, settlement_id]
        if len(set(targets)) != len(targets):
            raise PlanError("target identities must be unique")

        plan = {
            "format": "moonproj.erp.contract-milestone-cohort-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "commitment": {
                **commitment_source,
                "commitment_id": commitment_id,
                "principal_id": principal_id,
                "project_scope": project_scope,
                "counterparty_id": counterparty_id,
                "amount_minor": commitment_amount,
                "currency": currency,
            },
            "milestone": {
                **milestone_source,
                "milestone_id": milestone_id,
                "commitment_id": commitment_id,
                "sequence": sequence,
                "node_name": node_name,
                "trigger": trigger,
                "plan_amount_minor": plan_amount,
                "actual_amount_minor": actual_amount,
                "plan_pct_bps": plan_pct_bps,
                "currency": currency,
            },
            "settlement": {
                **settlement_source,
                "settlement_id": settlement_id,
                "commitment_id": commitment_id,
                "milestone_id": milestone_id,
                "amount_minor": actual_amount,
                "currency": currency,
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps({"output": str(args.output), "items": 3}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"contract milestone cohort plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
