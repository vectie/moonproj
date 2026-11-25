///|
fn adversarial_policy_payload() -> Json {
  Json::object({
    "schema": Json::string("moonproj.policy-radar-projection.v1"),
    "freshness": Json::string("stale"),
    "capture_state": Json::string("manual_refresh"),
    "sources": Json::array([
      Json::object({
        "source_id": Json::string("source-1"),
        "name": Json::string("Official plan"),
        "publisher": Json::string("Official publisher"),
        "format": Json::string("PDF"),
        "cadence": Json::string("daily"),
        "url": Json::string("https://example.gov.cn/plan.pdf"),
        "verification_state": Json::string("verified"),
        "reviewed_by": Json::string("owner-1"),
        "reviewed_at": Json::string("2026-08-10"),
        "audit_id": Json::string("audit-source-1"),
        "active": Json::boolean(false),
      }),
    ]),
    "changes": Json::array([
      Json::object({
        "change_id": Json::string("change-1"),
        "source_id": Json::string("source-1"),
        "impact": Json::string("wording"),
        "title": Json::string("Compute node wording"),
        "evidence": Json::string("candidate wording"),
        "location": Json::string("page 58"),
        "review_state": Json::string("confirmed"),
        "reviewed_by": Json::string("owner-1"),
        "reviewed_at": Json::string("2026-08-10"),
        "audit_id": Json::string("audit-change-1"),
        "notification_state": Json::string("draft"),
      }),
    ]),
    "opportunities": Json::array([
      Json::object({
        "opportunity_id": Json::string("opportunity-1"),
        "lane": Json::string("B2G"),
        "title": Json::string("Read-only validation"),
        "why_now": Json::string("candidate wording changed"),
        "next_validation": Json::string("confirm owner and boundary"),
        "gate": Json::string("procurement unknown"),
        "source_change_id": Json::string("change-1"),
      }),
    ]),
    "review_receipts": Json::array([
      Json::object({
        "audit_id": Json::string("audit-change-1"),
        "target_id": Json::string("change-1"),
        "decision": Json::string("confirmed"),
        "reviewed_by": Json::string("owner-1"),
        "reviewed_at": Json::string("2026-08-10"),
      }),
    ]),
    "boundary": Json::string("no legal or procurement effect"),
  })
}

///|
fn adversarial_policy_root_with(key : String, value : Json) -> Json {
  let payload = adversarial_policy_payload()
  match payload {
    Object(fields) => fields[key] = value
    _ => ()
  }
  payload
}

///|
fn adversarial_policy_item_with(
  collection : String,
  key : String,
  value : Json,
) -> Json {
  let payload = adversarial_policy_payload()
  match payload {
    Object(root) =>
      match root.get(collection) {
        Some(Array(values)) =>
          match values.get(0) {
            Some(Object(fields)) => fields[key] = value
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  payload
}

///|
fn adversarial_product_projection(
  product : String,
  decision : String,
  persisted : Bool,
) -> Json {
  Json::object({
    "product_in_gate": Json::object({
      "schema": Json::string("moonproj.product-in-gate-projection.v2"),
      "product": Json::string(product),
      "decision": Json::string(decision),
      "primary_value": Json::string(
        if persisted {
          "solution"
        } else {
          "unknown"
        },
      ),
      "segment": Json::string(if persisted { "owner segment" } else { "" }),
      "workflow": Json::string(if persisted { "weekly workflow" } else { "" }),
      "decided_at": Json::string(if persisted { "2026-08-10" } else { "" }),
      "problem_evidence": Json::array(
        if persisted {
          [Json::string("problem-1")]
        } else {
          []
        },
      ),
      "commitment_evidence": Json::array([]),
      "current_behavior_cost": Json::string(
        if persisted {
          "two days"
        } else {
          ""
        },
      ),
      "outcome_metric": Json::string(if persisted { "two hours" } else { "" }),
      "adoption_path": Json::string(if persisted { "owner-led" } else { "" }),
      "unresolved_risks": Json::string(if persisted { "retention" } else { "" }),
      "next_experiment": Json::string(if persisted { "pilot" } else { "" }),
      "review_by": Json::string(if persisted { "2026-09-01" } else { "" }),
      "owner": Json::string(if persisted { "owner-1" } else { "" }),
      "revision": Json::number(if persisted { 1 } else { 0 }),
      "event_id": Json::string(if persisted { "event-1" } else { "" }),
      "updated_at_ms": Json::number(if persisted { 1 } else { 0 }),
      "persisted": Json::boolean(persisted),
      "exit_gate_effect": Json::boolean(false),
    }),
  })
}

///|
fn adversarial_product_field_with(key : String, value : Json) -> Json {
  let payload = adversarial_product_projection("moonproj", "experiment", true)
  match product_in_gate_root(payload) {
    Object(fields) => fields[key] = value
    _ => ()
  }
  payload
}

///|
test "policy decoder rejects malformed nested contracts and broken graph links" {
  assert_true(
    policy_projection_from_json(adversarial_policy_payload()) is Some(_),
  )
  for key in ["sources", "changes", "opportunities", "review_receipts"] {
    assert_true(
      policy_projection_from_json(
        adversarial_policy_root_with(key, Json::string("not-an-array")),
      )
      is None,
    )
  }
  assert_true(
    policy_projection_from_json(
      adversarial_policy_item_with("sources", "name", Json::number(1)),
    )
    is None,
  )
  assert_true(
    policy_projection_from_json(
      adversarial_policy_item_with(
        "sources",
        "verification_state",
        Json::string("VERIFIED"),
      ),
    )
    is None,
  )
  assert_true(
    policy_projection_from_json(
      adversarial_policy_item_with(
        "changes",
        "source_id",
        Json::string("missing-source"),
      ),
    )
    is None,
  )
  assert_true(
    policy_projection_from_json(
      adversarial_policy_item_with(
        "opportunities",
        "source_change_id",
        Json::string("missing-change"),
      ),
    )
    is None,
  )
  let duplicate_source = adversarial_policy_payload()
  match duplicate_source {
    Object(root) =>
      match root.get("sources") {
        Some(Array(values)) => values.push(values[0])
        _ => ()
      }
    _ => ()
  }
  assert_true(policy_projection_from_json(duplicate_source) is None)
  let duplicate_receipt = adversarial_policy_payload()
  match duplicate_receipt {
    Object(root) =>
      match root.get("review_receipts") {
        Some(Array(values)) => values.push(values[0])
        _ => ()
      }
    _ => ()
  }
  assert_true(policy_projection_from_json(duplicate_receipt) is None)
}

///|
test "policy opportunity action requires both source and interpretation review" {
  let confirmed = policy_projection_from_json(adversarial_policy_payload()).unwrap()
  let opportunity = policy_opportunity_by_id(Some(confirmed), "opportunity-1").unwrap()
  assert_true(policy_opportunity_actionable(Some(confirmed), opportunity))
  let unverified_payload = adversarial_policy_item_with(
    "sources",
    "verification_state",
    Json::string("pending"),
  )
  let unverified = policy_projection_from_json(unverified_payload).unwrap()
  assert_false(policy_opportunity_actionable(Some(unverified), opportunity))
}

///|
test "product decoder rejects cross-product and control-flag spoofing" {
  let valid = adversarial_product_projection("moonproj", "experiment", true)
  let unknown = adversarial_product_projection("moonproj", "unknown", false)
  assert_true(product_in_gate_response_valid(valid, "moonproj"))
  assert_true(product_in_gate_response_valid(unknown, "moonproj"))
  assert_false(product_in_gate_response_valid(valid, "moonclaw"))
  assert_false(
    product_in_gate_response_valid(
      adversarial_product_field_with("schema", Json::string("v999")),
      "moonproj",
    ),
  )
  assert_false(
    product_in_gate_response_valid(
      adversarial_product_field_with("exit_gate_effect", Json::boolean(true)),
      "moonproj",
    ),
  )
  assert_false(
    product_in_gate_response_valid(
      adversarial_product_field_with("decision", Json::string("unknown")),
      "moonproj",
    ),
  )
  assert_false(
    product_in_gate_response_valid(
      adversarial_product_field_with(
        "problem_evidence",
        Json::array([Json::number(1)]),
      ),
      "moonproj",
    ),
  )
  assert_false(
    product_in_gate_response_valid(
      adversarial_product_field_with("owner", Json::string("")),
      "moonproj",
    ),
  )
}

///|
#warnings("-alert_unstable")
test "hostile policy and product text is escaped by rendered UI" {
  let hostile = "<script>alert(1)</script>"
  let policy_payload = adversarial_policy_item_with(
    "changes",
    "title",
    Json::string(hostile),
  )
  let projection = policy_projection_from_json(policy_payload).unwrap()
  let policy_page = @rabbita.simple_cell(
    model={
      ..initial_model(),
      page: PolicyRadar,
      policy_radar_state: "ready",
      policy_radar_projection: Some(projection),
    },
    update=(_ : Msg, model) => model,
    view=(emit, model) => policy_radar_view(msg => emit(msg), model),
  )
  let policy_html = opc_render_cell(policy_page)
  assert_false(policy_html.contains(hostile))
  assert_true(policy_html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
  let product_page = @rabbita.simple_cell(
    model={
      ..initial_model(),
      page: MoonSuite,
      moon_mode: true,
      product_in_gate_decision: "experiment",
      product_in_gate_segment: hostile,
    },
    update=(_ : Msg, model) => model,
    view=(emit, model) => moon_suite_view(msg => emit(msg), model),
  )
  let product_html = opc_render_cell(product_page)
  assert_false(product_html.contains(hostile))
  assert_true(product_html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
}
