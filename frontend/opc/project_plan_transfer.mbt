///|
#derive(Debug, Eq)
struct PlanTransferState {
  from_owner : String
  to_owner : String
  source : @plan_workbench.Draft?
  preview : @plan_workbench.Draft?
  note : String
}

///|
#derive(Debug, Eq)
enum PlanTransferMsg {
  From(String)
  To(String)
  Preview
  Apply
  Close
}

///|
fn plan_transfer_initial() -> PlanTransferState {
  { from_owner: "", to_owner: "", source: None, preview: None, note: "", }
}

///|
fn plan_transfer_update(
  action : PlanTransferMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard !s.actor.is_empty() &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.transfer
  let next = match action {
    From(from_owner) =>
      { ..plan_transfer_initial(), from_owner, to_owner: t.to_owner, }
    To(to_owner) =>
      { ..plan_transfer_initial(), from_owner: t.from_owner, to_owner, }
    Close => plan_transfer_initial()
    Preview => {
      let preview = @plan_workbench.transfer_owner(d, t.from_owner, t.to_owner) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                transfer: { ..t, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..t,
        source: Some(d),
        preview: Some(preview),
        note: if preview == d {
          "该负责人没有待交接的分配，草稿未改变。"
        } else {
          "预览未修改草稿；检查全部任务、里程碑和风险后应用。"
        },
      }
    }
    Apply => {
      guard t.source is Some(source) && t.preview is Some(preview) else {
        return (none, model)
      }
      if source != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              transfer: {
                ..t,
                source: None,
                preview: None,
                note: "草稿已变化，请重新预览交接。",
              },
            },
          },
        )
      }
      if preview == d {
        return (none, model)
      }
      return (none, { ..model, plan: plan_save_edit(s, preview), })
    }
  }
  (none, { ..model, plan: { ..s, transfer: next, }, })
}

///|
fn plan_transfer_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.transfer
  @html.details <| [
    @html.summary("批量交接负责人 / Reassign owner"),
    p(
      "将一个负责人的全部任务、里程碑和风险分配交给另一位已有负责人。只编辑计划草稿；不会授予权限、派发任务或通知任何人。原负责人记录和准备人不变。",
    ),
    p("转出负责人"),
    div(class="tag-row") <| d.owners.map(o => {
      plan_button(
        emit,
        Transfer(From(o.id)),
        o.name + " [" + o.id + "]",
        selected=t.from_owner == o.id,
      )
    }),
    p("接任负责人"),
    div(class="tag-row") <| d.owners.map(o => {
      plan_button(
        emit,
        Transfer(To(o.id)),
        o.name + " [" + o.id + "]",
        selected=t.to_owner == o.id,
      )
    }),
    plan_button(
      emit,
      Transfer(Preview),
      "预览负责人交接",
      disabled=t.from_owner.is_empty() ||
        t.to_owner.is_empty() ||
        t.from_owner == t.to_owner,
    ),
    plan_button(emit, Transfer(Close), "取消负责人交接"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.source, t.preview) {
      (Some(source), Some(preview)) if source == d =>
        div <| [
          p(t.from_owner + " → " + t.to_owner),
          p(
            "任务：" +
            d.tasks.filter(v => v.owner == t.from_owner).length().to_string(),
          ),
          div <| d.tasks
          .filter(v => v.owner == t.from_owner)
          .map(v => p(v.name + " [" + v.id + "]")),
          p(
            "里程碑：" +
            d.milestones
            .filter(v => v.owner == t.from_owner)
            .length()
            .to_string(),
          ),
          div <| d.milestones
          .filter(v => v.owner == t.from_owner)
          .map(v => p(v.name + " [" + v.id + "]")),
          p(
            "风险：" +
            d.risks.filter(v => v.owner == t.from_owner).length().to_string(),
          ),
          div <| d.risks
          .filter(v => v.owner == t.from_owner)
          .map(v => p(v.summary + " [" + v.id + "]")),
          plan_button(
            emit,
            Transfer(Apply),
            "应用全部负责人交接",
            disabled=preview == d,
          ),
        ]
      _ => @html.nothing
    },
  ]
}
