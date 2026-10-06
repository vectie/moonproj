///|
test "offer reply existing proposal detail exposes customer reply recording" {
  let model = apply_dispatch_snapshot(
    offer_test_model(),
    dispatch_decode_snapshot(
      offer_test_body(1, offer_test_value(), [
        {
          "revision": 1,
          "audit_state": "available",
          "offer_draft": offer_test_value(),
        },
      ]),
      "offer-task",
    ).unwrap(),
  )
  assert_true(guided_task(model).contains("记录客户回复"))
}
