///|
fn today_portfolio_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.today
  let rows = state.project_reads
  let successes = rows.filter(today_portfolio_success)
  let busy = today_portfolio_busy(state)
  let failed = rows.filter(row => {
    !today_portfolio_success(row) &&
    row.state != "queued" &&
    row.state != "loading"
  })
  let tasks = today_portfolio_tasks(state)
  let queue = today_portfolio_queue(state)
  let matches = today_filtered_queue(state)
  let available = ["ready", "empty"].contains(state.project_state)
  div <| [
    h3("跨项目工作"),
    p(
      "范围：本次公司项目列表返回的项目。项目列表可能省略有数据问题或未返回的项目；这里不是完整公司台账。",
    ),
    if !available {
      p("项目范围当前未知；请重新读取公司项目。")
    } else if rows.is_empty() {
      p(
        "本次列表没有返回可查看的公司项目；尚未读取任务。",
      )
    } else {
      div <| [
        p(
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          "已读取 " +
          successes.length().to_string() +
          " / " +
          rows.length().to_string() +
          " 个已列项目" +
          (if busy {
            " · 其余项目正在读取"
          } else if !failed.is_empty() {
            " · 部分项目读取失败"
          } else {
            " · 本次已列范围读取完成"
          }),
        ),
        p(
          "各项目按自身成功读取时的 UTC 日期判断到期。下方数字仅计入成功读取的项目；读取失败不代表没有任务。",
        ),
        button(
          type_="button",
          class="button button-secondary",
          attrs=@html.Attrs::build().disabled(busy),
          on_click=emit(TodayAction(RefreshTasks)),
          "刷新已列项目的任务",
        ),
        if !failed.is_empty() {
          button(
            type_="button",
            class="button button-secondary",
            attrs=@html.Attrs::build().disabled(busy),
            on_click=emit(TodayAction(RetryFailed)),
            "重试失败项目",
          )
        } else {
          @html.nothing
        },
        if successes.is_empty() {
          p("尚无成功的项目任务读取，任务数量未知。")
        } else {
          div <| [
            div(class="kpi-grid") <| [
              compact_kpi(
                "已观察的正式任务",
                tasks.length().to_string(),
                "仅成功读取的项目；不含草稿",
                "info",
              ),
              compact_kpi(
                "未结束工作",
                queue.length().to_string(),
                "仅成功读取的项目",
                "info",
              ),
              compact_kpi(
                "需要留意",
                queue
                .filter(task => {
                  !today_attention(
                    task,
                    today_portfolio_day(state, task.project_id),
                  ).is_empty()
                })
                .length()
                .to_string(),
                "已观察到到期或阻塞",
                "warn",
              ),
              compact_kpi(
                "未分配负责人",
                queue
                .filter(task => task.owner_id.is_empty())
                .length()
                .to_string(),
                "仅已观察的未结束工作",
                "info",
              ),
            ],
            today_filters_view(emit, state),
            p(
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              "匹配 " +
              matches.length().to_string() +
              " / " +
              queue.length().to_string() +
              " 项已观察的未结束工作（筛选不改变项目读取覆盖范围）",
            ),
            if queue.is_empty() {
              p("成功读取的项目中未观察到未结束工作。")
            } else if matches.is_empty() {
              p(
                "当前筛选没有匹配项；不代表公司没有工作。清除筛选可恢复已观察队列。",
              )
            } else {
              div <| matches.map(task => {
                let project = rows
                  .filter(row => row.project.id == task.project_id)
                  .get(0)
                div <| [
                  p(
                    "公司项目 · " +
                    project
                    .map(row => row.project.name)
                    .unwrap_or(task.project_id) +
                    " (" +
                    task.project_id +
                    ")",
                  ),
                  today_task_row(
                    emit,
                    task,
                    today_portfolio_day(state, task.project_id),
                  ),
                ]
              })
            },
          ]
        },
        details(open=!failed.is_empty(), [
          summary("逐项目读取状态"),
          div <| rows.map(row => {
            article <| [
              strong(row.project.name + " · " + row.project.id),
              p(
                if row.state == "queued" {
                  "等待读取"
                } else {
                  products_state_label(row.state)
                },
              ),
              if row.note.is_empty() {
                @html.nothing
              } else {
                p(row.note)
              },
              if today_portfolio_success(row) {
                p(
                  "成功读取 · " +
                  row.observed_at +
                  "（浏览器观察时间，UTC）",
                )
              } else {
                @html.nothing
              },
              if !today_portfolio_success(row) &&
                row.state != "queued" &&
                row.state != "loading" {
                secondary_button(
                  emit,
                  TodayAction(RetryProject(row.project.id)),
                  "重试此项目",
                )
              } else {
                @html.nothing
              },
              secondary_button(
                emit,
                TodayAction(ChooseProject(row.project.id)),
                "仅查看此项目",
              ),
            ]
          }),
        ]),
      ]
    },
  ]
}
