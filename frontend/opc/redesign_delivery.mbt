///|
fn project_row(
  name : String,
  kind : String,
  stage : String,
  gate : String,
  health : String,
  owner : String,
) -> @html.Html {
  tr <| [
    td <| [
      strong(name),
      small(kind),
    ],
    td(stage),
    td(gate),
    td <| [
      status_badge(
        health,
        tone=if health == "健康" { "accent" } else { "warning" },
      ),
    ],
    td(owner),
  ]
}

///|
fn projects_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Projects,
      primary_button(emit, RecordDecision("建立项目"), "建立项目"),
    ),
    div(class="stage-legend") <| [
      strong("软件六阶段"),
      span("需求 → 设计 → 开发 → 测试 → 灰度 → 全量"),
      strong("硬件六阶段"),
      span("概念 → EVT → DVT → PVT → 小批 → 量产"),
    ],
    section(class="section-block") <| [
      section_title(
        "项目组合", "阶段由 Agent 推进，Gate 只能由证据和授权放行。",
        "1 项阻塞",
      ),
      div(class="table-scroll") <| [
        table(class="data-table portfolio-table") <| [
          thead <| [
            tr <| [
              th("项目"),
              th("当前阶段"),
              th("下一 Gate"),
              th("健康"),
              th("责任 Agent"),
            ],
          ],
          tbody <| [
            project_row(
              "OPC Core v0.9", "软件", "测试 · 82%", "G4 工程化", "健康",
              "Builder-02",
            ),
            project_row(
              "Agent Evidence Bus", "软件", "开发 · 61%", "G2 功能完整",
              "有风险", "Architect-01",
            ),
            project_row(
              "Edge Node MkII", "硬件", "DVT · 48%", "DVT 热循环", "阻塞",
              "Hardware-01",
            ),
            project_row(
              "Company Control Pack", "扩展包", "灰度 · 90%", "G6 合规",
              "健康", "Finance-01",
            ),
          ],
        ],
      ],
    ],
  ]
}

///|
fn engineering_project_name(index : Int) -> String {
  match index {
    0 => "moonproj"
    1 => "moonclaw"
    2 => "moonbook"
    3 => "moontown"
    4 => "moondesk"
    5 => "moongate"
    6 => "moonrobo"
    7 => "moonmoon"
    _ => "moonfish"
  }
}

///|
fn audit_state_badge(model : Model) -> @html.Html {
  match model.engineering_audit_state {
    "submitting" => status_badge("提交中", tone="warning")
    "submitted" | "running" => status_badge("MoonClaw 执行中", tone="violet")
    "awaiting_artifact" => status_badge("等待证据文件", tone="warning")
    "ingested" | "ready" => status_badge("证据已复核", tone="success")
    "failed" => status_badge("连接失败", tone="warning")
    _ => status_badge("尚未审计", tone="muted")
  }
}

///|
fn evidence_dimension(
  title : String,
  question : String,
  contract : String,
  result : String,
  freshness : String,
) -> @html.Html {
  article(class="repo-card") <| [
    div(class="loop-head") <| [
      strong(title),
      status_badge(
        if result == "unknown" {
          "未知"
        } else {
          result
        },
        tone=if freshness != "fresh" {
          "muted"
        } else if result == "pass" || result == "eligible" {
          "success"
        } else if result == "fail" || result == "ineligible" {
          "warning"
        } else {
          "muted"
        },
      ),
    ],
    p(question),
    div(class="budget-row") <| [
      span(
        if freshness == "fresh" {
          "独立复核证据"
        } else if freshness == "stale" {
          "历史证据已过期"
        } else {
          "等待 MoonClaw 证据"
        },
      ),
      span(
        if freshness == "fresh" {
          "PostgreSQL 已接收"
        } else {
          "不得推测"
        },
      ),
    ],
    small(contract),
  ]
}

///|
fn engineering_project_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
  index : Int,
  name : String,
) -> @html.Html {
  button(
    type_="button",
    class=if model.engineering_project == index {
      "button button-primary button-small"
    } else {
      "button button-secondary button-small"
    },
    on_click=emit(SelectEngineeringProject(index)),
    name,
  )
}

///|
fn request_engineering_audit(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let project = engineering_project_name(model.engineering_project)
  let body = Json::object({ "project": Json::string(project) }).stringify()
  @http.post("/api/moonsuite/engineering/audits")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        let task_id : String? = match payload {
          Object(fields) =>
            match fields.get("task_id") {
              Some(String(value)) if !value.is_empty() => Some(value)
              _ => None
            }
          _ => None
        }
        let audit_id : String? = match payload {
          Object(fields) =>
            match fields.get("audit_id") {
              Some(String(value)) if !value.is_empty() => Some(value)
              _ => None
            }
          _ => None
        }
        match (audit_id, task_id) {
          (Some(audit), Some(task)) =>
            emit(EngineeringAuditSubmitted(audit, task))
          _ => emit(EngineeringAuditFailed)
        }
      }
      Err(_) => emit(EngineeringAuditStatus(project, "failed"))
    }
  })
}

///|
fn poll_engineering_audit(
  emit : @rabbita.Emit[Msg],
  project : String,
  audit_id : String,
  task_id : String,
) -> Cmd {
  @http.get(
    "/api/moonsuite/engineering/audits/" +
    audit_id +
    "?project=" +
    project +
    "&task_id=" +
    task_id,
  ).expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        let state = match payload {
          Object(fields) =>
            match fields.get("state") {
              Some(String(value)) => value
              _ => "failed"
            }
          _ => "failed"
        }
        emit(EngineeringAuditStatus(project, state))
      }
      Err(_) => emit(EngineeringAuditStatus(project, "failed"))
    }
  })
}

///|
fn projection_text(value : Json, section : String, key : String) -> String {
  match value {
    Object(root) =>
      match root.get("audit") {
        Some(Object(audit)) =>
          match audit.get(section) {
            Some(Object(fields)) =>
              match fields.get(key) {
                Some(String(text)) => text
                _ => "unknown"
              }
            _ => "unknown"
          }
        _ => "unknown"
      }
    _ => "unknown"
  }
}

///|
fn projection_root_text(
  value : Json,
  key : String,
  fallback : String,
) -> String {
  match value {
    Object(root) =>
      match root.get("audit") {
        Some(Object(audit)) =>
          match audit.get(key) {
            Some(String(text)) => text
            _ => fallback
          }
        _ => fallback
      }
    _ => fallback
  }
}

///|
fn load_engineering_projection(
  emit : @rabbita.Emit[Msg],
  project : String,
) -> Cmd {
  @http.get("/api/company/engineering/projects/" + project).expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        let freshness = match payload {
          Object(root) =>
            match root.get("audit") {
              Some(Object(audit)) =>
                match audit.get("freshness") {
                  Some(String(value)) => value
                  _ => "missing"
                }
              _ => "missing"
            }
          _ => "missing"
        }
        let findings = match payload {
          Object(root) =>
            match root.get("audit") {
              Some(Object(audit)) =>
                match audit.get("accepted_findings") {
                  Some(Array(values)) => values.length()
                  _ => 0
                }
              _ => 0
            }
          _ => 0
        }
        emit(
          EngineeringProjectionLoaded(
            project,
            projection_text(payload, "progress", "stage"),
            projection_text(payload, "health", "status"),
            projection_text(payload, "production", "release_eligibility"),
            freshness,
            projection_root_text(payload, "audit_id", ""),
            findings,
          ),
        )
      }
      Err(_) => emit(EngineeringAuditStatus(project, "failed"))
    }
  })
}

///|
fn request_engineering_remediation(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let project = engineering_project_name(model.engineering_project)
  let key = "rabbita-remediation-" + project + "-" + model.engineering_audit_id
  @http.post("/api/company/engineering/projects/" + project + "/remediations")
  .with_text(Json::object({ "idempotency_key": key }).stringify())
  .expect_text(result => {
    match result {
      Ok(_) => emit(EngineeringRemediationCreated)
      Err(_) => emit(EngineeringAuditFailed)
    }
  })
}

///|
fn moon_suite_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let selected = engineering_project_name(model.engineering_project)
  section(class="page") <| [
    page_intro(MoonSuite, audit_state_badge(model)),
    div(class="extension-boundary") <| [
      strong("Moon Suite 工程控制面"),
      p(
        "MoonProj 组织工程事实，MoonClaw Agent 采集与复核证据。界面不自行打分；未知、失败和不适用是不同结论。",
      ),
    ],
    section_title(
      "选择首批服务", "从我们的 Moon Suite 仓库开始建立工程基线。",
      "9 个已登记",
    ),
    div(class="tag-row") <| [
      engineering_project_button(emit, model, 0, "moonproj"),
      engineering_project_button(emit, model, 1, "moonclaw"),
      engineering_project_button(emit, model, 2, "moonbook"),
      engineering_project_button(emit, model, 3, "moontown"),
      engineering_project_button(emit, model, 4, "moondesk"),
      engineering_project_button(emit, model, 5, "moongate"),
      engineering_project_button(emit, model, 6, "moonrobo"),
      engineering_project_button(emit, model, 7, "moonmoon"),
      engineering_project_button(emit, model, 8, "moonfish"),
    ],
    div(class="repo-grid") <| [
      evidence_dimension(
        "走了多远",
        "生命周期、里程碑和已满足 Gate；只有声明了分母才显示百分比。",
        "moonsuite.project-progress-evidence.v1",
        model.engineering_progress,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "走得多好",
        "在精确 commit 上运行仓库自有构建、测试、格式和静态检查。",
        "moonsuite.project-health-evidence.v1",
        model.engineering_health,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "能否生产",
        "先检查三条红线，再逐项验证 G1–G7 和回滚能力。",
        "moonsuite.production-gate-evidence.v1",
        model.engineering_production,
        model.engineering_freshness,
      ),
    ],
    div(class="extension-boundary") <| [
      div <| [
        strong("\{selected} · 审计编排"),
        p(
          "Progress → Health → Production Gate → 独立 Reviewer 抽验；producer 与 reviewer 不得相同。",
        ),
      ],
      audit_state_badge(model),
    ],
    if !model.engineering_task_id.is_empty() {
      p(
        "MoonClaw task: \{model.engineering_task_id} · 尚未收到复核结论",
      )
    } else {
      @html.nothing
    },
    primary_button(emit, RequestEngineeringAudit, "让 MoonClaw 开始审计"),
    if model.engineering_findings > 0 && model.engineering_freshness == "fresh" {
      secondary_button(
        emit,
        RequestEngineeringRemediation,
        "从已接受发现创建整改",
      )
    } else {
      @html.nothing
    },
    secondary_button(emit, Navigate(Quality), "查看生产 Gate 政策"),
  ]
}

///|
fn quality_row(
  emit : @rabbita.Emit[Msg],
  index : Int,
  repo : String,
  scores : String,
  total : String,
  grade : String,
  blocker : String,
  selected : Bool,
) -> @html.Html {
  tr(class=if selected { "is-selected" } else { "" }) <| [
    td <| [
      strong(repo),
    ],
    td(scores),
    td(total),
    td <| [
      status_badge(grade, tone=if grade == "A" { "accent" } else { "warning" }),
    ],
    td(blocker),
    td <| [
      secondary_button(emit, SelectQualityProduct(index), "查看"),
    ],
  ]
}

///|
fn quality_product_name(model : Model, index : Int) -> String {
  if model.moon_mode {
    engineering_project_name(index)
  } else {
    match index {
      0 => "Core Service"
      1 => "Agent Runtime"
      2 => "Investment Pack"
      3 => "Desktop Console"
      4 => "Knowledge Service"
      5 => "Model Gateway"
      6 => "Robotics Runtime"
      7 => "World Model"
      _ => "Goal Orchestrator"
    }
  }
}

///|
fn quality_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let selected = quality_product_name(model, model.quality_product)
  section(class="page") <| [
    page_intro(Quality, status_badge("政策 · 非评分", tone="violet")),
    section_title(
      "3 大红线 · 一票否决", "触发任一红线即冻结，不进入 Gate 评分。",
      "等待证据",
    ),
    div(class="redline-grid") <| [
      article(class="redline-card") <| [
        strong("R1 · 数据泄露风险"),
        status_badge("未知", tone="muted"),
        p("敏感数据、凭据与客户信息不得越界。"),
      ],
      article(class="redline-card has-risk") <| [
        strong("R2 · 合规资质缺失"),
        status_badge("未知", tone="muted"),
        p("资质、许可或申报证据缺失即冻结。"),
      ],
      article(class="redline-card has-risk") <| [
        strong("R3 · 核心流程阻断"),
        status_badge("未知", tone="muted"),
        p("核心路径无法完成或无法回滚即冻结。"),
      ],
    ],
    section_title(
      "全系产品证据状态", "只有 MoonClaw 产出且独立 reviewer 接受的证据才能形成结论。",
      "",
    ),
    div(class="table-scroll panel-table") <| [
      table(class="data-table quality-table") <| [
        thead <| [
          tr <| [
            th("产品"),
            th("G1–G7"),
            th("结论"),
            th("复核"),
            th("证据"),
            th("操作"),
          ],
        ],
        tbody <| [
          quality_row(
            emit,
            0,
            quality_product_name(model, 0),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 0,
          ),
          quality_row(
            emit,
            1,
            quality_product_name(model, 1),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 1,
          ),
          quality_row(
            emit,
            2,
            quality_product_name(model, 2),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 2,
          ),
          quality_row(
            emit,
            3,
            quality_product_name(model, 3),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 3,
          ),
          quality_row(
            emit,
            4,
            quality_product_name(model, 4),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 4,
          ),
          quality_row(
            emit,
            5,
            quality_product_name(model, 5),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 5,
          ),
          quality_row(
            emit,
            6,
            quality_product_name(model, 6),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 6,
          ),
          quality_row(
            emit,
            7,
            quality_product_name(model, 7),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 7,
          ),
          quality_row(
            emit,
            8,
            quality_product_name(model, 8),
            "未知 × 7",
            "未知",
            "未执行",
            "无",
            model.quality_product == 8,
          ),
        ],
      ],
    ],
    div(class="quality-detail-grid") <| [
      section(class="section-block") <| [
        section_title(
          "\{selected} · 7-Gate 评审明细",
          "独立交叉评审；每项结论必须回溯到 commit、命令和收据。",
          "尚无证据",
        ),
        div(class="gate-list") <| [
          div <| [
            span("G1 需求与价值验证"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G2 产品功能完整性"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G3 用户体验与界面"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G4 技术工程化"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G5 数据与运营体系"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G6 安全与合规"),
            meter(0, "ok"),
            strong("未知"),
          ],
          div <| [
            span("G7 发布与运维"),
            meter(0, "ok"),
            strong("未知"),
          ],
        ],
      ],
      section(class="section-block") <| [
        section_title(
          "下一步", "先取得证据，再由 Agent 提出整改；MoonProj 不凭空生成问题。",
          "0 项已证实",
        ),
        ul(class="remediation-list") <| [
          li("选择 Moon Suite 项目并请求审计"),
          li("等待 producer 提交 commit 级证据"),
          li("等待不同 reviewer 复跑关键检查"),
        ],
        primary_button(
          emit,
          Navigate(MoonSuite),
          "返回 Moon Suite 发起审计",
        ),
      ],
    ],
  ]
}
