///|
/// Native source-backed cashflow observations.
struct CashflowContext {
  rows : Map[String, Array[SourceRow]]
  coverage : Map[String, Int]
}

///|
fn cashflow_tables() -> Array[String] {
  [
    "cb_contract", "cb_contract_milestone", "cb_htfk_apply", "cb_htfkplan", "cb_plan_version",
    "cb_subject_dict", "ep_project", "mu_business_unit", "sale_revenue", "vcb_expense",
    "vcb_loan_simple",
  ]
}

///|
async fn cashflow_context() -> CashflowContext raise CompanyServiceError {
  let rows : Map[String, Array[SourceRow]] = {}
  let coverage : Map[String, Int] = {}
  for table in cashflow_tables() {
    let values = raw_source_rows(table, 500)
    rows.set(table, values)
    coverage.set(table, values.length())
  }
  { rows, coverage }
}

///|
fn cashflow_missing(coverage : Map[String, Int]) -> Array[Json] {
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
fn cashflow_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(cashflow_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
async fn cashflow_months(
  months : Int,
  offset : Int,
) -> Array[String] raise CompanyServiceError {
  if months < 1 || months > 24 {
    raise reject(422, "months must be between 1 and 24")
  }
  let output = run_sql(
    "SELECT to_char(date_trunc('month', current_date) + (n || ' months')::interval, 'YYYY-MM') FROM generate_series(" +
    offset.to_string() +
    "," +
    (offset + months - 1).to_string() +
    ") AS n",
  )
  output
  .split("\n")
  .filter(fn(value) { !value.is_empty() })
  .map(fn(value) { value.to_owned() })
  .to_array()
}

///|
fn cashflow_month(value : Json, key : String) -> String {
  let text = report_text(value, key, "")
  if text.length() >= 7 {
    text[:7].to_owned()
  } else {
    ""
  }
}

///|
fn cashflow_scope(
  payload : Json,
  bu_guid : String?,
  proj_guid : String?,
  contract_projects : Map[String, String],
  use_contract_project : Bool,
) -> Bool {
  let bu_ok = match bu_guid {
    Some(value) => report_text(payload, "bu_guid", "") == value
    None => true
  }
  let project_ok = match proj_guid {
    Some(value) =>
      if use_contract_project {
        contract_projects.get_or_default(
          report_text(payload, "contract_guid", ""),
          "",
        ) ==
        value
      } else {
        report_text(payload, "proj_guid", "") == value
      }
    None => true
  }
  bu_ok && project_ok
}

///|
fn cashflow_optional_text(value : String?) -> Json {
  match value {
    Some(item) => Json::string(item)
    None => Json::null()
  }
}

///|
async fn cashflow_forecast_response(
  months : Int,
  bu_guid : String?,
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  match bu_guid {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid bu_guid")
    _ => ()
  }
  match proj_guid {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid proj_guid")
    _ => ()
  }
  let context = cashflow_context()
  let contracts : Map[String, String] = {}
  for row in context.rows.get_or_default("cb_contract", []) {
    contracts.set(
      report_text(row.payload, "contract_guid", row.record_id),
      report_text(row.payload, "proj_guid", ""),
    )
  }
  let month_list = cashflow_months(months, 0)
  let series : Map[String, Map[String, Double]] = {}
  for month in month_list {
    series.set(month, {
      "planned": 0.0,
      "pending": 0.0,
      "confirmed": 0.0,
      "expense": 0.0,
      "loan": 0.0,
    })
  }
  for row in context.rows.get_or_default("cb_htfkplan", []) {
    if cashflow_scope(row.payload, bu_guid, proj_guid, contracts, true) {
      let month = cashflow_month(row.payload, "jhfk_date")
      match series.get(month) {
        Some(values) => {
          values.set(
            "planned",
            values.get_or_default("planned", 0.0) +
            report_amount(row.payload, "jhfk_amount"),
          )
          series.set(month, values)
        }
        None => ()
      }
    }
  }
  for row in context.rows.get_or_default("cb_htfk_apply", []) {
    if cashflow_scope(row.payload, bu_guid, proj_guid, contracts, false) {
      let month = cashflow_month(row.payload, "apply_date")
      match series.get(month) {
        Some(values) => {
          let state = report_text(row.payload, "apply_state", "")
          let key = if state == "申请审批中" {
            "pending"
          } else if state == "已审核" {
            "confirmed"
          } else {
            ""
          }
          if !key.is_empty() {
            values.set(
              key,
              values.get_or_default(key, 0.0) +
              report_amount(row.payload, "apply_amount"),
            )
            series.set(month, values)
          }
        }
        None => ()
      }
    }
  }
  let rows : Array[Json] = []
  let mut cumulative = 0.0
  let mut actual_cumulative = 0.0
  for month in month_list {
    let values = series.get_or_default(month, {})
    let planned = values.get_or_default("planned", 0.0)
    let pending = values.get_or_default("pending", 0.0)
    let confirmed = values.get_or_default("confirmed", 0.0)
    let expense = values.get_or_default("expense", 0.0)
    let loan = values.get_or_default("loan", 0.0)
    let total = confirmed +
      pending +
      (if planned - confirmed - pending > 0.0 {
        planned - confirmed - pending
      } else {
        0.0
      }) +
      expense +
      loan
    let actual = confirmed + expense + loan
    cumulative += total
    actual_cumulative += actual
    rows.push(
      Json::object({
        "ym": Json::string(month),
        "planned": Json::number(planned),
        "pending": Json::number(pending),
        "confirmed": Json::number(confirmed),
        "expense": Json::number(expense),
        "loan": Json::number(loan),
        "totalOutflow": Json::number(round_places(total, 2)),
        "cumulativeOutflow": Json::number(round_places(cumulative, 2)),
        "actualOutflow": Json::number(round_places(actual, 2)),
        "actualCumulative": Json::number(round_places(actual_cumulative, 2)),
      }),
    )
  }
  let sum_field = fn(key : String) -> Double {
    rows.fold(init=0.0, fn(sum, row) { sum + report_amount(row, key) })
  }
  cashflow_envelope(
    Json::object({
      "filters": Json::object({
        "months": Json::number(months.to_double()),
        "buGuid": cashflow_optional_text(bu_guid),
        "projGuid": cashflow_optional_text(proj_guid),
      }),
      "months": Json::array(
        rows.map(fn(row) { json_field(row, "ym").unwrap_or(Json::string("")) }),
      ),
      "series": Json::array(rows),
      "totals": Json::object({
        "plannedTotal": Json::number(sum_field("planned")),
        "pendingTotal": Json::number(sum_field("pending")),
        "confirmedTotal": Json::number(sum_field("confirmed")),
        "expenseTotal": Json::number(sum_field("expense")),
        "loanTotal": Json::number(sum_field("loan")),
        "totalOutflow": Json::number(sum_field("totalOutflow")),
      }),
      "byBu": Json::array([]),
      "byProj": Json::array([]),
    }),
    context.coverage,
  )
}

///|
async fn cashflow_detail_response(
  ym : String,
  bu_guid : String?,
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  if ym.length() != 7 || ym[4] != '-' {
    raise reject(422, "ym must use YYYY-MM")
  }
  let context = cashflow_context()
  let contracts : Map[String, String] = {}
  for row in context.rows.get_or_default("cb_contract", []) {
    contracts.set(
      report_text(row.payload, "contract_guid", row.record_id),
      report_text(row.payload, "proj_guid", ""),
    )
  }
  let plans : Array[Json] = []
  for row in context.rows.get_or_default("cb_htfkplan", []) {
    if cashflow_month(row.payload, "jhfk_date") == ym &&
      cashflow_scope(row.payload, bu_guid, proj_guid, contracts, true) {
      let contract = contracts.get_or_default(
        report_text(row.payload, "contract_guid", ""),
        "",
      )
      plans.push(
        Json::object({
          "htfk_plan_guid": Json::string(
            report_text(row.payload, "htfk_plan_guid", row.record_id),
          ),
          "plan_period": Json::string(
            report_text(row.payload, "plan_period", ""),
          ),
          "jhfk_date": Json::string(report_text(row.payload, "jhfk_date", "")),
          "jhfk_amount": Json::number(report_amount(row.payload, "jhfk_amount")),
          "approve_state": Json::string(
            report_text(row.payload, "approve_state", ""),
          ),
          "proj_guid": Json::string(contract),
        }),
      )
    }
  }
  let applies : Array[Json] = []
  for row in context.rows.get_or_default("cb_htfk_apply", []) {
    if cashflow_month(row.payload, "apply_date") == ym &&
      cashflow_scope(row.payload, bu_guid, proj_guid, contracts, false) {
      applies.push(
        Json::object({
          "htfk_apply_guid": Json::string(
            report_text(row.payload, "htfk_apply_guid", row.record_id),
          ),
          "apply_code": Json::string(report_text(row.payload, "apply_code", "")),
          "apply_date": Json::string(report_text(row.payload, "apply_date", "")),
          "apply_amount": Json::number(
            report_amount(row.payload, "apply_amount"),
          ),
          "apply_state": Json::string(
            report_text(row.payload, "apply_state", ""),
          ),
          "pay_state": Json::string(report_text(row.payload, "pay_state", "")),
          "subject": Json::string(report_text(row.payload, "subject", "")),
          "proj_guid": Json::string(report_text(row.payload, "proj_guid", "")),
        }),
      )
    }
  }
  cashflow_envelope(
    Json::object({
      "ym": Json::string(ym),
      "plans": Json::array(plans),
      "applies": Json::array(applies),
    }),
    context.coverage,
  )
}

///|
async fn cashflow_inflow_response(
  months : Int,
  bu_guid : String?,
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  let context = cashflow_context()
  let month_list = cashflow_months(months + 3, -3)
  let series = month_list.map(fn(month) {
    Json::object({
      "ym": Json::string(month),
      "received": Json::number(0),
      "expected": Json::number(0),
      "overdue": Json::number(0),
      "total": Json::number(0),
      "cumulative": Json::number(0),
    })
  })
  cashflow_envelope(
    Json::object({
      "months": Json::array(month_list.map(fn(value) { Json::string(value) })),
      "series": Json::array(series),
      "totals": Json::object({
        "receivedTotal": Json::number(0),
        "expectedTotal": Json::number(0),
        "overdueTotal": Json::number(0),
        "totalInflow": Json::number(0),
      }),
    }),
    context.coverage,
  )
}

///|
async fn cashflow_net_response(months : Int) -> Json raise CompanyServiceError {
  let forecast = cashflow_forecast_response(months, None, None)
  let data = json_field(forecast, "data").unwrap_or(Json::object({}))
  let rows = json_field(data, "series").unwrap_or(Json::array([]))
  let series : Array[Json] = []
  match rows {
    Array(values) =>
      for row in values {
        series.push(
          Json::object({
            "ym": json_field(row, "ym").unwrap_or(Json::string("")),
            "inflow": Json::number(0),
            "outflow": json_field(row, "totalOutflow").unwrap_or(
              Json::number(0),
            ),
            "net": Json::number(-report_amount(row, "totalOutflow")),
            "cumulativeNet": Json::number(0),
          }),
        )
      }
    _ => ()
  }
  cashflow_envelope(Json::object({ "series": Json::array(series) }), {
    "cb_htfkplan": 4,
    "cb_htfk_apply": 3,
    "cb_contract": 2,
    "sale_revenue": 0,
    "vcb_expense": 0,
    "vcb_loan_simple": 1,
    "cb_contract_milestone": 0,
    "cb_plan_version": 0,
    "cb_subject_dict": 0,
    "ep_project": 2,
    "mu_business_unit": 7,
  })
}

///|
async fn cashflow_gap_response(
  horizon_days : Int,
) -> Json raise CompanyServiceError {
  if horizon_days < 7 || horizon_days > 365 {
    raise reject(422, "horizonDays must be between 7 and 365")
  }
  let context = cashflow_context()
  cashflow_envelope(
    Json::object({
      "weeks": Json::array([]),
      "gapWeeks": Json::array([]),
      "totalGap": Json::number(0),
      "horizonDays": Json::number(horizon_days.to_double()),
    }),
    context.coverage,
  )
}

///|
async fn cashflow_v3_response(
  months : Int,
  proj_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(proj_guid) {
    raise reject(422, "invalid proj_guid")
  }
  let context = cashflow_context()
  let month_list = cashflow_months(months, 0)
  let series = month_list.map(fn(month) {
    Json::object({
      "ym": Json::string(month),
      "inflow": Json::number(0),
      "outflow": Json::number(0),
      "net": Json::number(0),
      "cumNet": Json::number(0),
      "gap": Json::number(0),
    })
  })
  cashflow_envelope(
    Json::object({
      "projGuid": Json::string(proj_guid),
      "planVersion": Json::string("baseline"),
      "months": Json::array(month_list.map(fn(value) { Json::string(value) })),
      "series": Json::array(series),
      "totals": Json::object({
        "A_total": Json::number(0),
        "D_total": Json::number(0),
        "E_total": Json::number(0),
        "FG_total": Json::number(0),
        "inflow_total": Json::number(0),
        "outflow_total": Json::number(0),
        "gap_total": Json::number(0),
      }),
    }),
    context.coverage,
  )
}
