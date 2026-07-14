///|
test "target apply validates staging identifiers and CSV quoting" {
  assert_true(
    is_sha256(
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ),
  )
  assert_true(csv_cell("plain") == "plain")
  assert_true(csv_cell("a,b") == "\"a,b\"")
  assert_true(csv_cell("a\"b") == "\"a\"\"b\"")
}
