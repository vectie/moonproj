///|
/// Native port of the source profit-actual comparison.
///
/// Real receipts, paid applications, expenses, contracts, and loans are read
/// from imported PostgreSQL envelopes. Sparse plan subjects use the same
/// explicit progress/mapping fallbacks as the source implementation. This is
/// still an observation: it never approves a plan, consumes budget, posts
/// accounting, releases cash, files tax, or calls a provider.

///|
fn investment_actual_default_mappings() -> Map[String, String] {
  let values : Map[String, String] = {}
  values.set("progress.global", "0.30")
  values.set("progress.R10", "0.95")
  values.set("progress.R12", "0.50")
  values.set("progress.R19", "0.30")
  values.set("progress.R20", "0.30")
  values.set("progress.R25", "0.30")
  values.set("progress.R27", "0.30")
  values.set("progress.R28", "0.30")
  values.set("progress.R29", "0.30")
  values.set("progress.R30", "0.24")
  values.set("split.R10.land", "0.85")
  values.set("split.R10.pre", "0.15")
  values.set("tax.rate", "0.03")
  values.set("tax.split.R14", "0.42")
  values.set("tax.split.R15", "0.00")
  values.set("tax.split.R16", "0.52")
  values.set("tax.split.R17", "0.06")
  values.set("split.R20.R21", "0.62")
  values.set("split.R20.R22", "0.34")
  values.set("split.R20.R23", "0.04")
  values.set("rate.R24", "0.022")
  values.set("keyword.R19", "营销|推广|广告|渠道|代理|销售")
  values.set(
    "keyword.R20", "人力|工资|社保|行政|办公|审计|法务|管理",
  )
  values.set("threshold.loan", "100")
  values.set("threshold.warn", "5")
  values
}

///|
async fn investment_actual_mappings(
  project_id : String,
) -> Map[String, String] raise CompanyServiceError {
  let rows = raw_source_rows("tzsy_subject_mapping", 5000)
  let matching : Array[SourceRow] = []
  for row in rows {
    if report_text(row.payload, "proj_guid", "") == project_id {
      matching.push(row)
    }
  }
  if matching.is_empty() {
    investment_actual_default_mappings()
  } else {
    let values : Map[String, String] = {}
    for row in matching {
      let key = report_text(row.payload, "param_key", "")
      if !key.is_empty() {
        values.set(key, report_text(row.payload, "param_value", ""))
      }
    }
    values
  }
}

///|
fn investment_actual_number(
  mappings : Map[String, String],
  key : String,
  fallback : Double,
) -> Double {
  parse_number(mappings.get_or_default(key, fallback.to_string()))
}

///|
fn investment_actual_text(
  mappings : Map[String, String],
  key : String,
  fallback : String,
) -> String {
  mappings.get_or_default(key, fallback)
}

///|
fn investment_actual_matches(subject : String, pattern : String) -> Bool {
  for token_view in pattern.split("|") {
    let token = token_view.to_owned()
    if !token.is_empty() && subject.contains(token) {
      return true
    }
  }
  false
}

///|
async fn investment_actual_plan_values(
  project_id : String,
) -> Map[String, Double]? raise CompanyServiceError {
  let imports = raw_source_rows("tzsy_excel_import", 5000)
  let profit_rows = raw_source_rows("tzsy_profit_table", 10000)
  let mut selected_import = ""
  let mut selected_created = ""
  for row in imports {
    let payload = row.payload
    let import_id = report_text(payload, "import_guid", row.record_id)
    if report_text(payload, "proj_guid", "") == project_id &&
      profit_rows.any(fn(profit) {
        report_text(profit.payload, "import_guid", "") == import_id
      }) {
      let created = report_text(payload, "created_at", "")
      if selected_import.is_empty() || created.compare(selected_created) > 0 {
        selected_import = import_id
        selected_created = created
      }
    }
  }
  if selected_import.is_empty() {
    return None
  }
  let values : Map[String, Double] = {}
  for index in 4..<=33 {
    values.set("R" + index.to_string(), 0.0)
  }
  for row in profit_rows {
    let payload = row.payload
    if report_text(payload, "import_guid", "") == selected_import &&
      report_text(payload, "col_key", "") == "C" {
      let row_index = report_text(payload, "row_idx", "")
      if !row_index.is_empty() {
        values.set("R" + row_index, report_amount(payload, "num_value"))
      }
    }
  }
  Some(values)
}

///|
fn investment_actual_value(
  total : Double,
  source : String,
  simulated : Bool,
) -> Json {
  Json::object({
    "total": Json::number(total),
    "source": Json::string(source),
    "simulated": Json::boolean(simulated),
  })
}

///|
fn investment_actual_child(
  subject : String,
  amount : Double,
  kind : String,
  source : String,
  drilldown : String?,
) -> Json {
  let fields : Map[String, Json] = {}
  fields.set("subject", Json::string(subject))
  fields.set("amount", Json::number(amount))
  fields.set("kind", Json::string(kind))
  if !source.is_empty() {
    fields.set("source", Json::string(source))
  }
  match drilldown {
    Some(value) => fields.set("drilldown", Json::string(value))
    None => ()
  }
  Json::object(fields)
}

///|
fn investment_actual_add_child(
  children : Map[String, Json],
  key : String,
  child : Json,
) -> Unit {
  let values = match children.get(key) {
    Some(Array(items)) => items
    _ => []
  }
  values.push(child)
  children.set(key, Json::array(values))
}

///|
fn investment_actual_project(
  rows : Array[SourceRow],
  project_id : String,
) -> Json? {
  for row in rows {
    if report_text(row.payload, "proj_guid", row.record_id) == project_id &&
      json_field(row.payload, "deleted_at") is None {
      return Some(row.payload)
    }
  }
  None
}

///|
async fn investment_actual_response_native(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let tables = [
    "ep_project", "sys_user", "tzsy_version", "tzsy_excel_import", "tzsy_excel_sheet",
    "tzsy_profit_table", "tzsy_plan_line", "tzsy_subject_mapping", "sale_revenue",
    "cb_htfk_apply", "cb_contract", "vcb_expense", "vcb_loan_simple",
  ]
  let rows : Map[String, Array[SourceRow]] = {}
  let coverage : Map[String, Int] = {}
  for table in tables {
    let values = raw_source_rows(table, 10000)
    rows.set(table, values)
    coverage.set(table, values.length())
  }
  let project = match
    investment_actual_project(rows.get_or_default("ep_project", []), project_id) {
    Some(value) => value
    None =>
      return (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(41001),
          "message": Json::string("项目不存在"),
          "source_coverage": report_coverage(coverage),
          "missing_or_empty_source_tables": Json::array(
            report_missing(coverage),
          ),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(false),
          "provider_execution": Json::boolean(false),
          "simulation": Json::boolean(false),
        }),
      )
  }
  let plan = investment_actual_plan_values(project_id)
  let plan = match plan {
    Some(value) => value
    None =>
      return (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(41002),
          "message": Json::string("该项目暂无测算数据,无法对比"),
          "projectId": Json::string(project_id),
          "source_coverage": report_coverage(coverage),
          "missing_or_empty_source_tables": Json::array(
            report_missing(coverage),
          ),
          "authorizing": Json::boolean(false),
          "persisted": Json::boolean(false),
          "provider_execution": Json::boolean(false),
          "simulation": Json::boolean(false),
        }),
      )
  }
  let mappings = investment_actual_mappings(project_id)
  let progress = investment_actual_number(mappings, "progress.global", 0.30)
  let loan_threshold = investment_actual_number(
    mappings, "threshold.loan", 100.0,
  )
  let bu_guid = report_text(project, "bu_guid", "")
  let values : Map[String, Json] = {}
  let children : Map[String, Json] = {}
  let plan_value = fn(key : String) -> Double { plan.get_or_default(key, 0.0) }

  let sales = rows.get_or_default("sale_revenue", [])
  let received : Array[SourceRow] = []
  for row in sales {
    if report_text(row.payload, "proj_guid", "") == project_id &&
      report_text(row.payload, "status", "") == "received" {
      received.push(row)
    }
  }
  let r6 = received.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "amount") / 10000.0
  })
  values.set(
    "R6",
    investment_actual_value(r6, "sale_revenue.status=received", false),
  )
  for row in received {
    let subject = report_text(row.payload, "customer_name", "") +
      " " +
      report_text(row.payload, "receive_date", "")
    investment_actual_add_child(
      children,
      "R6",
      investment_actual_child(
        subject,
        report_amount(row.payload, "amount") / 10000.0,
        "income",
        "sale_revenue",
        None,
      ),
    )
  }
  values.set(
    "R7",
    investment_actual_value(0.0, "无其他收入业务表", true),
  )
  children.set("R7", Json::array([]))
  values.set("R4", investment_actual_value(r6, "R6 + R7", false))
  children.set(
    "R4",
    Json::array([
      investment_actual_child("回款额 (R6)", r6, "income", "", Some("R6")),
      investment_actual_child("其他收入 (R7)", 0.0, "income", "", None),
    ]),
  )
  let r5 = sales.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "proj_guid", "") == project_id {
      sum + report_amount(row.payload, "amount") / 10000.0
    } else {
      sum
    }
  })
  values.set("R5", investment_actual_value(r5, "sale_revenue.all", false))

  let contracts = rows.get_or_default("cb_contract", [])
  let applications = rows.get_or_default("cb_htfk_apply", [])
  let paid_applications : Array[SourceRow] = []
  for row in applications {
    if report_text(row.payload, "proj_guid", "") == project_id &&
      ["完全支付", "部分支付"].contains(
        report_text(row.payload, "pay_state", ""),
      ) {
      paid_applications.push(row)
    }
  }
  let r11 = paid_applications.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "apply_amount") / 10000.0
  })
  values.set(
    "R11",
    investment_actual_value(r11, "cb_htfk_apply.已支付", false),
  )
  for row in paid_applications {
    let contract_id = report_text(row.payload, "contract_guid", "")
    let mut contract_name = ""
    for contract in contracts {
      if report_text(contract.payload, "contract_guid", contract.record_id) ==
        contract_id {
        contract_name = report_text(contract.payload, "contract_name", "")
      }
    }
    let subject = if !contract_name.is_empty() {
      contract_name
    } else {
      report_text(row.payload, "subject", "工程付款")
    }
    investment_actual_add_child(
      children,
      "R11",
      investment_actual_child(
        subject,
        report_amount(row.payload, "apply_amount") / 10000.0,
        "expense",
        "cb_htfk_apply " + report_text(row.payload, "pay_state", ""),
        None,
      ),
    )
  }

  let progress_r10 = investment_actual_number(mappings, "progress.R10", 0.95)
  let r10 = plan_value("R10") * progress_r10
  values.set(
    "R10",
    investment_actual_value(
      r10,
      "模拟 (R10 进度 " + (progress_r10 * 100.0).to_int().to_string() + "%)",
      true,
    ),
  )
  children.set(
    "R10",
    Json::array([
      investment_actual_child(
        "土地征用费",
        r10 * investment_actual_number(mappings, "split.R10.land", 0.85),
        "expense",
        "模拟",
        None,
      ),
      investment_actual_child(
        "前期费用",
        r10 * investment_actual_number(mappings, "split.R10.pre", 0.15),
        "expense",
        "模拟",
        None,
      ),
    ]),
  )
  let progress_r12 = investment_actual_number(mappings, "progress.R12", 0.50)
  let r12 = plan_value("R12") * progress_r12
  values.set(
    "R12",
    investment_actual_value(
      r12,
      "模拟 (R12 进度 " + (progress_r12 * 100.0).to_int().to_string() + "%)",
      true,
    ),
  )
  children.set("R12", Json::array([]))
  let r9 = r10 + r11 + r12
  values.set("R9", investment_actual_value(r9, "R10+R11+R12", false))
  children.set(
    "R9",
    Json::array([
      investment_actual_child(
        "土地及前期 R10",
        r10,
        "expense",
        "模拟",
        Some("R10"),
      ),
      investment_actual_child(
        "工程运营 R11",
        r11,
        "expense",
        "实算",
        Some("R11"),
      ),
      investment_actual_child(
        "勘察设计 R12",
        r12,
        "expense",
        "模拟",
        Some("R12"),
      ),
    ]),
  )

  let tax_rate = investment_actual_number(mappings, "tax.rate", 0.03)
  let tax_actual = r6 * tax_rate
  values.set(
    "R13",
    investment_actual_value(
      tax_actual,
      "已回款 × " + (tax_rate * 100.0).to_string() + "% 综合税率",
      true,
    ),
  )
  let r14 = tax_actual *
    investment_actual_number(mappings, "tax.split.R14", 0.42)
  let r15 = tax_actual *
    investment_actual_number(mappings, "tax.split.R15", 0.0)
  let r16 = tax_actual *
    investment_actual_number(mappings, "tax.split.R16", 0.52)
  let r17 = tax_actual *
    investment_actual_number(mappings, "tax.split.R17", 0.06)
  values.set(
    "R14",
    investment_actual_value(r14, "增值税及附加估算", true),
  )
  values.set("R15", investment_actual_value(r15, "土增税未清算", true))
  values.set("R16", investment_actual_value(r16, "所得税估算", true))
  values.set("R17", investment_actual_value(r17, "其他税金估算", true))
  children.set(
    "R13",
    Json::array([
      investment_actual_child(
        "增值税及附加 R14",
        r14,
        "expense",
        "",
        None,
      ),
      investment_actual_child(
        "土增税 R15 (未清算)",
        r15,
        "expense",
        "",
        None,
      ),
      investment_actual_child("所得税 R16", r16, "expense", "", None),
      investment_actual_child("其他税金 R17", r17, "expense", "", None),
    ]),
  )

  let expense_rows = rows.get_or_default("vcb_expense", [])
  let marketing : Array[SourceRow] = []
  let administration : Array[SourceRow] = []
  let marketing_pattern = investment_actual_text(
    mappings, "keyword.R19", "营销|推广|广告|渠道|代理|销售",
  )
  let administration_pattern = investment_actual_text(
    mappings, "keyword.R20", "人力|工资|社保|行政|办公|审计|法务|管理",
  )
  for row in expense_rows {
    let payload = row.payload
    if report_text(payload, "bu_guid", "") == bu_guid &&
      ["完全支付", "部分支付", "已支付"].contains(
        report_text(payload, "pay_state", ""),
      ) {
      let subject = report_text(payload, "subject", "")
      if investment_actual_matches(subject, marketing_pattern) {
        marketing.push(row)
      } else if investment_actual_matches(subject, administration_pattern) {
        administration.push(row)
      }
    }
  }
  let r19_real = marketing.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "pay_amount") / 10000.0
  })
  let r20_real = administration.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "pay_amount") / 10000.0
  })
  let progress_r19 = investment_actual_number(
    mappings, "progress.R19", progress,
  )
  let progress_r20 = investment_actual_number(
    mappings, "progress.R20", progress,
  )
  let r19_sim = plan_value("R19") * progress_r19
  let r20_sim = plan_value("R20") * progress_r20
  let r19 = if r19_real > 0.0 { r19_real } else { r19_sim }
  let r20 = if r20_real > 0.0 { r20_real } else { r20_sim }
  values.set(
    "R19",
    investment_actual_value(
      r19,
      if r19_real > 0.0 {
        "vcb_expense.营销关键词"
      } else {
        "模拟 (无营销付款记录)"
      },
      r19_real == 0.0,
    ),
  )
  values.set(
    "R20",
    investment_actual_value(
      r20,
      if r20_real > 0.0 {
        "vcb_expense.管理关键词"
      } else {
        "模拟 (无管理付款记录)"
      },
      r20_real == 0.0,
    ),
  )
  let r21 = r20 * investment_actual_number(mappings, "split.R20.R21", 0.62)
  let r22 = r20 * investment_actual_number(mappings, "split.R20.R22", 0.34)
  let r23 = r20 * investment_actual_number(mappings, "split.R20.R23", 0.04)
  values.set(
    "R21",
    investment_actual_value(r21, "按管理费比例拆分", true),
  )
  values.set(
    "R22",
    investment_actual_value(r22, "按管理费比例拆分", true),
  )
  values.set(
    "R23",
    investment_actual_value(r23, "按管理费比例拆分", true),
  )
  for row in marketing {
    investment_actual_add_child(
      children,
      "R19",
      investment_actual_child(
        report_text(row.payload, "subject", ""),
        report_amount(row.payload, "pay_amount") / 10000.0,
        "expense",
        "vcb_expense " + report_text(row.payload, "expense_code", row.record_id),
        None,
      ),
    )
  }
  if marketing.is_empty() {
    investment_actual_add_child(
      children,
      "R19",
      investment_actual_child(
        "无营销付款记录,按进度模拟",
        r19_sim,
        "expense",
        "模拟",
        None,
      ),
    )
  }
  if administration.is_empty() {
    children.set(
      "R20",
      Json::array([
        investment_actual_child(
          "人力资源费用 R21",
          r21,
          "expense",
          "",
          None,
        ),
        investment_actual_child("行政费用 R22", r22, "expense", "", None),
        investment_actual_child(
          "审计法务费用 R23",
          r23,
          "expense",
          "",
          None,
        ),
      ]),
    )
  } else {
    for row in administration {
      investment_actual_add_child(
        children,
        "R20",
        investment_actual_child(
          report_text(row.payload, "subject", ""),
          report_amount(row.payload, "pay_amount") / 10000.0,
          "expense",
          "vcb_expense " +
          report_text(row.payload, "expense_code", row.record_id),
          None,
        ),
      )
    }
  }

  let rate_r24 = investment_actual_number(mappings, "rate.R24", 0.022)
  let r24 = r6 * rate_r24
  let progress_r25 = investment_actual_number(
    mappings, "progress.R25", progress,
  )
  let r25 = plan_value("R25") * progress_r25
  values.set(
    "R24",
    investment_actual_value(r24, "回款 × 委托管理费率", false),
  )
  values.set(
    "R25",
    investment_actual_value(
      r25,
      "模拟 (R25 进度 " + (progress_r25 * 100.0).to_int().to_string() + "%)",
      true,
    ),
  )

  let loans = rows.get_or_default("vcb_loan_simple", [])
  let project_loans = loans.filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id
  })
  let r29_real = project_loans.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "loan_amount") / 10000.0
  })
  let r30_real = project_loans.fold(init=0.0, fn(sum, row) {
    sum +
    (
      report_amount(row.payload, "loan_amount") -
      report_amount(row.payload, "remain_amount")
    ) /
    10000.0
  })
  let progress_r29 = investment_actual_number(
    mappings, "progress.R29", progress,
  )
  let progress_r30 = investment_actual_number(
    mappings,
    "progress.R30",
    progress * 0.8,
  )
  let r29_sim = plan_value("R29") * progress_r29
  let r30_sim = plan_value("R30") * progress_r30
  let r29_real_live = r29_real >= loan_threshold
  let r30_real_live = r30_real >= loan_threshold
  let r29 = if r29_real_live { r29_real } else { r29_sim }
  let r30 = if r30_real_live { r30_real } else { r30_sim }
  values.set(
    "R29",
    investment_actual_value(
      r29,
      if r29_real_live {
        "vcb_loan_simple"
      } else {
        "模拟 (真实数据低于阈值)"
      },
      !r29_real_live,
    ),
  )
  values.set(
    "R30",
    investment_actual_value(
      r30,
      if r30_real_live {
        "vcb_loan_simple"
      } else {
        "模拟 (真实数据低于阈值)"
      },
      !r30_real_live,
    ),
  )
  if r29_real_live {
    for row in project_loans {
      let payload = row.payload
      investment_actual_add_child(
        children,
        "R29",
        investment_actual_child(
          report_text(payload, "subject", "") +
          " " +
          report_text(payload, "loan_code", row.record_id),
          report_amount(payload, "loan_amount") / 10000.0,
          "inflow",
          "vcb_loan_simple",
          None,
        ),
      )
    }
  } else {
    children.set(
      "R29",
      Json::array([
        investment_actual_child(
          "融资总额 (模拟)",
          r29,
          "inflow",
          "模拟",
          None,
        ),
      ]),
    )
  }
  if r30_real_live {
    for row in project_loans {
      let payload = row.payload
      investment_actual_add_child(
        children,
        "R30",
        investment_actual_child(
          report_text(payload, "subject", "") + " 已还",
          (
            report_amount(payload, "loan_amount") -
            report_amount(payload, "remain_amount")
          ) /
          10000.0,
          "outflow",
          "vcb_loan_simple",
          None,
        ),
      )
    }
  } else {
    children.set(
      "R30",
      Json::array([
        investment_actual_child(
          "还贷总额 (模拟)",
          r30,
          "outflow",
          "模拟",
          None,
        ),
      ]),
    )
  }

  let progress_r27 = investment_actual_number(
    mappings, "progress.R27", progress,
  )
  let progress_r28 = investment_actual_number(
    mappings, "progress.R28", progress,
  )
  let r27 = plan_value("R27") * progress_r27
  let r28 = plan_value("R28") * progress_r28
  let r26 = r27 + r28
  values.set("R27", investment_actual_value(r27, "模拟 (R27 进度)", true))
  values.set("R28", investment_actual_value(r28, "模拟 (R28 进度)", true))
  values.set("R26", investment_actual_value(r26, "R27 + R28", true))
  children.set(
    "R26",
    Json::array([
      investment_actual_child(
        "财务费用 R27 (利息)",
        r27,
        "expense",
        "",
        None,
      ),
      investment_actual_child(
        "财务审计费用 R28",
        r28,
        "expense",
        "",
        None,
      ),
    ]),
  )
  let r18 = r19 + r20 + r24 + r25 + r26
  values.set("R18", investment_actual_value(r18, "R19+R20+R24+R25+R26", false))
  children.set(
    "R18",
    Json::array([
      investment_actual_child(
        "营销费用 R19",
        r19,
        "expense",
        "",
        Some("R19"),
      ),
      investment_actual_child(
        "管理费用 R20",
        r20,
        "expense",
        "",
        Some("R20"),
      ),
      investment_actual_child(
        "委托管理 R24 (自动)",
        r24,
        "expense",
        "",
        None,
      ),
      investment_actual_child("委派人员 R25", r25, "expense", "", None),
      investment_actual_child(
        "综合财务 R26",
        r26,
        "expense",
        "",
        Some("R26"),
      ),
    ]),
  )
  let r8 = r9 + tax_actual + r18
  values.set("R8", investment_actual_value(r8, "R9+R13+R18", false))
  children.set(
    "R8",
    Json::array([
      investment_actual_child("直接成本 R9", r9, "expense", "", Some("R9")),
      investment_actual_child(
        "税金 R13",
        tax_actual,
        "expense",
        "",
        Some("R13"),
      ),
      investment_actual_child(
        "间接费用 R18",
        r18,
        "expense",
        "",
        Some("R18"),
      ),
    ]),
  )
  let r32 = plan_value("R32")
  let r31 = r6 - r8 + r29 - r30
  let r33 = r31 + r32
  values.set(
    "R32",
    investment_actual_value(r32, "资产估值未评估,取测算值", true),
  )
  values.set("R31", investment_actual_value(r31, "R4-R8+R29-R30", false))
  values.set("R33", investment_actual_value(r33, "R31 + R32", false))
  children.set(
    "R31",
    Json::array([
      investment_actual_child(
        "项目总收入 R4",
        r6,
        "income",
        "",
        Some("R4"),
      ),
      investment_actual_child(
        "项目总成本 R8 (扣减)",
        r8,
        "expense",
        "",
        Some("R8"),
      ),
      investment_actual_child("融资 R29", r29, "inflow", "", Some("R29")),
      investment_actual_child(
        "还贷 R30 (扣减)",
        r30,
        "outflow",
        "",
        Some("R30"),
      ),
    ]),
  )

  let contract_total = contracts.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "proj_guid", "") == project_id {
      sum +
      (
        report_amount(row.payload, "ht_amount") +
        report_amount(row.payload, "sum_alter_amount")
      ) /
      10000.0
    } else {
      sum
    }
  })
  let ar_balance = r5 - r6
  let collection_rate = if r5 > 0.0 { r6 / r5 * 100.0 } else { 0.0 }
  let ar_turnover_days = if r6 > 0.0 {
    (ar_balance / (r6 / 365.0)).to_int()
  } else {
    0
  }
  let pay_progress = if contract_total > 0.0 {
    r11 / contract_total * 100.0
  } else {
    0.0
  }
  let loan_balance = r29 - r30
  let tax_gap = plan_value("R13") - tax_actual
  let operating = Json::object({
    "collectionRate": Json::object({
      "value": Json::number(round_places(collection_rate, 1)),
      "unit": Json::string("%"),
      "label": Json::string("回款率"),
      "tip": Json::string("R6 已回款 / R5 签约额"),
    }),
    "arBalance": Json::object({
      "value": Json::number(round_places(ar_balance, 0)),
      "unit": Json::string("万"),
      "label": Json::string("应收账款余额"),
      "tip": Json::string("R5 - R6 (尚未到账)"),
    }),
    "arTurnoverDays": Json::object({
      "value": Json::number(ar_turnover_days.to_double()),
      "unit": Json::string("天"),
      "label": Json::string("应收周转天数"),
      "tip": Json::string("(R5-R6) / (R6/365)"),
    }),
    "payProgress": Json::object({
      "value": Json::number(round_places(pay_progress, 1)),
      "unit": Json::string("%"),
      "label": Json::string("工程付款进度"),
      "tip": Json::string("R11 已付 / cb_contract 合同总额"),
    }),
    "loanBalance": Json::object({
      "value": Json::number(round_places(loan_balance, 0)),
      "unit": Json::string("万"),
      "label": Json::string("融资净余额"),
      "tip": Json::string("R29 - R30"),
    }),
    "taxGap": Json::object({
      "value": Json::number(round_places(tax_gap, 0)),
      "unit": Json::string("万"),
      "label": Json::string("税金清算缺口"),
      "tip": Json::string("测算 R13 - 已估算 R13"),
    }),
    "contractTotal": Json::object({
      "value": Json::number(round_places(contract_total, 0)),
      "unit": Json::string("万"),
      "label": Json::string("工程合同总额"),
      "tip": Json::string("cb_contract.contract_amount"),
    }),
  })
  let values_json : Map[String, Json] = {}
  for key, value in values {
    values_json.set(key, value)
  }
  let children_json : Map[String, Json] = {}
  for key, value in children {
    children_json.set(key, value)
  }
  let now = report_share_now()
  let as_of = if now.length() >= 10 { now[:10].to_owned() } else { now }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "projGuid": Json::string(project_id),
        "projName": Json::string(report_text(project, "proj_name", project_id)),
        "asOf": Json::string(as_of),
        "progress": Json::number(progress),
        "mappingsLoaded": Json::number(mappings.length().to_double()),
        "values": Json::object(values_json),
        "children": Json::object(children_json),
        "operating": operating,
      }),
      "source_kind": Json::string("imported_or_simulated"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(report_missing(coverage)),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "simulation": Json::boolean(true),
    }),
  )
}
