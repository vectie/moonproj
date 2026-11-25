///|
fn charter_resource_form_view(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
) -> @html.Html {
  if !state.resource_form_open {
    return @html.nothing
  }
  div(
    class="charter-inline-form",
    attrs=@html.Attrs::build().aria_label("登记公司资源"),
  ) <| [
    div(class="charter-form-grid") <| [
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-name"),
          "资源名称",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-res-name"),
          value=state.resource_name,
          placeholder="例如：OPC 研究知识库 MoonBook",
          on_input=emit.map(v => CharterAction(InputResource("name", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-kind"),
          "资源类别",
        ),
        @html.select(
          attrs=@html.Attrs::build().id("charter-res-kind"),
          on_change=emit.map(v => CharterAction(InputResource("kind", v))),
        ) <| [
          @html.option(
            value="moonbook",
            selected=state.resource_kind == "moonbook",
            "知识库 MoonBook",
          ),
          @html.option(
            value="corpus",
            selected=state.resource_kind == "corpus",
            "研究语料与数据",
          ),
          @html.option(
            value="tool",
            selected=state.resource_kind == "tool",
            "工具与脚本",
          ),
          @html.option(
            value="runtime",
            selected=state.resource_kind == "runtime",
            "算力与模型",
          ),
        ],
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-access"),
          "访问权限",
        ),
        @html.select(
          attrs=@html.Attrs::build().id("charter-res-access"),
          on_change=emit.map(v => CharterAction(InputResource("access", v))),
        ) <| [
          @html.option(
            value="read_only",
            selected=state.resource_access == "read_only",
            "只读",
          ),
          @html.option(
            value="read_write",
            selected=state.resource_access == "read_write",
            "可读写",
          ),
          @html.option(
            value="execute",
            selected=state.resource_access == "execute",
            "可执行",
          ),
        ],
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-owner"),
          "责任角色",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-res-owner"),
          value=state.resource_owner_role,
          placeholder="例如：role-director",
          on_input=emit.map(v => CharterAction(InputResource("owner_role", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-uri"),
          "路径 / URI",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-res-uri"),
          value=state.resource_uri,
          placeholder="例如：/path/to/opc-research-lab",
          on_input=emit.map(v => CharterAction(InputResource("uri", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-desk"),
          "MoonDesk 打开链接（可选）",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-res-desk"),
          value=state.resource_desk_url,
          placeholder="http://127.0.0.1:4201/?workspace=book-...",
          on_input=emit.map(v => CharterAction(InputResource("desk_url", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-res-notes"),
          "备注与边界",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-res-notes"),
          value=state.resource_notes,
          placeholder="例如：原始研究语料严格只读",
          on_input=emit.map(v => CharterAction(InputResource("notes", v))),
        ),
      ],
    ],
    div(class="charter-form-actions") <| [
      button(
        type_="button",
        class="button button-primary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(SubmitResource)),
        if state.saving {
          "正在保存…"
        } else {
          "登记并保存"
        },
      ),
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(ToggleResourceForm)),
        "取消",
      ),
    ],
  ]
}

///|
fn workspace_resources_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.charter
  section(
    class="charter-surface charter-resources-view",
    attrs=@html.Attrs::build().aria_label("公司资源清单"),
  ) <| [
    div(class="flow-heading") <| [
      div <| [
        small("知识、语料与工具台账"),
        h1("公司资源清单"),
      ],
      match state.charter {
        Some(_) =>
          button(
            type_="button",
            class="button button-secondary button-small",
            disabled=state.saving,
            on_click=emit(CharterAction(ToggleResourceForm)),
            "登记资源",
          )
        None => @html.nothing
      },
    ],
    match state.charter {
      None => charter_empty_or_error_panel(emit, state, "公司资源清单")
      Some(charter) =>
        div(class="charter-resources-body") <| [
          charter_inline_status_banner(emit, state),
          charter_resource_form_view(emit, state),
          if charter.resources.is_empty() {
            p(
              class="charter-muted-note",
              "尚未登记公司资源。点击上方“登记资源”绑定 MoonBook、语料库、工具或算力。",
            )
          } else {
            div(class="resource-groups") <| [
              "moonbook", "corpus", "tool", "runtime",
            ].map(kind => {
              let items = charter.resources.filter(r => r.kind == kind)
              if items.is_empty() {
                @html.nothing
              } else {
                section(
                  class="resource-group",
                  attrs=@html.Attrs::build().data_set("resource-kind", kind),
                ) <| [
                  div(class="charter-subhead") <| [
                    h2(charter_resource_kind_label(kind)),
                    span(
                      class="charter-count-pill",
                      items.length().to_string() + " 项",
                    ),
                    if kind == "runtime" {
                      @html.a(
                        href="http://127.0.0.1:15721/ui/rabbita#providers",
                        target=Blank,
                        class="button button-secondary button-small",
                        attrs=@html.Attrs::build()
                          .rel("noopener noreferrer")
                          .data_set("open-external", "moongate"),
                        "在 MoonGate 配置模型",
                      )
                    } else {
                      @html.nothing
                    },
                  ],
                  div(class="resource-grid") <| items.map(res => {
                    let owner_label = charter_role_display_name(
                      charter,
                      res.owner_role,
                    )
                    article(
                      class="resource-card",
                      attrs=@html.Attrs::build()
                        .data_set("resource-id", res.id)
                        .data_set("resource-kind", res.kind),
                    ) <| [
                      div(class="resource-card-head") <| [
                        h3(res.name),
                        span(
                          class="resource-access-badge",
                          attrs=@html.Attrs::build().data_set(
                            "access",
                            res.access,
                          ),
                          charter_access_label(res.access),
                        ),
                      ],
                      if !res.notes.is_empty() {
                        p(class="resource-notes", res.notes)
                      } else {
                        @html.nothing
                      },
                      if !owner_label.is_empty() {
                        small(class="resource-owner", "保管：" + owner_label)
                      } else {
                        @html.nothing
                      },
                      if !res.uri.is_empty() {
                        p(
                          class="resource-uri",
                          attrs=@html.Attrs::build().title(res.uri),
                          res.uri,
                        )
                      } else {
                        @html.nothing
                      },
                      if !res.desk_url.is_empty() {
                        div(class="resource-actions") <| [
                          button(
                            type_="button",
                            class="button button-secondary button-small",
                            on_click=emit(
                              WorkspaceAction(
                                OpenResource(res.name, res.desk_url),
                              ),
                            ),
                            "在 MoonDesk 打开",
                          ),
                        ]
                      } else {
                        @html.nothing
                      },
                    ]
                  }),
                ]
              }
            })
          },
        ]
    },
  ]
}
