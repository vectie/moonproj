///|
struct PlanHandoffState {
  task_id : String
  source : @plan_workbench.Draft?
  preview : @plan_workbench.TaskHandoff?
  note : String
} derive(Debug, Eq)

///|
enum PlanHandoffMsg {
  Select(String)
  Preview
  CreateDraft
  Close
} derive(Debug, Eq)

///|
fn plan_handoff_initial() -> PlanHandoffState {
  { task_id: "", source: None, preview: None, note: "", }
}

///|
fn plan_handoff_readable_store(saved : DispatchDraftStore) -> Bool {
  if saved.version != 1 {
    return false
  }
  let seen : Map[String, Bool] = Map::new()
  for item in saved.drafts {
    if item.id.is_empty() ||
      item.task_id.is_empty() ||
      item.idempotency_key.is_empty() ||
      seen.contains(item.id) {
      return false
    }
    seen[item.id] = true
    if item.research_brief is Some(brief) &&
      @research_handoff.decode(brief.to_json().stringify()) is Err(_) {
      return false
    }
  }
  true
}

///|
fn plan_handoff_update(
  emit : @rabbita.Emit[Msg],
  action : PlanHandoffMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard model.page == Projects &&
    !s.actor.is_empty() &&
    s.actor == model.dispatch_task_actor_id &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let h = s.handoff
  let next = match action {
    Select(task_id) => { ..plan_handoff_initial(), task_id, }
    Close => plan_handoff_initial()
    Preview => {
      let preview = @plan_workbench.task_handoff(d, h.task_id) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                handoff: { ..h, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..h,
        source: Some(d),
        preview: Some(preview),
        note: "Preview only. Adapt the milestone criteria and check prerequisites in the new task draft.",
      }
    }
    CreateDraft => {
      guard h.source is Some(source) && h.preview is Some(preview) else {
        return (none, model)
      }
      if source != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              handoff: {
                ..h,
                source: None,
                preview: None,
                note: "The plan changed. Preview this task again.",
              },
            },
          },
        )
      }
      // Merge any previously saved drafts before writing the new collection.
      // An unreadable collection must remain available for its existing recovery.
      let stored = dispatch_read_drafts(s.actor)
      if !stored.is_empty() {
        let saved : DispatchDraftStore? = Some(
          @json.from_json(@json.parse(stored)),
        ) catch {
          _ => None
        }
        guard saved is Some(saved) && plan_handoff_readable_store(saved) else {
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                handoff: {
                  ..h,
                  note: "Existing task drafts could not be read. Recover them in Dispatch before creating another draft; the stored collection was not changed.",
                },
              },
            },
          )
        }
      }
      let (_, restored) = dispatch_draft_update(
        emit,
        Restored(s.actor, stored),
        model,
      )
      let (_, prepared) = dispatch_prepare_draft(
        emit,
        restored,
        "",
        d.project_id,
        None,
        true,
      )
      let fresh = dispatch_active_draft(prepared).unwrap()
      return dispatch_save_draft(
        emit,
        {
          ..prepared,
          plan: { ..s, handoff: plan_handoff_initial(), },
          notice: "已从计划任务另建本地草稿。请填写负责人、开始日期与执行设置，调整验收条件并核对前置任务；尚未创建正式任务。",
        },
        {
          ..fresh,
          title: preview.title,
          acceptance: preview.acceptance,
          source_reference: Some(preview.source_reference),
          observed_problem: Some(preview.context),
          end_date: preview.end_date,
          note: "来自计划任务的独立本地快照；后续计划编辑不会自动改写本草稿。",
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, handoff: next, }, })
}
