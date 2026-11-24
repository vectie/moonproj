///|
fn plan_risk_impact_export(model : Model) -> (Cmd, Model) {
  let s = model.plan
  guard model.page == Projects &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
    return (none, model)
  }
  let report = @plan_workbench.risk_impact_report(d, s.risk_focus, project.name) catch {
    @plan_workbench.Invalid(message) =>
      return (none, { ..model, plan: { ..s, note: message, }, })
  }
  (
    @cmd.custom_cmd(_ => plan_download(report, "plan-risk-impact.txt", false)),
    model,
  )
}

///|
fn plan_risk_impact_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  guard d.project_id == s.selected &&
    s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
    return @html.nothing
  }
  let report = Ok(
    @plan_workbench.risk_impact_report(d, s.risk_focus, project.name),
  ) catch {
    e => Err(e)
  }
  @html.details <| [
    @html.summary("Risk impact explorer / 风险影响分析"),
    p(
      "Select a risk to trace its linked tasks and all downstream work, with unique task costs and affected owners/milestones. Edit links and estimates below; this view updates from the current draft.",
    ),
    div(class="tag-row") <| d.risks.map(r => {
      plan_button(
        emit,
        RiskFocus(r.id),
        r.id + " · " + r.summary,
        selected=s.risk_focus == r.id,
      )
    }),
    plan_button(
      emit,
      RiskFocus(""),
      "Clear risk selection",
      disabled=s.risk_focus.is_empty(),
    ),
    plan_button(
      emit,
      ExportRiskImpact,
      "Download risk impact brief (.txt)",
      disabled=report is Err(_),
    ),
    match report {
      Ok(text) => @html.pre(style=["white-space: pre-wrap"], text)
      Err(@plan_workbench.Invalid(message)) =>
        if s.risk_focus.is_empty() {
          p(
            if d.risks.is_empty() {
              "Add or import a risk and link its tasks below to explore impact."
            } else {
              "Select a risk to inspect its planning impact."
            },
          )
        } else {
          p(message)
        }
    },
  ]
}
