///|
fn source(bytes : Bytes) -> String {
  (
    {
      "contract_version": "moonproj.accepted-human-result.v1",
      "source_product": "moonproj",
      "provenance_scope": "captured_accepted_human_revision",
      "authenticity": "unsigned_source_observation",
      "authorizing": false,
      "content": {
        "encoding": "base64",
        "media_type": "text/plain;charset=utf-8",
        "size_bytes": bytes.length(),
        "sha256": "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
        "data": @base64.encode(bytes),
      },
    } : Json).stringify(indent=2)
}

///|
fn note(filename? : String = "result.md") -> @client_delivery.Note {
  {
    title: "客户交付",
    summary: "已完成约定简报。",
    review_request: "请审阅并回复需调整之处。",
    filename,
  }
}

///|
fn u16(bytes : Bytes, at : Int) -> Int {
  bytes[at].to_int() | (bytes[at + 1].to_int() << 8)
}

///|
fn u32(bytes : Bytes, at : Int) -> Int {
  u16(bytes, at) | (u16(bytes, at + 2) << 16)
}

///|
fn entries(bytes : Bytes) -> Map[String, Bytes] raise {
  let files : Map[String, Bytes] = Map([])
  let mut at = 0
  while u32(bytes, at) == 0x04034b50 {
    assert_eq(u16(bytes, at + 6), 2048)
    assert_eq(u16(bytes, at + 8), 0)
    let size = u32(bytes, at + 18)
    assert_eq(u32(bytes, at + 22), size)
    let name_size = u16(bytes, at + 26)
    let extra_size = u16(bytes, at + 28)
    let start = at + 30 + name_size + extra_size
    let name = @utf8.decode(bytes[at + 30:at + 30 + name_size])
    files[name] = Bytes::from_iter(bytes[start:start + size].iter())
    at = start + size
  }
  let central = at
  for _ in 0..<files.length() {
    assert_eq(u32(bytes, at), 0x02014b50)
    at += 46 + u16(bytes, at + 28) + u16(bytes, at + 30) + u16(bytes, at + 32)
  }
  assert_eq(u32(bytes, at), 0x06054b50)
  assert_eq(u16(bytes, at + 10), files.length())
  assert_eq(u32(bytes, at + 12), at - central)
  assert_eq(u32(bytes, at + 16), central)
  assert_eq(at + 22, bytes.length())
  files
}

///|
test "packet retains zero Unicode CRLF BOM and maximum text bytes with friendly README" {
  for
    bytes in [
      b"",
      @utf8.encode("你好🌙\r\nnext\n"),
      b"\xef\xbb\xbfheader\r\n",
      b"x".repeat(262144),
    ] {
    let source = source(bytes)
    assert_eq(@client_delivery.body(source), bytes)
    assert_eq(@utf8.encode(@client_delivery.body_text(source)), bytes)
    let archive = @client_delivery.archive(
      source,
      note(filename="客户简报.md"),
    )
    let files = entries(archive)
    assert_eq(files.length(), 2)
    assert_eq(files["客户简报.md"], bytes)
    assert_eq(
      files["README.txt"],
      @utf8.encode(@client_delivery.readme(note(filename="客户简报.md"))),
    )
    assert_false(files.contains("source-observation.json"))
    assert_eq(
      @client_delivery.archive(source, note(filename="客户简报.md")),
      archive,
    )
    let technical = entries(
      @client_delivery.archive(source, note(), include_source=true),
    )
    assert_eq(technical.length(), 3)
    assert_eq(technical["source-observation.json"], @utf8.encode(source))
  }
}

///|
test "packet checks actual decoded bytes not only same length declared digest" {
  let valid = source(b"first")
  let corrupt = valid.replace_all(
    old=@base64.encode(b"first"),
    new=@base64.encode(b"other"),
  )
  try @client_delivery.body(corrupt) catch {
    @client_delivery.Invalid(_) => ()
  } noraise {
    _ => fail("same-size wrong bytes must reject")
  }
  for bytes in [b"x".repeat(262145), b"\xff", b"has\x00nul", b"\xed\xa0\x80"] {
    try @client_delivery.body(source(bytes)) catch {
      @client_delivery.Invalid(_) => ()
    } noraise {
      _ => fail("invalid text must reject")
    }
  }
  try
    @client_delivery.body(
      valid.replace_all(old="text/plain;charset=utf-8", new="image/png"),
    )
  catch {
    @client_delivery.Invalid(_) => ()
  } noraise {
    _ => fail("binary declaration must reject")
  }
}

///|
test "packet filenames are editable portable basenames and never collide with notes" {
  for
    filename in [
      "report.md", "客户.csv", "results.tsv", "notes with spaces.txt", "output.mbt",
    ] {
    assert_true(@client_delivery.filename_valid(filename), msg=filename)
    assert_true(@client_delivery.validate_note(note(filename~)).is_empty())
  }
  for
    filename in [
      "",
      ".",
      "..",
      "../x.md",
      "/tmp/x.txt",
      "C:\\x.txt",
      "a/b",
      "a\\b",
      "bad\nname",
      "README.txt",
      "readme.TXT",
      "SOURCE-observation.json",
      "CON",
      "nul.txt",
      "lpt1.csv",
      "file.",
      " trailing.txt ",
      "x".repeat(129),
    ] {
    assert_false(@client_delivery.filename_valid(filename), msg=filename)
    try @client_delivery.archive(source(b"result"), note(filename~)) catch {
      @client_delivery.Invalid(_) => ()
    } noraise {
      _ => fail("invalid filename must reject")
    }
  }
  assert_eq(
    @client_delivery.default_filename("/private/workspace/customer/brief.md"),
    "brief.md",
  )
  assert_eq(
    @client_delivery.default_filename("C:\\private\\results.csv"),
    "results.csv",
  )
  assert_eq(
    @client_delivery.default_filename("/private/README.txt"),
    "delivered-result.txt",
  )
  assert_eq(@client_delivery.default_filename(""), "delivered-result.txt")
}
