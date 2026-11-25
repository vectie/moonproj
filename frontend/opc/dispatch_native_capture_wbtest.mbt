///|
// Captured canonical GET from actual MoonProj gateway and MoonClaw cold reload.
// Company persistence and model transport were deterministic local fixtures; no provider call.
// Source: feature-audit/dispatch-bridge/integration/roundtrip-01/08-cold-reload.json
// Captured file SHA256: 58cf7bc95a9cc4a9cbac9dee9bda9acdf27c63c4e440fe7462bf379156b267c4
#warnings("-alert_unstable")
test "actual native cold readback restores exact result and file without human acceptance" {
  let response =
    #| {
    #|   "data": {
    #|     "task": {
    #|       "taskGuid": "dispatch-note",
    #|       "projGuid": "dispatch-project",
    #|       "taskName": "Create a welcome note",
    #|       "remarks": "Write welcome-note.txt with exactly this content: Welcome to the native dispatch verification.\nThen report: The welcome note is ready: welcome-note.txt",
    #|       "sourceKind": "command",
    #|       "status": "in_progress",
    #|       "revision": 10,
    #|       "execution_workspace": "/workspace/scratch/665adc5202cf/feature-audit/dispatch-bridge/integration/roundtrip-01/workspace",
    #|       "execution_model": "moongate/dispatch-fixture",
    #|       "execution": {
    #|         "run_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f",
    #|         "task_id": "dispatch-note",
    #|         "session_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f",
    #|         "command_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start",
    #|         "workspace": "/workspace/scratch/665adc5202cf/feature-audit/dispatch-bridge/integration/roundtrip-01/workspace",
    #|         "model": "moongate/dispatch-fixture",
    #|         "state": "completed",
    #|         "summary": "The welcome note is ready: welcome-note.txt",
    #|         "error": "",
    #|         "evidence_ids": [
    #|           "moonclaw:mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f:journal:18",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-command.queued_for_runtime_turn-1790925107842",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.turn_started-1790925107876",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.planner_started-1790925107879",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.planner_selected-1790925107879",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-planner-step-1-1790925108001",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-tool-call-1-0-write-1790925108001",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-tool-write-1790925108013",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-continuation-after-step-0-1-",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.planner_started-1790925108030",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.planner_selected-1790925108030",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-planner-step-2-1790925108059",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-tool-finish-1790925108065",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-continuation-after-step-1-1-",
    #|           "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-runtime.turn_finished-1790925108084"
    #|         ],
    #|         "output_urls": [],
    #|         "artifact_refs": [
    #|           {
    #|             "path": "welcome-note.txt",
    #|             "evidence_id": "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-tool-write-1790925108013",
    #|             "command_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start"
    #|           }
    #|         ],
    #|         "receipt": {
    #|           "id": "moonclaw:mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f:journal:18",
    #|           "session_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f",
    #|           "command_id": "mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start",
    #|           "status": "runtime-completed",
    #|           "claim_id": "moonclaw-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-mp-7765f64b783d6f73505fe79da9ce3fc16d901b719056553efe2214d1afdc967f-start-1790925107858",
    #|           "journal_sequence": "18"
    #|         },
    #|         "dispatched": true,
    #|         "acceptance": "pending"
    #|       }
    #|     },
    #|     "reports": []
    #|   }
    #| }

  let snapshot = dispatch_decode_snapshot(response, "dispatch-note").unwrap()
  let model = apply_dispatch_snapshot(initial_model(), snapshot)
  assert_eq(model.dispatch_task_stage, "in_progress")
  assert_eq(model.dispatch_task_report_id, "")
  let run = model.dispatch_run.unwrap()
  assert_eq(run.state, "completed")
  assert_eq(run.summary, "The welcome note is ready: welcome-note.txt")
  assert_true(run.artifacts.any(item => item.path == "welcome-note.txt"))
  assert_eq(run.output_urls, [])
  assert_true(dispatch_can_submit(model))
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    _,
    model,
  ) => dispatch_native_result(model))
  let html = opc_render_cell(page)
  assert_true(html.contains("The welcome note is ready: welcome-note.txt"))
  assert_true(html.contains("输出文件（相对工作区）"))
  assert_true(html.contains("welcome-note.txt"))
  assert_false(html.contains("LATER_UNRELATED_ANSWER"))
  assert_false(html.contains("href=\"welcome-note.txt\""))
}
