///|
struct PlanCompareState {
  visible : Bool
  generation : Int
  before_key : String
  after_key : String
  before : Json?
  after : Json?
  result : @plan_workbench.PlanComparison?
  phase : String
  note : String
} derive(Debug, Eq)

///|
enum PlanCompareMsg {
  Show
  Select(Bool, String)
  Load
  Swap
  Close
  Received(String, Int, String, Int, String, String, Bool, Int, String)
  Export
} derive(Debug, Eq)

///|
fn plan_compare_initial() -> PlanCompareState {
  {
    visible: false,
    generation: 0,
    before_key: "",
    after_key: "",
    before: None,
    after: None,
    result: None,
    phase: "idle",
    note: "",
  }
}

///|
fn plan_compare_load(
  emit : @rabbita.Emit[Msg],
  state : PlanWorkbench,
  pair : PlanCompareState,
) -> (Cmd, PlanCompareState) {
  let next = {
    ..pair,
    generation: pair.generation + 1,
    before: None,
    after: None,
    result: None,
    phase: "selecting",
    note: "请选择 Before 和 After 两个已保存版本。",
  }
  if next.before_key.is_empty() || next.after_key.is_empty() {
    return (none, next)
  }
  let next = {
    ..next,
    phase: "loading",
    note: "正在只读验证两个已保存版本…",
  }
  let command = @cmd.custom_cmd(scheduler => {
    for is_before in [true, false] {
      let key = if is_before { next.before_key } else { next.after_key }
      plan_fetch(
        plan_url(state.selected) + "/" + dispatch_url_encode(key),
        "GET",
        "",
        (status, body) => {
          scheduler.add(
            emit(
              PlanAction(
                Compare(
                  Received(
                    state.actor,
                    state.epoch,
                    state.selected,
                    next.generation,
                    next.before_key,
                    next.after_key,
                    is_before,
                    status,
                    body,
                  ),
                ),
              ),
            ),
          )
        },
      )
    }
  })
  (command, next)
}

///|
/// Separate read-only state machine: never receives or mutates the editor draft,
/// prepared result, phase, revision, or browser storage.
fn plan_compare_update(
  emit : @rabbita.Emit[Msg],
  message : PlanCompareMsg,
  state : PlanWorkbench,
) -> (Cmd, PlanCompareState) {
  let s = state.comparison
  match message {
    Show => (none, { ..s, visible: true, })
    Close => (none, { ..plan_compare_initial(), generation: s.generation + 1, })
    Select(before, key) => {
      if !s.visible ||
        (
          !key.is_empty() &&
          !state.history.any(item => products_text(item, "key") == key)
        ) {
        return (none, s)
      }
      plan_compare_load(
        emit,
        state,
        if before {
          { ..s, before_key: key, }
        } else {
          { ..s, after_key: key, }
        },
      )
    }
    Load =>
      if s.visible {
        plan_compare_load(emit, state, s)
      } else {
        (none, s)
      }
    Swap =>
      if s.visible {
        plan_compare_load(emit, state, {
          ..s,
          before_key: s.after_key,
          after_key: s.before_key,
        })
      } else {
        (none, s)
      }
    Received(
      actor,
      epoch,
      project,
      generation,
      before_key,
      after_key,
      is_before,
      status,
      body
    ) => {
      if !s.visible ||
        s.phase != "loading" ||
        actor != state.actor ||
        epoch != state.epoch ||
        project != state.selected ||
        generation != s.generation ||
        before_key != s.before_key ||
        after_key != s.after_key {
        return (none, s)
      }
      let key = if is_before { before_key } else { after_key }
      let saved = if status == 200 {
        plan_decode_saved(body, actor, project, key)
      } else {
        None
      }
      guard saved is Some(saved) else {
        return (
          none,
          {
            ..s,
            before: None,
            after: None,
            result: None,
            phase: "error",
            note: "对比读取失败或版本验证未通过。可重试；当前编辑和准备结果未改变。",
          },
        )
      }
      let next = if is_before {
        { ..s, before: Some(saved), }
      } else {
        { ..s, after: Some(saved), }
      }
      match (next.before, next.after) {
        (Some(before), Some(after)) => {
          let result = @plan_workbench.compare_saved(before, after) catch {
            _ =>
              return (
                none,
                {
                  ..next,
                  phase: "error",
                  result: None,
                  note: "保存计划无法形成类型化对比；当前编辑未改变。",
                },
              )
          }
          (
            none,
            {
              ..next,
              phase: "ready",
              result: Some(result),
              note: "只读对比已完成；可继续编辑当前草稿。",
            },
          )
        }
        _ => (none, next)
      }
    }
    Export =>
      match s.result {
        Some(result) if s.visible && s.phase == "ready" =>
          (
            @cmd.custom_cmd(_ => {
              plan_download(
                result.readable(),
                "plan-comparison-" +
                s.before_key +
                "-to-" +
                s.after_key +
                ".txt",
                false,
              )
            }),
            s,
          )
        _ => (none, s)
      }
  }
}
