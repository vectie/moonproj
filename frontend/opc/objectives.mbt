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
fn objective_result_report(model : Model, work : String) -> String {
  if model.dispatch_task_id == work &&
    (
      model.delivery.editing ||
      model.delivery.busy ||
      ["revising", "resuming"].contains(delivery_control(model))
    ) {
    return ""
  }
  if model.dispatch_task_id == work && dispatch_can_accept_report(model) {
    model.dispatch_task_report_id
  } else {
    products_text(objective_metadata(model.today, work), "accepted_report_id")
  }
}

///|
fn objective_accept(
  emit : @rabbita.Emit[Msg],
  model : Model,
  id : String,
  work_id : String,
) -> (Cmd, Model) {
  let s = model.today
  let work = objective_metadata(s, work_id)
  let report = objective_result_report(model, work_id)
  if s.actor.is_empty() ||
    s.actor != model.dispatch_task_actor_id ||
    s.work_state != "ready" ||
    !s.tasks.any(t => {
      t.id == id && objective_is_node(s, t) && today_outstanding(t)
    }) ||
    report.is_empty() ||
    products_text(work, "parentTaskGuid") != id ||
    !s.tasks.any(t => t.id == work_id) {
    return (none, model)
  }
  let body : Json = {
    "idempotency_key": "objective-result-" + dispatch_command_nonce(),
    "status": "done",
    "objective_result": { "task_id": work_id, "report_id": report },
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
    { ..model, notice: "正在保存目标接受决定。", },
  )
}

///|
fn objective_prepare(
  emit : @rabbita.Emit[Msg],
  model : Model,
  parent : String?,
  revision_work~ : String = "",
  revision_report~ : String = "",
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
    delivery_mode: if parent is Some(_) {
      Some("coordinated")
    } else {
      None
    },
    delivery_limits: Some(""),
    owner_id: s.actor,
    begin_date: dispatch_today(),
    end_date: objective.map(t => t.due).unwrap_or(dispatch_today()),
    source_reference: if revision_report.is_empty() {
      parent.map(id => "moonproj:objective:" + id)
    } else {
      Some("moonproj:report:" + revision_report)
    },
    observed_problem: objective.map(t => t.title),
    title: if revision_work.is_empty() {
      objective.map(t => t.title).unwrap_or("")
    } else {
      "修改：" +
      products_text(objective_metadata(s, revision_work), "taskName")
    },
    acceptance: objective
    .map(t => {
      let remarks = products_text(objective_metadata(s, t.id), "remarks")
      remarks.strip_prefix("验收标准：").unwrap_or(remarks[:]).to_owned()
    })
    .unwrap_or(""),
    note: if !revision_report.is_empty() {
      "写明这份报告需要怎样修改；保存修改工作不会重跑或覆盖原结果。"
    } else if parent is None {
      "明确公司要达成的结果；保存目标不会启动执行。"
    } else {
      "对完整交付负责；按需安排专业工作，整合输出并说明验收结果与缺口。"
    },
  }
  let next = dispatch_replace_draft(
    { ..prepared, page: Objectives, notice: "", },
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
fn objective_request_changes(
  emit : @rabbita.Emit[Msg],
  model : Model,
  goal : String,
  work : String,
) -> (Cmd, Model) {
  let report = objective_result_report(model, work)
  if report.is_empty() ||
    products_text(objective_metadata(model.today, work), "parentTaskGuid") !=
    goal {
    return (none, model)
  }
  if model.dispatch_task_id == work &&
    delivery_coordinated(model) &&
    model.dispatch_run is Some(_) {
    return (
      none,
      {
        ..model,
        delivery: { ..model.delivery, editing: true, instruction: "", },
      },
    )
  }
  objective_prepare(
    emit,
    model,
    Some(goal),
    revision_work=work,
    revision_report=report,
  )
}

///|
fn objective_project_picker(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let s = model.today
  div(class="product-section") <| [
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
      div <| [
        p("先创建公司项目，再定义目标。"),
        secondary_button(emit, Navigate(Company), "公司设置"),
      ]
    } else if s.projects.length() == 1 && s.project_id == s.projects[0].id {
      p(s.projects[0].name)
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
    if !["ready", "empty"].contains(s.project_state) {
      secondary_button(emit, TodayAction(Refresh), "重试读取项目")
    } else {
      @html.nothing
    },
  ]
}

///|
fn objective_current_id(model : Model, goals : Array[TodayTask]) -> String {
  let s = model.today
  let draft_parent = if model.dispatch_task_form_open {
    dispatch_active_draft(model)
    .map(d => d.parent_task_id.unwrap_or(""))
    .unwrap_or("")
  } else {
    ""
  }
  let selected = objective_metadata(s, model.dispatch_task_id)
  let id = if !draft_parent.is_empty() {
    draft_parent
  } else if products_text(selected, "taskType") == "key_node" {
    model.dispatch_task_id
  } else {
    products_text(selected, "parentTaskGuid")
  }
  if goals.any(g => g.id == id) {
    id
  } else {
    let fallback = match goals.filter(today_outstanding).get(0) {
      Some(goal) => Some(goal)
      None => goals.get(0)
    }
    fallback.map(g => g.id).unwrap_or("")
  }
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
  let current = objective_current_id(model, goals)
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
          div <| [
            if goals.length() > 1 {
              div(class="tag-row") <| goals.map(goal => {
                button(
                  type_="button",
                  class="button button-secondary",
                  attrs=@html.Attrs::build().aria_pressed(
                    if goal.id == current {
                      "true"
                    } else {
                      "false"
                    },
                  ),
                  on_click=emit(TodayAction(OpenTask(goal.id))),
                  goal.title,
                )
              })
            } else {
              @html.nothing
            },
            div <| goals
            .filter(g => g.id == current)
            .map(goal => {
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
                if !today_outstanding(goal) {
                  p(
                    if products_field(
                        objective_metadata(s, goal.id),
                        "objective_result",
                      )
                      is Object(_) {
                      "已接受交付结果"
                    } else {
                      "记录已结束 · 未关联已验收交付结果"
                    },
                  )
                } else {
                  @html.nothing
                },
                if today_outstanding(goal) {
                  primary_button(
                    emit,
                    TodayAction(DelegateObjective(goal.id)),
                    if children.is_empty() {
                      "委派交付负责人"
                    } else {
                      "补充工作"
                    },
                  )
                } else {
                  @html.nothing
                },
                if products_field(
                    objective_metadata(s, goal.id),
                    "objective_result",
                  )
                  is Object(_) {
                  div <| [
                    p(
                      products_text(
                        products_field(
                          objective_metadata(s, goal.id),
                          "objective_result",
                        ),
                        "summary",
                      ),
                    ),
                    secondary_button(
                      emit,
                      TodayAction(
                        OpenTask(
                          products_text(
                            products_field(
                              objective_metadata(s, goal.id),
                              "objective_result",
                            ),
                            "task_id",
                          ),
                        ),
                      ),
                      "查看已接受交付",
                    ),
                  ]
                } else {
                  @html.nothing
                },
                if model.dispatch_task_form_open &&
                  dispatch_active_draft(model)
                  .map(d => {
                    d.parent_task_id == Some(goal.id) &&
                    d.project_id == s.project_id
                  })
                  .unwrap_or(false) {
                  dispatch_task_form(emit, model)
                } else {
                  @html.nothing
                },
                if children.is_empty() {
                  if model.dispatch_task_form_open {
                    @html.nothing
                  } else {
                    p(
                      "委派一项完整交付，写清负责人需要交回的结果。",
                    )
                  }
                } else {
                  div <| children
                  .filter(t => {
                    t.id != model.dispatch_task_id ||
                    model.dispatch_task_form_open
                  })
                  .map(task => {
                    today_task_row(emit, task, dispatch_today(), compact=true)
                  })
                },
                if children.any(t => t.id == model.dispatch_task_id) &&
                  !model.dispatch_task_form_open {
                  dispatch_durable_task_card(emit, model)
                } else {
                  @html.nothing
                },
                if today_outstanding(goal) && !model.dispatch_task_form_open {
                  div <| children
                  .filter(t => !objective_result_report(model, t.id).is_empty())
                  .map(work => {
                    div(class="task-next-action") <| [
                      p("交付结果 · " + work.title),
                      if children.any(today_outstanding) {
                        p("接受结果不改变其他工作状态。")
                      } else {
                        @html.nothing
                      },
                      secondary_button(
                        emit,
                        TodayAction(OpenTask(work.id)),
                        "检查交付结果",
                      ),
                      primary_button(
                        emit,
                        TodayAction(AcceptObjective(goal.id, work.id)),
                        "接受此交付结果",
                      ),
                      secondary_button(
                        emit,
                        TodayAction(ReviseObjective(goal.id, work.id)),
                        "要求修改",
                      ),
                    ]
                  })
                } else {
                  @html.nothing
                },
                details([
                  summary("计划与记录"),
                  secondary_button(
                    emit,
                    Navigate(Projects),
                    "编制交付计划",
                  ),
                  p(goal.id),
                  if products_field(
                      objective_metadata(s, goal.id),
                      "objective_result",
                    )
                    is Object(_) {
                    p(
                      "已接受报告 · " +
                      products_text(
                        products_field(
                          objective_metadata(s, goal.id),
                          "objective_result",
                        ),
                        "report_id",
                      ),
                    )
                  } else {
                    @html.nothing
                  },
                ]),
              ]
            }),
          ]
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
