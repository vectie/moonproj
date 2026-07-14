///|
test "route inventory capability fallback is explicit" {
  assert_eq(capability_id("unknown.js"), "RPT-01")
  assert_eq(capability_id("admin.js"), "FND-08")
}
