///|
/// Native source-backed investment observations.
///
/// Version, index, profit-summary, sensitivity, and profit-actual reads are
/// imported observations. They never activate a version, upload a workbook,
/// simulate an approved actual, or authorize valuation/accounting effects.
fn investment_dimension_rows() -> Array[Json] {
  [
    Json::object({
      "code": Json::string("key_point"),
      "name": Json::string("项目关键节点"),
      "icon": Json::string("📅"),
    }),
    Json::object({
      "code": Json::string("tax"),
      "name": Json::string("项目税费"),
      "icon": Json::string("💸"),
    }),
    Json::object({
      "code": Json::string("financing"),
      "name": Json::string("项目融资"),
      "icon": Json::string("🏦"),
    }),
    Json::object({
      "code": Json::string("investment"),
      "name": Json::string("项目投资及其他"),
      "icon": Json::string("💰"),
    }),
    Json::object({
      "code": Json::string("carry_over"),
      "name": Json::string("项目结转"),
      "icon": Json::string("📈"),
    }),
  ]
}

///|
fn investment_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  let missing : Array[Json] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(Json::string(table))
    }
  }
  missing.sort_by(fn(left, right) {
    left.stringify().compare(right.stringify())
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
async fn investment_versions_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let versions = raw_source_rows("tzsy_version", 500).filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    json_field(row.payload, "deleted_at") is None
  })
  let command_versions = investment_projection_payloads("investment_version").filter(fn(
      payload,
    ) {
      report_text(payload, "proj_guid", "") == project_id &&
      json_text(payload, "state", "active") != "deleted"
    },
  )
  let command_current = command_versions.any(fn(payload) {
    json_bool(payload, "is_current", false)
  })
  let users = raw_source_rows("sys_user", 500)
  let rows : Array[Json] = []
  for row in versions {
    let creator = report_text(row.payload, "created_by", "")
    let mut creator_name = ""
    for user in users {
      if report_text(user.payload, "user_id", user.record_id) == creator {
        creator_name = report_text(
          user.payload,
          "emp_name",
          report_text(user.payload, "user_name", ""),
        )
      }
    }
    rows.push(
      Json::object({
        "versionGuid": Json::string(
          report_text(row.payload, "version_guid", row.record_id),
        ),
        "versionName": Json::string(
          report_text(row.payload, "version_name", ""),
        ),
        "versionNo": Json::number(report_amount(row.payload, "version_no")),
        "isCurrent": Json::boolean(
          json_bool(row.payload, "is_current", false) && !command_current,
        ),
        "creatorName": Json::string(creator_name),
        "createdAt": Json::string(report_text(row.payload, "created_at", "")),
        "remark": json_field(row.payload, "remark").unwrap_or(Json::null()),
        "sourceKind": Json::string("imported"),
      }),
    )
  }
  for payload in command_versions {
    let creator = report_text(
      payload,
      "created_by",
      report_text(payload, "actor_user_id", ""),
    )
    let mut creator_name = ""
    for user in users {
      if report_text(user.payload, "user_id", user.record_id) == creator {
        creator_name = report_text(
          user.payload,
          "emp_name",
          report_text(user.payload, "user_name", ""),
        )
      }
    }
    rows.push(
      Json::object({
        "versionGuid": Json::string(report_text(payload, "version_guid", "")),
        "versionName": Json::string(report_text(payload, "version_name", "")),
        "versionNo": Json::number(json_number(payload, "version_no", 0.0)),
        "isCurrent": Json::boolean(json_bool(payload, "is_current", false)),
        "creatorName": Json::string(creator_name),
        "createdAt": Json::string(report_text(payload, "created_at", "")),
        "remark": json_field(payload, "remark").unwrap_or(Json::null()),
        "sourceKind": Json::string("command"),
        "commandProjection": Json::boolean(true),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    report_amount(right, "versionNo").compare(report_amount(left, "versionNo"))
  })
  if command_versions.is_empty() {
    investment_envelope(Json::array(rows), { "tzsy_version": versions.length() })
  } else {
    investment_command_envelope(
      Json::array(rows),
      { "tzsy_version": versions.length() },
      command_versions.length(),
    )
  }
}

///|
async fn investment_indices_response(
  version_id : String,
  dimension : String?,
) -> Json raise CompanyServiceError {
  if !valid_identifier(version_id) {
    raise reject(422, "invalid version_id")
  }
  match dimension {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid investment dimension")
    _ => ()
  }
  let rows = raw_source_rows("tzsy_plan_index", 500).filter(fn(row) {
    report_text(row.payload, "version_guid", "") == version_id &&
    json_field(row.payload, "deleted_at") is None &&
    (match dimension {
      Some(value) => report_text(row.payload, "dimension", "") == value
      None => true
    })
  })
  let command_rows = investment_projection_payloads("investment_index").filter(fn(
    payload,
  ) {
    report_text(payload, "version_guid", "") == version_id &&
    json_text(payload, "state", "active") != "deleted" &&
    (match dimension {
      Some(value) => report_text(payload, "dimension", "") == value
      None => true
    })
  })
  let groups : Map[String, Array[Json]] = {}
  for code in ["key_point", "tax", "financing", "investment", "carry_over"] {
    groups.set(code, [])
  }
  for row in rows {
    let payload = row.payload
    let code = report_text(payload, "dimension", "")
    let values = groups.get_or_default(code, [])
    values.push(
      Json::object({
        "indexGuid": Json::string(
          report_text(payload, "index_guid", row.record_id),
        ),
        "fullCode": Json::string(report_text(payload, "full_code", "")),
        "indexName": Json::string(report_text(payload, "index_name", "")),
        "parentCode": Json::string(report_text(payload, "parent_code", "")),
        "unit": Json::string(report_text(payload, "unit", "")),
        "indexValue": json_field(payload, "index_value").unwrap_or(Json::null()),
        "remark": json_field(payload, "remark").unwrap_or(Json::null()),
        "sourceKind": Json::string("imported"),
      }),
    )
    groups.set(code, values)
  }
  for payload in command_rows {
    let code = report_text(payload, "dimension", "")
    let values = groups.get_or_default(code, [])
    values.push(
      Json::object({
        "indexGuid": Json::string(report_text(payload, "index_guid", "")),
        "fullCode": Json::string(report_text(payload, "full_code", "")),
        "indexName": Json::string(report_text(payload, "index_name", "")),
        "parentCode": Json::string(report_text(payload, "parent_code", "")),
        "unit": Json::string(report_text(payload, "unit", "")),
        "indexValue": json_field(payload, "index_value").unwrap_or(Json::null()),
        "remark": json_field(payload, "remark").unwrap_or(Json::null()),
        "sourceKind": Json::string("command"),
        "commandProjection": Json::boolean(true),
      }),
    )
    groups.set(code, values)
  }
  let data : Array[Json] = []
  for dimension_row in investment_dimension_rows() {
    let code = report_text(dimension_row, "code", "")
    data.push(
      Json::object({
        "code": Json::string(code),
        "name": json_field(dimension_row, "name").unwrap_or(Json::string(code)),
        "icon": json_field(dimension_row, "icon").unwrap_or(Json::string("")),
        "items": Json::array(groups.get_or_default(code, [])),
      }),
    )
  }
  if command_rows.is_empty() {
    investment_envelope(Json::array(data), { "tzsy_plan_index": rows.length() })
  } else {
    investment_command_envelope(
      Json::array(data),
      { "tzsy_plan_index": rows.length() },
      command_rows.length(),
    )
  }
}

///|
async fn investment_profit_summary_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let version = investment_current_version_payload(project_id)
  if version is None {
    return investment_envelope(Json::null(), {
      "tzsy_version": 0,
      "tzsy_plan_index": 0,
    })
  }
  let version_payload = version.unwrap()
  let version_id = report_text(version_payload, "version_guid", "")
  let rows = investment_index_payloads(version_id)
  let command_indexes = investment_projection_payloads("investment_index").filter(fn(
      payload,
    ) {
      report_text(payload, "version_guid", "") == version_id &&
      json_text(payload, "state", "active") != "deleted"
    },
  )
  let values : Map[String, Double] = {}
  for payload in rows {
    values.set(
      report_text(payload, "full_code", ""),
      report_amount(payload, "index_value"),
    )
  }
  let revenue = values.get_or_default("CO.Revenue", 0.0)
  let cost = values.get_or_default("CO.Cost", 0.0)
  let gross = values.get_or_default("CO.GrossProfit", 0.0)
  let net = values.get_or_default("CO.NetProfit", 0.0)
  let data = Json::object({
    "versionGuid": Json::string(version_id),
    "versionName": Json::string(
      report_text(version_payload, "version_name", ""),
    ),
    "revenue": Json::number(revenue),
    "cost": Json::number(cost),
    "grossProfit": Json::number(gross),
    "netProfit": Json::number(net),
    "irr": Json::number(values.get_or_default("CO.IRR", 0.0)),
    "npv": Json::number(values.get_or_default("CO.NPV", 0.0)),
    "grossProfitMargin": Json::number(
      if revenue == 0.0 {
        0.0
      } else {
        round_places(gross / revenue * 100.0, 2)
      },
    ),
    "netProfitMargin": Json::number(
      if revenue == 0.0 {
        0.0
      } else {
        round_places(net / revenue * 100.0, 2)
      },
    ),
    "investment": Json::number(values.get_or_default("Inv.Total", 0.0)),
    "taxTotal": Json::number(values.get_or_default("Tax.Total", 0.0)),
    "finTotal": Json::number(values.get_or_default("Fin.Total", 0.0)),
    "sourceKind": Json::string(
      if json_text(version_payload, "source_kind", "") == "command" {
        "command"
      } else {
        "imported"
      },
    ),
  })
  let coverage = {
    "tzsy_version": raw_source_rows("tzsy_version", 500).length(),
    "tzsy_plan_index": raw_source_rows("tzsy_plan_index", 500).length(),
  }
  if json_text(version_payload, "source_kind", "") == "command" ||
    !command_indexes.is_empty() {
    investment_command_envelope(data, coverage, command_indexes.length() + 1)
  } else {
    investment_envelope(data, coverage)
  }
}

///|
async fn investment_sensitivity_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let version = investment_current_version_payload(project_id)
  if version is None {
    return investment_envelope(
      Json::object({ "msg": Json::string("尚无激活版本") }),
      { "tzsy_version": 0, "tzsy_plan_index": 0 },
    )
  }
  let version_payload = version.unwrap()
  let version_id = report_text(version_payload, "version_guid", "")
  let rows = investment_index_payloads(version_id)
  let command_indexes = investment_projection_payloads("investment_index").filter(fn(
      payload,
    ) {
      report_text(payload, "version_guid", "") == version_id &&
      json_text(payload, "state", "active") != "deleted"
    },
  )
  let mut sales = 0.0
  let mut cost = 1.0
  let mut tax = 0.0
  for payload in rows {
    let name = report_text(payload, "index_name", "")
    if name.contains("售价") || name.contains("收入") {
      sales = report_amount(payload, "index_value")
    }
    if name.contains("成本") {
      cost = report_amount(payload, "index_value")
    }
    if name.contains("税") {
      tax = report_amount(payload, "index_value")
    }
  }
  let irr = fn(s : Double, c : Double, t : Double) -> Double {
    if c <= 0.0 {
      return 0.0
    }
    let profit = s - c - t
    if profit <= 0.0 {
      return -100.0
    }
    let ratio = profit / c
    let mut root = 1.0
    for _ in 0..<12 {
      root = (4.0 * root + ratio / (root * root * root * root)) / 5.0
    }
    round_places((root - 1.0) * 100.0, 2)
  }
  let cases : Array[Json] = []
  for
    item in [
      ("基线", sales, cost, tax),
      ("售价 -5%", sales * 0.95, cost, tax),
      ("售价 -10%", sales * 0.90, cost, tax),
      ("成本 +5%", sales, cost * 1.05, tax),
      ("成本 +10%", sales, cost * 1.10, tax),
      ("税费 +5%", sales, cost, tax * 1.05),
    ] {
    cases.push(
      Json::object({
        "name": Json::string(item.0),
        "irr": Json::number(irr(item.1, item.2, item.3)),
      }),
    )
  }
  let data = Json::object({
    "base": Json::object({
      "sales": Json::number(sales),
      "cost": Json::number(cost),
      "tax": Json::number(tax),
    }),
    "baseIrr": Json::number(irr(sales, cost, tax)),
    "cases": Json::array(cases),
  })
  let coverage = {
    "tzsy_version": raw_source_rows("tzsy_version", 500).length(),
    "tzsy_plan_index": raw_source_rows("tzsy_plan_index", 500).length(),
  }
  if json_text(version_payload, "source_kind", "") == "command" ||
    !command_indexes.is_empty() {
    investment_command_envelope(data, coverage, command_indexes.length() + 1)
  } else {
    investment_envelope(data, coverage)
  }
}

///|
async fn investment_profit_actual_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  investment_actual_response_native(project_id)
}

///|
/// Source-compatible CBS hierarchy used by the designer's cost dashboard.
/// Missing CBS dictionaries are a successful empty observation: no synthetic
/// budget or accounting values are introduced by this read.
async fn investment_profit_actual_v2_response(
  project_id : String,
  plan_version : String?,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  match plan_version {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid plan_version")
    _ => ()
  }
  let tables = [
    "cb_change_apply", "cb_contract", "cb_expense_split", "cb_plan_version", "cb_r_master",
    "cb_subject_dict", "ep_project", "sale_revenue", "vcb_expense",
  ]
  let rows : Map[String, Array[SourceRow]] = {}
  let coverage : Map[String, Int] = {}
  for table in tables {
    let values = raw_source_rows(table, 5000)
    rows.set(table, values)
    coverage.set(table, values.length())
  }
  let mut project : SourceRow? = None
  for row in rows.get_or_default("ep_project", []) {
    if report_text(row.payload, "proj_guid", row.record_id) == project_id &&
      json_field(row.payload, "deleted_at") is None {
      project = Some(row)
    }
  }
  let project = match project {
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
        }),
      )
  }
  let mut active_version : Json? = None
  for row in rows.get_or_default("cb_plan_version", []) {
    if json_field(row.payload, "deleted_at") is None &&
      report_text(row.payload, "proj_guid", "") == project_id &&
      json_bool(row.payload, "is_active", false) {
      active_version = Some(row.payload)
    }
  }
  let selected_version = match plan_version {
    Some(value) => value
    None =>
      match active_version {
        Some(value) => report_text(value, "plan_version", "baseline")
        None => "baseline"
      }
  }
  let dict_rows = rows
    .get_or_default("cb_subject_dict", [])
    .filter(fn(row) {
      json_field(row.payload, "deleted_at") is None &&
      report_text(row.payload, "proj_guid", "") == project_id &&
      report_text(row.payload, "plan_version", "baseline") == selected_version
    })
  let contracts = rows
    .get_or_default("cb_contract", [])
    .filter(fn(row) {
      json_field(row.payload, "deleted_at") is None &&
      report_text(row.payload, "proj_guid", "") == project_id &&
      !report_text(row.payload, "r_code", "").is_empty()
    })
  let expenses : Map[String, Json] = {}
  for row in rows.get_or_default("vcb_expense", []) {
    let id = report_text(row.payload, "expense_guid", "")
    if !id.is_empty() {
      expenses.set(id, row.payload)
    }
  }
  let splits = rows.get_or_default("cb_expense_split", [])
  let changes = rows
    .get_or_default("cb_change_apply", [])
    .filter(fn(row) {
      json_field(row.payload, "deleted_at") is None &&
      report_text(row.payload, "proj_guid", "") == project_id
    })
  let r_names : Map[String, String] = {}
  for row in rows.get_or_default("cb_r_master", []) {
    if json_field(row.payload, "deleted_at") is None {
      let code = report_text(row.payload, "r_code", "")
      if !code.is_empty() {
        r_names.set(code, report_text(row.payload, "r_name", code))
      }
    }
  }
  let group_leaves : Map[String, Array[Json]] = {}
  let group_r : Map[String, String] = {}
  let group_l2_code : Map[String, String] = {}
  let group_l2 : Map[String, String] = {}
  let group_totals : Map[String, Map[String, Double]] = {}
  let r_order : Array[String] = []
  let r_totals : Map[String, Map[String, Double]] = {}
  fn add_total(target : Map[String, Double], key : String, value : Double) {
    target.set(key, target.get_or_default(key, 0.0) + value)
  }
  for row in dict_rows {
    let payload = row.payload
    let r_code = report_text(payload, "r_code", "")
    let l2_code = report_text(payload, "l2_code", "")
    let l3_code = report_text(payload, "l3_code", "")
    let group_key = r_code + "\u{1f}" + l2_code
    let a = report_amount(payload, "plan_amount")
    let mut d = 0.0
    let mut e = 0.0
    let mut g = 0.0
    for contract in contracts {
      let cp = contract.payload
      if report_text(cp, "l3_code", "") == l3_code {
        let amount = (
            report_amount(cp, "ht_amount") +
            report_amount(cp, "sum_alter_amount")
          ) /
          10000.0
        let state = report_text(cp, "cb_state", "")
        if state == "signed" || state == "paid" {
          d += amount
        } else if state == "approving" {
          e += amount
        }
      }
    }
    for split in splits {
      let sp = split.payload
      if report_text(sp, "l3_code", "") == l3_code {
        let expense = expenses.get_or_default(
          report_text(sp, "expense_guid", ""),
          Json::object({}),
        )
        let amount = report_amount(sp, "amount") / 10000.0
        let state = report_text(expense, "apply_state", "")
        if state == "approved" || state == "Approved" {
          d += amount
        } else if state == "approving" || state == "Approving" {
          e += amount
        }
      }
    }
    for change in changes {
      let cp = change.payload
      if report_text(cp, "l3_code", "") == l3_code {
        let amount = report_amount(cp, "change_amount") / 10000.0
        let state = report_text(cp, "state", "")
        if state == "confirmed" {
          d += amount
        } else if state == "estimated" || state == "approving" {
          g += amount
        }
      }
    }
    let f = if a - d - e > 0.0 { a - d - e } else { 0.0 }
    let b = d + e + f + g
    let values : Map[String, Double] = {
      "A": round_places(a, 2),
      "D": round_places(d, 2),
      "E": round_places(e, 2),
      "F": round_places(f, 2),
      "G": round_places(g, 2),
      "B": round_places(b, 2),
      "H": round_places(a - b, 2),
    }
    let leaf = Json::object({
      "l3Code": Json::string(l3_code),
      "subject": Json::string(report_text(payload, "subject", "")),
      "A": Json::number(values["A"]),
      "D": Json::number(values["D"]),
      "E": Json::number(values["E"]),
      "F": Json::number(values["F"]),
      "G": Json::number(values["G"]),
      "B": Json::number(values["B"]),
      "H": Json::number(values["H"]),
    })
    let leaves = group_leaves.get_or_default(group_key, [])
    leaves.push(leaf)
    group_leaves.set(group_key, leaves)
    group_r.set(group_key, r_code)
    group_l2_code.set(group_key, l2_code)
    group_l2.set(group_key, report_text(payload, "l2_name", l2_code))
    let group_values = group_totals.get_or_default(group_key, {})
    for key, value in values {
      add_total(group_values, key, value)
    }
    group_totals.set(group_key, group_values)
    let r_values = r_totals.get_or_default(r_code, {})
    for key, value in values {
      add_total(r_values, key, value)
    }
    r_totals.set(r_code, r_values)
    if !r_order.contains(r_code) {
      r_order.push(r_code)
    }
  }
  let output_rows : Array[Json] = []
  for r_code in r_order {
    let groups : Array[Json] = []
    for group_key, group_r_code in group_r {
      if group_r_code == r_code {
        let totals = group_totals.get_or_default(group_key, {})
        let group_fields : Map[String, Json] = {
          "l2Code": Json::string(group_l2_code.get_or_default(group_key, "")),
          "l2Name": Json::string(group_l2.get_or_default(group_key, "")),
          "leaves": Json::array(group_leaves.get_or_default(group_key, [])),
        }
        for key in ["A", "D", "E", "F", "G", "B", "H"] {
          group_fields.set(
            key,
            Json::number(round_places(totals.get_or_default(key, 0.0), 2)),
          )
        }
        groups.push(Json::object(group_fields))
      }
    }
    let totals = r_totals.get_or_default(r_code, {})
    let fields : Map[String, Json] = {
      "rCode": Json::string(r_code),
      "rName": Json::string(r_names.get_or_default(r_code, r_code)),
      "groups": Json::array(groups),
    }
    for key in ["A", "D", "E", "F", "G", "B", "H"] {
      fields.set(
        key,
        Json::number(round_places(totals.get_or_default(key, 0.0), 2)),
      )
    }
    output_rows.push(Json::object(fields))
  }
  let revenue_total = rows
    .get_or_default("sale_revenue", [])
    .fold(init=0.0, fn(total, row) {
      if json_field(row.payload, "deleted_at") is None &&
        report_text(row.payload, "proj_guid", "") == project_id &&
        report_text(row.payload, "status", "") == "received" {
        total + report_amount(row.payload, "amount") / 10000.0
      } else {
        total
      }
    })
  if !output_rows.is_empty() || revenue_total != 0.0 {
    output_rows.insert(
      0,
      Json::object({
        "rCode": Json::string("R6"),
        "rName": Json::string(r_names.get_or_default("R6", "回款额")),
        "A": Json::number(0.0),
        "D": Json::number(round_places(revenue_total, 2)),
        "E": Json::number(0.0),
        "F": Json::number(0.0),
        "G": Json::number(0.0),
        "B": Json::number(round_places(revenue_total, 2)),
        "H": Json::number(0.0),
        "groups": Json::array([]),
      }),
    )
  }
  let r0_total = contracts.fold(init=0.0, fn(total, row) {
    let code = report_text(row.payload, "r_code", "")
    if code.is_empty() || code == "R0" {
      total +
      (
        report_amount(row.payload, "ht_amount") +
        report_amount(row.payload, "sum_alter_amount")
      ) /
      10000.0
    } else {
      total
    }
  })
  if r0_total != 0.0 {
    output_rows.push(
      Json::object({
        "rCode": Json::string("R0"),
        "rName": Json::string("未归类(R0 兜底)"),
        "A": Json::number(0.0),
        "D": Json::number(round_places(r0_total, 2)),
        "E": Json::number(0.0),
        "F": Json::number(0.0),
        "G": Json::number(0.0),
        "B": Json::number(round_places(r0_total, 2)),
        "H": Json::number(round_places(-r0_total, 2)),
        "groups": Json::array([]),
      }),
    )
  }
  let target_total = output_rows.fold(init=0.0, fn(total, row) {
    if report_text(row, "rCode", "") == "R6" ||
      report_text(row, "rCode", "") == "R0" {
      total
    } else {
      total + report_amount(row, "A")
    }
  })
  let dynamic_total = output_rows.fold(init=0.0, fn(total, row) {
    if report_text(row, "rCode", "") == "R6" ||
      report_text(row, "rCode", "") == "R0" {
      total
    } else {
      total + report_amount(row, "B")
    }
  })
  let summary = Json::object({
    "targetCost": Json::number(round_places(target_total, 2)),
    "dynamicCost": Json::number(round_places(dynamic_total, 2)),
    "deviationPct": if target_total > 0.0 {
      Json::number(
        round_places((target_total - dynamic_total) / target_total * 100.0, 4),
      )
    } else {
      Json::null()
    },
  })
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "projGuid": Json::string(project_id),
        "projName": Json::string(
          report_text(project.payload, "proj_name", project_id),
        ),
        "planVersion": Json::string(selected_version),
        "asOf": Json::string("imported"),
        "rows": Json::array(output_rows),
        "summary": summary,
        "counts": Json::object({
          "leaves": Json::number(dict_rows.length().to_double()),
          "contracts": Json::number(contracts.length().to_double()),
          "expenses": Json::number(splits.length().to_double()),
          "changes": Json::number(changes.length().to_double()),
        }),
      }),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(report_missing(coverage)),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
    }),
  )
}
