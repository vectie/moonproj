///|
fn products_repository_label(row : ProductDefinition) -> String {
  match row.repository_state {
    "present" => "源码目录存在"
    "missing" => "已配置源码路径，当前不可用"
    _ => "源码位置未知"
  }
}

///|
fn products_document_view(doc : ProductDocument) -> @html.Html {
  div(class="product-document") <| [
    strong(doc.title),
    p("作者撰写的 PRD 快照 · " + doc.version),
    small(doc.provenance),
    if doc.availability == "available" && !doc.url.is_empty() {
      a(
        href=doc.url,
        class="button button-secondary button-small",
        "下载 PRD 快照（DOCX）",
      )
    } else {
      p(
        if doc.availability == "available" {
          "PRD 有记录，当前没有可用下载入口"
        } else {
          "PRD 已声明，当前文件不可用"
        },
      )
    },
  ]
}

///|
fn products_work_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  row : ProductDefinition,
) -> @html.Html {
  let state = model.products
  let chosen = products_pending_work(state)
  section(class="section-block product-work") <| [
    h3("下一步 · 准备一个目标"),
    match chosen {
      Some(group) =>
        div(class="boundary-note") <| [
          strong("已选择：" + group.title),
          p(group.next_action),
          p(
            "选择公司项目后继续准备；准备前的选择仅保留在当前页面。",
          ),
          details(class="journey-details") <| [
            summary("所选工作的验收与范围"),
            ul <| group.acceptance.map(text => li(text)),
            small("范围：" + group.requirement_ids.join(", ")),
          ],
          secondary_button(
            emit,
            ProductsAction(CancelWorkChoice),
            "取消本次选择",
          ),
        ]
      None => @html.nothing
    },
    p(
      "先选择本次工作的公司项目，再填写要交付的结果和验收标准。",
    ),
    p(
      if row.company_project_id.is_empty() {
        "尚未关联公司项目。产品、公司项目和任务是不同身份；下方选择仅用于本次工作，不会保存永久关联。"
      } else {
        "目录声明的公司项目：" +
        row.company_project_id +
        "。读取验证后才可用于本次工作。"
      },
    ),
    secondary_button(emit, ProductsAction(LoadProjects), "读取公司项目"),
    p(
      "公司项目：" +
      (if state.project_state == "empty" && !state.project_note.is_empty() {
        "没有可选择项目"
      } else {
        products_state_label(state.project_state)
      }),
    ),
    if state.project_note.is_empty() {
      @html.nothing
    } else {
      p(state.project_note)
    },
    if state.project_state == "ready" {
      div(
        class="product-project-picker",
        attrs=@html.Attrs::build().aria_label(
          "选择本次工作的公司项目",
        ),
      ) <| state.projects.map(project => {
        button(
          type_="button",
          class=if project.id == state.project_id {
            "button button-primary"
          } else {
            "button button-secondary"
          },
          attrs=@html.Attrs::build().aria_pressed(
            if project.id == state.project_id {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(ProductsAction(SelectProject(project.id))),
          project.name + " · " + project.id,
        )
      })
    } else {
      @html.nothing
    },
    if products_project_exists(state) {
      div <| [
        p("本次公司项目 ID：" + state.project_id),
        div(class="form-actions") <| [
          primary_button(
            emit,
            ProductsAction(Prepare),
            if chosen is Some(_) {
              "准备所选工作"
            } else {
              "准备任务"
            },
          ),
        ],
        small(
          "准备仅打开已有编排表单。执行工作区必须另行明确填写；不会从产品仓库推断。",
        ),
      ]
    } else {
      p(
        "准备新任务前，先选择读取到的有效公司项目。产品历史无需选择公司项目。",
      )
    },
    details(
      class="journey-details",
      open=state.project_state == "empty" ||
        model.company_setup.project.request is Some(_) ||
        model.company_setup.project.phase != "idle" ||
        !["idle", "loading", "ready", "empty"].contains(
          model.company_setup.units_state,
        ) ||
        !["", "可恢复"].contains(model.company_setup.storage) ||
        !model.company_setup.units_note.is_empty(),
    ) <| [
      summary("需要新项目？创建公司项目"),
      if !["", "可恢复"].contains(model.company_setup.storage) {
        p(class="boundary-note", model.company_setup.storage)
      } else {
        @html.nothing
      },
      company_setup_project_view(emit, model),
    ],
    details(class="journey-details", open=state.work_state != "idle") <| [
      summary("继续已有工作 · 产品任务历史"),
      h3("产品任务历史"),
      p(
        "只显示明确记录为此产品的正式任务，可跨公司项目查看。未标记产品的旧任务不会按项目归入此列表。",
      ),
      secondary_button(emit, ProductsAction(LoadWork), "读取产品任务"),
      p("产品任务：" + products_state_label(state.work_state)),
      div(class="product-task-list") <| state.tasks
      .filter(task => task.product_id == row.id)
      .map(task => {
        article(class="repo-card") <| [
          strong(task.title),
          small(
            task.id +
            " · " +
            task.product_id +
            " · " +
            task.project_id +
            " · " +
            task.state,
          ),
          secondary_button(
            emit,
            ProductsAction(OpenTask(task.id)),
            "打开正式任务",
          ),
          a(href="?task=" + dispatch_url_encode(task.id), "任务固定链接"),
        ]
      }),
    ],
  ]
}

///|
fn products_detail_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  row : ProductDefinition,
) -> @html.Html {
  let state = model.products
  article(
    class="product-detail",
    attrs=@html.Attrs::build().aria_label("产品详情 " + row.name),
  ) <| [
    div(class="product-detail-heading") <| [
      h2(row.name),
      small(row.id + " · " + row.kind),
    ],
    h3("产品目的"),
    p(row.purpose),
    if products_pending_work(state) is Some(_) {
      products_work_view(emit, model, row)
    } else {
      @html.nothing
    },
    products_inventory_view(emit, model, row),
    if products_pending_work(state) is None {
      products_work_view(emit, model, row)
    } else {
      @html.nothing
    },
    details(class="journey-details") <| [
      summary("产品意图与定义来源"),
      h3("产品意图"),
      p(row.philosophy),
      div <| row.philosophy_paragraphs.map(text => p(text)),
      small(
        (if row.philosophy_kind == "founder_intent" {
          "当前负责人方向"
        } else {
          "作者撰写的 PRD 定义"
        }) +
        " · " +
        row.philosophy_version,
      ),
      small("来源：" + row.philosophy_source),
      div(class="boundary-note") <| [
        strong("定义与观察分开"),
        p(
          "产品意图与 PRD 说明想做什么，不代表已经实现、验收、安装或正在运行。源码与文档状态只表示当前服务环境可读取的资源。",
        ),
      ],
    ],
    details(class="journey-details") <| [
      summary("源码与登记"),
      p("目录：已配置 · " + products_repository_label(row)),
      p(
        if row.engineering_target.is_empty() {
          "工程审计：未登记"
        } else {
          "工程审计：已登记 " + row.engineering_target
        },
      ),
      if row.repository_path.is_empty() {
        @html.nothing
      } else {
        small("配置路径：" + row.repository_path)
      },
      if row.repository_url.has_prefix("https://") {
        a(href=row.repository_url, "查看已记录的源码仓库")
      } else {
        small("没有可验证的源码远程链接")
      },
      if row.repository_revision.is_empty() {
        @html.nothing
      } else {
        small("来源记录版本：" + row.repository_revision)
      },
    ],
    details(class="journey-details") <| [
      summary("产品文档 · PRD"),
      p(
        "下载是打包的作者快照，不会自动同步 Library，也不是实现完成证明。",
      ),
      if row.documents.is_empty() {
        p("没有声明的产品文档")
      } else {
        div <| row.documents.map(products_document_view)
      },
    ],
    details(
      class="journey-details",
      open=!["idle", "loading", "ready", "not_enrolled"].contains(
          state.admission_state,
        ) ||
        !["idle", "loading", "ready", "not_enrolled"].contains(
          state.engineering_state,
        ),
    ) <| [
      summary("已观察的能力与证据"),
      p("需求准入：" + products_state_label(state.admission_state)),
      if state.admission_state == "ready" {
        p(
          if model.product_in_gate_persisted {
            "已记录需求决策：" + model.product_in_gate_decision
          } else {
            "没有持久化的需求准入记录；结论未知。"
          },
        )
      } else {
        @html.nothing
      },
      p("工程证据：" + products_state_label(state.engineering_state)),
      if state.engineering_state == "ready" {
        p(
          if model.engineering_freshness == "missing" {
            "没有工程证据；能力与出厂结论未知。"
          } else if model.engineering_freshness == "stale" {
            "历史证据已过期，不代表当前可信能力。"
          } else {
            "证据新鲜度：" +
            model.engineering_freshness +
            " · 工程状态：" +
            model.engineering_health
          },
        )
      } else {
        @html.nothing
      },
      if !row.engineering_target.is_empty() {
        div(class="form-actions") <| [
          secondary_button(
            emit,
            ProductsAction(OpenEngineering(MoonSuite)),
            "查看工程证据",
          ),
          secondary_button(
            emit,
            ProductsAction(OpenEngineering(Quality)),
            "配置发布候选",
          ),
        ]
      } else {
        p(
          "产品目录可独立读取；此产品尚未成为工程审计目标。",
        )
      },
      small(
        "选中产品只读取数据，不会启动审计、创建任务或调用模型。",
      ),
    ],
  ]
}

///|
fn products_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.products
  let rows = products_visible(state)
  section(class="page products-page") <| [
    page_intro(
      Products,
      secondary_button(emit, ProductsAction(Refresh), "刷新产品目录"),
    ),
    details(class="journey-details product-catalog-help") <| [
      summary("目录说明"),
      p(
        "范围：20 个 Moon 产品。LunaNexa、LunaFlux、LunaFlex、LunaChip、LunaRein 是独立基础设施依赖；MoonStat 已退役，MoonProp 与 Mooncake 不在本轮范围。",
      ),
      if state.state == "ready" {
        p(
          state.rows.length().to_string() +
          " 个已配置的活跃产品定义；数量不代表已安装、已完成或可发布。",
        )
      } else {
        @html.nothing
      },
    ],
    if state.state == "ready" {
      @html.nothing
    } else {
      div(
        class="product-catalog-state",
        attrs=@html.Attrs::build().aria_label("产品目录读取状态"),
      ) <| [
        strong("产品目录：" + products_state_label(state.state)),
        if state.state == "empty" {
          p("服务返回空目录；没有使用演示产品填充。")
        } else {
          p(
            "目录读取独立于数据库与执行运行时；失败时不会显示虚构产品。",
          )
        },
      ]
    },
    if state.rows.is_empty() {
      @html.nothing
    } else {
      div(class="product-toolbar") <| [
        div(class="field") <| [
          label(
            attrs=@html.Attrs::build().for_("product-search"),
            "搜索产品名称、ID 或目的",
          ),
          input(
            input_type=Text,
            attrs=@html.Attrs::build().id("product-search"),
            value=state.search,
            on_input=emit.map(value => ProductsAction(Search(value))),
            placeholder="例如 MoonBook",
          ),
        ],
        secondary_button(
          emit,
          ProductsAction(Reverse),
          if state.reverse {
            "名称排序：Z → A"
          } else {
            "名称排序：A → Z"
          },
        ),
      ]
    },
    div(class="products-layout") <| [
      div(
        class="product-list",
        attrs=@html.Attrs::build().aria_label("产品列表"),
      ) <| [
        if state.state == "ready" && rows.is_empty() {
          p("没有匹配产品；已有选择不会因筛选而改变。")
        } else {
          @html.nothing
        },
        div <| rows.map(row => {
          button(
            type_="button",
            class=if row.id == state.selected_id {
              "product-list-item is-selected"
            } else {
              "product-list-item"
            },
            attrs=@html.Attrs::build()
              .aria_label("选择产品 " + row.name)
              .aria_pressed(
                if row.id == state.selected_id {
                  "true"
                } else {
                  "false"
                },
              ),
            on_click=emit(ProductsAction(Select(row.id))),
            [
              strong(row.name),
              p(row.purpose),
              match products_inventory(state, row.id) {
                Some(inventory) =>
                  div <| [
                    small(
                      "下一范围：" +
                      inventory.next_milestone.title +
                      " · " +
                      products_inventory_range(
                        inventory.next_milestone.estimate_low_days,
                        inventory.next_milestone.estimate_high_days,
                      ),
                    ),
                  ]
                None => small("剩余工作：尚无可用评估")
              },
            ],
          )
        }),
      ],
      match products_selected(state) {
        Some(row) => products_detail_view(emit, model, row)
        None =>
          div(class="product-detail") <| [
            h2(
              if state.route_id.is_empty() {
                "选择一个产品"
              } else {
                "恢复产品选择"
              },
            ),
            p(products_route_note(state)),
          ]
      },
    ],
  ]
}

///|
fn engineering_catalog_selector(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  div <| [
    secondary_button(emit, Navigate(Products), "返回产品目录"),
    p("产品目录：" + products_state_label(model.products.state)),
    div(class="tag-row") <| model.products.rows
    .filter(row => !row.engineering_target.is_empty())
    .map(row => {
      engineering_project_button(
        emit,
        model,
        row.id,
        row.name + " · " + row.id,
      )
    }),
  ]
}

///|
fn products_preparation_context(model : Model) -> @html.Html {
  match model.products.prepared_product_snapshot {
    Some(row) =>
      div(class="boundary-note") <| [
        strong("产品上下文：" + row.name + " · " + row.id),
        p(row.purpose),
        details(class="journey-details") <| [
          summary("查看产品意图与来源"),
          p(row.philosophy),
          div <| row.philosophy_paragraphs.map(text => p(text)),
          small("意图来源：" + row.philosophy_source),
        ],
        small(
          "公司项目：" +
          model.products.prepared_project_id +
          "。请填写本次工作自己的交付与验收标准。",
        ),
      ]
    None => @html.nothing
  }
}
