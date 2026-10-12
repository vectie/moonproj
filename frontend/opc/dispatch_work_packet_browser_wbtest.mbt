///|
test "portable brief actual file picker handles selected bytes cancellation replaced reads and bounds" {
  research_test_picker_setup()
  defer research_test_picker_cleanup()
  defer work_packet_cancel_file()
  let received : Array[(String, String)] = []
  work_packet_pick_file((text, error) => received.push((text, error)))
  work_packet_pick_file((text, error) => received.push((text, error)))
  assert_true(research_test_picker_removed(0))
  assert_eq(received.length(), 1)
  research_test_picker_finish(0, "stale", 5, false)
  assert_eq(received.length(), 1)
  research_test_picker_finish(1, "selected 学习", 30, false)
  assert_eq(received[1], ("selected 学习", ""))
  assert_true(research_test_picker_removed(1))
  work_packet_pick_file((text, error) => received.push((text, error)))
  research_test_picker_finish(2, "too large", 262145, false)
  assert_true(received[2].1.contains("256 KiB"))
  work_packet_pick_file((text, error) => received.push((text, error)))
  research_test_picker_finish(3, "unreadable", 5, true)
  assert_true(received[3].1.contains("无法读取"))
  work_packet_pick_file((text, error) => received.push((text, error)))
  work_packet_cancel_file()
  assert_true(research_test_picker_removed(4))
  assert_true(received[4].1.contains("已取消"))
}

///|
test "portable brief file reducer previews actual selected bytes and fences closed late reads" {
  research_test_picker_setup()
  defer research_test_picker_cleanup()
  defer work_packet_cancel_file()
  let original = packet_test_model()
  let text = work_packet_from_draft(dispatch_active_draft(original).unwrap()).encode()
  let messages : Array[Msg] = []
  let (pick, choosing) = update(
    msg => {
      messages.push(msg)
      none
    },
    WorkPacketAction(Choose),
    original,
  )
  drafts_test_execute(pick)
  research_test_picker_finish(0, text, text.length(), false)
  assert_eq(messages.length(), 1)
  let (_, loaded) = update(_ => none, messages[0], choosing)
  assert_eq(loaded.work_packet.packet, Some(@work_packet.decode(text)))
  assert_eq(loaded.dispatch_drafts, original.dispatch_drafts)
  let (pick_again, choosing_again) = update(
    msg => {
      messages.push(msg)
      none
    },
    WorkPacketAction(Choose),
    loaded,
  )
  drafts_test_execute(pick_again)
  let (close, closed) = update(
    msg => {
      messages.push(msg)
      none
    },
    DraftAction(Park),
    choosing_again,
  )
  drafts_test_execute(close)
  assert_true(research_test_picker_removed(1))
  let (_, ignored) = update(_ => none, messages[1], closed)
  assert_eq(ignored.work_packet.packet, None)
  research_test_picker_finish(1, text, text.length(), false)
  assert_eq(messages.length(), 2)
  assert_eq(ignored.dispatch_drafts, original.dispatch_drafts)
}
