///|
#derive(Debug, Eq)
struct PlanScheduleState {
  anchor : String
  date : String
  source : @plan_workbench.Draft?
  preview : @plan_workbench.MilestoneRebase?
  note : String
}

///|
#derive(Debug, Eq)
enum PlanScheduleMsg {
  Anchor(String)
  Date(String)
  Preview
  Apply
  Close
}

///|
fn plan_schedule_initial() -> PlanScheduleState {
  { anchor: "", date: "", source: None, preview: None, note: "", }
}

///|
fn plan_schedule_update(
  action : PlanScheduleMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.schedule
  let next = match action {
    Anchor(anchor) => { ..plan_schedule_initial(), anchor, date: t.date, }
    Date(date) => { ..plan_schedule_initial(), anchor: t.anchor, date, }
    Close => plan_schedule_initial()
    Preview => {
      let preview = @plan_workbench.rebase_milestones(d, t.anchor, t.date) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                schedule: { ..t, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..t,
        source: Some(d),
        preview: Some(preview),
        note: "预览未修改草稿。请检查所有新日期后应用。",
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
              schedule: {
                ..t,
                source: None,
                preview: None,
                note: "草稿已变化，请重新预览日期。",
              },
            },
          },
        )
      }
      if preview.offset_days == 0 {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              schedule: {
                ..t,
                note: "新日期与原日期相同，草稿未改变。",
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
            note: edited.note +
            " 已将全部有日期的里程碑平移 " +
            preview.offset_days.to_string() +
            " 个日历日。",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, schedule: next, }, })
}

///|
fn plan_schedule_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.schedule
  @html.details <| [
    @html.summary("整体调整里程碑日期"),
    p(
      "选择一个已有日期的里程碑并指定新日期。全部有日期的里程碑按相同日历天数平移，保留间隔；空白日期保留。周末和节假日不另作调整。",
    ),
    if !d.milestones.any(m => !m.date.trim().is_empty()) {
      p(
        "请先填写至少一个里程碑的目标日期，再选择它作为基准。",
      )
    } else {
      @html.nothing
    },
    div(class="tag-row") <| d.milestones
    .filter(m => !m.date.trim().is_empty())
    .map(m => {
      plan_button(
        emit,
        Schedule(Anchor(m.id)),
        m.name + " · " + m.date + " [" + m.id + "]",
        selected=t.anchor == m.id,
      )
    }),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-schedule-date"),
        "基准里程碑的新日期 YYYY-MM-DD",
      ),
      input(
        input_type=Text,
        attrs=@html.Attrs::build().id("plan-schedule-date"),
        value=t.date,
        on_input=emit.map(v => PlanAction(Schedule(Date(v)))),
      ),
    ],
    plan_button(
      emit,
      Schedule(Preview),
      "预览整体日期调整",
      disabled=t.anchor.is_empty() || t.date.is_empty(),
    ),
    plan_button(emit, Schedule(Close), "取消日期调整"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.source, t.preview) {
      (Some(source), Some(preview)) if source == d =>
        div <| [
          p(
            "全部有日期的里程碑平移 " +
            preview.offset_days.to_string() +
            " 个日历日（正数延后，负数提前）。",
          ),
          div <| preview.draft.milestones.mapi((i, m) => {
            p(
              m.name +
              " [" +
              m.id +
              "]: " +
              (if m.date.trim().is_empty() {
                "未定日期 → 未定日期（保留）"
              } else {
                source.milestones[i].date + " → " + m.date
              }),
            )
          }),
          p(
            "应用后需重新准备并保存原生计划；已保存的历史版本不变。任务没有排期或工期，本操作只编辑里程碑日期。",
          ),
          plan_button(
            emit,
            Schedule(Apply),
            "应用全部新日期",
            disabled=preview.offset_days == 0,
          ),
        ]
      _ => @html.nothing
    },
  ]
}
