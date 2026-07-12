///|
pub(all) suberror ProgressPromotionError {
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Delivery(@delivery.DeliveryError)
  Money(@finance.MoneyError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ProgressPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ProgressPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ProgressPromotionError {
  match value {
    Object(value) => value
    _ => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ProgressPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ProgressPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ProgressPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ProgressPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ProgressPromotionError::InvalidInput
  }
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  actor_id : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id,
    capability: "delivery:progress:create",
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
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
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ProgressPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.delivery-progress-promotion-plan.v1" {
    raise ProgressPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = required_array(root, "items")
  let accepted : Array[Json] = []
  let report_ids : Array[String] = []
  for item_value in items {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    if required_string(item, "target_type") != "progress_report" {
      raise ProgressPromotionError::InvalidInput
    }
    if required_string(item, "disposition") != "ready_for_domain_import" {
      raise ProgressPromotionError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = object(required(item, "target_candidate"))
    if required_string(candidate, "state_policy") != "draft_only" {
      raise ProgressPromotionError::InvalidInput
    }
    let report_id = required_string(candidate, "report_id")
    if report_id != required_string(item, "target_id") || report_id != source_id {
      raise ProgressPromotionError::InvalidInput
    }
    let principal_id = required_string(candidate, "principal_id")
    let actor_id = required_string(candidate, "actor_id")
    let scope = required_string(candidate, "project_scope")
    let amount_minor = required_int64(candidate, "completed_value_minor")
    let evidence_ids : Array[String] = []
    for evidence_value in required_array(candidate, "evidence_ids") {
      match evidence_value {
        String(value) => evidence_ids.push(value)
        _ => raise ProgressPromotionError::InvalidInput
      }
    }
    let completed_value = @finance.Money::new(
      minor=amount_minor,
      currency=required_string(candidate, "currency"),
    ) catch {
      _ => raise ProgressPromotionError::InvalidInput
    }
    let report = @delivery.ProgressReport::new(
      report_id~,
      project_id=required_string(candidate, "project_id"),
      principal_id~,
      project_scope=scope,
      progress_bps=required_int64(candidate, "progress_bps"),
      completed_value~,
      evidence_ids~,
      actor_id~,
      grant=grant(
        "delivery-progress/" + source_id,
        principal_id,
        actor_id,
        scope,
        amount_minor,
      ),
    ) catch {
      _ => raise ProgressPromotionError::InvalidInput
    }
    if report.state != @delivery.ProgressState::Draft {
      raise ProgressPromotionError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("progress_report"),
        "target_id": Json::string(report.report_id),
        "target_candidate": candidate,
      }),
    )
    report_ids.push(report.report_id)
  }
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("delivery-progress-drafts-v1"),
    "accepted_items": Json::array(accepted),
    "progress_report_ids": strings_json(report_ids),
    "acceptance_created": Json::boolean(false),
    "recognition_created": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise ProgressPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: delivery_progress <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ProgressPromotionError::Quarantined(source) => {
        println("delivery progress refused quarantined item: " + source)
        @sys.exit(1)
      }
      ProgressPromotionError::InvalidInput => {
        println("delivery progress failed: invalid input")
        @sys.exit(1)
      }
      ProgressPromotionError::Io(_) => {
        println("delivery progress failed: filesystem error")
        @sys.exit(1)
      }
      ProgressPromotionError::Delivery(_) => {
        println("delivery progress failed: domain validation error")
        @sys.exit(1)
      }
      ProgressPromotionError::Money(_) => {
        println("delivery progress failed: invalid money")
        @sys.exit(1)
      }
    }
  }
}
