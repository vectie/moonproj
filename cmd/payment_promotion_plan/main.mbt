///|
pub(all) suberror PaymentPromotionPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> PaymentPromotionPlanError {
  PaymentPromotionPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise PaymentPromotionPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PaymentPromotionPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise PaymentPromotionPlanError {
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
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    String(value) => !value.is_empty()
    Number(value, ..) => value != 0.0
    _ => true
  }
}

///|
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) if number == number.trunc() => number.to_int().to_int64()
    String(value) => {
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
        let c = source.get_char(index).unwrap()
        if c < '0' || c > '9' {
          return default
        }
        result = result * 10 + (c.to_int() - '0'.to_int()).to_int64()
        index += 1
      }
      result * sign
    }
    _ => default
  }
}

///|
fn power10(digits : Int) -> Int64 {
  let mut value : Int64 = 1
  for _ in 0..<digits {
    value *= 10
  }
  value
}

///|
fn money_minor(
  value : Json,
  policy : Map[String, Json],
) -> Int64 raise PaymentPromotionPlanError {
  let source = text(value).trim().to_owned()
  if source.is_empty() {
    raise fail("invalid monetary value: " + source)
  }
  let scale = integer(field(Json::object(policy), "minor_units_per_unit"), 100L)
  if scale <= 0 {
    raise fail(
      "money policy must declare positive scale and half_even rounding",
    )
  }
  match field(Json::object(policy), "rounding") {
    Null => ()
    String(value) if value == "half_even" => ()
    _ =>
      raise fail(
        "money policy must declare positive scale and half_even rounding",
      )
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
  let mut whole : Int64 = 0
  let mut fraction : Int64 = 0
  let mut digits = 0
  let mut after_decimal = false
  while index < source.length() {
    let c = source.get_char(index).unwrap()
    if c == '.' {
      if after_decimal {
        raise fail("invalid monetary value: " + source)
      }
      after_decimal = true
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_int64()
      if after_decimal {
        fraction = fraction * 10 + digit
        digits += 1
      } else {
        whole = whole * 10 + digit
      }
    } else {
      raise fail("invalid monetary value: " + source)
    }
    index += 1
  }
  let denominator = power10(digits)
  let numerator = (whole * denominator + fraction) * scale
  let quotient = numerator / denominator
  let remainder = numerator % denominator
  let rounded = if remainder * 2 > denominator ||
    (remainder * 2 == denominator && quotient % 2 != 0) {
    quotient + 1
  } else {
    quotient
  }
  let allow_rounding = field(Json::object(policy), "allow_rounding") is True
  if !allow_rounding && remainder != 0 {
    raise fail("rounding required for monetary value: " + source)
  }
  let result = rounded * sign
  if result <= 0 {
    raise fail("non-positive monetary value: " + source)
  }
  result
}

///|
fn sorted_reasons(values : Array[String]) -> Json {
  let unique : Array[String] = []
  for value in values {
    let mut found = false
    for existing in unique {
      if existing == value {
        found = true
      }
    }
    if !found {
      unique.push(value)
    }
  }
  unique.sort_by(fn(left, right) { left.compare(right) })
  Json::array(unique.map(fn(value) { Json::string(value) }))
}

///|
fn percentage_bps(
  amount : Int64,
  commitment : Int64,
) -> Int64 raise PaymentPromotionPlanError {
  if commitment <= 0 || amount <= 0 || amount > commitment {
    raise fail("payment-plan amount is outside commitment")
  }
  let numerator = amount * 10000L
  let quotient = numerator / commitment
  let remainder = numerator % commitment
  if remainder * 2 > commitment ||
    (remainder * 2 == commitment && quotient % 2 != 0) {
    quotient + 1
  } else {
    quotient
  }
}

///|
fn safe_money(
  value : Json,
  policy : Map[String, Json],
  reasons : Array[String],
) -> Int64? {
  Some(money_minor(value, policy)) catch {
    PaymentPromotionPlanError::InvalidInput(message) => {
      reasons.push(message)
      None
    }
    PaymentPromotionPlanError::Io(_) => None
  }
}

///|
fn safe_percentage(
  amount : Int64,
  commitment : Int64,
  reasons : Array[String],
) -> Int64? {
  Some(percentage_bps(amount, commitment)) catch {
    PaymentPromotionPlanError::InvalidInput(message) => {
      reasons.push(message)
      None
    }
    PaymentPromotionPlanError::Io(_) => None
  }
}

///|
fn run(
  export_dir : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise PaymentPromotionPlanError {
  let manifest = object(read_json(export_dir + "/manifest.json"), "manifest")
  let config = object(read_json(mapping_path), "mapping")
  let principal_map = match config.get("principal_by_bu") {
    Some(value) => object(value, "principal_by_bu")
    None => {}
  }
  let counterparty_map = match config.get("counterparty_by_provider") {
    Some(value) => object(value, "counterparty_by_provider")
    None => {}
  }
  let currency_map = match config.get("currency_by_bu") {
    Some(value) => object(value, "currency_by_bu")
    None => {}
  }
  let state_map = match config.get("commitment_state_by_contract") {
    Some(value) => object(value, "commitment_state_by_contract")
    None => {}
  }
  let policy = match config.get("money_policy") {
    Some(value) => object(value, "money_policy")
    None => {}
  }
  let contracts = match read_json(export_dir + "/tables/cb_contract.json") {
    Array(values) => values
    _ => raise fail("contract/payment exports must be arrays")
  }
  let payment_plans = match read_json(export_dir + "/tables/cb_htfkplan.json") {
    Array(values) => values
    _ => raise fail("contract/payment exports must be arrays")
  }
  let applications = match
    read_json(export_dir + "/tables/cb_htfk_apply.json") {
    Array(values) => values
    _ => raise fail("contract/payment exports must be arrays")
  }
  let items : Array[Json] = []
  let contract_info : Map[String, Map[String, Json]] = {}
  for contract in contracts {
    let contract_id = text(field(contract, "contract_guid"))
    let bu_id = text(field(contract, "bu_guid"))
    let provider = text(field(contract, "yf_provider_name"))
    let principal = principal_map.get(bu_id).unwrap_or(Json::null())
    let counterparty = counterparty_map.get(provider).unwrap_or(Json::null())
    let currency = currency_map.get(bu_id).unwrap_or(Json::null())
    let reasons : Array[String] = []
    if !truthy(principal) {
      reasons.push("missing_principal_by_bu")
    }
    if !truthy(counterparty) {
      reasons.push("missing_counterparty_by_provider")
    }
    if !truthy(currency) {
      reasons.push("missing_currency_by_bu")
    }
    let amount = safe_money(field(contract, "ht_amount"), policy, reasons)
    let candidate = if reasons.is_empty() {
      Json::object({
        "commitment_id": Json::string(contract_id),
        "business_unit_id": Json::string(bu_id),
        "project_scope": Json::string(
          "project:" + text(field(contract, "proj_guid")),
        ),
        "principal_id": principal,
        "counterparty_id": counterparty,
        "amount_minor": Json::number(
          amount.unwrap().to_double(),
          repr=amount.unwrap().to_string(),
        ),
        "currency": currency,
      })
    } else {
      Json::null()
    }
    items.push(
      Json::object({
        "source_table": Json::string("cb_contract"),
        "source_id": Json::string(contract_id),
        "target_type": Json::string("commitment"),
        "target_id": Json::string(contract_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array([]),
        "target_candidate": candidate,
      }),
    )
    contract_info.set(contract_id, {
      "contract": contract,
      "principal": principal,
      "currency": currency,
      "amount_minor": match amount {
        Some(value) => Json::number(value.to_double(), repr=value.to_string())
        None => Json::null()
      },
      "reasons": sorted_reasons([]),
    })
    let target_state = state_map.get(contract_id).unwrap_or(Json::null())
    let valid_state = match target_state {
      String(value) =>
        ["draft", "submitted", "approved", "performed", "settled", "cancelled"].contains(
          value,
        )
      _ => false
    }
    let state_reasons : Array[String] = []
    if !reasons.is_empty() {
      state_reasons.push("commitment_mapping_unresolved")
    }
    if !valid_state {
      state_reasons.push("missing_or_invalid_commitment_state_mapping")
    }
    items.push(
      Json::object({
        "source_table": Json::string("cb_contract_state"),
        "source_id": Json::string("state:" + contract_id),
        "target_type": Json::string("commitment_state"),
        "target_id": Json::string(contract_id),
        "disposition": Json::string(
          if state_reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(state_reasons),
        "warnings": Json::array([
          Json::string(
            "legacy contract status is replayed only through the explicit target-state map",
          ),
        ]),
        "target_candidate": if state_reasons.is_empty() {
          Json::object({
            "commitment_id": Json::string(contract_id),
            "target_state": target_state,
          })
        } else {
          Json::null()
        },
      }),
    )
  }
  let plans_by_contract : Map[String, Array[Json]] = {}
  for row in payment_plans {
    let id = text(field(row, "contract_guid"))
    let rows = plans_by_contract.get(id).unwrap_or([])
    rows.push(row)
    plans_by_contract.set(id, rows)
  }
  for contract_id, rows in plans_by_contract {
    let info = contract_info.get(contract_id)
    rows.sort_by(fn(left, right) {
      let date_order = text(field(left, "jhfk_date")).compare(
        text(field(right, "jhfk_date")),
      )
      if date_order == 0 {
        text(field(left, "htfk_plan_guid")).compare(
          text(field(right, "htfk_plan_guid")),
        )
      } else {
        date_order
      }
    })
    let mut sequence = 1
    for row in rows {
      let plan_id = text(field(row, "htfk_plan_guid"))
      let reasons : Array[String] = []
      let contract = match info {
        Some(value) => value.get("contract").unwrap()
        None => Json::null()
      }
      if info is None {
        reasons.push("missing_contract")
      }
      let info_reasons = match info {
        Some(value) => value.get("reasons").unwrap()
        None => Json::array([])
      }
      match info_reasons {
        Array(values) =>
          for reason in values {
            reasons.push(text(reason))
          }
        _ => ()
      }
      let amount = safe_money(field(row, "jhfk_amount"), policy, reasons)
      let contract_amount = match info {
        Some(value) =>
          match value.get("amount_minor").unwrap() {
            Number(number, ..) => Some(number.to_int().to_int64())
            _ => None
          }
        None => None
      }
      let pct : Int64? = match (amount, contract_amount) {
        (Some(value), Some(total)) => safe_percentage(value, total, reasons)
        _ => None
      }
      let principal = match info {
        Some(value) => value.get("principal").unwrap()
        None => Json::null()
      }
      let currency = match info {
        Some(value) => value.get("currency").unwrap()
        None => Json::null()
      }
      let candidate = Json::object({
        "commitment_id": Json::string(contract_id),
        "principal_id": principal,
        "authority_scope": if info is Some(_) {
          Json::string("project:" + text(field(contract, "proj_guid")))
        } else {
          Json::null()
        },
        "currency": currency,
        "milestone": Json::object({
          "milestone_guid": Json::string(plan_id),
          "contract_guid": Json::string(contract_id),
          "sequence": Json::number(
            sequence.to_double(),
            repr=sequence.to_string(),
          ),
          "node_name": field(row, "plan_period"),
          "trigger_type": Json::string("time"),
          "plan_amount_minor": match amount {
            Some(value) =>
              Json::number(value.to_double(), repr=value.to_string())
            None => Json::null()
          },
          "plan_pct_bps": match pct {
            Some(value) =>
              Json::number(value.to_double(), repr=value.to_string())
            None => Json::null()
          },
        }),
      })
      items.push(
        Json::object({
          "source_table": Json::string("cb_htfkplan"),
          "source_id": Json::string(plan_id),
          "target_type": Json::string("contract_milestone"),
          "target_id": Json::string(plan_id),
          "disposition": Json::string(
            if reasons.is_empty() {
              "ready_for_domain_import"
            } else {
              "quarantined"
            },
          ),
          "reasons": sorted_reasons(reasons),
          "warnings": Json::array([
            Json::string(
              "source approval/confirmation flags remain evidence; only the planned milestone is promoted",
            ),
          ]),
          "target_candidate": if reasons.is_empty() {
            candidate
          } else {
            Json::null()
          },
        }),
      )
      sequence += 1
    }
  }
  for application in applications {
    let application_id = text(field(application, "htfk_apply_guid"))
    let contract_id = text(field(application, "contract_guid"))
    let info = contract_info.get(contract_id)
    let reasons : Array[String] = []
    if info is None {
      reasons.push("missing_contract")
    }
    let info_reasons = match info {
      Some(value) => value.get("reasons").unwrap()
      None => Json::array([])
    }
    match info_reasons {
      Array(values) =>
        for reason in values {
          reasons.push(text(reason))
        }
      _ => ()
    }
    let amount = safe_money(field(application, "apply_amount"), policy, reasons)
    let amount_bz = safe_money(
      field(application, "apply_amount_bz"),
      policy,
      reasons,
    )
    let total = match info {
      Some(value) =>
        match value.get("amount_minor").unwrap() {
          Number(number, ..) => Some(number.to_int().to_int64())
          _ => None
        }
      None => None
    }
    match (amount, total) {
      (Some(value), Some(commitment)) if value > commitment =>
        reasons.push("application_exceeds_commitment")
      _ => ()
    }
    let currency = match info {
      Some(value) => value.get("currency").unwrap()
      None => Json::null()
    }
    let principal = match info {
      Some(value) => value.get("principal").unwrap()
      None => Json::null()
    }
    let candidate = Json::object({
      "application": Json::object({
        "apply_guid": Json::string(application_id),
        "apply_code": field(application, "apply_code"),
        "contract_guid": Json::string(contract_id),
        "plan_guid": field(application, "htfk_plan_guid"),
        "apply_class": Json::number(
          integer(field(application, "apply_class"), 0L).to_double(),
          repr=integer(field(application, "apply_class"), 0L).to_string(),
        ),
        "apply_type_code": field(application, "apply_type_code"),
        "apply_state": field(application, "apply_state"),
        "pay_state": field(application, "pay_state"),
        "subject": field(application, "subject"),
        "apply_dept_guid": field(application, "apply_dept_guid"),
        "applied_by": field(application, "applied_by"),
        "apply_date": field(application, "apply_date"),
        "amount_minor": match amount {
          Some(value) => Json::number(value.to_double(), repr=value.to_string())
          None => Json::null()
        },
        "amount_bz_minor": match amount_bz {
          Some(value) => Json::number(value.to_double(), repr=value.to_string())
          None => Json::null()
        },
        "proj_guid": field(application, "proj_guid"),
        "proj_type": field(application, "proj_type"),
        "contract_class": field(application, "ht_class"),
        "bu_guid": field(application, "bu_guid"),
      }),
      "commitment_id": Json::string(contract_id),
      "currency": currency,
      "principal_id": principal,
      "authority_scope": Json::string(
        "project:" + text(field(application, "proj_guid")),
      ),
    })
    items.push(
      Json::object({
        "source_table": Json::string("cb_htfk_apply"),
        "source_id": Json::string(application_id),
        "target_type": Json::string("payment_application"),
        "target_id": Json::string(application_id),
        "disposition": Json::string(
          if reasons.is_empty() {
            "ready_for_domain_import"
          } else {
            "quarantined"
          },
        ),
        "reasons": sorted_reasons(reasons),
        "warnings": Json::array([
          Json::string(
            "source approval/payment flags remain evidence; promotion creates a requested settlement only",
          ),
        ]),
        "target_candidate": if reasons.is_empty() {
          candidate
        } else {
          Json::null()
        },
      }),
    )
  }
  let mut ready = 0
  for item in items {
    if text(field(item, "disposition")) == "ready_for_domain_import" {
      ready += 1
    }
  }
  let source_sha = text(field(Json::object(manifest), "source_sha256"))
  let report = Json::object({
    "format": Json::string("moonproj.erp.payment-promotion-plan.v1"),
    "source_snapshot_id": Json::string("erp-snapshot:" + source_sha),
    "source_sha256": Json::string(source_sha),
    "mapping_version": config
    .get("mapping_version")
    .unwrap_or(Json::string("unversioned-payment-map")),
    "summary": Json::object({
      "items": Json::number(
        items.length().to_double(),
        repr=items.length().to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
    }),
    "items": Json::array(items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise PaymentPromotionPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "quarantined": Json::number(
        (items.length() - ready).to_double(),
        repr=(items.length() - ready).to_string(),
      ),
      "ready": Json::number(ready.to_double(), repr=ready.to_string()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: payment_promotion_plan <export> <mapping> <output>")
    @sys.exit(2)
  }
  run(args[1], args[2], args[3]) catch {
    PaymentPromotionPlanError::InvalidInput(message) => {
      println("payment promotion plan failed: " + message)
      @sys.exit(1)
    }
    PaymentPromotionPlanError::Io(_) => {
      println("payment promotion plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
