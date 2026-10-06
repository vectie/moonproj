///|
test "source context reaches both existing native task prompt and captured product input" {
  let task = @task_evidence.with_source_context(native_test_task(), {
    "source_context": {
      "reference": "source:interview-7",
      "problem": "Cannot compare offers",
    },
  })
  let plain = native_execution_snapshot(task, "moongate/test", "owner")
  let request = @json.parse(native_text(plain, "request_body"))
  assert_true(native_text(request, "text").contains("source:interview-7"))
  assert_true(native_text(request, "text").contains("Cannot compare offers"))
  let context = native_context_snapshot(
    task,
    "Product",
    "Purpose",
    {},
    "PRD",
    {},
    "digest",
    "complete",
    [],
  )
  assert_true(native_text(context, "text").contains("source:interview-7"))
  let product = native_execution_snapshot(
    task,
    "moongate/test",
    "owner",
    product_context=context,
  )
  let product_request = @json.parse(native_text(product, "request_body"))
  assert_true(
    native_text(product_request, "text").contains("source:interview-7"),
  )
  assert_eq(
    native_text(product_request, "context_path"),
    native_text(context, "context_path"),
  )
}

///|
test "source-bound reserved request survives serialization unchanged and source changes are distinct inputs" {
  let task = @task_evidence.with_source_context(native_test_task(), {
    "source_context": { "reference": "source:7" },
  })
  let reserved = native_execution_snapshot(task, "moongate/test", "owner")
  let recovered = @json.parse(reserved.stringify())
  assert_eq(
    native_text(recovered, "request_body"),
    native_text(reserved, "request_body"),
  )
  let changed_task = @task_evidence.with_source_context(native_test_task(), {
    "source_context": { "reference": "source:8" },
  })
  let later = native_execution_snapshot(changed_task, "moongate/test", "owner")
  assert_false(
    native_text(later, "request_body") == native_text(reserved, "request_body"),
  )
  assert_true(native_text(recovered, "request_body").contains("source:7"))
  assert_false(native_text(recovered, "request_body").contains("source:8"))
}
