///|
test "GitHub issue import reaches editable template replacement and phase append" {
  let template = plan_github_read_template(
    (
      #|[{"number":7,"title":"Implement customer idea","body":"Source need\nAcceptance: usable","url":"https://github.com/team/demo/issues/7","state":"OPEN","assignees":[{"login":"sam"}],"milestone":{"title":"Launch"},"labels":[{"name":"customer"}]}]
    ),
  )
  let target : @plan_workbench.Draft = {
    key: "plan",
    project_id: "project",
    prepared_at: "2026-10-20T00:00:00Z",
    notes: "Existing scope",
    currency: "USD",
    limit: "0",
    contingency: "0",
    owners: [{ id: "lead", name: "Lead", role: "Planning", }],
    tasks: [],
    milestones: [],
    risks: [],
  }
  let replaced = @plan_workbench.apply_template(
    template, target, "lead", "planning-owner", "Lead", "github",
  )
  assert_eq(replaced.tasks.length(), 1)
  assert_eq(replaced.tasks[0].name, "Implement customer idea")
  assert_eq(replaced.tasks[0].owner, "")
  assert_true(replaced.notes.contains("https://github.com/team/demo/issues/7"))
  let appended = @plan_workbench.append_template(
    plan_source_template_for_append(template, target.currency),
    target,
    "lead",
    "planning-owner",
    "phase",
  )
  assert_eq(appended.tasks.length(), 1)
  assert_eq(appended.project_id, target.project_id)
}
