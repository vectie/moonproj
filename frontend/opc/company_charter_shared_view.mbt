///|
fn charter_stage_mark(status : String) -> String {
  match status {
    "achieved" => "✓"
    "active" => "●"
    _ => "○"
  }
}

///|
fn charter_stage_status_label(status : String) -> String {
  match status {
    "achieved" => "已达成"
    "active" => "当前阶段"
    _ => "待推进"
  }
}

///|
fn charter_role_status_label(status : String) -> String {
  match status {
    "evolving" => "演化中"
    "paused" => "已暂停"
    _ => "运行中"
  }
}

///|
fn charter_resource_kind_label(kind : String) -> String {
  match kind {
    "moonbook" => "知识库 MoonBook"
    "corpus" => "研究语料与数据"
    "tool" => "工具与脚本"
    "runtime" => "算力与模型"
    _ => "其他资源"
  }
}

///|
fn charter_access_label(access : String) -> String {
  match access {
    "read_write" => "可读写"
    "execute" => "可执行"
    _ => "只读"
  }
}

///|
fn charter_tier_title(tier : Int) -> String {
  match tier {
    0 => "Tier 0 · 创始人（最终问责）"
    1 => "Tier 1 · 协调负责人（统筹拆解）"
    _ => "Tier 2 · 专业执行与独立审查 Agent"
  }
}

///|
fn charter_role_display_name(
  charter : CompanyCharter,
  role_id : String,
) -> String {
  if role_id.is_empty() {
    return ""
  }
  for role in charter.roles {
    if role.id == role_id {
      return role.name
    }
  }
  role_id
}

///|
fn charter_power_label(token : String) -> String {
  match token {
    "mission:set" => "设定使命"
    "stage:accept" => "里程碑验收"
    "authority:grant" => "权限审批"
    "external:defend" => "对外答辩"
    "skill:promote" => "规则演化审批"
    "work:decompose" => "任务拆解"
    "worker:spawn" => "派发专员"
    "draft:integrate" => "整合交付"
    "decision:escalate" => "升级关键决策"
    "corpus:read" => "读取语料"
    "evidence:audit" => "证据核查"
    "claim:verify" => "论断校验"
    "draft:edit" => "修订草稿"
    "slides:revise" => "优化演示稿"
    "script:refine" => "打磨讲稿"
    "draft:critique" => "独立审查"
    "defense:challenge" => "答辩质询"
    "review:block" => "阻断不合规交付"
    _ => token
  }
}

///|
fn charter_inline_status_banner(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
  show_refresh~ : Bool = false,
) -> @html.Html {
  if !state.error.is_empty() {
    div(
      class="charter-inline-alert",
      attrs=@html.Attrs::build().role("alert"),
    ) <| [
      span(state.error),
      if show_refresh {
        button(
          type_="button",
          class="workspace-quiet-button",
          on_click=emit(CharterAction(Load)),
          "刷新",
        )
      } else {
        @html.nothing
      },
    ]
  } else if !state.save_note.is_empty() {
    p(
      class="charter-save-note",
      attrs=@html.Attrs::build().role("status"),
      state.save_note,
    )
  } else {
    @html.nothing
  }
}

///|
fn charter_init_inline_form(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
) -> @html.Html {
  if !state.init_form_open {
    return @html.nothing
  }
  div(
    class="charter-inline-form",
    attrs=@html.Attrs::build().aria_label("初始化 OPC 使命与组织"),
  ) <| [
    div(class="charter-form-grid") <| [
      div(class="field") <| [
        label(attrs=@html.Attrs::build().for_("charter-init-title"), "核心使命"),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-init-title"),
          value=state.init_title,
          placeholder="例如：一人公司创新博士研究与开题答辩",
          on_input=emit.map(v => CharterAction(InputInit("title", v))),
        ),
      ],
      div(class="field") <| [
        label(
          attrs=@html.Attrs::build().for_("charter-init-north-star"),
          "北极星目标",
        ),
        input(
          input_type=Text,
          attrs=@html.Attrs::build().id("charter-init-north-star"),
          value=state.init_north_star,
          placeholder="例如：用 20% 创始人关键判断驱动 80% 学术产出与评审通过",
          on_input=emit.map(v => CharterAction(InputInit("north_star", v))),
        ),
      ],
    ],
    if !state.error.is_empty() {
      p(
        class="charter-inline-error",
        attrs=@html.Attrs::build().role("alert"),
        state.error,
      )
    } else {
      @html.nothing
    },
    div(class="charter-form-actions") <| [
      button(
        type_="button",
        class="button button-primary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(SubmitInitForm)),
        if state.saving {
          "正在保存…"
        } else {
          "保存并初始化"
        },
      ),
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(InitializeDefault)),
        "使用默认模板初始化",
      ),
      button(
        type_="button",
        class="button button-secondary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(ToggleInitForm)),
        "取消",
      ),
    ],
  ]
}

///|
fn charter_empty_or_error_panel(
  emit : @rabbita.Emit[Msg],
  state : CompanyCharterState,
  surface_label : String,
) -> @html.Html {
  if state.status == "loading" {
    return section(class="charter-banner charter-state-loading") <| [
      span(
        class="charter-loading-dot",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      ),
      p(
        attrs=@html.Attrs::build().role("status"),
        "正在读取" + surface_label + "…",
      ),
    ]
  }
  if state.status == "error" {
    return section(
      class="charter-banner charter-state-error",
      attrs=@html.Attrs::build().role("alert"),
    ) <| [
      div(class="charter-banner-copy") <| [
        strong("未能读取公司章程"),
        p(
          if state.error.is_empty() {
            "读取公司章程时发生错误，不能推断当前未初始化。"
          } else {
            state.error
          },
        ),
      ],
      button(
        type_="button",
        class="button button-secondary button-small",
        on_click=emit(CharterAction(Load)),
        "重试读取",
      ),
    ]
  }
  section(class="charter-banner charter-state-empty") <| [
    div(class="charter-banner-row") <| [
      div(class="charter-banner-copy") <| [
        strong("尚未建立 OPC 使命与组织章程"),
        p(
          "初始化后即可追踪阶段权重、20% 关键决策、Agent 权责边界与演化记录。",
        ),
      ],
      button(
        type_="button",
        class="button button-primary button-small",
        disabled=state.saving,
        on_click=emit(CharterAction(ToggleInitForm)),
        "初始化 OPC 使命与组织",
      ),
    ],
    charter_init_inline_form(emit, state),
  ]
}
