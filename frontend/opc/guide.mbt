///|
fn guide_gate_row(
  id : String,
  purpose : String,
  evidence : String,
) -> @html.Html {
  @html.tr <| [
    @html.td <| [
      @html.strong(id),
    ],
    @html.td(purpose),
    @html.td(evidence),
  ]
}

///|
fn guide_view(emit : @rabbita.Emit[Msg], _model : Model) -> @html.Html {
  @html.section(class="page") <| [
    page_intro(Guide, status_badge("随时可查", tone="accent")),
    @html.section(class="section-block journey-guide") <| [
      @html.h2("按顺序完成一件工作"),
      @html.ol(class="journey-instructions") <| [
        @html.li <| [
          @html.strong("1 · 选择产品与目标"),
          @html.p(
            "在产品中选择要做的产品，读取并选择本次公司的项目，再点击准备任务。没有项目时可在同页创建。",
          ),
        ],
        @html.li <| [
          @html.strong("2 · 准备任务"),
          @html.p(
            "写下想要的结果、验收标准、实际执行工作区和必填的计划日期，再保存正式任务。模型与负责人可按需填写。",
          ),
        ],
        @html.li <| [
          @html.strong("3 · 明确开始执行"),
          @html.p(
            "在当前任务中开始。等待、失败或中断时按页面提示恢复同一执行；创建任务本身不会启动模型。",
          ),
        ],
        @html.li <| [
          @html.strong("4 · 检查输出，按需加入人工修改"),
          @html.p(
            "打开准确输出。需要调整时进入 MoonDesk 继续此工作，完成后返回，明确选择要提交的结果。",
          ),
        ],
        @html.li <| [
          @html.strong("5 · 提交报告，再接受结果"),
          @html.p(
            "提交与接受是两步。核对当前结果和对应报告；来源不一致或操作未确认时，先按提示恢复。",
          ),
        ],
        @html.li <| [
          @html.strong("6 · 保存经验，准备下一目标"),
          @html.p(
            "在对应 Book 的 Review → Learning 中添加和接受有用经验，确认保存状态。任务接受不会自动保存经验或在 Town 中复用。",
          ),
        ],
      ],
      @html.div(class="form-actions") <| [
        primary_button(emit, Navigate(Products), "从产品开始"),
        secondary_button(emit, Navigate(Dispatch), "继续当前任务"),
      ],
      @html.p(
        class="boundary-note",
        "执行需要已连接的公司服务、有效登录身份、MoonClaw 可访问的工作区；跨应用查看需要配置 MoonDesk。错误与恢复入口会保留在相应步骤中。",
      ),
    ],
    @html.details(class="journey-details") <| [
      @html.summary("发布与工程证据参考"),
      @html.section(class="section-block") <| [
        @html.div(class="section-heading") <| [
          @html.div <| [
            @html.h2("三个问题，一份证据"),
            @html.p(
              "三个维度是同一九 Gate 账本的投影，不是三套评分系统。",
            ),
          ],
        ],
        @html.div(class="three-column") <| [
          @html.article(class="compact-panel") <| [
            @html.h3("走了多远"),
            @html.p(
              "取连续通过的最后一个 Gate；它描述进度，不预测剩余工期。",
            ),
          ],
          @html.article(class="compact-panel") <| [
            @html.h3("走得多好"),
            @html.p(
              "汇总同一候选中的失败、阻断、未知和经复核问题。",
            ),
          ],
          @html.article(class="compact-panel") <| [
            @html.h3("能否生产"),
            @html.p(
              "只有九 Gate 和三条红线都具备可接受证据，才允许请求 Owner 授权。",
            ),
          ],
        ],
      ],
      @html.section(class="section-block") <| [
        @html.div(class="section-heading") <| [
          @html.div <| [
            @html.h2("九 Gate 速查"),
            @html.p(
              "每个 Gate 都要求可复核收据；没有证据时显示未知。",
            ),
          ],
        ],
        @html.div(class="table-scroll") <| [
          @html.table(class="data-table") <| [
            @html.thead <| [
              @html.tr <| [
                @html.th("Gate"),
                @html.th("回答什么"),
                @html.th("典型证据"),
              ],
            ],
            @html.tbody <| [
              guide_gate_row(
                "G1", "目标和候选是否明确", "需求、仓库、分支、commit、版本",
              ),
              guide_gate_row(
                "G2", "功能是否完整", "功能清单、业务验收和未移植项",
              ),
              guide_gate_row(
                "G3", "界面是否可用", "实际浏览、无障碍、窄屏和指南",
              ),
              guide_gate_row(
                "G4", "工程质量是否合格", "严格检查、测试和生成接口差异",
              ),
              guide_gate_row(
                "G5", "集成和数据是否一致", "PostgreSQL、刷新、重启和对账",
              ),
              guide_gate_row(
                "G6", "安全与合规是否受控", "秘密扫描、权限、依赖和责任人",
              ),
              guide_gate_row(
                "G7", "产物是否可交付", "应用包、校验和与兼容性矩阵",
              ),
              guide_gate_row(
                "G8", "安装和恢复是否可靠", "安装、运行、回滚、恢复和清理",
              ),
              guide_gate_row(
                "G9", "发布控制是否完整", "分支、tag、签名、校验和和发布记录",
              ),
            ],
          ],
        ],
      ],
      @html.section(class="section-block") <| [
        @html.div(class="section-heading") <| [
          @html.div <| [
            @html.h2("桌面版的数据边界"),
            @html.p(
              "LEPUSA 负责窗口与本地服务生命周期；MoonProj 仍拥有业务和数据规则。",
            ),
          ],
          status_badge("PostgreSQL", tone="muted"),
        ],
        @html.ul(class="plain-list") <| [
          @html.li <| [
            @html.strong("本地端口"),
            @html.span(
              "应用只绑定回环地址；关闭最后一个窗口时，LEPUSA 停止受管服务。",
            ),
          ],
          @html.li <| [
            @html.strong("正式数据"),
            @html.span(
              "来自 PostgreSQL。数据库不可用时保留界面，但不得把演示或会话草稿当作正式事实。",
            ),
          ],
          @html.li <| [
            @html.strong("应用数据"),
            @html.span(
              "运行配置和凭据文件属于 LEPUSA 用户数据目录，不得写入签名后的应用包。",
            ),
          ],
          @html.li <| [
            @html.strong("MoonClaw"),
            @html.span(
              "工程审计需要本机 MoonClaw 和可访问的 Moon Suite 工作区；缺失时结论保持未知。",
            ),
          ],
        ],
      ],
    ],
  ]
}
