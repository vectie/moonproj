///|
#warnings("-alert_unstable")
test "execution cockpit renders activity, attention, and ledger boundary" {
  let projection = sample_projection()
  assert_eq(projection.total, 5)
  assert_eq(projection.inbox.open_items().length(), 3)
  let page = @rabbita.simple_cell(model=(), update=(_ : Unit, model) => model, view=(
    _emit,
    _model,
  ) => view())
  let rendered = @rabbita.render_to_string(page)
  assert_true(rendered.contains("Attention Inbox"))
  assert_true(rendered.contains("不替代公司账"))
  assert_true(rendered.contains(@agent_port.protocol_version()))
}
