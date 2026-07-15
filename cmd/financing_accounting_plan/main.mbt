///|
pub(all) suberror FinancingAccountingPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> FinancingAccountingPlanError {
  FinancingAccountingPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise FinancingAccountingPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise FinancingAccountingPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise FinancingAccountingPlanError {
  match value {
    Object(fields) => fields
    _ => raise fail("expected object at " + path)
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn required_string(
  value : Json,
  key : String,
) -> String raise FinancingAccountingPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_bool(
  value : Json,
  key : String,
) -> Bool raise FinancingAccountingPlanError {
  match value {
    True => true
    False => false
    _ => raise fail(key + " must be boolean")
  }
}

///|
fn parse_integer(value : String, default : Int64) -> Int64 {
  let source = value.trim()
  if source.is_empty() {
    return default
  }
  let mut index = 0
  let mut sign : Int64 = 1
  match source.get_char(0) {
    Some('-') => {
      sign = -1
      index = 1
    }
    Some('+') => index = 1
    _ => ()
  }
  let mut result : Int64 = 0
  while index < source.length() {
    let char = source.get_char(index).unwrap()
    if char < '0' || char > '9' {
      return default
    }
    result = result * 10 + (char.to_int() - '0'.to_int()).to_int64()
    index += 1
  }
  result * sign
}

///|
fn integer(
  value : Json,
  key : String,
  minimum : Int64,
) -> Int64 raise FinancingAccountingPlanError {
  let result = match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), 0L)
    _ => raise fail(key + " must be an integer >= " + minimum.to_string())
  }
  if result < minimum {
    raise fail(key + " must be an integer >= " + minimum.to_string())
  }
  result
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
fn reject_secrets(
  value : Json,
  path : String,
) -> Unit raise FinancingAccountingPlanError {
  match value {
    Object(fields) =>
      for key in fields.keys() {
        if secret_key(key) {
          raise fail("secret-shaped key at " + path + "." + key)
        }
        match fields.get(key) {
          Some(child) => reject_secrets(child, path + "." + key)
          None => ()
        }
      }
    Array(values) =>
      for index in 0..<values.length() {
        reject_secrets(values[index], path + "[" + index.to_string() + "]")
      }
    _ => ()
  }
}

///|
fn map_string(
  mapping : Map[String, Json],
  key : String,
  path : String,
) -> String raise FinancingAccountingPlanError {
  required_string(mapping.get(key).unwrap_or(Json::null()), path + "." + key)
}

///|
fn event_map(
  mappings : Map[String, Json],
  source_id : String,
  action : String,
) -> Map[String, Json] raise FinancingAccountingPlanError {
  let value = object(
    mappings.get("financing_facility:" + source_id).unwrap_or(Json::null()),
    "accounting map",
  ) catch {
    FinancingAccountingPlanError::InvalidInput(_) =>
      raise fail("missing accounting map for financing_facility:" + source_id)
    FinancingAccountingPlanError::Io(_) =>
      raise fail("missing accounting map for financing_facility:" + source_id)
  }
  if map_string(value, "action", "accounting map") != action {
    raise fail("financing map action mismatch for " + source_id)
  }
  value
}

///|
fn event_json(
  source_id : String,
  mapping : Map[String, Json],
  scope : String,
) -> Json {
  Json::object({
    "source_id": Json::string(source_id),
    "event_id": field(Json::object(mapping), "event_id"),
    "event_type": field(Json::object(mapping), "event_type"),
    "journal_id": field(Json::object(mapping), "journal_id"),
    "description": field(Json::object(mapping), "description"),
    "scope": Json::string(scope),
    "debit_account": field(Json::object(mapping), "debit_account"),
    "credit_account": field(Json::object(mapping), "credit_account"),
    "amount_minor": field(Json::object(mapping), "amount_minor"),
  })
}

///|
fn run(
  facility_plan_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise FinancingAccountingPlanError {
  let facility_plan = object(read_json(facility_plan_path), "facility plan")
  let config_value = read_json(mapping_path)
  reject_secrets(config_value, "mapping")
  let config = object(config_value, "mapping")
  if required_string(field(Json::object(facility_plan), "format"), "format") !=
    "moonproj.erp.financing-facility-plan.v1" ||
    !required_bool(field(Json::object(facility_plan), "reviewed"), "reviewed") {
    raise fail("financing plan is not reviewed")
  }
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.financing-accounting-map.v1" ||
    !required_bool(field(Json::object(config), "reviewed"), "reviewed") {
    raise fail("financing accounting map is not reviewed")
  }
  let source_snapshot_id = required_string(
    field(Json::object(facility_plan), "source_snapshot_id"),
    "source_snapshot_id",
  )
  if required_string(
      field(Json::object(config), "source_snapshot_id"),
      "source_snapshot_id",
    ) !=
    source_snapshot_id {
    raise fail(
      "financing accounting map source snapshot differs from facility plan",
    )
  }
  let mappings = object(
    field(Json::object(config), "accounting_by_source"),
    "accounting_by_source",
  )
  let facilities = match field(Json::object(facility_plan), "facilities") {
    Array(values) if !values.is_empty() => values
    _ => raise fail("facility plan has no facilities")
  }
  let output_facilities : Array[Json] = []
  for index in 0..<facilities.length() {
    let facility = object(facilities[index], "facility")
    let facility_id = required_string(
      field(Json::object(facility), "facility_id"),
      "facility_id",
    )
    let source_id = required_string(
      field(Json::object(facility), "source_id"),
      "source_id",
    )
    let principal_id = required_string(
      field(Json::object(facility), "principal_id"),
      "principal_id",
    )
    let scope = required_string(
      field(Json::object(facility), "project_scope"),
      "project_scope",
    )
    let currency = required_string(
      field(Json::object(facility), "currency"),
      "currency",
    )
    let draw_amount = integer(
      field(Json::object(facility), "draw_amount_minor"),
      "draw_amount_minor",
      1L,
    )
    let repay_amount = integer(
      field(Json::object(facility), "repay_amount_minor"),
      "repay_amount_minor",
      1L,
    )
    let draw_id = facility_id + "/draw"
    let repayment_id = facility_id + "/repayment"
    let draw = event_map(mappings, draw_id, "draw")
    let repayment = event_map(mappings, repayment_id, "repayment")
    let mapping_fields = [
      "event_id", "event_type", "journal_id", "description", "scope", "debit_account",
      "credit_account", "principal_id", "currency",
    ]
    for
      triple in [
        ("draw", draw, draw_amount),
        ("repayment", repayment, repay_amount),
      ] {
      let action = triple.0
      let mapping = triple.1
      let expected = triple.2
      for key in mapping_fields {
        if field(Json::object(mapping), key) is Null ||
          !nonempty(field(Json::object(mapping), key)) {
          raise fail(action + " accounting map missing " + key)
        }
      }
      if text(field(Json::object(mapping), "principal_id")) != principal_id ||
        text(field(Json::object(mapping), "scope")) != scope ||
        text(field(Json::object(mapping), "currency")) != currency ||
        integer(
          field(Json::object(mapping), "amount_minor"),
          "amount_minor",
          0L,
        ) !=
        expected {
        raise fail(
          action + " accounting identity/amount mismatch for " + facility_id,
        )
      }
      let expected_journal = "financing/" +
        (if action == "draw" {
          draw_id + "/draw"
        } else {
          repayment_id + "/repayment"
        })
      if text(field(Json::object(mapping), "journal_id")) != expected_journal {
        raise fail(action + " journal identity mismatch for " + facility_id)
      }
    }
    output_facilities.push(
      Json::object({
        "source_table": Json::string(
          required_string(
            field(Json::object(facility), "source_table"),
            "source_table",
          ),
        ),
        "source_id": Json::string(source_id),
        "facility_id": Json::string(facility_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(scope),
        "lender_id": Json::string(
          required_string(
            field(Json::object(facility), "lender_id"),
            "lender_id",
          ),
        ),
        "currency": Json::string(currency),
        "limit_amount_minor": Json::number(
          integer(
            field(Json::object(facility), "limit_amount_minor"),
            "limit_amount_minor",
            1L,
          ).to_double(),
          repr=integer(
            field(Json::object(facility), "limit_amount_minor"),
            "limit_amount_minor",
            1L,
          ).to_string(),
        ),
        "annual_rate_bps": Json::number(
          integer(
            field(Json::object(facility), "annual_rate_bps"),
            "annual_rate_bps",
            0L,
          ).to_double(),
          repr=integer(
            field(Json::object(facility), "annual_rate_bps"),
            "annual_rate_bps",
            0L,
          ).to_string(),
        ),
        "draw_amount_minor": Json::number(
          draw_amount.to_double(),
          repr=draw_amount.to_string(),
        ),
        "repay_amount_minor": Json::number(
          repay_amount.to_double(),
          repr=repay_amount.to_string(),
        ),
        "draw": event_json(draw_id, draw, scope),
        "repayment": event_json(repayment_id, repayment, scope),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.financing-accounting-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(
      required_string(
        field(Json::object(config), "mapping_version"),
        "mapping_version",
      ),
    ),
    "run_id": Json::string(
      required_string(field(Json::object(config), "run_id"), "run_id"),
    ),
    "facilities": Json::array(output_facilities),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise FinancingAccountingPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "facilities": Json::number(
        output_facilities.length().to_double(),
        repr=output_facilities.length().to_string(),
      ),
      "links": Json::number(
        (output_facilities.length() * 2).to_double(),
        repr=(output_facilities.length() * 2).to_string(),
      ),
    }).stringify(),
  )
}

///|
fn nonempty(value : Json) -> Bool {
  match value {
    String(value) => !value.trim().is_empty()
    _ => false
  }
}

///|
fn text(value : Json) -> String {
  match value {
    String(value) => value
    Number(value, ..) => value.to_string()
    True => "true"
    False => "false"
    _ => ""
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println(
      "usage: financing_accounting_plan <facility-plan.json> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    FinancingAccountingPlanError::InvalidInput(message) => {
      println("financing accounting plan failed: " + message)
      @sys.exit(1)
    }
    FinancingAccountingPlanError::Io(_) => {
      println("financing accounting plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
