///|
pub suberror OfferReplyError {
  InvalidOfferReply(String)
} derive(Debug, Eq)

///|
fn offer_reply_keys() -> Array[String] {
  [
    "schema", "offer_revision", "respondent", "received_at", "summary", "kind", "evidence_kind",
    "source_reference", "supersedes_reply_id", "correction_reason",
  ]
}

///|
fn reply_optional_text(
  value : Json,
  key : String,
  limit : Int,
) -> Json raise OfferReplyError {
  offer_optional_text(value, key, limit) catch {
    InvalidOfferDraft(message) => raise InvalidOfferReply(message)
  }
}

///|
fn reply_positive_revision(value : Json) -> Bool {
  value is Number(number, ..) &&
  number > 0 &&
  number <= 9007199254740991.0 &&
  number.trunc() == number
}

///|
fn reply_utc_timestamp(value : String) -> Bool {
  if value.length() != 20 ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != 'Z' ||
    !offer_date(value[:10].to_owned()) {
    return false
  }
  for index in [11, 12, 14, 15, 17, 18] {
    if value[index] < '0' || value[index] > '9' {
      return false
    }
  }
  let hour = (value[11].to_int() - 48) * 10 + value[12].to_int() - 48
  let minute = (value[14].to_int() - 48) * 10 + value[15].to_int() - 48
  let second = (value[17].to_int() - 48) * 10 + value[18].to_int() - 48
  hour < 24 && minute < 60 && second < 60
}

///|
/// Normalize already-received feedback about one exact saved offer revision.
/// This record does not authenticate the respondent, accept an order or prove
/// customer acceptance or cash. Unknown respondent/time/reference remain null.
/// Text limits count Unicode characters; canonical JSON is at most 32KiB.
/// CR and CRLF become LF and outer whitespace is trimmed without flattening
/// multiline content. Corrections require an explicit predecessor and reason;
/// validating that predecessor against saved history is the command's job.
///
/// ```mbt check
/// test {
///   let reply = @task_evidence.normalize_offer_reply({
///     "schema": "moonproj.offer-reply.v1",
///     "offer_revision": 1,
///     "summary": "Please explain the timeline",
///     "kind": "changes_requested",
///     "evidence_kind": "human_observation",
///   })
///   assert_true(reply is { "respondent": Null, "received_at": Null, .. })
/// }
/// ```
pub fn normalize_offer_reply(value : Json) -> Json raise OfferReplyError {
  guard value is Object(values) else {
    raise InvalidOfferReply("offer_reply must be an object")
  }
  let keys = offer_reply_keys()
  for key, _ in values {
    if !keys.contains(key) {
      raise InvalidOfferReply("unknown offer_reply field: " + key)
    }
  }
  if field(value, "schema") != Json::string("moonproj.offer-reply.v1") {
    raise InvalidOfferReply("schema must be moonproj.offer-reply.v1")
  }
  if !reply_positive_revision(field(value, "offer_revision")) {
    raise InvalidOfferReply("offer_revision must be a positive safe integer")
  }
  let kind = text(value, "kind")
  if !["interested", "changes_requested", "declined", "other"].contains(kind) {
    raise InvalidOfferReply(
      "kind must be interested, changes_requested, declined or other",
    )
  }
  let evidence_kind = text(value, "evidence_kind")
  if evidence_kind != "reference" && evidence_kind != "human_observation" {
    raise InvalidOfferReply(
      "evidence_kind must be reference or human_observation",
    )
  }
  let normalized : Map[String, Json] = Map([])
  for key in keys {
    normalized[key] = if key == "schema" ||
      key == "offer_revision" ||
      key == "kind" ||
      key == "evidence_kind" {
      field(value, key)
    } else {
      let limit = if key == "summary" {
        8192
      } else if key == "source_reference" || key == "correction_reason" {
        2048
      } else if key == "received_at" {
        20
      } else {
        512
      }
      reply_optional_text(value, key, limit)
    }
  }
  let result = Json::object(normalized)
  if field(result, "summary") is Null {
    raise InvalidOfferReply("summary must be nonblank text")
  }
  if field(result, "received_at") is String(timestamp) &&
    !reply_utc_timestamp(timestamp) {
    raise InvalidOfferReply(
      "received_at must be a valid UTC timestamp YYYY-MM-DDTHH:mm:ssZ",
    )
  }
  if evidence_kind == "reference" && field(result, "source_reference") is Null {
    raise InvalidOfferReply(
      "source_reference is required for reference evidence",
    )
  }
  if field(result, "supersedes_reply_id") is String(_) &&
    field(result, "correction_reason") is Null {
    raise InvalidOfferReply(
      "correction_reason is required with supersedes_reply_id",
    )
  }
  if @utf8.encode(result.stringify()).length() > 32768 {
    raise InvalidOfferReply("canonical offer_reply exceeds 32KiB")
  }
  result
}

///|
fn reply_optional_project_matches(value : Json, project : Json) -> Bool {
  offer_optional_lineage_matches(value, "project_id", project) &&
  offer_optional_lineage_matches(value, "projectGuid", project)
}

///|
fn reply_command_lineage_matches(
  command : Json,
  request : Json,
  result : Json,
  task : String,
  event : String,
  audit : String,
  actor : String,
  revision : Json,
  reply : Json,
) -> Bool {
  let task_json = Json::string(task)
  let actor_json = Json::string(actor)
  let project = field(request, "project_id")
  let project_valid = match request {
    Object(fields) =>
      match fields.get("project_id") {
        None => true
        Some(String(project)) => !project.is_blank()
        _ => false
      }
    _ => false
  }
  let revision_ordered = match (field(reply, "offer_revision"), revision) {
    (Number(offer_revision, ..), Number(record_revision, ..)) =>
      offer_revision < record_revision
    _ => false
  }
  project_valid &&
  revision_ordered &&
  !actor.is_blank() &&
  !text(command, "idempotency_key").is_blank() &&
  offer_optional_lineage_matches(
    command,
    "kind",
    Json::string("company_command"),
  ) &&
  offer_optional_lineage_matches(
    command,
    "aggregate_type",
    Json::string("plan_task"),
  ) &&
  reply_optional_project_matches(command, project) &&
  offer_optional_lineage_matches(
    request,
    "command_type",
    Json::string("update"),
  ) &&
  offer_optional_lineage_matches(request, "actor_id", actor_json) &&
  offer_optional_lineage_matches(request, "taskGuid", task_json) &&
  offer_optional_lineage_matches(request, "projectGuid", project) &&
  offer_optional_lineage_matches(result, "task_id", task_json) &&
  offer_optional_lineage_matches(result, "taskGuid", task_json) &&
  offer_optional_lineage_matches(result, "aggregate_id", task_json) &&
  offer_optional_lineage_matches(result, "actor_id", actor_json) &&
  offer_optional_lineage_matches(result, "event_id", Json::string(event)) &&
  offer_optional_lineage_matches(result, "audit_id", Json::string(audit)) &&
  reply_optional_project_matches(result, project)
}

///|
fn reply_audit_matches(
  audit : Json,
  task : String,
  event : String,
  audit_id : String,
  actor : String,
  revision : Json,
  project : Json,
) -> Bool {
  let task_json = Json::string(task)
  !audit_id.is_blank() &&
  text(audit, "event_id") == event &&
  text(audit, "actor_id") == actor &&
  (text(audit, "aggregate_id") == task || text(audit, "task_id") == task) &&
  offer_optional_lineage_matches(audit, "aggregate_id", task_json) &&
  offer_optional_lineage_matches(audit, "task_id", task_json) &&
  offer_optional_lineage_matches(audit, "taskGuid", task_json) &&
  offer_optional_lineage_matches(audit, "audit_id", Json::string(audit_id)) &&
  offer_optional_lineage_matches(audit, "revision", revision) &&
  reply_optional_project_matches(audit, project)
}

///|
/// Read exact persisted company plan_task update command/audit pairs only.
/// Every original and correction remains visible at its recorded offer revision;
/// later offer updates never inherit a reply. Missing/conflicting audit remains
/// visible but cannot verify the save. Recorder identity comes from the stored
/// command actor, never the claimed respondent. Operation keys identify retries
/// and grant no authority. Callers must supply store rows, not client claims.
pub fn offer_reply_history(task_id : String, rows : Array[Json]) -> Array[Json] {
  let history : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  if task_id.is_blank() {
    return history
  }
  for row in rows {
    let command = field(row, "command")
    let request = field(command, "request")
    let result = field(command, "result")
    let revision = field(result, "revision")
    let event_id = text(row, "event_id")
    if text(command, "command_family") != "plan_task" ||
      text(command, "command_type") != "update" ||
      text(command, "aggregate_id") != task_id ||
      text(request, "task_id") != task_id ||
      event_id.is_blank() ||
      seen.contains(event_id) ||
      !reply_positive_revision(revision) {
      continue
    }
    let reply = normalize_offer_reply(
      field(field(request, "changes"), "offer_reply"),
    ) catch {
      _ => continue
    }
    seen[event_id] = true
    let actor = text(command, "actor_id")
    let audit = field(row, "audit")
    let audit_id = text(row, "audit_id")
    let audit_state = if !reply_command_lineage_matches(
        command, request, result, task_id, event_id, audit_id, actor, revision, reply,
      ) {
      "conflict"
    } else if audit is Null {
      "missing"
    } else if reply_audit_matches(
        audit,
        task_id,
        event_id,
        audit_id,
        actor,
        revision,
        field(request, "project_id"),
      ) {
      "available"
    } else {
      "conflict"
    }
    history.push({
      "reply_id": event_id,
      "event_id": event_id,
      "record_revision": revision,
      "recorded_by": actor,
      "recorded_at": match field(row, "recorded_at") {
        String(value) => Json::string(value)
        _ => Json::null()
      },
      "audit_id": audit_id,
      "audit_state": audit_state,
      "idempotency_key": text(command, "idempotency_key"),
      "offer_reply": reply,
      "customer_acceptance": "not_asserted",
      "cash": "not_asserted",
      "authorizing": false,
    })
  }
  history
}
