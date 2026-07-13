///|
using @html {
  aside,
  button,
  div,
  form,
  h1,
  h2,
  header,
  input,
  label,
  li,
  main_,
  nav,
  p,
  section,
  span,
  strong,
  table,
  tbody,
  td,
  th,
  thead,
  tr,
  ul,
}

///|
using @rabbita {cell, new, none, type Cmd}

///|
struct ContractRow {
  contract_id : String
  contract_code : String
  contract_name : String
  project_id : String
  project_name : String
  supplier_id : String
  supplier_name : String
  amount_minor : String
  amount_display : String
  currency : String
  sign_date : String
  state : String
  paid_amount_display : String
  milestone_count : String
  source_kind : String
}

///|
struct ContractMilestoneRow {
  milestone_id : String
  node_name : String
  plan_amount_display : String
  plan_pct_bps : String
  trigger_type : String
}

///|
struct PaymentApplyRow {
  apply_id : String
  apply_code : String
  contract_id : String
  contract_name : String
  project_name : String
  supplier_name : String
  subject : String
  amount_minor : String
  amount_display : String
  currency : String
  apply_date : String
  operation_state : String
  apply_state : String
  pay_state : String
  apply_type_code : String
  pay_class : String
  applied_by : String
  applied_by_name : String
  source_kind : String
  plan_id : String
  milestone_id : String
}

///|
struct TenderRow {
  tender_id : String
  name : String
  project_scope : String
  category : String
  estimated_amount_minor : String
  estimated_amount_display : String
  currency : String
  state : String
  awarded_supplier_id : String
  awarded_amount_display : String
  commitment_id : String
  bid_count : String
  source_kind : String
}

///|
struct SupplierRow {
  supplier_id : String
  supplier_code : String
  name : String
  category_code : String
  evaluation : String
  state : String
  scope : String
  source_kind : String
}

///|
struct SalesRow {
  aggregate_id : String
  primary : String
  secondary : String
  amount_display : String
  state : String
  source_kind : String
}

///|
struct DeliveryProgressRow {
  progress_id : String
  project_id : String
  building_no : String
  stage : String
  plan_date : String
  plan_pct : String
  actual_pct : String
  actual_date : String
  state : String
  remark : String
  source_kind : String
  source_id : String
}

///|
struct DeliveryOutputRow {
  output_id : String
  project_id : String
  contract_id : String
  period : String
  output_amount : String
  confirm_amount : String
  state : String
  remark : String
  source_kind : String
}

///|
struct DeliveryTaskRow {
  task_id : String
  task_name : String
  project_id : String
  plan_begin_date : String
  plan_end_date : String
  progress_pct : String
  status : String
  source_kind : String
}

///|
struct DeliveryReportRow {
  report_id : String
  task_id : String
  progress_pct : String
  report_date : String
  summary : String
  state : String
  source_kind : String
}

///|
struct ReportCostRow {
  bu_name : String
  proj_code : String
  proj_name : String
  target_cost : String
  dynamic_cost : String
  deviation_pct : String
  source_kind : String
}

///|
struct ReportContractRow {
  contract_code : String
  contract_name : String
  provider : String
  current_amount : String
  paid_total : String
  remain_amount : String
  paid_pct : String
  source_kind : String
}

///|
struct ReportStageRow {
  proj_code : String
  proj_name : String
  bu_name : String
  proj_status : String
  source_kind : String
}

///|
struct DashboardFunnelRow {
  stage_name : String
  count : String
  width_pct : String
}

///|
struct DashboardAnomalyRow {
  project_name : String
  company : String
  risk_score : String
  reason : String
  source_kind : String
}

///|
struct AdminQualityRow {
  rule : String
  count : String
  severity : String
  status : String
  source_kind : String
}

///|
struct AdminDictGroupRow {
  group_name : String
  total : String
  enabled : String
  source_kind : String
}

///|
struct AdminDictOptionRow {
  group_name : String
  code : String
  value : String
  display_order : String
  enabled : String
  source_kind : String
}

///|
struct InvestmentIndexRow {
  dimension : String
  index_name : String
  full_code : String
  index_value : String
  unit : String
  source_kind : String
}

///|
struct AuditRow {
  log_id : String
  created_at : String
  emp_name : String
  user_id : String
  action : String
  target_type : String
  target_id : String
  ip : String
  source_kind : String
}

///|
struct AuditActionRow {
  action : String
  count : String
  source_kind : String
}

///|
struct DynamicCostRow {
  cost_guid : String
  cost_code : String
  cost_name : String
  cost_level : String
  target_cost : String
  dynamic_cost : String
  deviation_pct : String
  contract_change : String
  actual_cost : String
  budget_cost : String
  estimate_change : String
  layout_spare : String
  end_cost : String
  remarks : String
  project_name : String
  source_kind : String
}

///|
struct UserRosterRow {
  user_code : String
  emp_name : String
  bu_name : String
  dept_name : String
  roles : String
  roles_source_status : String
  super_user : String
  enabled : String
  source_kind : String
}

///|
struct HealthTableRow {
  table : String
  row_count : String
  source_status : String
  source_kind : String
}

///|
struct LoanRow {
  loan_id : String
  loan_code : String
  subject : String
  apply_state : String
  loan_amount : String
  balance_amount : String
  remain_amount : String
  applied_by_name : String
  apply_dept_name : String
  project_name : String
  apply_date : String
  pay_unit : String
  source_kind : String
}

///|
struct WorkflowStepRow {
  step_guid : String
  step_key : String
  step_order : String
  step_name : String
  threshold : String
  assignee_count : String
  assignee_names : String
  source_kind : String
}

///|
struct WorkflowProcessRow {
  process_guid : String
  process_key : String
  process_name : String
  biz_type : String
  step_count : String
  instances_available : String
  actions_available : String
  source_kind : String
  steps : Array[WorkflowStepRow]
}

///|
struct ProjectRow {
  project_id : String
  project_code : String
  project_name : String
  bu_name : String
  proj_status : String
  begin_date : String
  current_stage : String
  task_count : String
  source_kind : String
  lifecycle_text : String
}

///|
struct Model {
  authenticated : Bool
  page : String
  collapsed : Bool
  mobile_nav : Bool
  open_group : String?
  show_demo : Bool
  user_code : String
  password : String
  api_status : String
  api_note : String
  expense_id : String
  expense_state : String
  expense_note : String
  contracts_loaded : Bool
  contract_rows : Array[ContractRow]
  contract_detail : ContractRow?
  contract_milestones : Array[ContractMilestoneRow]
  contract_id : String
  contract_state : String
  contract_note : String
  payment_applies_loaded : Bool
  payment_apply_rows : Array[PaymentApplyRow]
  payment_apply_id : String
  payment_apply_state : String
  payment_apply_note : String
  payment_apply_eligibility_note : String
  tenders_loaded : Bool
  tender_rows : Array[TenderRow]
  tender_id : String
  tender_state : String
  tender_note : String
  suppliers_loaded : Bool
  supplier_rows : Array[SupplierRow]
  supplier_id : String
  supplier_state : String
  supplier_evaluation : String
  supplier_note : String
  sales_loaded : Bool
  sales_family : String
  sales_rows : Array[SalesRow]
  sales_note : String
  delivery_loaded : Bool
  delivery_progress_rows : Array[DeliveryProgressRow]
  delivery_output_rows : Array[DeliveryOutputRow]
  delivery_task_rows : Array[DeliveryTaskRow]
  delivery_report_rows : Array[DeliveryReportRow]
  delivery_note : String
  delivery_progress_id : String
  delivery_progress_state : String
  delivery_output_id : String
  delivery_output_state : String
  delivery_task_id : String
  delivery_command_note : String
  reports_loaded : Bool
  report_cost_rows : Array[ReportCostRow]
  report_contract_rows : Array[ReportContractRow]
  report_stage_rows : Array[ReportStageRow]
  report_supplier_count : String
  report_approval_count : String
  reports_note : String
  dashboard_loaded : Bool
  dashboard_company_count : String
  dashboard_project_count : String
  dashboard_in_progress_count : String
  dashboard_contract_count : String
  dashboard_total_contract_amount : String
  dashboard_paid_amount : String
  dashboard_paid_ratio : String
  dashboard_target_cost : String
  dashboard_dynamic_cost : String
  dashboard_deviation_pct : String
  dashboard_overdue_tasks : String
  dashboard_missing_table_count : String
  dashboard_funnel_rows : Array[DashboardFunnelRow]
  dashboard_anomaly_rows : Array[DashboardAnomalyRow]
  dashboard_note : String
  admin_quality_loaded : Bool
  admin_quality_rows : Array[AdminQualityRow]
  admin_quality_note : String
  admin_dict_loaded : Bool
  admin_dict_group_rows : Array[AdminDictGroupRow]
  admin_dict_option_rows : Array[AdminDictOptionRow]
  admin_dict_note : String
  investment_loaded : Bool
  investment_version_id : String
  investment_version_name : String
  investment_index_rows : Array[InvestmentIndexRow]
  investment_dimension_count : String
  investment_total : String
  investment_revenue : String
  investment_cost : String
  investment_net_profit : String
  investment_net_profit_margin : String
  investment_irr : String
  investment_note : String
  audit_loaded : Bool
  audit_rows : Array[AuditRow]
  audit_action_rows : Array[AuditActionRow]
  audit_total : String
  audit_note : String
  dynamic_cost_loaded : Bool
  dynamic_cost_rows : Array[DynamicCostRow]
  dynamic_cost_project_name : String
  dynamic_cost_target : String
  dynamic_cost_total : String
  dynamic_cost_deviation : String
  dynamic_cost_spare : String
  dynamic_cost_end_count : String
  dynamic_cost_note : String
  users_loaded : Bool
  user_roster_rows : Array[UserRosterRow]
  users_note : String
  profile_loaded : Bool
  profile_user_id : String
  profile_user_code : String
  profile_user_name : String
  profile_emp_name : String
  profile_bu_name : String
  profile_dept_name : String
  profile_super_user : String
  profile_enabled : String
  profile_last_login : String
  profile_source_kind : String
  profile_note : String
  health_loaded : Bool
  health_table_rows : Array[HealthTableRow]
  health_source_table_count : String
  health_missing_table_count : String
  health_bpm_instance_count : String
  health_bpm_action_count : String
  health_note : String
  loans_loaded : Bool
  loan_rows : Array[LoanRow]
  loan_note : String
  loan_id : String
  loan_state : String
  loan_command_note : String
  workflow_loaded : Bool
  workflow_process_rows : Array[WorkflowProcessRow]
  workflow_note : String
  projects_loaded : Bool
  project_rows : Array[ProjectRow]
  project_detail : ProjectRow?
  project_note : String
}

///|
enum Msg {
  Login
  ToggleDemo
  FillDemo(String, String)
  InputUser(String)
  InputPassword(String)
  Navigate(String)
  ToggleSidebar
  ToggleMobileNav
  ToggleGroup(String)
  RefreshApi
  ApiLoaded
  ApiFailed
  SessionAuthenticated
  SessionAdapterFallback
  SessionLoginRejected(String)
  CreateExpense
  SubmitExpense
  RejectExpense
  ResubmitExpense
  ApproveExpense
  ExpenseCommandFinished(String)
  ExpenseCommandFailed
  ContractsLoaded(String)
  ContractsLoadFailed
  ContractLoaded(String)
  ContractLoadFailed
  CreateContract
  SubmitContract
  RejectContract
  ResubmitContract
  ApproveContract
  ContractCommandFinished(String)
  ContractCommandFailed
  PaymentAppliesLoaded(String)
  PaymentAppliesLoadFailed
  CreatePaymentApply
  SubmitPaymentApply
  RejectPaymentApply
  ResubmitPaymentApply
  ApprovePaymentApply
  UpdatePaymentApply
  VoidPaymentApply
  CheckPaymentEligibility
  PaymentApplyCommandFinished(String)
  PaymentApplyCommandFailed
  PaymentEligibilityLoaded(String)
  PaymentEligibilityLoadFailed
  TendersLoaded(String)
  TendersLoadFailed
  CreateTender
  PublishTender
  OpenTenderBidding
  AwardTender
  CompleteTender
  CancelTender
  TenderCommandFinished(String)
  TenderCommandFailed
  SuppliersLoaded(String)
  SuppliersLoadFailed
  CreateSupplier
  UpdateSupplier
  SubmitSupplierReview
  ReviewSupplier
  BlacklistSupplier
  VoidSupplier
  SupplierCommandFinished(String)
  SupplierCommandFailed
  SalesLoaded(String, String)
  SalesLoadFailed(String)
  DeliveryLoaded(String)
  DeliveryLoadFailed
  CreateDeliveryProgress
  ReportDeliveryProgress
  AcceptDeliveryProgress
  RejectDeliveryProgress
  CreateDeliveryOutput
  ConfirmDeliveryOutput
  ReportTaskProgress
  DeliveryCommandFinished(String)
  DeliveryCommandFailed
  ReportsLoaded(String)
  ReportsLoadFailed
  DashboardOverviewLoaded(String)
  DashboardFunnelLoaded(String)
  DashboardAnomaliesLoaded(String)
  DashboardLoadFailed
  AdminQualityLoaded(String)
  AdminQualityLoadFailed
  AdminDictGroupsLoaded(String)
  AdminDictOptionsLoaded(String)
  AdminDictLoadFailed
  InvestmentVersionsLoaded(String)
  InvestmentIndicesLoaded(String)
  InvestmentProfitLoaded(String)
  InvestmentLoadFailed
  AuditLoaded(String)
  AuditActionsLoaded(String)
  AuditLoadFailed
  DynamicCostLoaded(String)
  DynamicCostLoadFailed
  ProfileLoaded(String)
  ProfileLoadFailed
  UsersLoaded(String)
  UsersLoadFailed
  HealthTablesLoaded(String)
  HealthBpmLoaded(String)
  HealthLoadFailed
  LoansLoaded(String)
  LoansLoadFailed
  CreateLoan
  SubmitLoan
  UpdateLoan
  VoidLoan
  LoanCommandFinished(String)
  LoanCommandFailed
  WorkflowLoaded(String)
  WorkflowLoadFailed
  ProjectsLoaded(String)
  ProjectsLoadFailed
  ProjectLoaded(String)
  ProjectLoadFailed
}

///|
fn initial_model() -> Model {
  {
    authenticated: false,
    page: "/login",
    collapsed: false,
    mobile_nav: false,
    open_group: None,
    show_demo: false,
    user_code: "",
    password: "",
    api_status: "未连接",
    api_note: "使用已审核快照",
    expense_id: "EXP-RABBITA-LOCAL",
    expense_state: "未创建",
    expense_note: "先保存草稿，再提交审批",
    contracts_loaded: false,
    contract_rows: [],
    contract_detail: None,
    contract_milestones: [],
    contract_id: "CT-RABBITA-LOCAL",
    contract_state: "new",
    contract_note: "先保存草稿，再提交审批",
    payment_applies_loaded: false,
    payment_apply_rows: [],
    payment_apply_id: "PAY-RABBITA-LOCAL",
    payment_apply_state: "new",
    payment_apply_note: "先保存付款申请草稿，再提交审批",
    payment_apply_eligibility_note: "尚未校验付款节点条件",
    tenders_loaded: false,
    tender_rows: [],
    tender_id: "TD-RABBITA-LOCAL",
    tender_state: "new",
    tender_note: "合约规划读模型尚未加载",
    suppliers_loaded: false,
    supplier_rows: [],
    supplier_id: "SUP-RABBITA-LOCAL",
    supplier_state: "new",
    supplier_evaluation: "unrated",
    supplier_note: "供应商读模型尚未加载",
    sales_loaded: false,
    sales_family: "",
    sales_rows: [],
    sales_note: "销售/应收读模型尚未加载",
    delivery_loaded: false,
    delivery_progress_rows: [],
    delivery_output_rows: [],
    delivery_task_rows: [],
    delivery_report_rows: [],
    delivery_note: "工程进度/项目计划读模型尚未加载",
    delivery_progress_id: "PROG-RABBITA-LOCAL",
    delivery_progress_state: "new",
    delivery_output_id: "OUT-RABBITA-LOCAL",
    delivery_output_state: "new",
    delivery_task_id: "task-003",
    delivery_command_note: "导入任务保持只读；本地命令需要证据并写入审计",
    reports_loaded: false,
    report_cost_rows: [],
    report_contract_rows: [],
    report_stage_rows: [],
    report_supplier_count: "0",
    report_approval_count: "0",
    reports_note: "核心报表读模型尚未加载",
    dashboard_loaded: false,
    dashboard_company_count: "5",
    dashboard_project_count: "15",
    dashboard_in_progress_count: "15",
    dashboard_contract_count: "62",
    dashboard_total_contract_amount: "1,256,837,036",
    dashboard_paid_amount: "137,953,340",
    dashboard_paid_ratio: "10.98",
    dashboard_target_cost: "—",
    dashboard_dynamic_cost: "645,285,566",
    dashboard_deviation_pct: "+6.20",
    dashboard_overdue_tasks: "2",
    dashboard_missing_table_count: "0",
    dashboard_funnel_rows: [],
    dashboard_anomaly_rows: [],
    dashboard_note: "驾驶舱读模型尚未加载 · 使用设计快照",
    admin_quality_loaded: false,
    admin_quality_rows: [],
    admin_quality_note: "质量规则尚未加载 · 使用设计快照",
    admin_dict_loaded: false,
    admin_dict_group_rows: [],
    admin_dict_option_rows: [],
    admin_dict_note: "数据字典尚未加载 · 使用设计快照",
    investment_loaded: false,
    investment_version_id: "",
    investment_version_name: "",
    investment_index_rows: [],
    investment_dimension_count: "0",
    investment_total: "0",
    investment_revenue: "0",
    investment_cost: "0",
    investment_net_profit: "0",
    investment_net_profit_margin: "0",
    investment_irr: "0",
    investment_note: "投资测算读模型尚未加载 · 使用设计快照",
    audit_loaded: false,
    audit_rows: [],
    audit_action_rows: [],
    audit_total: "0",
    audit_note: "审计读模型尚未加载 · 使用设计快照",
    dynamic_cost_loaded: false,
    dynamic_cost_rows: [],
    dynamic_cost_project_name: "",
    dynamic_cost_target: "0",
    dynamic_cost_total: "0",
    dynamic_cost_deviation: "0",
    dynamic_cost_spare: "0",
    dynamic_cost_end_count: "0",
    dynamic_cost_note: "动态成本读模型尚未加载 · 使用设计快照",
    users_loaded: false,
    user_roster_rows: [],
    users_note: "身份读模型尚未加载 · 使用设计快照",
    profile_loaded: false,
    profile_user_id: "user-admin-0001",
    profile_user_code: "admin",
    profile_user_name: "系统管理员",
    profile_emp_name: "系统管理员",
    profile_bu_name: "集团总部",
    profile_dept_name: "数字化中心",
    profile_super_user: "是",
    profile_enabled: "是",
    profile_last_login: "2026-07-13 09:38",
    profile_source_kind: "设计快照",
    profile_note: "个人资料读模型尚未加载 · 使用设计快照",
    health_loaded: false,
    health_table_rows: [],
    health_source_table_count: "0",
    health_missing_table_count: "0",
    health_bpm_instance_count: "0",
    health_bpm_action_count: "0",
    health_note: "系统健康读模型尚未加载 · 使用设计快照",
    loans_loaded: false,
    loan_rows: [],
    loan_note: "员工借款读模型尚未加载",
    loan_id: "LOAN-RABBITA-LOCAL",
    loan_state: "new",
    loan_command_note: "本地借款命令需要员工范围 authority 与证据",
    workflow_loaded: false,
    workflow_process_rows: [],
    workflow_note: "工作流定义读模型尚未加载",
    projects_loaded: false,
    project_rows: [],
    project_detail: None,
    project_note: "项目主数据读模型尚未加载",
  }
}

///|
fn title_for(path : String) -> String {
  match path {
    "/dashboard" => "集团驾驶舱"
    "/dashboard-v3" => "集团驾驶舱"
    "/cockpit" => "集团驾驶舱"
    "/ai-hub" => "AI 工作台"
    "/ai-stats" => "AI 工作大盘"
    "/projects" => "项目主数据"
    "/projects/CD-HJL" => "项目全周期"
    "/project-plan" => "项目计划"
    "/project/progress" => "工程进度"
    "/tasks" => "我的待办"
    "/sales/customers" => "客户档案"
    "/sales/subscriptions" => "认筹登记"
    "/sales/contracts" => "签约管理"
    "/sales/mortgages" => "按揭办理"
    "/sales/revenues" => "销售回款 (R6)"
    "/marketing" => "营销管理"
    "/cost-dashboard-v3" => "成本驾驶舱"
    "/investment" => "投资收益"
    "/contracts" => "合同台帐"
    "/contracts/CT-RABBITA-LOCAL" => "新建合同"
    "/contracts/HT-CD-260701" => "合同详情"
    "/payment-applies" => "付款申请"
    "/dynamic-cost" => "动态成本"
    "/tender" => "合约规划"
    "/srm/providers" => "供应商库"
    "/srm/providers/SUP-00018" => "供应商详情"
    "/srm/risk-board" => "供应商风险面板"
    "/cbs/dict" => "CBS 字典"
    "/cbs/versions" => "目标版本管理"
    "/cbs/r0-queue" => "R0 待归类"
    "/cbs/approval-config" => "审批配置"
    "/fund/plan" => "资金计划"
    "/invoice" => "发票管理"
    "/expenses" => "我的报销"
    "/expenses/new" => "新建报销"
    "/expenses/EXP-260712-008" => "报销详情"
    "/loans" => "我的借款"
    "/loans/new" => "新建借款"
    "/loans/LOAN-260713-001" => "借款详情"
    "/reports" => "报表中心"
    "/report-builder" => "自定义报表"
    "/warning" => "异常预警中心"
    "/warning-rules" => "告警规则 DSL"
    "/cashflow" => "现金流预测"
    "/inbox" => "站内信"
    "/attachments" => "附件中心"
    "/notify-config" => "通知配置 / 订阅"
    "/audit-log" => "审计日志"
    "/error-log" => "错误日志"
    "/system-health" => "系统健康"
    "/users" => "用户/角色管理"
    "/admin" => "数据后台"
    "/ocr-config" => "OCR 配置"
    "/webhook-config" => "Webhook 三平台"
    "/profile" => "个人中心"
    "/share" => "分享报表"
    _ =>
      if path.has_prefix("/projects/") {
        "项目全周期"
      } else if path.has_prefix("/contracts/") {
        "合同详情"
      } else if path.has_prefix("/expenses/") {
        "报销详情"
      } else if path.has_prefix("/loans/") {
        "借款详情"
      } else if path.has_prefix("/srm/providers/") {
        "供应商详情"
      } else if path.has_prefix("/share/") {
        "分享报表"
      } else {
        "项目全周期管理"
      }
  }
}

///|
fn refresh_api(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/summary").expect_text(result => {
    match result {
      Ok(body) if body.contains("\"target\":\"postgresql\"") &&
        (
          body.contains("\"read_only\":true") ||
          body.contains("\"expense_command\"")
        ) => emit(ApiLoaded)
      Ok(_) => emit(ApiFailed)
      Err(_) => emit(ApiFailed)
    }
  })
}

///|
fn json_object_text(
  fields : Map[String, Json],
  key : String,
  fallback : String,
) -> String {
  match fields.get(key) {
    Some(Json::String(value)) => value
    Some(Json::Number(value, ..)) => value.to_string()
    Some(Json::True) => "true"
    Some(Json::False) => "false"
    _ => fallback
  }
}

///|
fn json_object_int(fields : Map[String, Json], key : String) -> Int {
  match fields.get(key) {
    Some(Json::Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
fn contract_from_json(value : Json) -> ContractRow? {
  match value {
    Json::Object(fields) =>
      Some({
        contract_id: json_object_text(fields, "contract_id", ""),
        contract_code: json_object_text(fields, "contract_code", ""),
        contract_name: json_object_text(fields, "contract_name", ""),
        project_id: json_object_text(fields, "project_id", ""),
        project_name: json_object_text(fields, "project_name", ""),
        supplier_id: json_object_text(fields, "supplier_id", ""),
        supplier_name: json_object_text(fields, "supplier_name", ""),
        amount_minor: json_object_text(fields, "amount_minor", "0"),
        amount_display: json_object_text(fields, "amount_display", "—"),
        currency: json_object_text(fields, "currency", "CNY"),
        sign_date: json_object_text(fields, "sign_date", ""),
        state: json_object_text(fields, "state", ""),
        paid_amount_display: json_object_text(
          fields, "paid_amount_display", "—",
        ),
        milestone_count: json_object_text(fields, "milestone_count", "0"),
        source_kind: json_object_text(fields, "source_kind", "command"),
      })
    _ => None
  }
}

///|
fn contract_milestones_from_json(value : Json) -> Array[ContractMilestoneRow] {
  let rows : Array[ContractMilestoneRow] = []
  match value {
    Json::Array(values) =>
      for value in values {
        match value {
          Json::Object(fields) =>
            rows.push({
              milestone_id: json_object_text(fields, "milestone_id", ""),
              node_name: json_object_text(fields, "node_name", ""),
              plan_amount_display: json_object_text(
                fields, "plan_amount_display", "—",
              ),
              plan_pct_bps: json_object_text(fields, "plan_pct_bps", "0"),
              trigger_type: json_object_text(fields, "trigger_type", ""),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn contract_rows_from_body(body : String) -> Array[ContractRow] {
  let rows : Array[ContractRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(values)) =>
          for value in values {
            match contract_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn contract_detail_from_body(
  body : String,
) -> (ContractRow?, Array[ContractMilestoneRow]) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      (
        contract_from_json(parsed),
        match fields.get("milestones") {
          Some(value) => contract_milestones_from_json(value)
          None => []
        },
      )
    _ => (None, [])
  }
}

///|
fn payment_apply_from_json(value : Json) -> PaymentApplyRow? {
  match value {
    Json::Object(fields) =>
      Some({
        apply_id: json_object_text(fields, "apply_id", ""),
        apply_code: json_object_text(fields, "apply_code", ""),
        contract_id: json_object_text(fields, "contract_id", ""),
        contract_name: json_object_text(fields, "contract_name", ""),
        project_name: json_object_text(fields, "project_name", ""),
        supplier_name: json_object_text(fields, "supplier_name", ""),
        subject: json_object_text(fields, "subject", ""),
        amount_minor: json_object_text(fields, "amount_minor", "0"),
        amount_display: json_object_text(fields, "amount_display", "—"),
        currency: json_object_text(fields, "currency", "CNY"),
        apply_date: json_object_text(fields, "apply_date", ""),
        operation_state: json_object_text(fields, "operation_state", ""),
        apply_state: json_object_text(fields, "apply_state", ""),
        pay_state: json_object_text(fields, "pay_state", ""),
        apply_type_code: json_object_text(fields, "apply_type_code", ""),
        pay_class: json_object_text(fields, "pay_class", "合同"),
        applied_by: json_object_text(fields, "applied_by", ""),
        applied_by_name: json_object_text(fields, "applied_by_name", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
        plan_id: json_object_text(fields, "plan_id", ""),
        milestone_id: json_object_text(fields, "milestone_id", ""),
      })
    _ => None
  }
}

///|
fn payment_apply_rows_from_body(body : String) -> Array[PaymentApplyRow] {
  let rows : Array[PaymentApplyRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(values)) =>
          for value in values {
            match payment_apply_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn tender_from_json(value : Json) -> TenderRow? {
  match value {
    Json::Object(fields) => {
      let bids = match fields.get("bids") {
        Some(Json::Array(values)) => values.length().to_string()
        _ => "0"
      }
      Some({
        tender_id: json_object_text(fields, "tender_id", ""),
        name: json_object_text(fields, "name", ""),
        project_scope: json_object_text(fields, "project_scope", ""),
        category: json_object_text(fields, "category", ""),
        estimated_amount_minor: json_object_text(
          fields, "estimated_amount_minor", "0",
        ),
        estimated_amount_display: json_object_text(
          fields, "estimated_amount_display", "—",
        ),
        currency: json_object_text(fields, "currency", "CNY"),
        state: json_object_text(fields, "state", "planning"),
        awarded_supplier_id: json_object_text(fields, "awarded_supplier_id", ""),
        awarded_amount_display: json_object_text(
          fields, "awarded_amount_display", "—",
        ),
        commitment_id: json_object_text(fields, "commitment_id", ""),
        bid_count: bids,
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    }
    _ => None
  }
}

///|
fn tender_rows_from_body(body : String) -> Array[TenderRow] {
  let rows : Array[TenderRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(values)) =>
          for value in values {
            match tender_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn supplier_from_json(value : Json) -> SupplierRow? {
  match value {
    Json::Object(fields) =>
      Some({
        supplier_id: json_object_text(fields, "supplier_id", ""),
        supplier_code: json_object_text(fields, "supplier_code", ""),
        name: json_object_text(fields, "name", ""),
        category_code: json_object_text(fields, "category_code", ""),
        evaluation: json_object_text(fields, "evaluation", "unrated"),
        state: json_object_text(fields, "state", "draft"),
        scope: json_object_text(fields, "scope", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn supplier_rows_from_body(body : String) -> Array[SupplierRow] {
  let rows : Array[SupplierRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(values)) =>
          for value in values {
            match supplier_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn supplier_state_label(state : String) -> String {
  match state {
    "new" => "未创建"
    "pending" => "处理中"
    "draft" => "草稿"
    "pending_review" => "待审核"
    "active" => "正常"
    "suspended" => "暂停"
    "blacklisted" => "黑名单"
    "voided" => "已作废"
    "error" => "命令失败"
    _ => state
  }
}

///|
fn supplier_evaluation_label(evaluation : String) -> String {
  match evaluation {
    "unrated" => "未定级"
    "reviewed" => "已评审"
    "qualified" => "合格"
    "unqualified" => "不合格"
    "strategic" => "战略"
    _ => evaluation
  }
}

///|
fn sales_row_from_json(value : Json) -> SalesRow? {
  match value {
    Json::Object(fields) => {
      let aggregate_type = json_object_text(fields, "aggregate_type", "")
      let aggregate_id = json_object_text(fields, "aggregate_id", "")
      let primary = if aggregate_type == "customer" {
        json_object_text(fields, "name", aggregate_id)
      } else if aggregate_type == "subscription" {
        json_object_text(fields, "unit_reference", aggregate_id)
      } else if aggregate_type == "sales_agreement" {
        json_object_text(fields, "agreement_id", aggregate_id)
      } else if aggregate_type == "mortgage" {
        json_object_text(fields, "bank_reference", aggregate_id)
      } else if aggregate_type == "refund" {
        json_object_text(fields, "reason", aggregate_id)
      } else if aggregate_type == "sale_revenue" {
        json_object_text(fields, "revenue_code", aggregate_id)
      } else {
        json_object_text(fields, "customer_id", aggregate_id)
      }
      let secondary = if aggregate_type == "customer" {
        json_object_text(fields, "contact_reference", "")
      } else {
        json_object_text(fields, "customer_id", "")
      }
      Some({
        aggregate_id,
        primary,
        secondary,
        amount_display: json_object_text(fields, "amount_display", "—"),
        state: json_object_text(fields, "state", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    }
    _ => None
  }
}

///|
fn sales_rows_from_body(body : String) -> Array[SalesRow] {
  let rows : Array[SalesRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("items") {
        Some(Json::Array(values)) =>
          for value in values {
            match sales_row_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn json_array_field(fields : Map[String, Json], key : String) -> Array[Json] {
  match fields.get(key) {
    Some(Json::Array(values)) => values
    _ => []
  }
}

///|
fn delivery_progress_from_json(value : Json) -> DeliveryProgressRow? {
  match value {
    Json::Object(fields) =>
      Some({
        progress_id: json_object_text(fields, "progress_id", ""),
        project_id: json_object_text(fields, "project_id", ""),
        building_no: json_object_text(fields, "building_no", ""),
        stage: json_object_text(fields, "stage", ""),
        plan_date: json_object_text(fields, "plan_date", ""),
        plan_pct: json_object_text(fields, "plan_pct", "0"),
        actual_pct: json_object_text(fields, "actual_pct", "0"),
        actual_date: json_object_text(fields, "actual_date", ""),
        state: json_object_text(fields, "state", ""),
        remark: json_object_text(fields, "remark", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
        source_id: json_object_text(fields, "source_id", ""),
      })
    _ => None
  }
}

///|
fn delivery_output_from_json(value : Json) -> DeliveryOutputRow? {
  match value {
    Json::Object(fields) =>
      Some({
        output_id: json_object_text(fields, "output_id", ""),
        project_id: json_object_text(fields, "project_id", ""),
        contract_id: json_object_text(fields, "contract_id", ""),
        period: json_object_text(fields, "period", ""),
        output_amount: json_object_text(fields, "output_amount", "0"),
        confirm_amount: json_object_text(fields, "confirm_amount", "0"),
        state: json_object_text(fields, "state", "reported"),
        remark: json_object_text(fields, "remark", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn delivery_task_from_json(value : Json) -> DeliveryTaskRow? {
  match value {
    Json::Object(fields) =>
      Some({
        task_id: json_object_text(fields, "task_id", ""),
        task_name: json_object_text(fields, "task_name", ""),
        project_id: json_object_text(fields, "project_id", ""),
        plan_begin_date: json_object_text(fields, "plan_begin_date", ""),
        plan_end_date: json_object_text(fields, "plan_end_date", ""),
        progress_pct: json_object_text(fields, "progress_pct", "0"),
        status: json_object_text(fields, "status", "pending"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn delivery_report_from_json(value : Json) -> DeliveryReportRow? {
  match value {
    Json::Object(fields) =>
      Some({
        report_id: json_object_text(fields, "report_id", ""),
        task_id: json_object_text(fields, "task_id", ""),
        progress_pct: json_object_text(fields, "progress_pct", "0"),
        report_date: json_object_text(fields, "report_date", ""),
        summary: json_object_text(fields, "summary", ""),
        state: json_object_text(fields, "state", "observed"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn delivery_overview_from_body(
  body : String,
) -> (
  Array[DeliveryProgressRow],
  Array[DeliveryOutputRow],
  Array[DeliveryTaskRow],
  Array[DeliveryReportRow],
) {
  let progress : Array[DeliveryProgressRow] = []
  let outputs : Array[DeliveryOutputRow] = []
  let tasks : Array[DeliveryTaskRow] = []
  let reports : Array[DeliveryReportRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      for value in json_array_field(fields, "progress") {
        match delivery_progress_from_json(value) {
          Some(row) => progress.push(row)
          None => ()
        }
      }
      for value in json_array_field(fields, "outputs") {
        match delivery_output_from_json(value) {
          Some(row) => outputs.push(row)
          None => ()
        }
      }
      for value in json_array_field(fields, "tasks") {
        match delivery_task_from_json(value) {
          Some(row) => tasks.push(row)
          None => ()
        }
      }
      for value in json_array_field(fields, "reports") {
        match delivery_report_from_json(value) {
          Some(row) => reports.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  (progress, outputs, tasks, reports)
}

///|
fn report_cost_from_json(value : Json) -> ReportCostRow? {
  match value {
    Json::Object(fields) =>
      Some({
        bu_name: json_object_text(fields, "buName", ""),
        proj_code: json_object_text(fields, "projCode", ""),
        proj_name: json_object_text(fields, "projName", ""),
        target_cost: json_object_text(fields, "targetCost", "0"),
        dynamic_cost: json_object_text(fields, "dynamicCost", "0"),
        deviation_pct: json_object_text(fields, "deviationPct", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn report_contract_from_json(value : Json) -> ReportContractRow? {
  match value {
    Json::Object(fields) =>
      Some({
        contract_code: json_object_text(fields, "contractCode", ""),
        contract_name: json_object_text(fields, "contractName", ""),
        provider: json_object_text(fields, "provider", ""),
        current_amount: json_object_text(fields, "currentAmount", "0"),
        paid_total: json_object_text(fields, "paidTotal", "0"),
        remain_amount: json_object_text(fields, "remainAmount", "0"),
        paid_pct: json_object_text(fields, "paidPct", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn report_stage_from_json(value : Json) -> ReportStageRow? {
  match value {
    Json::Object(fields) =>
      Some({
        proj_code: json_object_text(fields, "projCode", ""),
        proj_name: json_object_text(fields, "projName", ""),
        bu_name: json_object_text(fields, "buName", ""),
        proj_status: json_object_text(fields, "projStatus", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn reports_from_body(
  body : String,
) -> (
  Array[ReportCostRow],
  Array[ReportContractRow],
  Array[ReportStageRow],
  String,
  String,
) {
  let costs : Array[ReportCostRow] = []
  let contracts : Array[ReportContractRow] = []
  let stages : Array[ReportStageRow] = []
  let mut supplier_count = "0"
  let mut approval_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      match fields.get("cost_summary") {
        Some(Json::Object(summary)) =>
          for value in json_array_field(summary, "rows") {
            match report_cost_from_json(value) {
              Some(row) => costs.push(row)
              None => ()
            }
          }
        _ => ()
      }
      for value in json_array_field(fields, "contract_payment_ledger") {
        match report_contract_from_json(value) {
          Some(row) => contracts.push(row)
          None => ()
        }
      }
      match fields.get("supplier_analysis") {
        Some(Json::Array(values)) =>
          supplier_count = values.length().to_string()
        _ => ()
      }
      match fields.get("approval_efficiency") {
        Some(Json::Object(approval)) =>
          match approval.get("byType") {
            Some(Json::Array(values)) =>
              approval_count = values.length().to_string()
            _ => ()
          }
        _ => ()
      }
      match fields.get("project_stage_matrix") {
        Some(Json::Object(matrix)) =>
          for value in json_array_field(matrix, "projects") {
            match report_stage_from_json(value) {
              Some(row) => stages.push(row)
              None => ()
            }
          }
        _ => ()
      }
    }
    _ => ()
  }
  (costs, contracts, stages, supplier_count, approval_count)
}

///|
fn dashboard_overview_from_body(body : String) -> (Bool, Array[String]) {
  let values : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      match fields.get("data") {
        Some(Json::Object(data)) => {
          values.push(json_object_text(data, "companyCount", "0"))
          values.push(json_object_text(data, "projectCount", "0"))
          values.push(json_object_text(data, "inProgressCount", "0"))
          values.push(json_object_text(data, "contractCount", "0"))
          values.push(json_object_text(data, "totalContractAmount", "0"))
          values.push(json_object_text(data, "paidAmount", "0"))
          values.push(json_object_text(data, "paidRatio", "0"))
          match data.get("cost") {
            Some(Json::Object(cost)) => {
              values.push(json_object_text(cost, "target", "0"))
              values.push(json_object_text(cost, "dynamic", "0"))
              values.push(json_object_text(cost, "deviationPct", "0"))
            }
            _ => {
              values.push("0")
              values.push("0")
              values.push("0")
            }
          }
          match data.get("anomalies") {
            Some(Json::Object(anomalies)) =>
              values.push(json_object_text(anomalies, "overdueTasks", "0"))
            _ => values.push("0")
          }
        }
        _ => ()
      }
      values.push(
        json_array_field(fields, "missing_source_tables").length().to_string(),
      )
    }
    _ => ()
  }
  (values.length() == 12, values)
}

///|
fn dashboard_funnel_rows_from_body(body : String) -> Array[DashboardFunnelRow] {
  let rows : Array[DashboardFunnelRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              stage_name: json_object_text(row, "stageName", ""),
              count: json_object_text(row, "count", "0"),
              width_pct: json_object_text(row, "widthPct", "0%"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn dashboard_anomaly_rows_from_body(
  body : String,
) -> Array[DashboardAnomalyRow] {
  let rows : Array[DashboardAnomalyRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              project_name: json_object_text(row, "projName", ""),
              company: json_object_text(row, "buName", ""),
              risk_score: json_object_text(row, "riskScore", "0"),
              reason: json_object_text(row, "reason", "正常"),
              source_kind: json_object_text(fields, "source_kind", "imported"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn admin_quality_rows_from_body(body : String) -> Array[AdminQualityRow] {
  let rows : Array[AdminQualityRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "rules") {
            match value {
              Json::Object(row) =>
                rows.push({
                  rule: json_object_text(row, "rule", ""),
                  count: json_object_text(row, "count", "—"),
                  severity: json_object_text(row, "severity", "info"),
                  status: json_object_text(row, "status", "NO_SOURCE_ROWS"),
                  source_kind: json_object_text(
                    row, "sourceKind", "imported_or_empty",
                  ),
                })
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn admin_dict_group_rows_from_body(body : String) -> Array[AdminDictGroupRow] {
  let rows : Array[AdminDictGroupRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              group_name: json_object_text(row, "groupName", ""),
              total: json_object_text(row, "total", "0"),
              enabled: json_object_text(row, "enabled", "0"),
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn admin_dict_option_rows_from_body(body : String) -> Array[AdminDictOptionRow] {
  let rows : Array[AdminDictOptionRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              group_name: json_object_text(row, "groupName", ""),
              code: json_object_text(row, "code", ""),
              value: json_object_text(row, "value", ""),
              display_order: json_object_text(row, "displayOrder", "0"),
              enabled: if json_object_text(row, "enabled", "false") == "true" {
                "启用"
              } else {
                "禁用"
              },
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn investment_version_from_body(body : String) -> (String, String) {
  let mut version_id = ""
  let mut version_name = ""
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) => {
            let current = json_object_text(row, "isCurrent", "false") == "true"
            if version_id == "" || current {
              version_id = json_object_text(row, "versionGuid", "")
              version_name = json_object_text(row, "versionName", "")
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  (version_id, version_name)
}

///|
fn investment_index_rows_from_body(
  body : String,
) -> (Array[InvestmentIndexRow], String) {
  let rows : Array[InvestmentIndexRow] = []
  let mut dimension_count = 0
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(dimension) => {
            dimension_count = dimension_count + 1
            let dimension_name = json_object_text(dimension, "name", "")
            for item in json_array_field(dimension, "items") {
              match item {
                Json::Object(row) =>
                  rows.push({
                    dimension: dimension_name,
                    index_name: json_object_text(row, "indexName", ""),
                    full_code: json_object_text(row, "fullCode", ""),
                    index_value: json_object_text(row, "indexValue", "—"),
                    unit: json_object_text(row, "unit", ""),
                    source_kind: json_object_text(row, "sourceKind", "imported"),
                  })
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  (rows, dimension_count.to_string())
}

///|
fn investment_profit_from_body(body : String) -> Array[String] {
  let values : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          values.push(json_object_text(data, "versionName", ""))
          values.push(json_object_text(data, "investment", "0"))
          values.push(json_object_text(data, "revenue", "0"))
          values.push(json_object_text(data, "cost", "0"))
          values.push(json_object_text(data, "netProfit", "0"))
          values.push(json_object_text(data, "netProfitMargin", "0"))
          values.push(json_object_text(data, "irr", "0"))
        }
        _ => ()
      }
    _ => ()
  }
  values
}

///|
fn audit_rows_from_body(body : String) -> (Array[AuditRow], String) {
  let rows : Array[AuditRow] = []
  let mut total = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          total = json_object_text(data, "total", "0")
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push({
                  log_id: json_object_text(row, "logId", ""),
                  created_at: json_object_text(row, "createdAt", ""),
                  emp_name: json_object_text(row, "empName", ""),
                  user_id: json_object_text(row, "userId", ""),
                  action: json_object_text(row, "action", ""),
                  target_type: json_object_text(row, "targetType", ""),
                  target_id: json_object_text(row, "targetId", ""),
                  ip: json_object_text(row, "ip", "已脱敏"),
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                })
              _ => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
  (rows, total)
}

///|
fn audit_action_rows_from_body(body : String) -> Array[AuditActionRow] {
  let rows : Array[AuditActionRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              action: json_object_text(row, "action", ""),
              count: json_object_text(row, "count", "0"),
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn dynamic_cost_from_body(
  body : String,
) -> (Array[DynamicCostRow], Array[String]) {
  let rows : Array[DynamicCostRow] = []
  let summary : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          match data.get("summary") {
            Some(Json::Object(summary_fields)) => {
              summary.push(json_object_text(summary_fields, "projectName", ""))
              summary.push(
                json_object_text(summary_fields, "A_targetCost", "0"),
              )
              summary.push(json_object_text(summary_fields, "B_dtCost", "0"))
              summary.push(
                json_object_text(summary_fields, "C_deviationPct", "0"),
              )
              summary.push(
                json_object_text(summary_fields, "H_layoutSpare", "0"),
              )
              summary.push(json_object_text(summary_fields, "endCount", "0"))
            }
            _ => ()
          }
          for value in json_array_field(data, "items") {
            match value {
              Json::Object(row) =>
                rows.push({
                  cost_guid: json_object_text(row, "costGuid", ""),
                  cost_code: json_object_text(row, "costCode", ""),
                  cost_name: json_object_text(row, "costName", ""),
                  cost_level: json_object_text(row, "costLevel", "0"),
                  target_cost: json_object_text(row, "A_targetCost", "0"),
                  dynamic_cost: json_object_text(row, "B_dtCost", "0"),
                  deviation_pct: json_object_text(row, "C_deviationPct", "—"),
                  contract_change: json_object_text(row, "D_htAlterAmount", "0"),
                  actual_cost: json_object_text(row, "E_ztCost", "0"),
                  budget_cost: json_object_text(row, "F_dfsBudget", "0"),
                  estimate_change: json_object_text(row, "G_ygAlter", "0"),
                  layout_spare: json_object_text(row, "H_layoutSpare", "0"),
                  end_cost: if json_object_text(row, "isEndCost", "false") ==
                    "true" {
                    "是"
                  } else {
                    "否"
                  },
                  remarks: json_object_text(row, "remarks", ""),
                  project_name: json_object_text(row, "projectName", ""),
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                })
              _ => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
  (rows, summary)
}

///|
fn profile_from_body(body : String) -> Array[String] {
  let values : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          values.push(json_object_text(data, "userId", ""))
          values.push(json_object_text(data, "userCode", ""))
          values.push(json_object_text(data, "userName", ""))
          values.push(json_object_text(data, "empName", ""))
          values.push(json_object_text(data, "buName", ""))
          values.push(json_object_text(data, "deptName", ""))
          values.push(
            if json_object_text(data, "isSuperUser", "false") == "true" {
              "是"
            } else {
              "否"
            },
          )
          values.push(
            if json_object_text(data, "enabled", "false") == "true" {
              "是"
            } else {
              "否"
            },
          )
          values.push(json_object_text(data, "lastLoginTime", ""))
          values.push(json_object_text(data, "sourceKind", "imported"))
        }
        _ => ()
      }
    _ => ()
  }
  values
}

///|
fn user_roster_rows_from_body(body : String) -> Array[UserRosterRow] {
  let rows : Array[UserRosterRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              user_code: json_object_text(row, "userCode", ""),
              emp_name: json_object_text(row, "empName", ""),
              bu_name: json_object_text(row, "buName", "—"),
              dept_name: json_object_text(row, "deptName", "—"),
              roles: if json_array_field(row, "roles").length() == 0 {
                "—"
              } else {
                json_array_field(row, "roles").length().to_string()
              },
              roles_source_status: json_object_text(
                row, "rolesSourceStatus", "NO_SOURCE_ROWS",
              ),
              super_user: if json_object_text(row, "isSuperUser", "false") ==
                "true" {
                "是(证据)"
              } else {
                "否"
              },
              enabled: if json_object_text(row, "enabled", "false") == "true" {
                "启用"
              } else {
                "禁用"
              },
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn health_table_rows_from_body(body : String) -> Array[HealthTableRow] {
  let rows : Array[HealthTableRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              table: json_object_text(row, "table", ""),
              row_count: json_object_text(row, "rowCount", "—"),
              source_status: json_object_text(row, "sourceStatus", "unknown"),
              source_kind: json_object_text(
                row, "sourceKind", "imported_or_empty",
              ),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn health_table_counts_from_body(body : String) -> (String, String) {
  let rows = health_table_rows_from_body(body)
  let mut empty_count = 0
  for row in rows {
    if row.source_status != "rows_imported" {
      empty_count = empty_count + 1
    }
  }
  (rows.length().to_string(), empty_count.to_string())
}

///|
fn health_bpm_counts_from_body(body : String) -> (String, String) {
  let mut instance_count = "0"
  let mut action_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let mut total = 0
          for value in json_array_field(data, "byStatus") {
            match value {
              Json::Object(row) => total = total + json_object_int(row, "count")
              _ => ()
            }
          }
          instance_count = total.to_string()
        }
        _ => ()
      }
      match fields.get("source_coverage") {
        Some(Json::Object(coverage)) =>
          action_count = json_object_text(coverage, "wf_step_action", "0")
        _ => ()
      }
    }
    _ => ()
  }
  (instance_count, action_count)
}

///|
fn loan_from_json(value : Json) -> LoanRow? {
  match value {
    Json::Object(fields) =>
      Some({
        loan_id: json_object_text(fields, "loan_id", ""),
        loan_code: json_object_text(fields, "loan_code", ""),
        subject: json_object_text(fields, "subject", ""),
        apply_state: json_object_text(fields, "apply_state", ""),
        loan_amount: json_object_text(fields, "loan_amount", "0"),
        balance_amount: json_object_text(fields, "balance_amount", "0"),
        remain_amount: json_object_text(fields, "remain_amount", "0"),
        applied_by_name: json_object_text(fields, "applied_by_name", ""),
        apply_dept_name: json_object_text(fields, "apply_dept_name", ""),
        project_name: json_object_text(fields, "project_name", ""),
        apply_date: json_object_text(fields, "apply_date", ""),
        pay_unit: json_object_text(fields, "pay_unit", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn loan_rows_from_body(body : String) -> Array[LoanRow] {
  let rows : Array[LoanRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "items") {
        match loan_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn workflow_step_from_json(value : Json) -> WorkflowStepRow? {
  match value {
    Json::Object(fields) => {
      let mut assignee_names = ""
      for assignee in json_array_field(fields, "assignees") {
        match assignee {
          Json::Object(assignee_fields) => {
            let name = json_object_text(
              assignee_fields,
              "user_name",
              json_object_text(assignee_fields, "user_code", ""),
            )
            if name != "" {
              if assignee_names != "" {
                assignee_names = assignee_names + "、"
              }
              assignee_names = assignee_names + name
            }
          }
          _ => ()
        }
      }
      Some({
        step_guid: json_object_text(fields, "step_guid", ""),
        step_key: json_object_text(fields, "step_key", ""),
        step_order: json_object_text(fields, "step_order", "0"),
        step_name: json_object_text(fields, "step_name", ""),
        threshold: json_object_text(fields, "threshold", "1"),
        assignee_count: json_array_field(fields, "assignees")
        .length()
        .to_string(),
        assignee_names,
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    }
    _ => None
  }
}

///|
fn workflow_process_from_json(value : Json) -> WorkflowProcessRow? {
  match value {
    Json::Object(fields) => {
      let steps : Array[WorkflowStepRow] = []
      for step in json_array_field(fields, "steps") {
        match workflow_step_from_json(step) {
          Some(row) => steps.push(row)
          None => ()
        }
      }
      Some({
        process_guid: json_object_text(fields, "process_guid", ""),
        process_key: json_object_text(fields, "process_key", ""),
        process_name: json_object_text(fields, "process_name", ""),
        biz_type: json_object_text(fields, "biz_type", ""),
        step_count: json_object_text(
          fields,
          "step_count",
          steps.length().to_string(),
        ),
        instances_available: json_object_text(
          fields, "instances_available", "0",
        ),
        actions_available: json_object_text(fields, "actions_available", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
        steps,
      })
    }
    _ => None
  }
}

///|
fn workflow_rows_from_body(body : String) -> Array[WorkflowProcessRow] {
  let rows : Array[WorkflowProcessRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "items") {
        match workflow_process_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn project_from_json(value : Json) -> ProjectRow? {
  match value {
    Json::Object(fields) => {
      let mut lifecycle_text = ""
      let mut current_stage = ""
      let mut last_done = ""
      for stage in json_array_field(fields, "lifecycle") {
        match stage {
          Json::Object(stage_fields) => {
            let stage_name = json_object_text(stage_fields, "stage_name", "")
            let stage_status = json_object_text(
              stage_fields, "status", "pending",
            )
            let progress = json_object_text(stage_fields, "progress_pct", "0")
            if lifecycle_text != "" {
              lifecycle_text = lifecycle_text + " · "
            }
            lifecycle_text = lifecycle_text +
              stage_name +
              ":" +
              stage_status +
              " " +
              progress +
              "%"
            if stage_status == "in_progress" && current_stage == "" {
              current_stage = stage_name
            }
            if stage_status == "done" {
              last_done = stage_name
            }
          }
          _ => ()
        }
      }
      if current_stage == "" {
        current_stage = last_done
      }
      Some({
        project_id: json_object_text(fields, "project_id", ""),
        project_code: json_object_text(fields, "project_code", ""),
        project_name: json_object_text(fields, "project_name", ""),
        bu_name: json_object_text(fields, "bu_name", ""),
        proj_status: json_object_text(fields, "proj_status", ""),
        begin_date: json_object_text(fields, "begin_date", ""),
        current_stage: json_object_text(fields, "current_stage", current_stage),
        task_count: json_object_text(fields, "task_count", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
        lifecycle_text,
      })
    }
    _ => None
  }
}

///|
fn project_rows_from_body(body : String) -> Array[ProjectRow] {
  let rows : Array[ProjectRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "items") {
        match project_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn project_detail_from_body(body : String) -> ProjectRow? {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  project_from_json(parsed)
}

///|
fn load_sales(emit : @rabbita.Emit[Msg], family : String) -> Cmd {
  let path = if family == "invoices" {
    "/api/company/invoices"
  } else {
    "/api/company/sales/" + family
  }
  @http.get(path).expect_text(result => {
    match result {
      Ok(body) => emit(SalesLoaded(family, body))
      Err(_) => emit(SalesLoadFailed(family))
    }
  })
}

///|
fn load_delivery(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/delivery/overview?project_id=proj-0001").expect_text(result => {
    match result {
      Ok(body) => emit(DeliveryLoaded(body))
      Err(_) => emit(DeliveryLoadFailed)
    }
  })
}

///|
fn load_reports(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/reports/overview").expect_text(result => {
    match result {
      Ok(body) => emit(ReportsLoaded(body))
      Err(_) => emit(ReportsLoadFailed)
    }
  })
}

///|
fn load_dashboard_overview(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/dashboard/group/overview").expect_text(result => {
    match result {
      Ok(body) => emit(DashboardOverviewLoaded(body))
      Err(_) => emit(DashboardLoadFailed)
    }
  })
}

///|
fn load_dashboard_funnel(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/dashboard/group/funnel").expect_text(result => {
    match result {
      Ok(body) => emit(DashboardFunnelLoaded(body))
      Err(_) => emit(DashboardLoadFailed)
    }
  })
}

///|
fn load_dashboard_anomalies(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/dashboard/group/top-anomalies?limit=5").expect_text(result => {
    match result {
      Ok(body) => emit(DashboardAnomaliesLoaded(body))
      Err(_) => emit(DashboardLoadFailed)
    }
  })
}

///|
fn load_admin_quality(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/quality/overview").expect_text(result => {
    match result {
      Ok(body) => emit(AdminQualityLoaded(body))
      Err(_) => emit(AdminQualityLoadFailed)
    }
  })
}

///|
fn load_admin_dict_groups(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/dict/groups").expect_text(result => {
    match result {
      Ok(body) => emit(AdminDictGroupsLoaded(body))
      Err(_) => emit(AdminDictLoadFailed)
    }
  })
}

///|
fn load_admin_dict_options(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/dict/options").expect_text(result => {
    match result {
      Ok(body) => emit(AdminDictOptionsLoaded(body))
      Err(_) => emit(AdminDictLoadFailed)
    }
  })
}

///|
fn load_investment_versions(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/investment/projects/proj-0001/versions").expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentVersionsLoaded(body))
      Err(_) => emit(InvestmentLoadFailed)
    }
  })
}

///|
fn load_investment_indices(
  emit : @rabbita.Emit[Msg],
  version_id : String,
) -> Cmd {
  @http.get("/api/company/investment/versions/" + version_id + "/indices").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentIndicesLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn load_investment_profit(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/investment/projects/proj-0001/profit-summary").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentProfitLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn load_audit_logs(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/audit/logs?limit=100").expect_text(result => {
    match result {
      Ok(body) => emit(AuditLoaded(body))
      Err(_) => emit(AuditLoadFailed)
    }
  })
}

///|
fn load_audit_actions(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/audit/actions").expect_text(result => {
    match result {
      Ok(body) => emit(AuditActionsLoaded(body))
      Err(_) => emit(AuditLoadFailed)
    }
  })
}

///|
fn load_dynamic_cost(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/cost/dynamic-cost?projGuid=proj-0001").expect_text(result => {
    match result {
      Ok(body) => emit(DynamicCostLoaded(body))
      Err(_) => emit(DynamicCostLoadFailed)
    }
  })
}

///|
fn load_profile(emit : @rabbita.Emit[Msg], user_code : String) -> Cmd {
  let code = if user_code == "" { "admin" } else { user_code }
  @http.get("/api/company/auth/me?userCode=" + code).expect_text(result => {
    match result {
      Ok(body) => emit(ProfileLoaded(body))
      Err(_) => emit(ProfileLoadFailed)
    }
  })
}

///|
fn load_users(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/rbac/users").expect_text(result => {
    match result {
      Ok(body) => emit(UsersLoaded(body))
      Err(_) => emit(UsersLoadFailed)
    }
  })
}

///|
fn load_health_tables(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/health/tables").expect_text(result => {
    match result {
      Ok(body) => emit(HealthTablesLoaded(body))
      Err(_) => emit(HealthLoadFailed)
    }
  })
}

///|
fn load_health_bpm(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/health/bpm-pool").expect_text(result => {
    match result {
      Ok(body) => emit(HealthBpmLoaded(body))
      Err(_) => emit(HealthLoadFailed)
    }
  })
}

///|
fn load_loans(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/loans").expect_text(result => {
    match result {
      Ok(body) => emit(LoansLoaded(body))
      Err(_) => emit(LoansLoadFailed)
    }
  })
}

///|
fn load_workflow(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/workflow/process-defs").expect_text(result => {
    match result {
      Ok(body) => emit(WorkflowLoaded(body))
      Err(_) => emit(WorkflowLoadFailed)
    }
  })
}

///|
fn load_projects(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/projects").expect_text(result => {
    match result {
      Ok(body) => emit(ProjectsLoaded(body))
      Err(_) => emit(ProjectsLoadFailed)
    }
  })
}

///|
fn load_project(emit : @rabbita.Emit[Msg], path : String) -> Cmd {
  @http.get("/api/company" + path).expect_text(result => {
    match result {
      Ok(body) => emit(ProjectLoaded(body))
      Err(_) => emit(ProjectLoadFailed)
    }
  })
}

///|
fn loan_command_body(command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-loan-create-v1\",\"loan_id\":\"LOAN-RABBITA-LOCAL\",\"loan_code\":\"JK-RABBITA-LOCAL\",\"subject\":\"沈阳项目会议备用金\",\"employee_id\":\"employee-rabbita\",\"principal_id\":\"co-rabbita\",\"scope\":\"employee:employee-rabbita\",\"currency\":\"CNY\",\"amount_minor\":800000,\"apply_dept_guid\":\"bu-rabbita\",\"apply_date\":\"2026-07-13\",\"pay_unit\":\"个人备用金\",\"proj_guid\":\"proj-0001\",\"evidence_ids\":[\"rabbita:loan:purpose-001\"],\"authority\":{\"active\":true,\"principal_id\":\"co-rabbita\",\"actor_id\":\"rabbita-user\",\"capability\":\"advance:create\",\"scope\":\"employee:employee-rabbita\",\"max_amount_minor\":800000}}"
  } else if command_type == "update" {
    "{\"idempotency_key\":\"rabbita-loan-update-v1\",\"subject\":\"沈阳项目会议备用金（已补充用途）\",\"pay_unit\":\"个人备用金\",\"proj_guid\":\"proj-0001\"}"
  } else if command_type == "void" {
    "{\"idempotency_key\":\"rabbita-loan-void-v1\",\"reason\":\"本地演示撤回借款\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-loan-submit-v1\"}"
  }
}

///|
fn issue_loan_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let suffix = if command_type == "submit" {
    "submit-for-approval"
  } else {
    command_type
  }
  let path = if command_type == "create" {
    "/api/company/loans"
  } else {
    "/api/company/loans/" + model.loan_id + "/" + suffix
  }
  @http.post(path)
  .with_text(loan_command_body(command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(LoanCommandFinished(body))
      Err(_) => emit(LoanCommandFailed)
    }
  })
}

///|
fn delivery_command_body(command_type : String) -> String {
  if command_type == "create_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-create-v1\",\"progress_id\":\"PROG-RABBITA-LOCAL\",\"project_id\":\"proj-0001\",\"principal_id\":\"co-rabbita\",\"project_scope\":\"project:proj-0001\",\"stage\":\"主体结构\",\"plan_pct\":70,\"completed_value_minor\":125000,\"currency\":\"CNY\",\"evidence_ids\":[\"rabbita:progress:photo-001\"],\"remark\":\"本地进度命令演示\"}"
  } else if command_type == "report_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-report-v1\",\"progress_pct\":55,\"actual_date\":\"2026-07-13\",\"evidence_ids\":[\"rabbita:progress:report-001\"],\"remark\":\"已完成现场复核\"}"
  } else if command_type == "accept_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-accept-v1\",\"acceptance_id\":\"accept-rabbita-001\",\"acceptance_evidence_ids\":[\"rabbita:progress:acceptance-001\"]}"
  } else if command_type == "reject_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-reject-v1\",\"reason\":\"需要补充验收记录\"}"
  } else if command_type == "create_output" {
    "{\"idempotency_key\":\"rabbita-delivery-output-create-v1\",\"output_id\":\"OUT-RABBITA-LOCAL\",\"project_id\":\"proj-0001\",\"contract_id\":\"ht-tj-001\",\"period\":\"2026-07\",\"output_amount\":\"125000\",\"evidence_ids\":[\"rabbita:output:measure-001\"],\"remark\":\"本地产值确认演示\"}"
  } else if command_type == "confirm_output" {
    "{\"idempotency_key\":\"rabbita-delivery-output-confirm-v1\",\"confirm_amount\":\"125000\",\"confirmed_at\":\"2026-07-13\",\"evidence_ids\":[\"rabbita:output:acceptance-001\"]}"
  } else {
    "{\"idempotency_key\":\"rabbita-delivery-task-report-v1\",\"report_id\":\"TASK-REPORT-RABBITA-LOCAL\",\"task_id\":\"task-003\",\"project_id\":\"proj-0001\",\"progress_pct\":70,\"report_date\":\"2026-07-13\",\"summary\":\"本地任务汇报演示\",\"evidence_ids\":[\"rabbita:task-report:001\"]}"
  }
}

///|
fn issue_delivery_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create_progress" {
    "/api/company/delivery/progress"
  } else if command_type == "report_progress" {
    "/api/company/delivery/progress/\{model.delivery_progress_id}/report"
  } else if command_type == "accept_progress" {
    "/api/company/delivery/progress/\{model.delivery_progress_id}/accept"
  } else if command_type == "reject_progress" {
    "/api/company/delivery/progress/\{model.delivery_progress_id}/reject"
  } else if command_type == "create_output" {
    "/api/company/delivery/outputs"
  } else if command_type == "confirm_output" {
    "/api/company/delivery/outputs/\{model.delivery_output_id}/confirm"
  } else {
    "/api/company/delivery/tasks/\{model.delivery_task_id}/report"
  }
  @http.post(path)
  .with_text(delivery_command_body(command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(DeliveryCommandFinished(body))
      Err(_) => emit(DeliveryCommandFailed)
    }
  })
}

///|
fn load_suppliers(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/suppliers").expect_text(result => {
    match result {
      Ok(body) => emit(SuppliersLoaded(body))
      Err(_) => emit(SuppliersLoadFailed)
    }
  })
}

///|
fn supplier_command_body(_model : Model, command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-supplier-create-v1\",\"supplier_id\":\"SUP-RABBITA-LOCAL\",\"principal_id\":\"co-rabbita\",\"scope\":\"project:proj-0001\",\"supplier_code\":\"SUP-RABBITA-LOCAL\",\"name\":\"Rabbita 本地示例供应商\",\"category_code\":\"construction\"}"
  } else if command_type == "update" {
    "{\"idempotency_key\":\"rabbita-supplier-update-v1\",\"name\":\"Rabbita 本地示例供应商（已更新）\"}"
  } else if command_type == "review" {
    "{\"idempotency_key\":\"rabbita-supplier-review-v1\",\"evaluation\":\"qualified\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-supplier-" + command_type + "-v1\"}"
  }
}

///|
fn issue_supplier_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/suppliers"
  } else {
    "/api/company/suppliers/\{model.supplier_id}/\{command_type}"
  }
  @http.post(path)
  .with_text(supplier_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(SupplierCommandFinished(body))
      Err(_) => emit(SupplierCommandFailed)
    }
  })
}

///|
fn tender_state_label(state : String) -> String {
  match state {
    "planning" => "待规划"
    "publishing" => "公告中"
    "bidding" => "招标中"
    "awarded" => "已定标"
    "completed" => "已完成"
    "cancelled" => "已取消"
    _ => state
  }
}

///|
fn load_tenders(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/tenders").expect_text(result => {
    match result {
      Ok(body) => emit(TendersLoaded(body))
      Err(_) => emit(TendersLoadFailed)
    }
  })
}

///|
fn tender_command_body(_model : Model, command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-tender-create-v1\",\"tender_id\":\"TD-RABBITA-LOCAL\",\"project_scope\":\"project:proj-0001\",\"name\":\"海教园主体结构工程招标\",\"category\":\"construction\",\"estimated_amount_minor\":120000000,\"currency\":\"CNY\",\"bids\":[{\"supplier_id\":\"SUP-RABBITA-LOCAL\",\"amount_minor\":105000000}]}"
  } else if command_type == "cancel" {
    "{\"idempotency_key\":\"rabbita-tender-cancel-v1\",\"reason\":\"本地演示撤回规划\"}"
  } else if command_type == "award" {
    "{\"idempotency_key\":\"rabbita-tender-award-v1\",\"awarded_supplier_id\":\"SUP-RABBITA-LOCAL\",\"awarded_amount_minor\":105000000}"
  } else {
    "{\"idempotency_key\":\"rabbita-tender-" + command_type + "-v1\"}"
  }
}

///|
fn issue_tender_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/tenders"
  } else {
    "/api/company/tenders/\{model.tender_id}/\{command_type}"
  }
  @http.post(path)
  .with_text(tender_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(TenderCommandFinished(body))
      Err(_) => emit(TenderCommandFailed)
    }
  })
}

///|
fn payment_apply_state_label(state : String) -> String {
  match state {
    "draft" => "草稿"
    "submitted" => "审批中"
    "rejected" => "已驳回"
    "approved" => "已审核"
    "voided" => "已作废"
    "paid" => "完全支付"
    "partially_paid" => "部分支付"
    _ => state
  }
}

///|
fn load_payment_applies(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/payment-applies").expect_text(result => {
    match result {
      Ok(body) => emit(PaymentAppliesLoaded(body))
      Err(_) => emit(PaymentAppliesLoadFailed)
    }
  })
}

///|
fn payment_apply_command_body(_model : Model, command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-payment-create-v1\",\"apply_id\":\"PAY-RABBITA-LOCAL\",\"apply_code\":\"FK-RABBITA-LOCAL\",\"contract_id\":\"ht-tj-001\",\"plan_id\":\"plan-tj-001-2\",\"subject\":\"海教园1号楼总包进度款 Rabbita 演示\",\"amount_minor\":12000000,\"currency\":\"CNY\",\"apply_type_code\":\"WORK_PROGRESS\"}"
  } else if command_type == "reject" {
    "{\"idempotency_key\":\"rabbita-payment-reject-v1\",\"reason\":\"请补充付款申请附件\"}"
  } else if command_type == "update" {
    "{\"idempotency_key\":\"rabbita-payment-update-v1\",\"subject\":\"海教园1号楼总包进度款 Rabbita 演示（已补充说明）\",\"amount_minor\":12000000,\"apply_type_code\":\"WORK_PROGRESS\"}"
  } else if command_type == "void" {
    "{\"idempotency_key\":\"rabbita-payment-void-v1\",\"reason\":\"本地演示撤回付款申请\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-payment-" + command_type + "-v1\"}"
  }
}

///|
fn check_payment_eligibility(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get(
    "/api/company/payment-applies/eligibility?plan_id=plan-tj-001-2&amount_minor=12000000",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(PaymentEligibilityLoaded(body))
      Err(_) => emit(PaymentEligibilityLoadFailed)
    }
  })
}

///|
fn issue_payment_apply_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/payment-applies"
  } else {
    "/api/company/payment-applies/\{model.payment_apply_id}/\{command_type}"
  }
  @http.post(path)
  .with_text(payment_apply_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(PaymentApplyCommandFinished(body))
      Err(_) => emit(PaymentApplyCommandFailed)
    }
  })
}

///|
fn contract_state_label(state : String) -> String {
  match state {
    "draft" => "草稿"
    "submitted" => "审批中"
    "rejected" => "已驳回"
    "approved" => "已批准"
    "active" => "履行中"
    _ => state
  }
}

///|
fn load_contracts(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/contracts").expect_text(result => {
    match result {
      Ok(body) => emit(ContractsLoaded(body))
      Err(_) => emit(ContractsLoadFailed)
    }
  })
}

///|
fn load_contract(emit : @rabbita.Emit[Msg], path : String) -> Cmd {
  @http.get("/api/company" + path).expect_text(result => {
    match result {
      Ok(body) => emit(ContractLoaded(body))
      Err(_) => emit(ContractLoadFailed)
    }
  })
}

///|
fn contract_command_body(_model : Model, command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-contract-create-v1\",\"contract_id\":\"CT-RABBITA-LOCAL\",\"contract_code\":\"HT-RABBITA-LOCAL\",\"contract_name\":\"成都项目主体结构施工合同\",\"project_id\":\"CD-HJL\",\"project_name\":\"成都和锦里\",\"supplier_id\":\"supplier-rabbita\",\"supplier_name\":\"示例建设供应商\",\"sign_date\":\"2026-07-13\",\"amount_minor\":4860000000,\"currency\":\"CNY\"}"
  } else if command_type == "reject" {
    "{\"idempotency_key\":\"rabbita-contract-reject-v1\",\"reason\":\"请补充合同附件与付款节点\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-contract-" + command_type + "-v1\"}"
  }
}

///|
fn issue_contract_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/contracts"
  } else {
    "/api/company/contracts/\{model.contract_id}/\{command_type}"
  }
  @http.post(path)
  .with_text(contract_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(ContractCommandFinished(body))
      Err(_) => emit(ContractCommandFailed)
    }
  })
}

///|
fn session_login_body(model : Model) -> String {
  Json::object({
    "user_code": Json::string(model.user_code),
    "password": Json::string(model.password),
  }).stringify()
}

///|
fn login_session(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/session/login")
  .with_text(session_login_body(model))
  .expect_text(result => {
    match result {
      Ok(body) if body.contains("\"authenticated\":true") =>
        emit(SessionAuthenticated)
      Ok(body) if body.contains("unknown read-model endpoint") =>
        emit(SessionAdapterFallback)
      Err(_) => emit(SessionAdapterFallback)
      Ok(body) => emit(SessionLoginRejected(body))
    }
  })
}

///|
fn update(emit : @rabbita.Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    Login =>
      (
        login_session(emit, model),
        {
          ..model,
          api_status: "认证中",
          api_note: "正在验证本地开发会话…",
        },
      )
    ToggleDemo => (none, { ..model, show_demo: !model.show_demo })
    FillDemo(user_code, password) =>
      (none, { ..model, user_code, password, show_demo: false })
    InputUser(value) => (none, { ..model, user_code: value })
    InputPassword(value) => (none, { ..model, password: value })
    Navigate(path) => {
      let command = if path == "/dashboard" ||
        path == "/dashboard-v3" ||
        path == "/cockpit" {
        load_dashboard_overview(emit)
      } else if path == "/projects" {
        load_projects(emit)
      } else if path.has_prefix("/projects/") {
        load_project(emit, path)
      } else if path == "/contracts" {
        load_contracts(emit)
      } else if path.has_prefix("/contracts/") {
        load_contract(emit, path)
      } else if path == "/payment-applies" {
        load_payment_applies(emit)
      } else if path == "/tender" {
        load_tenders(emit)
      } else if path == "/srm/providers" {
        load_suppliers(emit)
      } else if path == "/sales/customers" {
        load_sales(emit, "customers")
      } else if path == "/sales/subscriptions" {
        load_sales(emit, "subscriptions")
      } else if path == "/sales/contracts" {
        load_sales(emit, "contracts")
      } else if path == "/sales/mortgages" {
        load_sales(emit, "mortgages")
      } else if path == "/sales/revenues" {
        load_sales(emit, "revenues")
      } else if path == "/invoice" {
        load_sales(emit, "invoices")
      } else if path == "/reports" {
        load_reports(emit)
      } else if path == "/admin" {
        load_admin_quality(emit)
      } else if path == "/users" {
        load_users(emit)
      } else if path == "/investment" {
        load_investment_versions(emit)
      } else if path == "/audit-log" {
        load_audit_logs(emit)
      } else if path == "/dynamic-cost" {
        load_dynamic_cost(emit)
      } else if path == "/profile" {
        load_profile(emit, model.user_code)
      } else if path == "/system-health" {
        load_health_tables(emit)
      } else if path == "/loans" {
        load_loans(emit)
      } else if path == "/tasks" {
        load_workflow(emit)
      } else if path == "/project-plan" || path == "/project/progress" {
        load_delivery(emit)
      } else {
        none
      }
      let contract_id = match path.rev_split_once("/") {
        Some((prefix, value)) if prefix == "/contracts" => value.to_owned()
        _ => model.contract_id
      }
      let loan_id = match path.rev_split_once("/") {
        Some((prefix, value)) if prefix == "/loans" && value != "new" =>
          value.to_owned()
        _ if path == "/loans/new" => "LOAN-RABBITA-LOCAL"
        _ => model.loan_id
      }
      let loan_state = if path == "/loans/new" {
        "new"
      } else if path.has_prefix("/loans/") && loan_id != "LOAN-RABBITA-LOCAL" {
        "Imported"
      } else {
        model.loan_state
      }
      (
        command,
        {
          ..model,
          authenticated: true,
          page: path,
          mobile_nav: false,
          contract_id,
          loan_id,
          loan_state,
          contract_detail: if path == "/contracts" {
            None
          } else {
            model.contract_detail
          },
        },
      )
    }
    ToggleSidebar => (none, { ..model, collapsed: !model.collapsed })
    ToggleMobileNav => (none, { ..model, mobile_nav: !model.mobile_nav })
    ToggleGroup(group) => {
      let open_group = match model.open_group {
        Some(current) if current == group => None
        _ => Some(group)
      }
      (none, { ..model, open_group, })
    }
    RefreshApi => (refresh_api(emit), model)
    SessionAuthenticated =>
      (
        refresh_api(emit),
        {
          ..model,
          authenticated: true,
          page: "/dashboard",
          mobile_nav: false,
          api_status: "已认证",
          api_note: "本地会话已建立",
        },
      )
    SessionAdapterFallback =>
      (
        refresh_api(emit),
        {
          ..model,
          authenticated: true,
          page: "/dashboard",
          mobile_nav: false,
          api_note: "只读适配器未启用会话 · 使用已审核快照",
        },
      )
    SessionLoginRejected(body) =>
      (
        none,
        {
          ..model,
          authenticated: false,
          page: "/login",
          api_status: "登录失败",
          api_note: body,
        },
      )
    ApiLoaded =>
      (
        load_dashboard_overview(emit),
        {
          ..model,
          api_status: "已连接",
          api_note: "PostgreSQL 投影读模型",
        },
      )
    ApiFailed =>
      (
        none,
        {
          ..model,
          api_status: "离线回退",
          api_note: "使用已审核快照",
        },
      )
    ContractsLoaded(body) =>
      (
        none,
        {
          ..model,
          contracts_loaded: true,
          contract_rows: contract_rows_from_body(body),
          contract_note: "已加载 PostgreSQL 合同与付款节点",
        },
      )
    ContractsLoadFailed =>
      (
        none,
        {
          ..model,
          contracts_loaded: false,
          contract_note: "合同读模型不可用 · 使用已审核快照",
        },
      )
    ContractLoaded(body) => {
      let (detail, milestones) = contract_detail_from_body(body)
      match detail {
        Some(row) =>
          (
            none,
            {
              ..model,
              contract_detail: Some(row),
              contract_milestones: milestones,
              contract_id: row.contract_id,
              contract_state: row.state,
              contract_note: "已加载 PostgreSQL 合同详情与付款节点",
            },
          )
        None =>
          (none, { ..model, contract_note: "合同详情响应无法解析" })
      }
    }
    ContractLoadFailed =>
      (
        none,
        {
          ..model,
          contract_detail: None,
          contract_milestones: [],
          contract_note: "合同详情不可用 · 可先保存本地草稿",
        },
      )
    CreateContract =>
      if model.contract_state == "draft" || model.contract_state == "submitted" {
        (none, model)
      } else {
        (
          issue_contract_command(emit, model, "create"),
          {
            ..model,
            contract_state: "pending",
            contract_note: "正在创建并写入 PostgreSQL 投影…",
          },
        )
      }
    SubmitContract =>
      if model.contract_id == "" || model.contract_state != "draft" {
        (none, model)
      } else {
        (
          issue_contract_command(emit, model, "submit"),
          {
            ..model,
            contract_state: "pending",
            contract_note: "正在提交合同审批…",
          },
        )
      }
    RejectContract =>
      if model.contract_id == "" || model.contract_state != "submitted" {
        (none, model)
      } else {
        (
          issue_contract_command(emit, model, "reject"),
          {
            ..model,
            contract_state: "pending",
            contract_note: "正在退回合同并写入审计…",
          },
        )
      }
    ResubmitContract =>
      if model.contract_id == "" || model.contract_state != "rejected" {
        (none, model)
      } else {
        (
          issue_contract_command(emit, model, "resubmit"),
          {
            ..model,
            contract_state: "pending",
            contract_note: "正在重新提交合同审批…",
          },
        )
      }
    ApproveContract =>
      if model.contract_id == "" || model.contract_state != "submitted" {
        (none, model)
      } else {
        (
          issue_contract_command(emit, model, "approve"),
          {
            ..model,
            contract_state: "pending",
            contract_note: "正在批准合同并写入审计…",
          },
        )
      }
    ContractCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"approved\"") {
        "approved"
      } else if body.contains("\"state\":\"rejected\"") {
        "rejected"
      } else if body.contains("\"state\":\"submitted\"") {
        "submitted"
      } else if body.contains("\"state\":\"draft\"") {
        "draft"
      } else {
        "error"
      }
      if next_state == "error" {
        (none, { ..model, contract_state: "error", contract_note: body })
      } else {
        (
          load_contract(emit, "/contracts/" + model.contract_id),
          {
            ..model,
            contract_state: next_state,
            contract_note: "已写入 PostgreSQL · 合同状态已更新 · 审计凭证已生成",
          },
        )
      }
    }
    ContractCommandFailed =>
      (
        none,
        {
          ..model,
          contract_state: "error",
          contract_note: "公司合同命令服务不可用或拒绝了请求",
        },
      )
    PaymentAppliesLoaded(body) =>
      (
        none,
        {
          ..model,
          payment_applies_loaded: true,
          payment_apply_rows: payment_apply_rows_from_body(body),
          payment_apply_note: "已加载 PostgreSQL 付款申请与支付状态",
        },
      )
    PaymentAppliesLoadFailed =>
      (
        none,
        {
          ..model,
          payment_applies_loaded: false,
          payment_apply_note: "付款申请读模型不可用 · 使用已审核快照",
        },
      )
    CreatePaymentApply =>
      if model.payment_apply_state == "draft" ||
        model.payment_apply_state == "submitted" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "create"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在创建付款申请并写入 PostgreSQL 投影…",
          },
        )
      }
    SubmitPaymentApply =>
      if model.payment_apply_id == "" || model.payment_apply_state != "draft" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "submit"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在提交付款申请审批…",
          },
        )
      }
    RejectPaymentApply =>
      if model.payment_apply_id == "" ||
        model.payment_apply_state != "submitted" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "reject"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在退回付款申请并写入审计…",
          },
        )
      }
    ResubmitPaymentApply =>
      if model.payment_apply_id == "" || model.payment_apply_state != "rejected" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "resubmit"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在重新提交付款申请审批…",
          },
        )
      }
    ApprovePaymentApply =>
      if model.payment_apply_id == "" ||
        model.payment_apply_state != "submitted" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "approve"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在审核付款申请并写入审计…",
          },
        )
      }
    UpdatePaymentApply =>
      if model.payment_apply_id == "" ||
        model.payment_apply_state != "submitted" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "update"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在保存付款申请修改…",
          },
        )
      }
    VoidPaymentApply =>
      if model.payment_apply_id == "" ||
        model.payment_apply_state == "new" ||
        model.payment_apply_state == "paid" ||
        model.payment_apply_state == "voided" {
        (none, model)
      } else {
        (
          issue_payment_apply_command(emit, model, "void"),
          {
            ..model,
            payment_apply_state: "pending",
            payment_apply_note: "正在作废付款申请并写入审计…",
          },
        )
      }
    CheckPaymentEligibility =>
      (
        check_payment_eligibility(emit),
        {
          ..model,
          payment_apply_eligibility_note: "正在校验付款节点条件…",
        },
      )
    PaymentApplyCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"approved\"") {
        "approved"
      } else if body.contains("\"state\":\"rejected\"") {
        "rejected"
      } else if body.contains("\"state\":\"submitted\"") {
        "submitted"
      } else if body.contains("\"state\":\"draft\"") {
        "draft"
      } else if body.contains("\"state\":\"voided\"") {
        "voided"
      } else {
        "error"
      }
      if next_state == "error" {
        (
          none,
          { ..model, payment_apply_state: "error", payment_apply_note: body },
        )
      } else {
        (
          load_payment_applies(emit),
          {
            ..model,
            payment_apply_state: next_state,
            payment_apply_note: "已写入 PostgreSQL · 付款申请状态已更新 · 审计凭证已生成",
          },
        )
      }
    }
    PaymentApplyCommandFailed =>
      (
        none,
        {
          ..model,
          payment_apply_state: "error",
          payment_apply_note: "公司付款申请命令服务不可用或拒绝了请求",
        },
      )
    PaymentEligibilityLoaded(body) =>
      (
        none,
        {
          ..model,
          payment_apply_eligibility_note: if body.contains("\"over_pay\":true") {
            "节点校验：超付，申请已被拦截"
          } else if body.contains("\"early_flag\":true") {
            "节点校验：提前付款，需要补充原因并进入加签审批"
          } else {
            "节点校验：付款条件满足"
          },
        },
      )
    PaymentEligibilityLoadFailed =>
      (
        none,
        {
          ..model,
          payment_apply_eligibility_note: "付款节点校验服务不可用",
        },
      )
    TendersLoaded(body) =>
      (
        none,
        {
          ..model,
          tenders_loaded: true,
          tender_rows: tender_rows_from_body(body),
          tender_note: "已加载 PostgreSQL 合约规划与招采状态",
        },
      )
    TendersLoadFailed =>
      (
        none,
        {
          ..model,
          tenders_loaded: false,
          tender_note: "合约规划读模型不可用 · 使用已审核快照",
        },
      )
    CreateTender =>
      if model.tender_state == "planning" || model.tender_state == "publishing" {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "create"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在创建合约规划并写入 PostgreSQL 投影…",
          },
        )
      }
    PublishTender =>
      if model.tender_id == "" || model.tender_state != "planning" {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "publish"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在发布招采计划…",
          },
        )
      }
    OpenTenderBidding =>
      if model.tender_id == "" || model.tender_state != "publishing" {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "open_bidding"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在开启投标阶段…",
          },
        )
      }
    AwardTender =>
      if model.tender_id == "" || model.tender_state != "bidding" {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "award"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在校验供应商资格并定标…",
          },
        )
      }
    CompleteTender =>
      if model.tender_id == "" || model.tender_state != "awarded" {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "complete"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在完成招标规划并写入审计…",
          },
        )
      }
    CancelTender =>
      if model.tender_id == "" ||
        (
          model.tender_state != "planning" &&
          model.tender_state != "publishing" &&
          model.tender_state != "bidding"
        ) {
        (none, model)
      } else {
        (
          issue_tender_command(emit, model, "cancel"),
          {
            ..model,
            tender_state: "pending",
            tender_note: "正在取消合约规划…",
          },
        )
      }
    TenderCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"planning\"") {
        "planning"
      } else if body.contains("\"state\":\"publishing\"") {
        "publishing"
      } else if body.contains("\"state\":\"bidding\"") {
        "bidding"
      } else if body.contains("\"state\":\"cancelled\"") {
        "cancelled"
      } else if body.contains("\"state\":\"awarded\"") {
        "awarded"
      } else if body.contains("\"state\":\"completed\"") {
        "completed"
      } else {
        "error"
      }
      if next_state == "error" {
        (none, { ..model, tender_state: "error", tender_note: body })
      } else {
        (
          load_tenders(emit),
          {
            ..model,
            tender_state: next_state,
            tender_note: "已写入 PostgreSQL · 合约规划状态已更新 · 审计凭证已生成",
          },
        )
      }
    }
    TenderCommandFailed =>
      (
        none,
        {
          ..model,
          tender_state: "error",
          tender_note: "公司合约规划命令服务不可用或拒绝了请求",
        },
      )
    SuppliersLoaded(body) =>
      (
        none,
        {
          ..model,
          suppliers_loaded: true,
          supplier_rows: supplier_rows_from_body(body),
          supplier_note: "已加载 PostgreSQL 供应商资格与范围",
        },
      )
    SuppliersLoadFailed =>
      (
        none,
        {
          ..model,
          suppliers_loaded: false,
          supplier_note: "供应商读模型不可用 · 使用已审核快照",
        },
      )
    CreateSupplier =>
      if model.supplier_state == "new" {
        (
          issue_supplier_command(emit, model, "create"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在创建供应商并写入 PostgreSQL 投影…",
          },
        )
      } else {
        (none, model)
      }
    UpdateSupplier =>
      if model.supplier_id == "" ||
        model.supplier_state == "new" ||
        model.supplier_state == "voided" {
        (none, model)
      } else {
        (
          issue_supplier_command(emit, model, "update"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在更新供应商主数据…",
          },
        )
      }
    SubmitSupplierReview =>
      if model.supplier_id == "" || model.supplier_state != "draft" {
        (none, model)
      } else {
        (
          issue_supplier_command(emit, model, "submit_review"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在提交供应商资格审核…",
          },
        )
      }
    ReviewSupplier =>
      if model.supplier_id == "" || model.supplier_state != "pending_review" {
        (none, model)
      } else {
        (
          issue_supplier_command(emit, model, "review"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在写入供应商资格评价…",
          },
        )
      }
    BlacklistSupplier =>
      if model.supplier_id == "" ||
        (
          model.supplier_state != "active" &&
          model.supplier_state != "suspended"
        ) {
        (none, model)
      } else {
        (
          issue_supplier_command(emit, model, "blacklist"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在执行供应商黑名单控制…",
          },
        )
      }
    VoidSupplier =>
      if model.supplier_id == "" ||
        model.supplier_state == "new" ||
        model.supplier_state == "voided" {
        (none, model)
      } else {
        (
          issue_supplier_command(emit, model, "void"),
          {
            ..model,
            supplier_state: "pending",
            supplier_note: "正在作废供应商并写入审计…",
          },
        )
      }
    SupplierCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"draft\"") {
        "draft"
      } else if body.contains("\"state\":\"pending_review\"") {
        "pending_review"
      } else if body.contains("\"state\":\"active\"") {
        "active"
      } else if body.contains("\"state\":\"suspended\"") {
        "suspended"
      } else if body.contains("\"state\":\"blacklisted\"") {
        "blacklisted"
      } else if body.contains("\"state\":\"voided\"") {
        "voided"
      } else {
        "error"
      }
      let next_evaluation = if body.contains("\"evaluation\":\"qualified\"") {
        "qualified"
      } else if body.contains("\"evaluation\":\"strategic\"") {
        "strategic"
      } else if body.contains("\"evaluation\":\"unqualified\"") {
        "unqualified"
      } else if body.contains("\"evaluation\":\"reviewed\"") {
        "reviewed"
      } else {
        model.supplier_evaluation
      }
      if next_state == "error" {
        (none, { ..model, supplier_state: "error", supplier_note: body })
      } else {
        (
          load_suppliers(emit),
          {
            ..model,
            supplier_state: next_state,
            supplier_evaluation: next_evaluation,
            supplier_note: "已写入 PostgreSQL · 供应商状态已更新 · 审计凭证已生成",
          },
        )
      }
    }
    SupplierCommandFailed =>
      (
        none,
        {
          ..model,
          supplier_state: "error",
          supplier_note: "公司供应商命令服务不可用或拒绝了请求",
        },
      )
    SalesLoaded(family, body) =>
      (
        none,
        {
          ..model,
          sales_loaded: true,
          sales_family: family,
          sales_rows: sales_rows_from_body(body),
          sales_note: "已加载 PostgreSQL 销售/应收读模型 · 导入记录保持只读",
        },
      )
    SalesLoadFailed(family) =>
      (
        none,
        {
          ..model,
          sales_loaded: false,
          sales_family: family,
          sales_rows: [],
          sales_note: "销售/应收读模型不可用 · 使用已审核快照",
        },
      )
    DeliveryLoaded(body) => {
      let (progress, outputs, tasks, reports) = delivery_overview_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          delivery_loaded: true,
          delivery_progress_rows: progress,
          delivery_output_rows: outputs,
          delivery_task_rows: tasks,
          delivery_report_rows: reports,
          delivery_note: "已加载 PostgreSQL 工程进度、项目计划与任务汇报 · 导入记录保持只读",
        },
      )
    }
    DeliveryLoadFailed =>
      (
        none,
        {
          ..model,
          delivery_loaded: false,
          delivery_progress_rows: [],
          delivery_output_rows: [],
          delivery_task_rows: [],
          delivery_report_rows: [],
          delivery_note: "工程进度/项目计划读模型不可用 · 使用已审核快照",
        },
      )
    ReportsLoaded(body) => {
      let (costs, contracts, stages, supplier_count, approval_count) = reports_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          reports_loaded: true,
          report_cost_rows: costs,
          report_contract_rows: contracts,
          report_stage_rows: stages,
          report_supplier_count: supplier_count,
          report_approval_count: approval_count,
          reports_note: "已加载 PostgreSQL 核心报表 · 源数据覆盖与缺口保持可见",
        },
      )
    }
    ReportsLoadFailed =>
      (
        none,
        {
          ..model,
          reports_loaded: false,
          report_cost_rows: [],
          report_contract_rows: [],
          report_stage_rows: [],
          reports_note: "核心报表读模型不可用 · 使用已审核快照",
        },
      )
    DashboardOverviewLoaded(body) => {
      let (loaded, values) = dashboard_overview_from_body(body)
      if loaded {
        (
          load_dashboard_funnel(emit),
          {
            ..model,
            dashboard_loaded: true,
            dashboard_company_count: values[0],
            dashboard_project_count: values[1],
            dashboard_in_progress_count: values[2],
            dashboard_contract_count: values[3],
            dashboard_total_contract_amount: values[4],
            dashboard_paid_amount: values[5],
            dashboard_paid_ratio: values[6],
            dashboard_target_cost: values[7],
            dashboard_dynamic_cost: values[8],
            dashboard_deviation_pct: values[9],
            dashboard_overdue_tasks: values[10],
            dashboard_missing_table_count: values[11],
            dashboard_note: "已加载 PostgreSQL 驾驶舱读模型 · 缺失源表保持可见",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            dashboard_loaded: false,
            dashboard_note: "驾驶舱读模型响应无效 · 使用已审核快照",
          },
        )
      }
    }
    DashboardFunnelLoaded(body) =>
      (
        load_dashboard_anomalies(emit),
        {
          ..model,
          dashboard_funnel_rows: dashboard_funnel_rows_from_body(body),
        },
      )
    DashboardAnomaliesLoaded(body) =>
      (
        none,
        {
          ..model,
          dashboard_anomaly_rows: dashboard_anomaly_rows_from_body(body),
        },
      )
    DashboardLoadFailed =>
      (
        none,
        {
          ..model,
          dashboard_loaded: false,
          dashboard_funnel_rows: [],
          dashboard_anomaly_rows: [],
          dashboard_note: "驾驶舱读模型不可用 · 使用已审核快照",
        },
      )
    AdminQualityLoaded(body) =>
      (
        load_admin_dict_groups(emit),
        {
          ..model,
          admin_quality_loaded: true,
          admin_quality_rows: admin_quality_rows_from_body(body),
          admin_quality_note: "已加载 PostgreSQL 数据质量规则 · 不可用源表保持可见",
        },
      )
    AdminQualityLoadFailed =>
      (
        none,
        {
          ..model,
          admin_quality_loaded: false,
          admin_quality_rows: [],
          admin_quality_note: "数据质量读模型不可用 · 使用已审核快照",
        },
      )
    AdminDictGroupsLoaded(body) =>
      (
        load_admin_dict_options(emit),
        {
          ..model,
          admin_dict_group_rows: admin_dict_group_rows_from_body(body),
          admin_dict_note: "已加载 PostgreSQL 数据字典分组 · 正在读取选项",
        },
      )
    AdminDictOptionsLoaded(body) =>
      (
        none,
        {
          ..model,
          admin_dict_loaded: true,
          admin_dict_option_rows: admin_dict_option_rows_from_body(body),
          admin_dict_note: "已加载 PostgreSQL 数据字典选项 · 写入仍受管理员授权约束",
        },
      )
    AdminDictLoadFailed =>
      (
        none,
        {
          ..model,
          admin_dict_loaded: false,
          admin_dict_group_rows: [],
          admin_dict_option_rows: [],
          admin_dict_note: "数据字典读模型不可用 · 使用设计快照",
        },
      )
    InvestmentVersionsLoaded(body) => {
      let (version_id, version_name) = investment_version_from_body(body)
      if version_id == "" {
        (
          none,
          {
            ..model,
            investment_loaded: false,
            investment_note: "投资版本源数据为空 · 使用设计快照",
          },
        )
      } else {
        (
          load_investment_indices(emit, version_id),
          {
            ..model,
            investment_version_id: version_id,
            investment_version_name: version_name,
            investment_note: "已加载 PostgreSQL 投资版本 · 正在读取指标",
          },
        )
      }
    }
    InvestmentIndicesLoaded(body) => {
      let (rows, dimension_count) = investment_index_rows_from_body(body)
      (
        load_investment_profit(emit),
        {
          ..model,
          investment_index_rows: rows,
          investment_dimension_count: dimension_count,
          investment_note: "已加载 PostgreSQL 投资指标 · 正在读取利润汇总",
        },
      )
    }
    InvestmentProfitLoaded(body) => {
      let values = investment_profit_from_body(body)
      if values.length() == 7 {
        (
          none,
          {
            ..model,
            investment_loaded: true,
            investment_version_name: values[0],
            investment_total: values[1],
            investment_revenue: values[2],
            investment_cost: values[3],
            investment_net_profit: values[4],
            investment_net_profit_margin: values[5],
            investment_irr: values[6],
            investment_note: "已加载 PostgreSQL 投资测算 · 版本/指标保持只读",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            investment_loaded: false,
            investment_note: "投资利润汇总响应无效 · 使用设计快照",
          },
        )
      }
    }
    InvestmentLoadFailed =>
      (
        none,
        {
          ..model,
          investment_loaded: false,
          investment_version_id: "",
          investment_version_name: "",
          investment_index_rows: [],
          investment_note: "投资测算读模型不可用 · 使用设计快照",
        },
      )
    AuditLoaded(body) => {
      let (rows, total) = audit_rows_from_body(body)
      (
        load_audit_actions(emit),
        {
          ..model,
          audit_rows: rows,
          audit_total: total,
          audit_note: "已加载 PostgreSQL 审计日志 · 正在读取动作汇总",
        },
      )
    }
    AuditActionsLoaded(body) =>
      (
        none,
        {
          ..model,
          audit_loaded: true,
          audit_action_rows: audit_action_rows_from_body(body),
          audit_note: "已加载 PostgreSQL 审计日志 · append-only 只读证据",
        },
      )
    AuditLoadFailed =>
      (
        none,
        {
          ..model,
          audit_loaded: false,
          audit_rows: [],
          audit_action_rows: [],
          audit_total: "0",
          audit_note: "审计读模型不可用 · 使用设计快照",
        },
      )
    DynamicCostLoaded(body) => {
      let (rows, summary) = dynamic_cost_from_body(body)
      if summary.length() == 6 {
        (
          none,
          {
            ..model,
            dynamic_cost_loaded: true,
            dynamic_cost_rows: rows,
            dynamic_cost_project_name: summary[0],
            dynamic_cost_target: summary[1],
            dynamic_cost_total: summary[2],
            dynamic_cost_deviation: summary[3],
            dynamic_cost_spare: summary[4],
            dynamic_cost_end_count: summary[5],
            dynamic_cost_note: "已加载 PostgreSQL 动态成本 · 五列公式保持源口径",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            dynamic_cost_loaded: false,
            dynamic_cost_rows: [],
            dynamic_cost_note: "动态成本响应无效 · 使用设计快照",
          },
        )
      }
    }
    DynamicCostLoadFailed =>
      (
        none,
        {
          ..model,
          dynamic_cost_loaded: false,
          dynamic_cost_rows: [],
          dynamic_cost_note: "动态成本读模型不可用 · 使用设计快照",
        },
      )
    ProfileLoaded(body) => {
      let values = profile_from_body(body)
      if values.length() == 10 {
        (
          none,
          {
            ..model,
            profile_loaded: true,
            profile_user_id: values[0],
            profile_user_code: values[1],
            profile_user_name: values[2],
            profile_emp_name: values[3],
            profile_bu_name: values[4],
            profile_dept_name: values[5],
            profile_super_user: values[6],
            profile_enabled: values[7],
            profile_last_login: values[8],
            profile_source_kind: values[9],
            profile_note: "已加载 PostgreSQL 个人资料 · 敏感认证字段未导入",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            profile_loaded: false,
            profile_note: "个人资料响应无效 · 使用设计快照",
          },
        )
      }
    }
    ProfileLoadFailed =>
      (
        none,
        {
          ..model,
          profile_loaded: false,
          profile_note: "个人资料读模型不可用 · 使用设计快照",
        },
      )
    UsersLoaded(body) =>
      (
        none,
        {
          ..model,
          users_loaded: true,
          user_roster_rows: user_roster_rows_from_body(body),
          users_note: "已加载 PostgreSQL 身份 roster · 角色源表缺失保持可见",
        },
      )
    UsersLoadFailed =>
      (
        none,
        {
          ..model,
          users_loaded: false,
          user_roster_rows: [],
          users_note: "身份读模型不可用 · 使用已审核快照",
        },
      )
    HealthTablesLoaded(body) => {
      let (source_table_count, missing_table_count) = health_table_counts_from_body(
        body,
      )
      (
        load_health_bpm(emit),
        {
          ..model,
          health_table_rows: health_table_rows_from_body(body),
          health_source_table_count: source_table_count,
          health_missing_table_count: missing_table_count,
          health_note: "已加载 PostgreSQL 源覆盖 · 正在读取 BPM 池状态",
        },
      )
    }
    HealthBpmLoaded(body) => {
      let (instance_count, action_count) = health_bpm_counts_from_body(body)
      (
        none,
        {
          ..model,
          health_loaded: true,
          health_bpm_instance_count: instance_count,
          health_bpm_action_count: action_count,
          health_note: "已加载 PostgreSQL 健康覆盖 · BPM 实例/动作保持源数据状态",
        },
      )
    }
    HealthLoadFailed =>
      (
        none,
        {
          ..model,
          health_loaded: false,
          health_table_rows: [],
          health_note: "系统健康读模型不可用 · 使用设计快照",
        },
      )
    LoansLoaded(body) =>
      (
        none,
        {
          ..model,
          loans_loaded: true,
          loan_rows: loan_rows_from_body(body),
          loan_note: "已加载 PostgreSQL 员工借款与冲账读模型 · 导入记录保持只读",
        },
      )
    LoansLoadFailed =>
      (
        none,
        {
          ..model,
          loans_loaded: false,
          loan_rows: [],
          loan_note: "员工借款读模型不可用 · 使用已审核快照",
        },
      )
    WorkflowLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_loaded: true,
          workflow_process_rows: workflow_rows_from_body(body),
          workflow_note: "已加载 PostgreSQL 工作流定义 · 实例与动作仍按源数据保持空白",
        },
      )
    WorkflowLoadFailed =>
      (
        none,
        {
          ..model,
          workflow_loaded: false,
          workflow_process_rows: [],
          workflow_note: "工作流定义读模型不可用 · 使用已审核快照",
        },
      )
    ProjectsLoaded(body) =>
      (
        none,
        {
          ..model,
          projects_loaded: true,
          project_rows: project_rows_from_body(body),
          project_note: "已加载 PostgreSQL 项目主数据与生命周期证据 · 导入记录保持只读",
        },
      )
    ProjectsLoadFailed =>
      (
        none,
        {
          ..model,
          projects_loaded: false,
          project_rows: [],
          project_note: "项目主数据读模型不可用 · 使用已审核快照",
        },
      )
    ProjectLoaded(body) =>
      (
        none,
        {
          ..model,
          projects_loaded: true,
          project_detail: project_detail_from_body(body),
          project_note: "已加载 PostgreSQL 项目详情与生命周期证据 · 导入记录保持只读",
        },
      )
    ProjectLoadFailed =>
      (
        none,
        {
          ..model,
          projects_loaded: false,
          project_detail: None,
          project_note: "项目详情读模型不可用 · 使用已审核快照",
        },
      )
    CreateLoan =>
      if model.loan_state == "pending" || model.loan_state == "Draft" {
        (none, model)
      } else {
        (
          issue_loan_command(emit, model, "create"),
          {
            ..model,
            loan_state: "pending",
            loan_command_note: "正在创建借款草稿并校验员工范围 authority…",
          },
        )
      }
    SubmitLoan =>
      if model.loan_id == "" || model.loan_state != "Draft" {
        (none, model)
      } else {
        (
          issue_loan_command(emit, model, "submit"),
          {
            ..model,
            loan_state: "pending",
            loan_command_note: "正在提交借款审批…",
          },
        )
      }
    UpdateLoan =>
      if model.loan_id == "" || model.loan_state != "Draft" {
        (none, model)
      } else {
        (
          issue_loan_command(emit, model, "update"),
          {
            ..model,
            loan_state: "pending",
            loan_command_note: "正在保存借款草稿修改…",
          },
        )
      }
    VoidLoan =>
      if model.loan_id == "" ||
        (model.loan_state != "Draft" && model.loan_state != "Rejected") {
        (none, model)
      } else {
        (
          issue_loan_command(emit, model, "void"),
          {
            ..model,
            loan_state: "pending",
            loan_command_note: "正在作废借款并写入审计…",
          },
        )
      }
    LoanCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"Approved\"") {
        "Approved"
      } else if body.contains("\"state\":\"Approving\"") {
        "Approving"
      } else if body.contains("\"state\":\"Voided\"") {
        "Voided"
      } else if body.contains("\"state\":\"Draft\"") {
        "Draft"
      } else {
        "error"
      }
      if next_state == "error" {
        (none, { ..model, loan_state: "error", loan_command_note: body })
      } else {
        let next_page = if body.contains("\"command_type\":\"create\"") {
          "/loans/LOAN-RABBITA-LOCAL"
        } else {
          model.page
        }
        (
          load_loans(emit),
          {
            ..model,
            page: next_page,
            loan_state: next_state,
            loan_command_note: "已写入 PostgreSQL · 借款命令完成 · 审计凭证已生成",
          },
        )
      }
    }
    LoanCommandFailed =>
      (
        none,
        {
          ..model,
          loan_state: "error",
          loan_command_note: "员工借款命令服务不可用或拒绝了请求",
        },
      )
    CreateDeliveryProgress =>
      if model.delivery_progress_state == "new" {
        (
          issue_delivery_command(emit, model, "create_progress"),
          {
            ..model,
            delivery_progress_state: "pending",
            delivery_command_note: "正在创建进度记录并校验证据…",
          },
        )
      } else {
        (none, model)
      }
    ReportDeliveryProgress =>
      if model.delivery_progress_state == "draft" {
        (
          issue_delivery_command(emit, model, "report_progress"),
          {
            ..model,
            delivery_progress_state: "pending",
            delivery_command_note: "正在提交实际进度与现场证据…",
          },
        )
      } else {
        (none, model)
      }
    AcceptDeliveryProgress =>
      if model.delivery_progress_state == "submitted" {
        (
          issue_delivery_command(emit, model, "accept_progress"),
          {
            ..model,
            delivery_progress_state: "pending",
            delivery_command_note: "正在校验验收证据并写入审计…",
          },
        )
      } else {
        (none, model)
      }
    RejectDeliveryProgress =>
      if model.delivery_progress_state == "submitted" {
        (
          issue_delivery_command(emit, model, "reject_progress"),
          {
            ..model,
            delivery_progress_state: "pending",
            delivery_command_note: "正在退回进度记录并写入审计…",
          },
        )
      } else {
        (none, model)
      }
    CreateDeliveryOutput =>
      if model.delivery_output_state == "new" {
        (
          issue_delivery_command(emit, model, "create_output"),
          {
            ..model,
            delivery_output_state: "pending",
            delivery_command_note: "正在登记产值并校验证据…",
          },
        )
      } else {
        (none, model)
      }
    ConfirmDeliveryOutput =>
      if model.delivery_output_state == "reported" {
        (
          issue_delivery_command(emit, model, "confirm_output"),
          {
            ..model,
            delivery_output_state: "pending",
            delivery_command_note: "正在确认产值并写入审计…",
          },
        )
      } else {
        (none, model)
      }
    ReportTaskProgress =>
      (
        issue_delivery_command(emit, model, "report_task"),
        {
          ..model,
          delivery_command_note: "正在提交任务汇报（不直接修改导入任务状态）…",
        },
      )
    DeliveryCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"accepted\"") {
        "accepted"
      } else if body.contains("\"state\":\"submitted\"") {
        "submitted"
      } else if body.contains("\"state\":\"rejected\"") {
        "rejected"
      } else if body.contains("\"state\":\"draft\"") {
        "draft"
      } else if body.contains("\"state\":\"reported\"") {
        "reported"
      } else if body.contains("\"state\":\"confirmed\"") {
        "confirmed"
      } else {
        "observed"
      }
      (
        load_delivery(emit),
        {
          ..model,
          delivery_progress_state: if body.contains("delivery_progress") {
            next_state
          } else {
            model.delivery_progress_state
          },
          delivery_output_state: if body.contains("delivery_output") {
            next_state
          } else {
            model.delivery_output_state
          },
          delivery_command_note: "已写入 PostgreSQL · 进度/产值命令完成 · 审计凭证已生成",
        },
      )
    }
    DeliveryCommandFailed =>
      (
        none,
        {
          ..model,
          delivery_progress_state: "error",
          delivery_output_state: "error",
          delivery_command_note: "公司工程进度命令服务不可用或拒绝了请求",
        },
      )
    CreateExpense =>
      if model.expense_state == "提交中" ||
        model.expense_state == "已提交" {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses")
          .with_text(
            "{\"idempotency_key\":\"rabbita-expense-create-v1\",\"expense_id\":\"EXP-RABBITA-LOCAL\",\"employee_id\":\"rabbita-user\",\"summary\":\"成都项目现场出差\",\"amount_minor\":8560,\"currency\":\"CNY\",\"project_id\":\"CD-HJL\",\"cost_subject\":\"travel\"}",
          )
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseCommandFinished(body))
              Err(_) => emit(ExpenseCommandFailed)
            }
          }),
          {
            ..model,
            expense_state: "提交中",
            expense_note: "正在创建并写入 PostgreSQL 投影…",
          },
        )
      }
    SubmitExpense =>
      if model.expense_id == "" || model.expense_state != "草稿" {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses/\{model.expense_id}/submit")
          .with_text("{\"idempotency_key\":\"rabbita-expense-submit-v1\"}")
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseCommandFinished(body))
              Err(_) => emit(ExpenseCommandFailed)
            }
          }),
          {
            ..model,
            expense_state: "提交中",
            expense_note: "正在提交审批…",
          },
        )
      }
    RejectExpense =>
      if model.expense_id == "" || model.expense_state != "已提交" {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses/\{model.expense_id}/reject")
          .with_text(
            "{\"idempotency_key\":\"rabbita-expense-reject-v1\",\"reason\":\"请补充发票与行程凭证\"}",
          )
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseCommandFinished(body))
              Err(_) => emit(ExpenseCommandFailed)
            }
          }),
          {
            ..model,
            expense_state: "审批处理中",
            expense_note: "正在退回并写入 PostgreSQL 投影…",
          },
        )
      }
    ResubmitExpense =>
      if model.expense_id == "" || model.expense_state != "已驳回" {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses/\{model.expense_id}/resubmit")
          .with_text("{\"idempotency_key\":\"rabbita-expense-resubmit-v1\"}")
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseCommandFinished(body))
              Err(_) => emit(ExpenseCommandFailed)
            }
          }),
          {
            ..model,
            expense_state: "审批处理中",
            expense_note: "正在重新提交审批…",
          },
        )
      }
    ApproveExpense =>
      if model.expense_id == "" || model.expense_state != "已提交" {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses/\{model.expense_id}/approve")
          .with_text("{\"idempotency_key\":\"rabbita-expense-approve-v1\"}")
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseCommandFinished(body))
              Err(_) => emit(ExpenseCommandFailed)
            }
          }),
          {
            ..model,
            expense_state: "审批处理中",
            expense_note: "正在批准并写入 PostgreSQL 投影…",
          },
        )
      }
    ExpenseCommandFinished(body) =>
      if body.contains("\"state\":\"approved\"") {
        (
          none,
          {
            ..model,
            expense_state: "已批准",
            expense_note: "已写入 PostgreSQL · 审批通过 · 审计凭证已生成",
          },
        )
      } else if body.contains("\"state\":\"rejected\"") {
        (
          none,
          {
            ..model,
            expense_state: "已驳回",
            expense_note: "已退回 · 请补充凭证后重新提交",
          },
        )
      } else if body.contains("\"state\":\"submitted\"") {
        (
          none,
          {
            ..model,
            expense_state: "已提交",
            expense_note: "已写入 PostgreSQL · 等待审批 · 审计凭证已生成",
          },
        )
      } else if body.contains("\"state\":\"draft\"") {
        (
          none,
          {
            ..model,
            expense_state: "草稿",
            expense_note: "已写入 PostgreSQL 草稿投影 · 可提交审批",
          },
        )
      } else if body.contains("\"error\"") {
        (none, { ..model, expense_state: "命令失败", expense_note: body })
      } else {
        (none, { ..model, expense_state: "命令完成", expense_note: body })
      }
    ExpenseCommandFailed =>
      (
        none,
        {
          ..model,
          expense_state: "命令失败",
          expense_note: "公司命令服务不可用或拒绝了请求",
        },
      )
  }
}

///|
fn icon(label : String) -> @html.Html {
  span(class="menu-icon", attrs=@html.Attrs::build().aria_hidden("true"), label)
}

///|
fn menu_leaf(
  emit : @rabbita.Emit[Msg],
  path : String,
  label : String,
  glyph : String,
  active : String,
  collapsed : Bool,
) -> @html.Html {
  let selected = path == active
  let class_name = if selected {
    "erp-menu-item is-active"
  } else {
    "erp-menu-item"
  }
  let attrs = @html.Attrs::build().aria_current(
    if selected {
      "page"
    } else {
      "false"
    },
  )
  let children : Array[@html.Html] = [icon(glyph)]
  if !collapsed {
    children.push(span(class="menu-text", label))
  }
  button(class=class_name, attrs~, on_click=emit(Navigate(path))) <| children
}

///|
fn menu_group(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  model : Model,
) -> @html.Html {
  let expanded = model.open_group == Some(group)
  let class_name = if expanded {
    "erp-menu-group is-open"
  } else {
    "erp-menu-group"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  if !model.collapsed {
    title_children.push(span(class="menu-text", label))
    title_children.push(
      span(class="menu-caret", if expanded { "⌄" } else { "›" }),
    )
  }
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded && !model.collapsed {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn nested_menu_group(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  model : Model,
) -> @html.Html {
  let expanded = model.open_group == Some(group)
  let class_name = if expanded {
    "erp-menu-group erp-nested is-open"
  } else {
    "erp-menu-group erp-nested"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  title_children.push(span(class="menu-text", label))
  title_children.push(
    span(class="menu-caret", if expanded { "⌄" } else { "›" }),
  )
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn menu_group_with_nested(
  emit : @rabbita.Emit[Msg],
  group : String,
  label : String,
  glyph : String,
  items : Array[(String, String)],
  nested : Array[(String, String, String, Array[(String, String)])],
  model : Model,
) -> @html.Html {
  let mut nested_open = false
  match model.open_group {
    Some(current) =>
      for entry in nested {
        if entry.0 == current {
          nested_open = true
        }
      }
    None => ()
  }
  let expanded = model.open_group == Some(group) || nested_open
  let class_name = if expanded {
    "erp-menu-group is-open"
  } else {
    "erp-menu-group"
  }
  let children : Array[@html.Html] = []
  let attrs = @html.Attrs::build().aria_expanded(
    if expanded {
      "true"
    } else {
      "false"
    },
  )
  let title_children : Array[@html.Html] = [icon(glyph)]
  if !model.collapsed {
    title_children.push(span(class="menu-text", label))
    title_children.push(
      span(class="menu-caret", if expanded { "⌄" } else { "›" }),
    )
  }
  children.push(
    button(
      class="erp-menu-group-title",
      attrs~,
      on_click=emit(ToggleGroup(group)),
    ) <| title_children,
  )
  if expanded && !model.collapsed {
    for item in items {
      children.push(
        menu_leaf(emit, item.0, item.1, "·", model.page, model.collapsed),
      )
    }
    for entry in nested {
      children.push(
        nested_menu_group(emit, entry.0, entry.1, entry.2, entry.3, model),
      )
    }
  }
  div(class=class_name) <| children
}

///|
fn sidebar(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let class_name = if model.collapsed {
    if model.mobile_nav {
      "erp-sidebar is-collapsed is-mobile-open"
    } else {
      "erp-sidebar is-collapsed"
    }
  } else if model.mobile_nav {
    "erp-sidebar is-mobile-open"
  } else {
    "erp-sidebar"
  }
  aside(class=class_name) <| [
    div(class="erp-brand") <| [
      span(class="erp-logo", "ERP"),
      if model.collapsed {
        @html.nothing
      } else {
        strong(class="erp-brand-text", "项目全周期管理")
      },
    ],
    nav(
      class="erp-navigation",
      attrs=@html.Attrs::build().aria_label("ERP主导航"),
    ) <| [
      menu_leaf(
        emit,
        "/dashboard",
        "AI 驾驶舱",
        "▣",
        model.page,
        model.collapsed,
      ),
      menu_leaf(
        emit,
        "/ai-hub",
        "AI 工作台",
        "✦",
        model.page,
        model.collapsed,
      ),
      menu_leaf(
        emit,
        "/ai-stats",
        "AI 工作大盘",
        "⌁",
        model.page,
        model.collapsed,
      ),
      menu_group(
        emit,
        "project",
        "项目管理",
        "▥",
        [
          ("/projects", "项目主数据"),
          ("/project-plan", "项目计划"),
          ("/project/progress", "工程进度"),
          ("/tasks", "我的待办"),
        ],
        model,
      ),
      menu_group(
        emit,
        "sales",
        "销售管理",
        "¥",
        [
          ("/sales/customers", "客户档案"),
          ("/sales/subscriptions", "认筹登记"),
          ("/sales/contracts", "签约管理"),
          ("/sales/mortgages", "按揭办理"),
          ("/sales/revenues", "销售回款 (R6)"),
          ("/marketing", "营销管理"),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "cost",
        "成本管理",
        "▤",
        [
          ("/cost-dashboard-v3", "成本驾驶舱"),
          ("/investment", "投资收益"),
          ("/contracts", "合同台帐"),
          ("/payment-applies", "付款申请"),
          ("/dynamic-cost", "动态成本"),
          ("/tender", "合约规划"),
        ],
        [
          (
            "cost-srm",
            "供应商管理",
            "↔",
            [
              ("/srm/providers", "供应商库"),
              ("/srm/risk-board", "风险面板"),
            ],
          ),
          (
            "cost-cbs",
            "科目主数据",
            "▧",
            [
              ("/cbs/dict", "CBS 字典"),
              ("/cbs/versions", "目标版本"),
              ("/cbs/r0-queue", "R0 待归类"),
              ("/cbs/approval-config", "审批配置"),
            ],
          ),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "finance",
        "财务管理",
        "▣",
        [("/fund/plan", "资金计划"), ("/invoice", "发票管理")],
        [
          (
            "finance-budget",
            "费用预算",
            "¥",
            [("/expenses", "我的报销"), ("/loans", "我的借款")],
          ),
        ],
        model,
      ),
      menu_group(
        emit,
        "analysis",
        "分析中心",
        "▦",
        [
          ("/reports", "报表中心"),
          ("/report-builder", "自定义报表"),
          ("/warning", "异常预警"),
        ],
        model,
      ),
      menu_group_with_nested(
        emit,
        "system",
        "系统管理",
        "⚙",
        [
          ("/inbox", "站内信"),
          ("/attachments", "附件中心"),
          ("/notify-config", "通知配置"),
        ],
        [
          (
            "system-advanced",
            "高级配置",
            "⚙",
            [
              ("/audit-log", "审计日志"),
              ("/error-log", "错误日志"),
              ("/system-health", "系统健康"),
              ("/users", "用户/角色"),
              ("/admin", "数据后台"),
              ("/ocr-config", "OCR 配置"),
              ("/webhook-config", "Webhook 三平台"),
            ],
          ),
        ],
        model,
      ),
    ],
  ]
}

///|
fn login_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  div(class="erp-login") <| [
    div(class="login-blob login-blob-one", @html.nothing),
    div(class="login-blob login-blob-two", @html.nothing),
    div(class="login-blob login-blob-three", @html.nothing),
    div(class="login-brand-side") <| [
      span(class="login-logo-big", "ERP"),
      h1("和泓置地 · ERP"),
      p(class="login-subtitle", "智能项目全周期管理平台"),
      ul(class="login-features") <| [
        li("AI 起单 — 拖文件自动识别 8 类业务"),
        li("AI 查询 — 大白话问出 SQL 报表"),
        li("现金流预测 — 实际 vs 计划 + 流入流出"),
        li("异常预警 — 12 内置规则 + 自定义 DSL"),
        li("BPM 工作流 — 报销/借款/付款全栈审批"),
      ],
      span(class="login-time", "2026.07.13 周一 09:40:00"),
    ],
    div(class="login-card") <| [
      div(class="login-card-heading") <| [
        h2("登录"),
        span("v1.4.0 项目全周期 + AI 工作台"),
      ],
      form(attrs=@html.Attrs::build().on_submit(_ => emit(Login))) <| [
        label(class="login-label", "账号"),
        input(
          input_type=@html.InputType::Text,
          value=model.user_code,
          placeholder="用户编码",
          autofocus=true,
          class="login-input",
          on_input=emit.map(value => InputUser(value)),
        ),
        label(class="login-label", "密码"),
        input(
          input_type=@html.InputType::Password,
          value=model.password,
          placeholder="密码",
          class="login-input",
          on_input=emit.map(value => InputPassword(value)),
        ),
        button(
          class="login-submit",
          type_="button",
          on_click=emit(Login),
          "登录",
        ),
      ],
      button(
        class="demo-toggle",
        on_click=emit(ToggleDemo),
        if model.show_demo {
          "收起测试账号"
        } else {
          "展开测试账号"
        },
      ),
      if model.show_demo {
        div(class="demo-list") <| [
          demo_row(emit, "admin", "admin123", "超级管理员"),
          demo_row(emit, "chengyuzhe", "123456", "报销发起人"),
          demo_row(emit, "tianguanglei", "123456", "费用使用人"),
          demo_row(emit, "limingjin", "123456", "部门负责人"),
          demo_row(emit, "liusong", "123456", "综管负责人"),
        ]
      } else {
        @html.nothing
      },
    ],
  ]
}

///|
fn demo_row(
  emit : @rabbita.Emit[Msg],
  user_code : String,
  password : String,
  role : String,
) -> @html.Html {
  button(class="demo-row", on_click=emit(FillDemo(user_code, password))) <| [
    strong(user_code),
    span("/ \{password}"),
    span(class="demo-role", role),
  ]
}

///|
fn metric(
  label : String,
  value : String,
  detail : String,
  class_name : String,
) -> @html.Html {
  section(class="erp-metric \{class_name}") <| [
    span(class="erp-metric-label", label),
    strong(class="erp-metric-value", value),
    span(class="erp-metric-detail", detail),
  ]
}

///|
fn phase_row(label : String, value : String, width : String) -> @html.Html {
  div(class="phase-row") <| [
    span(class="phase-label", label),
    span(class="phase-bar", style=["width: \{width}"]) <| [
      span(class="phase-value", value),
    ],
  ]
}

///|
fn risk_row(
  project : String,
  company : String,
  risk : String,
  description : String,
) -> @html.Html {
  tr <| [
    td(project),
    td(company),
    td <| [
      span(class="risk-tag", risk),
    ],
    td(description),
  ]
}

///|
fn dashboard_phase_rows(model : Model) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  if model.dashboard_loaded && model.dashboard_funnel_rows.length() > 0 {
    for row in model.dashboard_funnel_rows {
      rows.push(phase_row(row.stage_name, row.count, row.width_pct))
    }
  } else {
    rows.push(phase_row("立项", "15", "100%"))
    rows.push(phase_row("获取", "15", "100%"))
    rows.push(phase_row("规划设计", "14", "93%"))
    rows.push(phase_row("开发建设", "9", "60%"))
    rows.push(phase_row("销售去化", "3", "20%"))
    rows.push(phase_row("竣工交付", "1", "7%"))
    rows.push(phase_row("结算清盘", "0", "7%"))
  }
  rows
}

///|
fn dashboard_risk_rows(model : Model) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  if model.dashboard_loaded && model.dashboard_anomaly_rows.length() > 0 {
    for row in model.dashboard_anomaly_rows {
      rows.push(
        risk_row(
          row.project_name,
          row.company,
          row.risk_score,
          row.reason + " · " + row.source_kind,
        ),
      )
    }
  } else {
    rows.push(
      risk_row("成都和锦里", "成都公司", "20", "1 个任务延期"),
    )
    rows.push(
      risk_row("重庆南山居", "重庆公司", "20", "1 个任务延期"),
    )
    rows.push(
      risk_row("沈阳和山苑", "沈阳公司", "14", "成本超目标 1.40%"),
    )
    rows.push(
      risk_row(
        "天津海教园一期", "天津公司", "13", "成本超目标 1.25%",
      ),
    )
    rows.push(
      risk_row(
        "天津梅江湾三期", "天津公司", "11", "成本超目标 1.14%",
      ),
    )
  }
  rows
}

///|
fn dashboard_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let company_projects = if model.dashboard_loaded {
    model.dashboard_company_count + " / " + model.dashboard_project_count
  } else {
    "5 / 15"
  }
  let in_progress = if model.dashboard_loaded {
    "在建 " + model.dashboard_in_progress_count + " 个"
  } else {
    "在建 15 个"
  }
  let contract_total = if model.dashboard_loaded {
    "¥" + model.dashboard_total_contract_amount
  } else {
    "¥1,256,837,036"
  }
  let contract_detail = if model.dashboard_loaded {
    model.dashboard_contract_count + " 笔合同"
  } else {
    "62 笔合同"
  }
  let paid_ratio = if model.dashboard_loaded {
    model.dashboard_paid_ratio + "%"
  } else {
    "10.98%"
  }
  let paid_detail = if model.dashboard_loaded {
    "已付 ¥" + model.dashboard_paid_amount
  } else {
    "已付 ¥137,953,340"
  }
  let deviation = if model.dashboard_loaded {
    model.dashboard_deviation_pct + "%"
  } else {
    "+6.20%"
  }
  let dynamic_cost = if model.dashboard_loaded {
    "目标 ¥" +
    model.dashboard_target_cost +
    " · 动态 ¥" +
    model.dashboard_dynamic_cost
  } else {
    "动态 ¥645,285,566"
  }
  let overdue_note = if model.dashboard_loaded {
    "⚠ " + model.dashboard_overdue_tasks + " 个任务延期"
  } else {
    "⚠ 2 个任务延期"
  }
  div(class="erp-dashboard") <| [
    div(class="erp-dashboard-source") <| [
      div <| [
        span(class="erp-page-eyebrow", "READ MODEL"),
        strong(model.api_status),
        span(class="erp-source-note", model.api_note),
      ],
      button(class="erp-ghost-btn", on_click=emit(RefreshApi), "刷新数据"),
    ],
    div(class="erp-kpi-grid") <| [
      metric(
        "在管公司 / 项目", company_projects, in_progress, "metric-blue",
      ),
      metric("累计合同额", contract_total, contract_detail, "metric-blue"),
      metric("付款执行率", paid_ratio, paid_detail, "metric-blue"),
      metric("成本偏差率", deviation, dynamic_cost, "metric-green"),
    ],
    div(class="erp-alert-pill", overdue_note),
    div(class="erp-dashboard-grid") <| [
      section(class="erp-panel") <| [
        div(class="erp-panel-heading") <| [
          h2("项目阶段漏斗"),
          span(class="erp-info-tag", "RFC §13.1 — 全周期 7 阶段"),
        ],
        div(class="phase-list") <| [..dashboard_phase_rows(model)],
      ],
      section(class="erp-panel risk-panel") <| [
        div(class="erp-panel-heading") <| [
          h2("TOP 风险项目"),
          span(class="erp-danger-tag", "AI 异常洞察(规则版)"),
        ],
        table <| [
          thead <| [
            tr <| [
              th("项目"),
              th("公司"),
              th("风险"),
              th("说明"),
            ],
          ],
          tbody <| dashboard_risk_rows(model),
        ],
      ],
    ],
    p(
      class="erp-dashboard-note",
      model.dashboard_note +
      " · TOP 异常项目按规则评分排序(成本偏差权重 10、任务延期权重 20) · 缺失源表 " +
      model.dashboard_missing_table_count,
    ),
  ]
}

///|
fn table_header(headers : Array[String]) -> @html.Html {
  let cells : Array[@html.Html] = []
  for header in headers {
    cells.push(th(header))
  }
  tr <| cells
}

///|
fn table_row(cells : Array[String]) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for cell in cells {
    rendered.push(td(cell))
  }
  tr <| rendered
}

///|
fn data_table(
  headers : Array[String],
  rows : Array[Array[String]],
) -> @html.Html {
  let rendered_rows : Array[@html.Html] = []
  for row in rows {
    rendered_rows.push(table_row(row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header(headers),
    ],
    tbody <| rendered_rows,
  ]
}

///|
fn filter_bar(placeholder : String) -> @html.Html {
  div(class="erp-filter-bar") <| [
    input(
      input_type=@html.InputType::Text,
      placeholder~,
      class="erp-filter-input",
    ),
    button(class="erp-secondary-btn", "筛选"),
    button(class="erp-ghost-btn", "重置"),
  ]
}

///|
fn nav_button(
  emit : @rabbita.Emit[Msg],
  path : String,
  class_name : String,
  label : String,
) -> @html.Html {
  button(class=class_name, on_click=emit(Navigate(path)), label)
}

///|
fn page_shell(
  title : String,
  eyebrow : String,
  description : String,
  actions : Array[@html.Html],
  body : @html.Html,
) -> @html.Html {
  section(class="erp-page-shell") <| [
    div(class="erp-page-heading") <| [
      div <| [
        span(class="erp-page-eyebrow", eyebrow),
        h1(title),
        p(description),
      ],
      div(class="erp-page-actions") <| actions,
    ],
    body,
  ]
}

///|
fn table_panel(
  title : String,
  subtitle : String,
  content : @html.Html,
) -> @html.Html {
  section(class="erp-table-panel") <| [
    div(class="erp-panel-heading") <| [
      div <| [
        h2(title),
        span(class="erp-panel-subtitle", subtitle),
      ],
    ],
    content,
  ]
}

///|
fn project_runtime_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  for row in model.project_rows {
    rows.push([
      row.project_id,
      row.project_code,
      row.project_name,
      row.bu_name,
      row.current_stage,
      row.begin_date,
      row.proj_status,
      row.task_count,
      row.source_kind,
    ])
  }
  table_panel(
    "PostgreSQL 项目主数据",
    model.project_note + " · 导入项目保持只读",
    data_table(
      [
        "项目 ID", "项目编码", "项目名称", "所属公司", "当前阶段",
        "开始日期", "状态", "任务数", "来源",
      ],
      rows,
    ),
  )
}

///|
fn project_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "项目主数据",
    "PROJECTS",
    "维护集团项目、所属公司与项目阶段，作为成本、合同、销售与资金业务的共同主数据。",
    [
      nav_button(
        emit, "/projects/CD-HJL", "erp-primary-btn", "＋ 新建项目",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.projects_loaded {
            "PostgreSQL 项目主数据已连接"
          } else {
            "项目主数据读模型"
          },
        ),
        span(" · " + model.project_note),
      ]),
      div(class="erp-stat-grid") <| [
        metric("项目总数", "15", "在建项目", "metric-blue"),
        metric("本月新增", "2", "较上月 +1", "metric-blue"),
        metric("建设中", "9", "占比 60%", "metric-green"),
      ],
      filter_bar("项目编码 / 项目名称 / 所属公司"),
      table_panel(
        "项目列表",
        "设计快照 · 源数据见下方 PostgreSQL 读模型",
        data_table(
          [
            "项目编码", "项目名称", "所属公司", "当前阶段", "开始日期",
            "操作",
          ],
          [
            [
              "CD-HJL", "成都和锦里", "成都公司", "开发建设", "2024-03-18",
              "查看 / 编辑",
            ],
            [
              "CQ-NSJ", "重庆南山居", "重庆公司", "销售去化", "2023-09-01",
              "查看 / 编辑",
            ],
            [
              "SY-HSY", "沈阳和山苑", "沈阳公司", "规划设计", "2025-01-12",
              "查看 / 编辑",
            ],
            [
              "TJ-HJY", "天津海教园一期", "天津公司", "开发建设",
              "2024-06-20", "查看 / 编辑",
            ],
            [
              "TJ-MJW", "天津梅江湾三期", "天津公司", "获取", "2025-04-08",
              "查看 / 编辑",
            ],
          ],
        ),
      ),
      project_runtime_table(model),
    ],
  )
}

///|
fn delivery_runtime_banner(model : Model) -> @html.Html {
  let row_count = if model.delivery_loaded {
    (model.delivery_progress_rows.length() + model.delivery_task_rows.length()).to_string()
  } else {
    "—"
  }
  div(class="erp-runtime-banner", [
    strong(
      if model.delivery_loaded {
        "PostgreSQL 已连接"
      } else {
        "工程进度读模型"
      },
    ),
    span(
      " · " +
      row_count +
      (if model.delivery_loaded {
        " 条进度/任务投影"
      } else {
        " 等待加载"
      }),
    ),
    span(" · " + model.delivery_note),
    span(" · " + model.delivery_command_note),
  ])
}

///|
fn delivery_progress_table(model : Model) -> @html.Html {
  if !model.delivery_loaded {
    div(class="erp-runtime-empty", "等待 PostgreSQL 工程进度投影")
  } else {
    let rows : Array[Array[String]] = []
    for row in model.delivery_progress_rows {
      rows.push([
        row.progress_id,
        row.project_id,
        row.building_no,
        row.stage,
        row.plan_date,
        row.actual_date,
        row.plan_pct + "%",
        row.actual_pct + "%",
        row.state,
        row.source_kind,
        row.source_id,
        row.remark,
      ])
    }
    table_panel(
      "当前 PostgreSQL 工程进度",
      "源记录只读 · 本地命令需要证据并保留审计",
      data_table(
        [
          "记录", "项目", "楼栋", "阶段", "计划日期", "实际日期",
          "计划%", "实际%", "状态", "来源", "源ID", "备注",
        ],
        rows,
      ),
    )
  }
}

///|
fn delivery_outputs_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  for row in model.delivery_output_rows {
    rows.push([
      row.output_id,
      row.project_id,
      row.contract_id,
      row.period,
      row.output_amount,
      row.confirm_amount,
      row.state,
      row.source_kind,
      row.remark,
    ])
  }
  table_panel(
    "产值确认",
    "确认不等于入账 · 需要独立证据",
    data_table(
      [
        "记录", "项目", "合同", "期间", "申报产值", "确认产值", "状态",
        "来源", "备注",
      ],
      rows,
    ),
  )
}

///|
fn delivery_tasks_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  for row in model.delivery_task_rows {
    rows.push([
      row.task_id,
      row.project_id,
      row.task_name,
      row.plan_begin_date,
      row.plan_end_date,
      row.progress_pct + "%",
      row.status,
      row.source_kind,
    ])
  }
  table_panel(
    "项目计划任务",
    "导入任务状态保持只读 · 任务汇报单独留痕",
    data_table(
      [
        "任务", "项目", "名称", "计划开始", "计划完成", "完成度",
        "状态", "来源",
      ],
      rows,
    ),
  )
}

///|
fn delivery_reports_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  for row in model.delivery_report_rows {
    rows.push([
      row.report_id,
      row.task_id,
      row.progress_pct + "%",
      row.report_date,
      row.state,
      row.source_kind,
      row.summary,
    ])
  }
  table_panel(
    "任务汇报证据",
    "汇报记录不直接修改导入任务状态",
    data_table(
      ["报告", "任务", "进度", "日期", "状态", "来源", "摘要"],
      rows,
    ),
  )
}

///|
fn project_plan_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "项目计划",
    "PROJECT PLAN",
    "按项目阶段查看里程碑、计划工期与责任人，支持项目经理持续更新计划状态。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(ReportTaskProgress),
        "汇报当前任务",
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(CreateDeliveryProgress),
        "＋ 新建进度记录",
      ),
    ],
    div <| [
      delivery_runtime_banner(model),
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "计划总览"),
        button(class="erp-tab", "甘特图"),
        button(class="erp-tab", "里程碑"),
      ],
      delivery_tasks_table(model),
    ],
  )
}

///|
fn progress_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "工程进度",
    "PROJECT PROGRESS",
    "对照计划日期与实际完成率跟踪楼栋、施工阶段和交付节点。",
    [
      button(class="erp-secondary-btn", "导出进度表"),
      button(
        class="erp-primary-btn",
        on_click=emit(CreateDeliveryProgress),
        "＋ 更新进度",
      ),
    ],
    div <| [
      delivery_runtime_banner(model),
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "进度总览"),
        button(class="erp-tab", "楼栋视图"),
        button(class="erp-tab", "交付节点"),
      ],
      delivery_progress_table(model),
      delivery_outputs_table(model),
      div(class="erp-inline-actions") <| [
        button(
          class="erp-secondary-btn",
          on_click=emit(ReportDeliveryProgress),
          "提交现场进度",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(AcceptDeliveryProgress),
          "接受进度证据",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(RejectDeliveryProgress),
          "退回进度证据",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(CreateDeliveryOutput),
          "登记产值",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(ConfirmDeliveryOutput),
          "确认产值",
        ),
      ],
      delivery_reports_table(model),
    ],
  )
}

///|
fn workflow_runtime_table(model : Model) -> @html.Html {
  fn step_text(steps : Array[WorkflowStepRow]) -> String {
    let mut text = ""
    for step in steps {
      if text != "" {
        text = text + " · "
      }
      text = text +
        step.step_order +
        "." +
        step.step_name +
        " (" +
        step.step_guid +
        ") [" +
        step.step_key +
        "; 阈值 " +
        step.threshold +
        "; 指派 " +
        step.assignee_count +
        (if step.assignee_names != "" {
          " (" + step.assignee_names + ")"
        } else {
          ""
        }) +
        "; " +
        step.source_kind +
        "]"
    }
    text
  }
  let rows : Array[Array[String]] = []
  for row in model.workflow_process_rows {
    rows.push([
      row.process_guid,
      row.process_name,
      row.process_key,
      row.biz_type,
      row.step_count,
      row.instances_available,
      row.actions_available,
      row.source_kind,
      step_text(row.steps),
    ])
  }
  table_panel(
    "PostgreSQL 工作流定义",
    model.workflow_note + " · 审批实例与动作不从空源数据推断",
    data_table(
      [
        "流程 ID", "流程", "流程键", "业务类型", "步骤", "实例行",
        "动作行", "来源", "步骤定义",
      ],
      rows,
    ),
  )
}

///|
fn tasks_view(model : Model) -> @html.Html {
  page_shell(
    "我的待办",
    "WORKFLOW",
    "集中处理报销、借款、付款申请与项目协同任务，查看发起记录和审批历史。",
    [button(class="erp-primary-btn", "＋ 发起流程")],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.workflow_loaded {
            "PostgreSQL 工作流定义已连接"
          } else {
            "工作流读模型"
          },
        ),
        span(" · " + model.workflow_note),
      ]),
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "待办 (8)"),
        button(class="erp-tab", "已发起"),
        button(class="erp-tab", "审批历史"),
        button(class="erp-tab", "告警任务"),
      ],
      table_panel(
        "待办事项",
        "按优先级排序",
        data_table(
          [
            "事项", "类型", "发起人", "提交时间", "金额", "优先级",
            "操作",
          ],
          [
            [
              "成都和锦里 · 工程款付款申请", "付款审批", "陈志强",
              "今天 09:18", "¥1,280,000", "高", "处理",
            ],
            [
              "2026-07 差旅费用报销", "费用审批", "程玉哲", "昨天 16:42",
              "¥8,560", "中", "处理",
            ],
            [
              "南山居营销推广合同", "合同审批", "刘松", "2026-07-11",
              "¥360,000", "中", "处理",
            ],
            [
              "项目节点延期确认", "项目协同", "系统", "2026-07-10",
              "—", "高", "查看",
            ],
          ],
        ),
      ),
      workflow_runtime_table(model),
    ],
  )
}

///|
fn ai_hub_view() -> @html.Html {
  page_shell(
    "AI 工作台",
    "AI HUB",
    "把文件、自然语言问题和业务动作放进同一个工作台，AI 结果仍需业务人员确认后写入。",
    [button(class="erp-primary-btn", "＋ 上传文件")],
    div <| [
      div(class="erp-ai-grid") <| [
        section(class="erp-ai-card is-primary") <| [
          span(class="erp-ai-icon", "✦"),
          h2("AI 起单"),
          p(
            "拖入合同、发票或付款资料，自动识别业务类型并生成草稿。",
          ),
          button(class="erp-secondary-btn", "开始识别"),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⌁"),
          h2("AI 查询"),
          p(
            "用大白话查询项目、合同、成本和现金流，结果可追溯。",
          ),
          button(class="erp-secondary-btn", "打开查询"),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⚑"),
          h2("风险洞察"),
          p("基于延期、成本偏差和付款异常生成风险清单。"),
          button(class="erp-secondary-btn", "查看风险"),
        ],
      ],
      table_panel(
        "最近 AI 任务",
        "所有结果保留审计记录",
        data_table(["任务", "输入", "结果", "创建时间", "状态"], [
          [
            "合同要素识别", "南山居施工合同.pdf", "识别 32 个字段",
            "今天 09:12", "已完成",
          ],
          [
            "现金流问答", "未来 90 天资金缺口？", "预计峰值 ¥2,180 万",
            "昨天 17:06", "已完成",
          ],
          [
            "发票 OCR", "invoice_20260712.jpg", "待确认 1 个税号", "昨天 15:44",
            "待处理",
          ],
        ]),
      ),
    ],
  )
}

///|
fn ai_stats_view() -> @html.Html {
  page_shell(
    "AI 工作大盘",
    "AI ANALYTICS",
    "查看 AI 起单、查询、风险洞察的调用量、准确率和人工确认情况。",
    [button(class="erp-secondary-btn", "导出数据")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月调用", "1,286", "较上月 +18.4%", "metric-blue"),
        metric("自动通过率", "86.2%", "目标 85%", "metric-green"),
        metric(
          "节省人工", "214 小时", "按确认记录估算", "metric-blue",
        ),
        metric("待确认", "23", "需要业务复核", "metric-blue"),
      ],
      table_panel(
        "场景使用情况",
        "2026 年 7 月",
        data_table(
          [
            "场景", "调用次数", "自动通过", "平均耗时", "准确率",
            "趋势",
          ],
          [
            ["合同要素识别", "482", "418", "4.8s", "92.1%", "↑"],
            ["发票 OCR", "396", "324", "2.1s", "88.4%", "↑"],
            ["自然语言查询", "285", "—", "1.7s", "96.3%", "↑"],
            ["风险洞察", "123", "98", "6.2s", "79.7%", "→"],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_runtime_banner(model : Model, family : String) -> @html.Html {
  let active = model.sales_loaded && model.sales_family == family
  let row_count = if active {
    model.sales_rows.length().to_string()
  } else {
    "—"
  }
  let count_suffix = if active { " 条当前投影" } else { " 等待加载" }
  let sample = match model.sales_rows.get(0) {
    Some(row) =>
      " · " +
      row.aggregate_id +
      " · " +
      row.primary +
      " · " +
      row.secondary +
      " · " +
      row.amount_display +
      " · " +
      row.state +
      " · " +
      row.source_kind
    None => ""
  }
  div(class="erp-runtime-banner", [
    strong(if active { "PostgreSQL 已连接" } else { "销售读模型" }),
    span(" · " + row_count + count_suffix),
    span(sample),
    span(" · " + model.sales_note),
  ])
}

///|
fn sales_projection_table(model : Model, family : String) -> @html.Html {
  if !model.sales_loaded || model.sales_family != family {
    div(class="erp-runtime-empty", "等待 PostgreSQL 销售投影")
  } else {
    let rows : Array[Array[String]] = []
    for row in model.sales_rows {
      rows.push([
        row.aggregate_id,
        row.primary,
        row.secondary,
        row.amount_display,
        row.state,
        row.source_kind,
      ])
    }
    table_panel(
      "当前 PostgreSQL 投影",
      "源记录只读 · 本地命令保留审计凭证",
      data_table(
        ["记录", "主要信息", "关联客户", "金额", "状态", "来源"],
        rows,
      ),
    )
  }
}

///|
fn sales_customers_view(model : Model) -> @html.Html {
  page_shell(
    "客户档案",
    "SALES / CUSTOMERS",
    "维护客户、联系方式、认筹意向与跟进状态，贯通认筹、签约和回款。",
    [button(class="erp-primary-btn", "＋ 新增客户")],
    div <| [
      sales_runtime_banner(model, "customers"),
      sales_projection_table(model, "customers"),
      filter_bar("客户姓名 / 手机号 / 客户编号"),
      table_panel(
        "客户列表",
        "共 1,248 位客户",
        data_table(
          [
            "客户编号", "客户姓名", "手机号", "意向项目", "意向房源",
            "跟进状态", "最近联系",
          ],
          [
            [
              "CUS-20260701", "王晓峰", "138****6210", "成都和锦里", "2#-1802",
              "重点跟进", "今天",
            ],
            [
              "CUS-20260688", "赵文静", "186****4302", "重庆南山居", "5#-2101",
              "已认筹", "昨天",
            ],
            [
              "CUS-20260642", "李海涛", "139****0791", "沈阳和山苑", "—",
              "待回访", "2026-07-11",
            ],
            [
              "CUS-20260596", "陈敏", "158****9920", "天津海教园一期", "3#-901",
              "已签约", "2026-07-08",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_subscriptions_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  page_shell(
    "认筹登记",
    "SALES / SUBSCRIPTIONS",
    "登记认筹客户、房号、认筹金与转签状态，支持从客户档案快速发起签约。",
    [
      nav_button(
        emit, "/sales/subscriptions", "erp-primary-btn", "＋ 新建认筹",
      ),
    ],
    div <| [
      sales_runtime_banner(model, "subscriptions"),
      sales_projection_table(model, "subscriptions"),
      div(class="erp-stat-grid") <| [
        metric("本月认筹", "86", "认筹金 ¥516 万", "metric-blue"),
        metric("待转签", "24", "近 7 日新增 6", "metric-blue"),
        metric("转签率", "71.4%", "较上月 +4.2%", "metric-green"),
      ],
      filter_bar("认筹号 / 客户 / 房号"),
      table_panel(
        "认筹记录",
        "共 386 条",
        data_table(
          [
            "认筹号", "客户", "电话", "房号", "面积㎡", "单价(元/㎡)",
            "总价(元)", "认筹金", "认筹日", "状态",
          ],
          [
            [
              "RC-260713-001", "王晓峰", "138****6210", "2#-1802", "128.60", "18,600",
              "2,391,960", "60,000", "2026-07-13", "待转签",
            ],
            [
              "RC-260712-009", "赵文静", "186****4302", "5#-2101", "96.40", "16,800",
              "1,619,520", "50,000", "2026-07-12", "已认筹",
            ],
            [
              "RC-260711-014", "陈敏", "158****9920", "3#-901", "89.20", "22,100",
              "1,971,320", "80,000", "2026-07-11", "已转签",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_contracts_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "签约管理",
    "SALES / CONTRACTS",
    "管理销售合同、付款方式、签约日期和回款状态，与销售回款和发票联动。",
    [
      nav_button(
        emit, "/sales/contracts", "erp-primary-btn", "＋ 新建签约",
      ),
    ],
    div <| [
      sales_runtime_banner(model, "contracts"),
      sales_projection_table(model, "contracts"),
      filter_bar("签约号 / 客户 / 房号"),
      table_panel(
        "销售合同",
        "本月签约 42 套",
        data_table(
          [
            "签约号", "客户", "电话", "房号", "面积㎡", "总价(元)",
            "付款方式", "签约日", "状态",
          ],
          [
            [
              "SC-260713-004", "陈敏", "158****9920", "3#-901", "89.20", "1,971,320",
              "按揭", "2026-07-13", "已签约",
            ],
            [
              "SC-260712-016", "刘洋", "136****2840", "1#-1203", "116.80", "2,172,480",
              "组合贷", "2026-07-12", "已签约",
            ],
            [
              "SC-260710-008", "张伟", "133****5701", "6#-602", "78.40", "1,372,000",
              "一次性", "2026-07-10", "待备案",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_mortgages_view(model : Model) -> @html.Html {
  page_shell(
    "按揭办理",
    "SALES / MORTGAGES",
    "跟进按揭申请、银行审批与放款节点，及时发现资料缺失和逾期申请。",
    [button(class="erp-primary-btn", "＋ 新建按揭")],
    div <| [
      sales_runtime_banner(model, "mortgages"),
      sales_projection_table(model, "mortgages"),
      div(class="erp-stat-grid") <| [
        metric("办理中", "68", "涉及 5 家银行", "metric-blue"),
        metric("本月放款", "¥3,860 万", "32 笔", "metric-green"),
        metric("资料待补", "7", "需客户跟进", "metric-blue"),
      ],
      filter_bar("按揭号 / 客户 / 银行"),
      table_panel(
        "按揭申请",
        "共 214 条",
        data_table(
          [
            "按揭号", "客户", "银行", "贷款额(元)", "年限", "利率",
            "申请日", "批贷日", "放款日", "状态",
          ],
          [
            [
              "MT-260701-019", "王晓峰", "建设银行", "1,673,000", "30 年",
              "3.45%", "2026-07-01", "", "", "审批中",
            ],
            [
              "MT-260628-008", "赵文静", "招商银行", "1,130,000", "30 年",
              "3.45%", "2026-06-28", "2026-07-08", "", "待放款",
            ],
            [
              "MT-260615-002", "陈敏", "工商银行", "1,380,000", "25 年", "3.55%",
              "2026-06-15", "2026-06-22", "2026-07-03", "已放款",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn fallback_contract_rows() -> Array[ContractRow] {
  [
    {
      contract_id: "ht-tj-001",
      contract_code: "HT-TJHJY-001",
      contract_name: "海教园1号楼总包工程合同",
      project_id: "proj-0001",
      project_name: "天津海教园一期",
      supplier_id: "supplier-tj-001",
      supplier_name: "天津建工集团第三建筑工程有限公司",
      amount_minor: "1800000000",
      amount_display: "¥18,000,000.00",
      currency: "CNY",
      sign_date: "2026-03-15",
      state: "active",
      paid_amount_display: "¥3,600,000.00",
      milestone_count: "3",
      source_kind: "imported",
    },
    {
      contract_id: "ht-tj-002",
      contract_code: "HT-TJHJY-002",
      contract_name: "海教园1号楼幕墙采购合同",
      project_id: "proj-0001",
      project_name: "天津海教园一期",
      supplier_id: "supplier-tj-002",
      supplier_name: "天津永大幕墙工程有限公司",
      amount_minor: "680000000",
      amount_display: "¥6,800,000.00",
      currency: "CNY",
      sign_date: "2026-04-08",
      state: "active",
      paid_amount_display: "¥2,040,000.00",
      milestone_count: "1",
      source_kind: "imported",
    },
  ]
}

///|
fn contract_table_row(
  emit : @rabbita.Emit[Msg],
  row : ContractRow,
) -> @html.Html {
  tr <| [
    td(row.contract_code),
    td(row.contract_name),
    td(row.project_name),
    td(row.supplier_name),
    td(row.amount_display),
    td(row.paid_amount_display),
    td(row.sign_date),
    td <| [
      span(class="erp-status-tag is-success", contract_state_label(row.state)),
    ],
    td <| [
      button(
        class="erp-ghost-btn",
        on_click=emit(Navigate("/contracts/" + row.contract_id)),
        "查看详情",
      ),
    ],
  ]
}

///|
fn contract_table(
  emit : @rabbita.Emit[Msg],
  rows : Array[ContractRow],
) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for row in rows {
    rendered.push(contract_table_row(emit, row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "合同编号", "合同名称", "项目", "供应商", "合同金额", "已付款",
        "签订日期", "状态", "操作",
      ]),
    ],
    tbody <| rendered,
  ]
}

///|
fn contracts_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.contracts_loaded && model.contract_rows.length() > 0 {
    model.contract_rows
  } else {
    fallback_contract_rows()
  }
  page_shell(
    "合同台帐",
    "COST / CONTRACTS",
    "统一查看采购、工程、营销和咨询合同的签订、付款、发票与履约状态。",
    [
      button(class="erp-secondary-btn", "导出合同台帐"),
      nav_button(
        emit, "/contracts/CT-RABBITA-LOCAL", "erp-primary-btn", "＋ 新建合同",
      ),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("合同总数", "62", "覆盖 15 个项目", "metric-blue"),
        metric("合同金额", "¥12.57 亿", "较目标 +6.2%", "metric-blue"),
        metric("待付款", "¥1.84 亿", "24 个申请", "metric-green"),
      ],
      filter_bar("合同编号 / 项目 / 供应商"),
      table_panel(
        "合同列表",
        model.contract_note,
        contract_table(emit, rows),
      ),
    ],
  )
}

///|
fn fallback_payment_apply_rows() -> Array[PaymentApplyRow] {
  [
    {
      apply_id: "apply-tj-001",
      apply_code: "FK202604010001",
      contract_id: "ht-tj-001",
      contract_name: "海教园1号楼总包工程合同",
      project_name: "天津海教园一期",
      supplier_name: "天津建工集团第三建筑工程有限公司",
      subject: "海教园1号楼总包首付款 20%",
      amount_minor: "360000000",
      amount_display: "¥3,600,000.00",
      currency: "CNY",
      apply_date: "2026-04-02",
      operation_state: "paid",
      apply_state: "已审核",
      pay_state: "完全支付",
      apply_type_code: "WORK_PROGRESS",
      pay_class: "合同",
      applied_by: "user-lmj-0001",
      applied_by_name: "李明津",
      source_kind: "imported",
      plan_id: "plan-tj-001-1",
      milestone_id: "",
    },
    {
      apply_id: "apply-tj-002",
      apply_code: "FK202605150001",
      contract_id: "ht-tj-002",
      contract_name: "海教园1号楼幕墙采购合同",
      project_name: "天津海教园一期",
      supplier_name: "天津永大幕墙工程有限公司",
      subject: "海教园1号楼幕墙订货款 30%",
      amount_minor: "204000000",
      amount_display: "¥2,040,000.00",
      currency: "CNY",
      apply_date: "2026-05-16",
      operation_state: "paid",
      apply_state: "已审核",
      pay_state: "完全支付",
      apply_type_code: "PURCHASE",
      pay_class: "合同",
      applied_by: "user-lmj-0001",
      applied_by_name: "李明津",
      source_kind: "imported",
      plan_id: "plan-tj-002-1",
      milestone_id: "",
    },
    {
      apply_id: "apply-tj-003",
      apply_code: "FK202606010001",
      contract_id: "ht-tj-001",
      contract_name: "海教园1号楼总包工程合同",
      project_name: "天津海教园一期",
      supplier_name: "天津建工集团第三建筑工程有限公司",
      subject: "海教园1号楼总包进度款 第一批",
      amount_minor: "360000000",
      amount_display: "¥3,600,000.00",
      currency: "CNY",
      apply_date: "2026-06-01",
      operation_state: "submitted",
      apply_state: "申请审批中",
      pay_state: "未支付",
      apply_type_code: "WORK_PROGRESS",
      pay_class: "合同",
      applied_by: "user-lmj-0001",
      applied_by_name: "李明津",
      source_kind: "imported",
      plan_id: "plan-tj-001-2",
      milestone_id: "",
    },
  ]
}

///|
fn payment_apply_table_row(
  emit : @rabbita.Emit[Msg],
  row : PaymentApplyRow,
) -> @html.Html {
  tr <| [
    td(row.apply_code + " · " + row.apply_id + " / " + row.source_kind),
    td(row.project_name),
    td(row.contract_name),
    td(row.subject + " · " + row.pay_class + " / " + row.apply_type_code),
    td(row.supplier_name),
    td(row.amount_display + " " + row.currency + " / " + row.amount_minor),
    td(row.applied_by_name + " / " + row.applied_by),
    td(row.apply_date),
    td <| [
      span(
        class="erp-status-tag is-success",
        payment_apply_state_label(row.operation_state) +
        " · " +
        row.apply_state +
        " · " +
        row.pay_state,
      ),
    ],
    td <| [
      div <| [
        span("计划 " + row.plan_id + " / 节点 " + row.milestone_id),
        button(
          class="erp-ghost-btn",
          on_click=emit(Navigate("/contracts/" + row.contract_id)),
          "查看合同",
        ),
      ],
    ],
  ]
}

///|
fn payment_apply_table(
  emit : @rabbita.Emit[Msg],
  rows : Array[PaymentApplyRow],
) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for row in rows {
    rendered.push(payment_apply_table_row(emit, row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "申请编号 / 来源", "项目", "合同", "事由 / 类型", "收款方",
        "申请金额", "申请人", "提交日期", "状态", "关联 / 操作",
      ]),
    ],
    tbody <| rendered,
  ]
}

///|
fn payment_apply_actions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(CreatePaymentApply),
      "＋ 发起付款申请",
    ),
    button(
      class="erp-secondary-btn",
      on_click=emit(CheckPaymentEligibility),
      "校验付款节点",
    ),
  ]
  match model.payment_apply_state {
    "draft" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(SubmitPaymentApply),
          "提交审批",
        ),
      )
    "submitted" => {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(RejectPaymentApply),
          "退回",
        ),
      )
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(ApprovePaymentApply),
          "审核通过",
        ),
      )
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(UpdatePaymentApply),
          "保存修改",
        ),
      )
    }
    "rejected" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(ResubmitPaymentApply),
          "重新提交",
        ),
      )
    "approved" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(VoidPaymentApply),
          "作废申请",
        ),
      )
    _ => ()
  }
  actions
}

///|
fn payment_applies_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.payment_applies_loaded &&
    model.payment_apply_rows.length() > 0 {
    model.payment_apply_rows
  } else {
    fallback_payment_apply_rows()
  }
  page_shell(
    "付款申请",
    "COST / PAYMENTS",
    "按合同和成本科目发起付款申请，跟踪审批、付款和收款方信息。",
    payment_apply_actions(emit, model),
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "申请总数",
          rows.length().to_string(),
          "合同付款与支付状态",
          "metric-blue",
        ),
        metric(
          "本地命令",
          payment_apply_state_label(model.payment_apply_state),
          "Rabbita 审批回路",
          "metric-green",
        ),
        metric(
          "数据来源",
          if model.payment_applies_loaded {
            "PostgreSQL"
          } else {
            "快照"
          },
          model.payment_apply_note,
          "metric-blue",
        ),
      ],
      filter_bar("申请编号 / 合同 / 项目"),
      table_panel(
        "付款申请单",
        model.payment_apply_note + " · " + model.payment_apply_eligibility_note,
        payment_apply_table(emit, rows),
      ),
    ],
  )
}

///|
fn cost_dashboard_view() -> @html.Html {
  page_shell(
    "成本驾驶舱",
    "COST DASHBOARD",
    "从目标成本、动态成本、合同和付款四个层面观察项目成本偏差。",
    [
      button(class="erp-secondary-btn", "选择项目"),
      button(class="erp-secondary-btn", "导出分析"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("目标成本", "¥6.08 亿", "15 个项目", "metric-blue"),
        metric("动态成本", "¥6.45 亿", "偏差 +6.20%", "metric-green"),
        metric("已签合同", "¥5.82 亿", "覆盖率 90.2%", "metric-blue"),
        metric("待承诺", "¥6,280 万", "需关注 4 项", "metric-blue"),
      ],
      div(class="erp-dashboard-grid") <| [
        section(class="erp-panel") <| [
          div(class="erp-panel-heading") <| [
            h2("项目成本偏差"),
            span(class="erp-info-tag", "按动态成本"),
          ],
          div(class="erp-cost-bars") <| [
            phase_row("成都和锦里", "+8.4%", "84%"),
            phase_row("重庆南山居", "+5.7%", "57%"),
            phase_row("沈阳和山苑", "+1.4%", "14%"),
            phase_row("天津海教园", "+1.25%", "13%"),
          ],
        ],
        table_panel(
          "科目偏差 TOP 5",
          "动态成本 - 目标成本",
          data_table(
            [
              "CBS 科目", "目标成本", "动态成本", "偏差", "责任项目",
            ],
            [
              [
                "01-02 土地成本", "¥1.82 亿", "¥1.84 亿", "+1.1%", "成都和锦里",
              ],
              [
                "03-01 建安工程", "¥2.64 亿", "¥2.82 亿", "+6.8%", "成都和锦里",
              ],
              [
                "04-03 营销费用", "¥4,280 万", "¥4,560 万", "+6.5%", "重庆南山居",
              ],
            ],
          ),
        ),
      ],
    ],
  )
}

///|
fn investment_runtime_table(model : Model) -> @html.Html {
  if model.investment_loaded {
    let rows : Array[Array[String]] = []
    for row in model.investment_index_rows {
      rows.push([
        row.dimension,
        row.full_code,
        row.index_name,
        row.index_value,
        row.unit,
        row.source_kind,
      ])
    }
    table_panel(
      "投资指标（" +
      model.investment_index_rows.length().to_string() +
      " 项）",
      model.investment_note +
      " · 版本 " +
      model.investment_version_name +
      " (" +
      model.investment_version_id +
      ")",
      data_table(
        ["维度", "编码", "指标", "值", "单位", "来源"],
        rows,
      ),
    )
  } else {
    table_panel(
      "项目投资收益",
      "经营测算 vs 当前预测 · " + model.investment_note,
      data_table(
        [
          "项目", "总投资", "销售收入", "净利润", "利润率", "IRR",
          "状态",
        ],
        [
          [
            "成都和锦里", "¥2.36 亿", "¥3.82 亿", "¥5,420 万", "14.2%",
            "19.8%", "正常",
          ],
          [
            "重庆南山居", "¥1.84 亿", "¥2.76 亿", "¥3,180 万", "11.5%",
            "15.6%", "关注",
          ],
          [
            "沈阳和山苑", "¥1.62 亿", "¥2.28 亿", "¥2,960 万", "13.0%",
            "17.2%", "正常",
          ],
          [
            "天津海教园一期", "¥1.48 亿", "¥2.06 亿", "¥2,420 万", "11.7%",
            "16.1%", "正常",
          ],
        ],
      ),
    )
  }
}

///|
fn investment_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let stats = if model.investment_loaded {
    div(class="erp-stat-grid") <| [
      metric(
        "项目总投资",
        "¥" + model.investment_total,
        "版本 " + model.investment_version_name,
        "metric-blue",
      ),
      metric(
        "预计销售收入",
        "¥" + model.investment_revenue,
        "源指标 · 只读",
        "metric-blue",
      ),
      metric(
        "预计净利润",
        "¥" + model.investment_net_profit,
        "成本 ¥" +
        model.investment_cost +
        " · 利润率 " +
        model.investment_net_profit_margin +
        "%",
        "metric-green",
      ),
      metric(
        "加权 IRR",
        model.investment_irr + "%",
        model.investment_dimension_count + " 个源维度",
        "metric-green",
      ),
    ]
  } else {
    div(class="erp-stat-grid") <| [
      metric(
        "项目总投资", "¥8.42 亿", "含土地及开发", "metric-blue",
      ),
      metric(
        "预计销售收入", "¥12.68 亿", "去化率 64%", "metric-blue",
      ),
      metric("预计净利润", "¥1.72 亿", "利润率 13.6%", "metric-green"),
      metric("加权 IRR", "18.4%", "目标 16.0%", "metric-green"),
    ]
  }
  page_shell(
    "投资收益",
    "COST / INVESTMENT",
    "按项目查看投资额、销售收入、利润和 IRR，沉淀投资测算与实际经营的差异。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/investment")),
        "刷新测算",
      ),
    ],
    div <| [
      stats,
      investment_runtime_table(model),
    ],
  )
}

///|
fn dynamic_cost_table(model : Model) -> @html.Html {
  if model.dynamic_cost_loaded {
    let rows : Array[Array[String]] = []
    for row in model.dynamic_cost_rows {
      rows.push([
        row.cost_guid,
        row.cost_code + " · " + row.cost_name,
        row.cost_level,
        row.target_cost,
        row.dynamic_cost,
        row.deviation_pct,
        row.contract_change,
        row.actual_cost,
        row.budget_cost,
        row.estimate_change,
        row.layout_spare,
        row.end_cost,
        row.project_name + " · " + row.remarks + " · " + row.source_kind,
      ])
    }
    table_panel(
      "动态成本明细（" +
      model.dynamic_cost_rows.length().to_string() +
      " 项）",
      model.dynamic_cost_note +
      " · " +
      model.dynamic_cost_project_name +
      " · 末级 " +
      model.dynamic_cost_end_count,
      data_table(
        [
          "成本 ID", "科目", "层级", "目标 A", "动态 B", "偏差 C%", "合同 D",
          "已发 E", "预算 F", "预估 G", "余量 H", "末级", "备注/来源",
        ],
        rows,
      ),
    )
  } else {
    table_panel(
      "动态成本明细",
      "成都和锦里 · " + model.dynamic_cost_note,
      data_table(
        [
          "变更编号", "成本科目", "变更原因", "目标成本", "动态成本",
          "变更额", "发起人", "状态",
        ],
        [
          [
            "DC-260713-002", "03-01 建安工程", "设计优化", "¥264,000,000",
            "¥282,400,000", "+¥18,400,000", "王工", "审批中",
          ],
          [
            "DC-260709-006", "04-03 营销费用", "渠道政策调整", "¥42,800,000",
            "¥45,600,000", "+¥2,800,000", "刘松", "已完成",
          ],
          [
            "DC-260704-001", "05-02 配套工程", "管线迁改", "¥18,600,000",
            "¥19,280,000", "+¥680,000", "陈工", "待处理",
          ],
        ],
      ),
    )
  }
}

///|
fn dynamic_cost_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let stats = if model.dynamic_cost_loaded {
    div(class="erp-stat-grid") <| [
      metric(
        "目标成本 A",
        model.dynamic_cost_target,
        "末级科目 " + model.dynamic_cost_end_count,
        "metric-blue",
      ),
      metric(
        "动态成本 B",
        model.dynamic_cost_total,
        "A + D + E + F + G",
        "metric-green",
      ),
      metric(
        "偏差 C",
        model.dynamic_cost_deviation + "%",
        "规划余量 H " + model.dynamic_cost_spare,
        "metric-blue",
      ),
    ]
  } else {
    div(class="erp-stat-grid") <| [
      metric("目标成本", "¥6.08 亿", "15 个项目", "metric-blue"),
      metric("动态成本", "¥6.45 亿", "偏差 +6.20%", "metric-green"),
      metric("已签合同", "¥5.82 亿", "覆盖率 90.2%", "metric-blue"),
    ]
  }
  page_shell(
    "动态成本",
    "COST / FORECAST",
    "汇总合同、签证、变更和待发生成本，形成可追溯的动态成本预测。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/dynamic-cost")),
        "刷新成本",
      ),
    ],
    div <| [
      stats,
      filter_bar("项目 / 成本科目 / 变更编号"),
      dynamic_cost_table(model),
    ],
  )
}

///|
fn fallback_tender_rows() -> Array[TenderRow] {
  [
    {
      tender_id: "TP-CD-0301",
      name: "主体结构工程",
      project_scope: "project:CD-HJL",
      category: "03-01 建安工程",
      estimated_amount_minor: "26400000000",
      estimated_amount_display: "¥264,000,000.00",
      currency: "CNY",
      state: "bidding",
      awarded_supplier_id: "",
      awarded_amount_display: "¥48,600,000.00",
      commitment_id: "",
      bid_count: "0",
      source_kind: "snapshot",
    },
    {
      tender_id: "TP-CD-0502",
      name: "园林景观工程",
      project_scope: "project:CD-HJL",
      category: "05-02 配套工程",
      estimated_amount_minor: "1860000000",
      estimated_amount_display: "¥18,600,000.00",
      currency: "CNY",
      state: "planning",
      awarded_supplier_id: "",
      awarded_amount_display: "—",
      commitment_id: "",
      bid_count: "0",
      source_kind: "snapshot",
    },
    {
      tender_id: "TP-CQ-0403",
      name: "营销推广服务",
      project_scope: "project:CQ-NSJ",
      category: "04-03 营销费用",
      estimated_amount_minor: "4280000000",
      estimated_amount_display: "¥42,800,000.00",
      currency: "CNY",
      state: "bidding",
      awarded_supplier_id: "",
      awarded_amount_display: "¥3,600,000.00",
      commitment_id: "",
      bid_count: "0",
      source_kind: "snapshot",
    },
  ]
}

///|
fn tender_table_row(row : TenderRow) -> @html.Html {
  tr <| [
    td(row.tender_id + " / " + row.source_kind),
    td(row.project_scope),
    td(row.name),
    td(row.category),
    td(
      row.estimated_amount_display +
      " " +
      row.currency +
      " / " +
      row.estimated_amount_minor,
    ),
    td(
      row.awarded_amount_display +
      (if row.awarded_supplier_id == "" {
        ""
      } else {
        " / " + row.awarded_supplier_id
      }),
    ),
    td(row.bid_count + " 个投标"),
    td <| [
      span(class="erp-status-tag is-success", tender_state_label(row.state)),
      if row.commitment_id == "" {
        @html.nothing
      } else {
        span(" · 承诺 " + row.commitment_id)
      },
    ],
  ]
}

///|
fn tender_table(rows : Array[TenderRow]) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for row in rows {
    rendered.push(tender_table_row(row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "规划编号 / 来源", "项目范围", "合约包", "CBS / 类别", "预算金额",
        "已定标", "投标证据", "状态 / 承诺",
      ]),
    ],
    tbody <| rendered,
  ]
}

///|
fn tender_actions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(CreateTender),
      "＋ 新建合约规划",
    ),
  ]
  match model.tender_state {
    "planning" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(PublishTender),
          "发布招采计划",
        ),
      )
    "publishing" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(OpenTenderBidding),
          "开启投标",
        ),
      )
    "bidding" => {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(CancelTender),
          "取消规划",
        ),
      )
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(AwardTender),
          "定标（需供应商资格）",
        ),
      )
    }
    "awarded" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(CompleteTender),
          "完成招标",
        ),
      )
    _ => ()
  }
  actions
}

///|
fn tender_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.tenders_loaded && model.tender_rows.length() > 0 {
    model.tender_rows
  } else {
    fallback_tender_rows()
  }
  page_shell(
    "合约规划",
    "COST / TENDER",
    "按项目和 CBS 科目编制合约规划，控制招采范围、预算和合同落地。",
    tender_actions(emit, model),
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "规划数量",
          rows.length().to_string(),
          "招标计划与投标证据",
          "metric-blue",
        ),
        metric(
          "本地命令",
          tender_state_label(model.tender_state),
          "Rabbita 合约规划回路",
          "metric-green",
        ),
        metric(
          "数据来源",
          if model.tenders_loaded {
            "PostgreSQL"
          } else {
            "快照"
          },
          model.tender_note,
          "metric-blue",
        ),
      ],
      filter_bar("项目 / 合约包 / CBS 科目"),
      table_panel(
        "合约规划包",
        model.tender_note +
        " · award 需通过供应商资格与投标匹配校验",
        tender_table(rows),
      ),
    ],
  )
}

///|
fn fallback_supplier_rows() -> Array[SupplierRow] {
  [
    {
      supplier_id: "SUP-00018",
      supplier_code: "SUP-00018",
      name: "中建三局集团有限公司",
      category_code: "construction",
      evaluation: "qualified",
      state: "active",
      scope: "project:CD-HJL",
      source_kind: "snapshot",
    },
    {
      supplier_id: "SUP-00142",
      supplier_code: "SUP-00142",
      name: "众成广告传媒有限公司",
      category_code: "marketing",
      evaluation: "reviewed",
      state: "active",
      scope: "project:CQ-NSJ",
      source_kind: "snapshot",
    },
    {
      supplier_id: "SUP-00306",
      supplier_code: "SUP-00306",
      name: "绿城园林建设集团",
      category_code: "landscape",
      evaluation: "qualified",
      state: "active",
      scope: "project:SY-HSY",
      source_kind: "snapshot",
    },
    {
      supplier_id: "SUP-00427",
      supplier_code: "SUP-00427",
      name: "华北建材贸易有限公司",
      category_code: "materials",
      evaluation: "unqualified",
      state: "suspended",
      scope: "project:TJ-HJY",
      source_kind: "snapshot",
    },
  ]
}

///|
fn supplier_table(rows : Array[SupplierRow]) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for row in rows {
    rendered.push(
      tr <| [
        td(
          row.supplier_code + " · " + row.supplier_id + " / " + row.source_kind,
        ),
        td(row.name),
        td(row.category_code),
        td(row.scope),
        td(supplier_evaluation_label(row.evaluation)),
        td(supplier_state_label(row.state)),
      ],
    )
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "供应商编码 / 来源", "供应商名称", "主营类别", "服务范围",
        "资格评价", "状态",
      ]),
    ],
    tbody <| rendered,
  ]
}

///|
fn srm_providers_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.suppliers_loaded && model.supplier_rows.length() > 0 {
    model.supplier_rows
  } else {
    fallback_supplier_rows()
  }
  let actions : Array[@html.Html] = [
    nav_button(
      emit, "/srm/providers/SUP-00018", "erp-primary-btn", "＋ 新增供应商",
    ),
  ]
  match model.supplier_state {
    "new" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(CreateSupplier),
          "保存本地供应商",
        ),
      )
    "draft" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(SubmitSupplierReview),
          "提交资格审核",
        ),
      )
    "pending_review" =>
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(ReviewSupplier),
          "评定为合格",
        ),
      )
    "active" => {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(UpdateSupplier),
          "更新主数据",
        ),
      )
      actions.push(
        button(
          class="erp-danger-btn",
          on_click=emit(BlacklistSupplier),
          "加入黑名单",
        ),
      )
      actions.push(
        button(
          class="erp-ghost-btn",
          on_click=emit(VoidSupplier),
          "作废供应商",
        ),
      )
    }
    "suspended" => {
      actions.push(
        button(
          class="erp-danger-btn",
          on_click=emit(BlacklistSupplier),
          "加入黑名单",
        ),
      )
      actions.push(
        button(
          class="erp-ghost-btn",
          on_click=emit(VoidSupplier),
          "作废供应商",
        ),
      )
    }
    "blacklisted" =>
      actions.push(
        button(
          class="erp-ghost-btn",
          on_click=emit(VoidSupplier),
          "作废供应商",
        ),
      )
    _ => ()
  }
  page_shell(
    "供应商库",
    "SRM / PROVIDERS",
    "维护供应商资质、合作项目、联系人和履约评价，服务合同与招采环节。",
    actions,
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "本地命令",
          supplier_state_label(model.supplier_state),
          supplier_evaluation_label(model.supplier_evaluation),
          "metric-green",
        ),
        metric(
          "数据来源",
          if model.suppliers_loaded {
            "PostgreSQL"
          } else {
            "快照"
          },
          model.supplier_note,
          "metric-blue",
        ),
      ],
      filter_bar("供应商名称 / 统一社会信用代码 / 类别"),
      table_panel(
        "供应商列表",
        model.supplier_note +
        " · " +
        rows.length().to_string() +
        " 家供应商",
        supplier_table(rows),
      ),
    ],
  )
}

///|
fn srm_risk_view() -> @html.Html {
  page_shell(
    "供应商风险面板",
    "SRM / RISK",
    "集中查看资质到期、履约偏差、诉讼和集中度风险，支持责任人跟进。",
    [button(class="erp-secondary-btn", "导出风险清单")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("高风险", "6", "需在 7 日内处理", "metric-blue"),
        metric("中风险", "18", "较上周 -2", "metric-blue"),
        metric("资质即将到期", "12", "未来 30 天", "metric-green"),
      ],
      table_panel(
        "风险清单",
        "按风险等级排序",
        data_table(
          [
            "供应商", "风险类型", "风险说明", "影响合同", "责任人",
            "截止日期", "状态",
          ],
          [
            [
              "华北建材贸易有限公司", "资质到期", "安全生产许可证 15 天后到期",
              "3", "王磊", "2026-07-28", "待处理",
            ],
            [
              "众成广告传媒有限公司", "履约偏差", "投放效果低于约定 18%",
              "2", "刘松", "2026-07-20", "进行中",
            ],
            [
              "中建三局集团有限公司", "集中度", "单一供应商合同额占比 42%",
              "8", "陈志强", "2026-08-15", "关注",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn cbs_view(path : String) -> @html.Html {
  let title = title_for(path)
  page_shell(
    title,
    "CBS / MASTER DATA",
    "维护成本分解结构、目标版本和审批配置，确保项目成本口径一致。",
    [button(class="erp-primary-btn", "＋ 新建条目")],
    div <| [
      filter_bar("科目编码 / 科目名称 / 版本"),
      table_panel(
        "CBS 数据",
        "当前版本 V2026.07",
        data_table(
          [
            "编码", "名称", "层级", "适用范围", "最近更新", "维护人",
            "状态",
          ],
          [
            [
              "03", "建安工程", "一级", "全集团", "2026-07-01", "李明金",
              "正常",
            ],
            [
              "03-01", "主体结构工程", "二级", "开发项目", "2026-07-08",
              "李明金", "正常",
            ],
            [
              "03-01-002", "混凝土工程", "三级", "开发项目", "2026-07-12",
              "系统", "待审核",
            ],
            [
              "04-03", "营销费用", "二级", "销售项目", "2026-06-20", "刘松",
              "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn fund_plan_view() -> @html.Html {
  page_shell(
    "资金计划",
    "FINANCE / FUND PLAN",
    "统筹项目回款、融资、付款与资金缺口，形成月度和滚动资金计划。",
    [button(class="erp-primary-btn", "＋ 编制计划")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "本月可用资金", "¥4,280 万", "含银行余额", "metric-blue",
        ),
        metric(
          "本月计划流出", "¥3,860 万", "付款 48 笔", "metric-blue",
        ),
        metric(
          "资金缺口", "¥620 万", "预计 8 月出现", "metric-green",
        ),
      ],
      table_panel(
        "月度资金计划",
        "2026 年 7 月",
        data_table(
          [
            "项目 / 公司", "期初余额", "计划流入", "计划流出", "期末余额",
            "缺口", "负责人", "状态",
          ],
          [
            [
              "成都和锦里", "¥1,820 万", "¥2,460 万", "¥2,180 万", "¥2,100 万",
              "—", "陈志强", "正常",
            ],
            [
              "重庆南山居", "¥860 万", "¥1,120 万", "¥1,360 万", "¥620 万",
              "¥180 万", "刘松", "关注",
            ],
            [
              "沈阳和山苑", "¥1,240 万", "¥960 万", "¥820 万", "¥1,380 万",
              "—", "李明金", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn invoice_view(model : Model) -> @html.Html {
  page_shell(
    "发票管理",
    "FINANCE / INVOICE",
    "管理进项、销项发票的识别、验真、关联合同和入账状态。",
    [button(class="erp-primary-btn", "＋ 录入发票")],
    div <| [
      sales_runtime_banner(model, "invoices"),
      sales_projection_table(model, "invoices"),
      div(class="erp-stat-grid") <| [
        metric("本月进项", "¥1,286 万", "218 张", "metric-blue"),
        metric("待验真", "14", "金额 ¥82 万", "metric-blue"),
        metric("待入账", "36", "已关联合同", "metric-green"),
      ],
      filter_bar("发票号码 / 供应商 / 合同编号"),
      table_panel(
        "发票列表",
        "最近上传",
        data_table(
          [
            "发票号码", "发票类型", "供应商", "金额", "税额", "关联合同",
            "开票日期", "状态",
          ],
          [
            [
              "04400193 2687", "增值税专票", "中建三局", "¥1,165,138",
              "¥135,155", "HT-CD-260701", "2026-07-12", "待验真",
            ],
            [
              "04400193 2682", "增值税专票", "众成广告", "¥339,623", "¥19,977",
              "HT-CQ-260628", "2026-07-11", "已入账",
            ],
            [
              "04400192 9114", "增值税专票", "绿城园林", "¥816,514", "¥94,739",
              "HT-SY-260615", "2026-07-09", "已验真",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn expenses_view(emit : @rabbita.Emit[Msg]) -> @html.Html {
  page_shell(
    "我的报销",
    "FINANCE / EXPENSES",
    "发起差旅、招待和日常费用报销，查看预算占用、审批节点与付款进度。",
    [nav_button(emit, "/expenses/new", "erp-primary-btn", "＋ 新建报销")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("本月报销", "¥28,560", "8 笔", "metric-blue"),
        metric("审批中", "5", "金额 ¥16,420", "metric-blue"),
        metric("已付款", "¥62,180", "本年度", "metric-green"),
      ],
      filter_bar("报销单号 / 摘要 / 申请日期"),
      table_panel(
        "报销记录",
        "我的申请",
        data_table(
          [
            "报销单号", "费用类型", "摘要", "金额", "申请日期", "当前节点",
            "状态",
          ],
          [
            [
              "EXP-260712-008", "差旅费", "成都项目现场出差", "¥8,560",
              "2026-07-12", "部门负责人", "审批中",
            ],
            [
              "EXP-260705-003", "业务招待费", "供应商沟通会", "¥3,280",
              "2026-07-05", "财务复核", "审批中",
            ],
            [
              "EXP-260628-011", "办公费", "项目打印及耗材", "¥1,860",
              "2026-06-28", "—", "已完成",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn loan_runtime_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  for row in model.loan_rows {
    rows.push([
      row.loan_id,
      row.loan_code,
      row.subject,
      row.loan_amount,
      row.balance_amount,
      row.remain_amount,
      row.applied_by_name,
      row.apply_dept_name,
      row.project_name,
      row.apply_date,
      row.pay_unit,
      row.apply_state,
      row.source_kind,
    ])
  }
  table_panel(
    "PostgreSQL 借款与冲账",
    model.loan_note + " · 导入借款保持只读",
    data_table(
      [
        "记录", "借款单号", "用途", "借款金额", "已冲账", "未核销",
        "申请人", "部门", "项目", "日期", "收款单位", "状态", "来源",
      ],
      rows,
    ),
  )
}

///|
fn loans_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "我的借款",
    "FINANCE / LOANS",
    "发起备用金和差旅借款，跟踪核销、还款以及个人可用额度。",
    [nav_button(emit, "/loans/new", "erp-primary-btn", "＋ 新建借款")],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.loans_loaded {
            "PostgreSQL 已连接"
          } else {
            "员工借款读模型"
          },
        ),
        span(" · " + model.loan_note),
        span(" · " + model.loan_command_note),
      ]),
      div(class="erp-stat-grid") <| [
        metric("未核销借款", "¥18,000", "2 笔", "metric-blue"),
        metric("本月可用额度", "¥30,000", "个人额度", "metric-green"),
        metric("待审批", "1", "金额 ¥8,000", "metric-blue"),
      ],
      table_panel(
        "借款记录",
        "我的申请",
        data_table(
          [
            "借款单号", "借款类型", "用途", "金额", "申请日期", "预计归还",
            "核销状态", "审批状态",
          ],
          [
            [
              "LOAN-260701-002", "差旅借款", "成都项目驻场", "¥10,000",
              "2026-07-01", "2026-07-31", "未核销", "已完成",
            ],
            [
              "LOAN-260629-005", "备用金", "现场零星采购", "¥8,000", "2026-06-29",
              "2026-07-15", "待核销", "已完成",
            ],
            [
              "LOAN-260713-001", "差旅借款", "沈阳项目会议", "¥8,000",
              "2026-07-13", "2026-07-30", "—", "审批中",
            ],
          ],
        ),
      ),
      loan_runtime_table(model),
    ],
  )
}

///|
fn reports_runtime_banner(model : Model) -> @html.Html {
  div(class="erp-runtime-banner", [
    strong(
      if model.reports_loaded {
        "PostgreSQL 已连接"
      } else {
        "核心报表读模型"
      },
    ),
    span(
      " · " +
      (model.report_cost_rows.length() + model.report_contract_rows.length()).to_string() +
      " 条成本/合同报表行",
    ),
    span(" · " + model.reports_note),
    span(
      " · 供应商报表类型 " +
      model.report_supplier_count +
      " · 审批类型 " +
      model.report_approval_count,
    ),
  ])
}

///|
fn reports_data_tables(model : Model) -> @html.Html {
  let cost_rows : Array[Array[String]] = []
  for row in model.report_cost_rows {
    cost_rows.push([
      row.bu_name,
      row.proj_code,
      row.proj_name,
      row.target_cost,
      row.dynamic_cost,
      row.deviation_pct + "%",
      row.source_kind,
    ])
  }
  let contract_rows : Array[Array[String]] = []
  for row in model.report_contract_rows {
    contract_rows.push([
      row.contract_code,
      row.contract_name,
      row.provider,
      row.current_amount,
      row.paid_total,
      row.remain_amount,
      row.paid_pct + "%",
      row.source_kind,
    ])
  }
  let stage_rows : Array[Array[String]] = []
  for row in model.report_stage_rows {
    stage_rows.push([
      row.bu_name,
      row.proj_code,
      row.proj_name,
      row.proj_status,
      row.source_kind,
    ])
  }
  div <| [
    table_panel(
      "R1 集团成本汇总",
      "目标/动态成本来自导入源表 · 仅固定读模型",
      data_table(
        [
          "公司", "项目编码", "项目名称", "目标成本", "动态成本",
          "偏差%", "来源",
        ],
        cost_rows,
      ),
    ),
    table_panel(
      "R2 合同付款台账",
      "合同金额、已付、未付与付款率",
      data_table(
        [
          "合同", "名称", "乙方", "当前金额", "已付", "未付", "付款率",
          "来源",
        ],
        contract_rows,
      ),
    ),
    table_panel(
      "R5 项目阶段矩阵",
      "阶段明细由项目生命周期源表计算",
      data_table(
        ["公司", "项目编码", "项目名称", "当前阶段", "来源"],
        stage_rows,
      ),
    ),
  ]
}

///|
fn reports_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "报表中心",
    "ANALYSIS / REPORTS",
    "按主题打开经营、成本、资金、销售与项目报表，统一查看口径和更新时间。",
    [button(class="erp-secondary-btn", "管理收藏")],
    div <| [
      reports_runtime_banner(model),
      div(class="erp-report-grid") <| [
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "▦"),
          h2("经营驾驶舱"),
          p("公司、项目、合同与资金核心指标"),
          button(class="erp-secondary-btn", "打开"),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "¥"),
          h2("成本月报"),
          p("目标成本、动态成本与偏差分析"),
          nav_button(
            emit, "/share/cost-demo", "erp-secondary-btn", "分享预览",
          ),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "⌁"),
          h2("销售月报"),
          p("认筹、签约、回款和去化情况"),
          button(class="erp-secondary-btn", "打开"),
        ],
        section(class="erp-report-card") <| [
          span(class="erp-report-icon", "◷"),
          h2("资金预测"),
          p("未来 90 天流入流出和资金缺口"),
          button(class="erp-secondary-btn", "打开"),
        ],
      ],
      table_panel(
        "最近报表",
        "我的收藏",
        data_table(
          [
            "报表名称", "主题", "数据期间", "更新时间", "创建人",
            "操作",
          ],
          [
            [
              "集团经营周报", "经营", "2026-W28", "今天 08:30", "系统",
              "查看",
            ],
            [
              "项目成本偏差表", "成本", "2026-07", "昨天 18:20", "李明金",
              "查看",
            ],
            [
              "销售回款跟踪表", "销售", "2026-07", "昨天 17:45", "刘松",
              "查看",
            ],
          ],
        ),
      ),
      reports_data_tables(model),
    ],
  )
}

///|
fn share_view(path : String) -> @html.Html {
  let token = if path.has_prefix("/share/") {
    path[7:].to_owned()
  } else {
    "demo-cost"
  }
  div(class="erp-share-page") <| [
    div(class="erp-share-bar") <| [
      div <| [
        span(class="erp-share-brand", "ERP · 分享报表"),
        span(class="erp-share-note", "只读公开快照 · 不需要登录"),
      ],
      span(class="erp-share-token", "链接 \{token}"),
    ],
    div(class="erp-share-meta") <| [
      h1("集团成本汇总"),
      span(class="erp-status-tag is-success", "成本月报"),
      span(class="erp-share-expiry", "永不过期 · 数据期间 2026-07"),
    ],
    table_panel(
      "R1 集团成本汇总",
      "分享链接只展示已审核投影，不提供业务写入或导出权限",
      data_table(
        [
          "公司", "项目编码", "项目名称", "目标成本", "动态成本",
          "偏差%", "布置余地",
        ],
        [
          [
            "成都公司", "CD-HJL", "成都和锦里", "¥1860 万", "¥2016 万",
            "+8.4%", "¥42 万",
          ],
          [
            "重庆公司", "CQ-NSJ", "重庆南山居", "¥1240 万", "¥1261 万",
            "+1.7%", "¥86 万",
          ],
          [
            "沈阳公司", "SY-HSY", "沈阳和山苑", "¥980 万", "¥966 万",
            "-1.4%", "¥58 万",
          ],
          [
            "集团合计", "—", "3 个项目", "¥4080 万", "¥4243 万", "+4.0%",
            "¥186 万",
          ],
        ],
      ),
    ),
    div(
      class="erp-share-footer",
      "本页面由 ERP 报表分享链接生成 · 数据来自 PostgreSQL 投影读模型 · 仅链接持有者可访问",
    ),
  ]
}

///|
fn report_builder_view() -> @html.Html {
  page_shell(
    "自定义报表",
    "ANALYSIS / BUILDER",
    "选择数据主题、字段和筛选条件，保存为团队可复用的自定义报表。",
    [button(class="erp-primary-btn", "＋ 新建报表")],
    div <| [
      section(class="erp-builder-card") <| [
        span(class="erp-page-eyebrow", "REPORT BUILDER"),
        h2("从数据集开始"),
        div(class="erp-builder-options") <| [
          button(class="erp-option-card is-active", "项目与成本"),
          button(class="erp-option-card", "合同与付款"),
          button(class="erp-option-card", "销售与回款"),
          button(class="erp-option-card", "资金计划"),
        ],
        filter_bar("搜索字段，例如：项目名称、动态成本"),
      ],
      table_panel(
        "已保存报表",
        "共 12 个",
        data_table(
          [
            "报表名称", "数据集", "共享范围", "最近运行", "创建人",
            "状态",
          ],
          [
            [
              "项目成本月度变化", "项目与成本", "成本团队", "今天 08:10",
              "李明金", "正常",
            ],
            [
              "合同付款执行率", "合同与付款", "全集团", "昨天 19:42",
              "系统", "正常",
            ],
            [
              "销售去化漏斗", "销售与回款", "销售团队", "2026-07-11",
              "刘松", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn warning_view() -> @html.Html {
  page_shell(
    "异常预警中心",
    "ANALYSIS / WARNINGS",
    "集中处理成本偏差、项目延期、资金缺口、供应商和发票异常。",
    [
      button(class="erp-secondary-btn", "全部标记已读"),
      button(class="erp-primary-btn", "配置规则"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("未处理", "23", "高优先级 6", "metric-blue"),
        metric("本周新增", "8", "较上周 -3", "metric-blue"),
        metric("已关闭", "186", "关闭率 89.0%", "metric-green"),
      ],
      table_panel(
        "预警清单",
        "按优先级和更新时间",
        data_table(
          [
            "预警编号", "类型", "项目 / 对象", "预警内容", "触发时间",
            "责任人", "状态",
          ],
          [
            [
              "WARN-260713-006", "项目延期", "成都和锦里", "2# 楼砌体较计划晚 4 天",
              "今天 09:18", "陈志强", "待处理",
            ],
            [
              "WARN-260712-011", "成本偏差", "成都和锦里", "建安成本超目标 8.4%",
              "昨天 16:42", "李明金", "进行中",
            ],
            [
              "WARN-260711-004", "资金缺口", "重庆南山居", "8 月预计缺口 ¥180 万",
              "2026-07-11", "刘松", "待处理",
            ],
            [
              "WARN-260710-002", "发票异常", "04400193 2687", "销方税号待确认",
              "2026-07-10", "财务共享", "已完成",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn warning_rules_view() -> @html.Html {
  page_shell(
    "告警规则 DSL",
    "ANALYSIS / RULES",
    "用可审计的规则表达式配置阈值、通知对象和自动关闭条件。",
    [button(class="erp-primary-btn", "＋ 新建规则")],
    div <| [
      table_panel(
        "规则列表",
        "12 条内置规则 · 4 条自定义规则",
        data_table(
          [
            "规则名称", "对象", "触发条件", "通知方式", "最近触发",
            "启用状态",
          ],
          [
            [
              "成本偏差超过 5%", "项目成本", "dynamic_cost / target_cost > 1.05",
              "站内信 + 企业微信", "今天 09:18", "启用",
            ],
            [
              "任务延期超过 3 天", "项目任务", "today - planned_end > 3d",
              "站内信", "今天 08:42", "启用",
            ],
            [
              "发票税号缺失", "进项发票", "seller_tax_no is null", "待办",
              "昨天 16:20", "启用",
            ],
            [
              "现金流缺口", "资金计划", "forecast_balance < 0", "邮件 + 站内信",
              "2026-07-11", "停用",
            ],
          ],
        ),
      ),
      section(class="erp-code-card") <| [
        span(class="erp-page-eyebrow", "RULE PREVIEW"),
        p(
          "when project.cost_variance_ratio > 0.05 then warning('成本偏差', owner=project.cost_owner)",
        ),
      ],
    ],
  )
}

///|
fn cashflow_view() -> @html.Html {
  page_shell(
    "现金流预测",
    "FINANCE / CASHFLOW",
    "综合回款、融资和付款计划，预测未来 90 天的每日资金余额和缺口。",
    [
      button(class="erp-secondary-btn", "切换 30 / 90 天"),
      button(class="erp-secondary-btn", "导出预测"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("当前余额", "¥4,280 万", "截至今天", "metric-blue"),
        metric("90 天流入", "¥8,620 万", "回款 + 融资", "metric-green"),
        metric("90 天流出", "¥9,180 万", "工程 + 费用", "metric-blue"),
        metric("最低余额", "¥380 万", "8 月 18 日", "metric-blue"),
      ],
      table_panel(
        "滚动现金流",
        "未来 12 周",
        data_table(
          [
            "周次", "期初余额", "预计流入", "预计流出", "期末余额",
            "最大支出", "风险",
          ],
          [
            [
              "W29 · 07/13", "¥4,280 万", "¥1,260 万", "¥1,180 万", "¥4,360 万",
              "工程款", "正常",
            ],
            [
              "W30 · 07/20", "¥4,360 万", "¥820 万", "¥1,560 万", "¥3,620 万",
              "土地款", "关注",
            ],
            [
              "W31 · 07/27", "¥3,620 万", "¥1,180 万", "¥1,920 万", "¥2,880 万",
              "建安款", "关注",
            ],
            [
              "W32 · 08/03", "¥2,880 万", "¥1,460 万", "¥2,420 万", "¥1,920 万",
              "工程款", "关注",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn form_field(
  label_text : String,
  value : String,
  placeholder : String,
) -> @html.Html {
  div(class="erp-form-field") <| [
    label(class="erp-field-label", label_text),
    input(
      input_type=@html.InputType::Text,
      value~,
      placeholder~,
      class="erp-form-input",
    ),
  ]
}

///|
fn detail_toolbar(
  emit : @rabbita.Emit[Msg],
  back_path : String,
  action_label : String,
) -> @html.Html {
  div(class="erp-detail-toolbar") <| [
    nav_button(emit, back_path, "erp-ghost-btn", "‹ 返回列表"),
    nav_button(emit, back_path, "erp-primary-btn", action_label),
  ]
}

///|
fn project_detail_runtime_table(model : Model) -> @html.Html {
  match model.project_detail {
    Some(row) =>
      table_panel(
        "PostgreSQL 项目生命周期",
        model.project_note + " · 项目与任务导入记录保持只读",
        data_table(
          [
            "项目 ID", "项目", "当前阶段", "状态", "开始日期", "任务数",
            "来源", "生命周期",
          ],
          [
            [
              row.project_id,
              row.project_name,
              row.current_stage,
              row.proj_status,
              row.begin_date,
              row.task_count,
              row.source_kind,
              row.lifecycle_text,
            ],
          ],
        ),
      )
    None =>
      div(class="erp-runtime-empty", "等待 PostgreSQL 项目详情投影")
  }
}

///|
fn project_detail_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "项目全周期",
    "PROJECT DETAIL",
    "成都和锦里 · CD-HJL · 记录项目主数据、生命周期、计划、合同、成本与进度。",
    [detail_toolbar(emit, "/projects", "保存项目")],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.projects_loaded {
            "PostgreSQL 项目详情已连接"
          } else {
            "项目详情读模型"
          },
        ),
        span(" · " + model.project_note),
      ]),
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("项目基本信息"),
          span(class="erp-status-tag is-success", "开发建设"),
        ],
        div(class="erp-form-grid") <| [
          form_field("项目编码", "CD-HJL", "项目编码"),
          form_field("项目名称", "成都和锦里", "项目名称"),
          form_field("项目简称", "和锦里", "项目简称"),
          form_field("所属公司", "成都公司", "所属公司"),
          form_field("开始日期", "2024-03-18", "YYYY-MM-DD"),
          form_field("当前阶段", "开发建设", "项目阶段"),
        ],
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "项目概览"),
        button(class="erp-tab", "项目计划"),
        button(class="erp-tab", "合同与成本"),
        button(class="erp-tab", "工程进度"),
      ],
      table_panel(
        "生命周期节点",
        "变更均需保留操作人和证据",
        data_table(
          [
            "阶段", "计划日期", "实际日期", "责任人", "状态", "证据",
          ],
          [
            [
              "立项", "2024-01-15", "2024-01-15", "集团投资部", "已完成",
              "立项批复",
            ],
            [
              "规划设计", "2024-06-30", "2024-07-08", "设计管理部", "已完成",
              "设计审查",
            ],
            [
              "开发建设", "2025-01-01", "2025-01-08", "工程管理部", "进行中",
              "施工许可证",
            ],
            [
              "销售去化", "2026-08-01", "", "营销管理部", "待处理", "开盘计划",
            ],
          ],
        ),
      ),
      project_detail_runtime_table(model),
    ],
  )
}

///|
fn contract_detail_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let fallback = fallback_contract_rows()[0]
  let draft_row = {
    ..fallback,
    contract_id: model.contract_id,
    contract_code: if model.contract_id == "CT-RABBITA-LOCAL" {
      "HT-RABBITA-LOCAL"
    } else {
      fallback.contract_code
    },
    contract_name: if model.contract_id == "CT-RABBITA-LOCAL" {
      "成都项目主体结构施工合同"
    } else {
      fallback.contract_name
    },
    project_id: if model.contract_id == "CT-RABBITA-LOCAL" {
      "CD-HJL"
    } else {
      fallback.project_id
    },
    project_name: if model.contract_id == "CT-RABBITA-LOCAL" {
      "成都和锦里"
    } else {
      fallback.project_name
    },
    supplier_id: if model.contract_id == "CT-RABBITA-LOCAL" {
      "supplier-rabbita"
    } else {
      fallback.supplier_id
    },
    supplier_name: if model.contract_id == "CT-RABBITA-LOCAL" {
      "示例建设供应商"
    } else {
      fallback.supplier_name
    },
    amount_minor: if model.contract_id == "CT-RABBITA-LOCAL" {
      "4860000000"
    } else {
      fallback.amount_minor
    },
    amount_display: if model.contract_id == "CT-RABBITA-LOCAL" {
      "¥48,600,000.00"
    } else {
      fallback.amount_display
    },
    sign_date: if model.contract_id == "CT-RABBITA-LOCAL" {
      "2026-07-13"
    } else {
      fallback.sign_date
    },
    state: model.contract_state,
  }
  let row = match model.contract_detail {
    Some(value) => value
    None => draft_row
  }
  let actions : Array[@html.Html] = [
    nav_button(emit, "/contracts", "erp-ghost-btn", "‹ 返回列表"),
  ]
  if row.contract_id == "CT-RABBITA-LOCAL" && model.contract_detail is None {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateContract),
        "保存草稿",
      ),
    )
  }
  if model.contract_state == "draft" {
    actions.push(
      button(
        class="erp-primary-btn",
        on_click=emit(SubmitContract),
        "提交审批",
      ),
    )
  } else if model.contract_state == "submitted" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(RejectContract),
        "退回补充",
      ),
    )
    actions.push(
      button(
        class="erp-primary-btn",
        on_click=emit(ApproveContract),
        "批准合同",
      ),
    )
  } else if model.contract_state == "rejected" {
    actions.push(
      button(
        class="erp-primary-btn",
        on_click=emit(ResubmitContract),
        "重新提交",
      ),
    )
  }
  let milestone_rows : Array[Array[String]] = []
  for milestone in model.contract_milestones {
    milestone_rows.push([
      milestone.node_name + " · " + milestone.milestone_id,
      milestone.trigger_type,
      milestone.plan_amount_display,
      "—",
      milestone.plan_pct_bps + " bps",
      "已导入",
    ])
  }
  let milestones = if milestone_rows.length() > 0 {
    milestone_rows
  } else {
    [
      [
        "预付款", "合同生效", "¥4,860,000", "¥4,860,000", "2026-07-05",
        "已完成",
      ],
      [
        "主体结构 30%", "工程进度确认", "¥9,720,000", "¥7,940,000", "2026-08-15",
        "进行中",
      ],
      [
        "主体封顶", "验收通过", "¥14,580,000", "¥0", "2026-11-30", "待处理",
      ],
    ]
  }
  page_shell(
    if row.contract_id == "CT-RABBITA-LOCAL" && model.contract_detail is None {
      "新建合同"
    } else {
      "合同详情"
    },
    "CONTRACT DETAIL",
    "{row.contract_code} · {row.contract_name} · {row.project_name}",
    actions,
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("合同基本信息"),
          span(
            class="erp-status-tag is-pending",
            contract_state_label(model.contract_state),
          ),
          span(
            class="erp-source-note",
            model.contract_note +
            " · " +
            row.currency +
            " · " +
            row.source_kind +
            " · " +
            row.milestone_count +
            " 个付款节点",
          ),
        ],
        div(class="erp-form-grid") <| [
          form_field("合同编号", row.contract_code, "合同编号"),
          form_field("合同名称", row.contract_name, "合同名称"),
          form_field("所属项目", row.project_name, "项目"),
          form_field("供应商", row.supplier_name, "供应商"),
          form_field("合同金额", row.amount_display, "金额(元)"),
          form_field("币种", row.currency, "币种"),
          form_field("签订日期", row.sign_date, "YYYY-MM-DD"),
        ],
      ],
      table_panel(
        "付款节点",
        "合同金额 {row.amount_display} · 已付款 {row.paid_amount_display}",
        data_table(
          [
            "节点", "触发条件", "计划金额", "实际付款", "计划日期",
            "状态",
          ],
          milestones,
        ),
      ),
    ],
  )
}

///|
fn expense_editor_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  detail : Bool,
) -> @html.Html {
  let title = if detail { "报销详情" } else { "新建报销" }
  let action = if detail { "保存修改" } else { "提交审批" }
  let actions : Array[@html.Html] = [
    nav_button(emit, "/expenses", "erp-ghost-btn", "‹ 返回列表"),
  ]
  if detail {
    actions.push(button(class="erp-primary-btn", action))
  } else {
    if model.expense_state == "未创建" ||
      model.expense_state == "草稿" ||
      model.expense_state == "命令失败" {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(CreateExpense),
          "保存草稿",
        ),
      )
    }
    if model.expense_state == "草稿" {
      actions.push(
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitExpense),
          "提交审批",
        ),
      )
    }
    if model.expense_state == "已提交" {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(RejectExpense),
          "退回补充",
        ),
      )
      actions.push(
        button(
          class="erp-primary-btn",
          on_click=emit(ApproveExpense),
          "批准报销",
        ),
      )
    } else if model.expense_state == "已驳回" {
      actions.push(
        button(
          class="erp-primary-btn",
          on_click=emit(ResubmitExpense),
          "重新提交",
        ),
      )
    }
  }
  page_shell(
    title,
    "FINANCE / EXPENSE FORM",
    "差旅、招待和日常费用均需关联项目、费用科目与附件证据。",
    actions,
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("报销信息"),
          if detail {
            span(class="erp-status-tag is-pending", "审批中")
          } else {
            span(class="erp-info-tag", model.expense_state)
          },
          if detail {
            @html.nothing
          } else {
            span(class="erp-source-note", model.expense_note)
          },
        ],
        div(class="erp-form-grid") <| [
          form_field(
            "报销单号",
            if detail {
              "EXP-260712-008"
            } else {
              model.expense_id
            },
            "报销单号",
          ),
          form_field("费用类型", "差旅费", "费用类型"),
          form_field("费用摘要", "成都项目现场出差", "摘要"),
          form_field("费用金额", "8560", "金额(元)"),
          form_field("发生日期", "2026-07-12", "YYYY-MM-DD"),
          form_field("关联项目", "成都和锦里", "项目"),
          form_field("费用科目", "差旅交通", "费用科目"),
          form_field("付款方式", "个人垫付", "付款方式"),
        ],
      ],
      if detail ||
        model.expense_state == "草稿" ||
        model.expense_state == "未创建" {
        @html.nothing
      } else {
        div(class="erp-command-receipt") <| [
          strong("命令服务状态"),
          span(model.expense_note),
        ]
      },
      table_panel(
        "附件与分摊",
        "支持发票、行程单和费用拆分",
        data_table(
          [
            "附件名称", "类型", "金额", "上传人", "验真状态", "操作",
          ],
          [
            [
              "成都出差发票-01.pdf", "增值税发票", "¥3,280", "程玉哲",
              "已验真", "预览",
            ],
            [
              "高铁票-往返.zip", "行程凭证", "¥1,260", "程玉哲", "待确认",
              "预览",
            ],
            [
              "住宿发票-02.pdf", "增值税发票", "¥4,020", "程玉哲", "已验真",
              "预览",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn loan_state_label(state : String) -> String {
  match state {
    "Draft" => "草稿"
    "Approving" => "审批中"
    "Approved" => "已批准"
    "Rejected" => "已驳回"
    "Voided" => "已作废"
    _ => state
  }
}

///|
fn loan_editor_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  detail : Bool,
) -> @html.Html {
  let title = if detail { "借款详情" } else { "新建借款" }
  let is_local = model.loan_id == "LOAN-RABBITA-LOCAL"
  let actions : Array[@html.Html] = [
    nav_button(emit, "/loans", "erp-ghost-btn", "‹ 返回列表"),
  ]
  if !detail {
    if model.loan_state == "new" || model.loan_state == "error" {
      actions.push(
        button(
          class="erp-primary-btn",
          on_click=emit(CreateLoan),
          "保存借款草稿",
        ),
      )
    }
  } else if is_local {
    if model.loan_state == "Draft" {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(UpdateLoan),
          "保存修改",
        ),
      )
      actions.push(
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitLoan),
          "提交审批",
        ),
      )
    }
    if model.loan_state == "Draft" || model.loan_state == "Rejected" {
      actions.push(
        button(class="erp-danger-btn", on_click=emit(VoidLoan), "作废借款"),
      )
    }
  }
  let status_label = if model.loan_state == "Imported" {
    "导入只读"
  } else if model.loan_state == "new" {
    "草稿"
  } else {
    loan_state_label(model.loan_state)
  }
  let note = if model.loan_state == "Imported" {
    "来源 ERP 导入 · 只读，不提供本地写入"
  } else {
    model.loan_command_note
  }
  page_shell(
    title,
    "FINANCE / LOAN FORM",
    "备用金和差旅借款需要明确用途、归还日期和可核销预算。",
    actions,
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("借款信息"),
        span(class="erp-status-tag is-pending", status_label),
        span(class="erp-source-note", note),
      ],
      div(class="erp-form-grid") <| [
        form_field(
          "借款单号",
          if detail {
            model.loan_id
          } else {
            "自动生成"
          },
          "借款单号",
        ),
        form_field("借款类型", "差旅借款", "借款类型"),
        form_field("借款用途", "沈阳项目会议", "用途"),
        form_field("借款金额", "8000", "金额(元)"),
        form_field("预计归还", "2026-07-30", "YYYY-MM-DD"),
        form_field("关联项目", "沈阳和山苑", "项目"),
        form_field("核销科目", "差旅交通", "核销科目"),
        form_field("收款账户", "个人备用金", "账户"),
      ],
      if detail && is_local && model.loan_state == "error" {
        div(class="erp-command-receipt") <| [
          strong("命令服务状态"),
          span(model.loan_command_note),
        ]
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn provider_detail_view(emit : @rabbita.Emit[Msg]) -> @html.Html {
  page_shell(
    "供应商详情",
    "SRM / PROVIDER DETAIL",
    "SUP-00018 · 中建三局集团有限公司 · 工程施工",
    [detail_toolbar(emit, "/srm/providers", "保存供应商")],
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("供应商基本信息"),
          span(class="erp-status-tag is-success", "正常"),
        ],
        div(class="erp-form-grid") <| [
          form_field("供应商编码", "SUP-00018", "供应商编码"),
          form_field(
            "供应商名称", "中建三局集团有限公司", "供应商名称",
          ),
          form_field("类别", "工程施工", "供应商类别"),
          form_field(
            "统一社会信用代码", "91110000MA00XXXXXX", "统一社会信用代码",
          ),
          form_field("联系人", "周强", "联系人"),
          form_field("联系电话", "138****9001", "联系电话"),
        ],
      ],
      table_panel(
        "合作与评价",
        "最近评价 A · 低风险",
        data_table(
          [
            "项目", "合同数", "合同金额", "已付款", "最近评价", "履约状态",
          ],
          [
            [
              "成都和锦里", "8", "¥86,200,000", "¥24,600,000", "A", "正常",
            ],
            [
              "天津海教园一期", "3", "¥18,600,000", "¥6,280,000", "A", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn sales_revenues_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "销售回款 (R6)",
    "SALES / REVENUES",
    "登记销售回款、到账日期、付款类型与销售合同号，保持回款与应收台帐可追溯。",
    [nav_button(emit, "/sales/revenues", "erp-primary-btn", "＋ 新增回款")],
    div <| [
      sales_runtime_banner(model, "revenues"),
      sales_projection_table(model, "revenues"),
      div(class="erp-stat-grid") <| [
        metric("本月到账", "¥6,820 万", "126 笔", "metric-blue"),
        metric(
          "年度累计", "¥4.28 亿", "完成年度目标 68%", "metric-green",
        ),
        metric("待确认", "12", "金额 ¥380 万", "metric-blue"),
      ],
      filter_bar("回款编号 / 客户 / 销售合同号"),
      table_panel(
        "回款登记",
        "按到账日期倒序",
        data_table(
          [
            "回款编号", "客户", "金额", "到账日期", "状态", "付款类型",
            "销售合同号", "R 编码",
          ],
          [
            [
              "REV-260713-018", "陈敏", "¥1,971,320", "2026-07-13", "已确认",
              "首付", "SC-260713-004", "R-2026-0713",
            ],
            [
              "REV-260712-026", "刘洋", "¥652,000", "2026-07-12", "已确认",
              "按揭", "SC-260712-016", "R-2026-0712",
            ],
            [
              "REV-260710-011", "张伟", "¥420,000", "2026-07-10", "待确认",
              "首付", "SC-260710-008", "R-2026-0710",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn marketing_view() -> @html.Html {
  page_shell(
    "营销管理",
    "SALES / MARKETING",
    "管理营销活动、投放记录、渠道与营销物料，预算和实际花费挂接 CBS。",
    [button(class="erp-primary-btn", "＋ 新建营销活动")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("营销活动数", "18", "运行中 6 个", "metric-blue"),
        metric("投放总额", "¥1,286 万", "本年度", "metric-blue"),
        metric("有效线索", "3,842", "转化率 12.6%", "metric-green"),
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "营销活动"),
        button(class="erp-tab", "投放记录"),
        button(class="erp-tab", "营销渠道"),
        button(class="erp-tab", "营销物料"),
      ],
      table_panel(
        "营销活动",
        "v3.8 · R19 营销费用",
        data_table(
          [
            "编号", "活动名称", "类型", "预算(元)", "已花(元)", "周期",
            "状态", "挂 CBS",
          ],
          [
            [
              "CAM-260701", "成都和锦里开盘推广", "开盘活动", "¥1,800,000",
              "¥680,000", "2026-07-01 ~ 08-20", "运行中", "04-03",
            ],
            [
              "CAM-260615", "南山居线上投放", "线上获客", "¥960,000",
              "¥812,000", "2026-06-15 ~ 07-31", "运行中", "04-03",
            ],
            [
              "CAM-260501", "沈阳和山苑暖场", "客户活动", "¥420,000",
              "¥420,000", "2026-05-01 ~ 06-30", "已结束", "04-03",
            ],
          ],
        ),
      ),
      table_panel(
        "投放记录",
        "渠道效果和实际花费",
        data_table(
          [
            "编号", "所属活动", "投放渠道", "金额(元)", "投放日",
            "曝光", "线索",
          ],
          [
            [
              "PLC-260712-008", "成都和锦里开盘推广", "抖音", "¥180,000",
              "2026-07-12", "286,000", "420",
            ],
            [
              "PLC-260708-004", "南山居线上投放", "SEM", "¥96,000", "112,000",
              "186",
            ],
            [
              "PLC-260701-012", "成都和锦里开盘推广", "渠道分销", "¥240,000",
              "—", "98",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn inbox_view() -> @html.Html {
  page_shell(
    "站内信",
    "SYSTEM / INBOX",
    "统一接收审批、预警、系统和业务通知，保留已读状态与业务关联。",
    [button(class="erp-secondary-btn", "全部标记已读")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("未读消息", "8", "高优先级 2", "metric-blue"),
        metric("本周新增", "26", "较上周 +4", "metric-blue"),
        metric("业务通知", "18", "审批 / 预警", "metric-green"),
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "未读 (8)"),
        button(class="erp-tab", "全部消息"),
        button(class="erp-tab", "审批通知"),
        button(class="erp-tab", "系统通知"),
      ],
      table_panel(
        "消息列表",
        "按时间倒序",
        data_table(
          ["", "标题", "内容", "业务", "时间", "状态", "操作"],
          [
            [
              "●", "付款申请待审批", "成都和锦里主体结构施工合同付款申请 ¥128 万",
              "付款申请", "今天 09:18", "未读", "查看",
            ],
            [
              "●", "项目延期预警", "2# 楼砌体工程较计划晚 4 天，请确认处理方案",
              "异常预警", "今天 08:42", "未读", "查看",
            ],
            [
              "", "报销已通过", "EXP-260628-011 已完成审批并进入付款队列",
              "我的报销", "昨天 16:20", "已读", "查看",
            ],
            [
              "", "系统维护通知", "PostgreSQL 读模型已完成本次迁移校验",
              "系统", "2026-07-11", "已读", "查看",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn attachments_view() -> @html.Html {
  page_shell(
    "附件中心",
    "SYSTEM / ATTACHMENTS",
    "搜索合同、发票、报销和项目证据，查看 AI 识别状态与业务关联。",
    [button(class="erp-primary-btn", "＋ 上传附件")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("附件总数", "2,846", "本月新增 186", "metric-blue"),
        metric("待 OCR", "14", "需人工确认 6", "metric-blue"),
        metric("已关联", "98.4%", "来源可追溯", "metric-green"),
      ],
      filter_bar("文件名 / 业务类型 / 上传人"),
      table_panel(
        "附件搜索",
        "最近上传",
        data_table(
          [
            "文件名", "业务", "大小", "类型", "上传人", "上传时间",
            "AI", "操作",
          ],
          [
            [
              "主体结构施工合同.pdf", "合同 HT-CD-260701", "2.4 MB", "application/pdf",
              "陈志强", "今天 09:12", "已识别", "预览 / 下载",
            ],
            [
              "成都出差发票-01.pdf", "报销 EXP-260712-008", "428 KB", "application/pdf",
              "程玉哲", "昨天 16:42", "已验真", "预览 / 下载",
            ],
            [
              "工程进度照片-2#-0712.zip", "进度报告 rep-001", "18.6 MB",
              "application/zip", "王工", "昨天 15:20", "—", "预览 / 下载",
            ],
            [
              "销售合同扫描件.jpg", "签约 SC-260713-004", "1.1 MB", "image/jpeg",
              "刘松", "2026-07-11", "待确认", "预览 / 下载",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn health_table_status(status : String) -> String {
  if status == "rows_imported" {
    "已导入"
  } else if status == "no_rows_in_export" {
    "空/缺失"
  } else {
    status
  }
}

///|
fn health_table_panel(model : Model) -> @html.Html {
  if model.health_loaded {
    let rows : Array[Array[String]] = []
    for row in model.health_table_rows {
      rows.push([
        row.table,
        row.row_count,
        "PostgreSQL 控制导出 · " + row.source_kind,
        health_table_status(row.source_status),
      ])
    }
    table_panel(
      "表行数（源覆盖 " + model.health_source_table_count + " 张）",
      model.health_note,
      data_table(["表名", "行数", "来源", "状态"], rows),
    )
  } else {
    table_panel(
      "表行数(主要 21 张)",
      "最近探测 2026-07-13 09:40 · " + model.health_note,
      data_table(["表名", "行数", "说明", "状态"], [
        ["company_record", "120", "原始 ERP 证据 envelope", "正常"],
        [
          "company_aggregate_projection", "109", "公司域聚合投影", "正常",
        ],
        [
          "company_accounting_event_link", "7", "来源到会计事件链接", "正常",
        ],
        [
          "company_migration_receipt", "19", "迁移批次与回放凭证", "正常",
        ],
      ]),
    )
  }
}

///|
fn health_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let health_status_class = if model.health_loaded {
    "erp-status-tag is-success"
  } else {
    "erp-status-tag is-warning"
  }
  let health_status_label = if model.health_loaded {
    "源覆盖已读取"
  } else {
    "设计快照"
  }
  let stats = if model.health_loaded {
    div(class="erp-stat-grid") <| [
      metric(
        "源覆盖表",
        model.health_source_table_count,
        "空/缺表 " + model.health_missing_table_count,
        "metric-blue",
      ),
      metric(
        "BPM 实例",
        model.health_bpm_instance_count,
        "源数据计数 · 只读",
        "metric-green",
      ),
      metric(
        "BPM 动作",
        model.health_bpm_action_count,
        "授权状态：非授权",
        "metric-blue",
      ),
    ]
  } else {
    div(class="erp-stat-grid") <| [
      metric("启动时长", "18d 06h", "最近重启 06-25", "metric-blue"),
      metric("内存 RSS", "486 MB", "上限 2 GB", "metric-green"),
      metric("数据库大小", "1.82 GB", "增长 +4.6%", "metric-blue"),
    ]
  }
  let status_items = if model.health_loaded {
    [
      div(class="erp-health-item") <| [
        span("PostgreSQL 源覆盖"),
        strong("已读取"),
        span(
          model.health_source_table_count +
          " 张表 · 空/缺 " +
          model.health_missing_table_count,
        ),
      ],
      div(class="erp-health-item") <| [
        span("读模型 API"),
        strong("正常"),
        span("健康覆盖响应已返回"),
      ],
      div(class="erp-health-item") <| [
        span("BPM 实例池"),
        strong(model.health_bpm_instance_count + " 条"),
        span("源数据只读快照"),
      ],
      div(class="erp-health-item") <| [
        span("BPM 动作授权"),
        strong("非授权"),
        span(model.health_bpm_action_count + " 条源动作"),
      ],
    ]
  } else {
    [
      div(class="erp-health-item") <| [
        span("PostgreSQL 主库"),
        strong("快照"),
        span("等待源覆盖读模型"),
      ],
      div(class="erp-health-item") <| [
        span("读模型 API"),
        strong("未加载"),
        span("当前显示设计快照"),
      ],
      div(class="erp-health-item") <| [
        span("附件存储"),
        strong("快照"),
        span("未接入源探针"),
      ],
      div(class="erp-health-item") <| [
        span("通知队列"),
        strong("快照"),
        span("未接入源探针"),
      ],
    ]
  }
  page_shell(
    "系统健康",
    "SYSTEM / HEALTH",
    "查看服务、数据库、存储和消息队列的当前状态，所有指标来自只读运维探针。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/system-health")),
        "刷新探针",
      ),
    ],
    div <| [
      stats,
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("服务状态"),
          span(class=health_status_class, health_status_label),
        ],
        div(class="erp-health-grid") <| status_items,
      ],
      health_table_panel(model),
    ],
  )
}

///|
fn user_roster_table(model : Model) -> @html.Html {
  if model.users_loaded {
    let rows : Array[Array[String]] = []
    for row in model.user_roster_rows {
      let organization = if row.dept_name != "—" &&
        row.dept_name != row.bu_name {
        row.bu_name + " / " + row.dept_name
      } else {
        row.bu_name
      }
      let role_display = if row.roles == "—" {
        "— (" + row.roles_source_status + ")"
      } else {
        row.roles
      }
      rows.push([
        row.user_code,
        row.emp_name,
        organization,
        role_display,
        row.super_user,
        row.enabled,
        "只读 · " + row.source_kind,
      ])
    }
    table_panel(
      "用户管理",
      model.users_note,
      data_table(
        [
          "账号", "姓名", "组织", "角色", "超级用户", "状态", "操作",
        ],
        rows,
      ),
    )
  } else {
    table_panel(
      "用户管理",
      "5 个已迁移身份 · 密码由认证服务管理",
      data_table(
        [
          "账号", "姓名", "组织", "角色", "超级用户", "状态", "操作",
        ],
        [
          [
            "admin", "系统管理员", "集团总部", "超级管理员", "是(证据)",
            "启用", "编辑 / 重置",
          ],
          [
            "chengyuzhe", "程玉哲", "天津公司", "报销发起人", "否",
            "启用", "编辑 / 禁用",
          ],
          [
            "tianguanglei", "田光磊", "天津公司", "费用使用人", "否",
            "启用", "编辑 / 禁用",
          ],
          [
            "limingjin", "李明金", "天津公司", "部门负责人", "否", "启用",
            "编辑 / 禁用",
          ],
          [
            "liusong", "刘松", "集团总部", "综管负责人", "否", "启用",
            "编辑 / 禁用",
          ],
        ],
      ),
    )
  }
}

///|
fn users_view(model : Model) -> @html.Html {
  page_shell(
    "用户/角色管理",
    "SYSTEM / USERS",
    "管理用户身份、组织范围和角色权限；超级用户标记不会直接迁移为目标权限。",
    [button(class="erp-primary-btn", "＋ 新建用户")],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "用户管理"),
        button(class="erp-tab", "角色管理"),
        button(class="erp-tab", "权限目录"),
      ],
      user_roster_table(model),
      table_panel(
        "角色管理",
        if model.users_loaded {
          "角色源表未随导出 · 仅显示离线设计快照，不用于授权"
        } else {
          "按范围分配能力，不直接授予会计或付款权限"
        },
        data_table(
          [
            "编码", "名称", "描述", "数据范围", "权限数", "用户数",
            "状态",
          ],
          [
            [
              "super_admin", "超级管理员", "平台配置与运维", "全集团",
              "86", "1", "正常",
            ],
            [
              "expense_user", "费用使用人", "发起报销和借款", "所属组织",
              "12", "2", "正常",
            ],
            [
              "department_owner", "部门负责人", "部门预算与审批", "所属部门",
              "18", "1", "正常",
            ],
            [
              "general_manager", "综管负责人", "业务流程复核", "集团 / 项目",
              "24", "1", "正常",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn profile_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "个人中心",
    "SYSTEM / PROFILE",
    "管理个人资料、密码、通知订阅以及本人发起的业务单据。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/profile")),
        "刷新资料",
      ),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "基本信息"),
        button(class="erp-tab", "修改密码"),
        button(class="erp-tab", "我的订阅"),
        button(class="erp-tab", "我的发起 (6)"),
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("基本信息"),
          span(
            class="erp-info-tag",
            if model.profile_loaded {
              model.profile_source_kind
            } else {
              "Giant Claw · " + model.profile_source_kind
            },
          ),
        ],
        div(class="erp-form-grid") <| [
          form_field("账号", model.profile_user_code, "用户编码"),
          form_field("用户 ID", model.profile_user_id, "内部标识"),
          form_field("姓名", model.profile_emp_name, "姓名"),
          form_field("显示名", model.profile_user_name, "用户名称"),
          form_field("所属公司", model.profile_bu_name, "所属公司"),
          form_field("所属部门", model.profile_dept_name, "所属部门"),
          form_field("管理员", model.profile_super_user, "超级用户"),
          form_field("状态", model.profile_enabled, "启用状态"),
          form_field("联系电话", "138****0000", "联系电话"),
          form_field("最后登录", model.profile_last_login, "最后登录"),
        ],
      ],
      p(
        class="erp-dashboard-note",
        model.profile_note +
        " · 资料/密码/偏好写入仍需生产身份与命令授权",
      ),
      table_panel(
        "我的订阅",
        "异常预警通知规则",
        data_table(
          ["规则", "业务", "级别下限", "通道", "状态", "操作"],
          [
            [
              "cost_variance", "成本", "warning", "站内信 + 企业微信", "启用",
              "编辑",
            ],
            [
              "task_overdue", "项目任务", "warning", "站内信", "启用", "编辑",
            ],
            [
              "cash_gap", "资金计划", "critical", "邮件 + 站内信", "启用",
              "编辑",
            ],
          ],
        ),
      ),
      table_panel(
        "我的发起",
        "报销 / 借款 / 付款申请",
        data_table(
          ["编号", "主题 / 事由", "金额", "状态", "日期", "操作"],
          [
            [
              "EXP-260712-008", "成都项目现场出差", "¥8,560", "审批中",
              "2026-07-12", "查看",
            ],
            [
              "LOAN-260713-001", "沈阳项目会议", "¥8,000", "审批中", "2026-07-13",
              "查看",
            ],
            [
              "PAY-260713-006", "主体结构施工合同付款", "¥1,280,000",
              "审批中", "2026-07-13", "查看",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn notify_view() -> @html.Html {
  page_shell(
    "通知配置 / 订阅",
    "SYSTEM / NOTIFICATIONS",
    "配置站内信、邮件和 Webhook 的通知规则；敏感凭据只由生产密钥服务托管。",
    [button(class="erp-primary-btn", "＋ 新建规则")],
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("通知规则"),
          span(class="erp-info-tag", "只读迁移快照"),
        ],
        div(class="erp-form-grid") <| [
          form_field("规则", "cost_variance", "规则编码"),
          form_field("业务", "成本", "业务类型"),
          form_field("最低级别", "warning", "级别下限"),
          form_field("通道", "站内信,企业微信", "通道"),
          form_field("启用", "是", "启用状态"),
          form_field("发送时间", "实时", "发送时间"),
        ],
      ],
      table_panel(
        "通知队列",
        "最近发送记录",
        data_table(
          ["收件人", "主题", "入队时间", "状态", "操作"],
          [
            [
              "Giant Claw", "成本偏差超过 5% · 成都和锦里", "今天 09:18",
              "已发送", "查看",
            ],
            [
              "陈志强", "2# 楼任务延期", "今天 08:42", "已发送", "查看",
            ],
            [
              "刘松", "现金流缺口预测", "2026-07-11", "待发送", "重试",
            ],
          ],
        ),
      ),
      table_panel(
        "通知日志",
        "每日摘要",
        data_table(
          [
            "日期", "发送时间", "接收人数", "错误", "警告", "新增",
            "触发",
          ],
          [
            ["2026-07-13", "09:20", "5", "0", "2", "8", "定时摘要"],
            ["2026-07-12", "18:00", "5", "0", "4", "26", "定时摘要"],
          ],
        ),
      ),
    ],
  )
}

///|
fn ocr_view() -> @html.Html {
  page_shell(
    "OCR 配置",
    "SYSTEM / OCR",
    "配置发票、合同和身份证的 OCR 服务方，并在写入业务单据前保留人工确认。",
    [
      button(class="erp-secondary-btn", "测试连接"),
      button(class="erp-primary-btn", "保存配置"),
    ],
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("OCR 配置 / 测试"),
          span(class="erp-info-tag", "AI-4"),
        ],
        div(class="erp-form-grid") <| [
          form_field("服务方", "本地 PaddleOCR", "服务方"),
          form_field(
            "远程 OCR URL", "https://ocr.internal.example/v1", "远程 OCR URL",
          ),
          form_field(
            "API Key", "••••••••", "由密钥服务托管",
          ),
          form_field("合同识别", "启用", "合同识别"),
          form_field("发票识别", "启用", "发票识别"),
          form_field("人工确认阈值", "0.85", "置信度"),
        ],
      ],
      table_panel(
        "最近识别任务",
        "识别结果只产生草稿，不直接入账",
        data_table(
          ["任务", "文件", "类型", "字段数", "置信度", "状态"],
          [
            [
              "OCR-260713-018", "主体结构施工合同.pdf", "合同", "32", "0.96",
              "已完成",
            ],
            [
              "OCR-260712-008", "成都出差发票-01.pdf", "发票", "18", "0.91",
              "待确认",
            ],
            [
              "OCR-260711-004", "销售合同扫描件.jpg", "合同", "26", "0.78",
              "需复核",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn webhook_view() -> @html.Html {
  page_shell(
    "工单超期 Webhook",
    "SYSTEM / WEBHOOK",
    "为企业微信、飞书、钉钉配置工单超期通知；密钥和 URL 仅保留密文引用。",
    [button(class="erp-primary-btn", "保存配置")],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "企业微信"),
        button(class="erp-tab", "飞书"),
        button(class="erp-tab", "钉钉"),
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("企业微信配置"),
          span(class="erp-status-tag is-success", "已启用"),
        ],
        div(class="erp-form-grid") <| [
          form_field("启用", "是", "启用状态"),
          form_field(
            "Webhook URL", "https://qyapi.weixin.qq.com/••••", "Webhook URL",
          ),
          form_field(
            "密钥", "••••••••", "由密钥服务托管",
          ),
          form_field("超期阈值", "3 天", "工单超期"),
          form_field("通知范围", "项目任务", "业务范围"),
          form_field("重试策略", "3 次 / 5 分钟", "失败重试"),
        ],
      ],
      table_panel(
        "最近发送",
        "仅保留投递结果和摘要",
        data_table(
          [
            "平台", "事件", "发送时间", "状态", "重试次数", "摘要",
          ],
          [
            [
              "企业微信", "任务延期", "今天 08:42", "已发送", "0", "成都和锦里 2# 楼",
            ],
            [
              "飞书", "合同到期", "昨天 17:20", "已发送", "1", "供应商资质到期",
            ],
            [
              "钉钉", "资金缺口", "2026-07-11", "失败", "3", "重庆南山居 8 月预测",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn audit_runtime_table(model : Model) -> @html.Html {
  if model.audit_loaded {
    let rows : Array[Array[String]] = []
    for row in model.audit_rows {
      rows.push([
        row.log_id,
        row.created_at,
        row.emp_name,
        row.user_id,
        row.action,
        row.target_type,
        row.target_id,
        row.ip + " · " + row.source_kind,
      ])
    }
    let action_note = if model.audit_action_rows.length() == 0 {
      "无动作汇总"
    } else {
      let action = model.audit_action_rows[0]
      "动作 " +
      action.action +
      " × " +
      action.count +
      " · " +
      action.source_kind
    }
    table_panel(
      "审计日志（" + model.audit_total + " 条）",
      model.audit_note + " · " + action_note,
      data_table(
        [
          "ID", "时间", "用户", "user_id", "操作", "对象类型", "对象 ID",
          "IP / 来源",
        ],
        rows,
      ),
    )
  } else {
    table_panel(
      "审计日志",
      "只读 · append-only · " + model.audit_note,
      data_table(
        [
          "ID", "时间", "用户", "user_id", "操作", "对象类型", "对象 ID",
          "IP",
        ],
        [
          [
            "1", "2026-07-13 09:24", "系统管理员", "user-admin-0001", "登录",
            "identity", "user-admin-0001", "已脱敏",
          ],
          [
            "2", "2026-07-12 18:12", "系统管理员", "user-admin-0001", "更新通知配置",
            "notify_config", "cost_variance", "已脱敏",
          ],
          [
            "3", "2026-07-11 16:42", "程玉哲", "user-tgl-0001", "提交报销",
            "expense", "EXP-260712-008", "已脱敏",
          ],
          [
            "4", "2026-07-10 11:20", "李明金", "user-lmj-0001", "审批付款",
            "payment_apply", "PAY-260710-004", "已脱敏",
          ],
        ],
      ),
    )
  }
}

///|
fn audit_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "审计日志",
    "SYSTEM / AUDIT",
    "记录身份、权限、配置和业务对象变更；网络字段在迁移快照中按安全策略保留或脱敏。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/audit-log")),
        "刷新审计",
      ),
    ],
    div <| [
      filter_bar("用户 / 对象类型 / 对象 ID / 时间范围"),
      audit_runtime_table(model),
    ],
  )
}

///|
fn error_view() -> @html.Html {
  page_shell(
    "错误日志",
    "SYSTEM / ERRORS",
    "查看服务错误、HTTP 状态和业务上下文；原始网络标识不在公司投影中公开。",
    [button(class="erp-secondary-btn", "清理已处理")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("今日错误", "3", "较昨日 -4", "metric-blue"),
        metric("5xx", "1", "需运维关注", "metric-blue"),
        metric("已处理", "98.6%", "本周", "metric-green"),
      ],
      filter_bar("路径 / 方法 / 状态码 / 错误内容"),
      table_panel(
        "错误记录",
        "最近发生",
        data_table(
          ["ID", "时间", "方法", "路径", "状态码", "错误", "IP"],
          [
            [
              "ERR-260713-003", "今天 09:16", "GET", "/api/company/projections",
              "500", "projection query timeout", "已脱敏",
            ],
            [
              "ERR-260712-018", "昨天 17:20", "POST", "/api/ocr/recognize", "422",
              "confidence below threshold", "已脱敏",
            ],
            [
              "ERR-260711-004", "2026-07-11", "PUT", "/api/notify/config", "403",
              "authority denied", "已脱敏",
            ],
          ],
        ),
      ),
    ],
  )
}

///|
fn admin_dict_table(model : Model) -> @html.Html {
  if model.admin_dict_loaded {
    let rows : Array[Array[String]] = []
    for row in model.admin_dict_option_rows {
      rows.push([
        row.group_name,
        row.code,
        row.value,
        row.display_order,
        row.enabled,
        "只读 · " + row.source_kind,
      ])
    }
    let group_note = if model.admin_dict_group_rows.length() == 0 {
      model.admin_dict_note
    } else {
      let group = model.admin_dict_group_rows[0]
      "分组 " +
      group.group_name +
      " · " +
      group.enabled +
      "/" +
      group.total +
      " 启用 · " +
      group.source_kind +
      " · " +
      model.admin_dict_note
    }
    table_panel(
      "数据字典",
      group_note,
      data_table(
        ["分组", "编码", "值", "排序", "状态", "来源"],
        rows,
      ),
    )
  } else {
    table_panel(
      "数据字典",
      "系统参数和业务枚举 · " + model.admin_dict_note,
      data_table(["分组", "编码", "值", "排序", "状态", "操作"], [
        ["cost_subject", "CB-101", "建安工程", "1", "启用", "查看"],
        ["cost_subject", "CB-101-JZ", "主体建安", "2", "启用", "查看"],
        ["expense_proceeding", "travel", "差旅费", "1", "启用", "查看"],
        [
          "expense_proceeding", "entertainment", "业务招待费", "2", "启用",
          "查看",
        ],
      ]),
    )
  }
}

///|
fn admin_quality_table(model : Model) -> @html.Html {
  if model.admin_quality_loaded {
    let rows : Array[Array[String]] = []
    for row in model.admin_quality_rows {
      rows.push([row.rule, row.count, row.severity, row.status, row.source_kind])
    }
    table_panel(
      "数据质量看板",
      model.admin_quality_note,
      data_table(
        ["检查项", "异常数", "严重度", "状态", "来源"],
        rows,
      ),
    )
  } else {
    table_panel(
      "数据质量看板",
      model.admin_quality_note,
      data_table(["检查项", "规则", "异常数", "严重度", "状态"], [
        ["来源身份唯一性", "source_id 不重复", "0", "低", "通过"],
        [
          "投影来源可追溯", "source_snapshot + mapping", "0", "中", "通过",
        ],
        [
          "会计链接主键", "event/source/journal 唯一", "0", "高", "通过",
        ],
        [
          "任务依赖状态", "父任务完成度约束", "2", "高", "需复核",
        ],
      ]),
    )
  }
}

///|
fn admin_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "数据后台",
    "SYSTEM / ADMIN",
    "为管理员提供数据字典、质量看板、流程运行和 RBAC 只读审查入口。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/admin")),
        "刷新数据",
      ),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "数据字典"),
        button(class="erp-tab", "数据质量看板"),
        button(class="erp-tab", "审计日志"),
        button(class="erp-tab", "系统健康"),
        button(class="erp-tab", "角色权限"),
      ],
      admin_dict_table(model),
      admin_quality_table(model),
    ],
  )
}

///|
fn business_view(
  path : String,
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if path.has_prefix("/share/") {
    share_view(path)
  } else if path.has_prefix("/projects/") {
    project_detail_view(emit, model)
  } else if path.has_prefix("/contracts/") {
    contract_detail_view(emit, model)
  } else if path.has_prefix("/expenses/") && path != "/expenses/new" {
    expense_editor_view(emit, model, true)
  } else if path.has_prefix("/loans/") && path != "/loans/new" {
    loan_editor_view(emit, model, true)
  } else if path.has_prefix("/srm/providers/") {
    provider_detail_view(emit)
  } else {
    match path {
      "/dashboard-v3" => dashboard_view(emit, initial_model())
      "/cockpit" => dashboard_view(emit, initial_model())
      "/ai-hub" => ai_hub_view()
      "/ai-stats" => ai_stats_view()
      "/projects" => project_view(emit, model)
      "/projects/CD-HJL" => project_detail_view(emit, model)
      "/project-plan" => project_plan_view(emit, model)
      "/project/progress" => progress_view(emit, model)
      "/tasks" => tasks_view(model)
      "/sales/customers" => sales_customers_view(model)
      "/sales/subscriptions" => sales_subscriptions_view(emit, model)
      "/sales/contracts" => sales_contracts_view(emit, model)
      "/sales/mortgages" => sales_mortgages_view(model)
      "/sales/revenues" => sales_revenues_view(emit, model)
      "/marketing" => marketing_view()
      "/contracts" => contracts_view(emit, model)
      "/contracts/HT-CD-260701" => contract_detail_view(emit, model)
      "/payment-applies" => payment_applies_view(emit, model)
      "/cost-dashboard-v3" => cost_dashboard_view()
      "/investment" => investment_view(emit, model)
      "/dynamic-cost" => dynamic_cost_view(emit, model)
      "/tender" => tender_view(emit, model)
      "/srm/providers" => srm_providers_view(emit, model)
      "/srm/providers/SUP-00018" => provider_detail_view(emit)
      "/srm/risk-board" => srm_risk_view()
      "/cbs/dict" => cbs_view(path)
      "/cbs/versions" => cbs_view(path)
      "/cbs/r0-queue" => cbs_view(path)
      "/cbs/approval-config" => cbs_view(path)
      "/fund/plan" => fund_plan_view()
      "/invoice" => invoice_view(model)
      "/expenses" => expenses_view(emit)
      "/expenses/new" => expense_editor_view(emit, model, false)
      "/expenses/EXP-260712-008" => expense_editor_view(emit, model, true)
      "/loans" => loans_view(emit, model)
      "/loans/new" => loan_editor_view(emit, model, false)
      "/loans/LOAN-260713-001" => loan_editor_view(emit, model, true)
      "/reports" => reports_view(emit, model)
      "/report-builder" => report_builder_view()
      "/warning" => warning_view()
      "/warning-rules" => warning_rules_view()
      "/cashflow" => cashflow_view()
      "/inbox" => inbox_view()
      "/attachments" => attachments_view()
      "/notify-config" => notify_view()
      "/audit-log" => audit_view(emit, model)
      "/error-log" => error_view()
      "/system-health" => health_view(emit, model)
      "/users" => users_view(model)
      "/admin" => admin_view(emit, model)
      "/ocr-config" => ocr_view()
      "/webhook-config" => webhook_view()
      "/profile" => profile_view(emit, model)
      _ => placeholder_view(path)
    }
  }
}

///|
fn placeholder_view(path : String) -> @html.Html {
  let title = title_for(path)
  section(class="erp-placeholder") <| [
    h2(title),
    span(class="erp-info-tag", "ERP 页面迁移中"),
    p(
      "此页面已保留 erp_new 的导航、标题和内容边界；下一步将按原页面逐页迁移到 Rabbita，并把读取/写入接到公司域与 PostgreSQL 投影。",
    ),
    table <| [
      thead <| [
        tr <| [
          th("字段"),
          th("状态"),
          th("目标"),
        ],
      ],
      tbody <| [
        tr <| [
          td("页面结构"),
          td("已挂载"),
          td("Rabbita"),
        ],
        tr <| [
          td("数据读取"),
          td("待接入"),
          td("PostgreSQL 投影"),
        ],
        tr <| [
          td("业务写入"),
          td("待授权"),
          td("公司域命令"),
        ],
      ],
    ],
  ]
}

///|
fn header_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  header(class="erp-header") <| [
    button(
      class="erp-toggle",
      on_click=emit(ToggleSidebar),
      attrs=@html.Attrs::build().aria_label("折叠侧栏"),
      if model.collapsed {
        "☰"
      } else {
        "⌂"
      },
    ),
    button(
      class="erp-mobile-toggle",
      on_click=emit(ToggleMobileNav),
      attrs=@html.Attrs::build().aria_label("打开导航"),
      "☰",
    ),
    strong(class="erp-header-title", title_for(model.page)),
    div(class="erp-header-actions") <| [
      button(
        class="erp-header-icon",
        attrs=@html.Attrs::build().aria_label("最近访问"),
        "◷",
      ),
      button(
        class="erp-header-icon has-badge",
        attrs=@html.Attrs::build().aria_label("异常预警"),
        "♧",
      ),
      button(
        class="erp-user-area",
        on_click=emit(Navigate("/profile")),
        "♙  Giant Claw  ·  超级用户",
      ),
    ],
  ]
}

///|
fn app_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let body = if model.page == "/dashboard" ||
    model.page == "/dashboard-v3" ||
    model.page == "/cockpit" {
    dashboard_view(emit, model)
  } else {
    business_view(model.page, emit, model)
  }
  div(class="erp-layout") <| [
    if model.mobile_nav {
      div(class="erp-mobile-overlay", on_click=emit(ToggleMobileNav), "")
    } else {
      @html.nothing
    },
    sidebar(emit, model),
    main_(class="erp-main-shell") <| [
      header_view(emit, model),
      div(class="erp-main") <| [
        body,
      ],
    ],
  ]
}

///|
fn view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.page.has_prefix("/share/") {
    share_view(model.page)
  } else if model.authenticated {
    app_view(emit, model)
  } else {
    login_view(emit, model)
  }
}

///|
fn main {
  let app = cell(model=initial_model(), update~, view~)
  new(app).mount("app")
}
