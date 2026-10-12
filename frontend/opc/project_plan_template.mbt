///|
struct PlanTemplateState {
  source : String
  trello : Bool
  preview : @plan_workbench.Template?
  owner : String
  name : String
  note : String
  append_before : @plan_workbench.Draft?
  append_after : @plan_workbench.Draft?
} derive(Debug, Eq)

///|
enum PlanTemplateMsg {
  Source(String)
  Preview
  PreviewTrello
  Owner(String)
  Name(String)
  Apply
  Close
  Download
  DownloadReview
  PreviewAppend
  ApplyAppend
} derive(Debug, Eq)

///|
fn plan_template_initial() -> PlanTemplateState {
  {
    source: "",
    trello: false,
    preview: None,
    owner: "",
    name: "",
    note: "",
    append_before: None,
    append_after: None,
  }
}

///|
fn plan_template_update(
  action : PlanTemplateMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let t = s.template
  let next = match action {
    Source(source) => { ..plan_template_initial(), source, }
    Owner(owner) => { ..t, owner, append_before: None, append_after: None, }
    Name(name) => { ..t, name, append_before: None, append_after: None, }
    Close => plan_template_initial()
    Preview | PreviewTrello => {
      let preview = try {
        if action == PreviewTrello {
          plan_trello_read_template(t.source)
        } else {
          @plan_workbench.read_template(t.source)
        }
      } catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                template: {
                  ..t,
                  preview: None,
                  owner: "",
                  note,
                  append_before: None,
                  append_after: None,
                },
              },
            },
          )
      }
      {
        ..t,
        preview: Some(preview),
        trello: action == PreviewTrello,
        owner: "",
        name: d.owners
        .filter(o => o.id == s.actor)
        .get(0)
        .map(o => o.name)
        .unwrap_or(""),
        note: "选择你在模板中的负责人，再填写本项目使用的姓名。",
        append_before: None,
        append_after: None,
      }
    }
    PreviewAppend => {
      guard t.preview is Some(preview) else { return (none, model) }
      let after = @plan_workbench.append_template(
        preview,
        d,
        s.actor,
        t.owner,
        plan_nonce(),
      ) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                template: {
                  ..t,
                  note,
                  append_before: None,
                  append_after: None,
                },
              },
            },
          )
      }
      let after = if t.trello {
        { ..after, notes: d.notes + "\n\n" + preview.notes, }
      } else {
        after
      }
      {
        ..t,
        append_before: Some(d),
        append_after: Some(after),
        note: "阶段追加预览已生成，尚未更改草稿。请查看新增内容与完整合并结果。",
      }
    }
    ApplyAppend => {
      guard t.append_before is Some(before) && t.append_after is Some(after) else {
        return (none, model)
      }
      guard before == d else {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              template: {
                ..t,
                append_before: None,
                append_after: None,
                note: "草稿已变化，请重新预览追加阶段。",
              },
            },
          },
        )
      }
      let edited = plan_save_edit(s, after)
      return (
        none,
        {
          ..model,
          plan: {
            ..edited,
            template: plan_template_initial(),
            note: edited.note +
            " 已追加模板阶段，原有内容与预算不变；新增行仍可编辑。",
          },
        },
      )
    }
    Download | DownloadReview => {
      let exported = @plan_workbench.export_template(d) catch {
        @plan_workbench.Invalid(note) =>
          return (none, { ..model, plan: { ..s, template: { ..t, note, }, }, })
      }
      return (
        @cmd.custom_cmd(_ => {
          if action == DownloadReview {
            plan_download(plan_review_html(exported), "plan-review.html", false)
          } else {
            plan_download(exported, "plan-template.json", true)
          }
        }),
        model,
      )
    }
    Apply => {
      guard t.preview is Some(preview) else { return (none, model) }
      let draft = @plan_workbench.apply_template(
        preview,
        d,
        s.actor,
        t.owner,
        t.name,
        plan_nonce(),
      ) catch {
        @plan_workbench.Invalid(note) =>
          return (none, { ..model, plan: { ..s, template: { ..t, note, }, }, })
      }
      let edited = plan_save_edit(s, draft)
      return (
        none,
        {
          ..model,
          plan: {
            ..edited,
            template: plan_template_initial(),
            task_table: "",
            task_finder: plan_task_finder_initial(),
            extract: plan_extract_initial(),
            milestone_table: plan_milestone_table_initial(),
            risk_table: plan_risk_table_initial(),
            task_table_owner: s.actor,
            task_table_milestone: draft.milestones
            .get(0)
            .map(m => m.id)
            .unwrap_or(""),
            dependency_focus: "",
            note: edited.note +
            " 已用模板替换草稿。日期、成本、职责和验收文字保持原值；请按当前项目编辑。",
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, template: next, }, })
}

///|
fn plan_template_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
) -> @html.Html {
  let t = s.template
  section(class="section-block") <| [
    h3("复用完整计划模板"),
    p(
      "下载当前编辑内容，或粘贴模板在本项目继续编制。模板包含范围、负责人、任务、依赖、里程碑、验收标准、所需证据和风险；不包含原项目、请求或保存记录标识。文字可能含私人信息，分享前请检查。",
    ),
    plan_button(emit, Template(Download), "下载可复用计划模板 (.json)"),
    plan_button(
      emit,
      Template(DownloadReview),
      "下载离线计划审阅表 (.html)",
    ),
    p(
      "离线审阅表包含当前完整模板。审阅意见可另存 JSON 后重新加载；不代表计划批准或公司事实。分享前检查私人信息。",
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-template-source"),
        "计划模板 JSON",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-template-source"),
        value=t.source,
        on_input=emit.map(v => PlanAction(Template(Source(v)))),
        "",
      ),
    ],
    plan_button(
      emit,
      Template(Preview),
      "预览模板",
      disabled=t.source.trim().is_empty(),
    ),
    plan_button(
      emit,
      Template(PreviewTrello),
      "预览 Trello 看板 JSON",
      disabled=t.source.trim().is_empty(),
    ),
    p(
      "也可粘贴本地 Trello 看板导出 JSON，再选择预览 Trello。仅导入未归档列表中的未归档卡片；原负责人、截止日期和完成标记只保留为来源说明。请明确填写规划负责人、里程碑和预算。追加 Trello 工作时，来源说明会附加到当前范围说明。",
    ),
    plan_button(emit, Template(Close), "清空模板输入"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match t.preview {
      None => @html.nothing
      Some(preview) =>
        div <| [
          p(
            "模板：" +
            preview.owners.length().to_string() +
            " 位负责人 · " +
            preview.tasks.length().to_string() +
            " 个任务 · " +
            preview.milestones.length().to_string() +
            " 个里程碑 · " +
            preview.risks.length().to_string() +
            " 个风险",
          ),
          @html.details <| [
            @html.summary("查看完整模板内容"),
            @html.pre(preview.to_json().stringify(indent=2)),
          ],
          p("模板范围与上下文 / Template scope and context"),
          @html.pre(preview.notes),
          strong(
            "你在模板中接替哪位负责人？该行姓名使用下方填写值，职责和全部引用保留。",
          ),
          div(class="tag-row") <| preview.owners.map(o => {
            plan_button(
              emit,
              Template(Owner(o.id)),
              o.name + " · " + o.role + " (" + o.id + ")",
              selected=t.owner == o.id,
            )
          }),
          div(class="field") <| [
            label(
              attrs=@html.Attrs::build().for_("plan-template-name"),
              "你在本项目使用的姓名",
            ),
            input(
              input_type=Text,
              attrs=@html.Attrs::build().id("plan-template-name"),
              value=t.name,
              on_input=emit.map(v => PlanAction(Template(Name(v)))),
            ),
          ],
          p(
            "下面的操作替换当前浏览器草稿，原生保存历史不变。日期与金额照原样导入，不自动顺延、不换汇；其他负责人姓名和职责保留为可编辑文本。先下载当前模板可保留副本。导入不会发起原生保存或创建正式任务。",
          ),
          plan_button(
            emit,
            Template(Apply),
            "用模板替换当前草稿",
            disabled=t.owner.is_empty() || t.name.trim().is_empty(),
          ),
          h3("追加为新阶段 / Append reusable phase"),
          p(
            "保留当前草稿全部原有行、范围说明、币种、预算和预备费。模板任务、里程碑、验收要求与风险追加在后，引用一并重新编号。所选负责人映射到当前编制人，保留本项目姓名与职责（不使用上面的姓名输入）；其他负责人新增为可编辑行。模板范围说明及预算不导入。日期与成本原文保留，不建立跨阶段依赖、不自动换汇或顺延。",
          ),
          plan_button(
            emit,
            Template(PreviewAppend),
            "预览追加阶段 / Preview phase append",
            disabled=t.owner.is_empty(),
          ),
          match (t.append_before, t.append_after) {
            (Some(before), Some(after)) if s.draft == Some(before) =>
              div <| [
                p(
                  "新增：" +
                  (after.owners.length() - before.owners.length()).to_string() +
                  " 位负责人 · " +
                  (after.tasks.length() - before.tasks.length()).to_string() +
                  " 个任务 · " +
                  (after.milestones.length() - before.milestones.length()).to_string() +
                  " 个里程碑 · " +
                  (after.risks.length() - before.risks.length()).to_string() +
                  " 个风险。当前编制人的姓名与职责保持原值。",
                ),
                @html.details <| [
                  @html.summary(
                    "查看追加后的完整草稿 / Complete combined draft",
                  ),
                  @html.pre(after.to_json().stringify(indent=2)),
                ],
                p(
                  "追加只写入此浏览器草稿。请检查新增阶段是否符合项目范围与总预算，再单独准备原生计划；此处不保存原生版本、不派发正式任务。",
                ),
                plan_button(
                  emit,
                  Template(ApplyAppend),
                  "应用阶段追加 / Apply phase append",
                ),
              ]
            _ => @html.nothing
          },
        ]
    },
  ]
}
