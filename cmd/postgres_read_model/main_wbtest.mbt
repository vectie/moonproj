///|
test "read-model hex and identifier guards" {
  assert_eq(decode_hex("6d6f6f6e"), "moon")
  assert_true(valid_identifier("legacy:raw:cb_contract"))
  assert_true(!valid_identifier("aggregate type"))
}
