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
fn dispatch_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Dispatch,
      primary_button(
        emit,
        RecordDecision("创建并分派任务"),
        "创建任务",
      ),
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
