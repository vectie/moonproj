///|
test "absent optional guidance preserves legacy prompt and public metadata" {
  assert_eq(@task_evidence.guidance_prompt(Json::null()), "")
  assert_eq(@task_evidence.guidance_summary(Json::null()), Json::null())
  try @task_evidence.validate_guidance_selection({}, {}) catch {
    _ => ()
  } noraise {
    _ => fail("empty unsigned advice cannot be selected")
  }
}
