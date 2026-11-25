///|
// A packaged, read-only sibling of the configured product catalog. This adds
// planning context to the existing read projection, never company database rows.
fn product_inventory_directory(resources : ProductResources) -> String {
  let parts = resources.catalog_path.split("/").to_array()
  if parts.length() < 2 {
    "."
  } else {
    let parent = parts[:parts.length() - 1]
      .map(part => part.to_owned())
      .join("/")
    if parent.is_empty() {
      "/"
    } else {
      parent
    }
  }
}

///|
async fn read_product_work_inventory(
  resources : ProductResources,
  catalog : @registry.Catalog,
) -> (String, Array[@work_inventory.Inventory]) {
  let path = match
    contained_product_path(
      product_inventory_directory(resources),
      "moonsuite-work-inventory.json",
      false,
    ) {
    Some(path) => path
    None => return ("missing", [])
  }
  try {
    let file = @fs.open(path, mode=@fs.ReadOnly)
    defer file.close()
    let size = file.size()
    if size <= 0L || size > 16L * 1024L * 1024L {
      return ("invalid", [])
    }
    let value = @json.parse(@fs.read_file(path).text())
    let inventories = @work_inventory.parse_portfolio(
      value,
      catalog.products.map(product => product.id),
    )
    for inventory in inventories {
      let product = catalog.find(inventory.product_id).unwrap()
      let prd = product.documents
        .filter(document => document.id == "prd")
        .get(0)
      if prd is None ||
        prd.unwrap().metadata.get("sha256") !=
        Some(Json::string(inventory.prd_sha256)) {
        return ("invalid", [])
      }
    }
    ("ready", inventories)
  } catch {
    _ => ("invalid", [])
  }
}
