#!/usr/bin/env python3
"""Compile a reviewed marketing campaign/placement map into a native plan.

Channel and material rows remain catalog evidence. The plan never authorizes a
provider call, budget consumption, cash movement, or accounting posting.
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
        raise PlanError("marketing map is not an object")
    return value


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


def reject_secrets(value: Any, path: str = "mapping") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise PlanError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def source_fields(value: dict[str, Any], label: str) -> dict[str, str]:
    return {
        "source_table": string(value.get("source_table"), f"{label}.source_table"),
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
        if config.get("format") != "moonproj.erp.marketing-cohort-map.v1":
            raise PlanError("unexpected marketing map format")
        if config.get("reviewed") is not True:
            raise PlanError("marketing map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        campaign = obj(config.get("campaign"), "campaign")
        placement = obj(config.get("placement"), "placement")
        channel = obj(config.get("channel"), "channel")
        material = obj(config.get("material"), "material")
        if string(campaign.get("expected_state"), "campaign.expected_state") != "completed":
            raise PlanError("campaign.expected_state must be completed")
        if string(placement.get("expected_state"), "placement.expected_state") != "placed":
            raise PlanError("placement.expected_state must be placed")
        if string(channel.get("evidence_state"), "channel.evidence_state") != "catalog_evidence_only":
            raise PlanError("channel must remain catalog_evidence_only")
        if string(material.get("evidence_state"), "material.evidence_state") != "catalog_evidence_only":
            raise PlanError("material must remain catalog_evidence_only")
        campaign_id = string(campaign.get("campaign_id"), "campaign.campaign_id")
        placement_campaign_id = string(placement.get("campaign_id", campaign_id), "placement.campaign_id")
        if placement_campaign_id != campaign_id:
            raise PlanError("placement.campaign_id differs from campaign")
        budget = integer(campaign.get("budget_amount_minor"), "campaign.budget_amount_minor", 1)
        spend = integer(campaign.get("spend_amount_minor"), "campaign.spend_amount_minor", 1)
        placement_amount = integer(placement.get("amount_minor"), "placement.amount_minor", 1)
        if spend > budget or placement_amount > budget or placement_amount != spend:
            raise PlanError("marketing spend/placement amount exceeds or differs from budget map")
        currency = string(campaign.get("currency"), "campaign.currency")
        if string(placement.get("currency", currency), "placement.currency") != currency:
            raise PlanError("placement currency differs from campaign")
        leads = integer(placement.get("leads"), "placement.leads")
        plan = {
            "format": "moonproj.erp.marketing-cohort-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "campaign": {
                **source_fields(campaign, "campaign"),
                "campaign_id": campaign_id,
                "principal_id": string(campaign.get("principal_id"), "campaign.principal_id"),
                "project_scope": string(campaign.get("project_scope"), "campaign.project_scope"),
                "name": string(campaign.get("name"), "campaign.name"),
                "budget_amount_minor": budget,
                "spend_amount_minor": spend,
                "currency": currency,
            },
            "placement": {
                **source_fields(placement, "placement"),
                "placement_id": string(placement.get("placement_id"), "placement.placement_id"),
                "campaign_id": campaign_id,
                "channel": string(placement.get("channel"), "placement.channel"),
                "amount_minor": placement_amount,
                "currency": currency,
                "leads": leads,
            },
            "channel": {
                **source_fields(channel, "channel"),
                "channel_id": string(channel.get("channel_id"), "channel.channel_id"),
                "channel_code": string(channel.get("channel_code"), "channel.channel_code"),
                "name": string(channel.get("name"), "channel.name"),
                "evidence_state": "catalog_evidence_only",
            },
            "material": {
                **source_fields(material, "material"),
                "material_id": string(material.get("material_id"), "material.material_id"),
                "material_code": string(material.get("material_code"), "material.material_code"),
                "name": string(material.get("name"), "material.name"),
                "evidence_state": "catalog_evidence_only",
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "items": 4}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"marketing cohort plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
