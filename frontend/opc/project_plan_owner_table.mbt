///|
struct PlanOwnerTableState {
  text : String
  tsv : Bool
  base : @plan_workbench.Draft?
  preview : @plan_workbench.OwnerTableUpdate?
  note : String
} derive(Debug, Eq)

///|
enum PlanOwnerTableMsg {
  Text(String)
  Format(Bool)
  Preview
  Apply
  Close
  Export
} derive(Debug, Eq)

///|
fn plan_owner_table_initial() -> PlanOwnerTableState {
  { text: "", tsv: false, base: None, preview: None, note: "", }
}

///|
fn plan_owner_table_update(
  action : PlanOwnerTableMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.owner_table
  let next = match action {
    Text(text) => { ..t, text, base: None, preview: None, note: "", }
    Format(tsv) => { ..t, tsv, base: None, preview: None, note: "", }
    Close => { ..t, base: None, preview: None, note: "", }
    Export => {
      let csv = @plan_workbench.export_owner_table(d)
      return (
        @cmd.custom_cmd(_ => plan_download(csv, "plan-owners.csv", false)),
        model,
      )
    }
    Preview => {
      let preview = @plan_workbench.preview_owner_table(d, t.text, t.tsv) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                owner_table: { ..t, base: None, preview: None, note, },
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
              owner_table: {
                ..t,
                base: None,
                preview: None,
                note: "The draft changed. Preview the owner roster again.",
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
            " Applied " +
            preview.changes.length().to_string() +
            " owner additions/updates; other draft content retained.",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, owner_table: next, }, })
}

///|
fn plan_owner_table_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.owner_table
  @html.details <| [
    @html.summary("负责人名册 / Owner roster table"),
    p(
      "粘贴 CSV/TSV：现有 ID 更新，新 ID 追加。未列出的负责人或列保持不变；不会删除负责人。预览明确区分新增和修改。",
    ),
    plan_button(
      emit,
      OwnerTable(Export),
      "下载负责人 CSV / Download owner CSV",
    ),
    div(class="tag-row") <| [
      plan_button(emit, OwnerTable(Format(false)), "CSV", selected=!t.tsv),
      plan_button(emit, OwnerTable(Format(true)), "TSV", selected=t.tsv),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-owner-table"),
        "负责人 CSV / TSV（含表头）",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-owner-table"),
        value=t.text,
        on_input=emit.map(text => PlanAction(OwnerTable(Text(text)))),
        "",
      ),
    ],
    p(
      "列：id、name、role。新增负责人需要 name 和 role 列；现有 ID 只更新提供的列。name 不能为空，空 role 清空职责。多行或含逗号的文字使用带引号的单元格。",
    ),
    p(
      "保留现有 ID；更改 ID 会新增负责人。姓名可以重复，ID 必须唯一。任务、里程碑和风险的负责人引用不变；要交接任务请使用 Reassign owner。最多 40 位负责人。",
    ),
    p(
      "This is local planning metadata, not a user account or permission grant. Unknown columns are ignored and listed. Do not paste credentials. A blank role remains incomplete for later native validation.",
    ),
    plan_button(
      emit,
      OwnerTable(Preview),
      "预览负责人登记表 / Preview owner roster",
      disabled=t.text.trim().is_empty(),
    ),
    plan_button(emit, OwnerTable(Close), "关闭预览 / Close preview"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.base, t.preview) {
      (Some(base), Some(preview)) if base == d =>
        div <| [
          h3("负责人登记表预览 / Owner roster preview"),
          p(
            "New / 新增: " +
            preview.changes.filter(c => c.before is None).length().to_string() +
            "; Updated / 修改: " +
            preview.changes
            .filter(c => c.before is Some(_))
            .length()
            .to_string(),
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
              @html.summary(change.after.id + " · " + change.fields.join(", ")),
              strong("Before / 修改前"),
              match change.before {
                None => p("New owner / 新增负责人")
                Some(before) => @html.pre(ToJson::to_json(before).stringify(indent=2))
              },
              strong("After / 修改后"),
              @html.pre(ToJson::to_json(change.after).stringify(indent=2)),
            ]
          }),
          plan_button(
            emit,
            OwnerTable(Apply),
            "应用负责人登记表 / Apply owner roster",
            disabled=preview.changes.is_empty(),
          ),
        ]
      _ => @html.nothing
    },
  ]
}
