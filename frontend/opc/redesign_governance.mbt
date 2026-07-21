///|
fn observe_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Observe, status_badge("1 项已升级", tone="warning")),
    section_title(
      "SLO 面板", "错误预算驱动发布节奏；预算烧尽即自动冻结。",
      "3/4 健康",
    ),
    div(class="slo-grid") <| [
      compact_kpi(
        "API 可用性", "99.96%", "目标 99.90% · 余量 72%", "ok",
      ),
      compact_kpi(
        "P95 延迟", "428 ms", "目标 ≤400ms · 预算消耗 74%", "warn",
      ),
      compact_kpi(
        "任务成功率", "99.2%", "目标 99.0% · 余量 64%", "ok",
      ),
      compact_kpi("证据写入", "99.99%", "目标 99.95% · 余量 91%", "ok"),
    ],
    section(class="section-block") <| [
      section_title(
        "告警流", "自愈优先，只有超出自治边界的异常升级给 Owner。",
        "4 活跃",
      ),
      div(class="alert-row is-critical") <| [
        status_badge("严重", tone="warning"),
        strong("API P95 延迟连续 12 分钟超标"),
        span("Sentinel-01 · 已升级"),
        primary_button(
          emit,
          RecordDecision("处理 API 延迟告警"),
          "处理",
        ),
      ],
      div(class="alert-row") <| [
        status_badge("警告", tone="muted"),
        strong("证据队列积压 1,284 条"),
        span("Queue-01 · 自愈中"),
        secondary_button(emit, RecordDecision("查看自愈证据"), "查看"),
      ],
      div(class="alert-row") <| [
        status_badge("提示", tone="accent"),
        strong("夜间备份校验完成"),
        span("Backup-01 · 已恢复"),
        secondary_button(emit, RecordDecision("查看备份证据"), "证据"),
      ],
    ],
  ]
}

///|
fn operate_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Operate,
      primary_button(emit, RecordDecision("启动事件响应"), "启动响应"),
    ),
    div(class="kpi-grid") <| [
      compact_kpi("开放事件", "2", "SEV2 ×1 · SEV3 ×1", "warn"),
      compact_kpi("MTTR", "18 分", "近 30 天 ↓ 11%", "ok"),
      compact_kpi("复盘闭环", "7/8", "1 个阻断自动化", "info"),
      compact_kpi("Runbook 自动化", "67%", "6/9 已验证", "violet"),
    ],
    div(class="quality-detail-grid") <| [
      section(class="section-block") <| [
        section_title(
          "事件记录", "响应 → 恢复 → 复盘 → Runbook；不闭环就不能自动化。",
          "2 开放",
        ),
        div(class="incident-row") <| [
          status_badge("SEV2", tone="warning"),
          div <| [
            strong("支付回调延迟"),
            p("09:12 发现 · 09:18 降级 · 09:27 恢复"),
          ],
          status_badge("复盘中", tone="warning"),
        ],
        div(class="incident-row") <| [
          status_badge("SEV3", tone="muted"),
          div <| [
            strong("搜索索引滞后"),
            p("10:04 发现 · Sentinel-01 自愈中"),
          ],
          status_badge("响应中", tone="accent"),
        ],
        primary_button(
          emit,
          RecordDecision("审阅支付回调复盘"),
          "审阅未闭环复盘",
        ),
      ],
      section(class="section-block") <| [
        section_title(
          "Runbook 库", "每次人工处置都要沉淀为可验证的恢复程序。",
          "6/9 自动化",
        ),
        ul(class="runbook-list") <| [
          li <| [
            strong("API 延迟降级"),
            status_badge("已自动化", tone="accent"),
          ],
          li <| [
            strong("证据队列排空"),
            status_badge("已自动化", tone="accent"),
          ],
          li <| [
            strong("支付回调重放"),
            status_badge("待复盘", tone="warning"),
          ],
          li <| [
            strong("数据库只读切换"),
            status_badge("已演练", tone="accent"),
          ],
        ],
      ],
    ],
  ]
}

///|
fn company_domain_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Company,
      primary_button(
        emit,
        OpenCompanyForm,
        if model.company_saved {
          "编辑公司档案"
        } else {
          "建立公司档案"
        },
      ),
    ),
    if model.company_form_open {
      company_form(emit, model)
    } else {
      @html.nothing
    },
    div(class="kpi-grid") <| [
      compact_kpi(
        "现金余额", "¥85.2万", "银行连接后形成正式事实", "ok",
      ),
      compact_kpi("现金跑道", "14.2 月", "按当前月耗估算", "ok"),
      compact_kpi("应收合同", "¥12.6万", "3 份履约中", "info"),
      compact_kpi("本月税务", "2 项", "申报证据待核", "warn"),
    ],
    div(class="company-domain-grid") <| [
      div(class="domain-card") <| [
        strong("主体、权利与资源"),
        p(
          "法人主体、章程、保留事项、授权、资产、账户与数据权利。",
        ),
        secondary_button(
          emit,
          RecordDecision("管理主体、权利与资源"),
          "管理主体",
        ),
      ],
      div(class="domain-card") <| [
        strong("市场、销售与客户"),
        p(
          "客户问题、报价、订单、续购、销售与应收全过程。",
        ),
        secondary_button(emit, Navigate(Market), "进入市场域"),
      ],
      div(class="domain-card") <| [
        strong("采购、费用与合同"),
        p(
          "供应商、采购、合同、履约、发票、报销、借款与结算。",
        ),
        secondary_button(emit, Navigate(Commerce), "进入商务域"),
      ],
      div(class="domain-card") <| [
        strong("财务、税务与资本"),
        p(
          "预算、账簿、现金、银行、税务、融资、估值与投资组合。",
        ),
        secondary_button(emit, Navigate(Finance), "进入财资域"),
      ],
      div(class="domain-card") <| [
        strong("治理、风险与连续性"),
        p(
          "授权控制、复盘、审计、备份、恢复、受托人与停止路径。",
        ),
        secondary_button(emit, Navigate(Assurance), "进入治理域"),
      ],
      div(class="domain-card") <| [
        strong("智能体与行业扩展"),
        p(
          "MoonClaw 运行时、Moonfish 投资 Agent 与独立行业能力包。",
        ),
        secondary_button(emit, Navigate(Extensions), "管理扩展"),
      ],
    ],
    section(class="section-block") <| [
      section_title(
        "合规日历", "申报、支付和对账都必须具备完整证据链。",
        "本月 2 项",
      ),
      div(class="compliance-row") <| [
        strong("增值税及附加申报"),
        span("07-15"),
        status_badge("待复核", tone="warning"),
      ],
      div(class="compliance-row") <| [
        strong("企业所得税预缴"),
        span("07-31"),
        status_badge("证据准备中", tone="muted"),
      ],
    ],
  ]
}

///|
fn evidence_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Evidence, status_badge("今日 363 条", tone="accent")),
    div(class="evidence-summary") <| [
      compact_kpi("授权放行", "312", "范围与预算内", "ok"),
      compact_kpi("越权拦截", "4", "未产生业务影响", "warn"),
      compact_kpi(
        "待 Owner 裁决", "5", "均已进入注意力队列", "violet",
      ),
      compact_kpi("独立抽检", "47", "Gatekeeper-01", "info"),
    ],
    section(class="section-block") <| [
      section_title(
        "今日证据流", "时间倒序；主体、授权、输入、动作、输出与结果不可分割。",
        "实时",
      ),
      div(class="table-scroll") <| [
        table(class="data-table evidence-table") <| [
          thead <| [
            tr <| [
              th("时间"),
              th("行为者"),
              th("代表主体"),
              th("事件"),
              th("证据"),
              th("结果"),
            ],
          ],
          tbody <| [
            tr <| [
              td("09:42:18"),
              td("Gatekeeper-01"),
              td("公司"),
              td("抽检 Builder-02 发布动作"),
              td("EV-8471"),
              td <| [
                status_badge("放行", tone="accent"),
              ],
            ],
            tr <| [
              td("09:39:04"),
              td("Finance-01"),
              td("公司"),
              td("申请 ¥8,000 推理额度"),
              td("EV-8468"),
              td <| [
                status_badge("拦截", tone="warning"),
              ],
            ],
            tr <| [
              td("09:31:27"),
              td("Sentinel-01"),
              td("生产环境"),
              td("第三次自愈未收敛并升级"),
              td("EV-8460"),
              td <| [
                status_badge("待裁决", tone="warning"),
              ],
            ],
            tr <| [
              td("09:18:50"),
              td("Release-01"),
              td("moonproj"),
              td("提交 v0.8 灰度 Gate"),
              td("EV-8449"),
              td <| [
                status_badge("待裁决", tone="warning"),
              ],
            ],
          ],
        ],
      ],
      secondary_button(
        emit,
        RecordDecision("导出审计证据包"),
        "导出证据包",
      ),
    ],
  ]
}
