///|
async test "product work inventory reads all target requirements independently of company services" {
  let resources : ProductResources = {
    catalog_path: "config/moonsuite-engineering.json",
    document_root: "resources/product-documents",
    workspace_root: "/not-a-company-database",
  }
  let catalog = read_product_catalog(resources)
  let (status, inventories) = read_product_work_inventory(resources, catalog)
  assert_eq(status, "ready")
  assert_eq(inventories.length(), 20)
  assert_eq(
    inventories.fold(init=0, (count, item) => count + item.requirements.length()),
    344,
  )
  assert_eq(
    inventories.fold(init=0, (count, item) => {
      count + item.requirements.filter(row => row.track == "quality").length()
    }),
    102,
  )
  assert_false(
    inventories.any(item => {
      ["lunanexa", "moonstat", "moonprop", "mooncake"].contains(item.product_id)
    }),
  )
  let projection = product_catalog_projection(resources, catalog)
  guard projection
    is { "work_inventory_state": "ready", "products": Array(products), .. } else {
    abort("Missing inventory projection")
  }
  assert_eq(products.length(), 20)
  for product in products {
    guard product
      is {
        "id": String(id),
        "work_inventory": inventory,
        "company_project_id": Null,
        ..
      } else {
      abort("Product must retain company identity boundary")
    }
    assert_eq(@work_inventory.parse(inventory, id).product_id, id)
  }
}

///|
async test "product work inventory missing malformed or stale does not hide valid product definitions" {
  let root = @fs.tmpdir(prefix="moonproj-work-inventory-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let resources : ProductResources = {
    catalog_path: root + "/catalog.json",
    document_root: "resources/product-documents",
    workspace_root: root,
  }
  let catalog = @registry.parse(
    @fs.read_file("config/moonsuite-engineering.json").text(),
  )
  assert_eq(read_product_work_inventory(resources, catalog).0, "missing")
  let projection = product_catalog_projection(resources, catalog)
  guard projection
    is { "work_inventory_state": "missing", "products": Array(products), .. } else {
    abort("Missing state must remain explicit")
  }
  assert_eq(products.length(), 20)
  @fs.write_file(
    root + "/moonsuite-work-inventory.json",
    "{",
    create_mode=@fs.CreateOrTruncate,
  )
  assert_eq(read_product_work_inventory(resources, catalog).0, "invalid")
  let value = @json.parse(
    @fs.read_file("config/moonsuite-work-inventory.json").text(),
  )
  guard value is { "products": Array(rows), .. } else {
    abort("Inventory fixture")
  }
  guard rows[0] is Object(fields) else { abort("Inventory product") }
  fields["prd_sha256"] = "stale-document".to_json()
  @fs.write_file(
    root + "/moonsuite-work-inventory.json",
    value.stringify(),
    create_mode=@fs.CreateOrTruncate,
  )
  assert_eq(read_product_work_inventory(resources, catalog).0, "invalid")
  assert_eq(catalog.products.length(), 20)
}

///|
test "product work inventory follows the configured catalog directory" {
  let resources : ProductResources = {
    catalog_path: "catalog.json",
    document_root: "unused",
    workspace_root: "unused",
  }
  assert_eq(product_inventory_directory(resources), ".")
  assert_eq(
    product_inventory_directory({
      ..resources,
      catalog_path: "config/catalog.json",
    }),
    "config",
  )
  assert_eq(
    product_inventory_directory({ ..resources, catalog_path: "/catalog.json", }),
    "/",
  )
  assert_eq(
    product_inventory_directory({
      ..resources,
      catalog_path: "/bundle/config/catalog.json",
    }),
    "/bundle/config",
  )
}
