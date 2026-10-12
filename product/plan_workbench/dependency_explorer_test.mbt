///|
test "parallel waves impact and stable repair of a release backlog" {
  let task = @plan_workbench.Task::{
    id: "ship",
    name: "Ship release",
    owner: "alex",
    milestone: "release",
    cost: "10",
    dependencies: ["test", "docs"],
  }
  let draft = {
    ..table_draft(),
    tasks: [
      task,
      { ..task, id: "docs", dependencies: ["design"], },
      { ..task, id: "design", dependencies: [], },
      { ..task, id: "test", dependencies: ["design"], },
    ],
  }
  let graph = @plan_workbench.dependency_plan(draft, "design")
  assert_eq(graph.waves, [["design"], ["docs", "test"], ["ship"]])
  assert_eq(graph.downstream, ["ship", "docs", "test"])
  assert_eq(@plan_workbench.dependency_plan(draft, "ship").prerequisites, [
    "docs", "design", "test",
  ])
  let ordered = @plan_workbench.order_dependencies(draft)
  assert_eq(ordered.tasks.map(t => t.id), ["design", "docs", "test", "ship"])
  assert_eq(ordered.tasks[3], task)
  assert_eq(draft.tasks[0], task)
  assert_eq(@plan_workbench.order_dependencies(ordered), ordered)
  assert_true(
    @plan_workbench.dependency_report(draft, "design").contains(
      "Downstream impact: ship, docs, test",
    ),
  )
  let request = @plan_workbench.request(
    ordered,
    "alex",
    { "project_id": "project" },
    "source",
    "digest",
  )
  assert_eq(@plan_workbench.items(request, "tasks").length(), 4)
}

///|
test "cycle and missing prerequisite keep ordering unavailable" {
  let task = @plan_workbench.Task::{
    id: "a",
    name: "A",
    owner: "alex",
    milestone: "release",
    cost: "0",
    dependencies: ["b"],
  }
  let draft = {
    ..table_draft(),
    tasks: [task, { ..task, id: "b", dependencies: ["a"], }],
  }
  assert_true(!@plan_workbench.dependency_plan(draft, "a").issues.is_empty())
  assert_true((try? @plan_workbench.order_dependencies(draft)) is Err(_))
  let missing = { ..draft, tasks: [task], }
  assert_true(
    @plan_workbench.dependency_plan(missing, "a").issues[0].contains(
      "missing prerequisite b",
    ),
  )
}
