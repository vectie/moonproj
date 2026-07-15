///|
/// Compile a reviewed invoice/receivable/payable map without releasing cash or
/// posting the accounting book.
pub(all) suberror InvoiceSubledgerPlanError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
fn fail(message : String) -> InvoiceSubledgerPlanError {
  InvoiceSubledgerPlanError::InvalidInput(message)
}

///|
fn read_json(path : String) -> Json raise InvoiceSubledgerPlanError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvoiceSubledgerPlanError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise fail("cannot read " + path)
  }
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise InvoiceSubledgerPlanError {
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
) -> Json raise InvoiceSubledgerPlanError {
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
) -> String raise InvoiceSubledgerPlanError {
  match required(fields, key, path) {
    String(value) if !value.trim().is_empty() => value
    _ => raise fail("expected non-empty string at " + path + "." + key)
  }
}

///|
fn required_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool raise InvoiceSubledgerPlanError {
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
) -> Int64 raise InvoiceSubledgerPlanError {
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
) -> Array[Json] raise InvoiceSubledgerPlanError {
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
) -> Unit raise InvoiceSubledgerPlanError {
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
fn validate_payment(
  payment : Int64,
  amount : Int64,
  state : String,
  label : String,
) -> Unit raise InvoiceSubledgerPlanError {
  if payment < 0 || payment > amount {
    raise fail(label + " payment exceeds amount")
  }
  if state == "accepted" || state == "open" {
    if payment != 0 {
      raise fail(label + " open state requires zero payment")
    }
  } else if state == "partially_paid" || state == "partially_collected" {
    if payment <= 0 || payment >= amount {
      raise fail(
        label + " partial state requires payment between zero and amount",
      )
    }
  } else if state == "paid" || state == "collected" {
    if payment != amount {
      raise fail(label + " closed state requires full payment")
    }
  } else {
    raise fail(label + " is invalid")
  }
}

///|
fn run(
  mapping_path : String,
  output_path : String,
) -> Unit raise InvoiceSubledgerPlanError {
  let root_value = read_json(mapping_path)
  reject_secret_keys(root_value, "mapping")
  let root = object(root_value, "mapping")
  if required_string(root, "format", "mapping") !=
    "moonproj.erp.invoice-subledger-map.v1" {
    raise fail("unexpected invoice subledger map format")
  }
  if !required_bool(root, "reviewed", "mapping") {
    raise fail("invoice subledger map is not reviewed")
  }
  let source_snapshot_id = required_string(
    root, "source_snapshot_id", "mapping",
  )
  let mapping_version = required_string(root, "mapping_version", "mapping")
  let run_id = required_string(root, "run_id", "mapping")
  let invoices = required_array(root, "customer_invoices", "mapping")
  let payables = required_array(root, "supplier_payables", "mapping")
  let invoice_ids : Array[String] = []
  let receivable_ids : Array[String] = []
  let normalized_invoices : Array[Json] = []
  for index in 0..<invoices.length() {
    let path = "customer_invoices[" + index.to_string() + "]"
    let invoice = object(invoices[index], path)
    let source_table = required_string(invoice, "source_table", path)
    let source_id = required_string(invoice, "source_id", path)
    let invoice_id = required_string(invoice, "invoice_id", path)
    let receivable_id = required_string(invoice, "receivable_id", path)
    let principal_id = required_string(invoice, "principal_id", path)
    let customer_id = required_string(invoice, "customer_id", path)
    let currency = required_string(invoice, "currency", path)
    let amount = required_int(invoice, "amount_minor", path)
    let payment = required_int(invoice, "payment_minor", path)
    let invoice_state = required_string(invoice, "expected_invoice_state", path)
    let receivable_state = required_string(
      invoice, "expected_receivable_state", path,
    )
    if amount < 1 {
      raise fail("amount_minor must be >= 1 at " + path)
    }
    validate_payment(
      payment,
      amount,
      invoice_state,
      path + ".expected_invoice_state",
    )
    validate_payment(
      payment,
      amount,
      receivable_state,
      path + ".expected_receivable_state",
    )
    if invoice_ids.contains(invoice_id) {
      raise fail("duplicate invoice_id: " + invoice_id)
    }
    if receivable_ids.contains(receivable_id) {
      raise fail("duplicate receivable_id: " + receivable_id)
    }
    invoice_ids.push(invoice_id)
    receivable_ids.push(receivable_id)
    normalized_invoices.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "invoice_id": Json::string(invoice_id),
        "receivable_id": Json::string(receivable_id),
        "principal_id": Json::string(principal_id),
        "customer_id": Json::string(customer_id),
        "currency": Json::string(currency),
        "amount_minor": number(amount),
        "payment_minor": number(payment),
        "expected_invoice_state": Json::string(invoice_state),
        "expected_receivable_state": Json::string(receivable_state),
      }),
    )
  }
  let payable_ids : Array[String] = []
  let normalized_payables : Array[Json] = []
  for index in 0..<payables.length() {
    let path = "supplier_payables[" + index.to_string() + "]"
    let payable = object(payables[index], path)
    let source_table = required_string(payable, "source_table", path)
    let source_id = required_string(payable, "source_id", path)
    let payable_id = required_string(payable, "payable_id", path)
    let principal_id = required_string(payable, "principal_id", path)
    let project_scope = required_string(payable, "project_scope", path)
    let supplier_id = required_string(payable, "supplier_id", path)
    let source_reference = required_string(payable, "source_reference", path)
    let currency = required_string(payable, "currency", path)
    let amount = required_int(payable, "amount_minor", path)
    let payment = required_int(payable, "payment_minor", path)
    let state = required_string(payable, "expected_state", path)
    if amount < 1 {
      raise fail("amount_minor must be >= 1 at " + path)
    }
    validate_payment(payment, amount, state, path + ".expected_state")
    if payable_ids.contains(payable_id) {
      raise fail("duplicate payable_id: " + payable_id)
    }
    payable_ids.push(payable_id)
    normalized_payables.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "payable_id": Json::string(payable_id),
        "principal_id": Json::string(principal_id),
        "project_scope": Json::string(project_scope),
        "supplier_id": Json::string(supplier_id),
        "source_reference": Json::string(source_reference),
        "currency": Json::string(currency),
        "amount_minor": number(amount),
        "payment_minor": number(payment),
        "expected_state": Json::string(state),
      }),
    )
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.invoice-subledger-plan.v1"),
    "reviewed": Json::boolean(true),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "summary": Json::object({
      "invoices": number(normalized_invoices.length().to_int64()),
      "receivables": number(normalized_invoices.length().to_int64()),
      "payables": number(normalized_payables.length().to_int64()),
    }),
    "customer_invoices": Json::array(normalized_invoices),
    "supplier_payables": Json::array(normalized_payables),
  })
  @fs.write_string_to_file(output_path, report.stringify(indent=2) + "\n") catch {
    error => raise InvoiceSubledgerPlanError::Io(error)
  }
  println(
    Json::object({
      "output": Json::string(output_path),
      "invoices": number(normalized_invoices.length().to_int64()),
      "receivables": number(normalized_invoices.length().to_int64()),
      "payables": number(normalized_payables.length().to_int64()),
    }).stringify(),
  )
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: invoice_subledger_plan <mapping.json> <output.json>")
    @sys.exit(2)
  }
  run(args[1], args[2]) catch {
    InvoiceSubledgerPlanError::InvalidInput(message) => {
      println("invoice subledger plan failed: " + message)
      @sys.exit(1)
    }
    InvoiceSubledgerPlanError::Io(_) => {
      println("invoice subledger plan failed: filesystem error")
      @sys.exit(1)
    }
  }
}
