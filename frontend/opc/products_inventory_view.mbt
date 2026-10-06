///|
fn products_inventory_group_view(
  emit : @rabbita.Emit[Msg],
  row : ProductDefinition,
  group : @work_inventory.WorkGroup,
  first : Bool,
) -> @html.Html {
  details(class="product-work-group", open=first) <| [
    summary <| [
      strong(group.title),
      small(products_inventory_estimate(group)),
    ],
    p(group.next_action),
    p(class="boundary-note", group.estimate_scope),
    small(
      "估算信心：" +
      (match group.confidence {
        "high" => "高"
        "medium" => "中"
        _ => "低"
      }) +
      " · " +
      products_inventory_status(group.status),
    ),
    details(class="journey-details") <| [
      summary("验收标准、依赖与估算前提"),
      strong("验收标准"),
      ul <| group.acceptance.map(text => li(text)),
      strong("依赖"),
      if group.dependencies.is_empty() {
        p("没有额外声明的依赖；仍需按 PRD 验收。")
      } else {
        ul <| group.dependencies.map(text => li(text))
      },
      strong("估算前提"),
      ul <| group.assumptions.map(text => li(text)),
      small("范围 ID：" + group.requirement_ids.join(", ")),
      small("工作项 ID：" + group.id),
      details <| [
        summary("证据来源"),
        ul <| group.evidence.map(text => li(text)),
      ],
    ],
    secondary_button(
      emit,
      ProductsAction(PrepareWork(row.id, group.id)),
      "准备此工作",
    ),
  ]
}

///|
fn products_inventory_requirement_view(
  row : @work_inventory.Requirement,
) -> @html.Html {
  details(class="product-requirement") <| [
    summary <| [
      strong(row.id + " · " + row.title),
      small(
        products_inventory_status(row.status) +
        " · " +
        row.priority +
        " · " +
        row.track,
      ),
    ],
    p(row.statement),
    strong("必须满足的验收"),
    ul <| row.acceptance.map(text => li(text)),
    strong("当前判断与未解决部分"),
    p(row.reason),
    if row.dependencies.is_empty() {
      @html.nothing
    } else {
      div <| [
        strong("依赖"),
        ul <| row.dependencies.map(text => li(text)),
      ]
    },
    details <| [
      summary("当前证据与历史判断"),
      ul <| row.evidence.map(text => li(text)),
      p(
        "2026-09-30 PRD 历史判断：" +
        row.historical_status +
        "。它不是今天的完成证明。",
      ),
      ul <| row.historical_evidence.map(text => li(text)),
    ],
  ]
}

///|
fn products_inventory_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  row : ProductDefinition,
) -> @html.Html {
  let state = model.products
  let inventory = match products_inventory(state, row.id) {
    Some(inventory) => inventory
    None =>
      return section(class="section-block product-inventory") <| [
        h3("剩余工作清单"),
        p(
          if state.inventory_state == "invalid" {
            "打包工作清单无效或与 PRD 版本不匹配；请修复清单后刷新。产品定义和公司任务仍可分别读取。"
          } else {
            "本服务没有可用的 PRD 工作清单。没有将缺失清单解释为零剩余工作。"
          },
        ),
      ]
  }
  let requirements = products_inventory_visible(state, inventory)
  let milestone = inventory.next_milestone
  section(class="section-block product-inventory") <| [
    h3("剩余工作 · 从目标 PRD 到可验收结果"),
    p(
      class="inventory-provenance",
      "打包的产品工作清单 · 评估日期 " +
      inventory.as_of +
      " · 未写入公司数据库",
    ),
    div(class="boundary-note inventory-next") <| [
      strong("建议下一交付：" + milestone.title),
      p(
        products_inventory_range(
          milestone.estimate_low_days,
          milestone.estimate_high_days,
        ),
      ),
      p(milestone.scope),
      small(
        "估算信心：" +
        (match milestone.confidence {
          "high" => "高"
          "medium" => "中"
          _ => "低"
        }) +
        " · 仅限这项交付，不是产品总剩余量",
      ),
      match milestone.linked_group_id {
        Some(id) =>
          secondary_button(
            emit,
            ProductsAction(PrepareWork(row.id, id)),
            "准备建议的下一交付",
          )
        None => p("先完成上述证据审计，再估算实现范围。")
      },
    ],
    p(products_inventory_summary(inventory)),
    p(
      "这些数量表示要求的证据状态，不是完成比例；部分实现不等于整项未做。",
    ),
    p("当前关键缺口：" + inventory.current_gap),
    p(
      "下面的范围估算是有前提的工程人日；共享依赖和验证可能重叠，不应直接相加为发布日期。",
    ),
    div(class="product-work-groups") <| inventory.groups.map(group => {
      products_inventory_group_view(
        emit,
        row,
        group,
        milestone.linked_group_id == Some(group.id),
      )
    }),
    div(class="boundary-note") <| [
      strong("完整目标与估算边界"),
      p(inventory.full_target_estimate),
      p(inventory.vision_scope),
    ],
    details(class="journey-details") <| [
      summary(
        "查看全部 " +
        inventory.requirements.length().to_string() +
        " 项要求与验收标准",
      ),
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("requirement-search"),
          "查找要求 ID、标题或内容",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("requirement-search"),
          value=state.inventory_query,
          on_input=emit.map(text => ProductsAction(SearchWork(text))),
          placeholder="例如 MOONPROJ-R01",
        ),
      ],
      div(class="inventory-filters") <| [
        "all", "partial", "planned", "unverified", "verified", "missing",
      ].map(status => {
        button(
          type_="button",
          class="button button-secondary button-small",
          attrs=@html.Attrs::build().aria_pressed(
            if state.inventory_filter == status {
              "true"
            } else {
              "false"
            },
          ),
          on_click=emit(ProductsAction(FilterWork(status))),
          products_inventory_status(status),
        )
      }),
      p(
        "匹配 " +
        requirements.length().to_string() +
        " 项；筛选不会修改范围或评估。",
      ),
      div <| requirements.map(products_inventory_requirement_view),
    ],
    details(class="journey-details") <| [
      summary("原始 PRD 哲学、非目标与来源边界"),
      div <| inventory.philosophy.map(text => p(text)),
      strong("原始 PRD 的非目标"),
      ul <| inventory.non_goals.map(text => li(text)),
      p(
        "后续负责人方向有差异时，先补充验收定义，不静默删改原始非目标。",
      ),
      p(inventory.source_scope),
      small("目标来源：" + inventory.prd_source),
      small("PRD 快照 SHA256：" + inventory.prd_sha256),
    ],
  ]
}
