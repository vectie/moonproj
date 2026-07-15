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
fn dashboard_active(_payload : Json) -> Bool {
  true
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
  let contract_in_progress = contracts.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "js_state", "") != "已结算" {
      sum +
      report_amount(row.payload, "ht_amount") +
      report_amount(row.payload, "sum_alter_amount")
    } else {
      sum
    }
  })
  let trend : Array[Json] = []
  for index in 0..<10 {
    trend.push(
      Json::object({
        "ym": Json::string(index.to_string()),
        "plan": Json::number(0),
        "actual": Json::number(0),
      }),
    )
  }
  dashboard_envelope(
    Json::object({
      "scope": Json::object({
        "buGuid": dashboard_optional_json(business_unit_id),
        "projGuid": dashboard_optional_json(project_id),
      }),
      "kpi": Json::object({
        "projectCount": Json::number(projects.length().to_double()),
        "inProgressProjects": Json::number(0),
        "contractInProgressAmount": Json::number(contract_in_progress),
        "unpaidAmount": Json::number(0),
        "openWarnings": Json::number(0),
        "runningProcesses": Json::number(0),
      }),
      "paymentTrend": Json::array(trend),
      "stageDistribution": Json::array([]),
      "latestWarnings": Json::array([]),
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
  let applications = dashboard_rows(context, "cb_htfk_apply").filter(fn(row) {
    dashboard_active(row.payload) &&
    dashboard_scoped(row.payload, business_unit_id, project_id)
  })
  let expenses = dashboard_rows(context, "vcb_expense").filter(fn(row) {
    dashboard_active(row.payload) &&
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
  let units = dashboard_rows(context, "mu_business_unit").filter(fn(row) {
    report_text(row.payload, "bu_type", "") == "company" &&
    dashboard_active(row.payload)
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
      expense_by_city.push(
        Json::object({
          "buGuid": Json::string(unit_id),
          "name": Json::string(report_text(unit.payload, "bu_name", unit_id)),
          "expense": Json::number(unit_expense / 10000.0),
          "revenue": Json::number(0),
        }),
      )
    }
    expense_by_city.sort_by(fn(left, right) {
      report_amount(right, "expense").compare(report_amount(left, "expense"))
    })
  }
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
        "customerCount": Json::number(
          dashboard_rows(context, "sale_customer").length().to_double(),
        ),
        "totalRevenue": Json::number(0),
        "totalExpense": Json::number(
          (paid_contract_expense + paid_expense) / 10000.0,
        ),
        "netProfit": Json::number(
          -(paid_contract_expense + paid_expense) / 10000.0,
        ),
        "netProfitRate": Json::number(0),
        "healthScore": Json::number(0),
      }),
      "healthBreakdown": Json::object({}),
      "expenseByCategory": Json::array([]),
      "expenseByCity": Json::array(expense_by_city),
      "gauge": Json::object({}),
      "funnel": Json::array([]),
      "compareSales": Json::array([]),
      "compareCost": Json::array([]),
      "compareFund": Json::array([]),
      "tops": Json::object({
        "topUnpaid": Json::array([]),
        "topR0": Json::array([]),
        "topApproving": Json::array([]),
        "topOverbudget": Json::array([]),
        "topGap": Json::array([]),
      }),
    }),
    context,
    "imported_or_empty",
  )
}
