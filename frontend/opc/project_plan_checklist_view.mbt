///|
fn plan_checklist_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let t = s.checklist
  @html.details <| [
    @html.summary("Markdown checklist / Markdown 清单导入"),
    p(
      "Paste one-line checkbox list items: - [ ] Task, * [x] Task, + [ ] Task, or 1. [ ] Task. Headings and nested list parents become task-name context. Fenced code, quotes and HTML comments are excluded. Ordinary prose and continuation lines stay in the original source notes; they do not become tasks.",
    ),
    p(
      "Only unchecked items are included by default. Including checked items plans them again; it never records completion. All new tasks start with cost 0 and no dependencies. Indentation is context, not an execution dependency; use fenced code for code examples.",
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-checklist-source"),
        "Markdown source",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-checklist-source"),
        value=t.text,
        on_input=emit.map(text => PlanAction(Checklist(Text(text)))),
        "",
      ),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-checklist-owner"),
        "Assign all new tasks to owner",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-checklist-owner"),
        on_change=emit.map(id => PlanAction(Checklist(Owner(id)))),
      ) <| [
        @html.option(value="", selected=t.owner.is_empty(), "Choose owner"),
        ..d.owners.map(o => {
          @html.option(
            value=o.id,
            selected=t.owner == o.id,
            o.name + " [" + o.id + "]",
          )
        }),
      ],
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-checklist-milestone"),
        "Assign all new tasks to milestone",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-checklist-milestone"),
        on_change=emit.map(id => PlanAction(Checklist(Milestone(id)))),
      ) <| [
        @html.option(
          value="",
          selected=t.milestone.is_empty(),
          "Choose milestone",
        ),
        ..d.milestones.map(m => {
          @html.option(
            value=m.id,
            selected=t.milestone == m.id,
            m.name + " [" + m.id + "]",
          )
        }),
      ],
    ],
    div(class="tag-row") <| [
      plan_button(
        emit,
        Checklist(IncludeChecked(false)),
        "Unchecked items only",
        selected=!t.include_checked,
      ),
      plan_button(
        emit,
        Checklist(IncludeChecked(true)),
        "Include checked items as planned",
        selected=t.include_checked,
      ),
    ],
    plan_button(
      emit,
      Checklist(Preview),
      "Preview checklist tasks",
      disabled=t.text.trim().is_empty() ||
        t.owner.is_empty() ||
        t.milestone.is_empty(),
    ),
    plan_button(emit, Checklist(Close), "Close checklist preview"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), t.note),
    match (t.base, t.preview) {
      (Some(base), Some(preview)) if base == d =>
        div <| [
          h3("Checklist append preview"),
          p(
            "New planned tasks: " +
            preview.entries.length().to_string() +
            "; checked items skipped: " +
            preview.skipped_checked.to_string(),
          ),
          div <| preview.entries.map(e => {
            article(class="repo-card") <| [
              strong("Line " + e.line.to_string() + " · " + e.task.name),
              p(
                "Source checkbox: " +
                (if e.checked {
                  "checked; will be planned again"
                } else {
                  "unchecked"
                }),
              ),
              p(
                "New ID: " +
                e.task.id +
                " · Owner: " +
                e.task.owner +
                " · Milestone: " +
                e.task.milestone +
                " · Initial planned cost: 0 " +
                d.currency,
              ),
            ]
          }),
          @html.details <| [
            @html.summary("Original source retained verbatim in scope notes"),
            @html.pre(t.text),
          ],
          p(
            "Append keeps the existing tasks and stores the complete source and line-to-task mapping in this browser draft. Saved plan versions and formal company tasks stay unchanged.",
          ),
          plan_button(emit, Checklist(Apply), "Append checklist tasks"),
        ]
      _ => @html.nothing
    },
  ]
}
