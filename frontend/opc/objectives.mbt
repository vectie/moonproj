///|
// Objectives reuse durable company key nodes; delegated work uses the existing
// task parent link. There is no second task store or execution runtime.
fn objective_metadata(state : TodayState, id : String) -> Json {
  state.task_metadata.get(id).unwrap_or(Json::null())
}

///|
fn objective_read_metadata(body : String) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  let root = @json.parse(body) catch { _ => Json::null() }
  for row in @plan_workbench.items(root, "items") {
    result[products_text(row, "taskGuid")] = row
  }
  result
}

///|
fn objective_is_node(state : TodayState, task : TodayTask) -> Bool {
  products_text(objective_metadata(state, task.id), "taskType") == "key_node"
}

///|
fn objective_accept(
  emit : @rabbita.Emit[Msg],
  model : Model,
  id : String,
) -> (Cmd, Model) {
  let s = model.today
  if s.actor.is_empty() ||
    s.actor != model.dispatch_task_actor_id ||
    s.work_state != "ready" ||
    !s.tasks.any(t => {
      t.id == id && objective_is_node(s, t) && today_outstanding(t)
    }) {
    return (none, model)
  }
  let body : Json = {
    "idempotency_key": "objective-accept-" + id,
    "status": "done",
    "authority": {
      "active": true,
      "principal_id": "principal-opc-dispatch",
      "actor_id": s.actor,
      "capability": "project:task:update",
      "scope": "project:" + s.project_id,
    },
  }
  (
    @http.put("/api/company/plan/tasks/" + dispatch_url_encode(id))
    .with_json(body)
    .expect_text(result => {
      let (status, response) = match result {
        Ok(response) => (200, response)
        Err(_) => (0, "")
      }
      emit(
        TodayAction(
          ObjectiveAccepted(
            s.actor,
            s.epoch,
            s.project_id,
            id,
            status,
            response,
          ),
        ),
      )
    }),
    {
      ..model,
      notice: "正在保存目标接受决定；若连接中断，刷新后可重试同一决定。",
    },
  )
}

///|
fn objective_prepare(
  emit : @rabbita.Emit[Msg],
  model : Model,
  parent : String?,
) -> (Cmd, Model) {
  let s = model.today
  if s.actor.is_empty() ||
    s.actor != model.dispatch_task_actor_id ||
    s.project_state != "ready" ||
    s.scope != "project" ||
    !s.projects.any(p => p.id == s.project_id) {
    return (
      none,
      {
        ..model,
        notice: "先选择公司项目；没有项目时，请在公司设置中创建。",
      },
    )
  }
  let objective = match parent {
    None => None
    Some(id) => {
      let row = s.tasks
        .filter(t => {
          t.id == id && objective_is_node(s, t) && today_outstanding(t)
        })
        .get(0)
      if s.work_state != "ready" || row is None {
        return (none, model)
      }
      row
    }
  }
  let (_, prepared) = dispatch_prepare_draft(
    emit,
    model,
    "",
    s.project_id,
    None,
    true,
  )
  let base = dispatch_active_draft(prepared).unwrap()
  let draft = {
    ..base,
    task_type: Some(if parent is None { "key_node" } else { "task" }),
    parent_task_id: parent,
    owner_id: s.actor,
    begin_date: dispatch_today(),
    end_date: objective.map(t => t.due).unwrap_or(dispatch_today()),
    source_reference: parent.map(id => "moonproj:objective:" + id),
    observed_problem: objective.map(t => t.title),
    note: if parent is None {
      "明确公司要达成的结果；保存目标不会启动执行。"
    } else {
      "为这个目标准备一项工作；保存后可通过现有执行路径委派。"
    },
  }
  let next = dispatch_replace_draft(
    {
      ..prepared,
      page: if parent is None {
        Objectives
      } else {
        Dispatch
      },
      notice: "",
    },
    draft,
  )
  (
    @cmd.batch([
      dispatch_persist_drafts(emit, next, ""),
      remember_page_route(next.page, model.dispatch_task_id, push=true),
    ]),
    next,
  )
}

///|
fn objective_project_picker(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let s = model.today
  div(class="product-section") <| [
    div(class="form-actions") <| [
      secondary_button(emit, TodayAction(Refresh), "刷新公司项目"),
      secondary_button(emit, Navigate(Company), "公司设置"),
    ],
    if s.project_state == "loading" {
      p(
        attrs=@html.Attrs::build().role("status"),
        "正在读取公司项目…",
      )
    } else if !["ready", "empty"].contains(s.project_state) {
      p(
        attrs=@html.Attrs::build().role("status"),
        "公司数据尚未就绪 · " + products_state_label(s.project_state),
      )
    } else if s.projects.is_empty() {
      p("先在公司设置中创建项目，再定义目标。")
    } else {
      div(class="tag-row") <| s.projects.map(project => {
        button(
          type_="button",
          class="button button-secondary",
          attrs=@html.Attrs::build().aria_pressed(
            if s.project_id == project.id {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(TodayAction(ChooseProject(project.id))),
          project.name,
        )
      })
    },
    if s.project_note.is_empty() {
      @html.nothing
    } else {
      p(s.project_note)
    },
  ]
}

///|
fn objectives_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let s = model.today
  let ready = s.scope == "project" && ["ready", "empty"].contains(s.work_state)
  let goals = if ready {
    s.tasks.filter(t => objective_is_node(s, t))
  } else {
    []
  }
  section(class="page") <| [
    page_intro(Objectives, @html.nothing),
    objective_project_picker(emit, model),
    if s.project_id.is_empty() {
      @html.nothing
    } else {
      section(class="product-section") <| [
        div(class="form-actions") <| [
          primary_button(emit, TodayAction(NewObjective), "定义目标"),
          secondary_button(emit, TodayAction(RefreshTasks), "刷新工作"),
          secondary_button(emit, Navigate(Projects), "编制交付计划"),
        ],
        if model.dispatch_task_form_open &&
          dispatch_active_draft(model)
          .map(d => {
            d.task_type == Some("key_node") && d.project_id == s.project_id
          })
          .unwrap_or(false) {
          dispatch_task_form(emit, model)
        } else {
          @html.nothing
        },
        if !ready {
          p(
            attrs=@html.Attrs::build().role("status"),
            if s.work_state == "loading" {
              "正在读取目标与工作…"
            } else {
              "目标与工作读取未完成 · " +
              products_state_label(s.work_state)
            },
          )
        } else if goals.is_empty() {
          if model.dispatch_task_form_open {
            @html.nothing
          } else {
            p("还没有目标。先写下要交付的结果和验收标准。")
          }
        } else {
          div <| goals.map(goal => {
            let children = s.tasks.filter(t => {
              products_text(objective_metadata(s, t.id), "parentTaskGuid") ==
              goal.id
            })
            article(class="repo-card") <| [
              h2(goal.title),
              p(
                "负责人 · " +
                (if goal.owner_name.is_empty() {
                  goal.owner_id
                } else {
                  goal.owner_name
                }) +
                " · 目标日期 · " +
                goal.due,
              ),
              p(products_text(objective_metadata(s, goal.id), "remarks")),
              p("公司记录 · " + goal.status),
              if today_outstanding(goal) {
                primary_button(
                  emit,
                  TodayAction(DelegateObjective(goal.id)),
                  "委派工作",
                )
              } else {
                @html.nothing
              },
              if children.is_empty() {
                p("尚未委派工作。")
              } else {
                div <| children.map(task => {
                  today_task_row(emit, task, dispatch_today())
                })
              },
              details([
                summary("核对目标与结果"),
                p(goal.id),
                p(
                  "目标使用公司关键节点记录。关联不是执行依赖；子任务完成也不会自动接受目标。",
                ),
                if today_outstanding(goal) {
                  div <| [
                    p(
                      "核对各项工作输出与目标验收标准后，再明确接受。接受目标不会签约、支付或发布。",
                    ),
                    if children.any(today_outstanding) {
                      p(
                        "仍有未结束的工作；接受目标不会结束这些工作。",
                      )
                    } else {
                      @html.nothing
                    },
                    secondary_button(
                      emit,
                      TodayAction(AcceptObjective(goal.id)),
                      "我已核对结果，接受目标",
                    ),
                  ]
                } else {
                  @html.nothing
                },
              ]),
            ]
          })
        },
        if ready &&
          s.tasks.any(t => {
            !objective_is_node(s, t) &&
            products_text(objective_metadata(s, t.id), "parentTaskGuid").is_empty()
          }) {
          details([
            summary("未归入目标的工作"),
            div <| s.tasks
            .filter(t => {
              !objective_is_node(s, t) &&
              products_text(objective_metadata(s, t.id), "parentTaskGuid").is_empty()
            })
            .map(t => today_task_row(emit, t, dispatch_today())),
          ])
        } else {
          @html.nothing
        },
      ]
    },
  ]
}
