///|
pub(all) suberror RelationshipAuditError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct Relation {
  source_table : String
  source_column : String
  target_table : String
  target_column : String
}

///|
struct Record {
  relation : Relation
  references : Int
  orphans : Array[String]
}

///|
fn fail(message : String) -> RelationshipAuditError {
  RelationshipAuditError::InvalidInput(message)
}

///|
fn relation(
  source_table : String,
  source_column : String,
  target_table : String,
  target_column : String,
) -> Relation {
  { source_table, source_column, target_table, target_column }
}

///|
fn relationships() -> Array[Relation] {
  [
    relation("audit_log", "user_id", "sys_user", "user_id"),
    relation("cb_contract", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("cb_contract", "proj_guid", "ep_project", "proj_guid"),
    relation("cb_cost", "proj_guid", "ep_project", "proj_guid"),
    relation("cb_cost", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("cb_cost", "parent_cost_guid", "cb_cost", "cost_guid"),
    relation("cb_htfk_apply", "contract_guid", "cb_contract", "contract_guid"),
    relation("cb_htfk_apply", "htfk_plan_guid", "cb_htfkplan", "htfk_plan_guid"),
    relation("cb_htfk_apply", "apply_dept_guid", "mu_business_unit", "bu_guid"),
    relation("cb_htfk_apply", "applied_by", "sys_user", "user_id"),
    relation("cb_htfk_apply", "proj_guid", "ep_project", "proj_guid"),
    relation("cb_htfk_apply", "bu_guid", "mu_business_unit", "bu_guid"),
    relation(
      "cb_htfk_apply", "process_instance_guid", "wf_process_instance", "process_instance_guid",
    ),
    relation("cb_htfkplan", "contract_guid", "cb_contract", "contract_guid"),
    relation("cb_htfkplan", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("cb_htfkplan", "jbr_guid", "sys_user", "user_id"),
    relation("cb_loan_offset", "loan_guid", "vcb_loan_simple", "loan_guid"),
    relation(
      "cb_loan_offset", "related_expense_guid", "vcb_expense", "expense_guid",
    ),
    relation("cb_loan_offset", "operator_guid", "sys_user", "user_id"),
    relation("ep_project", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("jd_task", "proj_guid", "ep_project", "proj_guid"),
    relation("jd_task", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("jd_task", "parent_task_guid", "jd_task", "task_guid"),
    relation("jd_task", "owner_guid", "sys_user", "user_id"),
    relation("jd_task_report", "task_guid", "jd_task", "task_guid"),
    relation("jd_task_report", "operator_guid", "sys_user", "user_id"),
    relation("mu_business_unit", "parent_guid", "mu_business_unit", "bu_guid"),
    relation("proj_lifecycle_instance", "proj_guid", "ep_project", "proj_guid"),
    relation(
      "proj_lifecycle_instance", "stage_code", "proj_lifecycle_stage", "stage_code",
    ),
    relation("sys_user", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("sys_user", "dept_guid", "mu_business_unit", "bu_guid"),
    relation("tzsy_plan_index", "version_guid", "tzsy_version", "version_guid"),
    relation("tzsy_plan_index", "proj_guid", "ep_project", "proj_guid"),
    relation("tzsy_version", "proj_guid", "ep_project", "proj_guid"),
    relation("tzsy_version", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("tzsy_version", "created_by", "sys_user", "user_id"),
    relation("vcb_expense", "apply_dept_guid", "mu_business_unit", "bu_guid"),
    relation("vcb_expense", "applied_by", "sys_user", "user_id"),
    relation("vcb_expense", "bu_guid", "mu_business_unit", "bu_guid"),
    relation(
      "vcb_expense", "process_instance_guid", "wf_process_instance", "process_instance_guid",
    ),
    relation(
      "vcb_loan_simple", "apply_dept_guid", "mu_business_unit", "bu_guid",
    ),
    relation("vcb_loan_simple", "applied_by", "sys_user", "user_id"),
    relation("vcb_loan_simple", "bu_guid", "mu_business_unit", "bu_guid"),
    relation("vcb_loan_simple", "proj_guid", "ep_project", "proj_guid"),
    relation(
      "vcb_loan_simple", "process_instance_guid", "wf_process_instance", "process_instance_guid",
    ),
    relation("wf_process_def", "bu_guid", "mu_business_unit", "bu_guid"),
    relation(
      "wf_process_instance", "process_guid", "wf_process_def", "process_guid",
    ),
    relation("wf_process_instance", "initiator_guid", "sys_user", "user_id"),
    relation("wf_process_instance", "bu_guid", "mu_business_unit", "bu_guid"),
    relation(
      "wf_step_action", "process_instance_guid", "wf_process_instance", "process_instance_guid",
    ),
    relation("wf_step_action", "step_guid", "wf_step_def", "step_guid"),
    relation("wf_step_action", "assignee_user_guid", "sys_user", "user_id"),
    relation("wf_step_assignee", "step_guid", "wf_step_def", "step_guid"),
    relation("wf_step_assignee", "assignee_user_guid", "sys_user", "user_id"),
    relation("wf_step_def", "process_guid", "wf_process_def", "process_guid"),
    relation("cb_expense_detail", "expense_guid", "vcb_expense", "expense_guid"),
    relation("cb_expense_split", "expense_guid", "vcb_expense", "expense_guid"),
    relation("cb_expense_split", "user_guid", "sys_user", "user_id"),
    relation("cb_expense_split", "dept_guid", "mu_business_unit", "bu_guid"),
    relation(
      "cb_expense_split", "proceeding_guid", "vys_proceeding", "proceeding_guid",
    ),
  ]
}

///|
fn read_json(path : String) -> Json raise RelationshipAuditError {
  let text = @fs.read_file_to_string(path) catch {
    error => raise RelationshipAuditError::Io(error)
  }
  @json.parse(text) catch {
    _ => raise fail("cannot read JSON: " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise RelationshipAuditError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn text(
  fields : Map[String, Json],
  key : String,
) -> String raise RelationshipAuditError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    Some(_) => raise fail("manifest has invalid " + key)
    None => raise fail("manifest has no " + key)
  }
}

///|
fn quote(value : String) -> String {
  "\"" +
  value.split("\"").map(fn(part) { part.to_owned() }).to_array().join("\"\"") +
  "\""
}

///|
fn write_sql(work_dir : String) -> Unit raise RelationshipAuditError {
  let mut sql = ""
  for rel in relationships() {
    let source = quote(rel.source_table)
    let target = quote(rel.target_table)
    let source_col = quote(rel.source_column)
    let target_col = quote(rel.target_column)
    let source_ref = "CAST(s." + source_col + " AS TEXT)"
    let target_ref = "CAST(t." + target_col + " AS TEXT)"
    let nonempty = "s." +
      source_col +
      " IS NOT NULL AND TRIM(" +
      source_ref +
      ") <> ''"
    let prefix = "'R|" +
      rel.source_table +
      "|" +
      rel.source_column +
      "|" +
      rel.target_table +
      "|" +
      rel.target_column +
      "|'"
    sql += "SELECT " +
      prefix +
      " || (SELECT count(*) FROM " +
      source +
      " s WHERE " +
      nonempty +
      ");\n"
    sql += "SELECT 'O|" +
      rel.source_table +
      "|" +
      rel.source_column +
      "|" +
      rel.target_table +
      "|" +
      rel.target_column +
      "|' || hex(" +
      source_ref +
      ") FROM " +
      source +
      " s LEFT JOIN " +
      target +
      " t ON " +
      target_ref +
      " = " +
      source_ref +
      " WHERE " +
      nonempty +
      " AND t." +
      target_col +
      " IS NULL ORDER BY 1;\n"
  }
  @fs.write_string_to_file(work_dir + "/audit.sql", sql) catch {
    error => raise RelationshipAuditError::Io(error)
  }
}

///|
fn parse_int(value : String) -> Int raise RelationshipAuditError {
  let source = value.trim().to_owned()
  if source.is_empty() {
    raise fail("invalid relationship reference count")
  }
  let mut result = 0
  for char in source.iter() {
    if char < '0' || char > '9' {
      raise fail("invalid relationship reference count")
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  result
}

///|
fn decode_hex(value : String) -> String raise RelationshipAuditError {
  if value.length() % 2 != 0 {
    raise fail("invalid relationship orphan value")
  }
  let bytes : FixedArray[Byte] = FixedArray::make(value.length() / 2, 0)
  fn digit(char : Char) -> Int? {
    if char >= '0' && char <= '9' {
      Some(char.to_int() - '0'.to_int())
    } else if char >= 'a' && char <= 'f' {
      Some(char.to_int() - 'a'.to_int() + 10)
    } else if char >= 'A' && char <= 'F' {
      Some(char.to_int() - 'A'.to_int() + 10)
    } else {
      None
    }
  }
  for index in 0..<(value.length() / 2) {
    let high = digit(value.get_char(index * 2).unwrap()).unwrap_or(-1)
    let low = digit(value.get_char(index * 2 + 1).unwrap()).unwrap_or(-1)
    if high < 0 || low < 0 {
      raise fail("invalid relationship orphan value")
    }
    bytes[index] = (high * 16 + low).to_byte()
  }
  @encoding/utf8.decode_lossy(bytes.unsafe_reinterpret_as_bytes())
}

///|
fn same(left : Relation, right : Relation) -> Bool {
  left.source_table == right.source_table &&
  left.source_column == right.source_column &&
  left.target_table == right.target_table &&
  left.target_column == right.target_column
}

///|
fn find_record(records : Array[Record], rel : Relation) -> Record? {
  for record in records {
    if same(record.relation, rel) {
      return Some(record)
    }
  }
  None
}

///|
fn parse_records(path : String) -> Array[Record] raise RelationshipAuditError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise RelationshipAuditError::Io(error)
  }
  let records : Array[Record] = []
  for view in content.split("\n") {
    let line = view.to_owned()
    if !line.is_empty() {
      let values = line
        .split("|")
        .map(fn(value) { value.to_owned() })
        .to_array()
      if values.length() != 6 {
        raise fail("unexpected relationship audit row")
      }
      let rel = relation(values[1], values[2], values[3], values[4])
      if values[0] == "R" {
        records.push({
          relation: rel,
          references: parse_int(values[5]),
          orphans: [],
        })
      } else if values[0] == "O" {
        let value = decode_hex(values[5])
        let mut found = false
        for index in 0..<records.length() {
          if same(records[index].relation, rel) {
            records[index].orphans.push(value)
            found = true
          }
        }
        if !found {
          records.push({ relation: rel, references: 0, orphans: [value] })
        }
      } else {
        raise fail("unexpected relationship audit record type")
      }
    }
  }
  records
}

///|
fn report(
  manifest_path : String,
  rows_path : String,
  database : String,
  output_path : String,
) -> Unit raise RelationshipAuditError {
  let manifest = object(read_json(manifest_path), "manifest")
  let source_hash = text(manifest, "source_sha256")
  if source_hash.length() != 64 {
    raise fail("export manifest has no valid source hash")
  }
  let records = parse_records(rows_path)
  let reports : Array[Json] = []
  let mut reference_count = 0
  let mut orphan_count = 0
  for rel in relationships() {
    let record = match find_record(records, rel) {
      Some(value) => value
      None =>
        raise fail(
          "relationship audit did not return " +
          rel.source_table +
          " -> " +
          rel.target_table,
        )
    }
    reference_count += record.references
    orphan_count += record.orphans.length()
    let orphan_values = record.orphans.copy()
    orphan_values.sort_by(fn(left, right) { left.lexical_compare(right) })
    reports.push(
      Json::object({
        "source_table": Json::string(rel.source_table),
        "source_column": Json::string(rel.source_column),
        "target_table": Json::string(rel.target_table),
        "target_column": Json::string(rel.target_column),
        "references_checked": Json::number(
          record.references.to_double(),
          repr=record.references.to_string(),
        ),
        "orphan_values": Json::array(
          orphan_values.map(fn(value) { Json::string(value) }),
        ),
        "state": Json::string(
          if orphan_values.is_empty() {
            "ok"
          } else {
            "orphaned"
          },
        ),
      }),
    )
  }
  let state = if orphan_count == 0 {
    "relationship_integrity_verified"
  } else {
    "orphaned_references_found"
  }
  let result = Json::object({
    "format": Json::string("moonproj.erp.relationship-audit.v1"),
    "database": Json::string(database),
    "export_manifest": Json::string(manifest_path),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_hash),
    "relationship_count": Json::number(
      relationships().length().to_double(),
      repr=relationships().length().to_string(),
    ),
    "reference_count": Json::number(
      reference_count.to_double(),
      repr=reference_count.to_string(),
    ),
    "orphan_count": Json::number(
      orphan_count.to_double(),
      repr=orphan_count.to_string(),
    ),
    "relationships": Json::array(reports),
    "state": Json::string(state),
    "cutover_authorized": Json::boolean(false),
  })
  @fs.write_string_to_file(output_path, result.stringify(indent=2) + "\n") catch {
    error => raise RelationshipAuditError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "relationship_count": Json::number(relationships().length().to_double()),
      "reference_count": Json::number(reference_count.to_double()),
      "orphan_count": Json::number(orphan_count.to_double()),
      "state": Json::string(state),
    }).stringify(),
  )
  if orphan_count != 0 {
    raise fail("orphaned references found")
  }
}

///|
fn run(args : Array[String]) -> Unit raise RelationshipAuditError {
  if args.length() < 2 {
    raise fail("usage: relationship_audit <prepare|report> ...")
  }
  match args[1] {
    "prepare" if args.length() >= 4 => write_sql(args[3])
    "report" if args.length() >= 6 => report(args[2], args[3], args[4], args[5])
    _ => raise fail("invalid relationship audit arguments")
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  run(args) catch {
    RelationshipAuditError::InvalidInput(message) => {
      println("ERP relationship audit failed: " + message)
      @sys.exit(1)
    }
    RelationshipAuditError::Io(_) => {
      println("ERP relationship audit failed: filesystem error")
      @sys.exit(1)
    }
  }
}
