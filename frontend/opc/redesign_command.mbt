///|
#cfg(target="js")
extern "js" fn dispatch_command_nonce() -> String =
  #| () => String(Date.now())

///|
#cfg(target="js")
extern "js" fn dispatch_today() -> String =
  #| () => new Date().toISOString().slice(0, 10)

///|
fn dispatch_task_failure_note(action : String) -> String {
  "「\{action}」没有获得正式收据。MoonProj 签名网关、登录身份、PostgreSQL 或项目范围当前不可用或拒绝了命令；上一正式状态保持不变。请从受信任的 MoonProj gateway 打开此界面后重试。"
}

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
fn request_dispatch_task_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = dispatch_command_nonce()
  let idempotency_key = "opc-dispatch-create-" + nonce
  let task_id = "OPC-TASK-" + nonce
  let body = Json::object({
    "idempotency_key": Json::string(idempotency_key),
    "task_id": Json::string(task_id),
    "task_code": Json::string(task_id),
    "task_name": Json::string(model.dispatch_task_title.trim().to_owned()),
    "project_id": Json::string(model.dispatch_task_project_id.trim().to_owned()),
    "task_type": Json::string("task"),
    "plan_begin_date": Json::string(
      model.dispatch_task_begin_date.trim().to_owned(),
    ),
    "plan_end_date": Json::string(
      model.dispatch_task_end_date.trim().to_owned(),
    ),
    "owner_id": Json::string(model.dispatch_task_owner_id.trim().to_owned()),
    "remarks": Json::string(
      "验收标准：" + model.dispatch_task_acceptance.trim().to_owned(),
    ),
    "authority": dispatch_task_authority(model, "project:task:create"),
  }).stringify()
  @http.post("/api/company/plan/tasks")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let persisted_task_id = dispatch_result_text(
          response, "task", "task_id",
        )
        let state = dispatch_result_text(response, "task", "state")
        if persisted_task_id.is_empty() || state != "pending" {
          emit(DispatchTaskCommandFailed("创建任务"))
        } else {
          emit(
            DispatchTaskCreated(
              persisted_task_id,
              dispatch_result_text(response, "task", "event_id"),
              dispatch_result_text(response, "task", "audit_id"),
            ),
          )
        }
      }
      Err(_) => emit(DispatchTaskCommandFailed("创建任务"))
    }
  })
}

///|
fn request_dispatch_task_start(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let idempotency_key = "opc-dispatch-start-" + dispatch_command_nonce()
  let body = Json::object({
    "idempotency_key": Json::string(idempotency_key),
    "status": Json::string("in_progress"),
    "progress_pct": Json::number(0),
    "authority": dispatch_task_authority(model, "project:task:update"),
  }).stringify()
  @http.put("/api/company/plan/tasks/" + model.dispatch_task_id)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) =>
        if dispatch_result_text(response, "task", "state") == "in_progress" {
          emit(
            DispatchTaskStarted(
              dispatch_result_text(response, "task", "event_id"),
              dispatch_result_text(response, "task", "audit_id"),
            ),
          )
        } else {
          emit(DispatchTaskCommandFailed("开始任务"))
        }
      Err(_) => emit(DispatchTaskCommandFailed("开始任务"))
    }
  })
}

///|
fn request_dispatch_task_submit(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = dispatch_command_nonce()
  let report_id = "OPC-REPORT-" + nonce
  let body = Json::object({
    "idempotency_key": Json::string("opc-dispatch-submit-" + nonce),
    "report_id": Json::string(report_id),
    "task_id": Json::string(model.dispatch_task_id),
    "project_id": Json::string(model.dispatch_task_project_id.trim().to_owned()),
    "progress_pct": Json::number(100),
    "report_date": Json::string(dispatch_today()),
    "summary": Json::string(
      "提交验收：" +
      model.dispatch_task_title.trim().to_owned() +
      "；验收标准：" +
      model.dispatch_task_acceptance.trim().to_owned(),
    ),
    "evidence_ids": Json::array([
      Json::string(model.dispatch_task_evidence_id.trim().to_owned()),
    ]),
  }).stringify()
  @http.post("/api/company/plan/tasks/" + model.dispatch_task_id + "/report")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let persisted_report_id = dispatch_result_text(
          response, "task_report", "aggregate_id",
        )
        let state = dispatch_result_text(response, "task_report", "state")
        if persisted_report_id.is_empty() || state != "observed" {
          emit(DispatchTaskCommandFailed("提交验收"))
        } else {
          emit(
            DispatchTaskSubmitted(
              persisted_report_id,
              dispatch_result_text(response, "task_report", "event_id"),
              dispatch_result_text(response, "task_report", "audit_id"),
            ),
          )
        }
      }
      Err(_) => emit(DispatchTaskCommandFailed("提交验收"))
    }
  })
}

///|
fn request_dispatch_task_accept(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let idempotency_key = "opc-dispatch-accept-" + dispatch_command_nonce()
  let body = Json::object({
    "idempotency_key": Json::string(idempotency_key),
    "status": Json::string("done"),
    "progress_pct": Json::number(100),
    "authority": dispatch_task_authority(model, "project:task:update"),
  }).stringify()
  @http.put("/api/company/plan/tasks/" + model.dispatch_task_id)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) =>
        if dispatch_result_text(response, "task", "state") == "done" {
          emit(
            DispatchTaskAccepted(
              dispatch_result_text(response, "task", "event_id"),
              dispatch_result_text(response, "task", "audit_id"),
            ),
          )
        } else {
          emit(DispatchTaskCommandFailed("接受结果"))
        }
      Err(_) => emit(DispatchTaskCommandFailed("接受结果"))
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
fn attention_item(
  emit : @rabbita.Emit[Msg],
  kind : String,
  title : String,
  detail : String,
  source : String,
  ready : Bool,
) -> @html.Html {
  article(class="attention-item") <| [
    div(class="attention-main") <| [
      div(class="attention-title") <| [
        status_badge(kind, tone=if ready { "accent" } else { "warning" }),
        strong(title),
      ],
      p(detail),
      small(
        if ready {
          "来自 \{source} · 证据齐全 · 可裁决"
        } else {
          "来自 \{source} · 证据不足 · fail-closed 拦截"
        },
      ),
    ],
    div(class="attention-actions") <| [
      button(
        type_="button",
        class=if ready {
          "button button-primary button-small"
        } else {
          "button button-disabled button-small"
        },
        disabled=!ready,
        on_click=emit(RecordDecision("裁决：\{title}")),
        "裁决",
      ),
      secondary_button(
        emit,
        RecordDecision("委派补证：\{title}"),
        "委派",
      ),
    ],
  ]
}

///|
fn cockpit_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page command-page") <| [
    page_intro(Overview, status_badge("5 项待决", tone="warning")),
    div(class="kpi-grid") <| [
      compact_kpi(
        "现金跑道", "14.2 月", "余额 ¥85.2万 · 月耗 ¥6.0万", "ok",
      ),
      compact_kpi("Agent 编队", "9 运行", "2 个等待人类输入", "info"),
      compact_kpi("今日待决", "5", "只处理需要 Owner 的事", "warn"),
      compact_kpi(
        "出厂质检", "A×2 · B×4 · C×2", "2 个产品存在红线风险",
        "violet",
      ),
    ],
    div(class="cockpit-grid") <| [
      section(class="attention-column") <| [
        section_title(
          "注意力队列", "系统替你过滤；这里只出现必须由人承担的决定。",
          "5 待决",
        ),
        attention_item(
          emit, "Gate", "批准 v0.8.0 灰度发布", "G4/G6 证据齐全，回滚演练记录已归档。",
          "Release-01", true,
        ),
        attention_item(
          emit, "预算", "采购推理额度 ¥8,000", "缺少三家报价与预算归属，系统禁止批准。",
          "Finance-01", false,
        ),
        attention_item(
          emit, "升级", "生产告警连续三次自愈失败", "超出 L3 自治边界，需要决定降级或回滚。",
          "Sentinel-01", true,
        ),
        attention_item(
          emit, "审批", "年度服务合同续签", "法务差异已标记，现金影响在月度预算内。",
          "Company-01", true,
        ),
      ],
      section(class="loop-column") <| [
        section_title(
          "三环健康", "开发、监测、运维；治理轴贯穿全部动作。",
          "",
        ),
        article(class="loop-card") <| [
          div(class="loop-head") <| [
            strong("开发环"),
            strong("84"),
          ],
          meter(84, "violet"),
          p("需求 → 设计 → 开发 → 测试 → 发布"),
          secondary_button(emit, Navigate(Dispatch), "查看待验收 2"),
        ],
        article(class="loop-card") <| [
          div(class="loop-head") <| [
            strong("监测环"),
            strong("91"),
          ],
          meter(91, "info"),
          p("3/4 SLO 健康 · 错误预算消耗 34%"),
          secondary_button(emit, Navigate(Observe), "查看监测"),
        ],
        article(class="loop-card") <| [
          div(class="loop-head") <| [
            strong("运维环"),
            strong("78"),
          ],
          meter(78, "ok"),
          p("1 个复盘未闭环 · 6/9 Runbook 已自动化"),
          secondary_button(emit, Navigate(Operate), "查看运维"),
        ],
        article(class="governance-card") <| [
          div(class="loop-head") <| [
            strong("治理轴"),
            status_badge("fail-closed", tone="accent"),
          ],
          div(class="mini-stats") <| [
            div <| [
              strong("312"),
              small("授权放行"),
            ],
            div <| [
              strong("4"),
              small("越权拦截"),
            ],
            div <| [
              strong("47"),
              small("今日抽检"),
            ],
          ],
        ],
      ],
    ],
  ]
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
    page_intro(Fleet, status_badge("12 个在编", tone="accent")),
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
    "accepted" => "已接受"
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
) -> @html.Html {
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(id), label_text),
    input(
      input_type=Text,
      attrs=@html.Attrs::build().id(id),
      value~,
      placeholder~,
      on_input~,
    ),
  ]
}

///|
fn dispatch_task_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  form(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("创建正式编排任务"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("创建可追溯任务"),
        p(
          "任务先写入 MoonProj，再由签名身份逐步启动、提交与接受。",
        ),
      ],
      status_badge("PostgreSQL 命令边界", tone="accent"),
    ],
    div(class="form-grid") <| [
      dispatch_task_input(
        "dispatch-task-title",
        "任务名称",
        model.dispatch_task_title,
        "需要交付的结果",
        emit.map(value => InputDispatchTaskTitle(value)),
      ),
      dispatch_task_input(
        "dispatch-task-acceptance",
        "验收标准",
        model.dispatch_task_acceptance,
        "如何判断结果可以接受？",
        emit.map(value => InputDispatchTaskAcceptance(value)),
      ),
      dispatch_task_input(
        "dispatch-task-project",
        "项目 ID",
        model.dispatch_task_project_id,
        "已导入项目，例如 proj-0001",
        emit.map(value => InputDispatchTaskProjectId(value)),
      ),
      dispatch_task_input(
        "dispatch-task-actor",
        "签名身份",
        model.dispatch_task_actor_id,
        "必须与网关登录身份一致",
        emit.map(value => InputDispatchTaskActorId(value)),
      ),
      dispatch_task_input(
        "dispatch-task-owner",
        "负责人 ID（可选）",
        model.dispatch_task_owner_id,
        "授权范围内的负责人",
        emit.map(value => InputDispatchTaskOwnerId(value)),
      ),
      dispatch_task_input(
        "dispatch-task-begin",
        "计划开始",
        model.dispatch_task_begin_date,
        "YYYY-MM-DD",
        emit.map(value => InputDispatchTaskBeginDate(value)),
      ),
      dispatch_task_input(
        "dispatch-task-end",
        "计划完成",
        model.dispatch_task_end_date,
        "YYYY-MM-DD",
        emit.map(value => InputDispatchTaskEndDate(value)),
      ),
    ],
    div(class="form-actions") <| [
      primary_button(emit, CreateDispatchTask, "写入正式任务"),
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
        primary_button(emit, StartDispatchTask, "Start · 开始执行")
      "in_progress" =>
        div(class="inline-form") <| [
          dispatch_task_input(
            "dispatch-task-evidence",
            "证据 ID / 可追溯引用",
            model.dispatch_task_evidence_id,
            "真实制品、提交、报告或证据账本引用",
            emit.map(value => InputDispatchTaskEvidenceId(value)),
          ),
          primary_button(emit, SubmitDispatchTask, "Submit · 提交验收"),
        ]
      "submitted" =>
        primary_button(emit, AcceptDispatchTask, "Accept · 接受结果")
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
  article(class="work-card") <| [
    div(class="loop-head") <| [
      strong(model.dispatch_task_title),
      status_badge(
        dispatch_task_stage_label(model.dispatch_task_stage),
        tone=dispatch_task_stage_tone(model.dispatch_task_stage),
      ),
    ],
    p("验收标准 · \{model.dispatch_task_acceptance}"),
    div(class="work-meta") <| [
      span("任务 · \{model.dispatch_task_id}"),
      span("项目 · \{model.dispatch_task_project_id}"),
      span(
        if model.dispatch_task_owner_id.is_empty() {
          "负责人 · 未指定"
        } else {
          "负责人 · \{model.dispatch_task_owner_id}"
        },
      ),
    ],
    if model.dispatch_task_report_id.is_empty() {
      @html.nothing
    } else {
      small("任务报告 · \{model.dispatch_task_report_id}")
    },
    dispatch_task_receipts(model),
    dispatch_task_action(emit, model),
  ]
}

///|
fn dispatch_durable_lane(
  title : String,
  active : Bool,
  content : @html.Html,
) -> @html.Html {
  article(class="work-lane") <| [
    div(class="lane-heading") <| [
      strong(title),
      span(if active { "1" } else { "0" }),
    ],
    if active {
      content
    } else {
      div(class="lane-empty", "没有任务")
    },
  ]
}

///|
fn dispatch_durable_board(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let card = dispatch_durable_task_card(emit, model)
  div(class="work-board") <| [
    dispatch_durable_lane(
      "可启动",
      model.dispatch_task_stage == "pending",
      card,
    ),
    dispatch_durable_lane(
      "执行中",
      model.dispatch_task_stage == "in_progress",
      card,
    ),
    dispatch_durable_lane(
      "待验收",
      model.dispatch_task_stage == "submitted",
      card,
    ),
    dispatch_durable_lane(
      "已接受",
      model.dispatch_task_stage == "accepted",
      card,
    ),
  ]
}

///|
fn dispatch_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Dispatch,
      if model.dispatch_task_id.is_empty() {
        primary_button(emit, OpenDispatchTaskForm, "创建任务")
      } else {
        status_badge(
          dispatch_task_stage_label(model.dispatch_task_stage),
          tone=dispatch_task_stage_tone(model.dispatch_task_stage),
        )
      },
    ),
    div(class="extension-boundary") <| [
      strong("正式边界 · plan task + evidence-gated report"),
      p(
        "Create 与 Start/Accept 使用 `/api/company/plan/tasks` 权限命令；Submit 使用 `/api/company/plan/tasks/:id/report`。只有后端返回 event/audit receipt，界面才推进状态。",
      ),
    ],
    if model.dispatch_task_form_open {
      dispatch_task_form(emit, model)
    } else {
      @html.nothing
    },
    if model.dispatch_task_blocked {
      div(class="extension-boundary") <| [
        status_badge("安全阻断", tone="warning"),
        p(model.dispatch_task_note),
      ]
    } else {
      p(class="boundary-note", model.dispatch_task_note)
    },
    section(class="section-block") <| [
      section_title(
        "当前正式任务",
        "Start → Submit → Accept；每一步都等待同一持久化边界的收据。",
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
            "点击“创建任务”填写验收标准；网关不可用时会明确阻断，不会生成浏览器假记录。",
          ),
        ]
      } else {
        dispatch_durable_board(emit, model)
      },
    ],
    section_title(
      "编排参考投影", "以下卡片是界面布局样例，不是当前 PostgreSQL 任务或执行事实。",
      "只读样例",
    ),
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
  ]
}
