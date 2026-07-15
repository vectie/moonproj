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
test "native company service maps contract milestone command paths" {
  assert_true(
    milestone_command_spec(@http.Post, "/api/company/source/cost/milestones")
    is Some(("source-create", None, None)),
  )
  assert_true(
    milestone_command_spec(
      @http.Post,
      "/api/company/source/cost/contracts/CT-1/milestones",
    )
    is Some(("source-create", Some("CT-1"), None)),
  )
  assert_true(
    milestone_command_spec(
      @http.Post,
      "/api/company/source/cost/milestones/MS-1/trigger-event",
    )
    is Some(("trigger_event", None, Some("MS-1"))),
  )
  assert_true(
    milestone_command_spec(
      @http.Put,
      "/api/company/source/cost/milestones/MS-1",
    )
    is Some(("update", None, Some("MS-1"))),
  )
  assert_true(
    milestone_command_spec(
      @http.Delete,
      "/api/company/source/cost/milestones/MS-1",
    )
    is Some(("delete", None, Some("MS-1"))),
  )
}

///|
test "native company service normalizes contract milestone requests" {
  let body = @json.parse(
    "{\"contractGuid\":\"CT-1\",\"milestoneGuid\":\"MS-1\",\"nodeName\":\"Design\",\"triggerType\":\"event\",\"planPct\":25.5,\"notes\":\"review\"}",
  ) catch {
    _ => Json::null()
  }
  let items = milestone_create_items(body, "CT-1", 100000, 3, "key-1")
  assert_eq(items.length(), 1)
  assert_eq(json_text(items[0], "milestone_id", ""), "MS-1")
  assert_eq(json_int(items[0], "sequence", 0), 3)
  assert_eq(json_int(items[0], "plan_pct_bps", 0), 2550)
  assert_eq(json_int(items[0], "plan_amount_minor", 0), 25500)
  let update = milestone_update_request(
    "MS-1",
    @json.parse("{\"nodeName\":\"Updated\",\"planAmount\":12.5}") catch {
      _ => Json::null()
    },
    "actor-1",
  )
  assert_eq(json_text(update, "node_name", ""), "Updated")
  assert_eq(json_int(update, "plan_amount_minor", 0), 1250)
}

///|
test "native company service maps invoice command paths" {
  assert_true(
    invoice_command_spec(@http.Post, "/api/company/source/invoice/in")
    is Some(("in", "create", None)),
  )
  assert_true(
    invoice_command_spec(@http.Post, "/api/company/source/invoice/out")
    is Some(("out", "create", None)),
  )
  assert_true(
    invoice_command_spec(@http.Delete, "/api/company/source/invoice/out/INV-1")
    is Some(("out", "delete", Some("INV-1"))),
  )
  assert_true(
    invoice_command_spec(@http.Delete, "/api/company/source/invoice/out/INV/1")
    is None,
  )
}

///|
test "native company service normalizes invoice authority and tax" {
  let body = @json.parse(
    "{\"invoiceNo\":\"INV-1\",\"projGuid\":\"P-1\",\"totalAmount\":\"123.45\",\"taxRate\":\"0.13\",\"principal_id\":\"principal-1\",\"scope\":\"project:P-1\",\"authority\":{\"active\":true,\"principal_id\":\"principal-1\",\"actor_id\":\"actor-1\",\"scope\":\"project:P-1\",\"capability\":\"invoice:in:create\",\"max_amount_minor\":20000}}",
  ) catch {
    _ => Json::null()
  }
  let request = invoice_create_request("in", body, "actor-1", "invoice-key")
  assert_eq(json_text(request, "total_amount", ""), "123.45")
  assert_eq(json_text(request, "tax_rate", ""), "0.13")
  assert_eq(json_text(request, "tax_amount", ""), "14.20")
  assert_eq(json_text(request, "state", ""), "received")
  assert_eq(
    json_int(json_field(request, "authority").unwrap(), "max_amount_minor", 0),
    20000,
  )
}

///|
test "native company service maps sales revenue command paths" {
  assert_true(
    sales_revenue_command_spec(@http.Post, "/api/company/sales/revenues")
    is Some(("create", None)),
  )
  assert_true(
    sales_revenue_command_spec(@http.Put, "/api/company/sales/revenues/REV-1")
    is Some(("update", Some("REV-1"))),
  )
  assert_true(
    sales_revenue_command_spec(
      @http.Post,
      "/api/company/sales/revenues/REV-1/confirm-received",
    )
    is Some(("confirm_received", Some("REV-1"))),
  )
  assert_true(
    sales_revenue_command_spec(
      @http.Delete,
      "/api/company/sales/revenues/REV-1",
    )
    is Some(("delete", Some("REV-1"))),
  )
  assert_true(
    sales_revenue_command_spec(
      @http.Delete,
      "/api/company/sales/revenues/REV/1",
    )
    is None,
  )
}

///|
test "native company service normalizes sales revenue authority and amount" {
  let body = @json.parse(
    "{\"revenue_id\":\"REV-1\",\"revenue_code\":\"SR-1\",\"proj_guid\":\"P-1\",\"customer_name\":\"Customer\",\"amount\":\"4567.00\",\"status\":\"expected\",\"principal_id\":\"principal-1\",\"scope\":\"project:P-1\",\"authority\":{\"active\":true,\"principal_id\":\"principal-1\",\"actor_id\":\"actor-1\",\"scope\":\"project:P-1\",\"capability\":\"sales:revenue:create\",\"max_amount_minor\":500000}}",
  ) catch {
    _ => Json::null()
  }
  let request = sales_revenue_create_request(body, "actor-1")
  assert_eq(json_text(request, "revenue_guid", ""), "REV-1")
  assert_eq(json_int(request, "amount_minor", 0), 456700)
  assert_eq(json_text(request, "amount", ""), "4567.00")
  assert_eq(json_text(request, "state", ""), "expected")
  assert_eq(
    json_int(json_field(request, "authority").unwrap(), "max_amount_minor", 0),
    500000,
  )
  let update = sales_revenue_update_request(
    "REV-1",
    @json.parse(
      "{\"customer_name\":\"Updated\",\"principal_id\":\"principal-1\",\"scope\":\"project:P-1\",\"authority\":{\"active\":true,\"principal_id\":\"principal-1\",\"actor_id\":\"actor-1\",\"scope\":\"project:P-1\",\"capability\":\"sales:revenue:update\",\"max_amount_minor\":0}}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
  )
  assert_eq(
    json_text(json_field(update, "changes").unwrap(), "customer_name", ""),
    "Updated",
  )
}

///|
test "native company service maps supplier command paths" {
  assert_true(
    supplier_command_spec(@http.Post, "/api/company/suppliers")
    is Some(("create", None)),
  )
  assert_true(
    supplier_command_spec(@http.Post, "/api/company/source/srm/providers")
    is Some(("source-create", None)),
  )
  assert_true(
    supplier_command_spec(
      @http.Post,
      "/api/company/suppliers/SUP-1/submit_review",
    )
    is Some(("submit_review", Some("SUP-1"))),
  )
  assert_true(
    supplier_command_spec(
      @http.Patch,
      "/api/company/source/srm/providers/SUP-1",
    )
    is Some(("source-update", Some("SUP-1"))),
  )
  assert_true(
    supplier_command_spec(
      @http.Delete,
      "/api/company/source/srm/providers/SUP-1",
    )
    is Some(("source-void", Some("SUP-1"))),
  )
}

///|
test "native company service normalizes supplier source fields" {
  let body = @json.parse(
    "{\"providerGuid\":\"SUP-1\",\"providerCode\":\"G-1\",\"providerName\":\"Supplier\",\"mainCategoryCode\":\"CAT-1\",\"shortName\":\"S\",\"enabled\":true}",
  ) catch {
    _ => Json::null()
  }
  let request = supplier_source_create_request(body, "actor-1", "key-1")
  assert_eq(json_text(request, "supplier_id", ""), "SUP-1")
  assert_eq(json_text(request, "supplier_code", ""), "G-1")
  assert_eq(json_text(request, "category_code", ""), "CAT-1")
  assert_eq(json_text(request, "short_name", ""), "S")
  assert_true(json_bool(request, "enabled", false))
  let update = supplier_source_update_request(
    "SUP-1",
    @json.parse("{\"providerName\":\"Updated\",\"evalResult\":\"qualified\"}") catch {
      _ => Json::null()
    },
    "actor-1",
  )
  assert_eq(
    json_text(json_field(update, "changes").unwrap(), "name", ""),
    "Updated",
  )
  assert_eq(
    json_text(json_field(update, "changes").unwrap(), "evaluation", ""),
    "qualified",
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
