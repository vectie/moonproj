///|
#derive(Debug, Eq)
struct PlanTaskEdits {
  base : @plan_workbench.Draft
  source : String
  tsv : Bool
  preview : @plan_workbench.TaskTableUpdate
}

///|
#derive(Debug, Eq)
enum PlanTaskEditMsg {
  Preview
  Apply
  Close
}

///|
fn plan_task_edits_update(
  action : PlanTaskEditMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  match action {
    Close => (none, { ..model, plan: { ..s, task_edits: None, }, })
    Preview => {
      let preview = @plan_workbench.preview_task_table_updates(
        d,
        s.task_table,
        s.task_table_tsv,
      ) catch {
        @plan_workbench.Invalid(message) =>
          return (
            none,
            { ..model, plan: { ..s, task_edits: None, note: message, }, },
          )
      }
      (
        none,
        {
          ..model,
          plan: {
            ..s,
            task_edits: Some({
              base: d,
              source: s.task_table,
              tsv: s.task_table_tsv,
              preview,
            }),
            note: "任务表修改仅供预览；点击应用后才写入浏览器草稿。",
          },
        },
      )
    }
    Apply => {
      guard s.task_edits is Some(edits) else { return (none, model) }
      if edits.base != d ||
        edits.source != s.task_table ||
        edits.tsv != s.task_table_tsv {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              task_edits: None,
              note: "草稿或输入已改变，请重新预览任务表修改。",
            },
          },
        )
      }
      if edits.preview.changes.is_empty() {
        return (none, model)
      }
      let next = plan_save_edit(s, edits.preview.draft)
      (
        none,
        {
          ..model,
          plan: {
            ..next,
            note: next.note +
            " 已更新 " +
            edits.preview.changes.length().to_string() +
            " 个现有任务；未列出的任务和列保持不变。",
          },
        },
      )
    }
  }
}

///|
fn plan_task_edits_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
) -> @html.Html {
  div <| [
    p(
      "在表格中修改导出的任务后，粘贴到上方并预览更新。按现有 id 匹配；未列出的任务或列保留。空依赖清除前置任务，空成本设为 0；空标题、负责人或里程碑不接受。更新不使用追加导入的默认分配。",
    ),
    plan_button(
      emit,
      TaskEdits(Preview),
      "预览现有任务修改",
      disabled=s.task_table.trim().is_empty(),
    ),
    match s.task_edits {
      None => @html.nothing
      Some(edits) =>
        div <| [
          h3("现有任务修改预览"),
          p(
            edits.preview.changes.length().to_string() +
            " 个任务将更新；任务总数与顺序保持不变。",
          ),
          p(
            "忽略的列：" +
            (if edits.preview.ignored.is_empty() {
              "无"
            } else {
              edits.preview.ignored.join(", ")
            }),
          ),
          div <| edits.preview.changes.map(change => {
            @html.details <| [
              @html.summary(
                change.before.id + " · " + change.fields.join(", "),
              ),
              strong("Before / 修改前"),
              @html.pre(ToJson::to_json(change.before).stringify(indent=2)),
              strong("After / 修改后"),
              @html.pre(ToJson::to_json(change.after).stringify(indent=2)),
            ]
          }),
          p(
            "应用只修改当前浏览器草稿并撤销旧准备预览，不保存原生版本、不创建正式任务。原生准备与人工复核仍是后续独立步骤。",
          ),
          plan_button(
            emit,
            TaskEdits(Apply),
            "应用这些任务修改",
            disabled=edits.preview.changes.is_empty(),
          ),
          plan_button(emit, TaskEdits(Close), "关闭修改预览"),
        ]
    },
  ]
}
