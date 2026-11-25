///|
fn status_badge(label : String, tone~ : String = "neutral") -> @html.Html {
  span(class="status-badge status-\{tone}", label)
}

///|
fn sample_data_boundary() -> @html.Html {
  div(class="sample-data-boundary", attrs=@html.Attrs::build().role("note")) <| [
    strong("只读演练投影"),
    p(
      "以下内容只用于验证信息架构与响应式布局，不是 PostgreSQL 公司事实，也不会产生经营、审批或审计效果。",
    ),
  ]
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
  let label_text = if item.page == Delivery {
    "交付演练（会话内）"
  } else {
    item.label
  }
  let selected = item.page == active
  let attrs = @html.Attrs::build()
    .aria_current(if selected { "page" } else { "false" })
    .aria_label("\{label_text}：\{item.description}")
  button(
    type_="button",
    title=item.description,
    class=if selected { "nav-item is-active" } else { "nav-item" },
    attrs~,
    on_click=emit(Navigate(item.page)),
  ) <| [
    span(
      class="nav-glyph",
      attrs=@html.Attrs::build()
        .aria_hidden("true")
        .data_set("short-label", item.short_label),
      [opc_glyph(page_glyph(item.page))],
    ),
    span(class="nav-copy") <| [
      strong(label_text),
    ],
  ]
}

///|
fn sidebar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let items : Array[@html.Html] = []
  let more : Array[@html.Html] = []
  let demonstrations : Array[@html.Html] = []
  let mut current_group = ""
  for item in nav_items() {
    if [Workspace, Overview, Objectives, Company].contains(item.page) {
      items.push(nav_item_view(emit, item, model.page))
    } else if [Observe, Operate, Evidence, Delivery].contains(item.page) {
      demonstrations.push(nav_item_view(emit, item, model.page))
    } else if item.page != MoonSuite || model.moon_mode {
      if item.group != current_group {
        current_group = item.group
        more.push(p(class="nav-group", item.group))
      }
      more.push(nav_item_view(emit, item, model.page))
    }
  }
  more.push(
    details(
      class="nav-more",
      open=[Observe, Operate, Evidence, Delivery].contains(model.page),
    ) <| [
      summary("演练与开发"),
      div <| demonstrations,
    ],
  )
  items.push(
    details(
      class="nav-more",
      open=![Overview, Objectives, Company].contains(model.page),
    ) <| [
      summary("更多工具"),
      div <| more,
    ],
  )
  div(
    class=if model.mobile_nav { "sidebar is-open" } else { "sidebar" },
    attrs=@html.Attrs::build().id("primary-sidebar"),
  ) <| [
    div(class="brand") <| [
      @html.img(
        class="brand-mark",
        src="./moonproj.svg",
        alt="",
        width=36,
        height=36,
      ),
      div(class="brand-copy") <| [
        strong("MoonProj"),
      ],
    ],
    div(class="mode-switch") <| [
      button(
        type_="button",
        class=if !model.moon_mode {
          "mode-option is-active"
        } else {
          "mode-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if !model.moon_mode {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(SetMoonMode(false)),
        "通用模式",
      ),
      button(
        type_="button",
        class=if model.moon_mode {
          "mode-option is-active"
        } else {
          "mode-option"
        },
        attrs=@html.Attrs::build().aria_pressed(
          if model.moon_mode {
            "true"
          } else {
            "false"
          },
        ),
        on_click=emit(SetMoonMode(true)),
        "Moon 专案",
      ),
    ],
    nav(
      class="primary-nav",
      attrs=@html.Attrs::build().aria_label("基础 OPC 主导航"),
    ) <| items,
  ]
}

///|
fn topbar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let menu_label = if model.mobile_nav {
    "关闭主导航"
  } else {
    "打开主导航"
  }
  header(class="topbar") <| [
    button(
      type_="button",
      class="mobile-menu",
      title=menu_label,
      attrs=@html.Attrs::build()
        .aria_label(menu_label)
        .aria_controls("primary-sidebar")
        .aria_expanded(if model.mobile_nav { "true" } else { "false" }),
      on_click=emit(ToggleMobileNav),
      [opc_glyph("menu"), span(class="visually-hidden", "菜单")],
    ),
    div(class="topbar-title") <| [
      small(
        if model.moon_mode {
          "Moon Suite 产品线"
        } else {
          "通用公司运营"
        },
      ),
      strong(page_title(model.page)),
    ],
    div(class="topbar-state") <| [
      button(
        type_="button",
        class="button button-secondary button-small topbar-desktop-return",
        on_click=emit(WorkspaceAction(Flow)),
        "← 返回公司桌面",
      ),
    ],
  ]
}

///|
fn notice_view(emit : @rabbita.Emit[Msg], notice : String) -> @html.Html {
  if notice.is_empty() {
    @html.nothing
  } else {
    div(
      class="notice",
      attrs=@html.Attrs::build()
        .role("status")
        .aria_label("操作结果")
        .aria_live("polite")
        .aria_atomic("true"),
    ) <| [
      p(notice),
      button(
        type_="button",
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
fn system_setup(
  emit : @rabbita.Emit[Msg],
  title : String,
  description : String,
  complete : Bool,
  message : Msg,
) -> @html.Html {
  article(class=if complete { "system-setup is-ready" } else { "system-setup" }) <| [
    div(class="system-setup-copy") <| [
      strong(title),
      p(description),
    ],
    if complete {
      status_badge("空台账已启用", tone="accent")
    } else {
      button(
        type_="button",
        class="button button-secondary",
        attrs=@html.Attrs::build().aria_label("建立\{title}台账"),
        on_click=emit(message),
        "建立台账",
      )
    },
  ]
}

///|
fn scope_row(
  area : String,
  responsibility : String,
  owner_screen : String,
  ready : Bool,
) -> @html.Html {
  tr <| [
    td <| [
      strong(area),
    ],
    td(responsibility),
    td(owner_screen),
    td <| [
      status_badge(
        if ready {
          "台账已启用"
        } else {
          "待建立"
        },
        tone=if ready { "accent" } else { "muted" },
      ),
    ],
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

