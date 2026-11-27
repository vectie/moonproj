///|
#derive(Debug, Eq)
pub suberror OfferDraftError {
  InvalidOfferDraft(String)
}

///|
fn offer_draft_keys() -> Array[String] {
  [
    "schema", "title", "buyer", "buyer_reference", "problem", "problem_observed_on",
    "scope", "exclusions", "deliverables", "acceptance_criteria", "price_amount",
    "price_currency", "price_basis", "timing", "dependencies", "proof_sought", "state",
    "closure_reason", "demand_state",
  ]
}

///|
fn offer_clean_text(
  value : String,
  key : String,
  limit : Int32,
) -> String raise OfferDraftError {
  let result = StringBuilder()
  let mut after_cr = false
  for char in value {
    let code = char.to_int()
    if (code < 32 && char != '\n' && char != '\r' && char != '\t') ||
      (code >= 127 && code <= 159) ||
      (code >= 0xd800 && code <= 0xdfff) ||
      code == 0x061c ||
      code == 0x200e ||
      code == 0x200f ||
      (code >= 0x2028 && code <= 0x202e) ||
      (code >= 0x2066 && code <= 0x2069) {
      raise InvalidOfferDraft(
        key + " contains an unsupported control character",
      )
    }
    if char == '\r' {
      result.write_char('\n')
    } else if char != '\n' || !after_cr {
      result.write_char(char)
    }
    after_cr = char == '\r'
  }
  let normalized = result.to_string().trim().to_owned()
  if normalized.iter().count() > limit {
    raise InvalidOfferDraft(key + " is too long")
  }
  normalized
}

///|
fn offer_optional_text(
  value : Json,
  key : String,
  limit : Int32,
) -> Json raise OfferDraftError {
  match field(value, key) {
    Null => Json::null()
    String(value) => {
      let normalized = offer_clean_text(value, key, limit)
      if normalized.is_empty() {
        Json::null()
      } else {
        Json::string(normalized)
      }
    }
    _ => raise InvalidOfferDraft(key + " must be text or null")
  }
}

///|
fn offer_text_array(value : Json, key : String) -> Json raise OfferDraftError {
  let items = match field(value, key) {
    Null => return Json::array([])
    Array(items) => items
    _ => raise InvalidOfferDraft(key + " must be a text array")
  }
  if items.length() > 32 {
    raise InvalidOfferDraft(key + " has too many entries")
  }
  let normalized : Array[Json] = []
  for item in items {
    guard item is String(value) else {
      raise InvalidOfferDraft(key + " entries must be text")
    }
    let cleaned = offer_clean_text(value, key, 2048)
    if !cleaned.is_empty() {
      normalized.push(Json::string(cleaned))
    }
  }
  Json::array(normalized)
}

///|
fn offer_decimal(value : String) -> Bool {
  let mut whole = 0
  let mut fraction = 0
  let mut decimal = false
  for char in value {
    if char >= '0' && char <= '9' {
      if decimal {
        fraction += 1
      } else {
        whole += 1
      }
    } else if char == '.' && !decimal {
      decimal = true
    } else {
      return false
    }
  }
  whole > 0 && (!decimal || (fraction > 0 && fraction <= 2))
}

///|
fn offer_date(value : String) -> Bool {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    return false
  }
  for index in [0, 1, 2, 3, 5, 6, 8, 9] {
    if value[index] < '0' || value[index] > '9' {
      return false
    }
  }
  let year = (value[0].to_int() - 48) * 1000 +
    (value[1].to_int() - 48) * 100 +
    (value[2].to_int() - 48) * 10 +
    value[3].to_int() -
    48
  let month = (value[5].to_int() - 48) * 10 + value[6].to_int() - 48
  let day = (value[8].to_int() - 48) * 10 + value[9].to_int() - 48
  if year == 0 || month < 1 || month > 12 || day < 1 {
    return false
  }
  let days = if month == 2 {
    if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
      29
    } else {
      28
    }
  } else if [4, 6, 9, 11].contains(month) {
    30
  } else {
    31
  }
  day <= days
}

///|
/// Normalize the explicit v1 contract without inventing buyer, price or demand
/// evidence. Missing ordinary content remains saveable and visibly unresolved.
/// Limits count Unicode characters; the final canonical JSON is at most 64KiB.
///
/// ```mbt check
/// test {
///   let draft = @task_evidence.normalize_offer_draft({
///     "schema": "moonproj.offer-draft.v1",
///     "state": "draft",
///     "demand_state": "unproven",
///   })
///   assert_true(draft is { "title": String(""), "price_amount": Null, .. })
/// }
/// ```
pub fn normalize_offer_draft(value : Json) -> Json raise OfferDraftError {
  guard value is Object(values) else {
    raise InvalidOfferDraft("offer_draft must be an object")
  }
  let keys = offer_draft_keys()
  for key, _ in values {
    if !keys.contains(key) {
      raise InvalidOfferDraft("unknown offer_draft field: " + key)
    }
  }
  if field(value, "schema") != Json::string("moonproj.offer-draft.v1") {
    raise InvalidOfferDraft("schema must be moonproj.offer-draft.v1")
  }
  let state = field(value, "state")
  if state != Json::string("draft") && state != Json::string("closed") {
    raise InvalidOfferDraft("state must be draft or closed")
  }
  if field(value, "demand_state") != Json::string("unproven") {
    raise InvalidOfferDraft("demand_state must remain unproven")
  }
  let normalized : Map[String, Json] = Map([])
  for key in keys {
    normalized[key] = if key == "schema" ||
      key == "state" ||
      key == "demand_state" {
      field(value, key)
    } else if key == "deliverables" || key == "acceptance_criteria" {
      offer_text_array(value, key)
    } else if key == "title" {
      match offer_optional_text(value, key, 256) {
        Null => Json::string("")
        text => text
      }
    } else {
      offer_optional_text(value, key, if key == "buyer" { 256 } else { 8192 })
    }
  }
  let result = Json::object(normalized)
  if field(result, "price_amount") is String(amount) && !offer_decimal(amount) {
    raise InvalidOfferDraft(
      "price_amount must be a nonnegative decimal text with at most two fractional digits",
    )
  }
  if field(result, "price_currency") is String(currency) &&
    (
      currency.length() != 3 ||
      !currency.iter().all(char => char >= 'A' && char <= 'Z')
    ) {
    raise InvalidOfferDraft(
      "price_currency must contain three uppercase ASCII letters",
    )
  }
  if field(result, "problem_observed_on") is String(date) && !offer_date(date) {
    raise InvalidOfferDraft(
      "problem_observed_on must be a valid YYYY-MM-DD date",
    )
  }
  if state == Json::string("closed") && field(result, "closure_reason") is Null {
    raise InvalidOfferDraft("closure_reason is required when state is closed")
  }
  if @utf8.encode(result.stringify()).length() > 65536 {
    raise InvalidOfferDraft("canonical offer_draft exceeds 64KiB")
  }
  result
}

///|
fn offer_unresolved_normalized(value : Json) -> Array[String] {
  let unresolved : Array[String] = []
  for key in offer_draft_keys() {
    if key == "schema" ||
      key == "state" ||
      key == "demand_state" ||
      (key == "closure_reason" && text(value, "state") != "closed") {
      continue
    }
    match field(value, key) {
      Null | String("") | Array([]) => unresolved.push(key)
      _ => ()
    }
  }
  unresolved
}

///|
/// Return missing content keys in fixed contract order. A price amount and its
/// currency are independently unresolved; an explicit zero is real input.
pub fn offer_draft_unresolved(
  value : Json,
) -> Array[String] raise OfferDraftError {
  offer_unresolved_normalized(normalize_offer_draft(value))
}

///|
/// Minimal status projection, excluding buyer, problem, price and source bodies.
pub fn offer_draft_summary(value : Json) -> Json raise OfferDraftError {
  let normalized = normalize_offer_draft(value)
  {
    "schema": "moonproj.offer-draft-summary.v1",
    "title": field(normalized, "title"),
    "state": field(normalized, "state"),
    "demand_state": "unproven",
    "unresolved_fields": offer_unresolved_normalized(normalized),
  }
}

///|
fn offer_markdown_text(value : String) -> String {
  let result = StringBuilder()
  for line in value.split("\n") {
    result.write_string("> ")
    for char in line {
      match char {
        '&' => result.write_string("&amp;")
        '<' => result.write_string("&lt;")
        '>' => result.write_string("&gt;")
        '!'..<='/' | ':'..<='@' | '['..<='`' | '{'..<='~' => {
          result.write_char('\\')
          result.write_char(char)
        }
        _ => result.write_char(char)
      }
    }
    result.write_char('\n')
  }
  result.to_string()
}

///|
fn offer_markdown_field(
  result : StringBuilder,
  value : Json,
  key : String,
  label : String,
) -> Unit {
  result.write_string("## " + label + "\n\n")
  match field(value, key) {
    String(value) if !value.is_empty() =>
      result.write_string(offer_markdown_text(value))
    Array(items) if !items.is_empty() =>
      for index, item in items {
        result.write_string("Item " + (index + 1).to_string() + ":\n\n")
        if item is String(value) {
          result.write_string(offer_markdown_text(value))
        }
        result.write_char('\n')
      }
    _ => result.write_string("UNRESOLVED\n")
  }
  result.write_char('\n')
}

///|
/// Deterministic, inspectable Markdown. User content is inert escaped quoted
/// text, never generated headings, links or raw HTML. Source metadata is caller
/// supplied and is labelled canonical only with both IDs and a positive revision.
/// No actor, token, operation key or execution ID is accepted or exported.
pub fn offer_draft_markdown(
  value : Json,
  task_id~ : String,
  project_id~ : String,
  revision~ : Int32,
) -> String raise OfferDraftError {
  let normalized = normalize_offer_draft(value)
  let task = offer_clean_text(task_id, "task_id", 512)
  let project = offer_clean_text(project_id, "project_id", 512)
  let result = StringBuilder()
  result.write_string("# Offer draft\n\n## Source\n\n")
  if !task.is_empty() && !project.is_empty() && revision > 0 {
    result.write_string("Canonical task-linked offer draft\n\nTask:\n\n")
    result.write_string(offer_markdown_text(task))
    result.write_string("\nProject:\n\n")
    result.write_string(offer_markdown_text(project))
    result.write_string("\nTask revision: " + revision.to_string() + "\n\n")
  } else {
    result.write_string(
      "Local draft export. No canonical saved revision is established.\n\n",
    )
  }
  result.write_string(
    "## Status\n\nOffer state: " +
    text(normalized, "state") +
    "\n\nDemand state: unproven\n\nThis draft does not establish customer acceptance, revenue or cash.\n\n",
  )
  for
    (key, label) in [
      ("title", "Title"),
      ("buyer", "Buyer"),
      ("buyer_reference", "Buyer reference"),
      ("problem", "Observed problem"),
      ("problem_observed_on", "Problem observed on"),
      ("scope", "Scope"),
      ("exclusions", "Exclusions"),
      ("deliverables", "Deliverables"),
      ("acceptance_criteria", "Acceptance criteria"),
      ("price_amount", "Price amount"),
      ("price_currency", "Price currency"),
      ("price_basis", "Price basis"),
      ("timing", "Timing"),
      ("dependencies", "Dependencies"),
      ("proof_sought", "Proof sought"),
    ] {
    offer_markdown_field(result, normalized, key, label)
  }
  if field(normalized, "closure_reason") is String(_) {
    offer_markdown_field(result, normalized, "closure_reason", "Closure reason")
  }
  result.write_string("## Unresolved fields\n\n")
  let unresolved = offer_unresolved_normalized(normalized)
  if unresolved.is_empty() {
    result.write_string("None. Completed fields do not prove demand.\n")
  } else {
    for key in unresolved {
      result.write_string("- " + key + "\n")
    }
  }
  result.to_string()
}

///|
fn offer_optional_lineage_matches(
  value : Json,
  key : String,
  expected : Json,
) -> Bool {
  match value {
    Object(fields) =>
      match fields.get(key) {
        None => true
        Some(actual) => actual == expected
      }
    _ => false
  }
}

///|
/// Project offer revisions from exact task-scoped persisted command/audit pairs.
/// Missing/conflicting audit remains visible and cannot establish a verified
/// save. The operation key supports exact retry recovery, never authorization.
/// Callers must provide rows read from the store, not browser-supplied claims.
/// Present lineage markers must match exactly; omitted legacy markers are
/// tolerated, while a missing actor or operation key cannot verify a save.
pub fn offer_draft_history(task_id : String, rows : Array[Json]) -> Array[Json] {
  let history : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  if task_id.is_blank() {
    return history
  }
  for row in rows {
    let command = field(row, "command")
    let request = field(command, "request")
    let action = text(command, "command_type")
    let event_id = text(row, "event_id")
    if text(command, "command_family") != "plan_task" ||
      text(command, "aggregate_id") != task_id ||
      text(request, "task_id") != task_id ||
      (action != "create" && action != "update") ||
      event_id.is_empty() ||
      seen.contains(event_id) {
      continue
    }
    let result = field(command, "result")
    let revision = field(result, "revision")
    guard revision is Number(number, ..) &&
      number > 0 &&
      number <= 9007199254740991.0 &&
      number.trunc() == number else {
      continue
    }
    let offer = if action == "create" {
      field(request, "offer_draft")
    } else {
      field(field(request, "changes"), "offer_draft")
    }
    let normalized = normalize_offer_draft(offer) catch { _ => continue }
    seen[event_id] = true
    let audit = field(row, "audit")
    let audit_id = text(row, "audit_id")
    let actor = text(command, "actor_id")
    let operation_key = text(command, "idempotency_key")
    let lineage_matches = !actor.is_blank() &&
      !operation_key.is_blank() &&
      offer_optional_lineage_matches(result, "task_id", Json::string(task_id)) &&
      offer_optional_lineage_matches(result, "taskGuid", Json::string(task_id)) &&
      offer_optional_lineage_matches(result, "event_id", Json::string(event_id)) &&
      offer_optional_lineage_matches(result, "audit_id", Json::string(audit_id)) &&
      (
        audit is Null ||
        offer_optional_lineage_matches(audit, "revision", revision)
      )
    let audit_state = if !lineage_matches {
      "conflict"
    } else if audit is Null {
      "missing"
    } else if !audit_id.is_empty() &&
      text(audit, "event_id") == event_id &&
      text(audit, "actor_id") == actor &&
      (
        text(audit, "aggregate_id") == task_id ||
        text(audit, "task_id") == task_id
      ) {
      "available"
    } else {
      "conflict"
    }
    history.push({
      "revision": revision,
      "event_id": event_id,
      "audit_id": audit_id,
      "audit_state": audit_state,
      "recorded_at": match field(row, "recorded_at") {
        String(value) => Json::string(value)
        _ => Json::null()
      },
      "idempotency_key": Json::string(operation_key),
      "offer_draft": normalized,
    })
  }
  history
}
