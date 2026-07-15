///|
/// Native source-backed CBS observation reads.
fn cbs_tables() -> Array[String] {
  [
    "cb_change_apply", "cb_contract", "cb_expense_split", "cb_plan_version", "cb_r_master",
    "cb_subject_dict", "vcb_expense", "wf_approval_rule",
  ]
}

///|
async fn cbs_rows() -> Map[String, Array[SourceRow]] raise CompanyServiceError {
  let rows : Map[String, Array[SourceRow]] = {}
  for table in cbs_tables() {
    rows.set(table, raw_source_rows(table, 500))
  }
  rows
}

///|
fn cbs_coverage(rows : Map[String, Array[SourceRow]]) -> Map[String, Int] {
  let coverage : Map[String, Int] = {}
  for table in cbs_tables() {
    coverage.set(table, rows.get_or_default(table, []).length())
  }
  coverage
}

///|
fn cbs_missing(coverage : Map[String, Int]) -> Array[Json] {
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
fn cbs_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(cbs_missing(coverage)),
    "authorizing": Json::boolean(false),
  })
}

///|
fn cbs_filter_project(payload : Json, proj_guid : String?) -> Bool {
  match proj_guid {
    Some(value) => report_text(payload, "proj_guid", "") == value
    None => true
  }
}

///|
async fn cbs_r_master_response() -> Json raise CompanyServiceError {
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let items : Array[Json] = []
  for row in rows.get_or_default("cb_r_master", []) {
    if json_field(row.payload, "deleted_at") is None {
      items.push(
        Json::object({
          "r_code": Json::string(report_text(row.payload, "r_code", "")),
          "r_name": Json::string(report_text(row.payload, "r_name", "")),
          "r_kind": Json::string(report_text(row.payload, "r_kind", "")),
          "formula": Json::string(report_text(row.payload, "formula", "")),
          "display_order": Json::number(
            report_amount(row.payload, "display_order"),
          ),
          "is_live": Json::boolean(json_bool(row.payload, "is_live", true)),
        }),
      )
    }
  }
  cbs_envelope(Json::array(items), coverage)
}

///|
async fn cbs_dict_response(
  proj_guid : String,
  plan_version : String?,
  r_code : String?,
) -> Json raise CompanyServiceError {
  if !valid_identifier(proj_guid) {
    raise reject(422, "invalid proj_guid")
  }
  match plan_version {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid plan_version")
    _ => ()
  }
  match r_code {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid r_code")
    _ => ()
  }
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let version = match plan_version {
    Some(value) => value
    None => "baseline"
  }
  let items : Array[Json] = []
  for row in rows.get_or_default("cb_subject_dict", []) {
    if json_field(row.payload, "deleted_at") is None &&
      cbs_filter_project(row.payload, Some(proj_guid)) &&
      report_text(row.payload, "plan_version", "baseline") == version &&
      (match r_code {
        Some(value) => report_text(row.payload, "r_code", "") == value
        None => true
      }) {
      items.push(
        Json::object({
          "dict_guid": Json::string(
            report_text(row.payload, "dict_guid", row.record_id),
          ),
          "l3_code": Json::string(report_text(row.payload, "l3_code", "")),
          "r_code": Json::string(report_text(row.payload, "r_code", "")),
          "l2_code": Json::string(report_text(row.payload, "l2_code", "")),
          "l2_name": Json::string(report_text(row.payload, "l2_name", "")),
          "subject": Json::string(report_text(row.payload, "subject", "")),
          "plan_amount": Json::number(report_amount(row.payload, "plan_amount")),
          "src": Json::string(report_text(row.payload, "src", "")),
        }),
      )
    }
  }
  let local_rows = cbs_projection_payloads("cbs_subject_dict")
  for payload in local_rows {
    if json_text(payload, "state", "active") != "deleted" &&
      cbs_filter_project(payload, Some(proj_guid)) &&
      report_text(payload, "plan_version", "") == version &&
      (match r_code {
        Some(value) => report_text(payload, "r_code", "") == value
        None => true
      }) {
      items.push(
        Json::object({
          "dict_guid": Json::string(report_text(payload, "dict_guid", "")),
          "l3_code": Json::string(report_text(payload, "l3_code", "")),
          "r_code": Json::string(report_text(payload, "r_code", "")),
          "l2_code": Json::string(report_text(payload, "l2_code", "")),
          "l2_name": Json::string(report_text(payload, "l2_name", "")),
          "subject": Json::string(report_text(payload, "subject", "")),
          "plan_amount": Json::number(report_amount(payload, "plan_amount")),
          "src": Json::string(report_text(payload, "src", "manual")),
        }),
      )
    }
  }
  let envelope = cbs_envelope(
    Json::object({
      "planVersion": Json::string(version),
      "items": Json::array(items),
    }),
    coverage,
  )
  match envelope {
    Object(fields) => {
      fields.set("command_projection", Json::boolean(!local_rows.is_empty()))
      fields.set(
        "source_kind",
        Json::string(
          if local_rows.is_empty() {
            "imported_or_empty"
          } else {
            "imported_or_command"
          },
        ),
      )
      Json::object(fields)
    }
    _ => envelope
  }
}

///|
async fn cbs_f_balance_response(
  proj_guid : String,
  l3_code : String,
  plan_version : String?,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(proj_guid) || !valid_identifier(l3_code) {
    raise reject(422, "invalid CBS identifier")
  }
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let version = plan_version.unwrap_or("execution")
  let mut leaf : SourceRow? = None
  for row in rows.get_or_default("cb_subject_dict", []) {
    if json_field(row.payload, "deleted_at") is None &&
      cbs_filter_project(row.payload, Some(proj_guid)) &&
      report_text(row.payload, "plan_version", "baseline") == version &&
      report_text(row.payload, "l3_code", "") == l3_code {
      leaf = Some(row)
    }
  }
  match leaf {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("CBS leaf not found"),
          "data": Json::null(),
          "source_coverage": report_coverage(coverage),
          "authorizing": Json::boolean(false),
        }),
      )
    Some(value) =>
      (
        200,
        cbs_envelope(
          Json::object({
            "planVersion": Json::string(version),
            "l3Code": Json::string(l3_code),
            "A": Json::number(report_amount(value.payload, "plan_amount")),
            "usedDplusE": Json::number(0),
            "F": Json::number(report_amount(value.payload, "plan_amount")),
          }),
          coverage,
        ),
      )
  }
}

///|
async fn cbs_versions_response(
  proj_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(proj_guid) {
    raise reject(422, "invalid proj_guid")
  }
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let items : Array[Json] = []
  for row in rows.get_or_default("cb_plan_version", []) {
    if json_field(row.payload, "deleted_at") is None &&
      cbs_filter_project(row.payload, Some(proj_guid)) {
      items.push(
        Json::object({
          "plan_version": Json::string(
            report_text(row.payload, "plan_version", ""),
          ),
          "version_name": Json::string(
            report_text(row.payload, "version_name", ""),
          ),
          "parent_version": Json::string(
            report_text(row.payload, "parent_version", ""),
          ),
          "is_active": Json::boolean(json_bool(row.payload, "is_active", false)),
          "frozen_at": Json::string(report_text(row.payload, "frozen_at", "")),
          "frozen_by": Json::string(report_text(row.payload, "frozen_by", "")),
          "created_at": Json::string(report_text(row.payload, "created_at", "")),
          "created_by": Json::string(report_text(row.payload, "created_by", "")),
        }),
      )
    }
  }
  let local_rows = cbs_projection_payloads("cbs_plan_version")
  for payload in local_rows {
    if json_text(payload, "state", "active") != "deleted" &&
      cbs_filter_project(payload, Some(proj_guid)) {
      items.push(
        Json::object({
          "plan_version": Json::string(report_text(payload, "plan_version", "")),
          "version_name": Json::string(report_text(payload, "version_name", "")),
          "parent_version": Json::string(
            report_text(payload, "parent_version", ""),
          ),
          "is_active": Json::boolean(json_bool(payload, "is_active", false)),
          "frozen_at": Json::string(report_text(payload, "frozen_at", "")),
          "frozen_by": Json::string(report_text(payload, "frozen_by", "")),
          "created_at": Json::string(report_text(payload, "created_at", "")),
          "created_by": Json::string(report_text(payload, "created_by", "")),
        }),
      )
    }
  }
  let envelope = cbs_envelope(Json::array(items), coverage)
  match envelope {
    Object(fields) => {
      fields.set("command_projection", Json::boolean(!local_rows.is_empty()))
      fields.set(
        "source_kind",
        Json::string(
          if local_rows.is_empty() {
            "imported_or_empty"
          } else {
            "imported_or_command"
          },
        ),
      )
      Json::object(fields)
    }
    _ => envelope
  }
}

///|
async fn cbs_compare_response(
  proj_guid : String,
  version_a : String,
  version_b : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(proj_guid) ||
    !valid_identifier(version_a) ||
    !valid_identifier(version_b) {
    raise reject(422, "invalid CBS version identifier")
  }
  let rows = cbs_rows()
  cbs_envelope(
    Json::object({
      "projGuid": Json::string(proj_guid),
      "a": Json::string(version_a),
      "b": Json::string(version_b),
      "rows": Json::array([]),
    }),
    cbs_coverage(rows),
  )
}

///|
async fn cbs_r0_queue_response(
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  match proj_guid {
    Some(value) if !valid_identifier(value) =>
      raise reject(422, "invalid proj_guid")
    _ => ()
  }
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let items : Array[Json] = []
  for row in rows.get_or_default("cb_contract", []) {
    if json_field(row.payload, "deleted_at") is None &&
      cbs_filter_project(row.payload, proj_guid) {
      let r_code = report_text(row.payload, "r_code", "")
      if r_code.is_empty() || r_code == "R0" {
        items.push(
          Json::object({
            "refId": Json::string(
              report_text(row.payload, "contract_guid", row.record_id),
            ),
            "kind": Json::string("contract"),
            "name": Json::string(report_text(row.payload, "contract_name", "")),
            "amount": Json::number(report_amount(row.payload, "ht_amount")),
            "rCode": Json::string(if r_code.is_empty() { "R0" } else { r_code }),
            "l3Code": Json::string(report_text(row.payload, "l3_code", "")),
          }),
        )
      }
    }
  }
  cbs_envelope(Json::object({ "items": Json::array(items) }), coverage)
}

///|
async fn cbs_approval_rules_response(
  biz_type : String?,
) -> Json raise CompanyServiceError {
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let items : Array[Json] = []
  for row in rows.get_or_default("wf_approval_rule", []) {
    if json_field(row.payload, "deleted_at") is None &&
      (match biz_type {
        Some(value) => report_text(row.payload, "biz_type", "") == value
        None => true
      }) {
      items.push(
        Json::object({
          "rule_guid": Json::string(
            report_text(row.payload, "rule_guid", row.record_id),
          ),
          "biz_type": Json::string(report_text(row.payload, "biz_type", "")),
          "threshold": Json::number(report_amount(row.payload, "threshold")),
          "actor_user_id": Json::string(
            report_text(row.payload, "actor_user_id", ""),
          ),
          "description": Json::string(
            report_text(row.payload, "description", ""),
          ),
          "display_order": Json::number(
            report_amount(row.payload, "display_order"),
          ),
        }),
      )
    }
  }
  let local_rows = cbs_projection_payloads("cbs_approval_rule")
  for payload in local_rows {
    if json_text(payload, "state", "active") != "deleted" &&
      (match biz_type {
        Some(value) => json_text(payload, "biz_type", "") == value
        None => true
      }) {
      items.push(
        Json::object({
          "rule_guid": Json::string(json_text(payload, "rule_guid", "")),
          "biz_type": Json::string(json_text(payload, "biz_type", "")),
          "threshold": Json::number(json_number(payload, "threshold", 0.0)),
          "actor_user_id": Json::string(json_text(payload, "actor_user_id", "")),
          "description": Json::string(json_text(payload, "description", "")),
          "display_order": Json::number(
            json_number(payload, "display_order", 0.0),
          ),
        }),
      )
    }
  }
  let envelope = cbs_envelope(Json::array(items), coverage)
  match envelope {
    Object(fields) => {
      fields.set("command_projection", Json::boolean(!local_rows.is_empty()))
      fields.set(
        "source_kind",
        Json::string(
          if local_rows.is_empty() {
            "imported_or_empty"
          } else {
            "imported_or_command"
          },
        ),
      )
      Json::object(fields)
    }
    _ => envelope
  }
}

///|
async fn cbs_approval_pick_response(
  biz_type : String,
  amount : Double,
) -> Json raise CompanyServiceError {
  if biz_type.is_empty() {
    raise reject(422, "invalid biz_type")
  }
  let rows = cbs_rows()
  let candidates : Array[Json] = []
  for row in rows.get_or_default("wf_approval_rule", []) {
    if json_field(row.payload, "deleted_at") is None &&
      report_text(row.payload, "biz_type", "") == biz_type &&
      report_amount(row.payload, "threshold") <= amount {
      candidates.push(
        Json::object({
          "actor_user_id": Json::string(
            report_text(row.payload, "actor_user_id", ""),
          ),
          "threshold": Json::number(report_amount(row.payload, "threshold")),
          "description": Json::string(
            report_text(row.payload, "description", ""),
          ),
        }),
      )
    }
  }
  let local_rows = cbs_projection_payloads("cbs_approval_rule")
  for payload in local_rows {
    if json_text(payload, "state", "active") != "deleted" &&
      json_text(payload, "biz_type", "") == biz_type &&
      json_number(payload, "threshold", 0.0) <= amount {
      candidates.push(
        Json::object({
          "actor_user_id": Json::string(json_text(payload, "actor_user_id", "")),
          "threshold": Json::number(json_number(payload, "threshold", 0.0)),
          "description": Json::string(json_text(payload, "description", "")),
        }),
      )
    }
  }
  candidates.sort_by(fn(left, right) {
    json_number(right, "threshold", 0.0).compare(
      json_number(left, "threshold", 0.0),
    )
  })
  let selected = if candidates.is_empty() {
    Json::null()
  } else {
    candidates[0]
  }
  let envelope = cbs_envelope(selected, cbs_coverage(rows))
  match envelope {
    Object(fields) => {
      fields.set("command_projection", Json::boolean(!local_rows.is_empty()))
      fields.set(
        "source_kind",
        Json::string(
          if local_rows.is_empty() {
            "imported_or_empty"
          } else {
            "imported_or_command"
          },
        ),
      )
      Json::object(fields)
    }
    _ => envelope
  }
}

///|
async fn cbs_changes_response(
  proj_guid : String?,
  contract_guid : String?,
) -> Json raise CompanyServiceError {
  let rows = cbs_rows()
  cbs_envelope(Json::array([]), cbs_coverage(rows))
}

///|
async fn cbs_demo_contracts_response(
  proj_guid : String?,
) -> Json raise CompanyServiceError {
  let rows = cbs_rows()
  let coverage = cbs_coverage(rows)
  let items : Array[Json] = []
  for row in rows.get_or_default("cb_contract", []) {
    if json_field(row.payload, "deleted_at") is None &&
      cbs_filter_project(row.payload, proj_guid) {
      items.push(row.payload)
    }
  }
  let local_rows = cbs_projection_payloads("cbs_demo_contract")
  for payload in local_rows {
    if json_text(payload, "state", "draft") != "deleted" &&
      cbs_filter_project(payload, proj_guid) {
      let fields = cbs_copy_fields(payload)
      fields.set("id", Json::string(json_text(payload, "contract_guid", "")))
      fields.set("code", Json::string(json_text(payload, "contract_code", "")))
      fields.set("name", Json::string(json_text(payload, "contract_name", "")))
      fields.set("rCode", Json::string(json_text(payload, "r_code", "R0")))
      fields.set("l3Code", Json::string(json_text(payload, "l3_code", "")))
      fields.set(
        "amount",
        Json::number(json_number(payload, "ht_amount", 0.0) / 10000.0),
      )
      fields.set("state", Json::string(json_text(payload, "cb_state", "draft")))
      fields.set("source_kind", Json::string("command"))
      items.push(Json::object(fields))
    }
  }
  cbs_envelope(Json::array(items), coverage)
}
