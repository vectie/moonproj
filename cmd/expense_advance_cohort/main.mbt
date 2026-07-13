///|
pub(all) suberror ExpenseAdvanceCohortError {
  InvalidInput
  Io(@fs.IOError)
  Money(@finance.MoneyError)
  Advance(@employee_finance.AdvanceError)
  Expense(@expense.ExpenseError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ExpenseAdvanceCohortError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ExpenseAdvanceCohortError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ExpenseAdvanceCohortError {
  match value {
    Object(value) => value
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ExpenseAdvanceCohortError {
  match obj.get(key) {
    Some(value) => value
    None => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ExpenseAdvanceCohortError {
  match required(obj, key) {
    String(value) => value
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise ExpenseAdvanceCohortError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ExpenseAdvanceCohortError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ExpenseAdvanceCohortError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ExpenseAdvanceCohortError::InvalidInput
  }
}

///|
fn number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn money(
  minor : Int64,
  currency : String,
) -> @finance.Money raise ExpenseAdvanceCohortError {
  @finance.Money::new(minor~, currency~) catch {
    error => raise ExpenseAdvanceCohortError::Money(error)
  }
}

///|
fn grant(
  principal_id : String,
  capability : String,
  employee_id : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "expense-advance-cohort-migration/" + capability,
    principal_id,
    actor_id: "migration",
    capability,
    scope: "employee:" + employee_id,
    max_amount_minor: amount_minor,
    active: true,
  }
}

///|
fn advance_state_name(value : @employee_finance.AdvanceState) -> String {
  match value {
    @employee_finance.AdvanceState::Open => "open"
    @employee_finance.AdvanceState::PartiallyRepaid => "partially_repaid"
    @employee_finance.AdvanceState::Repaid => "repaid"
    @employee_finance.AdvanceState::WrittenOff => "written_off"
  }
}

///|
fn expense_state_name(value : @expense.ExpenseState) -> String {
  match value {
    @expense.ExpenseState::Draft => "draft"
    @expense.ExpenseState::Submitted => "submitted"
    @expense.ExpenseState::Approved => "approved"
    @expense.ExpenseState::Rejected => "rejected"
    @expense.ExpenseState::Paid => "paid"
  }
}

///|
fn item(
  source_table : String,
  source_id : String,
  target_type : String,
  target_id : String,
  source_snapshot_id : String,
  mapping_version : String,
  run_id : String,
  candidate : Map[String, Json],
) -> Json {
  let enriched = candidate.copy()
  enriched.set("source_snapshot_id", Json::string(source_snapshot_id))
  enriched.set("mapping_version", Json::string(mapping_version))
  enriched.set("run_id", Json::string(run_id))
  Json::object({
    "source_table": Json::string(source_table),
    "source_id": Json::string(source_id),
    "target_type": Json::string(target_type),
    "target_id": Json::string(target_id),
    "target_candidate": Json::object(enriched),
  })
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ExpenseAdvanceCohortError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.erp.expense-advance-cohort-plan.v1" ||
    !required_bool(root, "reviewed") {
    raise ExpenseAdvanceCohortError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let run_id = required_string(root, "run_id")

  let advance_map = object(required(root, "advance"))
  let advance_id = required_string(advance_map, "advance_id")
  let principal_id = required_string(advance_map, "principal_id")
  let employee_id = required_string(advance_map, "employee_id")
  let advance_minor = required_int64(advance_map, "amount_minor")
  let offset_minor = required_int64(advance_map, "offset_minor")
  let currency = required_string(advance_map, "currency")
  let advance_amount = money(advance_minor, currency)
  let advance = @employee_finance.EmployeeAdvance::new(
    advance_id~,
    principal_id~,
    employee_id~,
    amount=advance_amount,
    actor_id="migration",
    grant=grant(principal_id, "advance:create", employee_id, advance_minor),
  ) catch {
    error => raise ExpenseAdvanceCohortError::Advance(error)
  }

  let expense_map = object(required(root, "expense"))
  let expense_id = required_string(expense_map, "expense_id")
  let expense_minor = required_int64(expense_map, "amount_minor")
  let expense_amount = money(expense_minor, currency)
  let allocations : Array[@expense.ExpenseAllocation] = []
  let allocation_candidates : Array[Json] = []
  for value in required_array(expense_map, "allocations") {
    let allocation = object(value)
    let allocation_minor = required_int64(allocation, "amount_minor")
    let allocation_currency = required_string(allocation, "currency")
    let allocation_amount = money(allocation_minor, allocation_currency)
    allocations.push({
      project_scope: required_string(allocation, "project_scope"),
      cost_subject: required_string(allocation, "cost_subject"),
      amount: allocation_amount,
    })
    allocation_candidates.push(
      Json::object({
        "project_scope": Json::string(
          required_string(allocation, "project_scope"),
        ),
        "cost_subject": Json::string(
          required_string(allocation, "cost_subject"),
        ),
        "amount_minor": number(allocation_minor),
        "currency": Json::string(allocation_currency),
      }),
    )
  }
  let expense = @expense.ExpenseClaim::new(
    expense_id~,
    principal_id~,
    employee_id~,
    amount=expense_amount,
    allocations~,
    actor_id="migration",
    grant=grant(principal_id, "expense:create", employee_id, expense_minor),
  ) catch {
    error => raise ExpenseAdvanceCohortError::Expense(error)
  }
  let expense = expense.transition(
    @expense.ExpenseState::Submitted,
    actor_id="migration",
    grant=grant(principal_id, "expense:submit", employee_id, expense_minor),
  ) catch {
    error => raise ExpenseAdvanceCohortError::Expense(error)
  }
  let expense = expense.transition(
    @expense.ExpenseState::Approved,
    actor_id="migration",
    grant=grant(principal_id, "expense:approve", employee_id, expense_minor),
  ) catch {
    error => raise ExpenseAdvanceCohortError::Expense(error)
  }

  let offset_map = object(required(root, "offset"))
  let offset_id = required_string(offset_map, "offset_id")
  let (expense, advance) = expense.offset_advance(
    advance,
    amount_minor=offset_minor,
    actor_id="migration",
    expense_grant=grant(
      principal_id, "expense:offset", employee_id, offset_minor,
    ),
    advance_grant=grant(
      principal_id, "advance:offset", employee_id, offset_minor,
    ),
  ) catch {
    error => raise ExpenseAdvanceCohortError::Expense(error)
  }

  let accepted : Array[Json] = []
  let advance_source_table = required_string(advance_map, "source_table")
  let advance_source_id = required_string(advance_map, "source_id")
  accepted.push(
    item(
      advance_source_table,
      advance_source_id,
      "employee_advance",
      advance.advance_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "advance_id": Json::string(advance.advance_id),
        "principal_id": Json::string(advance.principal_id),
        "employee_id": Json::string(advance.employee_id),
        "amount_minor": number(advance.amount.minor),
        "repaid_minor": number(advance.repaid_minor),
        "outstanding_minor": number(advance.outstanding_minor()),
        "currency": Json::string(advance.amount.currency),
        "state": Json::string(advance_state_name(advance.state)),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  let expense_source_table = required_string(expense_map, "source_table")
  let expense_source_id = required_string(expense_map, "source_id")
  accepted.push(
    item(
      expense_source_table,
      expense_source_id,
      "expense_claim",
      expense.expense_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "expense_id": Json::string(expense.expense_id),
        "principal_id": Json::string(expense.principal_id),
        "employee_id": Json::string(expense.employee_id),
        "amount_minor": number(expense.amount.minor),
        "offset_minor": number(expense.offset_minor),
        "currency": Json::string(expense.amount.currency),
        "state": Json::string(expense_state_name(expense.state)),
        "allocations": Json::array(allocation_candidates),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )
  let offset_source_table = required_string(offset_map, "source_table")
  let offset_source_id = required_string(offset_map, "source_id")
  accepted.push(
    item(
      offset_source_table,
      offset_source_id,
      "employee_advance_offset",
      offset_id,
      source_snapshot_id,
      mapping_version,
      run_id,
      {
        "offset_id": Json::string(offset_id),
        "advance_id": Json::string(advance.advance_id),
        "expense_id": Json::string(expense.expense_id),
        "principal_id": Json::string(advance.principal_id),
        "employee_id": Json::string(advance.employee_id),
        "scope": Json::string("employee:" + advance.employee_id),
        "amount_minor": number(offset_minor),
        "currency": Json::string(currency),
        "resulting_repaid_minor": number(advance.repaid_minor),
        "resulting_advance_state": Json::string(
          advance_state_name(advance.state),
        ),
        "applied": Json::boolean(true),
        "cash_released": Json::boolean(false),
        "accounting_posted": Json::boolean(false),
        "period_closed": Json::boolean(false),
      },
    ),
  )

  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "run_id": Json::string(run_id),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("expense-advance-cohort-v1"),
    "accepted_items": Json::array(accepted),
    "cash_released": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "period_closed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise ExpenseAdvanceCohortError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: expense_advance_cohort <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ExpenseAdvanceCohortError::InvalidInput => {
        println("expense/advance cohort failed: invalid or unreviewed input")
        @sys.exit(1)
      }
      ExpenseAdvanceCohortError::Io(_) => {
        println("expense/advance cohort failed: filesystem error")
        @sys.exit(1)
      }
      ExpenseAdvanceCohortError::Money(_) => {
        println("expense/advance cohort failed: money validation")
        @sys.exit(1)
      }
      ExpenseAdvanceCohortError::Advance(_) => {
        println("expense/advance cohort failed: advance validation")
        @sys.exit(1)
      }
      ExpenseAdvanceCohortError::Expense(_) => {
        println("expense/advance cohort failed: expense validation")
        @sys.exit(1)
      }
    }
  }
}
