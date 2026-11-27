///|
fn diagram_draft() -> @plan_workbench.Draft {
  let task = @plan_workbench.Task::{
    id: "design",
    name: "Design",
    owner: "alex",
    milestone: "release",
    cost: "10.10",
    dependencies: [],
  }
  {
    ..table_draft(),
    tasks: [
      task,
      { ..task, id: "build", name: "Build", dependencies: ["design"], },
      {
        ..task,
        id: "docs",
        name: "Write documentation",
        dependencies: ["design"],
      },
      {
        ..task,
        id: "ship",
        name: "Ship",
        dependencies: ["build", "docs", "design"],
      },
    ],
  }
}

///|
test "standalone SVG preserves the full diamond and long prerequisite links" {
  let draft = diagram_draft()
  let before = ToJson::to_json(draft).stringify()
  let svg = @plan_workbench.export_dependency_svg(draft, "Launch", "build")
  assert_true(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  assert_eq(svg.split("class=\"planned-task\"").count(), 5)
  assert_eq(svg.split("class=\"dependency-edge\"").count(), 6)
  for
    label in [
      "Wave 1", "Wave 2", "Wave 3", "FOCUS", "PREREQUISITE OF FOCUS", "DOWNSTREAM OF FOCUS",
      "OTHER PLANNED TASK", "design -&gt; ship", "Plan version: plan", "Imported scope",
    ] {
    assert_true(svg.contains(label))
  }
  assert_true(svg.contains("marker-end=\"url(#arrow)\""))
  assert_false(svg.contains("<script"))
  assert_eq(ToJson::to_json(draft).stringify(), before)
  assert_eq(
    @plan_workbench.export_dependency_svg(draft, "Launch", "build"),
    svg,
  )
  let neutral = @plan_workbench.export_dependency_svg(draft, "Launch", "")
  assert_true(neutral.contains("Focus: none"))
  assert_false(neutral.contains("PREREQUISITE OF FOCUS"))
  assert_eq(neutral.split("class=\"planned-task\"").count(), 5)
}

///|
test "map escapes all authored markup while retaining Unicode and exact source context" {
  let original = diagram_draft()
  let task = {
    ..original.tasks[0],
    id: "<script>&\"'",
    name: "设计 🚀\n<script>alert('x')</script>",
  }
  let draft = {
    ..original,
    notes: "Source <link> & exact\r\nnext",
    tasks: [task],
  }
  let svg = @plan_workbench.export_dependency_svg(
    draft,
    "Buyer & <project>",
    task.id,
  )
  assert_true(svg.contains("Buyer &amp; &lt;project&gt;"))
  assert_true(svg.contains("&lt;script&gt;&amp;&quot;&apos;"))
  assert_true(svg.contains("设计 🚀"))
  assert_true(svg.contains("Source &lt;link&gt; &amp; exact\r\nnext"))
  assert_false(svg.contains("<script>"))
  assert_false(svg.contains("href="))
  assert_true(svg.contains("id=\"node-0\""))
  let invalid = { ..draft, notes: "bad\u{0001}", }
  assert_true(
    (Ok(@plan_workbench.export_dependency_svg(invalid, "Project", "")) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "map rejects ambiguous or broken dependency and assignment identities" {
  let draft = diagram_draft()
  let task = draft.tasks[0]
  for
    bad in [
      { ..draft, tasks: [], },
      { ..draft, tasks: [task, task], },
      { ..draft, tasks: [{ ..task, id: " ", }], },
      { ..draft, tasks: [{ ..task, dependencies: ["missing"], }], },
      { ..draft, tasks: [{ ..task, dependencies: [task.id], }], },
      {
        ..draft,
        tasks: [
          task,
          { ..task, id: "second", dependencies: [task.id, task.id], },
        ],
      },
      { ..draft, tasks: [{ ..task, owner: "missing", }], },
      { ..draft, owners: [draft.owners[0], draft.owners[0]], },
      { ..draft, tasks: [{ ..task, milestone: "missing", }], },
      { ..draft, milestones: [draft.milestones[0], draft.milestones[0]], },
    ] {
    assert_true(
      (Ok(@plan_workbench.export_dependency_svg(bad, "Project", "")) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  assert_true(
    (Ok(@plan_workbench.export_dependency_svg(draft, "Project", "removed")) catch {
      e => Err(e)
    })
    is Err(_),
  )
  assert_true(
    (Ok(@plan_workbench.export_dependency_svg(draft, " ", "")) catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "map accepts draft order independent of precedence without reordering the draft" {
  let d = diagram_draft()
  let reversed = {
    ..d,
    tasks: [d.tasks[3], d.tasks[2], d.tasks[1], d.tasks[0]],
  }
  let svg = @plan_workbench.export_dependency_svg(reversed, "Project", "ship")
  assert_true(svg.contains("Wave 3"))
  assert_eq(reversed.tasks[0].id, "ship")
  assert_eq(svg.split("class=\"dependency-edge\"").count(), 6)
  assert_true(svg.contains("Prerequisites: build, docs, design"))
}

///|
test "map supports one hundred tasks and rejects uninspectable dense graphs explicitly" {
  let draft = diagram_draft()
  let task = draft.tasks[0]
  let tasks : Array[@plan_workbench.Task] = []
  for i in 0..<100 {
    tasks.push({ ..task, id: "task-" + i.to_string(), })
  }
  let svg = @plan_workbench.export_dependency_svg(
    { ..draft, tasks, },
    "Project",
    "",
  )
  assert_eq(svg.split("class=\"planned-task\"").count(), 101)
  tasks.push({ ..task, id: "task-100", })
  assert_true(
    (Ok(
      @plan_workbench.export_dependency_svg({ ..draft, tasks, }, "Project", ""),
    ) catch {
      e => Err(e)
    })
    is Err(_),
  )
  let dense : Array[@plan_workbench.Task] = []
  for i in 0..<33 {
    dense.push({
      ..task,
      id: "dense-" + i.to_string(),
      dependencies: dense.map(t => t.id),
    })
  }
  assert_true(
    (Ok(
      @plan_workbench.export_dependency_svg(
        { ..draft, tasks: dense, },
        "Project",
        "",
      ),
    ) catch {
      e => Err(e)
    })
    is Err(@plan_workbench.Invalid(message)) &&
    message.contains("500"),
  )
}
