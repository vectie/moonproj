///|
fn project_row(
  name : String,
  kind : String,
  stage : String,
  gate : String,
  health : String,
  owner : String,
) -> @html.Html {
  tr <| [
    td <| [
      strong(name),
      small(kind),
    ],
    td(stage),
    td(gate),
    td <| [
      status_badge(
        health,
        tone=if health == "健康" { "accent" } else { "warning" },
      ),
    ],
    td(owner),
  ]
}

///|
fn projects_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(
      Projects,
      primary_button(emit, RecordDecision("建立项目"), "建立项目"),
    ),
    div(class="stage-legend") <| [
      strong("软件六阶段"),
      span("需求 → 设计 → 开发 → 测试 → 灰度 → 全量"),
      strong("硬件六阶段"),
      span("概念 → EVT → DVT → PVT → 小批 → 量产"),
    ],
    section(class="section-block") <| [
      section_title(
        "项目组合", "阶段由 Agent 推进，Gate 只能由证据和授权放行。",
        "1 项阻塞",
      ),
      div(class="table-scroll") <| [
        table(class="data-table portfolio-table") <| [
          thead <| [
            tr <| [
              th("项目"),
              th("当前阶段"),
              th("下一 Gate"),
              th("健康"),
              th("责任 Agent"),
            ],
          ],
          tbody <| [
            project_row(
              "OPC Core v0.9", "软件", "测试 · 82%", "G4 工程化", "健康",
              "Builder-02",
            ),
            project_row(
              "Agent Evidence Bus", "软件", "开发 · 61%", "G2 功能完整",
              "有风险", "Architect-01",
            ),
            project_row(
              "Edge Node MkII", "硬件", "DVT · 48%", "DVT 热循环", "阻塞",
              "Hardware-01",
            ),
            project_row(
              "Company Control Pack", "扩展包", "灰度 · 90%", "G6 合规",
              "健康", "Finance-01",
            ),
          ],
        ],
      ],
    ],
  ]
}

///|
fn moon_repo(
  name : String,
  version : String,
  ci : String,
  coverage : Int,
  grade : String,
  stage : String,
) -> @html.Html {
  article(class="repo-card") <| [
    div(class="loop-head") <| [
      strong(name),
      status_badge(grade, tone=if grade == "A" { "accent" } else { "warning" }),
    ],
    p("\{version} · \{stage}"),
    div(class="budget-row") <| [
      span(ci),
      span("覆盖率 \{coverage}%"),
    ],
    meter(
      coverage,
      if coverage >= 80 {
        "ok"
      } else if coverage >= 60 {
        "warn"
      } else {
        "bad"
      },
    ),
  ]
}

///|
fn moon_suite_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  section(class="page") <| [
    page_intro(MoonSuite, status_badge("扩展视图", tone="violet")),
    div(class="extension-boundary") <| [
      strong("Moon Suite 产品线投影"),
      p(
        "该页面读取兄弟项目状态；基础 OPC 不依赖任何 Moon 产品。Moonfish 仅作为投资分析 Agent 被吸收，不能直接交易。",
      ),
    ],
    div(class="kpi-grid") <| [
      compact_kpi("登记仓库", "8", "产品线注册表", "info"),
      compact_kpi("GA", "2", "可全量运行", "ok"),
      compact_kpi("冻结", "3", "B/C 或红线风险", "warn"),
      compact_kpi("平均覆盖率", "71%", "目标 ≥ 80%", "violet"),
    ],
    div(class="repo-grid") <| [
      moon_repo("moonproj", "v0.9.0-dev", "CI 通过", 84, "A", "灰度"),
      moon_repo("moonclaw", "v0.6.2", "CI 通过", 78, "A", "GA"),
      moon_repo("moonfish", "v0.5.1", "CI 运行中", 66, "B", "灰度"),
      moon_repo("moongate", "v0.8.0", "CI 通过", 82, "A", "GA"),
      moon_repo("moonbook", "v0.4.0", "CI 失败", 51, "C", "开发"),
      moon_repo("moondesk", "v0.7.0", "CI 通过", 69, "B", "内测"),
    ],
    secondary_button(emit, Navigate(Quality), "进入全系出厂质检"),
  ]
}

///|
fn quality_row(
  emit : @rabbita.Emit[Msg],
  index : Int,
  repo : String,
  scores : String,
  total : String,
  grade : String,
  blocker : String,
  selected : Bool,
) -> @html.Html {
  tr(class=if selected { "is-selected" } else { "" }) <| [
    td <| [
      strong(repo),
    ],
    td(scores),
    td(total),
    td <| [
      status_badge(grade, tone=if grade == "A" { "accent" } else { "warning" }),
    ],
    td(blocker),
    td <| [
      secondary_button(emit, SelectQualityProduct(index), "查看"),
    ],
  ]
}

///|
fn quality_product_name(model : Model, index : Int) -> String {
  if model.moon_mode {
    if index == 0 {
      "moonproj"
    } else if index == 1 {
      "moonclaw"
    } else if index == 2 {
      "moonfish"
    } else {
      "moondesk"
    }
  } else if index == 0 {
    "Core Service"
  } else if index == 1 {
    "Agent Runtime"
  } else if index == 2 {
    "Investment Pack"
  } else {
    "Desktop Console"
  }
}

///|
fn quality_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let selected = quality_product_name(model, model.quality_product)
  section(class="page") <| [
    page_intro(Quality, status_badge("7 Gate · 3 红线", tone="violet")),
    section_title(
      "3 大红线 · 一票否决", "触发任一红线即冻结，不进入 Gate 评分。",
      "2 项风险",
    ),
    div(class="redline-grid") <| [
      article(class="redline-card") <| [
        strong("R1 · 数据泄露风险"),
        status_badge("全线通过", tone="accent"),
        p("敏感数据、凭据与客户信息不得越界。"),
      ],
      article(class="redline-card has-risk") <| [
        strong("R2 · 合规资质缺失"),
        status_badge("1 项风险", tone="warning"),
        p("资质、许可或申报证据缺失即冻结。"),
      ],
      article(class="redline-card has-risk") <| [
        strong("R3 · 核心流程阻断"),
        status_badge("1 项风险", tone="warning"),
        p("核心路径无法完成或无法回滚即冻结。"),
      ],
    ],
    section_title(
      "全系产品重审总表", "选择产品查看 7-Gate 明细与整改动作。",
      "",
    ),
    div(class="table-scroll panel-table") <| [
      table(class="data-table quality-table") <| [
        thead <| [
          tr <| [
            th("产品"),
            th("G1–G7 分数"),
            th("总分"),
            th("等级"),
            th("核心卡点"),
            th("操作"),
          ],
        ],
        tbody <| [
          quality_row(
            emit,
            0,
            quality_product_name(model, 0),
            "88 · 92 · 86 · 84 · 78 · 91 · 85",
            "86",
            "A",
            "G5 事件口径",
            model.quality_product == 0,
          ),
          quality_row(
            emit,
            1,
            quality_product_name(model, 1),
            "91 · 88 · 82 · 90 · 76 · 89 · 84",
            "86",
            "A",
            "运营数据",
            model.quality_product == 1,
          ),
          quality_row(
            emit,
            2,
            quality_product_name(model, 2),
            "82 · 78 · 74 · 69 · 72 · 81 · 67",
            "75",
            "B",
            "回滚未演练",
            model.quality_product == 2,
          ),
          quality_row(
            emit,
            3,
            quality_product_name(model, 3),
            "76 · 72 · 69 · 61 · 58 · 79 · 64",
            "68",
            "C",
            "核心流程阻断风险",
            model.quality_product == 3,
          ),
        ],
      ],
    ],
    div(class="quality-detail-grid") <| [
      section(class="section-block") <| [
        section_title(
          "\{selected} · 7-Gate 评审明细",
          "独立交叉评审；每一分必须可回溯到证据。",
          "待 Owner 裁决",
        ),
        div(class="gate-list") <| [
          div <| [
            span("G1 需求与价值验证"),
            meter(82, "ok"),
            strong("82"),
          ],
          div <| [
            span("G2 产品功能完整性"),
            meter(76, "warn"),
            strong("76"),
          ],
          div <| [
            span("G3 用户体验与界面"),
            meter(72, "warn"),
            strong("72"),
          ],
          div <| [
            span("G4 技术工程化"),
            meter(61, "warn"),
            strong("61"),
          ],
          div <| [
            span("G5 数据与运营体系"),
            meter(58, "bad"),
            strong("58"),
          ],
          div <| [
            span("G6 安全与合规"),
            meter(79, "warn"),
            strong("79"),
          ],
          div <| [
            span("G7 发布与运维"),
            meter(64, "warn"),
            strong("64"),
          ],
        ],
      ],
      section(class="section-block") <| [
        section_title(
          "整改清单", "整改完成后由 Gatekeeper-01 安排复评。", "3 项",
        ),
        ul(class="remediation-list") <| [
          li("补齐核心事件埋点与实时看板"),
          li("完成十分钟回滚演练并归档证据"),
          li("修复核心流程阻断并加入回归测试"),
        ],
        primary_button(
          emit,
          RecordDecision("生成 \{selected} 整改任务"),
          "生成整改任务并分派 Agent",
        ),
      ],
    ],
  ]
}
