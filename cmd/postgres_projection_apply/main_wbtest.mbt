///|
test "projection event identity is deterministic" {
  let receipt : ProjectionReceipt = {
    source_snapshot_id: "snapshot-1",
    mapping_version: "mapping-1",
    items: [
      {
        source_table: "cb_contract",
        source_id: "contract-1",
        target_type: "contract",
        target_id: "contract-1",
        target_candidate: Json::object({ "name": Json::string("demo") }),
      },
    ],
  }
  assert_true(event_id(receipt, receipt.items[0]).has_prefix("erp-promotion:"))
  assert_true(
    canonical_payload(receipt, receipt.items[0])
    .stringify()
    .contains("mapping-1"),
  )
}
