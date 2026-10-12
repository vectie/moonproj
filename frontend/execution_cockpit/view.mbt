///|
using @html {article, div, h3, p, section, small, span, strong}

///|
fn phase_label(phase : @agent_port.ExecutionPhase) -> String {
  match phase {
    Queued => "排队"
    Ready => "可领取"
    Claimed => "已领取"
    Running => "运行中"
    WaitingForPeer => "等待协作者"
    WaitingForChildren => "等待子任务"
    WaitingForReview => "产出待审"
    WaitingForHuman => "等待人类"
    ReadyForRework => "待返工"
    Succeeded => "已完成"
    Failed => "失败"
    Rejected => "已拒绝"
    Cancelled => "已取消"
    Quarantined => "已隔离"
  }
}

///|
fn severity_label(severity : @attention.AttentionSeverity) -> String {
  match severity {
    Informational => "信息"
    Normal => "普通"
    Urgent => "紧急"
    Critical => "关键"
  }
}

///|
fn sample_attempt(
  id : String,
  work : String,
  phase : @agent_port.ExecutionPhase,
  cost_minor : Int64,
  reason : String,
) -> @agent_port.ExecutionAttempt {
  {
    protocol_version: @agent_port.protocol_version(),
    attempt_id: id,
    request_id: "request-\{id}",
    work_item_id: work,
    flow_run_id: "professional-service-shadow-001",
    phase,
    revision: 3,
    attempt_number: 1,
    claim: None,
    crash_streak: if phase is Quarantined {
      3
    } else {
      0
    },
    interrupted_streak: 0,
    rework_round: 0,
    artifact_refs: if phase is (WaitingForReview | Succeeded) {
      ["evidence/\{id}/output"]
    } else {
      []
    },
    cost_minor,
    terminal_reason: reason,
    events: [],
  }
}

///|
pub fn sample_projection() -> @attention.ExecutionActivityProjection {
  @attention.project_execution_activity(
    [
      sample_attempt(
        "attempt-research-7",
        "研究客户问题",
        Running,
        8200L,
        "agent is executing",
      ),
      sample_attempt(
        "attempt-delivery-4",
        "交付材料独立复核",
        WaitingForReview,
        4600L,
        "evidence package is ready",
      ),
      sample_attempt(
        "attempt-channel-2",
        "确认客户反馈归属",
        WaitingForHuman,
        1200L,
        "customer identity needs confirmation",
      ),
      sample_attempt(
        "attempt-procedure-3",
        "复盘失败步骤",
        Quarantined,
        3100L,
        "three consecutive runtime crashes",
      ),
      sample_attempt(
        "attempt-brief-6",
        "编制专业服务简报",
        Succeeded,
        6700L,
        "accepted by independent reviewer",
      ),
    ],
    principal_id="opc-001",
    at_epoch=1786464000L,
  ) catch {
    _ =>
      {
        total: 0,
        active: 0,
        waiting: 0,
        review: 0,
        succeeded: 0,
        quarantined: 0,
        total_cost_minor: 0L,
        rows: [],
        inbox: @attention.AttentionInbox::new(),
      }
  }
}

///|
fn stat(label : String, value : String) -> @html.Html {
  article(class="autonomy-card") <| [
    strong(value),
    small(label),
  ]
}

///|
fn activity_row(row : @attention.ExecutionActivityRow) -> @html.Html {
  article(class="agent-card") <| [
    div(class="loop-head") <| [
      div <| [
        strong(row.work_item_id),
        small(row.attempt_id),
      ],
      span(
        class=if row.needs_attention {
          "status warning"
        } else {
          "status accent"
        },
      ) <| [
        @html.text(phase_label(row.phase)),
      ],
    ],
    p(row.last_reason),
    div(class="budget-row") <| [
      span("尝试 \{row.attempt_number} · 修订 \{row.revision}"),
      span("证据 \{row.artifact_count}"),
    ],
    small("执行成本（非公司账）\{row.cost_minor} minor"),
  ]
}

///|
fn attention_row(item : @attention.AttentionItem) -> @html.Html {
  article(class="attention-item") <| [
    div(class="attention-main") <| [
      div(class="attention-title") <| [
        strong(item.title),
        span(class="status warning") <| [
          @html.text(severity_label(item.severity)),
        ],
      ],
      p(item.reason),
      small("需要：\{item.requested_action} · 来源 \{item.source_id}"),
    ],
    div(class="attention-actions") <| [
      span(class="status muted") <| [
        @html.text(if item.reversible { "可逆" } else { "需隔离审计" }),
      ],
    ],
  ]
}

///|
pub fn view() -> @html.Html {
  let projection = sample_projection()
  section(class="execution-cockpit") <| [
    div(class="section-heading") <| [
      div <| [
        h3("执行与活动投影"),
        p(
          "公司目标向下编排；MoonFlow 推进单条工作流；MoonClaw 执行尝试。这里展示执行账，不替代公司账。",
        ),
      ],
      span(class="status accent") <| [
        @html.text(@agent_port.protocol_version()),
      ],
    ],
    div(class="autonomy-grid") <| [
      stat("总尝试", projection.total.to_string()),
      stat("运行中", projection.active.to_string()),
      stat("待人工", projection.waiting.to_string()),
      stat("待复核", projection.review.to_string()),
      stat("已隔离", projection.quarantined.to_string()),
    ],
    div(class="agent-grid") <| projection.rows.map(activity_row),
    div(class="section-heading") <| [
      div <| [
        h3("Attention Inbox"),
        p(
          "只汇聚需要判断、证据或恢复操作的事项；重复信号按执行尝试去重。",
        ),
      ],
      span(class="status warning") <| [
        @html.text("\{projection.inbox.open_items().length()} 待处理"),
      ],
    ],
    div <| projection.inbox.open_items().map(attention_row),
  ]
}
