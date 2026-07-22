///|
test "basic OPC navigation is industry-neutral and complete" {
  let items = nav_items()
  assert_eq(items.length(), 10)
  assert_eq(page_path(Overview), "/")
  assert_eq(page_path(Evidence), "/evidence")
  for item in items {
    assert_true(!item.label.contains("地产"))
    assert_true(!item.label.contains("项目全周期"))
  }
}

///|
test "decision-first navigation covers command execute delivery assurance and governance" {
  let items = nav_items()
  assert_true(
    items.any(fn(item) { item.group == "指挥" && item.page == Overview }),
  )
  assert_true(
    items.any(fn(item) { item.group == "执行" && item.page == Fleet }),
  )
  assert_true(
    items.any(fn(item) { item.group == "交付" && item.page == Quality }),
  )
  assert_true(
    items.any(fn(item) { item.group == "保障" && item.page == Observe }),
  )
  assert_true(
    items.any(fn(item) { item.group == "治理" && item.page == Evidence }),
  )
}

///|
test "Moon product line is optional and hidden by default" {
  let model = initial_model()
  assert_true(!model.moon_mode)
  assert_eq(page_path(MoonSuite), "/moon")
  assert_eq(quality_product_name(model, 0), "Core Service")
  assert_eq(quality_product_name({ ..model, moon_mode: true }, 0), "moonproj")
}

///|
test "release dashboard starts from one unknown nine-gate ledger" {
  let model = initial_model()
  assert_eq(model.engineering_gate_states.length(), 9)
  assert_true(
    model.engineering_gate_states.all(fn(state) { state == "unknown" }),
  )
  assert_eq(model.engineering_branch, "main")
  assert_eq(model.engineering_review, "needs_evidence")
}

///|
test "release projection reads gate states from the shared audit" {
  let payload = @json.parse(
    "{\"audit\":{\"gates\":[{\"id\":\"G1\",\"status\":\"pass\"},{\"id\":\"G2\",\"status\":\"blocked\"}]}}",
  ) catch {
    _ => Json::null()
  }
  let states = projection_gate_states(payload)
  assert_eq(states.length(), 9)
  assert_eq(states[0], "pass")
  assert_eq(states[1], "blocked")
  assert_eq(states[8], "unknown")
}

///|
test "blank workspace contains no fictional company data" {
  let model = initial_model()
  assert_eq(model.company_name, "")
  assert_true(!model.company_saved)
  assert_true(!model.market_saved)
  assert_true(!model.work_saved)
  assert_true(!model.commitment_saved)
  assert_eq(setup_count(model), 0)
  assert_eq(readiness_count(model), 0)
  assert_eq(readiness_total(), 21)
}

///|
test "setup progress only advances from explicit UI records" {
  let model = {
    ..initial_model(),
    company_saved: true,
    market_saved: true,
    work_saved: true,
    commitment_saved: true,
    ledger_ready: true,
    continuity_ready: true,
  }
  assert_eq(setup_count(model), 6)
}

///|
test "all charter system registers contribute to readiness" {
  let model = {
    ..initial_model(),
    company_saved: true,
    market_saved: true,
    work_saved: true,
    commitment_saved: true,
    constitution_ready: true,
    authority_ready: true,
    resource_register_ready: true,
    offer_register_ready: true,
    workflow_ready: true,
    attention_ready: true,
    procurement_ready: true,
    expense_register_ready: true,
    budget_ready: true,
    ledger_ready: true,
    treasury_ready: true,
    tax_ready: true,
    financing_ready: true,
    investment_ready: true,
    control_ready: true,
    learning_ready: true,
    continuity_ready: true,
  }
  assert_eq(readiness_count(model), readiness_total())
  assert_eq(company_readiness_count(model), 3)
}

///|
test "commitment lifecycle keeps business stages distinct" {
  assert_eq(commitment_state(0), "草案")
  assert_eq(commitment_state(1), "已批准")
  assert_eq(commitment_state(2), "已签署")
  assert_eq(commitment_state(3), "已履约")
  assert_eq(commitment_state(4), "已结算")
  assert_eq(commitment_state(5), "已记录入账")
}

///|
test "delivery transitions require their preceding state" {
  let blank = initial_model()
  assert_true(!can_start_work(blank))
  assert_true(!can_submit_work(blank))
  assert_true(!can_accept_work(blank))
  assert_true(
    can_start_work({ ..blank, work_saved: true, workflow_ready: true }),
  )
  assert_true(can_submit_work({ ..blank, work_stage: 1 }))
  assert_true(can_accept_work({ ..blank, work_stage: 2 }))
}

///|
test "commitment effects require authority delivery treasury and ledger" {
  let blank = initial_model()
  assert_true(!can_approve_commitment(blank))
  assert_true(
    can_approve_commitment({
      ..blank,
      commitment_saved: true,
      authority_ready: true,
    }),
  )
  assert_true(
    can_sign_commitment({ ..blank, commitment_stage: 1, company_saved: true }),
  )
  assert_true(
    can_complete_commitment({ ..blank, commitment_stage: 2, work_stage: 3 }),
  )
  assert_true(
    can_settle_commitment({ ..blank, commitment_stage: 3, treasury_ready: true }),
  )
  assert_true(
    can_recognize_commitment({
      ..blank,
      commitment_stage: 4,
      ledger_ready: true,
    }),
  )
}
