///|
pub(all) suberror InvoiceSubledgerPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Invoice(@invoice.InvoiceError)
  Receivable(@receivable.ReceivableError)
  Payable(@payable.PayableError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise InvoiceSubledgerPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvoiceSubledgerPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn object(
  value : Json,
) -> Map[String, Json] raise InvoiceSubledgerPromotionError {
  match value {
    Object(value) => value
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise InvoiceSubledgerPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise InvoiceSubledgerPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise InvoiceSubledgerPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise InvoiceSubledgerPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise InvoiceSubledgerPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise InvoiceSubledgerPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn invoice_state_name(value : @invoice.InvoiceState) -> String {
  match value {
    @invoice.InvoiceState::Draft => "draft"
    @invoice.InvoiceState::Issued => "issued"
    @invoice.InvoiceState::Accepted => "accepted"
    @invoice.InvoiceState::PartiallyPaid => "partially_paid"
    @invoice.InvoiceState::Paid => "paid"
    @invoice.InvoiceState::Voided => "voided"
  }
}

///|
fn receivable_state_name(value : @receivable.ReceivableState) -> String {
  match value {
    @receivable.ReceivableState::Open => "open"
    @receivable.ReceivableState::PartiallyCollected => "partially_collected"
    @receivable.ReceivableState::Collected => "collected"
    @receivable.ReceivableState::WrittenOff => "written_off"
  }
}

///|
fn payable_state_name(value : @payable.PayableState) -> String {
  match value {
    @payable.PayableState::Open => "open"
    @payable.PayableState::PartiallyPaid => "partially_paid"
    @payable.PayableState::Paid => "paid"
    @payable.PayableState::Voided => "voided"
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "invoice-subledger-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise InvoiceSubledgerPromotionError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise InvoiceSubledgerPromotionError::Money(error)
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise InvoiceSubledgerPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.invoice-subledger-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise InvoiceSubledgerPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for value in required_array(root, "customer_invoices") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let invoice_id = required_string(item, "invoice_id")
    let receivable_id = required_string(item, "receivable_id")
    let principal_id = required_string(item, "principal_id")
    let customer_id = required_string(item, "customer_id")
    let currency = required_string(item, "currency")
    let amount_minor = required_int64(item, "amount_minor")
    let payment_minor = required_int64(item, "payment_minor")
    let expected_invoice_state = required_string(item, "expected_invoice_state")
    let expected_receivable_state = required_string(
      item, "expected_receivable_state",
    )
    let amount = money(amount_minor, currency)
    let customer_scope = "customer:" + customer_id
    let invoice = @invoice.Invoice::new(
      invoice_id~,
      principal_id~,
      customer_id~,
      source_id~,
      amount~,
      actor_id="migration",
      grant=grant(principal_id, "invoice:create", customer_scope, amount_minor),
    ) catch {
      error => raise InvoiceSubledgerPromotionError::Invoice(error)
    }
    let invoice = invoice.transition(
      @invoice.InvoiceState::Issued,
      actor_id="migration",
      grant=grant(principal_id, "invoice:issue", customer_scope, amount_minor),
    ) catch {
      error => raise InvoiceSubledgerPromotionError::Invoice(error)
    }
    let invoice = invoice.transition(
      @invoice.InvoiceState::Accepted,
      actor_id="migration",
      grant=grant(principal_id, "invoice:accept", customer_scope, amount_minor),
    ) catch {
      error => raise InvoiceSubledgerPromotionError::Invoice(error)
    }
    let receivable = invoice.open_receivable(
      receivable_id~,
      actor_id="migration",
      invoice_grant=grant(
        principal_id, "invoice:receivable-open", customer_scope, amount_minor,
      ),
      receivable_grant=grant(
        principal_id, "receivable:open", customer_scope, amount_minor,
      ),
    ) catch {
      error => raise InvoiceSubledgerPromotionError::Invoice(error)
    }
    let (invoice, receivable) = if payment_minor > 0L {
      let invoice = invoice.record_payment(
        amount_minor=payment_minor,
        actor_id="migration",
        grant=grant(
          principal_id, "invoice:collect", customer_scope, amount_minor,
        ),
      ) catch {
        error => raise InvoiceSubledgerPromotionError::Invoice(error)
      }
      let receivable = receivable.collect(
        amount_minor=payment_minor,
        actor_id="migration",
        grant=grant(
          principal_id, "receivable:collect", customer_scope, amount_minor,
        ),
      ) catch {
        error => raise InvoiceSubledgerPromotionError::Receivable(error)
      }
      (invoice, receivable)
    } else {
      (invoice, receivable)
    }
    if invoice_state_name(invoice.state) != expected_invoice_state ||
      receivable_state_name(receivable.state) != expected_receivable_state {
      raise InvoiceSubledgerPromotionError::InvalidInput
    }
    let collection_recorded = payment_minor > 0L
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("invoice"),
        "target_id": Json::string(invoice.invoice_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "invoice_id": Json::string(invoice.invoice_id),
          "receivable_id": Json::string(receivable.receivable_id),
          "principal_id": Json::string(invoice.principal_id),
          "customer_id": Json::string(invoice.customer_id),
          "source_id": Json::string(invoice.source_id),
          "amount_minor": number(invoice.amount.minor),
          "paid_minor": number(invoice.paid_minor),
          "outstanding_minor": number(invoice.outstanding_minor()),
          "currency": Json::string(invoice.amount.currency),
          "state": Json::string(invoice_state_name(invoice.state)),
          "event_count": number(invoice.events.length().to_int64()),
          "invoice_reviewed": Json::boolean(true),
          "receivable_opened": Json::boolean(true),
          "collection_recorded": Json::boolean(collection_recorded),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("receivable"),
        "target_id": Json::string(receivable.receivable_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "invoice_id": Json::string(invoice.invoice_id),
          "receivable_id": Json::string(receivable.receivable_id),
          "source_id": Json::string(receivable.source_id),
          "principal_id": Json::string(receivable.principal_id),
          "customer_id": Json::string(receivable.customer_id),
          "amount_minor": number(receivable.amount.minor),
          "collected_minor": number(receivable.collected_minor),
          "outstanding_minor": number(receivable.outstanding_minor()),
          "currency": Json::string(receivable.amount.currency),
          "state": Json::string(receivable_state_name(receivable.state)),
          "receivable_reviewed": Json::boolean(true),
          "collection_recorded": Json::boolean(collection_recorded),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  for value in required_array(root, "supplier_payables") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let payable_id = required_string(item, "payable_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let supplier_id = required_string(item, "supplier_id")
    let source_reference = required_string(item, "source_reference")
    let currency = required_string(item, "currency")
    let amount_minor = required_int64(item, "amount_minor")
    let payment_minor = required_int64(item, "payment_minor")
    let expected_state = required_string(item, "expected_state")
    let amount = money(amount_minor, currency)
    let payable = @payable.Payable::open(
      payable_id~,
      principal_id~,
      project_scope~,
      supplier_id~,
      source_reference~,
      amount~,
      actor_id="migration",
      grant=grant(principal_id, "payable:create", project_scope, amount_minor),
    ) catch {
      error => raise InvoiceSubledgerPromotionError::Payable(error)
    }
    let payable = if payment_minor > 0L {
      let payment = money(payment_minor, currency)
      payable.record_payment(
        payment~,
        actor_id="migration",
        grant=grant(principal_id, "payable:pay", project_scope, amount_minor),
      ) catch {
        error => raise InvoiceSubledgerPromotionError::Payable(error)
      }
    } else {
      payable
    }
    if payable_state_name(payable.state) != expected_state {
      raise InvoiceSubledgerPromotionError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("payable"),
        "target_id": Json::string(payable.payable_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "payable_id": Json::string(payable.payable_id),
          "principal_id": Json::string(payable.principal_id),
          "project_scope": Json::string(payable.project_scope),
          "supplier_id": Json::string(payable.supplier_id),
          "source_reference": Json::string(payable.source_reference),
          "amount_minor": number(payable.amount.minor),
          "outstanding_minor": number(payable.outstanding.minor),
          "currency": Json::string(payable.amount.currency),
          "state": Json::string(payable_state_name(payable.state)),
          "event_count": number(payable.events.length().to_int64()),
          "payable_reviewed": Json::boolean(true),
          "payment_recorded": Json::boolean(payment_minor > 0L),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise InvoiceSubledgerPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("invoice-subledger-v1"),
    "accepted_items": Json::array(accepted),
    "invoice_count": number(
      required_array(root, "customer_invoices").length().to_int64(),
    ),
    "receivable_count": number(
      required_array(root, "customer_invoices").length().to_int64(),
    ),
    "payable_count": number(
      required_array(root, "supplier_payables").length().to_int64(),
    ),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise InvoiceSubledgerPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: invoice_subledger <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      InvoiceSubledgerPromotionError::InvalidInput => {
        println(
          "invoice subledger promotion failed: invalid or unreviewed input",
        )
        @sys.exit(1)
      }
      InvoiceSubledgerPromotionError::Io(_) => {
        println("invoice subledger promotion failed: filesystem error")
        @sys.exit(1)
      }
      InvoiceSubledgerPromotionError::Money(_) => {
        println("invoice subledger promotion failed: money validation")
        @sys.exit(1)
      }
      InvoiceSubledgerPromotionError::Invoice(error) => {
        println(
          "invoice subledger promotion failed: invoice lifecycle validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      InvoiceSubledgerPromotionError::Receivable(error) => {
        println(
          "invoice subledger promotion failed: receivable lifecycle validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
      InvoiceSubledgerPromotionError::Payable(error) => {
        println(
          "invoice subledger promotion failed: payable lifecycle validation: \{to_repr(error)}",
        )
        @sys.exit(1)
      }
    }
  }
}
