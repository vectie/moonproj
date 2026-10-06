///|
/// The product definition catalog is independent of company and execution state.
pub(all) struct Catalog {
  products : Array[Product]
}

///|
pub(all) struct Product {
  id : String
  metadata : Map[String, Json]
  repository : Repository?
  engineering_target : String?
  documents : Array[Document]
}

///|
pub(all) struct Repository {
  path : String
  metadata : Map[String, Json]
}

///|
pub(all) struct Document {
  id : String
  path : String
  source_kind : String
  file_name : String
  metadata : Map[String, Json]
}

///|
pub suberror CatalogError {
  Invalid(String)
}

///|
pub fn valid_id(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(c => (c >= 'a' && c <= 'z') || c.is_ascii_digit() || c == '-')
}

///|
pub fn valid_relative_path(value : String) -> Bool {
  if value.is_empty() ||
    value.has_prefix("/") ||
    value.contains("\\") ||
    value.contains("\u0000") ||
    value.contains("%") {
    return false
  }
  for part in value.split("/") {
    if part.is_empty() || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
fn object(
  value : Json,
  fields : Array[String],
) -> Map[String, Json] raise CatalogError {
  let result = match value {
    Object(result) => result
    _ => raise Invalid("expected an object")
  }
  for key, _ in result {
    if !fields.contains(key) {
      raise Invalid("unsupported field: " + key)
    }
  }
  for key in fields {
    if !result.contains(key) {
      raise Invalid("missing field: " + key)
    }
  }
  result
}

///|
fn text(fields : Map[String, Json], key : String) -> String raise CatalogError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => raise Invalid("expected nonempty string: " + key)
  }
}

///|
fn nullable_text(
  fields : Map[String, Json],
  key : String,
) -> Unit raise CatalogError {
  match fields.get(key) {
    Some(Null) => ()
    Some(String(value)) if !value.trim().is_empty() => ()
    _ => raise Invalid("expected string or null: " + key)
  }
}

///|
fn parse_document(value : Json) -> Document raise CatalogError {
  let fields = object(value, [
    "id", "title", "type", "source_kind", "path", "version", "provenance", "sha256",
    "size_bytes", "library_file_id", "file_name", "library_captured_version_number",
  ])
  let id = text(fields, "id")
  let path = text(fields, "path")
  let file_name = text(fields, "file_name")
  let source_kind = text(fields, "source_kind")
  if !valid_id(id) ||
    !valid_relative_path(path) ||
    !valid_relative_path(file_name) ||
    file_name.contains("/") ||
    file_name.contains("\"") ||
    file_name.contains("\r") ||
    file_name.contains("\n") {
    raise Invalid("invalid document identity or relative path")
  }
  if source_kind != "packaged" && source_kind != "repository" {
    raise Invalid("unsupported document source_kind")
  }
  let document_type = text(fields, "type")
  if !((
      document_type == "prd" &&
      path.has_suffix(".docx") &&
      file_name.has_suffix(".docx")
    ) ||
    (
      (document_type == "readme" || document_type == "contract") &&
      path.has_suffix(".md") &&
      file_name.has_suffix(".md")
    )) {
    raise Invalid("unsupported document type or extension")
  }
  for key in ["title", "version", "provenance", "sha256"] {
    ignore(text(fields, key))
  }
  nullable_text(fields, "library_file_id")
  match fields["size_bytes"] {
    Number(n, ..) if n > 0 => ()
    _ => raise Invalid("invalid document size_bytes")
  }
  match fields["library_captured_version_number"] {
    Number(n, ..) if n >= 0 => ()
    _ => raise Invalid("invalid document library_captured_version_number")
  }
  { id, path, source_kind, file_name, metadata: fields, }
}

///|
fn parse_product(value : Json) -> Product raise CatalogError {
  let fields = object(value, [
    "id", "name", "product_kind", "purpose", "philosophy", "repository", "engineering_target",
    "documents", "company_project_id",
  ])
  let id = text(fields, "id")
  if !valid_id(id) {
    raise Invalid("invalid product id")
  }
  for key in ["name", "product_kind", "purpose"] {
    ignore(text(fields, key))
  }
  let philosophy = object(fields["philosophy"], [
    "excerpt", "paragraphs", "source_kind", "source", "version", "sha256",
  ])
  for key in ["excerpt", "source_kind", "source", "version", "sha256"] {
    ignore(text(philosophy, key))
  }
  match philosophy["paragraphs"] {
    Array(items) if !items.is_empty() =>
      for item in items {
        match item {
          String(s) if !s.trim().is_empty() => ()
          _ => raise Invalid("invalid philosophy paragraph")
        }
      }
    _ => raise Invalid("invalid philosophy paragraphs")
  }
  let repository = match fields["repository"] {
    Null => None
    value => {
      let metadata = object(value, ["path", "url", "revision", "source_kind"])
      let path = text(metadata, "path")
      if !valid_relative_path(path) {
        raise Invalid("invalid repository relative path")
      }
      nullable_text(metadata, "url")
      nullable_text(metadata, "revision")
      let source = text(metadata, "source_kind")
      if source != "configured" && source != "source_manifest" {
        raise Invalid("invalid repository source_kind")
      }
      Some(Repository::{ path, metadata, })
    }
  }
  let engineering_target = match fields["engineering_target"] {
    Null => None
    value => {
      let target = object(value, ["id", "lifecycle", "role", "tier"])
      let target_id = text(target, "id")
      if target_id != id {
        raise Invalid("engineering target must use the product id")
      }
      for key in ["lifecycle", "role", "tier"] {
        ignore(text(target, key))
      }
      Some(target_id)
    }
  }
  nullable_text(fields, "company_project_id")
  let documents = match fields["documents"] {
    Array(items) => {
      let documents : Array[Document] = []
      for item in items {
        let document = parse_document(item)
        if documents.any(d => d.id == document.id) {
          raise Invalid("duplicate document id")
        }
        documents.push(document)
      }
      documents
    }
    _ => raise Invalid("invalid documents array")
  }
  { id, metadata: fields, repository, engineering_target, documents, }
}

///|
pub fn parse(source : String) -> Catalog raise CatalogError {
  let value = @json.parse(source) catch {
    _ => raise Invalid("malformed catalog JSON")
  }
  let fields = object(value, ["schema", "workspace_root", "policy", "products"])
  if text(fields, "schema") != "moonsuite.product-portfolio.v2" {
    raise Invalid("unsupported catalog schema")
  }
  ignore(text(fields, "workspace_root"))
  let policy = object(fields["policy"], [
    "unknown_is_pass", "self_review_allowed", "trusted_review_verdict", "progress_percent_requires_declared_milestones",
    "release_candidate_requires_digest",
  ])
  if policy["unknown_is_pass"] != Json::boolean(false) ||
    policy["self_review_allowed"] != Json::boolean(false) ||
    policy["trusted_review_verdict"] != Json::string("accept") ||
    policy["progress_percent_requires_declared_milestones"] !=
    Json::boolean(true) ||
    policy["release_candidate_requires_digest"] != Json::boolean(true) {
    raise Invalid("unsupported engineering policy")
  }
  let products = match fields["products"] {
    Array(items) => {
      let products : Array[Product] = []
      for item in items {
        let product = parse_product(item)
        if products.any(p => p.id == product.id) {
          raise Invalid("duplicate product id")
        }
        products.push(product)
      }
      products
    }
    _ => raise Invalid("invalid products array")
  }
  { products, }
}

///|
pub fn Catalog::find(self : Catalog, id : String) -> Product? {
  for product in self.products {
    if product.id == id {
      return Some(product)
    }
  }
  None
}

///|
pub fn Catalog::engineering_repository(self : Catalog, id : String) -> String? {
  match self.find(id) {
    Some({ engineering_target: Some(_), repository: Some(repo), .. }) =>
      Some(repo.path)
    _ => None
  }
}
