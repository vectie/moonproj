///|
#derive(Debug, Eq)
struct PlanBreakdownState {
  task_id : String
  steps : Array[@plan_workbench.TaskStep]
  source : @plan_workbench.Draft?
  preview : @plan_workbench.Draft?
  note : String
}

///|
#derive(Debug, Eq)
enum PlanBreakdownMsg {
  Choose(String)
  Edit(String, String, String)
  Add
  Remove(String)
  Preview
  Apply
  Close
}

///|
fn plan_breakdown_initial() -> PlanBreakdownState {
  { task_id: "", steps: [], source: None, preview: None, note: "", }
}

///|
fn plan_breakdown_update(
  action : PlanBreakdownMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard !s.actor.is_empty() &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let b = s.breakdown
  let next = match action {
    Choose(id) =>
      if id.is_empty() {
        plan_breakdown_initial()
      } else {
        guard d.tasks.filter(t => t.id == id) is [task] else {
          return (none, model)
        }
        {
          ..plan_breakdown_initial(),
          task_id: id,
          steps: [
            { id: plan_nonce(), name: task.name + " · 1", cost: task.cost, },
            { id: plan_nonce(), name: "", cost: "0", },
          ],
        }
      }
    Edit(id, field, value) => {
      if !b.steps.any(step => step.id == id) ||
        (field != "name" && field != "cost") {
        return (none, model)
      }
      {
        ..b,
        source: None,
        preview: None,
        note: "",
        steps: b.steps.map(step => {
          if step.id != id {
            step
          } else if field == "name" {
            { ..step, name: value, }
          } else {
            { ..step, cost: value, }
          }
        }),
      }
    }
    Add => {
      if b.task_id.is_empty() || b.steps.length() >= 10 {
        return (none, model)
      }
      {
        ..b,
        source: None,
        preview: None,
        note: "",
        steps: [..b.steps, { id: plan_nonce(), name: "", cost: "0", }],
      }
    }
    Remove(id) => {
      if b.steps.length() <= 2 || !b.steps.any(step => step.id == id) {
        return (none, model)
      }
      {
        ..b,
        source: None,
        preview: None,
        note: "",
        steps: b.steps.filter(step => step.id != id),
      }
    }
    Close => plan_breakdown_initial()
    Preview => {
      let preview = @plan_workbench.break_down_task(d, b.task_id, b.steps) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                breakdown: { ..b, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..b,
        source: Some(d),
        preview: Some(preview),
        note: "Preview only. Review the sequence, follower dependencies and risk links before applying.",
      }
    }
    Apply => {
      guard b.source is Some(source) && b.preview is Some(preview) else {
        return (none, model)
      }
      if source != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              breakdown: {
                ..b,
                source: None,
                preview: None,
                note: "The draft changed. Preview the breakdown again.",
              },
            },
          },
        )
      }
      return (none, { ..model, plan: plan_save_edit(s, preview), })
    }
  }
  (none, { ..model, plan: { ..s, breakdown: next, }, })
}
