///|
// Living Company Operating Charter: Mission Spine, Tiered Org & Power Structure,
// Resource Registry, Evolution Ledger, and 80/20 Founder Focus classification.
struct CharterMission {
  title : String
  north_star : String
  active_stage_id : String
  focus_ratio : String
} derive(Debug, Eq)

///|
struct CharterStage {
  id : String
  order : Int
  title : String
  status : String
  weight_pct : Int
  outcome : String
  milestone_task_id : String
} derive(Debug, Eq)

///|
struct CharterRole {
  id : String
  name : String
  tier : Int
  reports_to : String
  kind : String
  mission : String
  powers : Array[String]
  limits : Array[String]
  skill_ref : String
  model : String
  version : String
  status : String
} derive(Debug, Eq)

///|
struct CharterResource {
  id : String
  name : String
  kind : String
  uri : String
  desk_url : String
  access : String
  owner_role : String
  notes : String
} derive(Debug, Eq)

///|
struct CharterEvolution {
  id : String
  date : String
  target : String
  target_id : String
  change : String
  evidence : String
} derive(Debug, Eq)

///|
struct CompanyCharter {
  schema : String
  revision : Int
  updated_by : String
  mission : CharterMission
  stages : Array[CharterStage]
  roles : Array[CharterRole]
  resources : Array[CharterResource]
  evolution_log : Array[CharterEvolution]
  critical_task_ids : Array[String]
} derive(Debug, Eq)

///|
struct CompanyCharterState {
  status : String
  request : Int
  saving : Bool
  error : String
  save_note : String
  persisted : Bool
  charter : CompanyCharter?
  init_form_open : Bool
  init_title : String
  init_north_star : String
  role_form_open : Bool
  role_name : String
  role_tier : Int
  role_kind : String
  role_reports_to : String
  role_mission : String
  role_powers : String
  role_limits : String
  role_skill_ref : String
  role_model : String
  evo_form_open : Bool
  evo_target : String
  evo_target_id : String
  evo_change : String
  evo_evidence : String
  resource_form_open : Bool
  resource_name : String
  resource_kind : String
  resource_uri : String
  resource_desk_url : String
  resource_access : String
  resource_owner_role : String
  resource_notes : String
} derive(Debug, Eq)

///|
enum CharterMsg {
  Load
  Loaded(Int, Int, String)
  Saved(Int, Int, String)
  ToggleInitForm
  InputInit(String, String)
  InitializeDefault
  SubmitInitForm
  ToggleCriticalTask(String)
  ToggleRoleForm
  InputRole(String, String)
  SubmitRole
  ToggleEvoForm
  InputEvo(String, String)
  SubmitEvo
  ToggleResourceForm
  InputResource(String, String)
  SubmitResource
} derive(Debug, Eq)

///|
fn charter_initial() -> CompanyCharterState {
  {
    status: "idle",
    request: 0,
    saving: false,
    error: "",
    save_note: "",
    persisted: false,
    charter: None,
    init_form_open: false,
    init_title: "",
    init_north_star: "",
    role_form_open: false,
    role_name: "",
    role_tier: 2,
    role_kind: "agent",
    role_reports_to: "",
    role_mission: "",
    role_powers: "",
    role_limits: "",
    role_skill_ref: "",
    role_model: "",
    evo_form_open: false,
    evo_target: "agent",
    evo_target_id: "",
    evo_change: "",
    evo_evidence: "",
    resource_form_open: false,
    resource_name: "",
    resource_kind: "moonbook",
    resource_uri: "",
    resource_desk_url: "",
    resource_access: "read_only",
    resource_owner_role: "",
    resource_notes: "",
  }
}

///|
fn charter_achieved_pct(charter : CompanyCharter) -> Int {
  let mut total = 0
  for stage in charter.stages {
    if stage.status == "achieved" {
      total += stage.weight_pct
    }
  }
  if total > 100 { 100 } else if total < 0 { 0 } else { total }
}

///|
fn charter_active_stage(charter : CompanyCharter) -> CharterStage? {
  if !charter.mission.active_stage_id.is_empty() {
    match charter.stages.filter(s => s.id == charter.mission.active_stage_id).get(0) {
      Some(stage) => return Some(stage)
      None => ()
    }
  }
  charter.stages.filter(s => s.status == "active").get(0)
}

///|
fn charter_find_stage(
  charter : CompanyCharter,
  stage_id : String,
) -> CharterStage? {
  if stage_id.is_empty() {
    return None
  }
  charter.stages.filter(s => s.id == stage_id).get(0)
}

///|
fn charter_is_critical_task(
  state : CompanyCharterState,
  task_id : String,
) -> Bool {
  match state.charter {
    Some(charter) => charter.critical_task_ids.contains(task_id)
    None => false
  }
}

///|
fn workspace_is_founder_critical(model : Model, job : TodayTask) -> Bool {
  let stage = workspace_stage(workspace_record(model, job), job)
  if ["waiting_approval", "review", "failed"].contains(stage) {
    return true
  }
  charter_is_critical_task(model.charter, job.id)
}

///|
fn workspace_founder_critical_jobs(model : Model) -> Array[TodayTask] {
  workspace_jobs(model).filter(job => workspace_is_founder_critical(model, job))
}

///|
fn workspace_delegated_jobs(model : Model) -> Array[TodayTask] {
  workspace_jobs(model).filter(job => !workspace_is_founder_critical(model, job))
}

///|
fn charter_starter_template(
  custom_title : String,
  custom_north_star : String,
) -> CompanyCharter {
  let title = if custom_title.trim().is_empty() {
    "创新型一人公司核心使命"
  } else {
    custom_title.trim().to_owned()
  }
  let north_star = if custom_north_star.trim().is_empty() {
    "将 80% 创始人精力聚焦于 20% 关键决策，让 Agent 组织在清晰边界内持续交付与演化。"
  } else {
    custom_north_star.trim().to_owned()
  }
  {
    schema: "moonproj.company-charter.v1",
    revision: 0,
    updated_by: "",
    mission: {
      title,
      north_star,
      active_stage_id: "stage-1",
      focus_ratio: "80/20",
    },
    stages: [
      {
        id: "stage-1",
        order: 1,
        title: "阶段 1 · 核心立项",
        status: "active",
        weight_pct: 25,
        outcome: "确立核心目标、验收口径与基础语料",
        milestone_task_id: "",
      },
      {
        id: "stage-2",
        order: 2,
        title: "阶段 2 · 关键验证",
        status: "upcoming",
        weight_pct: 25,
        outcome: "完成核心假设核验与关键成果草稿",
        milestone_task_id: "",
      },
      {
        id: "stage-3",
        order: 3,
        title: "阶段 3 · 独立审查",
        status: "upcoming",
        weight_pct: 25,
        outcome: "通过独立批评与反证检查",
        milestone_task_id: "",
      },
      {
        id: "stage-4",
        order: 4,
        title: "阶段 4 · 最终交付",
        status: "upcoming",
        weight_pct: 25,
        outcome: "形成创始人签收的可追溯最终成果",
        milestone_task_id: "",
      },
    ],
    roles: [
      {
        id: "founder",
        name: "创始人",
        tier: 0,
        reports_to: "",
        kind: "human",
        mission: "把关核心方向、关键 20% 拍板与最终成果签收。",
        powers: ["定义使命与阶段权重", "审批关键交付与外部承诺", "授权或调整 Agent 边界"],
        limits: ["不陷于可委派的重复执行细节"],
        skill_ref: "",
        model: "",
        version: "v1",
        status: "active",
      },
      {
        id: "coordinator",
        name: "协调负责人",
        tier: 1,
        reports_to: "founder",
        kind: "agent",
        mission: "拆解阶段目标、编排专员并行产出并汇总可审查版本。",
        powers: ["拆解任务并调度专业 Agent", "汇总交付草稿并提交审阅"],
        limits: ["不得越权签收最终交付", "不得修改原始只读语料"],
        skill_ref: "skills/coordinator/SKILL.md",
        model: "",
        version: "v1",
        status: "active",
      },
      {
        id: "reviewer",
        name: "独立审查 Agent",
        tier: 2,
        reports_to: "coordinator",
        kind: "agent",
        mission: "对照原始证据与验收标准执行独立核验与反证检查。",
        powers: ["审查引文与证据一致性", "提出阻断项与修改建议"],
        limits: ["不得自行修改执行者产出并直接验收"],
        skill_ref: "skills/reviewer/SKILL.md",
        model: "",
        version: "v1",
        status: "active",
      },
    ],
    resources: [],
    evolution_log: [
      {
        id: "evo-init",
        date: policy_today(),
        target: "company",
        target_id: "charter",
        change: "初始化 OPC 使命脊柱、三层权责结构与 80/20 聚焦基线。",
        evidence: "founder-init",
      },
    ],
    critical_task_ids: [],
  }
}

///|
extern "js" fn charter_fetch(
  url : String,
  method_ : String,
  key : String,
  body : String,
  receive : (Int, String) -> Unit,
) =
  #| (url, method, key, body, receive) => {
  #|   const controller = typeof AbortController === "function" ? new AbortController() : null;
  #|   let settled = false;
  #|   let timer;
  #|   const finish = (status, text) => {
  #|     if (settled) return;
  #|     settled = true;
  #|     clearTimeout(timer);
  #|     receive(status, text);
  #|   };
  #|   timer = setTimeout(() => {
  #|     finish(0, '{"error":"request_timeout"}');
  #|     if (controller) controller.abort();
  #|   }, 30000);
  #|   const headers = { Accept: "application/json" };
  #|   if (method === "PUT" || method === "POST") {
  #|     headers["Content-Type"] = "application/json";
  #|     if (key) headers["Idempotency-Key"] = key;
  #|   }
  #|   const options = { method, credentials: "same-origin", headers };
  #|   if (method === "PUT" || method === "POST") options.body = body;
  #|   if (controller) options.signal = controller.signal;
  #|   try {
  #|     fetch(url, options)
  #|       .then(response => response.text().then(text => finish(response.status, text)))
  #|       .catch(() => finish(0, ""));
  #|   } catch (_) {
  #|     finish(0, "");
  #|   }
  #| }

