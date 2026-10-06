///|
/// Product is optional organizational metadata, never a project or workspace.
fn plan_task_product_id(body : Json) -> String? raise CompanyServiceError {
  match json_field(body, "product_id") {
    None | Some(Null) => None
    Some(String(text)) => {
      let value = text.trim().to_owned()
      if value.is_empty() {
        None
      } else if valid_identifier(value) {
        Some(value)
      } else {
        raise reject(422, "product_id contains unsupported characters")
      }
    }
    _ => raise reject(422, "product_id must be text or null")
  }
}

///|
fn plan_task_product_public(payload : Json) -> Json {
  match json_field(payload, "product_id") {
    Some(String(value)) if !value.is_empty() => Json::string(value)
    _ => Json::null()
  }
}

///|
/// Old create requests retain their exact canonical shape. Only explicit update
/// input changes an existing association; it never touches execution metadata.
fn plan_task_product_metadata(
  body : Json,
  create_mode : Bool,
) -> Json raise CompanyServiceError {
  match plan_task_product_id(body) {
    Some(id) => Json::object({ "product_id": Json::string(id) })
    None =>
      if !create_mode && json_field(body, "product_id") is Some(_) {
        Json::object({ "product_id": Json::null() })
      } else {
        Json::object({})
      }
  }
}

///|
fn plan_task_with_product_metadata(
  request : Json,
  body : Json,
  create_mode : Bool,
) -> Json raise CompanyServiceError {
  let fields = match request {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  match plan_task_product_metadata(body, create_mode) {
    Object(metadata) =>
      for key, value in metadata {
        fields.set(key, value)
      }
    _ => ()
  }
  Json::object(fields)
}

///|
/// Match the read model's json_text fallback, including null or malformed fields.
fn plan_task_json_text_sql(key : String, fallback : String) -> String {
  let literal = @postgres.sql_literal(key)
  "(CASE WHEN jsonb_typeof(payload->" +
  literal +
  ") IN ('string', 'number', 'boolean') THEN payload->>" +
  literal +
  " ELSE " +
  fallback +
  " END)"
}

///|
fn plan_task_product_sql() -> String {
  "(CASE WHEN jsonb_typeof(payload->'product_id') = 'string' THEN nullif(payload->>'product_id', '') ELSE NULL END)"
}

///|
fn plan_task_projection_sql(
  include_deleted : Bool,
  project_id : String?,
  task_type : String?,
  product_id : String?,
  task_id : String?,
) -> String {
  let predicates : Array[String] = []
  if !include_deleted {
    predicates.push("coalesce(payload->>'state', '') <> 'deleted'")
  }
  match project_id {
    Some(id) =>
      predicates.push(
        plan_task_json_text_sql("project_id", "''") +
        " = " +
        @postgres.sql_literal(id),
      )
    None => ()
  }
  match task_type {
    Some(value) =>
      predicates.push(
        plan_task_json_text_sql("task_type", "'task'") +
        " = " +
        @postgres.sql_literal(value),
      )
    None => ()
  }
  match product_id {
    Some(id) =>
      predicates.push(
        plan_task_product_sql() + " = " + @postgres.sql_literal(id),
      )
    None => ()
  }
  let exact = match task_id {
    Some(id) => " AND aggregate_id = " + @postgres.sql_literal(id)
    None => ""
  }
  let filter = if predicates.is_empty() {
    ""
  } else {
    " WHERE " + predicates.join(" AND ")
  }
  // Select the latest revision FIRST: filtering revisions by the old product or
  // state would resurrect retagged or deleted work. Return the complete scope.
  "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
  "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
  "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, " +
  "source_event_id, revision FROM company_aggregate_projection " +
  "WHERE aggregate_type = 'plan_task'" +
  exact +
  " ORDER BY aggregate_id, revision DESC) latest" +
  filter +
  " ORDER BY aggregate_id"
}

///|
fn project_plan_source_task_sql(
  project_id : String?,
  task_type : String?,
  product_id : String?,
  task_id : String?,
) -> String {
  let predicates = ["record_type = 'legacy/raw/jd_task'"]
  match project_id {
    Some(id) =>
      predicates.push(
        plan_task_json_text_sql(
          "proj_guid",
          plan_task_json_text_sql("project_id", "''"),
        ) +
        " = " +
        @postgres.sql_literal(id),
      )
    None => ()
  }
  match task_type {
    Some(value) =>
      predicates.push(
        plan_task_json_text_sql("task_type", "'task'") +
        " = " +
        @postgres.sql_literal(value),
      )
    None => ()
  }
  match product_id {
    Some(id) =>
      predicates.push(
        plan_task_product_sql() + " = " + @postgres.sql_literal(id),
      )
    None => ()
  }
  match task_id {
    Some(id) =>
      predicates.push(
        plan_task_json_text_sql(
          "task_guid",
          plan_task_json_text_sql("task_id", "record_id"),
        ) +
        " = " +
        @postgres.sql_literal(id),
      )
    None => ()
  }
  "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(source_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_record WHERE " +
  predicates.join(" AND ") +
  " ORDER BY record_id"
}

///|
async fn product_work_source_rows(
  sql : String,
) -> Array[SourceRow] raise CompanyServiceError {
  let output = run_sql(sql)
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid product work source row JSON")
      }
      match payload {
        Object(_) =>
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[1]),
            payload,
          })
        _ => raise fail("product work source row payload is not an object")
      }
    }
  }
  result
}

///|
async fn project_plan_source_task_rows(
  project_id : String?,
  task_type : String?,
  product_id : String?,
  task_id : String?,
) -> Array[SourceRow] raise CompanyServiceError {
  product_work_source_rows(
    project_plan_source_task_sql(project_id, task_type, product_id, task_id),
  )
}

///|
fn project_plan_task_matches(
  item : Json,
  project_id : String?,
  task_type : String?,
  product_id : String?,
) -> Bool {
  let project_ok = match project_id {
    Some(id) => json_text(item, "projGuid", "") == id
    None => true
  }
  let type_ok = match task_type {
    Some(value) => json_text(item, "taskType", "task") == value
    None => true
  }
  let product_ok = match product_id {
    Some(id) => plan_task_product_public(item) == Json::string(id)
    None => true
  }
  project_ok && type_ok && product_ok
}

///|
fn project_plan_select_task_items(
  raw : Array[SourceRow],
  commands : Array[SourceRow],
  users : Array[SourceRow],
  project_id : String?,
  task_type : String?,
  product_id : String?,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in raw {
    let item = project_plan_task_item(row, false, users)
    if project_plan_task_matches(item, project_id, task_type, product_id) {
      result.push(item)
    }
  }
  for row in commands {
    let item = project_plan_task_item(row, true, users)
    if json_text(row.payload, "state", "") != "deleted" &&
      project_plan_task_matches(item, project_id, task_type, product_id) {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_int(left, "sortOrder", 0) - json_int(right, "sortOrder", 0)
    if order == 0 {
      let begin_order = json_text(left, "planBeginDate", "").lexical_compare(
        json_text(right, "planBeginDate", ""),
      )
      if begin_order == 0 {
        json_text(left, "taskGuid", "").lexical_compare(
          json_text(right, "taskGuid", ""),
        )
      } else {
        begin_order
      }
    } else {
      order
    }
  })
  result
}

///|
fn project_plan_validate_task_scope(
  project_id : String?,
  task_type : String?,
  product_id : String?,
) -> Unit raise CompanyServiceError {
  for
    pair in [
      ("project_id", project_id),
      ("task_type", task_type),
      ("product_id", product_id),
    ] {
    match pair.1 {
      Some(value) if !valid_identifier(value) =>
        raise reject(422, "invalid " + pair.0)
      _ => ()
    }
  }
}

///|
async fn project_plan_task_items(
  project_id : String?,
  task_type : String?,
  product_id : String?,
) -> Array[Json] raise CompanyServiceError {
  project_plan_validate_task_scope(project_id, task_type, product_id)
  let users = raw_source_rows("sys_user", 500)
  let raw = project_plan_source_task_rows(
    project_id,
    task_type,
    product_id,
    None,
  )
  let commands = plan_task_projection_rows(
    false,
    project_id?,
    task_type?,
    product_id?,
  )
  project_plan_select_task_items(
    raw, commands, users, project_id, task_type, product_id,
  )
}

///|
fn project_plan_tasks_response(items : Array[Json]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(items),
    "items": Json::array(items),
    "source_kind": Json::string("imported_or_command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
  })
}

///|
async fn product_work_tasks_response(
  project_id : String?,
  task_type : String?,
  product_id : String?,
) -> Json raise CompanyServiceError {
  project_plan_validate_task_scope(project_id, task_type, product_id)
  if project_id is None && product_id is None {
    // Preserve the previous unfiltered 200/items envelope, but make its lack of
    // an unfiltered catalog contract explicit. This is not an access decision.
    return Json::object({
      "items": Json::array([]),
      "scope_required": Json::boolean(true),
      "message": Json::string(
        "Choose product_id or project_id to list tasks; an unfiltered task catalog is not implemented",
      ),
      "authorizing": Json::boolean(false),
    })
  }
  project_plan_tasks_response(
    project_plan_task_items(project_id, task_type, product_id),
  )
}

///|
/// Imported detail/report recovery uses the same projected ID fallbacks as its
/// public rows, without a company-wide cap hiding the requested task or report.
fn delivery_source_report_sql(report_id : String?, task_id : String?) -> String {
  let predicates = ["record_type = 'legacy/raw/jd_task_report'"]
  match report_id {
    Some(id) =>
      predicates.push(
        plan_task_json_text_sql(
          "report_guid",
          plan_task_json_text_sql("report_id", "record_id"),
        ) +
        " = " +
        @postgres.sql_literal(id),
      )
    None => ()
  }
  match task_id {
    Some(id) =>
      predicates.push(
        plan_task_json_text_sql(
          "task_id",
          plan_task_json_text_sql("task_guid", "''"),
        ) +
        " = " +
        @postgres.sql_literal(id),
      )
    None => ()
  }
  "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(source_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_record WHERE " +
  predicates.join(" AND ") +
  " ORDER BY record_id" +
  (if report_id is None && task_id is None { " LIMIT 500" } else { "" })
}

///|
async fn delivery_report_task_payload(
  task_id : String,
  project_id : String,
) -> Json? raise CompanyServiceError {
  let imported = project_plan_source_task_rows(
    Some(project_id),
    None,
    None,
    Some(task_id),
  )
  if !imported.is_empty() {
    return Some(imported[0].payload)
  }
  match plan_task_latest(task_id) {
    Some((Object(fields), revision)) if json_text(
        Json::object(fields),
        "state",
        "",
      ) !=
      "deleted" &&
      json_text(Json::object(fields), "project_id", "") == project_id => {
      let copy = fields.copy()
      copy.set("__delivery_task_revision", Json::number(revision.to_double()))
      Some(Json::object(copy))
    }
    _ => None
  }
}

///|
/// Product metadata is derived only from the authoritative task snapshot (or
/// saved canonical request on replay). A client-supplied report tag is ignored.
fn delivery_task_report_request(
  body : Json,
  actor_id : String,
  product_snapshot : Json,
) -> Json raise CompanyServiceError {
  let request = Json::object({
    "command_type": Json::string("report"),
    "report_id": Json::string(
      delivery_required_text(body, "report_id", "", true),
    ),
    "task_id": Json::string(delivery_required_text(body, "task_id", "", true)),
    "project_id": Json::string(
      delivery_required_text(body, "project_id", "", true),
    ),
    "progress_bps": Json::number(
      delivery_progress_bps(body, "progress_pct").to_double(),
    ),
    "report_date": Json::string(
      delivery_required_text(body, "report_date", "", false),
    ),
    "summary": Json::string(delivery_required_text(body, "summary", "", false)),
    "evidence_ids": delivery_evidence(body, "evidence_ids"),
    "actor_id": Json::string(actor_id),
    "state": Json::string("observed"),
  })
  // Preserve legacy request equality by omitting absent product metadata.
  let fields = match request {
    Object(fields) => fields
    _ => Map::new()
  }
  match plan_task_product_public(product_snapshot) {
    String(id) => fields.set("product_id", Json::string(id))
    _ => ()
  }
  match delivery_task_source_metadata(body, product_snapshot) {
    Object(metadata) =>
      for key, value in metadata {
        fields.set(key, value)
      }
    _ => ()
  }
  Json::object(fields)
}

///|
fn project_plan_task_report_item(
  report : Json,
  task_id : String,
  users : Array[SourceRow],
) -> Json {
  let operator_id = json_text(report, "operator_id", "")
  Json::object({
    "reportGuid": Json::string(json_text(report, "report_id", "")),
    "reportDate": Json::string(json_text(report, "report_date", "")),
    "progressPct": Json::string(json_text(report, "progress_pct", "0")),
    "summary": Json::string(json_text(report, "summary", "")),
    "task_id": Json::string(json_text(report, "task_id", task_id)),
    "product_id": plan_task_product_public(report),
    "delivery_source": json_field(report, "delivery_source").unwrap_or(
      Json::null(),
    ),
    "delivery_source_snapshot": json_field(report, "delivery_source_snapshot").unwrap_or(
      Json::null(),
    ),
    "evidence_ids": json_field(report, "evidence_ids").unwrap_or(
      Json::array([]),
    ),
    "sourceId": Json::string(json_text(report, "source_id", "")),
    "operatorGuid": Json::string(operator_id),
    "operatorName": Json::string(project_task_user_name(users, operator_id)),
    "sourceKind": Json::string(json_text(report, "source_kind", "imported")),
  })
}
