///|
test "accounting-link CSV quoting is deterministic" {
  assert_true(csv_cell("plain") == "plain")
  assert_true(csv_cell("a,b") == "\"a,b\"")
  assert_true(csv_cell("a\"b") == "\"a\"\"b\"")
}
