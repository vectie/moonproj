///|
test "owner brief preserves context and distinguishes cross-owner handoffs" {
  let base = table_draft()
  let d = {
    ..base,
    owners: [..base.owners, { id: "sam", name: "Sam", role: "Reviewer", }],
    tasks: [
      {
        id: "input",
        name: "Input",
        owner: "sam",
        milestone: "release",
        cost: "0",
        dependencies: [],
      },
      {
        id: "build",
        name: "Build 界面",
        owner: "alex",
        milestone: "release",
        cost: "001.20",
        dependencies: ["input", "missing"],
      },
      {
        id: "review",
        name: "Review",
        owner: "sam",
        milestone: "release",
        cost: "2",
        dependencies: ["build"],
      },
    ],
    risks: [
      {
        id: "risk",
        summary: "Input late",
        severity: "medium",
        owner: "sam",
        mitigation: "Ask\nThen revise",
        tasks: ["build"],
      },
      {
        id: "private",
        summary: "Unrelated risk",
        severity: "low",
        owner: "sam",
        mitigation: "Elsewhere",
        tasks: [],
      },
    ],
  }
  let before = d.to_json().stringify()
  let brief = @plan_workbench.owner_brief(d, "alex", "Launch")
  assert_true(brief.contains("分配给此负责人的任务（1）"))
  assert_true(brief.contains("计划成本（原文）：001.20 USD"))
  assert_true(
    brief.contains(
      "Input [input] · Sam [sam] → Build 界面 [build] · Alex [alex]",
    ),
  )
  assert_true(
    brief.contains(
      "Build 界面 [build] · Alex [alex] → Review [review] · Sam [sam]",
    ),
  )
  assert_true(brief.contains("未找到任务 [missing]"))
  assert_true(brief.contains("验收条件：\nWorks"))
  assert_true(brief.contains("所需证据：\nTests"))
  assert_true(brief.contains("任务上下文：Input late"))
  assert_true(brief.contains("Ask\nThen revise"))
  assert_false(brief.contains("Unrelated risk"))
  assert_eq(d.to_json().stringify(), before)
  assert_eq(@plan_workbench.owner_brief(d, "alex", "Launch"), brief)
}

///|
test "owner brief supports empty assignments and incomplete authored rows" {
  let d = table_draft()
  assert_true(
    @plan_workbench.owner_brief(d, "alex", "P").contains(
      "无已分配任务。",
    ),
  )
  assert_true((try? @plan_workbench.owner_brief(d, "unknown", "P")) is Err(_))
  assert_true(
    (try? @plan_workbench.owner_brief(
      { ..d, owners: [..d.owners, ..d.owners], },
      "alex",
      "P",
    ))
    is Err(_),
  )
  let broken = {
    ..d,
    tasks: [
      {
        id: "t",
        name: "<script>\n中文",
        owner: "alex",
        milestone: "absent",
        cost: "draft cost",
        dependencies: [],
      },
    ],
  }
  let report = @plan_workbench.owner_brief(broken, "alex", "P")
  assert_true(report.contains("未找到里程碑 [absent]"))
  assert_true(report.contains("draft cost"))
  assert_true(report.contains("<script>\n中文"))
}
