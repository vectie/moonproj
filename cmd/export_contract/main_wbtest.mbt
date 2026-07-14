///|
test "export contract guard recognizes identifiers and hashes" {
  assert_true(is_identifier("cb_contract"))
  assert_true(!is_identifier("../cb_contract"))
  assert_true(
    is_sha256(
      "4ff5dd0ad0b75c6cfc572f99047fe41c5df4b8c48d3877f707fe063aec7dea03",
    ),
  )
  assert_true(!is_sha256("not-a-hash"))
}

///|
test "export contract guard rejects secrets and DSNs" {
  assert_true(contains_secret_marker("password_hash"))
  assert_true(contains_secret_marker("client_ip"))
  assert_true(!contains_secret_marker("display_name"))
  assert_true(contains_dsn("postgresql://user:password@host/db"))
  assert_true(contains_dsn("mysql://user@host/db"))
  assert_true(!contains_dsn("project:proj-0001"))
}
