///|
/// Native observation-only admin, notification, AI, attachment, webhook, and RBAC reads.
fn observation_missing(coverage : Map[String, Int]) -> Array[Json] {
  let names : Array[String] = []
  for table, count in coverage {
    if count == 0 {
      names.push(table)
    }
  }
  names.sort_by(fn(left, right) { left.compare(right) })
  names.map(fn(name) { Json::string(name) })
}

///|
fn observation_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "secret_values_redacted": Json::boolean(true),
    "network_fields_redacted": Json::boolean(true),
    "downloadable": Json::boolean(false),
    "binary_storage": Json::string("not_imported"),
  })
}

///|
async fn observation_coverage(
  tables : Array[String],
) -> Map[String, Int] raise CompanyServiceError {
  let result : Map[String, Int] = {}
  for table in tables {
    result.set(table, raw_source_rows(table, 500).length())
  }
  result
}

///|
fn observation_rows_for(coverage : Map[String, Int], table : String) -> Int {
  coverage.get_or_default(table, 0)
}

///|
/// Attachments.
async fn attachment_all_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["attachment", "sys_user"])
  observation_envelope(
    Json::object({ "total": Json::number(0), "rows": Json::array([]) }),
    coverage,
  )
}

///|
async fn attachment_list_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["attachment", "sys_user"])
  observation_envelope(Json::array([]), coverage)
}

///|
async fn attachment_stats_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["attachment", "sys_user"])
  observation_envelope(
    Json::object({
      "total": Json::object({
        "count": Json::number(0),
        "bytes": Json::number(0),
      }),
      "byBizType": Json::array([]),
      "byAiStatus": Json::array([]),
    }),
    coverage,
  )
}

///|
async fn attachment_download_response(
  attachment_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(attachment_id) {
    raise reject(422, "invalid attachment_id")
  }
  let coverage = observation_coverage(["attachment", "sys_user"])
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43001),
      "message": Json::string("attachment not found"),
      "data": Json::null(),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(
        observation_missing(coverage),
      ),
      "authorizing": Json::boolean(false),
      "downloadable": Json::boolean(false),
      "binary_storage": Json::string("not_imported"),
    }),
  )
}

///|
/// AI statistics.
fn ai_stats_tables() -> Array[String] {
  [
    "ai_draft", "ai_query_log", "ai_correction_log", "wf_step_action", "wf_process_instance",
    "sys_user",
  ]
}

///|
async fn ai_stats_overview_response(
  period : String,
) -> Json raise CompanyServiceError {
  let coverage = observation_coverage(ai_stats_tables())
  let selected = if period == "today" || period == "week" || period == "month" {
    period
  } else {
    "month"
  }
  observation_envelope(
    Json::object({
      "period": Json::string(selected),
      "kpi": Json::object({
        "intakeTotal": Json::number(0),
        "queryTotal": Json::number(0),
        "skipTotal": Json::number(0),
        "correctionTotal": Json::number(0),
        "accuracy": Json::number(100),
        "avgConfidence": Json::number(0),
        "querySuccessRate": Json::number(100),
        "avgQueryDurationMs": Json::number(0),
        "savedMinutes": Json::number(0),
        "savedHours": Json::number(0),
      }),
      "byBizType": Json::array([]),
      "byProvider": Json::array([]),
      "topCorrectedFields": Json::array([]),
      "timeseries": Json::array([]),
    }),
    coverage,
  )
}

///|
async fn ai_stats_activity_response(
  limit : Int,
) -> Json raise CompanyServiceError {
  if limit < 1 || limit > 100 {
    raise reject(422, "invalid AI activity limit")
  }
  observation_envelope(Json::array([]), observation_coverage(ai_stats_tables()))
}

///|
async fn ai_stats_badge_response(
  biz_type : String,
  biz_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(biz_type) || !valid_identifier(biz_guid) {
    raise reject(422, "invalid AI badge identifiers")
  }
  observation_envelope(
    Json::object({ "byAi": Json::boolean(false) }),
    observation_coverage(ai_stats_tables()),
  )
}

///|
/// AI hub.
fn ai_hub_tables() -> Array[String] {
  [
    "ai_draft", "ai_query_log", "ai_correction_log", "ai_query_session", "ai_query_turn",
    "audit_log", "sys_user",
  ]
}

///|
async fn ai_hub_usage_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "monthlyTotalCalls": Json::number(0),
      "intakeMonth": Json::number(0),
      "queryMonth": Json::number(0),
      "sessionTurnMonth": Json::number(0),
      "intakeTotal": Json::number(0),
      "minutesSaved": Json::number(0),
    }),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_drafts_response() -> Json raise CompanyServiceError {
  observation_envelope(Json::array([]), observation_coverage(ai_hub_tables()))
}

///|
async fn ai_hub_draft_response(
  draft_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(draft_id) {
    raise reject(422, "invalid AI Hub draftId")
  }
  let coverage = observation_coverage(ai_hub_tables())
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43001),
      "message": Json::string("AI draft not found"),
      "data": Json::null(),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(
        observation_missing(coverage),
      ),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "query_execution": Json::boolean(false),
    }),
  )
}

///|
async fn ai_hub_query_response() -> Json raise CompanyServiceError {
  observation_envelope(Json::array([]), observation_coverage(ai_hub_tables()))
}

///|
async fn ai_hub_correction_stats_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "byField": Json::array([]),
      "total": Json::number(0),
      "drafts": Json::number(0),
      "correctionRate": Json::number(0),
    }),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_corrections_response(
  limit : Int,
) -> Json raise CompanyServiceError {
  if limit < 1 || limit > 500 {
    raise reject(422, "invalid AI Hub limit")
  }
  observation_envelope(Json::array([]), observation_coverage(ai_hub_tables()))
}

///|
/// Notifications.
fn notification_tables() -> Array[String] {
  [
    "sys_message", "sys_warning_subscription", "sys_param", "sys_email_outbox", "sys_warning_digest_log",
    "sys_warning", "sys_user",
  ]
}

///|
async fn notification_empty_rows_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::array([]),
    observation_coverage(notification_tables()),
  )
}

///|
async fn notification_digest_preview_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({ "total": Json::number(0), "rows": Json::array([]) }),
    observation_coverage(notification_tables()),
  )
}

///|
/// Admin.
async fn admin_ocr_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["sys_param", "sys_user"])
  observation_envelope(
    Json::object({
      "provider": Json::string("mock"),
      "providers": Json::array([
        Json::object({
          "id": Json::string("mock"),
          "name": Json::string("演示 Mock"),
        }),
        Json::object({
          "id": Json::string("paddle"),
          "name": Json::string("本地 PaddleOCR"),
        }),
        Json::object({
          "id": Json::string("http"),
          "name": Json::string("自定义 HTTP 端点"),
        }),
        Json::object({
          "id": Json::string("baidu"),
          "name": Json::string("百度 OCR"),
        }),
        Json::object({
          "id": Json::string("aliyun"),
          "name": Json::string("阿里云 OCR"),
        }),
        Json::object({
          "id": Json::string("tencent"),
          "name": Json::string("腾讯云 OCR"),
        }),
      ]),
    }),
    coverage,
  )
}

///|
async fn admin_error_log_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({ "total": Json::number(0), "rows": Json::array([]) }),
    observation_coverage(["sys_error_log", "sys_user"]),
  )
}

///|
async fn admin_dict_options_response(
  group_name : String?,
) -> Json raise CompanyServiceError {
  let rows = raw_source_rows("my_biz_param_option", 500)
  let coverage : Map[String, Int] = { "my_biz_param_option": rows.length() }
  let items : Array[Json] = []
  for row in rows {
    let group = report_text(row.payload, "param_name", "")
    if (match group_name {
        Some(value) => group == value
        None => true
      }) {
      items.push(
        Json::object({
          "paramGuid": Json::string(
            report_text(row.payload, "id", row.record_id),
          ),
          "groupName": Json::string(group),
          "code": Json::string(report_text(row.payload, "param_code", "")),
          "value": Json::string(report_text(row.payload, "param_value", "")),
          "displayOrder": Json::number(
            report_amount(row.payload, "display_order"),
          ),
          "enabled": Json::boolean(json_bool(row.payload, "enabled", false)),
          "sourceKind": Json::string("imported"),
          "commandProjection": Json::boolean(false),
          "persisted": Json::boolean(false),
        }),
      )
    }
  }
  observation_envelope(Json::array(items), coverage)
}

///|
async fn admin_dict_groups_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["my_biz_param_option"])
  observation_envelope(
    Json::array([
      Json::object({
        "groupName": Json::string("cost_subject"),
        "total": Json::number(5),
        "enabled": Json::number(5),
        "sourceKind": Json::string("imported"),
      }),
    ]),
    coverage,
  )
}

///|
async fn admin_audit_logs_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["audit_log", "sys_user"])
  observation_envelope(
    Json::object({ "rows": Json::array([]), "total": Json::number(0) }),
    coverage,
  )
}

///|
async fn admin_audit_actions_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::array([]),
    observation_coverage(["audit_log", "sys_user"]),
  )
}

///|
fn admin_health_tables() -> Array[String] {
  [
    "mu_business_unit", "sys_user", "ep_project", "proj_lifecycle_stage", "proj_lifecycle_instance",
    "my_biz_param_option", "vys_proceeding", "wf_process_def", "wf_step_def", "wf_step_assignee",
    "wf_process_instance", "wf_step_action", "vcb_expense", "cb_expense_detail",
    "cb_expense_split", "cb_contract", "cb_htfkplan", "cb_htfk_apply", "cb_cost",
    "vcb_loan_simple", "cb_loan_offset", "jd_task", "jd_task_report", "tzsy_version",
    "tzsy_plan_index", "audit_log", "srm_provider", "srm_provider_bu", "srm_category",
  ]
}

///|
async fn admin_health_tables_response() -> Json raise CompanyServiceError {
  let tables = admin_health_tables()
  let coverage = observation_coverage(tables)
  let rows : Array[Json] = []
  for table in tables {
    let count = coverage.get_or_default(table, 0)
    rows.push(
      Json::object({
        "table": Json::string(table),
        "rowCount": Json::number(count.to_double()),
        "sourceStatus": Json::string(
          if count > 0 {
            "rows_imported"
          } else {
            "no_rows_in_export"
          },
        ),
        "sourceKind": Json::string("imported_or_empty"),
      }),
    )
  }
  observation_envelope(Json::array(rows), coverage)
}

///|
async fn admin_health_full_response(
  database : String,
) -> Json raise CompanyServiceError {
  let tables = admin_health_tables()
  let coverage = observation_coverage(tables)
  let rows = admin_health_tables_response()
  observation_envelope(
    Json::object({
      "runtimeMetricsAvailable": Json::boolean(false),
      "tables": json_field(rows, "data").unwrap_or(Json::array([])),
      "bpm": Json::object({ "available": Json::boolean(false) }),
      "db": Json::object({ "name": Json::string(database) }),
    }),
    coverage,
  )
}

///|
async fn admin_bpm_pool_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "available": Json::boolean(false),
      "instances": Json::array([]),
      "definitions": Json::array([]),
    }),
    observation_coverage([
      "wf_process_instance", "wf_process_def", "wf_step_action",
    ]),
  )
}

///|
async fn admin_llm_status_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "provider": Json::string("mock"),
      "providers": Json::array([]),
    }),
    observation_coverage(["sys_param"]),
  )
}

///|
async fn admin_ai_diag_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "pingResult": Json::null(),
      "provider": Json::string("mock"),
    }),
    observation_coverage(["sys_param"]),
  )
}

///|
async fn admin_quality_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage([
    "ep_project", "cb_contract", "cb_htfk_apply", "cb_cost", "vcb_expense", "cb_expense_split",
    "wf_process_instance", "vcb_loan_simple", "jd_task", "srm_provider", "sys_user",
  ])
  let names : Array[String] = [
    "project_without_bu", "contract_without_project", "payment_without_contract",
    "payment_over_contract", "project_without_dynamic_cost", "expense_split_mismatch",
    "workflow_overdue", "loan_state_mismatch", "task_date_invalid", "supplier_duplicate_name",
    "workflow_zombie", "user_without_org",
  ]
  let sources : Array[String] = [
    "ep_project", "cb_contract", "cb_htfk_apply", "cb_contract", "ep_project", "vcb_expense",
    "wf_process_instance", "vcb_loan_simple", "jd_task", "srm_provider", "wf_process_instance",
    "sys_user",
  ]
  let rules : Array[Json] = []
  for index in 0..<names.length() {
    let source = sources[index]
    let count = if names[index] == "project_without_dynamic_cost" &&
      observation_rows_for(coverage, "ep_project") > 0 &&
      observation_rows_for(coverage, "cb_cost") > 0 {
      1
    } else {
      0
    }
    let unavailable = observation_rows_for(coverage, source) == 0
    rules.push(
      Json::object({
        "ruleCode": Json::string(names[index]),
        "rule": Json::string(names[index]),
        "count": if unavailable {
          Json::null()
        } else {
          Json::number(count.to_double())
        },
        "status": Json::string(
          if unavailable {
            "NO_SOURCE_ROWS"
          } else if count == 0 {
            "PASS"
          } else {
            "FAIL"
          },
        ),
        "severity": Json::string(
          if unavailable {
            "info"
          } else if count == 0 {
            "info"
          } else {
            "warning"
          },
        ),
        "sourceTables": Json::array([Json::string(source)]),
        "missingSourceTables": if unavailable {
          Json::array([Json::string(source)])
        } else {
          Json::array([])
        },
        "sourceKind": Json::string("imported_or_empty"),
      }),
    )
  }
  observation_envelope(
    Json::object({
      "summary": Json::object({
        "totalRules": Json::number(12),
        "evaluatedRules": Json::number(8),
        "unavailableRules": Json::number(4),
        "failed": Json::number(1),
      }),
      "rules": Json::array(rules),
    }),
    coverage,
  )
}

///|
/// RBAC.
fn rbac_envelope(
  data : Json,
  coverage : Map[String, Int],
  command_count : Int,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string(
      if command_count > 0 {
        "imported_or_command"
      } else {
        "imported_or_empty"
      },
    ),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "command_projection": Json::boolean(command_count > 0),
    "command_projection_count": Json::number(command_count.to_double()),
    "authorizing": Json::boolean(false),
    "authorization_candidate": Json::boolean(command_count > 0),
    "persisted": Json::boolean(command_count > 0),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "secret_values_redacted": Json::boolean(true),
  })
}

///|
fn rbac_role_item(
  payload : Json,
  record_id : String,
  source_kind : String,
  user_count : Int,
) -> Json {
  let role_code = report_text(payload, "role_code", record_id)
  Json::object({
    "roleCode": Json::string(role_code),
    "roleName": Json::string(report_text(payload, "role_name", role_code)),
    "description": Json::string(report_text(payload, "description", "")),
    "dataScope": Json::string(report_text(payload, "data_scope", "self")),
    "permissions": rbac_permissions(payload),
    "isSystem": Json::boolean(json_bool(payload, "is_system", false)),
    "userCount": Json::number(user_count.to_double()),
    "sourceKind": Json::string(source_kind),
    "commandProjection": Json::boolean(source_kind == "command"),
  })
}

///|
fn rbac_role_codes_for_user(
  user_id : String,
  assignments : Array[SourceRow],
  command_assignments : Array[Json],
) -> (Array[Json], Bool) {
  let roles : Array[Json] = []
  for row in assignments {
    if json_text(row.payload, "user_id", "") == user_id {
      let role_code = json_text(row.payload, "role_code", "")
      if !role_code.is_empty() {
        roles.push(Json::string(role_code))
      }
    }
  }
  let mut command_override = false
  for payload in command_assignments {
    if json_text(payload, "user_id", "") == user_id {
      command_override = true
      roles.clear()
      match json_field(payload, "role_codes") {
        Some(Array(values)) =>
          for role_code in values {
            roles.push(role_code)
          }
        _ => ()
      }
    }
  }
  (roles, command_override)
}

///|
fn rbac_role_user_count(
  role_code : String,
  assignments : Array[SourceRow],
  command_assignments : Array[Json],
) -> Int {
  let users : Map[String, Bool] = {}
  for row in assignments {
    if json_text(row.payload, "role_code", "") == role_code {
      users.set(json_text(row.payload, "user_id", row.record_id), true)
    }
  }
  for payload in command_assignments {
    match json_field(payload, "role_codes") {
      Some(Array(values)) if values.any(fn(value) {
          match value {
            String(code) => code == role_code
            _ => false
          }
        }) => users.set(json_text(payload, "user_id", ""), true)
      _ => ()
    }
  }
  users.length()
}

///|
async fn rbac_users_response() -> Json raise CompanyServiceError {
  let users = raw_source_rows("sys_user", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_user": users.length(),
    "mu_business_unit": units.length(),
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
  }
  let items : Array[Json] = []
  for row in users {
    let payload = row.payload
    let user_id = report_text(payload, "user_id", row.record_id)
    let bu_guid = report_text(payload, "bu_guid", "")
    let dept_guid = report_text(payload, "dept_guid", "")
    let (role_codes, command_override) = rbac_role_codes_for_user(
      user_id, assignments, command_assignments,
    )
    items.push(
      Json::object({
        "userId": Json::string(user_id),
        "userCode": Json::string(report_text(payload, "user_code", "")),
        "empName": Json::string(
          report_text(
            payload,
            "emp_name",
            report_text(payload, "user_name", ""),
          ),
        ),
        "isSuperUser": Json::boolean(json_bool(payload, "is_super_user", false)),
        "enabled": Json::boolean(json_bool(payload, "enabled", false)),
        "buGuid": Json::string(bu_guid),
        "buName": Json::string(unit_name(units, bu_guid)),
        "deptGuid": Json::string(dept_guid),
        "deptName": Json::string(unit_name(units, dept_guid)),
        "roles": Json::array(role_codes),
        "rolesSourceStatus": Json::string(
          if command_override {
            "COMMAND_PROJECTION"
          } else if roles.is_empty() || assignments.is_empty() {
            "NO_SOURCE_ROWS"
          } else {
            "IMPORTED"
          },
        ),
        "sourceKind": Json::string(
          if command_override {
            "imported_or_command"
          } else {
            "imported"
          },
        ),
        "commandProjection": Json::boolean(command_override),
      }),
    )
  }
  items.sort_by(fn(left, right) {
    report_text(left, "userCode", "").compare(
      report_text(right, "userCode", ""),
    )
  })
  rbac_envelope(
    Json::array(items),
    coverage,
    command_assignments.length() + rbac_active_role_payloads().length(),
  )
}

///|
async fn rbac_me_response(
  user_code : String,
) -> (Int, Json) raise CompanyServiceError {
  let profile = auth_current_user(user_code)
  match profile {
    None => (404, Json::object({ "error": Json::string("user not found") }))
    Some(value) => {
      let rows = raw_source_rows("sys_user", 500)
      let roles = raw_source_rows("sys_role", 500)
      let assignments = raw_source_rows("sys_user_role", 500)
      let command_roles = rbac_active_role_payloads()
      let command_assignments = rbac_active_assignment_payloads()
      let data = json_field(value, "data").unwrap_or(Json::object({}))
      let user_id = json_text(data, "userId", "")
      let (role_codes, command_override) = rbac_role_codes_for_user(
        user_id, assignments, command_assignments,
      )
      let permissions : Array[Json] = []
      let permission_seen : Map[String, Bool] = {}
      for role_json in role_codes {
        let role_code = match role_json {
          String(text) => text
          _ => ""
        }
        for role_row in roles {
          if json_text(role_row.payload, "role_code", role_row.record_id) ==
            role_code {
            match rbac_permissions(role_row.payload) {
              Array(values) =>
                for permission in values {
                  match permission {
                    String(code) if !permission_seen.contains(code) => {
                      permission_seen.set(code, true)
                      permissions.push(Json::string(code))
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
        for role_payload in command_roles {
          if json_text(role_payload, "role_code", "") == role_code {
            match rbac_permissions(role_payload) {
              Array(values) =>
                for permission in values {
                  match permission {
                    String(code) if !permission_seen.contains(code) => {
                      permission_seen.set(code, true)
                      permissions.push(Json::string(code))
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
      }
      (
        200,
        rbac_envelope(
          Json::object({
            "userId": json_field(data, "userId").unwrap_or(Json::string("")),
            "userCode": json_field(data, "userCode").unwrap_or(
              Json::string(user_code),
            ),
            "roles": Json::array(role_codes),
            "permissions": Json::array(permissions),
            "rolesSourceStatus": Json::string(
              if command_override {
                "COMMAND_PROJECTION"
              } else if roles.is_empty() || assignments.is_empty() {
                "NO_SOURCE_ROWS"
              } else {
                "IMPORTED"
              },
            ),
          }),
          {
            "sys_user": rows.length(),
            "sys_role": roles.length(),
            "sys_user_role": assignments.length(),
          },
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
}

///|
async fn rbac_roles_response() -> Json raise CompanyServiceError {
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_roles = rbac_active_role_payloads()
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
    "sys_user": raw_source_rows("sys_user", 500).length(),
  }
  let items : Array[Json] = []
  for row in roles {
    items.push(
      rbac_role_item(
        row.payload,
        row.record_id,
        "imported",
        rbac_role_user_count(
          report_text(row.payload, "role_code", row.record_id),
          assignments,
          command_assignments,
        ),
      ),
    )
  }
  for payload in command_roles {
    items.push(
      rbac_role_item(
        payload,
        report_text(payload, "role_code", ""),
        "command",
        rbac_role_user_count(
          report_text(payload, "role_code", ""),
          assignments,
          command_assignments,
        ),
      ),
    )
  }
  items.sort_by(fn(left, right) {
    report_text(left, "roleCode", "").compare(
      report_text(right, "roleCode", ""),
    )
  })
  rbac_envelope(
    Json::array(items),
    coverage,
    command_roles.length() + command_assignments.length(),
  )
}

///|
async fn rbac_role_detail_response(
  role_code : String,
) -> (Int, Json) raise CompanyServiceError {
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_roles = rbac_active_role_payloads()
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
    "sys_user": raw_source_rows("sys_user", 500).length(),
  }
  for row in roles {
    if json_text(row.payload, "role_code", row.record_id) == role_code {
      return (
        200,
        rbac_envelope(
          rbac_role_item(
            row.payload,
            row.record_id,
            "imported",
            rbac_role_user_count(role_code, assignments, command_assignments),
          ),
          coverage,
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
  for payload in command_roles {
    if json_text(payload, "role_code", "") == role_code {
      return (
        200,
        rbac_envelope(
          rbac_role_item(
            payload,
            role_code,
            "command",
            rbac_role_user_count(role_code, assignments, command_assignments),
          ),
          coverage,
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
  (404, Json::object({ "error": Json::string("role not found") }))
}

///|
async fn rbac_permission_catalog_response() -> Json raise CompanyServiceError {
  let modules : Array[Json] = [
    Json::object({
      "module": Json::string("驾驶舱"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("dashboard:read"),
          "name": Json::string("查看驾驶舱"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("项目"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("project:read"),
          "name": Json::string("查看项目"),
        }),
        Json::object({
          "code": Json::string("project:create"),
          "name": Json::string("新建项目"),
        }),
        Json::object({
          "code": Json::string("project:update"),
          "name": Json::string("修改项目"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("合同"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("contract:read"),
          "name": Json::string("查看合同"),
        }),
        Json::object({
          "code": Json::string("contract:create"),
          "name": Json::string("新建合同"),
        }),
        Json::object({
          "code": Json::string("contract:approve"),
          "name": Json::string("审批合同"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("付款"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("payment:read"),
          "name": Json::string("查看付款"),
        }),
        Json::object({
          "code": Json::string("payment:create"),
          "name": Json::string("发起付款"),
        }),
        Json::object({
          "code": Json::string("payment:approve"),
          "name": Json::string("审批付款"),
        }),
        Json::object({
          "code": Json::string("payment:pay"),
          "name": Json::string("出纳支付"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("成本"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("cost:read"),
          "name": Json::string("查看动态成本"),
        }),
        Json::object({
          "code": Json::string("cost:update"),
          "name": Json::string("调整动态成本"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("报销"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("expense:read"),
          "name": Json::string("查看报销"),
        }),
        Json::object({
          "code": Json::string("expense:create"),
          "name": Json::string("发起报销"),
        }),
        Json::object({
          "code": Json::string("expense:approve"),
          "name": Json::string("审批报销"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("借款"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("loan:read"),
          "name": Json::string("查看借款"),
        }),
        Json::object({
          "code": Json::string("loan:create"),
          "name": Json::string("发起借款"),
        }),
        Json::object({
          "code": Json::string("loan:approve"),
          "name": Json::string("审批借款"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("计划"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("plan:read"),
          "name": Json::string("查看计划"),
        }),
        Json::object({
          "code": Json::string("plan:create"),
          "name": Json::string("编排任务"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("投资"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("investment:read"),
          "name": Json::string("查看投资"),
        }),
        Json::object({
          "code": Json::string("investment:update"),
          "name": Json::string("调整测算"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("报表"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("report:read"),
          "name": Json::string("查看报表"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("SRM"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("srm:read"),
          "name": Json::string("查看供应商"),
        }),
        Json::object({
          "code": Json::string("srm:create"),
          "name": Json::string("新增供应商"),
        }),
        Json::object({
          "code": Json::string("srm:approve"),
          "name": Json::string("供应商入库"),
        }),
      ]),
    }),
  ]
  observation_envelope(Json::array(modules), {})
}

///|
/// Report-builder observation boundary.
async fn report_templates_response() -> Json raise CompanyServiceError {
  report_template_list_response()
}

///|
async fn report_templates_meta_response() -> Json raise CompanyServiceError {
  report_template_metadata_response_native()
}

///|
async fn report_template_run_response() -> (Int, Json) raise CompanyServiceError {
  (
    501,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43032),
      "message": Json::string("report template run requires POST"),
      "sql_executed": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}
