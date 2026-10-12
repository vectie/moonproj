///|
test "money entry stays exact and refuses rounding or negative values" {
  assert_eq(@plan_workbench.minor("200.25", "cost"), 20025L)
  assert_eq(
    @plan_workbench.minor("999999999999999.99", "cost"),
    99999999999999999L,
  )
  for value in ["-1", "1.001", "1e3", "NaN", "", ".5"] {
    try @plan_workbench.minor(value, "cost") catch {
      _ => ()
    } noraise {
      _ => fail("amount should reject")
    }
  }
}
