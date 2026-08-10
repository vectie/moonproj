///|
struct PolicySourceView {
  source_id : String
  name : String
  publisher : String
  format : String
  cadence : String
  url : String
  verification_state : String
  reviewed_by : String
  reviewed_at : String
  audit_id : String
  active : Bool
} derive(Debug, Eq)

///|
struct PolicyChangeView {
  change_id : String
  source_id : String
  impact : String
  title : String
  evidence : String
  location : String
  review_state : String
  reviewed_by : String
  reviewed_at : String
  audit_id : String
  notification_state : String
} derive(Debug, Eq)

///|
struct PolicyOpportunityView {
  opportunity_id : String
  lane : String
  title : String
  why_now : String
  next_validation : String
  gate : String
  source_change_id : String
} derive(Debug, Eq)

///|
struct PolicyRadarProjection {
  freshness : String
  capture_state : String
  sources : Array[PolicySourceView]
  changes : Array[PolicyChangeView]
  opportunities : Array[PolicyOpportunityView]
  review_audit_ids : Array[String]
  boundary : String
} derive(Debug, Eq)

///|
#cfg(target="js")
extern "js" fn policy_nonce() -> String =
  #| () => String(Date.now())

///|
#cfg(target="js")
extern "js" fn policy_today() -> String =
  #| () => new Date().toISOString().slice(0, 10)

///|
#cfg(target="js")
extern "js" fn policy_validation_end_date() -> String =
  #| () => {
  #|   const value = new Date();
  #|   value.setUTCDate(value.getUTCDate() + 14);
  #|   return value.toISOString().slice(0, 10);
  #| }

///|
fn policy_json_text(value : Json, key : String, fallback : String) -> String {
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
fn policy_json_bool(value : Json, key : String, fallback : Bool) -> Bool {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => true
        Some(False) => false
        _ => fallback
      }
    _ => fallback
  }
}

///|
fn policy_json_array(value : Json, key : String) -> Array[Json] {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Array(values)) => values
        _ => []
      }
    _ => []
  }
}

///|
fn policy_source_from_json(value : Json) -> PolicySourceView? {
  let source_id = policy_json_text(value, "source_id", "")
  let name = policy_json_text(value, "name", "")
  if source_id.is_empty() || name.is_empty() {
    return None
  }
  Some({
    source_id,
    name,
    publisher: policy_json_text(value, "publisher", ""),
    format: policy_json_text(value, "format", ""),
    cadence: policy_json_text(value, "cadence", ""),
    url: policy_json_text(value, "url", ""),
    verification_state: policy_json_text(value, "verification_state", "pending"),
    reviewed_by: policy_json_text(value, "reviewed_by", ""),
    reviewed_at: policy_json_text(value, "reviewed_at", ""),
    audit_id: policy_json_text(value, "audit_id", ""),
    active: policy_json_bool(value, "active", false),
  })
}

///|
fn policy_change_from_json(value : Json) -> PolicyChangeView? {
  let change_id = policy_json_text(value, "change_id", "")
  let source_id = policy_json_text(value, "source_id", "")
  if change_id.is_empty() || source_id.is_empty() {
    return None
  }
  Some({
    change_id,
    source_id,
    impact: policy_json_text(value, "impact", "未分类"),
    title: policy_json_text(value, "title", "未命名变化"),
    evidence: policy_json_text(value, "evidence", ""),
    location: policy_json_text(value, "location", ""),
    review_state: policy_json_text(value, "review_state", "pending"),
    reviewed_by: policy_json_text(value, "reviewed_by", ""),
    reviewed_at: policy_json_text(value, "reviewed_at", ""),
    audit_id: policy_json_text(value, "audit_id", ""),
    notification_state: policy_json_text(value, "notification_state", "none"),
  })
}

///|
fn policy_opportunity_from_json(value : Json) -> PolicyOpportunityView? {
  let opportunity_id = policy_json_text(value, "opportunity_id", "")
  if opportunity_id.is_empty() {
    return None
  }
  Some({
    opportunity_id,
    lane: policy_json_text(value, "lane", "B2B+B2G"),
    title: policy_json_text(value, "title", "未命名假设"),
    why_now: policy_json_text(value, "why_now", ""),
    next_validation: policy_json_text(value, "next_validation", ""),
    gate: policy_json_text(value, "gate", "验证未知"),
    source_change_id: policy_json_text(value, "source_change_id", ""),
  })
}

///|
fn policy_projection_from_json(value : Json) -> PolicyRadarProjection? {
  if policy_json_text(value, "schema", "") !=
    "moonproj.policy-radar-projection.v1" {
    return None
  }
  let sources = policy_json_array(value, "sources").filter_map(
    policy_source_from_json,
  )
  let changes = policy_json_array(value, "changes").filter_map(
    policy_change_from_json,
  )
  let opportunities = policy_json_array(value, "opportunities").filter_map(
    policy_opportunity_from_json,
  )
  let review_audit_ids = policy_json_array(value, "review_receipts").filter_map(receipt => {
      let audit_id = policy_json_text(receipt, "audit_id", "")
      if audit_id.is_empty() {
        None
      } else {
        Some(audit_id)
      }
    },
  )
  Some({
    freshness: policy_json_text(value, "freshness", "missing"),
    capture_state: policy_json_text(value, "capture_state", "unknown"),
    sources,
    changes,
    opportunities,
    review_audit_ids,
    boundary: policy_json_text(value, "boundary", ""),
  })
}

///|
fn policy_projection_latest_audit(projection : PolicyRadarProjection) -> String {
  projection.review_audit_ids.get(0).unwrap_or("")
}

///|
fn policy_opportunity_by_id(
  projection : PolicyRadarProjection?,
  opportunity_id : String,
) -> PolicyOpportunityView? {
  match projection {
    Some(value) =>
      for item in value.opportunities {
        if item.opportunity_id == opportunity_id {
          return Some(item)
        }
      }
    None => ()
  }
  None
}

///|
fn policy_source_verified(
  projection : PolicyRadarProjection,
  source_id : String,
) -> Bool {
  projection.sources.any(source => {
    source.source_id == source_id && source.verification_state == "verified"
  })
}

///|
fn policy_change_confirmed(
  projection : PolicyRadarProjection,
  change_id : String,
) -> Bool {
  projection.changes.any(change => {
    change.change_id == change_id && change.review_state == "confirmed"
  })
}

///|
fn policy_opportunity_actionable(
  projection : PolicyRadarProjection?,
  opportunity : PolicyOpportunityView,
) -> Bool {
  match projection {
    Some(value) => policy_change_confirmed(value, opportunity.source_change_id)
    None => false
  }
}

///|
fn load_policy_radar(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/policy/radar").expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        match policy_projection_from_json(payload) {
          Some(projection) => emit(PolicyRadarLoaded(projection))
          None =>
            emit(
              PolicyRadarFailed("服务返回了不兼容的政策投影。"),
            )
        }
      }
      Err(_) =>
        emit(
          PolicyRadarFailed(
            "认证网关或政策投影服务当前不可用。",
          ),
        )
    }
  })
}

///|
fn policy_review_audit_from_response(value : Json) -> String {
  match value {
    Object(root) =>
      match root.get("policy_review") {
        Some(review) => policy_json_text(review, "audit_id", "")
        None => ""
      }
    _ => ""
  }
}

///|
fn request_policy_review(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let target_id = model.policy_review_target_id
  let prefix = if model.policy_review_kind == "source" {
    "/api/company/policy/sources/"
  } else {
    "/api/company/policy/changes/"
  }
  let body = Json::object({
    "idempotency_key": Json::string(
      "policy-" + model.policy_review_kind + "-review-" + policy_nonce(),
    ),
    "decision": Json::string(model.policy_review_decision),
    "evidence": Json::string(model.policy_review_evidence.trim().to_owned()),
    "reviewed_at": Json::string(policy_today()),
  }).stringify()
  @http.post(prefix + target_id + "/reviews")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => {
        let payload = @json.parse(response) catch { _ => Json::null() }
        let audit_id = policy_review_audit_from_response(payload)
        if audit_id.is_empty() {
          emit(PolicyReviewFailed("服务未返回政策复核审计收据。"))
        } else {
          emit(PolicyReviewSaved(target_id, audit_id))
        }
      }
      Err(_) =>
        emit(
          PolicyReviewFailed(
            "复核命令被拒绝。请先核验来源，并确认登录、网关和PostgreSQL可用。",
          ),
        )
    }
  })
}

///|
fn policy_state_label(state : String) -> String {
  match state {
    "verified" => "来源已核验"
    "confirmed" => "解读已确认"
    "rejected" => "已驳回"
    _ => "等待人工复核"
  }
}

///|
fn policy_state_tone(state : String) -> String {
  match state {
    "verified" | "confirmed" => "success"
    "rejected" => "warning"
    _ => "muted"
  }
}

///|
fn policy_source_row(
  emit : @rabbita.Emit[Msg],
  model : Model,
  source : PolicySourceView,
) -> @html.Html {
  tr <| [
    td <| [
      strong(source.name),
      small(source.url),
    ],
    td(source.publisher),
    td(source.format),
    td(source.cadence),
    td <| [
      status_badge(
        policy_state_label(source.verification_state),
        tone=policy_state_tone(source.verification_state),
      ),
      small(
        if source.reviewed_by.is_empty() {
          "未启用监测"
        } else {
          source.reviewed_by + " · " + source.reviewed_at
        },
      ),
    ],
    td <| [
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=model.policy_review_pending,
        on_click=emit(OpenPolicyReview("source", source.source_id, "verified")),
        if source.verification_state == "pending" {
          "核验"
        } else {
          "重审"
        },
      ),
    ],
  ]
}

///|
fn policy_change_item(
  emit : @rabbita.Emit[Msg],
  model : Model,
  projection : PolicyRadarProjection,
  change : PolicyChangeView,
) -> @html.Html {
  let source_verified = policy_source_verified(projection, change.source_id)
  article(class="policy-change-item") <| [
    div(class="policy-change-head") <| [
      status_badge(change.impact, tone="violet"),
      strong(change.title),
      status_badge(
        policy_state_label(change.review_state),
        tone=policy_state_tone(change.review_state),
      ),
    ],
    p(change.evidence),
    small(
      change.location +
      (if source_verified {
        " · 来源已核验"
      } else {
        " · 必须先核验来源"
      }),
    ),
    button(
      type_="button",
      class="button button-secondary button-small",
      disabled=!source_verified || model.policy_review_pending,
      on_click=emit(OpenPolicyReview("change", change.change_id, "confirmed")),
      if change.review_state == "pending" {
        "复核解读"
      } else {
        "重审解读"
      },
    ),
  ]
}

///|
fn policy_review_choice(
  emit : @rabbita.Emit[Msg],
  model : Model,
  value : String,
  label : String,
) -> @html.Html {
  button(
    type_="button",
    class=if model.policy_review_decision == value {
      "button button-primary button-small"
    } else {
      "button button-secondary button-small"
    },
    disabled=model.policy_review_pending,
    on_click=emit(SelectPolicyReviewDecision(value)),
    label,
  )
}

///|
fn policy_review_panel(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.policy_review_target_id.is_empty() {
    return @html.nothing
  }
  section(class="section-block policy-review-form") <| [
    section_title(
      if model.policy_review_kind == "source" {
        "来源核验"
      } else {
        "政策解读复核"
      },
      "结论、具名身份与依据将写入PostgreSQL命令投影和审计记录。",
      "REVIEW RECEIPT",
    ),
    p(class="policy-review-target", model.policy_review_target_id),
    div(class="policy-review-choices") <| [
      policy_review_choice(
        emit,
        model,
        if model.policy_review_kind == "source" {
          "verified"
        } else {
          "confirmed"
        },
        if model.policy_review_kind == "source" {
          "确认来源"
        } else {
          "确认解读"
        },
      ),
      policy_review_choice(emit, model, "rejected", "驳回"),
    ],
    div(class="field") <| [
      label(
        attrs=@html.Attrs::build().for_("policy-review-evidence"),
        "复核依据",
      ),
      input(
        input_type=Text,
        attrs=@html.Attrs::build().id("policy-review-evidence").required(true),
        value=model.policy_review_evidence,
        placeholder="例如：发布主体、规范URL、日期、PDF页码与解释边界",
        on_input=value => emit(InputPolicyReviewEvidence(value)),
      ),
      small("不得只填写“已确认”；必须留下可追溯依据。"),
    ],
    if model.policy_radar_error.is_empty() {
      @html.nothing
    } else {
      p(class="policy-inline-error", model.policy_radar_error)
    },
    div(class="policy-review-actions") <| [
      secondary_button(emit, CancelPolicyReview, "取消"),
      button(
        type_="button",
        class="button button-primary",
        disabled=model.policy_review_pending,
        on_click=emit(SubmitPolicyReview),
        if model.policy_review_pending {
          "写入中…"
        } else {
          "写入复核收据"
        },
      ),
    ],
  ]
}

///|
fn policy_graph_node(
  kind : String,
  label : String,
  state : String,
) -> @html.Html {
  div(class="policy-graph-node") <| [
    small(kind),
    strong(label),
    span(state),
  ]
}

///|
fn policy_loading_view(_emit : @rabbita.Emit[Msg]) -> @html.Html {
  section(class="page policy-radar") <| [
    page_intro(
      PolicyRadar,
      button(
        type_="button",
        class="button button-primary",
        disabled=true,
        "读取中…",
      ),
    ),
    div(class="policy-system-state", attrs=@html.Attrs::build().role("status")) <| [
      strong("正在读取政策投影"),
      p(
        "通过认证网关加载来源、复核收据、变化与验证假设。",
      ),
    ],
  ]
}

///|
fn policy_error_view(emit : @rabbita.Emit[Msg], message : String) -> @html.Html {
  section(class="page policy-radar") <| [
    page_intro(
      PolicyRadar,
      primary_button(emit, RefreshPolicyRadar, "重新加载"),
    ),
    div(
      class="policy-system-state is-error",
      attrs=@html.Attrs::build().role("alert"),
    ) <| [
      strong("政策投影不可用"),
      p(message),
      small(
        "没有显示缓存样本，也没有把连接失败解释成“无变化”。",
      ),
    ],
  ]
}

///|
fn policy_ready_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  projection : PolicyRadarProjection,
) -> @html.Html {
  let verified_sources = projection.sources
    .filter(source => source.verification_state == "verified")
    .length()
  let pending_changes = projection.changes
    .filter(change => change.review_state == "pending")
    .length()
  let confirmed_changes = projection.changes
    .filter(change => change.review_state == "confirmed")
    .length()
  section(class="page policy-radar") <| [
    page_intro(
      PolicyRadar,
      primary_button(emit, RefreshPolicyRadar, "刷新政策投影"),
    ),
    div(class="policy-boundary", attrs=@html.Attrs::build().role("status")) <| [
      strong("证据边界 · REVIEW REQUIRED"),
      p(
        "政府域名、政策措辞和高机会分数都不等于法律结论、预算落实或采购意图。来源、PDF页面、政策解读和商业路径必须分别复核。",
      ),
    ],
    if projection.freshness == "fresh" {
      @html.nothing
    } else {
      div(class="policy-stale-note") <| [
        strong("采集投影尚未新鲜"),
        p(
          "当前服务已接通复核记录，但官方网页/PDF尚未自动刷新；不得把候选目录当作最新扫描。",
        ),
      ]
    },
    div(class="kpi-grid") <| [
      compact_kpi(
        "候选来源",
        projection.sources.length().to_string(),
        "来自服务端政策目录",
        "info",
      ),
      compact_kpi(
        "已核验来源",
        verified_sources.to_string(),
        "未核验来源不能解读变化",
        "warn",
      ),
      compact_kpi(
        "待复核变化",
        pending_changes.to_string(),
        "按来源门禁排队",
        "violet",
      ),
      compact_kpi(
        "已确认解读",
        confirmed_changes.to_string(),
        "只生成通知草稿",
        "ok",
      ),
    ],
    policy_review_panel(emit, model),
    if projection.sources.is_empty() {
      section(class="section-block") <| [
        section_title("来源登记簿", "服务返回了空投影。", "EMPTY"),
        div(class="empty-panel") <| [
          strong("尚无政策来源"),
          p(
            "先由受控采集流程登记来源，不从浏览器直接创建“官方”事实。",
          ),
        ],
      ]
    } else {
      section(class="section-block policy-source-registry") <| [
        section_title(
          "来源登记簿",
          "先确认发布主体、规范URL、发布日期和页面保真，再允许进入解读。",
          projection.sources.length().to_string() + " 个候选",
        ),
        div(class="table-scroll") <| [
          table(class="data-table policy-source-table") <| [
            thead <| [
              tr <| [
                th("文件"),
                th("发布方"),
                th("载体"),
                th("扫描计划"),
                th("验证状态"),
                th("动作"),
              ],
            ],
            tbody <| projection.sources.map(source => {
              policy_source_row(emit, model, source)
            }),
          ],
        ],
      ]
    },
    div(class="policy-review-grid") <| [
      section(class="section-block") <| [
        section_title(
          "变化核验队列",
          "来源未核验时解读动作会在界面和服务端同时阻断。",
          projection.changes.length().to_string() + " 条",
        ),
        if projection.changes.is_empty() {
          div(class="empty-panel") <| [
            strong("没有可复核变化"),
            p("空结果不会被解释为政策没有变化。"),
          ]
        } else {
          div(class="policy-change-list") <| projection.changes.map(change => {
            policy_change_item(emit, model, projection, change)
          })
        },
      ],
      section(class="section-block policy-diff-panel") <| [
        section_title(
          "原文对照", "配置样本不是正式证据；右侧口径来自候选官方快照。",
          "一处口径修正",
        ),
        div(class="policy-diff-columns") <| [
          article(class="policy-diff-side is-removed") <| [
            div(class="policy-diff-label") <| [
              strong("配置样本"),
              status_badge("非官方证据", tone="warning"),
            ],
            p("建设“全市超级算力节点”。"),
            small("来源：用户提供的分析文字"),
          ],
          article(class="policy-diff-side is-added") <| [
            div(class="policy-diff-label") <| [
              strong("官方候选快照"),
              status_badge("等待复核", tone="accent"),
            ],
            p("加快打造北京市级算力节点。"),
            small("来源：北京市政府门户PDF · PAGE 58"),
          ],
        ],
        div(class="policy-diff-conclusion") <| [
          strong("当前安全口径"),
          p(
            "使用“3+N算力中心体系、北京市级算力节点”；超级节点仍作为待核词。",
          ),
        ],
      ],
    ],
    section(class="section-block policy-graph-panel") <| [
      section_title(
        "知识图谱路径", "图用于浏览；关系表是键盘和屏幕阅读器可用的等价视图。",
        "候选关系",
      ),
      div(class="policy-graph", attrs=@html.Attrs::build().aria_hidden("true")) <| [
        div(class="policy-graph-column") <| [
          policy_graph_node("发布方", "北京市政府门户", "候选"),
          policy_graph_node("文件", "昌平十五五规划", "PDF快照"),
        ],
        div(class="policy-graph-arrow", "→"),
        div(class="policy-graph-column") <| [
          policy_graph_node("政策信号", "3+N算力网络", "等待解读"),
          policy_graph_node(
            "产业目标", "先进能源4500亿", "等待解读",
          ),
        ],
        div(class="policy-graph-arrow", "→"),
        div(class="policy-graph-column") <| [
          policy_graph_node(
            "B2G假设", "区级边缘节点试点", "采购未核",
          ),
          policy_graph_node("B2B假设", "能源企业Agent", "客户未核"),
        ],
      ],
      details(class="policy-relation-details") <| [
        summary("查看等价关系表"),
        div(class="table-scroll") <| [
          table(class="data-table") <| [
            thead <| [
              tr <| [
                th("起点"),
                th("关系"),
                th("终点"),
                th("门禁"),
              ],
            ],
            tbody <| [
              tr <| [
                td("政府门户"),
                td("发布候选"),
                td("规划PDF"),
                td("来源核验"),
              ],
              tr <| [
                td("规划PDF"),
                td("提出"),
                td("3+N算力网络"),
                td("解读复核"),
              ],
              tr <| [
                td("政策信号"),
                td("产生假设"),
                td("验证任务"),
                td("正式任务命令"),
              ],
            ],
          ],
        ],
      ],
    ],
    section(class="section-block") <| [
      section_title(
        "B2B / B2G 商机队列",
        "只有对应政策解读已确认，才能准备验证任务；任务仍需具名保存。",
        projection.opportunities.length().to_string() + " 条假设",
      ),
      if projection.opportunities.is_empty() {
        div(class="empty-panel") <| [
          strong("没有机会假设"),
          p("系统不会因为缺少假设而自动生成虚构商机。"),
        ]
      } else {
        div(class="table-scroll") <| [
          table(class="data-table policy-opportunity-table") <| [
            thead <| [
              tr <| [
                th("轨道"),
                th("机会假设"),
                th("为什么现在"),
                th("下一验证"),
                th("门禁"),
                th("动作"),
              ],
            ],
            tbody <| projection.opportunities.map(opportunity => {
              let ready = policy_change_confirmed(
                projection,
                opportunity.source_change_id,
              )
              tr <| [
                td <| [
                  status_badge(
                    opportunity.lane,
                    tone=if opportunity.lane == "B2B" {
                      "accent"
                    } else if opportunity.lane == "B2G" {
                      "violet"
                    } else {
                      "warning"
                    },
                  ),
                ],
                td(opportunity.title),
                td(opportunity.why_now),
                td(opportunity.next_validation),
                td(if ready { "可准备验证" } else { opportunity.gate }),
                td <| [
                  button(
                    type_="button",
                    class="button button-secondary button-small",
                    disabled=!ready,
                    on_click=emit(
                      PreparePolicyValidationTask(opportunity.opportunity_id),
                    ),
                    "准备任务",
                  ),
                ],
              ]
            }),
          ],
        ]
      },
    ],
    if projection.review_audit_ids.is_empty() {
      @html.nothing
    } else {
      div(class="policy-audit-link") <| [
        div <| [
          strong("政策复核收据已进入证据链"),
          p(
            projection.review_audit_ids.length().to_string() +
            " 条持久化收据；均明确无法律与采购效果。",
          ),
        ],
        secondary_button(emit, OpenPolicyEvidence, "在证据页查看"),
      ]
    },
  ]
}

///|
fn policy_radar_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  match model.policy_radar_state {
    "error" => policy_error_view(emit, model.policy_radar_error)
    "ready" =>
      match model.policy_radar_projection {
        Some(projection) => policy_ready_view(emit, model, projection)
        None =>
          policy_error_view(emit, "政策投影状态与数据不一致。")
      }
    _ => policy_loading_view(emit)
  }
}
