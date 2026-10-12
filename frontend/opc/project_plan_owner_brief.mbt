///|
fn plan_owner_brief_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let project = s.projects
    .filter(p => p.id == s.selected)
    .get(0)
    .map(p => p.name)
    .unwrap_or(s.selected)
  let brief = @plan_workbench.owner_brief(d, s.brief_owner, project) catch {
    _ => ""
  }
  section(class="section-block") <| [
    h3("负责人计划简报"),
    p(
      "按负责人查看任务、里程碑、风险与跨负责人交接。仅查看和下载，不派发任务。",
    ),
    div(class="tag-row") <| d.owners.map(o => {
      plan_button(
        emit,
        BriefOwner(o.id),
        o.name + " · " + o.role,
        selected=s.brief_owner == o.id,
      )
    }),
    plan_button(
      emit,
      ExportOwnerBrief,
      "下载负责人简报 (.txt)",
      disabled=brief.is_empty(),
    ),
    if brief.is_empty() {
      p("请选择当前计划中的负责人。")
    } else {
      @html.pre(class="human-revision-content", brief)
    },
  ]
}
