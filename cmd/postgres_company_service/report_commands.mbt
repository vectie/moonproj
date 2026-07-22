///|
/// Native report-builder metadata, local template commands, and safe runs.
///
/// Templates are configuration projections. A run evaluates imported JSON
/// envelopes in memory against an allow-listed table/field/operator set; it
/// never accepts or executes SQL and never creates financial effects.

///|
fn report_template_definition(
  name : String,
  label : String,
  columns : Array[(String, String)],
  filterable : Array[(String, String)],
) -> Json {
  let column_values : Array[Json] = []
  for item in columns {
    let field = item.0
    let column_label = item.1
    column_values.push(
      Json::object({
        "field": Json::string(field),
        "label": Json::string(column_label),
      }),
    )
  }
  let filterable_values : Map[String, Json] = {}
  for item in filterable {
    let field = item.0
    let field_type = item.1
    filterable_values.set(field, Json::string(field_type))
  }
  Json::object({
    "name": Json::string(name),
    "label": Json::string(label),
    "columns": Json::array(column_values),
    "filterableTypes": Json::object(filterable_values),
  })
}

///|
fn report_template_metadata_tables() -> Array[Json] {
  [
    report_template_definition(
      "ep_project",
      "项目",
      [
        ("proj_code", "项目编码"),
        ("proj_name", "项目名称"),
        ("bu_guid", "公司ID"),
        ("proj_status", "阶段"),
        ("begin_date", "开始日期"),
      ],
      [
        ("proj_code", "text"),
        ("proj_name", "text"),
        (
          "proj_status", "enum:initiation/acquisition/planning/development/sales/delivery/settlement",
        ),
        ("begin_date", "date"),
      ],
    ),
    report_template_definition(
      "cb_contract",
      "合同",
      [
        ("contract_code", "合同号"),
        ("contract_name", "合同名"),
        ("yf_provider_name", "乙方"),
        ("ht_amount", "合同金额"),
        ("sum_alter_amount", "累计变更"),
        ("sign_date", "签订日"),
        ("js_state", "结算状态"),
        ("r_code", "R 编码"),
        ("l3_code", "CBS 三级"),
        ("cb_state", "CB 状态"),
      ],
      [
        ("contract_code", "text"),
        ("contract_name", "text"),
        ("yf_provider_name", "text"),
        ("ht_amount", "number"),
        ("sign_date", "date"),
        ("r_code", "text"),
        ("l3_code", "text"),
        ("cb_state", "enum:draft/approving/signed/paid"),
      ],
    ),
    report_template_definition(
      "cb_htfk_apply",
      "付款申请",
      [
        ("apply_code", "申请号"),
        ("subject", "事由"),
        ("apply_amount", "申请金额"),
        ("apply_state", "申请状态"),
        ("pay_state", "支付状态"),
        ("apply_date", "申请日"),
      ],
      [
        ("apply_code", "text"),
        ("subject", "text"),
        ("apply_amount", "number"),
        ("apply_state", "text"),
        ("pay_state", "text"),
        ("apply_date", "date"),
      ],
    ),
    report_template_definition(
      "vcb_expense",
      "报销",
      [
        ("expense_code", "报销号"),
        ("subject", "主题"),
        ("pay_amount", "应付金额"),
        ("apply_state", "状态"),
        ("apply_date", "申请日"),
      ],
      [
        ("expense_code", "text"),
        ("subject", "text"),
        ("pay_amount", "number"),
        ("apply_state", "text"),
        ("apply_date", "date"),
      ],
    ),
    report_template_definition(
      "vcb_loan_simple",
      "借款",
      [
        ("loan_code", "借款号"),
        ("subject", "主题"),
        ("loan_amount", "借款金额"),
        ("remain_amount", "剩余"),
        ("apply_state", "状态"),
        ("apply_date", "申请日"),
      ],
      [
        ("loan_code", "text"),
        ("subject", "text"),
        ("loan_amount", "number"),
        ("apply_state", "text"),
        ("apply_date", "date"),
      ],
    ),
    report_template_definition(
      "srm_provider",
      "供应商",
      [
        ("provider_code", "编码"),
        ("provider_name", "供应商"),
        ("short_name", "简称"),
        ("main_category_code", "类别"),
        ("eval_result", "评级"),
        ("contact_person", "联系人"),
      ],
      [
        ("provider_code", "text"),
        ("provider_name", "text"),
        ("main_category_code", "text"),
        ("eval_result", "text"),
      ],
    ),
    report_template_definition(
      "jd_task",
      "任务",
      [
        ("task_code", "编码"),
        ("task_name", "任务"),
        ("task_type", "类型"),
        ("plan_end_date", "计划完成"),
        ("progress_pct", "进度"),
        ("status", "状态"),
      ],
      [
        ("task_name", "text"),
        ("task_type", "text"),
        ("plan_end_date", "date"),
        ("status", "text"),
      ],
    ),
    report_template_definition(
      "sale_revenue",
      "销售回款",
      [
        ("revenue_code", "编码"),
        ("customer_name", "客户"),
        ("amount", "金额"),
        ("receive_date", "到账日"),
        ("status", "状态"),
        ("payment_type", "付款类型"),
      ],
      [
        ("customer_name", "text"),
        ("amount", "number"),
        ("receive_date", "date"),
        ("status", "text"),
      ],
    ),
    report_template_definition(
      "cb_subject_dict",
      "CBS 字典(v3)",
      [
        ("l3_code", "CBS 三级"),
        ("r_code", "R 编码"),
        ("l2_name", "大类"),
        ("subject", "子项"),
        ("plan_amount", "计划金额(万)"),
        ("plan_version", "版本"),
        ("src", "来源"),
      ],
      [
        ("l3_code", "text"),
        ("r_code", "text"),
        ("l2_name", "text"),
        ("subject", "text"),
        ("plan_amount", "number"),
        ("plan_version", "text"),
        ("src", "enum:seed/manual/cloned"),
      ],
    ),
    report_template_definition(
      "cb_change_apply",
      "合同变更(v3)",
      [
        ("change_code", "变更号"),
        ("reason", "原因"),
        ("change_amount", "金额"),
        ("state", "状态"),
        ("r_code", "R 编码"),
        ("l3_code", "CBS"),
        ("apply_date", "申请日"),
      ],
      [
        ("change_code", "text"),
        ("reason", "text"),
        ("change_amount", "number"),
        ("state", "enum:estimated/approving/confirmed"),
        ("r_code", "text"),
        ("l3_code", "text"),
        ("apply_date", "date"),
      ],
    ),
  ]
}

///|
fn report_template_definition_for(name : String) -> Json? {
  for item in report_template_metadata_tables() {
    if json_text(item, "name", "") == name {
      return Some(item)
    }
  }
  None
}

///|
fn report_template_field_names(definition : Json) -> Array[String] {
  match json_field(definition, "columns") {
    Some(Array(values)) =>
      values.map(fn(value) { json_text(value, "field", "") })
    _ => []
  }
}

///|
fn report_template_field_type(definition : Json, field : String) -> String {
  match json_field(definition, "filterableTypes") {
    Some(Object(values)) => json_text(Json::object(values), field, "text")
    _ => "text"
  }
}

///|
fn report_template_text(
  body : Json,
  primary : String,
  alternate : String,
  required : Bool,
  max_length : Int,
) -> String raise CompanyServiceError {
  let value = match json_field(body, primary) {
    Some(String(text)) => text
    Some(Null) | None =>
      match json_field(body, alternate) {
        Some(String(text)) => text
        Some(Null) | None => ""
        Some(_) => raise reject(400, primary + " must be text")
      }
    Some(_) => raise reject(400, primary + " must be text")
  }
  let trimmed = value.trim().to_owned()
  if required && trimmed.is_empty() {
    raise reject(400, primary + " is required")
  }
  if trimmed.length() > max_length {
    raise reject(400, primary + " is too long")
  }
  trimmed
}

///|
fn report_template_array(
  body : Json,
  key : String,
) -> Array[Json] raise CompanyServiceError {
  match json_field(body, key) {
    Some(Array(values)) => values
    Some(Null) | None => []
    Some(_) => raise reject(400, key + " must be an array")
  }
}

///|
fn report_template_json_array(
  payload : Json,
  primary : String,
  alternate : String,
) -> Json {
  fn parse_array(text : String) -> Json {
    let parsed = @json.parse(text) catch { _ => Json::null() }
    match parsed {
      Array(values) => Json::array(values)
      _ => Json::array([])
    }
  }
  match json_field(payload, primary) {
    Some(Array(values)) => Json::array(values)
    Some(String(text)) => parse_array(text)
    _ =>
      match json_field(payload, alternate) {
        Some(Array(values)) => Json::array(values)
        Some(String(text)) => parse_array(text)
        _ => Json::array([])
      }
  }
}

///|
fn report_template_spec(
  body : Json,
  require_name : Bool,
) -> Json raise CompanyServiceError {
  let base_table = report_template_text(
    body, "baseTable", "base_table", true, 64,
  )
  let definition = match report_template_definition_for(base_table) {
    Some(value) => value
    None => raise reject(400, "unsupported baseTable")
  }
  let valid_fields = report_template_field_names(definition)
  let raw_columns = report_template_array(body, "columns")
  if raw_columns.is_empty() {
    raise reject(400, "please select at least one column")
  }
  let columns : Array[String] = []
  let seen : Map[String, Bool] = {}
  for value in raw_columns {
    let column = match value {
      String(text) => text.trim().to_owned()
      _ => raise reject(400, "columns must be text values")
    }
    if column.is_empty() {
      continue
    }
    if !valid_fields.contains(column) {
      raise reject(400, "invalid column")
    }
    if seen.contains(column) {
      raise reject(400, "columns contains duplicates")
    }
    seen.set(column, true)
    columns.push(column)
  }
  if columns.is_empty() {
    raise reject(400, "please select at least one column")
  }
  let raw_filters = report_template_array(body, "filters")
  let filters : Array[Json] = []
  for item in raw_filters {
    let fields = match item {
      Object(values) => values
      _ => raise reject(400, "filter must be an object")
    }
    let field = match fields.get("field") {
      Some(String(text)) if !text.trim().is_empty() => text.trim().to_owned()
      _ => raise reject(400, "filter field is required")
    }
    let operator = match fields.get("op") {
      Some(String(text)) if !text.trim().is_empty() => text.trim().to_owned()
      _ => raise reject(400, "filter op is required")
    }
    if !valid_fields.contains(field) {
      raise reject(400, "invalid filter field")
    }
    if !["=", "!=", ">", ">=", "<", "<=", "like", "in"].contains(operator) {
      raise reject(400, "invalid filter operator")
    }
    filters.push(
      Json::object({
        "field": Json::string(field),
        "op": Json::string(operator),
        "value": fields.get("value").unwrap_or(Json::null()),
      }),
    )
  }
  let order_by = report_template_text(body, "orderBy", "order_by", false, 128)
  let mut order_field = ""
  let mut order_direction = "asc"
  if !order_by.is_empty() {
    let parts : Array[String] = order_by
      .split(" ")
      .map(fn(value) { value.to_owned() })
      .filter(fn(value) { !value.is_empty() })
      .to_array()
    if parts.is_empty() ||
      parts.length() > 2 ||
      !valid_fields.contains(parts[0]) {
      raise reject(400, "invalid order field")
    }
    order_field = parts[0]
    if parts.length() == 2 {
      order_direction = parts[1].to_lower()
      if order_direction != "asc" && order_direction != "desc" {
        raise reject(400, "invalid order direction")
      }
    }
  }
  let is_shared = match json_field(body, "isShared") {
    Some(True) => true
    Some(False) | None =>
      match json_field(body, "is_shared") {
        Some(True) => true
        Some(False) | None => false
        Some(_) => raise reject(400, "isShared must be boolean")
      }
    Some(_) => raise reject(400, "isShared must be boolean")
  }
  Json::object({
    "template_name": Json::string(
      report_template_text(
        body, "templateName", "template_name", require_name, 128,
      ),
    ),
    "description": Json::string(
      report_template_text(body, "description", "", false, 1024),
    ),
    "base_table": Json::string(base_table),
    "columns": Json::array(columns.map(fn(value) { Json::string(value) })),
    "filters": Json::array(filters),
    "order_by": Json::string(order_by),
    "order_field": Json::string(order_field),
    "order_direction": Json::string(order_direction),
    "is_shared": Json::boolean(is_shared),
  })
}

///|
async fn report_template_projection_payloads() -> Array[Json] raise CompanyServiceError {
  let output = run_sql(
    "SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'), revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'report_template' ORDER BY aggregate_id, revision LIMIT 4000",
  )
  let latest : Map[String, Json] = {}
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if !line.is_empty() {
      let row = fields(line, 3)
      let payload = @json.parse(decode_hex(row[2])) catch {
        _ => raise fail("invalid report template projection JSON")
      }
      latest.set(decode_hex(row[0]), payload)
    }
  }
  let result : Array[Json] = []
  for _, payload in latest {
    result.push(payload)
  }
  result
}

///|
async fn report_template_latest_projection(
  template_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'report_template' AND aggregate_id = " +
    @postgres.sql_literal(template_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid report template projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn report_template_source_row(
  payload : Json,
  template_id : String,
  source_id : String,
  source_kind : String,
) -> Json {
  Json::object({
    "templateId": Json::string(json_text(payload, "template_id", template_id)),
    "templateName": Json::string(
      json_text(
        payload,
        "template_name",
        json_text(payload, "templateName", ""),
      ),
    ),
    "description": Json::string(json_text(payload, "description", "")),
    "baseTable": Json::string(
      json_text(payload, "base_table", json_text(payload, "baseTable", "")),
    ),
    "columns": report_template_json_array(payload, "columns", "columns_json"),
    "filters": report_template_json_array(payload, "filters", "filters_json"),
    "orderBy": Json::string(
      json_text(payload, "order_by", json_text(payload, "orderBy", "")),
    ),
    "createdBy": Json::string(
      json_text(
        payload,
        "created_by",
        json_text(payload, "createdBy", json_text(payload, "actor_id", "")),
      ),
    ),
    "createdAt": Json::string(
      json_text(payload, "created_at", json_text(payload, "createdAt", "")),
    ),
    "isShared": Json::boolean(
      json_bool(payload, "is_shared", json_bool(payload, "isShared", false)),
    ),
    "isMine": Json::boolean(source_kind == "command"),
    "sourceKind": Json::string(source_kind),
    "sourceId": Json::string(source_id),
  })
}

///|
async fn report_template_list_response() -> Json raise CompanyServiceError {
  let source_rows = raw_source_rows("sys_report_template", 500)
  let local_rows = report_template_projection_payloads()
  let items : Array[Json] = []
  for row in source_rows {
    if json_field(row.payload, "deleted_at") is None {
      items.push(
        report_template_source_row(
          row.payload,
          json_text(row.payload, "template_id", row.record_id),
          row.source_id,
          "imported",
        ),
      )
    }
  }
  let mut command_count = 0
  for payload in local_rows {
    if json_text(payload, "state", "active") != "deleted" {
      command_count += 1
      items.push(
        report_template_source_row(
          payload,
          json_text(payload, "template_id", ""),
          json_text(payload, "source_id", json_text(payload, "template_id", "")),
          "command",
        ),
      )
    }
  }
  items.sort_by(fn(left, right) {
    let left_date = json_text(left, "createdAt", "")
    let right_date = json_text(right, "createdAt", "")
    let date_order = right_date.compare(left_date)
    if date_order == 0 {
      json_text(right, "templateId", "").compare(
        json_text(left, "templateId", ""),
      )
    } else {
      date_order
    }
  })
  let coverage : Map[String, Int] = {}
  coverage.set("sys_report_template", source_rows.length())
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(items),
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": report_missing(coverage),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "command_projection": Json::boolean(command_count > 0),
    "command_projection_count": Json::number(command_count.to_double()),
  })
}

///|
fn report_template_metadata_response_native() -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::object({
      "tables": Json::array(report_template_metadata_tables()),
      "operators": Json::array([
        Json::string("="),
        Json::string("!="),
        Json::string(">"),
        Json::string(">="),
        Json::string("<"),
        Json::string("<="),
        Json::string("like"),
        Json::string("in"),
      ]),
    }),
    "source_kind": Json::string("definition"),
    "source_coverage": Json::object({}),
    "missing_or_empty_source_tables": Json::array([]),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn report_template_scalar_text(value : Json) -> String {
  match value {
    String(text) => text
    Number(number, ..) => number.to_string()
    True => "true"
    False => "false"
    Null => ""
    _ => value.stringify()
  }
}

///|
fn report_template_scalar_number(value : Json) -> Double {
  match value {
    Number(number, ..) => number
    String(text) => parse_number(text)
    _ => 0.0
  }
}

///|
fn report_template_compare(
  left : Json,
  right : Json,
  field_type : String,
) -> Int {
  if field_type == "number" {
    report_template_scalar_number(left).compare(
      report_template_scalar_number(right),
    )
  } else {
    report_template_scalar_text(left).compare(
      report_template_scalar_text(right),
    )
  }
}

///|
fn report_template_filter_matches(
  payload : Json,
  filters : Json,
  definition : Json,
) -> Bool {
  match filters {
    Array(values) =>
      values.all(fn(item) {
        match item {
          Object(fields) => {
            let field = json_text(item, "field", "")
            let operator = json_text(item, "op", "")
            let left = json_field(payload, field).unwrap_or(Json::null())
            let right = fields.get("value").unwrap_or(Json::null())
            let field_type = report_template_field_type(definition, field)
            if operator == "in" {
              match right {
                Array(values) =>
                  values.any(fn(value) {
                    report_template_compare(left, value, field_type) == 0
                  })
                _ =>
                  report_template_scalar_text(right)
                  .split(",")
                  .map(fn(value) {
                    report_template_compare(
                      left,
                      Json::string(value.trim().to_owned()),
                      field_type,
                    ) ==
                    0
                  })
                  .any(fn(value) { value })
              }
            } else if operator == "like" {
              report_template_scalar_text(left)
              .to_lower()
              .contains(report_template_scalar_text(right).to_lower())
            } else {
              let comparison = report_template_compare(left, right, field_type)
              if operator == "=" {
                comparison == 0
              } else if operator == "!=" {
                comparison != 0
              } else if operator == ">" {
                comparison > 0
              } else if operator == ">=" {
                comparison >= 0
              } else if operator == "<" {
                comparison < 0
              } else if operator == "<=" {
                comparison <= 0
              } else {
                true
              }
            }
          }
          _ => false
        }
      })
    _ => true
  }
}

///|
async fn report_template_run_native(
  body : Json,
) -> (Int, Json) raise CompanyServiceError {
  let spec = report_template_spec(body, false)
  let base_table = json_text(spec, "base_table", "")
  let definition = report_template_definition_for(base_table).unwrap()
  let limit_value = match json_field(body, "limit") {
    Some(Number(number, ..)) if number >= 1.0 => number.to_int()
    Some(String(text)) => parse_number(text).to_int()
    None => 200
    _ => raise reject(400, "limit must be an integer")
  }
  let limit = if limit_value < 1 {
    1
  } else if limit_value > 1000 {
    1000
  } else {
    limit_value
  }
  let raw_rows = raw_source_rows(base_table, 1000)
  let filters = json_field(spec, "filters").unwrap_or(Json::array([]))
  let order_field = json_text(spec, "order_field", "")
  let order_direction = json_text(spec, "order_direction", "asc")
  let selected_rows : Array[SourceRow] = []
  for row in raw_rows {
    if json_field(row.payload, "deleted_at") is None &&
      report_template_filter_matches(row.payload, filters, definition) {
      selected_rows.push(row)
    }
  }
  if !order_field.is_empty() {
    let field_type = report_template_field_type(definition, order_field)
    selected_rows.sort_by(fn(left, right) {
      let comparison = report_template_compare(
        json_field(left.payload, order_field).unwrap_or(Json::null()),
        json_field(right.payload, order_field).unwrap_or(Json::null()),
        field_type,
      )
      if order_direction == "desc" {
        -comparison
      } else {
        comparison
      }
    })
  }
  let selected_columns = json_field(spec, "columns").unwrap_or(Json::array([]))
  let columns : Array[Json] = []
  match json_field(definition, "columns") {
    Some(Array(values)) =>
      match selected_columns {
        Array(requested) =>
          for column in values {
            let field = json_text(column, "field", "")
            if requested.any(fn(value) {
                report_template_scalar_text(value) == field
              }) {
              columns.push(column)
            }
          }
        _ => ()
      }
    _ => ()
  }
  let rows : Array[Json] = []
  let mut index = 0
  while index < selected_rows.length() && rows.length() < limit {
    let row = selected_rows[index]
    let output : Map[String, Json] = {}
    match selected_columns {
      Array(requested) =>
        for column in requested {
          let field = report_template_scalar_text(column)
          output.set(
            field,
            json_field(row.payload, field).unwrap_or(Json::null()),
          )
        }
      _ => ()
    }
    rows.push(Json::object(output))
    index += 1
  }
  let coverage : Map[String, Int] = {}
  for table in report_template_metadata_tables() {
    let name = json_text(table, "name", "")
    coverage.set(name, raw_source_rows(name, 1000).length())
  }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "sql": Json::null(),
        "sql_executed": Json::boolean(false),
        "rows": Json::array(rows),
        "total": Json::number(rows.length().to_double()),
        "columns": Json::array(columns),
      }),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": report_missing(coverage),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
    }),
  )
}

///|
fn report_template_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String?)? {
  if path == "/api/company/reports/templates" && request_method is @http.Post {
    return Some(("create", None))
  }
  let prefix = "/api/company/reports/templates/"
  if path.has_prefix(prefix) {
    let template_id = path[prefix.length():].to_owned()
    if valid_identifier(template_id) && request_method is @http.Delete {
      return Some(("delete", Some(template_id)))
    }
  }
  None
}

///|
fn report_template_command_envelope(
  command : Json,
  template : Json,
  replay : Bool,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "command": command,
    "template": template,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
fn report_template_copy_fields(value : Json) -> Map[String, Json] {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = {}
      fields.each((key, item) => result.set(key, item))
      result
    }
    _ => {}
  }
}

///|
fn report_template_hash_id(idempotency_key : String) -> String {
  let digest = @crypto.sha256(@encoding/utf8.encode(idempotency_key))
  "RPT-CMD-" + @crypto.bytes_to_hex_string(digest)[:24].to_owned()
}

///|
async fn report_template_command(
  command_type : String,
  template_id : String?,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let actor_user = auth_current_user(actor_id)
  match actor_user {
    Some(value) if json_bool(
        json_field(value, "data").unwrap_or(Json::null()),
        "enabled",
        false,
      ) => ()
    _ => raise reject(403, "user not found or disabled")
  }
  let expected_request = if command_type == "create" {
    let spec = report_template_spec(body, true)
    let id = report_template_hash_id(idempotency_key)
    let request = report_template_copy_fields(spec)
    request.set("command_type", Json::string("create"))
    request.set("template_id", Json::string(id))
    request.set("actor_id", Json::string(actor_id))
    Json::object(request)
  } else {
    let id = match template_id {
      Some(value) if valid_identifier(value) => value
      _ => raise reject(422, "template_id is required")
    }
    let reason = report_template_text(body, "reason", "", false, 1024)
    Json::object({
      "command_type": Json::string("delete"),
      "template_id": Json::string(id),
      "actor_id": Json::string(actor_id),
      "reason": Json::string(reason),
    })
  }
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          expected_request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        report_template_command_envelope(
          existing,
          json_field(existing, "result").unwrap_or(Json::null()),
          true,
        ),
      )
    }
    None => ()
  }
  let aggregate_id = json_text(expected_request, "template_id", "")
  let current = report_template_latest_projection(aggregate_id)
  if command_type == "create" {
    if current is Some(_) {
      raise reject(409, "report template already exists")
    }
    let imported = raw_source_rows("sys_report_template", 500)
    if imported.any(fn(row) {
        json_text(row.payload, "template_id", row.record_id) == aggregate_id
      }) {
      raise reject(409, "imported report template is read-only")
    }
  } else {
    let current_payload = match current {
      Some((value, _)) => value
      None => {
        let imported = raw_source_rows("sys_report_template", 500)
        if imported.any(fn(row) {
            json_text(row.payload, "template_id", row.record_id) == aggregate_id
          }) {
          raise reject(409, "imported report template is read-only")
        }
        raise reject(404, "template not found")
      }
    }
    if json_text(current_payload, "state", "active") == "deleted" {
      raise reject(409, "template is already deleted")
    }
    if json_text(
        current_payload,
        "created_by",
        json_text(current_payload, "actor_id", ""),
      ) !=
      actor_id {
      raise reject(403, "only the template owner can delete it")
    }
  }
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "report_template:" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let next_payload = if command_type == "create" {
    let fields = report_template_copy_fields(expected_request)
    fields.set("state", Json::string("active"))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("created_by", Json::string(actor_id))
    fields.set("created_at", Json::string(event_id))
    Json::object(fields)
  } else {
    let fields = report_template_copy_fields(current.unwrap().0)
    fields.set("state", Json::string("deleted"))
    fields.set("deleted_at", Json::string(event_id))
    fields.set("source_kind", Json::string("command"))
    fields.set("event_id", Json::string(event_id))
    fields.set("updated_by", Json::string(actor_id))
    fields.set(
      "reason",
      json_field(expected_request, "reason").unwrap_or(Json::string("")),
    )
    Json::object(fields)
  }
  let result_fields = report_template_copy_fields(next_payload)
  result_fields.set("template_id", Json::string(aggregate_id))
  result_fields.set("templateId", Json::string(aggregate_id))
  result_fields.set(
    "state",
    Json::string(if command_type == "create" { "active" } else { "deleted" }),
  )
  result_fields.set("revision", Json::number(revision.to_double()))
  result_fields.set("event_id", Json::string(event_id))
  result_fields.set("audit_id", Json::string(audit_id))
  result_fields.set("actor_id", Json::string(actor_id))
  result_fields.set("source_kind", Json::string("command"))
  result_fields.set("cash_effect", Json::boolean(false))
  result_fields.set("accounting_effect", Json::boolean(false))
  result_fields.set("tax_effect", Json::boolean(false))
  let result = Json::object(result_fields)
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("report_template"),
    "command_type": Json::string(command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("report_template"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "request": expected_request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("report_template." + command_type),
    "aggregate_type": Json::string("report_template"),
    "aggregate_id": Json::string(aggregate_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "state": Json::string(
      if command_type == "create" {
        "active"
      } else {
        "deleted"
      },
    ),
    "revision": Json::number(revision.to_double()),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('report_template', " +
    @postgres.sql_literal(aggregate_id) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    if command_type == "create" {
      201
    } else {
      200
    },
    report_template_command_envelope(command, result, false),
  )
}
