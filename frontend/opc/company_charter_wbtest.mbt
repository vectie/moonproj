///|
fn charter_research_fixture_json() -> Json {
  {
    "schema": "moonproj.company-charter.v1",
    "charter_id": "current",
    "revision": 3,
    "updated_by": "founder",
    "mission": {
      "title": "一人公司（OPC）创新博士研究",
      "north_star": "聚焦 20% 关键学术判断与答辩核心论点，以多 Agent 协作完成高质量开题与博士论文。",
      "active_stage_id": "opening-defense",
      "focus_ratio": "80/20",
    },
    "stages": [
      {
        "id": "proposal",
        "order": 1,
        "title": "Proposal",
        "status": "achieved",
        "weight_pct": 15,
        "outcome": "研究计划与核心命题确立",
        "milestone_task_id": "",
      },
      {
        "id": "advisory-board",
        "order": 2,
        "title": "Advisory Board",
        "status": "achieved",
        "weight_pct": 10,
        "outcome": "导师组架构与方法论审议通过",
        "milestone_task_id": "",
      },
      {
        "id": "opening-defense",
        "order": 3,
        "title": "Opening Defense",
        "status": "active",
        "weight_pct": 25,
        "outcome": "开题报告定稿、实证台账核验与答辩讲稿就绪",
        "milestone_task_id": "goal-1",
      },
      {
        "id": "dissertation",
        "order": 4,
        "title": "Dissertation",
        "status": "upcoming",
        "weight_pct": 50,
        "outcome": "完成博士论文终稿与外审答辩",
        "milestone_task_id": "",
      },
    ],
    "roles": [
      {
        "id": "founder",
        "name": "创始人（博士候选人）",
        "tier": 0,
        "reports_to": "",
        "kind": "human",
        "mission": "提出核心研究命题、审定关键 20% 学术决策并签署最终交付。",
        "powers": [
          "确定研究方向与方法论边界", "验收各阶段核心成果",
        ],
        "limits": ["不把时间耗费在重复文献排版与格式校对"],
        "skill_ref": "",
        "model": "",
        "version": "v1",
        "status": "active",
      },
      {
        "id": "research-director",
        "name": "研究协调负责人",
        "tier": 1,
        "reports_to": "founder",
        "kind": "agent",
        "mission": "统筹开题与论文阶段拆解，分派专员并整合最终交付稿。",
        "powers": ["拆解阶段子任务", "汇总多专员草稿"],
        "limits": ["不得越权签收最终论文", "不得改写原始语料"],
        "skill_ref": "skills/research-director/SKILL.md",
        "model": "claude-sonnet-4-5",
        "version": "v2",
        "status": "active",
      },
      {
        "id": "corpus-verifier",
        "name": "语料核验专员",
        "tier": 2,
        "reports_to": "research-director",
        "kind": "agent",
        "mission": "核对实证数据、引文来源与页码一致性。",
        "powers": ["读取只读研究语料", "出具引文核验报告"],
        "limits": ["严禁篡改原始语料文件"],
        "skill_ref": "skills/corpus-verifier/SKILL.md",
        "model": "claude-sonnet-4-5",
        "version": "v1",
        "status": "active",
      },
      {
        "id": "defense-editor",
        "name": "开题讲稿编辑",
        "tier": 2,
        "reports_to": "research-director",
        "kind": "agent",
        "mission": "润色开题讲稿结构、逻辑转承与图表说明。",
        "powers": ["在 MoonBook wiki 区域起草与修订讲稿"],
        "limits": ["不得编造未经核验的实证结论"],
        "skill_ref": "skills/defense-editor/SKILL.md",
        "model": "claude-sonnet-4-5",
        "version": "v2",
        "status": "evolving",
      },
      {
        "id": "advisory-critic",
        "name": "独立答辩批评者",
        "tier": 2,
        "reports_to": "founder",
        "kind": "agent",
        "mission": "模拟答辩委员会提出尖锐反证与方法论质疑。",
        "powers": ["独立审查交付草稿", "列出阻断级质疑问题"],
        "limits": ["不得直接修改作者正稿"],
        "skill_ref": "skills/advisory-critic/SKILL.md",
        "model": "claude-sonnet-4-5",
        "version": "v1",
        "status": "active",
      },
    ],
    "resources": [
      {
        "id": "book-opc-research",
        "name": "OPC Research Lab MoonBook",
        "kind": "moonbook",
        "uri": "/Users/founder/books/opc-research-lab",
        "desk_url": "http://127.0.0.1:4201/?workspace=book-opc-research&activity=wiki&path=wiki/index.md",
        "access": "read_write",
        "owner_role": "research-director",
        "notes": "唯一受管知识库与交付协作区",
      },
      {
        "id": "corpus-raw-downloads",
        "name": "原始博士研究文献语料",
        "kind": "corpus",
        "uri": "~/Downloads/Research",
        "desk_url": "",
        "access": "read_only",
        "owner_role": "corpus-verifier",
        "notes": "原始资料严格只读，永不原地修改",
      },
    ],
    "evolution_log": [
      {
        "id": "evo-1",
        "date": "2026-11-24",
        "target": "agent",
        "target_id": "defense-editor",
        "change": "新增开题答辩每页论点-证据映射要求（v1 -> v2）",
        "evidence": "导师组二轮预审纪要",
      },
    ],
    "critical_task_ids": ["work-3"],
  }
}

///|
fn charter_loaded_test_model() -> Model {
  let base = workspace_test_model()
  let response = Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0.0),
    "persisted": Json::boolean(true),
    "charter": charter_research_fixture_json(),
  }).stringify()
  let (_, loading) = update(_ => none, CharterAction(Load), base)
  let (_, ready) = update(
    _ => none,
    CharterAction(Loaded(loading.charter.request, 200, response)),
    loading,
  )
  ready
}

///|
test "decodes 4-stage research OPC charter and computes achieved percentage and active stage" {
  let charter = charter_decode_json(charter_research_fixture_json()).unwrap()
  assert_eq(charter.revision, 3)
  assert_eq(charter.mission.title, "一人公司（OPC）创新博士研究")
  assert_eq(charter.stages.length(), 4)
  assert_eq(charter.roles.length(), 5)
  assert_eq(charter.resources.length(), 2)
  assert_eq(charter.evolution_log.length(), 1)
  assert_eq(charter_achieved_pct(charter), 25)
  assert_eq(
    charter_active_stage(charter).map(s => s.title),
    Some("Opening Defense"),
  )
}

///|
test "80/20 founder focus surfaces review, approval, failed, and pinned critical jobs while keeping ordinary tasks delegated" {
  let base = charter_loaded_test_model()
  let meta = base.today.task_metadata.copy()
  // work-1 is waiting for founder review -> critical
  meta["work-1"] = {
    "taskType": "task",
    "parentTaskGuid": "goal-1",
    "sortOrder": 1,
    "execution": { "state": "completed" },
  }
  // work-2 is running normally and not in critical_task_ids -> delegated
  meta["work-2"] = {
    "taskType": "task",
    "parentTaskGuid": "goal-1",
    "sortOrder": 2,
    "execution": { "state": "running" },
  }
  // work-3 is pending, explicitly listed in critical_task_ids -> critical
  meta["work-3"] = {
    "taskType": "task",
    "parentTaskGuid": "goal-1",
    "sortOrder": 3,
  }
  let work4 = {
    ..today_test_task("work-4", "", "pending"),
    title: "4 · 预算审批：等待确认",
  }
  let work5 = {
    ..today_test_task("work-5", "", "pending"),
    title: "5 · 数据清洗：执行失败",
    execution_error: "语料索引读取失败",
  }
  meta["work-4"] = {
    "taskType": "task",
    "parentTaskGuid": "goal-1",
    "sortOrder": 4,
    "execution": { "state": "waiting_approval" },
  }
  meta["work-5"] = {
    "taskType": "task",
    "parentTaskGuid": "goal-1",
    "sortOrder": 5,
    "execution": { "state": "failed" },
  }
  let tasks = base.today.tasks.copy()
  tasks.push(work4)
  tasks.push(work5)
  let model = { ..base, today: { ..base.today, tasks, task_metadata: meta, }, }
  assert_eq(workspace_founder_critical_jobs(model).map(t => t.id), [
    "work-1", "work-3", "work-4", "work-5",
  ])
  assert_eq(workspace_delegated_jobs(model).map(t => t.id), ["work-2"])
}

///|
test "renders focus, org, and resources workspace tabs while preserving flow-board, job-dock, and job-app-host" {
  let model = charter_loaded_test_model()
  let focus_html = products_test_html(model)
  assert_true(focus_html.contains("一人公司（OPC）创新博士研究"))
  assert_true(focus_html.contains("已达成 25%"))
  assert_true(focus_html.contains("Opening Defense"))
  assert_true(focus_html.contains("我的 20% 关键决策"))
  assert_true(focus_html.contains("打开材料 (MoonDesk)"))
  assert_true(focus_html.contains("class=\"flow-board\""))
  assert_true(focus_html.contains("class=\"job-dock\""))
  assert_true(focus_html.contains("data-job-app-host"))

  let (_, org_model) = update(_ => none, WorkspaceAction(Tab("org")), model)
  let org_html = products_test_html(org_model)
  assert_true(org_html.contains("组织与权力结构"))
  assert_true(org_html.contains("Tier 0 · 创始人（最终问责）"))
  assert_true(org_html.contains("Tier 1 · 协调负责人（统筹拆解）"))
  assert_true(org_html.contains("Tier 2 · 专业执行与独立审查 Agent"))
  assert_true(org_html.contains("skills/defense-editor/SKILL.md"))
  assert_true(org_html.contains("演化记录"))
  assert_true(org_html.contains("class=\"job-dock\""))
  assert_true(org_html.contains("data-job-app-host"))

  let (_, res_model) = update(
    _ => none,
    WorkspaceAction(Tab("resources")),
    model,
  )
  let res_html = products_test_html(res_model)
  assert_true(res_html.contains("公司资源清单"))
  assert_true(res_html.contains("知识库 MoonBook"))
  assert_true(res_html.contains("研究语料与数据"))
  assert_true(res_html.contains("在 MoonDesk 打开"))
  assert_true(res_html.contains("class=\"job-dock\""))
  assert_true(res_html.contains("data-job-app-host"))
}

///|
test "charter empty and error states remain distinct and never pretend error equals empty" {
  let base = workspace_test_model()
  let (_, loading) = update(_ => none, CharterAction(Load), base)
  assert_true(
    products_test_html(loading).contains(
      "正在读取公司使命与阶段脊柱",
    ),
  )

  let (_, empty_model) = update(
    _ => none,
    CharterAction(
      Loaded(
        loading.charter.request,
        200,
        "{\"success\":true,\"persisted\":false,\"charter\":null}",
      ),
    ),
    loading,
  )
  let empty_html = products_test_html(empty_model)
  assert_true(empty_html.contains("初始化 OPC 使命与组织"))
  assert_false(empty_html.contains("重试读取"))

  let (_, err_model) = update(
    _ => none,
    CharterAction(
      Loaded(
        loading.charter.request,
        503,
        "{\"error\":\"database_unavailable\"}",
      ),
    ),
    loading,
  )
  let err_html = products_test_html(err_model)
  assert_true(err_html.contains("重试读取"))
  assert_false(err_html.contains("初始化 OPC 使命与组织"))
}

///|
test "adding a role, recording an evolution entry, and registering a resource emit valid PUT /api/company/charter payloads" {
  setup_transport_start(false)
  defer setup_transport_stop()

  // 1. Add a role
  let mut m = charter_loaded_test_model()
  let (_, m1) = update(_ => none, CharterAction(ToggleRoleForm), m)
  let (_, m2) = update(
    _ => none,
    CharterAction(InputRole("name", "Citation Auditor")),
    m1,
  )
  let (_, m3) = update(_ => none, CharterAction(InputRole("tier", "2")), m2)
  let (_, m4) = update(_ => none, CharterAction(InputRole("kind", "agent")), m3)
  let (_, m5) = update(
    _ => none,
    CharterAction(InputRole("reports_to", "research-director")),
    m4,
  )
  let (_, m6) = update(
    _ => none,
    CharterAction(InputRole("powers", "核查参考文献格式，校验 DOI")),
    m5,
  )
  let (_, m7) = update(
    _ => none,
    CharterAction(InputRole("limits", "不得删除原文段落")),
    m6,
  )
  let (role_cmd, role_saving) = update(_ => none, CharterAction(SubmitRole), m7)
  assert_true(role_saving.charter.saving)
  drafts_test_execute(role_cmd)

  let role_req = @json.parse(setup_transport_request(0))
  let role_opts = products_field(role_req, "options")
  assert_eq(products_text(role_req, "url"), "/api/company/charter")
  assert_eq(products_text(role_opts, "method"), "PUT")
  assert_false(
    products_text(products_field(role_opts, "headers"), "Idempotency-Key").is_empty(),
  )
  let role_body = @json.parse(products_text(role_opts, "body"))
  let role_decoded = charter_decode_json(role_body).unwrap()
  assert_eq(role_decoded.roles.length(), 6)
  assert_eq(role_decoded.roles[5].id, "citation-auditor")
  assert_eq(role_decoded.roles[5].powers, [
    "核查参考文献格式", "校验 DOI",
  ])
  assert_eq(role_decoded.roles[5].limits, ["不得删除原文段落"])
  assert_eq(charter_json_int(role_body, "expected_revision", -1), 3)

  // 2. Record an evolution entry
  m = charter_loaded_test_model()
  let (_, e1) = update(_ => none, CharterAction(ToggleEvoForm), m)
  let (_, e2) = update(
    _ => none,
    CharterAction(InputEvo("target", "agent")),
    e1,
  )
  let (_, e3) = update(
    _ => none,
    CharterAction(InputEvo("target_id", "advisory-critic")),
    e2,
  )
  let (_, e4) = update(
    _ => none,
    CharterAction(
      InputEvo("change", "升级反证清单至 v2，强制引用原始页码"),
    ),
    e3,
  )
  let (_, e5) = update(
    _ => none,
    CharterAction(InputEvo("evidence", "开题模拟演练复盘")),
    e4,
  )
  let (evo_cmd, evo_saving) = update(_ => none, CharterAction(SubmitEvo), e5)
  assert_true(evo_saving.charter.saving)
  drafts_test_execute(evo_cmd)

  let evo_req = @json.parse(setup_transport_request(1))
  let evo_opts = products_field(evo_req, "options")
  assert_eq(products_text(evo_opts, "method"), "PUT")
  let evo_body = @json.parse(products_text(evo_opts, "body"))
  let evo_decoded = charter_decode_json(evo_body).unwrap()
  assert_eq(evo_decoded.evolution_log.length(), 2)
  assert_eq(evo_decoded.evolution_log[1].target_id, "advisory-critic")
  assert_eq(
    evo_decoded.evolution_log[1].change,
    "升级反证清单至 v2，强制引用原始页码",
  )

  // 3. Register a resource
  m = charter_loaded_test_model()
  let (_, r1) = update(_ => none, CharterAction(ToggleResourceForm), m)
  let (_, r2) = update(
    _ => none,
    CharterAction(InputResource("name", "Citation Check Script")),
    r1,
  )
  let (_, r3) = update(
    _ => none,
    CharterAction(InputResource("kind", "tool")),
    r2,
  )
  let (_, r4) = update(
    _ => none,
    CharterAction(InputResource("access", "execute")),
    r3,
  )
  let (_, r5) = update(
    _ => none,
    CharterAction(InputResource("uri", "scripts/verify_citations.py")),
    r4,
  )
  let (res_cmd, res_saving) = update(
    _ => none,
    CharterAction(SubmitResource),
    r5,
  )
  assert_true(res_saving.charter.saving)
  drafts_test_execute(res_cmd)

  let res_req = @json.parse(setup_transport_request(2))
  let res_opts = products_field(res_req, "options")
  assert_eq(products_text(res_opts, "method"), "PUT")
  let res_body = @json.parse(products_text(res_opts, "body"))
  let res_decoded = charter_decode_json(res_body).unwrap()
  assert_eq(res_decoded.resources.length(), 3)
  assert_eq(res_decoded.resources[2].id, "citation-check-script")
  assert_eq(res_decoded.resources[2].kind, "tool")
  assert_eq(res_decoded.resources[2].access, "execute")
}

///|
test "selecting a task-bound stage keeps parent goal connected and resolves human role names" {
  let base = charter_loaded_test_model()
  let charter = base.charter.charter.unwrap()
  let updated_stages = charter.stages.map(s => {
    if s.id == "opening-defense" {
      { ..s, milestone_task_id: "work-2", }
    } else {
      s
    }
  })
  let model = {
    ..base,
    charter: {
      ..base.charter,
      charter: Some({ ..charter, stages: updated_stages, }),
    },
  }
  let (_, filtered) = update(
    _ => none,
    WorkspaceAction(SelectStage("opening-defense")),
    model,
  )
  let focus_html = products_test_html(filtered)
  assert_true(focus_html.contains("data-goal-id=\"goal-1\""))
  assert_true(focus_html.contains("data-stage-spotlight=\"true\""))
  assert_true(focus_html.contains("打开此阶段材料"))
  assert_false(focus_html.contains("其他工作"))

  let (_, org_model) = update(_ => none, WorkspaceAction(Tab("org")), model)
  let org_html = products_test_html(org_model)
  assert_true(
    org_html.contains("汇报对象：创始人（博士候选人）"),
  )
  assert_eq(charter_power_label("draft:critique"), "独立审查")
  assert_eq(charter_power_label("自定义权限"), "自定义权限")

  let (_, res_model) = update(
    _ => none,
    WorkspaceAction(Tab("resources")),
    model,
  )
  let res_html = products_test_html(res_model)
  assert_true(res_html.contains("保管：研究协调负责人"))

  let (_, opened_res) = update(
    _ => none,
    WorkspaceAction(
      OpenResource(
        "OPC Research Lab MoonBook", "http://127.0.0.1:4201/?workspace=book-opc-research&activity=wiki&path=wiki/index.md",
      ),
    ),
    res_model,
  )
  let opened_html = products_test_html(opened_res)
  assert_true(opened_html.contains("返回资源清单"))
  assert_true(opened_html.contains("data-visible=\"true\""))
  assert_true(opened_html.contains("book-opc-research"))

  // Standing agents appear in the bottom Dock and open an overlay sheet over the flow desktop
  let desktop_html = products_test_html(model)
  assert_true(desktop_html.contains("data-dock-agent=\"research-director\""))
  assert_false(desktop_html.contains("data-dock-agent=\"founder\""))
  let (_, agent_open) = update(
    _ => none,
    WorkspaceAction(InspectAgent("research-director")),
    model,
  )
  let agent_html = products_test_html(agent_open)
  assert_true(agent_html.contains("data-desktop-sheet=\"agent\""))
  assert_true(agent_html.contains("class=\"flow-board\""))
  assert_true(agent_html.contains("研究协调负责人"))
}
