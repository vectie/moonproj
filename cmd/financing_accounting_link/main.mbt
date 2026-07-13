///|
pub(all) suberror FinancingAccountingLinkError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Financing(@financing.FinancingError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise FinancingAccountingLinkError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise FinancingAccountingLinkError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise FinancingAccountingLinkError {
  match value {
    Object(value) => value
    _ => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise FinancingAccountingLinkError {
  match obj.get(key) {
    Some(value) => value
    None => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise FinancingAccountingLinkError {
  match required(obj, key) {
    String(value) => value
    _ => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise FinancingAccountingLinkError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise FinancingAccountingLinkError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise FinancingAccountingLinkError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise FinancingAccountingLinkError {
  match required(obj, key) {
    Array(value) => value
    _ => raise FinancingAccountingLinkError::InvalidInput
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
) -> @finance.Money raise FinancingAccountingLinkError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise FinancingAccountingLinkError::Money(error)
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
    grant_id: "financing-accounting-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn event_json(
  event : @accounting.AccountingEvent,
  source_table : String,
  source_id : String,
  principal_id : String,
  scope : String,
  amount_minor : Int64,
  currency : String,
  action : String,
) -> Json raise FinancingAccountingLinkError {
  if event.source_type != "financing_facility" ||
    event.source_id != source_id ||
    event.principal_id != principal_id ||
    event.journal.entry_id != "financing/" + source_id + "/" + action ||
    event.journal.postings.length() != 2 ||
    event.journal.postings[0].amount.minor != amount_minor ||
    event.journal.postings[0].amount.currency != currency {
    raise FinancingAccountingLinkError::InvalidInput
  }
  Json::object({
    "source_table": Json::string(source_table),
    "source_id": Json::string(source_id),
    "target_type": Json::string("financing_facility"),
    "target_id": Json::string(source_id),
    "target_candidate": Json::object({
      "principal_id": Json::string(event.principal_id),
      "scope": Json::string(scope),
      "event_id": Json::string(event.event_id),
      "event_type": Json::string(event.event_type),
      "source_type": Json::string(event.source_type),
      "source_id": Json::string(event.source_id),
      "journal_id": Json::string(event.journal.entry_id),
      "description": Json::string(event.journal.description),
      "debit_account": Json::string(event.journal.postings[0].account),
      "credit_account": Json::string(event.journal.postings[1].account),
      "amount_minor": number(event.journal.postings[0].amount.minor),
      "currency": Json::string(event.journal.postings[0].amount.currency),
      "action": Json::string(action),
      "accounting_event_created": Json::boolean(true),
      "accounting_linked": Json::boolean(false),
      "accounting_posted": Json::boolean(false),
      "cash_released": Json::boolean(false),
      "period_closed": Json::boolean(false),
    }),
  })
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise FinancingAccountingLinkError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.financing-accounting-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise FinancingAccountingLinkError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for value in required_array(root, "facilities") {
    let item = object(value)
    let source_table = required_string(item, "source_table")
    let facility_id = required_string(item, "facility_id")
    let principal_id = required_string(item, "principal_id")
    let project_scope = required_string(item, "project_scope")
    let currency = required_string(item, "currency")
    let limit_minor = required_int64(item, "limit_amount_minor")
    let draw_minor = required_int64(item, "draw_amount_minor")
    let repay_minor = required_int64(item, "repay_amount_minor")
    let annual_rate_bps = required_int64(item, "annual_rate_bps")
    let lender_id = required_string(item, "lender_id")
    let limit_amount = money(limit_minor, currency)
    let facility = @financing.FinancingFacility::new(
      facility_id~,
      principal_id~,
      project_scope~,
      lender_id~,
      limit_amount~,
      annual_rate_bps~,
      actor_id="migration",
      grant=grant(principal_id, "financing:create", project_scope, limit_minor),
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    let facility = facility.approve(
      actor_id="migration",
      grant=grant(principal_id, "financing:approve", project_scope, limit_minor),
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    let facility = facility.activate(
      actor_id="migration",
      grant=grant(
        principal_id, "financing:activate", project_scope, limit_minor,
      ),
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    let draw_amount = money(draw_minor, currency)
    let facility_after_draw = facility.draw(
      amount=draw_amount,
      actor_id="migration",
      grant=grant(principal_id, "financing:draw", project_scope, draw_minor),
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    let draw = object(required(item, "draw"))
    let draw_id = required_string(draw, "source_id")
    let draw_event_id = required_string(draw, "event_id")
    let draw_event_type = required_string(draw, "event_type")
    let draw_cash_account = required_string(draw, "debit_account")
    let draw_liability_account = required_string(draw, "credit_account")
    let draw_event = facility_after_draw.to_draw_event(
      draw_id~,
      event_id=draw_event_id,
      event_type=draw_event_type,
      amount=draw_amount,
      cash_account=draw_cash_account,
      liability_account=draw_liability_account,
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    accepted.push(
      event_json(
        draw_event, source_table, draw_id, principal_id, project_scope, draw_minor,
        currency, "draw",
      ),
    )
    let repay_amount = money(repay_minor, currency)
    let facility_after_repay = facility_after_draw.repay(
      amount=repay_amount,
      actor_id="migration",
      grant=grant(principal_id, "financing:repay", project_scope, repay_minor),
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    let repayment = object(required(item, "repayment"))
    let repayment_id = required_string(repayment, "source_id")
    let repayment_event_id = required_string(repayment, "event_id")
    let repayment_event_type = required_string(repayment, "event_type")
    let repayment_liability_account = required_string(
      repayment, "debit_account",
    )
    let repayment_cash_account = required_string(repayment, "credit_account")
    let repayment_event = facility_after_repay.to_repayment_event(
      repayment_id~,
      event_id=repayment_event_id,
      event_type=repayment_event_type,
      amount=repay_amount,
      liability_account=repayment_liability_account,
      cash_account=repayment_cash_account,
    ) catch {
      error => raise FinancingAccountingLinkError::Financing(error)
    }
    accepted.push(
      event_json(
        repayment_event, source_table, repayment_id, principal_id, project_scope,
        repay_minor, currency, "repayment",
      ),
    )
  }
  if accepted.length() == 0 {
    raise FinancingAccountingLinkError::InvalidInput
  }
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("financing-accounting-link-v1"),
    "accepted_items": Json::array(accepted),
    "accounting_event_created": Json::boolean(true),
    "accounting_linked": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise FinancingAccountingLinkError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: financing_accounting_link <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      FinancingAccountingLinkError::InvalidInput => {
        println("financing accounting link failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      FinancingAccountingLinkError::Io(_) => {
        println("financing accounting link failed: filesystem error")
        @sys.exit(1)
      }
      FinancingAccountingLinkError::Money(_) => {
        println("financing accounting link failed: money validation")
        @sys.exit(1)
      }
      FinancingAccountingLinkError::Financing(_) => {
        println("financing accounting link failed: financing validation")
        @sys.exit(1)
      }
    }
  }
}
