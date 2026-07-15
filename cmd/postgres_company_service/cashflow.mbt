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
  let units = context.rows.get_or_default("mu_business_unit", [])
  let projects = context.rows.get_or_default("ep_project", [])
  let month_list = cashflow_months(months, 0)
  let series : Map[String, Map[String, Double]] = {}
  let by_bu : Map[String, Double] = {}
  let by_proj : Map[String, Double] = {}
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
          let amount = report_amount(row.payload, "jhfk_amount")
          values.set("planned", values.get_or_default("planned", 0.0) + amount)
          series.set(month, values)
          let bu_guid = report_text(row.payload, "bu_guid", "")
          by_bu.set(bu_guid, by_bu.get_or_default(bu_guid, 0.0) + amount)
          let project_guid = contracts.get_or_default(
            report_text(row.payload, "contract_guid", ""),
            "",
          )
          if !project_guid.is_empty() {
            by_proj.set(
              project_guid,
              by_proj.get_or_default(project_guid, 0.0) + amount,
            )
          }
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
  for row in context.rows.get_or_default("vcb_expense", []) {
    if cashflow_scope(row.payload, bu_guid, proj_guid, contracts, false) {
      let month = cashflow_month(row.payload, "apply_date")
      match series.get(month) {
        Some(values) if report_text(row.payload, "apply_state", "") ==
          "Approved" &&
          report_text(row.payload, "pay_state", "") != "完全支付" => {
          values.set(
            "expense",
            values.get_or_default("expense", 0.0) +
            report_amount(row.payload, "pay_amount"),
          )
          series.set(month, values)
        }
        _ => ()
      }
    }
  }
  for row in context.rows.get_or_default("vcb_loan_simple", []) {
    if cashflow_scope(row.payload, bu_guid, proj_guid, contracts, false) {
      let month = cashflow_month(row.payload, "apply_date")
      let amount = report_amount(row.payload, "remain_amount")
      match series.get(month) {
        Some(values) if report_text(row.payload, "apply_state", "") ==
          "Approved" &&
          amount > 0.0 => {
          values.set("loan", values.get_or_default("loan", 0.0) + amount)
          series.set(month, values)
        }
        _ => ()
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
  let by_bu_rows : Array[Json] = []
  for bu_guid, amount in by_bu {
    let name = match source_payload(units, "bu_guid", bu_guid) {
      Some(value) => report_text(value, "bu_name", bu_guid)
      None => bu_guid
    }
    by_bu_rows.push(
      Json::object({
        "buGuid": Json::string(bu_guid),
        "buName": Json::string(name),
        "amount": Json::number(amount),
      }),
    )
  }
  by_bu_rows.sort_by(fn(left, right) {
    let order = json_number(right, "amount", 0.0).compare(
      json_number(left, "amount", 0.0),
    )
    if order == 0 {
      json_text(left, "buGuid", "").lexical_compare(
        json_text(right, "buGuid", ""),
      )
    } else {
      order
    }
  })
  let by_proj_rows : Array[Json] = []
  for project_guid, amount in by_proj {
    let name = match source_payload(projects, "proj_guid", project_guid) {
      Some(value) => report_text(value, "proj_name", project_guid)
      None => project_guid
    }
    by_proj_rows.push(
      Json::object({
        "projGuid": Json::string(project_guid),
        "projName": Json::string(name),
        "amount": Json::number(amount),
      }),
    )
  }
  by_proj_rows.sort_by(fn(left, right) {
    let order = json_number(right, "amount", 0.0).compare(
      json_number(left, "amount", 0.0),
    )
    if order == 0 {
      json_text(left, "projGuid", "").lexical_compare(
        json_text(right, "projGuid", ""),
      )
    } else {
      order
    }
  })
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
      "byBu": Json::array(
        if by_bu_rows.length() > 5 {
          by_bu_rows[0:5].to_owned()
        } else {
          by_bu_rows
        },
      ),
      "byProj": Json::array(
        if by_proj_rows.length() > 5 {
          by_proj_rows[0:5].to_owned()
        } else {
          by_proj_rows
        },
      ),
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
  if months < 1 || months > 24 {
    raise reject(422, "months must be between 1 and 24")
  }
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
  let month_list = cashflow_months(months + 3, -3)
  let month_set : Map[String, Bool] = {}
  let series_values : Map[String, Map[String, Double]] = {}
  for month in month_list {
    month_set.set(month, true)
    series_values.set(month, {
      "received": 0.0,
      "expected": 0.0,
      "overdue": 0.0,
    })
  }
  let today = @env.now().to_string()[0:10].to_owned()
  for row in context.rows.get_or_default("sale_revenue", []) {
    if !dashboard_active(row.payload) {
      continue
    }
    if bu_guid is Some(value) &&
      report_text(row.payload, "bu_guid", "") != value {
      continue
    }
    if proj_guid is Some(value) &&
      report_text(row.payload, "proj_guid", "") != value {
      continue
    }
    let month = cashflow_month(row.payload, "receive_date")
    if !month_set.contains(month) {
      continue
    }
    let state = report_text(row.payload, "status", "")
    let receive_date = report_text(row.payload, "receive_date", "")
    let normalized_state = if state == "expected" &&
      receive_date.length() >= 10 &&
      receive_date[0:10].to_owned() < today {
      "overdue"
    } else {
      state
    }
    if normalized_state == "received" ||
      normalized_state == "expected" ||
      normalized_state == "overdue" {
      match series_values.get(month) {
        Some(values) => {
          values.set(
            normalized_state,
            values.get_or_default(normalized_state, 0.0) +
            report_amount(row.payload, "amount"),
          )
          series_values.set(month, values)
        }
        None => ()
      }
    }
  }
  let mut cumulative = 0.0
  let series : Array[Json] = []
  for month in month_list {
    let values = series_values.get_or_default(month, {})
    let received = values.get_or_default("received", 0.0)
    let expected = values.get_or_default("expected", 0.0)
    let overdue = values.get_or_default("overdue", 0.0)
    let total = received + expected + overdue
    cumulative += total
    series.push(
      Json::object({
        "ym": Json::string(month),
        "received": Json::number(received),
        "expected": Json::number(expected),
        "overdue": Json::number(overdue),
        "total": Json::number(round_places(total, 2)),
        "cumulative": Json::number(round_places(cumulative, 2)),
      }),
    )
  }
  let sum_field = fn(key : String) -> Double {
    series.fold(init=0.0, fn(sum, row) { sum + report_amount(row, key) })
  }
  cashflow_envelope(
    Json::object({
      "months": Json::array(month_list.map(fn(value) { Json::string(value) })),
      "series": Json::array(series),
      "totals": Json::object({
        "receivedTotal": Json::number(sum_field("received")),
        "expectedTotal": Json::number(sum_field("expected")),
        "overdueTotal": Json::number(sum_field("overdue")),
        "totalInflow": Json::number(sum_field("total")),
      }),
    }),
    context.coverage,
  )
}

///|
async fn cashflow_net_response(months : Int) -> Json raise CompanyServiceError {
  if months < 1 || months > 24 {
    raise reject(422, "months must be between 1 and 24")
  }
  let context = cashflow_context()
  let forecast = cashflow_forecast_response(months, None, None)
  let data = json_field(forecast, "data").unwrap_or(Json::object({}))
  let rows = json_field(data, "series").unwrap_or(Json::array([]))
  let revenue_by_month : Map[String, Double] = {}
  for row in context.rows.get_or_default("sale_revenue", []) {
    if dashboard_active(row.payload) {
      let month = cashflow_month(row.payload, "receive_date")
      revenue_by_month.set(
        month,
        revenue_by_month.get_or_default(month, 0.0) +
        report_amount(row.payload, "amount"),
      )
    }
  }
  let series : Array[Json] = []
  let mut cumulative = 0.0
  match rows {
    Array(values) =>
      for row in values {
        let month = json_text(row, "ym", "")
        let inflow = revenue_by_month.get_or_default(month, 0.0)
        let outflow = report_amount(row, "planned") +
          report_amount(row, "pending")
        let net = inflow - outflow
        cumulative += net
        series.push(
          Json::object({
            "ym": Json::string(month),
            "inflow": Json::number(round_places(inflow, 2)),
            "outflow": Json::number(round_places(outflow, 2)),
            "net": Json::number(round_places(net, 2)),
            "cumulativeNet": Json::number(round_places(cumulative, 2)),
          }),
        )
      }
    _ => ()
  }
  cashflow_envelope(
    Json::object({ "series": Json::array(series) }),
    context.coverage,
  )
}

///|
fn cashflow_date_parts(value : String) -> (Int, Int, Int)? {
  if value.length() < 10 || value[4:5] != "-" || value[7:8] != "-" {
    return None
  }
  let year = parse_decimal(value[0:4].to_owned()) catch { _ => -1 }
  let month = parse_decimal(value[5:7].to_owned()) catch { _ => -1 }
  let day = parse_decimal(value[8:10].to_owned()) catch { _ => -1 }
  if year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > plan_days_in_month(year, month) {
    None
  } else {
    Some((year, month, day))
  }
}

///|
fn cashflow_week_start(value : String) -> String {
  match cashflow_date_parts(value) {
    Some((year, month, day)) => {
      let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
      let adjusted_year = if month < 3 { year - 1 } else { year }
      let weekday = (
          adjusted_year +
          adjusted_year / 4 -
          adjusted_year / 100 +
          adjusted_year / 400 +
          offsets[month - 1] +
          day
        ) %
        7
      let days_back = if weekday == 0 { 6 } else { weekday - 1 }
      plan_shift_date(value[:10].to_owned(), -days_back) catch {
        _ => ""
      }
    }
    None => ""
  }
}

///|
async fn cashflow_gap_response(
  horizon_days : Int,
) -> Json raise CompanyServiceError {
  if horizon_days < 7 || horizon_days > 365 {
    raise reject(422, "horizonDays must be between 7 and 365")
  }
  let context = cashflow_context()
  let today = @env.now().to_string()[0:10].to_owned()
  let end_date = plan_shift_date(today, horizon_days)
  let contracts : Map[String, String] = {}
  for row in context.rows.get_or_default("cb_contract", []) {
    if dashboard_active(row.payload) {
      contracts.set(
        report_text(row.payload, "contract_guid", row.record_id),
        report_text(row.payload, "contract_name", ""),
      )
    }
  }
  let buckets : Map[String, Map[String, Double]] = {}
  let out_items : Map[String, Array[Json]] = {}
  let in_items : Map[String, Array[Json]] = {}
  for row in context.rows.get_or_default("cb_contract_milestone", []) {
    if !dashboard_active(row.payload) ||
      report_text(row.payload, "trigger_type", "") != "time" ||
      !["pending", "reached"].contains(report_text(row.payload, "state", "")) {
      continue
    }
    let date_value = report_text(row.payload, "plan_date", "")
    let normalized_day = if date_value.length() >= 10 {
      date_value[:10].to_owned()
    } else {
      ""
    }
    if cashflow_date_parts(normalized_day) is None ||
      normalized_day < today ||
      normalized_day > end_date {
      continue
    }
    let week = cashflow_week_start(normalized_day)
    if week.is_empty() {
      continue
    }
    let amount = report_amount(row.payload, "plan_amount")
    let values = buckets.get_or_default(week, { "in": 0.0, "out": 0.0 })
    values.set("out", values.get_or_default("out", 0.0) + amount)
    buckets.set(week, values)
    let items = out_items.get_or_default(week, [])
    items.push(
      Json::object({
        "subject": Json::string(
          contracts.get_or_default(
            report_text(row.payload, "contract_guid", ""),
            "",
          ),
        ),
        "amount": Json::number(round_places(amount, 2)),
        "kind": Json::string("milestone"),
      }),
    )
    out_items.set(week, items)
  }
  for row in context.rows.get_or_default("sale_revenue", []) {
    if !dashboard_active(row.payload) ||
      report_text(row.payload, "status", "") != "pending" {
      continue
    }
    let date_value = report_text(row.payload, "receive_date", "")
    let normalized_day = if date_value.length() >= 10 {
      date_value[:10].to_owned()
    } else {
      ""
    }
    if normalized_day.is_empty() ||
      normalized_day < today ||
      normalized_day > end_date {
      continue
    }
    let week = cashflow_week_start(normalized_day)
    if week.is_empty() {
      continue
    }
    let amount = report_amount(row.payload, "amount")
    let values = buckets.get_or_default(week, { "in": 0.0, "out": 0.0 })
    values.set("in", values.get_or_default("in", 0.0) + amount)
    buckets.set(week, values)
    let items = in_items.get_or_default(week, [])
    items.push(
      Json::object({
        "subject": Json::string(report_text(row.payload, "customer_name", "")),
        "amount": Json::number(round_places(amount, 2)),
      }),
    )
    in_items.set(week, items)
  }
  let week_keys : Array[String] = []
  for week, _ in buckets {
    week_keys.push(week)
  }
  week_keys.sort_by(fn(left, right) { left.compare(right) })
  let weeks : Array[Json] = []
  let gap_weeks : Array[Json] = []
  let mut total_gap = 0.0
  for week in week_keys {
    let values = buckets.get_or_default(week, {})
    let incoming = values.get_or_default("in", 0.0)
    let outgoing = values.get_or_default("out", 0.0)
    let gap = round_places(outgoing - incoming, 2)
    let item = Json::object({
      "weekStart": Json::string(week),
      "in": Json::number(incoming),
      "out": Json::number(outgoing),
      "outItems": Json::array(out_items.get_or_default(week, [])),
      "inItems": Json::array(in_items.get_or_default(week, [])),
      "gap": Json::number(gap),
      "alert": Json::boolean(gap > 0.0),
    })
    weeks.push(item)
    if gap > 0.0 {
      gap_weeks.push(item)
      total_gap += gap
    }
  }
  cashflow_envelope(
    Json::object({
      "weeks": Json::array(weeks),
      "gapWeeks": Json::array(gap_weeks),
      "totalGap": Json::number(round_places(total_gap, 2)),
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
  if months < 1 || months > 24 {
    raise reject(422, "months must be between 1 and 24")
  }
  if !valid_identifier(proj_guid) {
    raise reject(422, "invalid proj_guid")
  }
  let context = cashflow_context()
  let month_list = cashflow_months(months, 0)
  let versions = context.rows
    .get_or_default("cb_plan_version", [])
    .filter(fn(row) {
      dashboard_active(row.payload) &&
      report_text(row.payload, "proj_guid", "") == proj_guid
    })
  let mut first_plan_version = ""
  let mut active_plan_version = ""
  for row in versions {
    let value = report_text(row.payload, "plan_version", "baseline")
    if first_plan_version.is_empty() {
      first_plan_version = value
    }
    if json_bool(row.payload, "is_active", false) &&
      active_plan_version.is_empty() {
      active_plan_version = value
    }
  }
  let plan_version = if !active_plan_version.is_empty() {
    active_plan_version
  } else if !first_plan_version.is_empty() {
    first_plan_version
  } else {
    "baseline"
  }
  let leaves = context.rows
    .get_or_default("cb_subject_dict", [])
    .filter(fn(row) {
      dashboard_active(row.payload) &&
      report_text(row.payload, "proj_guid", "") == proj_guid &&
      report_text(row.payload, "plan_version", "baseline") == plan_version
    })
  let contracts = context.rows
    .get_or_default("cb_contract", [])
    .filter(fn(row) {
      dashboard_active(row.payload) &&
      report_text(row.payload, "proj_guid", "") == proj_guid &&
      ["signed", "paid", "approving"].contains(
        report_text(row.payload, "cb_state", ""),
      )
    })
  let total_a = leaves.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row.payload, "plan_amount")
  })
  let total_d = contracts.fold(init=0.0, fn(sum, row) {
    if ["signed", "paid"].contains(report_text(row.payload, "cb_state", "")) {
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
  let total_e = contracts.fold(init=0.0, fn(sum, row) {
    if report_text(row.payload, "cb_state", "") == "approving" {
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
  let total_fg_base = leaves.fold(init=0.0, fn(sum, row) {
    let amount = report_amount(row.payload, "plan_amount")
    let positive = if amount > 0.0 { amount } else { 0.0 }
    sum + positive
  })
  let total_fg = if total_fg_base - total_d - total_e > 0.0 {
    total_fg_base - total_d - total_e + total_d * 0.05
  } else {
    total_d * 0.05
  }
  let revenue_by_month : Map[String, Double] = {}
  for row in context.rows.get_or_default("sale_revenue", []) {
    if dashboard_active(row.payload) &&
      report_text(row.payload, "proj_guid", "") == proj_guid &&
      report_text(row.payload, "status", "") == "expected" {
      let month = cashflow_month(row.payload, "receive_date")
      revenue_by_month.set(
        month,
        revenue_by_month.get_or_default(month, 0.0) +
        report_amount(row.payload, "amount") / 10000.0,
      )
    }
  }
  let fg_monthly = total_fg / months.to_double()
  let mut cumulative = 0.0
  let series : Array[Json] = []
  for index in 0..<month_list.length() {
    let month = month_list[index]
    let inflow = revenue_by_month.get_or_default(month, 0.0)
    let outflow = (if index == 0 { total_e } else { 0.0 }) + fg_monthly
    let net = inflow - outflow
    cumulative += net
    let gap = if cumulative < 0.0 { -cumulative } else { 0.0 }
    series.push(
      Json::object({
        "ym": Json::string(month),
        "inflow": Json::number(round_places(inflow, 2)),
        "outflow": Json::number(round_places(outflow, 2)),
        "net": Json::number(round_places(net, 2)),
        "cumNet": Json::number(round_places(cumulative, 2)),
        "gap": Json::number(round_places(gap, 2)),
      }),
    )
  }
  let sum_field = fn(key : String) -> Double {
    series.fold(init=0.0, fn(sum, row) { sum + report_amount(row, key) })
  }
  cashflow_envelope(
    Json::object({
      "projGuid": Json::string(proj_guid),
      "planVersion": Json::string(plan_version),
      "months": Json::array(month_list.map(fn(value) { Json::string(value) })),
      "series": Json::array(series),
      "totals": Json::object({
        "A_total": Json::number(round_places(total_a, 2)),
        "D_total": Json::number(round_places(total_d, 2)),
        "E_total": Json::number(round_places(total_e, 2)),
        "FG_total": Json::number(round_places(total_fg, 2)),
        "inflow_total": Json::number(round_places(sum_field("inflow"), 2)),
        "outflow_total": Json::number(round_places(sum_field("outflow"), 2)),
        "gap_total": Json::number(round_places(sum_field("gap"), 2)),
      }),
    }),
    context.coverage,
  )
}
