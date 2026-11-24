///|
fn dispatch_native_label(run : DispatchRun?) -> String {
  match run {
    None => "尚未开始 MoonClaw 原生执行"
    Some(run) =>
      match run.state {
        "queued" => "等待原生执行启动"
        "running" => "MoonClaw 正在执行"
        "waiting_approval" => "MoonClaw 等待原有执行确认；尚未完成"
        "completed" => "原生执行完成；请查看结果并提交验收"
        "failed" => "原生执行失败；查看错误和输出"
        "cancelled" => "原生执行已取消；未产生完成事实"
        "interrupted" => "原生执行已中断；可继续同一执行"
        "runtime_unavailable" =>
          "MoonClaw 当前不可用；可重试同一执行交接"
        _ => "原生执行状态待确认；刷新或重试同一交接"
      }
  }
}

///|
fn dispatch_open_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  div(class="inline-form") <| [
    dispatch_task_input(
      "dispatch-open-id",
      "恢复 / 打开正式任务",
      model.dispatch_task_open_id,
      "任务 ID（页面链接也会保留此 ID）",
      emit.map(value => InputDispatchTaskOpenId(value)),
    ),
    secondary_button(emit, OpenDispatchTask, "打开任务"),
    if model.dispatch_task_id.is_empty() {
      @html.nothing
    } else {
      secondary_button(
        emit,
        RefreshDispatchTask(
          model.dispatch_task_id,
          model.dispatch_task_selection,
        ),
        "刷新状态",
      )
    },
  ]
}

///|
fn dispatch_safe_link(value : String) -> Bool {
  value.has_prefix("https://") || value.has_prefix("http://")
}

///|
fn dispatch_result_reference(value : String) -> @html.Html {
  dispatch_named_result_reference(value, value)
}

///|
fn dispatch_named_result_reference(
  value : String,
  label : String,
) -> @html.Html {
  if dispatch_safe_link(value) {
    a(
      href=value,
      target=Blank,
      attrs=@html.Attrs::build().rel("noopener noreferrer"),
      if label.is_empty() {
        value
      } else {
        label
      },
    )
  } else {
    span(value)
  }
}

///|
fn dispatch_context_coverage_label(value : String) -> String {
  match value {
    "complete" => "完整（支持的可见正文）"
    "partial" => "部分"
    "unavailable" => "不可用"
    "untagged" => "捕获时未关联产品"
    _ => value
  }
}

///|
fn dispatch_context_artifact_label(value : String) -> String {
  match value {
    "pending" => "待暂存"
    "available" => "可用"
    "missing" => "文件缺失"
    "conflict" => "文件内容冲突"
    _ => "不可用"
  }
}

///|
fn dispatch_context_optional_text(
  label : String,
  value : String?,
) -> @html.Html {
  match value {
    Some(value) if !value.is_empty() => small(label + " · " + value)
    _ => @html.nothing
  }
}

///|
fn dispatch_context_optional_bytes(
  label : String,
  value : Double?,
) -> @html.Html {
  dispatch_context_optional_text(
    label,
    value.map(bytes => bytes.to_string() + " 字节"),
  )
}

///|
fn dispatch_product_context_view(
  model : Model,
  run : DispatchRun,
) -> @html.Html {
  match run.product_context {
    Unbound =>
      small(
        "本次执行产品上下文 · 未绑定（未记录运行快照）",
      )
    Unsupported(schema) =>
      small("本次执行产品上下文 · 暂不支持此版本：" + schema)
    Malformed =>
      small(
        "本次执行产品上下文 · 元数据无法读取；执行结果仍可查看",
      )
    Captured(context) =>
      div <| [
        strong(
          "本次执行捕获产品 · " +
          (if context.product_id.is_empty() {
            "未关联"
          } else if context.product_name.is_empty() {
            context.product_id
          } else {
            context.product_name + " (" + context.product_id + ")"
          }),
        ),
        small(
          "当前任务关联产品 · " +
          dispatch_product_label(model, model.dispatch_task_product_id),
        ),
        p(
          "捕获时完整性 · " +
          dispatch_context_coverage_label(context.coverage),
        ),
        p(
          "输入文件状态 · " +
          dispatch_context_artifact_label(context.artifact_state),
        ),
        if context.artifact_error.is_empty() {
          @html.nothing
        } else {
          p("输入文件说明 · " + context.artifact_error)
        },
        div <| context.issues.map(issue => small("快照限制 · " + issue)),
        if context.context_path.is_empty() {
          small("未记录输入文件路径")
        } else {
          div <| [
            small("执行工作区 · " + run.workspace),
            strong("产品上下文输入（相对执行工作区）"),
            span(context.context_path),
          ]
        },
        small(
          "输入暂存会在执行工作区写入文件，Review-only 也包含此步骤。",
        ),
        small(
          "完整仅指支持的可见正文，不代表页面还原、Agent 已阅读或任务已验收。",
        ),
        details <| [
          summary("快照与 PRD 来源"),
          small("快照格式 · " + context.schema),
          small("快照 SHA-256 · " + context.sha256),
          small("快照大小 · " + context.size_bytes.to_string() + " 字节"),
          match context.prd {
            None => small("未记录 PRD 来源元数据")
            Some(prd) =>
              div <| [
                dispatch_context_optional_text("PRD 文档", prd.document_id),
                dispatch_context_optional_text("PRD 版本", prd.version),
                dispatch_context_optional_text(
                  "PRD 提取覆盖",
                  prd.coverage.map(dispatch_context_coverage_label),
                ),
                dispatch_context_optional_text(
                  "源文件 SHA-256",
                  prd.source_sha256,
                ),
                dispatch_context_optional_bytes(
                  "源文件大小",
                  prd.source_size_bytes,
                ),
                dispatch_context_optional_text(
                  "正文 SHA-256",
                  prd.text_sha256,
                ),
                dispatch_context_optional_bytes(
                  "正文大小",
                  prd.text_size_bytes,
                ),
                dispatch_context_optional_text(
                  "提取版本",
                  prd.extraction_version,
                ),
                div <| prd.limitations
                .unwrap_or([])
                .map(limit => small("PRD 限制 · " + limit)),
              ]
          },
        ],
      ]
  }
}

///|
fn dispatch_native_result(
  model : Model,
  emit~ : @rabbita.Emit[Msg] = _ => none,
) -> @html.Html {
  div(class="inline-form") <| [
    match model.dispatch_run {
      None => @html.nothing
      Some(run) =>
        div <| [
          strong(dispatch_native_label(Some(run))),
          dispatch_guidance_capture_view(run.book_guidance),
          dispatch_context_notice(run),
          if run.summary.is_empty() {
            @html.nothing
          } else {
            p(run.summary)
          },
          if run.error.is_empty() {
            @html.nothing
          } else {
            p("错误 · " + run.error)
          },
          if run.state == "completed" {
            small(
              "结果来自最近一次读取；稍后写入的产物可点击“刷新状态”查看。",
            )
          } else {
            @html.nothing
          },
          div <| run.output_urls.map(dispatch_result_reference),
          if run.artifacts.is_empty() {
            @html.nothing
          } else {
            small("执行工作区 · " + run.workspace)
          },
          div <| run.artifacts.map(artifact => {
            div <| [
              strong("输出文件（相对工作区）"),
              span(artifact.path),
              details(class="journey-details") <| [
                summary("输出来源"),
                small("来源 · " + artifact.evidence_id),
              ],
              dispatch_output_button(
                emit,
                model,
                run.command_id,
                artifact.path,
                artifact.evidence_id,
              ),
            ]
          }),
          details(class="journey-details") <| [
            summary("执行身份与输入快照"),
            small("执行 · " + run.run_id),
            small(
              "会话 · " + run.session_id + " / 命令 · " + run.command_id,
            ),
            dispatch_product_context_view(model, run),
          ],
        ]
    },
    if model.dispatch_task_report_summary.is_empty() {
      @html.nothing
    } else {
      p("报告 · " + model.dispatch_task_report_summary)
    },
    if model.dispatch_task_evidence_id.is_empty() {
      @html.nothing
    } else {
      details <| [
        summary(
          "交付引用 · " +
          dispatch_report_evidence(model).length().to_string() +
          " 条",
        ),
        div <| dispatch_report_evidence(model).map(value => {
          p <| [
            dispatch_result_reference(value),
          ]
        }),
      ]
    },
  ]
}

///|
fn dispatch_execution_settings(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.dispatch_run is Some(_) {
    small("执行工作区 · " + model.dispatch_task_workspace)
  } else {
    details(
      class="journey-details",
      open=model.dispatch_task_workspace.is_empty() &&
        model.dispatch_task_report_id.is_empty(),
    ) <| [
      summary("执行工作区与模型"),
      p(
        "请填写 MoonClaw 可访问的实际工作区。产品源码目录不会自动成为执行工作区。",
      ),
      dispatch_task_input(
        "dispatch-saved-workspace",
        "执行工作区",
        model.dispatch_task_workspace,
        "MoonClaw 可访问的实际路径",
        emit.map(value => InputDispatchTaskWorkspace(value)),
      ),
      dispatch_task_input(
        "dispatch-saved-model",
        "执行模型（可选）",
        model.dispatch_task_model,
        "留空使用已配置模型",
        emit.map(value => InputDispatchTaskModel(value)),
      ),
      secondary_button(
        emit,
        SaveDispatchExecutionSettings,
        "保存执行设置",
      ),
    ]
  }
}

///|
fn dispatch_resume_label(model : Model) -> String {
  match model.dispatch_run {
    Some(run) if run.state == "interrupted" => "Resume · 继续原生执行"
    _ => "重试原生交接"
  }
}

///|
fn dispatch_context_notice(run : DispatchRun) -> @html.Html {
  match run.product_context {
    Captured(context) =>
      if context.coverage != "complete" ||
        context.artifact_state != "available" ||
        !context.artifact_error.is_empty() ||
        !context.issues.is_empty() {
        div(class="boundary-note") <| [
          strong("输入上下文说明"),
          p(
            "捕获时完整性 · " +
            dispatch_context_coverage_label(context.coverage),
          ),
          p(
            "输入文件状态 · " +
            dispatch_context_artifact_label(context.artifact_state),
          ),
          if context.artifact_error.is_empty() {
            @html.nothing
          } else {
            p(context.artifact_error)
          },
          div <| context.issues.map(issue => p(issue)),
        ]
      } else {
        @html.nothing
      }
    Malformed =>
      p("产品上下文元数据无法读取；仍可查看执行结果。")
    Unsupported(schema) => p("产品上下文版本暂不支持：" + schema)
    Unbound => small("本次执行未记录产品上下文快照。")
  }
}
