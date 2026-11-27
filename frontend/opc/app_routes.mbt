///|
fn nav_items() -> Array[NavItem] {
  [
    {
      page: Workspace,
      group: "指挥",
      label: "工作空间",
      short_label: "工",
      description: "工作关系、任务应用与交付",
    },
    {
      page: Products,
      group: "指挥",
      label: "产品",
      short_label: "产",
      description: "产品意图、PRD 与真实工作",
    },
    {
      page: Overview,
      group: "指挥",
      label: "今日",
      short_label: "驾",
      description: "今天需要我决定什么",
    },
    {
      page: Objectives,
      group: "指挥",
      label: "目标",
      short_label: "目",
      description: "明确结果，委派工作，核对交付",
    },
    {
      page: Fleet,
      group: "执行",
      label: "Agent 编队",
      short_label: "队",
      description: "劳动力、自治与预算",
    },
    {
      page: Dispatch,
      group: "执行",
      label: "任务编排",
      short_label: "派",
      description: "分派、执行与验收",
    },
    {
      page: Delivery,
      group: "交付",
      label: "工作与交付",
      short_label: "工",
      description: "会话内演练 · 非 PostgreSQL",
    },
    {
      page: Projects,
      group: "交付",
      label: "计划",
      short_label: "项",
      description: "交付计划、依赖与预算",
    },
    {
      page: MoonSuite,
      group: "交付",
      label: "Moon 专案",
      short_label: "月",
      description: "产品列车与出厂状态",
    },
    {
      page: Quality,
      group: "交付",
      label: "出厂质检",
      short_label: "质",
      description: "9 Gate、3 红线与发布演练",
    },
    {
      page: Observe,
      group: "保障",
      label: "监测环",
      short_label: "监",
      description: "SLO、错误预算与告警",
    },
    {
      page: Operate,
      group: "保障",
      label: "运维环",
      short_label: "运",
      description: "事件、复盘与 Runbook",
    },
    {
      page: Company,
      group: "治理",
      label: "公司域",
      short_label: "司",
      description: "主体、商务、财税与资本",
    },
    {
      page: PolicyRadar,
      group: "治理",
      label: "政策雷达",
      short_label: "策",
      description: "来源、变更、图谱与商机",
    },
    {
      page: Evidence,
      group: "治理",
      label: "证据与审计",
      short_label: "证",
      description: "授权、拦截与责任链",
    },
    {
      page: Guide,
      group: "帮助",
      label: "使用指南",
      short_label: "指",
      description: "页面、证据与桌面运行方式",
    },
  ]
}

///|
fn page_path(page : Page) -> String {
  match page {
    Workspace => "/workspace"
    Objectives => "/objectives"
    Overview => "/"
    Fleet => "/fleet"
    Dispatch => "/dispatch"
    Products => "/products"
    Projects => "/projects"
    MoonSuite => "/moon"
    Quality => "/quality"
    Observe => "/observe"
    Operate => "/operate"
    Company => "/company"
    PolicyRadar => "/policy-radar"
    Evidence => "/evidence"
    Guide => "/guide"
    Market => "/market"
    Delivery => "/delivery"
    Commerce => "/commerce"
    Finance => "/finance"
    Assurance => "/assurance"
    Extensions => "/extensions"
  }
}

///|
fn page_title(page : Page) -> String {
  match page {
    Workspace => "工作空间"
    Overview => "今日"
    Objectives => "目标"
    Fleet => "Agent 编队"
    Dispatch => "任务编排"
    Products => "产品"
    Projects => "计划"
    MoonSuite => "Moon 专案"
    Quality => "出厂质检"
    Observe => "监测环"
    Operate => "运维环"
    Company => "公司域"
    PolicyRadar => "政策雷达"
    Evidence => "证据与审计"
    Guide => "使用指南"
    Market => "市场与客户"
    Delivery => "工作与交付"
    Commerce => "商务与交换"
    Finance => "财务与资本"
    Assurance => "治理与韧性"
    Extensions => "智能与扩展"
  }
}

///|
fn page_question(page : Page) -> String {
  match page {
    Workspace => "每项工作如何汇成交付？"
    Objectives => "公司要达成什么结果，哪些工作需要委派？"
    Overview => "公司今天需要你做出什么决定？"
    Fleet => "我的 Agent 劳动力正在做什么？"
    Dispatch => "开发环转到哪里，什么需要我验收？"
    Products =>
      "我们在做哪些产品，为什么做，下一步在哪里？"
    Projects => "每项交付处在哪个阶段，Gate 是否通过？"
    MoonSuite => "Moon Suite 各产品离出厂还有多远？"
    Quality => "凭什么让这个产品出厂？"
    Observe => "系统健康吗，错误预算还剩多少？"
    Operate => "出事了吗，处置经验沉淀了吗？"
    Company => "公司还能活多久，承诺与义务是否受控？"
    PolicyRadar =>
      "今天哪一条政策变化值得核验，而不是立即相信？"
    Evidence => "Agent 做了什么，依据、授权和结果在哪里？"
    Guide => "第一次使用 MoonProj，应该从哪里开始？"
    Market => "哪一个客户问题值得公司解决并获得回报？"
    Delivery => "公司承诺的结果如何被稳定交付和验收？"
    Commerce =>
      "公司已经做出哪些承诺，还需要完成哪些交换？"
    Finance => "公司能否看清现金、利润、税务和资本状态？"
    Assurance => "当人或系统不可用时，公司还能否安全继续？"
    Extensions => "哪些智能或行业能力值得被明确启用？"
  }
}

///|
fn setup_count(model : Model) -> Int32 {
  let mut count = 0
  if model.company_saved {
    count += 1
  }
  if model.market_saved {
    count += 1
  }
  if model.work_saved {
    count += 1
  }
  if model.commitment_saved {
    count += 1
  }
  if model.ledger_ready {
    count += 1
  }
  if model.continuity_ready {
    count += 1
  }
  count
}

///|
fn readiness_count(model : Model) -> Int32 {
  let mut count = setup_count(model)
  if model.constitution_ready {
    count += 1
  }
  if model.authority_ready {
    count += 1
  }
  if model.resource_register_ready {
    count += 1
  }
  if model.offer_register_ready {
    count += 1
  }
  if model.workflow_ready {
    count += 1
  }
  if model.attention_ready {
    count += 1
  }
  if model.procurement_ready {
    count += 1
  }
  if model.expense_register_ready {
    count += 1
  }
  if model.budget_ready {
    count += 1
  }
  if model.treasury_ready {
    count += 1
  }
  if model.tax_ready {
    count += 1
  }
  if model.financing_ready {
    count += 1
  }
  if model.investment_ready {
    count += 1
  }
  if model.control_ready {
    count += 1
  }
  if model.learning_ready {
    count += 1
  }
  count
}

///|
fn readiness_total() -> Int32 {
  21
}

///|
fn company_readiness_count(model : Model) -> Int32 {
  let mut count = 0
  if model.constitution_ready {
    count += 1
  }
  if model.authority_ready {
    count += 1
  }
  if model.resource_register_ready {
    count += 1
  }
  count
}

///|
fn can_start_work(model : Model) -> Bool {
  model.work_saved && model.workflow_ready && model.work_stage == 0
}

///|
fn can_submit_work(model : Model) -> Bool {
  model.work_stage == 1
}

///|
fn can_accept_work(model : Model) -> Bool {
  model.work_stage == 2
}

///|
fn can_approve_commitment(model : Model) -> Bool {
  model.commitment_saved && model.authority_ready && model.commitment_stage == 0
}

///|
fn can_sign_commitment(model : Model) -> Bool {
  model.commitment_stage == 1 && model.company_saved
}

///|
fn can_complete_commitment(model : Model) -> Bool {
  model.commitment_stage == 2 && model.work_stage == 3
}

///|
fn can_settle_commitment(model : Model) -> Bool {
  model.commitment_stage == 3 && model.treasury_ready
}

///|
fn can_recognize_commitment(model : Model) -> Bool {
  model.commitment_stage == 4 && model.ledger_ready
}
