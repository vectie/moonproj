///|
fn plan_consolidation_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let c = s.consolidation
  @html.details <| [
    @html.summary("合并任务 / Consolidate tasks"),
    p(
      "Combine overlapping or overly detailed tasks after importing or editing a plan. Select at least two tasks with the same owner and milestone. Keep one selected ID and write a combined scope name. Their costs are added exactly; this does not remove duplicated cost estimates automatically.",
    ),
    p(
      "Internal dependency links collapse. External prerequisites, followers and risk links are retained, with duplicate links removed. Task order may change to keep prerequisites first. Only the local draft changes; saved versions remain in history.",
    ),
    div <| d.tasks.map(task => {
      plan_button(
        emit,
        Consolidation(Toggle(task.id)),
        (if c.selected.contains(task.id) {
          "Selected / 已选 · "
        } else {
          "Select / 选择 · "
        }) +
        task.name +
        " · " +
        task.id +
        " · " +
        task.cost +
        " " +
        d.currency +
        " · Owner: " +
        task.owner +
        " · Milestone: " +
        task.milestone,
        selected=c.selected.contains(task.id),
      )
    }),
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      "Selected tasks: " + c.selected.length().to_string(),
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-consolidation-retained"),
        "保留任务 ID / Task ID to retain",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-consolidation-retained"),
        on_change=emit.map(id => PlanAction(Consolidation(Retain(id)))),
      ) <| [
        @html.option(
          value="",
          selected=c.retained.is_empty(),
          "Choose a selected task",
        ),
        ..d.tasks
        .filter(t => c.selected.contains(t.id))
        .map(t => {
          @html.option(
            value=t.id,
            selected=c.retained == t.id,
            t.name + " · " + t.id,
          )
        }),
      ],
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-consolidation-name"),
        "合并后范围名称 / Combined scope name",
      ),
      input(
        input_type=Text,
        attrs=@html.Attrs::build().id("plan-consolidation-name"),
        value=c.name,
        on_input=emit.map(name => PlanAction(Consolidation(Name(name)))),
      ),
    ],
    plan_button(
      emit,
      Consolidation(Preview),
      "预览合并 / Preview consolidation",
      disabled=c.selected.length() < 2,
    ),
    plan_button(
      emit,
      Consolidation(Close),
      "取消合并 / Cancel consolidation",
    ),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), c.note),
    match (c.source, c.preview) {
      (Some(source), Some(preview)) if source == d => {
        let merged = preview.tasks.filter(t => t.id == c.retained)[0]
        div <| [
          h3("Preview: combined task"),
          p("Kept ID: " + merged.id + " · Name: " + merged.name),
          p(
            "Combined cost: " +
            merged.cost +
            " " +
            d.currency +
            " · Owner: " +
            merged.owner +
            " · Milestone: " +
            merged.milestone,
          ),
          p("External prerequisites: " + merged.dependencies.join(", ")),
          p(
            "Removed task IDs: " +
            c.selected.filter(id => id != c.retained).join(", "),
          ),
          h3("Original task scopes and amounts"),
          div <| source.tasks
          .filter(t => c.selected.contains(t.id))
          .map(t => {
            p(t.id + " · " + t.name + " · " + t.cost + " " + d.currency)
          }),
          h3("Updated follower dependencies"),
          div <| source.tasks
          .filter(t => {
            !c.selected.contains(t.id) &&
            t.dependencies.any(id => c.selected.contains(id))
          })
          .map(t => {
            let next = preview.tasks.filter(other => other.id == t.id)[0]
            p(
              t.id +
              " · " +
              t.name +
              ": " +
              t.dependencies.join(", ") +
              " → " +
              next.dependencies.join(", "),
            )
          }),
          h3("Consolidated risk links"),
          div <| source.risks.mapi((i, r) => {
            if r.tasks.any(id => c.selected.contains(id)) {
              p(
                r.id +
                " · " +
                r.summary +
                ": " +
                r.tasks.join(", ") +
                " → " +
                preview.risks[i].tasks.join(", "),
              )
            } else {
              @html.nothing
            }
          }),
          h3("Resulting dependency order"),
          div <| preview.tasks.mapi((i, t) => {
            p((i + 1).to_string() + ". " + t.id + " · " + t.name)
          }),
          p(
            "Plan cost and budget are unchanged. Only the chosen ID and combined name survive as task identity and title; review the original scopes above before applying. Apply saves locally and requires a new native prepare/save. Existing saved versions are unchanged.",
          ),
          plan_button(
            emit,
            Consolidation(Apply),
            "应用任务合并 / Apply consolidation",
          ),
        ]
      }
      _ => @html.nothing
    },
  ]
}
