///|
/// Native read-only observations for the investment Excel/import boundary.
/// These routes expose imported workbook metadata and safe previews only;
/// they never upload, parse, activate, or write an investment version.
struct InvestmentExcelSource {
  import_row : SourceRow
  rows : Map[String, Array[SourceRow]]
  coverage : Map[String, Int]
}

///|
fn investment_excel_tables() -> Array[String] {
  [
    "ep_project", "sys_user", "tzsy_version", "tzsy_excel_import", "tzsy_excel_sheet",
    "tzsy_profit_table", "tzsy_plan_line", "tzsy_subject_mapping",
  ]
}

///|
async fn investment_excel_context() -> Map[String, Array[SourceRow]] raise CompanyServiceError {
  let rows : Map[String, Array[SourceRow]] = {}
  for table in investment_excel_tables() {
    rows.set(table, raw_source_rows(table, 5000))
  }
  rows
}

///|
fn investment_excel_coverage(
  rows : Map[String, Array[SourceRow]],
) -> Map[String, Int] {
  let coverage : Map[String, Int] = {}
  for table in investment_excel_tables() {
    coverage.set(table, rows.get_or_default(table, []).length())
  }
  coverage
}

///|
fn investment_excel_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(report_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn investment_import_missing_response() -> (Int, Json) {
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43001),
      "message": Json::string("导入记录不存在"),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
    }),
  )
}

///|
async fn investment_excel_source(
  import_id : String,
) -> InvestmentExcelSource? raise CompanyServiceError {
  if !valid_identifier(import_id) {
    raise reject(422, "invalid import_guid")
  }
  let rows = investment_excel_context()
  let coverage = investment_excel_coverage(rows)
  let mut selected : SourceRow? = None
  for row in rows.get_or_default("tzsy_excel_import", []) {
    if report_text(row.payload, "import_guid", row.record_id) == import_id {
      selected = Some(row)
    }
  }
  match selected {
    Some(import_row) => Some({ import_row, rows, coverage })
    None => None
  }
}

///|
fn investment_excel_user_name(
  rows : Map[String, Array[SourceRow]],
  user_id : String,
) -> String {
  for row in rows.get_or_default("sys_user", []) {
    if report_text(row.payload, "user_id", row.record_id) == user_id {
      return report_text(
        row.payload,
        "emp_name",
        report_text(row.payload, "user_name", ""),
      )
    }
  }
  ""
}

///|
fn investment_excel_project(
  rows : Map[String, Array[SourceRow]],
  project_id : String,
) -> Json? {
  for row in rows.get_or_default("ep_project", []) {
    if report_text(row.payload, "proj_guid", row.record_id) == project_id &&
      json_field(row.payload, "deleted_at") is None {
      return Some(row.payload)
    }
  }
  None
}

///|
fn investment_excel_version(
  rows : Map[String, Array[SourceRow]],
  version_id : String,
) -> Json? {
  for row in rows.get_or_default("tzsy_version", []) {
    if report_text(row.payload, "version_guid", row.record_id) == version_id {
      return Some(row.payload)
    }
  }
  None
}

///|
fn investment_excel_sheet_data(
  rows : Map[String, Array[SourceRow]],
  import_id : String,
) -> Array[Json] {
  let result : Array[Json] = []
  for row in rows.get_or_default("tzsy_excel_sheet", []) {
    let payload = row.payload
    if report_text(payload, "import_guid", "") == import_id {
      result.push(
        Json::object({
          "sheetGuid": Json::string(
            report_text(payload, "sheet_guid", row.record_id),
          ),
          "sheetOrder": Json::number(report_amount(payload, "sheet_order")),
          "sheetName": Json::string(report_text(payload, "sheet_name", "")),
          "dimensionRef": Json::string(
            report_text(payload, "dimension_ref", ""),
          ),
          "rowCount": json_field(payload, "row_count").unwrap_or(Json::null()),
          "colCount": json_field(payload, "col_count").unwrap_or(Json::null()),
          "nonEmptyCount": json_field(payload, "non_empty_count").unwrap_or(
            Json::null(),
          ),
          "formulaCount": json_field(payload, "formula_count").unwrap_or(
            Json::null(),
          ),
          "crossSheetFormulaCount": json_field(
            payload, "cross_sheet_formula_count",
          ).unwrap_or(Json::null()),
          "mappedModule": Json::string(
            report_text(payload, "mapped_module", "unmapped"),
          ),
          "mappedModuleName": Json::string(
            report_text(payload, "mapped_module_name", ""),
          ),
          "department": Json::string(report_text(payload, "department", "")),
          "summary": json_field(payload, "summary_json").unwrap_or(
            json_field(payload, "summary").unwrap_or(Json::null()),
          ),
          "cellsJson": json_field(payload, "cells_json").unwrap_or(Json::null()),
        }),
      )
    }
  }
  result.sort_by(fn(left, right) {
    report_amount(left, "sheetOrder").compare(
      report_amount(right, "sheetOrder"),
    )
  })
  result
}

///|
async fn investment_imports_response(
  project_id : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let rows = investment_excel_context()
  let coverage = investment_excel_coverage(rows)
  let result : Array[Json] = []
  for row in rows.get_or_default("tzsy_excel_import", []) {
    let payload = row.payload
    if report_text(payload, "proj_guid", "") == project_id {
      let version_id = report_text(payload, "version_guid", "")
      let version = investment_excel_version(rows, version_id).unwrap_or(
        Json::object({}),
      )
      result.push(
        Json::object({
          "importGuid": Json::string(
            report_text(payload, "import_guid", row.record_id),
          ),
          "versionGuid": Json::string(version_id),
          "versionName": Json::string(report_text(version, "version_name", "")),
          "fileName": Json::string(report_text(payload, "file_name", "")),
          "fileSize": json_field(payload, "file_size").unwrap_or(Json::null()),
          "sheetCount": json_field(payload, "sheet_count").unwrap_or(
            Json::null(),
          ),
          "nonEmptyCells": json_field(payload, "non_empty_cells").unwrap_or(
            Json::null(),
          ),
          "formulaCount": json_field(payload, "formula_count").unwrap_or(
            Json::null(),
          ),
          "crossSheetFormulaCount": json_field(
            payload, "cross_sheet_formula_count",
          ).unwrap_or(Json::null()),
          "status": Json::string(report_text(payload, "status", "")),
          "createdByName": Json::string(
            investment_excel_user_name(
              rows,
              report_text(payload, "created_by", ""),
            ),
          ),
          "createdAt": Json::string(report_text(payload, "created_at", "")),
          "sourceKind": Json::string("imported"),
        }),
      )
    }
  }
  result.sort_by(fn(left, right) {
    report_text(right, "createdAt", "").compare(
      report_text(left, "createdAt", ""),
    )
  })
  if result.length() > 20 {
    investment_excel_envelope(Json::array(result[:20].to_owned()), coverage)
  } else {
    investment_excel_envelope(Json::array(result), coverage)
  }
}

///|
async fn investment_import_detail_response(
  import_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let source = investment_excel_source(import_id)
  let source = match source {
    Some(value) => value
    None => return investment_import_missing_response()
  }
  let payload = source.import_row.payload
  let project_id = report_text(payload, "proj_guid", "")
  let version_id = report_text(payload, "version_guid", "")
  let project = investment_excel_project(source.rows, project_id).unwrap_or(
    Json::object({}),
  )
  let version = investment_excel_version(source.rows, version_id).unwrap_or(
    Json::object({}),
  )
  let mapping = json_field(payload, "mapping_json").unwrap_or(
    json_field(payload, "mapping").unwrap_or(Json::null()),
  )
  let data = Json::object({
    "importGuid": Json::string(
      report_text(payload, "import_guid", source.import_row.record_id),
    ),
    "projGuid": Json::string(project_id),
    "projName": Json::string(report_text(project, "proj_name", "")),
    "versionGuid": Json::string(version_id),
    "versionName": Json::string(report_text(version, "version_name", "")),
    "fileName": Json::string(report_text(payload, "file_name", "")),
    "fileSize": json_field(payload, "file_size").unwrap_or(Json::null()),
    "sheetCount": json_field(payload, "sheet_count").unwrap_or(Json::null()),
    "nonEmptyCells": json_field(payload, "non_empty_cells").unwrap_or(
      Json::null(),
    ),
    "formulaCount": json_field(payload, "formula_count").unwrap_or(Json::null()),
    "crossSheetFormulaCount": json_field(payload, "cross_sheet_formula_count").unwrap_or(
      Json::null(),
    ),
    "status": Json::string(report_text(payload, "status", "")),
    "mapping": mapping,
    "createdByName": Json::string(
      investment_excel_user_name(
        source.rows,
        report_text(payload, "created_by", ""),
      ),
    ),
    "createdAt": Json::string(report_text(payload, "created_at", "")),
    "sheets": Json::array(investment_excel_sheet_data(source.rows, import_id)),
  })
  (200, investment_excel_envelope(data, source.coverage))
}

///|
fn investment_bridge_module_plan(module_name : String) -> Json {
  match module_name {
    "project_master" =>
      Json::object({
        "erpTargets": Json::array([Json::string("ep_project")]),
        "erpSources": Json::array([Json::string("ep_project")]),
        "apiEndpoints": Json::array([Json::string("GET /mdm/projects")]),
        "status": Json::string("parsed"),
        "gap": Json::string("Excel 项目主数据尚未回写 ep_project。"),
        "nextAction": Json::string(
          "完成抽取层和项目主数据 owner review 后再回写。",
        ),
      })
    "profit_summary" =>
      Json::object({
        "erpTargets": Json::array([Json::string("tzsy_plan_index")]),
        "erpSources": Json::array([Json::string("tzsy_plan_index")]),
        "apiEndpoints": Json::array([
          Json::string("GET /investment/projects/:projGuid/profit-summary"),
        ]),
        "status": Json::string("parsed"),
        "gap": Json::string(
          "利润指标仍需逐项校准，Excel 值未自动写入。",
        ),
        "nextAction": Json::string(
          "先完成 preview，再由 owner 批准批量 upsert。",
        ),
      })
    _ =>
      Json::object({
        "erpTargets": Json::array([]),
        "erpSources": Json::array([]),
        "apiEndpoints": Json::array([]),
        "status": Json::string("unmapped"),
        "gap": Json::string("sheet 未匹配已审计模块。"),
        "nextAction": Json::string("补充映射规则并重新审核。"),
      })
  }
}

///|
async fn investment_import_bridge_plan_response(
  import_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let source = investment_excel_source(import_id)
  let source = match source {
    Some(value) => value
    None => return investment_import_missing_response()
  }
  let payload = source.import_row.payload
  let sheets = investment_excel_sheet_data(source.rows, import_id)
  let module_counts : Map[String, Int] = {}
  let module_rows : Array[Json] = []
  let mut mapped = 0
  for sheet in sheets {
    let module_name = report_text(sheet, "mappedModule", "unmapped")
    module_counts.set(
      module_name,
      module_counts.get_or_default(module_name, 0) + 1,
    )
    if module_name != "unmapped" {
      mapped += 1
    }
    let plan = investment_bridge_module_plan(module_name)
    let plan_fields : Map[String, Json] = match plan {
      Object(fields) => fields
      _ => {}
    }
    let item_fields : Map[String, Json] = {
      "sheetOrder": json_field(sheet, "sheetOrder").unwrap_or(Json::number(0)),
      "sheetName": json_field(sheet, "sheetName").unwrap_or(Json::string("")),
      "mappedModule": Json::string(module_name),
      "mappedModuleName": json_field(sheet, "mappedModuleName").unwrap_or(
        Json::string(""),
      ),
      "department": json_field(sheet, "department").unwrap_or(Json::string("")),
    }
    for key, value in plan_fields {
      item_fields.set(key, value)
    }
    module_rows.push(Json::object(item_fields))
  }
  let module_json : Map[String, Json] = {}
  for module_name, count in module_counts {
    module_json.set(module_name, Json::number(count.to_double()))
  }
  (
    200,
    investment_excel_envelope(
      Json::object({
        "importGuid": Json::string(
          report_text(payload, "import_guid", source.import_row.record_id),
        ),
        "projGuid": Json::string(report_text(payload, "proj_guid", "")),
        "versionGuid": Json::string(report_text(payload, "version_guid", "")),
        "fileName": Json::string(report_text(payload, "file_name", "")),
        "status": Json::string(report_text(payload, "status", "")),
        "summary": Json::object({
          "sheetCount": json_field(payload, "sheet_count").unwrap_or(
            Json::null(),
          ),
          "nonEmptyCells": json_field(payload, "non_empty_cells").unwrap_or(
            Json::null(),
          ),
          "formulaCount": json_field(payload, "formula_count").unwrap_or(
            Json::null(),
          ),
          "crossSheetFormulaCount": json_field(
            payload, "cross_sheet_formula_count",
          ).unwrap_or(Json::null()),
          "moduleCounts": Json::object(module_json),
          "mappedSheetCount": Json::number(mapped.to_double()),
          "unmappedSheetCount": Json::number(
            (sheets.length() - mapped).to_double(),
          ),
          "createdAt": Json::string(report_text(payload, "created_at", "")),
        }),
        "sheets": Json::array(module_rows),
      }),
      source.coverage,
    ),
  )
}

///|
async fn investment_index_upsert_preview_response(
  import_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let source = investment_excel_source(import_id)
  let source = match source {
    Some(value) => value
    None => return investment_import_missing_response()
  }
  let payload = source.import_row.payload
  (
    200,
    investment_excel_envelope(
      Json::object({
        "importGuid": Json::string(
          report_text(payload, "import_guid", source.import_row.record_id),
        ),
        "projGuid": Json::string(report_text(payload, "proj_guid", "")),
        "versionGuid": Json::string(report_text(payload, "version_guid", "")),
        "versionName": Json::string(""),
        "versionNo": Json::null(),
        "versionIsCurrent": Json::null(),
        "fileName": Json::string(report_text(payload, "file_name", "")),
        "summary": Json::object({
          "sheetsTotal": Json::number(
            investment_excel_sheet_data(source.rows, import_id)
            .length()
            .to_double(),
          ),
          "sheetsWithMapping": Json::number(0),
          "sheetsExtracted": Json::number(0),
          "itemsTotal": Json::number(0),
          "itemsCanUpsert": Json::number(0),
          "itemsToInsert": Json::number(0),
          "itemsToUpdate": Json::number(0),
          "itemsToSkip": Json::number(0),
        }),
        "items": Json::array([]),
      }),
      source.coverage,
    ),
  )
}

///|
/// Native candidate for the source POST /excel-imports/:id/index-upsert route.
///
/// The ERP defaults this operation to dry-run and only writes when
/// `dryRun=false`. Native MoonBit exposes the same deterministic plan shape;
/// real index insertion/update remains an explicit owner-acceptance gate.
fn investment_index_upsert_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let prefix = "/api/company/investment/excel-imports/"
    let source_prefix = "/api/company/source/investment/excel-imports/"
    if path.has_prefix(prefix) && path.has_suffix("/index-upsert") {
      return Some(
        path[prefix.length():path.length() - "/index-upsert".length()].to_owned(),
      )
    }
    if path.has_prefix(source_prefix) && path.has_suffix("/index-upsert") {
      return Some(
        path[source_prefix.length():path.length() - "/index-upsert".length()].to_owned(),
      )
    }
  }
  None
}

///|
async fn investment_index_upsert_candidate(
  import_id : String,
  body : Json,
) -> (Int, Json) raise CompanyServiceError {
  let dry_run = match json_field(body, "dryRun") {
    Some(False) => false
    _ => true
  }
  let force = json_bool(body, "force", false)
  if !dry_run {
    return (
      409,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(46001),
        "message": Json::string(
          "Excel 指标 upsert 需要投资负责人确认；当前 native 服务仅提供 dry-run。",
        ),
        "source_kind": Json::string("investment_excel_index_upsert_candidate"),
        "dry_run": Json::boolean(false),
        "force": Json::boolean(force),
        "provider_execution": Json::boolean(false),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      }),
    )
  }
  let preview = investment_index_upsert_preview_response(import_id)
  if preview.0 != 200 {
    return preview
  }
  match preview.1 {
    Object(fields) => {
      fields.set(
        "source_kind",
        Json::string("investment_excel_index_upsert_candidate"),
      )
      fields.set("dry_run", Json::boolean(true))
      fields.set("force", Json::boolean(force))
      fields.set("provider_execution", Json::boolean(false))
      fields.set("persisted", Json::boolean(false))
      fields.set("authorizing", Json::boolean(false))
      fields.set("cash_effect", Json::boolean(false))
      fields.set("accounting_effect", Json::boolean(false))
      fields.set("tax_effect", Json::boolean(false))
      match fields.get("data") {
        Some(Object(data_fields)) => {
          data_fields.set("dryRun", Json::boolean(true))
          data_fields.set("force", Json::boolean(force))
          data_fields.set("inserted", Json::number(0))
          data_fields.set("updated", Json::number(0))
          data_fields.set("skipped", Json::number(0))
          data_fields.set("wouldInsert", Json::number(0))
          data_fields.set("wouldUpdate", Json::number(0))
        }
        _ => ()
      }
      (200, Json::object(fields))
    }
    _ => preview
  }
}

///|
fn investment_plan_line_import_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let suffix = "/plan-lines/import"
    let prefix = "/api/company/investment/excel-imports/"
    let source_prefix = "/api/company/source/investment/excel-imports/"
    if path.has_prefix(prefix) && path.has_suffix(suffix) {
      return Some(
        path[prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
    if path.has_prefix(source_prefix) && path.has_suffix(suffix) {
      return Some(
        path[source_prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
  }
  None
}

///|
async fn investment_plan_line_import_candidate(
  import_id : String,
  body : Json,
) -> (Int, Json) raise CompanyServiceError {
  let dry_run = match json_field(body, "dryRun") {
    Some(False) => false
    _ => true
  }
  let replace_existing = json_bool(body, "replaceExisting", false)
  if !dry_run {
    return (
      409,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(46002),
        "message": Json::string(
          "Excel 计划行导入需要投资负责人确认；当前 native 服务仅提供 dry-run。",
        ),
        "source_kind": Json::string(
          "investment_excel_plan_line_import_candidate",
        ),
        "dry_run": Json::boolean(false),
        "replace_existing": Json::boolean(replace_existing),
        "provider_execution": Json::boolean(false),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
        "cash_effect": Json::boolean(false),
        "accounting_effect": Json::boolean(false),
        "tax_effect": Json::boolean(false),
      }),
    )
  }
  let preview = investment_plan_line_preview_response(import_id)
  if preview.0 != 200 {
    return preview
  }
  match preview.1 {
    Object(fields) => {
      fields.set(
        "source_kind",
        Json::string("investment_excel_plan_line_import_candidate"),
      )
      fields.set("dry_run", Json::boolean(true))
      fields.set("replace_existing", Json::boolean(replace_existing))
      fields.set("provider_execution", Json::boolean(false))
      fields.set("persisted", Json::boolean(false))
      fields.set("authorizing", Json::boolean(false))
      fields.set("cash_effect", Json::boolean(false))
      fields.set("accounting_effect", Json::boolean(false))
      fields.set("tax_effect", Json::boolean(false))
      match fields.get("data") {
        Some(Object(data_fields)) => {
          data_fields.set("dryRun", Json::boolean(true))
          data_fields.set("replaceExisting", Json::boolean(replace_existing))
          data_fields.set("inserted", Json::number(0))
          data_fields.set("replaced", Json::number(0))
          let lines_total = match data_fields.get("summary") {
            Some(Object(summary)) =>
              summary.get("linesTotal").unwrap_or(Json::number(0))
            _ => Json::number(0)
          }
          match data_fields.get("summary") {
            Some(Object(summary)) => {
              summary.set("inserted", Json::number(0))
              summary.set("replaced", Json::number(0))
              summary.set("wouldInsert", lines_total)
            }
            _ => ()
          }
        }
        _ => ()
      }
      (200, Json::object(fields))
    }
    _ => preview
  }
}

///|
fn investment_subject_mappings_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Put {
    let suffix = "/subject-mappings"
    let prefix = "/api/company/investment/projects/"
    let source_prefix = "/api/company/source/investment/projects/"
    if path.has_prefix(prefix) && path.has_suffix(suffix) {
      return Some(
        path[prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
    if path.has_prefix(source_prefix) && path.has_suffix(suffix) {
      return Some(
        path[source_prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
  }
  None
}

///|
async fn investment_subject_mappings_candidate(
  project_id : String,
  body : Json,
) -> (Int, Json) raise CompanyServiceError {
  let dry_run = match json_field(body, "dryRun") {
    Some(False) => false
    _ => true
  }
  let items = match json_field(body, "items") {
    Some(Array(values)) if !values.is_empty() => values
    _ => raise reject(400, "缺少 items 数组")
  }
  if !dry_run {
    return (
      409,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(46003),
        "message": Json::string(
          "投资科目映射写入需要投资负责人确认；当前 native 服务仅提供 dry-run。",
        ),
        "source_kind": Json::string("investment_subject_mappings_candidate"),
        "dry_run": Json::boolean(false),
        "provider_execution": Json::boolean(false),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
      }),
    )
  }
  let existing = investment_subject_mappings_response(project_id)
  if existing.0 != 200 {
    return existing
  }
  let groups = match json_field(existing.1, "data") {
    Some(Object(data_fields)) =>
      data_fields.get("groups").unwrap_or(Json::object({}))
    _ => Json::object({})
  }
  (
    200,
    Json::object({
      "success": Json::boolean(true),
      "code": Json::number(0),
      "data": Json::object({
        "projGuid": Json::string(project_id),
        "groups": groups,
        "items": Json::array(items),
        "total": Json::number(items.length().to_double()),
        "updated": Json::number(0),
        "wouldUpdate": Json::number(items.length().to_double()),
        "dryRun": Json::boolean(true),
      }),
      "source_kind": Json::string("investment_subject_mappings_candidate"),
      "dry_run": Json::boolean(true),
      "provider_execution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}

///|
fn investment_plan_line_update_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Put {
    let prefix = "/api/company/investment/plan-lines/"
    let source_prefix = "/api/company/source/investment/plan-lines/"
    if path.has_prefix(prefix) {
      return Some(path[prefix.length():].to_owned())
    }
    if path.has_prefix(source_prefix) {
      return Some(path[source_prefix.length():].to_owned())
    }
  }
  None
}

///|
async fn investment_plan_line_update_candidate(
  line_id : String,
  body : Json,
) -> (Int, Json) raise CompanyServiceError {
  let dry_run = match json_field(body, "dryRun") {
    Some(False) => false
    _ => true
  }
  let status = json_text(body, "status", "")
  if !status.is_empty() &&
    !["imported", "adjusted", "confirmed", "locked"].contains(status) {
    raise reject(400, "status 不合法")
  }
  if !dry_run {
    return (
      409,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(46004),
        "message": Json::string(
          "计划行编辑需要投资负责人确认；当前 native 服务仅提供 dry-run。",
        ),
        "source_kind": Json::string("investment_plan_line_update_candidate"),
        "dry_run": Json::boolean(false),
        "provider_execution": Json::boolean(false),
        "persisted": Json::boolean(false),
        "authorizing": Json::boolean(false),
      }),
    )
  }
  if !valid_identifier(line_id) {
    raise reject(422, "invalid line_guid")
  }
  let rows = raw_source_rows("tzsy_plan_line", 5000)
  let mut current : Json? = None
  for row in rows {
    if report_text(row.payload, "line_guid", row.record_id) == line_id {
      current = Some(row.payload)
    }
  }
  match current {
    None =>
      (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(43001),
          "message": Json::string("计划行不存在"),
          "source_kind": Json::string("investment_plan_line_update_candidate"),
          "dry_run": Json::boolean(true),
          "provider_execution": Json::boolean(false),
          "persisted": Json::boolean(false),
          "authorizing": Json::boolean(false),
        }),
      )
    Some(value) =>
      (
        200,
        Json::object({
          "success": Json::boolean(true),
          "code": Json::number(0),
          "data": Json::object({
            "lineGuid": Json::string(line_id),
            "current": value,
            "requested": body,
            "dryRun": Json::boolean(true),
            "wouldUpdate": Json::boolean(true),
          }),
          "source_kind": Json::string("investment_plan_line_update_candidate"),
          "dry_run": Json::boolean(true),
          "provider_execution": Json::boolean(false),
          "persisted": Json::boolean(false),
          "authorizing": Json::boolean(false),
        }),
      )
  }
}

///|
fn investment_excel_upload_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Post {
    let suffix = "/excel-imports"
    let prefix = "/api/company/investment/projects/"
    let source_prefix = "/api/company/source/investment/projects/"
    if path.has_prefix(prefix) && path.has_suffix(suffix) {
      return Some(
        path[prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
    if path.has_prefix(source_prefix) && path.has_suffix(suffix) {
      return Some(
        path[source_prefix.length():path.length() - suffix.length()].to_owned(),
      )
    }
  }
  None
}

///|
fn investment_excel_upload_candidate(project_id : String) -> (Int, Json) {
  (
    409,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(46005),
      "message": Json::string(
        "Excel 工作簿上传需要二进制解析与投资负责人确认；当前 native 服务仅提供导入后 dry-run。",
      ),
      "data": Json::object({
        "projGuid": Json::string(project_id),
        "multipartAccepted": Json::boolean(false),
        "binaryParser": Json::string("not_connected"),
      }),
      "source_kind": Json::string("investment_excel_upload_candidate"),
      "dry_run": Json::boolean(true),
      "provider_execution": Json::boolean(false),
      "persisted": Json::boolean(false),
      "authorizing": Json::boolean(false),
      "cash_effect": Json::boolean(false),
      "accounting_effect": Json::boolean(false),
      "tax_effect": Json::boolean(false),
    }),
  )
}

///|
async fn investment_profit_table_response(
  import_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let source = investment_excel_source(import_id)
  let source = match source {
    Some(value) => value
    None => return investment_import_missing_response()
  }
  let payload = source.import_row.payload
  let row_cells : Map[String, Map[String, Json]] = {}
  let row_order : Array[String] = []
  for row in source.rows.get_or_default("tzsy_profit_table", []) {
    let value = row.payload
    if report_text(value, "import_guid", "") == import_id {
      let row_key = report_text(value, "row_idx", "0")
      let cells = row_cells.get_or_default(row_key, {})
      let column = report_text(
        value,
        "col_key",
        report_text(value, "col_idx", ""),
      )
      cells.set(
        column,
        Json::object({
          "text": json_field(value, "text_value").unwrap_or(Json::null()),
          "num": json_field(value, "num_value").unwrap_or(Json::null()),
          "formula": json_field(value, "formula").unwrap_or(Json::null()),
          "ref": json_field(value, "cell_ref").unwrap_or(Json::null()),
          "isHeader": Json::boolean(json_bool(value, "is_header", false)),
        }),
      )
      row_cells.set(row_key, cells)
      if !row_order.contains(row_key) {
        row_order.push(row_key)
      }
    }
  }
  row_order.sort_by(fn(left, right) { left.lexical_compare(right) })
  let table_rows : Array[Json] = []
  let columns : Array[String] = []
  for row_key in row_order {
    let cells = row_cells.get_or_default(row_key, {})
    let cell_fields : Map[String, Json] = {}
    for column, cell in cells {
      cell_fields.set(column, cell)
      if !columns.contains(column) {
        columns.push(column)
      }
    }
    table_rows.push(
      Json::object({
        "row": Json::number(
          report_amount(
            Json::object({ "value": Json::string(row_key) }),
            "value",
          ),
        ),
        "cells": Json::object(cell_fields),
      }),
    )
  }
  columns.sort_by(fn(left, right) { left.lexical_compare(right) })
  (
    200,
    investment_excel_envelope(
      Json::object({
        "importGuid": Json::string(
          report_text(payload, "import_guid", source.import_row.record_id),
        ),
        "projGuid": Json::string(report_text(payload, "proj_guid", "")),
        "versionGuid": Json::string(report_text(payload, "version_guid", "")),
        "sheetName": Json::string("利润测算总表"),
        "source": Json::string(
          if table_rows.is_empty() {
            "empty"
          } else {
            "tzsy_profit_table"
          },
        ),
        "merged": Json::array([]),
        "rows": Json::array(table_rows),
        "columnOrder": Json::array(
          columns.map(fn(value) { Json::string(value) }),
        ),
      }),
      source.coverage,
    ),
  )
}

///|
async fn investment_plan_line_preview_response(
  import_id : String,
) -> (Int, Json) raise CompanyServiceError {
  let source = investment_excel_source(import_id)
  let source = match source {
    Some(value) => value
    None => return investment_import_missing_response()
  }
  let sheets = investment_excel_sheet_data(source.rows, import_id)
  let summary_rows : Array[Json] = []
  for sheet in sheets {
    let module_name = report_text(sheet, "mappedModule", "unmapped")
    if [
        "land_cost_detail", "construction_cost_detail", "design_cost_detail", "marketing_cost_detail",
        "admin_cost_detail", "audit_fee_detail", "financial_cost_detail", "tax_detail",
      ].contains(module_name) {
      summary_rows.push(
        Json::object({
          "sheet": json_field(sheet, "sheetName").unwrap_or(Json::string("")),
          "module": Json::string(module_name),
          "lines": Json::number(0),
          "reason": Json::string(
            "源 sheet cells_json 未导入或尚未完成安全抽取。",
          ),
        }),
      )
    }
  }
  (
    200,
    investment_excel_envelope(
      Json::object({
        "importGuid": Json::string(
          report_text(
            source.import_row.payload,
            "import_guid",
            source.import_row.record_id,
          ),
        ),
        "projGuid": Json::string(
          report_text(source.import_row.payload, "proj_guid", ""),
        ),
        "versionGuid": Json::string(
          report_text(source.import_row.payload, "version_guid", ""),
        ),
        "summary": Json::object({
          "sheetsScanned": Json::number(sheets.length().to_double()),
          "sheetsWithRule": Json::number(summary_rows.length().to_double()),
          "linesTotal": Json::number(0),
          "amountTotal": Json::number(0.0),
        }),
        "sheetSummary": Json::array(summary_rows),
        "lines": Json::array([]),
      }),
      source.coverage,
    ),
  )
}

///|
async fn investment_profit_cockpit_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let rows = investment_excel_context()
  let coverage = investment_excel_coverage(rows)
  let project = match investment_excel_project(rows, project_id) {
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
        }),
      )
  }
  let import_ids : Map[String, Bool] = {}
  let mut first_import = ""
  for row in rows.get_or_default("tzsy_excel_import", []) {
    if report_text(row.payload, "proj_guid", "") == project_id {
      let id = report_text(row.payload, "import_guid", row.record_id)
      import_ids.set(id, true)
      if first_import.is_empty() {
        first_import = id
      }
    }
  }
  let values : Map[String, Json] = {}
  for row in rows.get_or_default("tzsy_profit_table", []) {
    let payload = row.payload
    if import_ids.contains(report_text(payload, "import_guid", "")) &&
      report_text(payload, "col_key", "") == "C" {
      values.set(
        "R" + report_text(payload, "row_idx", ""),
        Json::object({
          "total": json_field(payload, "num_value").unwrap_or(Json::number(0)),
        }),
      )
    }
  }
  if values.is_empty() {
    return (
      404,
      Json::object({
        "success": Json::boolean(false),
        "code": Json::number(41002),
        "message": Json::string("该项目暂无利润测算总表数据"),
        "source_coverage": report_coverage(coverage),
        "missing_or_empty_source_tables": Json::array(report_missing(coverage)),
        "authorizing": Json::boolean(false),
        "persisted": Json::boolean(false),
        "provider_execution": Json::boolean(false),
      }),
    )
  }
  let value_json : Map[String, Json] = {}
  for key, value in values {
    value_json.set(key, value)
  }
  (
    200,
    investment_excel_envelope(
      Json::object({
        "projGuid": Json::string(project_id),
        "projName": Json::string(report_text(project, "proj_name", project_id)),
        "versionGuid": Json::string(""),
        "importGuid": Json::string(first_import),
        "source": Json::string("tzsy_profit_table"),
        "values": Json::object(value_json),
        "children": Json::object({}),
      }),
      coverage,
    ),
  )
}

///|
async fn investment_subject_mappings_response(
  project_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let rows = investment_excel_context()
  let coverage = investment_excel_coverage(rows)
  let project = match investment_excel_project(rows, project_id) {
    Some(value) => value
    None =>
      return (
        404,
        Json::object({
          "success": Json::boolean(false),
          "code": Json::number(41001),
          "message": Json::string("项目不存在"),
        }),
      )
  }
  let groups : Map[String, Array[Json]] = {}
  for row in rows.get_or_default("tzsy_subject_mapping", []) {
    let payload = row.payload
    if report_text(payload, "proj_guid", "") == project_id {
      let category = report_text(payload, "category", "custom")
      let values = groups.get_or_default(category, [])
      values.push(
        Json::object({
          "key": Json::string(report_text(payload, "param_key", "")),
          "value": Json::string(report_text(payload, "param_value", "")),
          "type": Json::string(report_text(payload, "value_type", "string")),
          "description": Json::string(report_text(payload, "description", "")),
        }),
      )
      groups.set(category, values)
    }
  }
  let group_object : Map[String, Json] = {}
  for category, values in groups {
    group_object.set(category, Json::array(values))
  }
  (
    200,
    investment_excel_envelope(
      Json::object({
        "projGuid": Json::string(project_id),
        "projName": Json::string(report_text(project, "proj_name", "")),
        "groups": Json::object(group_object),
      }),
      coverage,
    ),
  )
}

///|
async fn investment_plan_lines_response(
  project_id : String,
  version_id : String?,
  module_code : String?,
  sheet : String?,
  department : String?,
  status : String?,
  keyword : String?,
) -> Json raise CompanyServiceError {
  if !valid_identifier(project_id) {
    raise reject(422, "invalid project_id")
  }
  let rows = investment_excel_context()
  let coverage = investment_excel_coverage(rows)
  let lines : Array[Json] = []
  for row in rows.get_or_default("tzsy_plan_line", []) {
    let payload = row.payload
    if report_text(payload, "proj_guid", "") != project_id {
      continue
    }
    let checks : Array[(String, String, String?)] = [
      ("version_guid", "versionGuid", version_id),
      ("module_code", "moduleCode", module_code),
      ("source_sheet", "sheet", sheet),
      ("department", "department", department),
      ("status", "status", status),
    ]
    let mut matched = true
    for check in checks {
      match check.2 {
        Some(value) if report_text(payload, check.0, "") != value =>
          matched = false
        _ => ()
      }
    }
    match keyword {
      Some(value) if !report_text(payload, "subject", "")
        .to_lower()
        .contains(value.to_lower()) => matched = false
      _ => ()
    }
    if matched {
      lines.push(
        Json::object({
          "lineGuid": Json::string(
            report_text(payload, "line_guid", row.record_id),
          ),
          "projGuid": Json::string(project_id),
          "versionGuid": Json::string(report_text(payload, "version_guid", "")),
          "importGuid": Json::string(report_text(payload, "import_guid", "")),
          "sourceSheet": Json::string(report_text(payload, "source_sheet", "")),
          "moduleCode": Json::string(report_text(payload, "module_code", "")),
          "moduleName": Json::string(report_text(payload, "module_name", "")),
          "subject": Json::string(report_text(payload, "subject", "")),
          "planAmount": json_field(payload, "plan_amount").unwrap_or(
            Json::null(),
          ),
          "planPeriod": Json::string(report_text(payload, "plan_period", "")),
          "department": Json::string(report_text(payload, "department", "")),
          "sourceRow": json_field(payload, "source_row").unwrap_or(Json::null()),
          "sourceCell": Json::string(report_text(payload, "source_cell", "")),
          "status": Json::string(report_text(payload, "status", "")),
          "remark": Json::string(report_text(payload, "remark", "")),
          "createdAt": Json::string(report_text(payload, "created_at", "")),
          "updatedAt": Json::string(report_text(payload, "updated_at", "")),
        }),
      )
    }
  }
  lines.sort_by(fn(left, right) {
    report_text(left, "moduleCode", "").compare(
      report_text(right, "moduleCode", ""),
    )
  })
  let by_module : Map[String, Json] = {}
  let amount_total = lines.fold(init=0.0, fn(total, line) {
    total + report_amount(line, "planAmount")
  })
  let data = Json::object({
    "lines": Json::array(lines),
    "summary": Json::object({
      "count": Json::number(lines.length().to_double()),
      "amountTotal": Json::number(round_places(amount_total, 4)),
      "byModule": Json::object(by_module),
    }),
  })
  investment_excel_envelope(data, coverage)
}
