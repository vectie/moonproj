///|
test "public comparison exact native minor delta never rounds across JS boundary" {
  assert_eq(
    @plan_workbench.comparison_delta(
      Json::string("9007199254740992"),
      Json::string("9007199254740993"),
      "CNY",
      "CNY",
    ),
    "+1 CNY minor units",
  )
  assert_eq(
    @plan_workbench.comparison_delta(
      Json::string("0"),
      Json::string("9223372036854775807"),
      "CNY",
      "CNY",
    ),
    "+9223372036854775807 CNY minor units",
  )
  assert_true(
    @plan_workbench.comparison_delta(
      Json::null(),
      Json::string("0"),
      "CNY",
      "CNY",
    ).has_prefix("Unavailable"),
  )
  assert_true(
    @plan_workbench.comparison_delta(
      Json::string("1"),
      Json::string("2"),
      "CNY",
      "USD",
    ).contains("no FX"),
  )
}
