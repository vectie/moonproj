///|
fn plan_compare_test_saved(d : @plan_workbench.Draft) -> Json {
  let artifact : Json = {
    "operation_ref": "moonproj/project.plan.prepare@0.1.0",
    "plan_request_id": d.key,
    "project": { "project_id": d.project_id },
    "recorded_at": d.prepared_at,
    "request_digest": "synthetic-digest",
    "source_evidence": [],
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
    "budget": {
      "currency": d.currency,
      "limit_minor": "100000",
      "planned_total_minor": "50025",
      "contingency_minor": "10000",
      "unallocated_minor": "39975",
    },
    "tasks": Json::array(
      d.tasks.map(t => ({ "task_id": t.id, "planned_cost_minor": "20025" } : Json)),
    ),
  }
  {
    "contract": "moonproj.project-plan-workbench.v1",
    "actor": "owner-test",
    "project_id": d.project_id,
    "key": d.key,
    "persisted": true,
    "draft": ToJson::to_json(d),
    "artifact": artifact,
    "artifact_json": artifact.stringify(),
    "readable": "Synthetic test only",
  }
}

///|
fn plan_compare_test_model() -> Model {
  let model = plan_test_model()
  {
    ..model,
    plan: {
      ..model.plan,
      prepared: Some(plan_compare_test_saved(plan_test_draft())),
      history: [
        { "key": "plan-fixture" },
        { "key": "plan-after" },
        { "key": "plan-third" },
      ],
      phase: "prepared",
    },
  }
}

///|
fn plan_compare_test_begin(model : Model) -> (Cmd, Model) {
  let (_, shown) = plan_update(_ => none, Compare(Show), model)
  let (_, selected) = plan_update(
    _ => none,
    Compare(Select(true, "plan-fixture")),
    shown,
  )
  plan_update(_ => none, Compare(Select(false, "plan-after")), selected)
}

///|
fn plan_compare_test_reply(
  model : Model,
  before : Bool,
  body : String,
  status? : Int = 200,
) -> Model {
  let s = model.plan
  plan_update(
    _ => none,
    Compare(
      Received(
        s.actor,
        s.epoch,
        s.selected,
        s.comparison.generation,
        s.comparison.before_key,
        s.comparison.after_key,
        before,
        status,
        body,
      ),
    ),
    model,
  ).1
}

///|
fn plan_compare_test_editor_unchanged(
  before : Model,
  after : Model,
) -> Unit raise {
  assert_eq(
    before.plan.draft.map(d => ToJson::to_json(d).stringify()),
    after.plan.draft.map(d => ToJson::to_json(d).stringify()),
  )
  assert_eq(before.plan.prepared, after.plan.prepared)
  assert_eq(before.plan.phase, after.plan.phase)
  assert_eq(before.plan.revision, after.plan.revision)
  assert_eq(before.plan.note, after.plan.note)
}

///|
test "comparison rejects mismatched saved identity malformed payload and authority without changing editor" {
  let model = plan_compare_test_model()
  let (_, pending) = plan_compare_test_begin(model)
  let body = plan_compare_test_saved(plan_test_draft()).stringify()
  for
    invalid in [
      "{",
      "{}",
      body.replace_all(old="owner-test", new="wrong-actor"),
      body.replace_all(old="company-actual", new="wrong-project"),
      body.replace_all(old="plan-fixture", new="wrong-key"),
      body.replace_all(old="pending_review", new="accepted"),
      body.replace_all(
        old="\"spend_authorized\":false",
        new="\"spend_authorized\":true",
      ),
    ] {
    let failed = plan_compare_test_reply(pending, true, invalid)
    assert_eq(failed.plan.comparison.phase, "error")
    assert_true(failed.plan.comparison.result is None)
    plan_compare_test_editor_unchanged(model, failed)
    assert_eq(
      products_test_effect_count(
        plan_update(_ => none, Compare(Export), failed).0,
      ),
      0,
    )
  }
}

///|
test "comparison GET pair is independent and preserves draft prepared result and local bytes" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_compare_test_model()
  let bytes = "  browser draft bytes intentionally not canonical  "
  assert_true(plan_store(model.plan.actor, model.plan.selected, bytes))
  let (cmd, pending) = plan_compare_test_begin(model)
  drafts_test_execute(cmd)
  let requests = @json.parse(plan_test_requests())
  guard requests is Array(requests) && requests.length() == 2 else {
    fail("Exactly two reads required")
  }
  for i, request in requests {
    assert_eq(products_text(request, "method"), "GET")
    assert_eq(products_text(request, "body"), "")
    assert_eq(
      products_text(request, "url"),
      plan_url(model.plan.selected) +
      "/" +
      (if i == 0 { "plan-fixture" } else { "plan-after" }),
    )
  }
  let after = {
    ..plan_test_draft(),
    key: "plan-after",
    notes: "Complete changed scope\nSecond line",
  }
  let first = plan_compare_test_reply(
    pending,
    false,
    plan_compare_test_saved(after).stringify(),
  )
  assert_true(first.plan.comparison.result is None)
  let ready = plan_compare_test_reply(
    first,
    true,
    plan_compare_test_saved(plan_test_draft()).stringify(),
  )
  assert_eq(ready.plan.comparison.phase, "ready")
  plan_compare_test_editor_unchanged(model, ready)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), bytes)
  let html = products_test_html(ready)
  for
    text in [
      "Before", "After", "Scope / source notes", "Complete changed scope", "Second line",
      "下载可读对比报告", "关闭对比",
    ] {
    assert_true(html.contains(text))
  }
  let (download, _) = plan_update(_ => none, Compare(Export), ready)
  drafts_test_execute(download)
  let files = @plan_workbench.items(
    ({ "files": @json.parse(plan_test_downloads()) } : Json),
    "files",
  )
  assert_eq(
    products_text(files[0], "text"),
    ready.plan.comparison.result.unwrap().readable(),
  )
  let (_, swapped) = plan_update(_ => none, Compare(Swap), ready)
  plan_compare_test_editor_unchanged(model, swapped)
  assert_true(swapped.plan.comparison.result is None)
  let failed = plan_compare_test_reply(swapped, true, "", status=503)
  plan_compare_test_editor_unchanged(model, failed)
  assert_eq(failed.plan.comparison.phase, "error")
  let (_, closed) = plan_update(_ => none, Compare(Close), failed)
  plan_compare_test_editor_unchanged(model, closed)
  assert_false(closed.plan.comparison.visible)
  assert_eq(plan_restore(model.plan.actor, model.plan.selected), bytes)
}

///|
test "late comparison replies fenced by pair generation actor project epoch cancel and reload while editing continues" {
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_compare_test_model()
  let (_, pending) = plan_compare_test_begin(model)
  let c = pending.plan.comparison
  let late = Compare(
    Received(
      "owner-test",
      1,
      "company-actual",
      c.generation,
      c.before_key,
      c.after_key,
      true,
      200,
      plan_compare_test_saved(plan_test_draft()).stringify(),
    ),
  )
  let (_, changed_pair) = plan_update(
    _ => none,
    Compare(Select(false, "plan-third")),
    pending,
  )
  let (_, closed) = plan_update(_ => none, Compare(Close), pending)
  let (_, reopened) = plan_compare_test_begin(closed)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), pending)
  let actor = plan_reconcile({
    ..pending,
    dispatch_task_actor_id: "another-actor",
  })
  let (_, refreshed) = plan_update(_ => none, Refresh, pending)
  for
    state in [
      changed_pair,
      closed,
      reopened,
      switched,
      actor,
      refreshed,
      plan_test_model(),
    ] {
    let (_, unchanged) = plan_update(_ => none, late, state)
    assert_eq(unchanged.plan, state.plan)
  }
  let (_, edited) = plan_update(
    _ => none,
    Edit("plan", "", "notes", "Editing during comparison"),
    pending,
  )
  let local = plan_restore(edited.plan.actor, edited.plan.selected)
  let first = plan_compare_test_reply(
    edited,
    true,
    plan_compare_test_saved(plan_test_draft()).stringify(),
  )
  let ready = plan_compare_test_reply(
    first,
    false,
    plan_compare_test_saved({ ..plan_test_draft(), key: "plan-after", }).stringify(),
  )
  assert_eq(ready.plan.comparison.phase, "ready")
  plan_compare_test_editor_unchanged(edited, ready)
  assert_eq(plan_restore(edited.plan.actor, edited.plan.selected), local)
  let (_, reloaded) = plan_update(_ => none, Choose("company-actual"), ready)
  assert_eq(reloaded.plan.draft.unwrap().notes, "Editing during comparison")
  assert_false(reloaded.plan.comparison.visible)
  assert_eq(plan_update(_ => none, late, reloaded).1.plan, reloaded.plan)
}

///|
test "typed stable ID comparison separates reorder labels sets provenance long fields and native money" {
  let d = plan_test_draft()
  let task = d.tasks[1]
  let a = {
    ..d,
    owners: [..d.owners, { id: "second", name: "Same name", role: "Reviewer", }],
    risks: [
      {
        id: "risk",
        summary: "Long risk",
        severity: "low",
        owner: "owner-test",
        mitigation: "Full mitigation\nTail",
        tasks: ["task-design", "task-review"],
      },
    ],
    tasks: [d.tasks[0], { ..task, dependencies: ["first", "second"], }],
  }
  let before = plan_compare_test_saved(a)
  let metadata = plan_compare_test_saved({
    ..a,
    key: "other-version",
    prepared_at: "2026-10-08T00:00:00Z",
  })
  assert_true(
    @plan_workbench.compare_saved(before, metadata).changes.is_empty(),
  )
  let reordered = {
    ..a,
    owners: [a.owners[1], a.owners[0]],
    tasks: [{ ..a.tasks[1], dependencies: ["second", "first"], }, a.tasks[0]],
    risks: [{ ..a.risks[0], tasks: ["task-review", "task-design"], }],
  }
  let diff = @plan_workbench.compare_saved(
    before,
    plan_compare_test_saved(reordered),
  )
  assert_eq(diff.changes.length(), 1)
  assert_eq(diff.changes[0].field, "Execution order (task IDs)")
  let changed = {
    ..a,
    notes: "New scope",
    owners: [
      { ..a.owners[0], name: "Renamed", role: "New role", },
      { ..a.owners[1], id: "different-owner", },
    ],
    tasks: [
      { ..a.tasks[0], id: "different-task", },
      {
        ..a.tasks[1],
        name: "Renamed task",
        owner: "second",
        milestone: "new-milestone",
        dependencies: [],
      },
    ],
    milestones: [
      {
        ..a.milestones[0],
        name: "Renamed milestone",
        owner: "second",
        date: "2027-01-01",
        criteria: "Changed criteria\nLast criterion",
        evidence: "Changed evidence\nLast evidence",
      },
    ],
    risks: [
      {
        ..a.risks[0],
        summary: "Renamed risk",
        severity: "high",
        owner: "second",
        mitigation: "Changed mitigation\nLast mitigation",
        tasks: [],
      },
    ],
  }
  let changes = @plan_workbench.compare_saved(
    before,
    plan_compare_test_saved(changed),
  )
  for
    field in [
      "Scope / source notes", "Name", "Role", "Owner ID", "Milestone ID", "Dependencies (ID set)",
      "Target date", "Acceptance criteria", "Required evidence", "Summary", "Severity",
      "Mitigation", "Related tasks (ID set)",
    ] {
    assert_true(changes.changes.any(c => c.field == field), msg=field)
  }
  for
    (kind, old, new) in [
      ("Owner", "second", "different-owner"),
      ("Task", "task-design", "different-task"),
    ] {
    assert_true(
      changes.changes.any(c => {
        c.kind == kind && c.id == old && c.status == "removed"
      }),
    )
    assert_true(
      changes.changes.any(c => {
        c.kind == kind && c.id == new && c.status == "added"
      }),
    )
  }
  assert_true(changes.readable().contains("Last evidence"))
  assert_true(changes.readable().contains("Last mitigation"))
  // Draft monetary spelling is not a native amount and must not affect deltas.
  let same_money = plan_compare_test_saved({
    ..a,
    limit: "9999999999.00",
    tasks: [{ ..a.tasks[0], cost: "999999.00", }, a.tasks[1]],
  })
  assert_true(
    @plan_workbench.compare_saved(before, same_money).changes.is_empty(),
  )
  let changed_ids = {
    ..a,
    milestones: [{ ..a.milestones[0], id: "different-milestone", }],
    risks: [{ ..a.risks[0], id: "different-risk", }],
  }
  let id_changes = @plan_workbench.compare_saved(
      before,
      plan_compare_test_saved(changed_ids),
    ).changes
  for
    (kind, old, new) in [
      ("Milestone", "milestone-one", "different-milestone"),
      ("Risk", "risk", "different-risk"),
    ] {
    assert_true(
      id_changes.any(c => c.kind == kind && c.id == old && c.status == "removed"),
    )
    assert_true(
      id_changes.any(c => c.kind == kind && c.id == new && c.status == "added"),
    )
  }
  let missing_money = @json.parse(
    before.stringify().replace_all(old="\"20025\"", new="null"),
  )
  let missing_changes = @plan_workbench.compare_saved(
      missing_money, missing_money,
    ).changes
  assert_true(
    missing_changes.any(c => {
      c.field == "Cost (minor units)" &&
      c.status == "unavailable" &&
      c.before.contains("missing value") &&
      c.delta.has_prefix("Unavailable")
    }),
  )
}

///|
test "comparison money is exact at native Int64 and JS safe integer boundaries and never invents zeros or FX" {
  for
    (a, b, delta) in [
      ("0", "9223372036854775807", "+9223372036854775807"),
      ("9223372036854775807", "0", "-9223372036854775807"),
      ("9007199254740992", "9007199254740993", "+1"),
      ("1", "1", "0"),
    ] {
    assert_eq(
      @plan_workbench.comparison_delta(
        Json::string(a),
        Json::string(b),
        "CNY",
        "CNY",
      ),
      delta + " CNY minor units",
    )
  }
  for
    bad in [
      Json::null(),
      Json::number(1),
      Json::string(""),
      Json::string("-1"),
      Json::string("1.5"),
      Json::string("1e2"),
      Json::string("9223372036854775808"),
    ] {
    assert_true(
      @plan_workbench.comparison_delta(bad, Json::string("0"), "CNY", "CNY").has_prefix(
        "Unavailable",
      ),
    )
  }
  assert_true(
    @plan_workbench.comparison_delta(
      Json::string("1"),
      Json::string("2"),
      "CNY",
      "USD",
    ).contains("no FX"),
  )
  assert_true(
    @plan_workbench.comparison_delta(
      Json::string("1"),
      Json::string("2"),
      "",
      "",
    ).has_prefix("Unavailable"),
  )
}

///|
test "actual native saved pair enters compiled UI read-only comparison and downloadable report" {
  let body = plan_test_file("gateway-response.json", "")
  let after_body = plan_test_file("gateway-compare-after.json", "")
  let d = plan_test_draft()
  let after = {
    ..d,
    key: "plan-after",
    notes: "Changed scope from actual UI typed input\nAll details retained",
    prepared_at: "2026-10-07T06:00:00Z",
    limit: "1100.00",
    tasks: [
      { ..d.tasks[0], name: "Design revised", cost: "201.25", },
      d.tasks[1],
    ],
    milestones: [
      {
        ..d.milestones[0],
        criteria: "Updated full criterion\nFinal criterion",
        evidence: "New reviewer receipt",
      },
    ],
  }
  ignore(
    plan_test_file("ui-compare-after-request.json", ToJson::to_json(after).stringify()),
  )
  if body.is_empty() || after_body.is_empty() {
    return
  }
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_compare_test_model()
  assert_true(
    plan_store("owner-test", "company-actual", "raw local draft preserved"),
  )
  let (_, pending) = plan_compare_test_begin(model)
  let first = plan_compare_test_reply(pending, true, body)
  let ready = plan_compare_test_reply(first, false, after_body)
  assert_eq(ready.plan.comparison.phase, "ready")
  plan_compare_test_editor_unchanged(model, ready)
  let report = ready.plan.comparison.result.unwrap().readable()
  for
    text in [
      "Design revised", "+100 CNY minor units", "+10000 CNY minor units", "Final criterion",
      "New reviewer receipt", "All details retained", "pending named-human review",
    ] {
    assert_true(report.contains(text), msg=text)
  }
  let (command, _) = plan_update(_ => none, Compare(Export), ready)
  drafts_test_execute(command)
  let downloads = @json.parse(plan_test_downloads())
  guard downloads is [file] else { fail("comparison report download missing") }
  assert_eq(products_text(file, "text"), report)
  assert_eq(
    plan_restore("owner-test", "company-actual"),
    "raw local draft preserved",
  )
  ignore(plan_test_file("ui-comparison-report.txt", report))
  ignore(plan_test_file("ui-comparison-render.html", products_test_html(ready)))
  ignore(
    plan_test_file(
      "ui-comparison-downloads.json",
      downloads.stringify(indent=2),
    ),
  )
}
