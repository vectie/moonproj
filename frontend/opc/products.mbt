///|
// Catalog definitions are authored intent, never runtime or delivery acceptance.
struct ProductDocument {
  id : String
  title : String
  kind : String
  provenance : String
  version : String
  availability : String
  url : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct ProductDefinition {
  id : String
  name : String
  kind : String
  purpose : String
  philosophy : String
  philosophy_paragraphs : Array[String]
  philosophy_source : String
  philosophy_kind : String
  philosophy_version : String
  repository_state : String
  repository_path : String
  repository_url : String
  repository_revision : String
  engineering_target : String
  company_project_id : String
  documents : Array[ProductDocument]
} derive(Debug, Eq, ToJson, FromJson)

///|
struct ProductCompanyProject {
  id : String
  name : String
  source : String
} derive(Debug, Eq)

///|
struct ProductWorkTask {
  id : String
  product_id : String
  project_id : String
  title : String
  state : String
} derive(Debug, Eq)

///|
struct ProductsState {
  rows : Array[ProductDefinition]
  inventories : Array[@work_inventory.Inventory]
  inventory_state : String
  inventory_filter : String
  inventory_query : String
  // A chosen outcome waits for an explicit, validated company project.
  // This is a page-local choice, not a draft, task, or persisted attribution.
  pending_work_group_id : String
  state : String
  request : Int
  selected_id : String
  // Exact requested identity survives a late, failed, reordered or missing catalog.
  route_id : String
  selection : Int
  search : String
  reverse : Bool
  admission_state : String
  engineering_state : String
  projects : Array[ProductCompanyProject]
  project_state : String
  project_request : Int
  project_choice : Int
  project_note : String
  project_id : String
  tasks : Array[ProductWorkTask]
  work_state : String
  work_request : Int
  prepared_product_id : String
  prepared_project_id : String
  prepared_product_snapshot : ProductDefinition?
} derive(Debug, Eq)

///|
enum ProductsMsg {
  Refresh
  CatalogRead(Int, Int, String)
  Select(String)
  Search(String)
  Reverse
  DetailRead(String, String, Int, Int, String)
  OpenEngineering(Page)
  LoadProjects
  ProjectsRead(String, Int, Int, Int, String)
  SelectProject(String)
  LoadWork
  WorkRead(String, Int, String, Int, Int, String)
  Prepare
  PrepareWork(String, String)
  CancelWorkChoice
  FilterWork(String)
  SearchWork(String)
  CancelPreparation
  OpenTask(String)
} derive(Debug, Eq)

///|
fn products_initial() -> ProductsState {
  {
    rows: [],
    inventories: [],
    inventory_state: "idle",
    inventory_filter: "all",
    inventory_query: "",
    pending_work_group_id: "",
    state: "idle",
    request: 0,
    selected_id: "",
    route_id: "",
    selection: 0,
    search: "",
    reverse: false,
    admission_state: "idle",
    engineering_state: "idle",
    projects: [],
    project_state: "idle",
    project_request: 0,
    project_choice: 0,
    project_note: "",
    project_id: "",
    tasks: [],
    work_state: "idle",
    work_request: 0,
    prepared_product_id: "",
    prepared_project_id: "",
    prepared_product_snapshot: None,
  }
}

///|
fn products_text(value : Json, key : String) -> String {
  dispatch_json_text(value, key)
}

///|
fn products_field(value : Json, key : String) -> Json {
  dispatch_json_field(value, key)
}

///|
fn products_id_valid(id : String) -> Bool {
  !id.is_empty() &&
  id.length() <= 96 &&
  id
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
  })
}

///|
fn products_optional_text(value : Json) -> Bool {
  value is Null || value is String(_)
}

///|
fn products_document_url(product : String, document : String) -> String {
  "/api/moonsuite/products/" + product + "/documents/" + document
}

///|
fn products_decode(body : String) -> Array[ProductDefinition]? {
  let root = @json.parse(body) catch { _ => return None }
  if products_text(root, "schema") != "moonsuite.product-portfolio.v2" ||
    products_text(root, "scope") != "active_product_definitions" {
    return None
  }
  let values = match products_field(root, "products") {
    Array(v) => v
    _ => return None
  }
  let rows : Array[ProductDefinition] = []
  for value in values {
    if ![
        "id", "name", "product_kind", "purpose", "philosophy", "repository", "engineering_target",
        "company_project_id", "documents",
      ].all(key => products_has(value, key)) {
      return None
    }
    let id = products_text(value, "id")
    if !products_id_valid(id) || rows.any(row => row.id == id) {
      return None
    }
    let name = products_text(value, "name")
    let kind = products_text(value, "product_kind")
    let purpose = products_text(value, "purpose")
    let philosophy = products_field(value, "philosophy")
    if name.is_empty() ||
      purpose.is_empty() ||
      !["platform", "desktop", "library", "specialist"].contains(kind) ||
      products_text(philosophy, "excerpt").is_empty() ||
      products_text(philosophy, "source").is_empty() ||
      products_text(philosophy, "version").is_empty() ||
      !["founder_intent", "authored_prd"].contains(
        products_text(philosophy, "source_kind"),
      ) {
      return None
    }
    let paragraphs = match products_field(philosophy, "paragraphs") {
      Array(values) => {
        let result : Array[String] = []
        for paragraph in values {
          match paragraph {
            String(text) if !text.is_empty() => result.push(text)
            _ => return None
          }
        }
        result
      }
      _ => return None
    }
    let repo = products_field(value, "repository")
    let repo_state = if repo is Null {
      "unknown"
    } else {
      products_text(repo, "availability")
    }
    if !(repo is Null) &&
      (
        products_text(repo, "path").is_empty() ||
        !["present", "missing"].contains(repo_state) ||
        !products_optional_text(products_field(repo, "url")) ||
        !products_optional_text(products_field(repo, "revision"))
      ) {
      return None
    }
    let target = products_field(value, "engineering_target")
    let target_id = products_text(target, "id")
    if !(target is Null) && (!products_id_valid(target_id) || target_id != id) {
      return None
    }
    let project = products_field(value, "company_project_id")
    if !products_optional_text(project) {
      return None
    }
    let docs : Array[ProductDocument] = []
    let documents = match products_field(value, "documents") {
      Array(v) => v
      _ => return None
    }
    for doc in documents {
      if ![
          "id", "title", "type", "source_kind", "provenance", "version", "availability",
          "url",
        ].all(key => products_has(doc, key)) {
        return None
      }
      let doc_id = products_text(doc, "id")
      let availability = products_text(doc, "availability")
      let url = products_text(doc, "url")
      if !products_id_valid(doc_id) ||
        docs.any(d => d.id == doc_id) ||
        products_text(doc, "title").is_empty() ||
        products_text(doc, "type") != "prd" ||
        products_text(doc, "source_kind") != "packaged" ||
        products_text(doc, "provenance").is_empty() ||
        products_text(doc, "version").is_empty() ||
        !["available", "missing", "repository_unavailable"].contains(
          availability,
        ) ||
        !products_optional_text(products_field(doc, "url")) ||
        (
          !url.is_empty() &&
          (
            availability != "available" ||
            url != products_document_url(id, doc_id)
          )
        ) {
        return None
      }
      docs.push({
        id: doc_id,
        title: products_text(doc, "title"),
        kind: products_text(doc, "type"),
        provenance: products_text(doc, "provenance"),
        version: products_text(doc, "version"),
        availability,
        url,
      })
    }
    rows.push({
      id,
      name,
      kind,
      purpose,
      philosophy: products_text(philosophy, "excerpt"),
      philosophy_paragraphs: paragraphs,
      philosophy_source: products_text(philosophy, "source"),
      philosophy_kind: products_text(philosophy, "source_kind"),
      philosophy_version: products_text(philosophy, "version"),
      repository_state: repo_state,
      repository_path: products_text(repo, "path"),
      repository_url: products_text(repo, "url"),
      repository_revision: products_text(repo, "revision"),
      engineering_target: target_id,
      company_project_id: products_text(value, "company_project_id"),
      documents: docs,
    })
  }
  Some(rows)
}

///|
fn products_selected(state : ProductsState) -> ProductDefinition? {
  products_find(state.rows, state.selected_id)
}

///|
fn products_visible(state : ProductsState) -> Array[ProductDefinition] {
  let query = state.search.trim().to_owned().to_lower()
  let rows = state.rows.filter(row => {
    query.is_empty() ||
    (row.name + " " + row.id + " " + row.purpose).to_lower().contains(query)
  })
  rows.sort_by((a, b) => {
    if state.reverse {
      b.name.lexical_compare(a.name)
    } else {
      a.name.lexical_compare(b.name)
    }
  })
  rows
}

///|
fn products_read_state(status : Int, body : String) -> String {
  if status == 0 {
    "offline"
  } else if status == 401 || status == 403 {
    "unauthorized"
  } else if status != 200 {
    let payload = @json.parse(body) catch { _ => Json::null() }
    match products_text(payload, "code") {
      "product_catalog_missing" => "missing"
      "product_catalog_invalid" => "invalid"
      _ => "unavailable"
    }
  } else {
    "ready"
  }
}

///|
fn products_state_label(state : String) -> String {
  match state {
    "idle" => "尚未读取"
    "loading" => "读取中"
    "ready" => "已读取"
    "empty" => "没有记录"
    "missing" => "未配置目录 / 资源缺失"
    "invalid" => "响应或配置无效"
    "unauthorized" => "需要登录 / 无读取权限"
    "offline" => "网络不可用"
    "unavailable" => "服务暂不可用"
    "not_enrolled" => "未登记工程审计"
    _ => state
  }
}

///|
fn products_decode_projects(body : String) -> Array[ProductCompanyProject]? {
  let root = @json.parse(body) catch { _ => return None }
  let items = match products_field(root, "items") {
    Array(v) => v
    _ => return None
  }
  let rows : Array[ProductCompanyProject] = []
  for item in items {
    let id = products_text(item, "project_id")
    if id.is_empty() ||
      rows.any(row => row.id == id) ||
      products_text(item, "project_name").is_empty() {
      return None
    }
    rows.push({
      id,
      name: products_text(item, "project_name"),
      source: products_text(item, "source_kind"),
    })
  }
  Some(rows)
}

///|
fn products_project_note(body : String) -> String {
  let root = @json.parse(body) catch { _ => return "" }
  match products_field(root, "diagnostics") {
    Array(values) if !values.is_empty() =>
      "部分项目的身份或组织归属存在数据问题，相关项目已从可选列表中省略；其余项目仍可使用。"
    _ => ""
  }
}

///|
fn products_decode_tasks(
  body : String,
  product_id : String,
) -> Array[ProductWorkTask]? {
  if !products_id_valid(product_id) {
    return None
  }
  let root = @json.parse(body) catch { _ => return None }
  let items = match products_field(root, "items") {
    Array(v) => v
    _ => return None
  }
  let rows : Array[ProductWorkTask] = []
  for item in items {
    let id = products_text(item, "taskGuid")
    let project_id = products_text(item, "projGuid")
    if id.is_empty() || project_id.is_empty() {
      return None
    }
    // Legacy company work has no product identity. It cannot become a product's
    // history merely because it belongs to the same company project.
    let tagged_product = products_field(item, "product_id")
    if tagged_product is Null {
      continue
    }
    if products_text(item, "product_id") != product_id ||
      rows.any(row => row.id == id) {
      return None
    }
    rows.push({
      id,
      product_id,
      project_id,
      title: products_text(item, "taskName"),
      state: products_text(item, "status"),
    })
  }
  Some(rows)
}

///|
fn products_can_audit(model : Model) -> Bool {
  model.products.state == "ready" &&
  model.products.rows.any(row => {
    row.id == model.engineering_project &&
    !row.engineering_target.is_empty() &&
    row.repository_state == "present"
  })
}

///|
fn products_find(
  rows : Array[ProductDefinition],
  id : String,
) -> ProductDefinition? {
  for row in rows {
    if row.id == id {
      return Some(row)
    }
  }
  None
}

///|
fn products_has(value : Json, key : String) -> Bool {
  match value {
    Object(fields) => fields.get(key) is Some(_)
    _ => false
  }
}

///|
fn products_project_exists(state : ProductsState) -> Bool {
  // The list and task creation share project_plan_project_rows on the service.
  // Native creation sets if_end=true; neither that field nor proj_status is an
  // eligibility flag. The service rechecks membership when creating a task.
  state.project_state == "ready" &&
  state.projects.any(row => row.id == state.project_id)
}

///|
fn products_engineering_enrolled(model : Model) -> Bool {
  model.products.state == "ready" &&
  model.products.rows.any(row => {
    row.id == model.engineering_project && !row.engineering_target.is_empty()
  })
}

///|
fn products_clear_preparation(state : ProductsState) -> ProductsState {
  {
    ..state,
    prepared_product_id: "",
    prepared_project_id: "",
    prepared_product_snapshot: None,
  }
}
