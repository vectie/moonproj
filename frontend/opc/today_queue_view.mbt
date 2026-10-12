///|
fn today_task_row(
  emit : @rabbita.Emit[Msg],
  task : TodayTask,
  day : String,
) -> @html.Html {
  let attention = today_attention(task, day)
  article(class="attention-item") <| [
    div(class="attention-main") <| [
      div(class="attention-title") <| [
        strong(task.title),
        status_badge(task.status, tone="info"),
      ],
      p(
        "负责人 · " +
        (if task.owner_id.is_empty() {
          "未分配"
        } else if task.owner_name.is_empty() {
          task.owner_id
        } else {
          task.owner_name + " (" + task.owner_id + ")"
        }),
      ),
      p(
        "到期日期 · " +
        (if today_date_valid(task.due) {
          task.due + "（UTC 日期；具体时刻未知）"
        } else if task.due.is_empty() {
          "未知"
        } else {
          "未知（原始值：" + task.due + "）"
        }),
      ),
      p(
        if attention.is_empty() {
          "本次读取未观察到到期或执行阻塞提醒"
        } else {
          attention
        },
      ),
      if !today_blocker(task).is_empty() && !task.execution_error.is_empty() {
        p("执行返回 · " + task.execution_error)
      } else {
        @html.nothing
      },
      small("正式任务 · " + task.id + " / 状态 · " + task.status),
    ],
    secondary_button(emit, TodayAction(OpenTask(task.id)), "打开任务详情"),
  ]
}

///|
fn today_drafts_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let drafts = model.dispatch_drafts.filter(draft => draft.state != "created")
  section(class="product-section") <| [
    h2("此浏览器的草稿"),
    p(
      "单独恢复，未计入正式任务数量。创建结果待确认的草稿请先恢复结果。",
    ),
    small(model.dispatch_draft_storage),
    if drafts.is_empty() {
      p("此浏览器没有可恢复的任务草稿")
    } else {
      div <| drafts.map(draft => {
        article(class="attention-item") <| [
          div <| [
            strong(
              if draft.title.is_empty() {
                "未命名草稿"
              } else {
                draft.title
              },
            ),
            p(
              "公司项目 · " +
              (if draft.project_id.is_empty() {
                "未选择"
              } else {
                draft.project_id
              }),
            ),
            small("本地状态 · " + draft.state),
          ],
          secondary_button(emit, DraftAction(Resume(draft.id)), "恢复草稿"),
        ]
      })
    },
  ]
}

///|
fn today_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.today
  let day = if state.observed_at.length() >= 10 {
    state.observed_at[:10].to_owned()
  } else {
    ""
  }
  let ready = state.work_state == "ready" || state.work_state == "empty"
  let queue = today_queue(state, day)
  let attention = queue.filter(task => !today_attention(task, day).is_empty())
  let selected = state.projects
    .filter(project => project.id == state.project_id)
    .get(0)
  section(class="page command-page") <| [
    page_intro(Overview, status_badge("今日工作", tone="info")),
    section(class="product-section") <| [
      h2("今日工作"),
      p(
        "1. 跨项目查看或选择一个项目 → 2. 查看现有工作 → 3. 打开任务详情",
      ),
      p(
        "先处理阻塞，再看到期工作。打开详情不会启动执行、提交报告或接受交付。",
      ),
      secondary_button(emit, TodayAction(Refresh), "刷新公司项目"),
      p("公司项目 · " + products_state_label(state.project_state)),
      if state.project_note.is_empty() {
        @html.nothing
      } else {
        p(state.project_note)
      },
      if ["ready", "empty"].contains(state.project_state) {
        button(
          type_="button",
          class=if state.scope == "all" {
            "button button-primary"
          } else {
            "button button-secondary"
          },
          attrs=@html.Attrs::build()
            .aria_pressed(if state.scope == "all" { "true" } else { "false" })
            .disabled(state.scope == "all" && today_portfolio_busy(state)),
          on_click=emit(TodayAction(ChooseAll)),
          "跨项目查看",
        )
      } else {
        @html.nothing
      },
      if state.project_state == "ready" {
        div(
          class="product-project-picker",
          attrs=@html.Attrs::build().aria_label("今日工作公司项目"),
        ) <| state.projects.map(project => {
          button(
            type_="button",
            class=if project.id == state.project_id {
              "button button-primary"
            } else {
              "button button-secondary"
            },
            attrs=@html.Attrs::build().aria_pressed(
              if project.id == state.project_id {
                "true"
              } else {
                "false"
              },
            ),
            on_click=emit(TodayAction(ChooseProject(project.id))),
            project.name + " · " + project.id,
          )
        })
      } else {
        @html.nothing
      },
      if state.scope == "all" {
        today_portfolio_view(emit, model)
      } else {
        match selected {
          None =>
            p(
              if state.project_state == "empty" {
                "当前账号没有可选择的公司项目；尚未读取任何项目的任务。"
              } else {
                "请选择一个实际公司项目；未选择前不显示任务统计。"
              },
            )
          Some(project) =>
            div <| [
              h3("当前范围 · " + project.name + " (" + project.id + ")"),
              secondary_button(
                emit,
                TodayAction(RefreshTasks),
                "刷新所选项目任务",
              ),
              p("任务读取 · " + products_state_label(state.work_state)),
              p(
                if state.observed_at.is_empty() {
                  "尚无成功的任务读取"
                } else {
                  "此项目上次成功读取 · " +
                  state.observed_at +
                  "（浏览器观察时间，UTC）"
                },
              ),
              p(
                "按成功读取当天的 UTC 日期判断到期，与任务表单一致。日期没有具体时刻；缺失或无法识别的日期保持未知。需要最新情况时请刷新。",
              ),
              if ready {
                div <| [
                  div(class="kpi-grid") <| [
                    compact_kpi(
                      "本项目已读取",
                      state.tasks.length().to_string(),
                      "正式任务；不含浏览器草稿",
                      "info",
                    ),
                    compact_kpi(
                      "未结束工作",
                      queue.length().to_string(),
                      "按正式任务状态；陌生状态保留检查",
                      "info",
                    ),
                    compact_kpi(
                      "需要留意",
                      attention.length().to_string(),
                      "已观察到到期或阻塞",
                      "warn",
                    ),
                    compact_kpi(
                      "未分配负责人",
                      queue
                      .filter(task => task.owner_id.is_empty())
                      .length()
                      .to_string(),
                      "仅未结束工作",
                      "info",
                    ),
                  ],
                  if state.work_state == "empty" {
                    p("本次成功读取：此项目没有正式任务")
                  } else if queue.is_empty() {
                    p("本次读取没有未结束工作")
                  } else {
                    div <| queue.map(task => today_task_row(emit, task, day))
                  },
                ]
              } else {
                p(
                  "任务数量与队列当前未知；读取失败或进行中不代表没有任务。",
                )
              },
            ]
        }
      },
    ],
    today_drafts_view(emit, model),
  ]
}
