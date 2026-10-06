///|
fn drafts_test_update(model : Model, action : DispatchDraftMsg) -> Model {
  let (_, next) = update(_ => none, DraftAction(action), model)
  next
}

///|
fn drafts_test_prepared() -> Model {
  products_test_update(
    {
      ..products_test_project(products_test_selected("moondesk")),
      dispatch_task_actor_id: "actor-drafts",
    },
    Prepare,
  )
}

///|
fn drafts_test_valid() -> Model {
  let mut model = drafts_test_prepared()
  for
    (field, value) in [
      ("title", "  Deliver draft B  "),
      ("acceptance", "  Verify B's saved output  "),
      ("owner_id", "owner-b"),
      ("workspace", "/workspace/authorized-b"),
      ("model", "configured-model-b"),
      ("begin_date", "2026-10-02"),
      ("end_date", "2026-10-03"),
    ] {
    model = drafts_test_update(model, Input(field, value))
  }
  model
}

///|
fn drafts_test_creating() -> Model {
  let saving = drafts_test_update(drafts_test_valid(), Create)
  drafts_test_update(
    saving,
    Stored("actor-drafts", saving.dispatch_draft_id, true),
  )
}

///|
fn drafts_test_receipt(task_id : String) -> String {
  Json::object({
    "task": Json::object({
      "task_id": Json::string(task_id),
      "state": Json::string("pending"),
    }),
  }).stringify()
}

///|
fn drafts_test_snapshot_body(task_id : String) -> String {
  Json::object({
    "data": Json::object({
      "task": Json::object({
        "taskGuid": Json::string(task_id),
        "product_id": Json::string("moondesk"),
        "projGuid": Json::string("company-actual"),
        "taskName": Json::string("Deliver draft B"),
        "status": Json::string("pending"),
      }),
      "reports": Json::array([]),
    }),
  }).stringify()
}

///|
// These effects execute only against the isolated, non-networking JS stub below.
// Other tests inspect reducer results without executing transport commands.
struct DraftsTestScheduler {
  mut effects : Int
}

///|
impl @cmd.Scheduler for DraftsTestScheduler with fn run_effect(self, _, effect) {
  self.effects += 1
  effect(self)
}

///|
impl @cmd.Scheduler for DraftsTestScheduler with fn queue_message(_, _, send) {
  send()
}

///|
impl @cmd.Scheduler for DraftsTestScheduler with fn drain_message(_) {
  ()
}

///|
impl @cmd.Scheduler for DraftsTestScheduler with fn hooks(_) {
  { url_request: None, url_changed: None, }
}

///|
fn drafts_test_execute(command : Cmd) -> Unit {
  let scheduler : DraftsTestScheduler = { effects: 0, }
  @cmd.Scheduler::add(scheduler, command)
  ignore(scheduler.effects)
}

///|
#cfg(target="js")
extern "js" fn drafts_test_transport(fail_storage : Bool) =
  #| failStorage => {
  #|   globalThis.__draftsTest = { priorWindow: globalThis.window, priorFetch: globalThis.fetch, events: [], posts: [], reads: [] };
  #|   const state = globalThis.__draftsTest;
  #|   const data = new Map();
  #|   globalThis.window = {
  #|     location: {href: "https://example.test/?task=task-1"},
  #|     localStorage: {
  #|       getItem: key => data.get(key) || null,
  #|       setItem: (key, value) => {state.events.push(failStorage ? "save-failed" : "save"); if (failStorage) throw new Error("storage denied"); data.set(key, value);},
  #|       removeItem: key => data.delete(key)
  #|     },
  #|     history: {
  #|       pushState: (_, __, url) => {globalThis.window.location.href = String(url);},
  #|       replaceState: (_, __, url) => {globalThis.window.location.href = String(url);}
  #|     }
  #|   };
  #|   globalThis.fetch = (url, options) => {
  #|     const method = options && options.method || "GET";
  #|     state.events.push(method + " " + url);
  #|     if (method === "POST") state.posts.push(options.body);
  #|     else state.reads.push(String(url));
  #|     return {then: () => ({catch: () => {}})};
  #|   };
  #| }

///|
#cfg(target="js")
extern "js" fn drafts_test_events() -> String =
  #| () => globalThis.__draftsTest.events.join("|")

///|
#cfg(target="js")
extern "js" fn drafts_test_post_count() -> Int =
  #| () => globalThis.__draftsTest.posts.length

///|
#cfg(target="js")
extern "js" fn drafts_test_post_body(index : Int) -> String =
  #| index => globalThis.__draftsTest.posts[index] || ""

///|
#cfg(target="js")
extern "js" fn drafts_test_transport_cleanup() =
  #| () => {
  #|   const state = globalThis.__draftsTest;
  #|   if (state.priorWindow === undefined) delete globalThis.window;
  #|   else globalThis.window = state.priorWindow;
  #|   if (state.priorFetch === undefined) delete globalThis.fetch;
  #|   else globalThis.fetch = state.priorFetch;
  #|   delete globalThis.__draftsTest;
  #| }

///|
test "draft Prepare B preserves selected A through running submitted interrupted loading and failed read" {
  for state in ["running", "submitted", "interrupted", "loading", "failed_read"] {
    let base = apply_dispatch_snapshot(
      products_test_project(products_test_selected("moondesk")),
      {
        ..dispatch_test_snapshot(
          if state == "interrupted" {
            "interrupted"
          } else {
            "running"
          },
        ),
        product_id: "moonbook",
        report_product_id: if state == "submitted" {
          "moonbook"
        } else {
          ""
        },
        report_id: if state == "submitted" {
          "report-a"
        } else {
          ""
        },
        report_summary: if state == "submitted" {
          "Canonical report A"
        } else {
          ""
        },
        evidence_ids: ["evidence-a"],
      },
    )
    let a = {
      ..base,
      dispatch_task_selection: 17,
      dispatch_task_pending_action: if state == "loading" {
        "load"
      } else {
        ""
      },
      dispatch_task_blocked: state == "failed_read",
      dispatch_task_note: if state == "failed_read" {
        "读取任务失败：offline"
      } else {
        base.dispatch_task_note
      },
      dispatch_task_event_id: "event-a",
      dispatch_task_audit_id: "audit-a",
    }
    let b = products_test_update(a, Prepare)
    let draft = dispatch_active_draft(b).unwrap()
    assert_eq(b.page, Dispatch)
    assert_true(b.dispatch_task_form_open)
    assert_eq(draft.product_id, "moondesk")
    assert_eq(draft.project_id, "company-actual")
    assert_eq(draft.product_snapshot, products_selected(a.products))
    assert_eq(b.dispatch_task_id, "task-1")
    assert_eq(b.dispatch_task_selection, 17)
    assert_eq(b.dispatch_task_product_id, "moonbook")
    assert_eq(b.dispatch_task_stage, a.dispatch_task_stage)
    assert_eq(b.dispatch_task_pending_action, a.dispatch_task_pending_action)
    assert_eq(b.dispatch_task_note, a.dispatch_task_note)
    assert_eq(b.dispatch_task_blocked, a.dispatch_task_blocked)
    assert_eq(b.dispatch_task_title, a.dispatch_task_title)
    assert_eq(b.dispatch_task_acceptance, a.dispatch_task_acceptance)
    assert_eq(b.dispatch_task_project_id, "native-project")
    assert_eq(b.dispatch_task_workspace, "/workspace/book")
    assert_eq(b.dispatch_task_report_id, a.dispatch_task_report_id)
    assert_eq(b.dispatch_task_report_summary, a.dispatch_task_report_summary)
    assert_eq(b.dispatch_report_product_id, a.dispatch_report_product_id)
    assert_eq(b.dispatch_task_evidence_id, a.dispatch_task_evidence_id)
    assert_eq(b.dispatch_task_event_id, "event-a")
    assert_eq(b.dispatch_task_audit_id, "audit-a")
    assert_eq(b.dispatch_run, a.dispatch_run)
  }
}

///|
test "repeated Prepare resumes typed draft for exact product and project while New preserves it" {
  let typed = drafts_test_valid()
  let original = dispatch_active_draft(typed).unwrap()
  let parked = drafts_test_update(typed, Park)
  let resumed = products_test_update(parked, Prepare)
  assert_eq(resumed.dispatch_drafts, [original])
  assert_eq(resumed.dispatch_draft_id, original.id)
  assert_true(resumed.dispatch_task_form_open)
  let another = drafts_test_update(resumed, New)
  let fresh = dispatch_active_draft(another).unwrap()
  assert_eq(another.dispatch_drafts.length(), 2)
  assert_eq(dispatch_draft_by_id(another, original.id), Some(original))
  assert_true(fresh.id != original.id)
  assert_true(fresh.task_id != original.task_id)
  assert_true(fresh.idempotency_key != original.idempotency_key)
  assert_eq(fresh.product_id, original.product_id)
  assert_eq(fresh.project_id, original.project_id)
  assert_eq(fresh.product_snapshot, original.product_snapshot)
  assert_eq(fresh.title, "MoonDesk · ")
  assert_eq(fresh.acceptance, "")
  assert_eq(fresh.workspace, "")
  assert_false(fresh.attempted)
  let (_, different_project) = dispatch_prepare_draft(
    _ => none,
    another,
    "moondesk",
    "company-two",
    fresh.product_snapshot,
    false,
  )
  assert_eq(different_project.dispatch_drafts.length(), 3)
  assert_eq(
    dispatch_active_draft(different_project).unwrap().project_id,
    "company-two",
  )
  assert_eq(
    dispatch_draft_by_id(different_project, original.id),
    Some(original),
  )
}

///|
test "parking opening C and resuming B preserve both canonical and draft contexts" {
  let b = drafts_test_valid()
  let original = dispatch_active_draft(b).unwrap()
  let parked = drafts_test_update(b, Park)
  assert_false(parked.dispatch_task_form_open)
  assert_eq(parked.dispatch_draft_id, original.id)
  assert_eq(parked.products.prepared_product_id, "")
  let (_, opening) = update(_ => none, RestoreDispatchTask("task-c"), parked)
  let snapshot = {
    ..dispatch_test_snapshot("completed"),
    task_id: "task-c",
    product_id: "moonbook",
    project_id: "project-c",
    title: "Canonical C title",
    acceptance: "Canonical C acceptance",
    run: Some({ ..dispatch_test_run("completed"), task_id: "task-c", }),
  }
  let (_, c) = update(
    _ => none,
    DispatchTaskLoaded("task-c", opening.dispatch_task_selection, snapshot),
    opening,
  )
  let resumed = drafts_test_update(c, Resume(original.id))
  assert_eq(resumed.dispatch_task_id, "task-c")
  assert_eq(resumed.dispatch_task_title, "Canonical C title")
  assert_eq(resumed.dispatch_task_acceptance, "Canonical C acceptance")
  assert_eq(resumed.dispatch_task_product_id, "moonbook")
  assert_eq(resumed.dispatch_run, snapshot.run)
  assert_eq(resumed.products.prepared_product_id, "moondesk")
  assert_eq(resumed.products.prepared_project_id, "company-actual")
  assert_eq(dispatch_active_draft(resumed), Some(original))
  let form = dispatch_draft_form_model(resumed)
  assert_eq(form.dispatch_task_title, original.title)
  assert_eq(form.dispatch_task_acceptance, original.acceptance)
  assert_eq(form.dispatch_task_project_id, original.project_id)
  assert_eq(form.dispatch_task_workspace, original.workspace)
  assert_eq(form.dispatch_task_owner_id, original.owner_id)
  assert_eq(form.dispatch_task_model, original.model)
  assert_eq(form.dispatch_task_begin_date, original.begin_date)
  assert_eq(form.dispatch_task_end_date, original.end_date)
  let html = products_test_html(resumed)
  assert_true(html.contains("Canonical C title"))
  assert_true(html.contains("Deliver draft B"))
  assert_true(html.contains("/workspace/authorized-b"))
  assert_true(html.contains("href=\"?task=task-c\""))
  let cancelled = products_test_update(resumed, CancelPreparation)
  assert_eq(cancelled.page, Products)
  assert_eq(cancelled.dispatch_task_id, "task-c")
  assert_eq(cancelled.dispatch_run, snapshot.run)
  assert_eq(dispatch_draft_by_id(cancelled, original.id), Some(original))
}

///|
test "Create persists stable identity and ordinary request before the first POST" {
  drafts_test_transport(false)
  let model = drafts_test_valid()
  let original = dispatch_active_draft(model).unwrap()
  let emitted : Array[Msg] = []
  let (save, saving) = update(
    msg => {
      emitted.push(msg)
      none
    },
    DraftAction(Create),
    model,
  )
  assert_eq(dispatch_active_draft(saving).unwrap().state, "saving")
  assert_false(dispatch_active_draft(saving).unwrap().attempted)
  assert_eq(drafts_test_post_count(), 0)
  drafts_test_execute(save)
  assert_eq(drafts_test_events(), "save")
  assert_eq(emitted.length(), 1)
  assert_true(
    emitted[0] is DraftAction(Stored(actor, id, true)) &&
    actor == "actor-drafts" &&
    id == original.id,
  )
  let saved = dispatch_read_drafts("actor-drafts")
  let store : DispatchDraftStore = @json.from_json(@json.parse(saved))
  assert_eq(store.version, 1)
  assert_eq(store.drafts[0].id, original.id)
  assert_eq(store.drafts[0].task_id, original.task_id)
  assert_eq(store.drafts[0].idempotency_key, original.idempotency_key)
  assert_eq(store.drafts[0].title, original.title)
  assert_eq(store.drafts[0].acceptance, original.acceptance)
  assert_eq(store.drafts[0].workspace, original.workspace)
  assert_eq(store.recent_tasks, [original.task_id])
  for
    forbidden in [
      "\"authority\"", "\"actor_id\"", "\"headers\"", "\"cookies\"", "\"authorization\"",
      "\"credentials\"",
    ] {
    assert_false(saved.contains(forbidden))
  }
  let (post, creating) = update(_ => none, emitted[0], saving)
  assert_eq(dispatch_active_draft(creating).unwrap().state, "creating")
  assert_true(dispatch_active_draft(creating).unwrap().attempted)
  assert_eq(drafts_test_post_count(), 0)
  drafts_test_execute(post)
  assert_eq(drafts_test_events(), "save|POST /api/company/plan/tasks")
  assert_eq(drafts_test_post_count(), 1)
  let body = @json.parse(drafts_test_post_body(0))
  assert_eq(body, dispatch_draft_create_body(original, "actor-drafts"))
  assert_eq(dispatch_json_text(body, "task_id"), original.task_id)
  assert_eq(
    dispatch_json_text(body, "idempotency_key"),
    original.idempotency_key,
  )
  assert_eq(dispatch_json_text(body, "product_id"), "moondesk")
  assert_eq(dispatch_json_text(body, "project_id"), "company-actual")
  assert_eq(dispatch_json_text(body, "task_name"), "Deliver draft B")
  assert_eq(
    dispatch_json_text(body, "remarks"),
    "验收标准：Verify B's saved output",
  )
  assert_eq(
    dispatch_json_text(dispatch_json_field(body, "authority"), "actor_id"),
    "actor-drafts",
  )
  let (duplicate, unchanged) = update(
    _ => none,
    DraftAction(Stored("actor-drafts", original.id, true)),
    creating,
  )
  drafts_test_execute(duplicate)
  assert_eq(drafts_test_post_count(), 1)
  assert_eq(unchanged.dispatch_drafts, creating.dispatch_drafts)
  drafts_test_transport_cleanup()
}

///|
test "saving attempted uncertain retryable rejected and created drafts freeze all ordinary request fields" {
  let editable = drafts_test_valid()
  let original = dispatch_active_draft(editable).unwrap()
  for
    state in [
      "saving", "creating", "uncertain", "recovering", "retryable", "rejected", "created",
    ] {
    let frozen = dispatch_replace_draft(editable, {
      ..original,
      state,
      attempted: state != "saving",
    })
    let mut edited = frozen
    for
      field in [
        "title", "acceptance", "project_id", "owner_id", "workspace", "model", "begin_date",
        "end_date",
      ] {
      edited = drafts_test_update(edited, Input(field, "replacement"))
    }
    assert_eq(edited.dispatch_drafts, frozen.dispatch_drafts)
    assert_eq(
      dispatch_draft_create_body(
        dispatch_active_draft(edited).unwrap(),
        "actor-drafts",
      ),
      dispatch_draft_create_body(original, "actor-drafts"),
    )
  }
}

///|
test "actor-scoped storage cannot expose another actor collection or accept stale restore" {
  drafts_test_transport(false)
  let a = drafts_test_valid()
  let saved = dispatch_draft_store(a)
  assert_true(dispatch_write_drafts("actor/a", saved))
  assert_eq(dispatch_read_drafts("actor/a"), saved)
  assert_eq(dispatch_read_drafts("actor%2Fa"), "")
  assert_eq(dispatch_read_drafts("actor-b"), "")
  assert_false(dispatch_write_drafts("", saved))
  let (same_command, same) = update(
    _ => none,
    DispatchSessionLoaded("actor-drafts"),
    a,
  )
  assert_eq(products_test_effect_count(same_command), 0)
  assert_eq(same.dispatch_drafts, a.dispatch_drafts)
  let (_, switched) = update(_ => none, DispatchSessionLoaded("actor-b"), a)
  assert_eq(switched.dispatch_task_actor_id, "actor-b")
  assert_eq(switched.dispatch_drafts, [])
  assert_eq(switched.dispatch_draft_id, "")
  assert_eq(switched.dispatch_recent_tasks, [])
  assert_false(switched.dispatch_task_form_open)
  assert_eq(switched.products.prepared_product_id, "")
  let stale = drafts_test_update(switched, Restored("actor-drafts", saved))
  assert_eq(stale.dispatch_drafts, [])
  assert_eq(stale.dispatch_task_actor_id, "actor-b")
  let (_, signed_out) = update(_ => none, DispatchSessionLoaded(""), a)
  assert_eq(signed_out.dispatch_drafts, [])
  assert_eq(signed_out.dispatch_recent_tasks, [])
  assert_true(signed_out.dispatch_draft_storage.contains("未登录"))
  drafts_test_transport_cleanup()
}

///|
test "reload turns interrupted create phases uncertain and preserves exact immutable recovery identity" {
  let ready = drafts_test_valid()
  let draft = dispatch_active_draft(ready).unwrap()
  for state in ["saving", "creating", "recovering", "retryable"] {
    let stored = dispatch_remember_recent(
      dispatch_replace_draft(ready, { ..draft, state, }),
      draft.task_id,
    )
    let restored = drafts_test_update(
      { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
      Restored("actor-drafts", dispatch_draft_store(stored)),
    )
    let recovered = dispatch_draft_by_id(restored, draft.id).unwrap()
    assert_eq(recovered.state, "uncertain")
    assert_true(recovered.attempted)
    assert_eq(recovered.task_id, draft.task_id)
    assert_eq(recovered.idempotency_key, draft.idempotency_key)
    assert_eq(
      dispatch_draft_create_body(recovered, "actor-drafts"),
      dispatch_draft_create_body(draft, "actor-drafts"),
    )
    assert_eq(restored.dispatch_recent_tasks, [draft.task_id])
    assert_eq(restored.dispatch_task_id, "")
    assert_false(restored.dispatch_task_form_open)
    let resumed = drafts_test_update(restored, Resume(draft.id))
    let recovering = drafts_test_update(resumed, Create)
    assert_eq(dispatch_active_draft(recovering).unwrap().state, "recovering")
    assert_eq(recovering.dispatch_task_id, "")
  }
}

///|
test "reload preserves typed editing drafts and never overwrites newer in-page edits" {
  let typed = drafts_test_valid()
  let original = dispatch_active_draft(typed).unwrap()
  let saved = dispatch_draft_store(typed)
  let restored = drafts_test_update(
    { ..initial_model(), dispatch_task_actor_id: "actor-drafts", },
    Restored("actor-drafts", saved),
  )
  assert_eq(restored.dispatch_drafts, [original])
  let revised = drafts_test_update(
    typed,
    Input("title", "More recent in-page title"),
  )
  let stale = drafts_test_update(revised, Restored("actor-drafts", saved))
  assert_eq(stale.dispatch_drafts, revised.dispatch_drafts)
  let corrupt = drafts_test_update(
    revised,
    Restored("actor-drafts", "storage-unavailable"),
  )
  assert_eq(corrupt.dispatch_drafts, revised.dispatch_drafts)
  assert_true(corrupt.dispatch_draft_storage.contains("无法读取"))
}

///|
test "uncertain create recovery performs only GET for original task and authenticates exact snapshot" {
  drafts_test_transport(false)
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  let uncertain = drafts_test_update(
    creating,
    CreateRead("actor-drafts", draft.id, 0, ""),
  )
  let (get, recovering) = update(_ => none, DraftAction(Create), uncertain)
  drafts_test_execute(get)
  assert_eq(drafts_test_post_count(), 0)
  assert_eq(
    drafts_test_events(),
    "GET /api/company/tasks/" + dispatch_url_encode(draft.task_id),
  )
  assert_eq(dispatch_active_draft(recovering).unwrap().state, "recovering")
  let confirmed = drafts_test_update(
    recovering,
    RecoveryRead(
      "actor-drafts",
      draft.id,
      200,
      drafts_test_snapshot_body(draft.task_id),
    ),
  )
  assert_eq(dispatch_draft_by_id(confirmed, draft.id).unwrap().state, "created")
  assert_eq(confirmed.dispatch_task_id, draft.task_id)
  assert_eq(confirmed.dispatch_task_stage, "loading")
  assert_false(confirmed.dispatch_task_form_open)
  assert_eq(confirmed.dispatch_recent_tasks, [draft.task_id])
  assert_eq(drafts_test_post_count(), 0)
  drafts_test_transport_cleanup()
}

///|
test "only exact recovery 404 permits same ID and same idempotency key retry" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  let uncertain = drafts_test_update(
    creating,
    CreateRead("actor-drafts", draft.id, 503, ""),
  )
  let recovering = drafts_test_update(uncertain, Recover(draft.id))
  for status in [0, 200, 401, 403, 409, 429, 500, 503] {
    let failed = drafts_test_update(
      recovering,
      RecoveryRead(
        "actor-drafts",
        draft.id,
        status,
        drafts_test_snapshot_body("wrong-task"),
      ),
    )
    assert_eq(dispatch_active_draft(failed).unwrap().state, "uncertain")
    assert_eq(failed.dispatch_task_id, "")
    let retry = drafts_test_update(failed, Create)
    assert_eq(dispatch_active_draft(retry).unwrap().state, "recovering")
    assert_eq(dispatch_active_draft(retry).unwrap().task_id, draft.task_id)
  }
  let missing = drafts_test_update(
    recovering,
    RecoveryRead("actor-drafts", draft.id, 404, "{\"error\":\"not found\"}"),
  )
  assert_eq(dispatch_active_draft(missing).unwrap().state, "retryable")
  let frozen = drafts_test_update(
    missing,
    Input("title", "Cannot mutate retry"),
  )
  assert_eq(dispatch_active_draft(frozen).unwrap().title, draft.title)
  let saving = drafts_test_update(frozen, Create)
  assert_eq(dispatch_active_draft(saving).unwrap().state, "saving")
  let retrying = drafts_test_update(
    saving,
    Stored("actor-drafts", draft.id, true),
  )
  let retried = dispatch_active_draft(retrying).unwrap()
  assert_eq(retried.state, "creating")
  assert_eq(retried.task_id, draft.task_id)
  assert_eq(retried.idempotency_key, draft.idempotency_key)
  assert_eq(
    dispatch_draft_create_body(retried, "actor-drafts"),
    dispatch_draft_create_body(draft, "actor-drafts"),
  )
}

///|
test "lost malformed mismatched and auth Create receipts remain uncertain without automatic new identity" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  for
    (status, body) in [
      (0, ""),
      (201, "{}"),
      (200, drafts_test_receipt("wrong-task")),
      (401, "{\"error\":\"login required\"}"),
      (403, "{}"),
      (409, "{}"),
      (429, "{}"),
      (500, "{}"),
      (503, "{}"),
    ] {
    let uncertain = drafts_test_update(
      creating,
      CreateRead("actor-drafts", draft.id, status, body),
    )
    let retained = dispatch_active_draft(uncertain).unwrap()
    assert_eq(retained.state, "uncertain")
    assert_eq(retained.task_id, draft.task_id)
    assert_eq(retained.idempotency_key, draft.idempotency_key)
    assert_eq(uncertain.dispatch_drafts.length(), 1)
    assert_eq(uncertain.dispatch_task_id, "")
    let discard = drafts_test_update(uncertain, Discard(draft.id))
    assert_eq(discard.dispatch_drafts, uncertain.dispatch_drafts)
    assert_true(discard.notice.contains("先按保留的任务 ID"))
  }
}

///|
test "duplicate Create success receipt never reopens or reselects an already confirmed task" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  let receipt = CreateRead(
    "actor-drafts",
    draft.id,
    201,
    drafts_test_receipt(draft.task_id),
  )
  let confirmed = drafts_test_update(creating, receipt)
  assert_eq(dispatch_draft_by_id(confirmed, draft.id).unwrap().state, "created")
  assert_eq(confirmed.dispatch_task_id, draft.task_id)
  let selection = confirmed.dispatch_task_selection
  let (command, duplicate) = update(_ => none, DraftAction(receipt), confirmed)
  assert_eq(products_test_effect_count(command), 0)
  assert_eq(duplicate.dispatch_task_selection, selection)
  assert_eq(duplicate.dispatch_recent_tasks, [draft.task_id])
  let (_, c) = update(_ => none, RestoreDispatchTask("task-c"), confirmed)
  let stale = drafts_test_update(c, receipt)
  assert_eq(stale.dispatch_task_id, "task-c")
  assert_eq(stale.dispatch_task_selection, c.dispatch_task_selection)
  assert_eq(stale.dispatch_recent_tasks, c.dispatch_recent_tasks)
}

///|
test "stale actor draft and phase receipts cannot change a different live draft" {
  let creating = drafts_test_creating()
  let a = dispatch_active_draft(creating).unwrap()
  let b = drafts_test_update(creating, New)
  let draft_b = dispatch_active_draft(b).unwrap()
  for
    action in [
      Stored("wrong-actor", a.id, true),
      CreateRead("wrong-actor", a.id, 201, drafts_test_receipt(a.task_id)),
      RecoveryRead(
        "wrong-actor",
        a.id,
        200,
        drafts_test_snapshot_body(a.task_id),
      ),
      CreateRead(
        "actor-drafts",
        "missing-draft",
        201,
        drafts_test_receipt(a.task_id),
      ),
      RecoveryRead("actor-drafts", "missing-draft", 404, ""),
      CreateRead(
        "actor-drafts",
        draft_b.id,
        201,
        drafts_test_receipt(draft_b.task_id),
      ),
      RecoveryRead("actor-drafts", a.id, 404, ""),
    ] {
    let (command, unchanged) = update(_ => none, DraftAction(action), b)
    assert_eq(products_test_effect_count(command), 0)
    assert_eq(unchanged.dispatch_drafts, b.dispatch_drafts)
    assert_eq(unchanged.dispatch_draft_id, draft_b.id)
    assert_eq(unchanged.dispatch_task_id, b.dispatch_task_id)
    assert_eq(unchanged.dispatch_task_selection, b.dispatch_task_selection)
  }
  let (missing, unchanged) = update(
    _ => none,
    DraftAction(Stored("actor-drafts", "missing-draft", true)),
    b,
  )
  assert_eq(products_test_effect_count(missing), 0)
  assert_eq(unchanged.dispatch_drafts, b.dispatch_drafts)
}

///|
test "late B create while C is selected confirms B without stealing C focus or its open draft" {
  let b = drafts_test_creating()
  let draft_b = dispatch_active_draft(b).unwrap()
  let (_, opening_c) = update(_ => none, RestoreDispatchTask("task-c"), b)
  let snapshot_c = {
    ..dispatch_test_snapshot("interrupted"),
    task_id: "task-c",
    product_id: "moonbook",
    run: Some({ ..dispatch_test_run("interrupted"), task_id: "task-c", }),
  }
  let (_, c) = update(
    _ => none,
    DispatchTaskLoaded("task-c", opening_c.dispatch_task_selection, snapshot_c),
    opening_c,
  )
  for current in [c, drafts_test_update(c, New)] {
    let completed_b = drafts_test_update(
      current,
      CreateRead(
        "actor-drafts",
        draft_b.id,
        201,
        drafts_test_receipt(draft_b.task_id),
      ),
    )
    assert_eq(
      dispatch_draft_by_id(completed_b, draft_b.id).unwrap().state,
      "created",
    )
    assert_eq(completed_b.dispatch_task_id, "task-c")
    assert_eq(
      completed_b.dispatch_task_selection,
      current.dispatch_task_selection,
    )
    assert_eq(completed_b.dispatch_run, current.dispatch_run)
    assert_eq(completed_b.dispatch_task_product_id, "moonbook")
    assert_eq(completed_b.dispatch_draft_id, current.dispatch_draft_id)
    assert_eq(
      completed_b.dispatch_task_form_open,
      current.dispatch_task_form_open,
    )
    assert_true(completed_b.dispatch_recent_tasks.contains(draft_b.task_id))
    assert_true(completed_b.dispatch_recent_tasks.contains("task-c"))
  }
}

///|
test "late selected task reads update canonical context without repopulating an independent draft" {
  let (_, opening_a) = update(
    _ => none,
    RestoreDispatchTask("task-1"),
    drafts_test_valid(),
  )
  let draft = dispatch_active_draft(opening_a).unwrap()
  let composing = drafts_test_update(opening_a, Resume(draft.id))
  let a = { ..dispatch_test_snapshot("completed"), product_id: "moonbook", }
  let (_, loaded) = update(
    _ => none,
    DispatchTaskLoaded("task-1", composing.dispatch_task_selection, a),
    composing,
  )
  assert_eq(loaded.dispatch_run, a.run)
  assert_eq(dispatch_active_draft(loaded), Some(draft))
  assert_true(loaded.dispatch_task_form_open)
  assert_eq(loaded.products.prepared_product_id, "moondesk")
  let (_, opening_c) = update(_ => none, RestoreDispatchTask("task-c"), loaded)
  let resumed = drafts_test_update(opening_c, Resume(draft.id))
  let (_, stale_read) = update(
    _ => none,
    DispatchTaskLoaded("task-1", composing.dispatch_task_selection, a),
    resumed,
  )
  let (_, stale_failure) = update(
    _ => none,
    DispatchTaskCommandFailed(
      "task-1",
      composing.dispatch_task_selection,
      "读取任务",
      "late failure",
    ),
    stale_read,
  )
  let (_, stale_report) = update(
    _ => none,
    DispatchTaskSubmitted(
      "task-1",
      composing.dispatch_task_selection,
      "old-report",
      "event",
      "audit",
    ),
    stale_failure,
  )
  assert_eq(stale_report.dispatch_task_id, "task-c")
  assert_eq(stale_report.dispatch_task_pending_action, "load")
  assert_eq(stale_report.dispatch_run, None)
  assert_eq(stale_report.dispatch_task_report_id, "")
  assert_eq(stale_report.dispatch_task_note, resumed.dispatch_task_note)
  assert_eq(dispatch_active_draft(stale_report), Some(draft))
}

///|
test "canonical retag readback displays task product separately from the historical report snapshot" {
  let response = "{\"data\":{\"task\":{\"taskGuid\":\"task-1\",\"product_id\":\"moondesk\",\"projGuid\":\"company-shared\",\"taskName\":\"Retagged delivery\",\"status\":\"in_progress\"},\"reports\":[{\"reportGuid\":\"report-old-product\",\"product_id\":\"moonbook\",\"summary\":\"Report keeps its original product snapshot\",\"evidence_ids\":[\"artifact-original\"]}]}}"
  let snapshot = dispatch_decode_snapshot(response, "task-1").unwrap()
  assert_eq(snapshot.product_id, "moondesk")
  assert_eq(snapshot.report_product_id, "moonbook")
  let loaded = apply_dispatch_snapshot(
    { ..drafts_test_valid(), dispatch_task_id: "task-1", },
    snapshot,
  )
  assert_eq(loaded.dispatch_task_product_id, "moondesk")
  assert_eq(loaded.dispatch_report_product_id, "moonbook")
  assert_eq(loaded.dispatch_task_stage, "submitted")
  assert_eq(loaded.dispatch_task_report_id, "report-old-product")
  assert_eq(loaded.dispatch_task_evidence_id, "artifact-original")
  assert_eq(dispatch_active_draft(loaded).unwrap().product_id, "moondesk")
  let html = products_test_html(loaded)
  assert_true(html.contains("产品 · MoonDesk (moondesk)"))
  assert_true(html.contains("创建时产品 · MoonBook (moonbook)"))
  assert_true(html.contains("report-old-product"))
}

///|
test "legacy null product stays unassigned despite a selected product and prepared draft" {
  let response = "{\"data\":{\"task\":{\"taskGuid\":\"legacy-task\",\"product_id\":null,\"projGuid\":\"company-actual\",\"taskName\":\"Legacy unassigned task\",\"status\":\"in_progress\"},\"reports\":[{\"reportGuid\":\"legacy-report\",\"product_id\":null,\"summary\":\"Legacy result\",\"evidence_ids\":[\"legacy-output\"]}]}}"
  let original = drafts_test_valid()
  let draft = dispatch_active_draft(original).unwrap()
  let loaded = apply_dispatch_snapshot(
    original,
    dispatch_decode_snapshot(response, "legacy-task").unwrap(),
  )
  assert_eq(loaded.dispatch_task_product_id, "")
  assert_eq(loaded.dispatch_report_product_id, "")
  assert_eq(
    dispatch_product_label(loaded, loaded.dispatch_task_product_id),
    "未关联",
  )
  assert_eq(dispatch_active_draft(loaded), Some(draft))
  assert_eq(loaded.products.prepared_product_id, "moondesk")
  let html = products_test_html(loaded)
  assert_true(html.contains("产品 · 未关联"))
  assert_true(html.contains("创建时产品 · 未关联"))
  let generic = { ..draft, product_id: "", product_snapshot: None, }
  assert_eq(
    dispatch_json_field(
      dispatch_draft_create_body(generic, "actor-drafts"),
      "product_id",
    ),
    Json::null(),
  )
}

///|
test "storage failure stays visibly editable and sends no POST before any attempted request" {
  drafts_test_transport(true)
  let ready = drafts_test_valid()
  let original = dispatch_active_draft(ready).unwrap()
  let emitted : Array[Msg] = []
  let (save, saving) = update(
    msg => {
      emitted.push(msg)
      none
    },
    DraftAction(Create),
    ready,
  )
  drafts_test_execute(save)
  assert_eq(emitted.length(), 1)
  assert_true(
    emitted[0] is DraftAction(Stored(actor, id, false)) &&
    actor == "actor-drafts" &&
    id == original.id,
  )
  let (no_post, failed) = update(_ => none, emitted[0], saving)
  drafts_test_execute(no_post)
  assert_eq(drafts_test_post_count(), 0)
  assert_eq(drafts_test_events(), "save-failed")
  let retained = dispatch_active_draft(failed).unwrap()
  assert_eq(retained.state, "editing")
  assert_false(retained.attempted)
  assert_eq(retained.task_id, original.task_id)
  assert_eq(retained.idempotency_key, original.idempotency_key)
  assert_eq(failed.dispatch_task_id, "")
  let html = products_test_html(failed)
  assert_true(html.contains("草稿未保存到此浏览器"))
  assert_true(html.contains("本地保存失败"))
  assert_true(html.contains("本次尚未发送创建"))
  assert_true(html.contains(original.task_id))
  let editable = drafts_test_update(
    failed,
    Input("title", "Correct before first POST"),
  )
  assert_eq(
    dispatch_active_draft(editable).unwrap().title,
    "Correct before first POST",
  )
  drafts_test_transport_cleanup()
}

///|
test "storage failure before an attempted retry keeps the same immutable retryable request" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  let retryable = dispatch_replace_draft(creating, {
    ..draft,
    state: "retryable",
  })
  let saving = drafts_test_update(retryable, Create)
  let (no_post, failed) = update(
    _ => none,
    DraftAction(Stored("actor-drafts", draft.id, false)),
    saving,
  )
  assert_eq(products_test_effect_count(no_post), 0)
  let retained = dispatch_active_draft(failed).unwrap()
  assert_eq(retained.state, "retryable")
  assert_true(retained.attempted)
  assert_eq(retained.task_id, draft.task_id)
  assert_eq(retained.idempotency_key, draft.idempotency_key)
  let ignored = drafts_test_update(
    failed,
    Input("title", "Cannot change attempted request"),
  )
  assert_eq(dispatch_active_draft(ignored), Some(retained))
}

///|
test "definitive 400 and 422 rejection requires explicit Revise with new identity and preserved old request" {
  let creating = drafts_test_creating()
  let original = dispatch_active_draft(creating).unwrap()
  for status in [400, 422] {
    let rejected = drafts_test_update(
      creating,
      CreateRead(
        "actor-drafts",
        original.id,
        status,
        "{\"error\":\"invalid acceptance\"}",
      ),
    )
    let retained = dispatch_active_draft(rejected).unwrap()
    assert_eq(retained.state, "rejected")
    assert_true(retained.attempted)
    assert_true(retained.note.contains("invalid acceptance"))
    assert_eq(retained.task_id, original.task_id)
    assert_eq(retained.idempotency_key, original.idempotency_key)
    assert_eq(rejected.dispatch_task_id, "")
    let (no_post, unchanged) = update(_ => none, DraftAction(Create), rejected)
    assert_eq(products_test_effect_count(no_post), 0)
    assert_eq(unchanged.dispatch_drafts, rejected.dispatch_drafts)
    assert_true(products_test_html(rejected).contains("修订为新草稿"))
    let revised = drafts_test_update(rejected, Revise(original.id))
    let replacement = dispatch_active_draft(revised).unwrap()
    assert_eq(revised.dispatch_drafts.length(), 2)
    assert_eq(dispatch_draft_by_id(revised, original.id), Some(retained))
    assert_true(replacement.id != original.id)
    assert_true(replacement.task_id != original.task_id)
    assert_true(replacement.idempotency_key != original.idempotency_key)
    assert_eq(replacement.state, "editing")
    assert_false(replacement.attempted)
    assert_eq(replacement.product_id, original.product_id)
    assert_eq(replacement.product_snapshot, original.product_snapshot)
    assert_eq(replacement.project_id, original.project_id)
    assert_eq(replacement.title, original.title)
    assert_eq(replacement.acceptance, original.acceptance)
    assert_eq(replacement.workspace, original.workspace)
    assert_eq(replacement.owner_id, original.owner_id)
    assert_eq(replacement.model, original.model)
    assert_eq(replacement.begin_date, original.begin_date)
    assert_eq(replacement.end_date, original.end_date)
    assert_true(revised.dispatch_recent_tasks.contains(original.task_id))
    let corrected = drafts_test_update(
      revised,
      Input("acceptance", "Corrected acceptance"),
    )
    assert_eq(
      dispatch_active_draft(corrected).unwrap().acceptance,
      "Corrected acceptance",
    )
    assert_eq(dispatch_draft_by_id(corrected, original.id), Some(retained))
  }
}

///|
test "Revise cannot bypass uncertainty and completed draft Resume opens exact canonical task" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  for
    state in [
      "editing", "saving", "creating", "uncertain", "recovering", "retryable", "created",
    ] {
    let model = dispatch_replace_draft(creating, { ..draft, state, })
    let (command, unchanged) = update(
      _ => none,
      DraftAction(Revise(draft.id)),
      model,
    )
    assert_eq(products_test_effect_count(command), 0)
    assert_eq(unchanged.dispatch_drafts, model.dispatch_drafts)
  }
  let completed = dispatch_replace_draft(creating, {
    ..draft,
    state: "created",
  })
  let opened = drafts_test_update(completed, Resume(draft.id))
  assert_eq(opened.dispatch_task_id, draft.task_id)
  assert_eq(opened.dispatch_task_stage, "loading")
  assert_false(opened.dispatch_task_form_open)
  assert_eq(opened.products.prepared_product_id, "")
  assert_eq(dispatch_draft_by_id(opened, draft.id).unwrap().state, "created")
}

///|
test "active-project service409 is distinct from ambiguous identity conflicts and retries" {
  let creating = drafts_test_creating()
  let draft = dispatch_active_draft(creating).unwrap()
  let body = "{\"error\":\"project-plan task requires an active project identity\"}"
  let rejected = drafts_test_update(
    creating,
    CreateRead("actor-drafts", draft.id, 409, body),
  )
  assert_eq(dispatch_active_draft(rejected).unwrap().state, "rejected")
  let revised = drafts_test_update(rejected, Revise(draft.id))
  let changed = drafts_test_update(
    revised,
    Input("project_id", "company-other"),
  )
  assert_eq(dispatch_active_draft(changed).unwrap().project_id, "company-other")
  assert_true(dispatch_active_draft(changed).unwrap().task_id != draft.task_id)
  let lost = drafts_test_update(
    creating,
    CreateRead("actor-drafts", draft.id, 0, ""),
  )
  let recovering = drafts_test_update(lost, Recover(draft.id))
  let retryable = drafts_test_update(
    recovering,
    RecoveryRead("actor-drafts", draft.id, 404, "{}"),
  )
  let saving = drafts_test_update(retryable, Create)
  let retry = drafts_test_update(saving, Stored("actor-drafts", draft.id, true))
  for status in [400, 409, 422] {
    let still_unknown = drafts_test_update(
      retry,
      CreateRead("actor-drafts", draft.id, status, body),
    )
    assert_eq(dispatch_active_draft(still_unknown).unwrap().state, "uncertain")
    let denied_revision = drafts_test_update(still_unknown, Revise(draft.id))
    assert_eq(denied_revision.dispatch_drafts.length(), 1)
  }
}

///|
test "repeated preparation prefers current second draft without replacing first" {
  let first = drafts_test_update(
    drafts_test_prepared(),
    Input("title", "First draft"),
  )
  let original = dispatch_active_draft(first).unwrap()
  let second = drafts_test_update(
    drafts_test_update(first, New),
    Input("title", "Second draft"),
  )
  let newer = dispatch_active_draft(second).unwrap()
  let prepared = products_test_update(second, Prepare)
  assert_eq(dispatch_active_draft(prepared), Some(newer))
  assert_eq(dispatch_draft_by_id(prepared, original.id), Some(original))
  assert_eq(prepared.dispatch_drafts.length(), 2)
}
