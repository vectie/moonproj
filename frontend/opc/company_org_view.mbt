///|
fn charter_role_card(
  charter : CompanyCharter,
  role : CharterRole,
) -> @html.Html {
  let reports_label = charter_role_display_name(charter, role.reports_to)
  article(
    class="org-role-card",
    attrs=@html.Attrs::build()
      .data_set("role-id", role.id)
      .data_set("tier", role.tier.to_string())
      .data_set("kind", role.kind),
  ) <| [
    div(class="org-role-head") <| [
      div(class="org-role-title") <| [
        h3(role.name),
        span(
          class="org-kind-badge",
          attrs=@html.Attrs::build().data_set("kind", role.kind),
          if role.kind == "human" {
            "人"
          } else {
            "Agent"
          },
        ),
        span(class="org-version-badge", role.version),
      ],
      span(
        class="org-status-badge",
        attrs=@html.Attrs::build().data_set("status", role.status),
        charter_role_status_label(role.status),
      ),
    ],
    if !reports_label.is_empty() {
      p(class="org-role-meta", "汇报对象：" + reports_label)
    } else {
      @html.nothing
    },
    if !role.mission.is_empty() {
      p(class="org-role-mission", role.mission)
    } else {
      @html.nothing
    },
    div(class="org-role-boundaries") <| [
      if !role.powers.is_empty() {
        div(class="org-boundary-block org-powers") <| [
          small("授权范围"),
          div(class="org-power-chips") <| role.powers.map(item => {
            span(
              class="org-power-chip",
              attrs=@html.Attrs::build().title(item),
              charter_power_label(item),
            )
          }),
        ]
      } else {
        @html.nothing
      },
      if !role.limits.is_empty() {
        div(class="org-boundary-block org-limits") <| [
          small("红线边界"),
          ul <| role.limits.map(item => li(item)),
        ]
      } else {
        @html.nothing
      },
    ],
    if !role.skill_ref.is_empty() ||
      (!role.model.is_empty() && role.model != "human") {
      div(class="org-role-foot") <| [
        if !role.skill_ref.is_empty() {
          span(class="org-skill-ref", attrs=@html.Attrs::build().title(role.skill_ref), role.skill_ref)
        } else {
          @html.nothing
        },
        if !role.model.is_empty() && role.model != "human" {
          span(class="org-model-tag", role.model)
        } else {
          @html.nothing
        },
      ]
    } else {
      @html.nothing
    },
  ]
}

///|
fn charter_role_form_view(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
) -> @html.Html {
  if !state.role_form_open {
    return @html.nothing
  }
  div(
    class="charter-inline-form",
    attrs=@html.Attrs::build().aria_label("新增组织角色"),
  ) <| [
    div(class="charter-form-grid") <| [
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-role-name"), "角色名称"),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-role-name"),
          value=state.role_name,
          placeholder="例如：语料核验专员",
          on_input=emit.map(v => CharterAction(InputRole("name", v))),
        ),
      ],
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-role-tier"), "权力层级"),
        @html.select(
          attrs=@html.Attrs::build().id("charter-role-tier"),
          on_change=emit.map(v => CharterAction(InputRole("tier", v))),
        ) <| [
          @html.option(
            value="0",
            selected=state.role_tier == 0,
            "Tier 0 · 创始人",
          ),
          @html.option(
            value="1",
            selected=state.role_tier == 1,
            "Tier 1 · 协调负责人",
          ),
          @html.option(
            value="2",
            selected=state.role_tier == 2,
            "Tier 2 · 专业执行与审查",
          ),
        ],
      ],
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-role-kind"), "执行主体"),
        @html.select(
          attrs=@html.Attrs::build().id("charter-role-kind"),
          on_change=emit.map(v => CharterAction(InputRole("kind", v))),
        ) <| [
          @html.option(
            value="agent",
            selected=state.role_kind == "agent",
            "Agent",
          ),
          @html.option(value="human", selected=state.role_kind == "human", "人"),
        ],
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-role-reports"),
          "汇报对象 ID",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-role-reports"),
          value=state.role_reports_to,
          placeholder="例如：role-director",
          on_input=emit.map(v => CharterAction(InputRole("reports_to", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-role-mission"),
          "角色使命",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-role-mission"),
          value=state.role_mission,
          placeholder="该角色负责的核心产出与职责",
          on_input=emit.map(v => CharterAction(InputRole("mission", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-role-skill"),
          "Skill 路径",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-role-skill"),
          value=state.role_skill_ref,
          placeholder="例如：skills/corpus-verifier/SKILL.md",
          on_input=emit.map(v => CharterAction(InputRole("skill_ref", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-role-powers"),
          "授权范围（逗号或换行分隔）",
        ),
        @html.textarea(
          id="charter-role-powers",
          value=state.role_powers,
          rows=2,
          placeholder="检索只读语料，生成引文核验清单",
          on_input=emit.map(v => CharterAction(InputRole("powers", v))),
          "",
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-role-limits"),
          "红线边界（逗号或换行分隔）",
        ),
        @html.textarea(
          id="charter-role-limits",
          value=state.role_limits,
          rows=2,
          placeholder="不得修改原始论文，不得越权签收",
          on_input=emit.map(v => CharterAction(InputRole("limits", v))),
          "",
        ),
      ],
    ],
    div(class="charter-form-actions") <| [
      button(
        type_="button",
        class="button button-primary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(SubmitRole)),
        if state.saving {
          "正在保存…"
        } else {
          "保存角色"
        },
      ),
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(ToggleRoleForm)),
        "取消",
      ),
    ],
  ]
}

///|
fn charter_evo_form_view(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
) -> @html.Html {
  if !state.evo_form_open {
    return @html.nothing
  }
  div(
    class="charter-inline-form",
    attrs=@html.Attrs::build().aria_label("记录演化升级"),
  ) <| [
    div(class="charter-form-grid") <| [
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-evo-target"), "升级对象"),
        @html.select(
          attrs=@html.Attrs::build().id("charter-evo-target"),
          on_change=emit.map(v => CharterAction(InputEvo("target", v))),
        ) <| [
          @html.option(
            value="agent",
            selected=state.evo_target == "agent",
            "Agent 能力升级",
          ),
          @html.option(
            value="company",
            selected=state.evo_target == "company",
            "公司规则升级",
          ),
        ],
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-evo-target-id"),
          "对象标识",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-evo-target-id"),
          value=state.evo_target_id,
          placeholder="例如：role-defense-editor 或 charter",
          on_input=emit.map(v => CharterAction(InputEvo("target_id", v))),
        ),
      ],
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-evo-change"), "演化变更"),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-evo-change"),
          value=state.evo_change,
          placeholder="例如：新增开题答辩逐条反证检查清单（v2）",
          on_input=emit.map(v => CharterAction(InputEvo("change", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-evo-evidence"),
          "触发依据 / 复盘证据",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-evo-evidence"),
          value=state.evo_evidence,
          placeholder="例如：导师组第 2 轮评审意见",
          on_input=emit.map(v => CharterAction(InputEvo("evidence", v))),
        ),
      ],
    ],
    div(class="charter-form-actions") <| [
      button(
        type_="button",
        class="button button-primary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(SubmitEvo)),
        if state.saving {
          "正在保存…"
        } else {
          "记录升级"
        },
      ),
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(ToggleEvoForm)),
        "取消",
      ),
    ],
  ]
}

///|
fn workspace_org_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let state = model.charter
  section(
    class="charter-surface charter-org-view",
    attrs=@html.Attrs::build().aria_label("组织与权力结构"),
  ) <| [
    div(class="flow-heading") <| [
      div <| [
        small("公司治理与编排"),
        h1("组织与权力结构"),
      ],
      match state.charter {
        Some(_) =>
          div(class="charter-heading-actions") <| [
            button(
              type_="button",
              class="button button-secondary button-small",
              disabled=state.saving,
              on_click=emit(CharterAction(ToggleRoleForm)),
              "新增角色",
            ),
            button(
              type_="button",
              class="button button-secondary button-small",
              disabled=state.saving,
              on_click=emit(CharterAction(ToggleEvoForm)),
              "记录演化升级",
            ),
          ]
        None => @html.nothing
      },
    ],
    match state.charter {
      None => charter_empty_or_error_panel(emit, state, "组织与权力结构")
      Some(charter) =>
        div(class="charter-org-body") <| [
          charter_inline_status_banner(emit, state),
          charter_role_form_view(emit, state),
          charter_evo_form_view(emit, state),
          div(class="org-tier-stack") <| [0, 1, 2].map(tier => {
            let tier_roles = charter.roles.filter(r => r.tier == tier)
            section(
              class="org-tier-band",
              attrs=@html.Attrs::build().data_set("tier", tier.to_string()),
            ) <| [
              div(class="charter-subhead") <| [
                h2(charter_tier_title(tier)),
                span(
                  class="charter-count-pill",
                  tier_roles.length().to_string() + " 位",
                ),
              ],
              if tier_roles.is_empty() {
                p(class="charter-muted-note", "本层级尚未登记角色。")
              } else {
                div(class="org-tier-grid") <| tier_roles.map(role => {
                  charter_role_card(charter, role)
                })
              },
            ]
          }),
          section(
            class="charter-evolution",
            attrs=@html.Attrs::build().aria_label("演化记录"),
          ) <| [
            div(class="charter-subhead") <| [
              h2("演化记录"),
              span(
                class="charter-count-pill",
                charter.evolution_log.length().to_string() + " 条",
              ),
            ],
            if charter.evolution_log.is_empty() {
              p(class="charter-muted-note", "尚未记录组织或 Agent 能力演化。")
            } else {
              @html.ol(class="evolution-timeline") <| charter.evolution_log.map(entry => {
                let target_label = charter_role_display_name(
                  charter,
                  entry.target_id,
                )
                li(
                  class="evolution-item",
                  attrs=@html.Attrs::build()
                    .data_set("evo-id", entry.id)
                    .data_set("target", entry.target),
                ) <| [
                  div(class="evolution-item-meta") <| [
                    if !entry.date.is_empty() {
                      span(class="evolution-date", entry.date)
                    } else {
                      @html.nothing
                    },
                    span(
                      class="evolution-target-badge",
                      attrs=@html.Attrs::build().data_set("target", entry.target),
                      if entry.target == "company" {
                        "公司规则"
                      } else {
                        "Agent 升级"
                      },
                    ),
                    if !target_label.is_empty() {
                      span(
                        class="evolution-target-id",
                        attrs=@html.Attrs::build().title(entry.target_id),
                        target_label,
                      )
                    } else {
                      @html.nothing
                    },
                  ],
                  p(class="evolution-change", entry.change),
                  if !entry.evidence.is_empty() {
                    small(
                      class="evolution-evidence",
                      "依据：" + entry.evidence,
                    )
                  } else {
                    @html.nothing
                  },
                ]
              })
            },
          ],
        ]
    },
  ]
}
