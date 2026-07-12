///|
pub(all) suberror LinkError {
  InvalidArguments
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Accounting(@accounting.AccountingEventError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise LinkError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise LinkError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise LinkError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise LinkError {
  match value {
    Object(value) => value
    _ => raise LinkError::InvalidInput
  }
}

///|
fn required(obj : Map[String, Json], key : String) -> Json raise LinkError {
  match obj.get(key) {
    Some(value) => value
    None => raise LinkError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise LinkError {
  match required(obj, key) {
    String(value) => value
    _ => raise LinkError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise LinkError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise LinkError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise LinkError {
  match required(obj, key) {
    Array(value) => value
    _ => raise LinkError::InvalidInput
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
    capability: "accounting:event:append",
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
fn run(plan_path : String, output_path : String) -> Unit raise LinkError {
  let root = object(read_json(plan_path))
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = required_array(root, "items")
  let actor_id = "migration"
  let mut log = @accounting.AccountingEventLog::empty()
  let accepted : Array[Json] = []
  let event_ids : Array[String] = []
  let journal_ids : Array[String] = []
  for item_value in items {
    let item = object(item_value)
    let disposition = required_string(item, "disposition")
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let target_type = required_string(item, "target_type")
    if target_type != "accounting_event_link" {
      raise LinkError::InvalidInput
    }
    if disposition != "ready_for_domain_import" {
      raise LinkError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = object(required(item, "target_candidate"))
    let journal = object(required(candidate, "journal"))
    let event_id = required_string(candidate, "event_id")
    let principal_id = required_string(candidate, "principal_id")
    let scope = required_string(candidate, "scope")
    let amount_minor = required_int64(journal, "amount_minor")
    let currency = required_string(journal, "currency")
    let amount = @finance.Money::new(minor=amount_minor, currency~) catch {
      _ => raise LinkError::InvalidInput
    }
    let journal_entry : @finance.JournalEntry = {
      entry_id: required_string(journal, "entry_id"),
      description: required_string(journal, "description"),
      postings: [
        {
          account: required_string(journal, "debit_account"),
          side: @finance.PostingSide::Debit,
          amount,
        },
        {
          account: required_string(journal, "credit_account"),
          side: @finance.PostingSide::Credit,
          amount,
        },
      ],
    }
    let source_type = required_string(candidate, "source_type")
    let source_event_id = required_string(candidate, "source_id")
    let event_type = required_string(candidate, "event_type")
    let source_target_type = required_string(candidate, "source_target_type")
    let expected_source_type = match source_target_type {
      "commitment" => source_table
      "employee_advance" => "employee_advance"
      "employee_advance_offset" => "employee_advance_offset"
      "payment_application" => "payment_application"
      _ => ""
    }
    if expected_source_type == "" ||
      source_type != expected_source_type ||
      source_event_id != source_id {
      raise LinkError::InvalidInput
    }
    let event = @accounting.AccountingEvent::new(
      event_id~,
      principal_id~,
      source_type~,
      source_id=source_event_id,
      event_type~,
      journal=journal_entry,
    ) catch {
      error => raise LinkError::Accounting(error)
    }
    log = log.append(
      event,
      scope~,
      actor_id~,
      grant=grant(event_id, principal_id, actor_id, scope, amount_minor),
    ) catch {
      error => raise LinkError::Accounting(error)
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "source_type": Json::string(source_type),
        "principal_id": Json::string(principal_id),
        "event_id": Json::string(event_id),
        "journal_id": Json::string(journal_entry.entry_id),
      }),
    )
    event_ids.push(event_id)
    journal_ids.push(journal_entry.entry_id)
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.accounting-link-receipt.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("validated_accounting_links"),
    "accepted_items": Json::array(accepted),
    "event_ids": strings_json(event_ids),
    "journal_ids": strings_json(journal_ids),
    "event_count": Json::number(log.events.length().to_double()),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise LinkError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: accounting_link <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      LinkError::Quarantined(source) => {
        println("accounting-link refused quarantined item: " + source)
        @sys.exit(1)
      }
      LinkError::InvalidInput => {
        println("accounting-link failed: invalid input")
        @sys.exit(1)
      }
      LinkError::Io(_) => {
        println("accounting-link failed: filesystem error")
        @sys.exit(1)
      }
      LinkError::Accounting(_) => {
        println("accounting-link failed: \\{to_repr(error)}")
        @sys.exit(1)
      }
      _ => {
        println("accounting-link failed")
        @sys.exit(1)
      }
    }
  }
}
