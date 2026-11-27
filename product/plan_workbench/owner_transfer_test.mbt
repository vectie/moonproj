///|
test "owner transfer preserves every other field and source" {
  let base = table_draft()
  let source = {
    ..base,
    owners: [
      { id: "old", name: "Previous", role: "Delivery", },
      { id: "new", name: "Next", role: "Delivery", },
    ],
    tasks: [
      {
        id: "t",
        name: "Work",
        owner: "old",
        milestone: "m",
        cost: "12.50",
        dependencies: [],
      },
      {
        id: "other",
        name: "Other",
        owner: "unresolved",
        milestone: "m",
        cost: "",
        dependencies: ["t"],
      },
    ],
    milestones: [{ ..base.milestones[0], owner: "old", }],
    risks: [
      {
        id: "r",
        summary: "Delay",
        severity: "high",
        owner: "old",
        mitigation: "Review",
        tasks: ["t"],
      },
    ],
  }
  let bytes = ToJson::to_json(source).stringify()
  let result = @plan_workbench.transfer_owner(source, "old", "new")
  assert_eq(result, {
    ..source,
    tasks: [{ ..source.tasks[0], owner: "new", }, source.tasks[1]],
    milestones: [{ ..source.milestones[0], owner: "new", }],
    risks: [{ ..source.risks[0], owner: "new", }],
  })
  assert_eq(ToJson::to_json(source).stringify(), bytes)
  assert_eq(@plan_workbench.transfer_owner(result, "old", "new"), result)
  assert_eq(@plan_workbench.transfer_owner(result, "new", "old"), source)
}

///|
test "owner transfer rejects missing ambiguous empty and identical endpoints" {
  let d = table_draft()
  let source = {
    ..d,
    owners: [
      { id: "a", name: "A", role: "", },
      { id: "b", name: "B", role: "", },
    ],
  }
  for
    (from, dest) in [
      ("a", "a"),
      ("a", ""),
      ("", "b"),
      ("a", "missing"),
      ("missing", "b"),
    ] {
    assert_true(
      (Ok(@plan_workbench.transfer_owner(source, from, dest)) catch {
        e => Err(e)
      })
      is Err(_),
    )
  }
  for id in ["a", "b"] {
    let dup = {
      ..source,
      owners: [..source.owners, { id, name: "Duplicate", role: "", }],
    }
    assert_true(
      (Ok(@plan_workbench.transfer_owner(dup, "a", "b")) catch { e => Err(e) })
      is Err(_),
    )
  }
}
