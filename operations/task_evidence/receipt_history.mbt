///|
/// Read-only projection of existing persisted commands and their audit rows.
/// Callers supply {command, audit} pairs from the company store, never browser
/// claims. Missing audit rows are visible and do not erase command receipts.
pub fn receipt_history(task_id : String, rows : Array[Json]) -> Json {
  let receipts : Array[Json] = []
  let mut original : Json = Json::null()
  let seen : Map[String, Bool] = Map([])
  for row in rows {
    let command = field(row, "command")
    let request = field(command, "request")
    let result = field(command, "result")
    let audit = field(row, "audit")
    let family = text(command, "command_family")
    let action = text(command, "command_type")
    let task_command = family == "plan_task" &&
      text(command, "aggregate_id") == task_id &&
      text(request, "task_id") == task_id
    let report_command = family == "delivery" &&
      text(command, "family") == "task_report" &&
      text(request, "task_id") == task_id
    let event_id = text(row, "event_id")
    if (!task_command && !report_command) ||
      event_id.is_empty() ||
      seen.contains(event_id) {
      continue
    }
    seen[event_id] = true
    let actor = text(command, "actor_id")
    let audit_id = text(row, "audit_id")
    let audit_state = if audit is Null {
      "missing"
    } else if !audit_id.is_empty() &&
      text(audit, "event_id") == event_id &&
      text(audit, "actor_id") == actor &&
      (
        text(audit, "aggregate_id") == text(command, "aggregate_id") ||
        text(audit, "task_id") == task_id
      ) {
      "available"
    } else {
      "conflict"
    }
    let changes = field(request, "changes")
    let label = if report_command {
      "report"
    } else if action == "update" &&
      changes is Object(fields) &&
      fields.contains("offer_reply") {
      "offer_reply"
    } else if action == "update" && text(changes, "status") == "done" {
      "internal_acceptance"
    } else {
      action
    }
    receipts.push({
      "action": label,
      "actor_id": actor,
      "event_id": event_id,
      "audit_id": audit_id,
      "audit_state": audit_state,
      "revision": field(result, "revision"),
      "recorded_at": field(row, "recorded_at"),
      "state": field(result, "state"),
      "report_id": if report_command {
        field(request, "report_id")
      } else {
        field(changes, "accepted_report_id")
      },
      "delivery_source": if report_command {
        field(request, "delivery_source")
      } else {
        field(changes, "accepted_delivery_source")
      },
    })
    if task_command && action == "create" && original is Null {
      let fields : Map[String, Json] = Map([])
      for
        key in [
          "task_id", "project_id", "task_name", "remarks", "owner_id", "plan_begin_date",
          "plan_end_date", "source_context",
        ] {
        fields[key] = field(request, key)
      }
      original = Json::object(fields)
    }
  }
  let history : Json = {
    "task_id": task_id,
    "original_brief": original,
    "receipts": receipts,
    "customer_acceptance": "not_recorded_here",
    "cash": "not_recorded_here",
    "authorizing": false,
  }
  let offers = offer_draft_history(task_id, rows)
  if !offers.is_empty() && history is Object(fields) {
    fields["offer_history"] = Json::array(offers)
  }
  let replies = offer_reply_history(task_id, rows)
  if !replies.is_empty() && history is Object(fields) {
    fields["offer_reply_history"] = Json::array(replies)
  }
  history
}
