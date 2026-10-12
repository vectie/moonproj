///|
#cfg(target="js")
extern "js" fn dispatch_command_nonce() -> String =
  #| () => String(Date.now()) + "-" + (typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2))

///|
#cfg(target="js")
extern "js" fn dispatch_today() -> String =
  #| () => new Date().toISOString().slice(0, 10)

///|
fn dispatch_result_text(
  response : String,
  section : String,
  key : String,
) -> String {
  let payload = @json.parse(response) catch { _ => Json::null() }
  match payload {
    Object(root) =>
      match root.get(section) {
        Some(Object(fields)) =>
          match fields.get(key) {
            Some(String(value)) => value
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
}

///|
fn dispatch_task_authority(model : Model, capability : String) -> Json {
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("principal-opc-dispatch"),
    "actor_id": Json::string(model.dispatch_task_actor_id.trim().to_owned()),
    "capability": Json::string(capability),
    "scope": Json::string(
      "project:" + model.dispatch_task_project_id.trim().to_owned(),
    ),
  })
}

///|
fn request_dispatch_task_submit(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  if !dispatch_report_requires_capture(model) {
    return dispatch_post_task_report(
      emit,
      model,
      dispatch_report_in_memory_body(model),
    )
  }
  @cmd.custom_cmd(scheduler => {
    match
      dispatch_report_operation_body(
        model,
        dispatch_report_in_memory_body(model),
      ) {
      Err(error) =>
        scheduler.add(emit(dispatch_failure(model, "提交验收", error)))
      Ok(body) =>
        if dispatch_selection_store(
            dispatch_report_operation_key(model),
            body.stringify(),
            true,
          ) {
          scheduler.add(dispatch_post_task_report(emit, model, body))
        } else {
          scheduler.add(
            emit(
              dispatch_failure(
                model, "提交验收", "无法保存准确报告操作，尚未提交。请启用浏览器本地存储后重试。",
              ),
            ),
          )
        }
    }
  })
}

///|
fn dispatch_new_report_body(model : Model) -> Json {
  let nonce = dispatch_command_nonce()
  let report_id = "OPC-REPORT-" + nonce
  let body = Json::object({
    "idempotency_key": Json::string("opc-dispatch-submit-" + nonce),
    "report_id": Json::string(report_id),
    "task_id": Json::string(model.dispatch_task_id),
    "project_id": Json::string(model.dispatch_task_project_id.trim().to_owned()),
    "progress_pct": Json::number(100),
    "report_date": Json::string(dispatch_today()),
    "summary": Json::string(dispatch_report_summary(model)),
    "evidence_ids": Json::array(
      dispatch_report_evidence(model).map(Json::string),
    ),
  })
  dispatch_report_with_source(body, model)
}

///|
fn dispatch_post_task_report(
  emit : @rabbita.Emit[Msg],
  model : Model,
  captured : Json,
) -> Cmd {
  let report_id = dispatch_json_text(captured, "report_id")
  let body = captured.stringify()
  @http.post(
    "/api/company/plan/tasks/" +
    dispatch_url_encode(model.dispatch_task_id) +
    "/report",
  )
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let persisted_report_id = dispatch_result_text(
          response, "task_report", "aggregate_id",
        )
        let state = dispatch_result_text(response, "task_report", "state")
        if persisted_report_id != report_id || state != "observed" {
          emit(
            dispatch_failure(
              model,
              "提交验收",
              dispatch_response_error(response),
            ),
          )
        } else {
          @cmd.batch([
            if dispatch_report_requires_capture(model) {
              @cmd.custom_cmd(_ => {
                ignore(
                  dispatch_selection_store(
                    dispatch_report_operation_key(model),
                    body,
                    false,
                  ),
                )
              })
            } else {
              none
            },
            emit(
              DispatchTaskSubmitted(
                model.dispatch_task_id,
                model.dispatch_task_selection,
                persisted_report_id,
                dispatch_result_text(response, "task_report", "event_id"),
                dispatch_result_text(response, "task_report", "audit_id"),
              ),
            ),
          ])
        }
      }
      Err(error) =>
        emit(dispatch_failure(model, "提交验收", error.to_string()))
    }
  })
}

///|
fn request_dispatch_task_accept(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let idempotency_key = "opc-dispatch-accept-" + dispatch_command_nonce()
  let body = dispatch_accept_report_body(model, idempotency_key).stringify()
  @http.put(
    "/api/company/plan/tasks/" + dispatch_url_encode(model.dispatch_task_id),
  )
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) =>
        if dispatch_result_text(response, "task", "state") == "done" &&
          dispatch_result_text(response, "task", "task_id") ==
          model.dispatch_task_id {
          emit(
            DispatchTaskAccepted(
              model.dispatch_task_id,
              model.dispatch_task_selection,
              dispatch_result_text(response, "task", "event_id"),
              dispatch_result_text(response, "task", "audit_id"),
            ),
          )
        } else {
          emit(
            dispatch_failure(
              model,
              "接受结果",
              dispatch_response_error(response),
            ),
          )
        }
      Err(error) =>
        emit(dispatch_failure(model, "接受结果", error.to_string()))
    }
  })
}

///|
fn compact_kpi(
  label : String,
  value : String,
  note : String,
  tone : String,
) -> @html.Html {
  article(class="kpi-card kpi-\{tone}") <| [
    p(label),
    strong(value),
    small(note),
  ]
}

///|
fn section_title(title : String, note : String, badge : String) -> @html.Html {
  div(class="section-title") <| [
    div <| [
      h2(title),
      p(note),
    ],
    if badge.is_empty() {
      @html.nothing
    } else {
      status_badge(badge, tone="warning")
    },
  ]
}

///|
fn meter(value : Int, tone : String) -> @html.Html {
  div(class="meter") <| [
    div(class="meter-value meter-\{tone} meter-w-\{value}", ""),
  ]
}

///|
fn cockpit_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  today_view(emit, model)
}

///|
fn autonomy_card(level : String, count : String, desc : String) -> @html.Html {
  article(class="autonomy-card") <| [
    div(class="loop-head") <| [
      strong(level),
      span(count),
    ],
    p(desc),
  ]
}

///|
fn agent_card(
  name : String,
  role : String,
  level : String,
  task : String,
  budget : Int,
  state : String,
) -> @html.Html {
  article(class="agent-card") <| [
    div(class="loop-head") <| [
      div <| [
        strong(name),
        small(role),
      ],
      status_badge(level, tone="violet"),
    ],
    div(class="agent-task") <| [
      small("当前任务"),
      strong(task),
      status_badge(
        state,
        tone=if state == "运行中" { "accent" } else { "warning" },
      ),
    ],
    div(class="budget-row") <| [
      span("预算消耗 \{budget}%"),
      span("今日留痕 26"),
    ],
    meter(budget, if budget > 70 { "warn" } else { "info" }),
  ]
}

///|
fn fleet_view(_emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Fleet, status_badge("只读演练", tone="warning")),
    sample_data_boundary(),
    section_title(
      "自治分级制度", "授权不是信任问题，是预算与证据问题；升级必须经过独立审计。",
      "L4 暂停开放",
    ),
    div(class="autonomy-grid") <| [
      autonomy_card("L0", "1 个", "仅建议，不执行"),
      autonomy_card("L1", "3 个", "执行后必须报备"),
      autonomy_card("L2", "4 个", "可执行，接受抽检"),
      autonomy_card("L3", "2 个", "预算内完全自治"),
      autonomy_card("L4", "0 个", "完全委托，暂不开放"),
    ],
    section_title(
      "在编 Agent", "按角色、自治边界、预算和证据观察公司的数字劳动力。",
      "11/12 在线",
    ),
    div(class="agent-grid") <| [
      agent_card(
        "Architect-01", "产品与架构 · 开发域", "L2", "设计 v0.9 权限边界",
        46, "运行中",
      ),
      agent_card(
        "Builder-02", "MoonBit 工程 · 开发域", "L2", "实现质量 Gate 证据包",
        68, "运行中",
      ),
      agent_card(
        "Test-01", "测试与验证 · 开发域", "L3", "执行全量回归", 31,
        "运行中",
      ),
      agent_card(
        "Sentinel-01", "SLO 巡检 · 监测域", "L3", "诊断 API 延迟突增",
        74, "等待人类",
      ),
      agent_card(
        "Finance-01", "账簿与税务 · 公司域", "L1", "核对本月申报证据",
        52, "产出待审",
      ),
      agent_card(
        "Gatekeeper-01", "独立质量审计 · 治理域", "L0", "抽检 L2 Agent 行为",
        18, "运行中",
      ),
    ],
    @execution_cockpit.view(),
  ]
}

///|
fn task_card(
  id : String,
  kind : String,
  title : String,
  agent : String,
  progress : Int,
  evidence : String,
) -> @html.Html {
  article(class="task-card") <| [
    div(class="loop-head") <| [
      small(id),
      status_badge(kind, tone="muted"),
    ],
    strong(title),
    p(agent),
    meter(progress, if progress == 100 { "ok" } else { "violet" }),
    small("\{progress}% · 证据 \{evidence} 条"),
  ]
}

///|
fn dispatch_lane(
  title : String,
  hint : String,
  cards : Array[@html.Html],
  gate : Bool,
) -> @html.Html {
  section(class=if gate { "dispatch-lane is-gate" } else { "dispatch-lane" }) <| [
    div(class="lane-title") <| [
      strong(title),
      if gate {
        status_badge("需裁决", tone="warning")
      } else {
        @html.nothing
      },
    ],
    small(hint),
    div(class="task-stack") <| cards,
  ]
}

///|
fn dispatch_task_stage_label(stage : String) -> String {
  match stage {
    "pending" => "待启动"
    "in_progress" => "执行中"
    "submitted" => "待验收"
    "accepted" => "内部任务已接受"
    "loading" => "读取中"
    "blocked" => "任务阻塞"
    _ => "尚未创建"
  }
}

///|
fn dispatch_task_stage_tone(stage : String) -> String {
  match stage {
    "accepted" => "accent"
    "in_progress" => "violet"
    "submitted" => "warning"
    _ => "muted"
  }
}

///|
fn dispatch_task_input(
  id : String,
  label_text : String,
  value : String,
  placeholder : String,
  on_input : @rabbita.Emit[String],
  read_only? : Bool = false,
) -> @html.Html {
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(id), label_text),
    input(
      input_type=Text,
      attrs=@html.Attrs::build().id(id),
      value~,
      placeholder~,
      read_only~,
      on_input~,
    ),
  ]
}

///|
fn dispatch_task_form(emit : @rabbita.Emit[Msg], source : Model) -> @html.Html {
  let model = dispatch_draft_form_model(source)
  let frozen = match dispatch_active_draft(source) {
    Some(draft) => draft.state != "editing"
    None => true
  }
  form(
    class="inline-form",
    attrs=@html.Attrs::build()
      .id("dispatch-draft")
      .aria_label("创建正式编排任务"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("准备任务 · 写清想要的结果"),
        p(
          "先保存任务，再明确开始执行。你仍可以查看输出、补充人工指令，最后提交并接受结果。",
        ),
      ],
      status_badge("任务准备", tone="muted"),
    ],
    products_preparation_context(model),
    p(
      match dispatch_active_draft(source) {
        Some(draft) => draft.note
        None => "没有打开的本地草稿"
      },
    ),
    p(class="boundary-note", source.dispatch_draft_storage),
    dispatch_source_context_form(emit, source, frozen),
    research_draft_context(emit, source),
    work_packet_view(emit, source),
    dispatch_offer_local_view(emit, source, frozen),
    div(class="form-grid") <| [
      dispatch_task_input(
        "dispatch-task-title",
        "任务名称",
        model.dispatch_task_title,
        "需要交付的结果",
        emit.map(value => DraftAction(Input("title", value))),
        read_only=frozen,
      ),
      dispatch_task_input(
        "dispatch-task-acceptance",
        "验收标准",
        model.dispatch_task_acceptance,
        "如何判断结果可以接受？",
        emit.map(value => DraftAction(Input("acceptance", value))),
        read_only=frozen,
      ),
      dispatch_task_input(
        "dispatch-task-workspace-input",
        "执行工作区（MoonBook / 本机目录）",
        model.dispatch_task_workspace,
        "MoonClaw 可访问的实际工作区路径",
        emit.map(value => DraftAction(Input("workspace", value))),
        read_only=frozen,
      ),
      dispatch_task_input(
        "dispatch-task-begin",
        "计划开始（必填）",
        model.dispatch_task_begin_date,
        "YYYY-MM-DD",
        emit.map(value => DraftAction(Input("begin_date", value))),
        read_only=frozen,
      ),
      dispatch_task_input(
        "dispatch-task-end",
        "计划完成（必填）",
        model.dispatch_task_end_date,
        "YYYY-MM-DD",
        emit.map(value => DraftAction(Input("end_date", value))),
        read_only=frozen,
      ),
    ],
    details(
      class="journey-details",
      open=model.dispatch_task_project_id.is_empty() ||
        model.dispatch_task_actor_id.is_empty(),
    ) <| [
      summary("公司项目与登录身份"),
      div(class="form-grid") <| [
        dispatch_task_input(
          "dispatch-task-project",
          "项目 ID",
          model.dispatch_task_project_id,
          "真实公司项目 ID",
          emit.map(value => DraftAction(Input("project_id", value))),
          read_only=frozen,
        ),
        div(class="field") <| [
          label("签名身份 · 来自网关会话"),
          p(
            if model.dispatch_task_actor_id.is_empty() {
              "尚未登录"
            } else {
              model.dispatch_task_actor_id
            },
          ),
          secondary_button(emit, LoadDispatchSession, "刷新登录身份"),
        ],
      ],
    ],
    details(class="journey-details") <| [
      summary("可选设置 · 模型与负责人"),
      div(class="form-grid") <| [
        dispatch_task_input(
          "dispatch-task-model",
          "执行模型（可选）",
          model.dispatch_task_model,
          "留空使用 MoonClaw 已配置模型",
          emit.map(value => DraftAction(Input("model", value))),
          read_only=frozen,
        ),
        dispatch_task_input(
          "dispatch-task-owner",
          "负责人 ID（可选）",
          model.dispatch_task_owner_id,
          "授权范围内的负责人",
          emit.map(value => DraftAction(Input("owner_id", value))),
          read_only=frozen,
        ),
      ],
    ],
    details(class="journey-details", open=frozen) <| [
      summary("草稿身份与恢复信息"),
      p(dispatch_draft_note(source)),
    ],
    div(class="form-actions") <| [
      dispatch_draft_create_button(emit, source),
      secondary_button(emit, ExportFounderPacket, "下载工作包 Markdown"),
      secondary_button(emit, DraftAction(Park), "暂存并关闭草稿"),
      secondary_button(emit, DraftAction(New), "另建草稿"),
      if !model.products.prepared_product_id.is_empty() {
        secondary_button(
          emit,
          ProductsAction(CancelPreparation),
          "暂存草稿，返回产品",
        )
      } else {
        @html.nothing
      },
    ],
  ]
}

///|
fn dispatch_task_receipts(model : Model) -> @html.Html {
  if model.dispatch_task_event_id.is_empty() &&
    model.dispatch_task_audit_id.is_empty() {
    small("尚未收到事件或审计收据")
  } else {
    div(class="work-meta") <| [
      span("事件 · \{model.dispatch_task_event_id}"),
      span("审计 · \{model.dispatch_task_audit_id}"),
    ]
  }
}

///|
fn dispatch_task_action(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if !model.dispatch_task_pending_action.is_empty() {
    status_badge("等待持久化收据", tone="warning")
  } else {
    match model.dispatch_task_stage {
      "pending" =>
        if dispatch_can_start(model) {
          primary_button(
            emit,
            StartDispatchTask,
            if model.dispatch_run is None {
              "Start · MoonClaw 执行"
            } else {
              dispatch_resume_label(model)
            },
          )
        } else {
          status_badge(
            dispatch_native_label(model.dispatch_run),
            tone="warning",
          )
        }
      "in_progress" =>
        if dispatch_can_start(model) {
          primary_button(emit, StartDispatchTask, dispatch_resume_label(model))
        } else if !dispatch_can_submit(model) {
          status_badge(
            dispatch_native_label(model.dispatch_run),
            tone="warning",
          )
        } else {
          div(class="inline-form") <| [
            if dispatch_report_evidence(model).is_empty() {
              dispatch_task_input(
                "dispatch-task-evidence",
                "证据 ID / 可追溯引用",
                model.dispatch_task_evidence_id,
                "真实制品、提交、报告或证据账本引用",
                emit.map(value => InputDispatchTaskEvidenceId(value)),
              )
            } else {
              small(
                "已保留原生执行与交付证据；完整引用见结果详情。",
              )
            },
            primary_button(emit, SubmitDispatchTask, "Submit · 提交验收"),
          ]
        }
      "submitted" =>
        div(class="inline-form") <| [
          if dispatch_can_submit(model) {
            primary_button(
              emit,
              SubmitDispatchTask,
              "Submit · 为已选新来源提交另一份报告",
            )
          } else {
            @html.nothing
          },
          if dispatch_can_accept_report(model) {
            primary_button(
              emit,
              AcceptDispatchTask,
              "Accept · 接受报告 " + model.dispatch_task_report_id,
            )
          } else {
            small(dispatch_accept_report_blocker(model))
          },
        ]
      "accepted" => status_badge("闭环完成", tone="accent")
      _ => status_badge("先创建任务", tone="muted")
    }
  }
}

///|
fn dispatch_durable_task_card(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  article(class="work-card focused-work") <| [
    div(class="loop-head") <| [
      strong(model.dispatch_task_title),
      status_badge(
        dispatch_task_stage_label(model.dispatch_task_stage),
        tone=dispatch_task_stage_tone(model.dispatch_task_stage),
      ),
    ],
    dispatch_journey_view(model),
    div(id="dispatch-source-context") <| [
      p("验收标准 · " + model.dispatch_task_acceptance),
      dispatch_source_context_view(model.dispatch_task_source_context),
    ],
    dispatch_offer_view(emit, model),
    p(
      "产品 · " +
      dispatch_product_label(model, model.dispatch_task_product_id),
    ),
    details(class="journey-details", id="dispatch-task-receipts") <| [
      summary("任务身份与收据"),
      p("任务 · " + model.dispatch_task_id),
      p("公司项目 · " + model.dispatch_task_project_id),
      p(
        "负责人 · " +
        (if model.dispatch_task_owner_id.is_empty() {
          "未指定"
        } else {
          model.dispatch_task_owner_id
        }),
      ),
      a(
        href="?task=" + dispatch_url_encode(model.dispatch_task_id),
        "正式任务链接",
      ),
      if model.dispatch_task_report_id.is_empty() {
        @html.nothing
      } else {
        p(
          "任务报告 · " +
          model.dispatch_task_report_id +
          " / 创建时产品 · " +
          dispatch_product_label(model, model.dispatch_report_product_id),
        )
      },
      dispatch_task_receipts(model),
      dispatch_commitment_receipts_view(model.dispatch_task_commitment),
    ],
    section(class="journey-section", id="dispatch-execution") <| [
      h3("执行与结果"),
      dispatch_execution_settings(emit, model),
      dispatch_guidance_view(emit, model),
      secondary_button(
        emit,
        RefreshDispatchTask(
          model.dispatch_task_id,
          model.dispatch_task_selection,
        ),
        "刷新状态",
      ),
      dispatch_native_result(model, emit~),
    ],
    if model.dispatch_run is Some(_) {
      section(class="journey-section") <| [
        h3(
          if model.dispatch_task_stage == "accepted" {
            "查看工作记录"
          } else {
            "需要调整？加入人工指令"
          },
        ),
        p(
          if model.dispatch_task_stage == "accepted" {
            "此任务已接受。可以查看原始工作，新的目标请另建任务。"
          } else {
            "在 MoonDesk 检查输出，或继续此工作。回来后明确选择要提交的结果。"
          },
        ),
        dispatch_desk_handoff_view(emit, model),
      ]
    } else {
      @html.nothing
    },
    dispatch_continuation_view(emit, model),
    section(id="dispatch-task-action", class="journey-section task-next-action") <| [
      h3(
        match model.dispatch_task_stage {
          "pending" => "准备好后开始执行"
          "submitted" => "检查报告并接受结果"
          "accepted" => "任务已接受"
          _ => "查看结果后提交报告"
        },
      ),
      dispatch_task_action(emit, model),
    ],
    secondary_button(emit, ExportFounderPacket, "下载工作包 Markdown"),
    dispatch_learning_next(emit, model),
  ]
}

///|
fn dispatch_durable_board(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  div(class="focused-workspace") <| [
    dispatch_durable_task_card(emit, model),
  ]
}

///|
fn dispatch_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Dispatch,
      secondary_button(emit, Navigate(Products), "选择产品与目标"),
    ),
    dispatch_goal_flow(emit, model),
    research_import_view(emit, model),
    if model.dispatch_task_form_open {
      dispatch_task_form(emit, model)
    } else {
      @html.nothing
    },
    if model.dispatch_task_blocked {
      div(class="extension-boundary") <| [
        status_badge("操作未完成", tone="warning"),
        p(model.dispatch_task_note),
      ]
    } else {
      p(class="boundary-note", model.dispatch_task_note)
    },
    section(id="dispatch-task-workspace", class="section-block") <| [
      section_title(
        "当前正式任务",
        "执行 → 查看输出 → 按需人工调整 → 提交报告 → 接受结果",
        if model.dispatch_task_id.is_empty() {
          "0 个"
        } else {
          "1 个"
        },
      ),
      if model.dispatch_task_id.is_empty() {
        div(class="empty-panel") <| [
          strong("还没有正式任务"),
          p(
            "先从产品选择本次目标并准备任务。已有工作可以在下方打开或恢复。",
          ),
        ]
      } else {
        dispatch_durable_board(emit, model)
      },
    ],
    details(
      class="journey-details task-history",
      open=![
          "", "未保存到此浏览器", "已保存到此浏览器", "已读取此浏览器草稿",
        ].contains(model.dispatch_draft_storage) ||
        (
          model.dispatch_draft_storage == "未保存到此浏览器" &&
          !model.dispatch_drafts.is_empty()
        ) ||
        model.dispatch_drafts.any(draft => {
          [
            "uncertain", "retryable", "rejected", "saving", "creating", "recovering",
          ].contains(draft.state)
        }),
    ) <| [
      summary("其他任务 · 草稿、恢复与手动打开"),
      dispatch_open_form(emit, model),
      dispatch_draft_list(emit, model),
      secondary_button(emit, OpenDispatchTaskForm, "创建独立任务草稿"),
    ],
    details(class="reference-projection") <| [
      summary <| [
        div <| [
          strong("编排参考投影"),
          small("布局样例 · 不是当前 PostgreSQL 事实"),
        ],
        status_badge("只读样例", tone="muted"),
      ],
      div(class="dispatch-board") <| [
        dispatch_lane(
          "待分派 · 2",
          "进入编队前的队列",
          [
            task_card(
              "T-241", "软件", "统一发布证据格式", "待选择 Agent", 12,
              "2",
            ),
            task_card(
              "T-244", "公司", "更新季度现金计划", "待选择 Agent", 5,
              "1",
            ),
          ],
          false,
        ),
        dispatch_lane(
          "Agent 执行中 · 3",
          "自治执行 · 证据留痕",
          [
            task_card(
              "T-238", "软件", "实现 SLO 错误预算冻结", "Builder-02", 72,
              "18",
            ),
            task_card(
              "T-239", "硬件", "DVT 热循环测试", "Hardware-01", 54, "32",
            ),
          ],
          false,
        ),
        dispatch_lane(
          "待你验收 · 2",
          "Gate 制 · 人类过闸",
          [
            task_card(
              "T-230", "软件", "v0.8 灰度发布包", "Release-01", 100, "47",
            ),
            task_card(
              "T-236", "运维", "支付服务事故复盘", "Ops-01", 100, "21",
            ),
          ],
          true,
        ),
        dispatch_lane(
          "已交付 · 4",
          "证据归档",
          [
            task_card(
              "T-221", "软件", "授权撤销回归", "Test-01", 100, "63",
            ),
            task_card(
              "T-226", "公司", "税务申报证据核对", "Finance-01", 100, "28",
            ),
          ],
          false,
        ),
      ],
    ],
  ]
}
