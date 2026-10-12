///|
test "Markdown checklist preserves heading and nested context with exact source and assignments" {
  let d = update_table_draft()
  let source = "\u{FEFF}# 客户 <brief>\r\nContext and [source](https://example.test/brief)\r\n## Deliverables\r\n- Package\r\n  - [ ] Research **buyers**\r\n    + [ ] Review [link](file.md)\r\n  * [X] Prior attempt\r\n    2) [ ] 修正 😀\r\n## Next\r\n1. [ ] Research **buyers**\r\n"
  let result = @plan_workbench.preview_markdown_checklist(
    d, source, "sam", "later", "import-a", false,
  )
  assert_eq(result.entries.map(e => e.line), [5, 6, 8, 10])
  assert_eq(result.skipped_checked, 1)
  assert_eq(result.entries[0].context, [
    "客户 <brief>", "Deliverables", "Package",
  ])
  assert_eq(result.entries[1].context, [
    "客户 <brief>", "Deliverables", "Package", "Research **buyers**",
  ])
  assert_eq(
    result.entries[2].task.name,
    "客户 <brief> / Deliverables / Package / Prior attempt / 修正 😀",
  )
  assert_eq(result.entries[3].context, ["客户 <brief>", "Next"])
  assert_eq(result.entries[1].text, "Review [link](file.md)")
  assert_eq(result.entries.map(e => e.task.id), [
    "import-a-line-5", "import-a-line-6", "import-a-line-8", "import-a-line-10",
  ])
  for entry in result.entries {
    assert_eq(entry.task.owner, "sam")
    assert_eq(entry.task.milestone, "later")
    assert_eq(entry.task.cost, "0")
    assert_eq(entry.task.dependencies, [])
    assert_false(entry.checked)
  }
  assert_true(result.draft.notes.has_suffix(source))
  assert_true(
    result.draft.notes.contains("Line 5 → import-a-line-5 (source unchecked)"),
  )
  assert_eq({ ..result.draft, tasks: d.tasks, notes: d.notes, }, d)
  assert_eq(result.draft.tasks[:3].to_array(), d.tasks)
  assert_eq(d, update_table_draft())
  assert_eq(
    @plan_workbench.budget_breakdown(result.draft).known_minor,
    @plan_workbench.budget_breakdown(d).known_minor,
  )
  assert_eq(
    @plan_workbench.preview_task_table_updates(
      result.draft,
      @plan_workbench.export_task_table(result.draft),
      false,
    ).draft,
    result.draft,
  )
}

///|
test "Markdown checklist skips code comments quotes and prose while keeping raw input" {
  let source = "# Work\n````md\n- [ ] fenced\n```\n- [ ] still fenced\n````\n~~~\n- [x] tildes\n~~~\n<!--\n- [ ] comment\n-->\n> - [ ] quoted\ntext - [ ] inline\n- ordinary context\n\t- [ ] real item\n    continuation is source only\n- [x] old item\n- [ ] real item"
  let result = @plan_workbench.preview_markdown_checklist(
    table_draft(),
    source,
    "alex",
    "release",
    "sample",
    false,
  )
  assert_eq(result.entries.map(e => e.line), [16, 19])
  assert_eq(result.entries.map(e => e.task.name), [
    "Work / ordinary context / real item", "Work / real item",
  ])
  assert_eq(result.skipped_checked, 1)
  assert_true(result.draft.notes.has_suffix(source))
  let comments = @plan_workbench.preview_markdown_checklist(
    table_draft(),
    "<!--\n```\n--> <!-- again\n- [ ] hidden\n-->\n- [ ] visible",
    "alex",
    "release",
    "comments",
    false,
  )
  assert_eq(comments.entries.map(e => e.text), ["visible"])
}

///|
test "Markdown checked items are explicit planned copies without completion or dependency inference" {
  let d = table_draft()
  let source = "- [x] Done in the source\n  - [X] Nested done\n- [ ] Remaining"
  let result = @plan_workbench.preview_markdown_checklist(
    d, source, "alex", "release", "again", true,
  )
  assert_eq(result.entries.map(e => e.checked), [true, true, false])
  assert_eq(result.entries.map(e => e.task.id), [
    "again-line-1", "again-line-2", "again-line-3",
  ])
  assert_eq(result.skipped_checked, 0)
  assert_true(
    result.draft.notes.contains("source checked; imported as planned"),
  )
  let request = @plan_workbench.request(
    result.draft,
    "alex",
    {},
    "source",
    "digest",
  )
  assert_eq(@plan_workbench.items(request, "tasks").length(), 3)
  for task in @plan_workbench.items(request, "tasks") {
    assert_eq(
      @plan_workbench.field(task, "dependencies"),
      ([] : Array[String]).to_json(),
    )
    assert_true(@plan_workbench.field(task, "status") is Null)
  }
}

///|
test "Markdown checklist rejects empty invalid or ambiguous inputs without partial append" {
  let d = table_draft()
  for
    source in [
      "", "- prose only", "- [ ]", "- [ ] Good\n- [x] ", "```\n- [ ] unfinished fence",
      "<!--\n- [ ] comment", "- [x] checked only",
    ] {
    assert_true(
      (try? @plan_workbench.preview_markdown_checklist(
        d, source, "alex", "release", "new", false,
      ))
      is Err(_),
    )
    assert_eq(d, table_draft())
  }
  for
    (owner, milestone, prefix) in [
      ("missing", "release", "n"),
      ("alex", "missing", "n"),
      ("alex", "release", " "),
    ] {
    assert_true(
      (try? @plan_workbench.preview_markdown_checklist(
        d, "- [ ] Good", owner, milestone, prefix, false,
      ))
      is Err(_),
    )
  }
  let duplicate = { ..d, owners: [..d.owners, d.owners[0]], }
  assert_true(
    (try? @plan_workbench.preview_markdown_checklist(
      duplicate, "- [ ] Good", "alex", "release", "n", false,
    ))
    is Err(_),
  )
  let first = @plan_workbench.preview_markdown_checklist(
      d, "- [ ] Good", "alex", "release", "new", false,
    ).draft
  assert_true(
    (try? @plan_workbench.preview_markdown_checklist(
      first, "- [ ] Good", "alex", "release", "new", false,
    ))
    is Err(_),
  )
  let dangling = {
    ..first,
    tasks: [{ ..first.tasks[0], id: "other", dependencies: ["new-line-1"], }],
  }
  assert_true(
    (try? @plan_workbench.preview_markdown_checklist(
      dangling, "- [ ] Good", "alex", "release", "new", false,
    ))
    is Err(_),
  )
}
