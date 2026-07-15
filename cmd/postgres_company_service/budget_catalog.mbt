///|
async fn business_units_tree_response() -> Json raise CompanyServiceError {
  let units = raw_source_rows("mu_business_unit", 500)
  units.sort_by(fn(left, right) {
    let level_order = json_int(left.payload, "level", 0).compare(
      json_int(right.payload, "level", 0),
    )
    if level_order == 0 {
      report_text(left.payload, "bu_code", "").compare(
        report_text(right.payload, "bu_code", ""),
      )
    } else {
      level_order
    }
  })
  let nodes : Map[String, Json] = {}
  let roots : Array[Json] = []
  for row in units {
    if !dashboard_active(row.payload) {
      continue
    }
    let guid = report_text(row.payload, "bu_guid", row.record_id)
    if guid.is_empty() {
      continue
    }
    let node = Json::object({
      "buGuid": Json::string(guid),
      "buCode": Json::string(report_text(row.payload, "bu_code", "")),
      "buName": Json::string(report_text(row.payload, "bu_name", "")),
      "legalName": Json::string(report_text(row.payload, "legal_name", "")),
      "hierarchyCode": Json::string(
        report_text(row.payload, "hierarchy_code", ""),
      ),
      "level": Json::number(json_int(row.payload, "level", 0).to_double()),
      "buType": Json::string(report_text(row.payload, "bu_type", "")),
      "children": Json::array([]),
      "sourceKind": Json::string("imported"),
    })
    nodes.set(guid, node)
    let parent_guid = report_text(row.payload, "parent_guid", "")
    match nodes.get(parent_guid) {
      Some(Object(parent_fields)) =>
        match parent_fields.get("children") {
          Some(Array(children)) => children.push(node)
          _ => ()
        }
      _ => roots.push(node)
    }
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(roots),
    "source_kind": Json::string("imported"),
    "source_coverage": Json::object({
      "mu_business_unit": Json::number(units.length().to_double()),
    }),
  })
}

///|
async fn budget_cost_subjects_response() -> Json raise CompanyServiceError {
  let raw = raw_source_rows("my_biz_param_option", 500)
  let options = raw.filter(fn(row) {
    report_text(row.payload, "param_name", "") == "cost_subject" &&
    json_bool(row.payload, "enabled", false)
  })
  options.sort_by(fn(left, right) {
    let order = json_int(left.payload, "display_order", 0).compare(
      json_int(right.payload, "display_order", 0),
    )
    if order == 0 {
      report_text(left.payload, "param_code", "").compare(
        report_text(right.payload, "param_code", ""),
      )
    } else {
      order
    }
  })
  let data = options.map(fn(row) {
    Json::object({
      "code": Json::string(report_text(row.payload, "param_code", "")),
      "name": Json::string(report_text(row.payload, "param_value", "")),
      "sourceKind": Json::string("imported"),
    })
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(data),
    "source_kind": Json::string("imported"),
    "source_coverage": Json::object({
      "my_biz_param_option": Json::number(raw.length().to_double()),
    }),
  })
}

///|
async fn budget_proceedings_response() -> Json raise CompanyServiceError {
  let raw = raw_source_rows("vys_proceeding", 500)
  let proceedings = raw.filter(fn(row) {
    json_bool(row.payload, "enabled", false)
  })
  proceedings.sort_by(fn(left, right) {
    let code_order = report_text(left.payload, "proceeding_code", "").compare(
      report_text(right.payload, "proceeding_code", ""),
    )
    if code_order == 0 {
      report_text(left.payload, "proceeding_guid", "").compare(
        report_text(right.payload, "proceeding_guid", ""),
      )
    } else {
      code_order
    }
  })
  let data = proceedings.map(fn(row) {
    Json::object({
      "guid": Json::string(report_text(row.payload, "proceeding_guid", "")),
      "code": Json::string(report_text(row.payload, "proceeding_code", "")),
      "name": Json::string(report_text(row.payload, "proceeding_name", "")),
      "sourceKind": Json::string("imported"),
    })
  })
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": Json::array(data),
    "source_kind": Json::string("imported"),
    "source_coverage": Json::object({
      "vys_proceeding": Json::number(raw.length().to_double()),
    }),
  })
}
