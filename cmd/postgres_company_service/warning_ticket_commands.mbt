///|
/// Native warning-ticket lifecycle candidates. These projections preserve the
/// ERP status/reassign/extend semantics without sending notifications or
/// invoking a ticket provider.
fn warning_ticket_transition_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String)? {
  let prefixes = [
    "/api/company/warning/tickets/", "/api/company/source/warning/tickets/",
  ]
  for prefix in prefixes {
    if request_method is @http.Patch && path.has_prefix(prefix) {
      let rest = path[prefix.length():].to_owned().split("/").to_array()
      if rest.length() == 2 && valid_identifier(rest[0].to_owned()) {
        let command_type = match rest[1].to_owned() {
          "status" => "status"
          "reassign" => "reassign"
          "extend" => "extend"
          _ => ""
        }
        if !command_type.is_empty() {
          return Some((command_type, rest[0].to_owned()))
        }
      }
    }
  }
  None
}

///|
fn warning_ticket_request(
  command_type : String,
  ticket_id : String,
  body : Json,
  actor_id : String,
) -> Json {
  let request = Json::object({
    "ticket_id": Json::string(ticket_id),
    "command_type": Json::string(command_type),
    "actor_id": Json::string(actor_id),
  })
  match command_type {
    "status" => {
      let fields : Map[String, Json] = match request {
        Object(values) => values
        _ => {}
      }
      fields.set("status", Json::string(json_text(body, "status", "")))
      fields.set(
        "note",
        Json::string(json_text(body, "note", "").trim().to_owned()),
      )
      Json::object(fields)
    }
    "reassign" => {
      let fields : Map[String, Json] = match request {
        Object(values) => values
        _ => {}
      }
      fields.set(
        "new_assignee_user_id",
        Json::string(
          json_text(
            body,
            "newAssigneeUserId",
            json_text(body, "new_assignee_user_id", ""),
          ),
        ),
      )
      fields.set(
        "reason",
        Json::string(json_text(body, "reason", "").trim().to_owned()),
      )
      Json::object(fields)
    }
    _ => {
      let fields : Map[String, Json] = match request {
        Object(values) => values
        _ => {}
      }
      fields.set(
        "new_due_date",
        Json::string(
          json_text(body, "newDueDate", json_text(body, "new_due_date", ""))
          .trim()
          .to_owned(),
        ),
      )
      fields.set(
        "reason",
        Json::string(json_text(body, "reason", "").trim().to_owned()),
      )
      Json::object(fields)
    }
  }
}

///|
async fn warning_ticket_transition(
  command_type : String,
  ticket_id : String,
  body : Json,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(ticket_id) || !valid_identifier(idempotency_key) {
    raise reject(422, "ticket id and Idempotency-Key must be valid")
  }
  let profile = match auth_current_user(actor_id) {
    Some(value) => value
    None => raise reject(403, "user not found or disabled")
  }
  let profile_data = json_field(profile, "data").unwrap_or(Json::null())
  if !json_bool(profile_data, "enabled", false) {
    raise reject(403, "user not found or disabled")
  }
  let actor_user_id = json_text(profile_data, "userId", actor_id)
  let request = warning_ticket_request(command_type, ticket_id, body, actor_id)
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "command": existing,
          "ticket": json_field(existing, "result").unwrap_or(Json::null()),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let states = warning_ticket_states()
  let current = match states.get(ticket_id) {
    Some(value) => value
    None => raise reject(404, "工单不存在")
  }
  let current_status = report_text(current, "status", "open")
  let current_assignee = report_text(current, "assignee_user_id", "")
  let created_by = report_text(current, "created_by", "")
  let is_super_user = json_bool(profile_data, "isSuperUser", false)
  let warning_guid = report_text(current, "warning_guid", "")
  let mut next_status = current_status
  let mut next_assignee = current_assignee
  let mut next_due_date = report_text(current, "due_date", "")
  let mut next_note = report_text(current, "note", "")
  let mut next_handled_at = json_field(current, "handled_at").unwrap_or(
    Json::null(),
  )
  let mut next_handled_note = json_field(current, "handled_note").unwrap_or(
    Json::null(),
  )
  let changed_at = run_sql(
      "SELECT to_char(current_timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')",
    )
    .trim()
    .to_owned()
  let mut warning_resolved = false
  match command_type {
    "status" => {
      if current_assignee != actor_user_id &&
        current_assignee != actor_id &&
        !is_super_user {
        raise reject(403, "仅负责人或超级用户可操作")
      }
      let requested_status = json_text(body, "status", "")
      if requested_status != "handling" &&
        requested_status != "done" &&
        requested_status != "cancelled" {
        raise reject(400, "status must be handling/done/cancelled")
      }
      let note = json_text(body, "note", "").trim().to_owned()
      if note.length() > 1024 {
        raise reject(422, "note is too long")
      }
      next_status = requested_status
      if !note.is_empty() {
        next_handled_note = Json::string(note)
      }
      if requested_status == "done" || requested_status == "cancelled" {
        next_handled_at = Json::string(changed_at)
      } else {
        next_handled_at = Json::null()
      }
      warning_resolved = requested_status == "done"
    }
    "reassign" => {
      if current_assignee != actor_user_id &&
        current_assignee != actor_id &&
        created_by != actor_id &&
        created_by != actor_user_id &&
        !is_super_user {
        raise reject(
          403, "仅当前负责人 / 创建人 / 超级用户可重指派",
        )
      }
      if current_status != "open" && current_status != "handling" {
        raise reject(400, "当前状态不可重指派")
      }
      let new_assignee = json_text(
        body,
        "newAssigneeUserId",
        json_text(body, "new_assignee_user_id", ""),
      )
      if !valid_identifier(new_assignee) {
        raise reject(400, "newAssigneeUserId is required")
      }
      if new_assignee == current_assignee {
        raise reject(400, "new assignee is unchanged")
      }
      let users = raw_source_rows("sys_user", 500)
      if !users.any(fn(row) {
          json_text(row.payload, "user_id", row.record_id) == new_assignee
        }) {
        raise reject(404, "assignee user not found")
      }
      let reason = json_text(body, "reason", "").trim().to_owned()
      if reason.length() > 1024 {
        raise reject(422, "reason is too long")
      }
      for other_id, other in states {
        if other_id != ticket_id &&
          report_text(other, "state", "active") != "deleted" &&
          report_text(other, "warning_guid", "") == warning_guid &&
          report_text(other, "assignee_user_id", "") == new_assignee &&
          (
            report_text(other, "status", "open") == "open" ||
            report_text(other, "status", "open") == "handling"
          ) {
          raise reject(400, "新负责人已有进行中的同告警工单")
        }
      }
      next_assignee = new_assignee
      if current_status == "handling" {
        next_status = "open"
      }
      let reason_suffix = if reason.is_empty() {
        ""
      } else {
        " reason:" + reason
      }
      let detail = "[" +
        changed_at +
        " reassign] " +
        current_assignee +
        " -> " +
        new_assignee +
        reason_suffix
      next_note = if next_note.is_empty() {
        detail
      } else {
        next_note + "\n" + detail
      }
    }
    _ => {
      if current_assignee != actor_user_id &&
        current_assignee != actor_id &&
        !is_super_user {
        raise reject(403, "仅负责人或超级用户可延期")
      }
      if current_status != "open" && current_status != "handling" {
        raise reject(400, "当前状态不可延期")
      }
      let new_due_date = json_text(
          body,
          "newDueDate",
          json_text(body, "new_due_date", ""),
        )
        .trim()
        .to_owned()
      if new_due_date.is_empty() {
        raise reject(400, "newDueDate is required")
      }
      if new_due_date.length() > 32 {
        raise reject(422, "newDueDate is too long")
      }
      if !next_due_date.is_empty() && new_due_date <= next_due_date {
        raise reject(400, "new due date must be later than current due date")
      }
      let reason = json_text(body, "reason", "").trim().to_owned()
      if reason.length() > 1024 {
        raise reject(422, "reason is too long")
      }
      let old_due_date = if next_due_date.is_empty() {
        "unset"
      } else {
        next_due_date
      }
      let reason_suffix = if reason.is_empty() {
        ""
      } else {
        " reason:" + reason
      }
      let detail = "[" +
        changed_at +
        " extend] " +
        old_due_date +
        " -> " +
        new_due_date +
        reason_suffix
      next_due_date = new_due_date
      next_note = if next_note.is_empty() {
        detail
      } else {
        next_note + "\n" + detail
      }
    }
  }
  let event_id = "warning:ticket_" + command_type + ":" + idempotency_key
  let audit_id = event_id + ":audit"
  let result = Json::object({
    "ticketId": Json::string(ticket_id),
    "warningGuid": Json::string(warning_guid),
    "status": Json::string(next_status),
    "assigneeUserId": Json::string(next_assignee),
    "note": Json::string(next_note),
    "dueDate": Json::string(next_due_date),
    "handledAt": next_handled_at,
    "handledNote": next_handled_note,
    "transition": Json::string(command_type),
    "warningResolved": Json::boolean(warning_resolved),
    "persisted": Json::boolean(true),
    "sourceKind": Json::string("command"),
    "commandProjection": Json::boolean(true),
    "authorization_candidate": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "notificationSent": Json::boolean(false),
    "webhookSent": Json::boolean(false),
    "cashEffect": Json::boolean(false),
    "accountingEffect": Json::boolean(false),
    "taxEffect": Json::boolean(false),
  })
  let projection_fields : Map[String, Json] = match current {
    Object(values) => values
    _ => {}
  }
  projection_fields.set("ticket_id", Json::string(ticket_id))
  projection_fields.set("warning_guid", Json::string(warning_guid))
  projection_fields.set("assignee_user_id", Json::string(next_assignee))
  projection_fields.set("status", Json::string(next_status))
  projection_fields.set("note", Json::string(next_note))
  projection_fields.set("due_date", Json::string(next_due_date))
  projection_fields.set("handled_at", next_handled_at)
  projection_fields.set("handled_note", next_handled_note)
  projection_fields.set("state", Json::string("active"))
  projection_fields.set("source_kind", Json::string("command"))
  projection_fields.set("event_id", Json::string(event_id))
  let projection = Json::object(projection_fields)
  let command_payload = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("warning"),
    "command_type": Json::string("ticket_" + command_type),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("warning_ticket"),
    "aggregate_id": Json::string(ticket_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit_payload = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("warning.ticket_" + command_type),
    "aggregate_type": Json::string("warning_ticket"),
    "aggregate_id": Json::string(ticket_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "warning_guid": Json::string(warning_guid),
    "authorizing": Json::boolean(false),
    "notification_sent": Json::boolean(false),
    "webhook_sent": Json::boolean(false),
  })
  let warning_state_insert = if warning_resolved {
    let warning_state = Json::object({
      "warning_guid": Json::string(warning_guid),
      "command_type": Json::string("resolve"),
      "note": Json::string("通过工单 #" + ticket_id + " 处理"),
      "actor_id": Json::string(actor_id),
      "state": Json::string("resolved"),
      "source_kind": Json::string("command"),
      "event_id": Json::string(event_id),
      "updated_by": Json::string(actor_id),
      "changed_at": Json::string(changed_at),
    })
    " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT 'warning_state', " +
    @postgres.sql_literal(warning_guid) +
    ", coalesce(max(revision), 0) + 1, " +
    @postgres.sql_literal(warning_state.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    " FROM company_aggregate_projection WHERE aggregate_type = 'warning_state' AND aggregate_id = " +
    @postgres.sql_literal(warning_guid) +
    ";"
  } else {
    ""
  }
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) SELECT 'warning_ticket', " +
    @postgres.sql_literal(ticket_id) +
    ", coalesce(max(revision), 0) + 1, " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    " FROM company_aggregate_projection WHERE aggregate_type = 'warning_ticket' AND aggregate_id = " +
    @postgres.sql_literal(ticket_id) +
    ";" +
    warning_state_insert +
    " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit_payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT (source_id) DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  let receipt = match existing_company_command(idempotency_key) {
    Some(value) => value
    None => raise fail("warning ticket transition receipt was not persisted")
  }
  (
    200,
    Json::object({
      "command": receipt,
      "ticket": json_field(receipt, "result").unwrap_or(result),
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
