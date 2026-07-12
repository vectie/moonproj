///|
using @html {
  aside,
  button,
  div,
  form,
  h1,
  h2,
  header,
  input,
  label,
  li,
  main_,
  nav,
  p,
  section,
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
using @rabbita {new, simple_cell}

///|
struct Model {
  authenticated : Bool
  page : String
  collapsed : Bool
  mobile_nav : Bool
  open_group : String?
  show_demo : Bool
  user_code : String
  password : String
}

///|
enum Msg {
  Login
  ToggleDemo
  FillDemo(String, String)
  InputUser(String)
  InputPassword(String)
  Navigate(String)
  ToggleSidebar
  ToggleMobileNav
  ToggleGroup(String)
}

///|
fn initial_model() -> Model {
  {
    authenticated: false,
    page: "/login",
    collapsed: false,
    mobile_nav: false,
    open_group: None,
    show_demo: false,
    user_code: "",
    password: "",
  }
}

///|
fn title_for(path : String) -> String {
  match path {
    "/dashboard" => "集团驾驶舱"
    "/ai-hub" => "AI 工作台"
    "/ai-stats" => "AI 工作大盘"
    "/projects" => "项目主数据"
    "/project-plan" => "项目计划"
    "/project/progress" => "工程进度"
    "/tasks" => "我的待办"
    "/sales/customers" => "客户档案"
    "/sales/subscriptions" => "认筹登记"
    "/sales/contracts" => "签约管理"
    "/sales/mortgages" => "按揭办理"
    "/sales/revenues" => "销售回款 (R6)"
    "/marketing" => "营销管理"
    "/cost-dashboard-v3" => "成本驾驶舱"
    "/investment" => "投资收益"
    "/contracts" => "合同台帐"
    "/payment-applies" => "付款申请"
    "/dynamic-cost" => "动态成本"
    "/tender" => "合约规划"
    "/srm/providers" => "供应商库"
    "/srm/risk-board" => "供应商风险面板"
    "/cbs/dict" => "CBS 字典"
    "/cbs/versions" => "目标版本管理"
    "/cbs/r0-queue" => "R0 待归类"
    "/cbs/approval-config" => "审批配置"
    "/fund/plan" => "资金计划"
    "/invoice" => "发票管理"
    "/expenses" => "我的报销"
    "/loans" => "我的借款"
    "/reports" => "报表中心"
    "/report-builder" => "自定义报表"
    "/warning" => "异常预警中心"
    "/inbox" => "站内信"
    "/attachments" => "附件中心"
    "/notify-config" => "通知配置 / 订阅"
    "/audit-log" => "审计日志"
    "/error-log" => "错误日志"
    "/system-health" => "系统健康"
    "/users" => "用户/角色管理"
    "/admin" => "数据后台"
    "/ocr-config" => "OCR 配置"
    "/webhook-config" => "Webhook 三平台"
    _ => "项目全周期管理"
  }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  match msg {
    Login =>
      { ..model, authenticated: true, page: "/dashboard", mobile_nav: false }
    ToggleDemo => { ..model, show_demo: !model.show_demo }
    FillDemo(user_code, password) =>
      { ..model, user_code, password, show_demo: false }
    InputUser(value) => { ..model, user_code: value }
    InputPassword(value) => { ..model, password: value }
    Navigate(path) =>
      { ..model, authenticated: true, page: path, mobile_nav: false }
    ToggleSidebar => { ..model, collapsed: !model.collapsed }
    ToggleMobileNav => { ..model, mobile_nav: !model.mobile_nav }
    ToggleGroup(group) => {
      let open_group = match model.open_group {
        Some(current) if current == group => None
        _ => Some(group)
      }
      { ..model, open_group, }
    }
  }
}

///|
fn icon(label : String) -> @html.Html {
  span(class="menu-icon", attrs=@html.Attrs::build().aria_hidden("true"), label)
}

///|
fn menu_leaf(
  emit : @rabbita.Emit[Msg],
  path : String,
  label : String,
  glyph : String,
  active : String,
  collapsed : Bool,
) -> @html.Html {
  let selected = path == active
  let class_name = if selected {
    "erp-menu-item is-active"
  } else {
    "erp-menu-item"
  }
  let attrs = @html.Attrs::build().aria_current(
    if selected {
      "page"
    } else {
      "false"
    },
  )
  let children : Array[@html.Html] = [icon(glyph)]
  if !collapsed {
    children.push(span(class="menu-text", label))
  }
  button(class=class_name, attrs~, on_click=emit(Navigate(path))) <| children
}

///|
fn menu_group(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  model : Model,
) -> @html.Html {
  let expanded = model.open_group == Some(group)
  let class_name = if expanded {
    "erp-menu-group is-open"
  } else {
    "erp-menu-group"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  if !model.collapsed {
    title_children.push(span(class="menu-text", label))
    title_children.push(
      span(class="menu-caret", if expanded { "⌄" } else { "›" }),
    )
  }
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded && !model.collapsed {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn nested_menu_group(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  model : Model,
) -> @html.Html {
  let expanded = model.open_group == Some(group)
  let class_name = if expanded {
    "erp-menu-group erp-nested is-open"
  } else {
    "erp-menu-group erp-nested"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  title_children.push(span(class="menu-text", label))
  title_children.push(
    span(class="menu-caret", if expanded { "⌄" } else { "›" }),
  )
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn menu_group_with_nested(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  nested : Array[(String, String, String, Array[(String, String)])],
  model : Model,
) -> @html.Html {
  let mut nested_open = false
  match model.open_group {
    Some(current) =>
      for entry in nested {
        if entry.0 == current {
          nested_open = true
        }
      }
    None => ()
  }
  let expanded = model.open_group == Some(group) || nested_open
  let class_name = if expanded {
    "erp-menu-group is-open"
  } else {
    "erp-menu-group"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  if !model.collapsed {
    title_children.push(span(class="menu-text", label))
    title_children.push(
      span(class="menu-caret", if expanded { "⌄" } else { "›" }),
    )
  }
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded && !model.collapsed {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
    for entry in nested {
      children.push(
        nested_menu_group(emit, entry.0, entry.1, entry.2, entry.3, model),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn sidebar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let class_name = if model.collapsed {
    if model.mobile_nav {
      "erp-sidebar is-collapsed is-mobile-open"
    } else {
      "erp-sidebar is-collapsed"
    }
  } else if model.mobile_nav {
    "erp-sidebar is-mobile-open"
  } else {
    "erp-sidebar"
  }
  aside(class=class_name) <| [
    div(class="erp-brand") <| [
      span(class="erp-logo", "ERP"),
      if model.collapsed {
        @html.nothing
      } else {
        strong(class="erp-brand-text", "项目全周期管理")
      },
    ],
    nav(
      class="erp-navigation",
      attrs=@html.Attrs::build().aria_label("ERP主导航"),
    ) <| [
      menu_leaf(
        emit,
        "/dashboard",
        "AI 驾驶舱",
        "▣",
        model.page,
        model.collapsed,
      ),
      menu_leaf(
        emit,
        "/ai-hub",
        "AI 工作台",
        "✦",
        model.page,
        model.collapsed,
      ),
      menu_leaf(
        emit,
        "/ai-stats",
        "AI 工作大盘",
        "⌁",
        model.page,
        model.collapsed,
      ),
      menu_group(
        emit,
        "project",
        "项目管理",
        "▥",
        [
          ("/projects", "项目主数据"),
          ("/project-plan", "项目计划"),
          ("/project/progress", "工程进度"),
          ("/tasks", "我的待办"),
        ],
        model,
      ),
      menu_group(
        emit,
        "sales",
        "销售管理",
        "¥",
        [
          ("/sales/customers", "客户档案"),
          ("/sales/subscriptions", "认筹登记"),
          ("/sales/contracts", "签约管理"),
          ("/sales/mortgages", "按揭办理"),
          ("/sales/revenues", "销售回款 (R6)"),
          ("/marketing", "营销管理"),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "cost",
        "成本管理",
        "▤",
        [
          ("/cost-dashboard-v3", "成本驾驶舱"),
          ("/investment", "投资收益"),
          ("/contracts", "合同台帐"),
          ("/payment-applies", "付款申请"),
          ("/dynamic-cost", "动态成本"),
          ("/tender", "合约规划"),
        ],
        [
          (
            "cost-srm",
            "供应商管理",
            "↔",
            [
              ("/srm/providers", "供应商库"),
              ("/srm/risk-board", "风险面板"),
            ],
          ),
          (
            "cost-cbs",
            "科目主数据",
            "▧",
            [
              ("/cbs/dict", "CBS 字典"),
              ("/cbs/versions", "目标版本"),
              ("/cbs/r0-queue", "R0 待归类"),
              ("/cbs/approval-config", "审批配置"),
            ],
          ),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "finance",
        "财务管理",
        "▣",
        [("/fund/plan", "资金计划"), ("/invoice", "发票管理")],
        [
          (
            "finance-budget",
            "费用预算",
            "¥",
            [("/expenses", "我的报销"), ("/loans", "我的借款")],
          ),
        ],
        model,
      ),
      menu_group(
        emit,
        "analysis",
        "分析中心",
        "▦",
        [
          ("/reports", "报表中心"),
          ("/report-builder", "自定义报表"),
          ("/warning", "异常预警"),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "system",
        "系统管理",
        "⚙",
        [
          ("/inbox", "站内信"),
          ("/attachments", "附件中心"),
          ("/notify-config", "通知配置"),
        ],
        [
          (
            "system-advanced",
            "高级配置",
            "⚙",
            [
              ("/audit-log", "审计日志"),
              ("/error-log", "错误日志"),
              ("/system-health", "系统健康"),
              ("/users", "用户/角色"),
              ("/admin", "数据后台"),
              ("/ocr-config", "OCR 配置"),
              ("/webhook-config", "Webhook 三平台"),
            ],
          ),
        ],
        model,
      ),
    ],
  ]
}

///|
fn login_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  div(class="erp-login") <| [
    div(class="login-blob login-blob-one", @html.nothing),
    div(class="login-blob login-blob-two", @html.nothing),
    div(class="login-blob login-blob-three", @html.nothing),
    div(class="login-brand-side") <| [
      span(class="login-logo-big", "ERP"),
      h1("和泓置地 · ERP"),
      p(class="login-subtitle", "智能项目全周期管理平台"),
      ul(class="login-features") <| [
        li("AI 起单 — 拖文件自动识别 8 类业务"),
        li("AI 查询 — 大白话问出 SQL 报表"),
        li("现金流预测 — 实际 vs 计划 + 流入流出"),
        li("异常预警 — 12 内置规则 + 自定义 DSL"),
        li("BPM 工作流 — 报销/借款/付款全栈审批"),
      ],
      span(class="login-time", "2026.07.13 周一 09:40:00"),
    ],
    div(class="login-card") <| [
      div(class="login-card-heading") <| [
        h2("登录"),
        span("v1.4.0 项目全周期 + AI 工作台"),
      ],
      form(attrs=@html.Attrs::build().on_submit(_ => emit(Login))) <| [
        label(class="login-label", "账号"),
        input(
          input_type=@html.InputType::Text,
          value=model.user_code,
          placeholder="用户编码",
          autofocus=true,
          class="login-input",
          on_input=emit.map(value => InputUser(value)),
        ),
        label(class="login-label", "密码"),
        input(
          input_type=@html.InputType::Password,
          value=model.password,
          placeholder="密码",
          class="login-input",
          on_input=emit.map(value => InputPassword(value)),
        ),
        button(
          class="login-submit",
          type_="button",
          on_click=emit(Login),
          "登录",
        ),
      ],
      button(
        class="demo-toggle",
        on_click=emit(ToggleDemo),
        if model.show_demo {
          "收起测试账号"
        } else {
          "展开测试账号"
        },
      ),
      if model.show_demo {
        div(class="demo-list") <| [
          demo_row(emit, "admin", "admin123", "超级管理员"),
          demo_row(emit, "chengyuzhe", "123456", "报销发起人"),
          demo_row(emit, "tianguanglei", "123456", "费用使用人"),
          demo_row(emit, "limingjin", "123456", "部门负责人"),
          demo_row(emit, "liusong", "123456", "综管负责人"),
        ]
      } else {
        @html.nothing
      },
    ],
  ]
}

///|
fn demo_row(
  emit : @rabbita.Emit[Msg],
  user_code : String,
  password : String,
  role : String,
) -> @html.Html {
  button(class="demo-row", on_click=emit(FillDemo(user_code, password))) <| [
    strong(user_code),
    span("/ \{password}"),
    span(class="demo-role", role),
  ]
}

///|
fn metric(
  label : String,
  value : String,
  detail : String,
  class_name : String,
) -> @html.Html {
  section(class="erp-metric \{class_name}") <| [
    span(class="erp-metric-label", label),
    strong(class="erp-metric-value", value),
    span(class="erp-metric-detail", detail),
  ]
}

///|
fn phase_row(label : String, value : String, width : String) -> @html.Html {
  div(class="phase-row") <| [
    span(class="phase-label", label),
    span(class="phase-bar", style=["width: \{width}"]) <| [
      span(class="phase-value", value),
    ],
  ]
}

///|
fn risk_row(
  project : String,
  company : String,
  risk : String,
  description : String,
) -> @html.Html {
  tr <| [
    td(project),
    td(company),
    td <| [
      span(class="risk-tag", risk),
    ],
    td(description),
  ]
}

///|
fn dashboard_view() -> @html.Html {
  div(class="erp-dashboard") <| [
    div(class="erp-kpi-grid") <| [
      metric("在管公司 / 项目", "5 / 15", "在建 15 个", "metric-blue"),
      metric(
        "累计合同额", "¥1,256,837,036", "62 笔合同", "metric-blue",
      ),
      metric("付款执行率", "10.98%", "已付 ¥137,953,340", "metric-blue"),
      metric(
        "成本偏差率", "+6.20%", "动态 ¥645,285,566", "metric-green",
      ),
    ],
    div(class="erp-alert-pill", "⚠ 2 个任务延期"),
    div(class="erp-dashboard-grid") <| [
      section(class="erp-panel") <| [
        div(class="erp-panel-heading") <| [
          h2("项目阶段漏斗"),
          span(class="erp-info-tag", "RFC §13.1 — 全周期 7 阶段"),
        ],
        div(class="phase-list") <| [
          phase_row("立项", "15", "100%"),
          phase_row("获取", "15", "100%"),
          phase_row("规划设计", "14", "93%"),
          phase_row("开发建设", "9", "60%"),
          phase_row("销售去化", "3", "20%"),
          phase_row("竣工交付", "1", "7%"),
          phase_row("结算清盘", "0", "7%"),
        ],
      ],
      section(class="erp-panel risk-panel") <| [
        div(class="erp-panel-heading") <| [
          h2("TOP 风险项目"),
          span(class="erp-danger-tag", "AI 异常洞察(规则版)"),
        ],
        table <| [
          thead <| [
            tr <| [
              th("项目"),
              th("公司"),
              th("风险"),
              th("说明"),
            ],
          ],
          tbody <| [
            risk_row(
              "成都和锦里", "成都公司", "20", "1 个任务延期",
            ),
            risk_row(
              "重庆南山居", "重庆公司", "20", "1 个任务延期",
            ),
            risk_row(
              "沈阳和山苑", "沈阳公司", "14", "成本超目标 1.40%",
            ),
            risk_row(
              "天津海教园一期", "天津公司", "13", "成本超目标 1.25%",
            ),
            risk_row(
              "天津梅江湾三期", "天津公司", "11", "成本超目标 1.14%",
            ),
          ],
        ],
      ],
    ],
    p(
      class="erp-dashboard-note",
      "数据已接入真实合同/付款/成本/进度; TOP 异常项目按 AI 规则评分排序(成本偏差权重 10、任务延期权重 20); 未来 Phase 10 接入真 AI(S12 场景 8)做 30 天前预测",
    ),
  ]
}

///|
fn placeholder_view(path : String) -> @html.Html {
  let title = title_for(path)
  section(class="erp-placeholder") <| [
    h2(title),
    span(class="erp-info-tag", "ERP 页面迁移中"),
    p(
      "此页面已保留 erp_new 的导航、标题和内容边界；下一步将按原页面逐页迁移到 Rabbita，并把读取/写入接到公司域与 PostgreSQL 投影。",
    ),
    table <| [
      thead <| [
        tr <| [
          th("字段"),
          th("状态"),
          th("目标"),
        ],
      ],
      tbody <| [
        tr <| [
          td("页面结构"),
          td("已挂载"),
          td("Rabbita"),
        ],
        tr <| [
          td("数据读取"),
          td("待接入"),
          td("PostgreSQL 投影"),
        ],
        tr <| [
          td("业务写入"),
          td("待授权"),
          td("公司域命令"),
        ],
      ],
    ],
  ]
}

///|
fn header_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  header(class="erp-header") <| [
    button(
      class="erp-toggle",
      on_click=emit(ToggleSidebar),
      attrs=@html.Attrs::build().aria_label("折叠侧栏"),
      if model.collapsed {
        "☰"
      } else {
        "⌂"
      },
    ),
    button(
      class="erp-mobile-toggle",
      on_click=emit(ToggleMobileNav),
      attrs=@html.Attrs::build().aria_label("打开导航"),
      "☰",
    ),
    strong(class="erp-header-title", title_for(model.page)),
    div(class="erp-header-actions") <| [
      button(
        class="erp-header-icon",
        attrs=@html.Attrs::build().aria_label("最近访问"),
        "◷",
      ),
      button(
        class="erp-header-icon has-badge",
        attrs=@html.Attrs::build().aria_label("异常预警"),
        "♧",
      ),
      button(class="erp-user-area", "♙  Giant Claw  ·  超级用户"),
    ],
  ]
}

///|
fn app_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let body = if model.page == "/dashboard" {
    dashboard_view()
  } else {
    placeholder_view(model.page)
  }
  div(class="erp-layout") <| [
    if model.mobile_nav {
      div(class="erp-mobile-overlay", on_click=emit(ToggleMobileNav), "")
    } else {
      @html.nothing
    },
    sidebar(emit, model),
    main_(class="erp-main-shell") <| [
      header_view(emit, model),
      div(class="erp-main") <| [
        body,
      ],
    ],
  ]
}

///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.authenticated {
    app_view(emit, model)
  } else {
    login_view(emit, model)
  }
}

///|
fn main {
  let app = simple_cell(model=initial_model(), update~, view~)
  new(app).mount("app")
}
