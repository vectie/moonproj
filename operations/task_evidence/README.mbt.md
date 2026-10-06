# Source context and existing task receipts

This package extends the existing signed task request with optional source
context and projects existing command/audit records for task recovery. It does
not grant execution, financial or customer-acceptance authority.

Old requests preserve their canonical shape. A source reference or observed
problem becomes part of the same existing request comparison on retry.

```mbt check
///|
test "optional source context uses the existing task request" {
  let request : Json = { "task_id": "task-1", "remarks": "Cite sources" }
  assert_eq(@task_evidence.with_source_context(request, {}), request)
  let bound = @task_evidence.with_source_context(request, {
    "source_context": {
      "reference": "interview:7",
      "problem": "Compare offers",
    },
  })
  assert_true(@task_evidence.source_prompt(bound).contains("interview:7"))
}
```

History takes task-scoped `{command, audit, event_id, audit_id, recorded_at}`
rows read by the company service. It never invents a missing audit receipt or
turns internal acceptance into customer acceptance or cash.

```mbt check
///|
test "no records does not imply company progress" {
  let history = @task_evidence.receipt_history("task-1", [])
  assert_true(
    history
    is {
      "original_brief": Null,
      "receipts": Array([]),
      "customer_acceptance": String("not_recorded_here"),
      "cash": String("not_recorded_here"),
      ..
    },
  )
}
```
