///|
pub(all) suberror TaxAccountingLinkError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Tax(@tax.TaxError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise TaxAccountingLinkError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaxAccountingLinkError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise TaxAccountingLinkError {
  match value {
    Object(value) => value
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise TaxAccountingLinkError {
  match obj.get(key) {
    Some(value) => value
    None => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise TaxAccountingLinkError {
  match required(obj, key) {
    String(value) => value
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise TaxAccountingLinkError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise TaxAccountingLinkError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise TaxAccountingLinkError {
  match required(obj, key) {
    Array(value) => value
    _ => raise TaxAccountingLinkError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise TaxAccountingLinkError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise TaxAccountingLinkError::Money(error)
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
    grant_id: "tax-accounting-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise TaxAccountingLinkError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.tax-accounting-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise TaxAccountingLinkError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for item_value in required_array(root, "items") {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let tax_id = required_string(item, "tax_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let source_reference = required_string(item, "source_reference")
    let jurisdiction = required_string(item, "jurisdiction")
    let category = required_string(item, "category")
    let currency = required_string(item, "currency")
    let base_amount_minor = required_int64(item, "base_amount_minor")
    let tax_rate_bps = required_int64(item, "tax_rate_bps")
    let withholding_rate_bps = required_int64(item, "withholding_rate_bps")
    let accounting = object(required(item, "accounting"))
    let base_amount = money(base_amount_minor, currency)
    let obligation = @tax.TaxObligation::new(
      tax_id~,
      principal_id~,
      project_scope~,
      source_reference~,
      jurisdiction~,
      category~,
      base_amount~,
      tax_rate_bps~,
      withholding_rate_bps~,
      actor_id="migration",
      grant=grant(principal_id, "tax:create", project_scope, base_amount_minor),
    ) catch {
      error => raise TaxAccountingLinkError::Tax(error)
    }
    let calculated = obligation.calculate(
      actor_id="migration",
      grant=grant(
        principal_id, "tax:calculate", project_scope, base_amount_minor,
      ),
    ) catch {
      error => raise TaxAccountingLinkError::Tax(error)
    }
    let reviewed = calculated.transition(
      @tax.TaxObligationState::Reviewed,
      actor_id="migration",
      grant=grant(principal_id, "tax:review", project_scope, base_amount_minor),
    ) catch {
      error => raise TaxAccountingLinkError::Tax(error)
    }
    let event_id = required_string(accounting, "event_id")
    let event_type = required_string(accounting, "event_type")
    let tax_expense_account = required_string(accounting, "tax_expense_account")
    let tax_payable_account = required_string(accounting, "tax_payable_account")
    let event = reviewed.to_accounting_event(
      event_id~,
      event_type~,
      tax_expense_account~,
      tax_payable_account~,
    ) catch {
      error => raise TaxAccountingLinkError::Tax(error)
    }
    if event.source_type != "tax_obligation" ||
      event.source_id != tax_id ||
      event.principal_id != principal_id ||
      event.journal.entry_id != required_string(accounting, "journal_id") ||
      event.journal.postings.length() != 2 ||
      event.journal.postings[0].amount.minor !=
      required_int64(accounting, "amount_minor") ||
      event.journal.postings[0].amount.currency != currency {
      raise TaxAccountingLinkError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(tax_id),
        "target_type": Json::string("tax_obligation"),
        "target_id": Json::string(tax_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "tax_id": Json::string(tax_id),
          "event_id": Json::string(event.event_id),
          "event_type": Json::string(event.event_type),
          "source_type": Json::string(event.source_type),
          "source_id": Json::string(event.source_id),
          "principal_id": Json::string(event.principal_id),
          "scope": Json::string(project_scope),
          "journal_id": Json::string(event.journal.entry_id),
          "description": Json::string(event.journal.description),
          "debit_account": Json::string(event.journal.postings[0].account),
          "credit_account": Json::string(event.journal.postings[1].account),
          "amount_minor": number(event.journal.postings[0].amount.minor),
          "currency": Json::string(event.journal.postings[0].amount.currency),
          "tax_amount_minor": number(reviewed.tax_amount.minor),
          "accounting_event_created": Json::boolean(true),
          "accounting_linked": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "tax_payment_recorded": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise TaxAccountingLinkError::InvalidInput
  }
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("tax-accounting-link-v1"),
    "accepted_items": Json::array(accepted),
    "accounting_event_created": Json::boolean(true),
    "accounting_linked": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "tax_payment_recorded": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise TaxAccountingLinkError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: tax_accounting_link <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      TaxAccountingLinkError::InvalidInput => {
        println("tax accounting link failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      TaxAccountingLinkError::Io(_) => {
        println("tax accounting link failed: filesystem error")
        @sys.exit(1)
      }
      TaxAccountingLinkError::Money(_) => {
        println("tax accounting link failed: money validation")
        @sys.exit(1)
      }
      TaxAccountingLinkError::Tax(error) => {
        println("tax accounting link failed: tax validation: \{to_repr(error)}")
        @sys.exit(1)
      }
    }
  }
}
