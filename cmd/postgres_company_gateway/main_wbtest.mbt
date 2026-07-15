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
