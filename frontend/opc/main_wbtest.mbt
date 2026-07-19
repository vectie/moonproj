///|
test "basic OPC navigation is industry-neutral and complete" {
  let items = nav_items()
  assert_eq(items.length(), 8)
  assert_eq(page_path(Overview), "/overview")
  assert_eq(page_path(Extensions), "/extensions")
  for item in items {
    assert_true(!item.label.contains("地产"))
    assert_true(!item.label.contains("项目全周期"))
  }
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
