///|
fn fixture_product(id : String, enrolled : Bool) -> Json {
  {
    "id": Json::string(id),
    "name": "Fixture",
    "product_kind": "platform",
    "purpose": "Definition, not acceptance",
    "philosophy": {
      "excerpt": "Intent",
      "paragraphs": ["Intent paragraph"],
      "source_kind": "authored_prd",
      "source": "prd/fixture.json",
      "version": "fixture",
      "sha256": "fixture",
    },
    "repository": {
      "path": Json::string(id),
      "url": null,
      "revision": null,
      "source_kind": "configured",
    },
    "engineering_target": if enrolled {
      {
        "id": Json::string(id),
        "lifecycle": "software",
        "role": "fixture",
        "tier": "core",
      }
    } else {
      Json::null()
    },
    "documents": [],
    "company_project_id": null,
  }
}

///|
fn fixture_catalog(products : Array[Json]) -> Json {
  {
    "schema": "moonsuite.product-portfolio.v2",
    "workspace_root": "..",
    "policy": {
      "unknown_is_pass": false,
      "self_review_allowed": false,
      "trusted_review_verdict": "accept",
      "progress_percent_requires_declared_milestones": true,
      "release_candidate_requires_digest": true,
    },
    "products": Json::array(products),
  }
}

///|
test "registry resolution uses stable IDs regardless of catalog order" {
  let first = @registry.parse(
    fixture_catalog([
      fixture_product("alpha", true),
      fixture_product("beta", false),
    ]).stringify(),
  )
  let reordered = @registry.parse(
    fixture_catalog([
      fixture_product("beta", false),
      fixture_product("alpha", true),
    ]).stringify(),
  )
  assert_eq(
    first.find("alpha").unwrap().id,
    reordered.find("alpha").unwrap().id,
  )
  assert_true(first.engineering_repository("alpha") is Some("alpha"))
  assert_true(first.engineering_repository("beta") is None)
  assert_true(reordered.engineering_repository("alpha") is Some("alpha"))
  assert_true(first.find("absent") is None)
}

///|
test "registry rejects malformed schema duplicate IDs and unsupported fields" {
  for
    source in [
      "{",
      "{}",
      fixture_catalog([
        fixture_product("alpha", true),
        fixture_product("alpha", false),
      ]).stringify(),
      fixture_catalog([fixture_product("../bad", true)]).stringify(),
    ] {
    let rejected = try {
      ignore(@registry.parse(source))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for
    (key, value) in [
      ("schema", Json::string("moonsuite.engineering-portfolio.v1")),
      ("unknown", Json::boolean(true)),
      ("products", Json::null()),
    ] {
    let root = match fixture_catalog([]) {
      Object(fields) => fields
      _ => abort("fixture")
    }
    root[key] = value
    assert_true(
      try {
        ignore(@registry.parse(Json::object(root).stringify()))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "registry rejects undeclared fields missing fields and repository traversal" {
  for mutation in ["name", "extra", "repository"] {
    let fields = match fixture_product("alpha", true) {
      Object(fields) => fields
      _ => abort("fixture")
    }
    if mutation == "name" {
      fields.remove("name")
    } else if mutation == "extra" {
      fields["extra"] = Json::string("undeclared")
    } else {
      fields["repository"] = {
        "path": "../secret",
        "url": null,
        "revision": null,
        "source_kind": "configured",
      }
    }
    assert_true(
      try {
        ignore(
          @registry.parse(fixture_catalog([Json::object(fields)]).stringify()),
        )
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "registry empty catalog is distinct from missing invalid catalog" {
  assert_eq(
    @registry.parse(fixture_catalog([]).stringify()).products.length(),
    0,
  )
}

///|
test "registry route and relative path identity reject traversal" {
  for id in ["", "..", "../secret", "moon%2fbook", "MOON", "moon/book"] {
    assert_false(@registry.valid_id(id))
  }
  for
    path in ["/etc/passwd", "../secret", "a/../b", "a//b", "a\\b", "a/%2e%2e/b"] {
    assert_false(@registry.valid_relative_path(path))
  }
  assert_true(@registry.valid_relative_path("docs/PRODUCT_CONTRACT.md"))
}

///|
test "registry validates declared document identity type and path" {
  let document : Json = {
    "id": "prd",
    "title": "Snapshot",
    "type": "prd",
    "source_kind": "packaged",
    "path": "Fixture.docx",
    "version": "snapshot",
    "provenance": "fixture",
    "sha256": "fixture",
    "size_bytes": 100,
    "library_file_id": null,
    "file_name": "Fixture.docx",
    "library_captured_version_number": 0,
  }
  for bad in ["../secret.docx", "Fixture.html", "/tmp/Fixture.docx"] {
    let doc = match document {
      Object(fields) => fields
      _ => abort("fixture")
    }
    doc["path"] = Json::string(bad)
    let product = match fixture_product("alpha", true) {
      Object(fields) => fields
      _ => abort("fixture")
    }
    product["documents"] = Json::array([Json::object(doc)])
    assert_true(
      try {
        ignore(
          @registry.parse(fixture_catalog([Json::object(product)]).stringify()),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let doc = match document {
    Object(fields) => fields
    _ => abort("fixture")
  }
  doc["path"] = Json::string("Fixture.docx")
  let product = match fixture_product("alpha", true) {
    Object(fields) => fields
    _ => abort("fixture")
  }
  product["documents"] = Json::array([Json::object(doc)])
  assert_eq(
    @registry.parse(fixture_catalog([Json::object(product)]).stringify())
    .find("alpha")
    .unwrap().documents.length(),
    1,
  )
  product["documents"] = Json::array([Json::object(doc), Json::object(doc)])
  assert_true(
    try {
      ignore(
        @registry.parse(fixture_catalog([Json::object(product)]).stringify()),
      )
      false
    } catch {
      _ => true
    },
  )
}
