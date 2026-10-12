#!/usr/bin/env python3
"""Build MoonProj's source-backed portfolio catalog from authorized PRD exports.

This is an explicit, reviewable snapshot. It does not turn dossier assessments
into runtime verification or company facts.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--requirements", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    dossier = json.loads(args.evidence.read_text(encoding="utf-8"))
    if dossier.get("schema") != "opc-prd-evidence-dossier.v1":
        raise SystemExit("Unexpected consolidated evidence schema")
    with args.requirements.open(encoding="utf-8-sig", newline="") as source:
        requirements = list(csv.DictReader(source))
    if len(dossier["products"]) != 26 or len(requirements) != 447:
        raise SystemExit("Source inventory does not match the reviewed 26/447 snapshot")
    by_product = {}
    for requirement in requirements:
        by_product.setdefault(requirement["Product"], []).append(requirement)
    role_intent = {
        "MoonDesk": {
            "role": "Quick prototyping: turn an idea or source into an inspectable artifact and review package.",
            "status": "User-directed intent; end-to-end promotion not yet verified",
            "handoff": "Inspectable prototype → evidence-bound MoonProj proposal or project decision",
        },
        "MoonProj": {
            "role": "Top-down management: set company goals, constraints, commitments, authority and review decisions.",
            "status": "User-directed intent; full company loop not yet verified",
            "handoff": "Owner decision → bounded work; reviewed result → next experiment",
        },
        "MoonTown": {
            "role": "Bottom-up emergence: surface book and worker observations as reviewable opportunities and dissent.",
            "status": "User-directed intent; live cross-product promotion not yet verified",
            "handoff": "Emerging opportunity → MoonProj owner decision queue",
        },
    }
    products = []
    for entry in dossier["products"]:
        name = entry["name"]
        rows = by_product.get(name, [])
        if not rows:
            raise SystemExit(f"No requirement rows for {name}")
        products.append({
            "id": entry["id"],
            "name": name,
            "lifecycle": "retired" if name == "MoonStat" else "active",
            "group": entry["group"],
            "class": entry["class"],
            "maturity_claim": entry["repo_maturity_claim"],
            "users": entry["primary_users"],
            "job": entry["job"],
            "philosophy_recommendation": entry["opc_philosophy_fit"],
            "role_intent": role_intent.get(name),
            "boundaries": entry["interfaces_and_handoffs"][:3],
            "evidence_summary": entry["verified_evidence"][:3],
            "known_gaps": entry["known_gaps"][:3],
            "optimality_assessment": entry["prd_optimality_assessment"],
            "future_recommendations": entry["future_use_cases"][:3],
            "requirements": rows,
        })
    catalog = {
        "schema": "moonproj.portfolio.catalog.v1",
        "source": {
            "evidence_library_file_id": "libfile_f2831aa05e40819184026f9ce4eb82d2",
            "evidence_sha256": hashlib.sha256(args.evidence.read_bytes()).hexdigest(),
            "requirements_library_file_id": "libfile_daaefa906fb08191817c793c27a3090d",
            "requirements_sha256": hashlib.sha256(args.requirements.read_bytes()).hexdigest(),
            "assessed_at": dossier["date"],
            "status": "Author-supplied portfolio dossier and PRD source; current operation not reverified by catalog load",
        },
        "excluded": ["MoonProp", "Mooncake"],
        "aliases": {"MoonMini": "alias, not an active product"},
        "products": products,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(products)} entries, {sum(len(p['requirements']) for p in products)} requirements, {args.output.stat().st_size} bytes")

if __name__ == "__main__":
    main()
