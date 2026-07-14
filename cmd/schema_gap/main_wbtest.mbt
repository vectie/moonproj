///|
test "schema gap capability defaults remain explicit" {
  assert_eq(capability_family("sale_customer"), "SAL")
  assert_eq(capability_id("sale_customer"), "SAL-01")
  assert_eq(capability_id("sys_password_history"), "FND-02")
  assert_eq(
    migration_action("sys_password_history", false),
    "security_review_exclude_credentials",
  )
  assert_eq(migration_action("cb_contract", true), "reconcile_fixture")
}
