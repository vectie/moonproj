///|
fn plan_dependency_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let graph = @plan_workbench.dependency_plan(d, s.dependency_focus)
  section(class="section-block") <| [
    h3("Dependency planning explorer"),
    p(
      "Explore parallel-ready waves and the impact of a task. Waves describe precedence only; shared owners may still need to sequence work. No duration or completion dates are inferred.",
    ),
    plan_button(
      emit,
      OrderDependencies,
      "Order tasks by dependencies",
      disabled=d.tasks.is_empty() || !graph.issues.is_empty(),
    ),
    plan_button(
      emit,
      ExportDependencies,
      "Download dependency plan",
      disabled=d.tasks.is_empty(),
    ),
    plan_button(
      emit,
      ExportDependencyDiagram,
      "Download dependency map (.svg)",
      disabled=d.tasks.is_empty() || !graph.issues.is_empty(),
    ),
    plan_button(
      emit,
      DependencyFocus(""),
      "Clear task focus",
      disabled=s.dependency_focus.is_empty(),
    ),
    div <| graph.issues.map(issue => p(issue)),
    if d.tasks.is_empty() {
      p("Add or import tasks to explore the plan.")
    } else {
      @html.nothing
    },
    div <| graph.waves.mapi((i, wave) => {
      article(class="repo-card") <| [
        h3("Wave " + (i + 1).to_string()),
        div(class="tag-row") <| wave.map(id => {
          let name = d.tasks
            .filter(t => t.id == id)
            .get(0)
            .map(t => t.name)
            .unwrap_or(id)
          plan_button(
            emit,
            DependencyFocus(id),
            id + " · " + name,
            selected=s.dependency_focus == id,
          )
        }),
      ]
    }),
    plan_diagram_view(s, d),
    h3("Task impact"),
    div(class="tag-row") <| d.tasks.map(t => {
      plan_button(
        emit,
        DependencyFocus(t.id),
        t.name,
        selected=s.dependency_focus == t.id,
      )
    }),
    if d.tasks.any(t => t.id == s.dependency_focus) {
      div <| [
        p("Selected task: " + s.dependency_focus),
        p(
          "All prerequisites (" +
          graph.prerequisites.length().to_string() +
          "): " +
          graph.prerequisites.join(", "),
        ),
        p(
          "Downstream tasks affected by a delay (" +
          graph.downstream.length().to_string() +
          "): " +
          graph.downstream.join(", "),
        ),
        p(
          "Affected milestones: " +
          d.milestones
          .filter(m => {
            d.tasks.any(t => {
              (graph.downstream.contains(t.id) || t.id == s.dependency_focus) &&
              t.milestone == m.id
            })
          })
          .map(m => m.name)
          .join(", "),
        ),
      ]
    } else {
      p("Select a task to trace its prerequisites and downstream work.")
    },
  ]
}
