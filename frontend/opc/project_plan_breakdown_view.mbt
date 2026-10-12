///|
fn plan_breakdown_field(
  emit : @rabbita.Emit[Msg],
  step : @plan_workbench.TaskStep,
  field : String,
  title : String,
  value : String,
) -> @html.Html {
  let id = "plan-breakdown-" + step.id + "-" + field
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(id), title),
    input(
      input_type=Text,
      attrs=@html.Attrs::build().id(id),
      value~,
      on_input=emit.map(v => PlanAction(Breakdown(Edit(step.id, field, v)))),
    ),
  ]
}

///|
fn plan_breakdown_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let b = s.breakdown
  @html.details <| [
    @html.summary("拆分任务 / Break down a task"),
    p(
      "Replace one broad task with 2–10 sequential steps. All steps inherit its owner and milestone; redistribute its exact cost without changing the total. Followers will wait for the final step; linked risks will cover every step. This edits the local draft only.",
    ),
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("plan-breakdown-task"),
        "原任务 / Original task",
      ),
      @html.select(
        attrs=@html.Attrs::build().id("plan-breakdown-task"),
        on_change=emit.map(id => PlanAction(Breakdown(Choose(id)))),
      ) <| [
        @html.option(value="", selected=b.task_id.is_empty(), "Choose a task"),
        ..d.tasks.map(task => {
          @html.option(
            value=task.id,
            selected=b.task_id == task.id,
            task.name + " · " + task.id,
          )
        }),
      ],
    ],
    match d.tasks.filter(t => t.id == b.task_id) {
      [task] =>
        div <| [
          p(
            "Original cost: " +
            task.cost +
            " " +
            d.currency +
            " · Owner: " +
            task.owner +
            " · Milestone: " +
            task.milestone,
          ),
          div <| b.steps.mapi((i, step) => {
            article(class="repo-card") <| [
              strong("Step " + (i + 1).to_string()),
              plan_breakdown_field(
                emit,
                step,
                "name",
                "步骤名称 / Step name",
                step.name,
              ),
              plan_breakdown_field(
                emit,
                step,
                "cost",
                "步骤成本 / Step cost",
                step.cost,
              ),
              plan_button(
                emit,
                Breakdown(Remove(step.id)),
                "移除此步骤 / Remove step",
                disabled=b.steps.length() <= 2,
              ),
            ]
          }),
          p(
            attrs=@html.Attrs::build().role("status").aria_live("polite"),
            plan_breakdown_cost_note(b.steps, task.cost, d.currency),
          ),
          plan_button(
            emit,
            Breakdown(Add),
            "添加步骤 / Add step",
            disabled=b.steps.length() >= 10,
          ),
          plan_button(
            emit,
            Breakdown(Preview),
            "预览拆分 / Preview breakdown",
          ),
          plan_button(emit, Breakdown(Close), "取消拆分 / Cancel breakdown"),
        ]
      _ => @html.nothing
    },
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), b.note),
    match (b.source, b.preview) {
      (Some(source), Some(preview)) if source == d =>
        div <| [
          h3("Preview: sequential replacement"),
          p("The original task ID will be removed: " + b.task_id),
          div <| preview.tasks
          .filter(task => b.steps.any(step => step.id == task.id))
          .mapi((i, task) => {
            article(class="repo-card") <| [
              strong((i + 1).to_string() + ". " + task.name + " · " + task.id),
              p(
                "Cost: " +
                task.cost +
                " " +
                d.currency +
                " · Owner: " +
                task.owner +
                " · Milestone: " +
                task.milestone,
              ),
              p(
                "Depends on: " +
                (if task.dependencies.is_empty() {
                  "None"
                } else {
                  task.dependencies.join(", ")
                }),
              ),
            ]
          }),
          h3("Updated follower dependencies"),
          if d.tasks.any(task => task.dependencies.contains(b.task_id)) {
            div <| d.tasks
            .filter(task => task.dependencies.contains(b.task_id))
            .map(task => {
              let next = preview.tasks.filter(t => t.id == task.id)[0]
              p(
                task.name +
                " · " +
                task.id +
                ": " +
                task.dependencies.join(", ") +
                " → " +
                next.dependencies.join(", "),
              )
            })
          } else {
            p("No following task references the original.")
          },
          h3("Expanded risk links"),
          if d.risks.any(risk => risk.tasks.contains(b.task_id)) {
            div <| d.risks.mapi((i, risk) => {
              if risk.tasks.contains(b.task_id) {
                p(
                  risk.summary +
                  " · " +
                  risk.id +
                  ": " +
                  risk.tasks.join(", ") +
                  " → " +
                  preview.risks[i].tasks.join(", "),
                )
              } else {
                @html.nothing
              }
            })
          } else {
            p("No risk references the original.")
          },
          p(
            "Total cost, other task fields, milestone criteria and plan budget are preserved. Apply saves locally and requires a new native prepare/save. Existing saved versions remain available in history.",
          ),
          plan_button(
            emit,
            Breakdown(Apply),
            "应用任务拆分 / Apply breakdown",
          ),
        ]
      _ => @html.nothing
    },
  ]
}

///|
fn plan_breakdown_amount(minor : Int64) -> String {
  let amount = if minor < 0L { -minor } else { minor }
  let fraction = (amount % 100L).to_string()
  (if minor < 0L { "-" } else { "" }) +
  (amount / 100L).to_string() +
  "." +
  (if fraction.length() == 1 { "0" } else { "" }) +
  fraction
}

///|
fn plan_breakdown_cost_note(
  steps : Array[@plan_workbench.TaskStep],
  original_cost : String,
  currency : String,
) -> String {
  let total = @plan_workbench.minor(original_cost, "Original task cost") catch {
    _ => return "Fix the original task cost before breaking it down."
  }
  let mut allocated = 0L
  for step in steps {
    let amount = @plan_workbench.minor(step.cost, "Step cost") catch {
      _ => return "Enter valid costs to see the remaining amount."
    }
    allocated += amount
  }
  "Allocated: " +
  plan_breakdown_amount(allocated) +
  " " +
  currency +
  " · Remaining to allocate: " +
  plan_breakdown_amount(total - allocated) +
  " " +
  currency
}
