///|
fn plan_handoff_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let h = s.handoff
  @html.details <| [
    @html.summary("从计划任务起草工作 / Plan task to Dispatch draft"),
    p(
      "Carry one task's scope, source, prerequisites, linked risks and milestone criteria into an editable task draft. This snapshot does not track completion or create formal work.",
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-handoff-task"),
        "选择计划任务 / Plan task",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-handoff-task"),
        on_change=emit.map(id => PlanAction(Handoff(Select(id)))),
      ) <| [
        @html.option(value="", selected=h.task_id.is_empty(), "Choose a task"),
        ..d.tasks.map(t => {
          @html.option(
            value=t.id,
            selected=h.task_id == t.id,
            t.name + " · " + t.id,
          )
        }),
      ],
    ],
    plan_button(
      emit,
      Handoff(Preview),
      "预览任务草稿 / Preview task draft",
      disabled=h.task_id.is_empty(),
    ),
    plan_button(emit, Handoff(Close), "取消 / Cancel task handoff"),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), h.note),
    match (h.source, h.preview) {
      (Some(source), Some(preview)) if source == d =>
        div <| [
          h3("Task draft preview"),
          p("Target project: " + d.project_id),
          ..[
            ("Title", preview.title),
            ("Source snapshot reference", preview.source_reference),
            ("Acceptance context to adapt", preview.acceptance),
            ("Scope, prerequisites and risks", preview.context),
            ("Due date (authored text)", preview.end_date),
          ].map(pair => {
            div <| [
              strong(pair.0),
              @html.pre(
                class="human-revision-content",
                if pair.1.is_empty() {
                  "Not supplied; fill in the task draft."
                } else {
                  pair.1
                },
              ),
            ]
          }),
          p(
            "The plan and existing drafts stay intact. The new draft has a fresh identity. Owner, start date and execution settings are blank; planned owners are context only. No dependency completion is inferred and no dependency enforcement is installed. Later plan edits do not update this snapshot.",
          ),
          plan_button(
            emit,
            Handoff(CreateDraft),
            "另建任务草稿 / Create local task draft",
          ),
        ]
      _ => @html.nothing
    },
  ]
}
