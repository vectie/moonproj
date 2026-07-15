///|
/// Delivery source and command boundary for the native PostgreSQL service.
fn delivery_aggregate(family : String) -> String {
  match family {
    "progress" => "delivery_progress"
    "output" => "delivery_output"
    "task_report" => "task_report"
    _ => ""
  }
}

///|
fn delivery_source_table(family : String) -> String {
  match family {
    "progress" => "proj_progress"
    "output" => "proj_output"
    "task_report" => "jd_task_report"
    _ => ""
  }
}

///|
async fn delivery_projection_rows(
  family : String,
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
  let aggregate_type = delivery_aggregate(family)
  if aggregate_type.is_empty() {
    raise fail("unsupported delivery projection family")
  }
  let deleted_clause = if include_deleted {
    ""
  } else {
    " WHERE coalesce(payload->>'state', '') <> 'deleted'"
  }
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), " +
    "encode(convert_to(payload::text, 'UTF8'), 'hex'), " +
    "encode(convert_to(source_event_id, 'UTF8'), 'hex'), revision::text " +
    "FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, " +
    "source_event_id, revision FROM company_aggregate_projection " +
    "WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " ORDER BY aggregate_id, revision DESC) latest" +
    deleted_clause +
    " ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid delivery projection JSON")
      }
      match payload {
        Object(payload_fields) => {
          payload_fields.set(
            "__revision",
            Json::number(parse_decimal(row[3]).to_double()),
          )
          result.push({
            record_id: decode_hex(row[0]),
            source_id: decode_hex(row[2]),
            payload: Json::object(payload_fields),
          })
        }
        _ => raise fail("delivery projection payload is not an object")
      }
    }
  }
  result
}

///|
fn delivery_number(
  value : Json,
  primary : String,
  fallback : String,
  default : Double,
) -> Double {
  marketing_number(value, primary, fallback, default)
}

///|
fn delivery_percent_text(bps : Int) -> String {
  round_places(bps.to_double() / 100.0, 2).to_string()
}

///|
fn delivery_bps_from_payload(
  payload : Json,
  primary : String,
  fallback : String,
) -> Int {
  let value = delivery_number(payload, primary, fallback, 0.0)
  (value + 0.5).to_int()
}

///|
fn delivery_source_id(row : SourceRow, prefix : String) -> String {
  if !row.source_id.is_empty() {
    row.source_id
  } else {
    "erp:" + prefix + ":" + row.record_id
  }
}

///|
fn delivery_runtime_progress_item(row : SourceRow, command : Bool) -> Json {
  let payload = row.payload
  let id = if command {
    row.record_id
  } else {
    json_text(
      payload,
      "progress_id",
      json_text(payload, "progress_guid", row.record_id),
    )
  }
  let project_id = if command {
    json_text(payload, "project_id", "")
  } else {
    json_text(payload, "proj_guid", json_text(payload, "project_id", ""))
  }
  let plan_bps = if command {
    delivery_bps_from_payload(payload, "plan_pct_bps", "plan_bps")
  } else {
    (delivery_number(payload, "plan_pct", "planPct", 0.0) * 100.0 + 0.5).to_int()
  }
  let actual_bps = if command {
    delivery_bps_from_payload(payload, "actual_progress_bps", "progress_bps")
  } else {
    (delivery_number(payload, "actual_pct", "actualPct", 0.0) * 100.0 + 0.5).to_int()
  }
  let source_id = delivery_source_id(row, "proj_progress")
  let source_kind = if command { "command" } else { "imported" }
  let value : Map[String, Json] = {
    "progress_id": Json::string(id),
    "project_id": Json::string(project_id),
    "building_no": Json::string(json_text(payload, "building_no", "")),
    "stage": Json::string(json_text(payload, "stage", "")),
    "plan_date": Json::string(json_text(payload, "plan_date", "")),
    "plan_pct": Json::string(
      if command {
        delivery_percent_text(plan_bps)
      } else {
        json_text(payload, "plan_pct", "0")
      },
    ),
    "actual_pct": Json::string(
      if command {
        delivery_percent_text(actual_bps)
      } else {
        json_text(payload, "actual_pct", "0")
      },
    ),
    "actual_date": Json::string(json_text(payload, "actual_date", "")),
    "contract_id": Json::string(
      if command {
        json_text(payload, "contract_id", "")
      } else {
        json_text(payload, "contract_guid", "")
      },
    ),
    "milestone_id": Json::string(
      if command {
        json_text(payload, "milestone_id", "")
      } else {
        json_text(payload, "milestone_guid", "")
      },
    ),
    "state": Json::string(
      json_text(payload, "state", if command { "draft" } else { "pending" }),
    ),
    "remark": Json::string(json_text(payload, "remark", "")),
    "reported_by": Json::string(
      if command {
        json_text(payload, "actor_id", "")
      } else {
        json_text(payload, "reported_by", "")
      },
    ),
    "evidence_ids": json_field(payload, "evidence_ids").unwrap_or(
      Json::array([]),
    ),
    "completed_value_minor": Json::number(
      json_int(payload, "completed_value_minor", 0).to_double(),
    ),
    "source_kind": Json::string(source_kind),
    "source_id": Json::string(source_id),
    "source_table": Json::string(
      if command {
        "company_command"
      } else {
        "proj_progress"
      },
    ),
  }
  if command {
    value.set(
      "revision",
      Json::number(json_int(payload, "__revision", 0).to_double()),
    )
  }
  value.set("progress_guid", Json::string(id))
  value.set("proj_guid", Json::string(project_id))
  value.set("progressGuid", Json::string(id))
  value.set("projGuid", Json::string(project_id))
  value.set("planDate", Json::string(json_text(payload, "plan_date", "")))
  value.set(
    "planPct",
    Json::string(
      if command {
        delivery_percent_text(plan_bps)
      } else {
        json_text(payload, "plan_pct", "0")
      },
    ),
  )
  value.set(
    "actualPct",
    Json::string(
      if command {
        delivery_percent_text(actual_bps)
      } else {
        json_text(payload, "actual_pct", "0")
      },
    ),
  )
  value.set("actualDate", Json::string(json_text(payload, "actual_date", "")))
  value.set(
    "contractGuid",
    Json::string(
      if command {
        json_text(payload, "contract_id", "")
      } else {
        json_text(payload, "contract_guid", "")
      },
    ),
  )
  value.set(
    "milestoneGuid",
    Json::string(
      if command {
        json_text(payload, "milestone_id", "")
      } else {
        json_text(payload, "milestone_guid", "")
      },
    ),
  )
  Json::object(value)
}

///|
fn delivery_runtime_output_item(
  row : SourceRow,
  command : Bool,
  contract_name : String,
) -> Json {
  let payload = row.payload
  let id = if command {
    row.record_id
  } else {
    json_text(
      payload,
      "output_id",
      json_text(payload, "output_guid", row.record_id),
    )
  }
  let project_id = if command {
    json_text(payload, "project_id", "")
  } else {
    json_text(payload, "proj_guid", json_text(payload, "project_id", ""))
  }
  let contract_id = if command {
    json_text(payload, "contract_id", "")
  } else {
    json_text(payload, "contract_guid", json_text(payload, "contract_id", ""))
  }
  let source_id = delivery_source_id(row, "proj_output")
  let source_kind = if command { "command" } else { "imported" }
  let value : Map[String, Json] = {
    "output_id": Json::string(id),
    "output_code": Json::string(json_text(payload, "output_code", "")),
    "project_id": Json::string(project_id),
    "contract_id": Json::string(contract_id),
    "period": Json::string(json_text(payload, "period", "")),
    "output_amount": Json::string(json_text(payload, "output_amount", "0")),
    "confirm_amount": Json::string(json_text(payload, "confirm_amount", "0")),
    "state": Json::string(
      json_text(payload, "state", if command { "reported" } else { "reported" }),
    ),
    "remark": Json::string(json_text(payload, "remark", "")),
    "confirmed_by": Json::string(
      if command && json_text(payload, "state", "") == "confirmed" {
        json_text(payload, "actor_id", "")
      } else {
        json_text(payload, "confirmed_by", "")
      },
    ),
    "confirmed_at": Json::string(json_text(payload, "confirmed_at", "")),
    "evidence_ids": json_field(payload, "evidence_ids").unwrap_or(
      Json::array([]),
    ),
    "source_kind": Json::string(source_kind),
    "source_id": Json::string(source_id),
    "source_table": Json::string(
      if command {
        "company_command"
      } else {
        "proj_output"
      },
    ),
    "contract_name": Json::string(contract_name),
  }
  if command {
    value.set(
      "revision",
      Json::number(json_int(payload, "__revision", 0).to_double()),
    )
  }
  value.set("output_guid", Json::string(id))
  value.set("proj_guid", Json::string(project_id))
  value.set("contract_guid", Json::string(contract_id))
  value.set("outputGuid", Json::string(id))
  value.set("outputCode", Json::string(json_text(payload, "output_code", "")))
  value.set("projGuid", Json::string(project_id))
  value.set("contractGuid", Json::string(contract_id))
  value.set(
    "outputAmount",
    Json::string(json_text(payload, "output_amount", "0")),
  )
  value.set(
    "confirmAmount",
    Json::string(json_text(payload, "confirm_amount", "0")),
  )
  Json::object(value)
}

///|
fn delivery_task_item(row : SourceRow) -> Json {
  let payload = row.payload
  let id = json_text(
    payload,
    "task_guid",
    json_text(payload, "task_id", row.record_id),
  )
  let progress_pct = delivery_number(
    payload, "progress_pct", "progressPct", 0.0,
  )
  Json::object({
    "task_id": Json::string(id),
    "task_code": Json::string(json_text(payload, "task_code", "")),
    "task_name": Json::string(json_text(payload, "task_name", "")),
    "project_id": Json::string(
      json_text(payload, "proj_guid", json_text(payload, "project_id", "")),
    ),
    "task_type": Json::string(json_text(payload, "task_type", "task")),
    "parent_task_id": Json::string(json_text(payload, "parent_task_guid", "")),
    "plan_begin_date": Json::string(json_text(payload, "plan_begin_date", "")),
    "plan_end_date": Json::string(json_text(payload, "plan_end_date", "")),
    "actual_begin_date": Json::string(
      json_text(payload, "actual_begin_date", ""),
    ),
    "actual_end_date": Json::string(json_text(payload, "actual_end_date", "")),
    "progress_pct": Json::string(progress_pct.to_string()),
    "progress_bps": Json::number((progress_pct * 100.0).to_int().to_double()),
    "owner_id": Json::string(json_text(payload, "owner_guid", "")),
    "status": Json::string(json_text(payload, "status", "pending")),
    "remarks": Json::string(json_text(payload, "remarks", "")),
    "sort_order": Json::number(json_int(payload, "sort_order", 0).to_double()),
    "source_kind": Json::string("imported"),
    "source_id": Json::string(delivery_source_id(row, "jd_task")),
    "source_table": Json::string("jd_task"),
  })
}

///|
fn delivery_contract_name(
  contracts : Array[SourceRow],
  contract_id : String,
) -> String {
  if contract_id.is_empty() {
    return ""
  }
  for contract in contracts {
    let payload = contract.payload
    let id = json_text(payload, "contract_guid", contract.record_id)
    if id == contract_id || contract.record_id == contract_id {
      return json_text(
        payload,
        "contract_name",
        json_text(payload, "ht_name", ""),
      )
    }
  }
  ""
}

///|
fn delivery_report_item(row : SourceRow, command : Bool) -> Json {
  let payload = row.payload
  let id = if command {
    row.record_id
  } else {
    json_text(
      payload,
      "report_guid",
      json_text(payload, "report_id", row.record_id),
    )
  }
  let task_id = json_text(
    payload,
    "task_id",
    json_text(payload, "task_guid", ""),
  )
  let project_id = json_text(payload, "project_id", "")
  let progress_bps = if command {
    delivery_bps_from_payload(payload, "progress_bps", "")
  } else {
    (delivery_number(payload, "progress_pct", "progressPct", 0.0) * 100.0 + 0.5).to_int()
  }
  Json::object({
    "report_id": Json::string(id),
    "task_id": Json::string(task_id),
    "project_id": Json::string(project_id),
    "progress_pct": Json::string(
      if command {
        delivery_percent_text(progress_bps)
      } else {
        json_text(payload, "progress_pct", "0")
      },
    ),
    "progress_bps": Json::number(progress_bps.to_double()),
    "report_date": Json::string(json_text(payload, "report_date", "")),
    "summary": Json::string(json_text(payload, "summary", "")),
    "operator_id": Json::string(
      if command {
        json_text(payload, "actor_id", "")
      } else {
        json_text(payload, "operator_guid", "")
      },
    ),
    "state": Json::string(
      json_text(payload, "state", if command { "observed" } else { "observed" }),
    ),
    "evidence_ids": json_field(payload, "evidence_ids").unwrap_or(
      Json::array([]),
    ),
    "source_kind": Json::string(if command { "command" } else { "imported" }),
    "source_id": Json::string(delivery_source_id(row, "jd_task_report")),
    "source_table": Json::string(
      if command {
        "company_command"
      } else {
        "jd_task_report"
      },
    ),
  })
}

///|
fn delivery_project_matches(value : Json, project_id : String?) -> Bool {
  match project_id {
    None => true
    Some(id) => json_text(value, "project_id", "") == id
  }
}

///|
async fn delivery_progress_items(
  progress_id : String?,
  project_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let raw = raw_source_rows("proj_progress", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = delivery_runtime_progress_item(row, false)
    let id_ok = match progress_id {
      Some(id) => json_text(item, "progress_id", "") == id
      None => true
    }
    if id_ok && delivery_project_matches(item, project_id) {
      result.push(item)
    }
  }
  let commands = delivery_projection_rows("progress", false)
  for row in commands {
    let item = delivery_runtime_progress_item(row, true)
    let id_ok = match progress_id {
      Some(id) => json_text(item, "progress_id", "") == id
      None => true
    }
    if id_ok && delivery_project_matches(item, project_id) {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(left, "plan_date", "").lexical_compare(
      json_text(right, "plan_date", ""),
    )
    if order == 0 {
      json_text(left, "progress_id", "").lexical_compare(
        json_text(right, "progress_id", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
async fn delivery_outputs_items(
  output_id : String?,
  project_id : String?,
  period : String?,
  state : String?,
) -> Array[Json] raise CompanyServiceError {
  let contracts = raw_source_rows("cb_contract", 500)
  let raw = raw_source_rows("proj_output", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = delivery_runtime_output_item(
      row,
      false,
      delivery_contract_name(
        contracts,
        json_text(row.payload, "contract_guid", ""),
      ),
    )
    let id_ok = match output_id {
      Some(id) => json_text(item, "output_id", "") == id
      None => true
    }
    let project_ok = delivery_project_matches(item, project_id)
    let period_ok = match period {
      Some(value) => json_text(item, "period", "") == value
      None => true
    }
    let state_ok = match state {
      Some(value) => json_text(item, "state", "") == value
      None => true
    }
    if id_ok && project_ok && period_ok && state_ok {
      result.push(item)
    }
  }
  let commands = delivery_projection_rows("output", false)
  for row in commands {
    let item = delivery_runtime_output_item(
      row,
      true,
      delivery_contract_name(
        contracts,
        json_text(row.payload, "contract_id", ""),
      ),
    )
    let id_ok = match output_id {
      Some(id) => json_text(item, "output_id", "") == id
      None => true
    }
    let project_ok = delivery_project_matches(item, project_id)
    let period_ok = match period {
      Some(value) => json_text(item, "period", "") == value
      None => true
    }
    let state_ok = match state {
      Some(value) => json_text(item, "state", "") == value
      None => true
    }
    if id_ok && project_ok && period_ok && state_ok {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_text(right, "period", "").lexical_compare(
      json_text(left, "period", ""),
    )
    if order == 0 {
      json_text(right, "output_id", "").lexical_compare(
        json_text(left, "output_id", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
async fn delivery_task_items(
  project_id : String?,
  task_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let raw = raw_source_rows("jd_task", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = delivery_task_item(row)
    let project_ok = delivery_project_matches(item, project_id)
    let task_ok = match task_id {
      Some(value) => json_text(item, "task_id", "") == value
      None => true
    }
    if project_ok && task_ok {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let order = json_int(left, "sort_order", 0) -
      json_int(right, "sort_order", 0)
    if order == 0 {
      json_text(left, "task_id", "").lexical_compare(
        json_text(right, "task_id", ""),
      )
    } else {
      order
    }
  })
  result
}

///|
async fn delivery_task_report_items(
  report_id : String?,
  task_id : String?,
) -> Array[Json] raise CompanyServiceError {
  let raw = raw_source_rows("jd_task_report", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = delivery_report_item(row, false)
    let report_ok = match report_id {
      Some(value) => json_text(item, "report_id", "") == value
      None => true
    }
    let task_ok = match task_id {
      Some(value) => json_text(item, "task_id", "") == value
      None => true
    }
    if report_ok && task_ok {
      result.push(item)
    }
  }
  let commands = delivery_projection_rows("task_report", false)
  for row in commands {
    let item = delivery_report_item(row, true)
    let report_ok = match report_id {
      Some(value) => json_text(item, "report_id", "") == value
      None => true
    }
    let task_ok = match task_id {
      Some(value) => json_text(item, "task_id", "") == value
      None => true
    }
    if report_ok && task_ok {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    json_text(right, "report_date", "").lexical_compare(
      json_text(left, "report_date", ""),
    )
  })
  result
}

///|
fn delivery_missing_tables(
  coverage : Json,
  tables : Array[String],
) -> Array[Json] {
  let missing : Array[Json] = []
  for table in tables {
    if json_int(coverage, table, 0) == 0 {
      missing.push(Json::string(table))
    }
  }
  missing
}

///|
fn delivery_runtime_metadata(
  coverage : Json,
  command_projection : Bool,
  tables : Array[String],
) -> Json {
  Json::object({
    "source_kind": Json::string(
      if command_projection {
        "imported_or_command"
      } else {
        "imported_or_empty"
      },
    ),
    "source_coverage": coverage,
    "missing_or_empty_source_tables": Json::array(
      delivery_missing_tables(coverage, tables),
    ),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(command_projection),
    "command_projection": Json::boolean(command_projection),
    "delivery_effect": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn delivery_progress_runtime_response(
  progress_id : String?,
  project_id : String?,
) -> Json raise CompanyServiceError {
  let items = delivery_progress_items(progress_id, project_id)
  let raw = raw_source_rows("proj_progress", 500)
  let commands = delivery_projection_rows("progress", false)
  let coverage = Json::object({
    "proj_progress": Json::number(raw.length().to_double()),
    "company_delivery_progress": Json::number(commands.length().to_double()),
  })
  match
    delivery_runtime_metadata(coverage, !commands.is_empty(), ["proj_progress"]) {
    Object(metadata) => {
      metadata.set("items", Json::array(items))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery progress metadata")
  }
}

///|
async fn delivery_outputs_runtime_response(
  output_id : String?,
  project_id : String?,
  period : String?,
  state : String?,
) -> Json raise CompanyServiceError {
  let items = delivery_outputs_items(output_id, project_id, period, state)
  let raw = raw_source_rows("proj_output", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let commands = delivery_projection_rows("output", false)
  let coverage = Json::object({
    "proj_output": Json::number(raw.length().to_double()),
    "cb_contract": Json::number(contracts.length().to_double()),
    "company_delivery_output": Json::number(commands.length().to_double()),
  })
  match
    delivery_runtime_metadata(coverage, !commands.is_empty(), [
      "proj_output", "cb_contract",
    ]) {
    Object(metadata) => {
      metadata.set("items", Json::array(items))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery output metadata")
  }
}

///|
async fn delivery_tasks_runtime_response(
  project_id : String?,
  task_id : String?,
) -> Json raise CompanyServiceError {
  let items = delivery_task_items(project_id, task_id)
  let raw = raw_source_rows("jd_task", 500)
  let coverage = Json::object({
    "jd_task": Json::number(raw.length().to_double()),
  })
  match delivery_runtime_metadata(coverage, false, ["jd_task"]) {
    Object(metadata) => {
      metadata.set("items", Json::array(items))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery task metadata")
  }
}

///|
async fn delivery_reports_runtime_response(
  report_id : String?,
  task_id : String?,
) -> Json raise CompanyServiceError {
  let items = delivery_task_report_items(report_id, task_id)
  let raw = raw_source_rows("jd_task_report", 500)
  let commands = delivery_projection_rows("task_report", false)
  let coverage = Json::object({
    "jd_task_report": Json::number(raw.length().to_double()),
    "company_task_report": Json::number(commands.length().to_double()),
  })
  match
    delivery_runtime_metadata(coverage, !commands.is_empty(), ["jd_task_report"]) {
    Object(metadata) => {
      metadata.set("items", Json::array(items))
      Json::object(metadata)
    }
    _ => raise fail("invalid delivery report metadata")
  }
}

///|
async fn delivery_plan_summary_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "project_id is invalid")
  }
  let tasks = delivery_task_items(Some(project_id), None)
  let mut done = 0
  let mut in_progress = 0
  let mut pending = 0
  let mut overdue = 0
  let mut blocked = 0
  for task in tasks {
    match json_text(task, "status", "pending") {
      "done" => done += 1
      "in_progress" => in_progress += 1
      "overdue" => overdue += 1
      "blocked" => blocked += 1
      _ => pending += 1
    }
  }
  Json::object({
    "done": Json::number(done.to_double()),
    "in_progress": Json::number(in_progress.to_double()),
    "pending": Json::number(pending.to_double()),
    "overdue": Json::number(overdue.to_double()),
    "blocked": Json::number(blocked.to_double()),
    "total": Json::number(
      (done + in_progress + pending + overdue + blocked).to_double(),
    ),
    "project_id": Json::string(project_id),
    "source_kind": Json::string("imported_or_command"),
    "authorizing": Json::boolean(false),
  })
}

///|
async fn delivery_overview_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "project_id is invalid")
  }
  let progress = delivery_progress_items(None, Some(project_id))
  let outputs = delivery_outputs_items(None, Some(project_id), None, None)
  let tasks = delivery_task_items(Some(project_id), None)
  let all_reports = delivery_task_report_items(None, None)
  let reports : Array[Json] = []
  for report in all_reports {
    let task_id = json_text(report, "task_id", "")
    for task in tasks {
      if json_text(task, "task_id", "") == task_id {
        reports.push(report)
        break
      }
    }
  }
  let plan_summary = delivery_plan_summary_response(project_id)
  let raw_progress = raw_source_rows("proj_progress", 500)
  let raw_outputs = raw_source_rows("proj_output", 500)
  let raw_tasks = raw_source_rows("jd_task", 500)
  let raw_reports = raw_source_rows("jd_task_report", 500)
  let mut command_projection = false
  for item in progress {
    if json_text(item, "source_kind", "") == "command" {
      command_projection = true
    }
  }
  for item in outputs {
    if json_text(item, "source_kind", "") == "command" {
      command_projection = true
    }
  }
  for item in reports {
    if json_text(item, "source_kind", "") == "command" {
      command_projection = true
    }
  }
  Json::object({
    "progress": Json::array(progress),
    "outputs": Json::array(outputs),
    "tasks": Json::array(tasks),
    "reports": Json::array(reports),
    "plan_summary": plan_summary,
    "source_kind": Json::string(
      if command_projection {
        "imported_or_command"
      } else {
        "imported_or_empty"
      },
    ),
    "source_coverage": Json::object({
      "proj_progress": Json::number(raw_progress.length().to_double()),
      "proj_output": Json::number(raw_outputs.length().to_double()),
      "jd_task": Json::number(raw_tasks.length().to_double()),
      "jd_task_report": Json::number(raw_reports.length().to_double()),
    }),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(command_projection),
    "delivery_effect": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn delivery_required_text(
  body : Json,
  primary : String,
  fallback : String,
  identifier : Bool,
) -> String raise CompanyServiceError {
  let value = match marketing_lookup(body, primary, fallback) {
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " is required")
  }
  if value.is_empty() {
    raise reject(422, primary + " is required")
  }
  if identifier && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn delivery_optional_text(
  body : Json,
  primary : String,
  fallback : String,
) -> String raise CompanyServiceError {
  match marketing_lookup(body, primary, fallback) {
    None | Some(Null) => ""
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
}

///|
fn delivery_evidence(
  body : Json,
  key : String,
) -> Json raise CompanyServiceError {
  match json_field(body, key) {
    Some(Array(values)) if !values.is_empty() => {
      let result : Array[Json] = []
      for value in values {
        let item = match value {
          String(text) => text.trim().to_owned()
          _ => raise reject(422, key + " contains an invalid evidence id")
        }
        if !valid_identifier(item) {
          raise reject(422, key + " contains an invalid evidence id")
        }
        result.push(Json::string(item))
      }
      Json::array(result)
    }
    _ => raise reject(422, key + " must contain at least one evidence id")
  }
}

///|
fn delivery_progress_bps(
  body : Json,
  key : String,
) -> Int raise CompanyServiceError {
  let value = match json_field(body, "progress_bps") {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    None =>
      match json_field(body, key) {
        Some(Number(number, ..)) => number * 100.0
        Some(String(text)) => parse_number(text.trim().to_owned()) * 100.0
        _ => raise reject(422, key + " must be a number")
      }
    _ => raise reject(422, "progress_bps must be an integer")
  }
  let bps = (value + 0.5).to_int()
  if bps < 0 || bps > 10000 {
    raise reject(422, "progress must be between 0 and 100 percent")
  }
  bps
}

///|
fn delivery_amount_minor(
  body : Json,
  key : String,
) -> Int raise CompanyServiceError {
  let value = match json_field(body, key) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    _ => raise reject(422, key + " must be a non-negative integer")
  }
  if value < 0.0 || value != value || value != value.to_int().to_double() {
    raise reject(422, key + " must be a non-negative integer")
  }
  value.to_int()
}

///|
async fn delivery_task_exists(
  task_id : String,
  project_id : String,
) -> Bool raise CompanyServiceError {
  let tasks = delivery_task_items(Some(project_id), Some(task_id))
  if !tasks.is_empty() {
    return true
  }
  for row in plan_task_projection_rows(false) {
    let payload = row.payload
    if row.record_id == task_id &&
      json_text(payload, "project_id", "") == project_id {
      return true
    }
  }
  false
}

///|
async fn delivery_imported_exists(
  family : String,
  id : String,
) -> Bool raise CompanyServiceError {
  let table = delivery_source_table(family)
  let rows = raw_source_rows(table, 500)
  for row in rows {
    let key = if family == "progress" {
      json_text(
        row.payload,
        "progress_guid",
        json_text(row.payload, "progress_id", row.record_id),
      )
    } else if family == "output" {
      json_text(
        row.payload,
        "output_guid",
        json_text(row.payload, "output_id", row.record_id),
      )
    } else {
      json_text(
        row.payload,
        "report_guid",
        json_text(row.payload, "report_id", row.record_id),
      )
    }
    if key == id || row.record_id == id {
      return true
    }
  }
  false
}

///|
async fn delivery_latest_payload(
  family : String,
  id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let aggregate_type = delivery_aggregate(family)
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') " +
    "FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid delivery projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn delivery_command_request(
  family : String,
  command_type : String,
  aggregate_id : String?,
  body : Json,
  actor_id : String,
) -> (String, Json, Bool, String?, String) raise CompanyServiceError {
  let aggregate_type = delivery_aggregate(family)
  if aggregate_type.is_empty() {
    raise reject(404, "unsupported delivery command family")
  }
  if family == "task_report" {
    let report_id = delivery_required_text(body, "report_id", "", true)
    let task_id = delivery_required_text(body, "task_id", "", true)
    let project_id = delivery_required_text(body, "project_id", "", true)
    if !delivery_task_exists(task_id, project_id) {
      raise reject(
        404, "task report target task was not found in the source projection",
      )
    }
    let request = Json::object({
      "command_type": Json::string("report"),
      "report_id": Json::string(report_id),
      "task_id": Json::string(task_id),
      "project_id": Json::string(project_id),
      "progress_bps": Json::number(
        delivery_progress_bps(body, "progress_pct").to_double(),
      ),
      "report_date": Json::string(
        delivery_required_text(body, "report_date", "", false),
      ),
      "summary": Json::string(
        delivery_required_text(body, "summary", "", false),
      ),
      "evidence_ids": delivery_evidence(body, "evidence_ids"),
      "actor_id": Json::string(actor_id),
      "state": Json::string("observed"),
    })
    if delivery_imported_exists(family, report_id) {
      raise reject(
        409, "imported task report ids are read-only; use a new local report id",
      )
    }
    return (report_id, request, true, None, "observed")
  }
  if command_type == "create" {
    let id_key = if family == "progress" { "progress_id" } else { "output_id" }
    let id = delivery_required_text(
      body,
      id_key,
      if family == "progress" {
        "progress_guid"
      } else {
        "output_guid"
      },
      true,
    )
    if delivery_imported_exists(family, id) {
      raise reject(
        409, "imported delivery records are read-only; use a new local id",
      )
    }
    if family == "progress" {
      let currency = delivery_required_text(body, "currency", "", true).to_upper()
      if currency.length() != 3 {
        raise reject(422, "currency must be a three-letter code")
      }
      let project_id = delivery_required_text(
        body, "project_id", "proj_guid", true,
      )
      let project_scope = delivery_required_text(
        body, "project_scope", "", true,
      )
      if project_scope != "project:" + project_id {
        raise reject(422, "project_scope must match project_id")
      }
      let request = Json::object({
        "command_type": Json::string("create"),
        "progress_id": Json::string(id),
        "project_id": Json::string(project_id),
        "principal_id": Json::string(
          delivery_required_text(body, "principal_id", "", true),
        ),
        "project_scope": Json::string(
          delivery_required_text(body, "project_scope", "", true),
        ),
        "building_no": Json::string(
          delivery_optional_text(body, "building_no", ""),
        ),
        "stage": Json::string(delivery_required_text(body, "stage", "", false)),
        "plan_date": Json::string(delivery_optional_text(body, "plan_date", "")),
        "plan_pct_bps": Json::number(
          delivery_progress_bps(body, "plan_pct").to_double(),
        ),
        "completed_value_minor": Json::number(
          delivery_amount_minor(body, "completed_value_minor").to_double(),
        ),
        "currency": Json::string(currency),
        "contract_id": Json::string(
          delivery_optional_text(body, "contract_id", "contract_guid"),
        ),
        "milestone_id": Json::string(
          delivery_optional_text(body, "milestone_id", "milestone_guid"),
        ),
        "evidence_ids": delivery_evidence(body, "evidence_ids"),
        "remark": Json::string(delivery_optional_text(body, "remark", "")),
        "actor_id": Json::string(actor_id),
        "state": Json::string("draft"),
      })
      return (id, request, true, None, "draft")
    }
    let request = Json::object({
      "command_type": Json::string("create"),
      "output_id": Json::string(id),
      "output_code": Json::string(
        delivery_optional_text(body, "output_code", ""),
      ),
      "project_id": Json::string(
        delivery_required_text(body, "project_id", "proj_guid", true),
      ),
      "contract_id": Json::string(
        delivery_required_text(body, "contract_id", "contract_guid", true),
      ),
      "period": Json::string(delivery_required_text(body, "period", "", false)),
      "output_amount": Json::string(
        delivery_required_text(body, "output_amount", "", false),
      ),
      "confirm_amount": Json::string("0"),
      "evidence_ids": delivery_evidence(body, "evidence_ids"),
      "remark": Json::string(delivery_optional_text(body, "remark", "")),
      "actor_id": Json::string(actor_id),
      "state": Json::string("reported"),
    })
    return (id, request, true, None, "reported")
  }
  let id = match aggregate_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "delivery aggregate id is required")
  }
  if family == "progress" {
    if command_type == "report" {
      return (
        id,
        Json::object({
          "command_type": Json::string("report"),
          "progress_id": Json::string(id),
          "actual_progress_bps": Json::number(
            delivery_progress_bps(body, "progress_pct").to_double(),
          ),
          "actual_date": Json::string(
            delivery_required_text(body, "actual_date", "", false),
          ),
          "evidence_ids": delivery_evidence(body, "evidence_ids"),
          "remark": Json::string(delivery_optional_text(body, "remark", "")),
          "actor_id": Json::string(actor_id),
        }),
        false,
        Some("draft"),
        "submitted",
      )
    }
    if command_type == "accept" {
      return (
        id,
        Json::object({
          "command_type": Json::string("accept"),
          "progress_id": Json::string(id),
          "acceptance_id": Json::string(
            delivery_required_text(body, "acceptance_id", "", true),
          ),
          "acceptance_evidence_ids": delivery_evidence(
            body, "acceptance_evidence_ids",
          ),
          "actor_id": Json::string(actor_id),
        }),
        false,
        Some("submitted"),
        "accepted",
      )
    }
    if command_type == "reject" {
      return (
        id,
        Json::object({
          "command_type": Json::string("reject"),
          "progress_id": Json::string(id),
          "reason": Json::string(
            delivery_required_text(body, "reason", "", false),
          ),
          "actor_id": Json::string(actor_id),
        }),
        false,
        Some("submitted"),
        "rejected",
      )
    }
    if command_type == "delete" {
      return (
        id,
        Json::object({
          "command_type": Json::string("delete"),
          "progress_id": Json::string(id),
          "reason": Json::string(delivery_optional_text(body, "reason", "")),
          "actor_id": Json::string(actor_id),
        }),
        false,
        None,
        "deleted",
      )
    }
  }
  if family == "output" && command_type == "confirm" {
    return (
      id,
      Json::object({
        "command_type": Json::string("confirm"),
        "output_id": Json::string(id),
        "confirm_amount": Json::string(
          delivery_required_text(body, "confirm_amount", "", false),
        ),
        "evidence_ids": delivery_evidence(body, "evidence_ids"),
        "confirmed_at": Json::string(
          delivery_required_text(body, "confirmed_at", "", false),
        ),
        "actor_id": Json::string(actor_id),
      }),
      false,
      Some("reported"),
      "confirmed",
    )
  }
  raise reject(404, "unsupported delivery command")
}

///|
async fn delivery_command(
  family : String,
  command_type : String,
  aggregate_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["progress", "output", "task_report"].contains(family) {
    raise reject(404, "unsupported delivery command family")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let lookup_id = if family == "task_report" {
    let requested = json_text(body, "report_id", "")
    if requested.is_empty() {
      aggregate_id
    } else {
      Some(requested)
    }
  } else {
    aggregate_id
  }
  let current = match lookup_id {
    Some(id) => delivery_latest_payload(family, id)
    None => None
  }
  let (id, request, create_mode, expected_state, next_state) = delivery_command_request(
    family, command_type, aggregate_id, body, actor_id,
  )
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored = json_field(existing, "request").unwrap_or(Json::null())
      if !json_equal(stored, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let response = Json::object({
        "command": existing,
        "idempotent_replay": Json::boolean(true),
      })
      match response {
        Object(fields) => {
          fields.set(
            family,
            json_field(existing, "result").unwrap_or(Json::null()),
          )
          (200, response)
        }
        _ => raise fail("invalid delivery replay response")
      }
    }
    None => {
      let imported = delivery_imported_exists(family, id)
      if create_mode {
        if current is Some(_) || imported {
          raise reject(409, "delivery record already exists")
        }
      } else {
        let current_payload = match current {
          Some((payload, _)) => payload
          None => {
            if imported {
              raise reject(409, "imported delivery records are read-only")
            }
            raise reject(404, "delivery record not found")
          }
        }
        if json_text(current_payload, "source_kind", "") != "command" {
          raise reject(409, "imported delivery records are read-only")
        }
        match expected_state {
          Some(value) if json_text(current_payload, "state", "") != value =>
            raise reject(409, "delivery transition requires " + value)
          _ => ()
        }
      }
      let current_payload = match current {
        Some((payload, _)) => payload
        None => Json::null()
      }
      let current_revision = match current {
        Some((_, revision)) => revision
        None => 0
      }
      let next_revision = if create_mode { 1 } else { current_revision + 1 }
      let event_id = "delivery:" +
        family +
        ":" +
        command_type +
        ":" +
        idempotency_key
      let command_source = "moonproj:command:" + idempotency_key
      let audit_id = event_id + ":audit"
      let result = Json::object({
        "aggregate_id": Json::string(id),
        "state": Json::string(next_state),
        "revision": Json::number(next_revision.to_double()),
        "event_id": Json::string(event_id),
        "audit_id": Json::string(audit_id),
        "actor_id": Json::string(actor_id),
        "delivery_effect": Json::boolean(false),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      })
      let command_payload = Json::object({
        "kind": Json::string("company_command"),
        "command_family": Json::string("delivery"),
        "family": Json::string(family),
        "command_type": Json::string(command_type),
        "idempotency_key": Json::string(idempotency_key),
        "aggregate_type": Json::string(delivery_aggregate(family)),
        "aggregate_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "request": request,
        "result": result,
      })
      let request_json = request.stringify()
      let current_json = current_payload.stringify()
      let next_payload_sql = if create_mode {
        @postgres.sql_literal(request_json) +
        "::jsonb || jsonb_build_object('state', " +
        @postgres.sql_literal(next_state) +
        ", 'source_kind', 'command', 'event_id', " +
        @postgres.sql_literal(event_id) +
        ", 'updated_by', " +
        @postgres.sql_literal(actor_id) +
        ")"
      } else {
        @postgres.sql_literal(current_json) +
        "::jsonb || " +
        @postgres.sql_literal(request_json) +
        "::jsonb || jsonb_build_object('state', " +
        @postgres.sql_literal(next_state) +
        ", 'source_kind', 'command', 'event_id', " +
        @postgres.sql_literal(event_id) +
        ", 'updated_by', " +
        @postgres.sql_literal(actor_id) +
        (if command_type == "delete" {
          ", 'deleted_at', " + @postgres.sql_literal(event_id)
        } else {
          ""
        }) +
        ")"
      }
      let audit_payload = Json::object({
        "audit_id": Json::string(audit_id),
        "action": Json::string("delivery." + family + "." + command_type),
        "aggregate_type": Json::string(delivery_aggregate(family)),
        "aggregate_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "event_id": Json::string(event_id),
        "state": Json::string(next_state),
        "revision": Json::number(next_revision.to_double()),
      })
      let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
        @postgres.sql_literal(event_id) +
        ", 4, " +
        @postgres.sql_literal(command_payload.stringify()) +
        "::jsonb, " +
        @postgres.sql_literal(command_source) +
        ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
        @postgres.sql_literal(delivery_aggregate(family)) +
        ", " +
        @postgres.sql_literal(id) +
        ", " +
        next_revision.to_string() +
        ", " +
        next_payload_sql +
        ", " +
        @postgres.sql_literal(event_id) +
        ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
        @postgres.sql_literal(audit_id) +
        ", 4, " +
        @postgres.sql_literal(audit_payload.stringify()) +
        "::jsonb, " +
        @postgres.sql_literal("moonproj:audit:" + event_id) +
        ") ON CONFLICT DO NOTHING; UPDATE company_record SET payload = payload || jsonb_build_object('result', " +
        @postgres.sql_literal(result.stringify()) +
        "::jsonb) WHERE source_id = " +
        @postgres.sql_literal(command_source) +
        "; COMMIT;"
      let _ = run_sql(sql)
      let response = Json::object({
        "command": command_payload,
        "idempotent_replay": Json::boolean(false),
      })
      match response {
        Object(fields) => {
          fields.set(family, result)
          (if create_mode { 201 } else { 200 }, response)
        }
        _ => raise fail("invalid delivery response")
      }
    }
  }
}

///|
fn delivery_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String, String?)? {
  if request_method is @http.Post {
    if path == "/api/company/delivery/progress" {
      return Some(("progress", "create", None))
    }
    if path == "/api/company/delivery/outputs" {
      return Some(("output", "create", None))
    }
  }
  let progress_prefix = "/api/company/delivery/progress/"
  if path.has_prefix(progress_prefix) {
    let rest = path[progress_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      valid_identifier(rest[0].to_owned()) &&
      request_method is @http.Post {
      let command = match rest[1].to_owned() {
        "report" => "report"
        "accept" => "accept"
        "reject" => "reject"
        _ => ""
      }
      if !command.is_empty() {
        return Some(("progress", command, Some(rest[0].to_owned())))
      }
    }
    if rest.length() == 1 &&
      valid_identifier(rest[0].to_owned()) &&
      request_method is @http.Delete {
      return Some(("progress", "delete", Some(rest[0].to_owned())))
    }
  }
  let output_prefix = "/api/company/delivery/outputs/"
  if request_method is @http.Post && path.has_prefix(output_prefix) {
    let rest = path[output_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      rest[1].to_owned() == "confirm" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("output", "confirm", Some(rest[0].to_owned())))
    }
  }
  let task_prefix = "/api/company/delivery/tasks/"
  if request_method is @http.Post && path.has_prefix(task_prefix) {
    let rest = path[task_prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 &&
      rest[1].to_owned() == "report" &&
      valid_identifier(rest[0].to_owned()) {
      return Some(("task_report", "report", Some(rest[0].to_owned())))
    }
  }
  None
}
