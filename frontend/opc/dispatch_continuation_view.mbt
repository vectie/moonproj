///|
fn dispatch_continuation_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.dispatch_run is None {
    return @html.nothing
  }
  let state = model.dispatch_continuation
  let current = state.task_id == model.dispatch_task_id &&
    state.selection == model.dispatch_task_selection
  section(id="dispatch-result-choice", class="journey-section result-choice") <| [
    h3("选择结果与报告"),
    small(
      "原始执行记录保持不变。返回链接仅提示候选命令或人工修订；服务端验证来源，明确选择后才用于提交报告。",
    ),
    secondary_button(
      emit,
      ContinuationAction(Refresh),
      "刷新后续执行与已选来源",
    ),
    if current {
      div <| [
        p("读取状态 · " + state.phase),
        if state.error != "" {
          p(state.error)
        } else {
          @html.nothing
        },
        p(
          "已保存交付来源 · " +
          (if state.selected is Null {
            "原始执行（尚未另选）"
          } else {
            dispatch_delivery_source_label(state.selected)
          }),
        ),
        if state.operation_pending {
          p(
            class="boundary-note",
            "结果选择尚未确认。请刷新后续执行与已选来源，恢复同一操作。",
          )
        } else {
          @html.nothing
        },
        if !state.source_verified {
          p(
            class="boundary-note",
            "交付来源尚未核实，请刷新正式任务后再提交或接受。",
          )
        } else {
          @html.nothing
        },
        details(
          class="journey-details",
          open=model.dispatch_task_stage == "submitted" ||
            model.dispatch_task_stage == "accepted",
        ) <| [
          summary("已保存报告与接受记录"),
          dispatch_report_selection_view(emit, model),
        ],
        dispatch_human_revision_view(emit, model),
        details(
          class="journey-details",
          open=!(state.candidate is Null) || state.operation_pending,
        ) <| [
          summary("其他执行结果 · 查看并明确选择"),
          div <| state.records.map(record => {
            div <| [
              strong(
                dispatch_json_text(record, "command_id") +
                " · " +
                dispatch_json_text(record, "state"),
              ),
              small(
                "原始运行 · " +
                dispatch_json_text(record, "original_run_id") +
                " / 历史参考 · " +
                dispatch_json_text(record, "prior_result_command_id"),
              ),
              p(dispatch_json_text(record, "summary")),
              secondary_button(
                emit,
                ContinuationAction(
                  Preview(dispatch_json_text(record, "command_id")),
                ),
                "查看此准确结果",
              ),
            ]
          }),
          if !(state.candidate is Null) {
            details(open=true) <| [
              summary(
                "候选结果 · " +
                dispatch_json_text(state.candidate, "command_id"),
              ),
              p(dispatch_json_text(state.candidate, "summary")),
              p(dispatch_json_text(state.candidate, "error")),
              div <| dispatch_json_strings(state.candidate, "output_urls").map(
                dispatch_result_reference,
              ),
              div <| dispatch_json_strings(state.candidate, "evidence_ids").map(value => {
                  p(value)
                },
              ),
              div <| dispatch_continuation_array(
                state.candidate,
                "artifact_refs",
              )
              .filter(item => {
                dispatch_json_text(item, "command_id") ==
                dispatch_json_text(state.candidate, "command_id")
              })
              .map(item => {
                div <| [
                  p(dispatch_json_text(item, "path")),
                  dispatch_output_button(
                    emit,
                    model,
                    dispatch_json_text(item, "command_id"),
                    dispatch_json_text(item, "path"),
                    dispatch_json_text(item, "evidence_id"),
                  ),
                ]
              }),
              details(class="journey-details") <| [
                summary("此结果的输入与来源"),
                small(
                  "来源已由服务端验证 · " +
                  dispatch_json_text(state.candidate, "continuation_id"),
                ),
                p(
                  "捕获模型 · " +
                  dispatch_json_text(state.candidate, "model"),
                ),
                p(
                  "输入快照 · " +
                  dispatch_json_text(
                    dispatch_json_field(state.candidate, "input"),
                    "path",
                  ) +
                  " / " +
                  dispatch_json_text(
                    dispatch_json_field(state.candidate, "input"),
                    "sha256",
                  ),
                ),
              ],
              if state.phase == "ready" &&
                !state.accepted &&
                !dispatch_task_inspection_only(model) &&
                dispatch_json_text(state.candidate, "state") == "completed" {
                secondary_button(
                  emit,
                  ContinuationAction(Select),
                  "明确选择此结果用于报告",
                )
              } else {
                small(
                  "只有当前未接受任务的已完成准确结果可被选择。",
                )
              },
            ]
          } else {
            @html.nothing
          },
          if !state.accepted &&
            !dispatch_task_inspection_only(model) &&
            model.dispatch_run is Some(run) &&
            run.state == "completed" {
            secondary_button(
              emit,
              ContinuationAction(SelectOriginal),
              "明确选择原始执行用于报告",
            )
          } else {
            @html.nothing
          },
        ],
        if state.accepted {
          small(
            "任务已接受，仅可查看；此处不会修改已接受报告。",
          )
        } else {
          small("选择结果不会自动提交报告或接受任务。")
        },
      ]
    } else {
      small("读取后续执行后可查看和选择结果。")
    },
  ]
}
