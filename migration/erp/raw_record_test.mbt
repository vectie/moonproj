///|
test "unmapped ERP rows remain durable raw evidence" {
  let record = raw_record(
    {
      table_name: "wf_step_def",
      record_id: "step-001",
      payload: "{\"step_guid\":\"step-001\",\"step_order\":1}",
    },
    schema_version=1,
  )
  assert_eq(record.record_type, "legacy/raw/wf_step_def")
  assert_eq(record.source_id, "erp:wf_step_def:step-001")
  assert_true(record.payload.contains("step_guid"))
}

///|
test "raw ERP rows reject missing table or record identity" {
  try
    raw_record(
      { table_name: "", record_id: "step-001", payload: "{}" },
      schema_version=1,
    )
  catch {
    ErpImportError::MissingIdentifier => ()
    _ => fail("wrong raw row error")
  } noraise {
    _ => fail("expected raw row identity error")
  }
}

///|
test "raw ERP rows stage as a unique opaque batch" {
  let records = raw_records(
    [
      {
        table_name: "wf_step_def",
        record_id: "step-001",
        payload: "{\"step_guid\":\"step-001\"}",
      },
      {
        table_name: "wf_step_def",
        record_id: "step-002",
        payload: "{\"step_guid\":\"step-002\"}",
      },
    ],
    schema_version=1,
  )
  assert_eq(records.length(), 2)
  assert_eq(records[1].source_id, "erp:wf_step_def:step-002")
}

///|
test "raw ERP batch rejects duplicate source identity" {
  try
    raw_records(
      [
        { table_name: "wf_step_def", record_id: "step-001", payload: "{}" },
        { table_name: "wf_step_def", record_id: "step-001", payload: "{}" },
      ],
      schema_version=1,
    )
  catch {
    ErpImportError::DuplicateRecord => ()
    _ => fail("wrong raw batch error")
  } noraise {
    _ => fail("expected duplicate raw batch error")
  }
}
