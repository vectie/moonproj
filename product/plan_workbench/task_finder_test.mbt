///|
test "task finder combines literal text and exact assignments without mutating the draft" {
  let d = update_table_draft()
  assert_eq(
    @plan_workbench.find_tasks(d, "  rEvIeW  ", "", "").map(t => t.id),
    ["T2"],
  )
  assert_eq(@plan_workbench.find_tasks(d, "t", "alex", "release"), d.tasks)
  assert_eq(@plan_workbench.find_tasks(d, "T2", "sam", "release"), [])
  assert_eq(@plan_workbench.find_tasks(d, "T2", "alex", "later"), [])
  assert_eq(@plan_workbench.find_tasks(d, "T2", "alex", "release"), [d.tasks[1]])
  assert_eq(@plan_workbench.find_tasks(d, ".*", "", ""), [])
  assert_eq(d, update_table_draft())
}

///|
test "task finder preserves Unicode exact IDs and distinguishes duplicate assignment labels" {
  let d = update_table_draft()
  let d = {
    ..d,
    owners: [d.owners[0], { ..d.owners[1], name: d.owners[0].name, }],
    milestones: [
      d.milestones[0],
      { ..d.milestones[1], name: d.milestones[0].name, },
    ],
    tasks: [
      d.tasks[0],
      {
        ..d.tasks[1],
        name: "界面 <script>, \"验收\"\nNext line",
        owner: "sam",
        milestone: "later",
      },
      d.tasks[2],
    ],
  }
  assert_eq(@plan_workbench.find_tasks(d, "界面", "sam", "later"), [
    d.tasks[1],
  ])
  assert_eq(@plan_workbench.find_tasks(d, "界面", "alex", "later"), [])
  assert_eq(
    @plan_workbench.find_tasks(d, "\"验收\"", "", "")[0].name,
    d.tasks[1].name,
  )
  assert_eq(@plan_workbench.find_tasks(d, "T2", "Alex", ""), [])
}

///|
test "task finder selection CSV updates the full draft without dropping external prerequisites" {
  let d = update_table_draft()
  let tasks = @plan_workbench.find_tasks(d, "Review", "alex", "release")
  let csv = @plan_workbench.export_task_table({ ..d, tasks, })
  assert_true(csv.contains("\"T2\",\"Review\""))
  assert_false(csv.contains("\"T1\",\"Design\""))
  assert_eq(tasks[0].dependencies, ["T1"])
  assert_eq(@plan_workbench.preview_task_table_updates(d, csv, false).changes, [])
  let edited = @plan_workbench.preview_task_table_updates(
      d,
      csv.replace_all(old="\"Review\"", new="\"Review revised\""),
      false,
    ).draft
  assert_eq(edited.tasks.map(t => t.id), d.tasks.map(t => t.id))
  assert_eq(edited.tasks[0], d.tasks[0])
  assert_eq(edited.tasks[2], d.tasks[2])
  assert_eq(edited.tasks[1].dependencies, ["T1"])
  assert_eq(edited.tasks[1].name, "Review revised")
}

///|
test "task finder handles no rows unresolved assignments and full 100-task capacity" {
  let d = update_table_draft()
  assert_eq(@plan_workbench.find_tasks({ ..d, tasks: [], }, "", "", ""), [])
  let tasks = Array::makei(100, i => {
    ..d.tasks[0],
    id: "task-" + i.to_string(),
    name: "Match",
    owner: if i % 2 == 0 {
      "missing-owner"
    } else {
      "alex"
    },
    milestone: "missing-milestone",
  })
  let large = { ..d, tasks, }
  assert_eq(@plan_workbench.find_tasks(large, "", "", ""), tasks)
  let found = @plan_workbench.find_tasks(
    large, "MATCH", "missing-owner", "missing-milestone",
  )
  assert_eq(found.length(), 50)
  assert_eq(found[0].id, "task-0")
  assert_eq(found[49].id, "task-98")
  assert_eq(@plan_workbench.find_tasks(large, "", "unknown", ""), [])
  assert_eq(large.tasks, tasks)
}
