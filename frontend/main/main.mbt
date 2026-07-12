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
    "/warning-rules" => "告警规则 DSL"
    "/cashflow" => "现金流预测"
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
    "/profile" => "个人中心"
    "/share" => "分享报表"
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
fn table_header(headers : Array[String]) -> @html.Html {
  let cells : Array[@html.Html] = []
  for header in headers {
    cells.push(th(header))
  }
  tr <| cells
}

///|
fn table_row(cells : Array[String]) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for cell in cells {
    rendered.push(td(cell))
  }
  tr <| rendered
}

///|
fn data_table(
  headers : Array[String],
  rows : Array[Array[String]],
) -> @html.Html {
  let rendered_rows : Array[@html.Html] = []
  for row in rows {
    rendered_rows.push(table_row(row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header(headers),
    ],
    tbody <| rendered_rows,
  ]
}

///|
fn filter_bar(placeholder : String) -> @html.Html {
  div(class="erp-filter-bar") <| [
    input(
      input_type=@html.InputType::Text,
      placeholder~,
      class="erp-filter-input",
    ),
    button(class="erp-secondary-btn", "筛选"),
    button(class="erp-ghost-btn", "重置"),
  ]
}

///|
fn page_shell(
  title : String,
  eyebrow : String,
  description : String,
  actions : Array[@html.Html],
  body : @html.Html,
) -> @html.Html {
  section(class="erp-page-shell") <| [
    div(class="erp-page-heading") <| [
      div <| [
        span(class="erp-page-eyebrow", eyebrow),
        h1(title),
        p(description),
      ],
      div(class="erp-page-actions") <| actions,
    ],
    body,
  ]
}

///|
fn table_panel(
  title : String,
  subtitle : String,
  content : @html.Html,
) -> @html.Html {
  section(class="erp-table-panel") <| [
    div(class="erp-panel-heading") <| [
      div <| [
        h2(title),
        span(class="erp-panel-subtitle", subtitle),
      ],
    ],
    content,
  ]
}

///|
fn project_view() -> @html.Html {
  page_shell(
    "项目主数据",
    "PROJECTS",
    "维护集团项目、所属公司与项目阶段，作为成本、合同、销售与资金业务的共同主数据。",
    [button(class="erp-primary-btn", "＋ 新建项目")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("项目总数", "15", "在建项目", "metric-blue"),
        metric("本月新增", "2", "较上月 +1", "metric-blue"),
        metric("建设中", "9", "占比 60%", "metric-green"),
      ],
      filter_bar("项目编码 / 项目名称 / 所属公司"),
      table_panel(
        "项目列表",
        "共 15 个项目",
        data_table(
          [
            "项目编码", "项目名称", "所属公司", "当前阶段", "开始日期",
            "操作",
          ],
          [
            [
              "CD-HJL", "成都和锦里", "成都公司", "开发建设", "2024-03-18",
              "查看 / 编辑",
            ],
            [
              "CQ-NSJ", "重庆南山居", "重庆公司", "销售去化", "2023-09-01",
              "查看 / 编辑",
            ],
            [
              "SY-HSY", "沈阳和山苑", "沈阳公司", "规划设计", "2025-01-12",
              "查看 / 编辑",
            ],
            [
              "TJ-HJY", "天津海教园一期", "天津公司", "开发建设",
              "2024-06-20", "查看 / 编辑",
            ],
            [
              "TJ-MJW", "天津梅江湾三期", "天津公司", "获取", "2025-04-08",
              "查看 / 编辑",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn project_plan_view() -> @html.Html {
  page_shell(
    "项目计划",
    "PROJECT PLAN",
    "按项目阶段查看里程碑、计划工期与责任人，支持项目经理持续更新计划状态。",
    [button(class="erp-primary-btn", "＋ 新建计划")],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "计划总览"),
        button(class="erp-tab", "甘特图"),
        button(class="erp-tab", "里程碑"),
      ],
      table_panel(
        "计划任务",
        "成都和锦里 · 2026 年度",
        data_table(
          [
            "任务名称", "阶段", "责任人", "计划开始", "计划完成",
            "完成度", "状态",
          ],
          [
            [
              "方案设计审查", "规划设计", "王工", "2026-02-01", "2026-02-18",
              "100%", "已完成",
            ],
            [
              "施工图审查", "开发建设", "李工", "2026-02-20", "2026-03-28",
              "76%", "进行中",
            ],
            [
              "主体结构封顶", "开发建设", "陈工", "2026-04-01", "2026-07-15",
              "38%", "进行中",
            ],
            [
              "首批房源开盘", "销售去化", "销售部", "2026-08-01", "2026-08-20",
              "0%", "待处理",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn progress_view() -> @html.Html {
  page_shell(
    "工程进度",
    "PROJECT PROGRESS",
    "对照计划日期与实际完成率跟踪楼栋、施工阶段和交付节点。",
    [
      button(class="erp-secondary-btn", "导出进度表"),
      button(class="erp-primary-btn", "＋ 更新进度"),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "进度总览"),
        button(class="erp-tab", "楼栋视图"),
        button(class="erp-tab", "交付节点"),
      ],
      table_panel(
        "楼栋进度",
        "截至 2026-07-13",
        data_table(
          [
            "楼栋", "阶段", "计划日期", "实际日期", "计划完成%",
            "实际完成%", "状态", "备注",
          ],
          [
            [
              "1#", "主体结构", "2026-06-30", "2026-06-28", "100%", "100%", "已完成",
              "",
            ],
            [
              "2#", "砌体工程", "2026-07-10", "", "82%", "76%", "进行中",
              "较计划晚 4 天",
            ],
            [
              "3#", "基础施工", "2026-07-25", "", "54%", "49%", "进行中",
              "材料已到场",
            ],
            [
              "5#", "桩基工程", "2026-06-18", "", "100%", "91%", "逾期", "需增加班组",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn tasks_view() -> @html.Html {
  page_shell(
    "我的待办",
    "WORKFLOW",
    "集中处理报销、借款、付款申请与项目协同任务，查看发起记录和审批历史。",
    [button(class="erp-primary-btn", "＋ 发起流程")],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "待办 (8)"),
        button(class="erp-tab", "已发起"),
        button(class="erp-tab", "审批历史"),
        button(class="erp-tab", "告警任务"),
      ],
      table_panel(
        "待办事项",
        "按优先级排序",
        data_table(
          [
            "事项", "类型", "发起人", "提交时间", "金额", "优先级",
            "操作",
          ],
          [
            [
              "成都和锦里 · 工程款付款申请", "付款审批", "陈志强",
              "今天 09:18", "¥1,280,000", "高", "处理",
            ],
            [
              "2026-07 差旅费用报销", "费用审批", "程玉哲", "昨天 16:42",
              "¥8,560", "中", "处理",
            ],
            [
              "南山居营销推广合同", "合同审批", "刘松", "2026-07-11",
              "¥360,000", "中", "处理",
            ],
            [
              "项目节点延期确认", "项目协同", "系统", "2026-07-10",
              "—", "高", "查看",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn ai_hub_view() -> @html.Html {
  page_shell(
    "AI 工作台",
    "AI HUB",
    "把文件、自然语言问题和业务动作放进同一个工作台，AI 结果仍需业务人员确认后写入。",
    [button(class="erp-primary-btn", "＋ 上传文件")],
    div <| [
      div(class="erp-ai-grid") <| [
        section(class="erp-ai-card is-primary") <| [
          span(class="erp-ai-icon", "✦"),
          h2("AI 起单"),
          p(
            "拖入合同、发票或付款资料，自动识别业务类型并生成草稿。",
          ),
          button(class="erp-secondary-btn", "开始识别"),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⌁"),
          h2("AI 查询"),
          p(
            "用大白话查询项目、合同、成本和现金流，结果可追溯。",
          ),
          button(class="erp-secondary-btn", "打开查询"),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⚑"),
          h2("风险洞察"),
          p("基于延期、成本偏差和付款异常生成风险清单。"),
          button(class="erp-secondary-btn", "查看风险"),
        ],
      ],
      table_panel(
        "最近 AI 任务",
        "所有结果保留审计记录",
        data_table(["任务", "输入", "结果", "创建时间", "状态"], [
          [
            "合同要素识别", "南山居施工合同.pdf", "识别 32 个字段",
            "今天 09:12", "已完成",
          ],
          [
            "现金流问答", "未来 90 天资金缺口？", "预计峰值 ¥2,180 万",
            "昨天 17:06", "已完成",
          ],
          [
            "发票 OCR", "invoice_20260712.jpg", "待确认 1 个税号", "昨天 15:44",
            "待处理",
          ],
        ]),
      ),
    ],
  )
}

///|
fn ai_stats_view() -> @html.Html {
  page_shell(
    "AI 工作大盘",
    "AI ANALYTICS",
    "查看 AI 起单、查询、风险洞察的调用量、准确率和人工确认情况。",
    [button(class="erp-secondary-btn", "导出数据")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月调用", "1,286", "较上月 +18.4%", "metric-blue"),
        metric("自动通过率", "86.2%", "目标 85%", "metric-green"),
        metric(
          "节省人工", "214 小时", "按确认记录估算", "metric-blue",
        ),
        metric("待确认", "23", "需要业务复核", "metric-blue"),
      ],
      table_panel(
        "场景使用情况",
        "2026 年 7 月",
        data_table(
          [
            "场景", "调用次数", "自动通过", "平均耗时", "准确率",
            "趋势",
          ],
          [
            ["合同要素识别", "482", "418", "4.8s", "92.1%", "↑"],
            ["发票 OCR", "396", "324", "2.1s", "88.4%", "↑"],
            ["自然语言查询", "285", "—", "1.7s", "96.3%", "↑"],
            ["风险洞察", "123", "98", "6.2s", "79.7%", "→"],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_customers_view() -> @html.Html {
  page_shell(
    "客户档案",
    "SALES / CUSTOMERS",
    "维护客户、联系方式、认筹意向与跟进状态，贯通认筹、签约和回款。",
    [button(class="erp-primary-btn", "＋ 新增客户")],
    div <| [
      filter_bar("客户姓名 / 手机号 / 客户编号"),
      table_panel(
        "客户列表",
        "共 1,248 位客户",
        data_table(
          [
            "客户编号", "客户姓名", "手机号", "意向项目", "意向房源",
            "跟进状态", "最近联系",
          ],
          [
            [
              "CUS-20260701", "王晓峰", "138****6210", "成都和锦里", "2#-1802",
              "重点跟进", "今天",
            ],
            [
              "CUS-20260688", "赵文静", "186****4302", "重庆南山居", "5#-2101",
              "已认筹", "昨天",
            ],
            [
              "CUS-20260642", "李海涛", "139****0791", "沈阳和山苑", "—",
              "待回访", "2026-07-11",
            ],
            [
              "CUS-20260596", "陈敏", "158****9920", "天津海教园一期", "3#-901",
              "已签约", "2026-07-08",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_subscriptions_view() -> @html.Html {
  page_shell(
    "认筹登记",
    "SALES / SUBSCRIPTIONS",
    "登记认筹客户、房号、认筹金与转签状态，支持从客户档案快速发起签约。",
    [button(class="erp-primary-btn", "＋ 新建认筹")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月认筹", "86", "认筹金 ¥516 万", "metric-blue"),
        metric("待转签", "24", "近 7 日新增 6", "metric-blue"),
        metric("转签率", "71.4%", "较上月 +4.2%", "metric-green"),
      ],
      filter_bar("认筹号 / 客户 / 房号"),
      table_panel(
        "认筹记录",
        "共 386 条",
        data_table(
          [
            "认筹号", "客户", "电话", "房号", "面积㎡", "单价(元/㎡)",
            "总价(元)", "认筹金", "认筹日", "状态",
          ],
          [
            [
              "RC-260713-001", "王晓峰", "138****6210", "2#-1802", "128.60", "18,600",
              "2,391,960", "60,000", "2026-07-13", "待转签",
            ],
            [
              "RC-260712-009", "赵文静", "186****4302", "5#-2101", "96.40", "16,800",
              "1,619,520", "50,000", "2026-07-12", "已认筹",
            ],
            [
              "RC-260711-014", "陈敏", "158****9920", "3#-901", "89.20", "22,100",
              "1,971,320", "80,000", "2026-07-11", "已转签",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_contracts_view() -> @html.Html {
  page_shell(
    "签约管理",
    "SALES / CONTRACTS",
    "管理销售合同、付款方式、签约日期和回款状态，与销售回款和发票联动。",
    [button(class="erp-primary-btn", "＋ 新建签约")],
    div <| [
      filter_bar("签约号 / 客户 / 房号"),
      table_panel(
        "销售合同",
        "本月签约 42 套",
        data_table(
          [
            "签约号", "客户", "电话", "房号", "面积㎡", "总价(元)",
            "付款方式", "签约日", "状态",
          ],
          [
            [
              "SC-260713-004", "陈敏", "158****9920", "3#-901", "89.20", "1,971,320",
              "按揭", "2026-07-13", "已签约",
            ],
            [
              "SC-260712-016", "刘洋", "136****2840", "1#-1203", "116.80", "2,172,480",
              "组合贷", "2026-07-12", "已签约",
            ],
            [
              "SC-260710-008", "张伟", "133****5701", "6#-602", "78.40", "1,372,000",
              "一次性", "2026-07-10", "待备案",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_mortgages_view() -> @html.Html {
  page_shell(
    "按揭办理",
    "SALES / MORTGAGES",
    "跟进按揭申请、银行审批与放款节点，及时发现资料缺失和逾期申请。",
    [button(class="erp-primary-btn", "＋ 新建按揭")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("办理中", "68", "涉及 5 家银行", "metric-blue"),
        metric("本月放款", "¥3,860 万", "32 笔", "metric-green"),
        metric("资料待补", "7", "需客户跟进", "metric-blue"),
      ],
      filter_bar("按揭号 / 客户 / 银行"),
      table_panel(
        "按揭申请",
        "共 214 条",
        data_table(
          [
            "按揭号", "客户", "银行", "贷款额(元)", "年限", "利率",
            "申请日", "批贷日", "放款日", "状态",
          ],
          [
            [
              "MT-260701-019", "王晓峰", "建设银行", "1,673,000", "30 年",
              "3.45%", "2026-07-01", "", "", "审批中",
            ],
            [
              "MT-260628-008", "赵文静", "招商银行", "1,130,000", "30 年",
              "3.45%", "2026-06-28", "2026-07-08", "", "待放款",
            ],
            [
              "MT-260615-002", "陈敏", "工商银行", "1,380,000", "25 年", "3.55%",
              "2026-06-15", "2026-06-22", "2026-07-03", "已放款",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn contracts_view() -> @html.Html {
  page_shell(
    "合同台帐",
    "COST / CONTRACTS",
    "统一查看采购、工程、营销和咨询合同的签订、付款、发票与履约状态。",
    [
      button(class="erp-secondary-btn", "导出合同台帐"),
      button(class="erp-primary-btn", "＋ 新建合同"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("合同总数", "62", "覆盖 15 个项目", "metric-blue"),
        metric("合同金额", "¥12.57 亿", "较目标 +6.2%", "metric-blue"),
        metric("待付款", "¥1.84 亿", "24 个申请", "metric-green"),
      ],
      filter_bar("合同编号 / 项目 / 供应商"),
      table_panel(
        "合同列表",
        "按签订日期倒序",
        data_table(
          [
            "合同编号", "合同名称", "项目", "供应商", "合同金额",
            "已付款", "签订日期", "状态",
          ],
          [
            [
              "HT-CD-260701", "主体结构施工合同", "成都和锦里", "中建三局",
              "¥48,600,000", "¥12,800,000", "2026-07-01", "履行中",
            ],
            [
              "HT-CQ-260628", "营销推广服务合同", "重庆南山居", "众成广告",
              "¥3,600,000", "¥1,200,000", "2026-06-28", "履行中",
            ],
            [
              "HT-SY-260615", "园林景观工程合同", "沈阳和山苑", "绿城园林",
              "¥8,920,000", "¥8,920,000", "2026-06-15", "已完成",
            ],
            [
              "HT-TJ-260602", "电梯设备采购合同", "天津海教园一期",
              "奥的斯", "¥5,180,000", "¥0", "2026-06-02", "待付款",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn payment_applies_view() -> @html.Html {
  page_shell(
    "付款申请",
    "COST / PAYMENTS",
    "按合同和成本科目发起付款申请，跟踪审批、付款和收款方信息。",
    [button(class="erp-primary-btn", "＋ 发起付款申请")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("待审批", "18", "金额 ¥2,860 万", "metric-blue"),
        metric(
          "本月已付", "¥1,380 万", "执行率 10.98%", "metric-green",
        ),
        metric("已驳回", "3", "请补充附件", "metric-blue"),
      ],
      filter_bar("申请编号 / 合同 / 项目"),
      table_panel(
        "付款申请单",
        "最近更新",
        data_table(
          [
            "申请编号", "项目", "合同", "收款方", "申请金额", "申请人",
            "提交日期", "状态",
          ],
          [
            [
              "PAY-260713-006", "成都和锦里", "主体结构施工合同", "中建三局",
              "¥1,280,000", "陈志强", "2026-07-13", "审批中",
            ],
            [
              "PAY-260712-011", "重庆南山居", "营销推广服务合同", "众成广告",
              "¥360,000", "刘松", "2026-07-12", "待处理",
            ],
            [
              "PAY-260710-004", "沈阳和山苑", "园林景观工程合同", "绿城园林",
              "¥890,000", "李明金", "2026-07-10", "已完成",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn cost_dashboard_view() -> @html.Html {
  page_shell(
    "成本驾驶舱",
    "COST DASHBOARD",
    "从目标成本、动态成本、合同和付款四个层面观察项目成本偏差。",
    [
      button(class="erp-secondary-btn", "选择项目"),
      button(class="erp-secondary-btn", "导出分析"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("目标成本", "¥6.08 亿", "15 个项目", "metric-blue"),
        metric("动态成本", "¥6.45 亿", "偏差 +6.20%", "metric-green"),
        metric("已签合同", "¥5.82 亿", "覆盖率 90.2%", "metric-blue"),
        metric("待承诺", "¥6,280 万", "需关注 4 项", "metric-blue"),
      ],
      div(class="erp-dashboard-grid") <| [
        section(class="erp-panel") <| [
          div(class="erp-panel-heading") <| [
            h2("项目成本偏差"),
            span(class="erp-info-tag", "按动态成本"),
          ],
          div(class="erp-cost-bars") <| [
            phase_row("成都和锦里", "+8.4%", "84%"),
            phase_row("重庆南山居", "+5.7%", "57%"),
            phase_row("沈阳和山苑", "+1.4%", "14%"),
            phase_row("天津海教园", "+1.25%", "13%"),
          ],
        ],
        table_panel(
          "科目偏差 TOP 5",
          "动态成本 - 目标成本",
          data_table(
            [
              "CBS 科目", "目标成本", "动态成本", "偏差", "责任项目",
            ],
            [
              [
                "01-02 土地成本", "¥1.82 亿", "¥1.84 亿", "+1.1%", "成都和锦里",
              ],
              [
                "03-01 建安工程", "¥2.64 亿", "¥2.82 亿", "+6.8%", "成都和锦里",
              ],
              [
                "04-03 营销费用", "¥4,280 万", "¥4,560 万", "+6.5%", "重庆南山居",
              ],
            ],
          ),
        ),
      ],
    ],
  )
}

///|
fn investment_view() -> @html.Html {
  page_shell(
    "投资收益",
    "COST / INVESTMENT",
    "按项目查看投资额、销售收入、利润和 IRR，沉淀投资测算与实际经营的差异。",
    [button(class="erp-secondary-btn", "导出测算")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "项目总投资", "¥8.42 亿", "含土地及开发", "metric-blue",
        ),
        metric(
          "预计销售收入", "¥12.68 亿", "去化率 64%", "metric-blue",
        ),
        metric(
          "预计净利润", "¥1.72 亿", "利润率 13.6%", "metric-green",
        ),
        metric("加权 IRR", "18.4%", "目标 16.0%", "metric-green"),
      ],
      table_panel(
        "项目投资收益",
        "经营测算 vs 当前预测",
        data_table(
          [
            "项目", "总投资", "销售收入", "净利润", "利润率", "IRR",
            "状态",
          ],
          [
            [
              "成都和锦里", "¥2.36 亿", "¥3.82 亿", "¥5,420 万", "14.2%",
              "19.8%", "正常",
            ],
            [
              "重庆南山居", "¥1.84 亿", "¥2.76 亿", "¥3,180 万", "11.5%",
              "15.6%", "关注",
            ],
            [
              "沈阳和山苑", "¥1.62 亿", "¥2.28 亿", "¥2,960 万", "13.0%",
              "17.2%", "正常",
            ],
            [
              "天津海教园一期", "¥1.48 亿", "¥2.06 亿", "¥2,420 万",
              "11.7%", "16.1%", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn dynamic_cost_view() -> @html.Html {
  page_shell(
    "动态成本",
    "COST / FORECAST",
    "汇总合同、签证、变更和待发生成本，形成可追溯的动态成本预测。",
    [button(class="erp-primary-btn", "＋ 新增变更")],
    div <| [
      filter_bar("项目 / 成本科目 / 变更编号"),
      table_panel(
        "动态成本明细",
        "成都和锦里",
        data_table(
          [
            "变更编号", "成本科目", "变更原因", "目标成本", "动态成本",
            "变更额", "发起人", "状态",
          ],
          [
            [
              "DC-260713-002", "03-01 建安工程", "设计优化", "¥264,000,000",
              "¥282,400,000", "+¥18,400,000", "王工", "审批中",
            ],
            [
              "DC-260709-006", "04-03 营销费用", "渠道政策调整", "¥42,800,000",
              "¥45,600,000", "+¥2,800,000", "刘松", "已完成",
            ],
            [
              "DC-260704-001", "05-02 配套工程", "管线迁改", "¥18,600,000",
              "¥19,280,000", "+¥680,000", "陈工", "待处理",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn tender_view() -> @html.Html {
  page_shell(
    "合约规划",
    "COST / TENDER",
    "按项目和 CBS 科目编制合约规划，控制招采范围、预算和合同落地。",
    [button(class="erp-primary-btn", "＋ 新建合约规划")],
    div <| [
      filter_bar("项目 / 合约包 / CBS 科目"),
      table_panel(
        "合约规划包",
        "共 38 个合约包",
        data_table(
          [
            "规划编号", "项目", "合约包", "CBS 科目", "预算金额",
            "已招采", "计划招标日", "状态",
          ],
          [
            [
              "TP-CD-0301", "成都和锦里", "主体结构工程", "03-01 建安工程",
              "¥264,000,000", "¥48,600,000", "2026-01-15", "进行中",
            ],
            [
              "TP-CD-0502", "成都和锦里", "园林景观工程", "05-02 配套工程",
              "¥18,600,000", "¥0", "2026-08-10", "待招采",
            ],
            [
              "TP-CQ-0403", "重庆南山居", "营销推广服务", "04-03 营销费用",
              "¥42,800,000", "¥3,600,000", "2026-02-20", "进行中",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn srm_providers_view() -> @html.Html {
  page_shell(
    "供应商库",
    "SRM / PROVIDERS",
    "维护供应商资质、合作项目、联系人和履约评价，服务合同与招采环节。",
    [button(class="erp-primary-btn", "＋ 新增供应商")],
    div <| [
      filter_bar("供应商名称 / 统一社会信用代码 / 类别"),
      table_panel(
        "供应商列表",
        "共 426 家供应商",
        data_table(
          [
            "供应商编码", "供应商名称", "类别", "合作项目", "联系人",
            "最近评价", "风险等级", "状态",
          ],
          [
            [
              "SUP-00018", "中建三局集团有限公司", "工程施工", "成都和锦里",
              "周强", "A", "低", "正常",
            ],
            [
              "SUP-00142", "众成广告传媒有限公司", "营销服务", "重庆南山居",
              "赵琳", "B", "中", "正常",
            ],
            [
              "SUP-00306", "绿城园林建设集团", "园林工程", "沈阳和山苑",
              "刘峰", "A", "低", "正常",
            ],
            [
              "SUP-00427", "华北建材贸易有限公司", "材料供应", "天津海教园",
              "王磊", "C", "高", "关注",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn srm_risk_view() -> @html.Html {
  page_shell(
    "供应商风险面板",
    "SRM / RISK",
    "集中查看资质到期、履约偏差、诉讼和集中度风险，支持责任人跟进。",
    [button(class="erp-secondary-btn", "导出风险清单")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("高风险", "6", "需在 7 日内处理", "metric-blue"),
        metric("中风险", "18", "较上周 -2", "metric-blue"),
        metric("资质即将到期", "12", "未来 30 天", "metric-green"),
      ],
      table_panel(
        "风险清单",
        "按风险等级排序",
        data_table(
          [
            "供应商", "风险类型", "风险说明", "影响合同", "责任人",
            "截止日期", "状态",
          ],
          [
            [
              "华北建材贸易有限公司", "资质到期", "安全生产许可证 15 天后到期",
              "3", "王磊", "2026-07-28", "待处理",
            ],
            [
              "众成广告传媒有限公司", "履约偏差", "投放效果低于约定 18%",
              "2", "刘松", "2026-07-20", "进行中",
            ],
            [
              "中建三局集团有限公司", "集中度", "单一供应商合同额占比 42%",
              "8", "陈志强", "2026-08-15", "关注",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn cbs_view(path : String) -> @html.Html {
  let title = title_for(path)
  page_shell(
    title,
    "CBS / MASTER DATA",
    "维护成本分解结构、目标版本和审批配置，确保项目成本口径一致。",
    [button(class="erp-primary-btn", "＋ 新建条目")],
    div <| [
      filter_bar("科目编码 / 科目名称 / 版本"),
      table_panel(
        "CBS 数据",
        "当前版本 V2026.07",
        data_table(
          [
            "编码", "名称", "层级", "适用范围", "最近更新", "维护人",
            "状态",
          ],
          [
            [
              "03", "建安工程", "一级", "全集团", "2026-07-01", "李明金",
              "正常",
            ],
            [
              "03-01", "主体结构工程", "二级", "开发项目", "2026-07-08",
              "李明金", "正常",
            ],
            [
              "03-01-002", "混凝土工程", "三级", "开发项目", "2026-07-12",
              "系统", "待审核",
            ],
            [
              "04-03", "营销费用", "二级", "销售项目", "2026-06-20", "刘松",
              "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn fund_plan_view() -> @html.Html {
  page_shell(
    "资金计划",
    "FINANCE / FUND PLAN",
    "统筹项目回款、融资、付款与资金缺口，形成月度和滚动资金计划。",
    [button(class="erp-primary-btn", "＋ 编制计划")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "本月可用资金", "¥4,280 万", "含银行余额", "metric-blue",
        ),
        metric(
          "本月计划流出", "¥3,860 万", "付款 48 笔", "metric-blue",
        ),
        metric(
          "资金缺口", "¥620 万", "预计 8 月出现", "metric-green",
        ),
      ],
      table_panel(
        "月度资金计划",
        "2026 年 7 月",
        data_table(
          [
            "项目 / 公司", "期初余额", "计划流入", "计划流出", "期末余额",
            "缺口", "负责人", "状态",
          ],
          [
            [
              "成都和锦里", "¥1,820 万", "¥2,460 万", "¥2,180 万", "¥2,100 万",
              "—", "陈志强", "正常",
            ],
            [
              "重庆南山居", "¥860 万", "¥1,120 万", "¥1,360 万", "¥620 万",
              "¥180 万", "刘松", "关注",
            ],
            [
              "沈阳和山苑", "¥1,240 万", "¥960 万", "¥820 万", "¥1,380 万",
              "—", "李明金", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn invoice_view() -> @html.Html {
  page_shell(
    "发票管理",
    "FINANCE / INVOICE",
    "管理进项、销项发票的识别、验真、关联合同和入账状态。",
    [button(class="erp-primary-btn", "＋ 录入发票")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月进项", "¥1,286 万", "218 张", "metric-blue"),
        metric("待验真", "14", "金额 ¥82 万", "metric-blue"),
        metric("待入账", "36", "已关联合同", "metric-green"),
      ],
      filter_bar("发票号码 / 供应商 / 合同编号"),
      table_panel(
        "发票列表",
        "最近上传",
        data_table(
          [
            "发票号码", "发票类型", "供应商", "金额", "税额", "关联合同",
            "开票日期", "状态",
          ],
          [
            [
              "04400193 2687", "增值税专票", "中建三局", "¥1,165,138",
              "¥135,155", "HT-CD-260701", "2026-07-12", "待验真",
            ],
            [
              "04400193 2682", "增值税专票", "众成广告", "¥339,623", "¥19,977",
              "HT-CQ-260628", "2026-07-11", "已入账",
            ],
            [
              "04400192 9114", "增值税专票", "绿城园林", "¥816,514", "¥94,739",
              "HT-SY-260615", "2026-07-09", "已验真",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn expenses_view() -> @html.Html {
  page_shell(
    "我的报销",
    "FINANCE / EXPENSES",
    "发起差旅、招待和日常费用报销，查看预算占用、审批节点与付款进度。",
    [button(class="erp-primary-btn", "＋ 新建报销")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月报销", "¥28,560", "8 笔", "metric-blue"),
        metric("审批中", "5", "金额 ¥16,420", "metric-blue"),
        metric("已付款", "¥62,180", "本年度", "metric-green"),
      ],
      filter_bar("报销单号 / 摘要 / 申请日期"),
      table_panel(
        "报销记录",
        "我的申请",
        data_table(
          [
            "报销单号", "费用类型", "摘要", "金额", "申请日期", "当前节点",
            "状态",
          ],
          [
            [
              "EXP-260712-008", "差旅费", "成都项目现场出差", "¥8,560",
              "2026-07-12", "部门负责人", "审批中",
            ],
            [
              "EXP-260705-003", "业务招待费", "供应商沟通会", "¥3,280",
              "2026-07-05", "财务复核", "审批中",
            ],
            [
              "EXP-260628-011", "办公费", "项目打印及耗材", "¥1,860",
              "2026-06-28", "—", "已完成",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn loans_view() -> @html.Html {
  page_shell(
    "我的借款",
    "FINANCE / LOANS",
    "发起备用金和差旅借款，跟踪核销、还款以及个人可用额度。",
    [button(class="erp-primary-btn", "＋ 新建借款")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("未核销借款", "¥18,000", "2 笔", "metric-blue"),
        metric("本月可用额度", "¥30,000", "个人额度", "metric-green"),
        metric("待审批", "1", "金额 ¥8,000", "metric-blue"),
      ],
      table_panel(
        "借款记录",
        "我的申请",
        data_table(
          [
            "借款单号", "借款类型", "用途", "金额", "申请日期", "预计归还",
            "核销状态", "审批状态",
          ],
          [
            [
              "LOAN-260701-002", "差旅借款", "成都项目驻场", "¥10,000",
              "2026-07-01", "2026-07-31", "未核销", "已完成",
            ],
            [
              "LOAN-260629-005", "备用金", "现场零星采购", "¥8,000", "2026-06-29",
              "2026-07-15", "待核销", "已完成",
            ],
            [
              "LOAN-260713-001", "差旅借款", "沈阳项目会议", "¥8,000",
              "2026-07-13", "2026-07-30", "—", "审批中",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn reports_view() -> @html.Html {
  page_shell(
    "报表中心",
    "ANALYSIS / REPORTS",
    "按主题打开经营、成本、资金、销售与项目报表，统一查看口径和更新时间。",
    [button(class="erp-secondary-btn", "管理收藏")],
    div <| [
      div(class="erp-report-grid") <| [
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "▦"),
          h2("经营驾驶舱"),
          p("公司、项目、合同与资金核心指标"),
          button(class="erp-secondary-btn", "打开"),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "¥"),
          h2("成本月报"),
          p("目标成本、动态成本与偏差分析"),
          button(class="erp-secondary-btn", "打开"),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "⌁"),
          h2("销售月报"),
          p("认筹、签约、回款和去化情况"),
          button(class="erp-secondary-btn", "打开"),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "◷"),
          h2("资金预测"),
          p("未来 90 天流入流出和资金缺口"),
          button(class="erp-secondary-btn", "打开"),
        ],
      ],
      table_panel(
        "最近报表",
        "我的收藏",
        data_table(
          [
            "报表名称", "主题", "数据期间", "更新时间", "创建人",
            "操作",
          ],
          [
            [
              "集团经营周报", "经营", "2026-W28", "今天 08:30", "系统",
              "查看",
            ],
            [
              "项目成本偏差表", "成本", "2026-07", "昨天 18:20", "李明金",
              "查看",
            ],
            [
              "销售回款跟踪表", "销售", "2026-07", "昨天 17:45", "刘松",
              "查看",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn report_builder_view() -> @html.Html {
  page_shell(
    "自定义报表",
    "ANALYSIS / BUILDER",
    "选择数据主题、字段和筛选条件，保存为团队可复用的自定义报表。",
    [button(class="erp-primary-btn", "＋ 新建报表")],
    div <| [
      section(class="erp-builder-card") <| [
        span(class="erp-page-eyebrow", "REPORT BUILDER"),
        h2("从数据集开始"),
        div(class="erp-builder-options") <| [
          button(class="erp-option-card is-active", "项目与成本"),
          button(class="erp-option-card", "合同与付款"),
          button(class="erp-option-card", "销售与回款"),
          button(class="erp-option-card", "资金计划"),
        ],
        filter_bar("搜索字段，例如：项目名称、动态成本"),
      ],
      table_panel(
        "已保存报表",
        "共 12 个",
        data_table(
          [
            "报表名称", "数据集", "共享范围", "最近运行", "创建人",
            "状态",
          ],
          [
            [
              "项目成本月度变化", "项目与成本", "成本团队", "今天 08:10",
              "李明金", "正常",
            ],
            [
              "合同付款执行率", "合同与付款", "全集团", "昨天 19:42",
              "系统", "正常",
            ],
            [
              "销售去化漏斗", "销售与回款", "销售团队", "2026-07-11",
              "刘松", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn warning_view() -> @html.Html {
  page_shell(
    "异常预警中心",
    "ANALYSIS / WARNINGS",
    "集中处理成本偏差、项目延期、资金缺口、供应商和发票异常。",
    [
      button(class="erp-secondary-btn", "全部标记已读"),
      button(class="erp-primary-btn", "配置规则"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("未处理", "23", "高优先级 6", "metric-blue"),
        metric("本周新增", "8", "较上周 -3", "metric-blue"),
        metric("已关闭", "186", "关闭率 89.0%", "metric-green"),
      ],
      table_panel(
        "预警清单",
        "按优先级和更新时间",
        data_table(
          [
            "预警编号", "类型", "项目 / 对象", "预警内容", "触发时间",
            "责任人", "状态",
          ],
          [
            [
              "WARN-260713-006", "项目延期", "成都和锦里", "2# 楼砌体较计划晚 4 天",
              "今天 09:18", "陈志强", "待处理",
            ],
            [
              "WARN-260712-011", "成本偏差", "成都和锦里", "建安成本超目标 8.4%",
              "昨天 16:42", "李明金", "进行中",
            ],
            [
              "WARN-260711-004", "资金缺口", "重庆南山居", "8 月预计缺口 ¥180 万",
              "2026-07-11", "刘松", "待处理",
            ],
            [
              "WARN-260710-002", "发票异常", "04400193 2687", "销方税号待确认",
              "2026-07-10", "财务共享", "已完成",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn warning_rules_view() -> @html.Html {
  page_shell(
    "告警规则 DSL",
    "ANALYSIS / RULES",
    "用可审计的规则表达式配置阈值、通知对象和自动关闭条件。",
    [button(class="erp-primary-btn", "＋ 新建规则")],
    div <| [
      table_panel(
        "规则列表",
        "12 条内置规则 · 4 条自定义规则",
        data_table(
          [
            "规则名称", "对象", "触发条件", "通知方式", "最近触发",
            "启用状态",
          ],
          [
            [
              "成本偏差超过 5%", "项目成本", "dynamic_cost / target_cost > 1.05",
              "站内信 + 企业微信", "今天 09:18", "启用",
            ],
            [
              "任务延期超过 3 天", "项目任务", "today - planned_end > 3d",
              "站内信", "今天 08:42", "启用",
            ],
            [
              "发票税号缺失", "进项发票", "seller_tax_no is null", "待办",
              "昨天 16:20", "启用",
            ],
            [
              "现金流缺口", "资金计划", "forecast_balance < 0", "邮件 + 站内信",
              "2026-07-11", "停用",
            ],
          ],
        ),
      ),
      section(class="erp-code-card") <| [
        span(class="erp-page-eyebrow", "RULE PREVIEW"),
        p(
          "when project.cost_variance_ratio > 0.05 then warning('成本偏差', owner=project.cost_owner)",
        ),
      ],
    ],
  )
}

///|
fn cashflow_view() -> @html.Html {
  page_shell(
    "现金流预测",
    "FINANCE / CASHFLOW",
    "综合回款、融资和付款计划，预测未来 90 天的每日资金余额和缺口。",
    [
      button(class="erp-secondary-btn", "切换 30 / 90 天"),
      button(class="erp-secondary-btn", "导出预测"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("当前余额", "¥4,280 万", "截至今天", "metric-blue"),
        metric("90 天流入", "¥8,620 万", "回款 + 融资", "metric-green"),
        metric("90 天流出", "¥9,180 万", "工程 + 费用", "metric-blue"),
        metric("最低余额", "¥380 万", "8 月 18 日", "metric-blue"),
      ],
      table_panel(
        "滚动现金流",
        "未来 12 周",
        data_table(
          [
            "周次", "期初余额", "预计流入", "预计流出", "期末余额",
            "最大支出", "风险",
          ],
          [
            [
              "W29 · 07/13", "¥4,280 万", "¥1,260 万", "¥1,180 万", "¥4,360 万",
              "工程款", "正常",
            ],
            [
              "W30 · 07/20", "¥4,360 万", "¥820 万", "¥1,560 万", "¥3,620 万",
              "土地款", "关注",
            ],
            [
              "W31 · 07/27", "¥3,620 万", "¥1,180 万", "¥1,920 万", "¥2,880 万",
              "建安款", "关注",
            ],
            [
              "W32 · 08/03", "¥2,880 万", "¥1,460 万", "¥2,420 万", "¥1,920 万",
              "工程款", "关注",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_revenues_view() -> @html.Html {
  page_shell(
    "销售回款 (R6)",
    "SALES / REVENUES",
    "登记销售回款、到账日期、付款类型与销售合同号，保持回款与应收台帐可追溯。",
    [button(class="erp-primary-btn", "＋ 新增回款")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月到账", "¥6,820 万", "126 笔", "metric-blue"),
        metric(
          "年度累计", "¥4.28 亿", "完成年度目标 68%", "metric-green",
        ),
        metric("待确认", "12", "金额 ¥380 万", "metric-blue"),
      ],
      filter_bar("回款编号 / 客户 / 销售合同号"),
      table_panel(
        "回款登记",
        "按到账日期倒序",
        data_table(
          [
            "回款编号", "客户", "金额", "到账日期", "状态", "付款类型",
            "销售合同号", "R 编码",
          ],
          [
            [
              "REV-260713-018", "陈敏", "¥1,971,320", "2026-07-13", "已确认",
              "首付", "SC-260713-004", "R-2026-0713",
            ],
            [
              "REV-260712-026", "刘洋", "¥652,000", "2026-07-12", "已确认",
              "按揭", "SC-260712-016", "R-2026-0712",
            ],
            [
              "REV-260710-011", "张伟", "¥420,000", "2026-07-10", "待确认",
              "首付", "SC-260710-008", "R-2026-0710",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn marketing_view() -> @html.Html {
  page_shell(
    "营销管理",
    "SALES / MARKETING",
    "管理营销活动、投放记录、渠道与营销物料，预算和实际花费挂接 CBS。",
    [button(class="erp-primary-btn", "＋ 新建营销活动")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("营销活动数", "18", "运行中 6 个", "metric-blue"),
        metric("投放总额", "¥1,286 万", "本年度", "metric-blue"),
        metric("有效线索", "3,842", "转化率 12.6%", "metric-green"),
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "营销活动"),
        button(class="erp-tab", "投放记录"),
        button(class="erp-tab", "营销渠道"),
        button(class="erp-tab", "营销物料"),
      ],
      table_panel(
        "营销活动",
        "v3.8 · R19 营销费用",
        data_table(
          [
            "编号", "活动名称", "类型", "预算(元)", "已花(元)", "周期",
            "状态", "挂 CBS",
          ],
          [
            [
              "CAM-260701", "成都和锦里开盘推广", "开盘活动", "¥1,800,000",
              "¥680,000", "2026-07-01 ~ 08-20", "运行中", "04-03",
            ],
            [
              "CAM-260615", "南山居线上投放", "线上获客", "¥960,000",
              "¥812,000", "2026-06-15 ~ 07-31", "运行中", "04-03",
            ],
            [
              "CAM-260501", "沈阳和山苑暖场", "客户活动", "¥420,000",
              "¥420,000", "2026-05-01 ~ 06-30", "已结束", "04-03",
            ],
          ],
        ),
      ),
      table_panel(
        "投放记录",
        "渠道效果和实际花费",
        data_table(
          [
            "编号", "所属活动", "投放渠道", "金额(元)", "投放日",
            "曝光", "线索",
          ],
          [
            [
              "PLC-260712-008", "成都和锦里开盘推广", "抖音", "¥180,000",
              "2026-07-12", "286,000", "420",
            ],
            [
              "PLC-260708-004", "南山居线上投放", "SEM", "¥96,000", "112,000",
              "186",
            ],
            [
              "PLC-260701-012", "成都和锦里开盘推广", "渠道分销", "¥240,000",
              "—", "98",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn system_view(path : String) -> @html.Html {
  let title = title_for(path)
  page_shell(
    title,
    "SYSTEM",
    "保留 erp_new 的运维与配置边界，所有高风险操作都需要权限和审计记录。",
    [button(class="erp-secondary-btn", "导出")],
    table_panel(
      "配置与记录",
      "最近更新",
      data_table(
        ["名称", "类型", "更新时间", "更新人", "状态", "操作"],
        [
          [
            "集团管理员", "角色", "今天 09:24", "Giant Claw", "正常",
            "查看",
          ],
          [
            "付款审批通知", "通知配置", "昨天 18:12", "系统", "正常",
            "编辑",
          ],
          [
            "PostgreSQL 主库", "系统健康", "昨天 17:50", "系统", "正常",
            "查看",
          ],
          [
            "合同 OCR 提取", "AI 配置", "2026-07-11", "Giant Claw", "启用",
            "配置",
          ],
        ],
      ),
    ),
  )
}

///|
fn business_view(path : String) -> @html.Html {
  match path {
    "/ai-hub" => ai_hub_view()
    "/ai-stats" => ai_stats_view()
    "/projects" => project_view()
    "/project-plan" => project_plan_view()
    "/project/progress" => progress_view()
    "/tasks" => tasks_view()
    "/sales/customers" => sales_customers_view()
    "/sales/subscriptions" => sales_subscriptions_view()
    "/sales/contracts" => sales_contracts_view()
    "/sales/mortgages" => sales_mortgages_view()
    "/sales/revenues" => sales_revenues_view()
    "/marketing" => marketing_view()
    "/contracts" => contracts_view()
    "/payment-applies" => payment_applies_view()
    "/cost-dashboard-v3" => cost_dashboard_view()
    "/investment" => investment_view()
    "/dynamic-cost" => dynamic_cost_view()
    "/tender" => tender_view()
    "/srm/providers" => srm_providers_view()
    "/srm/risk-board" => srm_risk_view()
    "/cbs/dict" => cbs_view(path)
    "/cbs/versions" => cbs_view(path)
    "/cbs/r0-queue" => cbs_view(path)
    "/cbs/approval-config" => cbs_view(path)
    "/fund/plan" => fund_plan_view()
    "/invoice" => invoice_view()
    "/expenses" => expenses_view()
    "/loans" => loans_view()
    "/reports" => reports_view()
    "/report-builder" => report_builder_view()
    "/warning" => warning_view()
    "/warning-rules" => warning_rules_view()
    "/cashflow" => cashflow_view()
    "/inbox" => system_view(path)
    "/attachments" => system_view(path)
    "/notify-config" => system_view(path)
    "/audit-log" => system_view(path)
    "/error-log" => system_view(path)
    "/system-health" => system_view(path)
    "/users" => system_view(path)
    "/admin" => system_view(path)
    "/ocr-config" => system_view(path)
    "/webhook-config" => system_view(path)
    "/profile" => system_view(path)
    _ => placeholder_view(path)
  }
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
    business_view(model.page)
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
