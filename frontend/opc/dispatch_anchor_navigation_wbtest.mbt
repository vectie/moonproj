///|
// In-memory browser/HTTP fixture: callbacks are explicitly released after the
// URL changes. No listener, network request, or browser process is started.
extern "js" fn anchor_test_browser(page : String, run : () -> Bool) -> Bool =
  #| (page, run) => {
  #|   const prior = {window: globalThis.window, location: globalThis.location, fetch: globalThis.fetch, localStorage: globalThis.localStorage};
  #|   const state = globalThis.__anchorNavigationTest = {pending: [], requests: [], assigned: '', listeners: []};
  #|   const storage = new Map();
  #|   globalThis.location = {href: page, assign: url => {state.assigned = url;}};
  #|   globalThis.localStorage = {getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key)};
  #|   globalThis.window = {
  #|     location: globalThis.location, localStorage: globalThis.localStorage,
  #|     addEventListener: (kind, callback) => {if (kind === 'popstate') state.listeners.push(callback);},
  #|     history: {pushState: (_, __, url) => {globalThis.location.href = String(url);}, replaceState: (_, __, url) => {globalThis.location.href = String(url);}}
  #|   };
  #|   globalThis.fetch = (url, config) => {
  #|     state.requests.push((config?.method || 'GET') + ' ' + url);
  #|     return {then: callback => {state.pending.push(callback); return {catch: () => {}};}};
  #|   };
  #|   try { return run(); } finally {
  #|     for (const key of ['window', 'location', 'fetch', 'localStorage']) {
  #|       if (prior[key] === undefined) delete globalThis[key]; else globalThis[key] = prior[key];
  #|     }
  #|     delete globalThis.__anchorNavigationTest;
  #|   }
  #| }

///|
extern "js" fn anchor_test_move(page : String) =
  #| page => {globalThis.location.href = page;}

///|
extern "js" fn anchor_test_pop(page : String) =
  #| page => {globalThis.location.href = page; globalThis.__anchorNavigationTest.listeners.forEach(callback => callback({type:'popstate'}));}

///|
extern "js" fn anchor_test_respond(body : String) =
  #| body => {globalThis.__anchorNavigationTest.pending.shift()({text: () => ({then: callback => callback(body)})});}

///|
extern "js" fn anchor_test_requests() -> String =
  #| () => globalThis.__anchorNavigationTest.requests.join('|')

///|
extern "js" fn anchor_test_assigned() -> String =
  #| () => globalThis.__anchorNavigationTest.assigned

///|
fn anchor_test_ack(model : Model) -> String {
  (
    {
      "schema": "moonproj.task-continuations.v1",
      "task_id": "task-1",
      "acceptance": "pending",
      "inspection_only": false,
      "idempotent_replay": false,
      "operation_applied": true,
      "operation_idempotency_key": dispatch_json_field(
        model.dispatch_continuation.operation,
        "idempotency_key",
      ),
      "operation_source": continuation_proj_source(),
      "continuations": ToJson::to_json(model.dispatch_continuation.records),
      "selected_delivery_source": continuation_proj_source(),
      "task": {
        "taskGuid": "task-1",
        "execution": {
          "run_id": "run-1",
          "command_id": "command-1",
          "session_id": "session-1",
        },
      },
    } : Json).stringify()
}

///|
test "guided anchors preserve delayed selection storage attach and canonical readback" {
  let page = "https://proj.example/dispatch?task=task-1&keep=%23value"
  assert_true(
    anchor_test_browser(page, () => {
      let emitted : Array[Msg] = []
      let emit : @rabbita.Emit[Msg] = msg => {
        emitted.push(msg)
        none
      }
      drafts_test_execute(dispatch_history_listener(emit))
      let (store, saving) = dispatch_continuation_update(
        emit,
        Select,
        continuation_proj_model(),
      )
      drafts_test_execute(store)
      anchor_test_pop(page + "#dispatch-task-workspace")
      let (post, attaching) = update(emit, emitted[0], saving)
      if attaching.dispatch_continuation.phase != "attaching" {
        return false
      }
      drafts_test_execute(post)
      anchor_test_pop(page + "#dispatch-draft")
      anchor_test_respond(anchor_test_ack(attaching))
      let (settle, recovering) = update(emit, emitted[1], attaching)
      drafts_test_execute(settle)
      if recovering.dispatch_continuation.phase != "recovering" ||
        recovering.dispatch_continuation.operation_pending ||
        recovering.dispatch_continuation.selected != continuation_proj_source() {
        return false
      }
      let (read, loading) = update(emit, emitted[2], recovering)
      drafts_test_execute(read)
      anchor_test_pop(page + "#dispatch-learning")
      anchor_test_respond(
        continuation_proj_envelope(
          loading,
          continuation_proj_source(),
          continuation_proj_record(),
        ),
      )
      let (_, ready) = update(emit, emitted[3], loading)
      ready.dispatch_continuation.phase == "ready" &&
      !ready.dispatch_continuation.operation_pending &&
      ready.dispatch_continuation.selected == continuation_proj_source() &&
      ready.dispatch_continuation.operation ==
      saving.dispatch_continuation.operation &&
      anchor_test_requests() ==
      "POST /api/company/plan/tasks/task-1/continuations|GET /api/company/tasks/task-1/continuations"
    }),
  )
}

///|
test "guided anchors keep an unconfirmed attach retryable with its original operation" {
  let page = "https://proj.example/?task=task-1"
  assert_true(
    anchor_test_browser(page, () => {
      let emitted : Array[Msg] = []
      let emit : @rabbita.Emit[Msg] = msg => {
        emitted.push(msg)
        none
      }
      let model = continuation_proj_model()
      let (store, saving) = dispatch_continuation_update(emit, Select, {
        ..model,
        dispatch_continuation: {
          ..model.dispatch_continuation,
          preview_command: "C1",
        },
      })
      drafts_test_execute(store)
      let (post, attaching) = update(emit, emitted[0], saving)
      drafts_test_execute(post)
      anchor_test_move(page + "#dispatch-task-workspace")
      anchor_test_respond("{\"error\":\"Please retry\"}")
      let (_, recovering) = update(emit, emitted[1], attaching)
      if emitted.length() != 3 ||
        recovering.dispatch_continuation.phase != "recovering" {
        return false
      }
      let (read, loading) = update(emit, emitted[2], recovering)
      drafts_test_execute(read)
      anchor_test_respond(
        continuation_proj_envelope(
          loading,
          Json::null(),
          continuation_proj_record(),
        ),
      )
      let (_, ready) = update(emit, emitted[3], loading)
      let (_, retry) = dispatch_continuation_update(emit, Select, ready)
      recovering.dispatch_continuation.phase == "recovering" &&
      ready.dispatch_continuation.phase == "ready" &&
      ready.dispatch_continuation.error.contains("Please retry") &&
      retry.dispatch_continuation.phase == "saving" &&
      retry.dispatch_continuation.operation_pending &&
      retry.dispatch_continuation.operation ==
      saving.dispatch_continuation.operation
    }),
  )
}

///|
test "anchor history after task push or replace preserves state and real Back Forward still restore" {
  let page = "https://proj.example/dispatch?task=task-1"
  assert_true(
    anchor_test_browser(page, () => {
      let emitted : Array[Msg] = []
      drafts_test_execute(
        dispatch_history_listener(msg => {
          emitted.push(msg)
          none
        }),
      )
      anchor_test_pop(page + "#dispatch-task-workspace")
      anchor_test_pop(page + "#dispatch-task-workspace")
      if emitted.length() != 0 {
        return false
      }
      dispatch_store_task("task-2", true)
      let second = dispatch_handoff_current_page().split("#").to_array()[0].to_owned()
      anchor_test_pop(second + "#dispatch-learning")
      anchor_test_pop(second + "#dispatch-task-workspace")
      anchor_test_pop(second + "#dispatch-learning")
      if emitted.length() != 0 {
        return false
      }
      anchor_test_pop(page + "#dispatch-task-workspace")
      anchor_test_pop(second + "#dispatch-learning")
      if emitted.length() != 2 ||
        !(emitted[0] is RestoreDispatchTask("task-1")) ||
        !(emitted[1] is RestorePageRoute(Dispatch, "task-2")) {
        return false
      }
      dispatch_store_task("task-3", false)
      let third = dispatch_handoff_current_page().split("#").to_array()[0].to_owned()
      anchor_test_pop(third)
      if emitted.length() != 2 {
        return false
      }
      anchor_test_pop(third + "&view=other#dispatch-draft")
      anchor_test_pop("https://proj.example/dispatch#dispatch-draft")
      anchor_test_pop("https://proj.example/other#dispatch-draft")
      anchor_test_pop("https://other.example/other#dispatch-draft")
      emitted.length() == 6 &&
      emitted[2] is RestorePageRoute(Dispatch, "task-3") &&
      emitted[3] is RestoreDispatchTask("") &&
      emitted[4] is RestoreDispatchTask("") &&
      emitted[5] is RestoreDispatchTask("")
    }),
  )
}

///|
test "fragment comparison keeps origin path query and encoded fragment bytes strict" {
  let page = "https://proj.example/dispatch?task=task-1&keep=%23value#old"
  for
    current in [
      "https://proj.example/dispatch?task=task-1&keep=%23value", "https://proj.example/dispatch?task=task-1&keep=%23value#",
      "https://proj.example/dispatch?task=task-1&keep=%23value#dispatch-task-workspace",
    ] {
    assert_true(
      anchor_test_browser(current, () => {
        dispatch_continuation_page_matches(page)
      }),
    )
  }
  for
    current in [
      "http://proj.example/dispatch?task=task-1&keep=%23value#old", "https://other.example/dispatch?task=task-1&keep=%23value#old",
      "https://proj.example:8443/dispatch?task=task-1&keep=%23value#old", "https://proj.example/other?task=task-1&keep=%23value#old",
      "https://proj.example/dispatch?task=other&keep=%23value#old", "https://proj.example/dispatch?task=task-1&keep=%23other#old",
      "https://proj.example/dispatch?keep=%23value&task=task-1#old",
    ] {
    assert_false(
      anchor_test_browser(current, () => {
        dispatch_continuation_page_matches(page)
      }),
    )
  }
}

///|
fn anchor_test_stale_responses(model : Model, page : String) -> Bool {
  for phase in ["saving", "attaching", "loading"] {
    let pending = {
      ..model,
      dispatch_continuation: { ..model.dispatch_continuation, phase, },
    }
    let action = match phase {
      "saving" => SelectionStored("task-1", 3, 1, page, true)
      "attaching" =>
        Attached("task-1", 3, 1, page, Ok(anchor_test_ack(pending)))
      _ =>
        Loaded(
          "task-1",
          3,
          1,
          page,
          "",
          Ok(
            continuation_proj_envelope(
              pending,
              continuation_proj_source(),
              continuation_proj_record(),
            ),
          ),
        )
    }
    let emitted : Array[Msg] = []
    let (_, unchanged) = dispatch_continuation_update(
      msg => {
        emitted.push(msg)
        none
      },
      action,
      pending,
    )
    if unchanged.dispatch_continuation.phase != phase ||
      unchanged.dispatch_continuation.selected !=
      pending.dispatch_continuation.selected ||
      unchanged.dispatch_continuation.operation_pending !=
      pending.dispatch_continuation.operation_pending ||
      emitted.length() != 0 {
      return false
    }
  }
  true
}

///|
test "real navigation and changed actor task selection request still reject delayed callbacks" {
  let page = "https://proj.example/dispatch?task=task-1"
  let (_, saving) = dispatch_continuation_update(
    _ => none,
    Select,
    continuation_proj_model(),
  )
  for
    current in [
      "https://other.example/dispatch?task=task-1#dispatch-task-workspace", "https://proj.example/other?task=task-1#dispatch-task-workspace",
      "https://proj.example/dispatch?task=other#dispatch-task-workspace", "https://proj.example/dispatch?task=task-1&view=other#dispatch-task-workspace",
    ] {
    assert_true(
      anchor_test_browser(current, () => {
        anchor_test_stale_responses(saving, page)
      }),
    )
  }
  for
    changed in [
      { ..saving, page: Overview, },
      { ..saving, dispatch_task_actor_id: "other-actor", },
      { ..saving, dispatch_task_id: "other-task", },
      { ..saving, dispatch_task_selection: 4, },
      {
        ..saving,
        dispatch_continuation: { ..saving.dispatch_continuation, request: 2, },
      },
    ] {
    assert_true(
      anchor_test_browser(page + "#dispatch-task-workspace", () => {
        anchor_test_stale_responses(changed, page)
      }),
    )
  }
}

///|
test "delayed desk handoff navigates after guided anchor but never after a real URL change" {
  let page = "https://proj.example/dispatch?task=task-1&keep=%23value"
  for
    current in [
      page + "#dispatch-task-workspace",
      "https://other.example/dispatch?task=task-1&keep=%23value#dispatch-task-workspace",
      "https://proj.example/other?task=task-1&keep=%23value#dispatch-task-workspace",
      "https://proj.example/dispatch?task=other&keep=%23value#dispatch-task-workspace",
      page + "&changed=1#dispatch-task-workspace",
    ] {
    assert_true(
      anchor_test_browser(page, () => {
        let emitted : Array[Msg] = []
        let emit : @rabbita.Emit[Msg] = msg => {
          emitted.push(msg)
          none
        }
        let (read, loading) = dispatch_desk_handoff_update(
          emit,
          Open,
          continuation_proj_model(),
        )
        drafts_test_execute(read)
        anchor_test_move(current)
        anchor_test_respond(handoff_proj_fixture())
        let (navigate, ready) = update(emit, emitted[0], loading)
        drafts_test_execute(navigate)
        !ready.dispatch_desk_handoff.pending &&
        ready.dispatch_desk_handoff.error == "" &&
        anchor_test_assigned().has_prefix("https://desk.example:8443/?") ==
        (current == page + "#dispatch-task-workspace") &&
        anchor_test_requests() == "GET /api/company/tasks/task-1/desk-handoff"
      }),
    )
  }
}
