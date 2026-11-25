///|
fn commitment_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  form(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("登记承诺草案"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("登记承诺草案"),
        p("草案不等于签署、履约、结算或入账。"),
      ],
      status_badge("无外部效果", tone="warning"),
    ],
    div(class="form-grid") <| [
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("commitment-title"),
          "承诺事项",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("commitment-title").required(true),
          value=model.commitment_title,
          placeholder="公司承诺提供或获得什么？",
          on_input=emit.map(value => InputCommitmentTitle(value)),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("commitment-counterparty"),
          "交易对手",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build()
            .id("commitment-counterparty")
            .required(true),
          value=model.commitment_counterparty,
          placeholder="客户、供应商或合作方",
          on_input=emit.map(value => InputCommitmentCounterparty(value)),
        ),
      ],
    ],
    div(class="form-actions") <| [
      primary_button(emit, SaveCommitment, "保存草案"),
    ],
  ]
}

///|
fn commitment_state(stage : Int32) -> String {
  match stage {
    0 => "草案"
    1 => "已批准"
    2 => "已签署"
    3 => "已履约"
    4 => "已结算"
    _ => "已记录入账"
  }
}

///|
fn commitment_next_action(
  emit : @rabbita.Emit[Msg],
  stage : Int32,
) -> @html.Html {
  match stage {
    0 => secondary_button(emit, ApproveCommitment, "记录批准")
    1 => secondary_button(emit, SignCommitment, "记录签署")
    2 => secondary_button(emit, CompleteCommitment, "关联履约")
    3 => secondary_button(emit, SettleCommitment, "检查结算")
    4 => secondary_button(emit, RecognizeCommitment, "检查入账")
    _ => status_badge("生命周期完整", tone="accent")
  }
}

///|
fn commerce_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Commerce,
      primary_button(emit, OpenCommitmentForm, "登记承诺"),
    ),
    if model.commitment_form_open {
      commitment_form(emit, model)
    } else {
      @html.nothing
    },
    div(class="system-grid") <| [
      system_setup(
        emit,
        "供应商、采购与里程碑",
        "询价、选择、合同、修订、里程碑、接受与争议分别留痕。",
        model.procurement_ready,
        SetupProcurement,
      ),
      system_setup(
        emit,
        "费用、借款与报销",
        "申请、批准、分摊、报销、还款与会计状态分离。",
        model.expense_register_ready,
        SetupExpenseRegister,
      ),
    ],
    div(class="state-rail") <| [
      div(
        class=if model.commitment_stage == 0 {
          "is-current"
        } else {
          "is-complete"
        },
      ) <| [
        span("1"),
        strong("提出"),
      ],
      div(
        class=if model.commitment_stage == 1 {
          "is-current"
        } else if model.commitment_stage > 1 {
          "is-complete"
        } else {
          ""
        },
      ) <| [
        span("2"),
        strong("批准"),
      ],
      div(
        class=if model.commitment_stage == 2 {
          "is-current"
        } else if model.commitment_stage > 2 {
          "is-complete"
        } else {
          ""
        },
      ) <| [
        span("3"),
        strong("签署"),
      ],
      div(
        class=if model.commitment_stage == 3 {
          "is-current"
        } else if model.commitment_stage > 3 {
          "is-complete"
        } else {
          ""
        },
      ) <| [
        span("4"),
        strong("履约"),
      ],
      div(
        class=if model.commitment_stage == 4 {
          "is-current"
        } else if model.commitment_stage > 4 {
          "is-complete"
        } else {
          ""
        },
      ) <| [
        span("5"),
        strong("结算"),
      ],
      div(class=if model.commitment_stage == 5 { "is-current" } else { "" }) <| [
        span("6"),
        strong("入账"),
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("公司承诺"),
          p("业务状态、支付状态和会计状态始终分离。"),
        ],
        status_badge(
          if model.commitment_saved {
            "1 份草案"
          } else {
            "空白"
          },
          tone="muted",
        ),
      ],
      if model.commitment_saved {
        table(class="data-table") <| [
          thead <| [
            tr <| [
              th("事项"),
              th("交易对手"),
              th("业务状态"),
              th("资金"),
              th("会计"),
              th("下一步"),
            ],
          ],
          tbody <| [
            tr <| [
              td(model.commitment_title),
              td(model.commitment_counterparty),
              td <| [
                status_badge(
                  commitment_state(model.commitment_stage),
                  tone="warning",
                ),
              ],
              td(
                if model.commitment_stage >= 4 {
                  "检查点已记录"
                } else {
                  "未发生"
                },
              ),
              td(
                if model.commitment_stage >= 5 {
                  "检查点已记录"
                } else {
                  "未确认"
                },
              ),
              td <| [
                commitment_next_action(emit, model.commitment_stage),
              ],
            ],
          ],
        ]
      } else {
        empty_table(
          [
            "事项", "交易对手", "业务状态", "资金", "会计", "下一步",
          ],
          "还没有公司承诺",
          primary_button(emit, OpenCommitmentForm, "登记第一份草案"),
        )
      },
    ],
    div(class="three-column") <| [
      article(class="compact-panel") <| [
        h3("采购"),
        p("供应商、报价、选择、合同与接受。"),
        status_badge(
          if model.procurement_ready {
            "空台账已启用"
          } else {
            "未启用"
          },
          tone="muted",
        ),
      ],
      article(class="compact-panel") <| [
        h3("销售"),
        p("报价、订单、履约、开票与收款。"),
        status_badge("未启用", tone="muted"),
      ],
      article(class="compact-panel") <| [
        h3("争议与变化"),
        p("修订、取消、退款和责任记录。"),
        status_badge(
          if model.expense_register_ready {
            "费用边界已启用"
          } else {
            "未启用"
          },
          tone="muted",
        ),
      ],
    ],
  ]
}

///|
fn finance_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Finance,
      primary_button(
        emit,
        SetupLedger,
        if model.ledger_ready {
          "检查账簿设置"
        } else {
          "建立基础账簿"
        },
      ),
    ),
    div(class="system-grid") <| [
      system_setup(
        emit,
        "预算与资源保留",
        "额度、用途、保留、释放与实际消耗保持可追溯。",
        model.budget_ready,
        SetupBudget,
      ),
      system_setup(
        emit,
        "总账与子账",
        "本位币、科目、期间、平衡分录、资产和月结。",
        model.ledger_ready,
        SetupLedger,
      ),
      system_setup(
        emit,
        "现金、银行与资金",
        "账户、流水、预测、收付、匹配和对账。",
        model.treasury_ready,
        SetupTreasury,
      ),
      system_setup(
        emit,
        "税务义务",
        "税额确定、证据、申报、支付、对账与风险。",
        model.tax_ready,
        SetupTax,
      ),
      system_setup(
        emit,
        "融资与资本",
        "资本、授信、提款、还款、契约和资金成本。",
        model.financing_ready,
        SetupFinancing,
      ),
      system_setup(
        emit,
        "投资组合",
        "授权、情景、建议、仓位、估值、绩效和风险。",
        model.investment_ready,
        SetupInvestment,
      ),
    ],
    div(class="metric-row") <| [
      metric("可用现金", "—", "银行账户尚未连接"),
      metric("应收", "—", "没有已接受的客户债权"),
      metric("应付", "—", "没有已接受的供应商债务"),
      metric("贡献毛利", "—", "尚无完整收入与成本证据"),
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("财务基础"),
          p("先建立账簿和对账，再允许智能体解释或建议。"),
        ],
        status_badge(
          if model.ledger_ready {
            "界面已启用"
          } else {
            "未设置"
          },
          tone=if model.ledger_ready { "accent" } else { "muted" },
        ),
      ],
      ul(class="finance-setup") <| [
        setup_row(
          "预算与资源保留",
          "额度、用途、审批、保留、释放与消耗。",
          model.budget_ready,
          secondary_button(emit, SetupBudget, "设置"),
        ),
        setup_row(
          "法人账簿",
          "本位币、会计政策、科目和期间。",
          model.ledger_ready,
          secondary_button(emit, SetupLedger, "设置"),
        ),
        setup_row(
          "银行与现金",
          "账户、流水、匹配和付款边界。",
          model.treasury_ready,
          secondary_button(emit, SetupTreasury, "设置"),
        ),
        setup_row(
          "税务档案",
          "税种、申报证据、支付和对账。",
          model.tax_ready,
          secondary_button(emit, SetupTax, "设置"),
        ),
        setup_row(
          "融资与投资",
          "额度、资本、授权、仓位与绩效。",
          model.financing_ready && model.investment_ready,
          secondary_button(
            emit,
            if model.financing_ready {
              SetupInvestment
            } else {
              SetupFinancing
            },
            if model.financing_ready {
              "设置投资"
            } else {
              "设置融资"
            },
          ),
        ),
      ],
    ],
    div(class="two-column") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("现金预测"),
            p("按已知承诺和收付计划形成。"),
          ],
        ],
        div(class="empty-panel") <| [
          strong("没有可计算的现金事件"),
          p("公司不会用预算或发票金额冒充实际现金。"),
        ],
      ],
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("月结与对账"),
            p("总账、子账、银行和税务必须一致。"),
          ],
        ],
        div(class="empty-panel") <| [
          strong("尚未开始首个期间"),
          p("关闭期间前需要平衡分录和通过控制报告。"),
        ],
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("投资能力"),
          p(
            "Moonfish 分析被吸收为本地证据，执行仍受公司授权。",
          ),
        ],
        status_badge(
          if model.investment_ready {
            "原生台账已启用"
          } else {
            "原生域"
          },
          tone="accent",
        ),
      ],
      empty_table(
        ["投资授权", "建议", "持仓", "估值", "风险状态"],
        "还没有投资授权或持仓",
        if model.investment_ready {
          status_badge("空台账 · 无交易权限", tone="muted")
        } else {
          secondary_button(emit, SetupInvestment, "建立投资台账")
        },
      ),
    ],
  ]
}

///|
fn control_row(
  decision : String,
  agent_role : String,
  human_gate : String,
) -> @html.Html {
  tr <| [
    td(decision),
    td(agent_role),
    td(human_gate),
  ]
}

///|
fn assurance_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Assurance,
      primary_button(
        emit,
        SetupContinuity,
        if model.continuity_ready {
          "检查连续性计划"
        } else {
          "建立连续性计划"
        },
      ),
    ),
    div(class="system-grid") <| [
      system_setup(
        emit,
        "控制、风险与事件",
        "阈值、预警、例外、事件、纠正措施和不可变审计。",
        model.control_ready,
        SetupControls,
      ),
      system_setup(
        emit,
        "复盘与标准程序",
        "指标、实验、反例、复盘、程序提升与失效假设。",
        model.learning_ready,
        SetupLearning,
      ),
      system_setup(
        emit,
        "连续性与受托模式",
        "运行记录、依赖、备份、恢复、受托访问和安全降级。",
        model.continuity_ready,
        SetupContinuity,
      ),
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("决策权与人工闸门"),
          p(
            "提出、执行、批准和对账不能全部由同一角色完成。",
          ),
        ],
        status_badge(
          if model.control_ready {
            "空台账已启用"
          } else {
            "默认拒绝"
          },
          tone="accent",
        ),
      ],
      table(class="data-table") <| [
        thead <| [
          tr <| [
            th("决策类别"),
            th("智能体可以做什么"),
            th("必须由谁确认"),
          ],
        ],
        tbody <| [
          control_row(
            "可逆内部草稿", "起草、检查、比较", "抽样或例外复核",
          ),
          control_row(
            "客户沟通", "准备内容与政策检查", "负责人确认身份、受众和承诺",
          ),
          control_row(
            "合同或例外定价", "准备选项和影响", "负责人或授权专业人员",
          ),
          control_row(
            "付款或投资", "读取、匹配、提出", "银行控制人与重要金额二次验证",
          ),
          control_row(
            "敏感数据或生产影响", "分类并建议最小权限", "数据或技术责任人",
          ),
        ],
      ],
    ],
    div(class="two-column") <| [
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("连续性"),
            p(
              "创始人不可用时，公司仍能安全暂停、说明和恢复。",
            ),
          ],
          status_badge(
            if model.continuity_ready {
              "清单已启用"
            } else {
              "未设置"
            },
            tone="muted",
          ),
        ],
        ul(class="plain-list") <| [
          li <| [
            strong("公司运行记录"),
            span(
              if model.continuity_ready {
                "已建立界面清单"
              } else {
                "尚未建立"
              },
            ),
          ],
          li <| [
            strong("备份与恢复"),
            span("尚未验证"),
          ],
          li <| [
            strong("受托人模式"),
            span("尚未指定"),
          ],
          li <| [
            strong("安全降级"),
            span("尚未演练"),
          ],
        ],
      ],
      section(class="section-block") <| [
        div(class="section-heading") <| [
          div <| [
            h2("学习系统"),
            p(
              "保留失败、反例和失效程序，而不只保存成功路径。",
            ),
          ],
        ],
        div(
          class=if model.learning_ready {
            "empty-panel is-ready"
          } else {
            "empty-panel"
          },
        ) <| [
          strong(
            if model.learning_ready {
              "学习台账已启用"
            } else {
              "尚无复盘或程序记录"
            },
          ),
          p(
            "重复结果或独立评审后，工作方法才可以升级为标准程序。",
          ),
        ],
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("审计与事件"),
          p("每次重要状态变化都应留下不可变证据。"),
        ],
      ],
      empty_table(
        ["时间", "行为者", "代表主体", "事件", "证据", "结果"],
        "还没有审计事件",
        if model.control_ready {
          status_badge("空台账 · 等待正式记录", tone="muted")
        } else {
          secondary_button(emit, SetupControls, "建立控制台账")
        },
      ),
    ],
  ]
}

///|
fn integration_row(
  name : String,
  role : String,
  ownership : String,
  state : String,
  tone : String,
) -> @html.Html {
  tr <| [
    td <| [
      strong(name),
    ],
    td(role),
    td(ownership),
    td <| [
      status_badge(state, tone~),
    ],
  ]
}

///|
fn extensions_view(_emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Extensions, status_badge("基础版独立运行", tone="accent")),
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("可选智能能力"),
          p(
            "缺少任何 MoonSuite 兄弟产品都不会阻止公司正常运行或恢复。",
          ),
        ],
        status_badge("浅集成", tone="muted"),
      ],
      table(class="data-table") <| [
        thead <| [
          tr <| [
            th("产品"),
            th("可提供能力"),
            th("MoonProj 保留所有权"),
            th("状态"),
          ],
        ],
        tbody <| [
          integration_row(
            "MoonClaw", "有界研究、提取、分析与执行收据", "授权、预算、业务状态与接受",
            "可选", "accent",
          ),
          integration_row(
            "MoonBook", "知识和证据投影", "公司事实、义务与账簿",
            "未连接", "muted",
          ),
          integration_row(
            "MoonFlow", "工作进展和恢复收据", "业务完成与外部影响",
            "未连接", "muted",
          ),
          integration_row(
            "Moontown", "常驻观察和周期调度", "优先级、期限与公司决策",
            "未连接", "muted",
          ),
          integration_row(
            "MoonGate", "模型访问、成本与健康", "公司数据与业务规则",
            "未连接", "muted",
          ),
          integration_row(
            "Moonfish", "分析、风险与投资智能体", "已吸收为原生投资域",
            "迁移中", "warning",
          ),
        ],
      ],
    ],
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("行业扩展包"),
          p(
            "行业能力显式启用；基础版不会悄悄继承其字段或导航。",
          ),
        ],
        status_badge("1 个可用", tone="muted"),
      ],
      article(class="extension-card") <| [
        div(class="extension-main") <| [
          div(class="extension-title") <| [
            span(class="extension-mark", "RE"),
            div <| [
              strong("房地产开发 ERP"),
              small("real-estate-erp · erp_new"),
            ],
          ],
          p(
            "保留开发项目、CBS、目标与动态成本、招采、工程进度、认筹、按揭及完整设计师 UI。",
          ),
          div(class="tag-row") <| [
            status_badge("独立入口", tone="accent"),
            status_badge("56 个浏览器路由", tone="muted"),
            status_badge("功能等价未完成", tone="warning"),
          ],
        ],
        div(class="extension-actions") <| [
          strong("/extensions/real-estate"),
          small(
            "当前仍由独立开发服务启动，尚未合并到基础版导航。",
          ),
        ],
      ],
    ],
    div(class="boundary-note") <| [
      strong("边界原则"),
      p(
        "扩展可以依赖基础 OPC；基础 OPC 永远不能依赖扩展。智能体可以提出，只有公司规则可以接受并产生业务影响。",
      ),
    ],
  ]
}

