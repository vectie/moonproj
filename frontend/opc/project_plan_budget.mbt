///|
fn plan_budget_breakdown_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let project = s.projects
    .filter(p => p.id == s.selected)
    .get(0)
    .map(p => p.name)
    .unwrap_or(s.selected)
  section(class="section-block") <| [
    h3("草稿成本分配 / Budget breakdown"),
    p(
      "按任务负责人和里程碑汇总成本；未填写或无效金额不会视为零。仅为规划，不是审批或账目。",
    ),
    plan_button(emit, ExportBudgetBreakdown, "下载成本分配 (.txt)"),
    @html.pre(
      class="human-revision-content",
      @plan_workbench.budget_report(d, project),
    ),
  ]
}
