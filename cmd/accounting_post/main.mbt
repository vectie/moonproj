///|
pub(all) suberror PostError {
  InvalidArguments
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Accounting(@accounting.AccountingError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise PostError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PostError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise PostError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise PostError {
  match value {
    Object(value) => value
    _ => raise PostError::InvalidInput
  }
}

///|
fn required(obj : Map[String, Json], key : String) -> Json raise PostError {
  match obj.get(key) {
    Some(value) => value
    None => raise PostError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise PostError {
  match required(obj, key) {
    String(value) => value
    _ => raise PostError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise PostError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise PostError::InvalidInput
  }
}

///|
fn required_bool(obj : Map[String, Json], key : String) -> Bool raise PostError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise PostError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise PostError {
  match required(obj, key) {
    Array(value) => value
    _ => raise PostError::InvalidInput
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
    grant_id: "accounting-post/" + capability + "/" + scope,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn account_kind(value : String) -> @accounting.AccountKind raise PostError {
  match value {
    "asset" => @accounting.AccountKind::Asset
    "liability" => @accounting.AccountKind::Liability
    "equity" => @accounting.AccountKind::Equity
    "revenue" => @accounting.AccountKind::Revenue
    "expense" => @accounting.AccountKind::Expense
    _ => raise PostError::InvalidInput
  }
}

///|
fn posting_json(posting : @finance.Posting) -> Json {
  Json::object({
    "account": Json::string(posting.account),
    "side": Json::string(
      match posting.side {
        @finance.PostingSide::Debit => "debit"
        @finance.PostingSide::Credit => "credit"
      },
    ),
    "amount_minor": Json::number(
      posting.amount.minor.to_double(),
      repr=posting.amount.minor.to_string(),
    ),
    "currency": Json::string(posting.amount.currency),
  })
}

///|
fn postings_json(entry : @finance.JournalEntry) -> Json {
  let values : Array[Json] = []
  for posting in entry.postings {
    values.push(posting_json(posting))
  }
  Json::array(values)
}

///|
fn run(plan_path : String, output_path : String) -> Unit raise PostError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.accounting-posting-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise PostError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let book_obj = object(required(root, "book"))
  let book_id = required_string(book_obj, "book_id")
  let principal_id = required_string(book_obj, "principal_id")
  let scope = required_string(book_obj, "scope")
  let period_id = required_string(book_obj, "period_id")
  let period_label = required_string(book_obj, "period_label")
  let mut book = @accounting.AccountingBook::new(
    book_id~,
    principal_id~,
    scope~,
    actor_id="migration",
    grant=grant(principal_id, "accounting:book:create", scope, 0L),
  ) catch {
    error => raise PostError::Accounting(error)
  }
  for account_value in required_array(book_obj, "accounts") {
    let account_obj = object(account_value)
    let account_id = required_string(account_obj, "account_id")
    let account_code = required_string(account_obj, "account_code")
    let account_name = required_string(account_obj, "name")
    let kind = account_kind(required_string(account_obj, "kind"))
    let account_currency = required_string(account_obj, "currency")
    let account = @accounting.Account::new(
      account_id~,
      account_code~,
      name=account_name,
      kind~,
      currency=account_currency,
    ) catch {
      error => raise PostError::Accounting(error)
    }
    book = book.add_account(
      account,
      actor_id="migration",
      grant=grant(principal_id, "accounting:account:add", scope, 0L),
    ) catch {
      error => raise PostError::Accounting(error)
    }
  }
  book = book.open_period(
    period_id~,
    label=period_label,
    actor_id="migration",
    grant=grant(principal_id, "accounting:period:create", scope, 0L),
  ) catch {
    error => raise PostError::Accounting(error)
  }
  let accepted : Array[Json] = []
  let journal_ids : Array[String] = []
  let event_ids : Array[String] = []
  let seen_events : Map[String, Bool] = {}
  for item_value in required_array(root, "items") {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    if required_string(item, "target_type") != "accounting_posting" {
      raise PostError::InvalidInput
    }
    if required_string(item, "disposition") != "ready_for_posting" {
      raise PostError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = object(required(item, "target_candidate"))
    let candidate_principal = required_string(candidate, "principal_id")
    let candidate_scope = required_string(candidate, "scope")
    if candidate_principal != principal_id ||
      candidate_scope != scope ||
      required_string(candidate, "source_id") != source_id {
      raise PostError::InvalidInput
    }
    let event_id = required_string(candidate, "event_id")
    let link_event_id = required_string(candidate, "link_event_id")
    if link_event_id != event_id || seen_events.contains(event_id) {
      raise PostError::InvalidInput
    }
    seen_events[event_id] = true
    let journal = object(required(candidate, "journal"))
    let amount_minor = required_int64(journal, "amount_minor")
    let currency = required_string(journal, "currency")
    let amount = @finance.Money::new(minor=amount_minor, currency~) catch {
      _ => raise PostError::InvalidInput
    }
    let debit : @finance.Posting = {
      account: required_string(journal, "debit_account"),
      side: @finance.PostingSide::Debit,
      amount,
    }
    let credit : @finance.Posting = {
      account: required_string(journal, "credit_account"),
      side: @finance.PostingSide::Credit,
      amount,
    }
    let entry : @finance.JournalEntry = {
      entry_id: required_string(journal, "entry_id"),
      description: required_string(journal, "description"),
      postings: [debit, credit],
    }
    book = book.post(
      period_id~,
      entry,
      actor_id="migration",
      grant=grant(principal_id, "accounting:post", scope, amount_minor),
    ) catch {
      error => raise PostError::Accounting(error)
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("accounting_posting"),
        "target_id": Json::string(entry.entry_id),
        "target_candidate": Json::object({
          "book_id": Json::string(book_id),
          "period_id": Json::string(period_id),
          "principal_id": Json::string(principal_id),
          "scope": Json::string(scope),
          "event_id": Json::string(event_id),
          "link_event_id": Json::string(link_event_id),
          "source_type": Json::string(required_string(candidate, "source_type")),
          "source_id": Json::string(required_string(candidate, "source_id")),
          "event_type": Json::string(required_string(candidate, "event_type")),
          "journal": Json::object({
            "entry_id": Json::string(entry.entry_id),
            "description": Json::string(entry.description),
            "debit_account": Json::string(debit.account),
            "credit_account": Json::string(credit.account),
            "amount_minor": Json::number(
              amount_minor.to_double(),
              repr=amount_minor.to_string(),
            ),
            "currency": Json::string(currency),
            "postings": postings_json(entry),
          }),
          "posted": Json::boolean(true),
          "cash_released": Json::boolean(false),
          "accounting_posted": Json::boolean(true),
          "period_closed": Json::boolean(false),
        }),
      }),
    )
    journal_ids.push(entry.entry_id)
    event_ids.push(event_id)
  }
  if accepted.length() == 0 {
    raise PostError::InvalidInput
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("accounting-posting-v1"),
    "accepted_items": Json::array(accepted),
    "event_ids": strings_json(event_ids),
    "journal_ids": strings_json(journal_ids),
    "posted": Json::boolean(true),
    "cash_released": Json::boolean(false),
    "period_closed": Json::boolean(false),
    "accounting_posted": Json::boolean(true),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise PostError::Io(error)
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
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: accounting_post <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      PostError::Quarantined(source) => {
        println("accounting-post refused quarantined item: " + source)
        @sys.exit(1)
      }
      PostError::InvalidInput => {
        println("accounting-post failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      PostError::Io(_) => {
        println("accounting-post failed: filesystem error")
        @sys.exit(1)
      }
      PostError::Accounting(_) => {
        println("accounting-post failed: accounting invariant")
        @sys.exit(1)
      }
      _ => {
        println("accounting-post failed")
        @sys.exit(1)
      }
    }
  }
}
