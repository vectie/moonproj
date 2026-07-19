///|
test "basic OPC stays industry-neutral until the extension is activated" {
  let core = @opc.basic_opc()
  assert_true(core.includes("company.identity"))
  assert_true(core.includes("finance.accounting"))
  assert_true(core.includes("continuity.trustee"))
  assert_true(!core.includes("real_estate.cbs"))
  assert_true(!core.includes("real_estate.mortgage"))
  assert_eq(core.active_extensions.length(), 0)
}

///|
test "real-estate ERP composes onto the OPC profile without replacing core" {
  let core = @opc.basic_opc()
  let pack = real_estate_erp()
  assert_eq(pack.mount_path, "/extensions/real-estate")
  let configured = core.activate(pack)
  assert_true(configured.includes("company.identity"))
  assert_true(configured.includes("finance.tax"))
  assert_true(configured.includes("real_estate.cbs"))
  assert_true(configured.includes("real_estate.engineering"))
  assert_true(configured.has_extension("real-estate-erp"))
  assert_eq(
    configured.capabilities.length(),
    core.capabilities.length() + pack.capabilities.length(),
  )
}

///|
test "an extension cannot be activated twice" {
  let configured = @opc.basic_opc().activate(real_estate_erp())
  try configured.activate(real_estate_erp()) catch {
    ExtensionAlreadyActive(id) => assert_eq(id, "real-estate-erp")
    _ => fail("unexpected catalog error")
  } noraise {
    _ => fail("duplicate extension activation must fail")
  }
}
