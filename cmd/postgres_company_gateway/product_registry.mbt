///|
/// Resource locations are explicit launch configuration, never client paths.
struct ProductResources {
  catalog_path : String
  document_root : String
  workspace_root : String
}

///|
#derive(Debug)
suberror ProductCatalogReadError {
  Missing
  Invalid
}

///|
async fn read_product_catalog(
  resources : ProductResources,
) -> @registry.Catalog raise ProductCatalogReadError {
  let source = @fs.read_file(resources.catalog_path).text() catch {
    _ => raise Missing
  }
  @registry.parse(source) catch {
    _ => raise Invalid
  }
}

///|
fn product_catalog_error(error : ProductCatalogReadError) -> Json {
  match error {
    Missing =>
      {
        "code": "product_catalog_missing",
        "error": "Product catalog is unavailable; configure MOONPROJ_PRODUCT_CATALOG",
      }
    Invalid =>
      {
        "code": "product_catalog_invalid",
        "error": "Product catalog is invalid; expected moonsuite.product-portfolio.v2",
      }
  }
}

///|
fn copy_product_fields(fields : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for key, value in fields {
    result[key] = value
  }
  result
}

///|
async fn contained_product_path(
  root : String,
  relative : String,
  directory : Bool,
) -> String? {
  if !@registry.valid_relative_path(relative) {
    return None
  }
  try {
    let real_root = @fs.realpath(root)
    let path = @fs.realpath(real_root + "/" + relative)
    if !path.has_prefix(real_root.trim_end(chars="/").to_owned() + "/") {
      return None
    }
    let kind = @fs.kind(path)
    if (directory && kind != @fs.Directory) ||
      (!directory && kind != @fs.Regular) {
      return None
    }
    Some(path)
  } catch {
    _ => None
  }
}

///|
async fn product_repository_path(
  resources : ProductResources,
  product : @registry.Product,
) -> String? {
  match product.repository {
    Some(repo) =>
      contained_product_path(resources.workspace_root, repo.path, true)
    None => None
  }
}

///|
async fn product_document_path(
  resources : ProductResources,
  product : @registry.Product,
  document : @registry.Document,
) -> String? {
  let root = if document.source_kind == "packaged" {
    resources.document_root
  } else {
    match product_repository_path(resources, product) {
      Some(path) => path
      None => return None
    }
  }
  let path = match contained_product_path(root, document.path, false) {
    Some(path) => path
    None => return None
  }
  // Ordinary bounded file serving. DOCX is downloaded; Markdown is plain text.
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => return None }
  defer file.close()
  let size = file.size() catch { _ => return None }
  if size <= 0L || size > 16L * 1024L * 1024L {
    return None
  }
  Some(path)
}

///|
fn product_document_route(path : String) -> (String, String)? {
  let parts = path.split("/").to_array()
  if parts.length() == 7 &&
    parts[0] == "" &&
    parts[1] == "api" &&
    parts[2] == "moonsuite" &&
    parts[3] == "products" &&
    parts[5] == "documents" {
    let product_id = parts[4].to_owned()
    let document_id = parts[6].to_owned()
    if @registry.valid_id(product_id) && @registry.valid_id(document_id) {
      return Some((product_id, document_id))
    }
  }
  None
}

///|
async fn product_catalog_projection(
  resources : ProductResources,
  catalog : @registry.Catalog,
) -> Json {
  let products : Array[Json] = []
  let (inventory_state, inventories) = read_product_work_inventory(
    resources, catalog,
  )
  for product in catalog.products {
    let fields = copy_product_fields(product.metadata)
    for inventory in inventories {
      if inventory.product_id == product.id {
        fields["work_inventory"] = inventory.projection()
      }
    }
    let repository_path = product_repository_path(resources, product)
    match product.repository {
      Some(repo) => {
        let metadata = copy_product_fields(repo.metadata)
        metadata["availability"] = Json::string(
          if repository_path is Some(_) {
            "present"
          } else {
            "missing"
          },
        )
        fields["repository"] = Json::object(metadata)
      }
      None => ()
    }
    let documents : Array[Json] = []
    for document in product.documents {
      let metadata = copy_product_fields(document.metadata)
      let available = product_document_path(resources, product, document)
        is Some(_)
      metadata["availability"] = Json::string(
        if available {
          "available"
        } else if document.source_kind == "repository" &&
          repository_path is None {
          "repository_unavailable"
        } else {
          "missing"
        },
      )
      metadata["url"] = if available {
        Json::string(
          "/api/moonsuite/products/" + product.id + "/documents/" + document.id,
        )
      } else {
        Json::null()
      }
      // Relative declaration metadata is provenance, not a local filesystem opener.
      documents.push(Json::object(metadata))
    }
    fields["documents"] = Json::array(documents)
    products.push(Json::object(fields))
  }
  {
    "schema": "moonsuite.product-portfolio.v2",
    "scope": "active_product_definitions",
    "work_inventory_state": Json::string(inventory_state),
    "products": Json::array(products),
  }
}

///|
async fn serve_product_resources(
  resources : ProductResources,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  if !(request.meth is @http.Get || request.meth is @http.Head) {
    send_json(conn, request.meth, 405, { "error": "method not allowed" })
    return
  }
  let path = path_only(request.path)
  if path != "/api/moonsuite/products" && product_document_route(path) is None {
    send_json(conn, request.meth, 404, {
      "error": "declared product document not found",
    })
    return
  }
  let catalog = read_product_catalog(resources) catch {
    error => {
      send_json(conn, request.meth, 503, product_catalog_error(error))
      return
    }
  }
  if path == "/api/moonsuite/products" {
    send_json(
      conn,
      request.meth,
      200,
      product_catalog_projection(resources, catalog),
    )
    return
  }
  let (product_id, document_id) = product_document_route(path).unwrap()
  let product = match catalog.find(product_id) {
    Some(product) => product
    None => {
      send_json(conn, request.meth, 404, { "error": "product not found" })
      return
    }
  }
  for document in product.documents {
    if document.id != document_id {
      continue
    }
    let file_path = match product_document_path(resources, product, document) {
      Some(path) => path
      None => {
        send_json(conn, request.meth, 404, {
          "code": "product_document_unavailable",
          "error": "Declared product document is unavailable",
        })
        return
      }
    }
    let body = @fs.read_file(file_path) catch {
      _ => {
        send_json(conn, request.meth, 404, {
          "code": "product_document_unavailable",
          "error": "Declared product document is unreadable",
        })
        return
      }
    }
    let is_docx = document.path.has_suffix(".docx")
    let result : ProxyResult = {
      status: 200,
      content_type: if is_docx {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      } else {
        "text/plain; charset=utf-8"
      },
      body: body.binary(),
      www_authenticate: None,
    }
    send_bytes(conn, request.meth, result, extra_headers={
      "Content-Disposition": (if is_docx { "attachment" } else { "inline" }) +
      "; filename=\"" +
      document.file_name +
      "\"",
      "X-Content-Type-Options": "nosniff",
    })
    return
  }
  send_json(conn, request.meth, 404, {
    "error": "declared product document not found",
  })
}

///|
fn moonsuite_project_path(
  catalog : @registry.Catalog,
  workspace_root : String,
  project : String,
) -> String? {
  match catalog.engineering_repository(project) {
    Some(relative) => Some(workspace_root + "/" + relative)
    None => None
  }
}

///|
async fn audit_product_catalog(
  resources : ProductResources,
) -> @registry.Catalog raise GatewayError {
  read_product_catalog(resources) catch {
    _ => raise GatewayError::Upstream("product catalog unavailable or invalid")
  }
}
