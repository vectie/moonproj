///|
struct PlanMilestoneTableState {
  text : String
  tsv : Bool
  base : @plan_workbench.Draft?
  preview : @plan_workbench.MilestoneTableUpdate?
  note : String
} derive(Debug, Eq)

///|
enum PlanMilestoneTableMsg {
  Text(String)
  Format(Bool)
  Preview
  Apply
  Close
  Export
} derive(Debug, Eq)

///|
fn plan_milestone_table_initial() -> PlanMilestoneTableState {
  { text: "", tsv: false, base: None, preview: None, note: "", }
}

///|
fn plan_milestone_table_update(
  action : PlanMilestoneTableMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.milestone_table
  let next = match action {
    Text(text) => { ..t, text, base: None, preview: None, note: "", }
    Format(tsv) => { ..t, tsv, base: None, preview: None, note: "", }
    Close => { ..t, base: None, preview: None, note: "", }
    Export => {
      let csv = @plan_workbench.export_milestone_table(d)
      return (
        @cmd.custom_cmd(_ => plan_download(csv, "plan-milestones.csv", false)),
        model,
      )
    }
    Preview => {
      let preview = @plan_workbench.preview_milestone_table_updates(
        d,
        t.text,
        t.tsv,
      ) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                milestone_table: { ..t, base: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..t,
        base: Some(d),
        preview: Some(preview),
        note: "Preview only. Apply edits to update the local draft.",
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
              milestone_table: {
                ..t,
                base: None,
                preview: None,
                note: "The draft changed. Preview the milestone table again.",
              },
            },
          },
        )
      }
      if preview.changes.is_empty() {
        return (none, model)
      }
      let edited = plan_save_edit(s, preview.draft)
      return (
        none,
        {
          ..model,
          plan: {
            ..edited,
            note: edited.note +
            " Updated " +
            preview.changes.length().to_string() +
            " existing milestones; task links retained.",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, milestone_table: next, }, })
}

///|
fn plan_milestone_table_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.milestone_table
  @html.details <| [
    @html.summary("编辑里程碑表 / Edit milestone table"),
    p(
      "下载 CSV，在表格中编辑后粘贴回来。按现有 id 更新；未列出的行或列保持不变。独立修改日期不会平移其他里程碑，关联任务保持原样。",
    ),
    plan_button(
      emit,
      MilestoneTable(Export),
      "下载可编辑里程碑 CSV / Download milestone CSV",
      disabled=d.milestones.is_empty(),
    ),
    div(class="tag-row") <| [
      plan_button(emit, MilestoneTable(Format(false)), "CSV", selected=!t.tsv),
      plan_button(emit, MilestoneTable(Format(true)), "TSV", selected=t.tsv),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-milestone-table"),
        "里程碑 CSV / TSV（含表头）",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-milestone-table"),
        value=t.text,
        on_input=emit.map(text => PlanAction(MilestoneTable(Text(text)))),
        "",
      ),
    ],
    p(
      "列：id、title、owner、date、criteria、evidence。日期为 YYYY-MM-DD；空日期取消目标日期，空 criteria/evidence 清空对应要求；空标题或负责人不接受。多行标准和证据使用带引号的单元格。",
    ),
    p(
      "这是草稿编辑；清空要求会留下待补全内容，原生准备仍会独立校验。Status、完成度及其他列忽略并列出，不会记录验收或执行结果。",
    ),
    plan_button(
      emit,
      MilestoneTable(Preview),
      "预览里程碑修改 / Preview milestone edits",
      disabled=t.text.trim().is_empty(),
    ),
    plan_button(
      emit,
      MilestoneTable(Close),
      "关闭修改预览 / Close preview",
    ),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.base, t.preview) {
      (Some(base), Some(preview)) if base == d =>
        div <| [
          h3("里程碑修改预览 / Milestone edit preview"),
          p(
            preview.changes.length().to_string() +
            " 个里程碑将更新；ID、顺序及关联任务保持不变。",
          ),
          p(
            "忽略的列 / Ignored columns: " +
            (if preview.ignored.is_empty() {
              "None"
            } else {
              preview.ignored.join(", ")
            }),
          ),
          div <| preview.changes.map(change => {
            @html.details <| [
              @html.summary(
                change.before.id + " · " + change.fields.join(", "),
              ),
              strong("Before / 修改前"),
              @html.pre(change.before.to_json().stringify(indent=2)),
              strong("After / 修改后"),
              @html.pre(change.after.to_json().stringify(indent=2)),
            ]
          }),
          plan_button(
            emit,
            MilestoneTable(Apply),
            "应用里程碑修改 / Apply milestone edits",
            disabled=preview.changes.is_empty(),
          ),
        ]
      _ => @html.nothing
    },
  ]
}
