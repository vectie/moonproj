///|
struct ReceiptIdentity {
  source_type : String
  source_id : String
  principal_id : String
  journal_id : String
}

///|
pub(all) suberror AccountingPostPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> AccountingPostPlanError {
  AccountingPostPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise AccountingPostPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise AccountingPostPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise AccountingPostPlanError {
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
fn required_string(
  value : Json,
  key : String,
) -> String raise AccountingPostPlanError {
  match value {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail(key + " must be a non-empty string")
  }
}

///|
fn required_object_field(
  value : Json,
  key : String,
) -> Json raise AccountingPostPlanError {
  match field(value, key) {
    Null => raise fail("missing field " + key)
    value => value
  }
}

///|
fn required_bool(
  value : Json,
  key : String,
) -> Bool raise AccountingPostPlanError {
  match required_object_field(value, key) {
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
fn integer(value : Json, default : Int64) -> Int64 {
  match value {
    Number(number, ..) if number == number.trunc() =>
      parse_integer(value.stringify(), default)
    _ => default
  }
}

///|
fn string_array(
  value : Json,
  key : String,
) -> Array[String] raise AccountingPostPlanError {
  let values = match value {
    Array(values) if !values.is_empty() => values
    _ => raise fail(key + " must be a non-empty string array")
  }
  let result : Array[String] = []
  for item in values {
    result.push(required_string(item, key + " item"))
  }
  result
}

///|
fn contains(values : Array[String], value : String) -> Bool {
  values.contains(value)
}

///|
fn run(
  link_plan_path : String,
  link_receipt_path : String,
  mapping_path : String,
  output_path : String,
) -> Unit raise AccountingPostPlanError {
  let link_plan = object(read_json(link_plan_path), "accounting-link plan")
  let link_receipt = object(
    read_json(link_receipt_path),
    "accounting-link receipt",
  )
  let config = object(read_json(mapping_path), "accounting-posting mapping")
  if required_string(field(Json::object(link_plan), "format"), "format") !=
    "moonproj.erp.accounting-link-plan.v1" {
    raise fail("unexpected accounting-link plan format")
  }
  if required_string(field(Json::object(link_receipt), "format"), "format") !=
    "moonproj.erp.accounting-link-receipt.v1" {
    raise fail("unexpected accounting-link receipt format")
  }
  if required_string(field(Json::object(link_receipt), "state"), "state") !=
    "validated_accounting_links" {
    raise fail("accounting-link receipt is not native-validated")
  }
  if required_string(field(Json::object(config), "format"), "format") !=
    "moonproj.erp.accounting-posting-map.v1" {
    raise fail("unexpected accounting-posting mapping format")
  }
  if !required_bool(Json::object(config), "reviewed") {
    raise fail("accounting-posting mapping is not reviewed")
  }
  let source_snapshot_id = required_string(
    field(Json::object(link_plan), "source_snapshot_id"),
    "source_snapshot_id",
  )
  if text(field(Json::object(link_receipt), "source_snapshot_id")) !=
    source_snapshot_id {
    raise fail("accounting-link plan/receipt source snapshot mismatch")
  }
  let receipt_items = match
    field(Json::object(link_receipt), "accepted_items") {
    Array(values) if !values.is_empty() => values
    _ => raise fail("accounting-link receipt has no accepted items")
  }
  let receipt_by_event : Map[String, ReceiptIdentity] = {}
  let receipt_journals : Array[String] = []
  for value in receipt_items {
    let item = object(value, "receipt item")
    let event_id = required_string(
      field(Json::object(item), "event_id"),
      "event_id",
    )
    let journal_id = required_string(
      field(Json::object(item), "journal_id"),
      "journal_id",
    )
    if receipt_by_event.get(event_id) is Some(_) ||
      receipt_journals.contains(journal_id) {
      raise fail("duplicate accounting-link receipt identity: " + event_id)
    }
    receipt_by_event.set(event_id, ReceiptIdentity::{
      source_type: required_string(
        field(Json::object(item), "source_type"),
        "source_type",
      ),
      source_id: required_string(
        field(Json::object(item), "source_id"),
        "source_id",
      ),
      principal_id: required_string(
        field(Json::object(item), "principal_id"),
        "principal_id",
      ),
      journal_id,
    })
    receipt_journals.push(journal_id)
  }
  let summary = object(field(Json::object(link_plan), "summary"), "summary")
  if integer(field(Json::object(summary), "quarantined"), 1L) != 0L {
    raise fail("accounting-link plan contains quarantined items")
  }
  let book = object(field(Json::object(config), "book"), "book")
  let _book_id = required_string(
    field(Json::object(book), "book_id"),
    "book_id",
  )
  let book_principal = required_string(
    field(Json::object(book), "principal_id"),
    "principal_id",
  )
  let book_scope = required_string(field(Json::object(book), "scope"), "scope")
  let _period_id = required_string(
    field(Json::object(book), "period_id"),
    "period_id",
  )
  let _period_label = required_string(
    field(Json::object(book), "period_label"),
    "period_label",
  )
  let accounts = match field(Json::object(book), "accounts") {
    Array(values) if !values.is_empty() => values
    _ => raise fail("book.accounts must be a non-empty array")
  }
  let account_codes : Array[String] = []
  let account_ids : Array[String] = []
  let account_currencies : Array[String] = []
  for account_value in accounts {
    let account = object(account_value, "book account")
    let account_id = required_string(
      field(Json::object(account), "account_id"),
      "account_id",
    )
    let account_code = required_string(
      field(Json::object(account), "account_code"),
      "account_code",
    )
    let _name = required_string(field(Json::object(account), "name"), "name")
    let kind = required_string(field(Json::object(account), "kind"), "kind")
    let currency = required_string(
      field(Json::object(account), "currency"),
      "currency",
    )
    if kind != "asset" &&
      kind != "liability" &&
      kind != "equity" &&
      kind != "revenue" &&
      kind != "expense" {
      raise fail("unsupported account kind: " + kind)
    }
    if currency.length() != 3 {
      raise fail("invalid account currency: " + currency)
    }
    if account_ids.contains(account_id) || account_codes.contains(account_code) {
      raise fail("duplicate chart account")
    }
    account_ids.push(account_id)
    account_codes.push(account_code)
    if !account_currencies.contains(currency) {
      account_currencies.push(currency)
    }
  }
  let items = match field(Json::object(link_plan), "items") {
    Array(values) if !values.is_empty() => values
    _ => raise fail("accounting-link plan has no items")
  }
  let approved = string_array(
    field(Json::object(config), "approved_event_ids"),
    "approved_event_ids",
  )
  let output_items : Array[Json] = []
  let event_ids : Array[String] = []
  for index in 0..<items.length() {
    let item = object(items[index], "accounting-link item")
    if required_string(field(Json::object(item), "disposition"), "disposition") !=
      "ready_for_domain_import" {
      raise fail("accounting-link item " + index.to_string() + " is not ready")
    }
    let candidate = object(
      field(Json::object(item), "target_candidate"),
      "target_candidate",
    )
    let event_id = required_string(
      field(Json::object(candidate), "event_id"),
      "event_id",
    )
    if !contains(approved, event_id) {
      continue
    }
    let receipt = match receipt_by_event.get(event_id) {
      Some(value) => value
      None =>
        raise fail(
          "event was not accepted by the native link receipt: " + event_id,
        )
    }
    if event_ids.contains(event_id) {
      raise fail("duplicate posting event: " + event_id)
    }
    event_ids.push(event_id)
    if text(field(Json::object(candidate), "principal_id")) != book_principal {
      raise fail("principal mismatch for " + event_id)
    }
    if text(field(Json::object(candidate), "scope")) != book_scope {
      raise fail("scope mismatch for " + event_id)
    }
    let journal = object(field(Json::object(candidate), "journal"), "journal")
    let entry_id = required_string(
      field(Json::object(journal), "entry_id"),
      "entry_id",
    )
    let _description = required_string(
      field(Json::object(journal), "description"),
      "description",
    )
    let debit_account = required_string(
      field(Json::object(journal), "debit_account"),
      "debit_account",
    )
    let credit_account = required_string(
      field(Json::object(journal), "credit_account"),
      "credit_account",
    )
    let currency = required_string(
      field(Json::object(journal), "currency"),
      "currency",
    )
    if !account_codes.contains(debit_account) ||
      !account_codes.contains(credit_account) {
      raise fail("journal account is absent from explicit chart: " + event_id)
    }
    if receipt.source_type !=
      text(field(Json::object(candidate), "source_type")) ||
      receipt.source_id != text(field(Json::object(candidate), "source_id")) ||
      receipt.principal_id !=
      text(field(Json::object(candidate), "principal_id")) ||
      receipt.journal_id != entry_id {
      raise fail("accounting-link receipt identity mismatch: " + event_id)
    }
    let amount = integer(field(Json::object(journal), "amount_minor"), 0L)
    if amount <= 0 {
      raise fail("journal amount is not positive: " + event_id)
    }
    if !account_currencies.contains(currency) {
      raise fail("journal currency is absent from explicit chart: " + event_id)
    }
    let candidate_fields = candidate
    candidate_fields.set("link_event_id", Json::string(event_id))
    output_items.push(
      Json::object({
        "source_table": Json::string(
          required_string(
            field(Json::object(item), "source_table"),
            "source_table",
          ),
        ),
        "source_id": Json::string(
          required_string(field(Json::object(item), "source_id"), "source_id"),
        ),
        "target_type": Json::string("accounting_posting"),
        "target_id": Json::string(entry_id),
        "disposition": Json::string("ready_for_posting"),
        "target_candidate": Json::object(candidate_fields),
      }),
    )
  }
  for approved_event in approved {
    if !event_ids.contains(approved_event) {
      raise fail("approved_event_ids must exactly match the link-plan events")
    }
  }
  let mapping_version = required_string(
    field(Json::object(config), "mapping_version"),
    "mapping_version",
  )
  let report = Json::object({
    "format": Json::string("moonproj.erp.accounting-posting-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "book": Json::object(book),
    "summary": Json::object({
      "items": Json::number(
        output_items.length().to_double(),
        repr=output_items.length().to_string(),
      ),
      "ready": Json::number(
        output_items.length().to_double(),
        repr=output_items.length().to_string(),
      ),
      "quarantined": Json::number(0.0, repr="0"),
    }),
    "items": Json::array(output_items),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise AccountingPostPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "items": Json::number(
        output_items.length().to_double(),
        repr=output_items.length().to_string(),
      ),
      "ready": Json::number(
        output_items.length().to_double(),
        repr=output_items.length().to_string(),
      ),
      "quarantined": Json::number(0.0, repr="0"),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 5 {
    println(
      "usage: accounting_post_plan <link-plan.json> <link-receipt.json> <mapping.json> <output.json>",
    )
    @sys.exit(2)
  }
  run(args[1], args[2], args[3], args[4]) catch {
    AccountingPostPlanError::InvalidInput(message) => {
      println("accounting-post plan failed: " + message)
      @sys.exit(1)
    }
    AccountingPostPlanError::Io(_) => {
      println("accounting-post plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
