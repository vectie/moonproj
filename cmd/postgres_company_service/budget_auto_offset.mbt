///|
/// Native port of the source expense auto-offset route.
///
/// Approved loans are used as a FIFO offset plan and the command-owned Draft
/// expense receives the calculated offset/pay amounts. Imported expenses are
/// never rewritten; loan balances are deliberately not changed here because
/// the source waits for the later workflow approval step.

///|
fn budget_auto_offset_envelope(
  data : Json,
  command : Json,
  replay : Bool,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "command": command,
    "idempotent_replay": Json::boolean(replay),
    "source_kind": Json::string("imported_or_command"),
    "command_projection": Json::boolean(true),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(true),
    "expense_effect": Json::boolean(true),
    "loan_offset_plan": Json::boolean(true),
    "loan_balance_effect": Json::boolean(false),
    "budget_effect": Json::boolean(false),
    "budget_consumption": Json::boolean(false),
    "workflow_synchronization": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn budget_auto_offset_command(
  expense_guid : String?,
  actor_id : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let expense_id = match expense_guid {
    Some(value) if valid_identifier(value) => value
    _ => raise reject(422, "expenseGuid is required")
  }
  let (actor_user_id, _) = budget_actor(actor_id)
  let request = Json::object({
    "command_type": Json::string("auto_offset"),
    "expense_guid": Json::string(expense_id),
    "actor_id": Json::string(actor_id),
  })
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        budget_auto_offset_envelope(
          json_field(existing, "result").unwrap_or(Json::null()),
          existing,
          true,
        ),
      )
    }
    None => ()
  }
  let current = match budget_latest_projection("budget_expense", expense_id) {
    Some((payload, revision)) => (payload, revision)
    None => {
      let imported = raw_source_rows("vcb_expense", 1000)
      if imported.any(fn(row) {
          report_text(row.payload, "expense_guid", row.record_id) == expense_id &&
          json_field(row.payload, "deleted_at") is None
        }) {
        raise reject(409, "imported expenses are read-only")
      }
      raise reject(404, "budget expense not found")
    }
  }
  let current_payload = current.0
  let current_revision = current.1
  if json_text(current_payload, "applied_by", "") != actor_user_id {
    raise reject(403, "only the expense applicant may offset this expense")
  }
  let state = json_text(current_payload, "apply_state", "Draft")
  if state != "Draft" {
    raise reject(400, "仅 Draft 可冲抵")
  }
  let expense_amount = json_number(current_payload, "expense_amount", 0.0)
  let loans = loan_read_items(None, Some("Approved")).filter(fn(item) {
    json_text(item, "applied_by", "") == actor_user_id &&
    json_number(item, "remain_amount", 0.0) > 0.0
  })
  loans.sort_by(fn(left, right) {
    json_text(left, "apply_date", "").lexical_compare(
      json_text(right, "apply_date", ""),
    )
  })
  let plan : Array[Json] = []
  let mut need = expense_amount
  for loan in loans {
    if need > 0.0 {
      let remain = json_number(loan, "remain_amount", 0.0)
      let take = round_places(if need < remain { need } else { remain }, 2)
      if take > 0.0 {
        plan.push(
          Json::object({
            "loanGuid": Json::string(json_text(loan, "loan_id", "")),
            "loanCode": Json::string(json_text(loan, "loan_code", "")),
            "amount": Json::number(take),
          }),
        )
        need = round_places(need - take, 2)
      }
    }
  }
  let total_offset = round_places(
    plan.fold(init=0.0, fn(sum, item) { sum + json_number(item, "amount", 0.0) }),
    2,
  )
  let next_revision = current_revision + 1
  let event_id = "budget-expense:auto_offset:" + idempotency_key
  let audit_id = event_id + ":audit"
  let fields = budget_copy_fields(current_payload)
  fields.set("offset_amount", Json::number(total_offset))
  fields.set(
    "pay_amount",
    Json::number(round_places(expense_amount - total_offset, 2)),
  )
  fields.set("source_kind", Json::string("command"))
  fields.set("event_id", Json::string(event_id))
  fields.set("updated_by", Json::string(actor_id))
  let next_payload = Json::object(fields)
  let result = Json::object({
    "expenseGuid": Json::string(expense_id),
    "offsetPlan": Json::array(plan),
    "totalOffset": Json::number(total_offset),
    "payAmount": Json::number(round_places(expense_amount - total_offset, 2)),
    "revision": Json::number(next_revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "expense_effect": Json::boolean(true),
    "loan_offset_plan": Json::boolean(true),
    "loan_balance_effect": Json::boolean(false),
    "budget_consumption": Json::boolean(false),
    "authorizing": Json::boolean(false),
  })
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("budget_expense"),
    "command_type": Json::string("auto_offset"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("budget_expense"),
    "aggregate_id": Json::string(expense_id),
    "actor_id": Json::string(actor_id),
    "request": request,
    "result": result,
  })
  let audit = Json::object({
    "audit_id": Json::string(audit_id),
    "action": Json::string("budget_expense.auto_offset"),
    "aggregate_type": Json::string("budget_expense"),
    "aggregate_id": Json::string(expense_id),
    "actor_id": Json::string(actor_id),
    "event_id": Json::string(event_id),
    "revision": Json::number(next_revision.to_double()),
    "expense_effect": Json::boolean(true),
    "loan_offset_plan": Json::boolean(true),
    "loan_balance_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_command'," +
    @postgres.sql_literal(event_id) +
    ",4," +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type,aggregate_id,revision,payload,source_event_id) VALUES ('budget_expense'," +
    @postgres.sql_literal(expense_id) +
    "," +
    next_revision.to_string() +
    "," +
    @postgres.sql_literal(next_payload.stringify()) +
    "::jsonb," +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('company_audit_event'," +
    @postgres.sql_literal(audit_id) +
    ",4," +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb," +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (200, budget_auto_offset_envelope(result, command, false))
}
