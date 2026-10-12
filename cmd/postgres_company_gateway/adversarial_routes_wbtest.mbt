///|
test "gateway command allowlist fuzz rejects ambiguous policy and product paths" {
  let invalid_ids = [
    "",
    ".",
    "..",
    "../secret",
    "a/b",
    "%2e%2e",
    "%2F",
    "a?admin=1",
    "a#fragment",
    "a b",
    "a+b",
    "产品",
    "x".repeat(129),
  ]
  for id in invalid_ids {
    assert_false(
      command_path_allowed(
        @http.Put,
        "/api/company/products/" + id + "/in-gate",
      ),
    )
    assert_false(
      command_path_allowed(
        @http.Post,
        "/api/company/policy/sources/" + id + "/reviews",
      ),
    )
    assert_false(
      command_path_allowed(
        @http.Post,
        "/api/company/policy/changes/" + id + "/reviews",
      ),
    )
  }
  let max_id = "x".repeat(128)
  assert_true(
    command_path_allowed(
      @http.Put,
      "/api/company/products/" + max_id + "/in-gate",
    ),
  )
  assert_true(
    command_path_allowed(
      @http.Post,
      "/api/company/policy/sources/" + max_id + "/reviews",
    ),
  )
}

///|
test "gateway allowlist does not grant adjacent methods or suffix smuggling" {
  let product = "/api/company/products/moonproj/in-gate"
  assert_true(command_path_allowed(@http.Put, product))
  for request_method in [@http.Get, @http.Post, @http.Patch, @http.Delete] {
    assert_false(command_path_allowed(request_method, product))
  }
  for suffix in ["/", "/extra", "/in-gate", "?method=PUT", "#fragment"] {
    assert_false(command_path_allowed(@http.Put, product + suffix))
  }
  let source = "/api/company/policy/sources/beijing-plan/reviews"
  let change = "/api/company/policy/changes/compute-node-wording/reviews"
  assert_true(command_path_allowed(@http.Post, source))
  assert_true(command_path_allowed(@http.Post, change))
  for request_method in [@http.Get, @http.Put, @http.Patch, @http.Delete] {
    assert_false(command_path_allowed(request_method, source))
    assert_false(command_path_allowed(request_method, change))
  }
  for suffix in ["/", "/extra", "/reviews", "?method=POST", "#fragment"] {
    assert_false(command_path_allowed(@http.Post, source + suffix))
    assert_false(command_path_allowed(@http.Post, change + suffix))
  }
}

///|
test "identifier property permits only bounded non-alias ASCII tokens" {
  for
    valid in [
      "a",
      "A1",
      "owner-1",
      "user_1",
      "version.1",
      "tenant:actor",
      "x".repeat(128),
    ] {
    assert_true(valid_identifier(valid))
  }
  for
    invalid in [
      "",
      ".",
      "..",
      "x".repeat(129),
      "a/b",
      "a\\b",
      "a b",
      "a%2Fb",
      "a\u0000b",
      "用户",
    ] {
    assert_false(valid_identifier(invalid))
  }
}
