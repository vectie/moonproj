///|
fn mission_weight_rail(
  stages : Array[CharterStage],
  selected_stage : String,
) -> @html.Html {
  if stages.is_empty() {
    return @html.nothing
  }
  div(
    class="mission-weight-rail",
    attrs=@html.Attrs::build().aria_hidden("true"),
  ) <| stages.map(stage => {
    let weight = if stage.weight_pct > 0 { stage.weight_pct } else { 10 }
    span(
      class="mission-weight-segment",
      attrs=@html.Attrs::build()
        .data_set("stage-status", stage.status)
        .data_set(
          "selected",
          if selected_stage == stage.id {
            "true"
          } else {
            "false"
          },
        )
        .style("flex-grow", weight.to_string())
        .title(stage.title + " · " + weight.to_string() + "%"),
      "",
    )
  })
}

///|
fn workspace_mission_spine_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.charter
  match state.charter {
    None => charter_empty_or_error_panel(emit, state, "公司使命与阶段脊柱")
    Some(charter) => {
      let achieved_pct = charter_achieved_pct(charter)
      let active_stage = charter_active_stage(charter)
      let selected = charter_find_stage(charter, model.workspace.selected_stage)
      let focus_stage = match selected {
        Some(s) => Some(s)
        None => active_stage
      }
      let jobs = workspace_jobs(model)
      section(
        class="mission-spine",
        attrs=@html.Attrs::build().aria_label("公司使命与阶段脊柱"),
      ) <| [
        div(class="mission-spine-head") <| [
          div(class="mission-spine-copy") <| [
            div(class="mission-kicker-row") <| [
              small("公司使命脊柱"),
              span(
                class="mission-ratio-tag",
                charter.mission.focus_ratio + " 杠杆",
              ),
            ],
            h1(charter.mission.title),
            if !charter.mission.north_star.is_empty() {
              p(class="mission-north-star", charter.mission.north_star)
            } else {
              @html.nothing
            },
          ],
          div(class="mission-spine-metrics") <| [
            span(
              class="mission-pct-pill",
              attrs=@html.Attrs::build().data_set(
                "achieved-pct",
                achieved_pct.to_string(),
              ),
              "已达成 " + achieved_pct.to_string() + "%",
            ),
          ],
        ],
        mission_weight_rail(charter.stages, model.workspace.selected_stage),
        charter_inline_status_banner(emit, state, show_refresh=true),
        if !charter.stages.is_empty() {
          div(
            class="mission-stepper",
            attrs=@html.Attrs::build()
              .role("list")
              .aria_label("使命阶段进度"),
          ) <| charter.stages.map(stage => {
            let is_selected = model.workspace.selected_stage == stage.id
            button(
              type_="button",
              class="mission-stage-step",
              attrs=@html.Attrs::build()
                .data_set("stage-id", stage.id)
                .data_set("stage-status", stage.status)
                .aria_pressed(if is_selected { "true" } else { "false" })
                .title(
                  stage.title +
                  " · " +
                  charter_stage_status_label(stage.status) +
                  " · 权重 " +
                  stage.weight_pct.to_string() +
                  "%",
                ),
              on_click=emit(WorkspaceAction(SelectStage(stage.id))),
            ) <| [
              span(
                class="mission-stage-mark",
                attrs=@html.Attrs::build()
                  .aria_hidden("true")
                  .data_set("stage-status", stage.status),
                charter_stage_mark(stage.status),
              ),
              div(class="mission-stage-text") <| [
                strong(stage.title),
                small(
                  charter_stage_status_label(stage.status) +
                  " · " +
                  stage.weight_pct.to_string() +
                  "%",
                ),
              ],
            ]
          })
        } else {
          @html.nothing
        },
        match focus_stage {
          Some(stage) => {
            let linked_job = if stage.milestone_task_id.is_empty() {
              None
            } else {
              jobs.filter(j => j.id == stage.milestone_task_id).get(0)
            }
            div(
              class="mission-stage-detail",
              attrs=@html.Attrs::build()
                .data_set("stage-id", stage.id)
                .data_set("stage-status", stage.status),
            ) <| [
              div(class="mission-stage-detail-copy") <| [
                strong(stage.title),
                if !stage.outcome.is_empty() {
                  p(stage.outcome)
                } else {
                  @html.nothing
                },
              ],
              div(class="mission-stage-detail-actions") <| [
                match linked_job {
                  Some(job) =>
                    button(
                      type_="button",
                      class="button button-primary button-small",
                      on_click=emit(WorkspaceAction(Focus(job.id))),
                      "打开此阶段材料",
                    )
                  None => @html.nothing
                },
                if selected is Some(_) {
                  button(
                    type_="button",
                    class="workspace-quiet-button",
                    on_click=emit(WorkspaceAction(SelectStage(""))),
                    "显示全部阶段",
                  )
                } else {
                  @html.nothing
                },
              ],
            ]
          }
          None => @html.nothing
        },
      ]
    }
  }
}

///|
fn founder_focus_reason(model : Model, job : TodayTask, stage : String) -> String {
  match stage {
    "waiting_approval" => "等待创始人确认"
    "review" => "待核对交付"
    "failed" => "执行受阻需介入"
    _ =>
      if charter_is_critical_task(model.charter, job.id) {
        "20% 关键路径"
      } else {
        "需关注"
      }
  }
}

///|
fn workspace_founder_focus_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let all_jobs = workspace_jobs(model)
  if all_jobs.is_empty() && !model.charter.persisted {
    return @html.nothing
  }
  let critical = workspace_founder_critical_jobs(model)
  let delegated = workspace_delegated_jobs(model)
  section(
    class="founder-focus",
    attrs=@html.Attrs::build()
      .aria_label("我的 20% 关键决策")
      .data_set(
        "has-critical",
        if critical.is_empty() {
          "false"
        } else {
          "true"
        },
      ),
  ) <| [
    div(class="founder-focus-head") <| [
      div(class="founder-focus-title") <| [
        span(
          class="founder-focus-beacon",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        h2("我的 20% 关键决策"),
      ],
      span(
        class="founder-focus-ratio",
        critical.length().to_string() +
        " 项需创始人判断 · " +
        delegated.length().to_string() +
        " 项委派执行",
      ),
    ],
    if critical.is_empty() {
      p(
        class="founder-focus-empty",
        if all_jobs.is_empty() {
          "暂无待处理的关键决策项。"
        } else {
          "当前没有待创始人拍板的关键项，其余 " +
          delegated.length().to_string() +
          " 项由团队按计划推进。"
        },
      )
    } else {
      div(class="founder-focus-grid") <| critical.map(job => {
        let stage = workspace_stage(workspace_record(model, job), job)
        let pinned = charter_is_critical_task(model.charter, job.id)
        article(
          class="founder-focus-card",
          attrs=@html.Attrs::build()
            .data_set("focus-job-id", job.id)
            .data_set("stage", stage),
        ) <| [
          div(class="founder-focus-card-head") <| [
            h3(job.title),
            span(
              class="founder-reason-badge",
              attrs=@html.Attrs::build().data_set("stage", stage),
              founder_focus_reason(model, job, stage),
            ),
          ],
          workspace_status(stage),
          if !job.execution_error.is_empty() && stage == "failed" {
            p(class="flow-job-error", job.execution_error)
          } else {
            @html.nothing
          },
          div(class="founder-focus-actions") <| [
            button(
              type_="button",
              class="button button-primary button-small",
              on_click=emit(WorkspaceAction(Focus(job.id))),
              "打开材料 (MoonDesk)",
            ),
            button(
              type_="button",
              class="button button-secondary button-small",
              on_click=emit(WorkspaceAction(FocusPane(job.id, "progress"))),
              "团队与交付",
            ),
            if model.charter.persisted {
              button(
                type_="button",
                class="workspace-quiet-button founder-pin-toggle",
                disabled=model.charter.saving,
                attrs=@html.Attrs::build().aria_pressed(
                  if pinned {
                    "true"
                  } else {
                    "false"
                  },
                ),
                on_click=emit(CharterAction(ToggleCriticalTask(job.id))),
                if pinned {
                  "取消 20% 标记"
                } else {
                  "固定到 20%"
                },
              )
            } else {
              @html.nothing
            },
          ],
        ]
      })
    },
  ]
}
