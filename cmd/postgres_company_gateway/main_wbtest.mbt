///|
test "native gateway validates identifiers and path boundaries" {
  assert_true(valid_identifier("limingjin"))
  assert_true(valid_identifier("user-1:profile"))
  assert_false(valid_identifier(""))
  assert_false(valid_identifier("user/1"))
  assert_true(command_path_allowed(@http.Post, "/api/company/expenses"))
  assert_false(command_path_allowed(@http.Post, "/api/company/summary"))
  assert_true(
    command_path_allowed(
      @http.Delete,
      "/api/company/source/srm/providers/SUP-1",
    ),
  )
  assert_true(
    command_path_allowed(@http.Delete, "/api/company/source/invoice/out/INV-1"),
  )
  assert_true(
    command_path_allowed(@http.Delete, "/api/company/sales/revenues/REV-1"),
  )
  assert_true(
    command_path_allowed(@http.Post, "/api/company/source/tender/tenders"),
  )
  assert_true(
    command_path_allowed(@http.Post, "/api/company/source/tender/splits"),
  )
  assert_true(
    command_path_allowed(@http.Post, "/api/company/marketing/campaigns"),
  )
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/marketing/placements/PLAC-1/effect",
    ),
  )
  assert_true(
    command_path_allowed(@http.Delete, "/api/company/marketing/materials/MAT-1"),
  )
  assert_true(command_path_allowed(@http.Post, "/api/company/fund/plans"))
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/fund/dispatches/FD-1/approve",
    ),
  )
  assert_true(
    command_path_allowed(@http.Delete, "/api/company/delivery/progress/PR-1"),
  )
  assert_true(
    command_path_allowed(@http.Delete, "/api/company/plan/tasks/PT-1"),
  )
  assert_true(
    command_path_allowed(
      @http.Delete,
      "/api/company/attachments/ATT-RABBITA-LOCAL",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Delete,
      "/api/company/source/attachments/ATT-RABBITA-LOCAL",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/investment/projects/proj-0001/excel-imports",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/source/investment/projects/proj-0001/excel-imports",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/investment/excel-imports/IMPORT-RABBITA-LOCAL/index-upsert",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/source/investment/excel-imports/IMPORT-RABBITA-LOCAL/index-upsert",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/investment/excel-imports/IMPORT-RABBITA-LOCAL/plan-lines/import",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/source/investment/excel-imports/IMPORT-RABBITA-LOCAL/plan-lines/import",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/investment/projects/proj-0001/subject-mappings",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/source/investment/projects/proj-0001/subject-mappings",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/investment/plan-lines/PLAN-RABBITA-LOCAL",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/source/investment/plan-lines/PLAN-RABBITA-LOCAL",
    ),
  )
}

///|
test "native gateway session and trusted identity tokens are deterministic" {
  assert_true(constant_time_equal("abc", "abc"))
  assert_false(constant_time_equal("abc", "abd"))
  assert_true(
    session_token("session-secret", "rabbita-user", 1) !=
    session_token("session-secret", "rabbita-user", 2),
  )
  let timestamp = (@env.now() / 1000UL).to_string()
  let signature = hmac_hex("identity-secret", "limingjin:" + timestamp)
  assert_true(
    verify_trusted_identity(
      "limingjin", timestamp, signature, "identity-secret",
    ),
  )
  assert_false(
    verify_trusted_identity(
      "limingjin", timestamp, signature, "different-secret",
    ),
  )
}

///|
test "native gateway parses session cookies and query keys" {
  assert_true(
    cookie_value("other=x; moonproj_session=abc123; mode=dev", SESSION_COOKIE)
    is Some("abc123"),
  )
  assert_true(cookie_value("mode=dev", SESSION_COOKIE) is None)
  assert_true(
    query_value("/api/test?idempotency_key=abc123", "idempotency_key")
    is Some("abc123"),
  )
  assert_eq(path_only("/api/test?x=1"), "/api/test")
}

///|
test "engineering audits only resolve registered Moon Suite repositories" {
  assert_true(
    moonsuite_project_path("/workspace", "moonproj")
    is Some("/workspace/moonproj"),
  )
  assert_true(
    moonsuite_project_path("/workspace", "moonclaw")
    is Some("/workspace/moonclaw"),
  )
  assert_true(moonsuite_project_path("/workspace", "../secret") is None)
  assert_true(moonsuite_project_path("/workspace", "unknown") is None)
}

///|
test "MoonClaw task identifiers are extracted from audit responses" {
  assert_true(
    moonclaw_task_id({ "task": { "id": "task-123" } }) is Some("task-123"),
  )
  assert_true(moonclaw_task_id({ "task": {} }) is None)
  assert_true(
    moonclaw_task_status({ "task": { "status": "running" } }) is Some("running"),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/engineering/projects/moonproj/remediations",
    ),
  )
}
