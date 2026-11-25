///|
fn assert_charter_rejected(
  body : Json,
  actor_id : String,
  key : String,
) -> Unit raise {
  try company_charter_upsert_request(body, actor_id, key) catch {
    error => assert_eq(service_error_response(error).0, 422)
  } noraise {
    _ => assert_true(false, msg="expected charter request to be rejected")
  }
}

///|
fn sample_charter_body() -> Json {
  {
    "mission": {
      "title": "  OPC Doctoral Research Lab  ",
      "north_star": "  Complete doctoral research on One-Person Companies  ",
      "active_stage_id": "opening-defense",
    },
    "stages": [
      {
        "id": "proposal",
        "order": 1,
        "title": "  Proposal  ",
        "status": "achieved",
        "weight_pct": 25,
        "outcome": "Approved by faculty committee",
      },
      {
        "id": "opening-defense",
        "order": 2,
        "title": "Opening Defense",
        "status": "active",
        "weight_pct": 50,
        "milestone_task_id": "OPC-TASK-1",
      },
    ],
    "roles": [
      {
        "id": "founder",
        "name": "  Founder  ",
        "tier": 0,
        "kind": "human",
        "mission": "Set research direction and make 20% critical decisions",
        "powers": ["  approve deliverables  ", "set priorities"],
        "limits": ["never fabricate citations"],
      },
      {
        "id": "research-director",
        "name": "Research Director",
        "tier": 1,
        "kind": "agent",
        "reports_to": "founder",
        "mission": "Coordinate specialist agents and synthesize drafts",
        "powers": ["delegate specialist tasks"],
        "limits": ["no owner acceptance"],
        "skill_ref": "skills/research-director/SKILL.md",
        "model": "claude-opus-4",
      },
    ],
    "resources": [
      {
        "id": "opc-research-book",
        "name": "  OPC Research Book  ",
        "kind": "moonbook",
        "uri": "file:///books/opc-research-lab",
        "desk_url": "http://127.0.0.1:4201/?workspace=book-opc-research",
        "owner_role": "research-director",
        "notes": "Primary research knowledge book",
      },
    ],
    "evolution_log": [
      {
        "id": "evo-1",
        "date": "2026-11-25",
        "target": "agent",
        "target_id": "research-director",
        "change": "Require independent corpus verification before synthesis",
        "evidence": "Opening defense review feedback",
      },
    ],
    "critical_task_ids": ["  OPC-TASK-1  ", "OPC-TASK-2"],
  }
}

///|
test "company charter response distinguishes empty vs persisted charter" {
  let empty = company_charter_response(None)
  assert_true(json_bool(empty, "success", false))
  assert_eq(json_int(empty, "code", -1), 0)
  assert_eq(json_field(empty, "charter"), Some(Json::null()))
  assert_false(json_bool(empty, "persisted", true))
  assert_false(json_bool(empty, "authorizing", true))

  let persisted = company_charter_response(
    Some({
      "schema": "moonproj.company-charter.v1",
      "charter_id": "current",
      "revision": 3,
      "mission": { "title": "OPC Lab" },
    }),
  )
  assert_true(json_bool(persisted, "success", false))
  assert_eq(json_int(persisted, "code", -1), 0)
  assert_true(json_bool(persisted, "persisted", false))
  assert_false(json_bool(persisted, "authorizing", true))
  let charter = json_field(persisted, "charter").unwrap()
  assert_eq(json_text(charter, "schema", ""), "moonproj.company-charter.v1")
  assert_eq(json_int(charter, "revision", 0), 3)
}

///|
test "company charter request validates trims and applies defaults canonically" {
  let request = company_charter_upsert_request(
    sample_charter_body(),
    "desktop-user",
    "charter-init-1",
  )
  assert_eq(json_text(request, "command_type", ""), "upsert_company_charter")
  assert_eq(json_text(request, "actor_id", ""), "desktop-user")
  assert_eq(json_field(request, "expected_revision"), Some(Json::null()))

  let mission = json_field(request, "mission").unwrap()
  assert_eq(json_text(mission, "title", ""), "OPC Doctoral Research Lab")
  assert_eq(
    json_text(mission, "north_star", ""),
    "Complete doctoral research on One-Person Companies",
  )
  assert_eq(json_text(mission, "active_stage_id", ""), "opening-defense")
  assert_eq(json_text(mission, "focus_ratio", ""), "80/20")

  let roles = match json_field(request, "roles") {
    Some(Array(items)) => items
    _ => []
  }
  assert_eq(roles.length(), 2)
  assert_eq(json_text(roles[0], "name", ""), "Founder")
  assert_eq(json_text(roles[0], "version", ""), "v1")
  assert_eq(json_text(roles[0], "status", ""), "active")
  let founder_powers = match json_field(roles[0], "powers") {
    Some(Array(items)) => items
    _ => []
  }
  assert_eq(founder_powers, [
    Json::string("approve deliverables"),
    Json::string("set priorities"),
  ])

  let resources = match json_field(request, "resources") {
    Some(Array(items)) => items
    _ => []
  }
  assert_eq(resources.length(), 1)
  assert_eq(json_text(resources[0], "name", ""), "OPC Research Book")
  assert_eq(json_text(resources[0], "access", ""), "read_only")

  let critical_tasks = match json_field(request, "critical_task_ids") {
    Some(Array(items)) => items
    _ => []
  }
  assert_eq(critical_tasks, [
    Json::string("OPC-TASK-1"),
    Json::string("OPC-TASK-2"),
  ])

  // Explicit expected_revision is preserved in canonical request
  let with_rev = company_charter_upsert_request(
    { "mission": { "title": "Minimal Charter" }, "expected_revision": 2 },
    "desktop-user",
    "charter-rev-2",
  )
  assert_eq(json_int(with_rev, "expected_revision", -1), 2)
  assert_false(json_equal(request, with_rev))
}

///|
test "company charter rejects invalid stage status duplicate role IDs invalid resource kind and bad identities" {
  // Invalid stage status
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "stages": [
        {
          "id": "s1",
          "order": 1,
          "title": "Stage 1",
          "status": "completed",
          "weight_pct": 25,
        },
      ],
    },
    "desktop-user",
    "k1",
  )

  // Stage weight out of range
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "stages": [
        {
          "id": "s1",
          "order": 1,
          "title": "Stage 1",
          "status": "active",
          "weight_pct": 101,
        },
      ],
    },
    "desktop-user",
    "k2",
  )

  // Duplicate stage IDs
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "stages": [
        {
          "id": "dup",
          "order": 1,
          "title": "One",
          "status": "achieved",
          "weight_pct": 50,
        },
        {
          "id": "dup",
          "order": 2,
          "title": "Two",
          "status": "active",
          "weight_pct": 50,
        },
      ],
    },
    "desktop-user",
    "k3",
  )

  // Duplicate role IDs
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "roles": [
        { "id": "director", "name": "Director 1", "tier": 1, "kind": "agent" },
        { "id": "director", "name": "Director 2", "tier": 1, "kind": "agent" },
      ],
    },
    "desktop-user",
    "k4",
  )

  // Invalid role tier and kind
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "roles": [{ "id": "r1", "name": "Bad Tier", "tier": 3, "kind": "agent" }],
    },
    "desktop-user",
    "k5",
  )
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "roles": [{ "id": "r1", "name": "Bad Kind", "tier": 1, "kind": "bot" }],
    },
    "desktop-user",
    "k6",
  )

  // Invalid resource kind and duplicate resource IDs
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "resources": [{ "id": "res-1", "name": "Bad Kind", "kind": "database" }],
    },
    "desktop-user",
    "k7",
  )
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "resources": [
        { "id": "res-1", "name": "First", "kind": "moonbook" },
        { "id": "res-1", "name": "Second", "kind": "corpus" },
      ],
    },
    "desktop-user",
    "k8",
  )

  // Invalid evolution target and empty change
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "evolution_log": [
        { "id": "e1", "target": "human", "change": "Updated rule" },
      ],
    },
    "desktop-user",
    "k9",
  )
  assert_charter_rejected(
    {
      "mission": { "title": "OPC" },
      "evolution_log": [{ "id": "e1", "target": "company", "change": "   " }],
    },
    "desktop-user",
    "k10",
  )

  // Invalid actor_id, invalid idempotency_key, negative expected_revision, missing mission title
  assert_charter_rejected(sample_charter_body(), "bad/actor", "k11")
  assert_charter_rejected(sample_charter_body(), "desktop-user", "")
  assert_charter_rejected(
    sample_charter_body(),
    "desktop-user",
    Array::make(100, "k").join(""),
  )
  assert_charter_rejected(
    { "mission": { "title": "OPC" }, "expected_revision": -1 },
    "desktop-user",
    "k12",
  )
  assert_charter_rejected(
    { "mission": { "title": "   " } },
    "desktop-user",
    "k13",
  )
}

///|
test "company charter SQL enforces locks idempotency revision increment expected_revision guard and audit event" {
  let request = company_charter_upsert_request(
    {
      "mission": { "title": "OPC Lab", "north_star": "Ship research" },
      "expected_revision": 1,
    },
    "desktop-user",
    "charter-key-1",
  )
  let sql = company_charter_upsert_sql(request, "charter-key-1")
  assert_true(
    sql
    .find("LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE")
    .unwrap() <
    sql.find("DO '").unwrap(),
  )
  assert_true(
    sql.contains("LOCK TABLE company_record IN SHARE ROW EXCLUSIVE MODE"),
  )
  assert_true(sql.contains("ON COMMIT DROP"))
  assert_true(sql.contains("canonical->''request'' IS DISTINCT FROM request"))
  assert_true(
    sql.find("IF canonical IS NOT NULL").unwrap() <
    sql.find("ELSIF expected_rev IS NOT NULL").unwrap(),
  )
  assert_true(
    sql.contains(
      "ELSIF expected_rev IS NOT NULL AND coalesce(current_revision, 0) <> expected_rev",
    ),
  )
  assert_true(
    sql.contains("next_revision := coalesce(current_revision, 0) + 1"),
  )
  assert_true(sql.contains("''moonproj.company-charter.v1''"))
  assert_true(sql.contains("''company_charter''"))
  assert_true(sql.contains("''company_charter.upsert''"))
  assert_true(sql.contains("''company_audit_event''"))
  assert_true(sql.contains("''company_command''"))
  assert_true(sql.contains("CASE WHEN next_revision = 1 THEN 201 ELSE 200 END"))
  assert_true(sql.contains("canonical_reference"))
  assert_false(sql.contains("ON CONFLICT"))

  let read_sql = company_charter_read_sql()
  assert_true(read_sql.contains("aggregate_type = 'company_charter'"))
  assert_true(read_sql.contains("aggregate_id = 'current'"))
  assert_true(
    read_sql.contains(
      "ORDER BY company_aggregate_projection.revision DESC LIMIT 1",
    ),
  )
}

///|
test "company charter post-commit recovery accepts matching receipt and rejects mismatch" {
  let request = company_charter_upsert_request(
    { "mission": { "title": "OPC Lab" } },
    "desktop-user",
    "recover-1",
  )
  let receipt : Json = {
    "kind": "company_command",
    "command_family": "company_charter",
    "request": request,
    "result": {
      "schema": "moonproj.company-charter.v1",
      "charter_id": "current",
      "revision": 1,
    },
  }
  assert_eq(company_command_recovery_receipt(Some(receipt), request), receipt)
  try company_command_recovery_receipt(None, request) catch {
    error => assert_eq(service_error_response(error).0, 503)
  } noraise {
    _ => assert_true(false)
  }
  let other_request = company_charter_upsert_request(
    { "mission": { "title": "Different Lab" } },
    "desktop-user",
    "recover-1",
  )
  try company_command_recovery_receipt(Some(receipt), other_request) catch {
    error => assert_eq(service_error_response(error).0, 409)
  } noraise {
    _ => assert_true(false)
  }
}
