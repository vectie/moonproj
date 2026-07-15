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

///|
test "native company service maps contract command paths" {
  assert_true(
    contract_command_spec(@http.Post, "/api/company/contracts")
    is Some(("create", None)),
  )
  assert_true(
    contract_command_spec(@http.Post, "/api/company/contracts/CT-1/submit")
    is Some(("submit", Some("CT-1"))),
  )
  assert_true(
    contract_command_spec(@http.Put, "/api/company/source/cost/contracts/CT-1")
    is Some(("source-update", Some("CT-1"))),
  )
  assert_true(
    contract_command_spec(
      @http.Delete,
      "/api/company/source/cost/contracts/CT-1",
    )
    is Some(("source-void", Some("CT-1"))),
  )
}

///|
test "native company service validates contract request fields" {
  let body = @json.parse(
    "{\"contract_id\":\"CT-1\",\"contract_code\":\"C-1\",\"contract_name\":\"Design\",\"project_id\":\"P-1\",\"project_name\":\"Project\",\"supplier_id\":\"SUP-1\",\"supplier_name\":\"Supplier\",\"sign_date\":\"2026-07-15\",\"amount_minor\":12345,\"currency\":\"cny\"}",
  ) catch {
    _ => Json::null()
  }
  let request = contract_create_request(body, "actor-1")
  assert_eq(json_text(request, "currency", ""), "CNY")
  assert_eq(json_int(request, "amount_minor", 0), 12345)
  assert_eq(json_text(request, "actor_id", ""), "actor-1")
}

///|
test "native company service maps payment command paths" {
  assert_true(
    payment_command_spec(@http.Post, "/api/company/payment-applies")
    is Some(("create", None)),
  )
  assert_true(
    payment_command_spec(
      @http.Post,
      "/api/company/payment-applies/PAY-1/reject",
    )
    is Some(("reject", Some("PAY-1"))),
  )
  assert_true(
    payment_command_spec(
      @http.Put,
      "/api/company/source/cost/payment-applies/PAY-1",
    )
    is Some(("source-update", Some("PAY-1"))),
  )
  assert_true(
    payment_command_spec(
      @http.Delete,
      "/api/company/source/cost/payment-applies/PAY-1",
    )
    is Some(("source-void", Some("PAY-1"))),
  )
}

///|
test "native company service maps dynamic-cost command paths" {
  assert_true(
    dynamic_cost_command_spec(@http.Post, "/api/company/cost/dynamic-cost")
    is Some(("source-create", None)),
  )
  assert_true(
    dynamic_cost_command_spec(
      @http.Put,
      "/api/company/source/cost/dynamic-cost/COST-1",
    )
    is Some(("source-update", Some("COST-1"))),
  )
  assert_true(
    dynamic_cost_command_spec(
      @http.Delete,
      "/api/company/source/cost/dynamic-cost/COST-1",
    )
    is Some(("source-void", Some("COST-1"))),
  )
  assert_true(
    dynamic_cost_command_spec(
      @http.Post,
      "/api/company/source/cost/dynamic-cost/COST-1",
    )
    is None,
  )
}

///|
test "native company service normalizes dynamic-cost source fields" {
  let body = @json.parse(
    "{\"costGuid\":\"COST-1\",\"projGuid\":\"P-1\",\"costCode\":\"C-1\",\"costName\":\"Design\",\"costLevel\":2,\"targetCost\":125.50,\"isEndCost\":true}",
  ) catch {
    _ => Json::null()
  }
  let request = source_dynamic_cost_create_request(body, "key-1")
  assert_eq(json_text(request, "cost_id", ""), "COST-1")
  assert_eq(json_text(request, "project_id", ""), "P-1")
  assert_eq(json_int(request, "target_cost_minor", 0), 12550)
  assert_true(json_bool(request, "is_end_cost", false))
  let update = source_dynamic_cost_update_request(
    @json.parse("{\"costName\":\"Updated\",\"dfsBudget\":12.25}") catch {
      _ => Json::null()
    },
  )
  assert_eq(json_text(update, "cost_name", ""), "Updated")
  assert_eq(json_int(update, "dfs_budget_minor", 0), 1225)
}
