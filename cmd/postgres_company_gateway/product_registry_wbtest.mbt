///|
async test "product catalog complete set and existing nine-target subset" {
  let catalog = @registry.parse(
    @fs.read_file("config/moonsuite-engineering.json").text(),
  )
  let expected = [
    "moonproj", "moonbook", "moonclaw", "moontown", "moondesk", "moongate", "moonrobo",
    "moonmoon", "moonfish", "mooncast", "moonchat", "moonfind", "moonflow", "moonfort",
    "moonlib", "moonmold", "moonpoly", "moonedit", "moonleaf", "moonvis",
  ]
  assert_eq(catalog.products.length(), 20)
  for id in expected {
    assert_true(catalog.find(id) is Some(_))
  }
  for
    excluded in [
      "moonprop", "mooncake", "moonstat", "moonwiki", "mooncode", "lunanexa", "moonbit-webview",
      "moonxi-net",
    ] {
    assert_true(catalog.find(excluded) is None)
  }
  let enrolled = catalog.products.filter(p => p.engineering_target is Some(_))
  assert_eq(enrolled.length(), 9)
  for
    id in [
      "moonproj", "moonbook", "moonclaw", "moontown", "moondesk", "moongate", "moonrobo",
      "moonmoon", "moonfish",
    ] {
    assert_true(catalog.engineering_repository(id) is Some(_))
  }
  assert_true(catalog.engineering_repository("moonfish") is Some("moonfish"))
  assert_true(catalog.engineering_repository("mooncast") is None)
  assert_true(catalog.find("moonpoly").unwrap().repository is None)
}

///|
test "declared document route never accepts filesystem paths" {
  assert_true(
    product_document_route("/api/moonsuite/products/moonproj/documents/prd")
    is Some(("moonproj", "prd")),
  )
  for
    path in [
      "/api/moonsuite/products/moonproj/documents/../secret", "/api/moonsuite/products/moonproj/documents/%2e%2e",
      "/api/moonsuite/products/%2fetc/documents/prd", "/api/moonsuite/products/moonproj/documents/prd/extra",
    ] {
    assert_true(product_document_route(path) is None)
  }
}

///|
async test "catalog projection records local availability without service dependencies" {
  let root = @fs.tmpdir(prefix="moonproj-products-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let catalog = @registry.parse(
    @fs.read_file("config/moonsuite-engineering.json").text(),
  )
  let resources : ProductResources = {
    catalog_path: "config/moonsuite-engineering.json",
    document_root: "resources/product-documents",
    workspace_root: root,
  }
  let projection = product_catalog_projection(resources, catalog)
  let products = match projection {
    Object(fields) =>
      match fields["products"] {
        Array(items) => items
        _ => []
      }
    _ => []
  }
  assert_eq(products.length(), 20)
  let product = catalog.find("moonproj").unwrap()
  assert_true(product_repository_path(resources, product) is None)
  assert_true(
    product_document_path(resources, product, product.documents[0]) is Some(_),
  )
  let missing : ProductResources = { ..resources, document_root: root, }
  assert_true(
    product_document_path(missing, product, product.documents[0]) is None,
  )
  @fs.mkdir(root + "/moonproj")
  assert_true(product_repository_path(resources, product) is Some(_))
}

///|
async test "product resources reject symlink escape and report missing invalid catalogs" {
  let root = @fs.tmpdir(prefix="moonproj-products-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(root + "/docs")
  @fs.write_file(
    root + "/outside.docx",
    "fixture",
    create_mode=@fs.CreateOrTruncate,
  )
  @fs.symlink(target=root + "/outside.docx", root + "/docs/escape.docx")
  assert_true(
    contained_product_path(root + "/docs", "escape.docx", false) is None,
  )
  let missing : ProductResources = {
    catalog_path: root + "/missing.json",
    document_root: root,
    workspace_root: root,
  }
  assert_true(
    try {
      ignore(read_product_catalog(missing))
      false
    } catch {
      Missing => true
      _ => false
    },
  )
  @fs.write_file(root + "/bad.json", "{}", create_mode=@fs.CreateOrTruncate)
  let invalid : ProductResources = {
    ..missing,
    catalog_path: root + "/bad.json",
  }
  assert_true(
    try {
      ignore(read_product_catalog(invalid))
      false
    } catch {
      Invalid => true
      _ => false
    },
  )
}
