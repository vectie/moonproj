///|
/// Native source-backed warning observations.
fn warning_tables() -> Array[String] {
  [
    "cb_contract", "cb_cost", "cb_expense_split", "cb_htfk_apply", "ep_project",
    "jd_task", "my_biz_param_option", "srm_provider", "sys_user", "vcb_expense",
    "vcb_loan_simple", "wf_process_instance",
  ]
}

///|
async fn warning_context() -> Map[String, Array[SourceRow]] raise CompanyServiceError {
  let rows : Map[String, Array[SourceRow]] = {}
  for table in warning_tables() {
    rows.set(table, raw_source_rows(table, 500))
  }
  rows
}

///|
fn warning_coverage(rows : Map[String, Array[SourceRow]]) -> Map[String, Int] {
  let result : Map[String, Int] = {}
  for table in warning_tables() {
    result.set(table, rows.get_or_default(table, []).length())
  }
  result
}

///|
fn warning_missing(coverage : Map[String, Int]) -> Array[Json] {
  let values : Array[String] = []
  for table, count in coverage {
    if count == 0 {
      values.push(table)
    }
  }
  values.sort_by(fn(left, right) { left.compare(right) })
  values.map(fn(value) { Json::string(value) })
}

///|
fn warning_envelope(
  data : Json,
  coverage : Map[String, Int],
  command_projection_count : Int,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string(
      if command_projection_count > 0 {
        "observed_imported_or_command"
      } else {
        "observed_imported_or_empty"
      },
    ),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(warning_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(command_projection_count > 0),
    "provider_execution": Json::boolean(false),
    "command_projection_count": Json::number(
      command_projection_count.to_double(),
    ),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
  })
}

///|
async fn warning_command_states() -> Map[String, Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, revision, payload FROM company_aggregate_projection WHERE aggregate_type = 'warning_state' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Map[String, Json] = {}
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid warning command projection JSON")
      }
      result.set(decode_hex(row[0]), payload)
    }
  }
  result
}

///|
fn warning_overlay_findings(
  findings : Array[Json],
  states : Map[String, Json],
) -> Array[Json] {
  let result : Array[Json] = []
  for finding in findings {
    let warning_id = report_text(finding, "warningGuid", "")
    match states.get(warning_id) {
      Some(state) => {
        let state_value = report_text(state, "state", "open")
        let fields : Map[String, Json] = match finding {
          Object(values) => values
          _ => {}
        }
        fields.set("status", Json::string(state_value))
        fields.set(
          "resolvedAt",
          json_field(state, "changed_at").unwrap_or(Json::null()),
        )
        fields.set(
          "resolvedBy",
          json_field(state, "actor_id").unwrap_or(Json::null()),
        )
        fields.set(
          "resolvedNote",
          json_field(state, "note").unwrap_or(Json::null()),
        )
        fields.set("sourceKind", Json::string("observed_imported_or_command"))
        fields.set("commandProjection", Json::boolean(true))
        fields.set("persisted", Json::boolean(true))
        result.push(Json::object(fields))
      }
      None => result.push(finding)
    }
  }
  result
}

///|
fn warning_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String)? {
  let prefix = "/api/company/warning/"
  if request_method is @http.Post && path.has_prefix(prefix) {
    let rest = path[prefix.length():].to_owned().split("/").to_array()
    if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
      let command = match rest[1].to_owned() {
        "resolve" => "resolve"
        "ignore" => "ignore"
        _ => ""
      }
      if !command.is_empty() {
        return Some((command, rest[0].to_owned()))
      }
    }
  }
  None
}

///|
fn warning_rule_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  let prefixes = [
    "/api/company/warning/rules/", "/api/company/source/warning/rules/",
  ]
  for prefix in prefixes {
    if request_method is @http.Patch && path.has_prefix(prefix) {
      let code = path[prefix.length():].to_owned()
      if valid_identifier(code) {
        return Some(code)
      }
    }
  }
  None
}

///|
fn warning_builtin_rule_code(code : String) -> Bool {
  [
    "W001", "W002", "W003", "W004", "W005", "W006", "W007", "W008", "W009", "W010",
    "W011", "W012",
  ].contains(code)
}

///|
async fn warning_rule_config_states() -> Map[String, Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM (SELECT DISTINCT ON (aggregate_id) aggregate_id, payload FROM company_aggregate_projection WHERE aggregate_type = 'warning_rule_config' ORDER BY aggregate_id, revision DESC) latest ORDER BY aggregate_id LIMIT 500",
  )
  let result : Map[String, Json] = {}
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 2)
      let payload = @json.parse(decode_hex(row[1])) catch {
        _ => raise fail("invalid warning rule projection JSON")
      }
      result.set(decode_hex(row[0]), payload)
    }
  }
  result
}

///|
async fn warning_rule_config_command(
  rule_code : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !warning_builtin_rule_code(rule_code) {
    raise reject(404, "warning rule does not exist")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let _ = rbac_require_super(actor_id)
  let enabled = json_bool(body, "enabled", false)
  let request = Json::object({
    "rule_code": Json::string(rule_code),
    "enabled": Json::boolean(enabled),
    "actor_id": Json::string(actor_id),
  })
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
      return (
        200,
        Json::object({
          "command": existing,
          "warning": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let event_id = "warning:rule_config:" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "ruleCode": Json::string(rule_code),
    "enabled": Json::boolean(enabled),
    "sourceKind": Json::string("command"),
    "commandProjection": Json::boolean(true),
    "persisted": Json::boolean(true),
    "authorization_candidate": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("warning"),
    "command_type": Json::string("rule_config"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("warning_rule_config"),
    "aggregate_id": Json::string(rule_code),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let projection = Json::object({
    "rule_code": Json::string(rule_code),
    "enabled": Json::boolean(enabled),
    "source_kind": Json::string("command"),
    "event_id": Json::string(event_id),
    "updated_by": Json::string(actor_id),
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("warning.rule_config"),
    "aggregate_type": Json::string("warning_rule_config"),
    "aggregate_id": Json::string(rule_code),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "enabled": Json::boolean(enabled),
    "authorization_candidate": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
  })
  let sql = "BEGIN; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT 'warning_rule_config', " +
    @postgres.sql_literal(rule_code) +
    ", coalesce(max(revision), 0) + 1, " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    " FROM company_aggregate_projection WHERE aggregate_type = 'warning_rule_config' AND aggregate_id = " +
    @postgres.sql_literal(rule_code) +
    "; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  let receipt = existing_company_command(idempotency_key)
  let receipt = match receipt {
    Some(value) => value
    None => raise fail("warning rule command receipt was not persisted")
  }
  (
    200,
    Json::object({
      "command": receipt,
      "warning": json_field(receipt, "result").unwrap_or(result),
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
async fn warning_state_command(
  command_type : String,
  warning_guid : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if command_type != "resolve" && command_type != "ignore" {
    raise reject(404, "unsupported warning command")
  }
  if !valid_identifier(warning_guid) {
    raise reject(422, "warning guid contains unsupported characters")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let note = json_text(body, "note", "").trim().to_owned()
  if note.length() > 1024 {
    raise reject(422, "note must be text")
  }
  let request = Json::object({
    "warning_guid": Json::string(warning_guid),
    "command_type": Json::string(command_type),
    "note": Json::string(note),
    "actor_id": Json::string(actor_id),
  })
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      let stored = json_field(existing, "request").unwrap_or(Json::null())
      if !json_equal(stored, request) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "warning": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let rows = warning_context()
  let findings = warning_findings(rows)
  let mut matched : Json? = None
  for finding in findings {
    if report_text(finding, "warningGuid", "") == warning_guid {
      matched = Some(finding)
    }
  }
  let finding = match matched {
    Some(value) => value
    None => raise reject(404, "告警不存在或未由当前源观察产生")
  }
  let states = warning_command_states()
  match states.get(warning_guid) {
    Some(state) if report_text(state, "state", "open") != "open" =>
      raise reject(409, "告警已处理")
    _ => ()
  }
  let next_state = if command_type == "resolve" {
    "resolved"
  } else {
    "ignored"
  }
  let event_id = "warning:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let command_source = "moonproj:command:" + idempotency_key
  let changed_at = run_sql(
      "SELECT to_char(current_timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')",
    )
    .trim()
    .to_owned()
  let result = Json::object({
    "warningGuid": Json::string(warning_guid),
    "ruleCode": json_field(finding, "ruleCode").unwrap_or(Json::string("")),
    "state": Json::string(next_state),
    "status": Json::string(next_state),
    "note": Json::string(note),
    "changed_at": Json::string(changed_at),
    "sourceKind": Json::string("command"),
    "commandProjection": Json::boolean(true),
    "persisted": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "providerExecution": Json::boolean(false),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
  })
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("warning"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("warning_state"),
    "aggregate_id": Json::string(warning_guid),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let projection_payload = Json::object({
    "warning_guid": Json::string(warning_guid),
    "command_type": Json::string(command_type),
    "note": Json::string(note),
    "actor_id": Json::string(actor_id),
    "state": Json::string(next_state),
    "source_kind": Json::string("command"),
    "event_id": Json::string(event_id),
    "updated_by": Json::string(actor_id),
    "changed_at": Json::string(changed_at),
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("warning." + command_type),
    "aggregate_type": Json::string("warning_state"),
    "aggregate_id": Json::string(warning_guid),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(next_state),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(command_source) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT 'warning_state', " +
    @postgres.sql_literal(warning_guid) +
    ", coalesce(max(revision), 0) + 1, " +
    @postgres.sql_literal(projection_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    " FROM company_aggregate_projection WHERE aggregate_type = 'warning_state' AND aggregate_id = " +
    @postgres.sql_literal(warning_guid) +
    "; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; UPDATE company_record SET payload = payload || jsonb_build_object('result', " +
    @postgres.sql_literal(result.stringify()) +
    "::jsonb) WHERE source_id = " +
    @postgres.sql_literal(command_source) +
    "; COMMIT;"
  let _ = run_sql(sql)
  let receipt = existing_company_command(idempotency_key)
  let receipt = match receipt {
    Some(value) => value
    None => raise fail("warning command receipt was not persisted")
  }
  (
    200,
    Json::object({
      "command": receipt,
      "warning": json_field(receipt, "result").unwrap_or(result),
      "idempotent_replay": Json::boolean(false),
    }),
  )
}

///|
fn warning_finding(
  code : String,
  name : String,
  severity : String,
  biz_type : String,
  guid : String,
  title : String,
  detail : String,
) -> Json {
  Json::object({
    "warningGuid": Json::string("source:" + code + ":" + guid),
    "ruleCode": Json::string(code),
    "ruleName": Json::string(name),
    "severity": Json::string(severity),
    "bizType": Json::string(biz_type),
    "bizDataGuid": Json::string(guid),
    "title": Json::string(title),
    "detail": Json::string(detail),
    "firstDetectedAt": Json::null(),
    "lastScanAt": Json::null(),
    "resolvedAt": Json::null(),
    "resolvedBy": Json::null(),
    "resolvedNote": Json::null(),
    "status": Json::string("open"),
    "sourceKind": Json::string("observed_imported"),
  })
}

///|
fn warning_findings(rows : Map[String, Array[SourceRow]]) -> Array[Json] {
  let projects = rows.get_or_default("ep_project", [])
  let costs = rows.get_or_default("cb_cost", [])
  let cost_projects : Map[String, Bool] = {}
  for row in costs {
    if json_field(row.payload, "deleted_at") is None &&
      json_bool(row.payload, "is_end_cost", false) {
      cost_projects.set(report_text(row.payload, "proj_guid", ""), true)
    }
  }
  let findings : Array[Json] = []
  for row in projects {
    let payload = row.payload
    let project_id = report_text(payload, "proj_guid", row.record_id)
    let status = report_text(payload, "proj_status", "")
    if json_field(payload, "deleted_at") is None &&
      (status == "planning" || status == "development" || status == "sales") &&
      !cost_projects.contains(project_id) {
      findings.push(
        warning_finding(
          "W005",
          "在建项目无动态成本科目",
          "warning",
          "project",
          project_id,
          report_text(payload, "proj_name", project_id),
          "缺少动态成本末级科目",
        ),
      )
    }
    if json_field(payload, "deleted_at") is None &&
      report_text(payload, "bu_guid", "").is_empty() {
      findings.push(
        warning_finding(
          "W001",
          "项目缺少所属公司",
          "error",
          "project",
          project_id,
          report_text(payload, "proj_name", project_id),
          "",
        ),
      )
    }
  }
  findings.sort_by(fn(left, right) {
    let code_compare = report_text(left, "ruleCode", "").compare(
      report_text(right, "ruleCode", ""),
    )
    if code_compare != 0 {
      code_compare
    } else {
      report_text(left, "bizDataGuid", "").compare(
        report_text(right, "bizDataGuid", ""),
      )
    }
  })
  findings
}

///|
async fn warning_list_response(
  status : String?,
  rule_code : String?,
  severity : String?,
  biz_type : String?,
) -> Json raise CompanyServiceError {
  let rows = warning_context()
  let coverage = warning_coverage(rows)
  let states = warning_command_states()
  let findings = warning_overlay_findings(warning_findings(rows), states).filter(fn(
      item,
    ) {
      let status_ok = match status {
        Some(value) if value != "all" =>
          report_text(item, "status", "") == value
        _ => true
      }
      let rule_ok = match rule_code {
        Some(value) => report_text(item, "ruleCode", "") == value
        None => true
      }
      let severity_ok = match severity {
        Some(value) => report_text(item, "severity", "") == value
        None => true
      }
      let biz_ok = match biz_type {
        Some(value) => report_text(item, "bizType", "") == value
        None => true
      }
      status_ok && rule_ok && severity_ok && biz_ok
    },
  )
  warning_envelope(
    Json::object({
      "total": Json::number(findings.length().to_double()),
      "rows": Json::array(findings),
    }),
    coverage,
    states.length(),
  )
}

///|
async fn warning_badge_response() -> Json raise CompanyServiceError {
  let rows = warning_context()
  let coverage = warning_coverage(rows)
  let states = warning_command_states()
  let findings = warning_overlay_findings(warning_findings(rows), states)
  warning_envelope(
    Json::object({
      "openTotal": Json::number(findings.length().to_double()),
      "top": Json::array(findings),
    }),
    coverage,
    states.length(),
  )
}

///|
async fn warning_rules_response() -> Json raise CompanyServiceError {
  let rows = warning_context()
  let coverage = warning_coverage(rows)
  let states = warning_command_states()
  let configs = warning_rule_config_states()
  let findings = warning_overlay_findings(warning_findings(rows), states)
  let codes : Array[String] = [
    "W001", "W002", "W003", "W004", "W005", "W006", "W007", "W008", "W009", "W010",
    "W011", "W012",
  ]
  let names : Array[String] = [
    "项目缺少所属公司", "合同未关联项目", "付款申请缺少合同",
    "付款累计超合同总额", "在建项目无动态成本科目", "报销分摊合计 ≠ 应付金额",
    "BPM 实例进行中超 7 天", "借款三态字段不一致", "任务计划完成日 < 开始日",
    "供应商重名(SRM)", "BPM 僵尸(>30 天 Running)", "用户缺少所属组织",
  ]
  let severities : Array[String] = [
    "error", "error", "error", "error", "warning", "error", "warning", "error", "warning",
    "warning", "error", "warning",
  ]
  let biz_types : Array[String] = [
    "project", "contract", "htfk_apply", "contract", "project", "expense", "wf_instance",
    "loan", "jd_task", "srm_provider", "wf_instance", "sys_user",
  ]
  let result : Array[Json] = []
  for index in 0..<codes.length() {
    let code = codes[index]
    let name = names[index]
    let severity = severities[index]
    let biz_type = biz_types[index]
    let open_count = findings.fold(init=0, fn(total, item) {
      total +
      (if report_text(item, "ruleCode", "") == code &&
        report_text(item, "status", "") == "open" {
        1
      } else {
        0
      })
    })
    let enabled = match configs.get(code) {
      Some(config) => json_bool(config, "enabled", true)
      None => true
    }
    result.push(
      Json::object({
        "ruleCode": Json::string(code),
        "ruleName": Json::string(name),
        "severity": Json::string(severity),
        "bizType": Json::string(biz_type),
        "enabled": Json::boolean(enabled),
        "openCount": Json::number(open_count.to_double()),
        "custom": Json::boolean(false),
        "sourceKind": Json::string(
          if configs.contains(code) {
            "command"
          } else {
            "observed_imported"
          },
        ),
        "commandProjection": Json::boolean(configs.contains(code)),
      }),
    )
  }
  warning_envelope(
    Json::array(result),
    coverage,
    states.length() + configs.length(),
  )
}

///|
async fn warning_empty_response(
  table : String,
) -> Json raise CompanyServiceError {
  let rows = warning_context()
  warning_envelope(Json::array([]), warning_coverage(rows), 0)
}
