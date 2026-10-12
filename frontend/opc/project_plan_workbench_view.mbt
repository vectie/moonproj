///|
fn plan_button(
  emit : @rabbita.Emit[Msg],
  action : PlanMsg,
  title : String,
  disabled? : Bool = false,
  selected? : Bool = false,
) -> @html.Html {
  button(
    type_="button",
    class=if selected {
      "button button-primary button-small"
    } else {
      "button button-secondary button-small"
    },
    attrs=@html.Attrs::build().disabled(disabled),
    on_click=emit(PlanAction(action)),
    title,
  )
}

///|
fn plan_field(
  emit : @rabbita.Emit[Msg],
  kind : String,
  id : String,
  field : String,
  title : String,
  value : String,
  multiline? : Bool = false,
) -> @html.Html {
  let dom_id = "plan-" + kind + "-" + id + "-" + field
  div(class="field") <| [
    label(attrs=@html.Attrs::build().for_(dom_id), title),
    if multiline {
      @html.textarea(
        attrs=@html.Attrs::build().id(dom_id),
        value~,
        on_input=emit.map(v => PlanAction(Edit(kind, id, field, v))),
        "",
      )
    } else {
      input(
        input_type=Text,
        attrs=@html.Attrs::build().id(dom_id),
        value~,
        on_input=emit.map(v => PlanAction(Edit(kind, id, field, v))),
      )
    },
  ]
}

///|
fn plan_choice(
  emit : @rabbita.Emit[Msg],
  kind : String,
  id : String,
  field : String,
  title : String,
  selected : String,
  options : Array[(String, String)],
) -> @html.Html {
  div(class="field") <| [
    strong(title),
    div(class="tag-row") <| options.map(pair => {
      plan_button(
        emit,
        Edit(kind, id, field, pair.0),
        pair.1,
        selected=selected == pair.0,
      )
    }),
    if !options.any(o => o.0 == selected) {
      p("请重新选择；原引用已缺失或尚未选择。")
    } else {
      @html.nothing
    },
  ]
}

///|
fn plan_result(saved : Json) -> @html.Html {
  let artifact = products_field(saved, "artifact")
  let budget = products_field(artifact, "budget")
  section(class="section-block") <| [
    h3("原生计划 · 等待具名人工复核"),
    p(
      "计划版本 " +
      products_text(saved, "key") +
      " · " +
      products_text(artifact, "recorded_at"),
    ),
    p(
      "以下都是规划值；未创建正式任务、开始执行、接受计划、批准预算、支付或记账。",
    ),
    p(
      "币种 " +
      products_text(budget, "currency") +
      " · 金额以最小单位显示（例如分）",
    ),
    div(class="kpi-grid") <| [
      compact_kpi(
        "预算上限",
        products_field(budget, "limit_minor").stringify(),
        "最小单位",
        "info",
      ),
      compact_kpi(
        "任务合计",
        products_field(budget, "planned_total_minor").stringify(),
        "最小单位",
        "info",
      ),
      compact_kpi(
        "预备金",
        products_field(budget, "contingency_minor").stringify(),
        "最小单位",
        "info",
      ),
      compact_kpi(
        "未分配",
        products_field(budget, "unallocated_minor").stringify(),
        "最小单位",
        "info",
      ),
    ],
    h3("依赖顺序"),
    div <| @plan_workbench.items(artifact, "tasks").mapi((i, task) => {
      article(class="repo-card") <| [
        strong((i + 1).to_string() + ". " + products_text(task, "name")),
        p(
          "负责人 " +
          plan_result_name(
            artifact,
            "owners",
            "owner_id",
            "display_name",
            products_text(task, "owner_id"),
          ) +
          " · 里程碑 " +
          plan_result_name(
            artifact,
            "milestones",
            "milestone_id",
            "name",
            products_text(task, "milestone_id"),
          ),
        ),
        p(
          "规划成本 " +
          products_field(task, "planned_cost_minor").stringify() +
          " 最小单位 · 前置 " +
          plan_dependency_names(artifact, task),
        ),
      ]
    }),
    h3("里程碑与验收"),
    div <| @plan_workbench.items(artifact, "milestones").map(m => {
      article(class="repo-card") <| [
        strong(
          products_text(m, "name") + " · " + products_text(m, "target_date"),
        ),
        p(
          "负责人 " +
          plan_result_name(
            artifact,
            "owners",
            "owner_id",
            "display_name",
            products_text(m, "owner_id"),
          ),
        ),
        div <| @plan_workbench.items(artifact, "acceptance_gates")
        .filter(g => {
          products_text(g, "scope_id") == products_text(m, "milestone_id")
        })
        .map(g => {
          div <| [
            p("标准：" + plan_strings(products_field(g, "criteria"))),
            p(
              "需要证据：" +
              plan_strings(products_field(g, "required_evidence")),
            ),
          ]
        }),
      ]
    }),
    h3("风险"),
    div <| @plan_workbench.items(artifact, "risks").map(r => {
      p(
        products_text(r, "severity") +
        " · " +
        products_text(r, "summary") +
        " → " +
        products_text(r, "mitigation"),
      )
    }),
  ]
}

///|
fn plan_result_name(
  a : Json,
  array : String,
  id_key : String,
  name_key : String,
  id : String,
) -> String {
  @plan_workbench.items(a, array)
  .filter(v => products_text(v, id_key) == id)
  .get(0)
  .map(v => products_text(v, name_key))
  .unwrap_or(id)
}

///|
fn plan_strings(value : Json) -> String {
  match value {
    Array(items) =>
      items
      .filter_map(v => {
        match v {
          String(t) => Some(t)
          _ => None
        }
      })
      .join("；")
    _ => ""
  }
}

///|
fn plan_dependency_names(a : Json, task : Json) -> String {
  match products_field(task, "dependencies") {
    Array(values) if !values.is_empty() =>
      values
      .filter_map(v => {
        match v {
          String(id) =>
            Some(plan_result_name(a, "tasks", "task_id", "name", id))
          _ => None
        }
      })
      .join("、")
    _ => "无"
  }
}

///|
fn projects_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let s = model.plan
  section(class="page plan-workbench") <| [
    page_intro(
      Projects,
      plan_button(
        emit,
        Refresh,
        "读取公司项目",
        disabled=s.phase == "loading",
      ),
    ),
    p(
      "项目计划工作台：公司项目来自现有公司服务。编辑草稿只保留在当前浏览器；准备后保存为网关工作区中的不可变原生计划。",
    ),
    p(attrs=@html.Attrs::build().role("status").aria_live("polite"), s.note),
    div(class="tag-row") <| s.projects.map(project => {
      plan_button(
        emit,
        Choose(project.id),
        project.name,
        selected=s.selected == project.id,
      )
    }),
    if s.selected.is_empty() {
      p(
        "请选择一个实际公司项目。没有项目时，请先使用公司设置。",
      )
    } else {
      p(
        "当前公司项目：" +
        s.projects
        .filter(p => p.id == s.selected)
        .get(0)
        .map(p => p.name)
        .unwrap_or(s.selected) +
        " · " +
        s.selected,
      )
    },
    match s.draft {
      None => @html.nothing
      Some(d) => {
        let owners = d.owners.map(o => {
          (o.id, if o.name.is_empty() { "未命名负责人" } else { o.name })
        })
        let milestones = d.milestones.map(m => {
          (m.id, if m.name.is_empty() { "未命名里程碑" } else { m.name })
        })
        div <| [
          plan_template_view(emit, s),
          plan_extract_view(emit, s, d),
          plan_owner_brief_view(emit, s, d),
          plan_transfer_view(emit, s, d),
          plan_budget_breakdown_view(emit, s, d),
          plan_text_replace_view(emit, s),
          section(class="section-block") <| [
            h3("范围与预算"),
            plan_field(
              emit,
              "plan",
              "",
              "notes",
              "范围、依据与排除项",
              d.notes,
              multiline=true,
            ),
            div(class="form-grid") <| [
              plan_field(
                emit,
                "plan",
                "",
                "currency",
                "三字母币种（固定两位小数）",
                d.currency,
              ),
              plan_field(emit, "plan", "", "limit", "预算上限", d.limit),
              plan_field(
                emit,
                "plan",
                "",
                "contingency",
                "预备金",
                d.contingency,
              ),
            ],
            h3("负责人"),
            plan_owner_table_view(emit, s, d),
            div <| d.owners.map(o => {
              article(class="repo-card") <| [
                plan_field(
                  emit,
                  "owner",
                  o.id,
                  "name",
                  if o.id == s.actor {
                    "你的姓名（已登录编制人）"
                  } else {
                    "姓名"
                  },
                  o.name,
                ),
                plan_field(emit, "owner", o.id, "role", "职责", o.role),
                if o.id == s.actor {
                  @html.nothing
                } else {
                  plan_button(emit, Remove("owner", o.id), "移除负责人")
                },
              ]
            }),
            plan_button(emit, Add("owner"), "添加负责人"),
          ],
          section(class="section-block") <| [
            h3("里程碑与验收标准"),
            p(
              "每个里程碑至少关联一个任务；标准和所需证据每行一项。技术标识自动生成。",
            ),
            div <| d.milestones.map(m => {
              article(class="repo-card") <| [
                plan_field(
                  emit,
                  "milestone",
                  m.id,
                  "name",
                  "里程碑名称",
                  m.name,
                ),
                plan_field(
                  emit,
                  "milestone",
                  m.id,
                  "date",
                  "目标日期 YYYY-MM-DD",
                  m.date,
                ),
                plan_choice(
                  emit,
                  "milestone",
                  m.id,
                  "owner",
                  "复核负责人",
                  m.owner,
                  owners,
                ),
                plan_field(
                  emit,
                  "milestone",
                  m.id,
                  "criteria",
                  "验收标准（每行一项）",
                  m.criteria,
                  multiline=true,
                ),
                plan_field(
                  emit,
                  "milestone",
                  m.id,
                  "evidence",
                  "所需证据（每行一项）",
                  m.evidence,
                  multiline=true,
                ),
                plan_button(emit, Remove("milestone", m.id), "移除里程碑"),
              ]
            }),
            plan_button(emit, Add("milestone"), "添加里程碑"),
            plan_milestone_table_view(emit, s, d),
            plan_schedule_view(emit, s, d),
            p(
              "导出当前草稿中的里程碑目标日期为不占用忙碌时间的全天标记。任务仅作为说明，不推算任务日期或工期。导出不代表已保存、接受或授权执行。",
            ),
            plan_button(
              emit,
              ExportCalendar,
              "下载里程碑日历 (.ics)",
              disabled=d.milestones.is_empty(),
            ),
          ],
          section(class="section-block") <| [
            h3("任务顺序"),
            plan_dependency_view(emit, s, d),
            p(
              "粘贴 CSV 或 TSV 待办表。必需列：id / Issue key 和 title / Summary。可选：Assignee、milestone、cost、dependencies（分号分隔，前置任务先列出）。其他列不导入；追加前请检查负责人和里程碑。",
            ),
            plan_button(
              emit,
              TaskTableFormat(false),
              "CSV",
              selected=!s.task_table_tsv,
            ),
            plan_button(
              emit,
              TaskTableFormat(true),
              "TSV",
              selected=s.task_table_tsv,
            ),
            plan_choice(
              emit,
              "task-table",
              "",
              "owner",
              "空白负责人使用",
              s.task_table_owner,
              owners,
            ),
            plan_choice(
              emit,
              "task-table",
              "",
              "milestone",
              "空白里程碑使用",
              s.task_table_milestone,
              milestones,
            ),
            plan_field(
              emit,
              "task-table",
              "",
              "source",
              "待办表（含表头）",
              s.task_table,
              multiline=true,
            ),
            plan_button(
              emit,
              ImportTasks,
              "追加导入任务",
              disabled=s.task_table.trim().is_empty(),
            ),
            plan_button(
              emit,
              ExportTasks,
              "下载可编辑任务 CSV",
              disabled=d.tasks.is_empty(),
            ),
            plan_task_edits_view(emit, s),
            plan_checklist_view(emit, s, d),
            p(
              "按执行依赖的先后添加任务，再点选前置任务。删除被引用的行后需修正引用，原生验证会拒绝无效计划。",
            ),
            plan_task_finder_view(emit, s, d),
            plan_breakdown_view(emit, s, d),
            plan_consolidation_view(emit, s, d),
            plan_handoff_view(emit, s, d),
            div <| d.tasks
            .mapi((i, t) => (i, t))
            .filter(pair => {
              s.task_finder.focus.is_empty() ||
              !d.tasks.any(task => task.id == s.task_finder.focus) ||
              pair.1.id == s.task_finder.focus
            })
            .map(pair => {
              let (i, t) = pair
              article(class="repo-card") <| [
                h3("任务 " + (i + 1).to_string()),
                plan_field(emit, "task", t.id, "name", "任务名称", t.name),
                plan_choice(
                  emit,
                  "task",
                  t.id,
                  "owner",
                  "负责人",
                  t.owner,
                  owners,
                ),
                plan_choice(
                  emit,
                  "task",
                  t.id,
                  "milestone",
                  "所属里程碑",
                  t.milestone,
                  milestones,
                ),
                plan_field(emit, "task", t.id, "cost", "规划成本", t.cost),
                strong("前置任务（点选 / 取消）"),
                div(class="tag-row") <| d.tasks
                .filter(other => other.id != t.id)
                .map(other => {
                  plan_button(
                    emit,
                    Toggle("task", t.id, other.id),
                    if other.name.is_empty() {
                      "未命名任务"
                    } else {
                      other.name
                    },
                    selected=t.dependencies.contains(other.id),
                  )
                }),
                if t.dependencies.any(dep => {
                    !d.tasks.any(other => other.id == dep)
                  }) {
                  p(
                    "存在已删除的前置任务；点击下方清除缺失引用后重新选择。",
                  )
                } else {
                  @html.nothing
                },
                div <| t.dependencies
                .filter(dep => !d.tasks.any(other => other.id == dep))
                .map(dep => {
                  plan_button(
                    emit,
                    Toggle("task", t.id, dep),
                    "清除缺失前置任务",
                  )
                }),
                plan_button(emit, Remove("task", t.id), "移除任务"),
                plan_button(
                  emit,
                  ShiftTask(t.id, -1),
                  "上移",
                  disabled=i == 0,
                ),
                plan_button(
                  emit,
                  ShiftTask(t.id, 1),
                  "下移",
                  disabled=i + 1 == d.tasks.length(),
                ),
              ]
            }),
            plan_button(emit, Add("task"), "添加任务"),
          ],
          section(class="section-block") <| [
            h3("风险与缓解（可选）"),
            plan_risk_table_view(emit, s, d),
            plan_risk_impact_view(emit, s, d),
            div <| d.risks.map(r => {
              article(class="repo-card") <| [
                plan_field(emit, "risk", r.id, "summary", "风险", r.summary),
                plan_field(
                  emit,
                  "risk",
                  r.id,
                  "mitigation",
                  "缓解措施",
                  r.mitigation,
                ),
                plan_choice(
                  emit,
                  "risk",
                  r.id,
                  "owner",
                  "负责人",
                  r.owner,
                  owners,
                ),
                plan_choice(
                  emit,
                  "risk",
                  r.id,
                  "severity",
                  "严重程度",
                  r.severity,
                  [
                    ("low", "低"),
                    ("medium", "中"),
                    ("high", "高"),
                    ("critical", "严重"),
                  ],
                ),
                strong("相关任务（点选 / 取消）"),
                div(class="tag-row") <| d.tasks.map(t => {
                  plan_button(
                    emit,
                    Toggle("risk", r.id, t.id),
                    if t.name.is_empty() {
                      "未命名任务"
                    } else {
                      t.name
                    },
                    selected=r.tasks.contains(t.id),
                  )
                }),
                div <| r.tasks
                .filter(id => !d.tasks.any(t => t.id == id))
                .map(id => {
                  plan_button(
                    emit,
                    Toggle("risk", r.id, id),
                    "清除缺失任务引用",
                  )
                }),
                plan_button(emit, Remove("risk", r.id), "移除风险"),
              ]
            }),
            plan_button(emit, Add("risk"), "添加风险"),
          ],
          plan_button(
            emit,
            Prepare,
            "原生准备并保存计划",
            disabled=["saving", "opening"].contains(s.phase),
          ),
          match s.prepared {
            Some(saved) =>
              div <| [
                plan_result(saved),
                plan_button(emit, Download(false), "下载可读计划"),
                plan_button(
                  emit,
                  Download(true),
                  "下载类型化原生 artifact",
                ),
              ]
            None => p("当前编辑尚无已验证的准备结果。")
          },
          section(class="section-block") <| [
            h3(
              "保存历史（当前登录人 · 当前公司项目 · 最近100项）",
            ),
            p(
              "打开历史会替换当前浏览器草稿；已保存计划本身不可变。",
            ),
            div <| s.history.map(item => {
              plan_button(
                emit,
                Open(products_text(item, "key")),
                products_text(item, "recorded_at") +
                " · " +
                products_text(item, "key"),
                disabled=["saving", "opening"].contains(s.phase),
              )
            }),
          ],
          plan_comparison_view(emit, s),
        ]
      }
    },
  ]
}
