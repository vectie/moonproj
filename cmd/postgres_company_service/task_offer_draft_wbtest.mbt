///|
fn offer_service_fixture() -> Json {
  {
    "schema": "moonproj.offer-draft.v1",
    "title": "A bounded proposal",
    "buyer": "Private buyer",
    "problem": "Private problem",
    "state": "draft",
    "demand_state": "unproven",
  }
}

///|
fn offer_service_authority(
  actor? : String = "actor",
  scope? : String = "project:P",
  capability? : String = "project:task:update",
) -> Json {
  {
    "active": true,
    "principal_id": "principal",
    "actor_id": actor,
    "capability": capability,
    "scope": scope,
  }
}

///|
fn offer_service_body() -> Json {
  {
    "offer_draft": offer_service_fixture(),
    "offer_base_revision": 3,
    "authority": offer_service_authority(),
  }
}

///|
fn offer_service_replace(
  value : Json,
  key : String,
  replacement : Json,
) -> Json {
  let fields = match value {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields[key] = replacement
  Json::object(fields)
}

///|
test "offer create is optional and separate from ordinary acceptance and source" {
  let legacy : Json = {
    "task_id": "T",
    "task_type": "task",
    "remarks": "Internal criterion",
    "source_context": { "reference": "R", "problem": "Observed problem" },
  }
  assert_eq(plan_task_offer_on_create(legacy, {}), legacy)
  let added = plan_task_offer_on_create(legacy, {
    "offer_draft": offer_service_fixture(),
  })
  assert_eq(json_field(added, "remarks"), json_field(legacy, "remarks"))
  assert_eq(
    json_field(added, "source_context"),
    json_field(legacy, "source_context"),
  )
  let offer = json_field(added, "offer_draft").unwrap()
  assert_eq(json_field(offer, "price_amount"), Some(Json::null()))
  assert_eq(json_field(offer, "problem_observed_on"), Some(Json::null()))
  assert_eq(json_text(offer, "demand_state", ""), "unproven")
  try
    plan_task_offer_on_create(
      offer_service_replace(legacy, "task_type", "key_node"),
      { "offer_draft": offer_service_fixture() },
    )
  catch {
    CompanyServiceError::CommandRejected(status, _) => assert_eq(status, 422)
    _ => raise fail("unexpected error")
  } noraise {
    _ => raise fail("key nodes must not be proposal tasks")
  }
}

///|
test "offer save accepts only the proposal and explicit observed revision under task update authority" {
  let good = offer_service_body()
  let request = plan_task_offer_request("T", "P", good, "actor")
  assert_eq(json_int(request, "offer_base_revision", 0), 3)
  let changes = json_field(request, "changes").unwrap()
  assert_true(changes is Object(fields) && fields.length() == 1)
  let cases : Array[(String, Json)] = [
    ("status", "done"),
    ("remarks", "overwrite"),
    ("source_context", {}),
    ("execution", {}),
    ("offer_base_revision", 0),
    ("offer_base_revision", 3.5),
    ("authority", offer_service_authority(actor="other")),
    ("authority", offer_service_authority(scope="project:other")),
    ("authority", offer_service_authority(capability="project:task:create")),
  ]
  for (key, value) in cases {
    try
      plan_task_offer_request(
        "T",
        "P",
        offer_service_replace(good, key, value),
        "actor",
      )
    catch {
      CompanyServiceError::CommandRejected(status, _) =>
        assert_true(status == 422 || status == 403)
      _ => raise fail("unexpected error")
    } noraise {
      _ => raise fail("invalid proposal mutation accepted")
    }
  }
}

///|
test "offer save eligibility rejects already executed reviewed and nonordinary work" {
  let pending : Json = {
    "state": "pending",
    "task_type": "task",
    "source_kind": "command",
  }
  assert_true(plan_task_offer_eligible(pending))
  let cases : Array[(String, Json)] = [
    ("state", "done"),
    ("state", "in_progress"),
    ("state", "blocked"),
    ("state", "deleted"),
    ("task_type", "key_node"),
    ("execution", {}),
    ("continuations", [{}]),
    ("human_revisions", [{}]),
    ("accepted_report_id", "report"),
    ("selected_delivery_source", {}),
    ("accepted_delivery_source", {}),
    ("continuations", true),
    ("source_kind", "imported"),
  ]
  for (key, value) in cases {
    assert_false(
      plan_task_offer_eligible(offer_service_replace(pending, key, value)),
    )
  }
}

///|
test "offer update preserves task business state and public lists omit private proposal body" {
  let task : Json = {
    "task_id": "T",
    "project_id": "P",
    "created_by": "actor",
    "state": "pending",
    "remarks": "Internal criterion",
    "source_context": { "reference": "R", "problem": "Original" },
    "execution_workspace": "/authorized/work",
    "accepted_report_id": null,
  }
  let request = plan_task_offer_request("T", "P", offer_service_body(), "actor")
  let (command, audit, next) = plan_task_offer_payloads(
    "T", task, 3, request, "actor", "save-1",
  )
  for
    key in [
      "task_id", "project_id", "created_by", "state", "remarks", "source_context",
      "execution_workspace", "accepted_report_id",
    ] {
    assert_eq(json_field(next, key), json_field(task, key))
  }
  let list = plan_task_offer_public({ "taskGuid": "T" }, next, false)
  assert_true(json_field(list, "offer_draft") is None)
  assert_false(list.stringify().contains("Private buyer"))
  assert_false(list.stringify().contains("Private problem"))
  assert_true(
    json_field(
      plan_task_offer_public({ "taskGuid": "T" }, next, true),
      "offer_draft",
    )
    is Some(_),
  )
  // Unescape the outer DO-body literal once to inspect the exact guarded SQL.
  let sql = plan_task_offer_sql("T", task, 3, request, "actor", "save-1").replace_all(
    old="''",
    new="'",
  )
  assert_true(sql.contains("LOCK TABLE company_aggregate_projection"))
  assert_true(sql.contains("LOCK TABLE company_record"))
  assert_true(sql.contains("payload->>'state'='pending'"))
  assert_true(sql.contains("aggregate_type='task_report'"))
  assert_true(sql.contains("payload->'execution'"))
  assert_true(sql.contains(" = 3 AND NOT EXISTS"))
  assert_true(sql.contains(@postgres.sql_literal(command.stringify())))
  assert_true(sql.contains(@postgres.sql_literal(audit.stringify())))
  assert_true(sql.contains(@postgres.sql_literal(next.stringify())))
  assert_false(sql.contains("CREATE TABLE"))
}

///|
test "exact detail supplies real creator before first offer while task lists remain minimal" {
  let payload : Json = { "created_by": "actor", "state": "pending" }
  let item : Json = { "taskGuid": "T" }
  assert_eq(plan_task_offer_public(item, payload, false), item)
  let detail = plan_task_offer_public(item, payload, true)
  assert_eq(json_field(detail, "created_by"), Some("actor".to_json()))
  assert_true(json_field(detail, "offer_draft") is None)
}

///|
test "exact offer replay binds actor task authority revision and content" {
  let body = offer_service_body()
  let request = plan_task_offer_request("T", "P", body, "actor")
  let (command, _, _) = plan_task_offer_payloads(
    "T",
    { "state": "pending" },
    3,
    request,
    "actor",
    "save-1",
  )
  assert_true(
    json_bool(
      plan_task_offer_replay(command, "T", body, "actor"),
      "idempotent_replay",
      false,
    ),
  )
  for
    (task, actor, changed) in [
      ("T", "other", body),
      ("other", "actor", body),
      ("T", "actor", offer_service_replace(body, "offer_base_revision", 4)),
      (
        "T",
        "actor",
        offer_service_replace(
          body,
          "offer_draft",
          offer_service_replace(offer_service_fixture(), "title", "Different"),
        ),
      ),
    ] {
    try plan_task_offer_replay(command, task, changed, actor) catch {
      CompanyServiceError::CommandRejected(status, _) =>
        assert_true(status == 409 || status == 403)
      _ => raise fail("unexpected error")
    } noraise {
      _ => raise fail("misbound replay accepted")
    }
  }
}
