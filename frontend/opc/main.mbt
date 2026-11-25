///|
using @html {
  a,
  article,
  button,
  details,
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
  summary,
  table,
  tbody,
  td,
  th,
  thead,
  tr,
  ul,
}

///|
using @rabbita {new, none, type Cmd}

///|
fn page_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  match model.page {
    Workspace => @html.nothing
    Overview => cockpit_view(emit, model)
    Fleet => fleet_view(emit, model)
    Dispatch => dispatch_view(emit, model)
    Products => products_view(emit, model)
    Objectives => objectives_view(emit, model)
    Projects => projects_view(emit, model)
    MoonSuite => moon_suite_view(emit, model)
    Quality => quality_view(emit, model)
    Observe => observe_view(emit, model)
    Operate => operate_view(emit, model)
    Company => company_domain_view(emit, model)
    PolicyRadar => policy_radar_view(emit, model)
    Evidence => evidence_view(emit, model)
    Guide => guide_view(emit, model)
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
    div(class="legacy-shell", hidden=model.page == Workspace) <| [
    if model.mobile_nav {
      button(
        type_="button",
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
      main_(
        class="main-content",
        attrs=@html.Attrs::build().id(if model.page == Workspace { "legacy-main-content" } else { "main-content" }).tabindex(-1),
      ) <| [
        notice_view(emit, model.notice),
        page_view(emit, model),
      ],
    ],
    ],
    workspace_shell_view(emit, model),
  ]
}

///|
priv struct AppModel(Model)

///|
impl Eq for AppModel with equal(_, _) {
  false
}

///|
fn main {
  let runtime = new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          AppModel(initial_model()),
          @cmd.batch([
            emit(ProductsAction(Refresh)),
            emit(CompanySetupAction(Refresh)),
            emit(CharterAction(Load)),
            emit(saved_page_route()),
            dispatch_history_listener(emit),
          ]),
        )
      },
      update=(model, msg, emit) => {
        let (cmd, next) = update(emit, msg, model.0)
        (AppModel(next), cmd)
      },
    )
    model.map(model => view(emit, model.0))
  })
  runtime.mount("app")
}
