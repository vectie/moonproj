///|
/// Compile a reviewed supplier/tender/commitment procurement cohort map.
pub(all) suberror ProcurementCohortPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> ProcurementCohortPlanError {
  ProcurementCohortPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise ProcurementCohortPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ProcurementCohortPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise ProcurementCohortPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ProcurementCohortPlanError {
  match fields.get(key) {
    Some(value) => value
    None => raise fail("missing field " + path + "." + key)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ProcurementCohortPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  key : String,
  fallback : String,
  path : String,
) -> String raise ProcurementCohortPlanError {
  match fields.get(key) {
    None => fallback
    Some(String(value)) if !value.trim().is_empty() => value
    Some(_) => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise ProcurementCohortPlanError {
  match required(fields, key, path) {
    True => true
    False => false
    _ => raise fail("expected boolean at " + path + "." + key)
  }
}

///|
fn required_int(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int64 raise ProcurementCohortPlanError {
  match required(fields, key, path) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise fail("expected integer at " + path + "." + key)
  }
}

///|
fn required_array(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Array[Json] raise ProcurementCohortPlanError {
  match required(fields, key, path) {
    Array(values) if !values.is_empty() => values
    _ => raise fail("expected non-empty array at " + path + "." + key)
  }
}

///|
fn secret_key(key : String) -> Bool {
  let lowered = key.to_lower()
  lowered.contains("password") ||
  lowered.contains("secret") ||
  lowered.contains("token") ||
  lowered.contains("private") ||
  lowered.has_suffix("ip")
}

///|
fn reject_secret_keys(
  value : Json,
  path : String,
) -> Unit raise ProcurementCohortPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secret_keys(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secret_keys(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise ProcurementCohortPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.procurement-cohort-map.v1" {
    raise fail("unexpected procurement map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("procurement map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let suppliers = required_array(root, "suppliers", "mapping")
  let tenders = required_array(root, "tenders", "mapping")
  let supplier_ids : Array[String] = []
  let normalized_suppliers : Array[Json] = []
  for index in 0..<suppliers.length() {
    let path = "suppliers[" + index.to_string() + "]"
    let supplier = object(suppliers[index], path)
    let source_table = required_string(supplier, "source_table", path)
    let source_id = required_string(supplier, "source_id", path)
    let supplier_id = required_string(supplier, "supplier_id", path)
    let principal_id = required_string(supplier, "principal_id", path)
    let scope = required_string(supplier, "scope", path)
    let supplier_code = required_string(supplier, "supplier_code", path)
    let name = required_string(supplier, "name", path)
    let category_code = required_string(supplier, "category_code", path)
    let evaluation = required_string(supplier, "expected_evaluation", path)
    let state = required_string(supplier, "expected_state", path)
    if supplier_ids.contains(supplier_id) {
      raise fail("duplicate supplier_id: " + supplier_id)
    }
    if (evaluation != "qualified" && evaluation != "strategic") ||
      state != "active" {
      raise fail("supplier evaluation or state is invalid at " + path)
    }
    supplier_ids.push(supplier_id)
    normalized_suppliers.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "supplier_id": Json::string(supplier_id),
        "principal_id": Json::string(principal_id),
        "scope": Json::string(scope),
        "supplier_code": Json::string(supplier_code),
        "name": Json::string(name),
        "category_code": Json::string(category_code),
        "expected_evaluation": Json::string(evaluation),
        "expected_state": Json::string(state),
      }),
    )
  }
  let tender_ids : Array[String] = []
  let commitment_ids : Array[String] = []
  let normalized_tenders : Array[Json] = []
  for index in 0..<tenders.length() {
    let path = "tenders[" + index.to_string() + "]"
    let tender = object(tenders[index], path)
    let source_table = required_string(tender, "source_table", path)
    let source_id = required_string(tender, "source_id", path)
    let tender_id = required_string(tender, "tender_id", path)
    let principal_id = required_string(tender, "principal_id", path)
    let project_scope = required_string(tender, "project_scope", path)
    let name = required_string(tender, "name", path)
    let category = required_string(tender, "category", path)
    let currency = required_string(tender, "currency", path)
    let estimated = required_int(tender, "estimated_amount_minor", path)
    let bids = required_array(tender, "bids", path)
    let awarded_supplier_id = required_string(
      tender, "awarded_supplier_id", path,
    )
    let awarded_amount = required_int(tender, "awarded_amount_minor", path)
    let commitment_id = required_string(tender, "commitment_id", path)
    let tender_state = required_string(tender, "expected_tender_state", path)
    let commitment_state = required_string(
      tender, "expected_commitment_state", path,
    )
    if tender_ids.contains(tender_id) {
      raise fail("duplicate tender_id: " + tender_id)
    }
    if commitment_ids.contains(commitment_id) {
      raise fail("duplicate commitment_id: " + commitment_id)
    }
    if !supplier_ids.contains(awarded_supplier_id) ||
      tender_state != "awarded" ||
      commitment_state != "performed" ||
      estimated < 1 ||
      awarded_amount < 1 ||
      awarded_amount > estimated ||
      bids.length() < 2 {
      raise fail(
        "tender award, commitment, amount, or bids are invalid at " + path,
      )
    }
    let bid_supplier_ids : Array[String] = []
    let normalized_bids : Array[Json] = []
    let mut awarded_match = false
    for bid_index in 0..<bids.length() {
      let bid_path = path + ".bids[" + bid_index.to_string() + "]"
      let bid = object(bids[bid_index], bid_path)
      let bid_supplier_id = required_string(bid, "supplier_id", bid_path)
      let bid_id = required_string(bid, "bid_id", bid_path)
      let amount = required_int(bid, "amount_minor", bid_path)
      let bid_currency = optional_string(bid, "currency", currency, bid_path)
      if !supplier_ids.contains(bid_supplier_id) ||
        amount < 1 ||
        amount > estimated ||
        bid_currency != currency ||
        bid_supplier_ids.contains(bid_supplier_id) {
        raise fail("bid is invalid at " + bid_path)
      }
      if bid_supplier_id == awarded_supplier_id {
        if amount != awarded_amount {
          raise fail("awarded amount differs from awarded bid at " + path)
        }
        awarded_match = true
      }
      bid_supplier_ids.push(bid_supplier_id)
      normalized_bids.push(
        Json::object({
          "supplier_id": Json::string(bid_supplier_id),
          "bid_id": Json::string(bid_id),
          "amount_minor": number(amount),
          "currency": Json::string(bid_currency),
        }),
      )
    }
    if !awarded_match {
      raise fail("awarded supplier has no matching bid at " + path)
    }
    tender_ids.push(tender_id)
    commitment_ids.push(commitment_id)
    normalized_tenders.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "tender_id": Json::string(tender_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "name": Json::string(name),
        "category": Json::string(category),
        "currency": Json::string(currency),
        "estimated_amount_minor": number(estimated),
        "bids": Json::array(normalized_bids),
        "awarded_supplier_id": Json::string(awarded_supplier_id),
        "awarded_amount_minor": number(awarded_amount),
        "commitment_id": Json::string(commitment_id),
        "expected_tender_state": Json::string(tender_state),
        "expected_commitment_state": Json::string(commitment_state),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.procurement-cohort-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "suppliers": number(normalized_suppliers.length().to_int64()),
      "tenders": number(normalized_tenders.length().to_int64()),
      "commitments": number(normalized_tenders.length().to_int64()),
    }),
    "suppliers": Json::array(normalized_suppliers),
    "tenders": Json::array(normalized_tenders),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise ProcurementCohortPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "suppliers": number(normalized_suppliers.length().to_int64()),
      "tenders": number(normalized_tenders.length().to_int64()),
      "commitments": number(normalized_tenders.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: procurement_cohort_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    ProcurementCohortPlanError::InvalidInput(message) => {
      println("procurement cohort plan failed: " + message)
      @sys.exit(1)
    }
    ProcurementCohortPlanError::Io(_) => {
      println("procurement cohort plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
