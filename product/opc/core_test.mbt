///|
test "basic OPC excludes autonomous staffing and agent marketplace" {
  let profile = basic_opc()
  assert_true(!profile.includes("autonomous-staffing"))
  assert_true(!profile.includes("agent-marketplace"))
}
