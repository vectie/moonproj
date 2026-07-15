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
fn warning_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("observed_imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(warning_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "command_projection_count": Json::number(0),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
  })
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
  let findings = warning_findings(rows).filter(fn(item) {
    let status_ok = match status {
      Some(value) if value != "all" => report_text(item, "status", "") == value
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
  })
  warning_envelope(
    Json::object({
      "total": Json::number(findings.length().to_double()),
      "rows": Json::array(findings),
    }),
    coverage,
  )
}

///|
async fn warning_badge_response() -> Json raise CompanyServiceError {
  let rows = warning_context()
  let coverage = warning_coverage(rows)
  let findings = warning_findings(rows)
  warning_envelope(
    Json::object({
      "openTotal": Json::number(findings.length().to_double()),
      "top": Json::array(findings),
    }),
    coverage,
  )
}

///|
async fn warning_rules_response() -> Json raise CompanyServiceError {
  let rows = warning_context()
  let coverage = warning_coverage(rows)
  let findings = warning_findings(rows)
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
    result.push(
      Json::object({
        "ruleCode": Json::string(code),
        "ruleName": Json::string(name),
        "severity": Json::string(severity),
        "bizType": Json::string(biz_type),
        "enabled": Json::boolean(true),
        "openCount": Json::number(open_count.to_double()),
        "custom": Json::boolean(false),
      }),
    )
  }
  warning_envelope(Json::array(result), coverage)
}

///|
async fn warning_empty_response(
  table : String,
) -> Json raise CompanyServiceError {
  let rows = warning_context()
  warning_envelope(Json::array([]), warning_coverage(rows))
}
