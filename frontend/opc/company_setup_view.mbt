///|
fn company_setup_status(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.company_setup
  div(class="boundary-note") <| [
    strong("公司工作区"),
    p("登录身份：" + products_state_label(state.session_state)),
    p(
      "正式档案：" +
      products_state_label(state.profile_state) +
      " · 组织单位：" +
      products_state_label(state.units_state),
    ),
    if state.units_note.is_empty() {
      @html.nothing
    } else {
      p(state.units_note)
    },
    if model.company_saved {
      div <| [
        strong(model.company_name),
        p(
          "已核实组织单位：" +
          company_setup_unit_label(company_setup_profile_unit(state).unwrap()),
        ),
        if company_setup_profile_unit(state).unwrap().name !=
          state.profile.unwrap().unit_name {
          small(
            "建档时记录的单位名称：" +
            (if state.profile.unwrap().unit_name.is_empty() {
              "名称未提供"
            } else {
              state.profile.unwrap().unit_name
            }) +
            "；上方显示当前读取的名称，组织身份未改变。",
          )
        } else {
          @html.nothing
        },
        small(
          "已持久化的组织工作区身份；不代表法律注册、资金、授权或就绪状态。首次创建后此处只读。",
        ),
      ]
    } else if state.profile_state == "empty" {
      p(
        "服务已确认尚无公司档案。可以创建工作区，或继续使用已有公司项目。",
      )
    } else if state.profile_state == "ready" {
      p("已读到档案，仍需核实它指向的实际组织单位。")
    } else {
      @html.nothing
    },
    secondary_button(
      emit,
      CompanySetupAction(Refresh),
      "重新读取身份与公司",
    ),
    if state.storage.is_empty() {
      @html.nothing
    } else {
      small("恢复存储：" + state.storage)
    },
  ]
}

///|
fn company_setup_operation_view(
  emit : @rabbita.Emit[Msg],
  op : CompanySetupOperation,
  kind : String,
) -> @html.Html {
  div <| [
    p(op.note),
    if kind == "project" && op.recover_only {
      secondary_button(
        emit,
        CompanySetupAction(DismissRecent),
        "关闭历史项目恢复提示",
      )
    } else {
      @html.nothing
    },
    match op.request {
      Some(request) =>
        div <| [
          small("待核实请求：" + request.name + " · " + request.key),
          if !company_setup_busy(op) {
            div(class="form-actions") <| [
              secondary_button(
                emit,
                CompanySetupAction(Recover(kind)),
                "核实正式记录",
              ),
              if op.phase == "retryable" {
                primary_button(
                  emit,
                  CompanySetupAction(Save(kind)),
                  "重试相同创建请求",
                )
              } else {
                @html.nothing
              },
            ]
          } else {
            @html.nothing
          },
        ]
      None => @html.nothing
    },
  ]
}

///|
fn company_setup_form(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.company_setup
  let editable = company_setup_company_editable(model)
  section(
    class="inline-form",
    attrs=@html.Attrs::build().aria_label("建立公司工作区"),
  ) <| [
    h3("建立公司工作区"),
    company_setup_status(emit, model),
    if editable {
      div <| [
        div(class="field") <| [
          label(
            attrs=@html.Attrs::build().for_("company-name"),
            "工作区 / 公司经营名称",
          ),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("company-name"),
            value=model.company_name,
            on_input=emit.map(value => InputCompanyName(value)),
            placeholder="填写实际使用的名称",
          ),
        ],
        p(
          "默认创建新的组织工作区根；如需绑定已导入单位，请明确选择。",
        ),
        secondary_button(
          emit,
          CompanySetupAction(Input("company_unit", "")),
          if state.company_unit_id.is_empty() {
            "已选择：新建工作区根"
          } else {
            "新建工作区根"
          },
        ),
        div <| state.units
        .filter(unit => unit.source == "imported")
        .map(unit => {
          secondary_button(
            emit,
            CompanySetupAction(Input("company_unit", unit.id)),
            (if state.company_unit_id == unit.id {
              "已选择："
            } else {
              "绑定："
            }) +
            company_setup_unit_label(unit),
          )
        }),
        if state.profile_state == "empty" &&
          ["ready", "empty"].contains(state.units_state) {
          primary_button(emit, SaveCompany, "保存公司工作区")
        } else {
          p("成功读取空档案后才可首次创建。")
        },
      ]
    } else {
      @html.nothing
    },
    company_setup_operation_view(emit, state.company, "company"),
  ]
}

///|
fn company_setup_project_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.company_setup
  section(class="section-block project-create") <| [
    h3("创建实际公司项目"),
    p(
      "新公司可先保存公司工作区，再选择实际组织单位；已有单位无需另建公司档案。创建项目不会自动创建任务或永久绑定产品。",
    ),
    p("组织单位：" + products_state_label(state.units_state)),
    if state.units_note.is_empty() {
      @html.nothing
    } else {
      p(state.units_note)
    },
    secondary_button(
      emit,
      CompanySetupAction(Refresh),
      "读取组织单位与身份",
    ),
    if state.units_state == "empty" {
      div <| [
        p(
          if state.units_note.is_empty() {
            "读取成功，当前没有组织单位。"
          } else {
            "没有可选择的单位；异常组织数据需修复，也可建立新的公司工作区。"
          },
        ),
        secondary_button(emit, OpenCompanyForm, "建立公司工作区"),
      ]
    } else {
      @html.nothing
    },
    if company_setup_editable(state.project) {
      div <| [
        div(class="field") <| [
          label(
            attrs=@html.Attrs::build().for_("new-project-code"),
            "项目编号",
          ),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("new-project-code"),
            value=state.project_code,
            on_input=emit.map(value => {
              CompanySetupAction(Input("project_code", value))
            }),
          ),
        ],
        div(class="field") <| [
          label(
            attrs=@html.Attrs::build().for_("new-project-name"),
            "项目名称",
          ),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("new-project-name"),
            value=state.project_name,
            on_input=emit.map(value => {
              CompanySetupAction(Input("project_name", value))
            }),
          ),
        ],
        div <| state.units.map(unit => {
          secondary_button(
            emit,
            CompanySetupAction(Input("project_unit", unit.id)),
            (if state.project_unit_id == unit.id {
              "已选择："
            } else {
              "选择组织单位："
            }) +
            company_setup_unit_label(unit),
          )
        }),
        if state.units_state == "ready" {
          primary_button(
            emit,
            CompanySetupAction(Save("project")),
            "创建公司项目",
          )
        } else {
          @html.nothing
        },
      ]
    } else {
      @html.nothing
    },
    company_setup_operation_view(emit, state.project, "project"),
    match state.exact_project {
      Some(project) =>
        div(class="boundary-note") <| [
          p(
            "精确读取核实的项目：" +
            project.name +
            " · " +
            project.id,
          ),
          small(
            "此记录来自精确 ID 读取，即使不在有数量上限的项目列表中也仍保留。",
          ),
          secondary_button(
            emit,
            CompanySetupAction(UseProject),
            "选择此项目用于当前产品工作",
          ),
        ]
      None => @html.nothing
    },
  ]
}
