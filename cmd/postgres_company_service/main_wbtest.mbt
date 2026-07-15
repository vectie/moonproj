///|
test "native company service validates bounded identifiers" {
  assert_true(valid_identifier("admin"))
  assert_true(valid_identifier("user-1:profile"))
  assert_false(valid_identifier(""))
  assert_false(valid_identifier("user/1"))
}

///|
test "native company service parses safe integer options" {
  assert_eq(
    parse_int_option(
      ["service", "--schema-version", "4"],
      "--schema-version",
      1,
    ),
    4,
  )
  assert_eq(
    parse_int_option(
      ["service", "--schema-version", "bad"],
      "--schema-version",
      1,
    ),
    1,
  )
  assert_eq(parse_int_option(["service"], "--schema-version", 4), 4)
}
