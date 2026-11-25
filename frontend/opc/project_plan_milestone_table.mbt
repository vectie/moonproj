///|
struct PlanMilestoneTableState {
  text : String
  tsv : Bool
  import_new : Bool
  base : @plan_workbench.Draft?
  preview : @plan_workbench.MilestoneTableUpdate?
  import_preview : @plan_workbench.MilestoneTableImport?
  note : String
} derive(Debug, Eq)

///|
enum PlanMilestoneTableMsg {
  Text(String)
  Format(Bool)
  ImportMode(Bool)
  Preview
  Apply
  Close
  Export
} derive(Debug, Eq)

///|
fn plan_milestone_table_initial() -> PlanMilestoneTableState {
  {
    text: "",
    tsv: false,
    import_new: false,
    base: None,
    preview: None,
    import_preview: None,
    note: "",
  }
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
    Text(text) =>
      { ..t, text, base: None, preview: None, import_preview: None, note: "", }
    Format(tsv) =>
      { ..t, tsv, base: None, preview: None, import_preview: None, note: "", }
    ImportMode(import_new) =>
      {
        ..t,
        import_new,
        base: None,
        preview: None,
        import_preview: None,
        note: "",
      }
    Close => { ..t, base: None, preview: None, import_preview: None, note: "", }
    Export => {
      let csv = @plan_workbench.export_milestone_table(d)
      return (
        @cmd.custom_cmd(_ => plan_download(csv, "plan-milestones.csv", false)),
        model,
      )
    }
    Preview if t.import_new => {
      let preview = @plan_workbench.preview_milestone_table_import(
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
                milestone_table: {
                  ..t,
                  base: None,
                  preview: None,
                  import_preview: None,
                  note,
                },
              },
            },
          )
      }
      {
        ..t,
        base: Some(d),
        preview: None,
        import_preview: Some(preview),
        note: "Preview only. Apply to add these milestones to the local draft.",
      }
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
                milestone_table: {
                  ..t,
                  base: None,
                  preview: None,
                  import_preview: None,
                  note,
                },
              },
            },
          )
      }
      {
        ..t,
        base: Some(d),
        preview: Some(preview),
        import_preview: None,
        note: "Preview only. Apply edits to update the local draft.",
      }
    }
    Apply if t.import_new => {
      guard t.base is Some(base) && t.import_preview is Some(preview) else {
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
                import_preview: None,
                note: "The draft changed. Preview the milestone import again.",
              },
            },
          },
        )
      }
      if preview.additions.is_empty() {
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
            " Added " +
            preview.additions.length().to_string() +
            " milestones with their source IDs; existing rows and task links retained.",
          },
        },
      )
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
                import_preview: None,
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
      if t.import_new {
        "将已有路线图导入草稿，包括空的里程碑列表。先检查预览，再应用新增；不会自动准备、保存原生计划或创建任务。"
      } else {
        "下载 CSV，在表格中编辑后粘贴回来。按现有 id 更新；未列出的行或列保持不变。独立修改日期不会平移其他里程碑，关联任务保持原样。"
      },
    ),
    div(class="tag-row") <| [
      plan_button(
        emit,
        MilestoneTable(ImportMode(false)),
        "编辑现有里程碑 / Edit existing milestones",
        selected=!t.import_new,
      ),
      plan_button(
        emit,
        MilestoneTable(ImportMode(true)),
        "导入新里程碑 / Import new milestones",
        selected=t.import_new,
      ),
    ],
    if t.import_new {
      p(
        "新导入需要 id、title、owner 列；保留来源 ID，方便后续任务 CSV 引用。date、criteria、evidence 可省略并留空。已有且所有字段相同的 ID 跳过；不同则拒绝，请切换现有编辑。新增行按输入顺序追加，合计最多 40 个里程碑。",
      )
    } else {
      @html.nothing
    },
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
      if t.import_new {
        "预览新里程碑 / Preview new milestones"
      } else {
        "预览里程碑修改 / Preview milestone edits"
      },
      disabled=t.text.trim().is_empty(),
    ),
    plan_button(
      emit,
      MilestoneTable(Close),
      "关闭修改预览 / Close preview",
    ),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.base, t.import_preview) {
      (Some(base), Some(preview)) if t.import_new && base == d =>
        div <| [
          h3("新里程碑预览 / New milestone preview"),
          p(
            preview.additions.length().to_string() +
            " new milestones; " +
            preview.unchanged.length().to_string() +
            " identical existing rows skipped.",
          ),
          p(
            "Ignored columns: " +
            (if preview.ignored.is_empty() {
              "None"
            } else {
              preview.ignored.join(", ")
            }),
          ),
          p(
            "Unchanged existing IDs: " +
            (if preview.unchanged.is_empty() {
              "None"
            } else {
              preview.unchanged.join(", ")
            }),
          ),
          div <| preview.additions.map(m => {
            @html.details <| [
              @html.summary(m.id + " · " + m.name),
              @html.pre(ToJson::to_json(m).stringify(indent=2)),
            ]
          }),
          plan_button(
            emit,
            MilestoneTable(Apply),
            "应用新增里程碑 / Apply new milestones",
            disabled=preview.additions.is_empty(),
          ),
        ]
      _ => @html.nothing
    },
    match (t.base, t.preview) {
      (Some(base), Some(preview)) if !t.import_new && base == d =>
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
              @html.pre(ToJson::to_json(change.before).stringify(indent=2)),
              strong("After / 修改后"),
              @html.pre(ToJson::to_json(change.after).stringify(indent=2)),
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
