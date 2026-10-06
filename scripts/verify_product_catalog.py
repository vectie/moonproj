#!/usr/bin/env python3
"""Verify the twenty-product catalog, enrollment preservation, and packaged PRD bytes.

Read-only and standard-library-only. Run from any working directory:
  python /path/to/moonproj/scripts/verify_product_catalog.py
Optional --source-workspace checks original PRDs, authored definitions, and receipts.
The original v1 enrollment file is preserved inside the manifest, not expected to
remain live after the intentional catalog schema transition.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ACTIVE = set("moonbook mooncast moonchat moonclaw moondesk moonedit moonfind moonfish moonflow moonfort moongate moonleaf moonlib moonmold moonmoon moonpoly moonproj moonrobo moontown moonvis".split())
ENROLLED = set("moonproj moonbook moonclaw moontown moondesk moongate moonrobo moonmoon moonfish".split())
UNRESOLVED = {"moonfish", "moonpoly", "moonedit", "moonleaf", "moonvis"}
FOUNDER = {
    "moonproj": "Top-down management",
    "moondesk": "Quick prototyping and human interleaving",
    "moontown": "Bottom-up reuse and emergence",
    "moonbook": "Experienced agent and memory",
}
SHA256 = re.compile(r"[a-f0-9]{64}")


def require(condition: bool, message: str):
    if not condition:
        raise ValueError(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keys(value: dict, expected: set[str], context: str):
    require(isinstance(value, dict), context + " must be an object")
    require(set(value) == expected, context + " fields differ: " + str(set(value) ^ expected))


def nonempty(value, context: str):
    require(isinstance(value, str) and bool(value.strip()), context + " must be nonempty text")


def verify(repository: Path, source_workspace: Path | None = None) -> dict:
    repository = repository.resolve(strict=True)
    catalog_path = repository / "config/moonsuite-engineering.json"
    document_root = (repository / "resources/product-documents").resolve(strict=True)
    catalog = json.loads(catalog_path.read_text())
    manifest = json.loads((document_root / "manifest.json").read_text())
    keys(catalog, {"schema", "workspace_root", "policy", "products"}, "catalog")
    require(catalog["schema"] == "moonsuite.product-portfolio.v2", "unsupported catalog schema")
    require(catalog["workspace_root"] == "..", "serving workspace root convention changed")
    require(manifest["schema"] == "moonsuite.product-documents.v1", "unsupported resource manifest")
    require(manifest["catalog_sha256"] == sha256(catalog_path), "catalog hash differs from resource manifest")
    baseline = manifest["original_engineering_portfolio"]
    require(baseline["schema"] == "moonsuite.engineering-portfolio.v1", "missing original enrollment provenance")
    require(catalog["policy"] == baseline["policy"], "engineering policy changed")
    baseline_targets = {row["id"]: row for row in baseline["projects"]}
    require(set(baseline_targets) == ENROLLED and len(baseline["projects"]) == 9, "original nine enrollment set differs")
    rows = catalog["products"]
    require(isinstance(rows, list) and len(rows) == 20, "exactly twenty active definitions required")
    require({row["id"] for row in rows} == ACTIVE, "active identity set changed or duplicate identity")
    assets = manifest["assets"]
    require(len(assets) == 20 and {row["product_id"] for row in assets} == ACTIVE, "asset identity set changed")
    assets_by_id = {asset["product_id"]: asset for asset in assets}
    inventory = manifest["inventory"]
    require(set(inventory["active_product_ids"]) == ACTIVE and len(inventory["active_product_ids"]) == 20, "manifest active coverage differs")
    require(set(inventory["source_manifest_product_ids"]) == ACTIVE - UNRESOLVED, "source-manifest coverage differs")
    require(inventory["configured_only_repository_ids"] == ["moonfish"], "configured target provenance differs")
    require(set(inventory["unknown_repository_ids"]) == UNRESOLVED - {"moonfish"}, "unknown repository coverage differs")
    require(set(inventory["unresolved_in_source_manifest"]) == UNRESOLVED, "unresolved source coverage differs")
    require(set(inventory["excluded_product_ids"]) == {"moonprop", "mooncake"}, "exclusion set differs")
    require(inventory["retired_product_ids"] == ["moonstat"], "retirement set differs")
    require(inventory["infrastructure_outside_product_catalog"] == ["lunanexa"], "infrastructure separation differs")
    library_ids, expected_files, enrolled, total_bytes = set(), {"manifest.json"}, set(), 0
    text_bytes, complete_extractions, partial_extractions = 0, 0, 0
    for row in rows:
        pid = row["id"]
        keys(row, {"id", "name", "product_kind", "purpose", "philosophy", "repository", "engineering_target", "documents", "company_project_id"}, pid)
        require(re.fullmatch(r"[a-z][a-z0-9-]*", pid) is not None, "invalid product identifier")
        for field in ("name", "purpose"):
            nonempty(row[field], pid + "." + field)
        require(row["product_kind"] in {"platform", "desktop", "library", "specialist"}, pid + " unsupported type")
        require(row["company_project_id"] is None, pid + " has an unverified company project relationship")
        philosophy = row["philosophy"]
        keys(philosophy, {"excerpt", "paragraphs", "source_kind", "source", "version", "sha256"}, pid + ".philosophy")
        for field in ("excerpt", "source", "version"):
            nonempty(philosophy[field], pid + ".philosophy." + field)
        require(isinstance(philosophy["paragraphs"], list) and len(philosophy["paragraphs"]) > 0, pid + " missing philosophy")
        for paragraph in philosophy["paragraphs"]:
            nonempty(paragraph, pid + ".philosophy.paragraph")
        require(SHA256.fullmatch(philosophy["sha256"]) is not None, pid + " invalid philosophy hash")
        if pid in FOUNDER:
            require(philosophy["source_kind"] == "founder_intent" and philosophy["excerpt"] == FOUNDER[pid], pid + " founder intent was overridden")
            captured = manifest["founder_direction_capture"]["directions"][pid]
            require(philosophy["excerpt"] == captured["heading"] and philosophy["paragraphs"] == [captured["direction"]], pid + " founder direction differs from its captured provenance")
        else:
            require(philosophy["source_kind"] == "authored_prd", pid + " PRD mislabeled as observed evidence")
        source_path = philosophy["source"].split("#", 1)[0]
        require(manifest["source_file_hashes"][source_path] == philosophy["sha256"], pid + " source provenance hash mismatch")
        repo = row["repository"]
        if pid in UNRESOLVED - {"moonfish"}:
            require(repo is None, pid + " has an invented repository mapping")
        else:
            keys(repo, {"path", "url", "revision", "source_kind"}, pid + ".repository")
            require(repo["path"] == pid, pid + " configured relative repository path changed")
            if pid == "moonfish":
                require(repo["source_kind"] == "configured" and repo["url"] is None and repo["revision"] is None, "MoonFish configured path must not imply a verified origin or revision")
            else:
                require(repo["source_kind"] == "source_manifest", pid + " repository source mislabeled")
                nonempty(repo["url"], pid + " repository origin")
                require(re.fullmatch(r"[a-f0-9]{40}", repo["revision"]) is not None, pid + " invalid source revision")
        target = row["engineering_target"]
        if pid in ENROLLED:
            keys(target, {"id", "lifecycle", "role", "tier"}, pid + ".engineering_target")
            require(target == {key: baseline_targets[pid][key] for key in target}, pid + " enrollment metadata changed")
            require(baseline_targets[pid]["repository"] == "../" + repo["path"], pid + " configured audit target changed")
            enrolled.add(pid)
        else:
            require(target is None, pid + " was silently enrolled for engineering audit")
        require(isinstance(row["documents"], list) and len(row["documents"]) == 1, pid + " needs exactly its declared PRD")
        doc = row["documents"][0]
        keys(doc, {"id", "title", "type", "source_kind", "path", "version", "provenance", "sha256", "size_bytes", "library_file_id", "file_name", "library_captured_version_number"}, pid + ".document")
        require((doc["id"], doc["type"], doc["source_kind"]) == ("prd", "prd", "packaged"), pid + " invalid document declaration")
        filename = row["name"] + "_PRD.docx"
        require(doc["path"] == doc["file_name"] == filename and Path(filename).name == filename, pid + " document path is not its bounded filename")
        document_path = document_root / filename
        require(not document_path.is_symlink(), pid + " resource symlink is not a byte copy")
        resolved = document_path.resolve(strict=True)
        require(resolved.is_relative_to(document_root) and resolved.is_file(), pid + " document leaves approved resource root")
        require(type(doc["size_bytes"]) is int and 0 < doc["size_bytes"] <= 16 * 1024 * 1024, pid + " document size outside bounds")
        require(resolved.stat().st_size == doc["size_bytes"], pid + " document size mismatch")
        require(SHA256.fullmatch(doc["sha256"]) is not None and sha256(resolved) == doc["sha256"], pid + " document hash mismatch")
        require(re.fullmatch(r"libfile_[a-f0-9]{32}", doc["library_file_id"]) is not None, pid + " invalid Library identity")
        require(doc["library_file_id"] not in library_ids, "duplicate Library identity")
        require(type(doc["library_captured_version_number"]) is int and doc["library_captured_version_number"] >= 0, pid + " invalid Library version metadata")
        with zipfile.ZipFile(resolved) as package:
            require(package.testzip() is None, pid + " corrupt document archive")
            require({"[Content_Types].xml", "word/document.xml"} <= set(package.namelist()), pid + " not a DOCX package")
        asset = assets_by_id[pid]
        require(asset["document_id"] == "prd" and asset["path"] == filename, pid + " asset identity mismatch")
        require(asset["source_sha256"] == asset["packaged_sha256"] == doc["sha256"], pid + " PRD source bytes changed")
        require(asset["size_bytes"] == doc["size_bytes"], pid + " manifest size mismatch")
        require(asset["library"] == {"library_file_id": doc["library_file_id"], "file_name": filename, "captured_version_number": doc["library_captured_version_number"], "captured_status": "succeeded", "captured_on": "2026-09-30"}, pid + " Library receipt identity changed")
        require(manifest["source_file_hashes"][asset["source_path"]] == doc["sha256"], pid + " source receipt hash differs")
        require(manifest["source_file_hashes"][asset["definition_path"]] == asset["definition_sha256"], pid + " definition hash differs")
        extraction = asset.get("text_extraction")
        require(isinstance(extraction, dict), pid + " missing declared text extraction")
        keys(extraction, {"schema", "path", "media_type", "source_docx_sha256", "source_docx_size_bytes", "text_sha256", "size_bytes", "extraction_version", "coverage", "limitations", "counts"}, pid + ".text_extraction")
        require(extraction["schema"] == "moonsuite.product-document-text.v1" and extraction["extraction_version"] == "docx-body-v1", pid + " unsupported text extraction")
        relative = extraction["path"]
        require(isinstance(relative, str) and relative and not Path(relative).is_absolute() and "\\" not in relative and all(part not in {"", ".", ".."} for part in relative.split("/")), pid + " invalid text sidecar path")
        text_path = document_root / relative
        require(not text_path.is_symlink() and text_path.resolve().is_relative_to(document_root), pid + " text sidecar escaped resource root")
        require(text_path.is_file(), pid + " missing text sidecar")
        require(extraction["source_docx_sha256"] == doc["sha256"] and extraction["source_docx_size_bytes"] == doc["size_bytes"], pid + " stale text extraction source")
        require(extraction["media_type"] == "text/plain; charset=utf-8", pid + " unsupported text media type")
        require(type(extraction["size_bytes"]) is int and extraction["size_bytes"] == text_path.stat().st_size, pid + " text sidecar size mismatch")
        require(SHA256.fullmatch(extraction["text_sha256"]) is not None and sha256(text_path) == extraction["text_sha256"], pid + " text sidecar hash mismatch")
        text_path.read_text(encoding="utf-8")
        require(extraction["coverage"] in {"complete", "partial"}, pid + " invalid extraction coverage")
        require(isinstance(extraction["limitations"], list) and len(extraction["limitations"]) >= 2, pid + " missing extraction scope/limitations")
        for limitation in extraction["limitations"]:
            nonempty(limitation, pid + ".text_extraction.limitation")
        keys(extraction["counts"], {"paragraphs", "tables", "table_rows", "table_cells"}, pid + ".text_extraction.counts")
        require(all(type(count) is int and count >= 0 for count in extraction["counts"].values()), pid + " invalid extraction counts")
        require(extraction["path"] not in expected_files, pid + " duplicate text resource path")
        expected_files.add(extraction["path"])
        text_bytes += extraction["size_bytes"]
        complete_extractions += extraction["coverage"] == "complete"
        partial_extractions += extraction["coverage"] == "partial"
        library_ids.add(doc["library_file_id"])
        expected_files.add(filename)
        total_bytes += doc["size_bytes"]
    require(enrolled == ENROLLED, "engineering subset differs")
    actual_files = {p.relative_to(document_root).as_posix() for p in document_root.rglob("*") if not p.is_dir()}
    expected_directories = {parent.as_posix() for name in expected_files for parent in Path(name).parents if parent != Path(".")}
    actual_directories = {p.relative_to(document_root).as_posix() for p in document_root.rglob("*") if p.is_dir()}
    require(actual_files == expected_files and actual_directories == expected_directories, "unexpected or missing resource files")
    require(manifest["asset_count"] == 20 and manifest["total_size_bytes"] == total_bytes, "manifest resource totals differ")
    source_checks = 0
    if source_workspace is not None:
        source_workspace = source_workspace.resolve(strict=True)
        for relative, expected_hash in manifest["source_file_hashes"].items():
            if relative == "moonproj/config/moonsuite-engineering.json":
                continue  # The intentional v1 -> v2 transition replaces this source.
            original = (source_workspace / relative).resolve(strict=True)
            require(original.is_relative_to(source_workspace), "original source escaped source workspace")
            require(sha256(original) == expected_hash, "original source changed: " + relative)
            source_checks += 1
    return {"status": "passed", "active_products": 20, "engineering_targets": len(enrolled), "source_manifest_repositories": 15, "configured_only_repositories": 1, "unknown_repository_locations": 4, "packaged_prds": 20, "total_prd_bytes": total_bytes, "packaged_text_sidecars": complete_extractions + partial_extractions, "complete_body_extractions": complete_extractions, "partial_body_extractions": partial_extractions, "total_text_bytes": text_bytes, "unique_library_identities": len(library_ids), "original_sources_checked": source_checks, "catalog_sha256": sha256(catalog_path)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--source-workspace", type=Path)
    arguments = parser.parse_args()
    try:
        print(json.dumps(verify(arguments.repository, arguments.source_workspace), indent=2))
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, "Catalog verification failed: " + str(error) + "\n")
