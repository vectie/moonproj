///|
struct CompanyProfile {
  name : String
  unit_id : String
  unit_name : String
  unit_source : String
} derive(Debug, Eq)

///|
struct CompanyUnit {
  id : String
  name : String
  source : String
} derive(Debug, Eq)

///|
struct CompanyUnitRead {
  rows : Array[CompanyUnit]
  note : String
} derive(Debug, Eq)

///|
// Recovery contains ordinary request data only. It is never authority or proof.
struct CompanySetupRequest {
  kind : String
  key : String
  name : String
  unit_id : String
  project_code : String
  project_id : String
  product_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
struct CompanySetupStore {
  version : Int
  company : CompanySetupRequest?
  project : CompanySetupRequest?
  recent_project : CompanySetupRequest?
} derive(Debug, Eq, ToJson, FromJson)

///|
struct CompanySetupOperation {
  request : CompanySetupRequest?
  phase : String
  note : String
  selection : Int
  project_choice : Int
  attempted : Bool
  retrying : Bool
  recover_only : Bool
} derive(Debug, Eq)

///|
struct CompanySetupState {
  actor : String
  epoch : Int
  session_request : Int
  read_request : Int
  session_state : String
  profile_state : String
  profile : CompanyProfile?
  units_state : String
  units : Array[CompanyUnit]
  units_note : String
  company_unit_id : String
  company : CompanySetupOperation
  project : CompanySetupOperation
  project_name : String
  project_code : String
  project_unit_id : String
  exact_project : ProductCompanyProject?
  recent_project : CompanySetupRequest?
  storage : String
} derive(Debug, Eq)

///|
enum CompanySetupMsg {
  Refresh
  SessionRead(Int, Int, String)
  ProfileRead(String, Int, Int, Int, String)
  UnitsRead(String, Int, Int, Int, String)
  Restored(String, Int, String)
  Input(String, String)
  Save(String)
  Persisted(String, Int, String, String, Bool)
  Posted(String, Int, String, String, Int, String)
  Recover(String)
  ExactRead(String, Int, String, Int, String)
  UseProject
  DismissRecent
} derive(Debug, Eq)

///|
fn company_setup_operation() -> CompanySetupOperation {
  {
    request: None,
    phase: "idle",
    note: "",
    selection: -1,
    project_choice: -1,
    attempted: false,
    retrying: false,
    recover_only: false,
  }
}

///|
fn company_setup_initial() -> CompanySetupState {
  {
    actor: "",
    epoch: 0,
    session_request: 0,
    read_request: 0,
    session_state: "idle",
    profile_state: "idle",
    profile: None,
    units_state: "idle",
    units: [],
    units_note: "",
    company_unit_id: "",
    company: company_setup_operation(),
    project: company_setup_operation(),
    project_name: "",
    project_code: "",
    project_unit_id: "",
    exact_project: None,
    recent_project: None,
    storage: "",
  }
}

///|
fn company_setup_identifier(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_' ||
    c == '.' ||
    c == ':'
  })
}

///|
fn company_setup_profile(body : String) -> CompanyProfile?? {
  let root = @json.parse(body) catch { _ => return None }
  if !products_has(root, "profile") ||
    !(products_field(root, "success") is True) ||
    products_field(root, "code") != Json::number(0) {
    return None
  }
  let profile = products_field(root, "profile")
  if profile is Null && products_field(root, "persisted") is False {
    return Some(None)
  }
  let name = products_text(profile, "company_name")
  let id = products_text(profile, "bu_guid")
  let unit_name = products_text(profile, "bu_name")
  let unit_source = products_text(profile, "unit_source_kind")
  if !(products_field(root, "persisted") is True) ||
    products_text(profile, "company_id") != "current" ||
    products_text(profile, "source_kind") != "command" ||
    products_field(profile, "revision") != Json::number(1) ||
    name.is_empty() ||
    !(products_field(profile, "bu_name") is String(_)) ||
    !company_setup_identifier(id) ||
    !["command", "imported"].contains(unit_source) {
    None
  } else {
    Some(Some({ name, unit_id: id, unit_name, unit_source, }))
  }
}

///|
fn company_setup_unit_nodes(
  values : Array[Json],
  rows : Array[CompanyUnit],
  issues : Array[String],
  depth : Int,
) -> Unit {
  if depth > 64 {
    issues.push("层级过深的分支已省略")
    return
  }
  for value in values {
    let id = products_text(value, "buGuid")
    let name = products_text(value, "buName")
    let source = products_text(value, "sourceKind")
    if !company_setup_identifier(id) ||
      !(products_field(value, "buName") is String(_)) ||
      !["imported", "command"].contains(source) {
      issues.push("无效组织节点已省略")
    } else {
      rows.push({ id, name, source, })
    }
    match products_field(value, "children") {
      Array(children) =>
        company_setup_unit_nodes(children, rows, issues, depth + 1)
      _ => issues.push("无效子层级已省略")
    }
  }
}

///|
fn company_setup_units(body : String) -> CompanyUnitRead? {
  let root = @json.parse(body) catch { _ => return None }
  if !(products_field(root, "success") is True) ||
    products_field(root, "code") != Json::number(0) {
    return None
  }
  let values = match products_field(root, "data") {
    Array(v) => v
    _ => return None
  }
  let rows : Array[CompanyUnit] = []
  let issues : Array[String] = []
  company_setup_unit_nodes(values, rows, issues, 0)
  let unique = rows.filter(row => {
    rows.filter(other => other.id == row.id).length() == 1
  })
  let diagnostic = match products_field(root, "diagnostics") {
    Array(values) => !values.is_empty()
    _ => false
  }
  Some({
    rows: unique,
    note: if diagnostic ||
      !issues.is_empty() ||
      unique.length() != rows.length() {
      "部分组织数据存在缺失、重复或层级问题；仅显示可核实的唯一单位，异常单位需单独修复。"
    } else {
      ""
    },
  })
}

///|
fn company_setup_unit_label(unit : CompanyUnit) -> String {
  if unit.name.is_empty() {
    unit.id + "（名称未提供）"
  } else {
    unit.name + " · " + unit.id
  }
}

///|
fn company_setup_profile_verified(state : CompanySetupState) -> Bool {
  state.profile_state == "ready" &&
  state.units_state == "ready" &&
  (match state.profile {
    Some(profile) =>
      state.units.any(unit => {
        unit.id == profile.unit_id && unit.source == profile.unit_source
      })
    None => false
  })
}

///|
fn company_setup_profile_unit(state : CompanySetupState) -> CompanyUnit? {
  match state.profile {
    Some(profile) =>
      state.units
      .filter(unit => {
        unit.id == profile.unit_id && unit.source == profile.unit_source
      })
      .get(0)
    None => None
  }
}

///|
fn company_setup_busy(op : CompanySetupOperation) -> Bool {
  ["saving", "posting", "checking"].contains(op.phase)
}

///|
fn company_setup_editable(op : CompanySetupOperation) -> Bool {
  op.request is None && !company_setup_busy(op)
}

///|
fn company_setup_company_editable(model : Model) -> Bool {
  company_setup_editable(model.company_setup.company) &&
  !model.company_saved &&
  model.company_setup.profile is None &&
  model.company_setup.profile_state == "empty"
}

///|
fn company_setup_request_valid(
  request : CompanySetupRequest,
  kind : String,
) -> Bool {
  request.kind == kind &&
  company_setup_identifier(request.key) &&
  request.key.length() <= 96 &&
  !request.name.trim().is_empty() &&
  request.name.length() <= 256 &&
  (if kind == "company" {
    (request.unit_id.is_empty() || company_setup_identifier(request.unit_id)) &&
    request.project_code.is_empty() &&
    request.project_id.is_empty() &&
    request.product_id.is_empty()
  } else {
    kind == "project" &&
    company_setup_identifier(request.unit_id) &&
    company_setup_identifier(request.project_id) &&
    !request.project_code.trim().is_empty() &&
    request.project_code.length() <= 128 &&
    products_id_valid(request.product_id)
  })
}

///|
fn company_setup_body(request : CompanySetupRequest) -> String {
  let fields : Map[String, Json] = Map([])
  if request.kind == "company" {
    fields["companyName"] = Json::string(request.name)
    if !request.unit_id.is_empty() {
      fields["existingBuGuid"] = Json::string(request.unit_id)
    }
  } else {
    fields["projGuid"] = Json::string(request.project_id)
    fields["projCode"] = Json::string(request.project_code)
    fields["projName"] = Json::string(request.name)
    fields["buGuid"] = Json::string(request.unit_id)
  }
  Json::object(fields).stringify()
}

///|
fn company_setup_exact(
  request : CompanySetupRequest,
  body : String,
) -> ProductCompanyProject? {
  let root = @json.parse(body) catch { _ => return None }
  if products_text(root, "project_id") != request.project_id ||
    products_text(root, "project_code") != request.project_code ||
    products_text(root, "project_name") != request.name ||
    products_text(root, "bu_guid") != request.unit_id ||
    products_text(root, "source_kind") != "command" {
    None
  } else {
    Some({ id: request.project_id, name: request.name, source: "command", })
  }
}

///|
fn company_setup_op(
  state : CompanySetupState,
  kind : String,
) -> CompanySetupOperation {
  if kind == "company" {
    state.company
  } else {
    state.project
  }
}

///|
fn company_setup_set_op(
  state : CompanySetupState,
  kind : String,
  op : CompanySetupOperation,
) -> CompanySetupState {
  if kind == "company" {
    { ..state, company: op, }
  } else {
    { ..state, project: op, }
  }
}

///|
fn company_setup_apply(model : Model, state : CompanySetupState) -> Model {
  let verified = company_setup_profile_verified(state)
  {
    ..model,
    company_setup: state,
    company_saved: verified,
    company_name: if verified {
      state.profile.unwrap().name
    } else {
      model.company_name
    },
  }
}

///|
fn company_setup_with_project(
  model : Model,
  project : ProductCompanyProject,
) -> Model {
  {
    ..model,
    products: {
      ..model.products,
      projects: model.products.projects.filter(row => row.id != project.id) +
      [project],
      project_state: "ready",
      project_id: project.id,
      project_choice: model.products.project_choice + 1,
      // Exact selection supersedes any list read that began before it.
      project_request: model.products.project_request + 1,
    },
  }
}
