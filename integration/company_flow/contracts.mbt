///|
pub fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
pub fn revision(value : Json) -> Int32 raise {
  match field(value, "source_revision") {
    Number(n, ..) if n >= 1 && n <= 2147483647.0 && n == n.trunc() => n.to_int()
    _ => fail("Flow binding requires an exact positive task revision")
  }
}

///|
fn identifier(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 256 &&
  value
  .iter()
  .all(c => {
    c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    c == '-' ||
    c == '_' ||
    c == '.' ||
    c == ':'
  })
}

///|
fn sha256_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].iter().all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f'))
}

///|
pub fn snapshot(task : Json, source_revision : Int32) -> Json raise {
  if source_revision < 1 ||
    !identifier(text(task, "task_id")) ||
    !identifier(text(task, "project_id")) ||
    !identifier(text(task, "created_by")) ||
    text(task, "event_id").is_empty() ||
    text(task, "source_kind") != "command" ||
    !["pending", "in_progress", "blocked", "overdue"].contains(
      text(task, "state"),
    ) ||
    field(task, "execution") != Json::null() ||
    field(task, "delivery_source") != Json::null() {
    fail(
      "Flow binding supports active local digital-plan tasks without native execution only",
    )
  }
  {
    "contract_id": "moonproj.company-task-snapshot.v1",
    "task_id": text(task, "task_id"),
    "project_id": text(task, "project_id"),
    "source_revision": source_revision,
    "task": task,
  }
}

///|
pub fn validate_snapshot(value : Json) -> Unit raise {
  if value != snapshot(field(value, "task"), revision(value)) {
    fail("Company task snapshot is incomplete or inconsistent")
  }
}

///|
pub fn binding(
  snapshot : Json,
  flow_request : Json,
  reference : String,
  digest : String,
) -> Json raise {
  validate_snapshot(snapshot)
  if text(flow_request, "product_id") != "moonproj" ||
    text(flow_request, "operation") != "moonproj/project.plan.prepare@0.1.0" ||
    text(flow_request, "requested_authority") != "workspace-mutation" ||
    text(flow_request, "required_claim") != "digital-artifact" ||
    reference.is_empty() ||
    !sha256_digest(digest) {
    fail(
      "Flow binding requires the bounded digital plan capability and exact source digest",
    )
  }
  for
    key in [
      "run_id", "request_id", "work_item_id", "declaration_id", "attempt_id", "book_id",
    ] {
    if !identifier(text(flow_request, key)) {
      fail("Flow binding has invalid " + key)
    }
  }
  if text(flow_request, "idempotency_key").is_empty() ||
    !sha256_digest(text(flow_request, "input_digest")) {
    fail("Flow binding requires exact request and input identity")
  }
  {
    "contract_id": "moonproj.flow-task-binding.v2",
    "task_id": text(snapshot, "task_id"),
    "project_id": text(snapshot, "project_id"),
    "source_revision": revision(snapshot),
    "snapshot": snapshot,
    "company_snapshot_ref": reference,
    "company_snapshot_digest": digest,
    "flow_request": flow_request,
    "run_id": text(flow_request, "run_id"),
    "work_item_id": text(flow_request, "work_item_id"),
    "declaration_id": text(flow_request, "declaration_id"),
    "request_id": text(flow_request, "request_id"),
    "attempt_id": text(flow_request, "attempt_id"),
    "idempotency_key": text(flow_request, "idempotency_key"),
    "input_digest": text(flow_request, "input_digest"),
    "authorizing": false,
  }
}

///|
pub fn validate_binding(value : Json) -> Unit raise {
  if value !=
    binding(
      field(value, "snapshot"),
      field(value, "flow_request"),
      text(value, "company_snapshot_ref"),
      text(value, "company_snapshot_digest"),
    ) {
    fail("Flow binding checkpoint changed or is incomplete")
  }
}

///|
pub fn require_current(value : Json, current : Json) -> Unit raise {
  validate_binding(value)
  validate_snapshot(current)
  if field(value, "snapshot") != current {
    fail("Task revision changed; capture it and approve a new Flow attempt")
  }
}

///|
pub fn validate_approval(value : Json, command : Json) -> Unit raise {
  validate_binding(value)
  let request = field(command, "request")
  let result = field(command, "result")
  let actor = text(command, "actor_id")
  let key = text(command, "idempotency_key")
  let event = "flow_task_binding:approve:" + key
  if !identifier(key) ||
    actor != text(field(field(value, "snapshot"), "task"), "created_by") ||
    text(command, "kind") != "company_command" ||
    text(command, "command_family") != "flow_task_binding" ||
    text(command, "command_type") != "approve" ||
    text(command, "aggregate_type") != "plan_task" ||
    text(command, "aggregate_id") != text(value, "task_id") ||
    text(request, "actor_id") != actor ||
    text(request, "command_type") != "approve" ||
    field(request, "binding") != value ||
    text(result, "task_id") != text(value, "task_id") ||
    text(result, "actor_id") != actor ||
    text(result, "state") != "approved" ||
    field(result, "source_revision") != field(value, "source_revision") ||
    text(result, "event_id") != event ||
    text(result, "audit_id") != event + ":audit" ||
    field(result, "execution_effect") != Json::boolean(false) ||
    field(result, "acceptance_effect") != Json::boolean(false) {
    fail(
      "Approval receipt does not authorize this exact task revision and Flow request",
    )
  }
  let authority = field(request, "authority")
  if field(authority, "active") != Json::boolean(true) ||
    text(authority, "actor_id") != actor ||
    text(authority, "principal_id").is_empty() ||
    text(authority, "capability") != "project:task:update" ||
    text(authority, "scope") != "project:" + text(value, "project_id") {
    fail("Approval receipt requires the exact active project-scoped authority")
  }
}
