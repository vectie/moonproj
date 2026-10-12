///|
struct PlanTextReplaceState {
  query : String
  replacement : String
  scope : String
  base : @plan_workbench.Draft?
  preview : @plan_workbench.PlanTextReplacement?
  note : String
} derive(Debug, Eq)

///|
enum PlanTextReplaceMsg {
  Query(String)
  Replacement(String)
  Scope(String)
  Preview
  Apply
  Close
} derive(Debug, Eq)

///|
fn plan_text_replace_initial() -> PlanTextReplaceState {
  {
    query: "",
    replacement: "",
    scope: "all",
    base: None,
    preview: None,
    note: "",
  }
}

///|
fn plan_text_replace_update(
  action : PlanTextReplaceMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let current = s.text_replace
  let cleared = { ..current, base: None, preview: None, note: "", }
  let next = match action {
    Query(query) => { ..cleared, query, }
    Replacement(replacement) => { ..cleared, replacement, }
    Scope(scope) => { ..cleared, scope, }
    Close => cleared
    Preview => {
      let preview = @plan_workbench.preview_plan_text_replacement(
        d,
        current.query,
        current.replacement,
        current.scope,
      ) catch {
        @plan_workbench.Invalid(message) =>
          return (
            none,
            {
              ..model,
              plan: { ..s, text_replace: { ..cleared, note: message, }, },
            },
          )
      }
      { ..cleared, base: Some(d), preview: Some(preview), }
    }
    Apply => {
      guard current.base is Some(base) && current.preview is Some(preview) else {
        return (none, model)
      }
      if base != d {
        return (
          none,
          {
            ..model,
            plan: {
              ..s,
              text_replace: {
                ..cleared,
                note: "Draft changed. Preview the replacements again.",
              },
            },
          },
        )
      }
      if preview.changes.is_empty() {
        return (none, model)
      }
      let updated = plan_save_edit(s, preview.draft)
      return (
        none,
        {
          ..model,
          plan: {
            ..updated,
            text_replace: {
              ..cleared,
              note: "Applied " +
              preview.occurrences.to_string() +
              " replacements across " +
              preview.changes.length().to_string() +
              " fields. " +
              updated.note,
            },
          },
        },
      )
    }
  }
  (none, { ..model, plan: { ..s, text_replace: next, }, })
}

///|
fn plan_text_replace_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
) -> @html.Html {
  let state = s.text_replace
  @html.details <| [
    @html.summary("查找并替换计划文本 / Find and replace plan text"),
    p(
      "Update a project term across authored text with an exact before/after preview. Matches are literal, case-sensitive and non-overlapping; spaces and newlines are significant. No regular expressions.",
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-text-replace-query"),
        "Find text",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-text-replace-query"),
        value=state.query,
        on_input=emit.map(v => PlanAction(TextReplace(Query(v)))),
        "",
      ),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-text-replace-value"),
        "Replace with (empty removes the matching text)",
      ),
      @html.textarea(
        attrs=@html.Attrs::build().id("plan-text-replace-value"),
        value=state.replacement,
        on_input=emit.map(v => PlanAction(TextReplace(Replacement(v)))),
        "",
      ),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-text-replace-scope"),
        "Text scope",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-text-replace-scope"),
        on_change=emit.map(v => PlanAction(TextReplace(Scope(v)))),
      ) <| [
        ("all", "All listed text fields"),
        ("notes", "Scope notes"),
        ("tasks", "Task titles"),
        ("milestones", "Milestone names, criteria and evidence"),
        ("risks", "Risk summaries and mitigations"),
      ].map(choice => {
        @html.option(value=choice.0, selected=state.scope == choice.0, choice.1)
      }),
    ],
    p(
      "Owner names/roles, stable IDs, assignments, dates, costs and links stay unchanged. Clearing an entire nonblank field is rejected; use its individual editor for that change.",
    ),
    plan_button(
      emit,
      TextReplace(Preview),
      "Preview text replacements",
      disabled=state.query.is_empty(),
    ),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), state.note),
    match state.preview {
      None => @html.nothing
      Some(preview) =>
        div <| [
          h3("Text replacement preview"),
          p(
            preview.occurrences.to_string() +
            " replacements across " +
            preview.changes.length().to_string() +
            " fields.",
          ),
          if preview.changes.is_empty() {
            p("No text would change. Adjust the find text or scope.")
          } else {
            @html.nothing
          },
          div <| preview.changes.map(change => {
            @html.details <| [
              @html.summary(
                change.kind +
                " · " +
                change.id +
                " · " +
                change.field +
                " (" +
                change.occurrences.to_string() +
                ")",
              ),
              strong("Before"),
              @html.pre(change.before),
              strong("After"),
              @html.pre(change.after),
            ]
          }),
          p(
            "Apply saves only this browser draft and invalidates its prepared preview. Saved versions remain unchanged. Check source quotations before replacing them.",
          ),
          plan_button(
            emit,
            TextReplace(Apply),
            "Apply text replacements",
            disabled=preview.changes.is_empty(),
          ),
          plan_button(emit, TextReplace(Close), "Close replacement preview"),
        ]
    },
  ]
}
