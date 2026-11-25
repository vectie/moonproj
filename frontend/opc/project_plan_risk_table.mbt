///|
struct PlanRiskTableState {
  text : String
  tsv : Bool
  base : @plan_workbench.Draft?
  preview : @plan_workbench.RiskTableUpdate?
  note : String
} derive(Debug, Eq)

///|
enum PlanRiskTableMsg {
  Text(String)
  Format(Bool)
  Preview
  Apply
  Close
  Export
} derive(Debug, Eq)

///|
fn plan_risk_table_initial() -> PlanRiskTableState {
  { text: "", tsv: false, base: None, preview: None, note: "", }
}

///|
fn plan_risk_table_update(
  action : PlanRiskTableMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.risk_table
  let next = match action {
    Text(text) => { ..t, text, base: None, preview: None, note: "", }
    Format(tsv) => { ..t, tsv, base: None, preview: None, note: "", }
    Close => { ..t, base: None, preview: None, note: "", }
    Export => {
      let csv = @plan_workbench.export_risk_table(d)
      return (
        @cmd.custom_cmd(_ => plan_download(csv, "plan-risks.csv", false)),
        model,
      )
    }
    Preview => {
      let preview = @plan_workbench.preview_risk_table(d, t.text, t.tsv) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                risk_table: { ..t, base: None, preview: None, note, },
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
              risk_table: {
                ..t,
                base: None,
                preview: None,
                note: "The draft changed. Preview the risk register again.",
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
            " risk additions/updates; other draft content retained.",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, risk_table: next, }, })
}

///|
fn plan_risk_table_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.risk_table
  @html.details <| [
    @html.summary("风险登记表 / Risk register table"),
    p(
      "粘贴 CSV/TSV：现有 ID 更新，新 ID 追加。未列出的风险或列保持不变；不会删除风险。预览明确区分新增和修改。",
    ),
    plan_button(emit, RiskTable(Export), "下载风险 CSV / Download risk CSV"),
    div(class="tag-row") <| [
      plan_button(emit, RiskTable(Format(false)), "CSV", selected=!t.tsv),
      plan_button(emit, RiskTable(Format(true)), "TSV", selected=t.tsv),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-risk-table"),
        "风险 CSV / TSV（含表头）",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-risk-table"),
        value=t.text,
        on_input=emit.map(text => PlanAction(RiskTable(Text(text)))),
        "",
      ),
    ],
    p(
      "列：id、summary、severity、owner、mitigation、tasks。新增风险必须填写 summary、severity、owner；severity 为 low、medium、high 或 critical。owner 使用现有 ID 或唯一姓名。",
    ),
    p(
      "tasks 使用分号分隔的现有任务 ID，或 JSON 字符串数组（导出格式）。空 mitigation/tasks 清空该字段；多行文本使用带引号的单元格。保留现有 ID，改变 ID 会新增风险。",
    ),
    p(
      "仅编辑本地规划草稿。Status、验收及其他列忽略并列出；不记录风险已解决、执行或审批。原生准备仍会独立校验完整计划。",
    ),
    plan_button(
      emit,
      RiskTable(Preview),
      "预览风险登记表 / Preview risk register",
      disabled=t.text.trim().is_empty(),
    ),
    plan_button(emit, RiskTable(Close), "关闭预览 / Close preview"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.base, t.preview) {
      (Some(base), Some(preview)) if base == d =>
        div <| [
          h3("风险登记表预览 / Risk register preview"),
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
                None => p("New risk / 新增风险")
                Some(before) => @html.pre(ToJson::to_json(before).stringify(indent=2))
              },
              strong("After / 修改后"),
              @html.pre(ToJson::to_json(change.after).stringify(indent=2)),
            ]
          }),
          plan_button(
            emit,
            RiskTable(Apply),
            "应用风险登记表 / Apply risk register",
            disabled=preview.changes.is_empty(),
          ),
        ]
      _ => @html.nothing
    },
  ]
}
