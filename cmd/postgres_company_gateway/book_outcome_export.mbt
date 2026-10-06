///|
fn book_outcome_export_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/outcome-export"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) && id != "." && id != ".." {
      return Some(id)
    }
  }
  None
}

///|
fn outcome_export_fields(
  value : Json,
  keys : Array[String],
  label : String,
) -> Unit raise GatewayError {
  guard value is Object(fields) &&
    fields.length() == keys.length() &&
    keys.all(key => fields.contains(key)) else {
    raise fail(label + " has missing or unsupported fields")
  }
}

///|
fn outcome_export_text(
  value : Json,
  key : String,
  limit : Int,
) -> String raise GatewayError {
  guard native_field(value, key) is String(text) &&
    !text.trim().is_empty() &&
    @encoding/utf8.encode(text).length() <= limit else {
    raise fail(
      "Provide " + key + " as nonblank text within the supported size limit",
    )
  }
  text
}

///|
fn outcome_export_integer(value : Json, key : String) -> Int raise GatewayError {
  guard native_field(value, key) is Number(number, ..) &&
    number >= 0 &&
    number <= 2147483647 &&
    number.trunc() == number else {
    raise fail(
      "Provide " + key + " as an exact nonnegative epoch-second integer",
    )
  }
  number.to_int()
}

///|
// A display link supplied by the mounted Proj page. It is never a fetch target,
// source of company identity, credential, or authority.
fn outcome_export_owner_route(
  draft : Json,
  task_id : String,
) -> String raise GatewayError {
  let route = outcome_export_text(draft, "owner_route", 4096)
  let prefix = if route.has_prefix("https://") {
    "https://"
  } else if route.has_prefix("http://") {
    "http://"
  } else {
    raise fail("The task display route must use HTTP or HTTPS")
  }
  let after_scheme = route[prefix.length():]
  guard after_scheme.find("/") is Some(slash) && slash > 0 else {
    raise fail("The task display route needs its actual origin and page path")
  }
  let authority = after_scheme[:slash]
  let query = "?page=dispatch&task=" + task_id.replace(old=":", new="%3A")
  if authority.contains("@") ||
    route.contains("#") ||
    route.contains("\\") ||
    route.iter().any(character => character < '!' || character > '~') ||
    !route.has_suffix(query) ||
    route.find("?") != Some(route.length() - query.length()) {
    raise fail(
      "The task display route must omit credentials, unrelated query fields and fragments and name this exact task",
    )
  }
  route
}

///|
fn outcome_export_gap(
  draft : Json,
  key : String,
  evidence_ids : Array[String],
) -> Bool raise GatewayError {
  let gap = native_field(draft, key)
  outcome_export_fields(
    gap,
    ["present", "severity", "summary", "evidence_refs"],
    key,
  )
  guard native_field(gap, "present") is (True | False) else {
    raise fail(
      "Explicitly choose whether " +
      key +
      " was observed; unknown is not absence",
    )
  }
  let present = native_field(gap, "present") == Json::boolean(true)
  let severity = outcome_export_integer(gap, "severity")
  if (present && (severity < 1 || severity > 5)) || (!present && severity != 0) {
    raise fail(key + " needs severity 1–5 when present and zero when absent")
  }
  ignore(outcome_export_text(gap, "summary", 4096))
  guard native_field(gap, "evidence_refs") is Array(references) &&
    !references.is_empty() else {
    raise fail("Select the captured evidence supporting " + key)
  }
  let seen : Array[String] = []
  for reference in references {
    guard reference is String(id) &&
      evidence_ids.contains(id) &&
      !seen.contains(id) else {
      raise fail(
        key + " must cite unique evidence from this exact captured task/report",
      )
    }
    seen.push(id)
  }
  present
}

///|
fn book_outcome_export_projection(
  handoff : Json,
  draft : Json,
) -> Json raise GatewayError {
  outcome_export_fields(
    draft,
    [
      "outcome_summary", "observed_at", "recorded_at", "information_gap", "recognition_gap",
      "decisiveness_gap", "capability", "owner_route",
    ],
    "Outcome draft",
  )
  let task_ref = native_field(handoff, "task")
  let report_ref = native_field(handoff, "report")
  let task_id = native_text(task_ref, "record_id")
  let report_id = native_text(report_ref, "record_id")
  if native_text(handoff, "contract_version") !=
    "moonproj.book-lesson-handoff.v1" ||
    native_text(handoff, "source_product") != "moonproj" ||
    native_field(handoff, "authorizing") != Json::boolean(false) ||
    native_text(handoff, "customer_acceptance") != "not_asserted" ||
    native_text(handoff, "cash") != "not_asserted" ||
    !valid_identifier(task_id) ||
    !valid_identifier(report_id) ||
    task_id == report_id {
    raise fail(
      "The exact accepted task/report handoff is unavailable or ambiguous",
    )
  }
  for key in ["task", "report"] {
    let reference = native_field(handoff, key)
    let snapshot = native_text(handoff, key + "_snapshot")
    if native_text(reference, "record_version").is_empty() ||
      native_text(reference, "record_digest") !=
      "sha256:" + native_context_hash(@encoding/utf8.encode(snapshot)) {
      raise fail(
        "The captured " + key + " bytes no longer match their exact reference",
      )
    }
  }
  let task = @json.parse(native_text(handoff, "task_snapshot")) catch {
    _ => raise fail("The task snapshot is invalid")
  }
  let report_snapshot = @json.parse(native_text(handoff, "report_snapshot")) catch {
    _ => raise fail("The accepted report snapshot is invalid")
  }
  let report = native_field(report_snapshot, "report")
  let title = outcome_export_text(task, "title", 4096)
  let deliverable_summary = outcome_export_text(report, "summary", 65536)
  let outcome_summary = outcome_export_text(draft, "outcome_summary", 8192)
  let observed_at = outcome_export_integer(draft, "observed_at")
  let recorded_at = outcome_export_integer(draft, "recorded_at")
  if recorded_at < observed_at {
    raise fail(
      "The observation cannot be later than this export's recorded time",
    )
  }
  let evidence_ids = [task_id, report_id]
  let owner_route = outcome_export_owner_route(draft, task_id)
  let information = outcome_export_gap(draft, "information_gap", evidence_ids)
  let recognition = outcome_export_gap(draft, "recognition_gap", evidence_ids)
  let decisiveness = outcome_export_gap(draft, "decisiveness_gap", evidence_ids)
  let capability = native_field(draft, "capability")
  if capability is Null {
    if information || recognition || decisiveness {
      raise fail(
        "A present gap needs the real capability change descriptor; keep the draft if no change is proposed",
      )
    }
  } else {
    outcome_export_fields(
      capability,
      ["id", "version", "summary", "change_text"],
      "Capability change",
    )
    ignore(outcome_export_text(capability, "id", 256))
    ignore(outcome_export_text(capability, "version", 128))
    ignore(outcome_export_text(capability, "summary", 4096))
    ignore(outcome_export_text(capability, "change_text", 65536))
  }
  // The exact digest basis excludes its own identity and is retained as bytes
  // in the companion evidence file. Unchanged input is the same export.
  let basis : Json = {
    "contract_version": "moonproj.outcome-authoring.v1",
    "handoff": handoff,
    "draft": draft,
  }
  let basis_text = basis.stringify()
  let digest = native_context_hash(@encoding/utf8.encode(basis_text))
  let identity = "moonproj-outcome-" + digest
  let handoff_filename = identity + "-handoff.json"
  let evidence_filename = identity + "-evidence.json"
  let submission_ref : Json = {
    "record_id": identity,
    "record_version": "1",
    "record_digest": "sha256:" + digest,
  }
  let evidence : Array[Json] = ["task", "report"].map(key => {
    let reference = native_field(handoff, key)
    {
      "reference_id": native_field(reference, "record_id"),
      "reference_version": native_field(reference, "record_version"),
      "digest": native_field(reference, "record_digest"),
      "provenance_ref": handoff_filename + "#/" + key + "_snapshot",
    }
  })
  let fields : Map[String, Json] = {
    "contract_version": Json::string(
      "moonbook.bookkeeper.product_outcome_submission.v1",
    ),
    "submission": submission_ref,
    "source_product": Json::string("moonproj"),
    "deliverable_title": Json::string(title),
    "deliverable_summary": Json::string(deliverable_summary),
    "outcome_summary": Json::string(outcome_summary),
    "owner_route": Json::string(owner_route),
    "evidence_refs": Json::array(evidence),
    // The task snapshot contains the named internal acceptance. This is
    // decision evidence, never a customer response or a Book review.
    "decision_evidence_id": Json::string(task_id),
    "observed_at": observed_at.to_json(),
    "recorded_at": recorded_at.to_json(),
    "information_gap": native_field(draft, "information_gap"),
    "recognition_gap": native_field(draft, "recognition_gap"),
    "decisiveness_gap": native_field(draft, "decisiveness_gap"),
  }
  if !(capability is Null) {
    fields["capability_id"] = native_field(capability, "id")
    fields["capability_version"] = native_field(capability, "version")
    fields["capability_summary"] = native_field(capability, "summary")
    fields["capability_change_digest"] = Json::string(
      "sha256:" +
      native_context_hash(
        @encoding/utf8.encode(native_text(capability, "change_text")),
      ),
    )
  }
  let submission = Json::object(fields)
  let evidence_bundle : Json = {
    "contract_version": "moonproj.outcome-evidence.v1",
    "handoff": handoff,
    "draft": draft,
    "submission": submission_ref,
    "digest_basis": basis_text,
    "customer_acceptance": "not_asserted",
    "cash": "not_asserted",
    "authorizing": false,
    "notice": "Authored observations and gap judgments are supplied claims for Book review. Source hashes identify retained bytes; internal acceptance is not customer acceptance, cash, or capability activation.",
  }
  {
    "contract_version": "moonproj.outcome-export.v1",
    "handoff": handoff,
    "draft": draft,
    "submission": submission,
    "evidence_bundle": evidence_bundle,
    "submission_filename": identity + ".json",
    "handoff_filename": handoff_filename,
    "evidence_filename": evidence_filename,
    "submission_json": submission.stringify(indent=2),
    "handoff_json": handoff.stringify(indent=2),
    "evidence_json": evidence_bundle.stringify(indent=2),
  }
}

///|
// This authenticated operation only reads canonical company task state.
// No execution observation, company command, or Book transmission occurs.
async fn book_outcome_export_task(
  bridge : NativeBridge,
  task_id : String,
  request : Json,
) -> ProxyResult raise GatewayError {
  outcome_export_fields(request, ["handoff", "draft"], "Outcome export request")
  let captured = book_lesson_handoff_task(bridge, task_id)
  if captured.status != 200 {
    return captured
  }
  let current = native_result_json(captured)
  if native_field(request, "handoff") != current {
    return native_json_result(409, {
      "error": "The accepted task/report changed. Your outcome draft is unchanged; explicitly refresh the source before preparing a new export.",
      "state": "source_changed",
      "task_id": task_id,
    })
  }
  native_json_result(
    200,
    book_outcome_export_projection(current, native_field(request, "draft")),
  )
}
