///|
/// Native source-backed dashboard and cockpit reads.
///
/// This keeps the browser response shapes useful while making the source
/// boundary explicit. These reads are observations only: they do not
/// authorize, persist, or invoke providers.
struct DashboardContext {
  rows : Map[String, Array[SourceRow]]
  coverage : Map[String, Int]
  missing : Array[String]
}

///|
fn dashboard_tables() -> Array[String] {
  [
    "cb_contract", "cb_cost", "cb_expense_split", "cb_htfk_apply", "cb_htfkplan",
    "ep_project", "jd_task", "mu_business_unit", "proj_lifecycle_instance", "proj_lifecycle_stage",
    "tzsy_plan_index", "tzsy_version", "vcb_expense", "wf_process_instance", "cb_plan_version",
    "cb_r_master", "cb_subject_dict", "fund_plan", "invoice_in", "invoice_out", "proj_progress",
    "sale_contract", "sale_customer", "sale_mortgage", "sale_refund", "sale_revenue",
    "sale_subscription", "sys_warning", "tender_award", "tender_plan",
  ]
}

///|
async fn dashboard_context(
  max_rows : Int,
) -> DashboardContext raise CompanyServiceError {
  let rows : Map[String, Array[SourceRow]] = {}
  let coverage : Map[String, Int] = {}
  for table in dashboard_tables() {
    let values = raw_source_rows(table, max_rows)
    rows.set(table, values)
    coverage.set(table, values.length())
  }
  let missing : Array[String] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(table)
    }
  }
  missing.sort_by(fn(left, right) { left.compare(right) })
  { rows, coverage, missing }
}

///|
fn dashboard_rows(
  context : DashboardContext,
  table : String,
) -> Array[SourceRow] {
  context.rows.get_or_default(table, [])
}

///|
fn dashboard_active(payload : Json) -> Bool {
  report_text(payload, "deleted_at", "").is_empty() &&
  report_text(payload, "deletedAt", "").is_empty()
}

///|
fn dashboard_scoped(
  payload : Json,
  business_unit_id : String?,
  project_id : String?,
) -> Bool {
  let payload_project = report_text(payload, "proj_guid", "")
  let payload_bu = report_text(payload, "bu_guid", "")
  (match project_id {
    Some(value) => payload_project == value
    None => true
  }) &&
  (match business_unit_id {
    Some(value) => payload_bu == value
    None => true
  })
}

///|
fn dashboard_envelope(
  data : Json,
  context : DashboardContext,
  source_kind : String,
) -> Json {
  let missing : Array[Json] = context.missing.map(fn(value) {
    Json::string(value)
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string(source_kind),
    "source_coverage": report_coverage(context.coverage),
    "missing_source_tables": Json::array(missing),
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn dashboard_optional_json(value : String?) -> Json {
  match value {
    Some(item) => Json::string(item)
    None => Json::null()
  }
}

///|
async fn dashboard_group_overview_response() -> Json raise CompanyServiceError {
  let context = dashboard_context(500)
  let units = dashboard_rows(context, "mu_business_unit")
  let projects = dashboard_rows(context, "ep_project").filter(fn(row) {
    dashboard_active(row.payload)
  })
  let contracts = dashboard_rows(context, "cb_contract").filter(fn(row) {
    dashboard_active(row.payload)
  })
  let applications = dashboard_rows(context, "cb_htfk_apply").filter(fn(row) {
    dashboard_active(row.payload)
  })
  let costs = dashboard_rows(context, "cb_cost").filter(fn(row) {
    dashboard_active(row.payload) && report_is_end_cost(row.payload)
  })
  let running : Map[String, Bool] = {}
  for row in dashboard_rows(context, "proj_lifecycle_instance") {
    if report_text(row.payload, "status", "") == "in_progress" {
      running.set(report_text(row.payload, "proj_guid", row.record_id), true)
    }
  }
  let total_contract = contracts.fold(init=0.0, fn(sum, row) {
    sum +
    report_amount(row.payload, "ht_amount") +
    report_amount(row.payload, "sum_alter_amount")
  })
  let paid = applications.fold(init=0.0, fn(sum, row) {
    if ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      sum + report_amount(row.payload, "apply_amount")
    } else {
      sum
    }
  })
  let target = costs.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "target_cost")
  })
  let dynamic = costs.fold(init=0.0, fn(sum, row) {
    sum +
    report_amount(row.payload, "ht_alter_amount") +
    report_amount(row.payload, "zt_cost") +
    report_amount(row.payload, "dfs_budget") +
    report_amount(row.payload, "yg_alter")
  })
  let company_count = units
    .filter(fn(row) { report_text(row.payload, "bu_type", "") == "company" })
    .length()
  let deviation = if target == 0.0 {
    0.0
  } else {
    round_places((target - dynamic) / target * 100.0, 2)
  }
  dashboard_envelope(
    Json::object({
      "companyCount": Json::number(company_count.to_double()),
      "projectCount": Json::number(projects.length().to_double()),
      "inProgressCount": Json::number(running.length().to_double()),
      "contractCount": Json::number(contracts.length().to_double()),
      "totalContractAmount": Json::number(total_contract),
      "paidAmount": Json::number(paid),
      "paidRatio": Json::number(
        if total_contract == 0.0 {
          0.0
        } else {
          round_places(paid / total_contract * 100.0, 2)
        },
      ),
      "cost": Json::object({
        "target": Json::number(target),
        "dynamic": Json::number(dynamic),
        "deviationPct": Json::number(deviation),
      }),
      "anomalies": Json::object({
        "overdueApprovals": Json::number(0),
        "overdueTasks": Json::number(
          dashboard_rows(context, "jd_task")
          .filter(fn(row) {
            report_text(row.payload, "status", "") == "overdue"
          })
          .length()
          .to_double(),
        ),
      }),
    }),
    context,
    "imported",
  )
}

///|
async fn dashboard_group_funnel_response() -> Json raise CompanyServiceError {
  let context = dashboard_context(500)
  let stages = dashboard_rows(context, "proj_lifecycle_stage")
  stages.sort_by(fn(left, right) {
    report_amount(left.payload, "stage_order").compare(
      report_amount(right.payload, "stage_order"),
    )
  })
  let grouped : Map[String, Map[String, Bool]] = {}
  for row in dashboard_rows(context, "proj_lifecycle_instance") {
    let status = report_text(row.payload, "status", "")
    if ["in_progress", "done"].contains(status) {
      let stage = report_text(row.payload, "stage_code", "")
      let projects = grouped.get_or_default(stage, {})
      projects.set(report_text(row.payload, "proj_guid", ""), true)
      grouped.set(stage, projects)
    }
  }
  let max_count = grouped
    .values()
    .fold(init=0, fn(current, values) {
      if values.length() > current {
        values.length()
      } else {
        current
      }
    })
  let data : Array[Json] = []
  for row in stages {
    let code = report_text(row.payload, "stage_code", "")
    let count = grouped.get_or_default(code, {}).length()
    data.push(
      Json::object({
        "stageCode": Json::string(code),
        "stageName": Json::string(report_text(row.payload, "stage_name", code)),
        "count": Json::number(count.to_double()),
        "widthPct": Json::string(
          if max_count == 0 {
            "0%"
          } else {
            (count.to_double() / max_count.to_double() * 100.0)
            .to_int()
            .to_string() +
            "%"
          },
        ),
      }),
    )
  }
  dashboard_envelope(Json::array(data), context, "imported")
}

///|
async fn dashboard_group_anomalies_response(
  limit : Int,
) -> Json raise CompanyServiceError {
  if limit < 1 || limit > 30 {
    raise reject(422, "limit must be between 1 and 30")
  }
  let context = dashboard_context(500)
  let units = dashboard_rows(context, "mu_business_unit")
  let projects = dashboard_rows(context, "ep_project")
  let costs = dashboard_rows(context, "cb_cost")
  let tasks = dashboard_rows(context, "jd_task")
  let ranked : Array[Json] = []
  for project in projects {
    if !dashboard_active(project.payload) {
      continue
    }
    let project_id = report_text(
      project.payload,
      "proj_guid",
      project.record_id,
    )
    let project_costs = costs.filter(fn(row) {
      report_is_end_cost(row.payload) &&
      report_text(row.payload, "proj_guid", "") == project_id
    })
    let target = project_costs.fold(init=0.0, fn(sum, row) {
      sum + report_amount(row.payload, "target_cost")
    })
    let dynamic = project_costs.fold(init=0.0, fn(sum, row) {
      sum +
      report_amount(row.payload, "ht_alter_amount") +
      report_amount(row.payload, "zt_cost") +
      report_amount(row.payload, "dfs_budget") +
      report_amount(row.payload, "yg_alter")
    })
    let deviation = if target == 0.0 {
      0.0
    } else {
      (target - dynamic) / target * 100.0
    }
    let overdue = tasks
      .filter(fn(row) {
        report_text(row.payload, "proj_guid", "") == project_id &&
        report_text(row.payload, "status", "") == "overdue"
      })
      .length()
    let risk = (if deviation < 0.0 { -deviation * 10.0 } else { 0.0 }) +
      overdue.to_double() * 20.0
    let reason = if deviation < 0.0 {
      "成本超目标 " + round_places(-deviation, 2).to_string() + "%"
    } else if overdue > 0 {
      overdue.to_string() + " 个任务延期"
    } else {
      "正常"
    }
    let bu_id = report_text(project.payload, "bu_guid", "")
    ranked.push(
      Json::object({
        "projGuid": Json::string(project_id),
        "projCode": Json::string(
          report_text(project.payload, "proj_code", project_id),
        ),
        "projName": Json::string(
          report_text(project.payload, "proj_name", project_id),
        ),
        "buName": Json::string(unit_name(units, bu_id)),
        "projStatus": Json::string(
          report_text(project.payload, "proj_status", ""),
        ),
        "targetCost": Json::number(target),
        "dynamicCost": Json::number(dynamic),
        "deviationPct": Json::number(round_places(deviation, 2)),
        "overdueTasks": Json::number(overdue.to_double()),
        "inProgressNodes": Json::number(0),
        "riskScore": Json::number(risk),
        "reason": Json::string(reason),
      }),
    )
  }
  ranked.sort_by(fn(left, right) {
    report_amount(right, "riskScore").compare(report_amount(left, "riskScore"))
  })
  let bounded_count = if limit < ranked.length() {
    limit
  } else {
    ranked.length()
  }
  let bounded = ranked[:bounded_count].to_owned()
  dashboard_envelope(Json::array(bounded), context, "imported")
}

///|
async fn dashboard_project_kpi_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let context = dashboard_context(500)
  let projects = dashboard_rows(context, "ep_project").filter(fn(row) {
    report_text(row.payload, "proj_guid", row.record_id) == project_id &&
    dashboard_active(row.payload)
  })
  if projects.is_empty() {
    return (404, Json::object({ "error": Json::string("project not found") }))
  }
  let project = projects[0]
  let tasks = dashboard_rows(context, "jd_task").filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    report_text(row.payload, "task_type", "") == "key_node"
  })
  let costs = dashboard_rows(context, "cb_cost").filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    report_is_end_cost(row.payload)
  })
  let contracts = dashboard_rows(context, "cb_contract").filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id
  })
  let applications = dashboard_rows(context, "cb_htfk_apply").filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id
  })
  let target = costs.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "target_cost")
  })
  let dynamic = costs.fold(init=0.0, fn(sum, row) {
    sum +
    report_amount(row.payload, "ht_alter_amount") +
    report_amount(row.payload, "zt_cost") +
    report_amount(row.payload, "dfs_budget") +
    report_amount(row.payload, "yg_alter")
  })
  let apply_total = applications.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "apply_amount")
  })
  let paid = applications.fold(init=0.0, fn(sum, row) {
    if ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      sum + report_amount(row.payload, "apply_amount")
    } else {
      sum
    }
  })
  let bu_id = report_text(project.payload, "bu_guid", "")
  let data = Json::object({
    "project": Json::object({
      "projGuid": Json::string(project_id),
      "projCode": Json::string(
        report_text(project.payload, "proj_code", project_id),
      ),
      "projName": Json::string(
        report_text(project.payload, "proj_name", project_id),
      ),
      "buName": Json::string(
        unit_name(dashboard_rows(context, "mu_business_unit"), bu_id),
      ),
      "projStatus": Json::string(
        report_text(project.payload, "proj_status", ""),
      ),
    }),
    "kpi": Json::object({
      "progress": Json::object({
        "avgProgress": Json::number(0),
        "totalNodes": Json::number(tasks.length().to_double()),
        "overdueNodes": Json::number(0),
        "done": Json::number(
          tasks
          .filter(fn(row) { report_text(row.payload, "status", "") == "done" })
          .length()
          .to_double(),
        ),
        "inProgress": Json::number(
          tasks
          .filter(fn(row) {
            report_text(row.payload, "status", "") == "in_progress"
          })
          .length()
          .to_double(),
        ),
      }),
      "cost": Json::object({
        "target": Json::number(target),
        "dynamic": Json::number(dynamic),
        "deviationPct": Json::number(
          if target == 0.0 {
            0.0
          } else {
            round_places((target - dynamic) / target * 100.0, 2)
          },
        ),
        "layoutSpare": Json::number(target - dynamic),
      }),
      "contract": Json::object({
        "count": Json::number(contracts.length().to_double()),
        "totalAmount": Json::number(
          contracts.fold(init=0.0, fn(sum, row) {
            sum +
            report_amount(row.payload, "ht_amount") +
            report_amount(row.payload, "sum_alter_amount")
          }),
        ),
      }),
      "payment": Json::object({
        "count": Json::number(applications.length().to_double()),
        "applyTotal": Json::number(apply_total),
        "paidTotal": Json::number(paid),
        "paidRatio": Json::number(
          if apply_total == 0.0 {
            0.0
          } else {
            round_places(paid / apply_total * 100.0, 2)
          },
        ),
      }),
      "cash": Json::object({ "thisMonthPlan": Json::number(0) }),
      "profit": Json::null(),
      "quality": Json::null(),
      "approval": Json::object({
        "avgDays": Json::null(),
        "overdueCount": Json::number(0),
      }),
    }),
  })
  (200, dashboard_envelope(data, context, "imported"))
}

///|
async fn dashboard_project_anomalies_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let context = dashboard_context(500)
  let projects = dashboard_rows(context, "ep_project").filter(fn(row) {
    report_text(row.payload, "proj_guid", row.record_id) == project_id &&
    dashboard_active(row.payload)
  })
  if projects.is_empty() {
    return (200, dashboard_envelope(Json::array([]), context, "imported"))
  }
  let costs = dashboard_rows(context, "cb_cost").filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    report_is_end_cost(row.payload)
  })
  let target = costs.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "target_cost")
  })
  let dynamic = costs.fold(init=0.0, fn(sum, row) {
    sum +
    report_amount(row.payload, "ht_alter_amount") +
    report_amount(row.payload, "zt_cost") +
    report_amount(row.payload, "dfs_budget") +
    report_amount(row.payload, "yg_alter")
  })
  let deviation = if target == 0.0 {
    0.0
  } else {
    (target - dynamic) / target * 100.0
  }
  let anomalies : Array[Json] = []
  if deviation < -1.0 {
    anomalies.push(
      Json::object({
        "severity": Json::string(
          if deviation < -5.0 {
            "error"
          } else {
            "warning"
          },
        ),
        "title": Json::string(
          "成本超目标 " + round_places(-deviation, 2).to_string() + "%",
        ),
        "detail": Json::string(
          "目标 ¥" + target.to_string() + " 动态 ¥" + dynamic.to_string(),
        ),
        "suggestion": Json::string(
          "建议立即组织成本分析会,识别超支科目并制定纠偏措施",
        ),
      }),
    )
  }
  (200, dashboard_envelope(Json::array(anomalies), context, "imported"))
}

///|
async fn dashboard_v2_response(
  business_unit_id : String?,
  project_id : String?,
) -> Json raise CompanyServiceError {
  if business_unit_id is Some(value) && !valid_identifier(value) {
    raise reject(422, "invalid buGuid")
  }
  if project_id is Some(value) && !valid_identifier(value) {
    raise reject(422, "invalid projGuid")
  }
  let context = dashboard_context(500)
  let projects = dashboard_rows(context, "ep_project").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let project_ids : Map[String, Bool] = {}
  for row in projects {
    project_ids.set(report_text(row.payload, "proj_guid", row.record_id), true)
  }
  let contracts = dashboard_rows(context, "cb_contract").filter(fn(row) {
    dashboard_active(row.payload) &&
    project_ids.contains(report_text(row.payload, "proj_guid", ""))
  })
  let contract_ids : Map[String, Bool] = {}
  for row in contracts {
    contract_ids.set(
      report_text(row.payload, "contract_guid", row.record_id),
      true,
    )
  }
  let applications = dashboard_rows(context, "cb_htfk_apply").filter(fn(row) {
    dashboard_active(row.payload) &&
    project_ids.contains(report_text(row.payload, "proj_guid", ""))
  })
  let plans = dashboard_rows(context, "cb_htfkplan").filter(fn(row) {
    dashboard_active(row.payload) &&
    contract_ids.contains(report_text(row.payload, "contract_guid", ""))
  })
  let warnings = dashboard_rows(context, "sys_warning").filter(fn(row) {
    dashboard_active(row.payload) &&
    report_text(row.payload, "status", "") == "open" &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let running_processes = dashboard_rows(context, "wf_process_instance").filter(fn(
      row,
    ) {
      dashboard_active(row.payload) &&
      report_text(row.payload, "status", "") == "Running" &&
      dashboard_scoped(row.payload, business_unit_id, project_id)
    },
  )
  let contract_in_progress = contracts.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "js_state", "") != "已结算" {
      sum +
      report_amount(row.payload, "ht_amount") +
      report_amount(row.payload, "sum_alter_amount")
    } else {
      sum
    }
  })
  let plan_by_month : Map[String, Double] = {}
  for row in plans {
    let month = cashflow_month(row.payload, "jhfk_date")
    plan_by_month.set(
      month,
      plan_by_month.get_or_default(month, 0.0) +
      report_amount(row.payload, "jhfk_amount"),
    )
  }
  let actual_by_month : Map[String, Double] = {}
  for row in applications {
    if report_text(row.payload, "apply_state", "") == "已审核" {
      let month = cashflow_month(row.payload, "apply_date")
      actual_by_month.set(
        month,
        actual_by_month.get_or_default(month, 0.0) +
        report_amount(row.payload, "apply_amount"),
      )
    }
  }
  let months = cashflow_months(10, -6)
  let trend : Array[Json] = []
  for month in months {
    trend.push(
      Json::object({
        "ym": Json::string(month),
        "plan": Json::number(plan_by_month.get_or_default(month, 0.0)),
        "actual": Json::number(actual_by_month.get_or_default(month, 0.0)),
      }),
    )
  }
  let stage_counts : Map[String, Int] = {}
  for row in projects {
    let stage = report_text(row.payload, "proj_status", "unknown")
    stage_counts.set(stage, stage_counts.get_or_default(stage, 0) + 1)
  }
  let stage_distribution : Array[Json] = []
  for stage, count in stage_counts {
    stage_distribution.push(
      Json::object({
        "stage": Json::string(stage),
        "count": Json::number(count.to_double()),
      }),
    )
  }
  stage_distribution.sort_by(fn(left, right) {
    json_text(left, "stage", "").lexical_compare(json_text(right, "stage", ""))
  })
  let latest_warnings : Array[Json] = []
  for row in warnings {
    latest_warnings.push(
      Json::object({
        "warningGuid": Json::string(
          report_text(row.payload, "warning_guid", row.record_id),
        ),
        "ruleCode": Json::string(report_text(row.payload, "rule_code", "")),
        "ruleName": Json::string(report_text(row.payload, "rule_name", "")),
        "severity": Json::string(report_text(row.payload, "severity", "")),
        "bizType": Json::string(report_text(row.payload, "biz_type", "")),
        "bizDataGuid": Json::string(
          report_text(row.payload, "biz_data_guid", ""),
        ),
        "title": Json::string(report_text(row.payload, "title", "")),
        "firstDetectedAt": Json::string(
          report_text(row.payload, "first_detected_at", ""),
        ),
      }),
    )
  }
  latest_warnings.sort_by(fn(left, right) {
    let left_severity = if json_text(left, "severity", "") == "error" {
      0
    } else {
      1
    }
    let right_severity = if json_text(right, "severity", "") == "error" {
      0
    } else {
      1
    }
    let order = left_severity - right_severity
    if order == 0 {
      json_text(left, "firstDetectedAt", "").lexical_compare(
        json_text(right, "firstDetectedAt", ""),
      )
    } else {
      order
    }
  })
  let unpaid_amount = applications.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "pay_state", "") == "未支付" &&
      report_text(row.payload, "apply_state", "") == "已审核" {
      sum + report_amount(row.payload, "apply_amount")
    } else {
      sum
    }
  })
  let in_progress_projects = projects
    .filter(fn(row) {
      ["planning", "development", "sales"].contains(
        report_text(row.payload, "proj_status", ""),
      )
    })
    .length()
  dashboard_envelope(
    Json::object({
      "scope": Json::object({
        "buGuid": dashboard_optional_json(business_unit_id),
        "projGuid": dashboard_optional_json(project_id),
      }),
      "kpi": Json::object({
        "projectCount": Json::number(projects.length().to_double()),
        "inProgressProjects": Json::number(in_progress_projects.to_double()),
        "contractInProgressAmount": Json::number(contract_in_progress),
        "unpaidAmount": Json::number(unpaid_amount),
        "openWarnings": Json::number(warnings.length().to_double()),
        "runningProcesses": Json::number(running_processes.length().to_double()),
      }),
      "paymentTrend": Json::array(trend),
      "stageDistribution": Json::array(stage_distribution),
      "latestWarnings": Json::array(
        if latest_warnings.length() > 5 {
          latest_warnings[0:5].to_owned()
        } else {
          latest_warnings
        },
      ),
    }),
    context,
    "imported_or_empty",
  )
}

///|
async fn dashboard_v3_response(
  business_unit_id : String?,
  project_id : String?,
) -> Json raise CompanyServiceError {
  if business_unit_id is Some(value) && !valid_identifier(value) {
    raise reject(422, "invalid buGuid")
  }
  if project_id is Some(value) && !valid_identifier(value) {
    raise reject(422, "invalid projGuid")
  }
  let context = dashboard_context(500)
  let projects = dashboard_rows(context, "ep_project").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let project_ids : Map[String, Bool] = {}
  for row in projects {
    project_ids.set(report_text(row.payload, "proj_guid", row.record_id), true)
  }
  let contracts = dashboard_rows(context, "cb_contract").filter(fn(row) {
    dashboard_active(row.payload) &&
    project_ids.contains(report_text(row.payload, "proj_guid", ""))
  })
  let contract_by_id : Map[String, Json] = {}
  for row in contracts {
    contract_by_id.set(
      report_text(row.payload, "contract_guid", row.record_id),
      row.payload,
    )
  }
  let applications = dashboard_rows(context, "cb_htfk_apply").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let expenses = dashboard_rows(context, "vcb_expense").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let sale_contracts = dashboard_rows(context, "sale_contract").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let sale_contract_ids : Map[String, Bool] = {}
  for row in sale_contracts {
    sale_contract_ids.set(
      report_text(row.payload, "scontract_guid", row.record_id),
      true,
    )
  }
  let sale_customers = dashboard_rows(context, "sale_customer").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let sale_subscriptions = dashboard_rows(context, "sale_subscription").filter(fn(
    row,
  ) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let sale_revenues = dashboard_rows(context, "sale_revenue").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let sale_mortgages = dashboard_rows(context, "sale_mortgage").filter(fn(row) {
    dashboard_active(row.payload) &&
    (
      sale_contract_ids.contains(report_text(row.payload, "scontract_guid", "")) ||
      (business_unit_id is None && project_id is None)
    )
  })
  let sale_refunds = dashboard_rows(context, "sale_refund").filter(fn(row) {
    dashboard_active(row.payload) &&
    (
      sale_contract_ids.contains(report_text(row.payload, "scontract_guid", "")) ||
      (business_unit_id is None && project_id is None)
    )
  })
  let fund_plans = dashboard_rows(context, "fund_plan").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let progress_rows = dashboard_rows(context, "proj_progress").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let invoice_in = dashboard_rows(context, "invoice_in").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let invoice_out = dashboard_rows(context, "invoice_out").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let tender_plans = dashboard_rows(context, "tender_plan").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let tender_ids : Map[String, Bool] = {}
  for row in tender_plans {
    tender_ids.set(report_text(row.payload, "tender_guid", row.record_id), true)
  }
  let tender_awards = dashboard_rows(context, "tender_award").filter(fn(row) {
    dashboard_active(row.payload) &&
    (
      tender_ids.contains(report_text(row.payload, "tender_guid", "")) ||
      (business_unit_id is None && project_id is None)
    )
  })
  let warnings = dashboard_rows(context, "sys_warning").filter(fn(row) {
    dashboard_active(row.payload) &&
    report_text(row.payload, "status", "") == "open" &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let processes = dashboard_rows(context, "wf_process_instance").filter(fn(
    row,
  ) {
    dashboard_active(row.payload) &&
    report_text(row.payload, "status", "") == "Running" &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let paid_contract_expense = applications.fold(init=0.0, fn(sum, row) {
    if ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      sum + report_amount(row.payload, "apply_amount")
    } else {
      sum
    }
  })
  let paid_expense = expenses.fold(init=0.0, fn(sum, row) {
    if ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      sum + report_amount(row.payload, "pay_amount")
    } else {
      sum
    }
  })
  let total_revenue = sale_revenues.fold(init=0.0, fn(sum, row) {
      if report_text(row.payload, "status", "") == "received" {
        sum + report_amount(row.payload, "amount")
      } else {
        sum
      }
    }) /
    10000.0
  let expected_revenue = sale_revenues.fold(init=0.0, fn(sum, row) {
      if report_text(row.payload, "status", "") == "expected" {
        sum + report_amount(row.payload, "amount")
      } else {
        sum
      }
    }) /
    10000.0
  let signed_contracts = contracts.filter(fn(row) {
    ["signed", "paid"].contains(report_text(row.payload, "cb_state", ""))
  })
  let approving_contracts = contracts.filter(fn(row) {
    report_text(row.payload, "cb_state", "") == "approving"
  })
  let unpaid_applications = applications.filter(fn(row) {
    report_text(row.payload, "apply_state", "") == "已审核" &&
    report_text(row.payload, "pay_state", "") == "未支付"
  })
  let r0_contracts = contracts.filter(fn(row) {
    ["", "R0"].contains(report_text(row.payload, "r_code", ""))
  })
  let progress_active = progress_rows.filter(fn(row) {
    ["pending", "in_progress"].contains(report_text(row.payload, "state", ""))
  })
  let progress_done = progress_rows.filter(fn(row) {
    report_text(row.payload, "state", "") == "completed"
  })
  let progress_average_raw = progress_active.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "actual_pct")
  })
  let progress_average = if progress_active.is_empty() {
    0.0
  } else {
    progress_average_raw / progress_active.length().to_double()
  }
  let tender_active = tender_plans.filter(fn(row) {
    ["planning", "publishing", "bidding"].contains(
      report_text(row.payload, "state", ""),
    )
  })
  let signed_sales = sale_contracts.filter(fn(row) {
    report_text(row.payload, "state", "") == "signed"
  })
  let released_mortgages = sale_mortgages.filter(fn(row) {
    report_text(row.payload, "state", "") == "released"
  })
  let approved_refunds = sale_refunds.filter(fn(row) {
    report_text(row.payload, "state", "") == "approved"
  })
  let dict_plan_sum = dashboard_rows(context, "cb_subject_dict").fold(
    init=0.0,
    fn(sum, row) { sum + report_amount(row.payload, "plan_amount") },
  )
  let signed_wan = signed_contracts.fold(init=0.0, fn(sum, row) {
    sum +
    (
      report_amount(row.payload, "ht_amount") +
      report_amount(row.payload, "sum_alter_amount")
    ) /
    10000.0
  })
  let approving_wan = approving_contracts.fold(init=0.0, fn(sum, row) {
    sum +
    (
      report_amount(row.payload, "ht_amount") +
      report_amount(row.payload, "sum_alter_amount")
    ) /
    10000.0
  })
  let fund_in_plan = fund_plans.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "direction", "") == "in" {
      sum + report_amount(row.payload, "plan_amount")
    } else {
      sum
    }
  })
  let fund_in_actual = fund_plans.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "direction", "") == "in" {
      sum + report_amount(row.payload, "actual_amount")
    } else {
      sum
    }
  })
  let fund_out_plan = fund_plans.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "direction", "") == "out" {
      sum + report_amount(row.payload, "plan_amount")
    } else {
      sum
    }
  })
  let fund_out_actual = fund_plans.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "direction", "") == "out" {
      sum + report_amount(row.payload, "actual_amount")
    } else {
      sum
    }
  })
  let invoice_in_total = invoice_in.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "total_amount")
  })
  let invoice_out_total = invoice_out.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "total_amount")
  })
  let invoice_in_tax = invoice_in.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "tax_amount")
  })
  let invoice_out_tax = invoice_out.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "tax_amount")
  })
  let units = dashboard_rows(context, "mu_business_unit").filter(fn(row) {
    report_text(row.payload, "bu_type", "") == "company" &&
    dashboard_active(row.payload)
  })
  let expense_by_category_map : Map[String, Double] = {}
  for row in applications {
    if ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      let contract = contract_by_id.get_or_default(
        report_text(row.payload, "contract_guid", ""),
        Json::object({}),
      )
      let code = report_text(contract, "r_code", "R0")
      expense_by_category_map.set(
        code,
        expense_by_category_map.get_or_default(code, 0.0) +
        report_amount(row.payload, "apply_amount") / 10000.0,
      )
    }
  }
  let expense_by_id : Map[String, Json] = {}
  for row in expenses {
    expense_by_id.set(
      report_text(row.payload, "expense_guid", row.record_id),
      row.payload,
    )
  }
  for row in dashboard_rows(context, "cb_expense_split") {
    let expense = expense_by_id.get_or_default(
      report_text(row.payload, "expense_guid", ""),
      Json::object({}),
    )
    if ["完全支付", "部分支付"].contains(
        report_text(expense, "pay_state", ""),
      ) {
      let code = report_text(row.payload, "r_code", "R0")
      expense_by_category_map.set(
        code,
        expense_by_category_map.get_or_default(code, 0.0) +
        report_amount(row.payload, "amount") / 10000.0,
      )
    }
  }
  let category_names : Map[String, String] = {}
  for row in dashboard_rows(context, "cb_r_master") {
    category_names.set(
      report_text(row.payload, "r_code", ""),
      report_text(row.payload, "r_name", ""),
    )
  }
  let expense_by_category : Array[Json] = []
  for code, amount in expense_by_category_map {
    if amount > 0.0 {
      expense_by_category.push(
        Json::object({
          "rCode": Json::string(code),
          "rName": Json::string(category_names.get_or_default(code, code)),
          "amount": Json::number(round_places(amount, 2)),
        }),
      )
    }
  }
  expense_by_category.sort_by(fn(left, right) {
    let order = json_number(right, "amount", 0.0).compare(
      json_number(left, "amount", 0.0),
    )
    if order == 0 {
      json_text(left, "rCode", "").lexical_compare(
        json_text(right, "rCode", ""),
      )
    } else {
      order
    }
  })
  let expense_by_city : Array[Json] = []
  if business_unit_id is None && project_id is None {
    for unit in units {
      let unit_id = report_text(unit.payload, "bu_guid", unit.record_id)
      let unit_expense = applications.fold(init=0.0, fn(sum, row) {
        if report_text(row.payload, "bu_guid", "") == unit_id &&
          ["完全支付", "部分支付"].contains(
            report_text(row.payload, "pay_state", ""),
          ) {
          sum + report_amount(row.payload, "apply_amount")
        } else {
          sum
        }
      })
      let unit_revenue = sale_revenues.fold(init=0.0, fn(sum, row) {
        if report_text(row.payload, "bu_guid", "") == unit_id &&
          report_text(row.payload, "status", "") == "received" {
          sum + report_amount(row.payload, "amount")
        } else {
          sum
        }
      })
      expense_by_city.push(
        Json::object({
          "buGuid": Json::string(unit_id),
          "name": Json::string(report_text(unit.payload, "bu_name", unit_id)),
          "expense": Json::number(unit_expense / 10000.0),
          "revenue": Json::number(unit_revenue / 10000.0),
        }),
      )
    }
    expense_by_city.sort_by(fn(left, right) {
      report_amount(right, "expense").compare(report_amount(left, "expense"))
    })
  }
  let total_expense = (paid_contract_expense + paid_expense) / 10000.0
  let net_profit = total_revenue - total_expense
  let net_profit_rate = if total_revenue > 0.0 {
    round_places(net_profit / total_revenue * 100.0, 2)
  } else {
    0.0
  }
  let available_cash = if fund_in_actual / 10000.0 > total_expense {
    fund_in_actual / 10000.0 - total_expense + expected_revenue * 0.3
  } else {
    expected_revenue * 0.3
  }
  let monthly_outflow = if total_expense > 0.0 {
    total_expense / 6.0
  } else {
    1.0
  }
  let cashflow_months_value = round_places(available_cash / monthly_outflow, 1)
  let health_score = if warnings.is_empty() {
    100
  } else {
    let score = 100 - warnings.length() * 10
    if score > 0 {
      score
    } else {
      0
    }
  }
  let health_breakdown = Json::object({
    "profit": Json::object({
      "score": Json::number(if total_revenue > 0.0 { 100 } else { 50 }),
      "weight": Json::number(40),
      "label": Json::string("利润达成率"),
    }),
    "recover": Json::object({
      "score": Json::number(
        if total_revenue + expected_revenue > 0.0 {
          round_places(
            total_revenue / (total_revenue + expected_revenue) * 100.0,
            0,
          )
        } else {
          0
        },
      ),
      "weight": Json::number(25),
      "label": Json::string("回款率"),
    }),
    "budget": Json::object({
      "score": Json::number(
        if dict_plan_sum > 0.0 {
          round_places(
            (signed_wan + approving_wan) / (dict_plan_sum / 10000.0) * 100.0,
            0,
          )
        } else {
          0
        },
      ),
      "weight": Json::number(20),
      "label": Json::string("预算执行"),
    }),
    "warning": Json::object({
      "score": Json::number(health_score.to_double()),
      "weight": Json::number(15),
      "label": Json::string("风险告警"),
    }),
  })
  fn compact_contract(row : SourceRow) -> Json {
    Json::object({
      "contractCode": Json::string(
        report_text(row.payload, "contract_code", ""),
      ),
      "contractName": Json::string(
        report_text(row.payload, "contract_name", ""),
      ),
      "htAmount": Json::number(report_amount(row.payload, "ht_amount")),
      "contractGuid": Json::string(
        report_text(row.payload, "contract_guid", row.record_id),
      ),
    })
  }
  let top_unpaid = signed_contracts.map(compact_contract)
  let top_r0 = r0_contracts.map(compact_contract)
  let top_approving = approving_contracts.map(compact_contract)
  let sort_contracts = fn(left : Json, right : Json) -> Int {
    let order = json_number(right, "htAmount", 0.0).compare(
      json_number(left, "htAmount", 0.0),
    )
    if order == 0 {
      json_text(left, "contractGuid", "").lexical_compare(
        json_text(right, "contractGuid", ""),
      )
    } else {
      order
    }
  }
  top_unpaid.sort_by(sort_contracts)
  top_r0.sort_by(sort_contracts)
  top_approving.sort_by(sort_contracts)
  let funnel = Json::array([
    Json::object({
      "stage": Json::string("客户"),
      "value": Json::number(sale_customers.length().to_double()),
    }),
    Json::object({
      "stage": Json::string("认筹"),
      "value": Json::number(sale_subscriptions.length().to_double()),
    }),
    Json::object({
      "stage": Json::string("签约"),
      "value": Json::number(signed_sales.length().to_double()),
    }),
    Json::object({
      "stage": Json::string("放款"),
      "value": Json::number(released_mortgages.length().to_double()),
    }),
    Json::object({
      "stage": Json::string("退房"),
      "value": Json::number(-approved_refunds.length().to_double()),
    }),
  ])
  let compare_sales = Json::array([
    Json::object({
      "name": Json::string("认筹"),
      "value": Json::number(sale_subscriptions.length().to_double()),
    }),
    Json::object({
      "name": Json::string("签约"),
      "value": Json::number(signed_sales.length().to_double()),
    }),
    Json::object({
      "name": Json::string("放款"),
      "value": Json::number(released_mortgages.length().to_double()),
    }),
  ])
  let compare_cost = Json::array([
    Json::object({
      "name": Json::string("A 目标"),
      "value": Json::number(dict_plan_sum),
    }),
    Json::object({
      "name": Json::string("D 已成"),
      "value": Json::number(signed_wan),
    }),
    Json::object({
      "name": Json::string("E 在途"),
      "value": Json::number(approving_wan),
    }),
  ])
  let compare_fund = Json::array([
    Json::object({
      "name": Json::string("收入计划"),
      "value": Json::number(fund_in_plan),
    }),
    Json::object({
      "name": Json::string("收入实际"),
      "value": Json::number(fund_in_actual),
    }),
    Json::object({
      "name": Json::string("支出计划"),
      "value": Json::number(fund_out_plan),
    }),
    Json::object({
      "name": Json::string("支出实际"),
      "value": Json::number(fund_out_actual),
    }),
  ])
  let level = if project_id is Some(_) {
    "project"
  } else if business_unit_id is Some(_) {
    "bu"
  } else {
    "group"
  }
  dashboard_envelope(
    Json::object({
      "scope": Json::object({
        "buGuid": dashboard_optional_json(business_unit_id),
        "projGuid": dashboard_optional_json(project_id),
        "level": Json::string(level),
      }),
      "kpi": Json::object({
        "r6Received": Json::number(total_revenue),
        "r6Expected": Json::number(expected_revenue),
        "contractSigned": Json::number(signed_wan),
        "contractApproving": Json::number(approving_wan),
        "dictPlanSum": Json::number(round_places(dict_plan_sum, 2)),
        "unpaidApply": Json::number(
          unpaid_applications.fold(init=0.0, fn(sum, row) {
            sum + report_amount(row.payload, "apply_amount")
          }) /
          10000.0,
        ),
        "r0PendingCount": Json::number(r0_contracts.length().to_double()),
        "customerCount": Json::number(sale_customers.length().to_double()),
        "subCount": Json::number(sale_subscriptions.length().to_double()),
        "signedCount": Json::number(signed_sales.length().to_double()),
        "mortgageCount": Json::number(released_mortgages.length().to_double()),
        "mortgageAmount": Json::number(
          released_mortgages.fold(init=0.0, fn(sum, row) {
            sum + report_amount(row.payload, "loan_amount")
          }) /
          10000.0,
        ),
        "refundCount": Json::number(approved_refunds.length().to_double()),
        "scontractTotal": Json::number(
          signed_sales.fold(init=0.0, fn(sum, row) {
            sum + report_amount(row.payload, "total_price")
          }) /
          10000.0,
        ),
        "fundInPlan": Json::number(fund_in_plan),
        "fundInActual": Json::number(fund_in_actual),
        "fundOutPlan": Json::number(fund_out_plan),
        "fundOutActual": Json::number(fund_out_actual),
        "progressActive": Json::number(progress_active.length().to_double()),
        "progressAvgPct": Json::number(round_places(progress_average, 1)),
        "progressDone": Json::number(progress_done.length().to_double()),
        "invInTotal": Json::number(invoice_in_total),
        "invOutTotal": Json::number(invoice_out_total),
        "netTax": Json::number(
          round_places(invoice_out_tax - invoice_in_tax, 2),
        ),
        "tenderActiveCount": Json::number(tender_active.length().to_double()),
        "tenderActiveAmount": Json::number(
          tender_active.fold(init=0.0, fn(sum, row) {
            sum + report_amount(row.payload, "estimated_amount")
          }) /
          10000.0,
        ),
        "tenderAwardedAmount": Json::number(
          tender_awards.fold(init=0.0, fn(sum, row) {
            sum + report_amount(row.payload, "award_amount")
          }) /
          10000.0,
        ),
        "openWarnings": Json::number(warnings.length().to_double()),
        "runningProcesses": Json::number(processes.length().to_double()),
        "totalRevenue": Json::number(total_revenue),
        "totalExpense": Json::number(total_expense),
        "netProfit": Json::number(net_profit),
        "netProfitRate": Json::number(net_profit_rate),
        "cashflowMonths": Json::number(cashflow_months_value),
        "healthScore": Json::number(health_score.to_double()),
      }),
      "healthBreakdown": health_breakdown,
      "expenseByCategory": Json::array(
        if expense_by_category.length() > 20 {
          expense_by_category[0:20].to_owned()
        } else {
          expense_by_category
        },
      ),
      "expenseByCity": Json::array(expense_by_city),
      "gauge": Json::object({
        "collectionRate": Json::number(
          if total_revenue + expected_revenue > 0.0 {
            round_places(
              total_revenue / (total_revenue + expected_revenue) * 100.0,
              1,
            )
          } else {
            0
          },
        ),
        "mortgageRate": Json::number(
          if signed_sales.is_empty() {
            0
          } else {
            round_places(
              released_mortgages.length().to_double() /
              signed_sales.length().to_double() *
              100.0,
              1,
            )
          },
        ),
        "payableRate": Json::number(
          if signed_wan > 0.0 {
            round_places(
              unpaid_applications.fold(init=0.0, fn(sum, row) {
                sum + report_amount(row.payload, "apply_amount")
              }) /
              10000.0 /
              signed_wan *
              100.0,
              1,
            )
          } else {
            0
          },
        ),
        "budgetUsedRate": Json::number(
          if dict_plan_sum > 0.0 {
            round_places(
              (signed_wan + approving_wan) / (dict_plan_sum / 10000.0) * 100.0,
              1,
            )
          } else {
            0
          },
        ),
      }),
      "funnel": funnel,
      "compareSales": compare_sales,
      "compareCost": compare_cost,
      "compareFund": compare_fund,
      "tops": Json::object({
        "topUnpaid": Json::array(
          if top_unpaid.length() > 5 {
            top_unpaid[0:5].to_owned()
          } else {
            top_unpaid
          },
        ),
        "topR0": Json::array(
          if top_r0.length() > 5 {
            top_r0[0:5].to_owned()
          } else {
            top_r0
          },
        ),
        "topApproving": Json::array(
          if top_approving.length() > 5 {
            top_approving[0:5].to_owned()
          } else {
            top_approving
          },
        ),
        "topOverbudget": Json::array([]),
        "topGap": Json::array([]),
      }),
    }),
    context,
    "imported_or_empty",
  )
}
