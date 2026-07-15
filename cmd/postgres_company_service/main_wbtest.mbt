///|
test "native company service validates bounded identifiers" {
  assert_true(valid_identifier("admin"))
  assert_true(valid_identifier("user-1:profile"))
  assert_false(valid_identifier(""))
  assert_false(valid_identifier("user/1"))
}

///|
test "native company service parses safe integer options" {
  assert_eq(
    parse_int_option(
      ["service", "--schema-version", "4"],
      "--schema-version",
      1,
    ),
    4,
  )
  assert_eq(
    parse_int_option(
      ["service", "--schema-version", "bad"],
      "--schema-version",
      1,
    ),
    1,
  )
  assert_eq(parse_int_option(["service"], "--schema-version", 4), 4)
}

///|
test "native company service compares idempotency JSON semantically" {
  let left = @json.parse("{\"amount_minor\":123,\"summary\":\"travel\"}") catch {
    _ => Json::null()
  }
  let right = @json.parse("{\"summary\":\"travel\",\"amount_minor\":123}") catch {
    _ => Json::null()
  }
  assert_true(json_equal(left, right))
  assert_false(
    json_equal(
      left,
      @json.parse("{\"summary\":\"other\",\"amount_minor\":123}") catch {
        _ => Json::null()
      },
    ),
  )
}

///|
test "native company service maps expense command paths" {
  assert_true(
    expense_command_spec(@http.Post, "/api/company/expenses")
    is Some(("create", None)),
  )
  assert_true(
    expense_command_spec(
      @http.Post,
      "/api/company/expenses/EXP-1/submit-for-approval",
    )
    is Some(("submit", Some("EXP-1"))),
  )
  assert_true(
    expense_command_spec(@http.Delete, "/api/company/expenses/EXP-1")
    is Some(("void", Some("EXP-1"))),
  )
  assert_true(
    expense_command_spec(@http.Post, "/api/company/expenses/EXP-1/unknown")
    is None,
  )
}
