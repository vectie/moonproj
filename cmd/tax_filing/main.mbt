///|
pub(all) suberror TaxFilingPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Tax(@tax.TaxError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise TaxFilingPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise TaxFilingPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise TaxFilingPromotionError {
  match value {
    Object(value) => value
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise TaxFilingPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise TaxFilingPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise TaxFilingPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise TaxFilingPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise TaxFilingPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn grant(
  principal_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "tax-filing-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn transition_filing(
  filing : @tax.TaxFiling,
  final_state : String,
  principal_id : String,
  scope : String,
  tax_amount_minor : Int64,
) -> @tax.TaxFiling raise TaxFilingPromotionError {
  let submitted = filing.transition(
    @tax.TaxFilingState::Submitted,
    actor_id="migration",
    grant=grant(principal_id, "tax:filing:submit", scope, tax_amount_minor),
  ) catch {
    error => raise TaxFilingPromotionError::Tax(error)
  }
  match final_state {
    "submitted" => submitted
    "accepted" =>
      submitted.transition(
        @tax.TaxFilingState::Accepted,
        actor_id="migration",
        grant=grant(principal_id, "tax:filing:accept", scope, tax_amount_minor),
      ) catch {
        error => raise TaxFilingPromotionError::Tax(error)
      }
    "rejected" =>
      submitted.transition(
        @tax.TaxFilingState::Rejected,
        actor_id="migration",
        grant=grant(principal_id, "tax:filing:reject", scope, tax_amount_minor),
      ) catch {
        error => raise TaxFilingPromotionError::Tax(error)
      }
    _ => raise TaxFilingPromotionError::InvalidInput
  }
}

///|
fn filing_state_name(state : @tax.TaxFilingState) -> String {
  match state {
    @tax.TaxFilingState::Prepared => "prepared"
    @tax.TaxFilingState::Submitted => "submitted"
    @tax.TaxFilingState::Accepted => "accepted"
    @tax.TaxFilingState::Rejected => "rejected"
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise TaxFilingPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.tax-filing-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise TaxFilingPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")
  let accepted : Array[Json] = []
  for filing_value in required_array(root, "filings") {
    let filing_obj = object(filing_value)
    let source_table = required_string(filing_obj, "source_table")
    let source_id = required_string(filing_obj, "source_id")
    let tax_id = required_string(filing_obj, "tax_id")
    let filing_id = required_string(filing_obj, "filing_id")
    let principal_id = required_string(filing_obj, "principal_id")
    let project_scope = required_string(filing_obj, "project_scope")
    let source_reference = required_string(filing_obj, "source_reference")
    let jurisdiction = required_string(filing_obj, "jurisdiction")
    let category = required_string(filing_obj, "category")
    let currency = required_string(filing_obj, "currency")
    let base_amount_minor = required_int64(filing_obj, "base_amount_minor")
    let tax_rate_bps = required_int64(filing_obj, "tax_rate_bps")
    let withholding_rate_bps = required_int64(
      filing_obj, "withholding_rate_bps",
    )
    let filing_period = required_string(filing_obj, "filing_period")
    let authority_reference = required_string(filing_obj, "authority_reference")
    let final_state = required_string(filing_obj, "final_state")
    let base_amount = @finance.Money::new(minor=base_amount_minor, currency~) catch {
      error => raise TaxFilingPromotionError::Money(error)
    }
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
      error => raise TaxFilingPromotionError::Tax(error)
    }
    let calculated = obligation.calculate(
      actor_id="migration",
      grant=grant(
        principal_id, "tax:calculate", project_scope, base_amount_minor,
      ),
    ) catch {
      error => raise TaxFilingPromotionError::Tax(error)
    }
    let reviewed = calculated.transition(
      @tax.TaxObligationState::Reviewed,
      actor_id="migration",
      grant=grant(principal_id, "tax:review", project_scope, base_amount_minor),
    ) catch {
      error => raise TaxFilingPromotionError::Tax(error)
    }
    let filing = reviewed.prepare_filing(
      filing_id~,
      filing_period~,
      authority_reference~,
      actor_id="migration",
      grant=grant(
        principal_id,
        "tax:filing:prepare",
        project_scope,
        reviewed.tax_amount.minor,
      ),
    ) catch {
      error => raise TaxFilingPromotionError::Tax(error)
    }
    let final_filing = transition_filing(
      filing,
      final_state,
      principal_id,
      project_scope,
      reviewed.tax_amount.minor,
    )
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("tax_filing"),
        "target_id": Json::string(final_filing.filing_id),
        "target_candidate": Json::object({
          "source_snapshot_id": Json::string(source_snapshot_id),
          "mapping_version": Json::string(mapping_version),
          "run_id": Json::string(run_id),
          "tax_id": Json::string(reviewed.tax_id),
          "filing_id": Json::string(final_filing.filing_id),
          "principal_id": Json::string(reviewed.principal_id),
          "project_scope": Json::string(reviewed.project_scope),
          "source_reference": Json::string(reviewed.source_reference),
          "jurisdiction": Json::string(reviewed.jurisdiction),
          "category": Json::string(reviewed.category),
          "filing_period": Json::string(final_filing.filing_period),
          "authority_reference": Json::string(final_filing.authority_reference),
          "base_amount_minor": number(reviewed.base_amount.minor),
          "tax_rate_bps": number(reviewed.tax_rate_bps),
          "withholding_rate_bps": number(reviewed.withholding_rate_bps),
          "tax_amount_minor": number(reviewed.tax_amount.minor),
          "withholding_amount_minor": number(reviewed.withholding_amount.minor),
          "reported_tax_amount_minor": number(
            final_filing.reported_tax_amount.minor,
          ),
          "currency": Json::string(final_filing.reported_tax_amount.currency),
          "obligation_state": Json::string("reviewed"),
          "filing_state": Json::string(filing_state_name(final_filing.state)),
          "obligation_event_count": number(reviewed.events.length().to_int64()),
          "filing_event_count": number(final_filing.events.length().to_int64()),
          "filing_reviewed": Json::boolean(true),
          "tax_payment_recorded": Json::boolean(false),
          "accounting_posted": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
  }
  if accepted.length() == 0 {
    raise TaxFilingPromotionError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("tax-filing-v1"),
    "accepted_items": Json::array(accepted),
    "tax_filing_count": number(accepted.length().to_int64()),
    "tax_payment_recorded": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise TaxFilingPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: tax_filing <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      TaxFilingPromotionError::InvalidInput => {
        println("tax filing promotion failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      TaxFilingPromotionError::Io(_) => {
        println("tax filing promotion failed: filesystem error")
        @sys.exit(1)
      }
      TaxFilingPromotionError::Money(_) => {
        println("tax filing promotion failed: money validation")
        @sys.exit(1)
      }
      TaxFilingPromotionError::Tax(_) => {
        println("tax filing promotion failed: tax validation")
        @sys.exit(1)
      }
    }
  }
}
