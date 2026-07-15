///|
/// Native project, plan-task, and task-report read/command boundary.
async fn plan_task_projection_rows(
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
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
    "WHERE aggregate_type = 'plan_task' ORDER BY aggregate_id, revision DESC) latest" +
    deleted_clause +
    " ORDER BY aggregate_id LIMIT 500",
  )
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 4)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid plan-task projection JSON")
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
        _ => raise fail("plan-task projection payload is not an object")
      }
    }
  }
  result
}

///|
fn project_task_user_name(users : Array[SourceRow], user_id : String) -> String {
  if user_id.is_empty() {
    return ""
  }
  for row in users {
    let payload = row.payload
    let id = json_text(payload, "user_id", row.record_id)
    if id == user_id || row.record_id == user_id {
      return json_text(payload, "emp_name", json_text(payload, "user_name", ""))
    }
  }
  ""
}

///|
fn project_plan_task_item(
  row : SourceRow,
  command : Bool,
  users : Array[SourceRow],
) -> Json {
  let payload = row.payload
  let task_id = if command {
    row.record_id
  } else {
    json_text(
      payload,
      "task_guid",
      json_text(payload, "task_id", row.record_id),
    )
  }
  let project_id = if command {
    json_text(payload, "project_id", "")
  } else {
    json_text(payload, "proj_guid", json_text(payload, "project_id", ""))
  }
  let task_type = json_text(payload, "task_type", "task")
  let owner_id = if command {
    json_text(payload, "owner_id", "")
  } else {
    json_text(payload, "owner_guid", "")
  }
  let status = if command {
    json_text(payload, "state", json_text(payload, "status", "pending"))
  } else {
    json_text(payload, "status", "pending")
  }
  let progress = if command {
    json_text(payload, "progress_pct", "0")
  } else {
    json_text(payload, "progress_pct", "0")
  }
  let source_id = if row.source_id.is_empty() {
    "erp:jd_task:" + row.record_id
  } else {
    row.source_id
  }
  Json::object({
    "taskGuid": Json::string(task_id),
    "taskCode": Json::string(json_text(payload, "task_code", "")),
    "taskName": Json::string(json_text(payload, "task_name", "")),
    "projGuid": Json::string(project_id),
    "taskType": Json::string(task_type),
    "parentTaskGuid": Json::string(
      if command {
        json_text(payload, "parent_task_id", "")
      } else {
        json_text(payload, "parent_task_guid", "")
      },
    ),
    "planBeginDate": Json::string(json_text(payload, "plan_begin_date", "")),
    "planEndDate": Json::string(json_text(payload, "plan_end_date", "")),
    "actualBeginDate": Json::string(json_text(payload, "actual_begin_date", "")),
    "actualEndDate": Json::string(json_text(payload, "actual_end_date", "")),
    "progressPct": Json::string(progress),
    "ownerGuid": Json::string(owner_id),
    "ownerName": Json::string(project_task_user_name(users, owner_id)),
    "status": Json::string(status),
    "remarks": Json::string(json_text(payload, "remarks", "")),
    "sortOrder": Json::number(json_int(payload, "sort_order", 0).to_double()),
    "sourceKind": Json::string(if command { "command" } else { "imported" }),
    "sourceId": Json::string(source_id),
    "revision": Json::number(json_int(payload, "__revision", 0).to_double()),
    "delayed": Json::boolean(status == "overdue"),
  })
}

///|
fn project_plan_task_matches(
  item : Json,
  project_id : String,
  task_type : String?,
) -> Bool {
  if json_text(item, "projGuid", "") != project_id {
    return false
  }
  match task_type {
    Some(value) => json_text(item, "taskType", "task") == value
    None => true
  }
}

///|
async fn project_plan_tasks(
  project_id : String,
  task_type : String?,
) -> Array[Json] raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  match task_type {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid task_type")
    _ => ()
  }
  let users = raw_source_rows("sys_user", 500)
  let raw = raw_source_rows("jd_task", 500)
  let result : Array[Json] = []
  for row in raw {
    let item = project_plan_task_item(row, false, users)
    if project_plan_task_matches(item, project_id, task_type) {
      result.push(item)
    }
  }
  let commands = plan_task_projection_rows(false)
  for row in commands {
    let item = project_plan_task_item(row, true, users)
    if project_plan_task_matches(item, project_id, task_type) {
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
async fn project_plan_task_reports(
  task_id : String,
) -> Array[Json] raise CompanyServiceError {
  let reports = delivery_task_report_items(None, Some(task_id))
  let users = raw_source_rows("sys_user", 500)
  let result : Array[Json] = []
  for report in reports {
    let operator_id = json_text(report, "operator_id", "")
    result.push(
      Json::object({
        "reportGuid": Json::string(json_text(report, "report_id", "")),
        "reportDate": Json::string(json_text(report, "report_date", "")),
        "progressPct": Json::string(json_text(report, "progress_pct", "0")),
        "summary": Json::string(json_text(report, "summary", "")),
        "operatorGuid": Json::string(operator_id),
        "operatorName": Json::string(project_task_user_name(users, operator_id)),
        "sourceKind": Json::string(json_text(report, "source_kind", "imported")),
      }),
    )
  }
  result
}

///|
async fn project_plan_project_item(
  row : SourceRow,
  units : Array[SourceRow],
  stages : Array[SourceRow],
  instances : Array[SourceRow],
) -> Json raise CompanyServiceError {
  let payload = row.payload
  let project_id = json_text(payload, "proj_guid", row.record_id)
  let bu_id = json_text(payload, "bu_guid", "")
  let bu_name = unit_name(units, bu_id)
  let lifecycle : Array[Json] = []
  let mut current_stage = ""
  let mut last_done = ""
  let ordered_stages = stages.copy()
  ordered_stages.sort_by(fn(left, right) {
    json_int(left.payload, "stage_order", 0) -
    json_int(right.payload, "stage_order", 0)
  })
  for stage in ordered_stages {
    let stage_payload = stage.payload
    let code = json_text(stage_payload, "stage_code", stage.record_id)
    let stage_name = json_text(stage_payload, "stage_name", code)
    let mut status = "pending"
    let mut progress = "0"
    let mut planned_start = ""
    let mut planned_end = ""
    let mut actual_start = ""
    let mut actual_end = ""
    for instance in instances {
      let instance_payload = instance.payload
      if json_text(instance_payload, "proj_guid", "") == project_id &&
        json_text(instance_payload, "stage_code", "") == code {
        status = json_text(instance_payload, "status", "pending")
        progress = json_text(instance_payload, "progress_pct", "0")
        planned_start = json_text(instance_payload, "planned_start", "")
        planned_end = json_text(instance_payload, "planned_end", "")
        actual_start = json_text(instance_payload, "actual_start", "")
        actual_end = json_text(instance_payload, "actual_end", "")
      }
    }
    if status == "in_progress" && current_stage.is_empty() {
      current_stage = stage_name
    }
    if status == "done" {
      last_done = stage_name
    }
    lifecycle.push(
      Json::object({
        "stage_code": Json::string(code),
        "stage_name": Json::string(stage_name),
        "stage_order": Json::number(
          json_int(stage_payload, "stage_order", 0).to_double(),
        ),
        "status": Json::string(status),
        "progress_pct": Json::string(progress),
        "planned_start": Json::string(planned_start),
        "planned_end": Json::string(planned_end),
        "actual_start": Json::string(actual_start),
        "actual_end": Json::string(actual_end),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  let tasks = project_plan_tasks(project_id, None)
  let reports : Array[Json] = []
  for task in tasks {
    let task_reports = project_plan_task_reports(
      json_text(task, "taskGuid", ""),
    )
    for report in task_reports {
      reports.push(report)
    }
  }
  let status_counts : Map[String, Int] = {}
  for task in tasks {
    let status = json_text(task, "status", "pending")
    status_counts.set(status, status_counts.get(status).unwrap_or(0) + 1)
  }
  let status_count_json : Map[String, Json] = {}
  for status, count in status_counts {
    status_count_json.set(status, Json::number(count.to_double()))
  }
  Json::object({
    "project_id": Json::string(project_id),
    "project_code": Json::string(json_text(payload, "proj_code", project_id)),
    "project_name": Json::string(json_text(payload, "proj_name", project_id)),
    "project_short_name": Json::string(
      json_text(payload, "proj_short_name", ""),
    ),
    "bu_guid": Json::string(bu_id),
    "bu_name": Json::string(bu_name),
    "level": Json::number(json_int(payload, "level", 0).to_double()),
    "level_code": Json::string(json_text(payload, "level_code", "")),
    "if_end": Json::boolean(json_bool(payload, "if_end", false)),
    "begin_date": Json::string(json_text(payload, "begin_date", "")),
    "end_date": Json::string(json_text(payload, "end_date", "")),
    "proj_status": Json::string(json_text(payload, "proj_status", "")),
    "created_at": Json::string(json_text(payload, "created_at", "")),
    "current_stage": Json::string(
      if current_stage.is_empty() {
        last_done
      } else {
        current_stage
      },
    ),
    "task_count": Json::number(tasks.length().to_double()),
    "task_status_counts": Json::object(status_count_json),
    "lifecycle": Json::array(lifecycle),
    "tasks": Json::array(tasks),
    "reports": Json::array(reports),
    "source_kind": Json::string("imported"),
    "source_id": Json::string(
      if row.source_id.is_empty() {
        "erp:ep_project:" + row.record_id
      } else {
        row.source_id
      },
    ),
  })
}

///|
async fn project_plan_project_items(
  project_id : String?,
  status : String?,
  keyword : String?,
) -> Array[Json] raise CompanyServiceError {
  match project_id {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid project_id")
    _ => ()
  }
  match status {
    Some(value) if value.length() > 64 =>
      raise reject(422, "invalid project status")
    _ => ()
  }
  match keyword {
    Some(value) if value.length() > 128 =>
      raise reject(422, "invalid project keyword")
    _ => ()
  }
  let raw_projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let stages = raw_source_rows("proj_lifecycle_stage", 500)
  let instances = raw_source_rows("proj_lifecycle_instance", 500)
  let result : Array[Json] = []
  for row in raw_projects {
    let item = project_plan_project_item(row, units, stages, instances)
    let id_ok = match project_id {
      Some(value) => json_text(item, "project_id", "") == value
      None => true
    }
    let status_ok = match status {
      Some(value) => json_text(item, "proj_status", "") == value
      None => true
    }
    let needle = match keyword {
      Some(value) => value.to_lower()
      None => ""
    }
    let keyword_ok = needle.is_empty() ||
      json_text(item, "project_name", "").to_lower().contains(needle) ||
      json_text(item, "project_code", "").to_lower().contains(needle)
    if id_ok && status_ok && keyword_ok {
      result.push(item)
    }
  }
  result.sort_by(fn(left, right) {
    let code_order = json_text(left, "project_code", "").lexical_compare(
      json_text(right, "project_code", ""),
    )
    if code_order == 0 {
      json_text(left, "project_id", "").lexical_compare(
        json_text(right, "project_id", ""),
      )
    } else {
      code_order
    }
  })
  result
}

///|
async fn project_runtime_response(
  project_id : String?,
  status : String?,
  keyword : String?,
) -> Json raise CompanyServiceError {
  let items = project_plan_project_items(project_id, status, keyword)
  let coverage = Json::object({
    "ep_project": Json::number(
      raw_source_rows("ep_project", 500).length().to_double(),
    ),
    "mu_business_unit": Json::number(
      raw_source_rows("mu_business_unit", 500).length().to_double(),
    ),
    "proj_lifecycle_stage": Json::number(
      raw_source_rows("proj_lifecycle_stage", 500).length().to_double(),
    ),
    "proj_lifecycle_instance": Json::number(
      raw_source_rows("proj_lifecycle_instance", 500).length().to_double(),
    ),
    "jd_task": Json::number(
      raw_source_rows("jd_task", 500).length().to_double(),
    ),
    "jd_task_report": Json::number(
      raw_source_rows("jd_task_report", 500).length().to_double(),
    ),
  })
  Json::object({
    "items": Json::array(items),
    "source_kind": Json::string("imported"),
    "command_projection": Json::boolean(false),
    "authorizing": Json::boolean(false),
    "source_coverage": coverage,
    "missing_source_tables": Json::array(
      delivery_missing_tables(coverage, [
        "ep_project", "mu_business_unit", "proj_lifecycle_stage", "proj_lifecycle_instance",
        "jd_task", "jd_task_report",
      ]),
    ),
  })
}

///|
async fn project_task_detail_response(
  task_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(task_id) {
    return (400, Json::object({ "error": Json::string("invalid task_id") }))
  }
  let users = raw_source_rows("sys_user", 500)
  let raw = raw_source_rows("jd_task", 500)
  let commands = plan_task_projection_rows(false)
  let mut selected : Json? = None
  for row in raw {
    let item = project_plan_task_item(row, false, users)
    if json_text(item, "taskGuid", "") == task_id {
      selected = Some(item)
    }
  }
  if selected is None {
    for row in commands {
      let item = project_plan_task_item(row, true, users)
      if json_text(item, "taskGuid", "") == task_id {
        selected = Some(item)
      }
    }
  }
  match selected {
    None => (404, Json::object({ "error": Json::string("task not found") }))
    Some(task) => {
      let reports = project_plan_task_reports(task_id)
      let project_id = json_text(
        task,
        "projGuid",
        json_text(task, "proj_guid", json_text(task, "project_id", "")),
      )
      let mut project_name = ""
      let projects = project_plan_project_items(Some(project_id), None, None)
      if !projects.is_empty() {
        project_name = json_text(projects[0], "project_name", "")
      }
      let detail_task = match task {
        Object(fields) => {
          fields.set("projGuid", Json::string(project_id))
          fields.set("projName", Json::string(project_name))
          Json::object(fields)
        }
        _ => task
      }
      (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "task": detail_task,
            "reports": Json::array(reports),
          }),
          "source_kind": Json::string("imported_or_command"),
          "source_coverage": Json::object({
            "jd_task": Json::number(raw.length().to_double()),
            "jd_task_report": Json::number(
              raw_source_rows("jd_task_report", 500).length().to_double(),
            ),
          }),
          "command_projection": Json::boolean(
            json_text(detail_task, "sourceKind", "") == "command",
          ),
          "authorizing": Json::boolean(false),
        }),
      )
    }
  }
}

///|
async fn project_lifecycle_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let projects = project_plan_project_items(Some(project_id), None, None)
  if projects.is_empty() {
    return (404, Json::object({ "error": Json::string("project not found") }))
  }
  let project = projects[0]
  let stages : Array[Json] = []
  let lifecycle_json = json_field(project, "lifecycle").unwrap_or(
    Json::array([]),
  )
  match lifecycle_json {
    Array(values) =>
      for stage in values {
        stages.push(
          Json::object({
            "stageCode": Json::string(json_text(stage, "stage_code", "")),
            "stageName": Json::string(json_text(stage, "stage_name", "")),
            "stageOrder": Json::number(
              json_int(stage, "stage_order", 0).to_double(),
            ),
            "status": Json::string(json_text(stage, "status", "pending")),
            "progressPct": Json::string(json_text(stage, "progress_pct", "0")),
            "plannedStart": Json::string(json_text(stage, "planned_start", "")),
            "plannedEnd": Json::string(json_text(stage, "planned_end", "")),
            "actualStart": Json::string(json_text(stage, "actual_start", "")),
            "actualEnd": Json::string(json_text(stage, "actual_end", "")),
            "sourceKind": Json::string("imported"),
          }),
        )
      }
    _ => ()
  }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "project": Json::object({
          "projGuid": Json::string(json_text(project, "project_id", "")),
          "projCode": Json::string(json_text(project, "project_code", "")),
          "projName": Json::string(json_text(project, "project_name", "")),
          "buGuid": Json::string(json_text(project, "bu_guid", "")),
          "buName": Json::string(json_text(project, "bu_name", "")),
          "projStatus": Json::string(json_text(project, "proj_status", "")),
        }),
        "stages": Json::array(stages),
      }),
      "source_kind": Json::string("imported"),
      "source_coverage": Json::object({
        "ep_project": Json::number(1),
        "proj_lifecycle_stage": Json::number(stages.length().to_double()),
        "proj_lifecycle_instance": Json::number(
          raw_source_rows("proj_lifecycle_instance", 500).length().to_double(),
        ),
      }),
      "authorizing": Json::boolean(false),
    }),
  )
}

///|
async fn project_plan_summary_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let tasks = project_plan_tasks(project_id, Some("key_node"))
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
  let mut upcoming_tasks = tasks.copy()
  upcoming_tasks = upcoming_tasks.filter(fn(task) {
    json_text(task, "status", "pending") != "done"
  })
  upcoming_tasks.sort_by(fn(left, right) {
    let end_order = json_text(left, "planEndDate", "").lexical_compare(
      json_text(right, "planEndDate", ""),
    )
    if end_order == 0 {
      json_text(left, "taskGuid", "").lexical_compare(
        json_text(right, "taskGuid", ""),
      )
    } else {
      end_order
    }
  })
  let upcoming : Array[Json] = []
  let mut upcoming_count = 0
  for task in upcoming_tasks {
    if upcoming_count >= 3 {
      break
    }
    upcoming.push(
      Json::object({
        "taskGuid": Json::string(json_text(task, "taskGuid", "")),
        "taskName": Json::string(json_text(task, "taskName", "")),
        "planEndDate": Json::string(json_text(task, "planEndDate", "")),
        "progressPct": Json::string(json_text(task, "progressPct", "0")),
        "delayed": Json::boolean(json_bool(task, "delayed", false)),
      }),
    )
    upcoming_count += 1
  }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "summary": Json::object({
          "done": Json::number(done.to_double()),
          "in_progress": Json::number(in_progress.to_double()),
          "pending": Json::number(pending.to_double()),
          "overdue": Json::number(overdue.to_double()),
          "blocked": Json::number(blocked.to_double()),
          "total": Json::number(
            (done + in_progress + pending + overdue + blocked).to_double(),
          ),
        }),
        "upcoming": Json::array(upcoming),
      }),
      "project_id": Json::string(project_id),
      "source_kind": Json::string("imported_or_command"),
      "source_coverage": Json::object({
        "jd_task": Json::number(
          raw_source_rows("jd_task", 500).length().to_double(),
        ),
      }),
      "command_projection": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}

///|
fn plan_is_leap_year(year : Int) -> Bool {
  year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
}

///|
fn plan_days_in_month(year : Int, month : Int) -> Int {
  if month == 2 {
    if plan_is_leap_year(year) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
fn plan_two_digits(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn plan_shift_date(
  value : String,
  delay_days : Int,
) -> String raise CompanyServiceError {
  if value.length() != 10 || value[4:5] != "-" || value[7:8] != "-" {
    return value
  }
  let year = parse_decimal(value[0:4].to_owned())
  let month = parse_decimal(value[5:7].to_owned())
  let day = parse_decimal(value[8:10].to_owned())
  if month < 1 || month > 12 || day < 1 || day > plan_days_in_month(year, month) {
    return value
  }
  let mut next_year = year
  let mut next_month = month
  let mut next_day = day
  let mut remaining = if delay_days < 0 { -delay_days } else { delay_days }
  if delay_days >= 0 {
    while remaining > 0 {
      next_day += 1
      if next_day > plan_days_in_month(next_year, next_month) {
        next_day = 1
        next_month += 1
        if next_month > 12 {
          next_month = 1
          next_year += 1
        }
      }
      remaining -= 1
    }
  } else {
    while remaining > 0 {
      next_day -= 1
      if next_day < 1 {
        next_month -= 1
        if next_month < 1 {
          next_month = 12
          next_year -= 1
        }
        next_day = plan_days_in_month(next_year, next_month)
      }
      remaining -= 1
    }
  }
  next_year.to_string() +
  "-" +
  plan_two_digits(next_month) +
  "-" +
  plan_two_digits(next_day)
}

///|
async fn project_delay_impact_response(
  task_id : String,
  delay_days : Int,
) -> (Int, Json) raise CompanyServiceError {
  if delay_days < -3650 || delay_days > 3650 {
    return (
      422,
      Json::object({
        "error": Json::string("delay_days is outside the supported range"),
      }),
    )
  }
  let detail = project_task_detail_response(task_id)
  if detail.0 != 200 {
    return detail
  }
  let data = json_field(detail.1, "data").unwrap_or(Json::null())
  let task = json_field(data, "task").unwrap_or(Json::null())
  let project_id = json_text(task, "projGuid", "")
  let old_end = json_text(task, "planEndDate", "")
  let new_end = plan_shift_date(old_end, delay_days)
  let impacts : Array[Json] = []
  if !project_id.is_empty() && !old_end.is_empty() {
    for follower in project_plan_tasks(project_id, None) {
      let begin = json_text(follower, "planBeginDate", "")
      if !begin.is_empty() && begin >= old_end {
        impacts.push(
          Json::object({
            "taskGuid": Json::string(json_text(follower, "taskGuid", "")),
            "taskName": Json::string(json_text(follower, "taskName", "")),
            "taskType": Json::string(json_text(follower, "taskType", "task")),
            "oldBegin": Json::string(begin),
            "oldEnd": Json::string(json_text(follower, "planEndDate", "")),
            "newBegin": Json::string(plan_shift_date(begin, delay_days)),
            "newEnd": Json::string(
              plan_shift_date(
                json_text(follower, "planEndDate", ""),
                delay_days,
              ),
            ),
            "sourceKind": Json::string("imported"),
          }),
        )
      }
    }
    impacts.sort_by(fn(left, right) {
      let begin_order = json_text(left, "oldBegin", "").lexical_compare(
        json_text(right, "oldBegin", ""),
      )
      if begin_order == 0 {
        json_text(left, "taskGuid", "").lexical_compare(
          json_text(right, "taskGuid", ""),
        )
      } else {
        begin_order
      }
    })
  }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "source": Json::object({
          "taskName": Json::string(json_text(task, "taskName", "")),
          "oldEnd": Json::string(old_end),
          "newEnd": Json::string(new_end),
          "delayDays": Json::number(delay_days.to_double()),
        }),
        "impact": Json::array(impacts),
        "impactCount": Json::number(impacts.length().to_double()),
        "calculation_available": Json::boolean(true),
      }),
      "source_kind": Json::string("imported"),
      "authorizing": Json::boolean(false),
    }),
  )
}

///|
fn plan_task_required(
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
fn plan_task_optional(
  body : Json,
  primary : String,
  fallbacks : Array[String],
  identifier : Bool,
) -> String raise CompanyServiceError {
  let mut selected : Json? = json_field(body, primary)
  if selected is None {
    for fallback in fallbacks {
      selected = json_field(body, fallback)
      if selected is Some(_) {
        break
      }
    }
  }
  let value = match selected {
    None | Some(Null) => ""
    Some(String(text)) => text.trim().to_owned()
    Some(Number(number, ..)) => number.to_string()
    _ => raise reject(422, primary + " must be text")
  }
  if identifier && !value.is_empty() && !valid_identifier(value) {
    raise reject(422, primary + " contains unsupported characters")
  }
  value
}

///|
fn plan_task_date(
  body : Json,
  primary : String,
  fallback : String,
  required : Bool,
) -> String raise CompanyServiceError {
  let value = if required {
    plan_task_required(body, primary, fallback, false)
  } else {
    plan_task_optional(body, primary, [fallback], false)
  }
  if !value.is_empty() &&
    (value.length() != 10 || value[4:5] != "-" || value[7:8] != "-") {
    raise reject(422, primary + " must be an ISO date")
  }
  value
}

///|
fn plan_task_progress(
  body : Json,
  primary : String,
) -> Double raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(Number(number, ..)) => number
    Some(String(text)) => parse_number(text.trim().to_owned())
    _ => raise reject(422, primary + " must be a number")
  }
  if value < 0.0 || value > 100.0 || value != value {
    raise reject(422, primary + " must be between 0 and 100")
  }
  round_places(value, 2)
}

///|
fn plan_task_authority(
  body : Json,
  actor_id : String,
  project_id : String,
  capability : String,
) -> Json raise CompanyServiceError {
  let grant = match json_field(body, "authority") {
    Some(Object(_)) => json_field(body, "authority").unwrap()
    _ => raise reject(403, "authority grant is required")
  }
  if !json_bool(grant, "active", false) {
    raise reject(403, "authority grant is inactive")
  }
  let principal_id = json_text(grant, "principal_id", "")
  if !valid_identifier(principal_id) {
    raise reject(403, "authority grant principal_id is required")
  }
  if json_text(grant, "actor_id", "") != actor_id {
    raise reject(403, "authority grant actor does not match signed actor")
  }
  if json_text(grant, "capability", "") != capability {
    raise reject(403, "authority grant must allow " + capability)
  }
  let scope = "project:" + project_id
  if json_text(grant, "scope", "") != scope {
    raise reject(403, "authority grant scope must be project-scoped")
  }
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string(principal_id),
    "actor_id": Json::string(actor_id),
    "capability": Json::string(capability),
    "scope": Json::string(scope),
  })
}

///|
async fn plan_task_project_exists(
  project_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("ep_project", 500) {
    if json_text(row.payload, "proj_guid", row.record_id) == project_id {
      return true
    }
  }
  false
}

///|
async fn plan_task_imported_exists(
  task_id : String,
) -> Bool raise CompanyServiceError {
  for row in raw_source_rows("jd_task", 500) {
    if json_text(row.payload, "task_guid", row.record_id) == task_id ||
      row.record_id == task_id {
      return true
    }
  }
  false
}

///|
async fn plan_task_latest(
  task_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'plan_task' AND aggregate_id = " +
    @postgres.sql_literal(task_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid plan task projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn plan_task_command_request(
  command_type : String,
  aggregate_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (String, Json, Bool, Json?) raise CompanyServiceError {
  if command_type == "create" {
    let requested = plan_task_optional(
      body,
      "task_id",
      ["task_guid", "taskGuid"],
      true,
    )
    let id = if requested.is_empty() {
      "PT-" + idempotency_key
    } else {
      requested
    }
    let project_id = plan_task_required(body, "project_id", "proj_guid", true)
    if !plan_task_project_exists(project_id) {
      raise reject(
        409, "project-plan task requires an imported project identity",
      )
    }
    let task_name = plan_task_required(body, "task_name", "taskName", false)
    let task_code = plan_task_optional(body, "task_code", ["taskCode"], true)
    let task_type = match
      plan_task_optional(body, "task_type", ["taskType"], false) {
      "" => "task"
      value => value
    }
    if task_type != "task" && task_type != "key_node" {
      raise reject(422, "task_type must be task or key_node")
    }
    let parent_id = plan_task_optional(
      body,
      "parent_task_id",
      ["parentTaskGuid", "parent_task_guid"],
      true,
    )
    let begin = plan_task_date(body, "plan_begin_date", "planBeginDate", true)
    let end = plan_task_date(body, "plan_end_date", "planEndDate", true)
    if !end.is_empty() && end < begin {
      raise reject(422, "plan end date cannot precede plan begin date")
    }
    let owner_id = plan_task_optional(
      body,
      "owner_id",
      ["ownerGuid", "owner_guid"],
      true,
    )
    let sort_order = match json_field(body, "sort_order") {
      Some(Number(number, ..)) => number.to_int()
      None => json_int(body, "sortOrder", 0)
      _ => raise reject(422, "sort_order must be a non-negative integer")
    }
    if sort_order < 0 {
      raise reject(422, "sort_order must be a non-negative integer")
    }
    let authority = plan_task_authority(
      body, actor_id, project_id, "project:task:create",
    )
    let request = Json::object({
      "command_type": Json::string("create"),
      "task_id": Json::string(id),
      "task_code": Json::string(task_code),
      "task_name": Json::string(task_name),
      "project_id": Json::string(project_id),
      "task_type": Json::string(task_type),
      "parent_task_id": Json::string(parent_id),
      "plan_begin_date": Json::string(begin),
      "plan_end_date": Json::string(end),
      "actual_begin_date": Json::string(""),
      "actual_end_date": Json::string(""),
      "progress_pct": Json::number(0),
      "owner_id": Json::string(owner_id),
      "status": Json::string("pending"),
      "remarks": Json::string(plan_task_optional(body, "remarks", [], false)),
      "sort_order": Json::number(sort_order.to_double()),
      "created_by": Json::string(actor_id),
      "authority": authority,
    })
    return (id, request, true, None)
  }
  let id = match aggregate_id {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "task_id is required")
  }
  let current = match plan_task_latest(id) {
    Some((payload, _)) => payload
    None => {
      if plan_task_imported_exists(id) {
        raise reject(
          409, "imported tasks are read-only; create a local planning task first",
        )
      }
      raise reject(404, "project-plan task not found")
    }
  }
  if json_text(current, "state", "") == "deleted" {
    raise reject(409, "project-plan task is already deleted")
  }
  let project_id = plan_task_required(current, "project_id", "", true)
  if json_text(current, "created_by", "") != actor_id {
    raise reject(403, "only the task creator may change this local task")
  }
  let authority = plan_task_authority(
    body,
    actor_id,
    project_id,
    "project:task:" + command_type,
  )
  if command_type == "delete" {
    return (
      id,
      Json::object({
        "command_type": Json::string("delete"),
        "task_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "reason": Json::string(plan_task_optional(body, "reason", [], false)),
        "authority": authority,
      }),
      false,
      Some(current),
    )
  }
  let changes : Map[String, Json] = {}
  let task_name = plan_task_optional(body, "task_name", ["taskName"], false)
  if !task_name.is_empty() {
    changes.set("task_name", Json::string(task_name))
  }
  let task_code = plan_task_optional(body, "task_code", ["taskCode"], true)
  if !task_code.is_empty() {
    changes.set("task_code", Json::string(task_code))
  }
  let owner_id = plan_task_optional(
    body,
    "owner_id",
    ["ownerGuid", "owner_guid"],
    true,
  )
  if !owner_id.is_empty() {
    changes.set("owner_id", Json::string(owner_id))
  }
  if json_field(body, "remarks") is Some(_) {
    changes.set(
      "remarks",
      Json::string(plan_task_optional(body, "remarks", [], false)),
    )
  }
  if json_field(body, "plan_begin_date") is Some(_) ||
    json_field(body, "planBeginDate") is Some(_) {
    changes.set(
      "plan_begin_date",
      Json::string(
        plan_task_date(body, "plan_begin_date", "planBeginDate", false),
      ),
    )
  }
  if json_field(body, "plan_end_date") is Some(_) ||
    json_field(body, "planEndDate") is Some(_) {
    changes.set(
      "plan_end_date",
      Json::string(plan_task_date(body, "plan_end_date", "planEndDate", false)),
    )
  }
  let begin = json_text(
    Json::object(changes),
    "plan_begin_date",
    json_text(current, "plan_begin_date", ""),
  )
  let end = json_text(
    Json::object(changes),
    "plan_end_date",
    json_text(current, "plan_end_date", ""),
  )
  if !begin.is_empty() && !end.is_empty() && end < begin {
    raise reject(422, "plan end date cannot precede plan begin date")
  }
  if json_field(body, "status") is Some(_) {
    let status = plan_task_required(body, "status", "", false)
    if !["pending", "in_progress", "done", "overdue", "blocked"].contains(
        status,
      ) {
      raise reject(422, "unsupported task status")
    }
    changes.set("status", Json::string(status))
  }
  if json_field(body, "progress_pct") is Some(_) ||
    json_field(body, "progressPct") is Some(_) {
    let progress = if json_field(body, "progress_pct") is Some(_) {
      plan_task_progress(body, "progress_pct")
    } else {
      plan_task_progress(body, "progressPct")
    }
    changes.set("progress_pct", Json::number(progress))
  }
  if changes.is_empty() {
    raise reject(422, "task update requires a mutable field")
  }
  (
    id,
    Json::object({
      "command_type": Json::string("update"),
      "task_id": Json::string(id),
      "actor_id": Json::string(actor_id),
      "changes": Json::object(changes),
      "authority": authority,
    }),
    false,
    Some(current),
  )
}

///|
async fn plan_task_command(
  command_type : String,
  aggregate_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !["create", "update", "delete"].contains(command_type) {
    raise reject(404, "unsupported project-plan task command")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let (id, request, create_mode, current_from_request) = plan_task_command_request(
    command_type, aggregate_id, body, actor_id, idempotency_key,
  )
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      let response = Json::object({
        "command": existing,
        "task": json_field(existing, "result").unwrap_or(Json::null()),
        "idempotent_replay": Json::boolean(true),
      })
      (200, response)
    }
    None => {
      if create_mode {
        if plan_task_imported_exists(id) || plan_task_latest(id) is Some(_) {
          raise reject(
            409, "imported tasks are read-only; use a distinct local identity",
          )
        }
      }
      let current = current_from_request
      let current_payload = current.unwrap_or(Json::null())
      let current_revision = match plan_task_latest(id) {
        Some((_, revision)) => revision
        None => 0
      }
      let next_revision = if create_mode { 1 } else { current_revision + 1 }
      let event_id = "plan_task:" + command_type + ":" + idempotency_key
      let command_source = "moonproj:command:" + idempotency_key
      let audit_id = event_id + ":audit"
      let next_state = if command_type == "create" {
        "pending"
      } else if command_type == "delete" {
        "deleted"
      } else {
        json_text(
          json_field(request, "changes").unwrap_or(Json::null()),
          "status",
          json_text(current_payload, "state", "pending"),
        )
      }
      let result = Json::object({
        "taskGuid": Json::string(id),
        "task_id": Json::string(id),
        "state": Json::string(next_state),
        "revision": Json::number(next_revision.to_double()),
        "event_id": Json::string(event_id),
        "audit_id": Json::string(audit_id),
        "actor_id": Json::string(actor_id),
        "sourceKind": Json::string("command"),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      })
      let command_payload = Json::object({
        "kind": Json::string("company_command"),
        "command_family": Json::string("plan_task"),
        "command_type": Json::string(command_type),
        "idempotency_key": Json::string(idempotency_key),
        "aggregate_type": Json::string("plan_task"),
        "aggregate_id": Json::string(id),
        "actor_id": Json::string(actor_id),
        "request": request,
        "result": result,
      })
      let request_json = request.stringify()
      let current_json = current_payload.stringify()
      let next_payload_sql = if create_mode {
        @postgres.sql_literal(request_json) +
        "::jsonb || jsonb_build_object('state', 'pending', 'source_kind', 'command', 'event_id', " +
        @postgres.sql_literal(event_id) +
        ", 'updated_by', " +
        @postgres.sql_literal(actor_id) +
        ")"
      } else if command_type == "delete" {
        @postgres.sql_literal(current_json) +
        "::jsonb || jsonb_build_object('state', 'deleted', 'deleted_at', " +
        @postgres.sql_literal(event_id) +
        ", 'source_kind', 'command', 'event_id', " +
        @postgres.sql_literal(event_id) +
        ", 'updated_by', " +
        @postgres.sql_literal(actor_id) +
        ")"
      } else {
        @postgres.sql_literal(current_json) +
        "::jsonb || coalesce(" +
        @postgres.sql_literal(request_json) +
        "::jsonb->'changes', '{}'::jsonb) || jsonb_build_object('state', " +
        @postgres.sql_literal(next_state) +
        ", 'source_kind', 'command', 'event_id', " +
        @postgres.sql_literal(event_id) +
        ", 'updated_by', " +
        @postgres.sql_literal(actor_id) +
        ")"
      }
      let audit_payload = Json::object({
        "audit_id": Json::string(audit_id),
        "action": Json::string("plan.task." + command_type),
        "aggregate_type": Json::string("plan_task"),
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
        ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('plan_task', " +
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
        "task": result,
        "idempotent_replay": Json::boolean(false),
      })
      (if create_mode { 201 } else { 200 }, response)
    }
  }
}

///|
fn plan_task_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if request_method is @http.Post && path == "/api/company/plan/tasks" {
    return Some(("create", None))
  }
  let prefix = "/api/company/plan/tasks/"
  if path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 1 && valid_identifier(rest[0].to_owned()) {
      if request_method is @http.Put {
        return Some(("update", Some(rest[0].to_owned())))
      }
      if request_method is @http.Delete {
        return Some(("delete", Some(rest[0].to_owned())))
      }
    }
    if rest.length() == 2 &&
      valid_identifier(rest[0].to_owned()) &&
      request_method is @http.Post {
      if rest[1].to_owned() == "delete" {
        return Some(("delete", Some(rest[0].to_owned())))
      }
      if rest[1].to_owned() == "report" {
        return Some(("report", Some(rest[0].to_owned())))
      }
    }
  }
  None
}
