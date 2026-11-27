///|
#derive(Debug, Eq)
struct PlanChecklistState {
  text : String
  owner : String
  milestone : String
  include_checked : Bool
  base : @plan_workbench.Draft?
  preview : @plan_workbench.ChecklistImport?
  note : String
}

///|
#derive(Debug, Eq)
enum PlanChecklistMsg {
  Text(String)
  Owner(String)
  Milestone(String)
  IncludeChecked(Bool)
  Preview
  Apply
  Close
}

///|
fn plan_checklist_initial() -> PlanChecklistState {
  {
    text: "",
    owner: "",
    milestone: "",
    include_checked: false,
    base: None,
    preview: None,
    note: "",
  }
}

///|
fn plan_checklist_update(
  action : PlanChecklistMsg,
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
  let t = s.checklist
  let cleared = { ..t, base: None, preview: None, note: "", }
  let next = match action {
    Text(text) => { ..cleared, text, }
    Owner(owner) => { ..cleared, owner, }
    Milestone(milestone) => { ..cleared, milestone, }
    IncludeChecked(include_checked) => { ..cleared, include_checked, }
    Close => cleared
    Preview => {
      if t.base == Some(d) && t.preview is Some(_) {
        return (none, model)
      }
      let preview = @plan_workbench.preview_markdown_checklist(
        d,
        t.text,
        t.owner,
        t.milestone,
        plan_nonce(),
        t.include_checked,
      ) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            { ..model, plan: { ..s, checklist: { ..cleared, note, }, }, },
          )
      }
      {
        ..t,
        base: Some(d),
        preview: Some(preview),
        note: "Preview only. Review the source lines and planned task names before appending.",
      }
    }
    Apply => {
      guard t.base is Some(base) && t.preview is Some(preview) else {
        return (none, model)
      }
      if base != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              checklist: {
                ..cleared,
                note: "The plan changed. Preview the checklist again.",
              },
            },
          },
        )
      }
      let edited = plan_save_edit(s, preview.draft)
      return (
        none,
        {
          ..model,
          plan: {
            ..edited,
            checklist: plan_checklist_initial(),
            note: edited.note +
            " Appended " +
            preview.entries.length().to_string() +
            " checklist tasks. Review their initial zero costs and add dependencies as needed; source checkmarks do not record completion.",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, checklist: next, }, })
}
