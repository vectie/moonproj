///|
fn example_packet() -> @work_packet.Packet {
  {
    title: "  Interview 学习 🚀\nDraft <script>  ",
    acceptance: "Keep two quotes\r\n\tand a source\\path\"value\"",
    source_reference: "https://example.test/source?q=one&lang=中文\nline two",
    observed_problem: "Buyer said: \"Where is my result?\"\r\n  Preserve this.",
    begin_date: "2028-02-29",
    end_date: " date not yet decided ",
  }
}

///|
test "portable brief round trips exact Unicode multiline source and incomplete dates" {
  let packet = example_packet()
  let text = packet.encode()
  assert_eq(@work_packet.decode(text), packet)
  assert_eq(@work_packet.decode(text).encode(), text)
  let empty : @work_packet.Packet = {
    title: "",
    acceptance: "",
    source_reference: "",
    observed_problem: "",
    begin_date: "",
    end_date: "",
  }
  assert_eq(@work_packet.decode(empty.encode()), empty)
  guard @json.parse(text) is Object(fields) else { fail("object expected") }
  assert_eq(fields.length(), 7)
  assert_eq(fields["schema"], Json::string("moonproj.work-brief.v1"))
}

///|
test "portable brief rejects other formats missing fields scalar types and hidden settings" {
  for value in ["", "not JSON", "[]", "null", "{}", "{\"schema\":\"future\"}"] {
    assert_true(
      (Ok(@work_packet.decode(value)) catch { e => Err(e) }) is Err(_),
    )
  }
  let text = example_packet().encode()
  for
    key in [
      "title", "acceptance", "source_reference", "observed_problem", "begin_date",
      "end_date",
    ] {
    guard @json.parse(text) is Object(fields) else { fail("object expected") }
    fields.remove(key)
    assert_true(
      (Ok(@work_packet.decode(Json::object(fields).stringify())) catch {
        e => Err(e)
      })
      is Err(_),
    )
    fields[key] = Json::null()
    assert_true(
      (Ok(@work_packet.decode(Json::object(fields).stringify())) catch {
        e => Err(e)
      })
      is Err(_),
    )
    fields[key] = Json::number(4)
    assert_true(
      (Ok(@work_packet.decode(Json::object(fields).stringify())) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for
    key in [
      "actor_id", "authority", "task_id", "idempotency_key", "project_id", "owner_id",
      "workspace", "offer_draft", "research_brief",
    ] {
    guard @json.parse(text) is Object(fields) else { fail("object expected") }
    fields[key] = Json::string("must not import")
    assert_true(
      (Ok(@work_packet.decode(Json::object(fields).stringify())) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
}

///|
test "portable brief bounds source text without truncating a valid field" {
  let long = Array::make(8192, "中").join("")
  let packet = { ..example_packet(), source_reference: long, }
  assert_eq(@work_packet.decode(packet.encode()), packet)
  assert_true(
    (Ok({ ..packet, source_reference: long + "x", }.encode()) catch {
      e => Err(e)
    })
    is Err(_),
  )
  guard @json.parse(packet.encode()) is Object(fields) else {
    fail("object expected")
  }
  fields["source_reference"] = Json::string(long + "x")
  assert_true(
    (Ok(@work_packet.decode(Json::object(fields).stringify())) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let too_large = Array::make(90000, "中").join("")
  assert_true(
    (Ok(@work_packet.decode(too_large)) catch { e => Err(e) }) is Err(_),
  )
  assert_true(
    (Ok(@work_packet.decode(Array::make(262145, " ").join(""))) catch {
      e => Err(e)
    })
    is Err(_),
  )
}
