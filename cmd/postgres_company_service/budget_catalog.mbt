///|
async fn business_units_tree_response() -> Json raise CompanyServiceError {
  business_units_tree_from_rows(
    product_work_source_rows(business_unit_tree_sql()),
  )
}

///|
fn business_units_tree_from_rows(units : Array[SourceRow]) -> Json {
  let counts : Map[String, Int] = Map([])
  for row in units {
    let id = json_text(row.payload, "bu_guid", row.record_id)
    counts.set(id, counts.get(id).unwrap_or(0) + 1)
  }
  let diagnostics : Array[Json] = []
  let mismatched : Map[String, Unit] = Map([])
  for row in units {
    let id = json_text(row.payload, "bu_guid", row.record_id)
    if json_text(row.payload, "__unit_source_kind", "imported") == "command" &&
      json_text(row.payload, "__unit_aggregate_id", row.record_id) != id {
      mismatched.set(id, ())
      diagnostics.push({
        "code": "identity_mismatch",
        "buGuid": Json::string(id),
        "message": "Native unit payload identity does not match its stored identity",
      })
    }
  }
  for id, count in counts {
    if count > 1 {
      diagnostics.push({
        "code": "ambiguous_identity",
        "buGuid": Json::string(id),
        "message": "This business unit ID has competing sources and is omitted from selection",
      })
    }
  }
  let units = units.filter(row => {
    dashboard_active(row.payload) &&
    json_text(row.payload, "state", "") != "deleted" &&
    counts.get(json_text(row.payload, "bu_guid", row.record_id)) == Some(1) &&
    !mismatched.contains(json_text(row.payload, "bu_guid", row.record_id))
  })
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
  let parents : Map[String, String] = Map([])
  let roots : Array[Json] = []
  for row in units {
    if !dashboard_active(row.payload) {
      continue
    }
    let guid = report_text(row.payload, "bu_guid", row.record_id)
    if guid.is_empty() {
      continue
    }
    let name = report_text(row.payload, "bu_name", "")
    let node = Json::object({
      "buGuid": Json::string(guid),
      "buCode": Json::string(report_text(row.payload, "bu_code", "")),
      "buName": Json::string(name),
      "displayName": Json::string(if name.is_empty() { guid } else { name }),
      "parentGuid": Json::string(report_text(row.payload, "parent_guid", "")),
      "legalName": Json::string(report_text(row.payload, "legal_name", "")),
      "hierarchyCode": Json::string(
        report_text(row.payload, "hierarchy_code", ""),
      ),
      "level": Json::number(json_int(row.payload, "level", 0).to_double()),
      "buType": Json::string(report_text(row.payload, "bu_type", "")),
      "children": Json::array([]),
      "sourceKind": Json::string(
        json_text(row.payload, "__unit_source_kind", "imported"),
      ),
    })
    nodes.set(guid, node)
    parents.set(guid, report_text(row.payload, "parent_guid", ""))
  }
  let cycle_nodes : Map[String, Unit] = Map([])
  for guid, _ in parents {
    let visited : Map[String, Unit] = Map([])
    let mut current = guid
    while parents.contains(current) {
      if visited.contains(current) {
        let start = current
        cycle_nodes.set(start, ())
        current = parents.get(start).unwrap_or("")
        while current != start {
          cycle_nodes.set(current, ())
          current = parents.get(current).unwrap_or(start)
        }
        break
      }
      visited.set(current, ())
      current = parents.get(current).unwrap_or("")
    }
  }
  // Resolve parents after every node exists, preserving imported identifiers
  // and hierarchy even when source level/order metadata is incomplete.
  for row in units {
    let guid = report_text(row.payload, "bu_guid", row.record_id)
    let node = match nodes.get(guid) {
      Some(node) => node
      None => continue
    }
    let parent_guid = report_text(row.payload, "parent_guid", "")
    let issue = if cycle_nodes.contains(guid) {
      "cycle"
    } else if !parent_guid.is_empty() &&
      counts.get(parent_guid).unwrap_or(0) > 1 {
      "ambiguous_parent"
    } else if !parent_guid.is_empty() && !nodes.contains(parent_guid) {
      "missing_parent"
    } else {
      ""
    }
    if !issue.is_empty() {
      diagnostics.push({
        "code": Json::string(issue),
        "buGuid": Json::string(guid),
        "message": "Displayed as a root without changing its original parent identity",
      })
      match node {
        Object(values) => values.set("hierarchyIssue", Json::string(issue))
        _ => ()
      }
    }
    if cycle_nodes.contains(guid) {
      roots.push(node)
      continue
    }
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
    "source_kind": Json::string("imported_or_command"),
    "authorizing": Json::boolean(false),
    "diagnostics": Json::array(diagnostics),
    "source_coverage": Json::object({
      "mu_business_unit": Json::number(
        units
        .filter(row => {
          json_text(row.payload, "__unit_source_kind", "imported") == "imported"
        })
        .length()
        .to_double(),
      ),
      "organization_unit": Json::number(
        units
        .filter(row => {
          json_text(row.payload, "__unit_source_kind", "imported") == "command"
        })
        .length()
        .to_double(),
      ),
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
    "authorizing": Json::boolean(false),
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
    "authorizing": Json::boolean(false),
    "source_coverage": Json::object({
      "vys_proceeding": Json::number(raw.length().to_double()),
    }),
  })
}
