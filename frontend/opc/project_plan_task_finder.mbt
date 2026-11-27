///|
#derive(Debug, Eq)
struct PlanTaskFinder {
  query : String
  owner : String
  milestone : String
  focus : String
}

///|
#derive(Debug, Eq)
enum PlanTaskFinderMsg {
  Query(String)
  Owner(String)
  Milestone(String)
  Focus(String)
  ShowAll
  Reset
  Export
}

///|
fn plan_task_finder_initial() -> PlanTaskFinder {
  { query: "", owner: "", milestone: "", focus: "", }
}

///|
fn plan_task_finder_rows(
  state : PlanTaskFinder,
  draft : @plan_workbench.Draft,
) -> Array[@plan_workbench.Task] {
  @plan_workbench.find_tasks(draft, state.query, state.owner, state.milestone)
}

///|
// Keep the stable-ID editing focus during renames/reassignment. Deletion of the
// focused row or newly added rows return to the whole editor, never hiding new work.
fn plan_task_finder_after_edit(
  state : PlanWorkbench,
  draft : @plan_workbench.Draft,
) -> PlanTaskFinder {
  let finder = state.task_finder
  let added = match state.draft {
    Some(before) =>
      draft.tasks.any(t => !before.tasks.any(old => old.id == t.id))
    None => true
  }
  if added || !draft.tasks.any(t => t.id == finder.focus) {
    { ..finder, focus: "", }
  } else {
    finder
  }
}

///|
fn plan_task_finder_update(
  action : PlanTaskFinderMsg,
  model : Model,
) -> (Cmd, Model) {
  let s = model.plan
  guard s.draft is Some(d) &&
    d.project_id == s.selected &&
    s.projects.any(p => p.id == s.selected) else {
    return (none, model)
  }
  let f = s.task_finder
  let next = match action {
    Query(query) => { ..f, query, focus: "", }
    Owner(owner) => { ..f, owner, focus: "", }
    Milestone(milestone) => { ..f, milestone, focus: "", }
    ShowAll => { ..f, focus: "", }
    Reset => plan_task_finder_initial()
    Focus(id) => {
      if !plan_task_finder_rows(f, d).any(t => t.id == id) {
        return (none, model)
      }
      { ..f, focus: id, }
    }
    Export => {
      let rows = plan_task_finder_rows(f, d)
      if rows.is_empty() {
        return (none, model)
      }
      let csv = @plan_workbench.export_task_table({ ..d, tasks: rows, })
      return (
        @cmd.custom_cmd(_ => {
          plan_download(csv, "plan-task-search-results.csv", false)
        }),
        model,
      )
    }
  }
  (none, { ..model, plan: { ..s, task_finder: next, }, })
}

///|
fn plan_task_finder_select(
  emit : @rabbita.Emit[Msg],
  owner : Bool,
  selected : String,
  choices : Array[(String, String)],
) -> @html.Html {
  let id = if owner {
    "plan-task-find-owner"
  } else {
    "plan-task-find-milestone"
  }
  let choices = if selected != "" && !choices.any(c => c.0 == selected) {
    [
      ..choices,
      (selected, "Missing reference / 已移除引用 · " + selected),
    ]
  } else {
    choices
  }
  div(class="field") <| [
    label(
      attrs=@html.Attrs::build().for_(id),
      if owner {
        "负责人 / Owner"
      } else {
        "里程碑 / Milestone"
      },
    ),
    @html.select(
      attrs=@html.Attrs::build().id(id),
      on_change=emit.map(value => {
        PlanAction(
          TaskFinder(if owner { Owner(value) } else { Milestone(value) }),
        )
      }),
    ) <| choices.map(c => @html.option(value=c.0, selected=selected == c.0, c.1)),
  ]
}

///|
fn plan_task_finder_view(
  emit : @rabbita.Emit[Msg],
  s : PlanWorkbench,
  d : @plan_workbench.Draft,
) -> @html.Html {
  let f = s.task_finder
  let rows = plan_task_finder_rows(f, d)
  div <| [
    @html.details <| [
      @html.summary("查找任务 / Find tasks"),
      p(
        "按任务名称或 ID 包含文本搜索（忽略 ASCII 大小写）；负责人和里程碑按精确 ID 筛选。筛选组合使用 AND。",
      ),
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("plan-task-find-query"),
          "任务名称或 ID / Task name or ID",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("plan-task-find-query"),
          value=f.query,
          on_input=emit.map(query => PlanAction(TaskFinder(Query(query)))),
        ),
      ],
      plan_task_finder_select(
        emit,
        true,
        f.owner,
        [
          ("", "全部负责人 / All owners"),
          ..d.owners.map(o => (o.id, o.name + " · " + o.id)),
        ],
      ),
      plan_task_finder_select(
        emit,
        false,
        f.milestone,
        [
          ("", "全部里程碑 / All milestones"),
          ..d.milestones.map(m => (m.id, m.name + " · " + m.id)),
        ],
      ),
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        "匹配 / Matches: " +
        rows.length().to_string() +
        " / " +
        d.tasks.length().to_string(),
      ),
      plan_button(emit, TaskFinder(Reset), "重置查找 / Reset finder"),
      plan_button(
        emit,
        TaskFinder(Export),
        "下载匹配任务 CSV / Download matching tasks",
        disabled=rows.is_empty(),
      ),
      p(
        "CSV 仅含当前匹配任务，保留原 ID 和依赖引用；不会自动包含范围外的前置任务，也不是完整计划备份。可在现有任务表更新中预览回填；遗漏的任务不删除。",
      ),
      if rows.is_empty() {
        p(
          "没有匹配任务。更改条件或重置查找；草稿任务未删除。 / No matching tasks.",
        )
      } else {
        @html.nothing
      },
      div <| rows.map(t => {
        article(class="repo-card") <| [
          strong(t.name + " · " + t.id),
          p("Owner: " + t.owner + " · Milestone: " + t.milestone),
          plan_button(
            emit,
            TaskFinder(Focus(t.id)),
            "编辑此任务 / Edit this task",
            selected=f.focus == t.id,
          ),
        ]
      }),
    ],
    if !f.focus.is_empty() && d.tasks.any(t => t.id == f.focus) {
      div <| [
        p(
          attrs=@html.Attrs::build().role("status"),
          "正在编辑 / Editing: " +
          f.focus +
          ". 其他任务仍保留在完整草稿中。改名或改派后此表单保持打开；查找结果会实时更新。",
        ),
        plan_button(
          emit,
          TaskFinder(ShowAll),
          "显示全部任务表单 / Show all task forms",
        ),
      ]
    } else {
      @html.nothing
    },
  ]
}
