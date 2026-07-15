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
        "isCurrent": Json::boolean(json_bool(row.payload, "is_current", false)),
        "creatorName": Json::string(creator_name),
        "createdAt": Json::string(report_text(row.payload, "created_at", "")),
        "remark": json_field(row.payload, "remark").unwrap_or(Json::null()),
        "sourceKind": Json::string("imported"),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    report_amount(right, "versionNo").compare(report_amount(left, "versionNo"))
  })
  investment_envelope(Json::array(rows), { "tzsy_version": versions.length() })
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
  investment_envelope(Json::array(data), { "tzsy_plan_index": rows.length() })
}

///|
async fn investment_profit_summary_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let versions = raw_source_rows("tzsy_version", 500).filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    json_bool(row.payload, "is_current", false)
  })
  if versions.is_empty() {
    return investment_envelope(Json::null(), {
      "tzsy_version": 0,
      "tzsy_plan_index": 0,
    })
  }
  let version = versions[0]
  let version_id = report_text(
    version.payload,
    "version_guid",
    version.record_id,
  )
  let rows = raw_source_rows("tzsy_plan_index", 500).filter(fn(row) {
    report_text(row.payload, "version_guid", "") == version_id &&
    json_field(row.payload, "deleted_at") is None
  })
  let values : Map[String, Double] = {}
  for row in rows {
    values.set(
      report_text(row.payload, "full_code", ""),
      report_amount(row.payload, "index_value"),
    )
  }
  let revenue = values.get_or_default("CO.Revenue", 0.0)
  let cost = values.get_or_default("CO.Cost", 0.0)
  let gross = values.get_or_default("CO.GrossProfit", 0.0)
  let net = values.get_or_default("CO.NetProfit", 0.0)
  investment_envelope(
    Json::object({
      "versionGuid": Json::string(version_id),
      "versionName": Json::string(
        report_text(version.payload, "version_name", ""),
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
      "sourceKind": Json::string("imported"),
    }),
    { "tzsy_version": versions.length(), "tzsy_plan_index": rows.length() },
  )
}

///|
async fn investment_sensitivity_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let versions = raw_source_rows("tzsy_version", 500).filter(fn(row) {
    report_text(row.payload, "proj_guid", "") == project_id &&
    json_bool(row.payload, "is_current", false)
  })
  if versions.is_empty() {
    return investment_envelope(
      Json::object({ "msg": Json::string("尚无激活版本") }),
      { "tzsy_version": 0, "tzsy_plan_index": 0 },
    )
  }
  let version_id = report_text(
    versions[0].payload,
    "version_guid",
    versions[0].record_id,
  )
  let rows = raw_source_rows("tzsy_plan_index", 500).filter(fn(row) {
    report_text(row.payload, "version_guid", "") == version_id
  })
  let mut sales = 0.0
  let mut cost = 1.0
  let mut tax = 0.0
  for row in rows {
    let name = report_text(row.payload, "index_name", "")
    if name.contains("售价") || name.contains("收入") {
      sales = report_amount(row.payload, "index_value")
    }
    if name.contains("成本") {
      cost = report_amount(row.payload, "index_value")
    }
    if name.contains("税") {
      tax = report_amount(row.payload, "index_value")
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
  investment_envelope(
    Json::object({
      "base": Json::object({
        "sales": Json::number(sales),
        "cost": Json::number(cost),
        "tax": Json::number(tax),
      }),
      "baseIrr": Json::number(irr(sales, cost, tax)),
      "cases": Json::array(cases),
    }),
    { "tzsy_version": versions.length(), "tzsy_plan_index": rows.length() },
  )
}

///|
async fn investment_profit_actual_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let tables = [
    "ep_project", "sys_user", "tzsy_version", "tzsy_excel_import", "tzsy_excel_sheet",
    "tzsy_profit_table", "tzsy_plan_line", "tzsy_subject_mapping",
  ]
  let coverage : Map[String, Int] = {}
  for table in tables {
    coverage.set(table, raw_source_rows(table, 5000).length())
  }
  let missing : Array[Json] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(Json::string(table))
    }
  }
  missing.sort_by(fn(left, right) {
    left.stringify().compare(right.stringify())
  })
  let project_exists = raw_source_rows("ep_project", 500).any(fn(row) {
    report_text(row.payload, "proj_guid", row.record_id) == project_id
  })
  if !project_exists {
    return (
      404,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(41001),
        "message": Json::string("项目不存在"),
        "source_coverage": report_coverage(coverage),
        "missing_or_empty_source_tables": Json::array(missing),
        "authorizing": Json::boolean(false),
        "persisted": Json::boolean(false),
        "provider_execution": Json::boolean(false),
        "simulation": Json::boolean(false),
      }),
    )
  }
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(41002),
      "message": Json::string("该项目暂无测算数据,无法对比"),
      "projectId": Json::string(project_id),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(missing),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "simulation": Json::boolean(false),
    }),
  )
}
