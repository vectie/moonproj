///|
test "R793-R797 planning import uses production task table" {
  let source =
    #|id,name,owner,milestone,cost,dependencies
    #|R793,MoonDesk staged creator handoff,cloud,feature-batch,0,
    #|R794,MoonBook CSL-JSON reference import,cloud,feature-batch,0,
    #|R795,MoonProj saved GitHub issue plan import,cloud,feature-batch,0,
    #|R796,MoonTown cross-dossier inquiry,cloud,feature-batch,0,
    #|R797,MoonFind saved Atom feed intake,cloud,feature-batch,0,
  let draft : @plan_workbench.Draft = {
    key: "R793-R797",
    project_id: "moonsuite-cloud",
    prepared_at: "2026-10-20T03:57:00Z",
    notes: "Planning-only batch import. Signed service persistence and release gates are unrun.",
    currency: "USD",
    limit: "0",
    contingency: "0",
    owners: [{ id: "cloud", name: "Cloud feature team", role: "Development", }],
    tasks: [],
    risks: [],
    milestones: [
      {
        id: "feature-batch",
        name: "Five useful feature rounds",
        owner: "cloud",
        date: "2026-10-20",
        criteria: "Focused feature tests and independent review; release gates reported honestly",
        evidence: "Per-round source and test receipts",
      },
    ],
  }
  let (imported, ignored) = @plan_workbench.import_task_table(
    draft, source, false, "cloud", "feature-batch",
  )
  assert_eq(imported.tasks.length(), 5)
  assert_eq(ignored.length(), 0)
  assert_eq(imported.tasks[0].id, "R793")
  assert_eq(imported.tasks[4].id, "R797")
  println("BATCH_IMPORTED_DRAFT=" + imported.to_json().stringify())
}
