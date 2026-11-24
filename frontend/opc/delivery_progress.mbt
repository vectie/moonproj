///|
fn delivery_progress(model : Model) -> Json {
  let note = dispatch_json_field(model.dispatch_offer_task, "delivery_progress")
  let execution = dispatch_json_field(model.dispatch_offer_task, "execution")
  let revision = dispatch_json_field(
    dispatch_json_field(execution, "revision_request"),
    "snapshot",
  )
  let command = if !dispatch_json_text(revision, "command_id").is_empty() {
    dispatch_json_text(revision, "command_id")
  } else {
    model.dispatch_run.map(r => r.command_id).unwrap_or("")
  }
  if dispatch_json_text(note, "schema") == "moonproj.delivery-progress.v1" &&
    dispatch_json_text(note, "task_id") == model.dispatch_task_id &&
    !command.is_empty() &&
    dispatch_json_text(note, "command_id") == command {
    note
  } else {
    Json::null()
  }
}

///|
fn delivery_contribution(note : Json, worker : String) -> Json {
  dispatch_continuation_array(note, "contributions")
  .filter(item => dispatch_json_text(item, "worker_id") == worker)
  .get(0)
  .unwrap_or(Json::null())
}

///|
fn delivery_now(model : Model) -> String {
  let control = delivery_control(model)
  if control == "stopped" {
    return "工作已停止，已有成果保留。"
  }
  if control == "stopping" {
    return "正在停止，等待执行团队确认。"
  }
  if ["revising", "resuming"].contains(control) {
    return "正在恢复这项交付，等待确认。"
  }
  if dispatch_task_inspection_only(model) {
    return "你已验收这项交付。"
  }
  guard model.dispatch_run is Some(run) else { return "尚未开始。" }
  let state = delivery_run_state(model)
  if ["failed", "cancelled", "interrupted", "runtime_unavailable", "unknown"].contains(
      state,
    ) {
    let error = delivery_run_error(model)
    return if error.is_empty() {
      dispatch_native_label(Some({ ..run, state, }))
    } else {
      error
    }
  }
  if state == "completed" {
    return "本轮执行已结束，请检查整合稿是否满足交付要求。"
  }
  if state == "waiting_approval" {
    return "正在等待你的确认，工作尚未完成。"
  }
  let now = dispatch_json_text(delivery_progress(model), "now")
  if !now.is_empty() {
    return now
  }
  let workers = delivery_workers(
    dispatch_json_field(model.dispatch_offer_task, "execution"),
  )
  if !workers.is_empty() &&
    workers.all(w => dispatch_json_field(w, "terminal") is True) {
    return "专员工作已结束，等待负责人整合或说明剩余问题；这不代表交付完成。"
  }
  if state == "queued" {
    "等待开始。"
  } else {
    "团队正在执行；尚未提供具体工作说明。"
  }
}

///|
fn delivery_latest_revision(model : Model) -> Json? {
  let execution = dispatch_json_field(model.dispatch_offer_task, "execution")
  let command = dispatch_json_text(
    dispatch_json_field(
      dispatch_json_field(execution, "revision_request"),
      "snapshot",
    ),
    "command_id",
  )
  if command.is_empty() {
    return dispatch_continuation_selected(model)
  }
  Some(
    dispatch_continuation_array(model.dispatch_offer_task, "continuations")
    .filter(r => dispatch_json_text(r, "command_id") == command)
    .get(0)
    .unwrap_or({
      "state": "unknown",
      "error": "本轮修改的执行状态尚未确认，请刷新。",
    }),
  )
}

///|
fn delivery_run_state(model : Model) -> String {
  match delivery_latest_revision(model) {
    Some(record) => dispatch_json_text(record, "state")
    None => model.dispatch_run.map(r => r.state).unwrap_or("")
  }
}

///|
fn delivery_run_error(model : Model) -> String {
  match delivery_latest_revision(model) {
    Some(record) => dispatch_json_text(record, "error")
    None => model.dispatch_run.map(r => r.error).unwrap_or("")
  }
}

///|
fn delivery_stage_label(model : Model) -> String {
  match delivery_control(model) {
    "stopping" => "停止待确认"
    "stopped" => "已停止"
    "revising" => "修改中"
    "resuming" => "恢复待确认"
    _ => {
      if dispatch_task_inspection_only(model) {
        return "已验收"
      }
      match model.dispatch_run {
        None => "待开始"
        Some(_) if delivery_run_state(model) == "completed" =>
          "本轮执行结束"
        Some(_) =>
          office_status_label(
            office_stage(delivery_run_state(model), "", false),
          )
      }
    }
  }
}

///|
fn delivery_overview_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let progress = delivery_progress(model)
  let promised = dispatch_json_text(progress, "deliverable")
  let next = dispatch_json_text(progress, "next")
  let attention = dispatch_json_text(progress, "needs_user")
  section(class="delivery-overview") <| [
    h3("你将收到"),
    p(if promised.is_empty() { model.dispatch_task_title } else { promised }),
    if model.dispatch_task_acceptance.is_empty() {
      @html.nothing
    } else {
      p(
        class="delivery-criteria",
        "交付要求 · " + model.dispatch_task_acceptance,
      )
    },
    div(
      class="delivery-situation",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
    ) <| [
      p <| [
        strong("现在 · "),
        span(delivery_now(model)),
      ],
      p <| [
        strong("接下来 · "),
        span(
          if dispatch_task_inspection_only(model) {
            "保留已验收版本；新的目标另建任务。"
          } else if delivery_control(model) == "stopped" {
            "由你决定是否继续这项交付。"
          } else if delivery_run_state(model) == "completed" {
            "查看整合稿；需要修改时发送修改要求。"
          } else if !next.is_empty() {
            next
          } else if model.dispatch_run is None {
            "开始后，负责人分配工作并整合最终成果。"
          } else {
            "等待负责人提供下一步说明；不按专员完成数推算交付完成。"
          },
        ),
      ],
      p <| [
        strong("需要你 · "),
        span(
          if dispatch_task_inspection_only(model) {
            "暂无待办。"
          } else if !attention.is_empty() &&
            delivery_control(model) != "stopped" {
            attention
          } else if delivery_control(model) == "stopped" {
            "决定是否继续，或查看已保留的成果。"
          } else if model.dispatch_run is None {
            "确认交付要求和工作区，然后开始。"
          } else if delivery_run_state(model) == "waiting_approval" {
            "打开执行记录，处理待确认事项。"
          } else if delivery_run_state(model) == "completed" {
            "检查当前整合稿，再决定验收或修改。"
          } else {
            "暂未收到具体的输入或决定请求。"
          },
        ),
      ],
    ],
    if dispatch_json_text(model.dispatch_task_source_context, "reference").is_empty() &&
      dispatch_json_text(model.dispatch_task_source_context, "problem").is_empty() {
      @html.nothing
    } else {
      section <| [
        h3("工作材料"),
        dispatch_source_context_view(
          model.dispatch_task_source_context,
          label="打开工作材料",
        ),
      ]
    },
    delivery_contributions_view(model),
    delivery_current_output_view(emit, model),
  ]
}

///|
fn delivery_contributions_view(model : Model) -> @html.Html {
  let execution = dispatch_json_field(model.dispatch_offer_task, "execution")
  let progress = delivery_progress(model)
  let workers = delivery_workers(execution)
  section(class="delivery-contributions") <| [
    h3("谁在为交付做什么"),
    p("负责人 · 分配工作、整合成果并核对交付要求。"),
    if workers.is_empty() {
      p(
        if model.dispatch_run is None {
          "尚未分配专员。"
        } else {
          "尚无可核实的专员记录。"
        },
      )
    } else {
      div <| workers.mapi((index, worker) => {
        let contribution = delivery_contribution(
          progress,
          dispatch_json_text(worker, "worker_id"),
        )
        let responsibility = dispatch_json_text(contribution, "responsibility")
        let target = dispatch_json_text(contribution, "contributes_to")
        let stage = office_status_label(
          office_stage(
            dispatch_json_text(worker, "status"),
            delivery_control(model),
            dispatch_json_field(worker, "terminal") is True,
          ),
        )
        details(class="delivery-contribution") <| [
          summary <| [
            strong(
              if responsibility.is_empty() {
                "专员 " + (index + 1).to_string()
              } else {
                responsibility
              },
            ),
            status_badge(stage, tone="info"),
            span(
              class="delivery-contribution-target",
              if target.is_empty() {
                "对交付的具体贡献尚未说明。"
              } else {
                "用于 · " + target
              },
            ),
          ],
          strong("已取得的成果"),
          p(
            if dispatch_json_text(worker, "summary").is_empty() {
              "尚无已保存的成果说明。"
            } else {
              dispatch_json_text(worker, "summary")
            },
          ),
          if dispatch_json_field(worker, "summary_truncated") is True {
            small("成果说明较长，此处仅显示部分。")
          } else {
            @html.nothing
          },
          div <| dispatch_continuation_array(worker, "artifact_references").map(item => {
              p(dispatch_json_text(item, "path"))
            },
          ),
          p(
            "专员的完成只代表这部分工作结束，不表示已整合、复核或验收。",
          ),
          details(class="journey-details") <| [
            summary("来源记录"),
            p(dispatch_json_text(worker, "worker_id")),
            p(dispatch_json_text(worker, "child_command_id")),
          ],
        ]
      })
    },
  ]
}

///|
fn delivery_current_output_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if dispatch_task_inspection_only(model) {
    let state = model.dispatch_continuation
    let accepted = state.report_records
      .filter(r => {
        dispatch_json_text(r, "reportGuid") == state.accepted_report_id
      })
      .get(0)
    return section(class="delivery-current-output") <| [
      h3("已验收的交付记录"),
      match accepted {
        Some(report) => p(dispatch_json_text(report, "summary"))
        None =>
          p(
            "正在等待已验收版本的记录；当前工作区文件不代表验收时的内容。",
          )
      },
      dispatch_accepted_human_export_view(emit, model),
      details(class="journey-details") <| [
        summary("查看验收版本与报告"),
        dispatch_report_selection_view(emit, model),
      ],
    ]
  }
  let revision = dispatch_continuation_selected(model)
  let human = dispatch_human_revision_selected(model)
  let summary_text = if human is Some(_) {
    "已选择你在 MoonDesk 保存的修订。"
  } else if revision is Some(record) {
    dispatch_json_text(record, "summary")
  } else {
    model.dispatch_run.map(r => r.summary).unwrap_or("")
  }
  let artifacts = if human is Some(record) {
    [dispatch_json_field(record, "output")]
  } else if revision is Some(record) {
    dispatch_continuation_array(record, "artifact_refs")
  } else {
    model.dispatch_run
    .map(r => {
      r.artifacts.map(a => {
        (
          {
            "path": a.path,
            "evidence_id": a.evidence_id,
            "command_id": r.command_id,
          } : Json)
      })
    })
    .unwrap_or([])
  }
  let artifacts = artifacts.filter(a => {
    !dispatch_json_text(a, "path").has_prefix(".moonproj-progress-")
  })
  let output = dispatch_json_text(delivery_progress(model), "output_path")
  let integrated = artifacts.filter(a => {
    dispatch_json_text(a, "path") == output &&
    dispatch_json_text(a, "command_id") ==
    dispatch_json_text(delivery_progress(model), "command_id")
  })
  section(class="delivery-current-output") <| [
    h3("当前整合稿"),
    if human is Some(record) {
      div <| [
        p(summary_text),
        strong(
          dispatch_json_text(dispatch_json_field(record, "output"), "path"),
        ),
        secondary_button(
          emit,
          ContinuationAction(
            PreviewHumanRevision(dispatch_json_text(record, "revision_id")),
          ),
          "查看已选修订",
        ),
      ]
    } else if integrated.is_empty() {
      p(
        "尚无可查看的整合稿。专员成果与执行摘要不等于最终交付。",
      )
    } else if summary_text.is_empty() {
      @html.nothing
    } else {
      p(summary_text)
    },
    div <| integrated.map(item => {
      div(class="delivery-output-file") <| [
        strong(dispatch_json_text(item, "path")),
        if human is Some(_) {
          @html.nothing
        } else {
          dispatch_output_button(
            emit,
            model,
            dispatch_json_text(item, "command_id"),
            dispatch_json_text(item, "path"),
            dispatch_json_text(item, "evidence_id"),
          )
        },
      ]
    }),
    if human is None && !artifacts.is_empty() && integrated.is_empty() {
      details(class="journey-details") <| [
        summary("其他已记录的输出"),
        div <| artifacts.map(item => {
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
      ]
    } else {
      @html.nothing
    },
    if integrated.is_empty() && human is None {
      @html.nothing
    } else {
      p(
        "文本稿可在 MoonDesk 编辑并保存修订，返回这里选择交付版本；保存不会自动验收。",
      )
    },
    dispatch_desk_handoff_view(emit, model),
  ]
}

///|
fn delivery_workers(execution : Json) -> Array[Json] {
  dispatch_continuation_array(execution, "workers").filter(w => {
    let child = dispatch_json_text(w, "child_session_id")
    !child.is_empty() &&
    !dispatch_continuation_array(
      dispatch_json_field(execution, "control_receipt"),
      "sessions",
    ).any(node => {
      dispatch_json_text(node, "session_id") == child &&
      dispatch_json_text(node, "state") == "missing"
    })
  })
}
