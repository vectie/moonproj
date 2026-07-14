///|
test "schema cohort mapping dispositions are bounded" {
  assert_true("typed_import" != "evidence_only")
  assert_true("exclude_sensitive" != "typed_import")
}
