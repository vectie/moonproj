///|
fn book_lesson_handoff_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/lesson-handoff"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
fn lesson_handoff_ref(id : String, version : Json, snapshot : String) -> Json {
  {
    "record_id": id,
    "record_version": version.stringify(),
    "record_digest": "sha256:" +
    native_context_hash(@encoding/utf8.encode(snapshot)),
  }
}

///|
/// Read-only handoff of the exact accepted task and report currently returned
/// by the company service. Snapshot digests identify these captured projections;
/// they are not a new company receipt, customer outcome or acceptance authority.
fn book_lesson_handoff_projection(data : Json) -> Json raise GatewayError {
  let task = native_field(data, "task")
  let history = native_field(data, "commitment")
  let task_id = native_text(task, "taskGuid")
  let report_id = native_text(task, "accepted_report_id")
  guard valid_identifier(task_id) &&
    !report_id.is_empty() &&
    native_text(task, "status") == "done" &&
    native_text(history, "task_id") == task_id else {
    raise GatewayError::Upstream(
      "Open an accepted task with its exact accepted report and command receipts",
    )
  }
  let reports = match native_field(data, "reports") {
    Array(items) => items
    _ => []
  }
  let selected = reports.filter(item => {
    native_text(item, "reportGuid") == report_id
  })
  let receipts = match native_field(history, "receipts") {
    Array(items) => items
    _ => []
  }
  let accepted = receipts.filter(item => {
    native_text(item, "action") == "internal_acceptance" &&
    native_text(item, "report_id") == report_id
  })
  let reported = receipts.filter(item => {
    native_text(item, "action") == "report" &&
    native_text(item, "report_id") == report_id
  })
  guard selected.length() == 1 &&
    accepted.length() == 1 &&
    reported.length() == 1 else {
    raise GatewayError::Upstream(
      "Accepted report or its exact command receipts are missing or ambiguous",
    )
  }
  let report = selected[0]
  let acceptance = accepted[0]
  let receipt = reported[0]
  for item in [acceptance, receipt] {
    if native_text(item, "audit_state") != "available" ||
      [
        native_text(item, "actor_id"),
        native_text(item, "event_id"),
        native_text(item, "audit_id"),
      ].contains("") {
      raise GatewayError::Upstream(
        "The accepted task requires its available named command and audit receipts",
      )
    }
    guard native_field(item, "revision") is Number(revision, ..) &&
      revision >= 1 &&
      revision.trunc() == revision else {
      raise GatewayError::Upstream("The command revision is unavailable")
    }
  }
  guard native_field(task, "revision") is Number(revision, ..) &&
    revision >= 1 &&
    revision.trunc() == revision &&
    native_text(report, "task_id") == task_id &&
    native_field(report, "delivery_source") ==
    native_field(task, "accepted_delivery_source") &&
    native_field(receipt, "delivery_source") ==
    native_field(task, "accepted_delivery_source") &&
    native_field(acceptance, "delivery_source") ==
    native_field(task, "accepted_delivery_source") else {
    raise GatewayError::Upstream(
      "The accepted report no longer matches the task's exact delivery source",
    )
  }
  let task_snapshot = (
    {
      "task_id": task_id,
      "project_id": native_text(task, "projGuid"),
      "revision": native_field(task, "revision"),
      "title": native_text(task, "taskName"),
      "source_context": native_field(task, "source_context"),
      "accepted_report_id": report_id,
      "accepted_delivery_source": native_field(task, "accepted_delivery_source"),
      "acceptance_receipt": acceptance,
    } : Json).stringify()
  let report_snapshot = ({ "report": report, "receipt": receipt } : Json).stringify()
  {
    "contract_version": "moonproj.book-lesson-handoff.v1",
    "source_product": "moonproj",
    "task": lesson_handoff_ref(
      task_id,
      native_field(task, "revision"),
      task_snapshot,
    ),
    "report": lesson_handoff_ref(
      report_id,
      native_field(receipt, "revision"),
      report_snapshot,
    ),
    "task_snapshot": task_snapshot,
    "report_snapshot": report_snapshot,
    "customer_acceptance": "not_asserted",
    "cash": "not_asserted",
    "authorizing": false,
  }
}

///|
async fn book_lesson_handoff_task(
  bridge : NativeBridge,
  task_id : String,
) -> ProxyResult raise GatewayError {
  let detail = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
  if detail.status != 200 {
    return detail
  }
  let data = native_field(native_result_json(detail), "data")
  if native_text(native_field(data, "task"), "taskGuid") != task_id {
    raise GatewayError::Upstream("Company service returned another task")
  }
  native_json_result(200, book_lesson_handoff_projection(data))
}
