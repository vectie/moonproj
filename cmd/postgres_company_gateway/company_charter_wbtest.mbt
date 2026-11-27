///|
test "gateway allows authenticated PUT /api/company/charter and rejects unallowed methods" {
  assert_true(command_path_allowed(@http.Put, "/api/company/charter"))
  assert_false(command_path_allowed(@http.Delete, "/api/company/charter"))
  assert_false(command_path_allowed(@http.Post, "/api/company/charter"))
}

///|
test "isolated worker books stay disjoint from registered parent MoonBook root" {
  let task = continuation_test_field(
    delivery_test_task(),
    "execution_workspace",
    Json::string("/Users/example/workspace/books/opc-doctoral-research"),
  )
  let parent_book = native_delivery_workspace(task)
  let workers_base = native_delivery_workers_base(task)
  assert_eq(parent_book, "/Users/example/workspace/books/opc-doctoral-research")
  assert_eq(
    workers_base, "/Users/example/workspace/books/.moonproj-workers/PT-native",
  )
  assert_false(workers_base == parent_book)
  assert_false(workers_base.has_prefix(parent_book + "/"))
  assert_false(parent_book.has_prefix(workers_base + "/"))
}
