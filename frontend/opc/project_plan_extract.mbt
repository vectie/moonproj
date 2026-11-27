///|
#derive(Debug, Eq)
struct PlanExtractState {
  tasks : Array[String]
  milestone : String
  source : @plan_workbench.Draft?
  preview : @plan_workbench.PhaseExtraction?
  note : String
}

///|
#derive(Debug, Eq)
enum PlanExtractMsg {
  Task(String)
  Milestone(String)
  Preview
  Download
  Close
}

///|
fn plan_extract_initial() -> PlanExtractState {
  { tasks: [], milestone: "", source: None, preview: None, note: "", }
}

///|
fn plan_extract_update(action : PlanExtractMsg, model : Model) -> (Cmd, Model) {
  let s = model.plan
  guard !s.actor.is_empty() &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let e = s.extract
  let next = match action {
    Task(id) => {
      if !d.tasks.any(t => t.id == id) {
        return (none, model)
      }
      {
        ..e,
        tasks: plan_toggle(e.tasks, id),
        source: None,
        preview: None,
        note: "",
      }
    }
    Milestone(id) => {
      if !id.is_empty() && !d.milestones.any(m => m.id == id) {
        return (none, model)
      }
      { ..e, milestone: id, source: None, preview: None, note: "", }
    }
    Close => plan_extract_initial()
    Preview => {
      let preview = @plan_workbench.extract_phase(d, e.tasks, e.milestone) catch {
        @plan_workbench.Invalid(note) =>
          return (
            none,
            {
              ..model,
              plan: {
                ..s,
                extract: { ..e, source: None, preview: None, note, },
              },
            },
          )
      }
      {
        ..e,
        source: Some(d),
        preview: Some(preview),
        note: "只读预览；草稿、存储与已准备计划保持不变。",
      }
    }
    Download => {
      guard e.source is Some(source) && e.preview is Some(preview) else {
        return (none, model)
      }
      if source != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              extract: {
                ..e,
                source: None,
                preview: None,
                note: "草稿已变化，请重新预览阶段。",
              },
            },
          },
        )
      }
      return (
        @cmd.custom_cmd(_ => {
          plan_download(preview.json, "plan-phase-template.json", true)
        }),
        model,
      )
    }
  }
  (none, { ..model, plan: { ..s, extract: next, }, })
}

///|
fn plan_extract_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let e = s.extract
  @html.details <| [
    @html.summary("提取可复用阶段 / Extract reusable phase"),
    p(
      "选择任务，或选择一个里程碑的全部任务；两者取并集。预览会自动加入所有前置任务，不加入下游任务。文字可能含私人信息，分享前请检查。",
    ),
    p("任务选择 / Tasks"),
    div(class="tag-row") <| d.tasks.map(t => {
      plan_button(
        emit,
        Extract(Task(t.id)),
        t.name + " [" + t.id + "]",
        selected=e.tasks.contains(t.id),
      )
    }),
    p("里程碑选择 / Milestone"),
    plan_button(
      emit,
      Extract(Milestone("")),
      "不按里程碑选择",
      selected=e.milestone.is_empty(),
    ),
    div(class="tag-row") <| d.milestones.map(m => {
      plan_button(
        emit,
        Extract(Milestone(m.id)),
        m.name + " [" + m.id + "]",
        selected=e.milestone == m.id,
      )
    }),
    plan_button(
      emit,
      Extract(Preview),
      "预览阶段 / Preview phase",
      disabled=e.tasks.is_empty() && e.milestone.is_empty(),
    ),
    plan_button(emit, Extract(Close), "清空阶段选择"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), e.note),
    match (e.source, e.preview) {
      (Some(source), Some(preview)) if source == d => {
        let t = @plan_workbench.read_template(preview.json) catch {
          _ => return @html.nothing
        }
        div <| [
          p("主动选择 / Selected: " + preview.selected.length().to_string()),
          div <| d.tasks
          .filter(t => preview.selected.contains(t.id))
          .map(t => p(t.name + " [" + t.id + "]")),
          p(
            "自动加入的前置任务 / Automatically included prerequisites: " +
            preview.prerequisites.length().to_string(),
          ),
          div <| d.tasks
          .filter(t => preview.prerequisites.contains(t.id))
          .map(t => p(t.name + " [" + t.id + "]")),
          p("相关负责人 / Owners: " + t.owners.length().to_string()),
          div <| t.owners.map(o => p(o.name + " · " + o.role)),
          p(
            "相关里程碑 / Milestones: " + t.milestones.length().to_string(),
          ),
          div <| t.milestones.map(m => {
            p(
              m.name +
              " · " +
              m.date +
              " · " +
              m.criteria +
              " · " +
              m.evidence,
            )
          }),
          p(
            "完整包含的风险 / Included risks: " +
            t.risks.length().to_string(),
          ),
          div <| t.risks.map(r => {
            p(r.summary + " · " + r.severity + " · " + r.mitigation)
          }),
          p(
            "省略风险 / Omitted risks: " +
            preview.omitted_risk_count.to_string() +
            ". Cross-scope and unscoped risks are context only below; unrelated risks are excluded.",
          ),
          @html.pre(t.notes),
          p(
            "项目范围及总预算未复制。模板预算和预备费留空，币种仅保留任务成本单位。替换草稿后需填写范围和预算；追加保留目标范围和预算，且不复制模板说明。请在追加预览中查看这些上下文限制，必要时手动记录。",
          ),
          @html.details <| [
            @html.summary("完整阶段模板 / Complete phase template"),
            @html.pre(preview.json),
          ],
          plan_button(
            emit,
            Extract(Download),
            "下载阶段模板 / Download phase template (.json)",
          ),
        ]
      }
      _ => @html.nothing
    },
  ]
}
