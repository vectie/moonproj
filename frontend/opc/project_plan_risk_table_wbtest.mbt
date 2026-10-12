///|
fn risk_register_fixture() -> Model {
  let model = plan_test_model()
  let d = model.plan.draft.unwrap()
  {
    ..model,
    plan: {
      ..model.plan,
      draft: Some({
        ..d,
        risks: [
          {
            id: "risk-old",
            summary: "Existing issue",
            severity: "medium",
            owner: "owner-test",
            mitigation: "Original mitigation",
            tasks: ["task-design"],
          },
          {
            id: "risk-other",
            summary: "Unlisted risk",
            severity: "low",
            owner: "owner-test",
            mitigation: "Keep this",
            tasks: [],
          },
        ],
      }),
      prepared: Some({ "fixture": "previous prepared result" }),
      phase: "prepared",
      risk_table: {
        ..plan_risk_table_initial(),
        text: "id,summary,severity,owner,mitigation,tasks,Status\nnew-risk,\"Supplier <script>界面, \"\"backup\"\"\",high,Test owner,\"Call\nAsk for backup\",task-design;task-review,Resolved\nrisk-old,Existing issue,critical,owner-test,,,Accepted",
      },
    },
  }
}

///|
test "risk register UI previews adds updates persists exports and sends only explicit prepare" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = risk_register_fixture()
  assert_true(
    plan_store(
      "owner-test",
      "company-actual",
      original.plan.draft.unwrap().to_json().stringify(),
    ),
  )
  let stored = plan_restore("owner-test", "company-actual")
  let (_, previewed) = plan_update(_ => none, RiskTable(Preview), original)
  assert_eq(previewed.plan.draft, original.plan.draft)
  assert_eq(previewed.plan.prepared, original.plan.prepared)
  assert_eq(previewed.plan.revision, original.plan.revision)
  assert_eq(previewed.plan.phase, original.plan.phase)
  assert_eq(plan_restore("owner-test", "company-actual"), stored)
  let changes = previewed.plan.risk_table.preview.unwrap().changes
  assert_eq(changes.length(), 2)
  assert_eq(changes[0].before, Some(original.plan.draft.unwrap().risks[0]))
  assert_eq(changes[1].before, None)
  let html = products_test_html(previewed)
  for
    expected in [
      "Risk register table", "Risk register preview", "New / 新增: 1; Updated / 修改: 1",
      "Before / 修改前", "New risk / 新增风险", "Supplier &lt;script&gt;界面",
      "Ignored columns: Status", "for=\"plan-risk-table\"", "id=\"plan-risk-table\"",
      "role=\"status\"",
    ] {
    assert_true(html.contains(expected))
  }
  assert_false(html.contains("Supplier <script>"))
  let (_, edited) = plan_update(_ => none, RiskTable(Apply), previewed)
  let d = edited.plan.draft.unwrap()
  assert_eq(d.risks.map(r => r.id), ["risk-old", "risk-other", "new-risk"])
  assert_eq(d.risks[0].severity, "critical")
  assert_eq(d.risks[0].mitigation, "")
  assert_eq(d.risks[0].tasks, [])
  assert_eq(d.risks[1], original.plan.draft.unwrap().risks[1])
  assert_eq(d.risks[2].summary, "Supplier <script>界面, \"backup\"")
  assert_eq(d.risks[2].mitigation, "Call\nAsk for backup")
  assert_eq(d.risks[2].tasks, ["task-design", "task-review"])
  let before = original.plan.draft.unwrap()
  assert_eq(
    {
      ..d,
      risks: before.risks,
      key: before.key,
      prepared_at: before.prepared_at,
    },
    before,
  )
  assert_false(d.key == before.key)
  assert_eq(edited.plan.prepared, None)
  assert_eq(edited.plan.revision, original.plan.revision + 1)
  assert_eq(edited.plan.risk_table.preview, None)
  assert_eq(edited.plan.risk_table.text, original.plan.risk_table.text)
  let restored : @plan_workbench.Draft = @json.from_json(
    @json.parse(plan_restore("owner-test", "company-actual")),
  )
  assert_eq(restored, d)
  let (_, repeated) = plan_update(_ => none, RiskTable(Apply), edited)
  assert_eq(repeated.plan, edited.plan)
  let (export, exported) = plan_update(_ => none, RiskTable(Export), edited)
  drafts_test_execute(export)
  assert_eq(exported.plan, edited.plan)
  guard @json.parse(plan_test_downloads()) is Array([download]) else {
    fail("one CSV download")
  }
  assert_eq(products_text(download, "name"), "plan-risks.csv")
  let csv = products_text(download, "text")
  assert_eq(csv, @plan_workbench.export_risk_table(d))
  assert_eq(@plan_workbench.preview_risk_table(d, csv, false).changes, [])
  assert_eq(plan_test_requests(), "[]")
  ignore(
    plan_test_file(
      "risk-register-before.json",
      before.to_json().stringify(indent=2),
    ),
  )
  ignore(
    plan_test_file("risk-register-input.csv", original.plan.risk_table.text),
  )
  ignore(plan_test_file("risk-register-preview.html", html))
  ignore(
    plan_test_file("risk-register-after.json", d.to_json().stringify(indent=2)),
  )
  ignore(plan_test_file("risk-register-output.csv", csv))
  let (_, switched) = plan_update(_ => none, Choose("company-second"), edited)
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), switched)
  assert_eq(reloaded.plan.draft, Some(d))
  assert_eq(reloaded.plan.risk_table, plan_risk_table_initial())
  let (prepare, saving) = plan_update(_ => none, Prepare, reloaded)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([request]) else {
    fail("one explicit prepare")
  }
  assert_eq(@json.parse(products_text(request, "body")), d.to_json())
  ignore(
    plan_test_file(
      "risk-register-prepare-request.json",
      products_text(request, "body"),
    ),
  )
}

///|
test "risk register closes and invalidates previews on input format draft and scope changes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, previewed) = plan_update(
    _ => none,
    RiskTable(Preview),
    risk_register_fixture(),
  )
  for
    action in [
      RiskTable(Close),
      RiskTable(Text("id,mitigation\nrisk-old,")),
      RiskTable(Format(true)),
      Edit("risk", "risk-old", "mitigation", "Changed"),
      Remove("task", "task-design"),
      Choose("company-second"),
      Refresh,
    ] {
    let (_, changed) = plan_update(_ => none, action, previewed)
    assert_eq(changed.plan.risk_table.preview, None)
    let (_, after) = plan_update(_ => none, RiskTable(Apply), changed)
    assert_eq(after.plan, changed.plan)
  }
  let (_, actor) = plan_update(_ => none, RiskTable(Apply), {
    ..previewed,
    dispatch_task_actor_id: "other",
  })
  assert_eq(actor.plan.draft, None)
  assert_eq(actor.plan.risk_table, plan_risk_table_initial())
  let stale = {
    ..previewed,
    plan: {
      ..previewed.plan,
      draft: Some({
        ..previewed.plan.draft.unwrap(),
        notes: "Different source",
      }),
    },
  }
  let (_, refused) = plan_update(_ => none, RiskTable(Apply), stale)
  assert_eq(refused.plan.draft, stale.plan.draft)
  assert_eq(refused.plan.revision, stale.plan.revision)
  assert_eq(refused.plan.risk_table.preview, None)
  let mismatched = {
    ..previewed,
    plan: { ..previewed.plan, selected: "company-second", },
  }
  let (_, ignored) = plan_update(_ => none, RiskTable(Export), mismatched)
  assert_eq(ignored.plan, mismatched.plan)
  assert_eq(plan_test_downloads(), "[]")
  assert_eq(plan_test_requests(), "[]")
}

///|
test "risk register no-op and failed previews preserve editor and fresh export bytes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = risk_register_fixture()
  let (_, bad_input) = plan_update(
    _ => none,
    RiskTable(Text("id,tasks\nrisk-old,missing")),
    original,
  )
  let (_, failed) = plan_update(_ => none, RiskTable(Preview), bad_input)
  assert_eq(failed.plan.draft, original.plan.draft)
  assert_eq(failed.plan.prepared, original.plan.prepared)
  assert_eq(failed.plan.risk_table.text, bad_input.plan.risk_table.text)
  assert_eq(failed.plan.risk_table.preview, None)
  assert_true(failed.plan.risk_table.note.contains("unknown or ambiguous task"))
  let (_, same_input) = plan_update(
    _ => none,
    RiskTable(
      Text(@plan_workbench.export_risk_table(original.plan.draft.unwrap())),
    ),
    original,
  )
  let (_, previewed) = plan_update(_ => none, RiskTable(Preview), same_input)
  assert_eq(previewed.plan.risk_table.preview.unwrap().changes, [])
  let (_, no_op) = plan_update(_ => none, RiskTable(Apply), previewed)
  assert_eq(no_op.plan, previewed.plan)
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  let (first, _) = plan_update(_ => none, RiskTable(Export), original)
  drafts_test_execute(first)
  let (_, edited) = plan_update(
    _ => none,
    Edit("risk", "risk-old", "mitigation", "Fresh mitigation"),
    original,
  )
  let (second, _) = plan_update(_ => none, RiskTable(Export), edited)
  drafts_test_execute(second)
  guard @json.parse(plan_test_downloads()) is Array([before, after]) else {
    fail("two downloads")
  }
  assert_false(products_text(before, "text").contains("Fresh mitigation"))
  assert_true(products_text(after, "text").contains("Fresh mitigation"))
  assert_eq(
    products_text(after, "text"),
    @plan_workbench.export_risk_table(edited.plan.draft.unwrap()),
  )
  assert_eq(plan_test_requests(), "[]")
}

///|
test "risk register UI can append into empty register with TSV" {
  plan_test_browser()
  defer plan_test_cleanup()
  let original = plan_test_model()
  let (download, _) = plan_update(_ => none, RiskTable(Export), original)
  drafts_test_execute(download)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("header download")
  }
  assert_eq(
    products_text(file, "text"),
    "id,summary,severity,owner,mitigation,tasks\r\n",
  )
  let (_, format) = plan_update(_ => none, RiskTable(Format(true)), original)
  let (_, input) = plan_update(
    _ => none,
    RiskTable(
      Text("id\tsummary\tseverity\towner\nR1\tNew risk\tlow\towner-test"),
    ),
    format,
  )
  let (_, previewed) = plan_update(_ => none, RiskTable(Preview), input)
  let (_, edited) = plan_update(_ => none, RiskTable(Apply), previewed)
  assert_eq(edited.plan.draft.unwrap().risks.length(), 1)
  assert_eq(edited.plan.draft.unwrap().risks[0].id, "R1")
  assert_eq(edited.plan.draft.unwrap().risks[0].mitigation, "")
  assert_eq(edited.plan.draft.unwrap().risks[0].tasks, [])
  assert_eq(plan_test_requests(), "[]")
}

///|
test "risk register staging resets after template replacement and saved version open" {
  plan_test_browser()
  defer plan_test_cleanup()
  let (_, previewed) = plan_update(
    _ => none,
    RiskTable(Preview),
    risk_register_fixture(),
  )
  let (_, source) = plan_update(
    _ => none,
    Template(
      Source(@plan_workbench.export_template(plan_template_test_draft())),
    ),
    previewed,
  )
  let (_, template) = plan_update(_ => none, Template(Preview), source)
  let (_, mapped) = plan_update(_ => none, Template(Owner("owner-1")), template)
  let (_, replaced) = plan_update(_ => none, Template(Apply), mapped)
  assert_eq(replaced.plan.template, plan_template_initial())
  assert_eq(replaced.plan.risk_table, plan_risk_table_initial())
  assert_eq(
    replaced.plan.draft.unwrap().risks[0].summary,
    "Examples arrive late",
  )
  let (_, after) = plan_update(_ => none, RiskTable(Apply), replaced)
  assert_eq(after.plan, replaced.plan)
  let draft = { ..plan_test_draft(), key: "saved-synthetic", }
  let artifact : Json = {
    "operation_ref": "moonproj/project.plan.prepare@0.1.0",
    "plan_request_id": draft.key,
    "project": { "project_id": draft.project_id },
    "workflow": {
      "status": "pending_review",
      "accepted": false,
      "review_required": true,
    },
    "authority_effects": {
      "spend_authorized": false,
      "accounting_posted": false,
      "payment_released": false,
      "contract_signed": false,
      "work_executed": false,
    },
  }
  let saved : Json = {
    "contract": "moonproj.project-plan-workbench.v1",
    "actor": "owner-test",
    "project_id": draft.project_id,
    "key": draft.key,
    "persisted": true,
    "draft": draft.to_json(),
    "artifact": artifact,
    "artifact_json": artifact.stringify(),
    "readable": "Synthetic response fixture only",
  }
  let (_, opening) = plan_update(_ => none, Open(draft.key), previewed)
  let (_, opened) = plan_update(
    _ => none,
    Read(
      "owner-test",
      opening.plan.epoch,
      opening.plan.revision,
      draft.key,
      "",
      200,
      saved.stringify(),
    ),
    opening,
  )
  assert_eq(opened.plan.draft, Some(draft))
  assert_eq(opened.plan.risk_table, plan_risk_table_initial())
  let (_, after) = plan_update(_ => none, RiskTable(Apply), opened)
  assert_eq(after.plan, opened.plan)
  assert_eq(plan_test_requests(), "[]")
}
