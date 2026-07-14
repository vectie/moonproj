///|
test "schema cohort wave ordering is stable" {
  assert_eq(wave_order[0], "foundation-security")
  assert_eq(wave_order[6], "reporting-notification")
  assert_eq(
    special_actions.get_or_default("sys_password_history", ""),
    "security_review_exclude_credentials",
  )
}
