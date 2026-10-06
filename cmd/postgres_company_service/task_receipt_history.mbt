///|
/// Exact task-scoped read of the existing command/audit store. No new ledger,
/// command family, receipt or company effect is created by this projection.
fn plan_task_receipt_history_sql(task_id : String) -> String {
  "SELECT encode(convert_to(jsonb_build_object('command', command.payload, " +
  "'event_id', command.record_id, 'audit', audit.payload, 'audit_id', audit.record_id, " +
  "'recorded_at', command.created_at)::text, 'UTF8'), 'hex') " +
  "FROM company_record command LEFT JOIN company_record audit ON " +
  "audit.record_type='company_audit_event' AND audit.record_id=command.record_id || ':audit' " +
  "WHERE command.record_type='company_command' AND " +
  "((command.payload->>'command_family'='plan_task' AND command.payload->>'aggregate_id'=" +
  @postgres.sql_literal(task_id) +
  ") OR (command.payload->>'command_family'='delivery' AND command.payload->>'family'='task_report' " +
  "AND command.payload->'request'->>'task_id'=" +
  @postgres.sql_literal(task_id) +
  ")) ORDER BY command.created_at, command.record_id"
}

///|
async fn plan_task_receipt_history(
  task_id : String,
) -> Json raise CompanyServiceError {
  let output = run_sql(plan_task_receipt_history_sql(task_id))
  let rows : Array[Json] = []
  for line in output.split("\n") {
    if !line.is_empty() {
      rows.push(
        @json.parse(decode_hex(line.to_owned())) catch {
          _ => raise fail("invalid task command history JSON")
        },
      )
    }
  }
  @task_evidence.receipt_history(task_id, rows)
}
