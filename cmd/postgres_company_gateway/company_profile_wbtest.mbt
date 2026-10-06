///|
test "gateway company bootstrap allows only exact POST through existing session boundary" {
  assert_true(command_path_allowed(@http.Post, "/api/company/profile"))
  for method in [@http.Put, @http.Delete, @http.Patch] {
    assert_false(command_path_allowed(method, "/api/company/profile"))
  }
  assert_false(
    command_path_allowed(@http.Post, "/api/company/profile/anything"),
  )
  assert_true(
    command_path_allowed(@http.Post, "/api/company/source/mdm/projects"),
  )
}
