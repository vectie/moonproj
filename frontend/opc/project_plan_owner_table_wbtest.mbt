///|
fn owner_roster_fixture() -> Model {
  let model = plan_test_model()
  let d = model.plan.draft.unwrap()
  {
    ..model,
    plan: {
      ..model.plan,
      draft: Some({
        ..d,
        owners: [
          ..d.owners,
          { id: "retained", name: "Unchanged", role: "Support", },
        ],
      }),
      prepared: Some({ "fixture": "previous prepared result" }),
      phase: "prepared",
      owner_table: {
        ..plan_owner_table_initial(),
        text: "id,name,role,Status\nnew-owner,\"New, \"\"界面\"\"\",\"Review\nBackup\",Active\nowner-test,Owner <script>,Lead,Admin",
      },
    },
  }
}

///|
test "owner roster UI previews persists restores and exports exact roster" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = owner_roster_fixture()
  assert_true(
    plan_store(
      "owner-test",
      "company-actual",
      original.plan.draft.unwrap().to_json().stringify(),
    ),
  )
  let stored = plan_restore("owner-test", "company-actual")
  let (_, previewed) = plan_update(_ => none, OwnerTable(Preview), original)
  assert_eq(previewed.plan.draft, original.plan.draft)
  assert_eq(previewed.plan.prepared, original.plan.prepared)
  assert_eq(previewed.plan.revision, original.plan.revision)
  assert_eq(previewed.plan.phase, original.plan.phase)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  let html = products_test_html(previewed)
  assert_true(html.contains("Owner roster table"))
  assert_true(html.contains("Owner roster preview"))
  assert_true(html.contains("New / 新增: 1; Updated / 修改: 1"))
  assert_true(html.contains("Owner &lt;script&gt;"))
  assert_true(html.contains("Ignored columns: Status"))
  assert_true(html.contains("for=\"plan-owner-table\""))
  let (_, edited) = plan_update(_ => none, OwnerTable(Apply), previewed)
  let d = edited.plan.draft.unwrap()
  assert_eq(d.owners.map(o => o.id), ["owner-test", "retained", "new-owner"])
  assert_eq(d.owners[0].name, "Owner <script>")
  assert_eq(d.owners[1], original.plan.draft.unwrap().owners[1])
  assert_eq(d.owners[2].role, "Review\nBackup")
  assert_eq(d.tasks, original.plan.draft.unwrap().tasks)
  assert_eq(d.milestones, original.plan.draft.unwrap().milestones)
  assert_eq(edited.plan.prepared, None)
  assert_eq(edited.plan.revision, original.plan.revision + 1)
  assert_eq(edited.plan.owner_table.preview, None)
  assert_eq(edited.plan.owner_table.text, original.plan.owner_table.text)
  assert_true(d.key != original.plan.draft.unwrap().key)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, d)
  let (_, repeated) = plan_update(_ => none, OwnerTable(Apply), edited)
  assert_eq(repeated.plan, edited.plan)
  let (export, exported) = plan_update(_ => none, OwnerTable(Export), edited)
  drafts_test_execute(export)
  assert_eq(exported.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one roster download")
  }
  assert_eq(products_text(download, "name"), "plan-owners.csv")
  assert_eq(products_text(download, "type"), "text/plain;charset=utf-8")
  let csv = products_text(download, "text")
  assert_eq(csv, @plan_workbench.export_owner_table(d))
  assert_eq(@plan_workbench.preview_owner_table(d, csv, false).changes, [])
  assert_eq(plan_test_requests(), "[]")
  ignore(
    plan_test_file(
      "owner-roster-before.json",
      original.plan.draft.unwrap().to_json().stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file("owner-roster-input.csv", original.plan.owner_table.text),
  )
  ignore(plan_test_file("owner-roster-preview.html", html))
  ignore(
    plan_test_file("owner-roster-after.json", d.to_json().stringify(indent=2)),
  )
  ignore(plan_test_file("owner-roster-output.csv", csv))
  let (_, switched) = plan_update(_ => none, Choose("company-second"), edited)
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), switched)
  assert_eq(reloaded.plan.draft, Some(d))
  assert_eq(reloaded.plan.owner_table, plan_owner_table_initial())
  let (prepare, saving) = plan_update(_ => none, Prepare, reloaded)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare")
  }
  assert_eq(@json.parse(products_text(request, "body")), d.to_json())
  ignore(
    plan_test_file(
      "owner-roster-prepare-request.json",
      products_text(request, "body"),
    ),
  )
}

///|
test "owner roster close draft changes and scope reset discard stale previews" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, previewed) = plan_update(
    _ => none,
    OwnerTable(Preview),
    owner_roster_fixture(),
  )
  for
    action in [
      OwnerTable(Close),
      OwnerTable(Text("id,role\nowner-test,")),
      OwnerTable(Format(true)),
      Edit("owner", "owner-test", "name", "New name"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, previewed)
    assert_eq(changed.plan.owner_table.preview, None)
    let (_, after) = plan_update(_ => none, OwnerTable(Apply), changed)
    assert_eq(after.plan, changed.plan)
  }
  let (_, actor) = plan_update(_ => none, OwnerTable(Apply), {
    ..previewed,
    dispatch_task_actor_id: "other",
  })
  assert_eq(actor.plan.draft, None)
  assert_eq(actor.plan.owner_table, plan_owner_table_initial())
  let stale = {
    ..previewed,
    plan: {
      ..previewed.plan,
      draft: Some({ ..previewed.plan.draft.unwrap(), notes: "changed", }),
    },
  }
  let (_, refused) = plan_update(_ => none, OwnerTable(Apply), stale)
  assert_eq(refused.plan.draft, stale.plan.draft)
  assert_eq(refused.plan.revision, stale.plan.revision)
  assert_eq(refused.plan.owner_table.preview, None)
  let mismatched = {
    ..previewed,
    plan: { ..previewed.plan, selected: "company-second", },
  }
  let (_, ignored) = plan_update(_ => none, OwnerTable(Export), mismatched)
  assert_eq(ignored.plan, mismatched.plan)
  assert_eq(plan_test_downloads(), "[]")
  assert_eq(plan_test_requests(), "[]")
}

///|
test "owner roster failures no-ops and repeat exports retain useful draft state" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = owner_roster_fixture()
  let (_, input) = plan_update(
    _ => none,
    OwnerTable(Text("id,name\nowner-test,\"broken")),
    original,
  )
  let (_, failed) = plan_update(_ => none, OwnerTable(Preview), input)
  assert_eq(failed.plan.draft, original.plan.draft)
  assert_eq(failed.plan.prepared, original.plan.prepared)
  assert_eq(failed.plan.owner_table.text, input.plan.owner_table.text)
  assert_eq(failed.plan.owner_table.preview, None)
  assert_false(failed.plan.owner_table.note.is_empty())
  let (_, same) = plan_update(
    _ => none,
    OwnerTable(
      Text(@plan_workbench.export_owner_table(original.plan.draft.unwrap())),
    ),
    original,
  )
  let (_, previewed) = plan_update(_ => none, OwnerTable(Preview), same)
  assert_eq(previewed.plan.owner_table.preview.unwrap().changes, [])
  let (_, no_op) = plan_update(_ => none, OwnerTable(Apply), previewed)
  assert_eq(no_op.plan, previewed.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  let (first, _) = plan_update(_ => none, OwnerTable(Export), original)
  drafts_test_execute(first)
  let (_, edited) = plan_update(
    _ => none,
    Edit("owner", "owner-test", "role", "Updated duty"),
    original,
  )
  let (second, _) = plan_update(_ => none, OwnerTable(Export), edited)
  drafts_test_execute(second)
  guard @json.parse(plan_test_downloads()) is Array([before, after]) else {
    fail("two roster downloads")
  }
  assert_false(products_text(before, "text").contains("Updated duty"))
  assert_true(products_text(after, "text").contains("Updated duty"))
  assert_eq(plan_test_requests(), "[]")
}
