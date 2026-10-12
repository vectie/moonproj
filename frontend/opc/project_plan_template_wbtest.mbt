///|
fn plan_template_test_draft() -> @plan_workbench.Draft {
  {
    ..plan_test_draft(),
    notes: "Synthetic two-stage delivery template.\nProduce a source-backed brief and independent review; external delivery is a separate action. 🌓",
    currency: "USD",
    limit: "1000.00",
    contingency: "100.00",
    owners: [
      { id: "owner-test", name: "Alex", role: "Research and delivery", },
      { id: "external-sam", name: "Sam", role: "Independent reviewer", },
    ],
    milestones: [
      {
        id: "discovery",
        name: "Discovery brief",
        owner: "owner-test",
        date: "2026-11-06",
        criteria: "Three concrete examples\nSource references retained",
        evidence: "Source-backed brief\nReview notes",
      },
      {
        id: "delivery",
        name: "Delivery package",
        owner: "external-sam",
        date: "2026-11-13",
        criteria: "Readable final artifact\nScope checklist",
        evidence: "Artifact link\nReviewer comments",
      },
    ],
    tasks: [
      {
        id: "research",
        name: "Collect examples",
        owner: "owner-test",
        milestone: "discovery",
        cost: "125.40",
        dependencies: [],
      },
      {
        id: "draft",
        name: "Draft brief",
        owner: "owner-test",
        milestone: "discovery",
        cost: "350.50",
        dependencies: ["research"],
      },
      {
        id: "review",
        name: "Review brief",
        owner: "external-sam",
        milestone: "delivery",
        cost: "100.00",
        dependencies: ["research", "draft"],
      },
      {
        id: "deliver",
        name: "Prepare delivery",
        owner: "owner-test",
        milestone: "delivery",
        cost: "25.00",
        dependencies: ["review"],
      },
    ],
    risks: [
      {
        id: "sources",
        summary: "Examples arrive late",
        severity: "medium",
        owner: "owner-test",
        mitigation: "Use named alternate sources\nKeep unresolved gaps explicit",
        tasks: ["research", "draft"],
      },
    ],
  }
}

///|
test "complete template download preview cross-project reuse edits reload and prepare" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let source = {
    ..model,
    plan: {
      ..model.plan,
      draft: Some(plan_template_test_draft()),
      prepared: Some({ "saved": "unchanged" }),
    },
  }
  let (download, unchanged) = plan_update(_ => none, Template(Download), source)
  drafts_test_execute(download)
  assert_eq(unchanged.plan, source.plan)
  guard @json.parse(plan_test_downloads()) is Array([file]) else {
    fail("one template download expected")
  }
  assert_eq(products_text(file, "name"), "plan-template.json")
  assert_eq(products_text(file, "type"), "application/json;charset=utf-8")
  let exported = products_text(file, "text")
  assert_eq(
    exported,
    @plan_workbench.export_template(plan_template_test_draft()),
  )
  ignore(plan_test_file("reusable-delivery-template.json", exported))
  ignore(
    plan_test_file(
      "template-source-draft.json",
      plan_template_test_draft().to_json().stringify(indent=2),
    ),
  )
  let (_, target) = plan_update(_ => none, Choose("company-second"), source)
  let (_, target) = plan_update(_ => none, Template(Source(exported)), target)
  let (_, previewed) = plan_update(_ => none, Template(Preview), target)
  assert_eq(previewed.plan.draft, target.plan.draft)
  assert_eq(previewed.plan.revision, target.plan.revision)
  assert_eq(plan_restore("owner-test", "company-second"), "")
  let (_, mapped) = plan_update(
    _ => none,
    Template(Owner("owner-2")),
    previewed,
  )
  let (_, mapped) = plan_update(_ => none, Template(Name("Morgan")), mapped)
  let html = products_test_html(mapped)
  for
    text in [
      "用模板替换当前草稿", "Discovery brief", "Source references retained",
      "Independent reviewer", "owner-2", "1000.00",
    ] {
    assert_true(html.contains(text))
  }
  ignore(plan_test_file("template-preview.html", html))
  let (_, imported) = plan_update(_ => none, Template(Apply), mapped)
  let d = imported.plan.draft.unwrap()
  assert_eq(d.project_id, "company-second")
  assert_eq(d.owners[1].id, "owner-test")
  assert_eq(d.owners[1].name, "Morgan")
  assert_eq(d.owners[0].name, "Alex")
  assert_true(d.owners[0].id != "owner-test")
  assert_eq(d.tasks[2].owner, "owner-test")
  assert_eq(d.tasks[2].dependencies, [d.tasks[0].id, d.tasks[1].id])
  assert_eq(d.risks[0].tasks, [d.tasks[0].id, d.tasks[1].id])
  assert_eq(d.tasks[3].milestone, d.milestones[1].id)
  assert_eq(d.milestones[1].owner, "owner-test")
  assert_true(d.key != source.plan.draft.unwrap().key)
  assert_true(d.key != target.plan.draft.unwrap().key)
  assert_eq(imported.plan.revision, mapped.plan.revision + 1)
  assert_eq(imported.plan.prepared, None)
  assert_eq(imported.plan.template, plan_template_initial())
  assert_eq(plan_test_requests(), "[]")
  let (_, repeat) = plan_update(_ => none, Template(Apply), imported)
  assert_eq(repeat.plan, imported.plan)
  let (_, reloaded) = plan_update(_ => none, Choose("company-second"), imported)
  assert_eq(reloaded.plan.draft, imported.plan.draft)
  let (_, edited) = plan_update(
    _ => none,
    Edit("task", d.tasks[0].id, "name", "Collect buyer examples"),
    reloaded,
  )
  assert_eq(edited.plan.draft.unwrap().tasks[0].name, "Collect buyer examples")
  let (prepare, saving) = plan_update(_ => none, Prepare, edited)
  drafts_test_execute(prepare)
  assert_eq(saving.plan.phase, "saving")
  guard @json.parse(plan_test_requests()) is Array([call]) else {
    fail("one prepare call expected")
  }
  assert_eq(
    products_text(call, "url"),
    "/api/company/projects/company-second/prepared-plans",
  )
  let body = products_text(call, "body")
  assert_eq(@json.parse(body), edited.plan.draft.unwrap().to_json())
  ignore(plan_test_file("template-ui-request.json", body))
  ignore(
    plan_test_file(
      "template-editable-plan.json",
      edited.plan.draft.unwrap().to_json().stringify(indent=2),
    ),
  )
  let native = plan_test_file("template-gateway-response.json", "")
  if !native.is_empty() {
    let record = @json.parse(native)
    let (_, opened) = plan_update(
      _ => none,
      Read(
        "owner-test",
        edited.plan.epoch,
        edited.plan.revision,
        products_text(record, "key"),
        "",
        200,
        native,
      ),
      { ..edited, plan: { ..edited.plan, phase: "opening", }, },
    )
    assert_eq(opened.plan.phase, "prepared")
    let opened_draft = opened.plan.draft.unwrap()
    ignore(
      plan_test_file(
        "template-opened-editable-plan.json",
        opened_draft.to_json().stringify(indent=2),
      ),
    )
    assert_eq(opened_draft.tasks[0].name, "Collect buyer examples")
    assert_eq(
      @plan_workbench.export_template(opened_draft),
      @plan_workbench.export_template(edited.plan.draft.unwrap()),
    )
    let (readable_download, downloaded) = plan_update(
      _ => none,
      Download(false),
      opened,
    )
    drafts_test_execute(readable_download)
    assert_eq(downloaded.plan, opened.plan)
    assert_true(plan_test_downloads().contains("60090"))
    guard @json.parse(plan_test_downloads()) is Array([_, readable_file]) else {
      fail("template and native readable downloads expected")
    }
    assert_eq(
      products_text(readable_file, "text"),
      products_text(record, "readable"),
    )
    ignore(plan_test_file("template-validated-native-response.json", native))
    ignore(
      plan_test_file(
        "template-validated-native-readable.txt",
        products_text(readable_file, "text"),
      ),
    )
    ignore(
      plan_test_file("template-saved-plan.html", products_test_html(opened)),
    )
  }
}

///|
test "template preview correction close repeated actions and scope changes preserve the editor" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let model = {
    ..model,
    plan: {
      ..model.plan,
      prepared: Some({ "saved": true }),
      phase: "prepared",
    },
  }
  let exported = @plan_workbench.export_template(plan_template_test_draft())
  let (_, typed) = plan_update(_ => none, Template(Source(exported)), model)
  let (_, preview) = plan_update(_ => none, Template(Preview), typed)
  let (_, unmapped) = plan_update(_ => none, Template(Apply), preview)
  assert_eq(unmapped.plan.draft, model.plan.draft)
  assert_eq(unmapped.plan.prepared, model.plan.prepared)
  assert_eq(unmapped.plan.revision, model.plan.revision)
  let (_, malformed) = plan_update(_ => none, Template(Source("{")), preview)
  assert_eq(malformed.plan.template.preview, None)
  let (_, failed) = plan_update(_ => none, Template(Preview), malformed)
  assert_true(failed.plan.template.note.contains("valid JSON"))
  assert_eq(failed.plan.draft, model.plan.draft)
  assert_eq(failed.plan.prepared, model.plan.prepared)
  assert_eq(failed.plan.phase, model.plan.phase)
  let (_, closed) = plan_update(_ => none, Template(Close), preview)
  assert_eq(closed.plan.template, plan_template_initial())
  assert_eq(closed.plan.draft, model.plan.draft)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), preview)
  assert_eq(switched.plan.template, plan_template_initial())
  let (_, ignored) = plan_update(_ => none, Template(Apply), switched)
  assert_eq(ignored.plan, switched.plan)
  let (_, actor_changed) = plan_update(_ => none, Template(Apply), {
    ..preview,
    dispatch_task_actor_id: "another",
  })
  assert_eq(actor_changed.plan.draft, None)
  assert_eq(actor_changed.plan.template, plan_template_initial())
  assert_eq(plan_restore("owner-test", "company-actual"), "")
  assert_eq(plan_test_requests(), "[]")
}

///|
test "template replacement fences in-flight save and makes newly mapped rows editable" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let (_, saving) = plan_update(_ => none, Prepare, model)
  let (_, typed) = plan_update(
    _ => none,
    Template(
      Source(@plan_workbench.export_template(plan_template_test_draft())),
    ),
    saving,
  )
  let (_, preview) = plan_update(_ => none, Template(Preview), typed)
  let (_, mapped) = plan_update(_ => none, Template(Owner("owner-1")), preview)
  let (_, mapped) = plan_update(_ => none, Template(Name("Test owner")), mapped)
  let (_, imported) = plan_update(_ => none, Template(Apply), mapped)
  let (_, late) = plan_update(
    _ => none,
    Read(
      "owner-test",
      saving.plan.epoch,
      saving.plan.revision,
      "plan-fixture",
      "",
      200,
      "{}",
    ),
    imported,
  )
  assert_eq(late.plan, imported.plan)
  assert_eq(imported.plan.phase, "editing")
  let d = imported.plan.draft.unwrap()
  let (_, changed) = plan_update(
    _ => none,
    Edit("milestone", d.milestones[0].id, "date", "2026-12-01"),
    imported,
  )
  assert_eq(changed.plan.draft.unwrap().milestones[0].date, "2026-12-01")
  assert_eq(changed.plan.draft.unwrap().milestones[1].date, "2026-11-13")
}
