///|
using @html {
  a,
  article,
  button,
  div,
  form,
  h1,
  h2,
  h3,
  header,
  input,
  label,
  li,
  main_,
  nav,
  p,
  section,
  small,
  span,
  strong,
  table,
  tbody,
  td,
  th,
  thead,
  tr,
  ul,
}

///|
using @rabbita {cell, new, none, type Cmd}

///|
enum Page {
  Overview
  Company
  Market
  Delivery
  Commerce
  Finance
  Assurance
  Extensions
} derive(Debug, Eq)

///|
struct NavItem {
  page : Page
  label : String
  short_label : String
  description : String
}

///|
struct Model {
  page : Page
  mobile_nav : Bool
  company_form_open : Bool
  company_name : String
  company_saved : Bool
  market_form_open : Bool
  market_party : String
  market_problem : String
  market_saved : Bool
  work_form_open : Bool
  work_title : String
  work_acceptance : String
  work_saved : Bool
  commitment_form_open : Bool
  commitment_title : String
  commitment_counterparty : String
  commitment_saved : Bool
  ledger_ready : Bool
  continuity_ready : Bool
  notice : String
}

///|
enum Msg {
  Navigate(Page)
  ToggleMobileNav
  OpenCompanyForm
  InputCompanyName(String)
  SaveCompany
  OpenMarketForm
  InputMarketParty(String)
  InputMarketProblem(String)
  SaveMarket
  OpenWorkForm
  InputWorkTitle(String)
  InputWorkAcceptance(String)
  SaveWork
  OpenCommitmentForm
  InputCommitmentTitle(String)
  InputCommitmentCounterparty(String)
  SaveCommitment
  SetupLedger
  SetupContinuity
  DismissNotice
}

///|
fn initial_model() -> Model {
  {
    page: Overview,
    mobile_nav: false,
    company_form_open: false,
    company_name: "",
    company_saved: false,
    market_form_open: false,
    market_party: "",
    market_problem: "",
    market_saved: false,
    work_form_open: false,
    work_title: "",
    work_acceptance: "",
    work_saved: false,
    commitment_form_open: false,
    commitment_title: "",
    commitment_counterparty: "",
    commitment_saved: false,
    ledger_ready: false,
    continuity_ready: false,
    notice: "",
  }
}

///|
fn nav_items() -> Array[NavItem] {
  [
    {
      page: Overview,
      label: "经营总览",
      short_label: "总",
      description: "今天需要关注什么",
    },
    {
      page: Company,
      label: "公司与权利",
      short_label: "司",
      description: "主体、资源与授权",
    },
    {
      page: Market,
      label: "市场与客户",
      short_label: "客",
      description: "需求、报价与复购",
    },
    {
      page: Delivery,
      label: "工作与交付",
      short_label: "交",
      description: "计划、验收与质量",
    },
    {
      page: Commerce,
      label: "商务与交换",
      short_label: "商",
      description: "承诺、合同与结算",
    },
    {
      page: Finance,
      label: "财务与资本",
      short_label: "财",
      description: "账簿、现金、税与投资",
    },
    {
      page: Assurance,
      label: "治理与韧性",
      short_label: "治",
      description: "控制、学习与连续性",
    },
    {
      page: Extensions,
      label: "智能与扩展",
      short_label: "扩",
      description: "智能体与行业能力包",
    },
  ]
}

///|
fn page_path(page : Page) -> String {
  match page {
    Overview => "/overview"
    Company => "/company"
    Market => "/market"
    Delivery => "/delivery"
    Commerce => "/commerce"
    Finance => "/finance"
    Assurance => "/assurance"
    Extensions => "/extensions"
  }
}

///|
fn page_title(page : Page) -> String {
  match page {
    Overview => "经营总览"
    Company => "公司与权利"
    Market => "市场与客户"
    Delivery => "工作与交付"
    Commerce => "商务与交换"
    Finance => "财务与资本"
    Assurance => "治理与韧性"
    Extensions => "智能与扩展"
  }
}

///|
fn page_question(page : Page) -> String {
  match page {
    Overview => "公司今天需要你做出什么决定？"
    Company => "谁拥有资源，谁可以代表公司行动？"
    Market => "哪一个客户问题值得公司解决并获得回报？"
    Delivery => "公司承诺的结果如何被稳定交付和验收？"
    Commerce =>
      "公司已经做出哪些承诺，还需要完成哪些交换？"
    Finance => "公司能否看清现金、利润、税务和资本状态？"
    Assurance => "当人或系统不可用时，公司还能否安全继续？"
    Extensions => "哪些智能或行业能力值得被明确启用？"
  }
}

///|
fn setup_count(model : Model) -> Int {
  let mut count = 0
  if model.company_saved {
    count += 1
  }
  if model.market_saved {
    count += 1
  }
  if model.work_saved {
    count += 1
  }
  if model.commitment_saved {
    count += 1
  }
  if model.ledger_ready {
    count += 1
  }
  if model.continuity_ready {
    count += 1
  }
  count
}

///|
fn update(_emit : @rabbita.Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    Navigate(page) => (none, { ..model, page, mobile_nav: false, notice: "" })
    ToggleMobileNav => (none, { ..model, mobile_nav: !model.mobile_nav })
    OpenCompanyForm =>
      (
        none,
        { ..model, page: Company, company_form_open: true, mobile_nav: false },
      )
    InputCompanyName(value) => (none, { ..model, company_name: value })
    SaveCompany =>
      if model.company_name.trim().is_empty() {
        (none, { ..model, notice: "请先填写公司名称。" })
      } else {
        (
          none,
          {
            ..model,
            company_saved: true,
            company_form_open: false,
            notice: "公司档案已保存在当前界面会话中。连接 PostgreSQL 后才会成为正式记录。",
          },
        )
      }
    OpenMarketForm => (none, { ..model, market_form_open: true })
    InputMarketParty(value) => (none, { ..model, market_party: value })
    InputMarketProblem(value) => (none, { ..model, market_problem: value })
    SaveMarket =>
      if model.market_party.trim().is_empty() ||
        model.market_problem.trim().is_empty() {
        (
          none,
          {
            ..model,
            notice: "请填写客户或买方，以及需要验证的问题。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            market_saved: true,
            market_form_open: false,
            notice: "客户机会已加入当前界面会话，尚未产生合同或收入事实。",
          },
        )
      }
    OpenWorkForm => (none, { ..model, work_form_open: true })
    InputWorkTitle(value) => (none, { ..model, work_title: value })
    InputWorkAcceptance(value) => (none, { ..model, work_acceptance: value })
    SaveWork =>
      if model.work_title.trim().is_empty() ||
        model.work_acceptance.trim().is_empty() {
        (
          none,
          {
            ..model,
            notice: "工作项需要名称和可检查的验收标准。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            work_saved: true,
            work_form_open: false,
            notice: "工作项已加入当前界面会话，尚未授权智能体执行。",
          },
        )
      }
    OpenCommitmentForm => (none, { ..model, commitment_form_open: true })
    InputCommitmentTitle(value) => (none, { ..model, commitment_title: value })
    InputCommitmentCounterparty(value) =>
      (none, { ..model, commitment_counterparty: value })
    SaveCommitment =>
      if model.commitment_title.trim().is_empty() ||
        model.commitment_counterparty.trim().is_empty() {
        (none, { ..model, notice: "承诺需要事项和交易对手。" })
      } else {
        (
          none,
          {
            ..model,
            commitment_saved: true,
            commitment_form_open: false,
            notice: "承诺草案已加入当前界面会话，尚未签署或产生会计影响。",
          },
        )
      }
    SetupLedger =>
      (
        none,
        {
          ..model,
          ledger_ready: true,
          notice: "基础账簿界面已启用；正式科目、期间和期初余额仍需财务负责人确认。",
        },
      )
    SetupContinuity =>
      (
        none,
        {
          ..model,
          continuity_ready: true,
          notice: "连续性清单已启用；备份恢复和受托人演练仍需真实验证。",
        },
      )
    DismissNotice => (none, { ..model, notice: "" })
  }
}

///|
fn status_badge(label : String, tone? : String = "neutral") -> @html.Html {
  span(class="status-badge status-\{tone}", label)
}

///|
fn primary_button(
  emit : @rabbita.Emit[Msg],
  message : Msg,
  label : String,
) -> @html.Html {
  button(
    type_="button",
    class="button button-primary",
    on_click=emit(message),
    label,
  )
}

///|
fn secondary_button(
  emit : @rabbita.Emit[Msg],
  message : Msg,
  label : String,
) -> @html.Html {
  button(
    type_="button",
    class="button button-secondary",
    on_click=emit(message),
    label,
  )
}

///|
fn page_intro(page : Page, action : @html.Html) -> @html.Html {
  header(class="page-intro") <| [
    div(class="page-intro-copy") <| [
      p(class="page-kicker", "BASIC OPC · \{page_path(page)}"),
      h1(page_title(page)),
      p(class="page-question", page_question(page)),
    ],
    action,
  ]
}

///|
fn nav_item_view(
  emit : @rabbita.Emit[Msg],
  item : NavItem,
  active : Page,
) -> @html.Html {
  let selected = item.page == active
  let attrs = @html.Attrs::build()
    .aria_current(if selected { "page" } else { "false" })
    .aria_label("\{item.label}：\{item.description}")
  button(
    class=if selected { "nav-item is-active" } else { "nav-item" },
    attrs~,
    on_click=emit(Navigate(item.page)),
  ) <| [
    span(
      class="nav-mark",
      attrs=@html.Attrs::build().aria_hidden("true"),
      item.short_label,
    ),
    span(class="nav-copy") <| [
      strong(item.label),
      small(item.description),
    ],
  ]
}

///|
fn sidebar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let items : Array[@html.Html] = []
  for item in nav_items() {
    items.push(nav_item_view(emit, item, model.page))
  }
  div(class=if model.mobile_nav { "sidebar is-open" } else { "sidebar" }) <| [
    div(class="brand") <| [
      span(class="brand-mark", "M"),
      div(class="brand-copy") <| [
        strong("MoonProj"),
        small("Basic OPC"),
      ],
    ],
    div(class="workspace-identity") <| [
      p("公司工作区"),
      strong(
        if model.company_saved {
          model.company_name
        } else {
          "尚未命名"
        },
      ),
      span(
        if model.company_saved {
          "设置中"
        } else {
          "等待建立公司档案"
        },
      ),
    ],
    nav(
      class="primary-nav",
      attrs=@html.Attrs::build().aria_label("基础 OPC 主导航"),
    ) <| items,
    div(class="sidebar-foot") <| [
      span("本地优先"),
      status_badge("未连接数据", tone="muted"),
    ],
  ]
}

///|
fn topbar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  header(class="topbar") <| [
    button(
      class="mobile-menu",
      attrs=@html.Attrs::build().aria_label("打开主导航"),
      on_click=emit(ToggleMobileNav),
      "菜单",
    ),
    div(class="topbar-title") <| [
      small("MoonProj / 基础版"),
      strong(page_title(model.page)),
    ],
    div(class="topbar-state") <| [
      span("设置进度 \{setup_count(model)}/6"),
      status_badge("P0 · 建立安全运行", tone="accent"),
    ],
  ]
}

///|
fn notice_view(emit : @rabbita.Emit[Msg], notice : String) -> @html.Html {
  if notice.is_empty() {
    @html.nothing
  } else {
    div(class="notice", attrs=@html.Attrs::build().aria_label("操作结果")) <| [
      p(notice),
      button(
        class="notice-close",
        attrs=@html.Attrs::build().aria_label("关闭提示"),
        on_click=emit(DismissNotice),
        "关闭",
      ),
    ]
  }
}

///|
fn metric(label : String, value : String, note : String) -> @html.Html {
  article(class="metric") <| [
    p(label),
    strong(value),
    small(note),
  ]
}

///|
fn circuit_panel(
  title : String,
  flow : String,
  question : String,
  state : String,
) -> @html.Html {
  article(class="circuit-panel") <| [
    div(class="circuit-head") <| [
      h3(title),
      status_badge(state, tone="muted"),
    ],
    p(class="circuit-flow", flow),
    p(class="circuit-question", question),
  ]
}

///|
fn setup_row(
  label : String,
  description : String,
  complete : Bool,
  action : @html.Html,
) -> @html.Html {
  li(class=if complete { "setup-row is-complete" } else { "setup-row" }) <| [
    span(class="setup-state", if complete { "完成" } else { "待办" }),
    div(class="setup-copy") <| [
      strong(label),
      p(description),
    ],
    action,
  ]
}

///|
fn empty_table(
  headers : Array[String],
  message : String,
  action : @html.Html,
) -> @html.Html {
  let head : Array[@html.Html] = []
  for value in headers {
    head.push(th(value))
  }
  table(class="data-table") <| [
    thead <| [
      tr <| head,
    ],
    tbody <| [
      tr <| [
        td(class="empty-cell", colspan=headers.length()) <| [
          strong(message),
          p(
            "这里不会显示虚构数据。建立正式记录或连接 PostgreSQL 后，状态才会出现。",
          ),
          action,
        ],
      ],
    ],
  ]
}

///|
fn overview_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
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
  form(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("建立公司档案"),
  ) <| [
    div(class="form-heading") <| [
      div <| [
        h3("建立公司档案"),
        p(
          "此处只收集产品运行所需的最小身份，不预设行业或组织结构。",
        ),
      ],
      status_badge("界面会话", tone="muted"),
    ],
    div(class="field") <| [
      label("公司名称"),
      input(
        input_type=Text,
        value=model.company_name,
        placeholder="填写法定或经营名称",
        on_input=emit.map(value => InputCompanyName(value)),
      ),
      small("保存到 PostgreSQL 前，这不是正式主体记录。"),
    ],
    div(class="form-actions") <| [
      primary_button(emit, SaveCompany, "保存公司档案"),
    ],
  ]
}

///|
fn company_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
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
          status_badge("0 项授权", tone="muted"),
        ],
        empty_table(
          ["代表", "能力", "范围", "限制", "状态"],
          "还没有授权记录",
          secondary_button(emit, OpenCompanyForm, "先建立公司"),
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
        status_badge("0 项资源", tone="muted"),
      ],
      empty_table(
        ["资源", "类型", "所有者", "保管人", "可用状态"],
        "还没有登记公司资源",
        secondary_button(emit, OpenCompanyForm, "完成主体设置"),
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
        label("客户或买方"),
        input(
          input_type=Text,
          value=model.market_party,
          placeholder="组织或个人",
          on_input=emit.map(value => InputMarketParty(value)),
        ),
      ],
      div(class="field") <| [
        label("需要验证的问题"),
        input(
          input_type=Text,
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
        div(class="empty-panel") <| [
          strong("尚未定义报价"),
          p("验证客户问题后，再把可重复交付封装为报价。"),
        ],
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
        label("工作名称"),
        input(
          input_type=Text,
          value=model.work_title,
          placeholder="需要完成的结果",
          on_input=emit.map(value => InputWorkTitle(value)),
        ),
      ],
      div(class="field") <| [
        label("验收标准"),
        input(
          input_type=Text,
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
fn lane(title : String, count : Int, content : @html.Html) -> @html.Html {
  article(class="work-lane") <| [
    div(class="lane-heading") <| [
      strong(title),
      span(count.to_string()),
    ],
    content,
  ]
}

///|
fn delivery_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(Delivery, primary_button(emit, OpenWorkForm, "创建工作项")),
    if model.work_form_open {
      work_form(emit, model)
    } else {
      @html.nothing
    },
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
          if model.work_saved {
            1
          } else {
            0
          },
          if model.work_saved {
            article(class="work-card") <| [
              strong(model.work_title),
              p(model.work_acceptance),
              div(class="work-meta") <| [
                span("负责人未指定"),
                status_badge("待计划", tone="muted"),
              ],
            ]
          } else {
            div(class="lane-empty", "没有工作项")
          },
        ),
        lane(
          "进行中",
          0,
          div(class="lane-empty", "没有进行中的工作"),
        ),
        lane(
          "待验收",
          0,
          div(class="lane-empty", "没有等待验收的结果"),
        ),
        lane(
          "已接受",
          0,
          div(class="lane-empty", "没有已接受的交付"),
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
        div(class="empty-panel") <| [
          strong("尚未记录干预时间"),
          p(
            "开始运行后记录审批、例外、返工和上下文重建时间。",
          ),
        ],
      ],
    ],
  ]
}

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
        label("承诺事项"),
        input(
          input_type=Text,
          value=model.commitment_title,
          placeholder="公司承诺提供或获得什么？",
          on_input=emit.map(value => InputCommitmentTitle(value)),
        ),
      ],
      div(class="field") <| [
        label("交易对手"),
        input(
          input_type=Text,
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
    div(class="state-rail") <| [
      div(class="is-current") <| [
        span("1"),
        strong("提出"),
      ],
      div <| [
        span("2"),
        strong("批准"),
      ],
      div <| [
        span("3"),
        strong("签署"),
      ],
      div <| [
        span("4"),
        strong("履约"),
      ],
      div <| [
        span("5"),
        strong("结算"),
      ],
      div <| [
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
            ],
          ],
          tbody <| [
            tr <| [
              td(model.commitment_title),
              td(model.commitment_counterparty),
              td <| [
                status_badge("草案", tone="warning"),
              ],
              td("未发生"),
              td("未确认"),
            ],
          ],
        ]
      } else {
        empty_table(
          ["事项", "交易对手", "业务状态", "资金", "会计"],
          "还没有公司承诺",
          primary_button(emit, OpenCommitmentForm, "登记第一份草案"),
        )
      },
    ],
    div(class="three-column") <| [
      article(class="compact-panel") <| [
        h3("采购"),
        p("供应商、报价、选择、合同与接受。"),
        status_badge("未启用", tone="muted"),
      ],
      article(class="compact-panel") <| [
        h3("销售"),
        p("报价、订单、履约、开票与收款。"),
        status_badge("未启用", tone="muted"),
      ],
      article(class="compact-panel") <| [
        h3("争议与变化"),
        p("修订、取消、退款和责任记录。"),
        status_badge("未启用", tone="muted"),
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
          "法人账簿",
          "本位币、会计政策、科目和期间。",
          model.ledger_ready,
          secondary_button(emit, SetupLedger, "设置"),
        ),
        setup_row(
          "银行与现金",
          "账户、流水、匹配和付款边界。",
          false,
          status_badge("待设置", tone="muted"),
        ),
        setup_row(
          "税务档案",
          "税种、申报证据、支付和对账。",
          false,
          status_badge("待设置", tone="muted"),
        ),
        setup_row(
          "融资与投资",
          "额度、资本、授权、仓位与绩效。",
          false,
          status_badge("待设置", tone="muted"),
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
        status_badge("原生域", tone="accent"),
      ],
      empty_table(
        ["投资授权", "建议", "持仓", "估值", "风险状态"],
        "还没有投资授权或持仓",
        status_badge("无交易权限", tone="muted"),
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
    section(class="section-block") <| [
      div(class="section-heading") <| [
        div <| [
          h2("决策权与人工闸门"),
          p(
            "提出、执行、批准和对账不能全部由同一角色完成。",
          ),
        ],
        status_badge("默认拒绝", tone="accent"),
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
        div(class="empty-panel") <| [
          strong("尚无复盘或程序记录"),
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
        status_badge("等待正式记录", tone="muted"),
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

///|
fn page_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  match model.page {
    Overview => overview_view(emit, model)
    Company => company_view(emit, model)
    Market => market_view(emit, model)
    Delivery => delivery_view(emit, model)
    Commerce => commerce_view(emit, model)
    Finance => finance_view(emit, model)
    Assurance => assurance_view(emit, model)
    Extensions => extensions_view(emit, model)
  }
}

///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  div(class="opc-app") <| [
    a(href="#main-content", class="skip-link", "跳到主要内容"),
    if model.mobile_nav {
      button(
        class="nav-scrim",
        attrs=@html.Attrs::build().aria_label("关闭主导航"),
        on_click=emit(ToggleMobileNav),
        "",
      )
    } else {
      @html.nothing
    },
    sidebar(emit, model),
    div(class="app-shell") <| [
      topbar(emit, model),
      main_(class="main-content", attrs=@html.Attrs::build().id("main-content")) <| [
        notice_view(emit, model.notice),
        page_view(emit, model),
      ],
    ],
  ]
}

///|
fn main {
  let app = cell(model=initial_model(), update~, view~)
  new(app).mount("app")
}
