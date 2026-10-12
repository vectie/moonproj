///|
struct PlanConsolidationState {
  selected : Array[String]
  retained : String
  name : String
  source : @plan_workbench.Draft?
  preview : @plan_workbench.Draft?
  note : String
} derive(Debug, Eq)

///|
enum PlanConsolidationMsg {
  Toggle(String)
  Retain(String)
  Name(String)
  Preview
  Apply
  Close
} derive(Debug, Eq)

///|
fn plan_consolidation_initial() -> PlanConsolidationState {
  {
    selected: [],
    retained: "",
    name: "",
    source: None,
    preview: None,
    note: "",
  }
}

///|
fn plan_consolidation_update(
  action : PlanConsolidationMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard !s.actor.is_empty() &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let c = s.consolidation
  let next = match action {
    Toggle(id) => {
      guard d.tasks.filter(t => t.id == id) is [task] else {
        return (none, model)
      }
      let selected = plan_toggle(c.selected, id)
      let retained = if selected.contains(c.retained) {
        c.retained
      } else {
        selected.get(0).unwrap_or("")
      }
      {
        ..c,
        selected,
        retained,
        name: if c.selected.is_empty() {
          task.name
        } else {
          c.name
        },
        source: None,
        preview: None,
        note: "",
      }
    }
    Retain(id) => {
      if !c.selected.contains(id) {
        return (none, model)
      }
      { ..c, retained: id, source: None, preview: None, note: "", }
    }
    Name(name) => { ..c, name, source: None, preview: None, note: "", }
    Close => plan_consolidation_initial()
    Preview => {
      let preview = @plan_workbench.consolidate_tasks(
        d,
        c.selected,
        c.retained,
        c.name,
      ) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                consolidation: { ..c, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..c,
        source: Some(d),
        preview: Some(preview),
        note: "Preview only. Check the combined scope, cost, dependency order and risk links before applying.",
      }
    }
    Apply => {
      guard c.source is Some(source) && c.preview is Some(preview) else {
        return (none, model)
      }
      if source != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              consolidation: {
                ..c,
                source: None,
                preview: None,
                note: "The draft changed. Preview the consolidation again.",
              },
            },
          },
        )
      }
      return (none, { ..model, plan: plan_save_edit(s, preview), })
    }
  }
  (none, { ..model, plan: { ..s, consolidation: next, }, })
}
