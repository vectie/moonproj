///|
/// MoonBit schema-versus-fixture gap report.
pub(all) suberror SchemaGapError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> SchemaGapError {
  SchemaGapError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SchemaGapError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SchemaGapError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SchemaGapError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise SchemaGapError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => raise fail("expected string at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn optional_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int raise SchemaGapError {
  match fields.get(key) {
    None => 0
    Some(Number(value, ..)) if value == value.trunc() => value.to_int()
    Some(_) => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn is_identifier(value : String) -> Bool {
  !value.is_empty() &&
  value
  .iter()
  .all(fn(c) { c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' })
}

///|
fn schema_tables(path : String) -> Array[String] raise SchemaGapError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SchemaGapError::Io(error)
  }
  let marker = "CREATE TABLE IF NOT EXISTS "
  let names : Array[String] = []
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    match line.find(marker) {
      Some(start) => {
        let tail = line.sub(start=start + marker.length())
        match tail.before(" ") {
          Some(view) => {
            let name = view.to_owned()
            if !is_identifier(name) {
              raise fail("unsafe schema table name: " + name)
            }
            if !names.contains(name) {
              names.push(name)
            }
          }
          None => raise fail("schema table has no name")
        }
      }
      None => ()
    }
  }
  if names.is_empty() {
    raise fail("schema initializer contains no CREATE TABLE definitions")
  }
  names.sort_by(fn(left, right) { left.lexical_compare(right) })
  names
}

///|
fn capability_family(table : String) -> String {
  if table.has_prefix("sale_") || table.has_prefix("mkt_") {
    "SAL"
  } else if table.has_prefix("srm_") || table.has_prefix("tender_") {
    "SRM"
  } else if table.has_prefix("fund_") ||
    table.has_prefix("bank_") ||
    table.has_prefix("tax_") {
    "FIN"
  } else if table.has_prefix("invoice") {
    "CTR/FIN"
  } else if table.has_prefix("wf_") {
    "WF"
  } else if table.has_prefix("proj_") || table.has_prefix("jd_") {
    "PRJ"
  } else if table.has_prefix("tzsy_") {
    "INV"
  } else if table.has_prefix("sys_") ||
    table.has_prefix("mu_") ||
    table.has_prefix("my_") {
    "FND"
  } else if table.has_prefix("vys_") || table.has_prefix("vcb_") {
    "EXP"
  } else if table.has_prefix("cb_") {
    "CTR/CST"
  } else {
    "RPT/FND"
  }
}

///|
fn capability_id(table : String) -> String {
  match table {
    "attachment" => "FND-05"
    "cb_change_apply" => "CTR-05"
    "cb_contract_milestone" => "CTR-02"
    "cb_plan_version" | "cb_r_master" | "cb_subject_dict" => "CST-01"
    "contract_split" => "CTR-05"
    "fund_dispatch" | "fund_plan" => "FIN-09"
    "invoice_in" => "FIN-03"
    "invoice_out" => "SAL-05"
    "mkt_campaign" | "mkt_channel" | "mkt_material" | "mkt_placement" =>
      "SAL-02"
    "proj_output" => "PRJ-05"
    "proj_progress" => "PRJ-03"
    "report_share_link" => "RPT-03"
    "sale_contract" => "SAL-04"
    "sale_customer" => "SAL-01"
    "sale_mortgage" => "SAL-06"
    "sale_refund" | "sale_subscription" => "SAL-03"
    "sale_revenue" => "SAL-05"
    "srm_category" | "srm_provider" | "srm_provider_bu" => "SRM-01"
    "sys_email_outbox" | "sys_message" => "FND-07"
    "sys_param" => "FND-04"
    "sys_password_history" => "FND-02"
    "sys_report_template" => "RPT-02"
    "sys_role" | "sys_user_role" => "FND-03"
    "sys_user_pref" => "FND-08"
    "sys_warning"
    | "sys_warning_rule_custom"
    | "sys_warning_scan"
    | "sys_warning_subscription"
    | "sys_warning_ticket" => "RPT-04"
    "tender_award" | "tender_plan" => "SRM-04"
    "tzsy_excel_import" | "tzsy_excel_sheet" | "tzsy_subject_mapping" =>
      "INV-02"
    "tzsy_plan_line" => "INV-01"
    "tzsy_profit_table" => "INV-04"
    "wf_approval_rule" => "WF-03"
    "wf_runtime_assignee" => "WF-04"
    _ =>
      match capability_family(table) {
        "FND" => "FND-08"
        "WF" => "WF-01"
        "PRJ" => "PRJ-01"
        "INV" => "INV-01"
        "CST" => "CST-04"
        "SRM" => "SRM-01"
        "CTR/CST" => "CTR-01"
        "CTR/FIN" => "FIN-03"
        "FIN" => "FIN-09"
        "SAL" => "SAL-01"
        "EXP" => "EXP-01"
        _ => "RPT-01"
      }
  }
}

///|
fn migration_action(table : String, present : Bool) -> String {
  if present {
    "reconcile_fixture"
  } else if table == "sys_password_history" {
    "security_review_exclude_credentials"
  } else {
    "specify_then_implement_then_import"
  }
}

///|
fn run(
  schema_path : String,
  manifest_path : String,
) -> Json raise SchemaGapError {
  let schema = schema_tables(schema_path)
  let manifest = object(read_json(manifest_path), "manifest")
  let manifest_tables = match manifest.get("tables") {
    Some(Array(values)) => values
    Some(_) => raise fail("manifest tables must be an array")
    None => raise fail("manifest has no tables")
  }
  let source_rows : Map[String, Int] = Map::Map([])
  for index in 0..<manifest_tables.length() {
    let path = "manifest.tables[" + index.to_string() + "]"
    let entry = object(manifest_tables[index], path)
    let table = required_string(entry, "table", path)
    source_rows.set(table, optional_int(entry, "rows", path))
  }
  let entries : Array[Json] = []
  let mut present_count = 0
  for table in schema {
    let present = source_rows.contains(table)
    if present {
      present_count += 1
    }
    let rows = source_rows.get_or_default(table, 0)
    entries.push(
      Json::object({
        "table": Json::string(table),
        "capability_family": Json::string(capability_family(table)),
        "capability_id": Json::string(capability_id(table)),
        "state": Json::string(
          if present {
            "present_in_snapshot"
          } else {
            "schema_only"
          },
        ),
        "snapshot_rows": Json::number(rows.to_double()),
        "migration_action": Json::string(migration_action(table, present)),
      }),
    )
  }
  Json::object({
    "format": Json::string("moonproj.erp.schema-gap.v1"),
    "schema_path": Json::string(schema_path),
    "export_manifest": Json::string(manifest_path),
    "schema_tables": Json::number(schema.length().to_double()),
    "present_tables": Json::number(present_count.to_double()),
    "schema_only_tables": Json::number(
      (schema.length() - present_count).to_double(),
    ),
    "source_snapshot_id": Json::string(
      "erp-snapshot:" + required_string(manifest, "source_sha256", "manifest"),
    ),
    "entries": Json::array(entries),
    "state": Json::string("scope_gap_recorded"),
    "cutover_authorized": Json::boolean(false),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: schema_gap <schema> <export_manifest> <output>")
    @sys.exit(2)
  }
  let report = run(args[1], args[2]) catch {
    error => {
      println("ERP schema gap report failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[3], output) catch {
    _ => {
      println("ERP schema gap report failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
