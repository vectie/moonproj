///|
test "basic OPC excludes autonomous staffing and agent marketplace" {
  let profile = @opc.basic_opc()
  assert_true(!profile.includes("autonomous-staffing"))
  assert_true(!profile.includes("agent-marketplace"))
}
