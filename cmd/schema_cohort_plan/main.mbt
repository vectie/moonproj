///|
/// MoonBit compiler for the ordered ERP schema-only migration cohorts.
pub(all) suberror SchemaCohortError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct CohortEntry {
  table : String
  capability_id : Json
  wave : String
  snapshot_rows : Json
  mut declared_dependencies : Array[String]
  migration_action : String
}

///|
let wave_order : Array[String] = [
  "foundation-security", "workflow-control", "cost-investment", "procurement-contract",
  "sales-receivables", "delivery-treasury", "reporting-notification",
]

///|
let table_waves : Map[String, String] = Map::Map([
  ("attachment", "foundation-security"),
  ("sys_role", "foundation-security"),
  ("sys_user_role", "foundation-security"),
  ("sys_password_history", "foundation-security"),
  ("sys_user_pref", "foundation-security"),
  ("sys_param", "foundation-security"),
  ("wf_approval_rule", "workflow-control"),
  ("wf_runtime_assignee", "workflow-control"),
  ("sys_warning", "workflow-control"),
  ("sys_warning_scan", "workflow-control"),
  ("sys_warning_subscription", "workflow-control"),
  ("sys_warning_rule_custom", "workflow-control"),
  ("sys_warning_ticket", "workflow-control"),
  ("cb_r_master", "cost-investment"),
  ("cb_subject_dict", "cost-investment"),
  ("cb_plan_version", "cost-investment"),
  ("tzsy_excel_import", "cost-investment"),
  ("tzsy_excel_sheet", "cost-investment"),
  ("tzsy_profit_table", "cost-investment"),
  ("tzsy_plan_line", "cost-investment"),
  ("tzsy_subject_mapping", "cost-investment"),
  ("cb_change_apply", "cost-investment"),
  ("cb_contract_milestone", "procurement-contract"),
  ("contract_split", "procurement-contract"),
  ("tender_plan", "procurement-contract"),
  ("tender_award", "procurement-contract"),
  ("srm_provider", "procurement-contract"),
  ("srm_provider_bu", "procurement-contract"),
  ("srm_category", "procurement-contract"),
  ("sale_customer", "sales-receivables"),
  ("sale_subscription", "sales-receivables"),
  ("sale_contract", "sales-receivables"),
  ("sale_mortgage", "sales-receivables"),
  ("sale_refund", "sales-receivables"),
  ("sale_revenue", "sales-receivables"),
  ("invoice_in", "sales-receivables"),
  ("invoice_out", "sales-receivables"),
  ("proj_progress", "delivery-treasury"),
  ("proj_output", "delivery-treasury"),
  ("fund_plan", "delivery-treasury"),
  ("fund_dispatch", "delivery-treasury"),
  ("mkt_campaign", "delivery-treasury"),
  ("mkt_placement", "delivery-treasury"),
  ("mkt_channel", "delivery-treasury"),
  ("mkt_material", "delivery-treasury"),
  ("sys_message", "reporting-notification"),
  ("sys_email_outbox", "reporting-notification"),
  ("sys_report_template", "reporting-notification"),
  ("report_share_link", "reporting-notification"),
])

///|
let special_actions : Map[String, String] = Map::Map([
  ("sys_password_history", "security_review_exclude_credentials"),
  ("report_share_link", "security_review_redact_tokens"),
  ("attachment", "content_hash_and_retention_review"),
  ("sys_email_outbox", "redact_network_and_message_secrets"),
])

///|
let wave_dependencies : Map[String, Array[String]] = Map::Map([
  ("foundation-security", []),
  ("workflow-control", ["foundation-security"]),
  ("cost-investment", ["foundation-security"]),
  ("procurement-contract", ["foundation-security", "cost-investment"]),
  (
    "sales-receivables",
    ["foundation-security", "workflow-control", "procurement-contract"],
  ),
  (
    "delivery-treasury",
    [
      "foundation-security", "workflow-control", "cost-investment", "procurement-contract",
    ],
  ),
  ("reporting-notification", ["foundation-security", "workflow-control"]),
])

///|
fn fail(message : String) -> SchemaCohortError {
  SchemaCohortError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise SchemaCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise SchemaCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot parse JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise SchemaCohortError {
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
) -> String raise SchemaCohortError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => raise fail("expected string at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise SchemaCohortError {
  match fields.get(key) {
    Some(Array(values)) => values
    Some(_) => raise fail("expected array at " + path + "." + key)
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn wave_index(wave : String) -> Int {
  let mut result = -1
  for index in 0..<wave_order.length() {
    if wave_order[index] == wave {
      result = index
    }
  }
  result
}

///|
fn table_name_after(line : String, marker : String) -> String? {
  match line.find(marker) {
    Some(start) => {
      let tail = line.sub(start=start + marker.length())
      match tail.before(" ") {
        Some(view) => Some(view.to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
fn reference_names(line : String) -> Array[String] {
  let marker = "REFERENCES "
  let names : Array[String] = []
  let mut cursor = 0
  while cursor < line.length() {
    let remaining = line.sub(start=cursor)
    match remaining.find(marker) {
      Some(offset) => {
        let start = cursor + offset
        let tail = line.sub(start=start + marker.length())
        match tail.before(" ") {
          Some(view) => names.push(view.to_owned())
          None => ()
        }
        cursor = start + marker.length()
      }
      None => cursor = line.length()
    }
  }
  names
}

///|
fn schema_references(
  path : String,
) -> Map[String, Array[String]] raise SchemaCohortError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise SchemaCohortError::Io(error)
  }
  let references : Map[String, Array[String]] = Map::Map([])
  let mut current : String? = None
  let marker = "CREATE TABLE IF NOT EXISTS "
  for line_view in text.split("\n") {
    let line = line_view.to_owned()
    match table_name_after(line, marker) {
      Some(table) => {
        current = Some(table)
        references.set(table, [])
      }
      None => ()
    }
    match current {
      Some(table) => {
        let found = references.get_or_default(table, [])
        for name in reference_names(line) {
          if !found.contains(name) {
            found.push(name)
          }
        }
        references.set(table, found)
        if line.contains(");") {
          current = None
        }
      }
      None => ()
    }
  }
  references
}

///|
fn table_in(values : Array[CohortEntry], table : String) -> Bool {
  values.any(fn(entry) { entry.table == table })
}

///|
fn sorted_dependencies(
  table : String,
  references : Map[String, Array[String]],
  entries : Array[CohortEntry],
) -> Array[String] {
  let result = references
    .get_or_default(table, [])
    .filter(fn(name) { table_in(entries, name) })
  result.sort_by(fn(left, right) { left.lexical_compare(right) })
  result
}

///|
fn entry_compare(left : CohortEntry, right : CohortEntry) -> Int {
  let wave_comparison = wave_index(left.wave) - wave_index(right.wave)
  if wave_comparison != 0 {
    wave_comparison
  } else {
    left.table.lexical_compare(right.table)
  }
}

///|
fn add_unique(values : Array[String], value : String) -> Array[String] {
  if !values.contains(value) {
    values.push(value)
  }
  values
}

///|
fn run(schema_path : String, gap_path : String) -> Json raise SchemaCohortError {
  let references = schema_references(schema_path)
  let gap = object(read_json(gap_path), "schema-gap")
  let gap_entries = required_array(gap, "entries", "schema-gap")
  let schema_only : Array[CohortEntry] = []
  for index in 0..<gap_entries.length() {
    let path = "schema-gap.entries[" + index.to_string() + "]"
    let entry = object(gap_entries[index], path)
    if required_string(entry, "state", path) == "schema_only" {
      let table = required_string(entry, "table", path)
      let wave = match table_waves.get(table) {
        Some(value) => value
        None => raise fail("schema-only table lacks an assigned wave: " + table)
      }
      let migration_action = special_actions.get_or_default(
        table, "specify_then_implement_then_import",
      )
      schema_only.push(CohortEntry::{
        table,
        capability_id: match entry.get("capability_id") {
          Some(value) => value
          None => Json::null()
        },
        wave,
        snapshot_rows: match entry.get("snapshot_rows") {
          Some(value) => value
          None => Json::number(0.0)
        },
        declared_dependencies: [],
        migration_action,
      })
    }
  }
  if schema_only.length() != 49 {
    raise fail(
      "expected 49 schema-only entries, found " +
      schema_only.length().to_string(),
    )
  }
  for entry in schema_only {
    entry.declared_dependencies = sorted_dependencies(
      entry.table,
      references,
      schema_only,
    )
  }
  schema_only.sort_by(entry_compare)
  let waves : Array[Json] = []
  for wave in wave_order {
    let tables : Array[String] = []
    for entry in schema_only {
      if entry.wave == wave {
        tables.push(entry.table)
      }
    }
    if tables.length() > 0 {
      let mut dependencies = wave_dependencies.get_or_default(wave, []).copy()
      for entry in schema_only {
        if entry.wave == wave {
          for dependency in entry.declared_dependencies {
            match table_waves.get(dependency) {
              Some(dependency_wave) if dependency_wave != wave =>
                dependencies = add_unique(dependencies, dependency_wave)
              _ => ()
            }
          }
        }
      }
      dependencies.sort_by(fn(left, right) {
        wave_index(left) - wave_index(right)
      })
      let required : Array[Json] = [
        Json::string("credential-safe export"),
        Json::string("row-level relationship audit"),
        Json::string("explicit principal/identity mappings"),
        Json::string("domain importer and exact parity/replay evidence"),
      ]
      waves.push(
        Json::object({
          "wave": Json::string(wave),
          "sequence": Json::number((wave_index(wave) + 1).to_double()),
          "tables": Json::array(tables.map(fn(table) { Json::string(table) })),
          "depends_on_waves": Json::array(
            dependencies.map(fn(value) { Json::string(value) }),
          ),
          "requires": Json::array(required),
        }),
      )
    }
  }
  let entries_json : Array[Json] = schema_only.map(fn(entry) {
    Json::object({
      "table": Json::string(entry.table),
      "capability_id": entry.capability_id,
      "wave": Json::string(entry.wave),
      "state": Json::string("schema_only"),
      "snapshot_rows": entry.snapshot_rows,
      "declared_schema_dependencies": Json::array(
        entry.declared_dependencies.map(fn(value) { Json::string(value) }),
      ),
      "migration_action": Json::string(entry.migration_action),
      "cutover_authorized": Json::boolean(false),
    })
  })
  Json::object({
    "format": Json::string("moonproj.erp.schema-cohort-plan.v1"),
    "schema_gap_format": match gap.get("format") {
      Some(value) => value
      None => Json::null()
    },
    "schema_tables": match gap.get("schema_tables") {
      Some(value) => value
      None => Json::null()
    },
    "present_tables": match gap.get("present_tables") {
      Some(value) => value
      None => Json::null()
    },
    "schema_only_tables": Json::number(entries_json.length().to_double()),
    "state": Json::string("schema_cohorts_planned"),
    "cutover_authorized": Json::boolean(false),
    "waves": Json::array(waves),
    "entries": Json::array(entries_json),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: schema_cohort_plan <schema> <schema_gap> <output>")
    @sys.exit(2)
  }
  let report = run(args[1], args[2]) catch {
    error => {
      println("ERP schema cohort plan failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[3], output) catch {
    _ => {
      println("ERP schema cohort plan failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
