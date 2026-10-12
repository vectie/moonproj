///|
extern "js" fn plan_diagram_download(text : String) =
  #| text => { const u = URL.createObjectURL(new Blob([text], {type: "image/svg+xml;charset=utf-8"})); const a = document.createElement("a"); a.href = u; a.download = "plan-dependencies.svg"; a.click(); setTimeout(() => URL.revokeObjectURL(u), 1000); }

///|
fn plan_diagram_export(model : Model) -> (Cmd, Model) {
  let s = model.plan
  guard model.page == Projects &&
    s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
    return (none, model)
  }
  let svg = @plan_workbench.export_dependency_svg(
    d,
    project.name,
    s.dependency_focus,
  ) catch {
    @plan_workbench.Invalid(message) =>
      return (none, { ..model, plan: { ..s, note: message, }, })
  }
  (@cmd.custom_cmd(_ => plan_diagram_download(svg)), model)
}

///|
fn plan_diagram_view(
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  guard d.project_id == s.selected &&
    s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
    return @html.nothing
  }
  let svg = @plan_workbench.export_dependency_svg(
    d,
    project.name,
    s.dependency_focus,
  ) catch {
    @plan_workbench.Invalid(message) => return p("Dependency map: " + message)
  }
  @html.details <| [
    @html.summary("Visual dependency map / 可视化依赖图"),
    p(
      "The complete graph is retained. Select a task above to label prerequisites and downstream impact. Long links route below the cards. Download the standalone SVG for a document or offline review.",
    ),
    div(style=["overflow: auto", "max-height: 640px"]) <| [
      @html.img(
        src="data:image/svg+xml;charset=utf-8," + dispatch_url_encode(svg),
        alt="Project dependency map for " +
          project.name +
          ". Arrows run from prerequisite to dependent. The same waves and selected-task relationships are listed in text above.",
        style=["max-width: none"],
      ),
    ],
  ]
}
