///|
fn _overview_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Overview,
      primary_button(
        emit,
        OpenCompanyForm,
        if model.company_saved {
          "查看公司档案"
        } else {
          "开始设置公司"
        },
      ),
    ),
    div(class="setup-banner") <| [
      div <| [
        p(class="banner-kicker", "当前阶段 · P0"),
        h2(
          if model.company_saved {
            "让公司具备安全运行边界"
          } else {
            "先把公司建立为一个可负责的主体"
          },
        ),
        p(
          "在自动化之前，明确公司身份、保留事项、资源、授权、记录和停止路径。所有数据默认从空白开始。",
        ),
      ],
      div(class="progress-block") <| [
        strong("\{setup_count(model)} / 6"),
        span("基础系统已设置"),
        div(class="progress-track") <| [
          div(class="progress-value progress-\{setup_count(model)}", ""),
        ],
      ],
    ],
    div(class="metric-row") <| [
      metric("需要决定", "—", "连接决策记录后显示"),
      metric("现金可见性", "—", "账簿与银行尚未连接"),
      metric(
        "客户信号",
        if model.market_saved {
          "1 条"
        } else {
          "—"
        },
        "仅显示已登记事实",
      ),
      metric("创始人负荷", "—", "尚未开始记录干预时间"),
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("公司系统地图"),
          p(
            "对照基础 OPC 的完整职责范围；启用台账不等于已经产生业务事实。",
          ),
        ],
        status_badge(
          "\{readiness_count(model)}/\{readiness_total()} 系统就绪",
          tone="accent",
        ),
      ],
      div(class="table-scroll") <| [
        table(class="data-table scope-table") <| [
          thead <| [
            tr <| [
              th("职责域"),
              th("必须覆盖"),
              th("责任界面"),
              th("状态"),
            ],
          ],
          tbody <| [
            scope_row(
              "1 · 主体与权利",
              "身份、章程、组织、角色、授权与 RBAC",
              "公司与权利",
              model.company_saved &&
              model.constitution_ready &&
              model.authority_ready,
            ),
            scope_row(
              "2 · 资源与预算",
              "所有权、保管、预算、保留与承诺",
              "公司 / 财务",
              model.resource_register_ready && model.budget_ready,
            ),
            scope_row(
              "3 · 市场与销售",
              "客户、报价、定价、管线、营销与复购",
              "市场与客户",
              model.market_saved && model.offer_register_ready,
            ),
            scope_row(
              "4 · 工作与交付",
              "组合、计划、进度、产物、验收、质量与容量",
              "工作与交付",
              model.work_saved && model.workflow_ready && model.attention_ready,
            ),
            scope_row(
              "5 · 工作流与控制",
              "审批、阈值、委托与职责分离",
              "交付 / 治理",
              model.workflow_ready && model.control_ready,
            ),
            scope_row(
              "6 · 供应与合同",
              "供应商、采购、合同、修订与里程碑",
              "商务与交换",
              model.procurement_ready && model.commitment_saved,
            ),
            scope_row(
              "7 · 费用与借款",
              "费用、垫款、借款、分摊、报销与还款",
              "商务与交换",
              model.expense_register_ready,
            ),
            scope_row(
              "8 · 收付与结算",
              "发票、应收、应付、收款、付款、退款与结算",
              "商务 / 财务",
              model.commitment_saved && model.treasury_ready,
            ),
            scope_row(
              "9 · 现金与融资",
              "银行、资金、预测、融资与贡献经济性",
              "财务与资本",
              model.treasury_ready && model.financing_ready,
            ),
            scope_row(
              "10 · 会计与报告",
              "总账、子账、资产、月结、报表与合并",
              "财务与资本",
              model.ledger_ready,
            ),
            scope_row(
              "11 · 税务",
              "确定、证据、申报、支付、对账与风险",
              "财务与资本",
              model.tax_ready,
            ),
            scope_row(
              "12 · 投资",
              "计划、授权、情景、组合、绩效与 Moonfish 智能体",
              "财务 / 扩展",
              model.investment_ready,
            ),
            scope_row(
              "13 · 保证与学习",
              "报告、预警、审计、复盘、连续性与有界 AI",
              "治理 / 扩展",
              model.control_ready &&
              model.learning_ready &&
              model.continuity_ready,
            ),
          ],
        ],
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("三个经营回路"),
          p(
            "公司必须同时创造价值、稳定交付并保持可治理。",
          ),
        ],
        status_badge("无模拟指标", tone="muted"),
      ],
      div(class="circuit-grid") <| [
        circuit_panel(
          "经济回路",
          "问题 → 报价 → 交付 → 现金 → 复购",
          "公司是否创造并获得了可持续价值？",
          if model.market_saved && model.commitment_saved {
            "已起步"
          } else {
            "未建立"
          },
        ),
        circuit_panel(
          "运营回路",
          "定向 → 计划 → 执行 → 验收 → 学习",
          "承诺能否被重复交付，而不依赖临时救火？",
          if model.work_saved {
            "已起步"
          } else {
            "未建立"
          },
        ),
        circuit_panel(
          "治理回路",
          "授权 → 监控 → 干预 → 对账 → 负责",
          "每个重要影响是否有权利、证据和停止路径？",
          if model.company_saved && model.ledger_ready {
            "已起步"
          } else {
            "未建立"
          },
        ),
      ],
    ],
    div(class="overview-columns") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("今天需要你的决定"),
            p("这里只列需要负责人判断的例外。"),
          ],
        ],
        ul(class="decision-list") <| [
          setup_row(
            "建立公司档案与保留事项",
            "确认谁是最终责任人，以及哪些决定不能委托。",
            model.company_saved,
            secondary_button(
              emit,
              OpenCompanyForm,
              if model.company_saved {
                "查看"
              } else {
                "设置"
              },
            ),
          ),
          setup_row(
            "记录第一个客户问题",
            "先验证付费问题，再增加功能或自动化。",
            model.market_saved,
            secondary_button(emit, Navigate(Market), "进入市场"),
          ),
          setup_row(
            "定义一次可验收交付",
            "输出、接受标准和变化过程必须可检查。",
            model.work_saved,
            secondary_button(emit, Navigate(Delivery), "进入交付"),
          ),
        ],
      ],
      section(class="section-block maturity-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("组织成熟度"),
            p("以退出条件推进，而不是以功能数量推进。"),
          ],
        ],
        ul(class="maturity-list") <| [
          li(class="is-current") <| [
            span("P0"),
            div <| [
              strong("安全运行"),
              small("主体、权利、记录、停止路径"),
            ],
          ],
          li <| [
            span("P1"),
            div <| [
              strong("需求证明"),
              small("客户、付费问题、下一次购买"),
            ],
          ],
          li <| [
            span("P2"),
            div <| [
              strong("重复交付"),
              small("标准工作、验收、容量"),
            ],
          ],
          li <| [
            span("P3"),
            div <| [
              strong("经济与控制"),
              small("毛利、现金、月结、集中度"),
            ],
          ],
          li <| [
            span("P4"),
            div <| [
              strong("韧性与学习"),
              small("恢复、受托、复盘、程序"),
            ],
          ],
          li <| [
            span("P5"),
            div <| [
              strong("受控扩张"),
              small("有界智能体、伙伴、组合治理"),
            ],
          ],
        ],
      ],
    ],
  ]
}

///|
fn company_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  company_setup_form(emit, model)
}

///|
fn _company_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Company,
      primary_button(
        emit,
        OpenCompanyForm,
        if model.company_saved {
          "查看公司工作区"
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
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("公司制度基础"),
          p(
            "先建立空台账与控制边界，再登记真实主体、资源和授权记录。",
          ),
        ],
        status_badge(
          "\{company_readiness_count(model)}/3 已启用",
          tone="muted",
        ),
      ],
      div(class="system-grid") <| [
        system_setup(
          emit,
          "章程与保留事项",
          "目的、风险偏好、资本边界以及不可委托的决定。",
          model.constitution_ready,
          SetupConstitution,
        ),
        system_setup(
          emit,
          "授权与职责",
          "主体、能力、范围、金额、期限、委托与撤销。",
          model.authority_ready,
          SetupAuthority,
        ),
        system_setup(
          emit,
          "资源与保管",
          "资产、账户、数据、凭证的所有权与保管责任。",
          model.resource_register_ready,
          SetupResourceRegister,
        ),
      ],
    ],
    div(class="entity-strip") <| [
      div <| [
        p("公司主体"),
        strong(
          if model.company_saved {
            model.company_name
          } else {
            "尚未建立"
          },
        ),
      ],
      div <| [
        p("最终责任人"),
        strong("尚未指定"),
      ],
      div <| [
        p("保留事项"),
        strong("尚未定义"),
      ],
      div <| [
        p("数据边界"),
        strong("本地优先"),
      ],
    ],
    div(class="two-column") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("权利与授权"),
            p("行动权按对象、范围、金额、时间和影响授予。"),
          ],
          status_badge(
            if model.authority_ready {
              "台账已启用"
            } else {
              "台账未启用"
            },
            tone="muted",
          ),
        ],
        empty_table(
          ["代表", "能力", "范围", "限制", "状态"],
          "还没有授权记录",
          secondary_button(emit, SetupAuthority, "建立授权台账"),
        ),
      ],
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("保留事项"),
            p("这些决定默认只能由最终责任人作出。"),
          ],
        ],
        ul(class="plain-list") <| [
          li <| [
            strong("治理规则"),
            span("章程、授权模型与重大结构变化"),
          ],
          li <| [
            strong("资金影响"),
            span("重要付款、融资与投资执行"),
          ],
          li <| [
            strong("外部承诺"),
            span("例外定价、合同与高风险声明"),
          ],
          li <| [
            strong("敏感影响"),
            span("敏感数据、生产部署与受监管行为"),
          ],
        ],
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("公司资源"),
          p("区分所有权、控制权、保管人和可用范围。"),
        ],
        status_badge(
          if model.resource_register_ready {
            "台账已启用"
          } else {
            "台账未启用"
          },
          tone="muted",
        ),
      ],
      empty_table(
        ["资源", "类型", "所有者", "保管人", "可用状态"],
        "还没有登记公司资源",
        secondary_button(emit, SetupResourceRegister, "建立资源台账"),
      ),
    ],
  ]
}

///|
fn market_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  form(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("登记客户机会"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("登记客户机会"),
        p("先记录买方与问题，不把兴趣误当作收入。"),
      ],
      status_badge("未成交", tone="warning"),
    ],
    div(class="form-grid") <| [
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("market-party"),
          "客户或买方",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("market-party").required(true),
          value=model.market_party,
          placeholder="组织或个人",
          on_input=emit.map(value => InputMarketParty(value)),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("market-problem"),
          "需要验证的问题",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("market-problem").required(true),
          value=model.market_problem,
          placeholder="客户愿意为什么结果付费？",
          on_input=emit.map(value => InputMarketProblem(value)),
        ),
      ],
    ],
    div(class="form-actions") <| [
      primary_button(emit, SaveMarket, "保存机会"),
    ],
  ]
}

///|
fn market_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Market,
      primary_button(emit, OpenMarketForm, "登记客户机会"),
    ),
    if model.market_form_open {
      market_form(emit, model)
    } else {
      @html.nothing
    },
    div(class="system-grid") <| [
      system_setup(
        emit,
        "报价、定价与续购",
        "把已验证问题封装为可比较的报价、价值度量和下一次购买条件。",
        model.offer_register_ready,
        SetupOfferRegister,
      ),
    ],
    div(class="metric-row") <| [
      metric(
        "有效机会",
        if model.market_saved {
          "1"
        } else {
          "—"
        },
        "已明确买方与问题",
      ),
      metric("付费验证", "—", "尚无收款或合同证据"),
      metric("交付接受率", "—", "尚无验收记录"),
      metric("复购信号", "—", "尚无续购记录"),
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("客户机会"),
          p(
            "从明确买方和付费问题开始，而不是从功能清单开始。",
          ),
        ],
        status_badge(
          if model.market_saved {
            "1 条界面记录"
          } else {
            "空白"
          },
          tone="muted",
        ),
      ],
      if model.market_saved {
        table(class="data-table") <| [
          thead <| [
            tr <| [
              th("客户或买方"),
              th("待验证问题"),
              th("商业状态"),
              th("下一步"),
            ],
          ],
          tbody <| [
            tr <| [
              td(model.market_party),
              td(model.market_problem),
              td <| [
                status_badge("待验证", tone="warning"),
              ],
              td("定义付费试用与接受标准"),
            ],
          ],
        ]
      } else {
        empty_table(
          ["客户或买方", "待验证问题", "商业状态", "下一步"],
          "还没有客户机会",
          primary_button(emit, OpenMarketForm, "登记第一条机会"),
        )
      },
    ],
    div(class="two-column") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("标准报价"),
            p("输入、输出、边界和接受标准。"),
          ],
        ],
        if model.offer_register_ready {
          div(class="empty-panel is-ready") <| [
            strong("报价台账已启用"),
            p(
              "尚无报价记录；客户问题、价格、边界和接受标准必须来自真实交易。",
            ),
          ]
        } else {
          div(class="empty-panel") <| [
            strong("尚未定义报价"),
            p("验证客户问题后，再把可重复交付封装为报价。"),
          ]
        },
      ],
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("客户成功"),
            p("激活、价值实现、续购和流失原因。"),
          ],
        ],
        div(class="empty-panel") <| [
          strong("尚无客户使用证据"),
          p("这里不使用访问量或线索数替代真实价值。"),
        ],
      ],
    ],
  ]
}

///|
fn work_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  form(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("创建工作项"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("创建可验收工作"),
        p("每项工作都必须说明完成后如何被检查。"),
      ],
      status_badge("不自动执行", tone="muted"),
    ],
    div(class="form-grid") <| [
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("work-title"), "工作名称"),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("work-title").required(true),
          value=model.work_title,
          placeholder="需要完成的结果",
          on_input=emit.map(value => InputWorkTitle(value)),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("work-acceptance"),
          "验收标准",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("work-acceptance").required(true),
          value=model.work_acceptance,
          placeholder="如何判断结果可以接受？",
          on_input=emit.map(value => InputWorkAcceptance(value)),
        ),
      ],
    ],
    div(class="form-actions") <| [
      primary_button(emit, SaveWork, "保存工作项"),
    ],
  ]
}

///|
fn lane(title : String, count : Int32, content : @html.Html) -> @html.Html {
  article(class="work-lane") <| [
    div(class="lane-heading") <| [
      strong(title),
      span(count.to_string()),
    ],
    content,
  ]
}

///|
fn work_card(model : Model, state : String, action : @html.Html) -> @html.Html {
  article(class="work-card") <| [
    strong(model.work_title),
    p(model.work_acceptance),
    div(class="work-meta") <| [
      span("负责人未指定"),
      status_badge(state, tone="muted"),
    ],
    action,
  ]
}

///|
fn delivery_boundary_notice() -> String {
  "SESSION-LOCAL / NOT POSTGRESQL EVIDENCE：此看板只演练定义 → 执行 → 提交 → 具名接受的界面状态，不写入 PostgreSQL，不构成正式交付、审计或结算证据。正式任务仍须通过任务编排的签名网关与持久化收据。"
}

///|
fn delivery_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Delivery, primary_button(emit, OpenWorkForm, "创建工作项")),
    div(class="boundary-note") <| [
      strong("会话内工作流演练"),
      p(delivery_boundary_notice()),
    ],
    if model.work_form_open {
      work_form(emit, model)
    } else {
      @html.nothing
    },
    div(class="system-grid") <| [
      system_setup(
        emit,
        "工作流与独立验收",
        "定义执行、提交、接受、变更与返工的分离状态。",
        model.workflow_ready,
        SetupWorkflow,
      ),
      system_setup(
        emit,
        "容量与负责人关注",
        "预算审批、例外、返工、救火和上下文恢复所消耗的负责人时间。",
        model.attention_ready,
        SetupAttention,
      ),
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("交付流"),
          p("执行者不能单独批准自己的重要结果。"),
        ],
        status_badge("按例外管理", tone="accent"),
      ],
      div(class="work-board") <| [
        lane(
          "待定义",
          if model.work_saved && model.work_stage == 0 {
            1
          } else {
            0
          },
          if model.work_saved && model.work_stage == 0 {
            work_card(
              model,
              "待计划",
              secondary_button(emit, StartWork, "开始执行"),
            )
          } else {
            div(class="lane-empty", "没有工作项")
          },
        ),
        lane(
          "进行中",
          if model.work_saved && model.work_stage == 1 {
            1
          } else {
            0
          },
          if model.work_saved && model.work_stage == 1 {
            work_card(
              model,
              "进行中",
              secondary_button(emit, SubmitWork, "提交验收"),
            )
          } else {
            div(class="lane-empty", "没有进行中的工作")
          },
        ),
        lane(
          "待验收",
          if model.work_saved && model.work_stage == 2 {
            1
          } else {
            0
          },
          if model.work_saved && model.work_stage == 2 {
            work_card(
              model,
              "待验收",
              primary_button(emit, AcceptWork, "接受结果"),
            )
          } else {
            div(class="lane-empty", "没有等待验收的结果")
          },
        ),
        lane(
          "已接受",
          if model.work_saved && model.work_stage == 3 {
            1
          } else {
            0
          },
          if model.work_saved && model.work_stage == 3 {
            work_card(
              model,
              "已接受",
              status_badge("等待结算与入账", tone="accent"),
            )
          } else {
            div(class="lane-empty", "没有已接受的交付")
          },
        ),
      ],
    ],
    div(class="two-column") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("质量边界"),
            p("接受、返工和缺陷分别记录。"),
          ],
        ],
        ul(class="plain-list") <| [
          li <| [
            strong("输入"),
            span("来源与版本必须明确"),
          ],
          li <| [
            strong("输出"),
            span("产物和证据必须可定位"),
          ],
          li <| [
            strong("验收"),
            span("由独立角色或规则检查"),
          ],
          li <| [
            strong("变化"),
            span("范围变化必须重新定价或批准"),
          ],
        ],
      ],
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("创始人容量"),
            p("关注必须像现金一样被预算。"),
          ],
        ],
        div(
          class=if model.attention_ready {
            "empty-panel is-ready"
          } else {
            "empty-panel"
          },
        ) <| [
          strong(
            if model.attention_ready {
              "关注预算台账已启用"
            } else {
              "尚未记录干预时间"
            },
          ),
          p(
            "开始运行后记录审批、例外、返工和上下文重建时间。",
          ),
        ],
      ],
    ],
  ]
}

