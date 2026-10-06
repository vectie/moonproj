#!/usr/bin/env python3
"""Regression checks for catalog coverage and resource integrity; no services used."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("catalog_verify", HERE / "verify_product_catalog.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProductCatalogDataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="moonproj-catalog-data-")
        self.repo = Path(self.temporary.name) / "moonproj"
        self.repo.mkdir()
        source = HERE.parent
        shutil.copytree(source / "config", self.repo / "config")
        shutil.copytree(source / "resources/product-documents", self.repo / "resources/product-documents")
        self.catalog_path = self.repo / "config/moonsuite-engineering.json"
        self.manifest_path = self.repo / "resources/product-documents/manifest.json"
        self.catalog = json.loads(self.catalog_path.read_text())

    def tearDown(self):
        self.temporary.cleanup()

    def row(self, identifier):
        return next(row for row in self.catalog["products"] if row["id"] == identifier)

    def save_catalog(self):
        self.catalog_path.write_text(json.dumps(self.catalog))
        manifest = json.loads(self.manifest_path.read_text())
        manifest["catalog_sha256"] = hashlib.sha256(self.catalog_path.read_bytes()).hexdigest()
        self.manifest_path.write_text(json.dumps(manifest))

    def reject(self):
        self.save_catalog()
        with self.assertRaises((ValueError, OSError)):
            module.verify(self.repo)

    def test_complete_real_catalog(self):
        result = module.verify(self.repo)
        self.assertEqual(result["active_products"], 20)
        self.assertEqual(result["engineering_targets"], 9)
        self.assertEqual(result["packaged_prds"], 20)
        self.assertEqual(result["unique_library_identities"], 20)

    def test_order_does_not_change_identity(self):
        self.catalog["products"].reverse()
        self.save_catalog()
        self.assertEqual(module.verify(self.repo)["active_products"], 20)

    def test_unknown_schema_rejected(self):
        self.catalog["schema"] = "invented"
        self.reject()

    def test_duplicate_product_rejected(self):
        self.catalog["products"][-1] = self.catalog["products"][0]
        self.reject()

    def test_retired_product_rejected(self):
        self.row("moonvis")["id"] = "moonstat"
        self.reject()

    def test_infrastructure_not_promoted_to_product(self):
        self.row("moonvis")["id"] = "lunanexa"
        self.reject()

    def test_inventory_does_not_grant_audit_enrollment(self):
        self.row("moonfind")["engineering_target"] = dict(self.row("moonproj")["engineering_target"])
        self.reject()

    def test_moonfish_configured_target_preserved(self):
        self.row("moonfish")["repository"] = None
        self.reject()

    def test_moonfish_origin_not_guessed(self):
        self.row("moonfish")["repository"]["url"] = "https://example.invalid/guess.git"
        self.reject()

    def test_unconfigured_repository_not_guessed(self):
        self.row("moonpoly")["repository"] = dict(self.row("moonfish")["repository"])
        self.reject()

    def test_founder_intent_cannot_be_overridden(self):
        self.row("moonproj")["philosophy"]["source_kind"] = "authored_prd"
        self.reject()

    def test_unverified_company_project_rejected(self):
        self.row("moonproj")["company_project_id"] = "proj-0001"
        self.reject()

    def test_fake_score_field_rejected(self):
        self.row("moonproj")["maturity_score"] = 100
        self.reject()

    def test_document_path_traversal_rejected(self):
        self.row("moonproj")["documents"][0]["path"] = "../../secrets.docx"
        self.reject()

    def test_missing_document_rejected(self):
        (self.repo / "resources/product-documents/MoonProj_PRD.docx").unlink()
        self.reject()

    def test_changed_document_bytes_rejected(self):
        path = self.repo / "resources/product-documents/MoonProj_PRD.docx"
        data = path.read_bytes()
        path.write_bytes(bytes([data[0] ^ 1]) + data[1:])
        self.reject()

    def test_document_symlink_escape_rejected(self):
        path = self.repo / "resources/product-documents/MoonProj_PRD.docx"
        target = Path(self.temporary.name) / "outside.docx"
        shutil.move(path, target)
        path.symlink_to(target)
        self.reject()

    def test_library_identity_change_rejected(self):
        self.row("moonproj")["documents"][0]["library_file_id"] = "libfile_" + "a" * 32
        self.reject()

    def test_current_library_version_claim_rejected(self):
        self.row("moonproj")["documents"][0]["library_current_version_number"] = 0
        self.reject()

    def test_undeclared_resource_rejected(self):
        (self.repo / "resources/product-documents/extra.txt").write_text("unapproved")
        self.reject()


if __name__ == "__main__":
    unittest.main(verbosity=2)
