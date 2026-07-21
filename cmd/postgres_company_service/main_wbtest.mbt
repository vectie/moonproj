///|
test "native company service validates bounded identifiers" {
  assert_true(valid_identifier("admin"))
  assert_true(valid_identifier("user-1:profile"))
  assert_false(valid_identifier(""))
  assert_false(valid_identifier("user/1"))
}

///|
fn engineering_test_envelope() -> Json {
  @json.parse(
    "{\"schema\":\"moonsuite.engineering-audit-envelope.v1\",\"project\":\"moonproj\",\"progress\":{\"schema\":\"moonsuite.project-progress-evidence.v1\",\"project\":\"moonproj\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"observed_at\":\"2026-07-21T10:00:00Z\",\"lifecycle\":\"delivery\",\"stage\":\"G3\",\"gate_state\":\"pass\",\"completed_milestones\":[\"build\"],\"current_work\":[\"audit\"],\"blockers\":[],\"next_gate\":{\"id\":\"G4\",\"name\":\"operate\",\"criteria\":[\"runbook\"],\"evidence\":[\"docs/runbook.md\"]},\"unknowns\":[]},\"health\":{\"schema\":\"moonsuite.project-health-evidence.v1\",\"project\":\"moonproj\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"observed_at\":\"2026-07-21T10:00:00Z\",\"checks\":[{\"dimension\":\"tests\",\"status\":\"pass\",\"command\":\"moon test\",\"exit_code\":0,\"duration_ms\":12,\"evidence\":[\"receipt:test\"]}],\"delivery\":{\"status\":\"pass\",\"evidence\":[\"ci\"]},\"operations\":{\"status\":\"unknown\",\"evidence\":[]},\"trend\":{\"status\":\"unknown\",\"baseline_evidence\":[]},\"failures\":[],\"unknowns\":[\"production telemetry\"]},\"production\":{\"schema\":\"moonsuite.production-gate-evidence.v1\",\"project\":\"moonproj\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"candidate\":\"main@0123456\",\"observed_at\":\"2026-07-21T10:00:00Z\",\"redlines\":[{\"id\":\"R1\",\"status\":\"pass\",\"evidence\":[\"receipt:r1\"]}],\"gates\":[{\"id\":\"G1\",\"status\":\"pass\",\"criteria\":[\"tests\"]}],\"computed_grade\":\"G1\",\"release_eligibility\":\"needs_evidence\",\"missing_evidence\":[\"rollback drill\"],\"owner_decisions\":[]},\"review\":{\"schema\":\"moonsuite.evidence-review.v1\",\"project\":\"moonproj\",\"producer_artifact\":\"audit-envelope\",\"producer_agent\":\"producer-01\",\"reviewer_agent\":\"reviewer-02\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"observed_at\":\"2026-07-21T10:01:00Z\",\"verdict\":\"accept\",\"verified_claims\":[\"moon test passed\"],\"rejected_claims\":[],\"rerun_receipts\":[\"receipt:rerun\"],\"missing_evidence\":[\"rollback drill\"]}}",
  ) catch {
    _ => Json::null()
  }
}

///|
test "engineering evidence validates all contracts and derives accepted projection" {
  let envelope = engineering_test_envelope()
  let result = validate_engineering_envelope(envelope, "moonproj")
  assert_eq(result.0, "0123456789abcdef0123456789abcdef01234567")
  assert_eq(result.1, "accept")
  let projection = engineering_projection(
    "audit-1",
    "task-1",
    "moonproj",
    result.0,
    result.1,
    envelope,
    "",
  )
  assert_true(json_bool(projection, "trusted", false))
  assert_eq(
    engineering_health_status(json_field(envelope, "health").unwrap()),
    "pass",
  )
  assert_eq(engineering_findings(envelope).length(), 2)
}

///|
test "engineering evidence rejects contract drift and non-independent review" {
  let envelope = engineering_test_envelope()
  match envelope {
    Object(root) =>
      match root["progress"] {
        Object(progress) => progress["unexpected"] = Json::boolean(true)
        _ => ()
      }
    _ => ()
  }
  let mut rejected = false
  try {
    let _ = validate_engineering_envelope(envelope, "moonproj")
  } catch {
    CompanyServiceError::InvalidInput(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
  let envelope = engineering_test_envelope()
  match envelope {
    Object(root) =>
      match root["review"] {
        Object(review) => review["reviewer_agent"] = Json::string("producer-01")
        _ => ()
      }
    _ => ()
  }
  rejected = false
  try {
    let _ = validate_engineering_envelope(envelope, "moonproj")
  } catch {
    CompanyServiceError::InvalidInput(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "native company service maps exact import template routes" {
  assert_true(
    import_template_spec(@http.Get, "/api/company/import/project/template")
    is Some("project"),
  )
  assert_true(
    import_template_spec(
      @http.Head,
      "/api/company/source/import/contract/template",
    )
    is Some("contract"),
  )
  assert_true(
    import_template_spec(@http.Get, "/api/company/import/unsupported/template")
    is Some("unsupported"),
  )
  assert_true(
    import_template_spec(
      @http.Get,
      "/api/company/import/project/template/extra",
    )
    is None,
  )
  assert_true(
    import_template_csv("project")
    is Some(
      "\u{FEFF}projCode,projName,projShortName,buCode,projStatus,beginDate\n"
    ),
  )
  assert_true(import_template_csv("unsupported") is None)
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
test "native auth password command keeps source password policy" {
  let weak = auth_command_request(
    "change_password",
    @json.parse("{\"currentPassword\":\"oldpass\",\"newPassword\":\"newpass\"}") catch {
      _ => Json::null()
    },
    "admin",
  ) catch {
    _ => Json::null()
  }
  assert_true(weak is Null)
  let valid = auth_command_request(
    "change_password",
    @json.parse(
      "{\"currentPassword\":\"oldpass1\",\"newPassword\":\"newpass2\"}",
    ) catch {
      _ => Json::null()
    },
    "admin",
  ) catch {
    _ => Json::null()
  }
  assert_true(valid is Object(_))
  assert_true(json_bool(valid, "credential_values_redacted", false))
  let legacy_alias = auth_command_request(
    "change_password",
    @json.parse("{\"oldPassword\":\"oldpass1\",\"newPassword\":\"newpass2\"}") catch {
      _ => Json::null()
    },
    "admin",
  ) catch {
    _ => Json::null()
  }
  assert_true(legacy_alias is Object(_))
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
  assert_true(
    invoice_command_spec(
      @http.Post,
      "/api/company/source/invoice/out/INV-1/delete",
    )
    is Some(("out", "delete", Some("INV-1"))),
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
test "native company service maps sales customer command paths" {
  assert_true(
    sales_customer_command_spec(@http.Post, "/api/company/sales/customers")
    is Some(("create", None)),
  )
  assert_true(
    sales_customer_command_spec(
      @http.Post,
      "/api/company/source/sales/customers",
    )
    is Some(("create", None)),
  )
  assert_true(
    sales_customer_command_spec(
      @http.Put,
      "/api/company/source/sales/customers/CUS-1",
    )
    is Some(("update", Some("CUS-1"))),
  )
  assert_true(
    sales_customer_command_spec(
      @http.Delete,
      "/api/company/sales/customers/CUS-1",
    )
    is Some(("delete", Some("CUS-1"))),
  )
  let request = sales_customer_create_request(
    @json.parse(
      "{\"customerName\":\"Native Customer\",\"phone\":\"13800000000\",\"projGuid\":\"P-1\"}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    "customer-test-key",
  )
  assert_eq(json_text(request, "customer_name", ""), "Native Customer")
  assert_eq(
    json_text(request, "customer_guid", ""),
    "customer-customer-test-key",
  )
}

///|
test "native company service maps sales subscription command paths" {
  assert_true(
    sales_subscription_command_spec(
      @http.Post,
      "/api/company/source/sales/subscriptions",
    )
    is Some(("create", None)),
  )
  assert_true(
    sales_subscription_command_spec(
      @http.Post,
      "/api/company/sales/subscriptions/SUB-1/convert-to-contract",
    )
    is Some(("convert_to_contract", Some("SUB-1"))),
  )
  assert_true(
    sales_subscription_command_spec(
      @http.Post,
      "/api/company/sales/subscriptions/SUB-1/unknown",
    )
    is None,
  )
  let request = sales_subscription_create_request(
    @json.parse(
      "{\"customerGuid\":\"CUS-1\",\"projGuid\":\"P-1\",\"buildingNo\":\"1\",\"unitNo\":\"101\",\"totalPrice\":123.45}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    "subscription-test-key",
  )
  assert_eq(json_text(request, "customer_guid", ""), "CUS-1")
  assert_eq(json_text(request, "state", ""), "subscribed")
  assert_true(json_number(request, "total_price", 0.0) == 123.45)
}

///|
test "native company service maps sales mortgage command paths" {
  assert_true(
    sales_mortgage_command_spec(
      @http.Post,
      "/api/company/source/sales/mortgages",
    )
    is Some(("create", None)),
  )
  assert_true(
    sales_mortgage_command_spec(
      @http.Post,
      "/api/company/sales/mortgages/MTG-1/approve",
    )
    is Some(("approve", Some("MTG-1"))),
  )
  assert_true(
    sales_mortgage_command_spec(
      @http.Post,
      "/api/company/source/sales/mortgages/MTG-1/release",
    )
    is Some(("release", Some("MTG-1"))),
  )
  assert_true(
    sales_mortgage_command_spec(
      @http.Post,
      "/api/company/sales/mortgages/MTG-1/unknown",
    )
    is None,
  )
  let request = sales_mortgage_create_request(
    @json.parse(
      "{\"scontractGuid\":\"SCT-1\",\"bankName\":\"Native Bank\",\"loanAmount\":100000}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    "mortgage-test-key",
  )
  assert_eq(json_text(request, "state", ""), "applying")
  assert_true(json_number(request, "loan_amount", 0.0) == 100000.0)
}

///|
test "native company service maps sales refund command paths" {
  assert_true(
    sales_refund_command_spec(@http.Post, "/api/company/source/sales/refunds")
    is Some(("create", None)),
  )
  assert_true(
    sales_refund_command_spec(
      @http.Post,
      "/api/company/sales/refunds/RF-1/approve",
    )
    is Some(("approve", Some("RF-1"))),
  )
  assert_true(
    sales_refund_command_spec(
      @http.Post,
      "/api/company/sales/refunds/RF-1/reject",
    )
    is None,
  )
  let request = sales_refund_create_request(
    @json.parse(
      "{\"scontractGuid\":\"SCT-1\",\"reason\":\"buyer request\",\"refundAmount\":12.5}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    "refund-test-key",
  )
  assert_eq(json_text(request, "state", ""), "applying")
  assert_true(json_number(request, "refund_amount", 0.0) == 12.5)
}

///|
test "native company service maps CBS R0 resolution command paths" {
  assert_true(cbs_r0_command_spec(@http.Post, "/api/company/cbs/r0/resolve"))
  assert_true(
    cbs_r0_command_spec(@http.Post, "/api/company/source/cbs/r0/resolve"),
  )
  assert_true(!cbs_r0_command_spec(@http.Get, "/api/company/cbs/r0/resolve"))
}

///|
test "native company service maps CBS demo contract command paths" {
  assert_true(
    cbs_demo_contract_command_spec(
      @http.Post,
      "/api/company/cbs/demo/contracts",
    ),
  )
  assert_true(
    cbs_demo_contract_command_spec(
      @http.Post,
      "/api/company/source/cbs/demo/contracts",
    ),
  )
  assert_true(
    cbs_demo_contract_state_spec(
      @http.Put,
      "/api/company/cbs/demo/contracts/demo-1/state",
    )
    is Some("demo-1"),
  )
  assert_true(
    cbs_demo_legacy_command_spec(
      @http.Post,
      "/api/company/source/cbs/demo/legacy",
    ),
  )
  assert_true(
    cbs_demo_clear_command_spec(
      @http.Delete,
      "/api/company/source/cbs/demo/clear",
    ),
  )
  assert_true(
    cbs_contract_action_spec(
      @http.Post,
      "/api/company/source/cbs/contracts/demo-1/mark-paid",
    )
    is Some(("mark-paid", "demo-1")),
  )
  assert_true(cbs_change_command_spec(@http.Post, "/api/company/cbs/changes"))
  assert_true(
    cbs_change_command_spec(@http.Post, "/api/company/source/cbs/changes"),
  )
  assert_true(
    cbs_change_action_spec(
      @http.Post,
      "/api/company/source/cbs/changes/change-1/submit-approval",
    )
    is Some(("submit-approval", "change-1")),
  )
  assert_true(
    cbs_change_action_spec(
      @http.Post,
      "/api/company/cbs/changes/change-1/approve",
    )
    is Some(("approve", "change-1")),
  )
}

///|
test "native company service maps tender and split command paths" {
  assert_true(
    tender_command_spec(@http.Post, "/api/company/tenders")
    is Some(("create", None)),
  )
  assert_true(
    tender_command_spec(@http.Post, "/api/company/source/tender/tenders")
    is Some(("source-create", None)),
  )
  assert_true(
    tender_command_spec(@http.Post, "/api/company/tenders/TD-1/open_bidding")
    is Some(("open_bidding", Some("TD-1"))),
  )
  assert_true(
    tender_command_spec(@http.Delete, "/api/company/source/tender/tenders/TD-1")
    is Some(("source-delete", Some("TD-1"))),
  )
  assert_true(
    tender_command_spec(@http.Post, "/api/company/tender-splits")
    is Some(("split-create", None)),
  )
  assert_true(
    tender_command_spec(@http.Post, "/api/company/source/tender/splits")
    is Some(("source-split-create", None)),
  )
}

///|
test "native company service normalizes source tender and split fields" {
  let tender = tender_create_request(
    @json.parse(
      "{\"projGuid\":\"P-1\",\"tenderName\":\"Build\",\"estimatedAmount\":\"12345.67\",\"planPublishDate\":\"2026-07-14\"}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    true,
    "source-tender-key",
  )
  assert_eq(json_text(tender, "project_scope", ""), "project:P-1")
  assert_eq(json_int(tender, "estimated_amount_minor", 0), 1234567)
  assert_eq(json_text(tender, "state", "planning"), "planning")
  let split = split_create_request(
    @json.parse(
      "{\"parentContractGuid\":\"CT-1\",\"splitName\":\"Electrical\",\"splitAmount\":\"1234.50\",\"splitPct\":\"10.00\"}",
    ) catch {
      _ => Json::null()
    },
    "actor-1",
    true,
    "source-split-key",
  )
  assert_eq(json_int(split, "split_amount_minor", 0), 123450)
  assert_eq(json_int(split, "split_pct_bps", 0), 1000)
  assert_eq(json_text(split, "state", ""), "planned")
}

///|
test "native company service maps marketing command paths" {
  assert_true(
    marketing_command_spec(@http.Post, "/api/company/marketing/campaigns")
    is Some(("campaign", "create", None)),
  )
  assert_true(
    marketing_command_spec(@http.Put, "/api/company/marketing/campaigns/CAMP-1")
    is Some(("campaign", "update", Some("CAMP-1"))),
  )
  assert_true(
    marketing_command_spec(
      @http.Put,
      "/api/company/marketing/placements/PLAC-1/effect",
    )
    is Some(("placement", "effect", Some("PLAC-1"))),
  )
  assert_true(
    marketing_command_spec(
      @http.Delete,
      "/api/company/marketing/materials/MAT-1",
    )
    is Some(("material", "delete", Some("MAT-1"))),
  )
}

///|
test "native company service normalizes marketing amounts and authority" {
  let body = @json.parse(
    "{\"campaignGuid\":\"CAMP-1\",\"projGuid\":\"P-1\",\"name\":\"Launch\",\"budget\":\"123.45\",\"principal_id\":\"principal-1\",\"scope\":\"project:P-1\",\"authority\":{\"active\":true,\"principal_id\":\"principal-1\",\"actor_id\":\"actor-1\",\"scope\":\"project:P-1\",\"capability\":\"marketing:campaign:create\",\"max_amount_minor\":20000}}",
  ) catch {
    _ => Json::null()
  }
  let normalized = marketing_create_request(
    "campaign", body, "actor-1", "marketing-create-1",
  )
  assert_eq(normalized.0, "CAMP-1")
  assert_eq(json_int(normalized.1, "budget_minor", 0), 12345)
  assert_eq(json_text(normalized.1, "state", ""), "planning")
  assert_eq(json_text(normalized.1, "principal_id", ""), "principal-1")
  assert_eq(
    json_int(
      json_field(normalized.1, "authority").unwrap(),
      "max_amount_minor",
      0,
    ),
    20000,
  )
}

///|
test "native company service maps fund command paths" {
  assert_true(
    fund_command_spec(@http.Post, "/api/company/fund/plans")
    is Some(("plan", "create", None)),
  )
  assert_true(
    fund_command_spec(@http.Put, "/api/company/fund/plans/FP-1")
    is Some(("plan", "update", Some("FP-1"))),
  )
  assert_true(
    fund_command_spec(@http.Post, "/api/company/fund/plans/FP-1/delete")
    is Some(("plan", "delete", Some("FP-1"))),
  )
  assert_true(
    fund_command_spec(@http.Post, "/api/company/fund/dispatches/FD-1/approve")
    is Some(("dispatch", "approve", Some("FD-1"))),
  )
}

///|
test "native company service maps delivery command paths" {
  assert_true(
    delivery_command_spec(@http.Post, "/api/company/delivery/progress")
    is Some(("progress", "create", None)),
  )
  assert_true(
    delivery_command_spec(
      @http.Post,
      "/api/company/delivery/progress/PR-1/accept",
    )
    is Some(("progress", "accept", Some("PR-1"))),
  )
  assert_true(
    delivery_command_spec(@http.Delete, "/api/company/delivery/progress/PR-1")
    is Some(("progress", "delete", Some("PR-1"))),
  )
  assert_true(
    delivery_command_spec(
      @http.Post,
      "/api/company/delivery/outputs/OUT-1/confirm",
    )
    is Some(("output", "confirm", Some("OUT-1"))),
  )
  assert_true(
    delivery_command_spec(
      @http.Post,
      "/api/company/delivery/tasks/TASK-1/report",
    )
    is Some(("task_report", "report", Some("TASK-1"))),
  )
}

///|
test "native company service maps project-plan task paths" {
  assert_true(
    plan_task_command_spec(@http.Post, "/api/company/plan/tasks")
    is Some(("create", None)),
  )
  assert_true(
    plan_task_command_spec(@http.Put, "/api/company/plan/tasks/PT-1")
    is Some(("update", Some("PT-1"))),
  )
  assert_true(
    plan_task_command_spec(@http.Delete, "/api/company/plan/tasks/PT-1")
    is Some(("delete", Some("PT-1"))),
  )
  assert_true(
    plan_task_command_spec(@http.Post, "/api/company/plan/tasks/PT-1/report")
    is Some(("report", Some("PT-1"))),
  )
}

///|
test "native company service maps MDM project source paths" {
  assert_true(
    project_source_command_spec(@http.Post, "/api/company/source/mdm/projects")
    is Some(("create", None)),
  )
  assert_true(
    project_source_command_spec(
      @http.Put,
      "/api/company/source/mdm/projects/PRJ-1",
    )
    is Some(("update", Some("PRJ-1"))),
  )
  assert_true(
    project_source_command_spec(
      @http.Delete,
      "/api/company/source/mdm/projects/PRJ-1",
    )
    is Some(("delete", Some("PRJ-1"))),
  )
  let body = @json.parse(
    "{\"projGuid\":\"PRJ-1\",\"projCode\":\"P-1\",\"projName\":\"Project\",\"buGuid\":\"BU-1\"}",
  ) catch {
    _ => Json::null()
  }
  let request = project_source_create_request(body, "key-1", "actor-1")
  assert_eq(json_text(request, "project_id", ""), "PRJ-1")
  assert_eq(json_text(request, "proj_code", ""), "P-1")
  assert_eq(json_text(request, "bu_guid", ""), "BU-1")
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

///|
test "native company service maps employee-loan command paths" {
  assert_true(
    loan_command_spec(@http.Post, "/api/company/loans")
    is Some(("create", None)),
  )
  assert_true(
    loan_command_spec(
      @http.Post,
      "/api/company/loans/LOAN-1/submit-for-approval",
    )
    is Some(("submit", Some("LOAN-1"))),
  )
  assert_true(
    loan_command_spec(@http.Post, "/api/company/loans/LOAN-1/offset")
    is Some(("offset", Some("LOAN-1"))),
  )
  assert_true(
    loan_command_spec(@http.Put, "/api/company/loans/LOAN-1")
    is Some(("update", Some("LOAN-1"))),
  )
  assert_true(
    loan_command_spec(@http.Delete, "/api/company/loans/LOAN-1")
    is Some(("void", Some("LOAN-1"))),
  )
  assert_true(
    loan_command_spec(
      @http.Post,
      "/api/company/loans/LOAN-1/sync-from-workflow",
    )
    is Some(("sync_from_workflow", Some("LOAN-1"))),
  )
}
