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
    "submitted" | "running" =>
      status_badge("生产与独立复核中", tone="violet")
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
#cfg(target="js")
extern "js" fn product_in_gate_nonce() -> String =
  #| () => String(Date.now())

///|
#cfg(target="js")
extern "js" fn product_in_gate_today() -> String =
  #| () => new Date().toISOString().slice(0, 10)

///|
fn product_in_gate_refs(value : String) -> Array[Json] {
  let result : Array[Json] = []
  for item in value.split(";") {
    let trimmed = item.trim().to_owned()
    if !trimmed.is_empty() {
      result.push(Json::string(trimmed))
    }
  }
  result
}

///|
fn product_in_gate_root(value : Json) -> Json {
  match value {
    Object(root) => root.get("product_in_gate").unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn product_in_gate_response_text(
  value : Json,
  key : String,
  fallback : String,
) -> String {
  projection_item_text(product_in_gate_root(value), key, fallback)
}

///|
fn product_in_gate_response_refs(value : Json, key : String) -> String {
  match product_in_gate_root(value) {
    Object(fields) =>
      match fields.get(key) {
        Some(Array(values)) =>
          values
          .filter_map(value => {
            match value {
              String(text) => Some(text)
              _ => None
            }
          })
          .join("; ")
        _ => ""
      }
    _ => ""
  }
}

///|
fn product_in_gate_response_persisted(value : Json) -> Bool {
  match product_in_gate_root(value) {
    Object(fields) => fields.get("persisted") is Some(True)
    _ => false
  }
}

///|
fn load_product_in_gate(emit : @rabbita.Emit[Msg], project : String) -> Cmd {
  @http.get("/api/company/products/" + project + "/in-gate").expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        emit(
          ProductInGateLoaded(
            project,
            product_in_gate_response_text(payload, "decision", "unknown"),
            product_in_gate_response_text(payload, "primary_value", "unknown"),
            product_in_gate_response_text(payload, "segment", ""),
            product_in_gate_response_text(payload, "workflow", ""),
            product_in_gate_response_refs(payload, "problem_evidence"),
            product_in_gate_response_refs(payload, "commitment_evidence"),
            product_in_gate_response_text(payload, "current_behavior_cost", ""),
            product_in_gate_response_text(payload, "outcome_metric", ""),
            product_in_gate_response_text(payload, "adoption_path", ""),
            product_in_gate_response_text(payload, "unresolved_risks", ""),
            product_in_gate_response_text(payload, "next_experiment", ""),
            product_in_gate_response_text(payload, "review_by", ""),
            product_in_gate_response_text(payload, "owner", ""),
            product_in_gate_response_persisted(payload),
          ),
        )
      }
      Err(_) => emit(ProductInGateFailed(project))
    }
  })
}

///|
fn request_product_in_gate_mark(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let project = engineering_project_name(model.engineering_project)
  let body = Json::object({
    "idempotency_key": Json::string(
      "product-in-gate-" + project + "-" + product_in_gate_nonce(),
    ),
    "decision": Json::string(model.product_in_gate_decision),
    "primary_value": Json::string(model.product_in_gate_primary_value),
    "segment": Json::string(model.product_in_gate_segment.trim().to_owned()),
    "workflow": Json::string(model.product_in_gate_workflow.trim().to_owned()),
    "decided_at": Json::string(product_in_gate_today()),
    "problem_evidence": Json::array(
      product_in_gate_refs(model.product_in_gate_problem_evidence),
    ),
    "commitment_evidence": Json::array(
      product_in_gate_refs(model.product_in_gate_commitment_evidence),
    ),
    "current_behavior_cost": Json::string(
      model.product_in_gate_current_behavior_cost.trim().to_owned(),
    ),
    "outcome_metric": Json::string(
      model.product_in_gate_outcome_metric.trim().to_owned(),
    ),
    "adoption_path": Json::string(
      model.product_in_gate_adoption_path.trim().to_owned(),
    ),
    "unresolved_risks": Json::string(
      model.product_in_gate_unresolved_risks.trim().to_owned(),
    ),
    "next_experiment": Json::string(
      model.product_in_gate_next_experiment.trim().to_owned(),
    ),
    "review_by": Json::string(model.product_in_gate_review_by.trim().to_owned()),
  }).stringify()
  @http.put("/api/company/products/" + project + "/in-gate")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        if product_in_gate_response_text(payload, "decision", "").is_empty() {
          emit(ProductInGateFailed(project))
        } else {
          emit(ProductInGateSaved(project))
        }
      }
      Err(_) => emit(ProductInGateFailed(project))
    }
  })
}

///|
fn product_in_gate_choice(
  emit : @rabbita.Emit[Msg],
  selected : String,
  value : String,
  label : String,
  decision : Bool,
) -> @html.Html {
  button(
    type_="button",
    class=if selected == value {
      "button button-primary button-small"
    } else {
      "button button-secondary button-small"
    },
    on_click=if decision {
      emit(SelectProductInGateDecision(value))
    } else {
      emit(SelectProductInGatePrimaryValue(value))
    },
    label,
  )
}

///|
fn product_in_gate_input(
  id : String,
  title : String,
  value : String,
  placeholder : String,
  on_input : @rabbita.Emit[String],
) -> @html.Html {
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(id), title),
    input(
      input_type=Text,
      attrs=@html.Attrs::build().id(id).required(true),
      value~,
      placeholder~,
      on_input~,
    ),
  ]
}

///|
fn product_in_gate_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
  selected : String,
) -> @html.Html {
  section(class="section-block release-candidate") <| [
    div(class="form-heading") <| [
      div <| [
        h3("产品 In-Gate · 采用标记"),
        p(
          "持久化用户需求、承诺与重复使用判断。这不是 G0，不改变出厂 G1-G9。",
        ),
      ],
      status_badge(
        model.product_in_gate_decision,
        tone=if model.product_in_gate_decision == "pass" {
          "success"
        } else if model.product_in_gate_decision == "experiment" {
          "warning"
        } else {
          "muted"
        },
      ),
    ],
    p(
      selected +
      (if model.product_in_gate_persisted {
        " · PostgreSQL 已持久化 · Owner " + model.product_in_gate_owner
      } else {
        " · 尚未持久化"
      }),
    ),
    strong("决策"),
    div(class="tag-row") <| [
      product_in_gate_choice(
        emit,
        model.product_in_gate_decision,
        "experiment",
        "实验",
        true,
      ),
      product_in_gate_choice(
        emit,
        model.product_in_gate_decision,
        "pass",
        "通过",
        true,
      ),
      product_in_gate_choice(
        emit,
        model.product_in_gate_decision,
        "park",
        "暂存",
        true,
      ),
    ],
    strong("主要价值假设"),
    div(class="tag-row") <| [
      product_in_gate_choice(
        emit,
        model.product_in_gate_primary_value,
        "solution",
        "解决方案",
        false,
      ),
      product_in_gate_choice(
        emit,
        model.product_in_gate_primary_value,
        "convenience",
        "便利",
        false,
      ),
      product_in_gate_choice(
        emit,
        model.product_in_gate_primary_value,
        "experience",
        "体验",
        false,
      ),
    ],
    div(class="form-grid") <| [
      product_in_gate_input(
        "in-gate-segment",
        "目标用户 / 买家",
        model.product_in_gate_segment,
        "一个可触达的细分用户群",
        emit.map(value => InputProductInGateSegment(value)),
      ),
      product_in_gate_input(
        "in-gate-workflow",
        "使用情境 / 重复工作流",
        model.product_in_gate_workflow,
        "触发、频率与用户会重复完成的工作",
        emit.map(value => InputProductInGateWorkflow(value)),
      ),
      product_in_gate_input(
        "in-gate-problem-evidence",
        "问题证据收据",
        model.product_in_gate_problem_evidence,
        "receipt-1; receipt-2; receipt-3",
        emit.map(value => InputProductInGateProblemEvidence(value)),
      ),
      product_in_gate_input(
        "in-gate-commitment-evidence",
        "承诺证据收据",
        model.product_in_gate_commitment_evidence,
        "level4:pilot-a; level4:pilot-b 或 level5:payment-1",
        emit.map(value => InputProductInGateCommitmentEvidence(value)),
      ),
      product_in_gate_input(
        "in-gate-current-behavior-cost",
        "当前做法与成本",
        model.product_in_gate_current_behavior_cost,
        "当前替代做法及其时间、金钱、延误或风险成本",
        emit.map(value => InputProductInGateCurrentBehaviorCost(value)),
      ),
      product_in_gate_input(
        "in-gate-outcome",
        "可测量结果",
        model.product_in_gate_outcome_metric,
        "基线、目标与时间窗口",
        emit.map(value => InputProductInGateOutcomeMetric(value)),
      ),
      product_in_gate_input(
        "in-gate-adoption",
        "采用路径",
        model.product_in_gate_adoption_path,
        "引入、配置、激活和重复使用责任人",
        emit.map(value => InputProductInGateAdoptionPath(value)),
      ),
      product_in_gate_input(
        "in-gate-risks",
        "未解决风险",
        model.product_in_gate_unresolved_risks,
        "仍需证伪的风险；没有则明确填写 none recorded",
        emit.map(value => InputProductInGateUnresolvedRisks(value)),
      ),
      product_in_gate_input(
        "in-gate-next-experiment",
        "下一个实验 / 暂存条件",
        model.product_in_gate_next_experiment,
        "下一个可证伪步骤",
        emit.map(value => InputProductInGateNextExperiment(value)),
      ),
      product_in_gate_input(
        "in-gate-review-by",
        "复核日期",
        model.product_in_gate_review_by,
        "YYYY-MM-DD，须在决策后 90 天内",
        emit.map(value => InputProductInGateReviewBy(value)),
      ),
    ],
    primary_button(emit, SaveProductInGate, "持久化 Product In-Gate 标记"),
  ]
}

///|
fn request_engineering_audit(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let project = engineering_project_name(model.engineering_project)
  let body = Json::object({
    "project": Json::string(project),
    "branch": Json::string(model.engineering_branch),
    "version": Json::string(model.engineering_version),
    "tag": Json::string(model.engineering_tag),
  }).stringify()
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
fn projection_gate_states(value : Json) -> Array[String] {
  let result : Array[String] = []
  match value {
    Object(root) =>
      match root.get("audit") {
        Some(Object(audit)) =>
          match audit.get("gates") {
            Some(Array(gates)) =>
              for gate in gates {
                result.push(projection_item_text(gate, "status", "unknown"))
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
  while result.length() < 9 {
    result.push("unknown")
  }
  result
}

///|
fn projection_item_text(
  value : Json,
  key : String,
  fallback : String,
) -> String {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => text
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
            projection_root_text(payload, "repository", "unknown"),
            projection_root_text(payload, "branch", "unknown"),
            projection_root_text(payload, "commit", "unknown"),
            projection_root_text(payload, "review_verdict", "needs_evidence"),
            projection_gate_states(payload),
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
    product_in_gate_panel(emit, model, selected),
    div(class="repo-grid") <| [
      evidence_dimension(
        "走了多远",
        "由同一证据账本中连续通过的 G1-G9 推导，不另建进度评分。",
        "moonsuite.engineering-evidence.v2 / progress projection",
        model.engineering_progress,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "走得多好",
        "由精确 commit 的 Gate 收据、失败、阻断与未知推导。",
        "moonsuite.engineering-evidence.v2 / health projection",
        model.engineering_health,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "能否生产",
        "R1-R3 与 G1-G9 共用同一批收据；全通过也只进入 Owner 授权。",
        "moonsuite.engineering-evidence.v2 / production projection",
        model.engineering_production,
        model.engineering_freshness,
      ),
    ],
    div(class="extension-boundary") <| [
      div <| [
        strong("\{selected} · 审计编排"),
        p(
          "一次候选测试 → 一份 G1-G9 账本 → 独立 Reviewer 抽验 → 三个投影；producer 与 reviewer 不得相同。",
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
    primary_button(emit, Navigate(Quality), "配置并测试发布候选"),
    if model.engineering_findings > 0 && model.engineering_freshness == "fresh" {
      secondary_button(
        emit,
        RequestEngineeringRemediation,
        "从已接受发现创建整改",
      )
    } else {
      @html.nothing
    },
    secondary_button(emit, Navigate(Quality), "打开统一九 Gate 控制台"),
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
fn engineering_gate_label(index : Int) -> String {
  match index {
    0 => "G1 目标、需求与候选身份"
    1 => "G2 功能完整与验收路径"
    2 => "G3 UI、无障碍与使用指南"
    3 => "G4 构建、测试与工程质量"
    4 => "G5 集成、持久化与数据一致性"
    5 => "G6 安全、合规与秘密扫描"
    6 => "G7 产物、兼容性与打包"
    7 => "G8 安装、运行、回滚与恢复"
    _ => "G9 Git、Tag、校验和与发布控制"
  }
}

///|
fn engineering_gate_state(model : Model, index : Int) -> String {
  if index < model.engineering_gate_states.length() {
    model.engineering_gate_states[index]
  } else {
    "unknown"
  }
}

///|
fn engineering_gate_row(model : Model, index : Int) -> @html.Html {
  let state = engineering_gate_state(model, index)
  div(class="release-gate-row") <| [
    span(class="release-gate-index", "G" + (index + 1).to_string()),
    div <| [
      strong(engineering_gate_label(index)),
      small(
        if state == "unknown" {
          "没有被独立复核的收据"
        } else {
          "来自同一候选证据账本"
        },
      ),
    ],
    status_badge(
      if state == "unknown" {
        "未知"
      } else {
        state
      },
      tone=if state == "pass" {
        "success"
      } else if state == "fail" || state == "blocked" {
        "warning"
      } else {
        "muted"
      },
    ),
  ]
}

///|
fn quality_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let selected = quality_product_name(model, model.engineering_project)
  section(class="page") <| [
    page_intro(Quality, audit_state_badge(model)),
    section_title(
      "这个精确候选可以发布吗？",
      "九个 Gate、三个维度和发布演练共用同一份 commit 级证据账本。",
      if model.engineering_production == "ready_for_owner_authorization" {
        "等待 Owner 授权"
      } else {
        "不得发布"
      },
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
    section(class="section-block release-candidate") <| [
      div(class="form-heading") <| [
        div <| [
          h3("\{selected} · 发布候选"),
          p(
            "提交只启动只读演练；不会创建 tag、push 或 GitHub Release。",
          ),
        ],
        status_badge(
          model.engineering_review,
          tone=if model.engineering_review == "accept" {
            "success"
          } else {
            "muted"
          },
        ),
      ],
      div(class="form-grid release-form-grid") <| [
        div(class="field") <| [
          label(attrs=@html.Attrs::build().for_("release-branch"), "Branch"),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("release-branch").required(true),
            value=model.engineering_branch,
            placeholder="main",
            on_input=emit.map(value => InputEngineeringBranch(value)),
          ),
        ],
        div(class="field") <| [
          label(attrs=@html.Attrs::build().for_("release-version"), "Version"),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("release-version").required(true),
            value=model.engineering_version,
            placeholder="0.1.0",
            on_input=emit.map(value => InputEngineeringVersion(value)),
          ),
        ],
        div(class="field") <| [
          label(attrs=@html.Attrs::build().for_("release-tag"), "Proposed tag"),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("release-tag").required(true),
            value=model.engineering_tag,
            placeholder="v0.1.0",
            on_input=emit.map(value => InputEngineeringTag(value)),
          ),
        ],
      ],
      div(class="candidate-identity") <| [
        span("Repository · \{model.engineering_repository}"),
        span("Commit · \{model.engineering_commit}"),
      ],
      primary_button(
        emit,
        RequestEngineeringAudit,
        "让 MoonClaw 测试这个候选",
      ),
    ],
    div(class="repo-grid release-dimensions") <| [
      evidence_dimension(
        "走了多远",
        "由连续通过的 Gate 推导，不另做进度评分。",
        "same-ledger/G1-G9",
        model.engineering_progress,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "走得多好",
        "由同一 Gate 的失败、阻断和未知推导。",
        "same-ledger/receipts",
        model.engineering_health,
        model.engineering_freshness,
      ),
      evidence_dimension(
        "能否生产",
        "R1-R3 与 G1-G9 全部有证据后才可请求 Owner 授权。",
        "same-ledger/release",
        model.engineering_production,
        model.engineering_freshness,
      ),
    ],
    section(class="section-block") <| [
      section_title(
        "统一九 Gate 证据账本",
        "每一行都属于上面的精确候选；缺证据就是未知。",
        "\{model.engineering_findings} 个已复核问题",
      ),
      div(class="release-gate-list") <| [
        engineering_gate_row(model, 0),
        engineering_gate_row(model, 1),
        engineering_gate_row(model, 2),
        engineering_gate_row(model, 3),
        engineering_gate_row(model, 4),
        engineering_gate_row(model, 5),
        engineering_gate_row(model, 6),
        engineering_gate_row(model, 7),
        engineering_gate_row(model, 8),
      ],
    ],
    div(class="extension-boundary release-authority") <| [
      div <| [
        strong("发布权仍属于 Owner"),
        p(
          if model.engineering_production == "ready_for_owner_authorization" {
            "证据允许请求授权，但 MoonProj 尚未执行发布。"
          } else {
            "当前候选未满足授权条件；MoonProj 不提供绕过入口。"
          },
        ),
      ],
      status_badge(
        if model.engineering_production == "ready_for_owner_authorization" {
          "可请求授权"
        } else {
          "锁定"
        },
        tone=if model.engineering_production == "ready_for_owner_authorization" {
          "success"
        } else {
          "warning"
        },
      ),
    ],
  ]
}
