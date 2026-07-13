///|
pub(all) suberror RecognitionPromotionError {
  InvalidInput
  Quarantined(String)
  NoAcceptedItems
  Io(@fs.IOError)
  Delivery(@delivery.DeliveryError)
  Money(@finance.MoneyError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise RecognitionPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise RecognitionPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise RecognitionPromotionError {
  match value {
    Object(value) => value
    _ => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise RecognitionPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise RecognitionPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise RecognitionPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise RecognitionPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise RecognitionPromotionError::InvalidInput
  }
}

///|
fn string_array(
  obj : Map[String, Json],
  key : String,
) -> Array[String] raise RecognitionPromotionError {
  let values : Array[String] = []
  for value in required_array(obj, key) {
    match value {
      String(value) => values.push(value)
      _ => raise RecognitionPromotionError::InvalidInput
    }
  }
  values
}

///|
fn strings_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id,
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn postings_json(event : @accounting.AccountingEvent) -> Json {
  let postings : Array[Json] = []
  for posting in event.journal.postings {
    let side = match posting.side {
      @finance.PostingSide::Debit => "debit"
      @finance.PostingSide::Credit => "credit"
    }
    postings.push(
      Json::object({
        "account": Json::string(posting.account),
        "side": Json::string(side),
        "amount_minor": Json::number(
          posting.amount.minor.to_double(),
          repr=posting.amount.minor.to_string(),
        ),
        "currency": Json::string(posting.amount.currency),
      }),
    )
  }
  Json::array(postings)
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise RecognitionPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.delivery-recognition-promotion-plan.v1" {
    raise RecognitionPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = match required(root, "items") {
    Array(value) => value
    _ => raise RecognitionPromotionError::InvalidInput
  }
  let accepted : Array[Json] = []
  let recognition_ids : Array[String] = []
  for item_value in items {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    if required_string(item, "target_type") != "delivery_recognition" {
      raise RecognitionPromotionError::InvalidInput
    }
    if required_string(item, "disposition") != "ready_for_domain_import" {
      raise RecognitionPromotionError::Quarantined(
        source_table + ":" + source_id,
      )
    }
    let candidate = object(required(item, "target_candidate"))
    if required_string(candidate, "review_state") != "accepted" ||
      required_string(candidate, "amount_basis") != "reviewed_measurement" ||
      required_string(candidate, "report_id") != source_id ||
      required_string(item, "target_id") !=
      required_string(candidate, "recognition_id") {
      raise RecognitionPromotionError::InvalidInput
    }
    let principal_id = required_string(candidate, "principal_id")
    let project_id = required_string(candidate, "project_id")
    let scope = required_string(candidate, "project_scope")
    let amount_minor = required_int64(candidate, "completed_value_minor")
    let currency = required_string(candidate, "currency")
    let evidence_ids = string_array(candidate, "evidence_ids")
    let acceptance_evidence_ids = string_array(
      candidate, "acceptance_evidence_ids",
    )
    let accepted_by = required_string(candidate, "accepted_by")
    let created_by = required_string(candidate, "created_by")
    let completed_value = @finance.Money::new(minor=amount_minor, currency~) catch {
      _ => raise RecognitionPromotionError::InvalidInput
    }
    let report = @delivery.ProgressReport::new(
      report_id=source_id,
      project_id~,
      principal_id~,
      project_scope=scope,
      progress_bps=required_int64(candidate, "progress_bps"),
      completed_value~,
      evidence_ids~,
      actor_id=created_by,
      grant=grant(
        "delivery-recognition-create/" + source_id,
        principal_id,
        created_by,
        "delivery:progress:create",
        scope,
        amount_minor,
      ),
    ) catch {
      _ => raise RecognitionPromotionError::InvalidInput
    }
    let submitted = report.submit(
      actor_id=accepted_by,
      grant=grant(
        "delivery-recognition-submit/" + source_id,
        principal_id,
        accepted_by,
        "delivery:progress:submit",
        scope,
        amount_minor,
      ),
    ) catch {
      _ => raise RecognitionPromotionError::InvalidInput
    }
    let accepted_report = submitted.accept(
      actor_id=accepted_by,
      grant=grant(
        "delivery-recognition-accept/" + source_id,
        principal_id,
        accepted_by,
        "delivery:progress:accept",
        scope,
        amount_minor,
      ),
    ) catch {
      _ => raise RecognitionPromotionError::InvalidInput
    }
    let recognition = accepted_report.recognize(
      recognition_id=required_string(candidate, "recognition_id"),
      acceptance_id=required_string(candidate, "acceptance_id"),
      acceptance_evidence_ids~,
      accepted_by~,
      actor_id=created_by,
      contract_asset_account=required_string(
        candidate, "contract_asset_account",
      ),
      revenue_account=required_string(candidate, "revenue_account"),
      grant=grant(
        "delivery-recognition-link/" + source_id,
        principal_id,
        created_by,
        "delivery:recognition:create",
        scope,
        amount_minor,
      ),
    ) catch {
      _ => raise RecognitionPromotionError::InvalidInput
    }
    let event = recognition.accounting_event
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("delivery_recognition"),
        "target_id": Json::string(recognition.recognition_id),
        "target_candidate": Json::object({
          "recognition_id": Json::string(recognition.recognition_id),
          "report_id": Json::string(recognition.report_id),
          "project_id": Json::string(recognition.project_id),
          "principal_id": Json::string(recognition.principal_id),
          "project_scope": Json::string(recognition.project_scope),
          "progress_bps": Json::number(
            required_int64(candidate, "progress_bps").to_double(),
            repr=required_int64(candidate, "progress_bps").to_string(),
          ),
          "completed_value_minor": Json::number(
            amount_minor.to_double(),
            repr=amount_minor.to_string(),
          ),
          "amount_basis": Json::string("reviewed_measurement"),
          "currency": Json::string(currency),
          "evidence_ids": strings_json(evidence_ids),
          "acceptance_id": Json::string(recognition.acceptance_id),
          "acceptance_evidence_ids": strings_json(
            recognition.acceptance_evidence_ids,
          ),
          "accepted_by": Json::string(recognition.accepted_by),
          "created_by": Json::string(recognition.created_by),
          "review_state": Json::string("accepted"),
          "event_id": Json::string(event.event_id),
          "source_type": Json::string(event.source_type),
          "source_id": Json::string(event.source_id),
          "event_type": Json::string(event.event_type),
          "journal": Json::object({
            "entry_id": Json::string(event.journal.entry_id),
            "description": Json::string(event.journal.description),
            "postings": postings_json(event),
          }),
          "recognition_state": Json::string("pending_posting"),
          "posted": Json::boolean(false),
          "cash_released": Json::boolean(false),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
    recognition_ids.push(recognition.recognition_id)
  }
  if accepted.length() == 0 {
    raise RecognitionPromotionError::NoAcceptedItems
  }
  let ids : Array[Json] = []
  for id in recognition_ids {
    ids.push(Json::string(id))
  }
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("delivery-recognition-v1"),
    "accepted_items": Json::array(accepted),
    "delivery_recognition_ids": Json::array(ids),
    "recognition_created": Json::boolean(true),
    "posting_created": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise RecognitionPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: delivery_recognition <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      RecognitionPromotionError::Quarantined(source) => {
        println("delivery recognition refused quarantined item: " + source)
        @sys.exit(1)
      }
      RecognitionPromotionError::NoAcceptedItems => {
        println("delivery recognition found no reviewed accepted items")
        @sys.exit(1)
      }
      RecognitionPromotionError::InvalidInput => {
        println("delivery recognition failed: invalid input")
        @sys.exit(1)
      }
      RecognitionPromotionError::Io(_) => {
        println("delivery recognition failed: filesystem error")
        @sys.exit(1)
      }
      RecognitionPromotionError::Delivery(_) => {
        println("delivery recognition failed: domain validation error")
        @sys.exit(1)
      }
      RecognitionPromotionError::Money(_) => {
        println("delivery recognition failed: invalid money")
        @sys.exit(1)
      }
    }
  }
}
