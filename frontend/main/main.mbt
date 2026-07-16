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
#cfg(target="js")
extern "js" fn download_blob(blob : @dom.Blob, filename : String) -> Unit =
  #| (blob, filename) => {
  #|   const url = URL.createObjectURL(blob);
  #|   const anchor = document.createElement('a');
  #|   anchor.href = url;
  #|   anchor.download = filename;
  #|   document.body.appendChild(anchor);
  #|   anchor.click();
  #|   anchor.remove();
  #|   URL.revokeObjectURL(url);
  #| }

///|
#cfg(target="js")
extern "js" fn download_text(text : String, filename : String) -> Unit =
  #| (text, filename) => {
  #|   const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
  #|   const url = URL.createObjectURL(blob);
  #|   const anchor = document.createElement('a');
  #|   anchor.href = url;
  #|   anchor.download = filename;
  #|   document.body.appendChild(anchor);
  #|   anchor.click();
  #|   anchor.remove();
  #|   URL.revokeObjectURL(url);
  #| }

///|
#cfg(target="js")
extern "js" fn read_file_input_text(
  input_id : String,
  callback : (String) -> Unit,
) -> Unit =
  #| (inputId, callback) => {
  #|   const input = document.getElementById(inputId);
  #|   const file = input && input.files ? input.files[0] : null;
  #|   if (!file) { callback(''); return; }
  #|   const reader = new FileReader();
  #|   reader.onload = () => callback(String(reader.result || ''));
  #|   reader.onerror = () => callback('');
  #|   reader.readAsText(file, 'utf-8');
  #| }

///|
#cfg(target="js")
extern "js" fn import_nonce() -> String =
  #| () => String(Date.now())

///|
struct ExpenseRow {
  expense_id : String
  expense_code : String
  subject : String
  expense_amount : String
  apply_date : String
  apply_state : String
  pay_state : String
  applied_by_name : String
  apply_dept_name : String
  source_kind : String
}

///|
struct ExpenseDetail {
  expense_id : String
  expense_code : String
  subject : String
  apply_state : String
  pay_state : String
  expense_amount : String
  offset_amount : String
  pay_amount : String
  applied_by_name : String
  apply_dept_name : String
  apply_date : String
  pay_unit : String
  source_kind : String
  details : Array[Array[String]]
  splits : Array[Array[String]]
}

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
struct TenderAwardRow {
  award_code : String
  tender_id : String
  provider_id : String
  provider_name : String
  award_amount : String
  award_date : String
  remark : String
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
struct SupplierRiskRow {
  provider_guid : String
  provider_code : String
  provider_name : String
  short_name : String
  main_category_code : String
  rating : String
  risk_score : String
  risk_tags : String
  rating_updated_at : String
  contract_count : String
  contract_total : String
  overdue_count : String
  overdue_amount : String
  source_kind : String
}

///|
struct SupplierDetailBusinessUnitRow {
  bu_guid : String
  bu_code : String
  bu_name : String
}

///|
struct SupplierDetailContractRow {
  contract_guid : String
  contract_code : String
  contract_name : String
  amount : String
  sign_date : String
  ht_cf_state : String
}

///|
struct SupplierDetail {
  provider_guid : String
  provider_code : String
  provider_name : String
  short_name : String
  legal_person : String
  business_license : String
  register_capital : String
  business_scope : String
  category_code : String
  category_name : String
  eval_result : String
  inspect_state : String
  audit_state : String
  source : String
  contact_person : String
  contact_phone : String
  address : String
  qualifications : String
  enabled : String
  created_by : String
  created_at : String
  process_instance_guid : String
  business_units : Array[SupplierDetailBusinessUnitRow]
  contracts : Array[SupplierDetailContractRow]
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
struct SalesCustomerRow {
  customer_guid : String
  customer_code : String
  customer_name : String
  phone : String
  id_card_no : String
  proj_guid : String
  source : String
  remark : String
  created_at : String
  state : String
  source_kind : String
}

///|
struct SalesSubscriptionRow {
  sub_guid : String
  sub_code : String
  customer_guid : String
  customer_name : String
  phone : String
  proj_guid : String
  building_no : String
  unit_no : String
  area : String
  unit_price : String
  total_price : String
  sub_amount : String
  sub_date : String
  state : String
  source_kind : String
}

///|
struct SalesContractRow {
  scontract_guid : String
  scontract_code : String
  customer_guid : String
  customer_name : String
  phone : String
  proj_guid : String
  building_no : String
  unit_no : String
  area : String
  total_price : String
  payment_type : String
  signed_date : String
  state : String
  source_kind : String
}

///|
struct SalesMortgageRow {
  mortgage_guid : String
  mortgage_code : String
  customer_guid : String
  customer_name : String
  bank_name : String
  loan_amount : String
  loan_years : String
  rate : String
  apply_date : String
  approval_date : String
  release_date : String
  state : String
  source_kind : String
}

///|
struct SalesRevenueRow {
  revenue_guid : String
  revenue_code : String
  proj_guid : String
  customer_name : String
  amount : String
  receive_date : String
  status : String
  payment_type : String
  contract_no : String
  remark : String
  source_kind : String
}

///|
struct InvoiceRow {
  invoice_guid : String
  invoice_no : String
  counterparty : String
  invoice_date : String
  total_amount : String
  tax_amount : String
  tax_rate : String
  invoice_type : String
  state : String
  source_kind : String
}

///|
struct InvoiceTaxRow {
  period : String
  total_in : String
  tax_in : String
  total_out : String
  tax_out : String
  net_tax : String
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
  task_code : String
  task_name : String
  project_id : String
  task_type : String
  parent_task_id : String
  plan_begin_date : String
  plan_end_date : String
  actual_begin_date : String
  actual_end_date : String
  progress_pct : String
  status : String
  owner_name : String
  delayed : Bool
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
  spare : String
  d_amount : String
  e_amount : String
  f_amount : String
  g_amount : String
  source_kind : String
}

///|
struct ReportContractRow {
  contract_code : String
  contract_name : String
  bu_name : String
  proj_name : String
  provider : String
  sign_date : String
  current_amount : String
  applied_total : String
  paid_total : String
  remain_amount : String
  paid_pct : String
  source_kind : String
}

///|
struct ReportSupplierRow {
  provider_name : String
  short_name : String
  category_name : String
  eval_result : String
  contract_count : String
  bu_count : String
  proj_count : String
  total_amount : String
  recent_amount : String
  source_kind : String
}

///|
struct ReportApprovalRow {
  biz_type : String
  total : String
  completed : String
  rejected : String
  running : String
  overdue : String
  avg_days : String
  reject_rate : String
}

///|
struct ReportSlowStepRow {
  step_name : String
  emp_name : String
  avg_days : String
  count : String
}

///|
struct ReportStageCell {
  stage_code : String
  stage_name : String
  status : String
  progress_pct : String
}

///|
struct ReportStageRow {
  proj_guid : String
  proj_code : String
  proj_name : String
  bu_name : String
  proj_status : String
  begin_date : String
  end_date : String
  cells : Array[ReportStageCell]
  source_kind : String
}

///|
struct ReportShareRow {
  token : String
  report_key : String
  report_label : String
  title : String
  created_at : String
  expires_at : String
  never_expires : String
  access_count : String
  revoked : String
  expired : String
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
struct DashboardV2TrendRow {
  month : String
  plan : String
  actual : String
}

///|
struct DashboardV2StageRow {
  stage : String
  count : String
}

///|
struct DashboardV2WarningRow {
  title : String
  severity : String
  source_kind : String
}

///|
struct DashboardV3PairRow {
  label : String
  value : String
}

///|
struct DashboardV3CityRow {
  name : String
  expense : String
  revenue : String
}

///|
struct DashboardV3ContractRow {
  code : String
  name : String
  amount : String
}

///|
struct DashboardV3Snapshot {
  scope : String
  health_score : String
  total_revenue : String
  total_expense : String
  net_profit : String
  net_profit_rate : String
  cashflow_months : String
  customer_count : String
  signed_count : String
  mortgage_count : String
  progress_active : String
  progress_done : String
  tender_active_count : String
  open_warnings : String
  running_processes : String
  missing_table_count : String
  health_rows : Array[DashboardV3PairRow]
  expense_rows : Array[DashboardV3PairRow]
  city_rows : Array[DashboardV3CityRow]
  funnel_rows : Array[DashboardV3PairRow]
  top_unpaid_rows : Array[DashboardV3ContractRow]
  top_approving_rows : Array[DashboardV3ContractRow]
  top_overbudget_rows : Array[DashboardV3PairRow]
  top_gap_rows : Array[DashboardV3PairRow]
}

///|
fn empty_dashboard_v3() -> DashboardV3Snapshot {
  {
    scope: "",
    health_score: "0",
    total_revenue: "0",
    total_expense: "0",
    net_profit: "0",
    net_profit_rate: "0",
    cashflow_months: "0",
    customer_count: "0",
    signed_count: "0",
    mortgage_count: "0",
    progress_active: "0",
    progress_done: "0",
    tender_active_count: "0",
    open_warnings: "0",
    running_processes: "0",
    missing_table_count: "0",
    health_rows: [],
    expense_rows: [],
    city_rows: [],
    funnel_rows: [],
    top_unpaid_rows: [],
    top_approving_rows: [],
    top_overbudget_rows: [],
    top_gap_rows: [],
  }
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
  param_guid : String
  group_name : String
  code : String
  value : String
  display_order : String
  enabled : String
  source_kind : String
}

///|
struct InvestmentIndexRow {
  index_guid : String
  dimension : String
  index_name : String
  full_code : String
  index_value : String
  unit : String
  source_kind : String
}

///|
struct InvestmentVersionRow {
  version_guid : String
  version_name : String
  version_no : String
  is_current : Bool
  creator_name : String
  created_at : String
  remark : String
  source_kind : String
}

///|
struct InvestmentSensitivityCase {
  name : String
  irr : String
  source_kind : String
}

///|
struct InvestmentImportRow {
  import_guid : String
  version_guid : String
  version_name : String
  file_name : String
  file_size : String
  sheet_count : String
  non_empty_cells : String
  formula_count : String
  status : String
  created_by_name : String
  created_at : String
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
struct CostDashboardRow {
  code : String
  name : String
  level : String
  target_cost : String
  committed_cost : String
  in_transit : String
  planned_spare : String
  estimated_change : String
  dynamic_cost : String
  layout_spare : String
}

///|
struct AiHubDraftRow {
  draft_id : String
  biz_type : String
  description : String
  confidence : String
  status : String
  created_at : String
  source_kind : String
}

///|
struct AiHubQueryRow {
  qid : String
  question : String
  explanation : String
  row_count : String
  duration_ms : String
  error : String
  created_at : String
  source_kind : String
}

///|
struct AiHubCorrectionRow {
  biz_type : String
  field_name : String
  llm_value : String
  user_value : String
  created_at : String
  source_kind : String
}

///|
struct CashflowRow {
  ym : String
  planned : String
  pending : String
  confirmed : String
  expense : String
  loan : String
  total_outflow : String
  cumulative_outflow : String
  actual_outflow : String
  actual_cumulative : String
}

///|
struct CbsRow {
  l3_code : String
  r_code : String
  l2_name : String
  subject : String
  plan_amount : String
  src : String
}

///|
struct FundPlanRow {
  plan_guid : String
  proj_guid : String
  plan_code : String
  plan_period : String
  direction : String
  category : String
  proj_name : String
  plan_amount : String
  actual_amount : String
  state : String
  r_code : String
  remark : String
  source_kind : String
}

///|
struct FundGapRow {
  period : String
  plan_in : String
  plan_out : String
  net : String
  cum_net : String
  gap : String
}

///|
struct FundDispatchRow {
  dispatch_guid : String
  dispatch_code : String
  dispatch_date : String
  from_proj : String
  to_proj : String
  amount : String
  reason : String
  state : String
  source_kind : String
}

///|
struct WarningRow {
  warning_guid : String
  rule_code : String
  rule_name : String
  severity : String
  biz_type : String
  title : String
  detail : String
  status : String
  source_kind : String
}

///|
struct AttachmentRow {
  att_guid : String
  file_name : String
  file_size : String
  mime_type : String
  biz_type : String
  biz_guid : String
  uploaded_by_name : String
  uploaded_at : String
  ai_status : String
  source_kind : String
  download_available : String
}

///|
struct InitiatedRow {
  id : String
  code : String
  subject : String
  amount : String
  state : String
  date : String
  biz : String
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
struct WorkflowObservationRow {
  process_instance_guid : String
  process_name : String
  biz_type : String
  biz_data_guid : String
  status : String
  initiated_at : String
  decision : String
  source_kind : String
  initiator_name : String
  completed_at : String
  last_action_time : String
  current_step_order : String
  current_step_name : String
}

///|
struct WorkflowTicketRow {
  ticket_id : String
  warning_guid : String
  status : String
  note : String
  due_date : String
  created_at : String
  created_by : String
  handled_at : String
  assignee_user_id : String
  source_kind : String
  rule_code : String
  rule_name : String
  severity : String
  biz_type : String
  biz_data_guid : String
  title : String
}

///|
struct BudgetScopeUserRow {
  user_id : String
  emp_name : String
  dept_guid : String
  bu_guid : String
  source_kind : String
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
struct ProjectStageRow {
  stage_code : String
  stage_name : String
  stage_order : String
  status : String
  progress_pct : String
  planned_start : String
  planned_end : String
  actual_start : String
  actual_end : String
  source_kind : String
}

///|
struct ProjectKpi {
  progress_avg : String
  progress_done : String
  progress_total_nodes : String
  progress_overdue_nodes : String
  cost_deviation_pct : String
  cost_dynamic : String
  cost_target : String
  contract_total : String
  contract_count : String
  payment_paid_ratio : String
  payment_paid_total : String
  payment_apply_total : String
  cash_this_month_plan : String
  profit_irr : String
  profit_net_profit : String
  profit_npv : String
  approval_avg_days : String
}

///|
struct ProjectAnomalyRow {
  severity : String
  title : String
  detail : String
  suggestion : String
}

///|
struct ImportCsvData {
  headers : Array[String]
  preview_rows : Array[Array[String]]
  rows_json : String
  row_count : String
  within_limit : Bool
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
  expenses_loaded : Bool
  expense_rows : Array[ExpenseRow]
  expenses_note : String
  expense_detail_loaded : Bool
  expense_detail : ExpenseDetail?
  expense_detail_note : String
  api_status : String
  api_note : String
  expense_id : String
  expense_state : String
  expense_note : String
  expense_budget_check_note : String
  contracts_loaded : Bool
  contract_rows : Array[ContractRow]
  contract_detail : ContractRow?
  contract_milestones : Array[ContractMilestoneRow]
  contract_id : String
  contract_state : String
  contract_note : String
  contract_milestone_node_name : String
  contract_milestone_trigger_type : String
  contract_milestone_trigger_value : String
  contract_milestone_plan_date : String
  contract_milestone_plan_amount : String
  contract_milestone_plan_pct : String
  contract_milestone_notes : String
  contract_milestone_command_note : String
  payment_applies_loaded : Bool
  payment_apply_rows : Array[PaymentApplyRow]
  payment_apply_id : String
  payment_apply_state : String
  payment_apply_note : String
  payment_apply_eligibility_note : String
  tenders_loaded : Bool
  tender_project_id : String
  tender_selected_source_kind : String
  tender_form_open : String
  tender_name : String
  tender_category : String
  tender_estimated_amount : String
  tender_plan_publish_date : String
  tender_plan_award_date : String
  tender_remark : String
  tender_award_provider_guid : String
  tender_award_provider_name : String
  tender_award_amount : String
  tender_award_date : String
  tender_award_remark : String
  tender_tab : String
  tender_rows : Array[TenderRow]
  tender_award_rows : Array[TenderAwardRow]
  tender_id : String
  tender_state : String
  tender_note : String
  tender_source_loaded : Bool
  tender_source_award_count : String
  tender_source_split_count : String
  tender_source_note : String
  tender_source_command_note : String
  suppliers_loaded : Bool
  supplier_rows : Array[SupplierRow]
  supplier_source_loaded : Bool
  supplier_source_rows : Array[SupplierRow]
  supplier_source_missing_table_count : String
  supplier_source_note : String
  supplier_dict_loaded : Bool
  supplier_category_count : String
  supplier_eval_count : String
  supplier_source_count : String
  supplier_dict_note : String
  supplier_risk_loaded : Bool
  supplier_risk_rows : Array[SupplierRiskRow]
  supplier_risk_distribution_total : String
  supplier_risk_missing_table_count : String
  supplier_risk_note : String
  supplier_id : String
  supplier_state : String
  supplier_evaluation : String
  supplier_note : String
  supplier_detail_loaded : Bool
  supplier_detail : SupplierDetail?
  supplier_detail_note : String
  supplier_detail_risk_loaded : Bool
  supplier_detail_risk_score : String
  supplier_detail_risk_rating : String
  supplier_detail_risk_tags : String
  supplier_detail_risk_contract_count : String
  supplier_detail_risk_overdue_count : String
  supplier_detail_risk_note : String
  supplier_check_sign_note : String
  supplier_stats_loaded : Bool
  supplier_stats_total : String
  supplier_stats_contract_rows : String
  supplier_stats_top_business : String
  supplier_stats_note : String
  sales_loaded : Bool
  sales_family : String
  sales_rows : Array[SalesRow]
  sales_customer_rows : Array[SalesCustomerRow]
  sales_customer_project_id : String
  sales_customer_keyword : String
  sales_customer_form_open : Bool
  sales_customer_edit_id : String
  sales_customer_name : String
  sales_customer_id_card_no : String
  sales_customer_phone : String
  sales_customer_source : String
  sales_customer_remark : String
  sales_subscription_rows : Array[SalesSubscriptionRow]
  sales_subscription_loaded : Bool
  sales_subscription_project_id : String
  sales_subscription_state : String
  sales_subscription_form_open : Bool
  sales_subscription_customer_guid : String
  sales_subscription_proj_guid : String
  sales_subscription_building_no : String
  sales_subscription_unit_no : String
  sales_subscription_area : String
  sales_subscription_unit_price : String
  sales_subscription_total_price : String
  sales_subscription_sub_amount : String
  sales_subscription_sub_date : String
  sales_subscription_payment_type : String
  sales_contract_rows : Array[SalesContractRow]
  sales_contract_loaded : Bool
  sales_contract_project_id : String
  sales_contract_state : String
  sales_mortgage_rows : Array[SalesMortgageRow]
  sales_mortgage_loaded : Bool
  sales_mortgage_filter_state : String
  sales_mortgage_form_open : Bool
  sales_mortgage_form_contract : String
  sales_mortgage_form_customer : String
  sales_mortgage_form_bank : String
  sales_mortgage_form_amount : String
  sales_mortgage_form_years : String
  sales_mortgage_form_rate : String
  sales_mortgage_form_date : String
  sales_mortgage_form_remark : String
  sales_refund_form_open : Bool
  sales_refund_form_contract : String
  sales_refund_form_customer : String
  sales_refund_form_reason : String
  sales_refund_form_amount : String
  sales_refund_form_date : String
  sales_revenue_rows : Array[SalesRevenueRow]
  sales_revenue_loaded : Bool
  sales_revenue_project_id : String
  sales_revenue_filter_status : String
  sales_revenue_keyword : String
  sales_revenue_form_open : Bool
  sales_revenue_editing_id : String
  sales_revenue_form_project : String
  sales_revenue_form_customer : String
  sales_revenue_form_amount : String
  sales_revenue_form_date : String
  sales_revenue_form_status : String
  sales_revenue_form_payment_type : String
  sales_revenue_form_contract_no : String
  sales_revenue_form_remark : String
  sales_note : String
  sales_customer_command_note : String
  sales_subscription_command_note : String
  sales_mortgage_id : String
  sales_mortgage_state : String
  sales_mortgage_command_note : String
  sales_refund_id : String
  sales_refund_state : String
  sales_refund_command_note : String
  sales_revenue_id : String
  sales_revenue_state : String
  sales_revenue_command_note : String
  invoice_source_loaded : Bool
  invoice_project_id : String
  invoice_tab : String
  invoice_form_open : String
  invoice_no : String
  invoice_counterparty : String
  invoice_date : String
  invoice_total_amount : String
  invoice_tax_rate : String
  invoice_type : String
  invoice_remark : String
  invoice_in_rows : Array[InvoiceRow]
  invoice_out_rows : Array[InvoiceRow]
  invoice_tax_rows : Array[InvoiceTaxRow]
  invoice_source_in_count : String
  invoice_source_out_count : String
  invoice_source_tax_count : String
  invoice_source_note : String
  delivery_loaded : Bool
  delivery_project_id : String
  delivery_tab : String
  delivery_progress_rows : Array[DeliveryProgressRow]
  delivery_output_rows : Array[DeliveryOutputRow]
  delivery_source_progress_rows : Array[DeliveryProgressRow]
  delivery_source_output_rows : Array[DeliveryOutputRow]
  delivery_task_rows : Array[DeliveryTaskRow]
  delivery_report_rows : Array[DeliveryReportRow]
  delivery_note : String
  delivery_source_loaded : Bool
  delivery_source_progress_count : String
  delivery_source_output_count : String
  delivery_source_note : String
  delivery_form_open : String
  delivery_building_no : String
  delivery_stage : String
  delivery_plan_date : String
  delivery_plan_pct : String
  delivery_contract_id : String
  delivery_remark : String
  delivery_report_actual_pct : String
  delivery_report_date : String
  delivery_report_remark : String
  delivery_output_contract_id : String
  delivery_output_period : String
  delivery_output_amount : String
  delivery_output_remark : String
  delivery_progress_id : String
  delivery_progress_state : String
  delivery_output_id : String
  delivery_output_state : String
  delivery_task_id : String
  delivery_command_note : String
  project_plan_project_id : String
  plan_task_id : String
  plan_task_state : String
  plan_task_command_note : String
  plan_ai_suggestion_note : String
  plan_ai_suggestion_rows : Array[Array[String]]
  plan_ai_proj_type : String
  plan_ai_scale : String
  plan_ai_region : String
  plan_ai_begin_date : String
  plan_report_task_id : String
  plan_report_task_name : String
  plan_report_progress : String
  plan_report_date : String
  plan_report_summary : String
  plan_create_task_code : String
  plan_create_task_name : String
  plan_create_task_type : String
  plan_create_begin_date : String
  plan_create_end_date : String
  plan_create_owner : String
  plan_create_remarks : String
  plan_delay_task_id : String
  plan_delay_days : String
  plan_delay_note : String
  plan_delay_rows : Array[Array[String]]
  reports_loaded : Bool
  report_tab : String
  report_cost_rows : Array[ReportCostRow]
  report_contract_rows : Array[ReportContractRow]
  report_supplier_rows : Array[ReportSupplierRow]
  report_approval_rows : Array[ReportApprovalRow]
  report_slow_step_rows : Array[ReportSlowStepRow]
  report_stage_rows : Array[ReportStageRow]
  report_stage_names : Array[String]
  report_share_dialog : Bool
  report_share_list_open : Bool
  report_share_title : String
  report_share_days : String
  report_share_result_token : String
  report_share_result_url : String
  report_share_rows : Array[ReportShareRow]
  report_share_note : String
  report_favorite_loaded : Bool
  report_favorite_keys : Array[String]
  share_loaded : Bool
  share_meta_loaded : Bool
  share_token : String
  share_report_key : String
  share_report_label : String
  share_title : String
  share_expires_at : String
  share_never_expires : Bool
  share_data_body : String
  share_note : String
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
  dashboard_v2_loaded : Bool
  dashboard_v2_project_count : String
  dashboard_v2_in_progress : String
  dashboard_v2_contract_amount : String
  dashboard_v2_unpaid_amount : String
  dashboard_v2_open_warnings : String
  dashboard_v2_running_processes : String
  dashboard_v2_trend_rows : Array[DashboardV2TrendRow]
  dashboard_v2_stage_rows : Array[DashboardV2StageRow]
  dashboard_v2_warning_rows : Array[DashboardV2WarningRow]
  dashboard_v2_missing_table_count : String
  dashboard_v2_note : String
  dashboard_v3_loaded : Bool
  dashboard_v3 : DashboardV3Snapshot
  dashboard_v3_note : String
  admin_quality_loaded : Bool
  admin_quality_rows : Array[AdminQualityRow]
  admin_quality_note : String
  admin_dict_loaded : Bool
  admin_dict_group_rows : Array[AdminDictGroupRow]
  admin_dict_option_rows : Array[AdminDictOptionRow]
  admin_dict_note : String
  admin_dict_command_note : String
  admin_backup_note : String
  investment_loaded : Bool
  investment_version_id : String
  investment_version_name : String
  investment_version_rows : Array[InvestmentVersionRow]
  investment_index_rows : Array[InvestmentIndexRow]
  investment_index_selected : String
  investment_index_edit_value : String
  investment_index_edit_remark : String
  investment_new_version_name : String
  investment_new_version_copy_from : String
  investment_new_version_remark : String
  investment_new_version_activate : Bool
  investment_new_index_dimension : String
  investment_new_index_full_code : String
  investment_new_index_name : String
  investment_new_index_parent_code : String
  investment_new_index_unit : String
  investment_new_index_value : String
  investment_new_index_remark : String
  investment_dimension_count : String
  investment_total : String
  investment_revenue : String
  investment_cost : String
  investment_net_profit : String
  investment_net_profit_margin : String
  investment_irr : String
  investment_sensitivity_loaded : Bool
  investment_sensitivity_cases : Array[InvestmentSensitivityCase]
  investment_sensitivity_note : String
  investment_imports_loaded : Bool
  investment_import_rows : Array[InvestmentImportRow]
  investment_import_note : String
  investment_import_selected : String
  investment_import_detail_note : String
  investment_import_bridge_note : String
  investment_import_index_preview_note : String
  investment_import_profit_note : String
  investment_import_plan_note : String
  investment_actual_loaded : Bool
  investment_actual_code : String
  investment_actual_message : String
  investment_actual_simulation : String
  investment_actual_missing_table_count : String
  investment_actual_note : String
  investment_note : String
  investment_explain_note : String
  investment_explain_text : String
  investment_project_id : String
  investment_project_name : String
  investment_excel_file_name : String
  investment_excel_version_name : String
  investment_excel_activate : Bool
  investment_upload_note : String
  investment_mapping_note : String
  investment_plan_line_note : String
  investment_index_upsert_note : String
  investment_plan_line_import_note : String
  investment_command_note : String
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
  dynamic_cost_project_id : String
  dynamic_cost_remark_loaded : Bool
  dynamic_cost_remark_code : String
  dynamic_cost_remark_name : String
  dynamic_cost_remark_text : String
  dynamic_cost_remark_project : String
  dynamic_cost_remark_source : String
  dynamic_cost_remark_note : String
  dynamic_cost_export_note : String
  dynamic_cost_create_code : String
  dynamic_cost_create_name : String
  dynamic_cost_create_level : String
  dynamic_cost_create_parent : String
  dynamic_cost_create_target : String
  dynamic_cost_create_contract_change : String
  dynamic_cost_create_in_transit : String
  dynamic_cost_create_budget : String
  dynamic_cost_create_estimate_change : String
  dynamic_cost_create_remarks : String
  dynamic_cost_command_note : String
  cost_dashboard_loaded : Bool
  cost_dashboard_rows : Array[CostDashboardRow]
  cost_dashboard_project_name : String
  cost_dashboard_plan_version : String
  cost_dashboard_target : String
  cost_dashboard_dynamic : String
  cost_dashboard_deviation : String
  cost_dashboard_contract_count : String
  cost_dashboard_expense_count : String
  cost_dashboard_change_count : String
  cost_dashboard_note : String
  cashflow_loaded : Bool
  cashflow_rows : Array[CashflowRow]
  cashflow_planned_total : String
  cashflow_pending_total : String
  cashflow_confirmed_total : String
  cashflow_expense_total : String
  cashflow_loan_total : String
  cashflow_total_outflow : String
  cashflow_missing_table_count : String
  cashflow_note : String
  cashflow_inflow_loaded : Bool
  cashflow_inflow_total : String
  cashflow_inflow_missing_table_count : String
  cashflow_inflow_note : String
  cashflow_explain_note : String
  cashflow_explain_text : String
  cbs_loaded : Bool
  cbs_rows : Array[CbsRow]
  cbs_plan_version : String
  cbs_r0_count : String
  cbs_missing_table_count : String
  cbs_note : String
  fund_loaded : Bool
  fund_project_id : String
  fund_tab : String
  fund_form_open : String
  fund_plan_period : String
  fund_plan_direction : String
  fund_plan_category : String
  fund_plan_r_code : String
  fund_plan_amount : String
  fund_plan_actual_amount : String
  fund_plan_remark : String
  fund_dispatch_from : String
  fund_dispatch_to : String
  fund_dispatch_amount : String
  fund_dispatch_reason : String
  fund_dispatch_date : String
  fund_rows : Array[FundPlanRow]
  fund_gap_rows : Array[FundGapRow]
  fund_dispatch_rows : Array[FundDispatchRow]
  fund_gap_series_count : String
  fund_dispatch_count : String
  fund_missing_table_count : String
  fund_note : String
  fund_plan_id : String
  fund_dispatch_id : String
  fund_command_state : String
  fund_command_note : String
  warnings_loaded : Bool
  warning_rows : Array[WarningRow]
  warning_rule_count : String
  warning_missing_table_count : String
  warning_note : String
  warning_action_state : String
  warning_action_note : String
  warning_rule_preview_note : String
  warning_rule_command_note : String
  warning_ticket_note : String
  warning_action_guid : String
  attachments_loaded : Bool
  attachment_rows : Array[AttachmentRow]
  attachment_total : String
  attachment_bytes : String
  attachment_pending : String
  attachment_missing_table_count : String
  attachment_note : String
  attachment_biz_type : String
  attachment_ai_status : String
  attachment_keyword : String
  attachment_file_name : String
  attachment_file_mime : String
  attachment_file_size : String
  attachment_action_guid : String
  attachment_action_note : String
  attachment_download_note : String
  attachment_delete_note : String
  marketing_loaded : Bool
  marketing_project_id : String
  marketing_tab : String
  marketing_form_open : String
  marketing_campaign_name : String
  marketing_campaign_type : String
  marketing_campaign_budget : String
  marketing_campaign_start : String
  marketing_campaign_end : String
  marketing_campaign_goal : String
  marketing_campaign_remark : String
  marketing_placement_campaign : String
  marketing_placement_channel : String
  marketing_placement_channel_name : String
  marketing_placement_amount : String
  marketing_placement_date : String
  marketing_placement_duration : String
  marketing_channel_name : String
  marketing_channel_type : String
  marketing_channel_contact : String
  marketing_channel_phone : String
  marketing_material_name : String
  marketing_material_type : String
  marketing_material_unit_cost : String
  marketing_material_quantity : String
  marketing_campaign_rows : Array[Array[String]]
  marketing_placement_rows : Array[Array[String]]
  marketing_channel_rows : Array[Array[String]]
  marketing_material_rows : Array[Array[String]]
  marketing_campaign_count : String
  marketing_placement_count : String
  marketing_channel_count : String
  marketing_material_count : String
  marketing_missing_table_count : String
  marketing_note : String
  inbox_loaded : Bool
  inbox_rows : Array[Array[String]]
  inbox_total : String
  inbox_unread : String
  inbox_missing_table_count : String
  inbox_note : String
  notify_loaded : Bool
  notify_subscription_rows : Array[Array[String]]
  notify_config_rows : Array[Array[String]]
  notify_outbox_rows : Array[Array[String]]
  notify_digest_rows : Array[Array[String]]
  notify_subscription_count : String
  notify_configured_count : String
  notify_outbox_count : String
  notify_digest_count : String
  notify_missing_table_count : String
  notify_note : String
  notify_email_note : String
  ocr_loaded : Bool
  ocr_provider : String
  ocr_scene : String
  ocr_provider_rows : Array[Array[String]]
  ocr_configured_count : String
  ocr_missing_table_count : String
  ocr_note : String
  ocr_command_note : String
  provider_test_note : String
  error_loaded : Bool
  error_rows : Array[Array[String]]
  error_total : String
  error_today_count : String
  error_five_xx_count : String
  error_missing_table_count : String
  error_note : String
  ai_stats_loaded : Bool
  ai_stats_period : String
  ai_stats_intake_total : String
  ai_stats_query_total : String
  ai_stats_skip_total : String
  ai_stats_correction_total : String
  ai_stats_accuracy : String
  ai_stats_saved_hours : String
  ai_stats_scene_rows : Array[Array[String]]
  ai_stats_activity_rows : Array[Array[String]]
  ai_stats_missing_table_count : String
  ai_stats_note : String
  ai_stats_export_note : String
  ai_hub_loaded : Bool
  ai_hub_draft_rows : Array[AiHubDraftRow]
  ai_hub_query_rows : Array[AiHubQueryRow]
  ai_hub_correction_rows : Array[AiHubCorrectionRow]
  ai_hub_monthly_calls : String
  ai_hub_minutes_saved : String
  ai_hub_intake_total : String
  ai_hub_correction_total : String
  ai_hub_correction_rate : String
  ai_hub_missing_table_count : String
  ai_hub_note : String
  ai_hub_explain_note : String
  ai_hub_explain_text : String
  ai_hub_intake_description : String
  ai_hub_intake_biz_hint : String
  ai_hub_file_name : String
  ai_hub_query_text : String
  ai_hub_command_text : String
  ai_hub_command_note : String
  webhook_loaded : Bool
  webhook_rows : Array[Array[String]]
  webhook_missing_table_count : String
  webhook_note : String
  webhook_command_note : String
  report_builder_loaded : Bool
  report_builder_table_rows : Array[Array[String]]
  report_builder_template_rows : Array[Array[String]]
  report_builder_missing_table_count : String
  report_builder_note : String
  report_builder_command_state : String
  report_builder_command_note : String
  report_builder_template_id : String
  report_builder_run_rows : Array[Array[String]]
  users_loaded : Bool
  user_roster_rows : Array[UserRosterRow]
  users_note : String
  rbac_roles_loaded : Bool
  rbac_role_rows : Array[Array[String]]
  rbac_roles_note : String
  rbac_catalog_loaded : Bool
  rbac_catalog_rows : Array[Array[String]]
  rbac_catalog_note : String
  profile_loaded : Bool
  profile_user_id : String
  profile_user_code : String
  profile_user_name : String
  profile_edit_name : String
  profile_password_old : String
  profile_password_new : String
  profile_password_confirm : String
  profile_bu_guid : String
  profile_bu_name : String
  profile_dept_name : String
  profile_super_user : String
  profile_enabled : String
  profile_last_login : String
  profile_source_kind : String
  profile_note : String
  profile_command_note : String
  profile_initiated_loaded : Bool
  profile_initiated_rows : Array[InitiatedRow]
  profile_initiated_note : String
  health_loaded : Bool
  health_table_rows : Array[HealthTableRow]
  health_source_table_count : String
  health_missing_table_count : String
  health_bpm_instance_count : String
  health_bpm_action_count : String
  health_note : String
  health_inventory_loaded : Bool
  health_inventory_schema_count : String
  health_inventory_snapshot_count : String
  health_inventory_schema_only_count : String
  health_inventory_export_state : String
  health_inventory_snapshot_id : String
  health_inventory_note : String
  loans_loaded : Bool
  loan_rows : Array[LoanRow]
  loan_note : String
  budget_scope_loaded : Bool
  budget_scope_users : Array[BudgetScopeUserRow]
  budget_scope_note : String
  budget_loan_balance_loaded : Bool
  budget_loan_balance_total : String
  budget_loan_count : String
  budget_loan_note : String
  loan_id : String
  loan_state : String
  loan_command_note : String
  loan_workflow_sync_note : String
  workflow_loaded : Bool
  workflow_process_rows : Array[WorkflowProcessRow]
  workflow_note : String
  workflow_observation_loaded : Bool
  workflow_pending_rows : Array[WorkflowObservationRow]
  workflow_initiated_rows : Array[WorkflowObservationRow]
  workflow_history_rows : Array[WorkflowObservationRow]
  workflow_task_tab : String
  workflow_tickets_loaded : Bool
  workflow_ticket_rows : Array[WorkflowTicketRow]
  workflow_ticket_note : String
  workflow_observation_note : String
  workflow_command_note : String
  projects_loaded : Bool
  project_rows : Array[ProjectRow]
  project_detail : ProjectRow?
  project_stage_rows : Array[ProjectStageRow]
  project_kpi_loaded : Bool
  project_kpi : ProjectKpi
  project_kpi_note : String
  project_anomalies_loaded : Bool
  project_anomaly_rows : Array[ProjectAnomalyRow]
  project_anomaly_note : String
  project_note : String
  import_template_note : String
  import_biz_type : String
  import_file_name : String
  import_headers : Array[String]
  import_preview_rows : Array[Array[String]]
  import_rows_json : String
  import_row_count : String
  import_key : String
  import_state : String
  import_note : String
}

///|
enum Msg {
  Login
  ToggleDemo
  FillDemo(String, String)
  InputUser(String)
  InputPassword(String)
  InputProjectPlanProject(String)
  InputPlanAiProjectType(String)
  InputPlanAiScale(String)
  InputPlanAiRegion(String)
  InputPlanAiBeginDate(String)
  InputPlanReportProgress(String)
  InputPlanReportDate(String)
  InputPlanReportSummary(String)
  SelectPlanTask(String, String)
  InputPlanCreateTaskCode(String)
  InputPlanCreateTaskName(String)
  InputPlanCreateTaskType(String)
  InputPlanCreateBeginDate(String)
  InputPlanCreateEndDate(String)
  InputPlanCreateOwner(String)
  InputPlanCreateRemarks(String)
  InputPlanDelayDays(String)
  RunPlanDelayImpact
  ExportPlanCsv
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
  ProfilePasswordLoggedOut
  ExpensesLoaded(String)
  ExpensesLoadFailed
  ExpenseDetailLoaded(String)
  ExpenseDetailLoadFailed
  CreateExpense
  UpdateExpense
  VoidExpense
  CheckExpenseBudget
  ExpenseBudgetCheckFinished(String)
  ExpenseBudgetCheckFailed
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
  InputContractMilestoneNodeName(String)
  InputContractMilestoneTriggerType(String)
  InputContractMilestoneTriggerValue(String)
  InputContractMilestonePlanDate(String)
  InputContractMilestonePlanAmount(String)
  InputContractMilestonePlanPct(String)
  InputContractMilestoneNotes(String)
  RequestContractMilestoneCreate
  ContractMilestoneTrigger(String)
  ContractMilestoneDelete(String)
  ContractMilestoneCommandFinished(String)
  ContractMilestoneCommandFailed
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
  TenderSourceTendersLoaded(String)
  TenderSourceAwardsLoaded(String)
  TenderSourceSplitsLoaded(String)
  TenderSourceLoadFailed
  SelectTenderProject(String)
  SelectTenderRow(String, String, String, String)
  AdvanceTenderRow(String, String, String)
  SelectTenderProvider(String, String)
  SelectTenderTab(String)
  OpenTenderForm(String)
  CloseTenderForm
  InputTenderField(String, String)
  SubmitTenderForm
  PublishTender
  OpenTenderBidding
  AwardTender
  CompleteTender
  CancelTender
  TenderCommandFinished(String)
  TenderCommandFailed
  AdvanceSourceTender
  AwardSourceTender
  TenderSourceCommandFinished(String, String)
  TenderSourceCommandFailed(String)
  SuppliersLoaded(String)
  SuppliersLoadFailed
  SupplierSourceLoaded(String)
  SupplierSourceLoadFailed
  SupplierDictCategoriesLoaded(String)
  SupplierDictEvalLoaded(String)
  SupplierDictSourcesLoaded(String)
  SupplierDictLoadFailed
  SupplierDetailLoaded(String)
  SupplierDetailLoadFailed
  SupplierDetailRiskLoaded(String)
  SupplierDetailRiskLoadFailed
  RequestSupplierCheckSign
  SupplierCheckSignFinished(String)
  SupplierCheckSignFailed
  SupplierStatsLoaded(String)
  SupplierStatsLoadFailed
  SupplierRiskLoaded(String)
  SupplierRiskLoadFailed
  CreateSupplier
  UpdateSupplier
  SubmitSupplierReview
  ReviewSupplier
  BlacklistSupplier
  VoidSupplier
  SupplierCommandFinished(String)
  SupplierCommandFailed
  RescoreSuppliers
  SupplierRescoreFinished(String)
  SupplierRescoreFailed
  SalesLoaded(String, String)
  SalesLoadFailed(String)
  SelectSalesCustomerProject(String)
  InputSalesCustomerKeyword(String)
  OpenSalesCustomerCreate
  OpenSalesCustomerEdit(String)
  CloseSalesCustomerForm
  InputSalesCustomerField(String, String)
  SubmitSalesCustomerForm
  DeleteSalesCustomer(String)
  SalesCustomerCommandFinished(String)
  SalesCustomerCommandFailed
  SelectSalesSubscriptionProject(String)
  SelectSalesSubscriptionState(String)
  OpenSalesSubscriptionForm
  CloseSalesSubscriptionForm
  InputSalesSubscriptionField(String, String)
  SubmitSalesSubscriptionForm
  ConvertSalesSubscription(String)
  SalesSubscriptionCommandFinished(String)
  SalesSubscriptionCommandFailed
  SelectSalesContractProject(String)
  SelectSalesContractState(String)
  SelectSalesMortgageState(String)
  OpenSalesMortgageForm(String, String, String)
  CloseSalesMortgageForm
  InputSalesMortgageField(String, String)
  SubmitSalesMortgageForm
  OpenSalesRefundForm(String, String, String)
  CloseSalesRefundForm
  InputSalesRefundField(String, String)
  SubmitSalesRefundForm
  SelectSalesRevenueProject(String)
  SelectSalesRevenueStatus(String)
  InputSalesRevenueKeyword(String)
  QuerySalesRevenue
  OpenSalesRevenueEdit(String)
  CloseSalesRevenueForm
  InputSalesRevenueField(String, String)
  SubmitSalesRevenueForm
  CreateSalesMortgage
  ApproveSalesMortgage
  ReleaseSalesMortgage
  SalesMortgageCommandFinished(String)
  SalesMortgageCommandFailed
  CreateSalesRefund
  ApproveSalesRefund
  SalesRefundCommandFinished(String)
  SalesRefundCommandFailed
  CreateSalesRevenue
  UpdateSalesRevenue
  ConfirmSalesRevenue
  DeleteSalesRevenue
  SalesRevenueCommandFinished(String)
  SalesRevenueCommandFailed
  InvoiceSourceInLoaded(String)
  InvoiceSourceOutLoaded(String)
  InvoiceSourceTaxLoaded(String)
  InvoiceSourceLoadFailed
  SelectInvoiceProject(String)
  SelectInvoiceTab(String)
  OpenInvoiceForm(String)
  CloseInvoiceForm
  InputInvoiceField(String, String)
  CreateInvoice(String)
  DeleteInvoice(String, String)
  InvoiceCommandFinished
  InvoiceCommandFailed
  DeliverySourceProgressLoaded(String)
  DeliverySourceOutputsLoaded(String)
  DeliverySourceLoadFailed
  DeliveryLoaded(String)
  DeliveryLoadFailed
  SelectDeliveryProject(String)
  SelectDeliveryTab(String)
  OpenDeliveryForm(String)
  CloseDeliveryForm
  InputDeliveryField(String, String)
  CreateDeliveryProgress
  ReportDeliveryProgress
  AcceptDeliveryProgress
  RejectDeliveryProgress
  CreateDeliveryOutput
  ConfirmDeliveryOutput
  ReportTaskProgress
  CreatePlanTask
  UpdatePlanTask
  DeletePlanTask
  PlanTaskCommandFinished(String)
  PlanTaskCommandFailed
  PlanDelayImpactFinished(String)
  PlanDelayImpactFailed
  SuggestProjectPlan
  ProjectPlanSuggestionFinished(String)
  ProjectPlanSuggestionFailed
  DeliveryCommandFinished(String)
  DeliveryCommandFailed
  ReportsLoaded(String)
  ReportsLoadFailed
  SelectReportTab(String)
  ExportReportsCsv
  OpenReportShare
  CloseReportShare
  InputReportShareTitle(String)
  SelectReportShareDays(String)
  CreateReportShare
  ReportShareCreated(String)
  ReportShareCreateFailed(String)
  OpenReportShareList
  CloseReportShareList
  ReportSharesLoaded(String)
  ReportSharesLoadFailed
  RevokeReportShare(String)
  ReportShareRevoked(String)
  ReportShareRevokeFailed(String)
  ReportPreferencesLoaded(String)
  ReportPreferencesLoadFailed
  ToggleReportFavorite
  ReportPreferenceUpdated(String)
  ShareMetaLoaded(String)
  ShareDataLoaded(String)
  ShareLoadFailed(String)
  DashboardOverviewLoaded(String)
  DashboardFunnelLoaded(String)
  DashboardAnomaliesLoaded(String)
  DashboardLoadFailed
  DashboardV2Loaded(String)
  DashboardV2LoadFailed
  DashboardV3Loaded(String)
  DashboardV3LoadFailed
  AdminQualityLoaded(String)
  AdminQualityLoadFailed
  AdminDictGroupsLoaded(String)
  AdminDictOptionsLoaded(String)
  AdminDictLoadFailed
  CreateAdminDictOption
  UpdateAdminDictOption
  AdminDictCommandFinished(String)
  AdminDictCommandFailed
  RequestAdminBackup
  AdminBackupFinished(String)
  AdminBackupFailed
  InvestmentVersionsLoaded(String)
  InvestmentIndicesLoaded(String)
  InvestmentProfitLoaded(String)
  InvestmentSensitivityLoaded(String)
  InvestmentImportsLoaded(String)
  SelectInvestmentProject(String)
  SelectInvestmentImport(String)
  InvestmentImportDetailLoaded(String)
  InvestmentImportBridgeLoaded(String)
  InvestmentImportIndexPreviewLoaded(String)
  InvestmentImportProfitLoaded(String)
  InvestmentImportPlanLoaded(String)
  InvestmentProfitActualLoaded(String)
  InvestmentLoadFailed
  ExplainInvestment
  InvestmentExplainFinished(String)
  InvestmentExplainFailed
  SelectInvestmentVersion(String)
  SelectInvestmentIndex(String)
  InputInvestmentIndexEditValue(String)
  InputInvestmentIndexEditRemark(String)
  InputInvestmentVersionName(String)
  InputInvestmentVersionCopyFrom(String)
  InputInvestmentVersionRemark(String)
  ToggleInvestmentVersionActivate
  InputInvestmentIndexDimension(String)
  InputInvestmentIndexFullCode(String)
  InputInvestmentIndexName(String)
  InputInvestmentIndexParentCode(String)
  InputInvestmentIndexUnit(String)
  InputInvestmentIndexValue(String)
  InputInvestmentIndexRemark(String)
  InputInvestmentExcelFileSelected(String)
  InputInvestmentExcelVersionName(String)
  ToggleInvestmentExcelActivate
  RequestInvestmentExcelUpload
  InvestmentExcelUploadFinished(String)
  InvestmentExcelUploadFailed
  RequestInvestmentSubjectMappings
  InvestmentSubjectMappingsFinished(String)
  InvestmentSubjectMappingsFailed
  RequestInvestmentPlanLineUpdate
  InvestmentPlanLineUpdateFinished(String)
  InvestmentPlanLineUpdateFailed
  RequestInvestmentIndexUpsert
  InvestmentIndexUpsertFinished(String)
  InvestmentIndexUpsertFailed
  RequestInvestmentPlanLineImport
  InvestmentPlanLineImportFinished(String)
  InvestmentPlanLineImportFailed
  RequestInvestmentVersionCreate
  RequestInvestmentVersionActivate
  RequestInvestmentVersionDelete
  RequestInvestmentIndexCreate
  RequestInvestmentIndexUpdate
  RequestInvestmentIndexDelete
  InvestmentCommandFinished(String, String)
  InvestmentCommandFailed(String)
  AuditLoaded(String)
  AuditActionsLoaded(String)
  AuditLoadFailed
  DynamicCostLoaded(String)
  DynamicCostLoadFailed
  InputDynamicCostProject(String)
  ViewDynamicCostRemarks(String)
  DynamicCostRemarksLoaded(String)
  DynamicCostRemarksLoadFailed
  ExportDynamicCostCsv
  ExportDynamicCostXlsx
  DynamicCostExportFinished(@dom.Blob)
  DynamicCostExportFailed
  InputDynamicCostCreateCode(String)
  InputDynamicCostCreateName(String)
  InputDynamicCostCreateLevel(String)
  InputDynamicCostCreateParent(String)
  InputDynamicCostCreateTarget(String)
  InputDynamicCostCreateContractChange(String)
  InputDynamicCostCreateInTransit(String)
  InputDynamicCostCreateBudget(String)
  InputDynamicCostCreateEstimateChange(String)
  InputDynamicCostCreateRemarks(String)
  RequestDynamicCostCreate
  DynamicCostCommandFinished(String)
  DynamicCostCommandFailed
  CostDashboardLoaded(String)
  CostDashboardLoadFailed
  CashflowLoaded(String)
  CashflowLoadFailed
  CashflowInflowLoaded(String)
  CashflowInflowLoadFailed
  ExplainCashflow
  CashflowExplainFinished(String)
  CashflowExplainFailed
  CbsLoaded(String)
  CbsLoadFailed
  CbsR0Loaded(String)
  CbsR0LoadFailed
  FundLoaded(String)
  FundLoadFailed
  FundGapLoaded(String)
  FundGapLoadFailed
  FundDispatchLoaded(String)
  FundDispatchLoadFailed
  SelectFundProject(String)
  SelectFundTab(String)
  OpenFundForm(String)
  CloseFundForm
  InputFundField(String, String)
  CreateFundPlan
  UpdateFundPlan
  DeleteFundPlan
  OpenFundPlanEdit(String)
  DeleteFundPlanRow(String)
  SelectFundDispatch(String)
  CreateFundDispatch
  ApproveFundDispatch
  FundCommandFinished(String)
  FundCommandFailed
  WarningsLoaded(String)
  WarningsLoadFailed
  WarningRulesLoaded(String)
  WarningRulesLoadFailed
  ResolveWarning
  IgnoreWarning
  WarningCommandFinished(String)
  WarningCommandFailed
  PreviewWarningScan
  WarningScanPreviewFinished(String)
  WarningScanPreviewFailed
  PreviewWarningCustomRule
  WarningCustomRulePreviewFinished(String)
  WarningCustomRulePreviewFailed
  CreateWarningCustomRule
  DeleteWarningCustomRule
  WarningCustomRuleCommandFinished(String)
  WarningCustomRuleCommandFailed
  CreateWarningTicket
  HandleWarningTicket
  CompleteWarningTicket
  ReassignWarningTicket
  ExtendWarningTicket
  WarningTicketCommandFinished(String, String)
  WarningTicketCommandFailed(String)
  AttachmentsLoaded(String)
  AttachmentsLoadFailed
  AttachmentStatsLoaded(String)
  AttachmentStatsLoadFailed
  InputAttachmentBizType(String)
  InputAttachmentAiStatus(String)
  InputAttachmentKeyword(String)
  AttachmentFileSelected(String)
  SearchAttachments
  AttachmentAction(String, String)
  RequestAttachmentUpload
  AttachmentCommandFinished(String)
  AttachmentCommandFailed
  RequestAttachmentDownload
  AttachmentDownloadFinished(String)
  AttachmentDownloadFailed
  RequestAttachmentReextract
  AttachmentReextractFinished(String)
  AttachmentReextractFailed
  RequestAttachmentDelete
  AttachmentDeleteFinished(String)
  AttachmentDeleteFailed
  MarketingLoaded(String, String)
  MarketingLoadFailed(String)
  SelectMarketingProject(String)
  SelectMarketingTab(String)
  OpenMarketingForm(String)
  CloseMarketingForm
  InputMarketingField(String, String)
  CreateMarketingCampaign
  CreateMarketingPlacement
  CreateMarketingChannel
  CreateMarketingMaterial
  MarketingCommandFinished(String)
  MarketingCommandFailed
  DeleteMarketingCampaign(String)
  InboxLoaded(String)
  InboxLoadFailed
  InboxUnreadLoaded(String)
  InboxUnreadLoadFailed
  MarkInboxReadAll
  InboxCommandFinished(String)
  InboxCommandFailed
  NotifySubscriptionsLoaded(String)
  CreateNotifySubscription
  NotifyCommandFinished(String)
  NotifyCommandFailed
  DispatchNotifyDigest
  NotifyDigestDispatchFinished(String)
  NotifyDigestDispatchFailed
  TestNotifyEmail
  RedeliverNotifyEmail
  NotifyEmailCommandFinished(String, String)
  NotifyEmailCommandFailed(String)
  NotifyConfigLoaded(String)
  NotifyOutboxLoaded(String)
  NotifyDigestPreviewLoaded(String)
  NotifyDigestLoaded(String)
  NotifyProvidersLoaded(String)
  NotifyLoadFailed(String)
  OcrLoaded(String)
  OcrLoadFailed
  SaveOcrConfig
  OcrConfigCommandFinished(String)
  OcrConfigCommandFailed
  TestOcrProvider
  OcrCommandFinished(String)
  OcrCommandFailed
  TestLlmProvider
  TestNotifyLlmProvider
  ProviderCommandFinished(String, String)
  ProviderCommandFailed(String)
  ErrorLogLoaded(String)
  ErrorLogLoadFailed
  AiStatsOverviewLoaded(String)
  AiStatsActivityLoaded(String)
  AiStatsLoadFailed
  ExportAiStats
  AiStatsExportFinished(@dom.Blob)
  AiStatsExportFailed
  AiHubUsageLoaded(String)
  AiHubDraftsLoaded(String)
  AiHubQueryLogLoaded(String)
  AiHubCorrectionStatsLoaded(String)
  AiHubCorrectionsLoaded(String)
  AiHubLoadFailed
  ExplainAiHub
  AiHubExplainFinished(String)
  AiHubExplainFailed
  InputAiHubIntakeDescription(String)
  InputAiHubIntakeBizHint(String)
  AiHubFileSelected(String)
  InputAiHubQueryText(String)
  InputAiHubCommandText(String)
  RunAiHubCommand(String)
  AiHubCommandFinished(String, String)
  AiHubCommandFailed(String)
  WebhookLoaded(String)
  WebhookLoadFailed
  SaveWebhookConfig
  WebhookConfigCommandFinished(String)
  WebhookConfigCommandFailed
  TestWebhookDelivery
  WebhookCommandFinished(String)
  WebhookCommandFailed
  PreviewWebhookOverdue
  WebhookOverduePreviewFinished(String)
  WebhookOverduePreviewFailed
  ScanWebhookOverdue
  WebhookOverdueScanFinished(String)
  WebhookOverdueScanFailed
  ReportBuilderMetaLoaded(String)
  ReportBuilderTemplatesLoaded(String)
  ReportBuilderLoadFailed
  CreateReportTemplate
  RunReportTemplate
  DeleteReportTemplate
  ReportBuilderCommandFinished(String)
  ReportBuilderRunFinished(String)
  ReportBuilderCommandFailed
  ProfileLoaded(String)
  ProfileLoadFailed
  ProfileInitiatedLoaded(String)
  ProfileInitiatedLoadFailed
  UpdateProfile
  InputProfileName(String)
  InputProfilePasswordOld(String)
  InputProfilePasswordNew(String)
  InputProfilePasswordConfirm(String)
  ProfileCommandFinished(String)
  ProfileCommandFailed
  ChangePassword
  UsersLoaded(String)
  UsersLoadFailed
  CreateLocalUser
  RbacUserCommandFinished(String)
  RbacUserCommandFailed
  CreateLocalRole
  RbacRoleCommandFinished(String)
  RbacRoleCommandFailed
  AssignLocalRole
  RbacAssignmentFinished(String)
  RbacAssignmentFailed
  ToggleAdminUser
  RbacUserToggleFinished(String)
  RbacUserToggleFailed
  ResetAdminUserPassword
  RbacUserResetFinished(String)
  RbacUserResetFailed
  UpdateAdminUser
  RbacUserUpdateFinished(String)
  RbacUserUpdateFailed
  DeleteLocalRole
  RbacRoleDeleteFinished(String)
  RbacRoleDeleteFailed
  RbacRolesLoaded(String)
  RbacRolesLoadFailed
  RbacCatalogLoaded(String)
  RbacCatalogLoadFailed
  HealthTablesLoaded(String)
  HealthBpmLoaded(String)
  HealthInventoryLoaded(String)
  HealthInventoryLoadFailed
  HealthLoadFailed
  LoansLoaded(String)
  LoansLoadFailed
  CreateLoan
  SubmitLoan
  UpdateLoan
  VoidLoan
  SyncLoanWorkflow
  LoanWorkflowSyncFinished(String)
  LoanWorkflowSyncFailed
  LoanCommandFinished(String)
  LoanCommandFailed
  WorkflowLoaded(String)
  WorkflowLoadFailed
  WorkflowObservationPendingLoaded(String)
  WorkflowObservationInitiatedLoaded(String)
  WorkflowObservationHistoryLoaded(String)
  WorkflowObservationLoadFailed
  WorkflowTicketsLoaded(String)
  WorkflowTicketsLoadFailed
  SelectWorkflowTab(String)
  StartWorkflowCandidate
  ApproveWorkflowCandidate
  RejectWorkflowCandidate
  CosignWorkflowCandidate
  TransferWorkflowCandidate
  WorkflowCommandFinished(String, String)
  WorkflowCommandFailed(String)
  BudgetScopeLoaded(String)
  BudgetLoanBalanceLoaded(String)
  BudgetScopeLoadFailed
  ProjectsLoaded(String)
  ProjectsLoadFailed
  ProjectLoaded(String)
  ProjectLoadFailed
  ProjectStagesLoaded(String)
  ProjectStagesLoadFailed
  ProjectKpiLoaded(String)
  ProjectKpiLoadFailed
  ProjectAnomaliesLoaded(String)
  ProjectAnomaliesLoadFailed
  DownloadImportTemplate(String)
  ImportTemplateDownloaded(String, @dom.Blob)
  ImportTemplateDownloadFailed(String)
  SelectImportFile(String, String)
  ImportCsvLoaded(String, String)
  RunImportDryRun
  CommitImportBatch
  ImportCommandFinished(String, String)
  ImportCommandFailed(String)
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
    expenses_loaded: false,
    expense_rows: [],
    expenses_note: "报销读模型尚未加载 · 使用设计快照",
    expense_detail_loaded: false,
    expense_detail: None,
    expense_detail_note: "报销详情读模型尚未加载 · 使用设计快照",
    api_status: "未连接",
    api_note: "使用已审核快照",
    expense_id: "EXP-RABBITA-LOCAL",
    expense_state: "未创建",
    expense_note: "先保存草稿，再提交审批",
    expense_budget_check_note: "预算预检尚未运行",
    contracts_loaded: false,
    contract_rows: [],
    contract_detail: None,
    contract_milestones: [],
    contract_id: "CT-RABBITA-LOCAL",
    contract_state: "new",
    contract_note: "先保存草稿，再提交审批",
    contract_milestone_node_name: "",
    contract_milestone_trigger_type: "time",
    contract_milestone_trigger_value: "",
    contract_milestone_plan_date: "",
    contract_milestone_plan_amount: "0",
    contract_milestone_plan_pct: "0",
    contract_milestone_notes: "",
    contract_milestone_command_note: "付款节点命令候选尚未运行",
    payment_applies_loaded: false,
    payment_apply_rows: [],
    payment_apply_id: "PAY-RABBITA-LOCAL",
    payment_apply_state: "new",
    payment_apply_note: "先保存付款申请草稿，再提交审批",
    payment_apply_eligibility_note: "尚未校验付款节点条件",
    tenders_loaded: false,
    tender_project_id: "proj-0001",
    tender_selected_source_kind: "command",
    tender_form_open: "",
    tender_name: "",
    tender_category: "建安工程",
    tender_estimated_amount: "0",
    tender_plan_publish_date: "2026-07-16",
    tender_plan_award_date: "",
    tender_remark: "",
    tender_award_provider_guid: "",
    tender_award_provider_name: "",
    tender_award_amount: "0",
    tender_award_date: "2026-07-16",
    tender_award_remark: "",
    tender_tab: "tenders",
    tender_rows: [],
    tender_award_rows: [],
    tender_id: "TD-RABBITA-LOCAL",
    tender_state: "new",
    tender_note: "合约规划读模型尚未加载",
    tender_source_loaded: false,
    tender_source_award_count: "0",
    tender_source_split_count: "0",
    tender_source_note: "源招标/定标/分判观察尚未加载 · 使用设计快照",
    tender_source_command_note: "源招标命令候选尚未执行",
    suppliers_loaded: false,
    supplier_rows: [],
    supplier_source_loaded: false,
    supplier_source_rows: [],
    supplier_source_missing_table_count: "0",
    supplier_source_note: "供应商源表读模型尚未加载 · 使用设计快照",
    supplier_dict_loaded: false,
    supplier_category_count: "0",
    supplier_eval_count: "0",
    supplier_source_count: "0",
    supplier_dict_note: "供应商字典源观察尚未加载 · 使用设计快照",
    supplier_risk_loaded: false,
    supplier_risk_rows: [],
    supplier_risk_distribution_total: "0",
    supplier_risk_missing_table_count: "0",
    supplier_risk_note: "供应商风险读模型尚未加载 · 使用设计快照",
    supplier_id: "SUP-RABBITA-LOCAL",
    supplier_state: "new",
    supplier_evaluation: "unrated",
    supplier_note: "供应商读模型尚未加载",
    supplier_detail_loaded: false,
    supplier_detail: None,
    supplier_detail_note: "供应商源详情尚未加载 · 使用设计快照",
    supplier_detail_risk_loaded: false,
    supplier_detail_risk_score: "0",
    supplier_detail_risk_rating: "未定级",
    supplier_detail_risk_tags: "源表未提供",
    supplier_detail_risk_contract_count: "0",
    supplier_detail_risk_overdue_count: "0",
    supplier_detail_risk_note: "供应商源风险详情尚未加载 · 使用设计快照",
    supplier_check_sign_note: "供应商签约校验边界尚未检查",
    supplier_stats_loaded: false,
    supplier_stats_total: "0",
    supplier_stats_contract_rows: "0",
    supplier_stats_top_business: "源表未提供",
    supplier_stats_note: "供应商统计源读模型尚未加载 · 使用设计快照",
    sales_loaded: false,
    sales_family: "",
    sales_rows: [],
    sales_customer_rows: [],
    sales_customer_project_id: "",
    sales_customer_keyword: "",
    sales_customer_form_open: false,
    sales_customer_edit_id: "",
    sales_customer_name: "",
    sales_customer_id_card_no: "",
    sales_customer_phone: "",
    sales_customer_source: "案场",
    sales_customer_remark: "",
    sales_subscription_rows: [],
    sales_subscription_loaded: false,
    sales_subscription_project_id: "",
    sales_subscription_state: "",
    sales_subscription_form_open: false,
    sales_subscription_customer_guid: "",
    sales_subscription_proj_guid: "",
    sales_subscription_building_no: "",
    sales_subscription_unit_no: "",
    sales_subscription_area: "0",
    sales_subscription_unit_price: "0",
    sales_subscription_total_price: "0",
    sales_subscription_sub_amount: "0",
    sales_subscription_sub_date: "2026-07-16",
    sales_subscription_payment_type: "按揭",
    sales_contract_rows: [],
    sales_contract_loaded: false,
    sales_contract_project_id: "",
    sales_contract_state: "",
    sales_mortgage_rows: [],
    sales_mortgage_loaded: false,
    sales_mortgage_filter_state: "",
    sales_mortgage_form_open: false,
    sales_mortgage_form_contract: "",
    sales_mortgage_form_customer: "",
    sales_mortgage_form_bank: "建设银行",
    sales_mortgage_form_amount: "0",
    sales_mortgage_form_years: "30",
    sales_mortgage_form_rate: "0.0485",
    sales_mortgage_form_date: "2026-07-16",
    sales_mortgage_form_remark: "",
    sales_refund_form_open: false,
    sales_refund_form_contract: "",
    sales_refund_form_customer: "",
    sales_refund_form_reason: "",
    sales_refund_form_amount: "0",
    sales_refund_form_date: "2026-07-16",
    sales_revenue_rows: [],
    sales_revenue_loaded: false,
    sales_revenue_project_id: "",
    sales_revenue_filter_status: "",
    sales_revenue_keyword: "",
    sales_revenue_form_open: false,
    sales_revenue_editing_id: "",
    sales_revenue_form_project: "",
    sales_revenue_form_customer: "",
    sales_revenue_form_amount: "0",
    sales_revenue_form_date: "2026-07-16",
    sales_revenue_form_status: "expected",
    sales_revenue_form_payment_type: "首付",
    sales_revenue_form_contract_no: "",
    sales_revenue_form_remark: "",
    sales_note: "销售/应收读模型尚未加载",
    sales_customer_command_note: "客户命令尚未执行",
    sales_subscription_command_note: "认筹命令尚未执行",
    sales_mortgage_id: "MTG-RABBITA-LOCAL",
    sales_mortgage_state: "new",
    sales_mortgage_command_note: "按揭命令尚未执行",
    sales_refund_id: "RF-RABBITA-LOCAL",
    sales_refund_state: "new",
    sales_refund_command_note: "退款命令尚未执行",
    sales_revenue_id: "REV-RABBITA-LOCAL",
    sales_revenue_state: "new",
    sales_revenue_command_note: "本地回款登记需要销售/财务 authority；不会自动释放现金或过账",
    invoice_source_loaded: false,
    invoice_project_id: "proj-0001",
    invoice_tab: "in",
    invoice_form_open: "",
    invoice_no: "",
    invoice_counterparty: "",
    invoice_date: "2026-07-16",
    invoice_total_amount: "0",
    invoice_tax_rate: "0.09",
    invoice_type: "增值税专用发票",
    invoice_remark: "",
    invoice_in_rows: [],
    invoice_out_rows: [],
    invoice_tax_rows: [],
    invoice_source_in_count: "0",
    invoice_source_out_count: "0",
    invoice_source_tax_count: "0",
    invoice_source_note: "发票源读模型尚未加载 · 使用设计快照",
    delivery_loaded: false,
    delivery_project_id: "proj-0001",
    delivery_tab: "progress",
    delivery_progress_rows: [],
    delivery_output_rows: [],
    delivery_source_progress_rows: [],
    delivery_source_output_rows: [],
    delivery_task_rows: [],
    delivery_report_rows: [],
    delivery_note: "工程进度/项目计划读模型尚未加载",
    delivery_source_loaded: false,
    delivery_source_progress_count: "0",
    delivery_source_output_count: "0",
    delivery_source_note: "源进度/产值观察尚未加载 · 使用设计快照",
    delivery_form_open: "",
    delivery_building_no: "1-1",
    delivery_stage: "",
    delivery_plan_date: "2026-07-16",
    delivery_plan_pct: "100",
    delivery_contract_id: "",
    delivery_remark: "",
    delivery_report_actual_pct: "0",
    delivery_report_date: "2026-07-16",
    delivery_report_remark: "",
    delivery_output_contract_id: "",
    delivery_output_period: "2026-07",
    delivery_output_amount: "0",
    delivery_output_remark: "",
    delivery_progress_id: "PROG-RABBITA-LOCAL",
    delivery_progress_state: "new",
    delivery_output_id: "OUT-RABBITA-LOCAL",
    delivery_output_state: "new",
    delivery_task_id: "task-003",
    delivery_command_note: "导入任务保持只读；本地命令需要证据并写入审计",
    project_plan_project_id: "proj-0001",
    plan_task_id: "",
    plan_task_state: "idle",
    plan_task_command_note: "项目计划任务命令尚未运行",
    plan_ai_suggestion_note: "AI 计划建议尚未运行 · provider/LLM 保持关闭",
    plan_ai_suggestion_rows: [],
    plan_ai_proj_type: "住宅",
    plan_ai_scale: "中型",
    plan_ai_region: "全国",
    plan_ai_begin_date: "2026-08-01",
    plan_report_task_id: "task-003",
    plan_report_task_name: "主体结构施工",
    plan_report_progress: "0",
    plan_report_date: "2026-07-16",
    plan_report_summary: "",
    plan_create_task_code: "",
    plan_create_task_name: "",
    plan_create_task_type: "task",
    plan_create_begin_date: "2026-08-01",
    plan_create_end_date: "",
    plan_create_owner: "",
    plan_create_remarks: "",
    plan_delay_task_id: "",
    plan_delay_days: "7",
    plan_delay_note: "尚未计算延期影响",
    plan_delay_rows: [],
    reports_loaded: false,
    report_tab: "cost",
    report_cost_rows: [],
    report_contract_rows: [],
    report_supplier_rows: [],
    report_approval_rows: [],
    report_slow_step_rows: [],
    report_stage_rows: [],
    report_stage_names: [],
    report_share_dialog: false,
    report_share_list_open: false,
    report_share_title: "",
    report_share_days: "7",
    report_share_result_token: "",
    report_share_result_url: "",
    report_share_rows: [],
    report_share_note: "报表分享尚未执行",
    report_favorite_loaded: false,
    report_favorite_keys: [],
    share_loaded: false,
    share_meta_loaded: false,
    share_token: "",
    share_report_key: "",
    share_report_label: "",
    share_title: "",
    share_expires_at: "",
    share_never_expires: false,
    share_data_body: "",
    share_note: "分享报表尚未加载",
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
    dashboard_v2_loaded: false,
    dashboard_v2_project_count: "0",
    dashboard_v2_in_progress: "0",
    dashboard_v2_contract_amount: "0",
    dashboard_v2_unpaid_amount: "0",
    dashboard_v2_open_warnings: "0",
    dashboard_v2_running_processes: "0",
    dashboard_v2_trend_rows: [],
    dashboard_v2_stage_rows: [],
    dashboard_v2_warning_rows: [],
    dashboard_v2_missing_table_count: "0",
    dashboard_v2_note: "驾驶舱 v2 源观察尚未加载 · 不使用合成管理指标",
    dashboard_v3_loaded: false,
    dashboard_v3: empty_dashboard_v3(),
    dashboard_v3_note: "驾驶舱 v3 源观察尚未加载 · 不使用合成管理指标",
    admin_quality_loaded: false,
    admin_quality_rows: [],
    admin_quality_note: "质量规则尚未加载 · 使用设计快照",
    admin_dict_loaded: false,
    admin_dict_group_rows: [],
    admin_dict_option_rows: [],
    admin_dict_note: "数据字典尚未加载 · 使用设计快照",
    admin_dict_command_note: "本地字典命令尚未执行",
    admin_backup_note: "PostgreSQL 备份导出边界尚未检查",
    investment_loaded: false,
    investment_version_id: "",
    investment_version_name: "",
    investment_version_rows: [],
    investment_index_rows: [],
    investment_index_selected: "",
    investment_index_edit_value: "",
    investment_index_edit_remark: "",
    investment_new_version_name: "Rabbita 投资调整版",
    investment_new_version_copy_from: "",
    investment_new_version_remark: "Rabbita 版本创建候选",
    investment_new_version_activate: false,
    investment_new_index_dimension: "investment",
    investment_new_index_full_code: "",
    investment_new_index_name: "",
    investment_new_index_parent_code: "",
    investment_new_index_unit: "万元",
    investment_new_index_value: "0",
    investment_new_index_remark: "Rabbita 指标创建候选",
    investment_dimension_count: "0",
    investment_total: "0",
    investment_revenue: "0",
    investment_cost: "0",
    investment_net_profit: "0",
    investment_net_profit_margin: "0",
    investment_irr: "0",
    investment_sensitivity_loaded: false,
    investment_sensitivity_cases: [],
    investment_sensitivity_note: "投资敏感性读模型尚未加载 · 使用设计快照",
    investment_imports_loaded: false,
    investment_import_rows: [],
    investment_import_note: "Excel 导入历史尚未加载 · 使用设计快照",
    investment_import_selected: "",
    investment_import_detail_note: "尚未选择导入记录",
    investment_import_bridge_note: "尚未读取逻辑桥接计划",
    investment_import_index_preview_note: "尚未读取指标 upsert 预览",
    investment_import_profit_note: "尚未读取利润测算总表",
    investment_import_plan_note: "尚未读取计划行预览",
    investment_actual_loaded: false,
    investment_actual_code: "",
    investment_actual_message: "",
    investment_actual_simulation: "false",
    investment_actual_missing_table_count: "0",
    investment_actual_note: "实际利润对比尚未加载 · 保持审批边界",
    investment_note: "投资测算读模型尚未加载 · 使用设计快照",
    investment_explain_note: "解释候选尚未运行 · provider/LLM 保持关闭",
    investment_explain_text: "等待投资解释候选",
    investment_project_id: "proj-0001",
    investment_project_name: "天津海教园一期",
    investment_excel_file_name: "",
    investment_excel_version_name: "",
    investment_excel_activate: false,
    investment_upload_note: "Excel 工作簿上传候选尚未运行 · 二进制解析保持关闭",
    investment_mapping_note: "科目映射候选尚未运行 · 投资主数据保持只读",
    investment_plan_line_note: "计划行编辑候选尚未运行 · 投资计划保持只读",
    investment_index_upsert_note: "Excel 指标 upsert 候选尚未运行 · 投资指标保持只读",
    investment_plan_line_import_note: "Excel 计划行导入候选尚未运行 · 投资计划保持只读",
    investment_command_note: "投资版本/指标命令候选尚未运行",
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
    dynamic_cost_project_id: "proj-0001",
    dynamic_cost_remark_loaded: false,
    dynamic_cost_remark_code: "",
    dynamic_cost_remark_name: "",
    dynamic_cost_remark_text: "",
    dynamic_cost_remark_project: "",
    dynamic_cost_remark_source: "",
    dynamic_cost_remark_note: "点击成本 A / B / H 查看科目备注",
    dynamic_cost_export_note: "尚未导出动态成本",
    dynamic_cost_create_code: "",
    dynamic_cost_create_name: "",
    dynamic_cost_create_level: "2",
    dynamic_cost_create_parent: "",
    dynamic_cost_create_target: "0",
    dynamic_cost_create_contract_change: "0",
    dynamic_cost_create_in_transit: "0",
    dynamic_cost_create_budget: "0",
    dynamic_cost_create_estimate_change: "0",
    dynamic_cost_create_remarks: "",
    dynamic_cost_command_note: "动态成本科目命令候选尚未运行",
    cost_dashboard_loaded: false,
    cost_dashboard_rows: [],
    cost_dashboard_project_name: "",
    cost_dashboard_plan_version: "",
    cost_dashboard_target: "0",
    cost_dashboard_dynamic: "0",
    cost_dashboard_deviation: "0",
    cost_dashboard_contract_count: "0",
    cost_dashboard_expense_count: "0",
    cost_dashboard_change_count: "0",
    cost_dashboard_note: "成本驾驶舱 v3 源读模型尚未加载 · 使用设计快照",
    cashflow_loaded: false,
    cashflow_rows: [],
    cashflow_planned_total: "0",
    cashflow_pending_total: "0",
    cashflow_confirmed_total: "0",
    cashflow_expense_total: "0",
    cashflow_loan_total: "0",
    cashflow_total_outflow: "0",
    cashflow_missing_table_count: "0",
    cashflow_note: "现金流预测读模型尚未加载 · 使用设计快照",
    cashflow_inflow_loaded: false,
    cashflow_inflow_total: "0",
    cashflow_inflow_missing_table_count: "0",
    cashflow_inflow_note: "回款源读模型尚未加载",
    cashflow_explain_note: "解释候选尚未运行 · provider/LLM 保持关闭",
    cashflow_explain_text: "等待现金流解释候选",
    cbs_loaded: false,
    cbs_rows: [],
    cbs_plan_version: "baseline",
    cbs_r0_count: "0",
    cbs_missing_table_count: "0",
    cbs_note: "CBS 读模型尚未加载 · 使用设计快照",
    fund_loaded: false,
    fund_project_id: "proj-0001",
    fund_tab: "plans",
    fund_form_open: "",
    fund_plan_period: "2026-08",
    fund_plan_direction: "out",
    fund_plan_category: "工程款",
    fund_plan_r_code: "R11",
    fund_plan_amount: "50",
    fund_plan_actual_amount: "0",
    fund_plan_remark: "",
    fund_dispatch_from: "",
    fund_dispatch_to: "",
    fund_dispatch_amount: "10",
    fund_dispatch_reason: "",
    fund_dispatch_date: "2026-07-16",
    fund_rows: [],
    fund_gap_rows: [],
    fund_dispatch_rows: [],
    fund_gap_series_count: "0",
    fund_dispatch_count: "0",
    fund_missing_table_count: "0",
    fund_note: "资金计划读模型尚未加载 · 使用设计快照",
    fund_plan_id: "",
    fund_dispatch_id: "",
    fund_command_state: "idle",
    fund_command_note: "资金计划命令尚未运行",
    warnings_loaded: false,
    warning_rows: [],
    warning_rule_count: "0",
    warning_missing_table_count: "0",
    warning_note: "预警读模型尚未加载 · 使用设计快照",
    warning_action_state: "未执行",
    warning_action_note: "告警处理命令仍未执行",
    warning_rule_preview_note: "自定义规则预览尚未执行",
    warning_rule_command_note: "自定义规则命令尚未执行",
    warning_ticket_note: "告警工单候选尚未执行",
    warning_action_guid: "",
    attachments_loaded: false,
    attachment_rows: [],
    attachment_total: "0",
    attachment_bytes: "0",
    attachment_pending: "0",
    attachment_missing_table_count: "0",
    attachment_note: "附件源读模型尚未加载 · 使用设计快照",
    attachment_biz_type: "",
    attachment_ai_status: "",
    attachment_keyword: "",
    attachment_file_name: "",
    attachment_file_mime: "",
    attachment_file_size: "",
    attachment_action_guid: "ATT-RABBITA-LOCAL",
    attachment_action_note: "OCR 重提取候选尚未运行 · provider/OCR 保持关闭",
    attachment_download_note: "附件下载边界尚未检查",
    attachment_delete_note: "删除候选尚未运行 · 对象存储与负责人确认保持关闭",
    marketing_loaded: false,
    marketing_project_id: "proj-0001",
    marketing_tab: "campaigns",
    marketing_form_open: "",
    marketing_campaign_name: "",
    marketing_campaign_type: "推广活动",
    marketing_campaign_budget: "50",
    marketing_campaign_start: "2026-07-16",
    marketing_campaign_end: "",
    marketing_campaign_goal: "",
    marketing_campaign_remark: "",
    marketing_placement_campaign: "",
    marketing_placement_channel: "",
    marketing_placement_channel_name: "",
    marketing_placement_amount: "10",
    marketing_placement_date: "2026-07-16",
    marketing_placement_duration: "30",
    marketing_channel_name: "",
    marketing_channel_type: "线上",
    marketing_channel_contact: "",
    marketing_channel_phone: "",
    marketing_material_name: "",
    marketing_material_type: "现场包装",
    marketing_material_unit_cost: "100",
    marketing_material_quantity: "1",
    marketing_campaign_rows: [],
    marketing_placement_rows: [],
    marketing_channel_rows: [],
    marketing_material_rows: [],
    marketing_campaign_count: "0",
    marketing_placement_count: "0",
    marketing_channel_count: "0",
    marketing_material_count: "0",
    marketing_missing_table_count: "0",
    marketing_note: "营销源读模型尚未加载 · 使用设计快照",
    inbox_loaded: false,
    inbox_rows: [],
    inbox_total: "0",
    inbox_unread: "0",
    inbox_missing_table_count: "0",
    inbox_note: "站内信源读模型尚未加载 · 使用设计快照",
    notify_loaded: false,
    notify_subscription_rows: [],
    notify_config_rows: [],
    notify_outbox_rows: [],
    notify_digest_rows: [],
    notify_subscription_count: "0",
    notify_configured_count: "0",
    notify_outbox_count: "0",
    notify_digest_count: "0",
    notify_missing_table_count: "0",
    notify_note: "通知配置源读模型尚未加载 · 使用设计快照",
    notify_email_note: "邮件命令候选尚未执行",
    ocr_loaded: false,
    ocr_provider: "mock",
    ocr_scene: "auto",
    ocr_provider_rows: [],
    ocr_configured_count: "0",
    ocr_missing_table_count: "0",
    ocr_note: "OCR 源读模型尚未加载 · 使用设计快照",
    ocr_command_note: "OCR 测试命令尚未执行",
    provider_test_note: "LLM/provider 测试命令尚未执行",
    error_loaded: false,
    error_rows: [],
    error_total: "0",
    error_today_count: "0",
    error_five_xx_count: "0",
    error_missing_table_count: "0",
    error_note: "错误日志源读模型尚未加载 · 使用设计快照",
    ai_stats_loaded: false,
    ai_stats_period: "month",
    ai_stats_intake_total: "0",
    ai_stats_query_total: "0",
    ai_stats_skip_total: "0",
    ai_stats_correction_total: "0",
    ai_stats_accuracy: "100",
    ai_stats_saved_hours: "0",
    ai_stats_scene_rows: [],
    ai_stats_activity_rows: [],
    ai_stats_missing_table_count: "0",
    ai_stats_note: "AI 分析源读模型尚未加载 · 使用设计快照",
    ai_stats_export_note: "XLSX 导出尚未执行",
    ai_hub_loaded: false,
    ai_hub_draft_rows: [],
    ai_hub_query_rows: [],
    ai_hub_correction_rows: [],
    ai_hub_monthly_calls: "0",
    ai_hub_minutes_saved: "0",
    ai_hub_intake_total: "0",
    ai_hub_correction_total: "0",
    ai_hub_correction_rate: "0",
    ai_hub_missing_table_count: "0",
    ai_hub_note: "AI 工作台源读模型尚未加载 · 使用设计快照",
    ai_hub_explain_note: "解释候选尚未运行 · provider/LLM 保持关闭",
    ai_hub_explain_text: "等待解释候选",
    ai_hub_intake_description: "",
    ai_hub_intake_biz_hint: "expense",
    ai_hub_file_name: "",
    ai_hub_query_text: "",
    ai_hub_command_text: "",
    ai_hub_command_note: "AI Hub 命令候选尚未运行 · 需要 AI 负责人确认",
    webhook_loaded: false,
    webhook_rows: [],
    webhook_missing_table_count: "0",
    webhook_note: "Webhook 配置源读模型尚未加载 · 使用设计快照",
    webhook_command_note: "Webhook 测试命令尚未执行",
    report_builder_loaded: false,
    report_builder_table_rows: [],
    report_builder_template_rows: [],
    report_builder_missing_table_count: "0",
    report_builder_note: "自定义报表源读模型尚未加载 · 使用设计快照",
    report_builder_command_state: "未执行",
    report_builder_command_note: "模板创建、运行、删除仍未执行",
    report_builder_template_id: "",
    report_builder_run_rows: [],
    users_loaded: false,
    user_roster_rows: [],
    users_note: "身份读模型尚未加载 · 使用设计快照",
    rbac_roles_loaded: false,
    rbac_role_rows: [],
    rbac_roles_note: "角色读模型尚未加载 · 使用设计快照",
    rbac_catalog_loaded: false,
    rbac_catalog_rows: [],
    rbac_catalog_note: "权限目录读模型尚未加载 · 使用设计快照",
    profile_loaded: false,
    profile_user_id: "user-admin-0001",
    profile_user_code: "admin",
    profile_user_name: "系统管理员",
    profile_edit_name: "系统管理员",
    profile_password_old: "",
    profile_password_new: "",
    profile_password_confirm: "",
    profile_bu_guid: "bu-group-0001",
    profile_bu_name: "集团总部",
    profile_dept_name: "数字化中心",
    profile_super_user: "是",
    profile_enabled: "是",
    profile_last_login: "2026-07-13 09:38",
    profile_source_kind: "设计快照",
    profile_note: "个人资料读模型尚未加载 · 使用设计快照",
    profile_command_note: "个人资料命令尚未执行",
    profile_initiated_loaded: false,
    profile_initiated_rows: [],
    profile_initiated_note: "本人发起读模型尚未加载 · 使用设计快照",
    health_loaded: false,
    health_table_rows: [],
    health_source_table_count: "0",
    health_missing_table_count: "0",
    health_bpm_instance_count: "0",
    health_bpm_action_count: "0",
    health_note: "系统健康读模型尚未加载 · 使用设计快照",
    health_inventory_loaded: false,
    health_inventory_schema_count: "0",
    health_inventory_snapshot_count: "0",
    health_inventory_schema_only_count: "0",
    health_inventory_export_state: "待读取",
    health_inventory_snapshot_id: "",
    health_inventory_note: "迁移源范围尚未加载 · 使用设计快照",
    loans_loaded: false,
    loan_rows: [],
    loan_note: "员工借款读模型尚未加载",
    budget_scope_loaded: false,
    budget_scope_users: [],
    budget_scope_note: "预算人员范围源读模型尚未加载 · 使用设计快照",
    budget_loan_balance_loaded: false,
    budget_loan_balance_total: "0",
    budget_loan_count: "0",
    budget_loan_note: "个人借款余额源读模型尚未加载",
    loan_id: "LOAN-RABBITA-LOCAL",
    loan_state: "new",
    loan_command_note: "本地借款命令需要员工范围 authority 与证据",
    loan_workflow_sync_note: "工作流同步候选尚未运行 · wf_process_instance 源行保持只读",
    workflow_loaded: false,
    workflow_process_rows: [],
    workflow_note: "工作流定义读模型尚未加载",
    workflow_observation_loaded: false,
    workflow_pending_rows: [],
    workflow_initiated_rows: [],
    workflow_history_rows: [],
    workflow_task_tab: "pending",
    workflow_tickets_loaded: false,
    workflow_ticket_rows: [],
    workflow_ticket_note: "告警工单源读模型尚未加载",
    workflow_observation_note: "工作流实例源读模型尚未加载 · 使用设计快照",
    workflow_command_note: "本地工作流命令候选尚未执行",
    projects_loaded: false,
    project_rows: [],
    project_detail: None,
    project_stage_rows: [],
    project_kpi_loaded: false,
    project_kpi: {
      progress_avg: "0",
      progress_done: "0",
      progress_total_nodes: "0",
      progress_overdue_nodes: "0",
      cost_deviation_pct: "0",
      cost_dynamic: "0",
      cost_target: "0",
      contract_total: "0",
      contract_count: "0",
      payment_paid_ratio: "0",
      payment_paid_total: "0",
      payment_apply_total: "0",
      cash_this_month_plan: "0",
      profit_irr: "",
      profit_net_profit: "",
      profit_npv: "",
      approval_avg_days: "",
    },
    project_kpi_note: "项目 KPI 尚未加载",
    project_anomalies_loaded: false,
    project_anomaly_rows: [],
    project_anomaly_note: "项目风险预警尚未加载",
    project_note: "项目主数据读模型尚未加载",
    import_template_note: "项目/合同 CSV 模板尚未下载",
    import_biz_type: "",
    import_file_name: "",
    import_headers: [],
    import_preview_rows: [],
    import_rows_json: "[]",
    import_row_count: "0",
    import_key: "",
    import_state: "idle",
    import_note: "尚未选择 CSV 文件",
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
        contract_id: json_object_text(
          fields,
          "contract_id",
          json_object_text(fields, "contractGuid", ""),
        ),
        contract_code: json_object_text(
          fields,
          "contract_code",
          json_object_text(fields, "contractCode", ""),
        ),
        contract_name: json_object_text(
          fields,
          "contract_name",
          json_object_text(fields, "contractName", ""),
        ),
        project_id: json_object_text(
          fields,
          "project_id",
          json_object_text(fields, "projGuid", ""),
        ),
        project_name: json_object_text(
          fields,
          "project_name",
          json_object_text(fields, "projName", ""),
        ),
        supplier_id: json_object_text(
          fields,
          "supplier_id",
          json_object_text(fields, "yfProviderName", ""),
        ),
        supplier_name: json_object_text(
          fields,
          "supplier_name",
          json_object_text(fields, "yfProviderName", ""),
        ),
        amount_minor: json_object_text(
          fields,
          "amount_minor",
          json_object_text(fields, "htAmount", "0"),
        ),
        amount_display: json_object_text(fields, "amount_display", "—"),
        currency: json_object_text(fields, "currency", "CNY"),
        sign_date: json_object_text(
          fields,
          "sign_date",
          json_object_text(fields, "signDate", ""),
        ),
        state: json_object_text(fields, "state", ""),
        paid_amount_display: json_object_text(
          fields,
          "paid_amount_display",
          json_object_text(fields, "paidAmount", "—"),
        ),
        milestone_count: json_object_text(
          fields,
          "milestone_count",
          json_object_text(fields, "milestoneCount", "0"),
        ),
        source_kind: json_object_text(
          fields,
          "source_kind",
          json_object_text(fields, "sourceKind", "command"),
        ),
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
              milestone_id: json_object_text(
                fields,
                "milestone_id",
                json_object_text(fields, "milestoneGuid", ""),
              ),
              node_name: json_object_text(
                fields,
                "node_name",
                json_object_text(fields, "nodeName", ""),
              ),
              plan_amount_display: json_object_text(
                fields,
                "plan_amount_display",
                json_object_text(fields, "planAmount", "—"),
              ),
              plan_pct_bps: json_object_text(
                fields,
                "plan_pct_bps",
                json_object_text(fields, "planPct", "0"),
              ),
              trigger_type: json_object_text(
                fields,
                "trigger_type",
                json_object_text(fields, "triggerType", ""),
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
        _ =>
          for value in json_array_field(fields, "data") {
            match contract_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
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
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let detail = match data.get("contract") {
            Some(value) => contract_from_json(value)
            None => None
          }
          let milestones = match data.get("milestones") {
            Some(value) => contract_milestones_from_json(value)
            None => []
          }
          (detail, milestones)
        }
        _ =>
          (
            contract_from_json(parsed),
            match fields.get("milestones") {
              Some(value) => contract_milestones_from_json(value)
              None => []
            },
          )
      }
    _ => (None, [])
  }
}

///|
fn payment_apply_from_json(value : Json) -> PaymentApplyRow? {
  match value {
    Json::Object(fields) =>
      Some({
        apply_id: json_object_text(
          fields,
          "apply_id",
          json_object_text(fields, "htfkApplyGuid", ""),
        ),
        apply_code: json_object_text(
          fields,
          "apply_code",
          json_object_text(fields, "applyCode", ""),
        ),
        contract_id: json_object_text(
          fields,
          "contract_id",
          json_object_text(fields, "contractGuid", ""),
        ),
        contract_name: json_object_text(
          fields,
          "contract_name",
          json_object_text(fields, "contractName", ""),
        ),
        project_name: json_object_text(
          fields,
          "project_name",
          json_object_text(fields, "projName", ""),
        ),
        supplier_name: json_object_text(
          fields,
          "supplier_name",
          json_object_text(fields, "yfProviderName", ""),
        ),
        subject: json_object_text(fields, "subject", ""),
        amount_minor: json_object_text(
          fields,
          "amount_minor",
          json_object_text(fields, "applyAmount", "0"),
        ),
        amount_display: json_object_text(fields, "amount_display", "—"),
        currency: json_object_text(fields, "currency", "CNY"),
        apply_date: json_object_text(
          fields,
          "apply_date",
          json_object_text(fields, "applyDate", ""),
        ),
        operation_state: json_object_text(
          fields,
          "operation_state",
          json_object_text(fields, "operationState", ""),
        ),
        apply_state: json_object_text(
          fields,
          "apply_state",
          json_object_text(fields, "applyState", ""),
        ),
        pay_state: json_object_text(
          fields,
          "pay_state",
          json_object_text(fields, "payState", ""),
        ),
        apply_type_code: json_object_text(
          fields,
          "apply_type_code",
          json_object_text(fields, "applyTypeCode", ""),
        ),
        pay_class: json_object_text(fields, "pay_class", "合同"),
        applied_by: json_object_text(
          fields,
          "applied_by",
          json_object_text(fields, "appliedBy", ""),
        ),
        applied_by_name: json_object_text(
          fields,
          "applied_by_name",
          json_object_text(fields, "appliedByName", ""),
        ),
        source_kind: json_object_text(
          fields,
          "source_kind",
          json_object_text(fields, "sourceKind", "imported"),
        ),
        plan_id: json_object_text(
          fields,
          "plan_id",
          json_object_text(fields, "htfkPlanGuid", ""),
        ),
        milestone_id: json_object_text(
          fields,
          "milestone_id",
          json_object_text(fields, "milestoneGuid", ""),
        ),
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
        _ =>
          for value in json_array_field(fields, "data") {
            match payment_apply_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
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
    Json::Object(fields) => {
      let values = match fields.get("items") {
        Some(Json::Array(values)) => values
        _ => json_array_field(fields, "data")
      }
      for value in values {
        match tender_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn tender_award_from_json(value : Json) -> TenderAwardRow? {
  match value {
    Json::Object(fields) =>
      Some({
        award_code: json_object_text(fields, "award_code", ""),
        tender_id: json_object_text(fields, "tender_guid", ""),
        provider_id: json_object_text(fields, "provider_guid", ""),
        provider_name: json_object_text(fields, "provider_name", ""),
        award_amount: json_object_text(
          fields,
          "award_amount",
          json_object_text(fields, "award_amount_display", "—"),
        ),
        award_date: json_object_text(fields, "award_date", ""),
        remark: json_object_text(fields, "remark", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn tender_award_rows_from_body(body : String) -> Array[TenderAwardRow] {
  let rows : Array[TenderAwardRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("items") {
        Some(Json::Array(values)) => values
        _ => json_array_field(fields, "data")
      }
      for value in values {
        match tender_award_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
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
fn supplier_source_category_code(fields : Map[String, Json]) -> String {
  match fields.get("mainCategory") {
    Some(Json::Object(category)) => json_object_text(category, "code", "")
    _ => ""
  }
}

///|
fn supplier_source_evaluation(fields : Map[String, Json]) -> String {
  match json_object_text(fields, "evalResult", "未定级") {
    "战略" => "strategic"
    "合格" => "qualified"
    "不合格" => "unqualified"
    "黑名单" => "unqualified"
    "已评审" => "reviewed"
    _ => "unrated"
  }
}

///|
fn supplier_source_from_json(value : Json) -> SupplierRow? {
  match value {
    Json::Object(fields) => {
      let enabled = json_object_text(fields, "enabled", "true")
      let eval_result = json_object_text(fields, "evalResult", "未定级")
      let state = if eval_result == "黑名单" {
        "blacklisted"
      } else if enabled == "true" || enabled == "1" {
        "active"
      } else {
        "suspended"
      }
      Some({
        supplier_id: json_object_text(fields, "providerGuid", ""),
        supplier_code: json_object_text(fields, "providerCode", ""),
        name: json_object_text(fields, "providerName", ""),
        category_code: supplier_source_category_code(fields),
        evaluation: supplier_source_evaluation(fields),
        state,
        scope: json_object_text(fields, "businessScope", ""),
        source_kind: json_object_text(fields, "sourceKind", "imported"),
      })
    }
    _ => None
  }
}

///|
fn supplier_source_rows_from_body(
  body : String,
) -> (Array[SupplierRow], String) {
  let rows : Array[SupplierRow] = []
  let mut missing_table_count = 0
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      missing_table_count = json_array_field(
        fields, "missing_or_empty_source_tables",
      ).length()
      for value in json_array_field(fields, "data") {
        match supplier_source_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  (rows, missing_table_count.to_string())
}

///|
fn supplier_detail_business_units(
  value : Json,
) -> Array[SupplierDetailBusinessUnitRow] {
  let rows : Array[SupplierDetailBusinessUnitRow] = []
  match value {
    Json::Array(values) =>
      for value in values {
        match value {
          Json::Object(fields) =>
            rows.push({
              bu_guid: json_object_text(fields, "buGuid", ""),
              bu_code: json_object_text(fields, "buCode", ""),
              bu_name: json_object_text(fields, "buName", ""),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn supplier_detail_contracts(value : Json) -> Array[SupplierDetailContractRow] {
  let rows : Array[SupplierDetailContractRow] = []
  match value {
    Json::Array(values) =>
      for value in values {
        match value {
          Json::Object(fields) =>
            rows.push({
              contract_guid: json_object_text(fields, "contractGuid", ""),
              contract_code: json_object_text(fields, "contractCode", ""),
              contract_name: json_object_text(fields, "contractName", ""),
              amount: json_object_text(fields, "amount", "0"),
              sign_date: json_object_text(fields, "signDate", ""),
              ht_cf_state: json_object_text(fields, "htCfState", ""),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn supplier_detail_from_body(body : String) -> SupplierDetail? {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          match data.get("provider") {
            Some(Json::Object(provider)) => {
              let category_code = match provider.get("mainCategory") {
                Some(Json::Object(category)) =>
                  json_object_text(category, "code", "")
                _ => ""
              }
              let category_name = match provider.get("mainCategory") {
                Some(Json::Object(category)) =>
                  json_object_text(category, "name", "")
                _ => ""
              }
              Some({
                provider_guid: json_object_text(provider, "providerGuid", ""),
                provider_code: json_object_text(provider, "providerCode", ""),
                provider_name: json_object_text(provider, "providerName", ""),
                short_name: json_object_text(provider, "shortName", ""),
                legal_person: json_object_text(provider, "legalPerson", ""),
                business_license: json_object_text(
                  provider, "businessLicense", "",
                ),
                register_capital: json_object_text(
                  provider, "registerCapital", "",
                ),
                business_scope: json_object_text(provider, "businessScope", ""),
                category_code,
                category_name,
                eval_result: json_object_text(
                  provider, "evalResult", "未定级",
                ),
                inspect_state: json_object_text(provider, "inspectState", ""),
                audit_state: json_object_text(provider, "auditState", ""),
                source: json_object_text(provider, "source", ""),
                contact_person: json_object_text(provider, "contactPerson", ""),
                contact_phone: json_object_text(provider, "contactPhone", ""),
                address: json_object_text(provider, "address", ""),
                qualifications: json_object_text(provider, "qualifications", ""),
                enabled: json_object_text(provider, "enabled", "true"),
                created_by: json_object_text(provider, "createdBy", ""),
                created_at: json_object_text(provider, "createdAt", ""),
                process_instance_guid: json_object_text(
                  provider, "processInstanceGuid", "",
                ),
                business_units: match data.get("serviceBus") {
                  Some(value) => supplier_detail_business_units(value)
                  _ => []
                },
                contracts: match data.get("contracts") {
                  Some(value) => supplier_detail_contracts(value)
                  _ => []
                },
              })
            }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn supplier_detail_risk_from_body(
  body : String,
) -> (String, String, String, String, String, String) {
  let mut score = "0"
  let mut rating = "未定级"
  let mut tags = "源表未提供"
  let mut contract_count = "0"
  let mut overdue_count = "0"
  let mut note = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables").length()
      note = if missing == 0 {
        "风险源表已提供"
      } else {
        "缺失/空源表 " + missing.to_string()
      }
      match fields.get("data") {
        Some(Json::Object(data)) => {
          score = json_object_text(data, "score", "0")
          rating = json_object_text(data, "rating", "未定级")
          tags = json_object_text(data, "riskTags", "")
          if tags == "" {
            tags = "无显式风险标签"
          }
          contract_count = json_object_text(data, "contractCount", "0")
          overdue_count = json_object_text(data, "overdueCount", "0")
        }
        _ => ()
      }
    }
    _ => note = "风险源读模型不可用"
  }
  (score, rating, tags, contract_count, overdue_count, note)
}

///|
fn supplier_stats_from_body(body : String) -> (String, String, String, String) {
  let mut total = "0"
  let mut contract_rows = "0"
  let mut top_business = "源表未提供"
  let mut missing_table_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      missing_table_count = json_array_field(
          fields, "missing_or_empty_source_tables",
        )
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          total = json_object_text(data, "total", "0")
          match fields.get("source_coverage") {
            Some(Json::Object(coverage)) =>
              contract_rows = json_object_text(coverage, "cb_contract", "0")
            _ => ()
          }
          let mut found = false
          for value in json_array_field(data, "topBusiness") {
            if !found {
              match value {
                Json::Object(row) => {
                  top_business = json_object_text(
                    row, "name", "源表未提供",
                  )
                  found = true
                }
                _ => ()
              }
            }
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
  (
    total,
    contract_rows,
    top_business,
    "缺失/空源表 " + missing_table_count,
  )
}

///|
fn supplier_risk_from_json(value : Json) -> SupplierRiskRow? {
  match value {
    Json::Object(fields) =>
      Some({
        provider_guid: json_object_text(fields, "providerGuid", ""),
        provider_code: json_object_text(fields, "providerCode", ""),
        provider_name: json_object_text(fields, "providerName", ""),
        short_name: json_object_text(fields, "shortName", ""),
        main_category_code: json_object_text(fields, "mainCategoryCode", ""),
        rating: json_object_text(fields, "rating", ""),
        risk_score: json_object_text(fields, "riskScore", "0"),
        risk_tags: json_object_text(fields, "riskTags", ""),
        rating_updated_at: json_object_text(fields, "ratingUpdatedAt", ""),
        contract_count: json_object_text(fields, "contractCount", "0"),
        contract_total: json_object_text(fields, "contractTotal", "0"),
        overdue_count: json_object_text(fields, "overdueCount", "0"),
        overdue_amount: json_object_text(fields, "overdueAmount", "0"),
        source_kind: json_object_text(fields, "sourceKind", "imported"),
      })
    _ => None
  }
}

///|
fn supplier_risk_from_body(
  body : String,
) -> (Array[SupplierRiskRow], String, String) {
  let rows : Array[SupplierRiskRow] = []
  let mut distribution_total = 0
  let mut missing_table_count = 0
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      missing_table_count = json_array_field(
        fields, "missing_or_empty_source_tables",
      ).length()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "highRisk") {
            match supplier_risk_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
          for value in json_array_field(data, "distribution") {
            match value {
              Json::Object(row) =>
                distribution_total += json_object_int(row, "c")
              _ => ()
            }
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
  (rows, distribution_total.to_string(), missing_table_count.to_string())
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
      } else if aggregate_type == "invoice" {
        json_object_text(
          fields,
          "invoiceNo",
          json_object_text(fields, "name", aggregate_id),
        )
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
        state: json_object_text(
          fields,
          "state",
          json_object_text(fields, "status", ""),
        ),
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
    Json::Object(fields) => {
      let values = match fields.get("items") {
        Some(Json::Array(values)) => values
        _ => json_array_field(fields, "data")
      }
      for value in values {
        match sales_row_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn sales_customer_from_json(value : Json) -> SalesCustomerRow? {
  match value {
    Json::Object(fields) =>
      Some({
        customer_guid: json_object_text(
          fields,
          "customer_guid",
          json_object_text(fields, "customer_id", ""),
        ),
        customer_code: json_object_text(fields, "customer_code", "—"),
        customer_name: json_object_text(
          fields,
          "customer_name",
          json_object_text(fields, "name", "—"),
        ),
        phone: json_object_text(
          fields,
          "phone",
          json_object_text(fields, "contact_reference", "—"),
        ),
        id_card_no: json_object_text(fields, "id_card_no", ""),
        proj_guid: json_object_text(fields, "proj_guid", ""),
        source: json_object_text(fields, "source", ""),
        remark: json_object_text(fields, "remark", ""),
        created_at: json_object_text(fields, "created_at", ""),
        state: json_object_text(fields, "state", "active"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn sales_customer_rows_from_body(body : String) -> Array[SalesCustomerRow] {
  let rows : Array[SalesCustomerRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("items") {
        Some(Json::Array(values)) => values
        _ => json_array_field(fields, "data")
      }
      for value in values {
        match sales_customer_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn sales_subscription_from_json(value : Json) -> SalesSubscriptionRow? {
  match value {
    Json::Object(fields) =>
      Some({
        sub_guid: json_object_text(
          fields,
          "sub_guid",
          json_object_text(fields, "subscription_guid", ""),
        ),
        sub_code: json_object_text(fields, "sub_code", "—"),
        customer_guid: json_object_text(fields, "customer_guid", "—"),
        customer_name: json_object_text(fields, "customer_name", "—"),
        phone: json_object_text(fields, "phone", "—"),
        proj_guid: json_object_text(fields, "proj_guid", ""),
        building_no: json_object_text(fields, "building_no", "—"),
        unit_no: json_object_text(fields, "unit_no", "—"),
        area: json_object_text(fields, "area", "0"),
        unit_price: json_object_text(fields, "unit_price", "0"),
        total_price: json_object_text(fields, "total_price", "0"),
        sub_amount: json_object_text(fields, "sub_amount", "0"),
        sub_date: json_object_text(fields, "sub_date", ""),
        state: json_object_text(
          fields,
          "state",
          json_object_text(fields, "status", "reserved"),
        ),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn sales_subscription_rows_from_body(
  body : String,
) -> Array[SalesSubscriptionRow] {
  let rows : Array[SalesSubscriptionRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("data") {
        Some(Json::Array(values)) => values
        _ =>
          match fields.get("items") {
            Some(Json::Array(values)) => values
            _ => []
          }
      }
      for value in values {
        match sales_subscription_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn sales_parse_number(value : String) -> Double {
  let parsed = @json.parse(value) catch { _ => Json::null() }
  match parsed {
    Json::Number(number, ..) => number
    _ => 0.0
  }
}

///|
fn sales_contract_from_json(value : Json) -> SalesContractRow? {
  match value {
    Json::Object(fields) =>
      Some({
        scontract_guid: json_object_text(
          fields,
          "scontract_guid",
          json_object_text(fields, "contract_guid", ""),
        ),
        scontract_code: json_object_text(
          fields,
          "scontract_code",
          json_object_text(fields, "agreement_id", "—"),
        ),
        customer_guid: json_object_text(fields, "customer_guid", "—"),
        customer_name: json_object_text(fields, "customer_name", "—"),
        phone: json_object_text(fields, "phone", "—"),
        proj_guid: json_object_text(fields, "proj_guid", ""),
        building_no: json_object_text(fields, "building_no", "—"),
        unit_no: json_object_text(fields, "unit_no", "—"),
        area: json_object_text(fields, "area", "0"),
        total_price: json_object_text(fields, "total_price", "0"),
        payment_type: json_object_text(fields, "payment_type", "—"),
        signed_date: json_object_text(fields, "signed_date", ""),
        state: json_object_text(
          fields,
          "state",
          json_object_text(fields, "status", "draft"),
        ),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn sales_contract_rows_from_body(body : String) -> Array[SalesContractRow] {
  let rows : Array[SalesContractRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("data") {
        Some(Json::Array(values)) => values
        _ =>
          match fields.get("items") {
            Some(Json::Array(values)) => values
            _ => []
          }
      }
      for value in values {
        match sales_contract_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn sales_mortgage_from_json(value : Json) -> SalesMortgageRow? {
  match value {
    Json::Object(fields) =>
      Some({
        mortgage_guid: json_object_text(
          fields,
          "mortgage_guid",
          json_object_text(fields, "mortgage_id", ""),
        ),
        mortgage_code: json_object_text(fields, "mortgage_code", "—"),
        customer_guid: json_object_text(fields, "customer_guid", "—"),
        customer_name: json_object_text(fields, "customer_name", "—"),
        bank_name: json_object_text(fields, "bank_name", "—"),
        loan_amount: json_object_text(fields, "loan_amount", "0"),
        loan_years: json_object_text(fields, "loan_years", "0"),
        rate: json_object_text(fields, "rate", "0"),
        apply_date: json_object_text(fields, "apply_date", ""),
        approval_date: json_object_text(fields, "approval_date", ""),
        release_date: json_object_text(fields, "release_date", ""),
        state: json_object_text(fields, "state", "applying"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn sales_mortgage_rows_from_body(body : String) -> Array[SalesMortgageRow] {
  let rows : Array[SalesMortgageRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("data") {
        Some(Json::Array(values)) => values
        _ =>
          match fields.get("items") {
            Some(Json::Array(values)) => values
            _ => []
          }
      }
      for value in values {
        match sales_mortgage_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn sales_revenue_from_json(value : Json) -> SalesRevenueRow? {
  match value {
    Json::Object(fields) =>
      Some({
        revenue_guid: json_object_text(
          fields,
          "revenue_guid",
          json_object_text(fields, "revenue_id", ""),
        ),
        revenue_code: json_object_text(fields, "revenue_code", "—"),
        proj_guid: json_object_text(fields, "proj_guid", ""),
        customer_name: json_object_text(fields, "customer_name", "—"),
        amount: json_object_text(
          fields,
          "amount",
          json_object_text(fields, "amount_display", "0"),
        ),
        receive_date: json_object_text(fields, "receive_date", ""),
        status: json_object_text(
          fields,
          "status",
          json_object_text(fields, "state", "expected"),
        ),
        payment_type: json_object_text(fields, "payment_type", "—"),
        contract_no: json_object_text(fields, "contract_no", ""),
        remark: json_object_text(fields, "remark", ""),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn sales_revenue_rows_from_body(body : String) -> Array[SalesRevenueRow] {
  let rows : Array[SalesRevenueRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("data") {
        Some(Json::Array(values)) => values
        _ =>
          match fields.get("items") {
            Some(Json::Array(values)) => values
            _ => []
          }
      }
      for value in values {
        match sales_revenue_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn append_sales_rows(target : Array[SalesRow], body : String) -> Int {
  let rows = sales_rows_from_body(body)
  for row in rows {
    target.push(row)
  }
  rows.length()
}

///|
fn invoice_tax_row_count_from_body(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          json_array_field(data, "rows").length().to_string()
        _ => "0"
      }
    _ => "0"
  }
}

///|
fn invoice_rows_from_body(
  body : String,
  direction : String,
) -> Array[InvoiceRow] {
  let rows : Array[InvoiceRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let values = match fields.get("data") {
        Some(Json::Array(items)) => items
        _ => []
      }
      for value in values {
        match value {
          Json::Object(row) =>
            rows.push({
              invoice_guid: json_object_text(
                row,
                "invoice_guid",
                json_object_text(row, "invoiceGuid", ""),
              ),
              invoice_no: json_object_text(row, "invoiceNo", "—"),
              counterparty: if direction == "in" {
                json_object_text(row, "providerName", "—")
              } else {
                json_object_text(row, "customerName", "—")
              },
              invoice_date: json_object_text(row, "invoiceDate", "—"),
              total_amount: json_object_text(row, "totalAmount", "0"),
              tax_amount: json_object_text(row, "taxAmount", "0"),
              tax_rate: json_object_text(row, "taxRate", "0"),
              invoice_type: json_object_text(row, "invoiceType", "—"),
              state: json_object_text(row, "state", "—"),
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn invoice_tax_rows_from_body(body : String) -> Array[InvoiceTaxRow] {
  let rows : Array[InvoiceTaxRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push({
                  period: json_object_text(row, "period", "—"),
                  total_in: json_object_text(row, "totalIn", "0"),
                  tax_in: json_object_text(row, "taxIn", "0"),
                  total_out: json_object_text(row, "totalOut", "0"),
                  tax_out: json_object_text(row, "taxOut", "0"),
                  net_tax: json_object_text(row, "netTax", "0"),
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
fn delivery_source_progress_from_body(
  body : String,
) -> Array[DeliveryProgressRow] {
  let rows : Array[DeliveryProgressRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match delivery_progress_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn delivery_source_outputs_from_body(body : String) -> Array[DeliveryOutputRow] {
  let rows : Array[DeliveryOutputRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match delivery_output_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn delivery_task_from_json(value : Json) -> DeliveryTaskRow? {
  match value {
    Json::Object(fields) =>
      Some({
        task_id: json_object_text(fields, "task_id", ""),
        task_code: json_object_text(fields, "task_code", ""),
        task_name: json_object_text(fields, "task_name", ""),
        project_id: json_object_text(fields, "project_id", ""),
        task_type: json_object_text(fields, "task_type", "task"),
        parent_task_id: json_object_text(fields, "parent_task_id", ""),
        plan_begin_date: json_object_text(fields, "plan_begin_date", ""),
        plan_end_date: json_object_text(fields, "plan_end_date", ""),
        actual_begin_date: json_object_text(fields, "actual_begin_date", ""),
        actual_end_date: json_object_text(fields, "actual_end_date", ""),
        progress_pct: json_object_text(fields, "progress_pct", "0"),
        status: json_object_text(fields, "status", "pending"),
        owner_name: json_object_text(fields, "owner_name", ""),
        delayed: json_object_text(fields, "delayed", "false") == "true",
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
fn source_data_row_count(body : String) -> Int {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => json_array_field(fields, "data").length()
    _ => 0
  }
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
        spare: json_object_text(fields, "spare", "0"),
        d_amount: json_object_text(fields, "d", "0"),
        e_amount: json_object_text(fields, "e", "0"),
        f_amount: json_object_text(fields, "f", "0"),
        g_amount: json_object_text(fields, "g", "0"),
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
        bu_name: json_object_text(fields, "buName", ""),
        proj_name: json_object_text(fields, "projName", ""),
        provider: json_object_text(fields, "provider", ""),
        sign_date: json_object_text(fields, "signDate", ""),
        current_amount: json_object_text(fields, "currentAmount", "0"),
        applied_total: json_object_text(fields, "appliedTotal", "0"),
        paid_total: json_object_text(fields, "paidTotal", "0"),
        remain_amount: json_object_text(fields, "remainAmount", "0"),
        paid_pct: json_object_text(fields, "paidPct", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn report_supplier_from_json(value : Json) -> ReportSupplierRow? {
  match value {
    Json::Object(fields) =>
      Some({
        provider_name: json_object_text(fields, "providerName", ""),
        short_name: json_object_text(fields, "shortName", ""),
        category_name: json_object_text(fields, "categoryName", ""),
        eval_result: json_object_text(fields, "evalResult", ""),
        contract_count: json_object_text(fields, "contractCount", "0"),
        bu_count: json_object_text(fields, "buCount", "0"),
        proj_count: json_object_text(fields, "projCount", "0"),
        total_amount: json_object_text(fields, "totalAmount", "0"),
        recent_amount: json_object_text(fields, "recentAmount", "0"),
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    _ => None
  }
}

///|
fn report_approval_from_json(value : Json) -> ReportApprovalRow? {
  match value {
    Json::Object(fields) =>
      Some({
        biz_type: json_object_text(fields, "bizType", ""),
        total: json_object_text(fields, "total", "0"),
        completed: json_object_text(fields, "completed", "0"),
        rejected: json_object_text(fields, "rejected", "0"),
        running: json_object_text(fields, "running", "0"),
        overdue: json_object_text(fields, "overdue", "0"),
        avg_days: json_object_text(fields, "avgDays", "—"),
        reject_rate: json_object_text(fields, "rejectRate", "0"),
      })
    _ => None
  }
}

///|
fn report_slow_step_from_json(value : Json) -> ReportSlowStepRow? {
  match value {
    Json::Object(fields) =>
      Some({
        step_name: json_object_text(fields, "stepName", ""),
        emp_name: json_object_text(fields, "empName", ""),
        avg_days: json_object_text(fields, "avgDays", "0"),
        count: json_object_text(fields, "count", "0"),
      })
    _ => None
  }
}

///|
fn report_stage_cell_from_json(value : Json) -> ReportStageCell? {
  match value {
    Json::Object(fields) =>
      Some({
        stage_code: json_object_text(fields, "stageCode", ""),
        stage_name: json_object_text(fields, "stageName", ""),
        status: json_object_text(fields, "status", "pending"),
        progress_pct: json_object_text(fields, "progressPct", "0"),
      })
    _ => None
  }
}

///|
fn report_stage_from_json(value : Json) -> ReportStageRow? {
  match value {
    Json::Object(fields) => {
      let cells : Array[ReportStageCell] = []
      for value in json_array_field(fields, "cells") {
        match report_stage_cell_from_json(value) {
          Some(row) => cells.push(row)
          None => ()
        }
      }
      Some({
        proj_guid: json_object_text(fields, "projGuid", ""),
        proj_code: json_object_text(fields, "projCode", ""),
        proj_name: json_object_text(fields, "projName", ""),
        bu_name: json_object_text(fields, "buName", ""),
        proj_status: json_object_text(fields, "projStatus", ""),
        begin_date: json_object_text(fields, "beginDate", ""),
        end_date: json_object_text(fields, "endDate", ""),
        cells,
        source_kind: json_object_text(fields, "source_kind", "imported"),
      })
    }
    _ => None
  }
}

///|
fn report_supplier_rows_from_body(body : String) -> Array[ReportSupplierRow] {
  let rows : Array[ReportSupplierRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("supplier_analysis") {
        Some(Json::Array(values)) =>
          for value in values {
            match report_supplier_from_json(value) {
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
fn report_approval_rows_from_body(
  body : String,
) -> (Array[ReportApprovalRow], Array[ReportSlowStepRow]) {
  let rows : Array[ReportApprovalRow] = []
  let slow_steps : Array[ReportSlowStepRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("approval_efficiency") {
        Some(Json::Object(approval)) => {
          for value in json_array_field(approval, "byType") {
            match report_approval_from_json(value) {
              Some(row) => rows.push(row)
              None => ()
            }
          }
          for value in json_array_field(approval, "slowSteps") {
            match report_slow_step_from_json(value) {
              Some(row) => slow_steps.push(row)
              None => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
  (rows, slow_steps)
}

///|
fn report_stage_names_from_body(body : String) -> Array[String] {
  let names : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("project_stage_matrix") {
        Some(Json::Object(matrix)) =>
          for value in json_array_field(matrix, "stages") {
            match value {
              Json::Object(stage) =>
                names.push(
                  json_object_text(
                    stage,
                    "name",
                    json_object_text(stage, "code", ""),
                  ),
                )
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  names
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
fn dashboard_v2_from_body(
  body : String,
) -> (
  Bool,
  Array[String],
  Array[DashboardV2TrendRow],
  Array[DashboardV2StageRow],
  Array[DashboardV2WarningRow],
  String,
) {
  let values : Array[String] = []
  let trend_rows : Array[DashboardV2TrendRow] = []
  let stage_rows : Array[DashboardV2StageRow] = []
  let warning_rows : Array[DashboardV2WarningRow] = []
  let mut missing_table_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      missing_table_count = json_array_field(
          fields, "missing_or_empty_source_tables",
        )
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          match data.get("kpi") {
            Some(Json::Object(kpi)) => {
              values.push(json_object_text(kpi, "projectCount", "0"))
              values.push(json_object_text(kpi, "inProgressProjects", "0"))
              values.push(
                json_object_text(kpi, "contractInProgressAmount", "0"),
              )
              values.push(json_object_text(kpi, "unpaidAmount", "0"))
              values.push(json_object_text(kpi, "openWarnings", "0"))
              values.push(json_object_text(kpi, "runningProcesses", "0"))
            }
            _ => ()
          }
          for value in json_array_field(data, "paymentTrend") {
            match value {
              Json::Object(row) =>
                trend_rows.push({
                  month: json_object_text(row, "ym", ""),
                  plan: json_object_text(row, "plan", "0"),
                  actual: json_object_text(row, "actual", "0"),
                })
              _ => ()
            }
          }
          for value in json_array_field(data, "stageDistribution") {
            match value {
              Json::Object(row) =>
                stage_rows.push({
                  stage: json_object_text(row, "stage", ""),
                  count: json_object_text(row, "count", "0"),
                })
              _ => ()
            }
          }
          for value in json_array_field(data, "latestWarnings") {
            match value {
              Json::Object(row) =>
                warning_rows.push({
                  title: json_object_text(row, "title", ""),
                  severity: json_object_text(row, "severity", "info"),
                  source_kind: json_object_text(
                    fields, "source_kind", "imported_or_empty",
                  ),
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
  (
    values.length() == 6,
    values,
    trend_rows,
    stage_rows,
    warning_rows,
    missing_table_count,
  )
}

///|
fn dashboard_v3_pair_rows(
  data : Map[String, Json],
  key : String,
  label_key : String,
  value_key : String,
) -> Array[DashboardV3PairRow] {
  let rows : Array[DashboardV3PairRow] = []
  for value in json_array_field(data, key) {
    match value {
      Json::Object(row) =>
        rows.push({
          label: json_object_text(row, label_key, "—"),
          value: json_object_text(row, value_key, "0"),
        })
      _ => ()
    }
  }
  rows
}

///|
fn dashboard_v3_health_rows(
  data : Map[String, Json],
) -> Array[DashboardV3PairRow] {
  let rows : Array[DashboardV3PairRow] = []
  for key in ["profit", "recover", "budget", "warning"] {
    match data.get(key) {
      Some(Json::Object(row)) =>
        rows.push({
          label: json_object_text(row, "label", key),
          value: json_object_text(row, "score", "0") +
          " / " +
          json_object_text(row, "weight", "0"),
        })
      _ => ()
    }
  }
  rows
}

///|
fn dashboard_v3_city_rows(
  data : Map[String, Json],
) -> Array[DashboardV3CityRow] {
  let rows : Array[DashboardV3CityRow] = []
  for value in json_array_field(data, "expenseByCity") {
    match value {
      Json::Object(row) =>
        rows.push({
          name: json_object_text(row, "name", "—"),
          expense: json_object_text(row, "expense", "0"),
          revenue: json_object_text(row, "revenue", "0"),
        })
      _ => ()
    }
  }
  rows
}

///|
fn dashboard_v3_contract_rows(
  data : Map[String, Json],
  key : String,
) -> Array[DashboardV3ContractRow] {
  let rows : Array[DashboardV3ContractRow] = []
  for value in json_array_field(data, key) {
    match value {
      Json::Object(row) =>
        rows.push({
          code: json_object_text(row, "contractCode", "—"),
          name: json_object_text(row, "contractName", "—"),
          amount: json_object_text(row, "htAmount", "0"),
        })
      _ => ()
    }
  }
  rows
}

///|
fn dashboard_v3_from_body(body : String) -> (Bool, DashboardV3Snapshot) {
  let mut snapshot = empty_dashboard_v3()
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      snapshot = {
        ..snapshot,
        missing_table_count: json_array_field(
          fields, "missing_or_empty_source_tables",
        )
        .length()
        .to_string(),
      }
      match fields.get("data") {
        Some(Json::Object(data)) => {
          match data.get("scope") {
            Some(Json::Object(scope)) => {
              let level = json_object_text(scope, "level", "group")
              let project = json_object_text(scope, "projGuid", "")
              let business_unit = json_object_text(scope, "buGuid", "")
              snapshot = {
                ..snapshot,
                scope: if project != "" {
                  level + " · 项目 " + project
                } else if business_unit != "" {
                  level + " · 公司 " + business_unit
                } else {
                  level
                },
              }
            }
            _ => ()
          }
          match data.get("kpi") {
            Some(Json::Object(kpi)) =>
              snapshot = {
                ..snapshot,
                health_score: json_object_text(kpi, "healthScore", "0"),
                total_revenue: json_object_text(kpi, "totalRevenue", "0"),
                total_expense: json_object_text(kpi, "totalExpense", "0"),
                net_profit: json_object_text(kpi, "netProfit", "0"),
                net_profit_rate: json_object_text(kpi, "netProfitRate", "0"),
                cashflow_months: json_object_text(kpi, "cashflowMonths", "0"),
                customer_count: json_object_text(kpi, "customerCount", "0"),
                signed_count: json_object_text(kpi, "signedCount", "0"),
                mortgage_count: json_object_text(kpi, "mortgageCount", "0"),
                progress_active: json_object_text(kpi, "progressActive", "0"),
                progress_done: json_object_text(kpi, "progressDone", "0"),
                tender_active_count: json_object_text(
                  kpi, "tenderActiveCount", "0",
                ),
                open_warnings: json_object_text(kpi, "openWarnings", "0"),
                running_processes: json_object_text(
                  kpi, "runningProcesses", "0",
                ),
              }
            _ => ()
          }
          let health_rows = match data.get("healthBreakdown") {
            Some(Json::Object(health)) => dashboard_v3_health_rows(health)
            _ => []
          }
          snapshot = {
            ..snapshot,
            health_rows,
            expense_rows: dashboard_v3_pair_rows(
              data, "expenseByCategory", "rName", "amount",
            ),
            city_rows: dashboard_v3_city_rows(data),
            funnel_rows: dashboard_v3_pair_rows(
              data, "funnel", "stage", "value",
            ),
            top_unpaid_rows: dashboard_v3_contract_rows(data, "topUnpaid"),
            top_approving_rows: dashboard_v3_contract_rows(data, "topApproving"),
            top_overbudget_rows: dashboard_v3_pair_rows(
              data, "topOverbudget", "subject", "used",
            ),
            top_gap_rows: dashboard_v3_pair_rows(
              data, "topGap", "planPeriod", "net",
            ),
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
  (snapshot.health_rows.length() > 0 || snapshot.scope != "", snapshot)
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
              param_guid: json_object_text(row, "paramGuid", ""),
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
fn investment_version_rows_from_body(
  body : String,
) -> Array[InvestmentVersionRow] {
  let rows : Array[InvestmentVersionRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              version_guid: json_object_text(row, "versionGuid", ""),
              version_name: json_object_text(row, "versionName", ""),
              version_no: json_object_text(row, "versionNo", "0"),
              is_current: json_object_text(row, "isCurrent", "false") == "true",
              creator_name: json_object_text(row, "creatorName", ""),
              created_at: json_object_text(row, "createdAt", ""),
              remark: json_object_text(row, "remark", ""),
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
                    index_guid: json_object_text(row, "indexGuid", ""),
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
fn investment_index_value_for(
  rows : Array[InvestmentIndexRow],
  index_id : String,
) -> String {
  for row in rows {
    if row.index_guid == index_id {
      return row.index_value
    }
  }
  ""
}

///|
fn investment_index_remark_for(
  rows : Array[InvestmentIndexRow],
  index_id : String,
) -> String {
  for row in rows {
    if row.index_guid == index_id {
      return "已从 PostgreSQL 投资指标读取 · " + row.source_kind
    }
  }
  ""
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
fn investment_explain_text_from_body(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          json_object_text(data, "explain", "投资解释候选响应为空")
        _ => "投资解释候选响应为空"
      }
    _ => "投资解释候选响应无效"
  }
}

///|
fn investment_sensitivity_from_body(
  body : String,
) -> (Bool, Array[InvestmentSensitivityCase], String) {
  let rows : Array[InvestmentSensitivityCase] = []
  let mut base_irr = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          base_irr = json_object_text(data, "baseIrr", "0")
          for value in json_array_field(data, "cases") {
            match value {
              Json::Object(row) =>
                rows.push({
                  name: json_object_text(row, "name", ""),
                  irr: json_object_text(row, "irr", "0"),
                  source_kind: json_object_text(
                    fields, "source_kind", "imported",
                  ),
                })
              _ => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
  (rows.length() > 0, rows, base_irr)
}

///|
fn investment_import_rows_from_body(
  body : String,
) -> (Bool, Array[InvestmentImportRow], String) {
  let rows : Array[InvestmentImportRow] = []
  let mut loaded = false
  let mut note = "Excel 导入历史响应为空"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      loaded = true
      let missing = json_array_field(fields, "missing_or_empty_source_tables").length()
      note = "已加载 PostgreSQL Excel 导入历史 · 二进制内容不读取 · 空源表 " +
        missing.to_string()
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              import_guid: json_object_text(row, "importGuid", ""),
              version_guid: json_object_text(row, "versionGuid", ""),
              version_name: json_object_text(row, "versionName", ""),
              file_name: json_object_text(row, "fileName", ""),
              file_size: json_object_text(row, "fileSize", "—"),
              sheet_count: json_object_text(row, "sheetCount", "—"),
              non_empty_cells: json_object_text(row, "nonEmptyCells", "—"),
              formula_count: json_object_text(row, "formulaCount", "—"),
              status: json_object_text(row, "status", ""),
              created_by_name: json_object_text(row, "createdByName", ""),
              created_at: json_object_text(row, "createdAt", ""),
              source_kind: json_object_text(row, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    }
    _ => ()
  }
  (loaded, rows, note)
}

///|
fn investment_import_read_note(body : String, action : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let code = json_object_text(fields, "code", "0")
      if code != "0" && code != "" {
        "导入 " +
        action +
        " 未完成 · 源边界 code=" +
        code +
        " · 未读取二进制、不写入"
      } else {
        match fields.get("data") {
          Some(Json::Object(data)) =>
            if action == "detail" {
              "导入详情 " +
              json_object_text(data, "fileName", "") +
              " · 版本 " +
              json_object_text(data, "versionName", "") +
              " · sheet " +
              json_array_field(data, "sheets").length().to_string() +
              " · 元数据只读"
            } else if action == "bridge" {
              match data.get("summary") {
                Some(Json::Object(summary)) =>
                  "逻辑桥接计划 · 已映射 " +
                  json_object_text(summary, "mappedSheetCount", "0") +
                  " · 未映射 " +
                  json_object_text(summary, "unmappedSheetCount", "0") +
                  " · 不回写 ERP"
                _ => "逻辑桥接计划已读取 · 不回写 ERP"
              }
            } else if action == "index-preview" {
              match data.get("summary") {
                Some(Json::Object(summary)) =>
                  "指标 upsert 预览 · 可处理 " +
                  json_object_text(summary, "itemsCanUpsert", "0") +
                  " · 新增 " +
                  json_object_text(summary, "itemsToInsert", "0") +
                  " · 覆盖 " +
                  json_object_text(summary, "itemsToUpdate", "0") +
                  " · dry-run"
                _ => "指标 upsert 预览已读取 · dry-run"
              }
            } else if action == "profit" {
              "利润测算总表已读取 · " +
              json_object_text(data, "source", "empty") +
              " · 行 " +
              json_array_field(data, "rows").length().to_string() +
              " · 不回写"
            } else {
              match data.get("summary") {
                Some(Json::Object(summary)) =>
                  "计划行预览 · 扫描 " +
                  json_object_text(summary, "sheetsScanned", "0") +
                  " 个 sheet · 计划行 " +
                  json_object_text(summary, "linesTotal", "0") +
                  " · 不写入"
                _ => "计划行预览已读取 · 不写入"
              }
            }
          _ => "导入 " + action + " 响应为空 · 保持只读边界"
        }
      }
    }
    _ => "导入 " + action + " 响应无效 · 保持只读边界"
  }
}

///|
fn investment_profit_actual_from_body(
  body : String,
) -> (Bool, String, String, String, String) {
  let mut code = ""
  let mut message = ""
  let mut simulation = "false"
  let mut missing_table_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      code = json_object_text(fields, "code", "")
      message = json_object_text(fields, "message", "")
      simulation = json_object_text(fields, "simulation", "false")
      missing_table_count = json_array_field(
          fields, "missing_or_empty_source_tables",
        )
        .length()
        .to_string()
    }
    _ => ()
  }
  (code != "", code, message, simulation, missing_table_count)
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
fn append_cost_dashboard_rows(
  value : Json,
  level : String,
  rows : Array[CostDashboardRow],
) -> Unit {
  match value {
    Json::Object(fields) => {
      rows.push({
        code: json_object_text(fields, "rCode", ""),
        name: json_object_text(fields, "rName", ""),
        level,
        target_cost: json_object_text(fields, "A", "0"),
        committed_cost: json_object_text(fields, "D", "0"),
        in_transit: json_object_text(fields, "E", "0"),
        planned_spare: json_object_text(fields, "F", "0"),
        estimated_change: json_object_text(fields, "G", "0"),
        dynamic_cost: json_object_text(fields, "B", "0"),
        layout_spare: json_object_text(fields, "H", "0"),
      })
      for group in json_array_field(fields, "groups") {
        match group {
          Json::Object(group_fields) => {
            rows.push({
              code: json_object_text(group_fields, "l2Code", ""),
              name: json_object_text(group_fields, "l2Name", ""),
              level: "L2",
              target_cost: json_object_text(group_fields, "A", "0"),
              committed_cost: json_object_text(group_fields, "D", "0"),
              in_transit: json_object_text(group_fields, "E", "0"),
              planned_spare: json_object_text(group_fields, "F", "0"),
              estimated_change: json_object_text(group_fields, "G", "0"),
              dynamic_cost: json_object_text(group_fields, "B", "0"),
              layout_spare: json_object_text(group_fields, "H", "0"),
            })
            for leaf in json_array_field(group_fields, "leaves") {
              match leaf {
                Json::Object(leaf_fields) =>
                  rows.push({
                    code: json_object_text(leaf_fields, "l3Code", ""),
                    name: json_object_text(leaf_fields, "subject", ""),
                    level: "L3",
                    target_cost: json_object_text(leaf_fields, "A", "0"),
                    committed_cost: json_object_text(leaf_fields, "D", "0"),
                    in_transit: json_object_text(leaf_fields, "E", "0"),
                    planned_spare: json_object_text(leaf_fields, "F", "0"),
                    estimated_change: json_object_text(leaf_fields, "G", "0"),
                    dynamic_cost: json_object_text(leaf_fields, "B", "0"),
                    layout_spare: json_object_text(leaf_fields, "H", "0"),
                  })
                _ => ()
              }
            }
          }
          _ => ()
        }
      }
    }
    _ => ()
  }
}

///|
fn cost_dashboard_from_body(
  body : String,
) -> (Bool, Array[CostDashboardRow], Array[String], String) {
  let rows : Array[CostDashboardRow] = []
  let summary : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables").length()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "rows") {
            append_cost_dashboard_rows(value, "R", rows)
          }
          summary.push(json_object_text(data, "projName", ""))
          summary.push(json_object_text(data, "planVersion", "baseline"))
          match data.get("summary") {
            Some(Json::Object(summary_fields)) => {
              summary.push(json_object_text(summary_fields, "targetCost", "0"))
              summary.push(json_object_text(summary_fields, "dynamicCost", "0"))
              summary.push(
                json_object_text(summary_fields, "deviationPct", "0"),
              )
            }
            _ => {
              summary.push("0")
              summary.push("0")
              summary.push("0")
            }
          }
          match data.get("counts") {
            Some(Json::Object(counts)) => {
              summary.push(json_object_text(counts, "contracts", "0"))
              summary.push(json_object_text(counts, "expenses", "0"))
              summary.push(json_object_text(counts, "changes", "0"))
            }
            _ => {
              summary.push("0")
              summary.push("0")
              summary.push("0")
            }
          }
          (
            true,
            rows,
            summary,
            "已加载 PostgreSQL 成本驾驶舱 v3 源读模型 · CBS 空表 " +
            missing.to_string(),
          )
        }
        _ =>
          (
            false,
            [],
            [],
            "成本驾驶舱响应缺少 data · 使用设计快照",
          )
      }
    }
    _ => (false, [], [], "成本驾驶舱响应无效 · 使用设计快照")
  }
}

///|
fn cashflow_from_body(
  body : String,
) -> (Array[CashflowRow], Array[String], String) {
  let rows : Array[CashflowRow] = []
  let totals : Array[String] = []
  let mut missing_table_count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      missing_table_count = json_array_field(
          fields, "missing_or_empty_source_tables",
        )
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          match data.get("totals") {
            Some(Json::Object(summary)) => {
              totals.push(json_object_text(summary, "plannedTotal", "0"))
              totals.push(json_object_text(summary, "pendingTotal", "0"))
              totals.push(json_object_text(summary, "confirmedTotal", "0"))
              totals.push(json_object_text(summary, "expenseTotal", "0"))
              totals.push(json_object_text(summary, "loanTotal", "0"))
              totals.push(json_object_text(summary, "totalOutflow", "0"))
            }
            _ => ()
          }
          for value in json_array_field(data, "series") {
            match value {
              Json::Object(row) =>
                rows.push({
                  ym: json_object_text(row, "ym", ""),
                  planned: json_object_text(row, "planned", "0"),
                  pending: json_object_text(row, "pending", "0"),
                  confirmed: json_object_text(row, "confirmed", "0"),
                  expense: json_object_text(row, "expense", "0"),
                  loan: json_object_text(row, "loan", "0"),
                  total_outflow: json_object_text(row, "totalOutflow", "0"),
                  cumulative_outflow: json_object_text(
                    row, "cumulativeOutflow", "0",
                  ),
                  actual_outflow: json_object_text(row, "actualOutflow", "0"),
                  actual_cumulative: json_object_text(
                    row, "actualCumulative", "0",
                  ),
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
  (rows, totals, missing_table_count)
}

///|
fn cashflow_inflow_from_body(body : String) -> (Bool, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) =>
          match data.get("totals") {
            Some(Json::Object(totals)) =>
              (
                true,
                json_object_text(totals, "totalInflow", "0"),
                missing,
                "已加载 PostgreSQL 回款预测 · sale_revenue 保持只读",
              )
            _ =>
              (
                false, "0", missing, "回款预测响应无效 · 使用明确空源状态",
              )
          }
        _ =>
          (
            false, "0", missing, "回款预测响应无效 · 使用明确空源状态",
          )
      }
    }
    _ =>
      (false, "0", "0", "回款预测响应无效 · 使用明确空源状态")
  }
}

///|
fn cashflow_explain_text_from_body(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          json_object_text(data, "explain", "现金流解释候选响应为空")
        _ => "现金流解释候选响应为空"
      }
    _ => "现金流解释候选响应无效"
  }
}

///|
fn cbs_from_body(
  body : String,
) -> (Bool, Array[CbsRow], String, String, String) {
  let rows : Array[CbsRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let version = json_object_text(data, "planVersion", "baseline")
          for value in json_array_field(data, "items") {
            match value {
              Json::Object(row) =>
                rows.push({
                  l3_code: json_object_text(row, "l3_code", ""),
                  r_code: json_object_text(row, "r_code", ""),
                  l2_name: json_object_text(row, "l2_name", ""),
                  subject: json_object_text(row, "subject", ""),
                  plan_amount: json_object_text(row, "plan_amount", "0"),
                  src: json_object_text(row, "src", "imported"),
                })
              _ => ()
            }
          }
          (
            true, rows, version, missing, "已加载 PostgreSQL CBS 源读模型 · 字典保持只读",
          )
        }
        _ =>
          (
            false, rows, "baseline", missing, "CBS 响应无效 · 使用设计快照",
          )
      }
    }
    _ =>
      (false, rows, "baseline", "0", "CBS 响应无效 · 使用设计快照")
  }
}

///|
fn cbs_r0_from_body(body : String) -> (Bool, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          (true, json_array_field(data, "items").length().to_string())
        _ => (false, "0")
      }
    _ => (false, "0")
  }
}

///|
fn fund_from_body(body : String) -> (Bool, Array[FundPlanRow], String) {
  let rows : Array[FundPlanRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  plan_guid: json_object_text(row, "plan_guid", ""),
                  proj_guid: json_object_text(row, "proj_guid", ""),
                  plan_code: json_object_text(row, "plan_code", "—"),
                  plan_period: json_object_text(row, "plan_period", "—"),
                  direction: json_object_text(row, "direction", "—"),
                  category: json_object_text(row, "category", "—"),
                  proj_name: json_object_text(row, "proj_name", "—"),
                  plan_amount: json_object_text(row, "plan_amount", "0"),
                  actual_amount: json_object_text(row, "actual_amount", "0"),
                  state: json_object_text(row, "state", "source_read_only"),
                  r_code: json_object_text(row, "r_code", ""),
                  remark: json_object_text(row, "remark", ""),
                  source_kind: json_object_text(
                    row,
                    "source_kind",
                    json_object_text(row, "sourceKind", "imported"),
                  ),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|

///|
fn fund_gap_from_body(body : String) -> (Bool, Array[FundGapRow], String) {
  let rows : Array[FundGapRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "series") {
            match value {
              Json::Object(row) =>
                rows.push({
                  period: json_object_text(row, "period", "—"),
                  plan_in: json_object_text(row, "planIn", "0"),
                  plan_out: json_object_text(row, "planOut", "0"),
                  net: json_object_text(row, "net", "0"),
                  cum_net: json_object_text(row, "cumNet", "0"),
                  gap: json_object_text(row, "gap", "0"),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn fund_dispatch_rows_from_body(
  body : String,
) -> (Bool, Array[FundDispatchRow], String) {
  let rows : Array[FundDispatchRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  dispatch_guid: json_object_text(row, "dispatch_guid", ""),
                  dispatch_code: json_object_text(row, "dispatch_code", "—"),
                  dispatch_date: json_object_text(row, "dispatch_date", "—"),
                  from_proj: json_object_text(row, "from_proj", "—"),
                  to_proj: json_object_text(row, "to_proj", "—"),
                  amount: json_object_text(row, "amount", "0"),
                  reason: json_object_text(row, "reason", "—"),
                  state: json_object_text(row, "state", "pending"),
                  source_kind: json_object_text(
                    row,
                    "source_kind",
                    json_object_text(row, "sourceKind", "imported"),
                  ),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn warnings_from_body(body : String) -> (Bool, Array[WarningRow], String) {
  let rows : Array[WarningRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push({
                  warning_guid: json_object_text(row, "warningGuid", ""),
                  rule_code: json_object_text(row, "ruleCode", "—"),
                  rule_name: json_object_text(row, "ruleName", "—"),
                  severity: json_object_text(row, "severity", "—"),
                  biz_type: json_object_text(row, "bizType", "—"),
                  title: json_object_text(row, "title", "—"),
                  detail: json_object_text(row, "detail", "—"),
                  status: json_object_text(row, "status", "observed"),
                  source_kind: json_object_text(
                    row, "sourceKind", "observed_imported",
                  ),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn warning_rules_count_from_body(body : String) -> (Bool, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      (true, json_array_field(fields, "data").length().to_string())
    _ => (false, "0")
  }
}

///|
fn warning_command_from_body(body : String) -> (Bool, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("warning") {
        Some(Json::Object(warning)) =>
          (
            true,
            json_object_text(warning, "state", "error"),
            json_object_text(warning, "warningGuid", ""),
            if json_object_text(warning, "state", "") == "resolved" {
              "告警已标记为已处理 · 仅写入本地状态投影与审计"
            } else {
              "告警已标记为忽略 · 仅写入本地状态投影与审计"
            },
          )
        _ => (false, "error", "", "告警命令响应无效")
      }
    _ => (false, "error", "", "告警命令响应无效")
  }
}

///|
fn attachments_from_body(
  body : String,
) -> (Bool, Array[AttachmentRow], String, String) {
  let rows : Array[AttachmentRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let total = json_object_text(data, "total", "0")
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) => {
                let mut ai_status = "未处理"
                match row.get("ai") {
                  Some(Json::Object(ai)) =>
                    ai_status = json_object_text(ai, "status", "未处理")
                  _ => ()
                }
                rows.push({
                  att_guid: json_object_text(row, "attGuid", ""),
                  file_name: json_object_text(row, "fileName", ""),
                  file_size: json_object_text(row, "fileSize", "0"),
                  mime_type: json_object_text(row, "mimeType", ""),
                  biz_type: json_object_text(row, "bizType", ""),
                  biz_guid: json_object_text(row, "bizGuid", ""),
                  uploaded_by_name: json_object_text(row, "uploadedByName", ""),
                  uploaded_at: json_object_text(row, "uploadedAt", ""),
                  ai_status,
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                  download_available: if json_object_text(
                      row, "downloadAvailable", "false",
                    ) ==
                    "true" {
                    "可下载"
                  } else {
                    "未导入文件"
                  },
                })
              }
              _ => ()
            }
          }
          (true, rows, total, missing)
        }
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  att_guid: json_object_text(row, "attGuid", ""),
                  file_name: json_object_text(row, "fileName", ""),
                  file_size: json_object_text(row, "fileSize", "0"),
                  mime_type: json_object_text(row, "mimeType", ""),
                  biz_type: json_object_text(row, "bizType", ""),
                  biz_guid: json_object_text(row, "bizGuid", ""),
                  uploaded_by_name: json_object_text(row, "uploadedByName", ""),
                  uploaded_at: json_object_text(row, "uploadedAt", ""),
                  ai_status: "未处理",
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                  download_available: "未导入文件",
                })
              _ => ()
            }
          }
          (true, rows, rows.length().to_string(), missing)
        }
        _ => (false, rows, "0", missing)
      }
    }
    _ => (false, rows, "0", "0")
  }
}

///|
fn attachment_stats_from_body(
  body : String,
) -> (Bool, String, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let total = match data.get("total") {
            Some(Json::Object(total_fields)) =>
              json_object_text(total_fields, "count", "0")
            _ => "0"
          }
          let bytes = match data.get("total") {
            Some(Json::Object(total_fields)) =>
              json_object_text(total_fields, "bytes", "0")
            _ => "0"
          }
          let mut pending = "0"
          for value in json_array_field(data, "byAiStatus") {
            match value {
              Json::Object(row) => {
                let status = json_object_text(row, "aiStatus", "")
                if status == "pending" {
                  pending = json_object_text(row, "count", "0")
                }
              }
              _ => ()
            }
          }
          (true, total, bytes, pending, missing)
        }
        _ => (false, "0", "0", "0", missing)
      }
    }
    _ => (false, "0", "0", "0", "0")
  }
}

///|
fn marketing_rows_from_body(
  body : String,
  family : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                if family == "campaigns" {
                  rows.push([
                    json_object_text(row, "campaignCode", "—"),
                    json_object_text(row, "name", "—"),
                    json_object_text(row, "campaignType", "—"),
                    json_object_text(row, "budget", "0"),
                    json_object_text(row, "actualCost", "0"),
                    json_object_text(row, "startDate", "") +
                    " ~ " +
                    json_object_text(row, "endDate", ""),
                    json_object_text(row, "state", "—"),
                    json_object_text(row, "l3Code", "—"),
                    json_object_text(row, "campaignGuid", ""),
                    json_object_text(
                      row,
                      "sourceKind",
                      json_object_text(row, "source_kind", "imported"),
                    ),
                  ])
                } else if family == "placements" {
                  rows.push([
                    json_object_text(row, "placementCode", "—"),
                    json_object_text(row, "campaignName", "—"),
                    json_object_text(row, "channelName", "—"),
                    json_object_text(row, "amount", "0"),
                    json_object_text(row, "placeDate", ""),
                    json_object_text(row, "impressions", "0"),
                    json_object_text(row, "leads", "0"),
                  ])
                } else if family == "channels" {
                  rows.push([
                    json_object_text(row, "channelCode", "—"),
                    json_object_text(row, "name", "—"),
                    json_object_text(row, "channelType", "—"),
                    json_object_text(row, "totalCost", "0"),
                    json_object_text(row, "placementCount", "0"),
                    json_object_text(row, "state", "—"),
                  ])
                } else {
                  rows.push([
                    json_object_text(row, "materialCode", "—"),
                    json_object_text(row, "name", "—"),
                    json_object_text(row, "materialType", "—"),
                    json_object_text(row, "unitCost", "0"),
                    json_object_text(row, "quantity", "0"),
                    json_object_text(row, "totalCost", "0"),
                    json_object_text(row, "usagePeriod", "—"),
                    json_object_text(row, "state", "—"),
                  ])
                }
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn marketing_sum(rows : Array[Array[String]], index : Int) -> String {
  let mut total = 0.0
  for row in rows {
    if index < row.length() {
      let parsed = @json.parse(row[index]) catch { _ => Json::null() }
      match parsed {
        Json::Number(value, ..) => total = total + value
        _ => ()
      }
    }
  }
  total.to_string()
}

///|
fn inbox_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let total = json_object_text(data, "total", "0")
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push([
                  if json_object_text(row, "isRead", "false") == "true" {
                    ""
                  } else {
                    "●"
                  },
                  json_object_text(row, "title", "—"),
                  json_object_text(row, "content", "—"),
                  json_object_text(row, "bizType", "—"),
                  json_object_text(row, "createdAt", "—"),
                  if json_object_text(row, "isRead", "false") == "true" {
                    "已读"
                  } else {
                    "未读"
                  },
                  "查看",
                ])
              _ => ()
            }
          }
          (true, rows, total, missing)
        }
        _ => (false, rows, "0", missing)
      }
    }
    _ => (false, rows, "0", "0")
  }
}

///|
fn inbox_unread_from_body(body : String) -> (Bool, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => (true, json_object_text(data, "count", "0"))
        _ => (false, "0")
      }
    _ => (false, "0")
  }
}

///|
fn notify_subscriptions_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "ruleCode", "全部规则"),
                  json_object_text(row, "bizType", "全部业务"),
                  json_object_text(row, "severityMin", "—"),
                  json_object_text(row, "channels", "—"),
                  if json_object_text(row, "enabled", "false") == "true" {
                    "启用"
                  } else {
                    "停用"
                  },
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn notify_config_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let configured = json_array_field(data, "configured")
          for value in configured {
            match value {
              Json::String(key) => rows.push([key, "已配置", "源表"])
              _ => ()
            }
          }
          (true, rows, configured.length().to_string(), missing)
        }
        _ => (false, rows, "0", missing)
      }
    }
    _ => (false, rows, "0", "0")
  }
}

///|
fn notify_outbox_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "toAddr", "—"),
                  json_object_text(row, "subject", "—"),
                  json_object_text(row, "createdAt", "—"),
                  json_object_text(row, "status", "—"),
                  "查看",
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn notify_digest_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "warningGuid", "—"),
                  json_object_text(row, "ruleCode", "—"),
                  json_object_text(row, "severity", "—"),
                  json_object_text(row, "title", "—"),
                  "预览",
                  "0",
                  "source_read_only",
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "digestDate", "—"),
                  json_object_text(row, "triggeredAt", "—"),
                  json_object_text(row, "userCount", "0"),
                  json_object_text(row, "errorCount", "0"),
                  json_object_text(row, "warningCount", "0"),
                  json_object_text(row, "newCount", "0"),
                  json_object_text(row, "triggeredBy", "—"),
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn ocr_from_body(
  body : String,
) -> (Bool, String, String, Array[Array[String]], String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "providers") {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "code", "—"),
                  json_object_text(row, "label", "—"),
                  if json_object_text(row, "current", "false") == "true" {
                    "当前"
                  } else {
                    "—"
                  },
                  if json_object_text(row, "needsKey", "false") == "true" {
                    "需密钥"
                  } else {
                    "无需密钥"
                  },
                  "状态键已脱敏",
                ])
              _ => ()
            }
          }
          (
            true,
            json_object_text(data, "provider", "mock"),
            json_object_text(data, "scene", "auto"),
            rows,
            json_object_text(data, "configuredKeyCount", "0"),
            missing,
          )
        }
        _ => (false, "mock", "auto", rows, "0", missing)
      }
    }
    _ => (false, "mock", "auto", rows, "0", "0")
  }
}

///|
fn error_logs_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String, String, String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "errId", "—"),
                  json_object_text(row, "occurredAt", "—"),
                  json_object_text(row, "method", "—"),
                  json_object_text(row, "path", "—"),
                  json_object_text(row, "status", "0"),
                  json_object_text(row, "errorMessage", "—"),
                  if json_object_text(row, "ip", "") == "" {
                    "—"
                  } else {
                    "已脱敏"
                  },
                ])
              _ => ()
            }
          }
          (
            true,
            rows,
            json_object_text(data, "total", "0"),
            json_object_text(data, "todayCount", "0"),
            json_object_text(data, "fiveXxCount", "0"),
            missing,
          )
        }
        _ => (false, rows, "0", "0", "0", missing)
      }
    }
    _ => (false, rows, "0", "0", "0", "0")
  }
}

///|
fn ai_stats_overview_from_body(
  body : String,
) -> (
  Bool,
  String,
  String,
  String,
  String,
  String,
  String,
  String,
  Array[Array[String]],
  String,
) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) =>
          match data.get("kpi") {
            Some(Json::Object(kpi)) => {
              for value in json_array_field(data, "byBizType") {
                match value {
                  Json::Object(row) =>
                    rows.push([
                      json_object_text(row, "bizType", "—"),
                      json_object_text(row, "count", "0"),
                      "—",
                      "—",
                      "—",
                      "源表未提供场景明细",
                    ])
                  _ => ()
                }
              }
              (
                true,
                json_object_text(data, "period", "month"),
                json_object_text(kpi, "intakeTotal", "0"),
                json_object_text(kpi, "queryTotal", "0"),
                json_object_text(kpi, "skipTotal", "0"),
                json_object_text(kpi, "correctionTotal", "0"),
                json_object_text(kpi, "accuracy", "100"),
                json_object_text(kpi, "savedHours", "0"),
                rows,
                missing,
              )
            }
            _ => (false, "month", "0", "0", "0", "0", "100", "0", rows, missing)
          }
        _ => (false, "month", "0", "0", "0", "0", "100", "0", rows, missing)
      }
    }
    _ => (false, "month", "0", "0", "0", "0", "100", "0", rows, "0")
  }
}

///|
fn ai_stats_activity_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "type", "—"),
                  json_object_text(row, "title", "—"),
                  json_object_text(row, "detail", "—"),
                  json_object_text(row, "time", "—"),
                  json_object_text(row, "sourceKind", "imported"),
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn ai_hub_usage_from_body(
  body : String,
) -> (Bool, String, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) =>
          (
            true,
            json_object_text(data, "monthlyTotalCalls", "0"),
            json_object_text(data, "minutesSaved", "0"),
            json_object_text(data, "intakeTotal", "0"),
            missing,
          )
        _ => (false, "0", "0", "0", missing)
      }
    }
    _ => (false, "0", "0", "0", "0")
  }
}

///|
fn ai_hub_explain_text_from_body(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          json_object_text(data, "explain", "解释候选响应为空")
        _ => "解释候选响应为空"
      }
    _ => "解释候选响应无效"
  }
}

///|
fn ai_hub_draft_rows_from_body(
  body : String,
) -> (Bool, Array[AiHubDraftRow], String) {
  let rows : Array[AiHubDraftRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  draft_id: json_object_text(row, "draftId", ""),
                  biz_type: json_object_text(row, "bizType", ""),
                  description: json_object_text(row, "description", ""),
                  confidence: json_object_text(row, "confidence", "0"),
                  status: json_object_text(row, "status", ""),
                  created_at: json_object_text(row, "createdAt", ""),
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn ai_hub_query_rows_from_body(
  body : String,
) -> (Bool, Array[AiHubQueryRow], String) {
  let rows : Array[AiHubQueryRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  qid: json_object_text(row, "qid", ""),
                  question: json_object_text(row, "question", ""),
                  explanation: json_object_text(row, "explanation", ""),
                  row_count: json_object_text(row, "rowCount", "0"),
                  duration_ms: json_object_text(row, "durationMs", "0"),
                  error: json_object_text(row, "error", ""),
                  created_at: json_object_text(row, "createdAt", ""),
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn ai_hub_correction_stats_from_body(
  body : String,
) -> (Bool, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) =>
          (
            true,
            json_object_text(data, "total", "0"),
            json_object_text(data, "correctionRate", "0"),
            missing,
          )
        _ => (false, "0", "0", missing)
      }
    }
    _ => (false, "0", "0", "0")
  }
}

///|
fn ai_hub_correction_rows_from_body(
  body : String,
) -> (Bool, Array[AiHubCorrectionRow], String) {
  let rows : Array[AiHubCorrectionRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push({
                  biz_type: json_object_text(row, "bizType", ""),
                  field_name: json_object_text(row, "fieldName", ""),
                  llm_value: json_object_text(row, "llmValue", ""),
                  user_value: json_object_text(row, "userValue", ""),
                  created_at: json_object_text(row, "createdAt", ""),
                  source_kind: json_object_text(row, "sourceKind", "imported"),
                })
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn webhook_config_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      let note = json_object_text(fields, "note", "Webhook 配置只读")
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for platform in ["wecom", "feishu", "dingtalk"] {
            match data.get(platform) {
              Some(Json::Object(row)) =>
                rows.push([
                  json_object_text(row, "label", platform),
                  if json_object_text(row, "enabled", "false") == "true" {
                    "已启用"
                  } else {
                    "未启用"
                  },
                  if json_object_text(row, "urlConfigured", "false") == "true" {
                    json_object_text(row, "url", "已配置（已脱敏）")
                  } else {
                    "— 未配置 —"
                  },
                  if json_object_text(row, "hasSecret", "false") == "true" {
                    json_object_text(row, "secret", "****")
                  } else {
                    "未设置"
                  },
                  json_object_text(row, "sourceKind", "imported"),
                ])
              _ => ()
            }
          }
          (true, rows, missing, note)
        }
        _ => (false, rows, missing, note)
      }
    }
    _ => (false, rows, "0", "Webhook 配置响应无效")
  }
}

///|
fn report_builder_meta_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String, String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "tables") {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "label", "—"),
                  json_object_text(row, "name", "—"),
                  json_array_field(row, "columns").length().to_string(),
                  "白名单",
                  "definition",
                ])
              _ => ()
            }
          }
          (
            true, rows, missing, "字段元数据来自 ERP 白名单定义 · 不执行 SQL",
          )
        }
        _ => (false, rows, missing, "报表元数据响应无效")
      }
    }
    _ => (false, rows, "0", "报表元数据响应无效")
  }
}

///|
fn report_builder_templates_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables")
        .length()
        .to_string()
      match fields.get("data") {
        Some(Json::Array(items)) => {
          for value in items {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "templateName", "—"),
                  json_object_text(row, "baseTable", "—"),
                  json_array_field(row, "columns").length().to_string(),
                  json_array_field(row, "filters").length().to_string(),
                  json_object_text(row, "createdBy", "—"),
                  json_object_text(row, "createdAt", "—"),
                  json_object_text(row, "sourceKind", "imported"),
                ])
              _ => ()
            }
          }
          (true, rows, missing)
        }
        _ => (false, rows, missing)
      }
    }
    _ => (false, rows, "0")
  }
}

///|
fn report_builder_command_from_body(
  body : String,
) -> (Bool, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("template") {
        Some(Json::Object(template)) =>
          (
            true,
            json_object_text(template, "state", "active"),
            json_object_text(template, "template_id", ""),
            if json_object_text(template, "state", "active") == "deleted" {
              "模板已删除 · 仅保留命令投影、回执与审计"
            } else {
              "模板已写入 PostgreSQL 命令投影 · 不触发现金、会计或税务"
            },
          )
        _ => (false, "error", "", "报表模板命令响应无效")
      }
    _ => (false, "error", "", "报表模板命令响应无效")
  }
}

///|
fn report_builder_run_from_body(
  body : String,
) -> (Bool, Array[Array[String]], String) {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "rows") {
            match value {
              Json::Object(row) =>
                rows.push([
                  json_object_text(row, "contract_code", "—"),
                  json_object_text(row, "ht_amount", "0"),
                ])
              _ => ()
            }
          }
          (
            true, rows, "已在导入源信封内存中运行 · sql_executed=false · 不持久化、不触发外部执行",
          )
        }
        _ => (false, rows, "报表运行响应无效")
      }
    _ => (false, rows, "报表运行响应无效")
  }
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
          values.push(json_object_text(data, "buGuid", ""))
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
fn append_initiated_rows(target : Array[InitiatedRow], value : Json) -> Unit {
  match value {
    Json::Object(row) =>
      target.push({
        id: json_object_text(row, "id", ""),
        code: json_object_text(row, "code", ""),
        subject: json_object_text(row, "subject", ""),
        amount: json_object_text(row, "amount", "0"),
        state: json_object_text(row, "state", ""),
        date: json_object_text(row, "date", ""),
        biz: json_object_text(row, "biz", ""),
        source_kind: json_object_text(row, "sourceKind", "imported"),
      })
    _ => ()
  }
}

///|
fn initiated_rows_from_body(body : String) -> Array[InitiatedRow] {
  let rows : Array[InitiatedRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "expenses") {
            append_initiated_rows(rows, value)
          }
          for value in json_array_field(data, "loans") {
            append_initiated_rows(rows, value)
          }
          for value in json_array_field(data, "applies") {
            append_initiated_rows(rows, value)
          }
        }
        _ => ()
      }
    _ => ()
  }
  rows
}

///|
fn expense_rows_from_body(body : String) -> Array[ExpenseRow] {
  let rows : Array[ExpenseRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              expense_id: json_object_text(row, "expenseGuid", ""),
              expense_code: json_object_text(row, "expenseCode", ""),
              subject: json_object_text(row, "subject", ""),
              expense_amount: json_object_text(row, "expenseAmount", "0"),
              apply_date: json_object_text(row, "applyDate", ""),
              apply_state: json_object_text(row, "applyState", ""),
              pay_state: json_object_text(row, "payState", ""),
              applied_by_name: json_object_text(row, "appliedByName", ""),
              apply_dept_name: json_object_text(row, "applyDeptName", ""),
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
fn expense_detail_rows_from_json(value : Json) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  match value {
    Json::Array(values) =>
      for value in values {
        match value {
          Json::Object(fields) =>
            rows.push([
              json_object_text(fields, "summary", "—"),
              json_object_text(fields, "amount", "0"),
              json_object_text(fields, "occurDate", "—"),
              json_object_text(fields, "detailGuid", "—"),
            ])
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn expense_split_rows_from_json(value : Json) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  match value {
    Json::Array(values) =>
      for value in values {
        match value {
          Json::Object(fields) => {
            let user_name = match fields.get("user") {
              Some(Json::Object(user)) =>
                json_object_text(user, "userName", "—")
              _ => "—"
            }
            let dept_name = match fields.get("dept") {
              Some(Json::Object(dept)) =>
                json_object_text(dept, "deptName", "—")
              _ => "—"
            }
            let cost_name = match fields.get("costSubject") {
              Some(Json::Object(cost)) => json_object_text(cost, "name", "—")
              _ => "—"
            }
            let proceeding_name = match fields.get("proceeding") {
              Some(Json::Object(proceeding)) =>
                json_object_text(proceeding, "name", "—")
              _ => "—"
            }
            rows.push([
              user_name,
              dept_name,
              cost_name,
              proceeding_name,
              json_object_text(fields, "amount", "0"),
            ])
          }
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn expense_detail_from_body(body : String) -> (Bool, ExpenseDetail?, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let missing = json_array_field(fields, "missing_or_empty_source_tables").length()
      let source_kind = json_object_text(
        fields, "source_kind", "imported_or_empty",
      )
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let detail_values = match data.get("details") {
            Some(value) => value
            _ => Json::null()
          }
          let split_values = match data.get("splits") {
            Some(value) => value
            _ => Json::null()
          }
          let detail = match data.get("expense") {
            Some(Json::Object(expense)) =>
              Some({
                expense_id: json_object_text(expense, "expenseGuid", ""),
                expense_code: json_object_text(expense, "expenseCode", ""),
                subject: json_object_text(expense, "subject", ""),
                apply_state: json_object_text(expense, "applyState", ""),
                pay_state: json_object_text(expense, "payState", ""),
                expense_amount: json_object_text(expense, "expenseAmount", "0"),
                offset_amount: json_object_text(expense, "offsetAmount", "0"),
                pay_amount: json_object_text(expense, "payAmount", "0"),
                applied_by_name: json_object_text(expense, "appliedByName", ""),
                apply_dept_name: json_object_text(expense, "applyDeptName", ""),
                apply_date: json_object_text(expense, "applyDate", ""),
                pay_unit: json_object_text(expense, "payUnit", ""),
                source_kind: json_object_text(
                  expense, "sourceKind", source_kind,
                ),
                details: expense_detail_rows_from_json(detail_values),
                splits: expense_split_rows_from_json(split_values),
              })
            _ => None
          }
          (
            true,
            detail,
            "已加载 PostgreSQL 报销详情源读模型 · 空源表 " +
            missing.to_string(),
          )
        }
        _ =>
          (false, None, "报销详情响应缺少 data · 使用设计快照")
      }
    }
    _ => (false, None, "报销详情响应无效 · 使用设计快照")
  }
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
fn rbac_role_rows_from_body(body : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push([
              json_object_text(row, "roleCode", ""),
              json_object_text(row, "roleName", ""),
              json_object_text(row, "description", "—"),
              json_object_text(row, "dataScope", "self"),
              json_array_field(row, "permissions").length().to_string(),
              json_object_text(row, "userCount", "0"),
              "只读 · " + json_object_text(row, "sourceKind", "imported"),
            ])
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn rbac_catalog_rows_from_body(body : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push([
              json_object_text(row, "module", ""),
              json_array_field(row, "perms").length().to_string(),
              "定义 · 不授予权限",
            ])
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
fn health_inventory_from_body(
  body : String,
) -> (Bool, String, String, String, String, String, String) {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          let schema_count = json_object_text(data, "schemaTableCount", "0")
          let snapshot_count = json_object_text(data, "snapshotTableCount", "0")
          let schema_only_count = json_object_text(
            data, "schemaOnlyTableCount", "0",
          )
          let export_state = json_object_text(
            fields, "source_export_state", "source_export_incomplete",
          )
          let snapshot_id = json_object_text(fields, "source_snapshot_id", "")
          (
            schema_count != "0" && snapshot_count != "0",
            schema_count,
            snapshot_count,
            schema_only_count,
            export_state,
            snapshot_id,
            "迁移范围来自 hash-bound PostgreSQL 源清单 · promotion/cutover 均未授权",
          )
        }
        _ =>
          (
            false, "0", "0", "0", "响应无迁移范围数据", "", "迁移源范围响应无效",
          )
      }
    _ =>
      (
        false, "0", "0", "0", "响应无迁移范围数据", "", "迁移源范围响应无效",
      )
  }
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
fn budget_scope_user_from_json(value : Json) -> BudgetScopeUserRow? {
  match value {
    Json::Object(fields) =>
      Some({
        user_id: json_object_text(fields, "userId", ""),
        emp_name: json_object_text(fields, "empName", ""),
        dept_guid: json_object_text(fields, "deptGuid", ""),
        bu_guid: json_object_text(fields, "buGuid", ""),
        source_kind: json_object_text(fields, "sourceKind", "imported"),
      })
    _ => None
  }
}

///|
fn budget_scope_users_from_body(body : String) -> Array[BudgetScopeUserRow] {
  let rows : Array[BudgetScopeUserRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match budget_scope_user_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn budget_loan_balance_from_body(body : String) -> (String, String) {
  let mut total = "0"
  let mut count = "0"
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          total = json_object_text(data, "total", "0")
          count = json_array_field(data, "loans").length().to_string()
        }
        _ => ()
      }
    _ => ()
  }
  (total, count)
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
fn workflow_observation_from_json(value : Json) -> WorkflowObservationRow? {
  match value {
    Json::Object(fields) => {
      let initiator_name = match fields.get("initiator") {
        Some(Json::Object(initiator)) =>
          json_object_text(
            initiator,
            "empName",
            json_object_text(initiator, "userName", ""),
          )
        _ => ""
      }
      let current_step_order = match fields.get("currentStep") {
        Some(Json::Object(step)) => json_object_text(step, "stepOrder", "0")
        _ => json_object_text(fields, "currentStepOrder", "0")
      }
      let current_step_name = match fields.get("currentStep") {
        Some(Json::Object(step)) => json_object_text(step, "stepName", "")
        _ => ""
      }
      Some({
        process_instance_guid: json_object_text(
          fields, "processInstanceGuid", "",
        ),
        process_name: json_object_text(fields, "processName", ""),
        biz_type: json_object_text(fields, "bizType", ""),
        biz_data_guid: json_object_text(fields, "bizDataGuid", ""),
        status: json_object_text(fields, "status", ""),
        initiated_at: json_object_text(fields, "initiatedAt", ""),
        decision: json_object_text(
          fields,
          "myLastDecision",
          json_object_text(fields, "decision", ""),
        ),
        source_kind: json_object_text(fields, "sourceKind", "imported_or_empty"),
        initiator_name,
        completed_at: json_object_text(fields, "completedAt", ""),
        last_action_time: json_object_text(fields, "myLastActionTime", ""),
        current_step_order,
        current_step_name,
      })
    }
    _ => None
  }
}

///|
fn workflow_observation_rows_from_body(
  body : String,
) -> Array[WorkflowObservationRow] {
  let rows : Array[WorkflowObservationRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match workflow_observation_from_json(value) {
          Some(row) => rows.push(row)
          None => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn workflow_ticket_from_json(value : Json) -> WorkflowTicketRow? {
  match value {
    Json::Object(fields) => {
      let warning_fields = match fields.get("warning") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      Some({
        ticket_id: json_object_text(fields, "ticketId", ""),
        warning_guid: json_object_text(fields, "warningGuid", ""),
        status: json_object_text(fields, "status", "open"),
        note: json_object_text(fields, "note", ""),
        due_date: json_object_text(fields, "dueDate", ""),
        created_at: json_object_text(fields, "createdAt", ""),
        created_by: json_object_text(fields, "createdBy", ""),
        handled_at: json_object_text(fields, "handledAt", ""),
        assignee_user_id: json_object_text(fields, "assigneeUserId", ""),
        source_kind: json_object_text(fields, "sourceKind", "imported_or_empty"),
        rule_code: json_object_text(warning_fields, "ruleCode", ""),
        rule_name: json_object_text(warning_fields, "ruleName", ""),
        severity: json_object_text(warning_fields, "severity", ""),
        biz_type: json_object_text(warning_fields, "bizType", ""),
        biz_data_guid: json_object_text(warning_fields, "bizDataGuid", ""),
        title: json_object_text(warning_fields, "title", ""),
      })
    }
    _ => None
  }
}

///|
fn workflow_ticket_rows_from_body(body : String) -> Array[WorkflowTicketRow] {
  let rows : Array[WorkflowTicketRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match workflow_ticket_from_json(value) {
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
fn project_stage_rows_from_body(body : String) -> Array[ProjectStageRow] {
  let rows : Array[ProjectStageRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(root) => {
      let data = match root.get("data") {
        Some(Json::Object(value)) => value
        _ => root
      }
      for value in json_array_field(data, "stages") {
        match value {
          Json::Object(fields) =>
            rows.push({
              stage_code: json_object_text(fields, "stageCode", ""),
              stage_name: json_object_text(fields, "stageName", ""),
              stage_order: json_object_text(fields, "stageOrder", "0"),
              status: json_object_text(fields, "status", "pending"),
              progress_pct: json_object_text(fields, "progressPct", "0"),
              planned_start: json_object_text(fields, "plannedStart", ""),
              planned_end: json_object_text(fields, "plannedEnd", ""),
              actual_start: json_object_text(fields, "actualStart", ""),
              actual_end: json_object_text(fields, "actualEnd", ""),
              source_kind: json_object_text(fields, "sourceKind", "imported"),
            })
          _ => ()
        }
      }
    }
    _ => ()
  }
  rows
}

///|
fn project_kpi_from_body(body : String) -> ProjectKpi? {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(root) => {
      let data = match root.get("data") {
        Some(Json::Object(value)) => value
        _ => return None
      }
      let kpi = match data.get("kpi") {
        Some(Json::Object(value)) => value
        _ => return None
      }
      let progress = match kpi.get("progress") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let cost = match kpi.get("cost") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let contract = match kpi.get("contract") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let payment = match kpi.get("payment") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let cash = match kpi.get("cash") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let profit = match kpi.get("profit") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      let approval = match kpi.get("approval") {
        Some(Json::Object(value)) => value
        _ => {}
      }
      Some({
        progress_avg: json_object_text(progress, "avgProgress", "0"),
        progress_done: json_object_text(progress, "done", "0"),
        progress_total_nodes: json_object_text(progress, "totalNodes", "0"),
        progress_overdue_nodes: json_object_text(progress, "overdueNodes", "0"),
        cost_deviation_pct: json_object_text(cost, "deviationPct", "0"),
        cost_dynamic: json_object_text(cost, "dynamic", "0"),
        cost_target: json_object_text(cost, "target", "0"),
        contract_total: json_object_text(contract, "totalAmount", "0"),
        contract_count: json_object_text(contract, "count", "0"),
        payment_paid_ratio: json_object_text(payment, "paidRatio", "0"),
        payment_paid_total: json_object_text(payment, "paidTotal", "0"),
        payment_apply_total: json_object_text(payment, "applyTotal", "0"),
        cash_this_month_plan: json_object_text(cash, "thisMonthPlan", "0"),
        profit_irr: json_object_text(profit, "irr", ""),
        profit_net_profit: json_object_text(profit, "netProfit", ""),
        profit_npv: json_object_text(profit, "npv", ""),
        approval_avg_days: json_object_text(approval, "avgDays", ""),
      })
    }
    _ => None
  }
}

///|
fn project_anomaly_rows_from_body(body : String) -> Array[ProjectAnomalyRow] {
  let rows : Array[ProjectAnomalyRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              severity: json_object_text(row, "severity", "warning"),
              title: json_object_text(row, "title", "项目风险预警"),
              detail: json_object_text(row, "detail", ""),
              suggestion: json_object_text(row, "suggestion", ""),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn load_sales_for(
  emit : @rabbita.Emit[Msg],
  family : String,
  project_id : String,
  keyword : String,
) -> Cmd {
  let path = if family == "invoices" {
    "/api/company/invoices"
  } else {
    let project_query = if project_id.trim().is_empty() {
      ""
    } else {
      "?projGuid=" + project_id
    }
    let keyword_query = if (family == "customers" || family == "revenues") &&
      !keyword.trim().is_empty() {
      (if project_query.is_empty() { "?keyword=" } else { "&keyword=" }) +
      keyword
    } else {
      ""
    }
    "/api/company/source/sales/" + family + project_query + keyword_query
  }
  @http.get(path).expect_text(result => {
    match result {
      Ok(body) => emit(SalesLoaded(family, body))
      Err(_) => emit(SalesLoadFailed(family))
    }
  })
}

///|
fn load_sales(emit : @rabbita.Emit[Msg], family : String) -> Cmd {
  load_sales_for(emit, family, "proj-0001", "")
}

///|
fn load_invoice_source_in_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/source/invoice/in?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(InvoiceSourceInLoaded(body))
        Err(_) => emit(InvoiceSourceLoadFailed)
      }
    },
  )
}

///|
fn load_invoice_source_out_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/source/invoice/out?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(InvoiceSourceOutLoaded(body))
        Err(_) => emit(InvoiceSourceLoadFailed)
      }
    },
  )
}

///|
fn load_invoice_source_tax_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/source/invoice/tax-ledger?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(InvoiceSourceTaxLoaded(body))
        Err(_) => emit(InvoiceSourceLoadFailed)
      }
    },
  )
}

///|
fn invoice_authority(
  model : Model,
  direction : String,
  max_amount_minor : Double,
) -> Json {
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("principal-rabbita"),
    "actor_id": Json::string(model.user_code),
    "scope": Json::string("project:" + model.invoice_project_id),
    "capability": Json::string("invoice:" + direction + ":create"),
    "max_amount_minor": Json::number(max_amount_minor),
  })
}

///|
fn issue_invoice_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
  direction : String,
) -> Cmd {
  let nonce = import_nonce()
  let path = "/api/company/source/invoice/" + direction
  let fields : Map[String, Json] = {
    "idempotency_key": Json::string(
      "rabbita-invoice-" + direction + "-" + nonce,
    ),
    "invoiceNo": Json::string(
      if model.invoice_no.is_empty() {
        "INV-RABBITA-" + nonce
      } else {
        model.invoice_no
      },
    ),
    "projGuid": Json::string(model.invoice_project_id),
    "invoiceDate": Json::string(model.invoice_date),
    "totalAmount": Json::string(model.invoice_total_amount),
    "taxRate": Json::string(model.invoice_tax_rate),
    "invoiceType": Json::string(model.invoice_type),
    "remark": Json::string(model.invoice_remark),
    "principal_id": Json::string("principal-rabbita"),
    "scope": Json::string("project:" + model.invoice_project_id),
    "authority": invoice_authority(model, direction, 2000000000.0),
  }
  if direction == "in" {
    fields.set("providerName", Json::string(model.invoice_counterparty))
  } else {
    fields.set("customerName", Json::string(model.invoice_counterparty))
  }
  let body = Json::object(fields).stringify()
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(_) => emit(InvoiceCommandFinished)
      Err(_) => emit(InvoiceCommandFailed)
    }
  })
}

///|
fn issue_invoice_delete(
  emit : @rabbita.Emit[Msg],
  model : Model,
  direction : String,
  invoice_id : String,
) -> Cmd {
  let nonce = import_nonce()
  let scope = "project:" + model.invoice_project_id
  let body = Json::object({
    "idempotency_key": Json::string(
      "rabbita-invoice-delete-" + direction + "-" + nonce,
    ),
    "principal_id": Json::string("principal-rabbita"),
    "scope": Json::string(scope),
    "authority": Json::object({
      "active": Json::boolean(true),
      "principal_id": Json::string("principal-rabbita"),
      "actor_id": Json::string(model.user_code),
      "scope": Json::string(scope),
      "capability": Json::string("invoice:" + direction + ":delete"),
      "max_amount_minor": Json::number(0.0),
    }),
  }).stringify()
  @http.post(
    "/api/company/source/invoice/" + direction + "/" + invoice_id + "/delete",
  )
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(_) => emit(InvoiceCommandFinished)
      Err(_) => emit(InvoiceCommandFailed)
    }
  })
}

///|
fn load_delivery(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  load_delivery_source_progress_for(emit, project_id)
}

///|
fn load_delivery_for_project(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/delivery/overview?project_id=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(DeliveryLoaded(body))
        Err(_) => emit(DeliveryLoadFailed)
      }
    },
  )
}

///|
fn load_delivery_source_progress_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/source/delivery/progress?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(DeliverySourceProgressLoaded(body))
        Err(_) => emit(DeliverySourceLoadFailed)
      }
    },
  )
}

///|
fn load_delivery_source_outputs_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/source/delivery/outputs?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(DeliverySourceOutputsLoaded(body))
        Err(_) => emit(DeliverySourceLoadFailed)
      }
    },
  )
}

///|
fn load_delivery_overview_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/delivery/overview?project_id=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(DeliveryLoaded(body))
        Err(_) => emit(DeliveryLoadFailed)
      }
    },
  )
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
fn load_dashboard_v2(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/dashboard/v2/group").expect_text(result => {
    match result {
      Ok(body) => emit(DashboardV2Loaded(body))
      Err(_) => emit(DashboardV2LoadFailed)
    }
  })
}

///|
fn load_dashboard_v3(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/dashboard/v3/group").expect_text(result => {
    match result {
      Ok(body) => emit(DashboardV3Loaded(body))
      Err(_) => emit(DashboardV3LoadFailed)
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
fn admin_dict_editable_guid(model : Model) -> String {
  for row in model.admin_dict_option_rows {
    if row.source_kind == "command" && row.param_guid != "" {
      return row.param_guid
    }
  }
  ""
}

///|
fn admin_dict_command_body(command_type : String) -> String {
  if command_type == "create" {
    "{\"idempotency_key\":\"rabbita-admin-dict-create-v1\",\"groupName\":\"rabbita_local\",\"code\":\"rabbita_option\",\"value\":\"Rabbita 本地字典演示\",\"displayOrder\":99}"
  } else {
    "{\"idempotency_key\":\"rabbita-admin-dict-update-v1\",\"enabled\":false,\"value\":\"Rabbita 本地字典已复核\",\"displayOrder\":100}"
  }
}

///|
fn issue_admin_dict_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/admin/dict/options"
  } else {
    "/api/company/admin/dict/options/" + admin_dict_editable_guid(model)
  }
  let body = admin_dict_command_body(command_type)
  if command_type == "create" {
    @http.post(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(AdminDictCommandFinished(value))
        Err(_) => emit(AdminDictCommandFailed)
      }
    })
  } else {
    @http.patch(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(AdminDictCommandFinished(value))
        Err(_) => emit(AdminDictCommandFailed)
      }
    })
  }
}

///|
fn issue_admin_backup(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/backup/db").expect_text(result => {
    match result {
      Ok(body) => emit(AdminBackupFinished(body))
      Err(_) => emit(AdminBackupFailed)
    }
  })
}

///|
fn load_investment_versions_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/investment/projects/" + project_id + "/versions").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentVersionsLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn load_investment_versions(emit : @rabbita.Emit[Msg]) -> Cmd {
  load_investment_versions_for(emit, "proj-0001")
}

///|
fn load_investment_imports_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/investment/projects/" + project_id + "/excel-imports").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentImportsLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn load_investment_imports(emit : @rabbita.Emit[Msg]) -> Cmd {
  load_investment_imports_for(emit, "proj-0001")
}

///|
fn load_investment_import_detail(
  emit : @rabbita.Emit[Msg],
  import_id : String,
) -> Cmd {
  @http.get("/api/company/investment/excel-imports/" + import_id).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentImportDetailLoaded(body))
      Err(_) => emit(InvestmentImportDetailLoaded("{}"))
    }
  })
}

///|
fn load_investment_import_bridge(
  emit : @rabbita.Emit[Msg],
  import_id : String,
) -> Cmd {
  @http.get(
    "/api/company/investment/excel-imports/" + import_id + "/bridge-plan",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentImportBridgeLoaded(body))
      Err(_) => emit(InvestmentImportBridgeLoaded("{}"))
    }
  })
}

///|
fn load_investment_import_index_preview(
  emit : @rabbita.Emit[Msg],
  import_id : String,
) -> Cmd {
  @http.get(
    "/api/company/investment/excel-imports/" +
    import_id +
    "/index-upsert-preview",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentImportIndexPreviewLoaded(body))
      Err(_) => emit(InvestmentImportIndexPreviewLoaded("{}"))
    }
  })
}

///|
fn load_investment_import_profit(
  emit : @rabbita.Emit[Msg],
  import_id : String,
) -> Cmd {
  @http.get(
    "/api/company/investment/excel-imports/" + import_id + "/profit-table",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentImportProfitLoaded(body))
      Err(_) => emit(InvestmentImportProfitLoaded("{}"))
    }
  })
}

///|
fn load_investment_import_plan(
  emit : @rabbita.Emit[Msg],
  import_id : String,
) -> Cmd {
  @http.get(
    "/api/company/investment/excel-imports/" + import_id + "/plan-line-preview",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentImportPlanLoaded(body))
      Err(_) => emit(InvestmentImportPlanLoaded("{}"))
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
fn load_investment_profit_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get(
    "/api/company/investment/projects/" + project_id + "/profit-summary",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentProfitLoaded(body))
      Err(_) => emit(InvestmentLoadFailed)
    }
  })
}

///|
fn load_investment_sensitivity_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/investment/projects/" + project_id + "/sensitivity").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentSensitivityLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn load_investment_profit_actual_for(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/investment/projects/" + project_id + "/profit-actual").expect_text(result => {
      match result {
        Ok(body) => emit(InvestmentProfitActualLoaded(body))
        Err(_) => emit(InvestmentLoadFailed)
      }
    },
  )
}

///|
fn issue_investment_explain(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post(
    "/api/company/investment/projects/" +
    model.investment_project_id +
    "/ai-explain",
  )
  .with_text("{}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentExplainFinished(body))
      Err(_) => emit(InvestmentExplainFailed)
    }
  })
}

///|
fn issue_investment_excel_upload(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  @http.post(
    "/api/company/investment/projects/" +
    model.investment_project_id +
    "/excel-imports",
  )
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-investment-excel-upload-" + import_nonce(),
      ),
      "fileName": Json::string(model.investment_excel_file_name),
      "versionName": Json::string(model.investment_excel_version_name),
      "activate": Json::boolean(model.investment_excel_activate),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentExcelUploadFinished(body))
      Err(_) => emit(InvestmentExcelUploadFailed)
    }
  })
}

///|
fn issue_investment_subject_mappings(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  @http.put(
    "/api/company/investment/projects/" +
    model.investment_project_id +
    "/subject-mappings",
  )
  .with_text(
    "{\"idempotency_key\":\"rabbita-investment-subject-mappings-v1\",\"dryRun\":true,\"items\":[{\"group\":\"revenue\",\"subjectCode\":\"INV-REVENUE\",\"subjectName\":\"项目销售收入\"}]}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentSubjectMappingsFinished(body))
      Err(_) => emit(InvestmentSubjectMappingsFailed)
    }
  })
}

///|
fn issue_investment_plan_line_update(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.put("/api/company/investment/plan-lines/PLAN-RABBITA-LOCAL")
  .with_text(
    "{\"idempotency_key\":\"rabbita-investment-plan-line-update-v1\",\"dryRun\":true,\"subject\":\"项目销售收入\",\"status\":\"adjusted\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentPlanLineUpdateFinished(body))
      Err(_) => emit(InvestmentPlanLineUpdateFailed)
    }
  })
}

///|
fn issue_investment_index_upsert(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let import_id = if model.investment_import_selected.is_empty() {
    "IMPORT-RABBITA-LOCAL"
  } else {
    model.investment_import_selected
  }
  @http.post(
    "/api/company/investment/excel-imports/" + import_id + "/index-upsert",
  )
  .with_text(
    "{\"idempotency_key\":\"rabbita-investment-index-upsert-v1\",\"dryRun\":true,\"force\":false}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentIndexUpsertFinished(body))
      Err(_) => emit(InvestmentIndexUpsertFailed)
    }
  })
}

///|
fn issue_investment_plan_line_import(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let import_id = if model.investment_import_selected.is_empty() {
    "IMPORT-RABBITA-LOCAL"
  } else {
    model.investment_import_selected
  }
  @http.post(
    "/api/company/investment/excel-imports/" + import_id + "/plan-lines/import",
  )
  .with_text(
    "{\"idempotency_key\":\"rabbita-investment-plan-line-import-v1\",\"dryRun\":true,\"replaceExisting\":false}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(InvestmentPlanLineImportFinished(body))
      Err(_) => emit(InvestmentPlanLineImportFailed)
    }
  })
}

///|
fn investment_edit_value_json(value : String) -> Json {
  let parsed = @json.parse(value.trim()) catch { _ => Json::null() }
  match parsed {
    Json::Number(_, ..) => parsed
    _ => Json::string(value)
  }
}

///|
fn issue_investment_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let version_id = if model.investment_version_id.is_empty() {
    "INV-RABBITA-V2"
  } else {
    model.investment_version_id
  }
  let index_id = if model.investment_index_selected.is_empty() {
    "INV-RABBITA-INDEX"
  } else {
    model.investment_index_selected
  }
  let project_id = model.investment_project_id
  let (path, default_body) = if command_type == "version_create" {
    (
      "/api/company/investment/projects/" + project_id + "/versions",
      "{\"idempotency_key\":\"rabbita-investment-version-create-v1\",\"versionGuid\":\"INV-RABBITA-V2\",\"versionName\":\"Rabbita 本地投资版本\",\"activate\":false,\"remark\":\"本地投资版本命令候选\"}",
    )
  } else if command_type == "version_activate" {
    (
      "/api/company/investment/projects/" +
      project_id +
      "/versions/" +
      version_id +
      "/activate",
      "{\"idempotency_key\":\"rabbita-investment-version-activate-v1\"}",
    )
  } else if command_type == "version_delete" {
    (
      "/api/company/investment/projects/" +
      project_id +
      "/versions/" +
      version_id,
      "{\"idempotency_key\":\"rabbita-investment-version-delete-v1\"}",
    )
  } else if command_type == "index_create" {
    (
      "/api/company/investment/versions/" + version_id + "/indices",
      "{\"idempotency_key\":\"rabbita-investment-index-create-v1\",\"indexGuid\":\"INV-RABBITA-INDEX\",\"dimension\":\"investment\",\"fullCode\":\"Inv.Rabbita\",\"indexName\":\"Rabbita 投资指标\",\"unit\":\"万元\",\"indexValue\":100,\"remark\":\"本地指标命令候选\"}",
    )
  } else if command_type == "index_update" {
    (
      "/api/company/investment/indices/" + index_id,
      "{\"idempotency_key\":\"rabbita-investment-index-update-v1\",\"indexValue\":120,\"remark\":\"本地指标已复核\"}",
    )
  } else {
    (
      "/api/company/investment/indices/" + index_id,
      "{\"idempotency_key\":\"rabbita-investment-index-delete-v1\"}",
    )
  }
  let body = if command_type == "version_create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-investment-version-create-v1"),
      "versionGuid": Json::string("INV-RABBITA-V2"),
      "versionName": Json::string(model.investment_new_version_name),
      "copyFrom": Json::string(model.investment_new_version_copy_from),
      "activate": Json::boolean(model.investment_new_version_activate),
      "remark": Json::string(model.investment_new_version_remark),
    }).stringify()
  } else if command_type == "index_create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-investment-index-create-v1"),
      "indexGuid": Json::string("INV-RABBITA-INDEX"),
      "dimension": Json::string(model.investment_new_index_dimension),
      "fullCode": Json::string(model.investment_new_index_full_code),
      "indexName": Json::string(model.investment_new_index_name),
      "parentCode": Json::string(model.investment_new_index_parent_code),
      "unit": Json::string(model.investment_new_index_unit),
      "indexValue": investment_edit_value_json(model.investment_new_index_value),
      "remark": Json::string(model.investment_new_index_remark),
    }).stringify()
  } else if command_type == "index_update" {
    Json::object({
      "idempotency_key": Json::string("rabbita-investment-index-update-v1"),
      "indexValue": investment_edit_value_json(
        model.investment_index_edit_value,
      ),
      "remark": Json::string(model.investment_index_edit_remark),
    }).stringify()
  } else {
    default_body
  }
  if command_type == "version_delete" {
    @http.delete(path + "?idempotency_key=rabbita-investment-version-delete-v1").expect_text(result => {
        match result {
          Ok(value) => emit(InvestmentCommandFinished(command_type, value))
          Err(_) => emit(InvestmentCommandFailed(command_type))
        }
      },
    )
  } else if command_type == "index_delete" {
    @http.delete(path + "?idempotency_key=rabbita-investment-index-delete-v1").expect_text(result => {
        match result {
          Ok(value) => emit(InvestmentCommandFinished(command_type, value))
          Err(_) => emit(InvestmentCommandFailed(command_type))
        }
      },
    )
  } else {
    let request = if command_type == "index_update" {
      @http.put(path)
    } else {
      @http.post(path)
    }
    request
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(InvestmentCommandFinished(command_type, value))
        Err(_) => emit(InvestmentCommandFailed(command_type))
      }
    })
  }
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
fn load_dynamic_cost(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/cost/dynamic-cost?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(DynamicCostLoaded(body))
        Err(_) => emit(DynamicCostLoadFailed)
      }
    },
  )
}

///|
fn load_dynamic_cost_remarks(
  emit : @rabbita.Emit[Msg],
  cost_id : String,
) -> Cmd {
  @http.get("/api/company/source/cost/dynamic-cost/" + cost_id + "/remarks").expect_text(result => {
      match result {
        Ok(body) => emit(DynamicCostRemarksLoaded(body))
        Err(_) => emit(DynamicCostRemarksLoadFailed)
      }
    },
  )
}

///|
fn dynamic_cost_remarks_from_body(body : String) -> Array[String] {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  let fields = match parsed {
    Json::Object(root) =>
      match root.get("data") {
        Some(Json::Object(data)) => data
        _ => root
      }
    _ => {}
  }
  [
    json_object_text(fields, "costCode", ""),
    json_object_text(fields, "costName", ""),
    json_object_text(fields, "remarks", ""),
    json_object_text(fields, "projectName", ""),
    json_object_text(fields, "sourceKind", ""),
  ]
}

///|
fn dynamic_cost_csv(model : Model) -> String {
  let lines : Array[String] = []
  lines.push(
    "科目编码,科目名称,层级,A 目标成本,B 动态成本,C 偏差率%,D 合约+变更,E 在途,F 待发生,G 预估变更,H 规划余量",
  )
  for row in model.dynamic_cost_rows {
    lines.push(
      [
        row.cost_code,
        row.cost_name,
        row.cost_level,
        row.target_cost,
        row.dynamic_cost,
        row.deviation_pct,
        row.contract_change,
        row.actual_cost,
        row.budget_cost,
        row.estimate_change,
        row.layout_spare,
      ]
      .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
      .join(","),
    )
  }
  lines.join("\n")
}

///|
fn dynamic_cost_export_body(model : Model) -> String {
  let rows : Array[String] = []
  for row in model.dynamic_cost_rows {
    rows.push(
      Json::object({
        "costCode": Json::string(row.cost_code),
        "costName": Json::string(row.cost_name),
        "costLevel": Json::string(row.cost_level),
        "A_targetCost": Json::string(row.target_cost),
        "B_dtCost": Json::string(row.dynamic_cost),
        "C_deviationPct": Json::string(row.deviation_pct),
        "D_htAlterAmount": Json::string(row.contract_change),
        "E_ztCost": Json::string(row.actual_cost),
        "F_dfsBudget": Json::string(row.budget_cost),
        "G_ygAlter": Json::string(row.estimate_change),
        "H_layoutSpare": Json::string(row.layout_spare),
      }).stringify(),
    )
  }
  let summary_rows = [
    Json::object({
      "k": Json::string("末端科目数"),
      "v": Json::string(model.dynamic_cost_end_count),
    }).stringify(),
    Json::object({
      "k": Json::string("A 目标成本"),
      "v": Json::string(model.dynamic_cost_target),
    }).stringify(),
    Json::object({
      "k": Json::string("B 动态成本"),
      "v": Json::string(model.dynamic_cost_total),
    }).stringify(),
    Json::object({
      "k": Json::string("C 偏差率(%)"),
      "v": Json::string(model.dynamic_cost_deviation),
    }).stringify(),
    Json::object({
      "k": Json::string("H 规划余量"),
      "v": Json::string(model.dynamic_cost_spare),
    }).stringify(),
  ]
  "{\"filename\":\"dynamic-cost\",\"sheets\":[" +
  "{\"name\":\"科目明细\",\"columns\":[" +
  "{\"label\":\"科目编码\",\"field\":\"costCode\"},{\"label\":\"科目名称\",\"field\":\"costName\"},{\"label\":\"层级\",\"field\":\"costLevel\"},{\"label\":\"A 目标成本\",\"field\":\"A_targetCost\"},{\"label\":\"B 动态成本\",\"field\":\"B_dtCost\"},{\"label\":\"C 偏差率(%)\",\"field\":\"C_deviationPct\"},{\"label\":\"D 合约+变更\",\"field\":\"D_htAlterAmount\"},{\"label\":\"E 在途\",\"field\":\"E_ztCost\"},{\"label\":\"F 待发生\",\"field\":\"F_dfsBudget\"},{\"label\":\"G 预估变更\",\"field\":\"G_ygAlter\"},{\"label\":\"H 规划余量\",\"field\":\"H_layoutSpare\"}],\"rows\":[" +
  rows.join(",") +
  "]},{\"name\":\"项目汇总\",\"columns\":[{\"label\":\"指标\",\"field\":\"k\"},{\"label\":\"值\",\"field\":\"v\"}],\"rows\":[" +
  summary_rows.join(",") +
  "]}]}"
}

///|
fn issue_dynamic_cost_export(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/export/excel")
  .with_text(dynamic_cost_export_body(model))
  .expect_blob(result => {
    match result {
      Ok(blob) => emit(DynamicCostExportFinished(blob))
      Err(_) => emit(DynamicCostExportFailed)
    }
  })
}

///|
fn dynamic_cost_create_body(model : Model) -> String {
  Json::object({
    "idempotency_key": Json::string("rabbita-dynamic-cost-create-v1"),
    "projGuid": Json::string("proj-0001"),
    "costCode": Json::string(model.dynamic_cost_create_code),
    "costName": Json::string(model.dynamic_cost_create_name),
    "costLevel": investment_edit_value_json(model.dynamic_cost_create_level),
    "parentCostGuid": Json::string(model.dynamic_cost_create_parent),
    "isEndCost": Json::boolean(true),
    "targetCost": investment_edit_value_json(model.dynamic_cost_create_target),
    "htAlterAmount": investment_edit_value_json(
      model.dynamic_cost_create_contract_change,
    ),
    "ztCost": investment_edit_value_json(model.dynamic_cost_create_in_transit),
    "dfsBudget": investment_edit_value_json(model.dynamic_cost_create_budget),
    "ygAlter": investment_edit_value_json(
      model.dynamic_cost_create_estimate_change,
    ),
    "remarks": Json::string(model.dynamic_cost_create_remarks),
  }).stringify()
}

///|
fn issue_dynamic_cost_create(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/cost/dynamic-cost")
  .with_text(dynamic_cost_create_body(model))
  .expect_text(result => {
    match result {
      Ok(body) => emit(DynamicCostCommandFinished(body))
      Err(_) => emit(DynamicCostCommandFailed)
    }
  })
}

///|
fn load_cost_dashboard(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get(
    "/api/company/investment/projects/proj-0001/profit-actual-v2?planVersion=baseline",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(CostDashboardLoaded(body))
      Err(_) => emit(CostDashboardLoadFailed)
    }
  })
}

///|
fn load_cashflow(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/cashflow/forecast?months=6&projGuid=proj-0001").expect_text(result => {
      match result {
        Ok(body) => emit(CashflowLoaded(body))
        Err(_) => emit(CashflowLoadFailed)
      }
    },
  )
}

///|
fn load_cashflow_inflow(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/cashflow/inflow?months=6&projGuid=proj-0001").expect_text(result => {
      match result {
        Ok(body) => emit(CashflowInflowLoaded(body))
        Err(_) => emit(CashflowInflowLoadFailed)
      }
    },
  )
}

///|
fn issue_cashflow_explain(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/cashflow/ai-explain")
  .with_text(
    "{\"series\":[{\"month\":\"2026-08\",\"net\":-1200000}],\"gapWeeks\":[{\"week\":\"2026-W33\",\"gap\":1200000}]}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(CashflowExplainFinished(body))
      Err(_) => emit(CashflowExplainFailed)
    }
  })
}

///|
fn load_cbs(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/cbs/dict?projGuid=proj-0001").expect_text(result => {
    match result {
      Ok(body) => emit(CbsLoaded(body))
      Err(_) => emit(CbsLoadFailed)
    }
  })
}

///|
fn load_cbs_r0(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/cbs/r0/queue?projGuid=proj-0001").expect_text(result => {
    match result {
      Ok(body) => emit(CbsR0Loaded(body))
      Err(_) => emit(CbsR0LoadFailed)
    }
  })
}

///|
fn load_fund_for(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/fund/plans?projGuid=" + project_id).expect_text(result => {
    match result {
      Ok(body) => emit(FundLoaded(body))
      Err(_) => emit(FundLoadFailed)
    }
  })
}

///|
fn load_fund_gap_for(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/fund/gap-analysis?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(FundGapLoaded(body))
        Err(_) => emit(FundGapLoadFailed)
      }
    },
  )
}

///|
fn load_fund_dispatches(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/fund/dispatches").expect_text(result => {
    match result {
      Ok(body) => emit(FundDispatchLoaded(body))
      Err(_) => emit(FundDispatchLoadFailed)
    }
  })
}

///|
fn fund_authority_json(
  model : Model,
  capability : String,
  max_amount_minor : Double,
) -> Json {
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("principal-rabbita"),
    "actor_id": Json::string(model.user_code),
    "capability": Json::string(capability),
    "scope": Json::string("project:" + model.fund_project_id),
    "max_amount_minor": Json::number(max_amount_minor),
  })
}

///|
fn fund_amount_minor_json(value : String) -> Json {
  let parsed = @json.parse(value) catch { _ => Json::null() }
  match parsed {
    Json::Number(number, ..) => Json::number(number * 1000000.0)
    _ => Json::number(0.0)
  }
}

///|
fn fund_command_body(model : Model, command_type : String) -> String {
  if command_type == "create_plan" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-fund-plan-create-" + import_nonce(),
      ),
      "plan_id": Json::string("FP-RABBITA-LOCAL"),
      "plan_code": Json::string("FP-RABBITA-LOCAL"),
      "project_id": Json::string(model.fund_project_id),
      "plan_period": Json::string(model.fund_plan_period),
      "direction": Json::string(model.fund_plan_direction),
      "category": Json::string(model.fund_plan_category),
      "r_code": Json::string(model.fund_plan_r_code),
      "plan_amount_minor": fund_amount_minor_json(model.fund_plan_amount),
      "remark": Json::string(model.fund_plan_remark),
      "authority": fund_authority_json(model, "fund:plan:create", 2000000000.0),
    }).stringify()
  } else if command_type == "update_plan" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-fund-plan-update-" + import_nonce(),
      ),
      "plan_period": Json::string(model.fund_plan_period),
      "direction": Json::string(model.fund_plan_direction),
      "category": Json::string(model.fund_plan_category),
      "r_code": Json::string(model.fund_plan_r_code),
      "plan_amount_minor": fund_amount_minor_json(model.fund_plan_amount),
      "actual_amount_minor": fund_amount_minor_json(
        model.fund_plan_actual_amount,
      ),
      "remark": Json::string(model.fund_plan_remark),
    }).stringify()
  } else if command_type == "delete_plan" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-fund-plan-delete-" + import_nonce(),
      ),
      "reason": Json::string(
        if model.fund_plan_remark.is_empty() {
          "Rabbita 资金计划撤回"
        } else {
          model.fund_plan_remark
        },
      ),
    }).stringify()
  } else if command_type == "create_dispatch" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-fund-dispatch-create-" + import_nonce(),
      ),
      "dispatch_id": Json::string("FD-RABBITA-LOCAL"),
      "dispatch_code": Json::string("FD-RABBITA-LOCAL"),
      "project_id": Json::string(model.fund_project_id),
      "from_project_id": Json::string(model.fund_dispatch_from),
      "to_project_id": Json::string(model.fund_dispatch_to),
      "amount_minor": fund_amount_minor_json(model.fund_dispatch_amount),
      "reason": Json::string(model.fund_dispatch_reason),
      "dispatch_date": Json::string(model.fund_dispatch_date),
      "authority": fund_authority_json(
        model, "fund:dispatch:create", 2000000000.0,
      ),
    }).stringify()
  } else {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-fund-dispatch-approve-" + import_nonce(),
      ),
      "authority": fund_authority_json(
        model, "fund:dispatch:approve", 2000000000.0,
      ),
    }).stringify()
  }
}

///|
fn issue_fund_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create_plan" {
    "/api/company/fund/plans"
  } else if command_type == "update_plan" {
    "/api/company/fund/plans/" + model.fund_plan_id
  } else if command_type == "delete_plan" {
    "/api/company/fund/plans/" + model.fund_plan_id + "/delete"
  } else if command_type == "create_dispatch" {
    "/api/company/fund/dispatches"
  } else {
    "/api/company/fund/dispatches/" + model.fund_dispatch_id + "/approve"
  }
  let body = fund_command_body(model, command_type)
  if command_type == "update_plan" {
    @http.put(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(FundCommandFinished(value))
        Err(_) => emit(FundCommandFailed)
      }
    })
  } else {
    @http.post(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(FundCommandFinished(value))
        Err(_) => emit(FundCommandFailed)
      }
    })
  }
}

///|
fn load_warnings(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/warning?status=open").expect_text(result => {
    match result {
      Ok(body) => emit(WarningsLoaded(body))
      Err(_) => emit(WarningsLoadFailed)
    }
  })
}

///|
fn load_warning_rules(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/warning/rules").expect_text(result => {
    match result {
      Ok(body) => emit(WarningRulesLoaded(body))
      Err(_) => emit(WarningRulesLoadFailed)
    }
  })
}

///|
fn warning_command_body(model : Model, command_type : String) -> String {
  "{\"note\":\"Rabbita 本地告警处理演示\",\"idempotency_key\":\"rabbita-warning-" +
  command_type +
  "-" +
  model.warning_action_guid +
  "\"}"
}

///|
fn issue_warning_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  @http.post(
    "/api/company/warning/" + model.warning_action_guid + "/" + command_type,
  )
  .with_text(warning_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(WarningCommandFinished(body))
      Err(_) => emit(WarningCommandFailed)
    }
  })
}

///|
fn issue_warning_custom_rule_preview(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/warning/custom-rules/preview")
  .with_text(
    "{\"idempotency_key\":\"rabbita-warning-custom-preview-v1\",\"sqlTemplate\":\"SELECT 1\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(WarningCustomRulePreviewFinished(body))
      Err(_) => emit(WarningCustomRulePreviewFailed)
    }
  })
}

///|
fn issue_warning_custom_rule_command(
  emit : @rabbita.Emit[Msg],
  create : Bool,
) -> Cmd {
  if create {
    @http.post("/api/company/source/warning/custom-rules")
    .with_text(
      "{\"idempotency_key\":\"rabbita-warning-custom-create-v1\",\"ruleCode\":\"XRABBITA\",\"ruleName\":\"Rabbita 本地规则\",\"severity\":\"warning\",\"bizType\":\"project\",\"sqlTemplate\":\"SELECT 1\",\"enabled\":true}",
    )
    .expect_text(result => {
      match result {
        Ok(body) => emit(WarningCustomRuleCommandFinished(body))
        Err(_) => emit(WarningCustomRuleCommandFailed)
      }
    })
  } else {
    @http.delete(
      "/api/company/source/warning/custom-rules/XRABBITA?idempotency_key=rabbita-warning-custom-delete-v1",
    ).expect_text(result => {
      match result {
        Ok(body) => emit(WarningCustomRuleCommandFinished(body))
        Err(_) => emit(WarningCustomRuleCommandFailed)
      }
    })
  }
}

///|
fn issue_warning_ticket_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let warning_guid = if model.warning_action_guid.is_empty() {
    "source:W005:proj-0002"
  } else {
    model.warning_action_guid
  }
  let ticket_id = "local-ticket-rabbita-warning-ticket-create-v1"
  let (path, body) = if command_type == "create" {
    (
      "/api/company/source/warning/" + warning_guid + "/to-ticket",
      "{\"idempotency_key\":\"rabbita-warning-ticket-create-v1\",\"assigneeUserId\":\"user-admin-0001\",\"note\":\"Rabbita 本地告警工单候选\",\"dueDate\":\"2030-01-01\"}",
    )
  } else if command_type == "handling" {
    (
      "/api/company/source/warning/tickets/" + ticket_id + "/status",
      "{\"idempotency_key\":\"rabbita-warning-ticket-handling-v1\",\"status\":\"handling\",\"note\":\"Rabbita 已开始处理\"}",
    )
  } else if command_type == "done" {
    (
      "/api/company/source/warning/tickets/" + ticket_id + "/status",
      "{\"idempotency_key\":\"rabbita-warning-ticket-done-v1\",\"status\":\"done\",\"note\":\"Rabbita 已完成处理\"}",
    )
  } else if command_type == "reassign" {
    (
      "/api/company/source/warning/tickets/" + ticket_id + "/reassign",
      "{\"idempotency_key\":\"rabbita-warning-ticket-reassign-v1\",\"newAssigneeUserId\":\"user-lmj-0001\",\"reason\":\"Rabbita 本地转派候选\"}",
    )
  } else {
    (
      "/api/company/source/warning/tickets/" + ticket_id + "/extend",
      "{\"idempotency_key\":\"rabbita-warning-ticket-extend-v1\",\"newDueDate\":\"2030-02-01\",\"reason\":\"Rabbita 本地延期候选\"}",
    )
  }
  if command_type == "create" {
    @http.post(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(WarningTicketCommandFinished(command_type, value))
        Err(_) => emit(WarningTicketCommandFailed(command_type))
      }
    })
  } else {
    @http.patch(path)
    .with_text(body)
    .expect_text(result => {
      match result {
        Ok(value) => emit(WarningTicketCommandFinished(command_type, value))
        Err(_) => emit(WarningTicketCommandFailed(command_type))
      }
    })
  }
}

///|
fn issue_warning_scan_preview(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/warning/scan")
  .with_text("{\"idempotency_key\":\"rabbita-warning-scan-preview-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(WarningScanPreviewFinished(body))
      Err(_) => emit(WarningScanPreviewFailed)
    }
  })
}

///|
fn attachment_query(model : Model) -> String {
  let mut query = ""
  if !model.attachment_ai_status.is_empty() {
    query = query + "?aiStatus=" + model.attachment_ai_status
  }
  if !model.attachment_keyword.is_empty() {
    query = query +
      (if query.is_empty() { "?" } else { "&" }) +
      "keyword=" +
      model.attachment_keyword
  }
  query
}

///|
fn load_attachments(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.get("/api/company/attachments/all" + attachment_query(model)).expect_text(result => {
      match result {
        Ok(body) => emit(AttachmentsLoaded(body))
        Err(_) => emit(AttachmentsLoadFailed)
      }
    },
  )
}

///|
fn load_attachment_stats(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/attachments/stats").expect_text(result => {
    match result {
      Ok(body) => emit(AttachmentStatsLoaded(body))
      Err(_) => emit(AttachmentStatsLoadFailed)
    }
  })
}

///|
fn issue_attachment_upload(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/attachments/upload")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-attachment-upload-" + import_nonce(),
      ),
      "fileName": Json::string(model.attachment_file_name),
      "mimeType": Json::string(model.attachment_file_mime),
      "fileSize": Json::string(model.attachment_file_size),
      "bizType": Json::string(model.attachment_biz_type),
      "bizGuid": Json::string("RABBITA-ATTACHMENT-LOCAL"),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(AttachmentCommandFinished(body))
      Err(_) => emit(AttachmentCommandFailed)
    }
  })
}

///|
fn issue_attachment_download(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.get("/api/company/attachments/download/" + model.attachment_action_guid).expect_text(result => {
      match result {
        Ok(body) => emit(AttachmentDownloadFinished(body))
        Err(_) => emit(AttachmentDownloadFailed)
      }
    },
  )
}

///|
fn issue_attachment_reextract(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post(
    "/api/company/attachments/re-extract/" + model.attachment_action_guid,
  )
  .with_text("{}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(AttachmentReextractFinished(body))
      Err(_) => emit(AttachmentReextractFailed)
    }
  })
}

///|
fn issue_attachment_delete(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.delete("/api/company/attachments/" + model.attachment_action_guid).expect_text(result => {
      match result {
        Ok(body) => emit(AttachmentDeleteFinished(body))
        Err(_) => emit(AttachmentDeleteFailed)
      }
    },
  )
}

///|
fn load_marketing_for(
  emit : @rabbita.Emit[Msg],
  family : String,
  project_id : String,
) -> Cmd {
  let path = if family == "campaigns" {
    "/api/company/marketing/campaigns?projGuid=" + project_id
  } else if family == "placements" {
    "/api/company/marketing/placements"
  } else if family == "channels" {
    "/api/company/marketing/channels"
  } else {
    "/api/company/marketing/materials?projGuid=" + project_id
  }
  @http.get(path).expect_text(result => {
    match result {
      Ok(body) => emit(MarketingLoaded(family, body))
      Err(_) => emit(MarketingLoadFailed(family))
    }
  })
}

///|
fn marketing_number(value : String, scale : Double) -> Json {
  let parsed = @json.parse(value) catch { _ => Json::null() }
  match parsed {
    Json::Number(number, ..) => Json::number(number * scale)
    _ => Json::number(0.0)
  }
}

///|
fn marketing_authority(
  model : Model,
  capability : String,
  max_amount_minor : Double,
) -> Json {
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("co-rabbita"),
    "actor_id": Json::string(model.user_code),
    "scope": Json::string("project:" + model.marketing_project_id),
    "capability": Json::string(capability),
    "max_amount_minor": Json::number(max_amount_minor),
  })
}

///|
fn issue_marketing_campaign_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = import_nonce()
  @http.post("/api/company/marketing/campaigns")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-marketing-campaign-create-" + nonce,
      ),
      "campaignGuid": Json::string("CAMP-RABBITA-" + nonce),
      "campaignCode": Json::string("CAMP-RABBITA-" + nonce),
      "projGuid": Json::string(model.marketing_project_id),
      "name": Json::string(
        if model.marketing_campaign_name.is_empty() {
          "Rabbita 本地营销活动"
        } else {
          model.marketing_campaign_name
        },
      ),
      "campaignType": Json::string(model.marketing_campaign_type),
      "budget": marketing_number(model.marketing_campaign_budget, 10000.0),
      "startDate": Json::string(model.marketing_campaign_start),
      "endDate": Json::string(model.marketing_campaign_end),
      "goal": Json::string(model.marketing_campaign_goal),
      "remark": Json::string(model.marketing_campaign_remark),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string("project:" + model.marketing_project_id),
      "authority": marketing_authority(
        model, "marketing:campaign:create", 2000000000.0,
      ),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(MarketingCommandFinished(body))
      Err(_) => emit(MarketingCommandFailed)
    }
  })
}

///|
fn issue_marketing_campaign_delete(
  emit : @rabbita.Emit[Msg],
  campaign_id : String,
) -> Cmd {
  let key = "rabbita-marketing-campaign-delete-" + import_nonce()
  @http.delete(
    "/api/company/marketing/campaigns/" +
    campaign_id +
    "?idempotency_key=" +
    key,
  ).expect_text(result => {
    match result {
      Ok(body) => emit(MarketingCommandFinished(body))
      Err(_) => emit(MarketingCommandFailed)
    }
  })
}

///|
fn issue_marketing_placement_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = import_nonce()
  @http.post("/api/company/marketing/placements")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-marketing-placement-create-" + nonce,
      ),
      "placementGuid": Json::string("PLAC-RABBITA-" + nonce),
      "placementCode": Json::string("PLAC-RABBITA-" + nonce),
      "campaignGuid": Json::string(model.marketing_placement_campaign),
      "channelGuid": Json::string(model.marketing_placement_channel),
      "channelName": Json::string(
        if model.marketing_placement_channel_name.is_empty() {
          "Rabbita 本地渠道"
        } else {
          model.marketing_placement_channel_name
        },
      ),
      "amount": marketing_number(model.marketing_placement_amount, 10000.0),
      "placeDate": Json::string(model.marketing_placement_date),
      "durationDays": marketing_number(model.marketing_placement_duration, 1.0),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string("project:" + model.marketing_project_id),
      "authority": marketing_authority(
        model, "marketing:placement:create", 2000000000.0,
      ),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(MarketingCommandFinished(body))
      Err(_) => emit(MarketingCommandFailed)
    }
  })
}

///|
fn issue_marketing_channel_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = import_nonce()
  @http.post("/api/company/marketing/channels")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-marketing-channel-create-" + nonce,
      ),
      "channelGuid": Json::string("CH-RABBITA-" + nonce),
      "channelCode": Json::string("CH-RABBITA-" + nonce),
      "name": Json::string(
        if model.marketing_channel_name.is_empty() {
          "Rabbita 本地渠道"
        } else {
          model.marketing_channel_name
        },
      ),
      "channelType": Json::string(model.marketing_channel_type),
      "contactPerson": Json::string(model.marketing_channel_contact),
      "contactPhone": Json::string(model.marketing_channel_phone),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string("project:" + model.marketing_project_id),
      "authority": marketing_authority(model, "marketing:channel:create", 0.0),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(MarketingCommandFinished(body))
      Err(_) => emit(MarketingCommandFailed)
    }
  })
}

///|
fn issue_marketing_material_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = import_nonce()
  @http.post("/api/company/marketing/materials")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-marketing-material-create-" + nonce,
      ),
      "materialGuid": Json::string("MAT-RABBITA-" + nonce),
      "materialCode": Json::string("MAT-RABBITA-" + nonce),
      "projGuid": Json::string(model.marketing_project_id),
      "name": Json::string(
        if model.marketing_material_name.is_empty() {
          "Rabbita 本地物料"
        } else {
          model.marketing_material_name
        },
      ),
      "materialType": Json::string(model.marketing_material_type),
      "unitCost": marketing_number(model.marketing_material_unit_cost, 1.0),
      "quantity": marketing_number(model.marketing_material_quantity, 1.0),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string("project:" + model.marketing_project_id),
      "authority": marketing_authority(
        model, "marketing:material:create", 2000000000.0,
      ),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(MarketingCommandFinished(body))
      Err(_) => emit(MarketingCommandFailed)
    }
  })
}

///|
fn load_inbox(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/notify/messages?userCode=admin&status=unread").expect_text(result => {
      match result {
        Ok(body) => emit(InboxLoaded(body))
        Err(_) => emit(InboxLoadFailed)
      }
    },
  )
}

///|
fn load_inbox_unread(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/notify/messages/unread-count?userCode=admin").expect_text(result => {
      match result {
        Ok(body) => emit(InboxUnreadLoaded(body))
        Err(_) => emit(InboxUnreadLoadFailed)
      }
    },
  )
}

///|
fn mark_inbox_read_all(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/notify/messages/read-all")
  .with_text("{\"idempotency_key\":\"rabbita-inbox-read-all-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(InboxCommandFinished(body))
      Err(_) => emit(InboxCommandFailed)
    }
  })
}

///|
fn load_notify(emit : @rabbita.Emit[Msg], family : String) -> Cmd {
  let path = if family == "subscriptions" {
    "/api/company/notify/subscriptions?userCode=admin"
  } else if family == "config" {
    "/api/company/notify/config"
  } else if family == "outbox" {
    "/api/company/notify/email-outbox"
  } else if family == "preview" {
    "/api/company/notify/digest/preview"
  } else if family == "digest" {
    "/api/company/notify/digest/log"
  } else {
    "/api/company/notify/llm-providers"
  }
  @http.get(path).expect_text(result => {
    match result {
      Ok(body) if family == "subscriptions" =>
        emit(NotifySubscriptionsLoaded(body))
      Ok(body) if family == "config" => emit(NotifyConfigLoaded(body))
      Ok(body) if family == "outbox" => emit(NotifyOutboxLoaded(body))
      Ok(body) if family == "preview" => emit(NotifyDigestPreviewLoaded(body))
      Ok(body) if family == "digest" => emit(NotifyDigestLoaded(body))
      Ok(body) => emit(NotifyProvidersLoaded(body))
      Err(_) => emit(NotifyLoadFailed(family))
    }
  })
}

///|
fn issue_notify_subscription_create(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/notify/subscriptions")
  .with_text(
    "{\"idempotency_key\":\"rabbita-notify-subscription-create-v1\",\"ruleCode\":\"W005\",\"bizType\":\"expense\",\"severityMin\":\"warning\",\"channels\":[\"in_app\",\"webhook\"],\"enabled\":true}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(NotifyCommandFinished(body))
      Err(_) => emit(NotifyCommandFailed)
    }
  })
}

///|
fn issue_notify_digest_dispatch(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/notify/digest/dispatch")
  .with_text("{\"idempotency_key\":\"rabbita-notify-digest-dispatch-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(NotifyDigestDispatchFinished(body))
      Err(_) => emit(NotifyDigestDispatchFailed)
    }
  })
}

///|
fn issue_notify_email_command(
  emit : @rabbita.Emit[Msg],
  command_type : String,
) -> Cmd {
  let path = if command_type == "test" {
    "/api/company/source/notify/email-outbox/test"
  } else {
    "/api/company/source/notify/email-outbox/EMAIL-RABBITA-LOCAL/redeliver"
  }
  let body = if command_type == "test" {
    "{\"idempotency_key\":\"rabbita-notify-email-test-v1\",\"to\":\"qa@example.com\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-notify-email-redeliver-v1\"}"
  }
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(value) => emit(NotifyEmailCommandFinished(command_type, value))
      Err(_) => emit(NotifyEmailCommandFailed(command_type))
    }
  })
}

///|
fn load_ocr(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/ocr/status").expect_text(result => {
    match result {
      Ok(body) => emit(OcrLoaded(body))
      Err(_) => emit(OcrLoadFailed)
    }
  })
}

///|
fn issue_ocr_config_save(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/admin/sys-param")
  .with_text(
    "{\"idempotency_key\":\"rabbita-ocr-config-save-v1\",\"code\":\"ocr.provider\",\"value\":\"paddle\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(OcrConfigCommandFinished(body))
      Err(_) => emit(OcrConfigCommandFailed)
    }
  })
}

///|
fn issue_ocr_provider_test(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/admin/ocr/test")
  .with_text(
    "{\"idempotency_key\":\"rabbita-ocr-test-v1\",\"provider\":\"paddle\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(OcrCommandFinished(body))
      Err(_) => emit(OcrCommandFailed)
    }
  })
}

///|
fn issue_ai_provider_test(emit : @rabbita.Emit[Msg], family : String) -> Cmd {
  let path = if family == "llm" {
    "/api/company/source/admin/llm/test"
  } else {
    "/api/company/source/notify/llm-test"
  }
  let body = if family == "llm" {
    "{\"idempotency_key\":\"rabbita-llm-test-v1\",\"provider\":\"mock\",\"model\":\"native-preview\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-notify-llm-test-v1\",\"provider\":\"mock\",\"model\":\"native-preview\"}"
  }
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(value) => emit(ProviderCommandFinished(family, value))
      Err(_) => emit(ProviderCommandFailed(family))
    }
  })
}

///|
fn load_error_log(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/admin/error-log?limit=100").expect_text(result => {
    match result {
      Ok(body) => emit(ErrorLogLoaded(body))
      Err(_) => emit(ErrorLogLoadFailed)
    }
  })
}

///|
fn load_ai_stats_overview(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-stats/overview?period=month").expect_text(result => {
    match result {
      Ok(body) => emit(AiStatsOverviewLoaded(body))
      Err(_) => emit(AiStatsLoadFailed)
    }
  })
}

///|
fn load_ai_stats_activity(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-stats/activity?limit=30").expect_text(result => {
    match result {
      Ok(body) => emit(AiStatsActivityLoaded(body))
      Err(_) => emit(AiStatsLoadFailed)
    }
  })
}

///|
fn ai_stats_export_body(model : Model) -> String {
  "{\"filename\":\"ai-stats\",\"sheets\":[{\"name\":\"AI概览\",\"columns\":[{\"label\":\"指标\",\"field\":\"metric\"},{\"label\":\"数值\",\"field\":\"value\"},{\"label\":\"口径\",\"field\":\"scope\"}],\"rows\":[" +
  "{\"metric\":\"本月调用\",\"value\":\"" +
  model.ai_stats_intake_total +
  "\",\"scope\":\"AI 起单记录\"}," +
  "{\"metric\":\"自然语言查询\",\"value\":\"" +
  model.ai_stats_query_total +
  "\",\"scope\":\"查询调用记录\"}," +
  "{\"metric\":\"自动跳过\",\"value\":\"" +
  model.ai_stats_skip_total +
  "\",\"scope\":\"人工确认记录\"}," +
  "{\"metric\":\"准确率\",\"value\":\"" +
  model.ai_stats_accuracy +
  "%\",\"scope\":\"源分析估算\"}," +
  "{\"metric\":\"节省人工\",\"value\":\"" +
  model.ai_stats_saved_hours +
  " 小时\",\"scope\":\"按确认记录估算\"}]}]}"
}

///|
fn issue_ai_stats_export(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/export/excel")
  .with_text(ai_stats_export_body(model))
  .expect_blob(result => {
    match result {
      Ok(blob) => emit(AiStatsExportFinished(blob))
      Err(_) => emit(AiStatsExportFailed)
    }
  })
}

///|
fn load_ai_hub_usage(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-hub/usage-stats").expect_text(result => {
    match result {
      Ok(body) => emit(AiHubUsageLoaded(body))
      Err(_) => emit(AiHubLoadFailed)
    }
  })
}

///|
fn load_ai_hub_drafts(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-hub/drafts?userCode=admin").expect_text(result => {
    match result {
      Ok(body) => emit(AiHubDraftsLoaded(body))
      Err(_) => emit(AiHubLoadFailed)
    }
  })
}

///|
fn load_ai_hub_query_log(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-hub/query-log?userCode=admin").expect_text(result => {
    match result {
      Ok(body) => emit(AiHubQueryLogLoaded(body))
      Err(_) => emit(AiHubLoadFailed)
    }
  })
}

///|
fn load_ai_hub_correction_stats(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-hub/correction-stats").expect_text(result => {
    match result {
      Ok(body) => emit(AiHubCorrectionStatsLoaded(body))
      Err(_) => emit(AiHubLoadFailed)
    }
  })
}

///|
fn load_ai_hub_corrections(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/ai-hub/corrections?limit=50").expect_text(result => {
    match result {
      Ok(body) => emit(AiHubCorrectionsLoaded(body))
      Err(_) => emit(AiHubLoadFailed)
    }
  })
}

///|
fn issue_ai_hub_explain(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/ai-hub/explain")
  .with_text(
    "{\"title\":\"AI 工作台源读模型\",\"focus\":\"异常值与时间范围\",\"table\":[{\"metric\":\"drafts\",\"value\":0},{\"metric\":\"queries\",\"value\":0}]}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(AiHubExplainFinished(body))
      Err(_) => emit(AiHubExplainFailed)
    }
  })
}

///|
fn issue_ai_hub_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let body = if command_type == "intake" {
    Json::object({
      "idempotency_key": Json::string("rabbita-ai-hub-intake-" + import_nonce()),
      "bizType": Json::string(model.ai_hub_intake_biz_hint),
      "description": Json::string(model.ai_hub_intake_description),
      "fileName": Json::string(model.ai_hub_file_name),
      "source": Json::string("rabbita"),
    }).stringify()
  } else if command_type == "confirm" {
    "{\"idempotency_key\":\"rabbita-ai-hub-confirm-v1\",\"draftId\":\"DRAFT-RABBITA-LOCAL\"}"
  } else if command_type == "discard" {
    "{\"idempotency_key\":\"rabbita-ai-hub-discard-v1\",\"draftId\":\"DRAFT-RABBITA-LOCAL\"}"
  } else if command_type == "query" {
    Json::object({
      "idempotency_key": Json::string("rabbita-ai-hub-query-" + import_nonce()),
      "question": Json::string(
        if model.ai_hub_query_text.is_empty() {
          "项目成本异常在哪里？"
        } else {
          model.ai_hub_query_text
        },
      ),
    }).stringify()
  } else if command_type == "rule-from-nl" {
    "{\"idempotency_key\":\"rabbita-ai-hub-rule-v1\",\"prompt\":\"成本偏差超过 5% 时提醒负责人\"}"
  } else if command_type == "approval-draft" {
    "{\"idempotency_key\":\"rabbita-ai-hub-approval-draft-v1\",\"draftId\":\"DRAFT-RABBITA-LOCAL\"}"
  } else if command_type == "global-ask" {
    "{\"idempotency_key\":\"rabbita-ai-hub-global-ask-v1\",\"question\":\"未来 90 天资金缺口？\"}"
  } else if command_type == "query-session" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-ai-hub-query-session-" + import_nonce(),
      ),
      "sessionId": Json::string("SESSION-RABBITA-LOCAL"),
      "question": Json::string(
        if model.ai_hub_query_text.is_empty() {
          "查看本月合同付款"
        } else {
          model.ai_hub_query_text
        },
      ),
    }).stringify()
  } else {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-ai-hub-command-" + import_nonce(),
      ),
      "command": Json::string(
        if model.ai_hub_command_text.is_empty() {
          "preview"
        } else {
          model.ai_hub_command_text
        },
      ),
    }).stringify()
  }
  @http.post("/api/company/source/ai-hub/" + command_type)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(value) => emit(AiHubCommandFinished(command_type, value))
      Err(_) => emit(AiHubCommandFailed(command_type))
    }
  })
}

///|
fn load_webhook_config(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/webhook/config").expect_text(result => {
    match result {
      Ok(body) => emit(WebhookLoaded(body))
      Err(_) => emit(WebhookLoadFailed)
    }
  })
}

///|
fn issue_webhook_config_save(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.put("/api/company/source/webhook/config/wecom")
  .with_text(
    "{\"idempotency_key\":\"rabbita-webhook-config-save-v1\",\"enabled\":true,\"secret\":\"__keep__\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(WebhookConfigCommandFinished(body))
      Err(_) => emit(WebhookConfigCommandFailed)
    }
  })
}

///|
fn issue_webhook_test(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/webhook/test/wecom")
  .with_text(
    "{\"idempotency_key\":\"rabbita-webhook-test-v1\",\"title\":\"Rabbita 干运行测试\",\"content\":\"不会发送到外部 provider\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(WebhookCommandFinished(body))
      Err(_) => emit(WebhookCommandFailed)
    }
  })
}

///|
fn issue_webhook_overdue_preview(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/webhook/scan-overdue/preview")
  .with_text("{\"idempotency_key\":\"rabbita-webhook-overdue-preview-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(WebhookOverduePreviewFinished(body))
      Err(_) => emit(WebhookOverduePreviewFailed)
    }
  })
}

///|
fn issue_webhook_overdue_scan(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/webhook/scan-overdue")
  .with_text("{\"idempotency_key\":\"rabbita-webhook-overdue-scan-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(WebhookOverdueScanFinished(body))
      Err(_) => emit(WebhookOverdueScanFailed)
    }
  })
}

///|
fn load_report_builder_meta(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/reports/templates/meta").expect_text(result => {
    match result {
      Ok(body) => emit(ReportBuilderMetaLoaded(body))
      Err(_) => emit(ReportBuilderLoadFailed)
    }
  })
}

///|
fn load_report_builder_templates(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/reports/templates").expect_text(result => {
    match result {
      Ok(body) => emit(ReportBuilderTemplatesLoaded(body))
      Err(_) => emit(ReportBuilderLoadFailed)
    }
  })
}

///|
fn report_builder_create_body() -> String {
  "{\"templateName\":\"Rabbita 本地合同报表\",\"description\":\"本地报表模板命令演示\",\"baseTable\":\"cb_contract\",\"columns\":[\"contract_code\",\"ht_amount\"],\"filters\":[{\"field\":\"ht_amount\",\"op\":\">\",\"value\":0}],\"orderBy\":\"ht_amount desc\",\"isShared\":false,\"idempotency_key\":\"rabbita-report-template-create-v1\"}"
}

///|
fn report_builder_run_body() -> String {
  "{\"baseTable\":\"cb_contract\",\"columns\":[\"contract_code\",\"ht_amount\"],\"filters\":[{\"field\":\"ht_amount\",\"op\":\">\",\"value\":0}],\"orderBy\":\"ht_amount desc\",\"limit\":20,\"idempotency_key\":\"rabbita-report-template-run-v1\"}"
}

///|
fn issue_report_builder_create(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/reports/templates")
  .with_text(report_builder_create_body())
  .expect_text(result => {
    match result {
      Ok(body) => emit(ReportBuilderCommandFinished(body))
      Err(_) => emit(ReportBuilderCommandFailed)
    }
  })
}

///|
fn issue_report_builder_run(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/reports/templates/run")
  .with_text(report_builder_run_body())
  .expect_text(result => {
    match result {
      Ok(body) => emit(ReportBuilderRunFinished(body))
      Err(_) => emit(ReportBuilderCommandFailed)
    }
  })
}

///|
fn issue_report_builder_delete(
  emit : @rabbita.Emit[Msg],
  template_id : String,
) -> Cmd {
  @http.delete(
    "/api/company/reports/templates/" +
    template_id +
    "?idempotency_key=rabbita-report-template-delete-v1",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(ReportBuilderCommandFinished(body))
      Err(_) => emit(ReportBuilderCommandFailed)
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
fn load_profile_initiated(emit : @rabbita.Emit[Msg], user_code : String) -> Cmd {
  let code = if user_code == "" { "admin" } else { user_code }
  @http.get("/api/company/auth/my-initiated?userCode=" + code).expect_text(result => {
    match result {
      Ok(body) => emit(ProfileInitiatedLoaded(body))
      Err(_) => emit(ProfileInitiatedLoadFailed)
    }
  })
}

///|
fn issue_profile_update(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let body = Json::object({
    "idempotency_key": Json::string("rabbita-auth-profile-" + import_nonce()),
    "empName": Json::string(model.profile_edit_name),
    "userName": Json::string(model.profile_user_name),
  }).stringify()
  @http.put("/api/company/auth/profile")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(body) => emit(ProfileCommandFinished(body))
      Err(_) => emit(ProfileCommandFailed)
    }
  })
}

///|
fn issue_password_change(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let body = Json::object({
    "idempotency_key": Json::string("rabbita-auth-password-" + import_nonce()),
    "oldPassword": Json::string(model.profile_password_old),
    "newPassword": Json::string(model.profile_password_new),
  }).stringify()
  @http.post("/api/company/auth/change-password")
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(body) => emit(ProfileCommandFinished(body))
      Err(_) => emit(ProfileCommandFailed)
    }
  })
}

///|
fn logout_after_password_change(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/session/logout").expect_text(_ => {
    emit(ProfilePasswordLoggedOut)
  })
}

///|
fn load_expenses(emit : @rabbita.Emit[Msg], user_code : String) -> Cmd {
  let code = if user_code == "" { "admin" } else { user_code }
  @http.get("/api/company/budget/expenses?userCode=" + code).expect_text(result => {
    match result {
      Ok(body) => emit(ExpensesLoaded(body))
      Err(_) => emit(ExpensesLoadFailed)
    }
  })
}

///|
fn load_expense_detail(
  emit : @rabbita.Emit[Msg],
  path : String,
  user_code : String,
) -> Cmd {
  let expense_id = match path.rev_split_once("/") {
    Some((_, value)) => value.to_owned()
    _ => ""
  }
  let code = if user_code == "" { "admin" } else { user_code }
  @http.get("/api/company/budget/expenses/" + expense_id + "?userCode=" + code).expect_text(result => {
      match result {
        Ok(body) => emit(ExpenseDetailLoaded(body))
        Err(_) => emit(ExpenseDetailLoadFailed)
      }
    },
  )
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
fn issue_rbac_user_create(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/rbac/users")
  .with_text(
    "{\"idempotency_key\":\"rabbita-rbac-user-create-v1\",\"userCode\":\"rabbita-local-user\",\"empName\":\"Rabbita 本地用户\",\"password\":\"not-returned\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacUserCommandFinished(body))
      Err(_) => emit(RbacUserCommandFailed)
    }
  })
}

///|
fn issue_rbac_role_create(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/rbac/roles")
  .with_text(
    "{\"idempotency_key\":\"rabbita-rbac-role-create-v1\",\"roleCode\":\"rabbita-local-role\",\"roleName\":\"Rabbita 本地角色\",\"dataScope\":\"self\",\"permissions\":[\"dashboard:read\"]}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacRoleCommandFinished(body))
      Err(_) => emit(RbacRoleCommandFailed)
    }
  })
}

///|
fn issue_rbac_role_assignment(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/rbac/users/user-admin-0001/roles")
  .with_text(
    "{\"idempotency_key\":\"rabbita-rbac-role-assignment-v1\",\"roleCodes\":[\"rabbita-local-role\"]}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacAssignmentFinished(body))
      Err(_) => emit(RbacAssignmentFailed)
    }
  })
}

///|
fn issue_rbac_user_toggle(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/rbac/users/user-admin-0001/toggle")
  .with_text("{\"idempotency_key\":\"rabbita-rbac-user-toggle-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacUserToggleFinished(body))
      Err(_) => emit(RbacUserToggleFailed)
    }
  })
}

///|
fn issue_rbac_user_reset(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/rbac/users/user-admin-0001/reset-password")
  .with_text(
    "{\"idempotency_key\":\"rabbita-rbac-user-reset-v1\",\"password\":\"not-returned\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacUserResetFinished(body))
      Err(_) => emit(RbacUserResetFailed)
    }
  })
}

///|
fn issue_rbac_role_delete(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.delete(
    "/api/company/rbac/roles/rabbita-local-role?idempotency_key=rabbita-rbac-role-delete-v1",
  ).expect_text(result => {
    match result {
      Ok(body) => emit(RbacRoleDeleteFinished(body))
      Err(_) => emit(RbacRoleDeleteFailed)
    }
  })
}

///|
fn issue_rbac_user_update(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.put("/api/company/rbac/users/user-admin-0001")
  .with_text(
    "{\"idempotency_key\":\"rabbita-rbac-user-update-v1\",\"empName\":\"Rabbita 管理员（已复核）\"}",
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(RbacUserUpdateFinished(body))
      Err(_) => emit(RbacUserUpdateFailed)
    }
  })
}

///|
fn load_rbac_roles(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/rbac/roles").expect_text(result => {
    match result {
      Ok(body) => emit(RbacRolesLoaded(body))
      Err(_) => emit(RbacRolesLoadFailed)
    }
  })
}

///|
fn load_rbac_catalog(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/rbac/permission-catalog").expect_text(result => {
    match result {
      Ok(body) => emit(RbacCatalogLoaded(body))
      Err(_) => emit(RbacCatalogLoadFailed)
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
fn load_health_inventory(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/migration/schema-coverage").expect_text(result => {
    match result {
      Ok(body) => emit(HealthInventoryLoaded(body))
      Err(_) => emit(HealthInventoryLoadFailed)
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
fn load_budget_scope(emit : @rabbita.Emit[Msg], bu_guid : String) -> Cmd {
  let bu_query = if bu_guid == "" { "" } else { "?buGuid=" + bu_guid }
  @http.get("/api/company/source/budget/users-in-bu" + bu_query).expect_text(result => {
    match result {
      Ok(body) => emit(BudgetScopeLoaded(body))
      Err(_) => emit(BudgetScopeLoadFailed)
    }
  })
}

///|
fn load_budget_loan_balance(
  emit : @rabbita.Emit[Msg],
  user_code : String,
) -> Cmd {
  let query = if user_code == "" { "" } else { "?userCode=" + user_code }
  @http.get("/api/company/source/budget/my-loan-balance" + query).expect_text(result => {
    match result {
      Ok(body) => emit(BudgetLoanBalanceLoaded(body))
      Err(_) => emit(BudgetScopeLoadFailed)
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
fn load_workflow_observation_pending(
  emit : @rabbita.Emit[Msg],
  user_code : String,
) -> Cmd {
  @http.get("/api/company/source/workflow/tasks/mine?userCode=" + user_code).expect_text(result => {
      match result {
        Ok(body) => emit(WorkflowObservationPendingLoaded(body))
        Err(_) => emit(WorkflowObservationLoadFailed)
      }
    },
  )
}

///|
fn load_workflow_observation_initiated(
  emit : @rabbita.Emit[Msg],
  user_code : String,
) -> Cmd {
  @http.get(
    "/api/company/source/workflow/tasks/initiated?userCode=" + user_code,
  ).expect_text(result => {
    match result {
      Ok(body) => emit(WorkflowObservationInitiatedLoaded(body))
      Err(_) => emit(WorkflowObservationLoadFailed)
    }
  })
}

///|
fn load_workflow_observation_history(
  emit : @rabbita.Emit[Msg],
  user_code : String,
) -> Cmd {
  @http.get(
    "/api/company/source/workflow/tasks/my-history?userCode=" + user_code,
  ).expect_text(result => {
    match result {
      Ok(body) => emit(WorkflowObservationHistoryLoaded(body))
      Err(_) => emit(WorkflowObservationLoadFailed)
    }
  })
}

///|
fn load_workflow_tickets(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/warning/tickets/mine").expect_text(result => {
    match result {
      Ok(body) => emit(WorkflowTicketsLoaded(body))
      Err(_) => emit(WorkflowTicketsLoadFailed)
    }
  })
}

///|
fn issue_workflow_command(
  emit : @rabbita.Emit[Msg],
  command_type : String,
) -> Cmd {
  let instance_id = "wf-rabbita-workflow-start-v1"
  let (path, body) = if command_type == "start" {
    (
      "/api/company/source/workflow/instances", "{\"idempotency_key\":\"rabbita-workflow-start-v1\",\"processKey\":\"expense-approval\",\"bizType\":\"Expense\",\"bizDataGuid\":\"RABBITA-WORKFLOW-LOCAL\"}",
    )
  } else if command_type == "approve" {
    (
      "/api/company/source/workflow/instances/" + instance_id + "/approve",
      "{\"idempotency_key\":\"rabbita-workflow-approve-v1\",\"comment\":\"Rabbita 本地工作流审批候选\"}",
    )
  } else if command_type == "reject" {
    (
      "/api/company/source/workflow/instances/" + instance_id + "/reject",
      "{\"idempotency_key\":\"rabbita-workflow-reject-v1\",\"comment\":\"Rabbita 本地工作流驳回候选\"}",
    )
  } else if command_type == "cosign" {
    (
      "/api/company/source/workflow/instances/" + instance_id + "/cosigners",
      "{\"idempotency_key\":\"rabbita-workflow-cosign-v1\",\"cosigners\":[\"admin\"]}",
    )
  } else {
    (
      "/api/company/source/workflow/instances/" + instance_id + "/transfer",
      "{\"idempotency_key\":\"rabbita-workflow-transfer-v1\",\"toUserId\":\"admin\"}",
    )
  }
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(value) => emit(WorkflowCommandFinished(command_type, value))
      Err(_) => emit(WorkflowCommandFailed(command_type))
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
fn import_input_id(biz_type : String) -> String {
  "erp-import-" + biz_type + "-file"
}

///|
fn parse_import_csv(text : String) -> ImportCsvData {
  let normalized = if text.has_prefix("\u{FEFF}") {
    text[1:].to_owned()
  } else {
    text
  }
  let lines = normalized.split("\n").to_array()
  if lines.length() == 0 {
    return {
      headers: [],
      preview_rows: [],
      rows_json: "[]",
      row_count: "0",
      within_limit: false,
    }
  }
  let headers : Array[String] = []
  for header in lines[0].split(",") {
    headers.push(header.trim().to_owned())
  }
  let json_rows : Array[Json] = []
  let preview_rows : Array[Array[String]] = []
  for index in 1..<lines.length() {
    let line = lines[index].trim()
    if line.is_empty() {
      continue
    }
    let values = line.split(",").to_array()
    let fields : Map[String, Json] = {}
    let preview : Array[String] = []
    for column in 0..<headers.length() {
      let value = values.get(column).unwrap_or("").trim().to_owned()
      fields.set(headers[column], Json::string(value))
      preview.push(value)
    }
    json_rows.push(Json::object(fields))
    if preview_rows.length() < 5 {
      preview_rows.push(preview)
    }
  }
  {
    headers,
    preview_rows,
    rows_json: Json::array(json_rows).stringify(),
    row_count: json_rows.length().to_string(),
    within_limit: json_rows.length() <= 500,
  }
}

///|
fn start_import_file_read(emit : @rabbita.Emit[Msg], biz_type : String) -> Cmd {
  @cmd.custom_cmd(fn(scheduler : &@cmd.Scheduler) {
    read_file_input_text(import_input_id(biz_type), fn(text) {
      scheduler.add(emit(ImportCsvLoaded(biz_type, text)))
    })
  })
}

///|
fn issue_import_template(emit : @rabbita.Emit[Msg], biz_type : String) -> Cmd {
  @http.get("/api/company/import/" + biz_type + "/template").expect_blob(result => {
    match result {
      Ok(blob) => emit(ImportTemplateDownloaded(biz_type, blob))
      Err(_) => emit(ImportTemplateDownloadFailed(biz_type))
    }
  })
}

///|
fn import_command_body(model : Model, dry_run : Bool) -> String {
  let mode = if dry_run { "dry" } else { "commit" }
  let key = model.import_key + "-" + mode
  "{\"idempotency_key\":\"" +
  key +
  "\",\"rows\":" +
  model.import_rows_json +
  ",\"dryRun\":" +
  (if dry_run { "true" } else { "false" }) +
  "}"
}

///|
fn issue_import_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  dry_run : Bool,
) -> Cmd {
  @http.post("/api/company/import/" + model.import_biz_type)
  .with_text(import_command_body(model, dry_run))
  .expect_text(result => {
    match result {
      Ok(body) => emit(ImportCommandFinished(model.import_biz_type, body))
      Err(_) => emit(ImportCommandFailed(model.import_biz_type))
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
fn project_id_from_path(path : String) -> String {
  let parts = path.split("/").to_array()
  if parts.length() > 2 {
    if parts[2] == "CD-HJL" {
      "proj-0001"
    } else {
      parts[2].to_owned()
    }
  } else {
    "proj-0001"
  }
}

///|
fn load_project_stages(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/projects/" + project_id + "/lifecycle").expect_text(result => {
    match result {
      Ok(body) => emit(ProjectStagesLoaded(body))
      Err(_) => emit(ProjectStagesLoadFailed)
    }
  })
}

///|
fn load_project_kpi(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/dashboard/project/" + project_id + "/kpi").expect_text(result => {
      match result {
        Ok(body) => emit(ProjectKpiLoaded(body))
        Err(_) => emit(ProjectKpiLoadFailed)
      }
    },
  )
}

///|
fn load_project_anomalies(
  emit : @rabbita.Emit[Msg],
  project_id : String,
) -> Cmd {
  @http.get("/api/company/dashboard/project/" + project_id + "/anomalies").expect_text(result => {
      match result {
        Ok(body) => emit(ProjectAnomaliesLoaded(body))
        Err(_) => emit(ProjectAnomaliesLoadFailed)
      }
    },
  )
}

///|
fn issue_sales_customer_create(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let nonce = import_nonce()
  @http.post("/api/company/sales/customers")
  .with_text(
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-customer-create-" + nonce),
      "customer_guid": Json::string("CUS-RABBITA-" + nonce),
      "customer_code": Json::string("CUS-RABBITA-" + nonce),
      "customer_name": Json::string(
        if model.sales_customer_name.is_empty() {
          "Rabbita 本地客户演示"
        } else {
          model.sales_customer_name
        },
      ),
      "id_card_no": Json::string(model.sales_customer_id_card_no),
      "phone": Json::string(model.sales_customer_phone),
      "proj_guid": Json::string(model.sales_customer_project_id),
      "bu_guid": Json::string("bu-group-0001"),
      "source": Json::string(model.sales_customer_source),
      "remark": Json::string(model.sales_customer_remark),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(SalesCustomerCommandFinished(body))
      Err(_) => emit(SalesCustomerCommandFailed)
    }
  })
}

///|
fn issue_sales_customer_update(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  let nonce = import_nonce()
  @http.put("/api/company/sales/customers/" + model.sales_customer_edit_id)
  .with_text(
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-customer-update-" + nonce),
      "customerName": Json::string(model.sales_customer_name),
      "idCardNo": Json::string(model.sales_customer_id_card_no),
      "phone": Json::string(model.sales_customer_phone),
      "source": Json::string(model.sales_customer_source),
      "remark": Json::string(model.sales_customer_remark),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(SalesCustomerCommandFinished(body))
      Err(_) => emit(SalesCustomerCommandFailed)
    }
  })
}

///|
fn issue_sales_customer_delete(
  emit : @rabbita.Emit[Msg],
  customer_id : String,
) -> Cmd {
  @http.delete("/api/company/sales/customers/" + customer_id).expect_text(result => {
    match result {
      Ok(body) => emit(SalesCustomerCommandFinished(body))
      Err(_) => emit(SalesCustomerCommandFailed)
    }
  })
}

///|
fn issue_sales_subscription_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  let nonce = import_nonce()
  let subscription_id = "SUB-RABBITA-" + nonce
  @http.post("/api/company/sales/subscriptions")
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-sales-subscription-create-" + nonce,
      ),
      "sub_guid": Json::string(subscription_id),
      "sub_code": Json::string(subscription_id),
      "customer_guid": Json::string(model.sales_subscription_customer_guid),
      "proj_guid": Json::string(model.sales_subscription_proj_guid),
      "bu_guid": Json::string("bu-group-0001"),
      "building_no": Json::string(model.sales_subscription_building_no),
      "unit_no": Json::string(model.sales_subscription_unit_no),
      "area": Json::number(sales_parse_number(model.sales_subscription_area)),
      "unit_price": Json::number(
        sales_parse_number(model.sales_subscription_unit_price),
      ),
      "total_price": Json::number(
        sales_parse_number(model.sales_subscription_total_price),
      ),
      "sub_amount": Json::number(
        sales_parse_number(model.sales_subscription_sub_amount),
      ),
      "sub_date": Json::string(model.sales_subscription_sub_date),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(SalesSubscriptionCommandFinished(body))
      Err(_) => emit(SalesSubscriptionCommandFailed)
    }
  })
}

///|
fn issue_sales_subscription_convert(
  emit : @rabbita.Emit[Msg],
  subscription_id : String,
  payment_type : String,
) -> Cmd {
  let nonce = import_nonce()
  @http.post(
    "/api/company/sales/subscriptions/" +
    subscription_id +
    "/convert-to-contract",
  )
  .with_text(
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-sales-subscription-convert-" + nonce,
      ),
      "paymentType": Json::string(payment_type),
      "signedDate": Json::string("2026-07-16"),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(SalesSubscriptionCommandFinished(body))
      Err(_) => emit(SalesSubscriptionCommandFailed)
    }
  })
}

///|
fn issue_sales_mortgage_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let nonce = import_nonce()
  let path = if command_type == "create" {
    "/api/company/sales/mortgages"
  } else {
    "/api/company/sales/mortgages/" +
    model.sales_mortgage_id +
    "/" +
    command_type
  }
  let body = if command_type == "create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-mortgage-create-" + nonce),
      "mortgage_guid": Json::string(model.sales_mortgage_id),
      "mortgage_code": Json::string(model.sales_mortgage_id),
      "scontract_guid": Json::string(model.sales_mortgage_form_contract),
      "customer_guid": Json::string(model.sales_mortgage_form_customer),
      "bank_name": Json::string(model.sales_mortgage_form_bank),
      "loan_amount": Json::number(
        sales_parse_number(model.sales_mortgage_form_amount),
      ),
      "loan_years": Json::number(
        sales_parse_number(model.sales_mortgage_form_years),
      ),
      "rate": Json::number(sales_parse_number(model.sales_mortgage_form_rate)),
      "apply_date": Json::string(model.sales_mortgage_form_date),
      "remark": Json::string(model.sales_mortgage_form_remark),
    }).stringify()
  } else if command_type == "approve" {
    "{\"idempotency_key\":\"rabbita-sales-mortgage-approve-v1\"}"
  } else {
    "{\"idempotency_key\":\"rabbita-sales-mortgage-release-v1\"}"
  }
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => emit(SalesMortgageCommandFinished(response))
      Err(_) => emit(SalesMortgageCommandFailed)
    }
  })
}

///|
fn issue_sales_refund_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let nonce = import_nonce()
  let path = if command_type == "create" {
    "/api/company/sales/refunds"
  } else {
    "/api/company/sales/refunds/" + model.sales_refund_id + "/approve"
  }
  let body = if command_type == "create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-refund-create-" + nonce),
      "refund_guid": Json::string(model.sales_refund_id),
      "refund_code": Json::string(model.sales_refund_id),
      "scontract_guid": Json::string(model.sales_refund_form_contract),
      "customer_guid": Json::string(model.sales_refund_form_customer),
      "reason": Json::string(model.sales_refund_form_reason),
      "refund_amount": Json::number(
        sales_parse_number(model.sales_refund_form_amount),
      ),
      "refund_date": Json::string(model.sales_refund_form_date),
    }).stringify()
  } else {
    "{\"idempotency_key\":\"rabbita-sales-refund-approve-v1\"}"
  }
  @http.post(path)
  .with_text(body)
  .expect_text(result => {
    match result {
      Ok(response) => emit(SalesRefundCommandFinished(response))
      Err(_) => emit(SalesRefundCommandFailed)
    }
  })
}

///|
fn sales_revenue_command_body(
  command_type : String,
  model : Model,
  nonce : String,
) -> String {
  let project_id = if model.sales_revenue_form_project.is_empty() {
    "proj-0001"
  } else {
    model.sales_revenue_form_project
  }
  let scope = "project:" + project_id
  let amount_minor = (sales_parse_number(model.sales_revenue_form_amount) *
  100.0).to_int()
  let revenue_id = if model.sales_revenue_editing_id.is_empty() {
    "REV-RABBITA-" + nonce
  } else {
    model.sales_revenue_editing_id
  }
  let capability = if command_type == "create" {
    "sales:revenue:create"
  } else if command_type == "update" {
    "sales:revenue:update"
  } else if command_type == "confirm_received" {
    "sales:revenue:confirm_received"
  } else {
    "sales:revenue:delete"
  }
  let authority = Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("co-rabbita"),
    "actor_id": Json::string("rabbita-user"),
    "capability": Json::string(capability),
    "scope": Json::string(scope),
    "max_amount_minor": Json::number(50000000.0),
  })
  if command_type == "create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-revenue-create-" + nonce),
      "revenue_id": Json::string(revenue_id),
      "revenue_code": Json::string("SR-" + nonce),
      "proj_guid": Json::string(project_id),
      "customer_name": Json::string(model.sales_revenue_form_customer),
      "amount_minor": Json::number(amount_minor.to_double()),
      "receive_date": Json::string(model.sales_revenue_form_date),
      "status": Json::string(model.sales_revenue_form_status),
      "payment_type": Json::string(model.sales_revenue_form_payment_type),
      "contract_no": Json::string(model.sales_revenue_form_contract_no),
      "remark": Json::string(model.sales_revenue_form_remark),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string(scope),
      "authority": authority,
    }).stringify()
  } else if command_type == "update" {
    Json::object({
      "idempotency_key": Json::string("rabbita-sales-revenue-update-" + nonce),
      "customer_name": Json::string(model.sales_revenue_form_customer),
      "amount_minor": Json::number(amount_minor.to_double()),
      "receive_date": Json::string(model.sales_revenue_form_date),
      "payment_type": Json::string(model.sales_revenue_form_payment_type),
      "contract_no": Json::string(model.sales_revenue_form_contract_no),
      "remark": Json::string(model.sales_revenue_form_remark),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string(scope),
      "authority": authority,
    }).stringify()
  } else {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-sales-revenue-" + command_type + "-" + nonce,
      ),
      "principal_id": Json::string("co-rabbita"),
      "scope": Json::string(scope),
      "authority": authority,
    }).stringify()
  }
}

///|
fn issue_sales_revenue_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let suffix = if command_type == "confirm_received" {
    "confirm-received"
  } else {
    command_type
  }
  let path = if command_type == "create" {
    "/api/company/sales/revenues"
  } else {
    "/api/company/sales/revenues/" + model.sales_revenue_id + "/" + suffix
  }
  let nonce = import_nonce()
  let body = sales_revenue_command_body(command_type, model, nonce)
  let request = if command_type == "update" {
    @http.put(path).with_text(body)
  } else if command_type == "delete" {
    @http.delete(path)
  } else {
    @http.post(path).with_text(body)
  }
  request.expect_text(result => {
    match result {
      Ok(body) => emit(SalesRevenueCommandFinished(body))
      Err(_) => emit(SalesRevenueCommandFailed)
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
  } else if command_type == "sync_from_workflow" {
    "{\"idempotency_key\":\"rabbita-loan-workflow-sync-v1\"}"
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
  } else if command_type == "sync_from_workflow" {
    "sync-from-workflow"
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
fn issue_loan_workflow_sync(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/loans/" + model.loan_id + "/sync-from-workflow")
  .with_text(loan_command_body("sync_from_workflow"))
  .expect_text(result => {
    match result {
      Ok(body) => emit(LoanWorkflowSyncFinished(body))
      Err(_) => emit(LoanWorkflowSyncFailed)
    }
  })
}

///|
fn delivery_command_body(model : Model, command_type : String) -> String {
  if command_type == "create_progress" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-delivery-progress-create-" + import_nonce(),
      ),
      "progress_id": Json::string("PROG-RABBITA-" + import_nonce()),
      "project_id": Json::string(model.delivery_project_id),
      "principal_id": Json::string("co-rabbita"),
      "project_scope": Json::string("project:" + model.delivery_project_id),
      "building_no": Json::string(model.delivery_building_no),
      "stage": Json::string(
        if model.delivery_stage.is_empty() {
          "主体结构"
        } else {
          model.delivery_stage
        },
      ),
      "plan_pct": Json::number(sales_parse_number(model.delivery_plan_pct)),
      "completed_value_minor": Json::number(0.0),
      "currency": Json::string("CNY"),
      "contract_id": Json::string(model.delivery_contract_id),
      "plan_date": Json::string(model.delivery_plan_date),
      "evidence_ids": Json::array([Json::string("rabbita:progress:photo-001")]),
      "remark": Json::string(model.delivery_remark),
    }).stringify()
  } else if command_type == "report_progress" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-delivery-progress-report-" + import_nonce(),
      ),
      "progress_pct": Json::number(
        sales_parse_number(model.delivery_report_actual_pct),
      ),
      "actual_date": Json::string(model.delivery_report_date),
      "evidence_ids": Json::array([Json::string("rabbita:progress:report-001")]),
      "remark": Json::string(model.delivery_report_remark),
    }).stringify()
  } else if command_type == "accept_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-accept-v1\",\"acceptance_id\":\"accept-rabbita-001\",\"acceptance_evidence_ids\":[\"rabbita:progress:acceptance-001\"]}"
  } else if command_type == "reject_progress" {
    "{\"idempotency_key\":\"rabbita-delivery-progress-reject-v1\",\"reason\":\"需要补充验收记录\"}"
  } else if command_type == "create_output" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-delivery-output-create-" + import_nonce(),
      ),
      "output_id": Json::string("OUT-RABBITA-" + import_nonce()),
      "project_id": Json::string(model.delivery_project_id),
      "contract_id": Json::string(model.delivery_output_contract_id),
      "period": Json::string(model.delivery_output_period),
      "output_amount": Json::string(model.delivery_output_amount),
      "evidence_ids": Json::array([Json::string("rabbita:output:measure-001")]),
      "remark": Json::string(model.delivery_output_remark),
    }).stringify()
  } else if command_type == "confirm_output" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-delivery-output-confirm-" + import_nonce(),
      ),
      "confirm_amount": Json::string(model.delivery_output_amount),
      "confirmed_at": Json::string(model.delivery_report_date),
      "evidence_ids": Json::array([
        Json::string("rabbita:output:acceptance-001"),
      ]),
    }).stringify()
  } else {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-delivery-task-report-" + import_nonce(),
      ),
      "report_id": Json::string("TASK-REPORT-RABBITA-LOCAL"),
      "task_id": Json::string(
        if model.plan_report_task_id.is_empty() {
          model.delivery_task_id
        } else {
          model.plan_report_task_id
        },
      ),
      "project_id": Json::string(model.project_plan_project_id),
      "progress_pct": Json::string(model.plan_report_progress),
      "report_date": Json::string(model.plan_report_date),
      "summary": Json::string(model.plan_report_summary),
      "evidence_ids": Json::array([Json::string("rabbita:task-report:001")]),
    }).stringify()
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
    "/api/company/plan/tasks/\{model.delivery_task_id}/report"
  }
  @http.post(path)
  .with_text(delivery_command_body(model, command_type))
  .expect_text(result => {
    match result {
      Ok(body) => emit(DeliveryCommandFinished(body))
      Err(_) => emit(DeliveryCommandFailed)
    }
  })
}

///|
fn plan_task_authority(model : Model, capability : String) -> Json {
  Json::object({
    "active": Json::boolean(true),
    "principal_id": Json::string("principal-rabbita-plan"),
    "actor_id": Json::string(model.user_code),
    "capability": Json::string(capability),
    "scope": Json::string("project:" + model.project_plan_project_id),
  })
}

///|
fn plan_task_command_body(model : Model, command_type : String) -> String {
  if command_type == "create" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-plan-task-create-" + import_nonce(),
      ),
      "task_id": Json::string("PT-RABBITA-LOCAL"),
      "task_code": Json::string(
        if model.plan_create_task_code.is_empty() {
          "PT-RABBITA-LOCAL"
        } else {
          model.plan_create_task_code
        },
      ),
      "task_name": Json::string(model.plan_create_task_name),
      "project_id": Json::string(model.project_plan_project_id),
      "task_type": Json::string(model.plan_create_task_type),
      "plan_begin_date": Json::string(model.plan_create_begin_date),
      "plan_end_date": Json::string(model.plan_create_end_date),
      "owner_id": Json::string(model.plan_create_owner),
      "remarks": Json::string(model.plan_create_remarks),
      "authority": plan_task_authority(model, "project:task:create"),
    }).stringify()
  } else if command_type == "update" {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-plan-task-update-" + import_nonce(),
      ),
      "taskName": Json::string(
        if model.plan_create_task_name.is_empty() {
          "项目计划任务已复核"
        } else {
          model.plan_create_task_name
        },
      ),
      "progressPct": Json::string(model.plan_report_progress),
      "authority": plan_task_authority(model, "project:task:update"),
    }).stringify()
  } else {
    Json::object({
      "idempotency_key": Json::string(
        "rabbita-plan-task-delete-" + import_nonce(),
      ),
      "reason": Json::string("项目计划命令演示撤回"),
      "authority": plan_task_authority(model, "project:task:delete"),
    }).stringify()
  }
}

///|
fn issue_plan_task_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  let path = if command_type == "create" {
    "/api/company/plan/tasks"
  } else if command_type == "update" {
    "/api/company/plan/tasks/" + model.plan_task_id
  } else {
    "/api/company/plan/tasks/" + model.plan_task_id + "/delete"
  }
  if command_type == "update" {
    @http.put(path)
    .with_text(plan_task_command_body(model, command_type))
    .expect_text(result => {
      match result {
        Ok(body) => emit(PlanTaskCommandFinished(body))
        Err(_) => emit(PlanTaskCommandFailed)
      }
    })
  } else {
    @http.post(path)
    .with_text(plan_task_command_body(model, command_type))
    .expect_text(result => {
      match result {
        Ok(body) => emit(PlanTaskCommandFinished(body))
        Err(_) => emit(PlanTaskCommandFailed)
      }
    })
  }
}

///|
fn issue_project_plan_suggestion(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  @http.post("/api/company/plan/ai-suggest-plan")
  .with_text(
    Json::object({
      "projType": Json::string(model.plan_ai_proj_type),
      "scale": Json::string(model.plan_ai_scale),
      "region": Json::string(model.plan_ai_region),
      "beginDate": Json::string(model.plan_ai_begin_date),
    }).stringify(),
  )
  .expect_text(result => {
    match result {
      Ok(body) => emit(ProjectPlanSuggestionFinished(body))
      Err(_) => emit(ProjectPlanSuggestionFailed)
    }
  })
}

///|
fn issue_plan_delay_impact(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.get(
    "/api/company/tasks/" +
    model.plan_delay_task_id +
    "/delay-impact?delayDays=" +
    model.plan_delay_days,
  ).expect_text(result => {
    match result {
      Ok(body) => emit(PlanDelayImpactFinished(body))
      Err(_) => emit(PlanDelayImpactFailed)
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
fn load_supplier_source(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/srm/categories").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierDictCategoriesLoaded(body))
      Err(_) => emit(SupplierDictLoadFailed)
    }
  })
}

///|
fn load_supplier_dict_eval(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/srm/dict/eval-results").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierDictEvalLoaded(body))
      Err(_) => emit(SupplierDictLoadFailed)
    }
  })
}

///|
fn load_supplier_dict_sources(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/srm/dict/sources").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierDictSourcesLoaded(body))
      Err(_) => emit(SupplierDictLoadFailed)
    }
  })
}

///|
fn load_supplier_source_list(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/srm/providers").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierSourceLoaded(body))
      Err(_) => emit(SupplierSourceLoadFailed)
    }
  })
}

///|
fn load_supplier_detail(emit : @rabbita.Emit[Msg], path : String) -> Cmd {
  let provider_guid = match path.rev_split_once("/") {
    Some((_, value)) => value.to_owned()
    _ => ""
  }
  @http.get("/api/company/srm/providers/" + provider_guid).expect_text(result => {
    match result {
      Ok(body) => emit(SupplierDetailLoaded(body))
      Err(_) => emit(SupplierDetailLoadFailed)
    }
  })
}

///|
fn load_supplier_detail_risk(
  emit : @rabbita.Emit[Msg],
  provider_guid : String,
) -> Cmd {
  @http.get("/api/company/srm/providers/" + provider_guid + "/risk").expect_text(result => {
      match result {
        Ok(body) => emit(SupplierDetailRiskLoaded(body))
        Err(_) => emit(SupplierDetailRiskLoadFailed)
      }
    },
  )
}

///|
fn issue_supplier_check_sign(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.get("/api/company/srm/providers/" + model.supplier_id + "/check-sign").expect_text(result => {
      match result {
        Ok(body) => emit(SupplierCheckSignFinished(body))
        Err(_) => emit(SupplierCheckSignFailed)
      }
    },
  )
}

///|
fn load_supplier_stats(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/srm/stats/overview").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierStatsLoaded(body))
      Err(_) => emit(SupplierStatsLoadFailed)
    }
  })
}

///|
fn load_supplier_risk(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/srm/risk-board").expect_text(result => {
    match result {
      Ok(body) => emit(SupplierRiskLoaded(body))
      Err(_) => emit(SupplierRiskLoadFailed)
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
fn issue_supplier_rescore(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.post("/api/company/source/srm/providers/rescore-all")
  .with_text("{\"idempotency_key\":\"rabbita-supplier-rescore-v1\"}")
  .expect_text(result => {
    match result {
      Ok(body) => emit(SupplierRescoreFinished(body))
      Err(_) => emit(SupplierRescoreFailed)
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
fn load_tenders(emit : @rabbita.Emit[Msg], project_id : String) -> Cmd {
  @http.get("/api/company/source/tender/tenders?projGuid=" + project_id).expect_text(result => {
      match result {
        Ok(body) => emit(TenderSourceTendersLoaded(body))
        Err(_) => emit(TenderSourceLoadFailed)
      }
    },
  )
}

///|
fn load_tender_source_awards(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/tender/awards").expect_text(result => {
    match result {
      Ok(body) => emit(TenderSourceAwardsLoaded(body))
      Err(_) => emit(TenderSourceLoadFailed)
    }
  })
}

///|
fn load_tender_source_splits(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/source/tender/splits").expect_text(result => {
    match result {
      Ok(body) => emit(TenderSourceSplitsLoaded(body))
      Err(_) => emit(TenderSourceLoadFailed)
    }
  })
}

///|
fn tender_command_body(model : Model, command_type : String) -> String {
  if command_type == "create" {
    Json::object({
      "idempotency_key": Json::string("rabbita-tender-create-v1"),
      "tender_id": Json::string("TD-RABBITA-LOCAL"),
      "project_scope": Json::string("project:" + model.tender_project_id),
      "name": Json::string(
        if model.tender_name.is_empty() {
          "海教园主体结构工程招标"
        } else {
          model.tender_name
        },
      ),
      "category": Json::string(
        if model.tender_category.is_empty() {
          "construction"
        } else {
          model.tender_category
        },
      ),
      "estimated_amount": Json::string(model.tender_estimated_amount),
      "currency": Json::string("CNY"),
      "bids": Json::array([]),
      "plan_publish_date": Json::string(model.tender_plan_publish_date),
      "plan_award_date": Json::string(model.tender_plan_award_date),
      "remark": Json::string(model.tender_remark),
    }).stringify()
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
fn issue_source_tender_command(
  emit : @rabbita.Emit[Msg],
  model : Model,
  command_type : String,
) -> Cmd {
  if command_type == "state" {
    @http.put(
      "/api/company/source/tender/tenders/" + model.tender_id + "/state",
    )
    .with_text(
      "{\"idempotency_key\":\"rabbita-tender-source-state-v1\",\"state\":\"publishing\"}",
    )
    .expect_text(result => {
      match result {
        Ok(body) => emit(TenderSourceCommandFinished(command_type, body))
        Err(_) => emit(TenderSourceCommandFailed(command_type))
      }
    })
  } else {
    @http.post("/api/company/source/tender/awards")
    .with_text(
      Json::object({
        "idempotency_key": Json::string("rabbita-tender-source-award-v1"),
        "tenderGuid": Json::string(model.tender_id),
        "providerGuid": Json::string(model.tender_award_provider_guid),
        "providerName": Json::string(model.tender_award_provider_name),
        "awardAmount": Json::string(model.tender_award_amount),
        "awardDate": Json::string(model.tender_award_date),
        "remark": Json::string(model.tender_award_remark),
      }).stringify(),
    )
    .expect_text(result => {
      match result {
        Ok(body) => emit(TenderSourceCommandFinished(command_type, body))
        Err(_) => emit(TenderSourceCommandFailed(command_type))
      }
    })
  }
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
  @http.get("/api/company/source/cost/payment-applies?view=all").expect_text(result => {
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
  @http.get("/api/company/source/cost/contracts").expect_text(result => {
    match result {
      Ok(body) => emit(ContractsLoaded(body))
      Err(_) => emit(ContractsLoadFailed)
    }
  })
}

///|
fn load_contract(emit : @rabbita.Emit[Msg], path : String) -> Cmd {
  let request_path = if path.contains("CT-RABBITA-LOCAL") {
    "/api/company" + path
  } else {
    "/api/company/source/cost" + path
  }
  @http.get(request_path).expect_text(result => {
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
fn contract_milestone_create_body(model : Model) -> String {
  Json::object({
    "idempotency_key": Json::string("rabbita-contract-milestone-create-v1"),
    "contractGuid": Json::string(model.contract_id),
    "nodeName": Json::string(model.contract_milestone_node_name),
    "triggerType": Json::string(model.contract_milestone_trigger_type),
    "triggerValue": Json::string(model.contract_milestone_trigger_value),
    "planDate": Json::string(model.contract_milestone_plan_date),
    "planAmount": investment_edit_value_json(
      model.contract_milestone_plan_amount,
    ),
    "planPct": investment_edit_value_json(model.contract_milestone_plan_pct),
    "notes": Json::string(model.contract_milestone_notes),
  }).stringify()
}

///|
fn issue_contract_milestone_create(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  @http.post(
    "/api/company/source/cost/contracts/" + model.contract_id + "/milestones",
  )
  .with_text(contract_milestone_create_body(model))
  .expect_text(result => {
    match result {
      Ok(body) => emit(ContractMilestoneCommandFinished(body))
      Err(_) => emit(ContractMilestoneCommandFailed)
    }
  })
}

///|
fn issue_contract_milestone_action(
  emit : @rabbita.Emit[Msg],
  milestone_id : String,
  action : String,
) -> Cmd {
  let key = "rabbita-contract-milestone-" + action + "-v1"
  let path = if action == "trigger-event" {
    "/api/company/source/cost/milestones/" + milestone_id + "/trigger-event"
  } else {
    "/api/company/source/cost/milestones/" + milestone_id
  }
  if action == "delete" {
    @http.delete(path + "?idempotency_key=" + key).expect_text(result => {
      match result {
        Ok(body) => emit(ContractMilestoneCommandFinished(body))
        Err(_) => emit(ContractMilestoneCommandFailed)
      }
    })
  } else {
    @http.post(path)
    .with_text(
      Json::object({
        "idempotency_key": Json::string(key),
        "notes": Json::string("Rabbita 合同节点事件候选"),
      }).stringify(),
    )
    .expect_text(result => {
      match result {
        Ok(body) => emit(ContractMilestoneCommandFinished(body))
        Err(_) => emit(ContractMilestoneCommandFailed)
      }
    })
  }
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
  return match msg {
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
    InputProjectPlanProject(value) =>
      (
        load_delivery_for_project(emit, value),
        {
          ..model,
          project_plan_project_id: value,
          delivery_loaded: false,
          delivery_note: "正在读取所选项目的 PostgreSQL 计划…",
        },
      )
    InputPlanAiProjectType(value) =>
      (none, { ..model, plan_ai_proj_type: value })
    InputPlanAiScale(value) => (none, { ..model, plan_ai_scale: value })
    InputPlanAiRegion(value) => (none, { ..model, plan_ai_region: value })
    InputPlanAiBeginDate(value) =>
      (none, { ..model, plan_ai_begin_date: value })
    InputPlanReportProgress(value) =>
      (none, { ..model, plan_report_progress: value })
    InputPlanReportDate(value) => (none, { ..model, plan_report_date: value })
    InputPlanReportSummary(value) =>
      (none, { ..model, plan_report_summary: value })
    SelectPlanTask(task_id, task_name) =>
      (
        none,
        {
          ..model,
          plan_report_task_id: task_id,
          plan_report_task_name: task_name,
          plan_delay_task_id: task_id,
          delivery_task_id: task_id,
        },
      )
    InputPlanCreateTaskCode(value) =>
      (none, { ..model, plan_create_task_code: value })
    InputPlanCreateTaskName(value) =>
      (none, { ..model, plan_create_task_name: value })
    InputPlanCreateTaskType(value) =>
      (none, { ..model, plan_create_task_type: value })
    InputPlanCreateBeginDate(value) =>
      (none, { ..model, plan_create_begin_date: value })
    InputPlanCreateEndDate(value) =>
      (none, { ..model, plan_create_end_date: value })
    InputPlanCreateOwner(value) => (none, { ..model, plan_create_owner: value })
    InputPlanCreateRemarks(value) =>
      (none, { ..model, plan_create_remarks: value })
    InputPlanDelayDays(value) => (none, { ..model, plan_delay_days: value })
    RunPlanDelayImpact =>
      if model.plan_delay_task_id == "" {
        (none, { ..model, plan_delay_note: "请先选择任务" })
      } else {
        (
          issue_plan_delay_impact(emit, model),
          { ..model, plan_delay_note: "正在计算延期影响…" },
        )
      }
    ExportPlanCsv =>
      (
        {
          download_text(
            project_plan_csv(model),
            "项目计划-" + model.project_plan_project_id + ".csv",
          )
          none
        },
        model,
      )
    InputProfileName(value) => (none, { ..model, profile_edit_name: value })
    InputProfilePasswordOld(value) =>
      (none, { ..model, profile_password_old: value })
    InputProfilePasswordNew(value) =>
      (none, { ..model, profile_password_new: value })
    InputProfilePasswordConfirm(value) =>
      (none, { ..model, profile_password_confirm: value })
    InputAttachmentBizType(value) =>
      (none, { ..model, attachment_biz_type: value })
    InputAttachmentAiStatus(value) =>
      (none, { ..model, attachment_ai_status: value })
    InputAttachmentKeyword(value) =>
      (none, { ..model, attachment_keyword: value })
    AttachmentFileSelected(value) =>
      (
        none,
        {
          ..model,
          attachment_file_name: value,
          attachment_note: if value.is_empty() {
            "尚未选择上传文件"
          } else {
            "已选择文件 " + value + " · 仍需二进制对象存储授权"
          },
        },
      )
    SearchAttachments =>
      (
        load_attachments(emit, model),
        {
          ..model,
          attachment_note: "正在按条件读取 PostgreSQL 附件元数据…",
        },
      )
    AttachmentAction(guid, action) => {
      let next_model = { ..model, attachment_action_guid: guid }
      if action == "download" {
        (
          issue_attachment_download(emit, next_model),
          {
            ..next_model,
            attachment_download_note: "正在检查附件下载边界 · 不读取二进制…",
          },
        )
      } else if action == "reextract" {
        (
          issue_attachment_reextract(emit, next_model),
          {
            ..next_model,
            attachment_action_note: "正在检查 OCR 重提取边界 · 不读取二进制、不调用 OCR…",
          },
        )
      } else {
        (
          issue_attachment_delete(emit, next_model),
          {
            ..next_model,
            attachment_delete_note: "正在检查附件删除边界 · 不删除二进制、不写入元数据…",
          },
        )
      }
    }
    Navigate(path) => {
      let command = if path.has_prefix("/share/") {
        load_share_meta(emit, share_token_from_path(path))
      } else if path == "/dashboard" ||
        path == "/dashboard-v3" ||
        path == "/cockpit" {
        load_dashboard_overview(emit)
      } else if path == "/projects" {
        load_projects(emit)
      } else if path.has_prefix("/projects/") {
        let project_id = project_id_from_path(path)
        @cmd.batch([
          load_project(emit, "/projects/" + project_id),
          load_project_stages(emit, project_id),
          load_project_kpi(emit, project_id),
          load_project_anomalies(emit, project_id),
        ])
      } else if path == "/contracts" {
        load_contracts(emit)
      } else if path.has_prefix("/contracts/") {
        load_contract(emit, path)
      } else if path == "/payment-applies" {
        load_payment_applies(emit)
      } else if path == "/tender" {
        @cmd.batch([
          load_projects(emit),
          load_tenders(emit, model.tender_project_id),
          load_supplier_source_list(emit),
        ])
      } else if path == "/srm/providers" {
        load_supplier_source(emit)
      } else if path.has_prefix("/srm/providers/") {
        load_supplier_detail(emit, path)
      } else if path == "/srm/risk-board" {
        load_supplier_risk(emit)
      } else if path == "/sales/customers" {
        @cmd.batch([
          load_projects(emit),
          load_sales_for(
            emit,
            "customers",
            model.sales_customer_project_id,
            model.sales_customer_keyword,
          ),
        ])
      } else if path == "/sales/subscriptions" {
        @cmd.batch([
          load_projects(emit),
          load_sales_for(
            emit,
            "subscriptions",
            model.sales_subscription_project_id,
            "",
          ),
          load_sales_for(emit, "customers", "", ""),
        ])
      } else if path == "/sales/contracts" {
        @cmd.batch([
          load_projects(emit),
          load_sales_for(emit, "contracts", model.sales_contract_project_id, ""),
        ])
      } else if path == "/sales/mortgages" {
        load_sales(emit, "mortgages")
      } else if path == "/sales/revenues" {
        @cmd.batch([
          load_projects(emit),
          load_sales_for(
            emit,
            "revenues",
            model.sales_revenue_project_id,
            model.sales_revenue_keyword,
          ),
        ])
      } else if path == "/invoice" {
        @cmd.batch([
          load_projects(emit),
          load_invoice_source_in_for(emit, model.invoice_project_id),
        ])
      } else if path == "/ai-stats" {
        load_ai_stats_overview(emit)
      } else if path == "/ai-hub" {
        load_ai_hub_usage(emit)
      } else if path == "/webhook-config" {
        load_webhook_config(emit)
      } else if path == "/reports" {
        @cmd.batch([
          load_reports(emit),
          load_report_preferences(emit, model.user_code),
        ])
      } else if path == "/report-builder" {
        load_report_builder_meta(emit)
      } else if path == "/expenses" {
        load_expenses(emit, model.user_code)
      } else if path == "/expenses/new" {
        load_budget_scope(emit, model.profile_bu_guid)
      } else if path.has_prefix("/expenses/") && path != "/expenses/new" {
        load_expense_detail(emit, path, model.user_code)
      } else if path == "/admin" {
        load_admin_quality(emit)
      } else if path == "/users" {
        load_users(emit)
      } else if path == "/investment" {
        @cmd.batch([
          load_projects(emit),
          load_investment_versions(emit),
          load_investment_imports(emit),
        ])
      } else if path == "/audit-log" {
        load_audit_logs(emit)
      } else if path == "/dynamic-cost" {
        @cmd.batch([
          load_projects(emit),
          load_dynamic_cost(emit, model.dynamic_cost_project_id),
        ])
      } else if path == "/cost-dashboard-v3" {
        load_cost_dashboard(emit)
      } else if path == "/cashflow" {
        load_cashflow(emit)
      } else if path == "/cbs/dict" ||
        path == "/cbs/versions" ||
        path == "/cbs/r0-queue" ||
        path == "/cbs/approval-config" {
        load_cbs(emit)
      } else if path == "/fund/plan" {
        @cmd.batch([
          load_projects(emit),
          load_fund_for(emit, model.fund_project_id),
        ])
      } else if path == "/warning" || path == "/warning-rules" {
        load_warnings(emit)
      } else if path == "/attachments" {
        load_attachments(emit, model)
      } else if path == "/marketing" {
        @cmd.batch([
          load_projects(emit),
          load_marketing_for(emit, "campaigns", model.marketing_project_id),
        ])
      } else if path == "/inbox" {
        load_inbox(emit)
      } else if path == "/notify-config" {
        load_notify(emit, "subscriptions")
      } else if path == "/ocr-config" {
        load_ocr(emit)
      } else if path == "/error-log" {
        load_error_log(emit)
      } else if path == "/profile" {
        load_profile(emit, model.user_code)
      } else if path == "/system-health" {
        load_health_tables(emit)
      } else if path == "/loans" {
        load_loans(emit)
      } else if path == "/tasks" {
        @cmd.batch([
          load_workflow(emit),
          load_workflow_observation_pending(emit, model.user_code),
          load_workflow_observation_initiated(emit, model.user_code),
          load_workflow_observation_history(emit, model.user_code),
          load_workflow_tickets(emit),
        ])
      } else if path == "/project-plan" {
        @cmd.batch([
          load_projects(emit),
          load_delivery_for_project(emit, model.project_plan_project_id),
        ])
      } else if path == "/project/progress" {
        @cmd.batch([
          load_projects(emit),
          load_delivery(emit, model.delivery_project_id),
        ])
      } else {
        none
      }
      let contract_id = match path.rev_split_once("/") {
        Some((prefix, value)) if prefix == "/contracts" => value.to_owned()
        _ => model.contract_id
      }
      let expense_id = match path.rev_split_once("/") {
        Some((prefix, value)) if prefix == "/expenses" && value != "new" =>
          value.to_owned()
        _ if path == "/expenses/new" => "EXP-RABBITA-LOCAL"
        _ => model.expense_id
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
          share_loaded: false,
          share_meta_loaded: false,
          share_token: if path.has_prefix("/share/") {
            share_token_from_path(path)
          } else {
            model.share_token
          },
          share_report_key: if path.has_prefix("/share/") {
            ""
          } else {
            model.share_report_key
          },
          share_report_label: if path.has_prefix("/share/") {
            ""
          } else {
            model.share_report_label
          },
          share_title: if path.has_prefix("/share/") {
            ""
          } else {
            model.share_title
          },
          share_expires_at: if path.has_prefix("/share/") {
            ""
          } else {
            model.share_expires_at
          },
          share_never_expires: if path.has_prefix("/share/") {
            false
          } else {
            model.share_never_expires
          },
          share_data_body: if path.has_prefix("/share/") {
            ""
          } else {
            model.share_data_body
          },
          share_note: if path.has_prefix("/share/") {
            "正在加载公开分享元数据…"
          } else {
            model.share_note
          },
          contract_id,
          expense_id,
          expense_detail_loaded: if path.has_prefix("/expenses/") &&
            path != "/expenses/new" {
            false
          } else {
            model.expense_detail_loaded
          },
          expense_detail: if path.has_prefix("/expenses/") &&
            path != "/expenses/new" {
            None
          } else {
            model.expense_detail
          },
          expense_detail_note: if path.has_prefix("/expenses/") &&
            path != "/expenses/new" {
            "正在加载 PostgreSQL 报销详情源读模型…"
          } else {
            model.expense_detail_note
          },
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
    ProfilePasswordLoggedOut =>
      (
        none,
        {
          ..model,
          authenticated: false,
          page: "/login",
          api_status: "密码已更新",
          api_note: "请使用新密码重新登录",
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
    InputContractMilestoneNodeName(value) =>
      (none, { ..model, contract_milestone_node_name: value })
    InputContractMilestoneTriggerType(value) =>
      (none, { ..model, contract_milestone_trigger_type: value })
    InputContractMilestoneTriggerValue(value) =>
      (none, { ..model, contract_milestone_trigger_value: value })
    InputContractMilestonePlanDate(value) =>
      (none, { ..model, contract_milestone_plan_date: value })
    InputContractMilestonePlanAmount(value) =>
      (none, { ..model, contract_milestone_plan_amount: value })
    InputContractMilestonePlanPct(value) =>
      (none, { ..model, contract_milestone_plan_pct: value })
    InputContractMilestoneNotes(value) =>
      (none, { ..model, contract_milestone_notes: value })
    RequestContractMilestoneCreate =>
      if model.contract_id.is_empty() ||
        model.contract_milestone_node_name.trim().is_empty() {
        (
          none,
          {
            ..model,
            contract_milestone_command_note: "请先填写合同和节点名称",
          },
        )
      } else {
        (
          issue_contract_milestone_create(emit, model),
          {
            ..model,
            contract_milestone_command_note: "正在提交付款节点创建候选…",
          },
        )
      }
    ContractMilestoneTrigger(milestone_id) =>
      if milestone_id.trim().is_empty() {
        (
          none,
          {
            ..model,
            contract_milestone_command_note: "节点缺少 milestoneGuid",
          },
        )
      } else {
        (
          issue_contract_milestone_action(emit, milestone_id, "trigger-event"),
          {
            ..model,
            contract_milestone_command_note: "正在提交节点事件候选…",
          },
        )
      }
    ContractMilestoneDelete(milestone_id) =>
      if milestone_id.trim().is_empty() {
        (
          none,
          {
            ..model,
            contract_milestone_command_note: "节点缺少 milestoneGuid",
          },
        )
      } else {
        (
          issue_contract_milestone_action(emit, milestone_id, "delete"),
          {
            ..model,
            contract_milestone_command_note: "正在提交节点删除候选…",
          },
        )
      }
    ContractMilestoneCommandFinished(body) =>
      (
        load_contract(emit, "/contracts/" + model.contract_id),
        {
          ..model,
          contract_milestone_command_note: if body.contains(
              "\"persisted\":true",
            ) {
            "合同节点候选已写入 PostgreSQL 投影 · 付款/现金/会计/税务仍未执行"
          } else {
            "合同节点候选已返回 · 请复核 owner 边界"
          },
        },
      )
    ContractMilestoneCommandFailed =>
      (
        none,
        {
          ..model,
          contract_milestone_command_note: "合同节点命令服务不可用或被权限/源状态拒绝",
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
    SelectTenderProject(project_id) =>
      (
        load_tenders(emit, project_id),
        {
          ..model,
          tender_project_id: project_id,
          tenders_loaded: false,
          tender_rows: [],
          tender_award_rows: [],
          tender_source_loaded: false,
          tender_source_note: "正在读取所选项目的招采源观察…",
          tender_note: "正在读取项目招标计划…",
        },
      )
    TenderSourceTendersLoaded(body) =>
      (
        load_tender_source_awards(emit),
        {
          ..model,
          tenders_loaded: true,
          tender_rows: tender_rows_from_body(body),
          tender_source_loaded: false,
          tender_source_award_count: "0",
          tender_source_split_count: "0",
          tender_note: "已加载 PostgreSQL 招标源读模型 · 正在读取定标与分判",
          tender_source_note: "招标源已连接 · 继续读取定标/分判",
        },
      )
    TenderSourceAwardsLoaded(body) =>
      (
        load_tender_source_splits(emit),
        {
          ..model,
          tender_source_award_count: source_data_row_count(body).to_string(),
          tender_award_rows: tender_award_rows_from_body(body),
          tender_source_note: "招标源已连接 · 定标 " +
          source_data_row_count(body).to_string() +
          " 行 · 正在读取分判",
        },
      )
    TenderSourceSplitsLoaded(body) =>
      (
        none,
        {
          ..model,
          tender_source_loaded: true,
          tender_source_split_count: source_data_row_count(body).to_string(),
          tender_note: "已加载 PostgreSQL 招采源观察 · 空表保持可见",
          tender_source_note: "定标 " +
          model.tender_source_award_count +
          " 行 · 分判 " +
          source_data_row_count(body).to_string() +
          " 行 · 源记录只读",
        },
      )
    TenderSourceLoadFailed =>
      (
        none,
        {
          ..model,
          tenders_loaded: false,
          tender_rows: [],
          tender_award_rows: [],
          tender_source_loaded: false,
          tender_source_note: "招采源读模型不可用 · 使用已审核快照",
          tender_note: "合约规划源读模型不可用 · 使用已审核快照",
        },
      )
    AdvanceTenderRow(tender_id, current_state, target_state) => {
      let command = if current_state == "planning" &&
        target_state == "publishing" {
        "publish"
      } else if current_state == "publishing" && target_state == "bidding" {
        "open_bidding"
      } else if current_state == "awarded" && target_state == "completed" {
        "complete"
      } else {
        ""
      }
      if command.is_empty() {
        (none, model)
      } else {
        let selected = {
          ..model,
          tender_id,
          tender_state: current_state,
          tender_selected_source_kind: "command",
        }
        (
          issue_tender_command(emit, selected, command),
          {
            ..selected,
            tender_state: "pending",
            tender_note: "正在推进招标行状态：" +
            current_state +
            " → " +
            target_state,
          },
        )
      }
    }
    SelectTenderRow(tender_id, tender_name, tender_state, source_kind) =>
      (
        none,
        {
          ..model,
          tender_id,
          tender_name,
          tender_state,
          tender_selected_source_kind: source_kind,
          tender_note: "已选择招标 " +
          tender_id +
          " · 可继续推进状态或定标",
        },
      )
    SelectTenderProvider(provider_id, provider_name) =>
      (
        none,
        {
          ..model,
          tender_award_provider_guid: provider_id,
          tender_award_provider_name: provider_name,
        },
      )
    SelectTenderTab(tab) => (none, { ..model, tender_tab: tab })
    OpenTenderForm(kind) =>
      (
        none,
        {
          ..model,
          tender_form_open: kind,
          tender_name: if kind == "tender" {
            ""
          } else {
            model.tender_name
          },
          tender_estimated_amount: if kind == "tender" {
            "0"
          } else {
            model.tender_estimated_amount
          },
          tender_award_provider_guid: if kind == "award" {
            model.tender_award_provider_guid
          } else {
            ""
          },
          tender_award_provider_name: if kind == "award" {
            model.tender_award_provider_name
          } else {
            ""
          },
          tender_award_amount: if kind == "award" {
            model.tender_award_amount
          } else {
            "0"
          },
          tender_award_date: if kind == "award" {
            "2026-07-16"
          } else {
            model.tender_award_date
          },
        },
      )
    CloseTenderForm => (none, { ..model, tender_form_open: "" })
    InputTenderField(field, value) =>
      (
        none,
        {
          ..model,
          tender_name: if field == "name" {
            value
          } else {
            model.tender_name
          },
          tender_category: if field == "category" {
            value
          } else {
            model.tender_category
          },
          tender_estimated_amount: if field == "estimated_amount" {
            value
          } else {
            model.tender_estimated_amount
          },
          tender_plan_publish_date: if field == "plan_publish_date" {
            value
          } else {
            model.tender_plan_publish_date
          },
          tender_plan_award_date: if field == "plan_award_date" {
            value
          } else {
            model.tender_plan_award_date
          },
          tender_remark: if field == "remark" {
            value
          } else {
            model.tender_remark
          },
          tender_award_provider_guid: if field == "award_provider_guid" {
            value
          } else {
            model.tender_award_provider_guid
          },
          tender_award_provider_name: if field == "award_provider_name" {
            value
          } else {
            model.tender_award_provider_name
          },
          tender_award_amount: if field == "award_amount" {
            value
          } else {
            model.tender_award_amount
          },
          tender_award_date: if field == "award_date" {
            value
          } else {
            model.tender_award_date
          },
          tender_award_remark: if field == "award_remark" {
            value
          } else {
            model.tender_award_remark
          },
        },
      )
    SubmitTenderForm =>
      if model.tender_form_open == "award" {
        if model.tender_id.is_empty() ||
          model.tender_award_provider_guid.is_empty() ||
          model.tender_award_amount.trim().is_empty() {
          (
            none,
            {
              ..model,
              tender_source_command_note: "定标需要招标 ID、供应商和中标金额",
            },
          )
        } else {
          (
            issue_source_tender_command(emit, model, "award"),
            {
              ..model,
              tender_form_open: "",
              tender_source_command_note: "正在提交定标表单 · 校验供应商资格…",
            },
          )
        }
      } else if model.tender_name.trim().is_empty() {
        (none, { ..model, tender_note: "招标名称不能为空" })
      } else {
        (
          issue_tender_command(emit, model, "create"),
          {
            ..model,
            tender_form_open: "",
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
          load_tenders(emit, model.tender_project_id),
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
    AdvanceSourceTender =>
      if model.tender_id == "" || model.tender_selected_source_kind == "command" {
        (none, model)
      } else {
        (
          issue_source_tender_command(emit, model, "state"),
          {
            ..model,
            tender_source_command_note: "正在提交源招标状态推进候选…",
          },
        )
      }
    AwardSourceTender =>
      if model.tender_id == "" || model.tender_selected_source_kind == "command" {
        (none, model)
      } else {
        (
          issue_source_tender_command(emit, model, "award"),
          {
            ..model,
            tender_source_command_note: "正在提交源定标候选 · 校验供应商资格…",
          },
        )
      }
    TenderSourceCommandFinished(command_type, body) =>
      (
        if command_type == "award" {
          load_tender_source_awards(emit)
        } else {
          load_tenders(emit, model.tender_project_id)
        },
        {
          ..model,
          tender_source_command_note: if body.contains(
              "\"source_kind\":\"command\"",
            ) {
            (if command_type == "award" {
              "源定标"
            } else {
              "源状态推进"
            }) +
            "候选已写入 PostgreSQL · workflow/contract/cash/accounting/tax 未执行"
          } else {
            "源招标命令已返回 · 请复核响应边界"
          },
        },
      )
    TenderSourceCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          tender_source_command_note: (if command_type == "award" {
            "源定标"
          } else {
            "源状态推进"
          }) +
          "候选被服务、权限、状态或供应商资格拒绝",
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
    SupplierSourceLoaded(body) => {
      let (rows, missing_table_count) = supplier_source_rows_from_body(body)
      (
        load_supplier_stats(emit),
        {
          ..model,
          supplier_source_loaded: true,
          supplier_source_rows: rows,
          supplier_source_missing_table_count: missing_table_count,
          supplier_source_note: "已加载 PostgreSQL 供应商源表 · 空表与缺失表保持可见 · " +
          model.supplier_dict_note,
        },
      )
    }
    SupplierDictCategoriesLoaded(body) =>
      (
        load_supplier_dict_eval(emit),
        {
          ..model,
          supplier_dict_loaded: false,
          supplier_category_count: source_data_row_count(body).to_string(),
          supplier_dict_note: "供应商类别源 " +
          source_data_row_count(body).to_string() +
          " 行 · 正在读取评价字典",
        },
      )
    SupplierDictEvalLoaded(body) =>
      (
        load_supplier_dict_sources(emit),
        {
          ..model,
          supplier_eval_count: source_data_row_count(body).to_string(),
          supplier_dict_note: "供应商类别 " +
          model.supplier_category_count +
          " 行 · 评价字典 " +
          source_data_row_count(body).to_string() +
          " 行 · 正在读取来源字典",
        },
      )
    SupplierDictSourcesLoaded(body) =>
      (
        load_supplier_source_list(emit),
        {
          ..model,
          supplier_dict_loaded: true,
          supplier_source_count: source_data_row_count(body).to_string(),
          supplier_dict_note: "供应商类别 " +
          model.supplier_category_count +
          " · 评价 " +
          model.supplier_eval_count +
          " · 来源 " +
          source_data_row_count(body).to_string() +
          " 行",
        },
      )
    SupplierDictLoadFailed =>
      (
        load_supplier_source_list(emit),
        {
          ..model,
          supplier_dict_loaded: false,
          supplier_dict_note: "供应商字典源观察不可用 · 使用设计快照",
        },
      )
    SupplierSourceLoadFailed =>
      (
        none,
        {
          ..model,
          supplier_source_loaded: false,
          supplier_source_rows: [],
          supplier_source_missing_table_count: "0",
          supplier_source_note: "供应商源表读模型不可用 · 使用已审核投影或设计快照",
        },
      )
    SupplierDetailLoaded(body) =>
      match supplier_detail_from_body(body) {
        Some(detail) =>
          (
            load_supplier_detail_risk(emit, detail.provider_guid),
            {
              ..model,
              supplier_id: detail.provider_guid,
              supplier_detail_loaded: true,
              supplier_detail: Some(detail),
              supplier_detail_note: "已加载 PostgreSQL 供应商源详情 · 关联组织与合同只读",
            },
          )
        None =>
          (
            none,
            {
              ..model,
              supplier_detail_loaded: false,
              supplier_detail: None,
              supplier_detail_note: "供应商源详情为空 · 使用设计快照",
              supplier_detail_risk_loaded: false,
              supplier_detail_risk_note: "供应商源风险详情为空 · 使用设计快照",
            },
          )
      }
    SupplierDetailLoadFailed =>
      (
        none,
        {
          ..model,
          supplier_detail_loaded: false,
          supplier_detail: None,
          supplier_detail_note: "供应商源详情不可用 · 使用设计快照",
          supplier_detail_risk_loaded: false,
          supplier_detail_risk_note: "供应商源风险详情不可用 · 使用设计快照",
        },
      )
    SupplierDetailRiskLoaded(body) => {
      let (score, rating, tags, contract_count, overdue_count, risk_note) = supplier_detail_risk_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          supplier_detail_risk_loaded: true,
          supplier_detail_risk_score: score,
          supplier_detail_risk_rating: rating,
          supplier_detail_risk_tags: tags,
          supplier_detail_risk_contract_count: contract_count,
          supplier_detail_risk_overdue_count: overdue_count,
          supplier_detail_risk_note: "已加载 PostgreSQL 供应商风险详情 · " +
          risk_note,
        },
      )
    }
    SupplierDetailRiskLoadFailed =>
      (
        none,
        {
          ..model,
          supplier_detail_risk_loaded: false,
          supplier_detail_risk_score: "0",
          supplier_detail_risk_rating: "未定级",
          supplier_detail_risk_tags: "源表未提供",
          supplier_detail_risk_contract_count: "0",
          supplier_detail_risk_overdue_count: "0",
          supplier_detail_risk_note: "供应商源风险详情不可用 · 使用设计快照",
        },
      )
    RequestSupplierCheckSign =>
      (
        issue_supplier_check_sign(emit, model),
        {
          ..model,
          supplier_check_sign_note: "正在检查供应商签约边界 · 不授权签署…",
        },
      )
    SupplierCheckSignFinished(body) =>
      (
        none,
        {
          ..model,
          supplier_check_sign_note: if body.contains(
              "\"decision\":\"derived_command_preview\"",
            ) {
            "供应商签约校验为本地派生预览 · procurement owner 仍需审批 · 未持久化风险"
          } else if body.contains("\"decision\":\"gated\"") {
            "导入供应商已到采购负责人审批门 · 未执行签约校验"
          } else if body.contains("\"code\":43001") {
            "供应商签约校验返回源-404 · 未生成替代记录"
          } else {
            "供应商签约校验响应已返回 · 请复核授权边界"
          },
        },
      )
    SupplierCheckSignFailed =>
      (
        none,
        {
          ..model,
          supplier_check_sign_note: "供应商签约校验服务不可用或被网关拒绝",
        },
      )
    SupplierStatsLoaded(body) => {
      let (total, contract_rows, top_business, stats_note) = supplier_stats_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          supplier_stats_loaded: true,
          supplier_stats_total: total,
          supplier_stats_contract_rows: contract_rows,
          supplier_stats_top_business: top_business,
          supplier_stats_note: "已加载 PostgreSQL 供应商统计源读模型 · " +
          stats_note,
        },
      )
    }
    SupplierStatsLoadFailed =>
      (
        none,
        {
          ..model,
          supplier_stats_loaded: false,
          supplier_stats_total: "0",
          supplier_stats_contract_rows: "0",
          supplier_stats_top_business: "源表未提供",
          supplier_stats_note: "供应商统计源读模型不可用 · 使用设计快照",
        },
      )
    SupplierRiskLoaded(body) => {
      let (rows, distribution_total, missing_table_count) = supplier_risk_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          supplier_risk_loaded: true,
          supplier_risk_rows: rows,
          supplier_risk_distribution_total: distribution_total,
          supplier_risk_missing_table_count: missing_table_count,
          supplier_risk_note: "已加载 PostgreSQL 供应商风险源读模型 · D/E 风险行只读",
        },
      )
    }
    SupplierRiskLoadFailed =>
      (
        none,
        {
          ..model,
          supplier_risk_loaded: false,
          supplier_risk_rows: [],
          supplier_risk_distribution_total: "0",
          supplier_risk_missing_table_count: "0",
          supplier_risk_note: "供应商风险源读模型不可用 · 使用设计快照",
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
    RescoreSuppliers =>
      (
        issue_supplier_rescore(emit),
        {
          ..model,
          supplier_note: "正在重算供应商风险评分 · 不调用 provider…",
        },
      )
    SupplierRescoreFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_suppliers(emit)
        } else {
          none
        },
        {
          ..model,
          supplier_note: if body.contains("\"providerExecution\":false") {
            "供应商风险重算已写入本地投影 · 导入供应商受保护 · 不调用 provider"
          } else {
            "供应商风险重算候选已返回 · 请复核执行边界"
          },
        },
      )
    SupplierRescoreFailed =>
      (
        none,
        {
          ..model,
          supplier_note: "供应商风险重算服务不可用或被网关拒绝",
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
          sales_customer_rows: if family == "customers" {
            sales_customer_rows_from_body(body)
          } else {
            model.sales_customer_rows
          },
          sales_subscription_rows: if family == "subscriptions" {
            sales_subscription_rows_from_body(body)
          } else {
            model.sales_subscription_rows
          },
          sales_subscription_loaded: if family == "subscriptions" {
            true
          } else {
            model.sales_subscription_loaded
          },
          sales_contract_rows: if family == "contracts" {
            sales_contract_rows_from_body(body)
          } else {
            model.sales_contract_rows
          },
          sales_contract_loaded: if family == "contracts" {
            true
          } else {
            model.sales_contract_loaded
          },
          sales_mortgage_rows: if family == "mortgages" {
            sales_mortgage_rows_from_body(body)
          } else {
            model.sales_mortgage_rows
          },
          sales_mortgage_loaded: if family == "mortgages" {
            true
          } else {
            model.sales_mortgage_loaded
          },
          sales_revenue_rows: if family == "revenues" {
            sales_revenue_rows_from_body(body)
          } else {
            model.sales_revenue_rows
          },
          sales_revenue_loaded: if family == "revenues" {
            true
          } else {
            model.sales_revenue_loaded
          },
          sales_note: "已加载 PostgreSQL 销售源读模型 · 空表保持可见 · 导入记录保持只读",
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
          sales_customer_rows: if family == "customers" {
            []
          } else {
            model.sales_customer_rows
          },
          sales_subscription_rows: if family == "subscriptions" {
            []
          } else {
            model.sales_subscription_rows
          },
          sales_subscription_loaded: if family == "subscriptions" {
            false
          } else {
            model.sales_subscription_loaded
          },
          sales_contract_rows: if family == "contracts" {
            []
          } else {
            model.sales_contract_rows
          },
          sales_contract_loaded: if family == "contracts" {
            false
          } else {
            model.sales_contract_loaded
          },
          sales_mortgage_rows: if family == "mortgages" {
            []
          } else {
            model.sales_mortgage_rows
          },
          sales_mortgage_loaded: if family == "mortgages" {
            false
          } else {
            model.sales_mortgage_loaded
          },
          sales_revenue_rows: if family == "revenues" {
            []
          } else {
            model.sales_revenue_rows
          },
          sales_revenue_loaded: if family == "revenues" {
            false
          } else {
            model.sales_revenue_loaded
          },
          sales_note: "销售/应收读模型不可用 · 使用已审核快照",
        },
      )
    SelectSalesCustomerProject(project_id) =>
      (
        load_sales_for(
          emit,
          "customers",
          project_id,
          model.sales_customer_keyword,
        ),
        {
          ..model,
          sales_customer_project_id: project_id,
          sales_loaded: false,
          sales_customer_rows: [],
          sales_note: "正在读取所选项目的客户档案…",
        },
      )
    InputSalesCustomerKeyword(value) =>
      (none, { ..model, sales_customer_keyword: value })
    OpenSalesCustomerCreate =>
      (
        none,
        {
          ..model,
          sales_customer_form_open: true,
          sales_customer_edit_id: "",
          sales_customer_name: "",
          sales_customer_id_card_no: "",
          sales_customer_phone: "",
          sales_customer_source: "案场",
          sales_customer_remark: "",
        },
      )
    OpenSalesCustomerEdit(customer_id) => {
      let mut name = ""
      let mut id_card_no = ""
      let mut phone = ""
      let mut source = ""
      let mut remark = ""
      let mut project_id = model.sales_customer_project_id
      for row in model.sales_customer_rows {
        if row.customer_guid == customer_id {
          name = row.customer_name
          id_card_no = row.id_card_no
          phone = row.phone
          source = row.source
          remark = row.remark
          project_id = row.proj_guid
        }
      }
      (
        none,
        {
          ..model,
          sales_customer_form_open: true,
          sales_customer_edit_id: customer_id,
          sales_customer_project_id: project_id,
          sales_customer_name: name,
          sales_customer_id_card_no: id_card_no,
          sales_customer_phone: phone,
          sales_customer_source: source,
          sales_customer_remark: remark,
        },
      )
    }
    CloseSalesCustomerForm =>
      (none, { ..model, sales_customer_form_open: false })
    InputSalesCustomerField(field, value) =>
      (
        none,
        {
          ..model,
          sales_customer_name: if field == "name" {
            value
          } else {
            model.sales_customer_name
          },
          sales_customer_id_card_no: if field == "id_card_no" {
            value
          } else {
            model.sales_customer_id_card_no
          },
          sales_customer_phone: if field == "phone" {
            value
          } else {
            model.sales_customer_phone
          },
          sales_customer_project_id: if field == "project_id" {
            value
          } else {
            model.sales_customer_project_id
          },
          sales_customer_source: if field == "source" {
            value
          } else {
            model.sales_customer_source
          },
          sales_customer_remark: if field == "remark" {
            value
          } else {
            model.sales_customer_remark
          },
        },
      )
    SubmitSalesCustomerForm =>
      if model.sales_customer_name.trim().is_empty() ||
        model.sales_customer_phone.trim().is_empty() {
        (
          none,
          {
            ..model,
            sales_customer_command_note: "姓名和电话不能为空",
          },
        )
      } else if model.sales_customer_edit_id.is_empty() {
        (
          issue_sales_customer_create(emit, model),
          {
            ..model,
            sales_customer_form_open: false,
            sales_customer_command_note: "正在写入本地客户档案命令…",
          },
        )
      } else {
        (
          issue_sales_customer_update(emit, model),
          {
            ..model,
            sales_customer_form_open: false,
            sales_customer_command_note: "正在更新本地客户档案命令…",
          },
        )
      }
    DeleteSalesCustomer(customer_id) =>
      if customer_id.is_empty() {
        (none, model)
      } else {
        (
          issue_sales_customer_delete(emit, customer_id),
          {
            ..model,
            sales_customer_command_note: "正在提交客户归档/删除命令…",
          },
        )
      }
    SalesCustomerCommandFinished(body) =>
      (
        load_sales_for(
          emit,
          "customers",
          model.sales_customer_project_id,
          model.sales_customer_keyword,
        ),
        {
          ..model,
          sales_customer_form_open: false,
          sales_customer_command_note: if body.contains(
              "\"idempotent_replay\":true",
            ) {
            "客户命令已幂等重放 · 本地投影保持稳定"
          } else {
            "客户命令已写入 PostgreSQL · 导入客户保持只读 · 不触发合同/回款"
          },
        },
      )
    SalesCustomerCommandFailed =>
      (
        none,
        {
          ..model,
          sales_customer_command_note: "客户命令服务不可用、权限不足或客户已存在",
        },
      )
    SelectSalesSubscriptionProject(project_id) =>
      (
        load_sales_for(emit, "subscriptions", project_id, ""),
        {
          ..model,
          sales_subscription_project_id: project_id,
          sales_subscription_rows: [],
          sales_subscription_loaded: false,
          sales_loaded: false,
          sales_note: "正在读取所选项目的认筹档案…",
        },
      )
    SelectSalesSubscriptionState(state) =>
      (none, { ..model, sales_subscription_state: state })
    OpenSalesSubscriptionForm =>
      (
        none,
        {
          ..model,
          sales_subscription_form_open: true,
          sales_subscription_customer_guid: "",
          sales_subscription_proj_guid: if model.sales_subscription_project_id.is_empty() {
            model.project_rows
            .get(0)
            .map(row => row.project_id)
            .unwrap_or("proj-0001")
          } else {
            model.sales_subscription_project_id
          },
          sales_subscription_building_no: "",
          sales_subscription_unit_no: "",
          sales_subscription_area: "0",
          sales_subscription_unit_price: "0",
          sales_subscription_total_price: "0",
          sales_subscription_sub_amount: "0",
          sales_subscription_sub_date: "2026-07-16",
          sales_subscription_payment_type: "按揭",
        },
      )
    CloseSalesSubscriptionForm =>
      (none, { ..model, sales_subscription_form_open: false })
    InputSalesSubscriptionField(field, value) => {
      let total = if field == "area" || field == "unit_price" {
        let area = if field == "area" {
          sales_parse_number(value)
        } else {
          sales_parse_number(model.sales_subscription_area)
        }
        let unit_price = if field == "unit_price" {
          sales_parse_number(value)
        } else {
          sales_parse_number(model.sales_subscription_unit_price)
        }
        (area * unit_price).to_string()
      } else {
        model.sales_subscription_total_price
      }
      (
        none,
        {
          ..model,
          sales_subscription_customer_guid: if field == "customer_guid" {
            value
          } else {
            model.sales_subscription_customer_guid
          },
          sales_subscription_proj_guid: if field == "proj_guid" {
            value
          } else {
            model.sales_subscription_proj_guid
          },
          sales_subscription_building_no: if field == "building_no" {
            value
          } else {
            model.sales_subscription_building_no
          },
          sales_subscription_unit_no: if field == "unit_no" {
            value
          } else {
            model.sales_subscription_unit_no
          },
          sales_subscription_area: if field == "area" {
            value
          } else {
            model.sales_subscription_area
          },
          sales_subscription_unit_price: if field == "unit_price" {
            value
          } else {
            model.sales_subscription_unit_price
          },
          sales_subscription_total_price: total,
          sales_subscription_sub_amount: if field == "sub_amount" {
            value
          } else {
            model.sales_subscription_sub_amount
          },
          sales_subscription_sub_date: if field == "sub_date" {
            value
          } else {
            model.sales_subscription_sub_date
          },
          sales_subscription_payment_type: if field == "payment_type" {
            value
          } else {
            model.sales_subscription_payment_type
          },
        },
      )
    }
    SubmitSalesSubscriptionForm =>
      if model.sales_subscription_customer_guid.trim().is_empty() ||
        model.sales_subscription_proj_guid.trim().is_empty() ||
        model.sales_subscription_building_no.trim().is_empty() ||
        model.sales_subscription_unit_no.trim().is_empty() {
        (
          none,
          {
            ..model,
            sales_subscription_command_note: "客户、项目、楼栋、房号不能为空",
          },
        )
      } else {
        (
          issue_sales_subscription_create(emit, model),
          {
            ..model,
            sales_subscription_form_open: false,
            sales_subscription_command_note: "正在写入本地认筹命令…",
          },
        )
      }
    ConvertSalesSubscription(subscription_id) =>
      if subscription_id.is_empty() {
        (none, model)
      } else {
        (
          issue_sales_subscription_convert(
            emit,
            subscription_id,
            model.sales_subscription_payment_type,
          ),
          {
            ..model,
            sales_subscription_command_note: "正在提交转签约候选 · 不自动创建合同或回款…",
          },
        )
      }
    SalesSubscriptionCommandFinished(body) =>
      (
        load_sales_for(
          emit,
          "subscriptions",
          model.sales_subscription_project_id,
          "",
        ),
        {
          ..model,
          sales_subscription_command_note: if body.contains(
              "\"idempotent_replay\":true",
            ) {
            "认筹命令已幂等重放 · 本地投影保持稳定"
          } else if body.contains("\"command_type\":\"convert_to_contract\"") {
            "转签约候选已写入 PostgreSQL · 合同/回款仍保持待处理"
          } else {
            "认筹命令已写入 PostgreSQL · 合同/回款仍保持待处理"
          },
        },
      )
    SalesSubscriptionCommandFailed =>
      (
        none,
        {
          ..model,
          sales_subscription_command_note: "认筹命令服务不可用或请求不满足边界",
        },
      )
    SelectSalesContractProject(project_id) =>
      (
        load_sales_for(emit, "contracts", project_id, ""),
        {
          ..model,
          sales_contract_project_id: project_id,
          sales_contract_rows: [],
          sales_contract_loaded: false,
          sales_loaded: false,
          sales_note: "正在读取所选项目的签约档案…",
        },
      )
    SelectSalesContractState(state) =>
      (none, { ..model, sales_contract_state: state })
    SelectSalesMortgageState(state) =>
      (none, { ..model, sales_mortgage_filter_state: state })
    SelectSalesRevenueProject(project_id) =>
      (
        load_sales_for(
          emit,
          "revenues",
          project_id,
          model.sales_revenue_keyword,
        ),
        {
          ..model,
          sales_revenue_project_id: project_id,
          sales_revenue_rows: [],
          sales_revenue_loaded: false,
          sales_loaded: false,
          sales_note: "正在读取所选项目的回款档案…",
        },
      )
    SelectSalesRevenueStatus(status) =>
      (none, { ..model, sales_revenue_filter_status: status })
    InputSalesRevenueKeyword(keyword) =>
      (none, { ..model, sales_revenue_keyword: keyword })
    QuerySalesRevenue =>
      (
        load_sales_for(
          emit,
          "revenues",
          model.sales_revenue_project_id,
          model.sales_revenue_keyword,
        ),
        {
          ..model,
          sales_revenue_loaded: false,
          sales_note: "正在查询回款源记录…",
        },
      )
    OpenSalesRevenueEdit(revenue_id) => {
      let mut project = model.sales_revenue_project_id
      let mut customer = ""
      let mut amount = "0"
      let mut date = "2026-07-16"
      let mut status = "expected"
      let mut payment_type = "首付"
      let mut contract_no = ""
      let mut remark = ""
      for row in model.sales_revenue_rows {
        if row.revenue_guid == revenue_id {
          project = row.proj_guid
          customer = row.customer_name
          amount = row.amount
          date = row.receive_date
          status = row.status
          payment_type = row.payment_type
          contract_no = row.contract_no
          remark = row.remark
        }
      }
      (
        none,
        {
          ..model,
          sales_revenue_form_open: true,
          sales_revenue_editing_id: revenue_id,
          sales_revenue_form_project: project,
          sales_revenue_form_customer: customer,
          sales_revenue_form_amount: amount,
          sales_revenue_form_date: date,
          sales_revenue_form_status: status,
          sales_revenue_form_payment_type: payment_type,
          sales_revenue_form_contract_no: contract_no,
          sales_revenue_form_remark: remark,
        },
      )
    }
    CloseSalesRevenueForm => (none, { ..model, sales_revenue_form_open: false })
    InputSalesRevenueField(field, value) =>
      (
        none,
        {
          ..model,
          sales_revenue_form_project: if field == "project" {
            value
          } else {
            model.sales_revenue_form_project
          },
          sales_revenue_form_customer: if field == "customer" {
            value
          } else {
            model.sales_revenue_form_customer
          },
          sales_revenue_form_amount: if field == "amount" {
            value
          } else {
            model.sales_revenue_form_amount
          },
          sales_revenue_form_date: if field == "date" {
            value
          } else {
            model.sales_revenue_form_date
          },
          sales_revenue_form_status: if field == "status" {
            value
          } else {
            model.sales_revenue_form_status
          },
          sales_revenue_form_payment_type: if field == "payment_type" {
            value
          } else {
            model.sales_revenue_form_payment_type
          },
          sales_revenue_form_contract_no: if field == "contract_no" {
            value
          } else {
            model.sales_revenue_form_contract_no
          },
          sales_revenue_form_remark: if field == "remark" {
            value
          } else {
            model.sales_revenue_form_remark
          },
        },
      )
    SubmitSalesRevenueForm =>
      if model.sales_revenue_form_project.trim().is_empty() ||
        model.sales_revenue_form_customer.trim().is_empty() ||
        sales_parse_number(model.sales_revenue_form_amount) <= 0.0 {
        (
          none,
          {
            ..model,
            sales_revenue_command_note: "项目、客户和正数金额不能为空",
          },
        )
      } else {
        let command_type = if model.sales_revenue_editing_id.is_empty() {
          "create"
        } else {
          "update"
        }
        (
          issue_sales_revenue_command(emit, model, command_type),
          {
            ..model,
            sales_revenue_form_open: false,
            sales_revenue_state: "pending",
            sales_revenue_command_note: "正在登记本地回款 · 校验销售/财务 authority…",
          },
        )
      }
    OpenSalesMortgageForm(contract_id, customer_id, amount) =>
      (
        none,
        {
          ..model,
          sales_mortgage_form_open: true,
          sales_mortgage_form_contract: contract_id,
          sales_mortgage_form_customer: customer_id,
          sales_mortgage_form_amount: amount,
          sales_mortgage_form_bank: "建设银行",
          sales_mortgage_form_years: "30",
          sales_mortgage_form_rate: "0.0485",
          sales_mortgage_form_date: "2026-07-16",
          sales_mortgage_form_remark: "",
        },
      )
    CloseSalesMortgageForm =>
      (none, { ..model, sales_mortgage_form_open: false })
    InputSalesMortgageField(field, value) =>
      (
        none,
        {
          ..model,
          sales_mortgage_form_contract: if field == "contract" {
            value
          } else {
            model.sales_mortgage_form_contract
          },
          sales_mortgage_form_customer: if field == "customer" {
            value
          } else {
            model.sales_mortgage_form_customer
          },
          sales_mortgage_form_bank: if field == "bank" {
            value
          } else {
            model.sales_mortgage_form_bank
          },
          sales_mortgage_form_amount: if field == "amount" {
            value
          } else {
            model.sales_mortgage_form_amount
          },
          sales_mortgage_form_years: if field == "years" {
            value
          } else {
            model.sales_mortgage_form_years
          },
          sales_mortgage_form_rate: if field == "rate" {
            value
          } else {
            model.sales_mortgage_form_rate
          },
          sales_mortgage_form_date: if field == "date" {
            value
          } else {
            model.sales_mortgage_form_date
          },
          sales_mortgage_form_remark: if field == "remark" {
            value
          } else {
            model.sales_mortgage_form_remark
          },
        },
      )
    SubmitSalesMortgageForm =>
      if model.sales_mortgage_form_contract.trim().is_empty() ||
        model.sales_mortgage_form_bank.trim().is_empty() ||
        sales_parse_number(model.sales_mortgage_form_amount) <= 0.0 {
        (
          none,
          {
            ..model,
            sales_mortgage_command_note: "合同、银行和正数贷款金额不能为空",
          },
        )
      } else {
        (
          issue_sales_mortgage_command(emit, model, "create"),
          {
            ..model,
            sales_mortgage_form_open: false,
            sales_mortgage_state: "pending",
            sales_mortgage_command_note: "正在写入本地按揭申请命令…",
          },
        )
      }
    CreateSalesMortgage =>
      (
        none,
        {
          ..model,
          sales_mortgage_form_open: true,
          sales_mortgage_form_contract: "SCT-RABBITA-LOCAL",
          sales_mortgage_form_customer: "CUS-RABBITA-LOCAL",
          sales_mortgage_form_bank: "建设银行",
          sales_mortgage_form_amount: "1673000",
          sales_mortgage_form_years: "30",
          sales_mortgage_form_rate: "0.0345",
          sales_mortgage_form_date: "2026-07-16",
          sales_mortgage_form_remark: "Rabbita 本地按揭命令演示",
        },
      )
    ApproveSalesMortgage =>
      if model.sales_mortgage_state == "applying" {
        (
          issue_sales_mortgage_command(emit, model, "approve"),
          {
            ..model,
            sales_mortgage_state: "pending",
            sales_mortgage_command_note: "正在记录本地批贷候选…",
          },
        )
      } else {
        (none, model)
      }
    ReleaseSalesMortgage =>
      if model.sales_mortgage_state == "approved" {
        (
          issue_sales_mortgage_command(emit, model, "release"),
          {
            ..model,
            sales_mortgage_state: "pending",
            sales_mortgage_command_note: "正在记录本地放款候选 · 不调用银行/回款…",
          },
        )
      } else {
        (none, model)
      }
    SalesMortgageCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"released\"") {
        "released"
      } else if body.contains("\"state\":\"approved\"") {
        "approved"
      } else if body.contains("\"state\":\"applying\"") {
        "applying"
      } else {
        model.sales_mortgage_state
      }
      (
        load_sales(emit, "mortgages"),
        {
          ..model,
          sales_mortgage_state: next_state,
          sales_mortgage_command_note: if body.contains(
              "\"idempotent_replay\":true",
            ) {
            "按揭命令已幂等重放 · 本地投影保持稳定"
          } else if next_state == "released" {
            "按揭放款候选已写入 PostgreSQL · 回款/银行/现金仍保持待处理"
          } else {
            "按揭命令已写入 PostgreSQL · provider 与下游回款未执行"
          },
        },
      )
    }
    SalesMortgageCommandFailed =>
      (
        none,
        {
          ..model,
          sales_mortgage_state: "error",
          sales_mortgage_command_note: "按揭命令服务不可用、状态不允许或请求被拒绝",
        },
      )
    OpenSalesRefundForm(contract_id, customer_id, amount) =>
      (
        none,
        {
          ..model,
          sales_refund_form_open: true,
          sales_refund_form_contract: contract_id,
          sales_refund_form_customer: customer_id,
          sales_refund_form_reason: "",
          sales_refund_form_amount: amount,
          sales_refund_form_date: "2026-07-16",
        },
      )
    CloseSalesRefundForm => (none, { ..model, sales_refund_form_open: false })
    InputSalesRefundField(field, value) =>
      (
        none,
        {
          ..model,
          sales_refund_form_contract: if field == "contract" {
            value
          } else {
            model.sales_refund_form_contract
          },
          sales_refund_form_customer: if field == "customer" {
            value
          } else {
            model.sales_refund_form_customer
          },
          sales_refund_form_reason: if field == "reason" {
            value
          } else {
            model.sales_refund_form_reason
          },
          sales_refund_form_amount: if field == "amount" {
            value
          } else {
            model.sales_refund_form_amount
          },
          sales_refund_form_date: if field == "date" {
            value
          } else {
            model.sales_refund_form_date
          },
        },
      )
    SubmitSalesRefundForm =>
      if model.sales_refund_form_contract.trim().is_empty() ||
        model.sales_refund_form_reason.trim().is_empty() {
        (
          none,
          {
            ..model,
            sales_refund_command_note: "合同和退房原因不能为空",
          },
        )
      } else {
        (
          issue_sales_refund_command(emit, model, "create"),
          {
            ..model,
            sales_refund_form_open: false,
            sales_refund_state: "pending",
            sales_refund_command_note: "正在写入本地退款申请 · 不触发合同/回款/现金…",
          },
        )
      }
    CreateSalesRefund =>
      if model.sales_refund_state == "new" ||
        model.sales_refund_state == "error" {
        (
          none,
          {
            ..model,
            sales_refund_form_open: true,
            sales_refund_form_contract: "SCT-RABBITA-LOCAL",
            sales_refund_form_customer: "CUS-RABBITA-LOCAL",
            sales_refund_form_reason: "个人原因",
            sales_refund_form_amount: "120000",
            sales_refund_form_date: "2026-07-16",
          },
        )
      } else {
        (none, model)
      }
    ApproveSalesRefund =>
      if model.sales_refund_state == "applying" {
        (
          issue_sales_refund_command(emit, model, "approve"),
          {
            ..model,
            sales_refund_state: "pending",
            sales_refund_command_note: "正在记录退款审批候选 · 合同/回款仍保持待处理…",
          },
        )
      } else {
        (none, model)
      }
    SalesRefundCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"approved\"") {
        "approved"
      } else if body.contains("\"state\":\"applying\"") {
        "applying"
      } else {
        "error"
      }
      if next_state == "error" {
        (
          none,
          {
            ..model,
            sales_refund_state: "error",
            sales_refund_command_note: body,
          },
        )
      } else {
        (
          load_sales(emit, "revenues"),
          {
            ..model,
            sales_refund_state: next_state,
            sales_refund_command_note: if body.contains(
                "\"idempotent_replay\":true",
              ) {
              "退款命令已幂等重放 · 本地投影保持稳定"
            } else if next_state == "approved" {
              "退款审批候选已写入 PostgreSQL · 合同/回款/现金/会计/税务仍未执行"
            } else {
              "退款申请已写入 PostgreSQL · 需要后续审批，不触发外部退款"
            },
          },
        )
      }
    }
    SalesRefundCommandFailed =>
      (
        none,
        {
          ..model,
          sales_refund_state: "error",
          sales_refund_command_note: "退款命令服务不可用、状态不允许或请求被拒绝",
        },
      )
    CreateSalesRevenue =>
      (
        none,
        {
          ..model,
          sales_revenue_form_open: true,
          sales_revenue_editing_id: "",
          sales_revenue_form_project: if model.sales_revenue_project_id.is_empty() {
            model.project_rows
            .get(0)
            .map(row => row.project_id)
            .unwrap_or("proj-0001")
          } else {
            model.sales_revenue_project_id
          },
          sales_revenue_form_customer: "",
          sales_revenue_form_amount: "0",
          sales_revenue_form_date: "2026-07-16",
          sales_revenue_form_status: "expected",
          sales_revenue_form_payment_type: "首付",
          sales_revenue_form_contract_no: "",
          sales_revenue_form_remark: "",
        },
      )
    UpdateSalesRevenue =>
      if model.sales_revenue_state == "expected" {
        (
          issue_sales_revenue_command(emit, model, "update"),
          {
            ..model,
            sales_revenue_state: "pending",
            sales_revenue_command_note: "正在更新本地回款备注并写入审计…",
          },
        )
      } else {
        (none, model)
      }
    ConfirmSalesRevenue =>
      if model.sales_revenue_state == "expected" {
        (
          issue_sales_revenue_command(emit, model, "confirm_received"),
          {
            ..model,
            sales_revenue_state: "pending",
            sales_revenue_command_note: "正在确认到账证据 · 不释放现金或过账…",
          },
        )
      } else {
        (none, model)
      }
    DeleteSalesRevenue =>
      if model.sales_revenue_state == "received" ||
        model.sales_revenue_state == "expected" {
        (
          issue_sales_revenue_command(emit, model, "delete"),
          {
            ..model,
            sales_revenue_state: "pending",
            sales_revenue_command_note: "正在撤回本地回款投影 · 导入行仍保持只读…",
          },
        )
      } else {
        (none, model)
      }
    SalesRevenueCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"deleted\"") {
        "deleted"
      } else if body.contains("\"state\":\"received\"") {
        "received"
      } else if body.contains("\"state\":\"expected\"") {
        "expected"
      } else {
        "observed"
      }
      (
        load_sales_for(
          emit,
          "revenues",
          model.sales_revenue_project_id,
          model.sales_revenue_keyword,
        ),
        {
          ..model,
          sales_revenue_form_open: false,
          sales_revenue_state: next_state,
          sales_revenue_command_note: "已写入 PostgreSQL · 回款命令完成 · 审计凭证已生成",
        },
      )
    }
    SalesRevenueCommandFailed =>
      (
        none,
        {
          ..model,
          sales_revenue_state: "error",
          sales_revenue_command_note: "回款命令服务不可用、authority 不足或状态不允许",
        },
      )
    InvoiceSourceInLoaded(body) =>
      (
        load_invoice_source_out_for(emit, model.invoice_project_id),
        {
          ..model,
          sales_loaded: true,
          sales_family: "invoices",
          sales_rows: sales_rows_from_body(body),
          invoice_in_rows: invoice_rows_from_body(body, "in"),
          invoice_source_loaded: false,
          invoice_source_in_count: invoice_rows_from_body(body, "in")
          .length()
          .to_string(),
          invoice_source_out_count: "0",
          invoice_source_tax_count: "0",
          sales_note: "已加载 PostgreSQL 进项发票源读模型 · 正在读取销项与税务台账",
          invoice_source_note: "进项源已连接 · 导入行只读 · 本地登记需授权 · 继续读取销项/税务台账",
        },
      )
    InvoiceSourceOutLoaded(body) => {
      let rows = model.sales_rows
      let out_count = append_sales_rows(rows, body)
      (
        load_invoice_source_tax_for(emit, model.invoice_project_id),
        {
          ..model,
          sales_rows: rows,
          invoice_out_rows: invoice_rows_from_body(body, "out"),
          invoice_source_out_count: out_count.to_string(),
          sales_note: "已加载 PostgreSQL 进项/销项发票源读模型 · 正在读取税务台账",
          invoice_source_note: "进项/销项源已连接 · 导入行只读 · 本地登记需授权 · 正在读取税务台账",
        },
      )
    }
    InvoiceSourceTaxLoaded(body) =>
      (
        none,
        {
          ..model,
          invoice_source_loaded: true,
          invoice_tax_rows: invoice_tax_rows_from_body(body),
          invoice_source_tax_count: invoice_tax_row_count_from_body(body),
          sales_note: "已加载 PostgreSQL 发票与税务台账源读模型 · 空表保持可见",
          invoice_source_note: "导入行只读 · 本地登记需授权 · 进项 " +
          model.invoice_source_in_count +
          " · 销项 " +
          model.invoice_source_out_count +
          " · 税务台账 " +
          invoice_tax_row_count_from_body(body) +
          " 行",
        },
      )
    InvoiceSourceLoadFailed =>
      (
        none,
        {
          ..model,
          invoice_source_loaded: false,
          sales_loaded: false,
          sales_rows: [],
          invoice_source_note: "发票源读模型不可用 · 使用设计快照",
          sales_note: "发票源读模型不可用 · 使用设计快照",
        },
      )
    OpenInvoiceForm(direction) =>
      (
        none,
        {
          ..model,
          invoice_form_open: direction,
          invoice_type: if direction == "in" {
            "增值税专用发票"
          } else {
            "增值税普通发票"
          },
        },
      )
    CloseInvoiceForm => (none, { ..model, invoice_form_open: "" })
    InputInvoiceField(field, value) =>
      (
        none,
        {
          ..model,
          invoice_no: if field == "invoice_no" {
            value
          } else {
            model.invoice_no
          },
          invoice_counterparty: if field == "invoice_counterparty" {
            value
          } else {
            model.invoice_counterparty
          },
          invoice_date: if field == "invoice_date" {
            value
          } else {
            model.invoice_date
          },
          invoice_total_amount: if field == "invoice_total_amount" {
            value
          } else {
            model.invoice_total_amount
          },
          invoice_tax_rate: if field == "invoice_tax_rate" {
            value
          } else {
            model.invoice_tax_rate
          },
          invoice_type: if field == "invoice_type" {
            value
          } else {
            model.invoice_type
          },
          invoice_remark: if field == "invoice_remark" {
            value
          } else {
            model.invoice_remark
          },
        },
      )
    DeleteInvoice(direction, invoice_id) =>
      if invoice_id.is_empty() || model.invoice_form_open != "" {
        (none, model)
      } else {
        (
          issue_invoice_delete(emit, model, direction, invoice_id),
          {
            ..model,
            invoice_source_note: "正在提交 " +
            direction +
            " 发票删除/归档命令…",
          },
        )
      }
    CreateInvoice(direction) =>
      (
        issue_invoice_create(emit, model, direction),
        {
          ..model,
          invoice_source_note: "正在写入 " + direction + " 发票命令…",
        },
      )
    InvoiceCommandFinished =>
      (
        load_invoice_source_in_for(emit, model.invoice_project_id),
        {
          ..model,
          invoice_form_open: "",
          invoice_source_note: "发票命令已写入 PostgreSQL · 正在刷新进项/销项/税务台账",
        },
      )
    InvoiceCommandFailed =>
      (
        none,
        {
          ..model,
          invoice_source_note: "发票命令服务不可用、authority 不足或请求被拒绝",
        },
      )
    SelectInvoiceProject(project_id) =>
      (
        load_invoice_source_in_for(emit, project_id),
        {
          ..model,
          invoice_project_id: project_id,
          invoice_source_loaded: false,
          invoice_in_rows: [],
          invoice_out_rows: [],
          invoice_tax_rows: [],
          invoice_source_in_count: "0",
          invoice_source_out_count: "0",
          invoice_source_tax_count: "0",
          sales_rows: [],
          invoice_source_note: "正在读取项目发票与税务台账…",
        },
      )
    SelectInvoiceTab(tab) => (none, { ..model, invoice_tab: tab })
    SelectDeliveryProject(project_id) =>
      (
        load_delivery(emit, project_id),
        {
          ..model,
          delivery_project_id: project_id,
          delivery_loaded: false,
          delivery_source_loaded: false,
          delivery_progress_rows: [],
          delivery_output_rows: [],
          delivery_source_progress_rows: [],
          delivery_source_output_rows: [],
          delivery_task_rows: [],
          delivery_report_rows: [],
          delivery_note: "正在读取所选项目的工程进度…",
          delivery_source_note: "正在读取项目源进度/产值…",
        },
      )
    SelectDeliveryTab(tab) => (none, { ..model, delivery_tab: tab })
    DeliverySourceProgressLoaded(body) => {
      let rows = delivery_source_progress_from_body(body)
      (
        load_delivery_source_outputs_for(emit, model.delivery_project_id),
        {
          ..model,
          delivery_source_loaded: false,
          delivery_source_progress_rows: rows,
          delivery_source_progress_count: rows.length().to_string(),
          delivery_source_note: "ERP 源进度已读取 · 继续读取源产值",
        },
      )
    }
    DeliverySourceOutputsLoaded(body) => {
      let rows = delivery_source_outputs_from_body(body)
      (
        load_delivery_overview_for(emit, model.delivery_project_id),
        {
          ..model,
          delivery_source_loaded: true,
          delivery_source_output_rows: rows,
          delivery_source_output_count: rows.length().to_string(),
          delivery_source_note: "ERP 源进度 " +
          model.delivery_source_progress_count +
          " 行 · 源产值 " +
          rows.length().to_string() +
          " 行 · 空表保持可见",
        },
      )
    }
    DeliverySourceLoadFailed =>
      (
        load_delivery_overview_for(emit, model.delivery_project_id),
        {
          ..model,
          delivery_source_loaded: false,
          delivery_source_note: "ERP 源进度/产值读取不可用 · 使用已审核任务观察",
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
          delivery_source_progress_rows: [],
          delivery_source_output_rows: [],
          delivery_task_rows: [],
          delivery_report_rows: [],
          delivery_note: "工程进度/项目计划读模型不可用 · 使用已审核快照",
        },
      )
    ReportsLoaded(body) => {
      let (costs, contracts, stages, supplier_count, approval_count) = reports_from_body(
        body,
      )
      let suppliers = report_supplier_rows_from_body(body)
      let (approval_rows, slow_steps) = report_approval_rows_from_body(body)
      (
        none,
        {
          ..model,
          reports_loaded: true,
          report_tab: model.report_tab,
          report_cost_rows: costs,
          report_contract_rows: contracts,
          report_supplier_rows: suppliers,
          report_approval_rows: approval_rows,
          report_slow_step_rows: slow_steps,
          report_stage_rows: stages,
          report_stage_names: report_stage_names_from_body(body),
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
          report_supplier_rows: [],
          report_approval_rows: [],
          report_slow_step_rows: [],
          report_cost_rows: [],
          report_contract_rows: [],
          report_stage_rows: [],
          report_stage_names: [],
          reports_note: "核心报表读模型不可用 · 使用已审核快照",
        },
      )
    SelectReportTab(tab) => (none, { ..model, report_tab: tab })
    ReportPreferencesLoaded(body) =>
      (
        none,
        {
          ..model,
          report_favorite_loaded: true,
          report_favorite_keys: report_favorite_keys_from_body(body),
          reports_note: model.reports_note + " · 已读取我的常用报表",
        },
      )
    ReportPreferencesLoadFailed =>
      (
        none,
        {
          ..model,
          report_favorite_loaded: false,
          report_favorite_keys: [],
          reports_note: model.reports_note + " · 常用报表偏好不可用",
        },
      )
    ToggleReportFavorite =>
      (
        issue_report_preference_update(emit, model),
        {
          ..model,
          report_favorite_keys: report_favorite_next_keys(model),
          reports_note: "正在更新我的常用报表…",
        },
      )
    ReportPreferenceUpdated(body) =>
      (
        none,
        {
          ..model,
          report_favorite_loaded: true,
          report_favorite_keys: report_favorite_keys_from_body(body),
          reports_note: if body.contains("\"persisted\":true") {
            "我的常用报表已更新 · 偏好命令不改变报表数据"
          } else {
            "常用报表命令已返回 · 请复核偏好状态"
          },
        },
      )
    ExportReportsCsv =>
      (
        {
          download_text(
            report_csv(model),
            "报表-" + model.report_tab + ".csv",
          )
          none
        },
        {
          ..model,
          reports_note: "已导出当前报表 CSV · PostgreSQL 源数据仍保持只读",
        },
      )
    OpenReportShare =>
      (
        none,
        {
          ..model,
          report_share_dialog: true,
          report_share_result_token: "",
          report_share_result_url: "",
          report_share_title: if model.report_tab == "cost" {
            "R1 集团成本汇总"
          } else if model.report_tab == "contract" {
            "R2 合同付款台账"
          } else if model.report_tab == "supplier" {
            "R3 供应商合作分析"
          } else if model.report_tab == "approval" {
            "R4 审批效率分析"
          } else {
            "R5 项目阶段进度大盘"
          },
          report_share_days: "7",
          report_share_note: "分享表单已打开 · 仅允许五类核心报表",
        },
      )
    CloseReportShare => (none, { ..model, report_share_dialog: false })
    InputReportShareTitle(value) =>
      (none, { ..model, report_share_title: value })
    SelectReportShareDays(value) =>
      (none, { ..model, report_share_days: value })
    CreateReportShare =>
      (
        issue_report_share_create(emit, model),
        {
          ..model,
          report_share_note: "正在创建本地报表分享候选 · 公开读取仍受 HTTPS/过期/撤销边界约束",
        },
      )
    ReportShareCreated(body) => {
      let token = report_share_token_from_body(body)
      (
        load_report_shares(emit),
        {
          ..model,
          report_share_dialog: true,
          report_share_result_token: token,
          report_share_result_url: if token == "" {
            ""
          } else {
            "#/share/" + token
          },
          report_share_note: if token == "" {
            "分享命令已返回 · 未找到 token，请复核响应"
          } else {
            "分享链接已生成 · 持有人可只读查看当前报表"
          },
        },
      )
    }
    ReportShareCreateFailed(note) =>
      (none, { ..model, report_share_note: note })
    OpenReportShareList =>
      (
        load_report_shares(emit),
        {
          ..model,
          report_share_list_open: true,
          report_share_note: "正在加载本人创建的分享链接…",
        },
      )
    CloseReportShareList => (none, { ..model, report_share_list_open: false })
    ReportSharesLoaded(body) =>
      (
        none,
        {
          ..model,
          report_share_rows: report_share_rows_from_body(body),
          report_share_note: "已加载本人报表分享链接 · 可撤销命令不会修改报表数据",
        },
      )
    ReportSharesLoadFailed =>
      (
        none,
        {
          ..model,
          report_share_rows: [],
          report_share_note: "分享链接读模型不可用或需要已认证用户",
        },
      )
    RevokeReportShare(token) =>
      (
        issue_report_share_revoke(emit, token),
        {
          ..model,
          report_share_note: "正在撤销分享链接 " + token + "…",
        },
      )
    ReportShareRevoked(body) =>
      (
        load_report_shares(emit),
        {
          ..model,
          report_share_note: if body.contains("\"persisted\":true") {
            "分享链接已撤销 · 报表数据保持只读"
          } else {
            "撤销命令已返回 · 请复核状态"
          },
        },
      )
    ReportShareRevokeFailed(note) =>
      (none, { ..model, report_share_note: note })
    ShareMetaLoaded(body) => {
      let parsed = @json.parse(body) catch { _ => Json::null() }
      match parsed {
        Json::Object(fields) =>
          match fields.get("data") {
            Some(Json::Object(data)) =>
              (
                load_share_data(emit, model.share_token),
                {
                  ..model,
                  share_meta_loaded: true,
                  share_report_key: json_object_text(data, "reportKey", ""),
                  share_report_label: json_object_text(data, "reportLabel", ""),
                  share_title: json_object_text(data, "title", ""),
                  share_expires_at: json_object_text(data, "expiresAt", ""),
                  share_never_expires: json_object_text(
                    data, "neverExpires", "false",
                  ) ==
                  "true",
                  share_note: "分享元数据已加载 · 正在读取只读报表数据",
                },
              )
            _ =>
              (
                none,
                {
                  ..model,
                  share_meta_loaded: false,
                  share_note: if body.contains("链接已撤销") {
                    "分享链接已撤销"
                  } else if body.contains("链接已过期") {
                    "分享链接已过期"
                  } else {
                    "分享链接不存在或元数据不可用"
                  },
                },
              )
          }
        _ =>
          (
            none,
            {
              ..model,
              share_meta_loaded: false,
              share_note: "分享元数据响应无效",
            },
          )
      }
    }
    ShareDataLoaded(body) =>
      (
        none,
        {
          ..model,
          share_loaded: true,
          share_data_body: body,
          share_note: "公开报表数据已加载 · 不需要登录、不提供写入权限",
        },
      )
    ShareLoadFailed(note) =>
      (none, { ..model, share_loaded: false, share_note: note })
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
    DashboardAnomaliesLoaded(body) => {
      let command = if model.page == "/dashboard-v3" {
        load_dashboard_v3(emit)
      } else {
        load_dashboard_v2(emit)
      }
      (
        command,
        {
          ..model,
          dashboard_anomaly_rows: dashboard_anomaly_rows_from_body(body),
        },
      )
    }
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
    DashboardV2Loaded(body) => {
      let (
        loaded,
        values,
        trend_rows,
        stage_rows,
        warning_rows,
        missing_table_count,
      ) = dashboard_v2_from_body(body)
      if loaded {
        (
          none,
          {
            ..model,
            dashboard_v2_loaded: true,
            dashboard_v2_project_count: values[0],
            dashboard_v2_in_progress: values[1],
            dashboard_v2_contract_amount: values[2],
            dashboard_v2_unpaid_amount: values[3],
            dashboard_v2_open_warnings: values[4],
            dashboard_v2_running_processes: values[5],
            dashboard_v2_trend_rows: trend_rows,
            dashboard_v2_stage_rows: stage_rows,
            dashboard_v2_warning_rows: warning_rows,
            dashboard_v2_missing_table_count: missing_table_count,
            dashboard_v2_note: "已加载 PostgreSQL 驾驶舱 v2 源观察 · 仅读 · 缺失源表保持可见",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            dashboard_v2_loaded: false,
            dashboard_v2_trend_rows: [],
            dashboard_v2_stage_rows: [],
            dashboard_v2_warning_rows: [],
            dashboard_v2_note: "驾驶舱 v2 响应无效 · 不显示合成管理指标",
          },
        )
      }
    }
    DashboardV2LoadFailed =>
      (
        none,
        {
          ..model,
          dashboard_v2_loaded: false,
          dashboard_v2_trend_rows: [],
          dashboard_v2_stage_rows: [],
          dashboard_v2_warning_rows: [],
          dashboard_v2_note: "驾驶舱 v2 源观察不可用 · 保留源缺口状态",
        },
      )
    DashboardV3Loaded(body) => {
      let (loaded, snapshot) = dashboard_v3_from_body(body)
      if loaded {
        (
          none,
          {
            ..model,
            dashboard_v3_loaded: true,
            dashboard_v3: snapshot,
            dashboard_v3_note: "已加载 PostgreSQL 驾驶舱 v3 源观察 · 仅读 · 金额按万元展示",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            dashboard_v3_loaded: false,
            dashboard_v3: empty_dashboard_v3(),
            dashboard_v3_note: "驾驶舱 v3 响应无效 · 不显示合成管理指标",
          },
        )
      }
    }
    DashboardV3LoadFailed =>
      (
        none,
        {
          ..model,
          dashboard_v3_loaded: false,
          dashboard_v3: empty_dashboard_v3(),
          dashboard_v3_note: "驾驶舱 v3 源观察不可用 · 保留源缺口状态",
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
          admin_dict_note: "已加载 PostgreSQL 数据字典选项 · 导入行只读",
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
    CreateAdminDictOption =>
      (
        issue_admin_dict_command(emit, model, "create"),
        {
          ..model,
          admin_dict_command_note: "正在创建本地字典项并写入审计…",
        },
      )
    UpdateAdminDictOption =>
      if admin_dict_editable_guid(model) == "" {
        (
          none,
          {
            ..model,
            admin_dict_command_note: "当前没有可编辑的本地字典覆盖项",
          },
        )
      } else {
        (
          issue_admin_dict_command(emit, model, "update"),
          {
            ..model,
            admin_dict_command_note: "正在更新本地字典项并写入审计…",
          },
        )
      }
    AdminDictCommandFinished(body) =>
      (
        load_admin_dict_groups(emit),
        {
          ..model,
          admin_dict_command_note: if body.contains(
              "\"idempotent_replay\":true",
            ) {
            "命令已幂等重放 · 字典覆盖保持稳定"
          } else {
            "已写入 PostgreSQL 本地字典覆盖 · 导入行未修改 · 无外部副作用"
          },
        },
      )
    AdminDictCommandFailed =>
      (
        none,
        {
          ..model,
          admin_dict_command_note: "字典命令服务不可用、管理员权限不足或请求被拒绝",
        },
      )
    RequestAdminBackup =>
      (
        issue_admin_backup(emit),
        {
          ..model,
          admin_backup_note: "正在检查 PostgreSQL 备份导出边界…",
        },
      )
    AdminBackupFinished(body) =>
      (
        none,
        {
          ..model,
          admin_backup_note: if body.contains("\"backup_status\":\"gated\"") &&
            body.contains("\"format\":\"postgresql\"") {
            "备份请求已到 PostgreSQL 目标格式门 · 未导出二进制 · owner/retention/download 未授权"
          } else {
            "备份边界响应已返回 · 请复核导出与保留策略"
          },
        },
      )
    AdminBackupFailed =>
      (
        none,
        {
          ..model,
          admin_backup_note: "备份边界服务不可用或被网关拒绝",
        },
      )
    SelectInvestmentProject(project_id) => {
      let mut project_name = project_id
      for row in model.project_rows {
        if row.project_id == project_id {
          project_name = row.project_name
        }
      }
      (
        @cmd.batch([
          load_investment_versions_for(emit, project_id),
          load_investment_imports_for(emit, project_id),
        ]),
        {
          ..model,
          investment_project_id: project_id,
          investment_project_name: project_name,
          investment_loaded: false,
          investment_version_id: "",
          investment_version_name: "",
          investment_version_rows: [],
          investment_index_rows: [],
          investment_index_selected: "",
          investment_index_edit_value: "",
          investment_index_edit_remark: "",
          investment_imports_loaded: false,
          investment_import_rows: [],
          investment_import_selected: "",
          investment_note: "正在读取项目投资版本…",
          investment_import_note: "正在读取项目 Excel 导入历史…",
        },
      )
    }
    InvestmentVersionsLoaded(body) => {
      let (version_id, version_name) = investment_version_from_body(body)
      let version_rows = investment_version_rows_from_body(body)
      if version_id == "" {
        (
          none,
          {
            ..model,
            investment_loaded: false,
            investment_note: "投资版本源数据为空 · 使用设计快照",
            investment_version_rows: version_rows,
          },
        )
      } else {
        (
          load_investment_indices(emit, version_id),
          {
            ..model,
            investment_version_id: version_id,
            investment_version_name: version_name,
            investment_version_rows: version_rows,
            investment_note: "已加载 PostgreSQL 投资版本 · 正在读取指标",
          },
        )
      }
    }
    SelectInvestmentVersion(version_id) =>
      if version_id.trim().is_empty() {
        (
          none,
          {
            ..model,
            investment_note: "版本记录缺少 versionGuid · 无法读取指标",
          },
        )
      } else {
        let mut version_name = version_id
        for row in model.investment_version_rows {
          if row.version_guid == version_id {
            version_name = row.version_name
          }
        }
        (
          load_investment_indices(emit, version_id),
          {
            ..model,
            investment_version_id: version_id,
            investment_version_name: version_name,
            investment_loaded: false,
            investment_index_selected: "",
            investment_index_edit_value: "",
            investment_index_edit_remark: "",
            investment_note: "正在读取所选投资版本指标…",
          },
        )
      }
    SelectInvestmentIndex(index_id) =>
      (
        none,
        {
          ..model,
          investment_index_selected: index_id,
          investment_index_edit_value: investment_index_value_for(
            model.investment_index_rows,
            index_id,
          ),
          investment_index_edit_remark: investment_index_remark_for(
            model.investment_index_rows,
            index_id,
          ),
          investment_command_note: if index_id.is_empty() {
            model.investment_command_note
          } else {
            "已选择指标 " +
            index_id +
            " · 更新/删除仍需投资负责人确认"
          },
        },
      )
    InputInvestmentIndexEditValue(value) =>
      (none, { ..model, investment_index_edit_value: value })
    InputInvestmentIndexEditRemark(value) =>
      (none, { ..model, investment_index_edit_remark: value })
    InputInvestmentVersionName(value) =>
      (none, { ..model, investment_new_version_name: value })
    InputInvestmentVersionCopyFrom(value) =>
      (none, { ..model, investment_new_version_copy_from: value })
    InputInvestmentVersionRemark(value) =>
      (none, { ..model, investment_new_version_remark: value })
    ToggleInvestmentVersionActivate =>
      (
        none,
        {
          ..model,
          investment_new_version_activate: !model.investment_new_version_activate,
        },
      )
    InputInvestmentIndexDimension(value) =>
      (none, { ..model, investment_new_index_dimension: value })
    InputInvestmentIndexFullCode(value) =>
      (none, { ..model, investment_new_index_full_code: value })
    InputInvestmentIndexName(value) =>
      (none, { ..model, investment_new_index_name: value })
    InputInvestmentIndexParentCode(value) =>
      (none, { ..model, investment_new_index_parent_code: value })
    InputInvestmentIndexUnit(value) =>
      (none, { ..model, investment_new_index_unit: value })
    InputInvestmentIndexValue(value) =>
      (none, { ..model, investment_new_index_value: value })
    InputInvestmentIndexRemark(value) =>
      (none, { ..model, investment_new_index_remark: value })
    InvestmentImportsLoaded(body) => {
      let (loaded, rows, note) = investment_import_rows_from_body(body)
      (
        none,
        {
          ..model,
          investment_imports_loaded: loaded,
          investment_import_rows: rows,
          investment_import_note: if loaded {
            note
          } else {
            "Excel 导入历史为空 · 源表只读"
          },
        },
      )
    }
    SelectInvestmentImport(import_id) =>
      if import_id.trim().is_empty() {
        (
          none,
          {
            ..model,
            investment_import_note: "导入记录缺少 importGuid · 无法读取详情",
          },
        )
      } else {
        (
          @cmd.batch([
            load_investment_import_detail(emit, import_id),
            load_investment_import_bridge(emit, import_id),
            load_investment_import_index_preview(emit, import_id),
            load_investment_import_profit(emit, import_id),
            load_investment_import_plan(emit, import_id),
          ]),
          {
            ..model,
            investment_import_selected: import_id,
            investment_import_detail_note: "正在读取导入详情…",
            investment_import_bridge_note: "正在读取逻辑桥接计划…",
            investment_import_index_preview_note: "正在读取指标 upsert 预览…",
            investment_import_profit_note: "正在读取利润测算总表…",
            investment_import_plan_note: "正在读取计划行预览…",
          },
        )
      }
    InvestmentImportDetailLoaded(body) =>
      (
        none,
        {
          ..model,
          investment_import_detail_note: investment_import_read_note(
            body, "detail",
          ),
        },
      )
    InvestmentImportBridgeLoaded(body) =>
      (
        none,
        {
          ..model,
          investment_import_bridge_note: investment_import_read_note(
            body, "bridge",
          ),
        },
      )
    InvestmentImportIndexPreviewLoaded(body) =>
      (
        none,
        {
          ..model,
          investment_import_index_preview_note: investment_import_read_note(
            body, "index-preview",
          ),
        },
      )
    InvestmentImportProfitLoaded(body) =>
      (
        none,
        {
          ..model,
          investment_import_profit_note: investment_import_read_note(
            body, "profit",
          ),
        },
      )
    InvestmentImportPlanLoaded(body) =>
      (
        none,
        {
          ..model,
          investment_import_plan_note: investment_import_read_note(body, "plan"),
        },
      )
    InvestmentIndicesLoaded(body) => {
      let (rows, dimension_count) = investment_index_rows_from_body(body)
      (
        load_investment_profit_for(emit, model.investment_project_id),
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
          load_investment_sensitivity_for(emit, model.investment_project_id),
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
    InvestmentSensitivityLoaded(body) => {
      let (loaded, cases, base_irr) = investment_sensitivity_from_body(body)
      (
        load_investment_profit_actual_for(emit, model.investment_project_id),
        {
          ..model,
          investment_sensitivity_loaded: loaded,
          investment_sensitivity_cases: cases,
          investment_sensitivity_note: if loaded {
            "已加载 PostgreSQL 敏感性情景 · 基线 IRR " +
            base_irr +
            "% · 只读观察"
          } else {
            "投资敏感性响应为空 · 使用设计快照"
          },
        },
      )
    }
    InvestmentProfitActualLoaded(body) => {
      let (loaded, code, message, simulation, missing_table_count) = investment_profit_actual_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          investment_actual_loaded: loaded,
          investment_actual_code: code,
          investment_actual_message: message,
          investment_actual_simulation: simulation,
          investment_actual_missing_table_count: missing_table_count,
          investment_actual_note: if code == "41002" {
            "当前项目没有测算利润表 · 源接口明确禁止模拟"
          } else if code == "41003" {
            "实际利润模拟需要审批 · 当前仅保留边界"
          } else {
            "实际利润对比源边界 · 仅读观察"
          },
        },
      )
    }
    InvestmentLoadFailed =>
      (
        none,
        {
          ..model,
          investment_loaded: false,
          investment_version_id: "",
          investment_version_name: "",
          investment_version_rows: [],
          investment_index_rows: [],
          investment_sensitivity_loaded: false,
          investment_sensitivity_cases: [],
          investment_sensitivity_note: "投资敏感性读模型不可用 · 使用设计快照",
          investment_imports_loaded: false,
          investment_import_rows: [],
          investment_import_note: "Excel 导入历史读模型不可用 · 使用设计快照",
          investment_import_selected: "",
          investment_import_detail_note: "导入详情读模型不可用",
          investment_import_bridge_note: "逻辑桥接读模型不可用",
          investment_import_index_preview_note: "指标 upsert 预览不可用",
          investment_import_profit_note: "利润测算总表不可用",
          investment_import_plan_note: "计划行预览不可用",
          investment_actual_loaded: false,
          investment_actual_code: "",
          investment_actual_message: "实际利润边界不可用",
          investment_actual_simulation: "false",
          investment_actual_missing_table_count: "0",
          investment_actual_note: "实际利润源边界不可用 · 保持审批边界",
          investment_note: "投资测算读模型不可用 · 使用设计快照",
          investment_explain_note: "解释候选不可用 · provider/LLM 保持关闭",
          investment_explain_text: "投资解释候选不可用",
        },
      )
    ExplainInvestment =>
      (
        issue_investment_explain(emit, model),
        {
          ..model,
          investment_explain_note: "正在生成确定性投资解释 · 不调用 provider/LLM…",
        },
      )
    InvestmentExplainFinished(body) =>
      (
        none,
        {
          ..model,
          investment_explain_note: if body.contains(
              "\"provider\":\"native-deterministic\"",
            ) {
            "投资解释候选已生成 · native-deterministic · 不持久化、不授权"
          } else {
            "投资解释候选响应已返回 · provider/LLM 未执行"
          },
          investment_explain_text: investment_explain_text_from_body(body),
        },
      )
    InvestmentExplainFailed =>
      (
        none,
        {
          ..model,
          investment_explain_note: "投资解释候选不可用 · provider/LLM 保持关闭",
          investment_explain_text: "投资解释候选不可用",
        },
      )
    InputInvestmentExcelFileSelected(value) =>
      (
        none,
        {
          ..model,
          investment_excel_file_name: value,
          investment_excel_version_name: if model.investment_excel_version_name.is_empty() {
            if value.is_empty() {
              ""
            } else {
              "Excel 导入版 · " + value
            }
          } else {
            model.investment_excel_version_name
          },
          investment_upload_note: if value.is_empty() {
            "尚未选择 Excel 工作簿"
          } else {
            "已选择 " +
            value +
            " · 仍需二进制解析与投资负责人授权"
          },
        },
      )
    InputInvestmentExcelVersionName(value) =>
      (none, { ..model, investment_excel_version_name: value })
    ToggleInvestmentExcelActivate =>
      (
        none,
        { ..model, investment_excel_activate: !model.investment_excel_activate },
      )
    RequestInvestmentExcelUpload =>
      if model.investment_excel_file_name.trim().is_empty() {
        (
          none,
          { ..model, investment_upload_note: "请先选择 .xlsx 工作簿" },
        )
      } else {
        (
          issue_investment_excel_upload(emit, model),
          {
            ..model,
            investment_upload_note: "正在检查 Excel 工作簿上传边界 · 不读取二进制、不写入导入记录…",
          },
        )
      }
    InvestmentExcelUploadFinished(body) =>
      (
        none,
        {
          ..model,
          investment_upload_note: if body.contains("\"code\":46005") {
            "Excel 上传候选已验证 · 需要二进制解析与投资负责人确认 · 未导入工作簿"
          } else {
            "Excel 上传候选响应已返回 · 未写入投资源"
          },
        },
      )
    InvestmentExcelUploadFailed =>
      (
        none,
        {
          ..model,
          investment_upload_note: "Excel 上传候选服务不可用或被网关拒绝",
        },
      )
    RequestInvestmentSubjectMappings =>
      (
        issue_investment_subject_mappings(emit, model),
        {
          ..model,
          investment_mapping_note: "正在检查科目映射边界 · 不写入投资主数据、不触发估值…",
        },
      )
    InvestmentSubjectMappingsFinished(body) =>
      (
        none,
        {
          ..model,
          investment_mapping_note: if body.contains("\"wouldUpdate\"") {
            "科目映射候选已返回 · 仅 dry-run 预览 · 未写入投资主数据"
          } else if body.contains("\"code\":46003") {
            "科目映射候选已验证 · 需要投资负责人确认 · 未写入"
          } else {
            "科目映射候选响应已返回 · 未写入投资主数据"
          },
        },
      )
    InvestmentSubjectMappingsFailed =>
      (
        none,
        {
          ..model,
          investment_mapping_note: "科目映射候选服务不可用或被网关拒绝",
        },
      )
    RequestInvestmentPlanLineUpdate =>
      (
        issue_investment_plan_line_update(emit),
        {
          ..model,
          investment_plan_line_note: "正在检查计划行编辑边界 · 不写入计划、不触发估值…",
        },
      )
    InvestmentPlanLineUpdateFinished(body) =>
      (
        none,
        {
          ..model,
          investment_plan_line_note: if body.contains("\"wouldUpdate\":true") {
            "计划行编辑候选已返回 · 仅 dry-run 预览 · 未写入投资计划"
          } else if body.contains("\"code\":43001") {
            "计划行编辑候选已验证 · 当前计划行源记录不存在 · 未写入"
          } else if body.contains("\"code\":46004") {
            "计划行编辑候选已验证 · 需要投资负责人确认 · 未写入"
          } else {
            "计划行编辑候选响应已返回 · 未写入投资计划"
          },
        },
      )
    InvestmentPlanLineUpdateFailed =>
      (
        none,
        {
          ..model,
          investment_plan_line_note: "计划行编辑候选服务不可用或被网关拒绝",
        },
      )
    RequestInvestmentIndexUpsert =>
      (
        issue_investment_index_upsert(emit, model),
        {
          ..model,
          investment_index_upsert_note: "正在检查 Excel 指标 upsert 边界 · 不写入指标、不触发估值…",
        },
      )
    InvestmentIndexUpsertFinished(body) =>
      (
        none,
        {
          ..model,
          investment_index_upsert_note: if body.contains("\"wouldInsert\"") {
            "Excel 指标 upsert 候选已返回 · 仅 dry-run 预览 · 未写入指标"
          } else if body.contains("\"code\":43001") {
            "Excel 指标 upsert 候选已验证 · 当前导入记录不存在 · 未写入"
          } else if body.contains("\"code\":46001") {
            "Excel 指标 upsert 候选已验证 · 需要投资负责人确认 · 未写入"
          } else {
            "Excel 指标 upsert 候选响应已返回 · 未写入指标"
          },
        },
      )
    InvestmentIndexUpsertFailed =>
      (
        none,
        {
          ..model,
          investment_index_upsert_note: "Excel 指标 upsert 候选服务不可用或被网关拒绝",
        },
      )
    RequestInvestmentPlanLineImport =>
      (
        issue_investment_plan_line_import(emit, model),
        {
          ..model,
          investment_plan_line_import_note: "正在检查 Excel 计划行导入边界 · 不解析二进制、不写入计划…",
        },
      )
    InvestmentPlanLineImportFinished(body) =>
      (
        none,
        {
          ..model,
          investment_plan_line_import_note: if body.contains("\"wouldInsert\"") {
            "Excel 计划行导入候选已返回 · 仅 dry-run 预览 · 未写入计划"
          } else if body.contains("\"code\":43001") {
            "Excel 计划行导入候选已验证 · 当前导入记录不存在 · 未写入"
          } else if body.contains("\"code\":46002") {
            "Excel 计划行导入候选已验证 · 需要投资负责人确认 · 未写入"
          } else {
            "Excel 计划行导入候选响应已返回 · 未写入计划"
          },
        },
      )
    InvestmentPlanLineImportFailed =>
      (
        none,
        {
          ..model,
          investment_plan_line_import_note: "Excel 计划行导入候选服务不可用或被网关拒绝",
        },
      )
    RequestInvestmentVersionCreate =>
      if model.investment_new_version_name.trim().is_empty() {
        (none, { ..model, investment_command_note: "请先填写版本名称" })
      } else {
        (
          issue_investment_command(emit, model, "version_create"),
          {
            ..model,
            investment_command_note: "正在创建本地投资版本候选 · 不改变导入版本…",
          },
        )
      }
    RequestInvestmentVersionActivate =>
      (
        issue_investment_command(emit, model, "version_activate"),
        {
          ..model,
          investment_command_note: "正在激活本地投资版本候选 · 不触发估值/资金…",
        },
      )
    RequestInvestmentVersionDelete =>
      (
        issue_investment_command(emit, model, "version_delete"),
        {
          ..model,
          investment_command_note: "正在删除本地投资版本候选 · 导入版本保持只读…",
        },
      )
    RequestInvestmentIndexCreate =>
      if model.investment_new_index_full_code.trim().is_empty() ||
        model.investment_new_index_name.trim().is_empty() {
        (
          none,
          {
            ..model,
            investment_command_note: "请先填写指标编码和名称",
          },
        )
      } else {
        (
          issue_investment_command(emit, model, "index_create"),
          {
            ..model,
            investment_command_note: "正在创建本地投资指标候选 · 不触发估值…",
          },
        )
      }
    RequestInvestmentIndexUpdate =>
      (
        issue_investment_command(emit, model, "index_update"),
        {
          ..model,
          investment_command_note: "正在更新本地投资指标候选 · 导入指标保持只读…",
        },
      )
    RequestInvestmentIndexDelete =>
      (
        issue_investment_command(emit, model, "index_delete"),
        {
          ..model,
          investment_command_note: "正在删除本地投资指标候选 · 导入指标保持只读…",
        },
      )
    InvestmentCommandFinished(command_type, body) =>
      (
        @cmd.batch([
          load_investment_versions_for(emit, model.investment_project_id),
          load_investment_imports_for(emit, model.investment_project_id),
        ]),
        {
          ..model,
          investment_command_note: if body.contains("\"persisted\":true") {
            "投资 " +
            command_type +
            " 候选已持久化 · cash/accounting/tax/provider 均未执行"
          } else {
            "投资 " +
            command_type +
            " 候选已返回 · 请复核执行边界"
          },
        },
      )
    InvestmentCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          investment_command_note: "投资 " +
          command_type +
          " 服务不可用或被网关拒绝",
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
    InputDynamicCostProject(value) =>
      (
        load_dynamic_cost(emit, value),
        {
          ..model,
          dynamic_cost_project_id: value,
          dynamic_cost_remark_loaded: false,
          dynamic_cost_remark_note: "项目范围已切换 · 点击成本 A / B / H 查看科目备注",
        },
      )
    ViewDynamicCostRemarks(cost_id) =>
      if cost_id.trim().is_empty() {
        (
          none,
          { ..model, dynamic_cost_remark_note: "成本科目缺少 costGuid" },
        )
      } else {
        (
          load_dynamic_cost_remarks(emit, cost_id),
          { ..model, dynamic_cost_remark_note: "正在读取科目备注…" },
        )
      }
    DynamicCostRemarksLoaded(body) => {
      let values = dynamic_cost_remarks_from_body(body)
      if values.length() == 5 {
        (
          none,
          {
            ..model,
            dynamic_cost_remark_loaded: true,
            dynamic_cost_remark_code: values[0],
            dynamic_cost_remark_name: values[1],
            dynamic_cost_remark_text: values[2],
            dynamic_cost_remark_project: values[3],
            dynamic_cost_remark_source: values[4],
            dynamic_cost_remark_note: "备注读模型已连接 · 不产生写入或财务效果",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            dynamic_cost_remark_loaded: false,
            dynamic_cost_remark_note: "科目备注响应无效",
          },
        )
      }
    }
    DynamicCostRemarksLoadFailed =>
      (
        none,
        {
          ..model,
          dynamic_cost_remark_loaded: false,
          dynamic_cost_remark_note: "科目备注读模型不可用或源科目不存在",
        },
      )
    ExportDynamicCostCsv =>
      (
        {
          download_text(
            dynamic_cost_csv(model),
            "dynamic-cost-" + model.dynamic_cost_project_id + ".csv",
          )
          none
        },
        {
          ..model,
          dynamic_cost_export_note: "CSV 已生成并开始下载 · 仅包含当前项目动态成本",
        },
      )
    ExportDynamicCostXlsx =>
      (
        issue_dynamic_cost_export(emit, model),
        {
          ..model,
          dynamic_cost_export_note: "正在生成动态成本 XLSX 报表…",
        },
      )
    DynamicCostExportFinished(blob) =>
      (
        {
          download_blob(
            blob,
            "dynamic-cost-" + model.dynamic_cost_project_id + ".xlsx",
          )
          none
        },
        {
          ..model,
          dynamic_cost_export_note: "XLSX 已生成并开始下载 · 仅包含当前项目动态成本",
        },
      )
    DynamicCostExportFailed =>
      (
        none,
        {
          ..model,
          dynamic_cost_export_note: "XLSX 导出服务不可用或被网关拒绝",
        },
      )
    InputDynamicCostCreateCode(value) =>
      (none, { ..model, dynamic_cost_create_code: value })
    InputDynamicCostCreateName(value) =>
      (none, { ..model, dynamic_cost_create_name: value })
    InputDynamicCostCreateLevel(value) =>
      (none, { ..model, dynamic_cost_create_level: value })
    InputDynamicCostCreateParent(value) =>
      (none, { ..model, dynamic_cost_create_parent: value })
    InputDynamicCostCreateTarget(value) =>
      (none, { ..model, dynamic_cost_create_target: value })
    InputDynamicCostCreateContractChange(value) =>
      (none, { ..model, dynamic_cost_create_contract_change: value })
    InputDynamicCostCreateInTransit(value) =>
      (none, { ..model, dynamic_cost_create_in_transit: value })
    InputDynamicCostCreateBudget(value) =>
      (none, { ..model, dynamic_cost_create_budget: value })
    InputDynamicCostCreateEstimateChange(value) =>
      (none, { ..model, dynamic_cost_create_estimate_change: value })
    InputDynamicCostCreateRemarks(value) =>
      (none, { ..model, dynamic_cost_create_remarks: value })
    RequestDynamicCostCreate =>
      if model.dynamic_cost_create_code.trim().is_empty() ||
        model.dynamic_cost_create_name.trim().is_empty() {
        (
          none,
          {
            ..model,
            dynamic_cost_command_note: "请先填写科目编码和名称",
          },
        )
      } else {
        (
          issue_dynamic_cost_create(emit, model),
          {
            ..model,
            dynamic_cost_command_note: "正在提交成本科目创建候选…",
          },
        )
      }
    DynamicCostCommandFinished(body) =>
      (
        load_dynamic_cost(emit, model.dynamic_cost_project_id),
        {
          ..model,
          dynamic_cost_command_note: if body.contains("\"persisted\":true") {
            "成本科目候选已写入 PostgreSQL 投影 · CBS/预算/现金/会计/税务仍未执行"
          } else {
            "成本科目候选已返回 · 请复核 owner 边界"
          },
        },
      )
    DynamicCostCommandFailed =>
      (
        none,
        {
          ..model,
          dynamic_cost_command_note: "成本科目命令服务不可用或被权限/源状态拒绝",
        },
      )
    CostDashboardLoaded(body) => {
      let (loaded, rows, summary, note) = cost_dashboard_from_body(body)
      if loaded && summary.length() == 8 {
        (
          none,
          {
            ..model,
            cost_dashboard_loaded: true,
            cost_dashboard_rows: rows,
            cost_dashboard_project_name: summary[0],
            cost_dashboard_plan_version: summary[1],
            cost_dashboard_target: summary[2],
            cost_dashboard_dynamic: summary[3],
            cost_dashboard_deviation: summary[4],
            cost_dashboard_contract_count: summary[5],
            cost_dashboard_expense_count: summary[6],
            cost_dashboard_change_count: summary[7],
            cost_dashboard_note: note,
          },
        )
      } else {
        (
          none,
          {
            ..model,
            cost_dashboard_loaded: false,
            cost_dashboard_rows: [],
            cost_dashboard_note: "成本驾驶舱响应无效 · 使用设计快照",
          },
        )
      }
    }
    CostDashboardLoadFailed =>
      (
        none,
        {
          ..model,
          cost_dashboard_loaded: false,
          cost_dashboard_rows: [],
          cost_dashboard_note: "成本驾驶舱源读模型不可用 · 使用设计快照",
        },
      )
    CashflowLoaded(body) => {
      let (rows, totals, missing_table_count) = cashflow_from_body(body)
      if totals.length() == 6 {
        (
          load_cashflow_inflow(emit),
          {
            ..model,
            cashflow_loaded: true,
            cashflow_rows: rows,
            cashflow_planned_total: totals[0],
            cashflow_pending_total: totals[1],
            cashflow_confirmed_total: totals[2],
            cashflow_expense_total: totals[3],
            cashflow_loan_total: totals[4],
            cashflow_total_outflow: totals[5],
            cashflow_missing_table_count: missing_table_count,
            cashflow_note: "已加载 PostgreSQL 现金流预测 · 源计划/申请保持只读",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            cashflow_loaded: false,
            cashflow_rows: [],
            cashflow_note: "现金流预测响应无效 · 使用设计快照",
          },
        )
      }
    }
    CashflowLoadFailed =>
      (
        none,
        {
          ..model,
          cashflow_loaded: false,
          cashflow_rows: [],
          cashflow_note: "现金流预测读模型不可用 · 使用设计快照",
        },
      )
    CashflowInflowLoaded(body) => {
      let (loaded, total, missing_table_count, note) = cashflow_inflow_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          cashflow_inflow_loaded: loaded,
          cashflow_inflow_total: total,
          cashflow_inflow_missing_table_count: missing_table_count,
          cashflow_inflow_note: note,
        },
      )
    }
    CashflowInflowLoadFailed =>
      (
        none,
        {
          ..model,
          cashflow_inflow_loaded: false,
          cashflow_inflow_total: "0",
          cashflow_inflow_note: "回款读模型不可用 · 保留空源状态",
        },
      )
    ExplainCashflow =>
      (
        issue_cashflow_explain(emit),
        {
          ..model,
          cashflow_explain_note: "正在生成确定性现金流解释 · 不调用 provider/LLM…",
        },
      )
    CashflowExplainFinished(body) =>
      (
        none,
        {
          ..model,
          cashflow_explain_note: if body.contains(
              "\"provider\":\"native-deterministic\"",
            ) {
            "现金流解释候选已生成 · native-deterministic · 不持久化、不授权"
          } else {
            "现金流解释候选响应已返回 · provider/LLM 未执行"
          },
          cashflow_explain_text: cashflow_explain_text_from_body(body),
        },
      )
    CashflowExplainFailed =>
      (
        none,
        {
          ..model,
          cashflow_explain_note: "现金流解释候选不可用 · provider/LLM 保持关闭",
          cashflow_explain_text: "现金流解释候选不可用",
        },
      )
    CbsLoaded(body) => {
      let (loaded, rows, version, missing_table_count, note) = cbs_from_body(
        body,
      )
      (
        if loaded {
          load_cbs_r0(emit)
        } else {
          none
        },
        {
          ..model,
          cbs_loaded: loaded,
          cbs_rows: rows,
          cbs_plan_version: version,
          cbs_missing_table_count: missing_table_count,
          cbs_note: note,
        },
      )
    }
    CbsLoadFailed =>
      (
        none,
        {
          ..model,
          cbs_loaded: false,
          cbs_rows: [],
          cbs_note: "CBS 读模型不可用 · 使用设计快照",
        },
      )
    CbsR0Loaded(body) => {
      let (loaded, count) = cbs_r0_from_body(body)
      (none, { ..model, cbs_r0_count: if loaded { count } else { "0" } })
    }
    CbsR0LoadFailed => (none, { ..model, cbs_r0_count: "0" })
    FundLoaded(body) => {
      let (loaded, rows, missing_table_count) = fund_from_body(body)
      (
        if loaded {
          load_fund_gap_for(emit, model.fund_project_id)
        } else {
          none
        },
        {
          ..model,
          fund_loaded: loaded,
          fund_rows: rows,
          fund_missing_table_count: missing_table_count,
          fund_note: if loaded {
            "已加载 PostgreSQL 资金计划源读模型 · 计划/调度保持只读 · 空源表 " +
            missing_table_count
          } else {
            "资金计划响应无效 · 使用设计快照"
          },
        },
      )
    }
    FundLoadFailed =>
      (
        none,
        {
          ..model,
          fund_loaded: false,
          fund_rows: [],
          fund_note: "资金计划读模型不可用 · 使用设计快照",
        },
      )
    FundGapLoaded(body) => {
      let (loaded, rows, missing) = fund_gap_from_body(body)
      (
        if loaded {
          load_fund_dispatches(emit)
        } else {
          none
        },
        {
          ..model,
          fund_gap_rows: rows,
          fund_gap_series_count: if loaded {
            rows.length().to_string()
          } else {
            "0"
          },
          fund_missing_table_count: missing,
        },
      )
    }
    FundGapLoadFailed => (none, { ..model, fund_gap_series_count: "0" })
    FundDispatchLoaded(body) => {
      let (loaded, rows, missing) = fund_dispatch_rows_from_body(body)
      (
        none,
        {
          ..model,
          fund_dispatch_rows: rows,
          fund_dispatch_count: if loaded {
            rows.length().to_string()
          } else {
            "0"
          },
          fund_missing_table_count: missing,
        },
      )
    }
    FundDispatchLoadFailed => (none, { ..model, fund_dispatch_count: "0" })
    SelectFundProject(project_id) =>
      (
        load_fund_for(emit, project_id),
        {
          ..model,
          fund_project_id: project_id,
          fund_loaded: false,
          fund_rows: [],
          fund_gap_rows: [],
          fund_dispatch_rows: [],
          fund_note: "正在读取项目资金计划…",
        },
      )
    SelectFundTab(tab) => (none, { ..model, fund_tab: tab })
    OpenFundForm(form) =>
      (
        none,
        {
          ..model,
          fund_form_open: form,
          fund_plan_id: if form == "plan" {
            ""
          } else {
            model.fund_plan_id
          },
        },
      )
    CloseFundForm => (none, { ..model, fund_form_open: "" })
    InputFundField(field, value) =>
      (
        none,
        {
          ..model,
          fund_plan_period: if field == "plan_period" {
            value
          } else {
            model.fund_plan_period
          },
          fund_plan_direction: if field == "plan_direction" {
            value
          } else {
            model.fund_plan_direction
          },
          fund_plan_category: if field == "plan_category" {
            value
          } else {
            model.fund_plan_category
          },
          fund_plan_r_code: if field == "plan_r_code" {
            value
          } else {
            model.fund_plan_r_code
          },
          fund_plan_amount: if field == "plan_amount" {
            value
          } else {
            model.fund_plan_amount
          },
          fund_plan_actual_amount: if field == "actual_amount" {
            value
          } else {
            model.fund_plan_actual_amount
          },
          fund_plan_remark: if field == "plan_remark" {
            value
          } else {
            model.fund_plan_remark
          },
          fund_dispatch_from: if field == "dispatch_from" {
            value
          } else {
            model.fund_dispatch_from
          },
          fund_dispatch_to: if field == "dispatch_to" {
            value
          } else {
            model.fund_dispatch_to
          },
          fund_dispatch_amount: if field == "dispatch_amount" {
            value
          } else {
            model.fund_dispatch_amount
          },
          fund_dispatch_reason: if field == "dispatch_reason" {
            value
          } else {
            model.fund_dispatch_reason
          },
          fund_dispatch_date: if field == "dispatch_date" {
            value
          } else {
            model.fund_dispatch_date
          },
        },
      )
    OpenFundPlanEdit(plan_id) => {
      let mut plan_period = model.fund_plan_period
      let mut direction = model.fund_plan_direction
      let mut category = model.fund_plan_category
      let mut r_code = model.fund_plan_r_code
      let mut amount = model.fund_plan_amount
      let mut actual_amount = model.fund_plan_actual_amount
      let mut remark = model.fund_plan_remark
      for row in model.fund_rows {
        if row.plan_guid == plan_id {
          plan_period = row.plan_period
          direction = row.direction
          category = row.category
          r_code = row.r_code
          amount = row.plan_amount
          actual_amount = row.actual_amount
          remark = row.remark
        }
      }
      (
        none,
        {
          ..model,
          fund_plan_id: plan_id,
          fund_form_open: "plan",
          fund_plan_period: plan_period,
          fund_plan_direction: direction,
          fund_plan_category: category,
          fund_plan_r_code: r_code,
          fund_plan_amount: amount,
          fund_plan_actual_amount: actual_amount,
          fund_plan_remark: remark,
        },
      )
    }
    DeleteFundPlanRow(plan_id) =>
      if plan_id.is_empty() {
        (none, model)
      } else {
        let selected = { ..model, fund_plan_id: plan_id }
        (
          issue_fund_command(emit, selected, "delete_plan"),
          {
            ..selected,
            fund_command_state: "pending",
            fund_command_note: "正在作废资金计划草稿…",
          },
        )
      }
    SelectFundDispatch(dispatch_id) =>
      if dispatch_id.is_empty() {
        (none, model)
      } else {
        let selected = { ..model, fund_dispatch_id: dispatch_id }
        (
          issue_fund_command(emit, selected, "approve_dispatch"),
          {
            ..selected,
            fund_command_state: "pending",
            fund_command_note: "正在审批资金调度申请…",
          },
        )
      }
    CreateFundPlan =>
      if model.fund_plan_id != "" {
        (
          issue_fund_command(emit, model, "update_plan"),
          {
            ..model,
            fund_form_open: "",
            fund_command_state: "pending",
            fund_command_note: "正在更新资金计划草稿…",
          },
        )
      } else {
        (
          issue_fund_command(emit, model, "create_plan"),
          {
            ..model,
            fund_form_open: "",
            fund_command_state: "pending",
            fund_command_note: "正在创建资金计划草稿…",
          },
        )
      }
    UpdateFundPlan =>
      if model.fund_plan_id == "" || model.fund_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_fund_command(emit, model, "update_plan"),
          {
            ..model,
            fund_form_open: "",
            fund_command_state: "pending",
            fund_command_note: "正在更新资金计划草稿…",
          },
        )
      }
    DeleteFundPlan =>
      if model.fund_plan_id == "" || model.fund_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_fund_command(emit, model, "delete_plan"),
          {
            ..model,
            fund_form_open: "",
            fund_command_state: "pending",
            fund_command_note: "正在作废资金计划草稿…",
          },
        )
      }
    CreateFundDispatch =>
      if model.fund_dispatch_id != "" {
        (none, model)
      } else {
        (
          issue_fund_command(emit, model, "create_dispatch"),
          {
            ..model,
            fund_form_open: "",
            fund_command_state: "pending",
            fund_command_note: "正在创建资金调度申请…",
          },
        )
      }
    ApproveFundDispatch =>
      if model.fund_dispatch_id == "" || model.fund_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_fund_command(emit, model, "approve_dispatch"),
          {
            ..model,
            fund_command_state: "pending",
            fund_command_note: "正在审批资金调度申请…",
          },
        )
      }
    FundCommandFinished(body) => {
      let is_plan = body.contains("FP-RABBITA-LOCAL")
      let is_dispatch = body.contains("FD-RABBITA-LOCAL")
      let next_state = if body.contains("\"state\":\"planned\"") {
        "planned"
      } else if body.contains("\"state\":\"updated\"") {
        "updated"
      } else if body.contains("\"state\":\"deleted\"") {
        "deleted"
      } else if body.contains("\"state\":\"pending\"") {
        "pending"
      } else if body.contains("\"state\":\"approved\"") {
        "approved"
      } else {
        "error"
      }
      if next_state == "error" {
        (
          none,
          { ..model, fund_command_state: "error", fund_command_note: body },
        )
      } else {
        (
          load_fund_for(emit, model.fund_project_id),
          {
            ..model,
            fund_plan_id: if is_plan && next_state == "deleted" {
              ""
            } else if is_plan {
              "FP-RABBITA-LOCAL"
            } else {
              model.fund_plan_id
            },
            fund_dispatch_id: if is_dispatch {
              "FD-RABBITA-LOCAL"
            } else {
              model.fund_dispatch_id
            },
            fund_command_state: next_state,
            fund_command_note: "已写入 PostgreSQL 资金命令投影 · 现金/会计/税务仍未触发",
          },
        )
      }
    }
    FundCommandFailed =>
      (
        none,
        {
          ..model,
          fund_command_state: "error",
          fund_command_note: "资金命令请求失败 · 保持源记录只读",
        },
      )
    WarningsLoaded(body) => {
      let (loaded, rows, missing_table_count) = warnings_from_body(body)
      (
        if loaded {
          load_warning_rules(emit)
        } else {
          none
        },
        {
          ..model,
          warnings_loaded: loaded,
          warning_rows: rows,
          warning_action_guid: if rows.length() > 0 {
            rows[0].warning_guid
          } else {
            ""
          },
          warning_missing_table_count: missing_table_count,
          warning_note: if loaded {
            "已加载 PostgreSQL 观察型预警 · 不写入目标告警/工单 · 空源表 " +
            missing_table_count
          } else {
            "预警响应无效 · 使用设计快照"
          },
        },
      )
    }
    WarningsLoadFailed =>
      (
        none,
        {
          ..model,
          warnings_loaded: false,
          warning_rows: [],
          warning_action_guid: "",
          warning_note: "预警读模型不可用 · 使用设计快照",
        },
      )
    WarningRulesLoaded(body) => {
      let (loaded, count) = warning_rules_count_from_body(body)
      (none, { ..model, warning_rule_count: if loaded { count } else { "0" } })
    }
    WarningRulesLoadFailed => (none, { ..model, warning_rule_count: "0" })
    ResolveWarning =>
      if model.warning_action_guid == "" ||
        model.warning_action_state == "pending" {
        (none, model)
      } else {
        (
          issue_warning_command(emit, model, "resolve"),
          {
            ..model,
            warning_action_state: "pending",
            warning_action_note: "正在写入告警处理命令…",
          },
        )
      }
    IgnoreWarning =>
      if model.warning_action_guid == "" ||
        model.warning_action_state == "pending" {
        (none, model)
      } else {
        (
          issue_warning_command(emit, model, "ignore"),
          {
            ..model,
            warning_action_state: "pending",
            warning_action_note: "正在写入告警忽略命令…",
          },
        )
      }
    WarningCommandFinished(body) => {
      let (loaded, state, guid, note) = warning_command_from_body(body)
      (
        if loaded {
          load_warnings(emit)
        } else {
          none
        },
        {
          ..model,
          warning_action_state: if loaded {
            state
          } else {
            "error"
          },
          warning_action_guid: if loaded {
            guid
          } else {
            model.warning_action_guid
          },
          warning_action_note: note,
        },
      )
    }
    WarningCommandFailed =>
      (
        none,
        {
          ..model,
          warning_action_state: "error",
          warning_action_note: "告警处理命令服务不可用或拒绝了请求",
        },
      )
    PreviewWarningScan =>
      (
        issue_warning_scan_preview(emit),
        {
          ..model,
          warning_note: "正在运行预警扫描预览 · 不写入告警、不发送通知…",
        },
      )
    WarningScanPreviewFinished(body) =>
      (
        if body.contains("\"dryRun\":true") {
          load_warnings(emit)
        } else {
          none
        },
        {
          ..model,
          warning_note: if body.contains("\"persisted\":false") &&
            body.contains("\"notificationsSent\":0") {
            "预警扫描预览已返回 · 不写入、不发送通知、不调用 provider"
          } else {
            "预警扫描候选已返回 · 请复核执行边界"
          },
        },
      )
    WarningScanPreviewFailed =>
      (
        none,
        {
          ..model,
          warning_note: "预警扫描预览服务不可用或被网关拒绝",
        },
      )
    PreviewWarningCustomRule =>
      (
        issue_warning_custom_rule_preview(emit),
        {
          ..model,
          warning_rule_preview_note: "正在检查自定义规则 SQL 预览边界…",
        },
      )
    WarningCustomRulePreviewFinished(body) =>
      (
        none,
        {
          ..model,
          warning_rule_preview_note: if body.contains(
              "\"queryExecution\":false",
            ) &&
            body.contains("\"persisted\":false") {
            "自定义规则预览已返回 · SQL 已摘要化 · 不执行查询、不持久化"
          } else {
            "自定义规则预览已返回 · 请复核查询边界"
          },
        },
      )
    WarningCustomRulePreviewFailed =>
      (
        none,
        {
          ..model,
          warning_rule_preview_note: "自定义规则预览服务不可用或被网关拒绝",
        },
      )
    CreateWarningCustomRule =>
      (
        issue_warning_custom_rule_command(emit, true),
        {
          ..model,
          warning_rule_command_note: "正在创建本地自定义规则候选…",
        },
      )
    DeleteWarningCustomRule =>
      (
        issue_warning_custom_rule_command(emit, false),
        {
          ..model,
          warning_rule_command_note: "正在删除本地自定义规则候选…",
        },
      )
    WarningCustomRuleCommandFinished(body) =>
      (
        load_warning_rules(emit),
        {
          ..model,
          warning_rule_command_note: if body.contains("\"state\":\"deleted\"") {
            "本地自定义规则已删除 · 已写入命令与审计投影"
          } else {
            "本地自定义规则已创建 · SQL 仅保存摘要，不执行查询"
          },
        },
      )
    WarningCustomRuleCommandFailed =>
      (
        none,
        {
          ..model,
          warning_rule_command_note: "自定义规则命令服务不可用或被网关拒绝",
        },
      )
    CreateWarningTicket =>
      (
        issue_warning_ticket_command(emit, model, "create"),
        {
          ..model,
          warning_ticket_note: "正在创建本地告警工单候选 · 不发送通知或 webhook…",
        },
      )
    HandleWarningTicket =>
      (
        issue_warning_ticket_command(emit, model, "handling"),
        {
          ..model,
          warning_ticket_note: "正在推进本地工单处理候选 · 仅写入工单投影…",
        },
      )
    CompleteWarningTicket =>
      (
        issue_warning_ticket_command(emit, model, "done"),
        {
          ..model,
          warning_ticket_note: "正在完成本地工单候选 · 告警解析仅写入本地状态…",
        },
      )
    ReassignWarningTicket =>
      (
        issue_warning_ticket_command(emit, model, "reassign"),
        {
          ..model,
          warning_ticket_note: "正在转派本地工单候选 · 不触发外部通知…",
        },
      )
    ExtendWarningTicket =>
      (
        issue_warning_ticket_command(emit, model, "extend"),
        {
          ..model,
          warning_ticket_note: "正在延期本地工单候选 · 仅更新 due date…",
        },
      )
    WarningTicketCommandFinished(command_type, body) =>
      (
        load_warnings(emit),
        {
          ..model,
          warning_ticket_note: if body.contains("\"persisted\":true") {
            "告警工单 " +
            command_type +
            " 候选已持久化 · notification/webhook/cash/accounting/tax 均未执行"
          } else {
            "告警工单 " +
            command_type +
            " 候选已返回 · 请复核执行边界"
          },
        },
      )
    WarningTicketCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          warning_ticket_note: "告警工单 " +
          command_type +
          " 服务不可用或被网关拒绝",
        },
      )
    AttachmentsLoaded(body) => {
      let (loaded, rows, total, missing) = attachments_from_body(body)
      (
        if loaded {
          load_attachment_stats(emit)
        } else {
          none
        },
        {
          ..model,
          attachments_loaded: loaded,
          attachment_rows: rows,
          attachment_action_guid: if rows.length() > 0 {
            rows[0].att_guid
          } else {
            model.attachment_action_guid
          },
          attachment_total: total,
          attachment_missing_table_count: missing,
          attachment_note: if loaded {
            "已加载 PostgreSQL 附件源读模型 · 不含二进制文件 · 空源表 " +
            missing
          } else {
            "附件响应无效 · 使用设计快照"
          },
        },
      )
    }
    AttachmentsLoadFailed =>
      (
        none,
        {
          ..model,
          attachments_loaded: false,
          attachment_rows: [],
          attachment_note: "附件源读模型不可用 · 使用设计快照",
        },
      )
    AttachmentStatsLoaded(body) => {
      let (loaded, total, bytes, pending, missing) = attachment_stats_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          attachment_total: if loaded {
            total
          } else {
            model.attachment_total
          },
          attachment_bytes: if loaded {
            bytes
          } else {
            model.attachment_bytes
          },
          attachment_pending: if loaded {
            pending
          } else {
            model.attachment_pending
          },
          attachment_missing_table_count: if loaded {
            missing
          } else {
            model.attachment_missing_table_count
          },
          attachment_note: if loaded {
            "已加载 PostgreSQL 附件统计 · 不含二进制文件 · 空源表 " +
            missing
          } else {
            "附件统计不可用 · 保留已加载附件源状态"
          },
        },
      )
    }
    AttachmentStatsLoadFailed =>
      (
        none,
        {
          ..model,
          attachment_note: "附件统计不可用 · 保留已加载附件源状态",
        },
      )
    RequestAttachmentUpload =>
      if model.attachment_file_name.trim().is_empty() {
        (none, { ..model, attachment_note: "请先选择文件" })
      } else {
        (
          issue_attachment_upload(emit, model),
          { ..model, attachment_note: "正在检查附件上传边界…" },
        )
      }
    AttachmentCommandFinished(body) =>
      (
        none,
        {
          ..model,
          attachment_note: if body.contains("\"multipartAccepted\":false") {
            "上传候选已到达 native 服务 · 当前不接受 multipart · 对象存储与负责人确认仍待完成"
          } else {
            "附件命令候选已返回 · 保持二进制与外部存储边界"
          },
        },
      )
    AttachmentCommandFailed =>
      (
        none,
        {
          ..model,
          attachment_note: "附件上传候选服务不可用或被网关拒绝",
        },
      )
    RequestAttachmentDownload =>
      (
        issue_attachment_download(emit, model),
        {
          ..model,
          attachment_download_note: "正在检查附件下载边界 · 不读取二进制…",
        },
      )
    AttachmentDownloadFinished(body) =>
      (
        none,
        {
          ..model,
          attachment_download_note: if body.contains(
              "\"binary_storage\":\"not_imported\"",
            ) {
            "附件下载已到达 source-404 边界 · binary storage 未迁移 · 不返回字节"
          } else {
            "附件下载候选已返回 · 请复核二进制所有权边界"
          },
        },
      )
    AttachmentDownloadFailed =>
      (
        none,
        {
          ..model,
          attachment_download_note: "附件下载服务不可用或被网关拒绝",
        },
      )
    RequestAttachmentReextract =>
      (
        issue_attachment_reextract(emit, model),
        {
          ..model,
          attachment_action_note: "正在检查 OCR 重提取边界 · 不读取二进制、不调用 OCR…",
        },
      )
    AttachmentReextractFinished(body) =>
      (
        none,
        {
          ..model,
          attachment_action_note: if body.contains("\"wouldReExtract\":true") {
            "OCR 重提取候选已返回 · provider/OCR 未执行 · 不持久化元数据"
          } else if body.contains("\"code\":43001") {
            "OCR 重提取候选已验证 · 当前附件源不存在 · 不执行 provider/OCR"
          } else {
            "OCR 重提取候选响应已返回 · provider/OCR 未执行"
          },
        },
      )
    AttachmentReextractFailed =>
      (
        none,
        {
          ..model,
          attachment_action_note: "OCR 重提取候选服务不可用或被网关拒绝",
        },
      )
    RequestAttachmentDelete =>
      (
        issue_attachment_delete(emit, model),
        {
          ..model,
          attachment_delete_note: "正在检查附件删除边界 · 不删除二进制、不写入元数据…",
        },
      )
    AttachmentDeleteFinished(body) =>
      (
        none,
        {
          ..model,
          attachment_delete_note: if body.contains("\"code\":43003") {
            "附件删除候选已验证 · 需要对象存储所有权与负责人确认 · 未执行删除"
          } else {
            "附件删除候选响应已返回 · 未执行删除"
          },
        },
      )
    AttachmentDeleteFailed =>
      (
        none,
        {
          ..model,
          attachment_delete_note: "附件删除候选服务不可用或被网关拒绝",
        },
      )
    MarketingLoaded(family, body) => {
      let (loaded, rows, missing) = marketing_rows_from_body(body, family)
      let command = if !loaded {
        none
      } else if family == "campaigns" {
        load_marketing_for(emit, "placements", model.marketing_project_id)
      } else if family == "placements" {
        load_marketing_for(emit, "channels", model.marketing_project_id)
      } else if family == "channels" {
        load_marketing_for(emit, "materials", model.marketing_project_id)
      } else {
        none
      }
      let next_loaded = if family == "campaigns" {
        loaded
      } else {
        model.marketing_loaded
      }
      (
        command,
        {
          ..model,
          marketing_loaded: next_loaded,
          marketing_campaign_rows: if family == "campaigns" {
            rows
          } else {
            model.marketing_campaign_rows
          },
          marketing_placement_rows: if family == "placements" {
            rows
          } else {
            model.marketing_placement_rows
          },
          marketing_channel_rows: if family == "channels" {
            rows
          } else {
            model.marketing_channel_rows
          },
          marketing_material_rows: if family == "materials" {
            rows
          } else {
            model.marketing_material_rows
          },
          marketing_campaign_count: if family == "campaigns" {
            rows.length().to_string()
          } else {
            model.marketing_campaign_count
          },
          marketing_placement_count: if family == "placements" {
            rows.length().to_string()
          } else {
            model.marketing_placement_count
          },
          marketing_channel_count: if family == "channels" {
            rows.length().to_string()
          } else {
            model.marketing_channel_count
          },
          marketing_material_count: if family == "materials" {
            rows.length().to_string()
          } else {
            model.marketing_material_count
          },
          marketing_missing_table_count: missing,
          marketing_note: if loaded {
            "已加载 PostgreSQL 营销读模型 · 导入行只读 · 本地命令需授权 · 空源表 " +
            missing
          } else {
            "营销 " + family + " 响应无效 · 使用设计快照"
          },
        },
      )
    }
    MarketingLoadFailed(family) =>
      (
        none,
        {
          ..model,
          marketing_loaded: if family == "campaigns" {
            false
          } else {
            model.marketing_loaded
          },
          marketing_note: "营销 " +
          family +
          " 源读模型不可用 · 使用设计快照",
        },
      )
    SelectMarketingProject(project_id) =>
      (
        load_marketing_for(emit, "campaigns", project_id),
        {
          ..model,
          marketing_project_id: project_id,
          marketing_loaded: false,
          marketing_campaign_rows: [],
          marketing_placement_rows: [],
          marketing_channel_rows: [],
          marketing_material_rows: [],
          marketing_note: "正在读取项目营销数据…",
        },
      )
    SelectMarketingTab(tab) => (none, { ..model, marketing_tab: tab })
    OpenMarketingForm(form) => (none, { ..model, marketing_form_open: form })
    CloseMarketingForm => (none, { ..model, marketing_form_open: "" })
    InputMarketingField(field, value) =>
      (
        none,
        {
          ..model,
          marketing_campaign_name: if field == "campaign_name" {
            value
          } else {
            model.marketing_campaign_name
          },
          marketing_campaign_type: if field == "campaign_type" {
            value
          } else {
            model.marketing_campaign_type
          },
          marketing_campaign_budget: if field == "campaign_budget" {
            value
          } else {
            model.marketing_campaign_budget
          },
          marketing_campaign_start: if field == "campaign_start" {
            value
          } else {
            model.marketing_campaign_start
          },
          marketing_campaign_end: if field == "campaign_end" {
            value
          } else {
            model.marketing_campaign_end
          },
          marketing_campaign_goal: if field == "campaign_goal" {
            value
          } else {
            model.marketing_campaign_goal
          },
          marketing_campaign_remark: if field == "campaign_remark" {
            value
          } else {
            model.marketing_campaign_remark
          },
          marketing_placement_campaign: if field == "placement_campaign" {
            value
          } else {
            model.marketing_placement_campaign
          },
          marketing_placement_channel: if field == "placement_channel" {
            value
          } else {
            model.marketing_placement_channel
          },
          marketing_placement_channel_name: if field == "placement_channel_name" {
            value
          } else {
            model.marketing_placement_channel_name
          },
          marketing_placement_amount: if field == "placement_amount" {
            value
          } else {
            model.marketing_placement_amount
          },
          marketing_placement_date: if field == "placement_date" {
            value
          } else {
            model.marketing_placement_date
          },
          marketing_placement_duration: if field == "placement_duration" {
            value
          } else {
            model.marketing_placement_duration
          },
          marketing_channel_name: if field == "channel_name" {
            value
          } else {
            model.marketing_channel_name
          },
          marketing_channel_type: if field == "channel_type" {
            value
          } else {
            model.marketing_channel_type
          },
          marketing_channel_contact: if field == "channel_contact" {
            value
          } else {
            model.marketing_channel_contact
          },
          marketing_channel_phone: if field == "channel_phone" {
            value
          } else {
            model.marketing_channel_phone
          },
          marketing_material_name: if field == "material_name" {
            value
          } else {
            model.marketing_material_name
          },
          marketing_material_type: if field == "material_type" {
            value
          } else {
            model.marketing_material_type
          },
          marketing_material_unit_cost: if field == "material_unit_cost" {
            value
          } else {
            model.marketing_material_unit_cost
          },
          marketing_material_quantity: if field == "material_quantity" {
            value
          } else {
            model.marketing_material_quantity
          },
        },
      )
    CreateMarketingCampaign =>
      (
        issue_marketing_campaign_create(emit, model),
        {
          ..model,
          marketing_form_open: "",
          marketing_note: "正在写入本地营销活动命令…",
        },
      )
    DeleteMarketingCampaign(campaign_id) =>
      if campaign_id.is_empty() {
        (none, model)
      } else {
        (
          issue_marketing_campaign_delete(emit, campaign_id),
          { ..model, marketing_note: "正在作废本地营销活动命令…" },
        )
      }
    CreateMarketingPlacement =>
      (
        issue_marketing_placement_create(emit, model),
        {
          ..model,
          marketing_form_open: "",
          marketing_note: "正在写入本地投放命令…",
        },
      )
    CreateMarketingChannel =>
      (
        issue_marketing_channel_create(emit, model),
        {
          ..model,
          marketing_form_open: "",
          marketing_note: "正在写入本地渠道命令…",
        },
      )
    CreateMarketingMaterial =>
      (
        issue_marketing_material_create(emit, model),
        {
          ..model,
          marketing_form_open: "",
          marketing_note: "正在写入本地物料命令…",
        },
      )
    MarketingCommandFinished(body) =>
      (
        if body.contains("\"campaign\"") ||
          body.contains("\"placement\"") ||
          body.contains("\"channel\"") ||
          body.contains("\"material\"") {
          load_marketing_for(emit, "campaigns", model.marketing_project_id)
        } else {
          none
        },
        {
          ..model,
          marketing_note: if body.contains("\"state\":\"planning\"") {
            "营销活动命令已写入 PostgreSQL · 导入源行仍只读 · 无 provider/预算扣减"
          } else {
            "营销活动命令已返回 · 请复核响应边界"
          },
        },
      )
    MarketingCommandFailed =>
      (
        none,
        {
          ..model,
          marketing_note: "营销活动命令服务不可用或被网关拒绝",
        },
      )
    InboxLoaded(body) => {
      let (loaded, rows, total, missing) = inbox_from_body(body)
      (
        if loaded {
          load_inbox_unread(emit)
        } else {
          none
        },
        {
          ..model,
          inbox_loaded: loaded,
          inbox_rows: rows,
          inbox_total: if loaded {
            total
          } else {
            "0"
          },
          inbox_missing_table_count: missing,
          inbox_note: if loaded {
            "已加载 PostgreSQL 通知消息 · 仅只读源记录 · 空源表 " +
            missing
          } else {
            "通知消息响应无效 · 使用设计快照"
          },
        },
      )
    }
    InboxLoadFailed =>
      (
        none,
        {
          ..model,
          inbox_loaded: false,
          inbox_rows: [],
          inbox_note: "通知消息读模型不可用 · 使用设计快照",
        },
      )
    InboxUnreadLoaded(body) => {
      let (loaded, count) = inbox_unread_from_body(body)
      (
        none,
        {
          ..model,
          inbox_unread: if loaded {
            count
          } else {
            model.inbox_unread
          },
          inbox_note: if loaded {
            model.inbox_note
          } else {
            "通知未读统计不可用 · 保留消息源状态"
          },
        },
      )
    }
    InboxUnreadLoadFailed =>
      (
        none,
        {
          ..model,
          inbox_note: "通知未读统计不可用 · 保留消息源状态",
        },
      )
    MarkInboxReadAll =>
      (
        mark_inbox_read_all(emit),
        { ..model, inbox_note: "正在写入全部已读命令…" },
      )
    InboxCommandFinished(body) =>
      (
        if body.contains("\"state\":\"read\"") {
          load_inbox(emit)
        } else {
          none
        },
        {
          ..model,
          inbox_note: if body.contains("\"delivery_effect\":false") {
            "已写入本地全部已读投影 · 不发送通知、不调用 provider"
          } else {
            "通知命令已返回 · 保持本地只读/无投递边界"
          },
        },
      )
    InboxCommandFailed =>
      (
        none,
        {
          ..model,
          inbox_note: "全部已读命令服务不可用或被网关拒绝",
        },
      )
    NotifySubscriptionsLoaded(body) => {
      let (loaded, rows, missing) = notify_subscriptions_from_body(body)
      (
        if loaded {
          load_notify(emit, "config")
        } else {
          none
        },
        {
          ..model,
          notify_loaded: loaded,
          notify_subscription_rows: rows,
          notify_subscription_count: if loaded {
            rows.length().to_string()
          } else {
            "0"
          },
          notify_missing_table_count: missing,
          notify_note: if loaded {
            "已加载 PostgreSQL 通知订阅 · 仅只读源记录 · 空源表 " +
            missing
          } else {
            "通知订阅响应无效 · 使用设计快照"
          },
        },
      )
    }
    CreateNotifySubscription =>
      (
        issue_notify_subscription_create(emit),
        { ..model, notify_note: "正在写入本地通知订阅命令…" },
      )
    NotifyCommandFinished(body) =>
      (
        if body.contains("\"subId\"") {
          load_notify(emit, "subscriptions")
        } else {
          none
        },
        {
          ..model,
          notify_note: if body.contains("\"delivery_effect\":false") {
            "通知订阅命令已写入 PostgreSQL · 不发送通知、不调用 provider"
          } else {
            "通知订阅命令已返回 · 请复核响应边界"
          },
        },
      )
    NotifyCommandFailed =>
      (
        none,
        {
          ..model,
          notify_note: "通知订阅命令服务不可用或被网关拒绝",
        },
      )
    DispatchNotifyDigest =>
      (
        issue_notify_digest_dispatch(emit),
        { ..model, notify_note: "正在检查通知摘要派发边界…" },
      )
    NotifyDigestDispatchFinished(body) =>
      (
        if body.contains("\"dryRun\":true") {
          load_notify(emit, "digest")
        } else {
          none
        },
        {
          ..model,
          notify_note: if body.contains("\"delivery_effect\":false") {
            "通知摘要派发候选已写入本地收据 · dry-run · 不发送、不调用 provider"
          } else {
            "通知摘要派发候选已返回 · 请复核投递边界"
          },
        },
      )
    NotifyDigestDispatchFailed =>
      (
        none,
        {
          ..model,
          notify_note: "通知摘要派发候选服务不可用或被网关拒绝",
        },
      )
    TestNotifyEmail =>
      (
        issue_notify_email_command(emit, "test"),
        {
          ..model,
          notify_email_note: "正在提交邮件测试候选 · 不入队、不发送…",
        },
      )
    RedeliverNotifyEmail =>
      (
        issue_notify_email_command(emit, "redeliver"),
        {
          ..model,
          notify_email_note: "正在提交邮件重投候选 · 不入队、不发送…",
        },
      )
    NotifyEmailCommandFinished(command_type, body) =>
      (
        if command_type == "test" && body.contains("\"dryRun\":true") {
          load_notify(emit, "outbox")
        } else {
          none
        },
        {
          ..model,
          notify_email_note: if body.contains("\"providerExecution\":false") {
            (if command_type == "test" {
              "邮件测试"
            } else {
              "邮件重投"
            }) +
            "候选已记录 · provider/投递未执行 · 收件人已脱敏"
          } else {
            "邮件候选已返回 · 请复核投递边界"
          },
        },
      )
    NotifyEmailCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          notify_email_note: (if command_type == "test" {
            "邮件测试"
          } else {
            "邮件重投"
          }) +
          "被服务、权限或源队列状态拒绝",
        },
      )
    NotifyConfigLoaded(body) => {
      let (loaded, rows, configured, missing) = notify_config_from_body(body)
      (
        if loaded {
          load_notify(emit, "outbox")
        } else {
          none
        },
        {
          ..model,
          notify_config_rows: rows,
          notify_configured_count: if loaded {
            configured
          } else {
            "0"
          },
          notify_missing_table_count: missing,
          notify_note: if loaded {
            "通知配置仅显示已配置键 · 敏感值已隐藏 · 空源表 " +
            missing
          } else {
            "通知配置响应无效 · 使用设计快照"
          },
        },
      )
    }
    NotifyOutboxLoaded(body) => {
      let (loaded, rows, missing) = notify_outbox_from_body(body)
      (
        if loaded {
          load_notify(emit, "preview")
        } else {
          none
        },
        {
          ..model,
          notify_outbox_rows: rows,
          notify_outbox_count: if loaded {
            rows.length().to_string()
          } else {
            "0"
          },
          notify_missing_table_count: missing,
          notify_note: if loaded {
            "通知邮件队列仅显示元数据 · 邮件正文未导入 · 空源表 " +
            missing
          } else {
            "通知邮件队列响应无效 · 使用设计快照"
          },
        },
      )
    }
    NotifyDigestPreviewLoaded(body) => {
      let (loaded, rows, missing) = notify_digest_from_body(body)
      (
        if loaded {
          load_notify(emit, "digest")
        } else {
          none
        },
        {
          ..model,
          notify_digest_rows: rows,
          notify_digest_count: if loaded {
            rows.length().to_string()
          } else {
            "0"
          },
          notify_missing_table_count: missing,
          notify_note: if loaded {
            "通知摘要预览来自开放预警源 · 不触发发送 · 空源表 " +
            missing
          } else {
            "通知摘要预览响应无效 · 使用设计快照"
          },
        },
      )
    }
    NotifyDigestLoaded(body) => {
      let (loaded, rows, missing) = notify_digest_from_body(body)
      (
        if loaded {
          load_notify(emit, "providers")
        } else {
          none
        },
        {
          ..model,
          notify_digest_rows: if loaded {
            rows
          } else {
            model.notify_digest_rows
          },
          notify_digest_count: if loaded {
            rows.length().to_string()
          } else {
            model.notify_digest_count
          },
          notify_missing_table_count: missing,
          notify_note: if loaded {
            "通知摘要日志仅只读 · 不执行投递 · 空源表 " +
            missing
          } else {
            "通知摘要日志响应无效 · 使用设计快照"
          },
        },
      )
    }
    NotifyProvidersLoaded(body) =>
      (
        none,
        {
          ..model,
          notify_note: if body.contains("\"provider_execution\":false") {
            "通知源读取完成 · LLM 提供商仅发现，不执行调用"
          } else {
            "通知源读取完成 · 提供商执行未授权"
          },
        },
      )
    NotifyLoadFailed(family) =>
      (
        none,
        {
          ..model,
          notify_loaded: if family == "subscriptions" {
            false
          } else {
            model.notify_loaded
          },
          notify_note: "通知 " +
          family +
          " 源读模型不可用 · 使用设计快照",
        },
      )
    OcrLoaded(body) => {
      let (loaded, provider, scene, rows, configured, missing) = ocr_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          ocr_loaded: loaded,
          ocr_provider: provider,
          ocr_scene: scene,
          ocr_provider_rows: rows,
          ocr_configured_count: configured,
          ocr_missing_table_count: missing,
          ocr_note: if loaded {
            "已加载 PostgreSQL OCR 配置状态 · 不执行识别 · 密钥已脱敏 · 空源表 " +
            missing
          } else {
            "OCR 配置响应无效 · 使用设计快照"
          },
        },
      )
    }
    OcrLoadFailed =>
      (
        none,
        {
          ..model,
          ocr_loaded: false,
          ocr_provider_rows: [],
          ocr_note: "OCR 配置读模型不可用 · 使用设计快照",
        },
      )
    SaveOcrConfig =>
      (
        issue_ocr_config_save(emit),
        { ..model, ocr_command_note: "正在写入 OCR 配置候选…" },
      )
    OcrConfigCommandFinished(body) =>
      (
        if body.contains("\"valueRedacted\":true") {
          load_ocr(emit)
        } else {
          none
        },
        {
          ..model,
          ocr_command_note: if body.contains("\"authorization_candidate\":true") {
            "OCR 配置候选已写入 PostgreSQL · 值已脱敏 · provider 未执行"
          } else {
            "OCR 配置命令已返回 · 请复核响应边界"
          },
        },
      )
    OcrConfigCommandFailed =>
      (
        none,
        {
          ..model,
          ocr_command_note: "OCR 配置候选服务不可用或被网关拒绝",
        },
      )
    TestOcrProvider =>
      (
        issue_ocr_provider_test(emit),
        {
          ..model,
          ocr_command_note: "正在提交 OCR provider 干运行测试…",
        },
      )
    OcrCommandFinished(body) =>
      (
        none,
        {
          ..model,
          ocr_command_note: if body.contains("\"idempotent_replay\":true") {
            "OCR 测试命令已幂等重放 · provider 未执行"
          } else {
            "OCR 测试候选已记录 · provider 未执行 · 密钥未返回"
          },
        },
      )
    OcrCommandFailed =>
      (
        none,
        {
          ..model,
          ocr_command_note: "OCR 测试被服务、权限或 provider 配置拒绝",
        },
      )
    TestLlmProvider =>
      (
        issue_ai_provider_test(emit, "llm"),
        {
          ..model,
          provider_test_note: "正在提交管理端 LLM provider 干运行测试…",
        },
      )
    TestNotifyLlmProvider =>
      (
        issue_ai_provider_test(emit, "notify-llm"),
        {
          ..model,
          provider_test_note: "正在提交通知 LLM provider 干运行测试…",
        },
      )
    ProviderCommandFinished(family, body) =>
      (
        none,
        {
          ..model,
          provider_test_note: if body.contains("\"providerExecution\":false") {
            (if family == "llm" { "管理端 LLM" } else { "通知 LLM" }) +
            " 测试候选已记录 · provider 未执行 · 密钥未返回"
          } else {
            "provider 测试候选已返回 · 请复核响应边界"
          },
        },
      )
    ProviderCommandFailed(family) =>
      (
        none,
        {
          ..model,
          provider_test_note: (if family == "llm" {
            "管理端 LLM"
          } else {
            "通知 LLM"
          }) +
          " 测试被服务、权限或 provider 配置拒绝",
        },
      )
    ErrorLogLoaded(body) => {
      let (loaded, rows, total, today, five_xx, missing) = error_logs_from_body(
        body,
      )
      (
        none,
        {
          ..model,
          error_loaded: loaded,
          error_rows: rows,
          error_total: if loaded {
            total
          } else {
            "0"
          },
          error_today_count: if loaded {
            today
          } else {
            "0"
          },
          error_five_xx_count: if loaded {
            five_xx
          } else {
            "0"
          },
          error_missing_table_count: missing,
          error_note: if loaded {
            "已加载 PostgreSQL 错误日志元数据 · IP/堆栈已脱敏 · 空源表 " +
            missing
          } else {
            "错误日志响应无效 · 使用设计快照"
          },
        },
      )
    }
    ErrorLogLoadFailed =>
      (
        none,
        {
          ..model,
          error_loaded: false,
          error_rows: [],
          error_note: "错误日志读模型不可用 · 使用设计快照",
        },
      )
    AiStatsOverviewLoaded(body) => {
      let (
        loaded,
        period,
        intake,
        query,
        skip,
        correction,
        accuracy,
        saved_hours,
        scene_rows,
        missing,
      ) = ai_stats_overview_from_body(body)
      (
        if loaded {
          load_ai_stats_activity(emit)
        } else {
          none
        },
        {
          ..model,
          ai_stats_loaded: loaded,
          ai_stats_period: period,
          ai_stats_intake_total: intake,
          ai_stats_query_total: query,
          ai_stats_skip_total: skip,
          ai_stats_correction_total: correction,
          ai_stats_accuracy: accuracy,
          ai_stats_saved_hours: saved_hours,
          ai_stats_scene_rows: scene_rows,
          ai_stats_missing_table_count: missing,
          ai_stats_note: if loaded {
            "已加载 PostgreSQL AI 分析源读模型 · 不执行 LLM/OCR · 空源表 " +
            missing
          } else {
            "AI 分析响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiStatsActivityLoaded(body) => {
      let (loaded, rows, missing) = ai_stats_activity_from_body(body)
      (
        none,
        {
          ..model,
          ai_stats_activity_rows: rows,
          ai_stats_missing_table_count: missing,
          ai_stats_note: if loaded {
            model.ai_stats_note
          } else {
            "AI 活动读模型响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiStatsLoadFailed =>
      (
        none,
        {
          ..model,
          ai_stats_loaded: false,
          ai_stats_scene_rows: [],
          ai_stats_activity_rows: [],
          ai_stats_note: "AI 分析读模型不可用 · 使用设计快照",
        },
      )
    ExportAiStats =>
      (
        issue_ai_stats_export(emit, model),
        { ..model, ai_stats_export_note: "正在生成 XLSX 报表…" },
      )
    AiStatsExportFinished(blob) =>
      (
        {
          download_blob(blob, "ai-stats.xlsx")
          none
        },
        {
          ..model,
          ai_stats_export_note: "XLSX 已生成并开始下载 · 仅包含当前 AI 分析摘要",
        },
      )
    AiStatsExportFailed =>
      (
        none,
        {
          ..model,
          ai_stats_export_note: "XLSX 导出服务不可用或被网关拒绝",
        },
      )
    AiHubUsageLoaded(body) => {
      let (loaded, calls, minutes, intake, missing) = ai_hub_usage_from_body(
        body,
      )
      (
        if loaded {
          load_ai_hub_drafts(emit)
        } else {
          none
        },
        {
          ..model,
          ai_hub_loaded: loaded,
          ai_hub_monthly_calls: calls,
          ai_hub_minutes_saved: minutes,
          ai_hub_intake_total: intake,
          ai_hub_missing_table_count: missing,
          ai_hub_note: if loaded {
            "已加载 PostgreSQL AI 工作台使用统计 · 不执行 provider/LLM/OCR · 空源表 " +
            missing
          } else {
            "AI 工作台使用统计响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiHubDraftsLoaded(body) => {
      let (loaded, rows, missing) = ai_hub_draft_rows_from_body(body)
      (
        if loaded {
          load_ai_hub_query_log(emit)
        } else {
          none
        },
        {
          ..model,
          ai_hub_draft_rows: rows,
          ai_hub_missing_table_count: missing,
          ai_hub_note: if loaded {
            model.ai_hub_note
          } else {
            "AI 草稿历史响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiHubQueryLogLoaded(body) => {
      let (loaded, rows, missing) = ai_hub_query_rows_from_body(body)
      (
        if loaded {
          load_ai_hub_correction_stats(emit)
        } else {
          none
        },
        {
          ..model,
          ai_hub_loaded: model.ai_hub_loaded && loaded,
          ai_hub_query_rows: rows,
          ai_hub_missing_table_count: missing,
          ai_hub_note: if loaded {
            model.ai_hub_note + " · 草稿/问数历史保持只读"
          } else {
            "AI 查询历史响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiHubCorrectionStatsLoaded(body) => {
      let (loaded, total, rate, missing) = ai_hub_correction_stats_from_body(
        body,
      )
      (
        if loaded {
          load_ai_hub_corrections(emit)
        } else {
          none
        },
        {
          ..model,
          ai_hub_correction_total: total,
          ai_hub_correction_rate: rate,
          ai_hub_missing_table_count: missing,
          ai_hub_note: if loaded {
            model.ai_hub_note
          } else {
            "AI 修正统计响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiHubCorrectionsLoaded(body) => {
      let (loaded, rows, missing) = ai_hub_correction_rows_from_body(body)
      (
        none,
        {
          ..model,
          ai_hub_loaded: model.ai_hub_loaded && loaded,
          ai_hub_correction_rows: rows,
          ai_hub_missing_table_count: missing,
          ai_hub_note: if loaded {
            model.ai_hub_note + " · 修正日志保持只读"
          } else {
            "AI 修正日志响应无效 · 使用设计快照"
          },
        },
      )
    }
    AiHubLoadFailed =>
      (
        none,
        {
          ..model,
          ai_hub_loaded: false,
          ai_hub_draft_rows: [],
          ai_hub_query_rows: [],
          ai_hub_correction_rows: [],
          ai_hub_note: "AI 工作台源读模型不可用 · 起单/查询/命令仍需授权",
          ai_hub_explain_note: "解释候选不可用 · provider/LLM 保持关闭",
        },
      )
    ExplainAiHub =>
      (
        issue_ai_hub_explain(emit),
        {
          ..model,
          ai_hub_explain_note: "正在生成确定性解释候选 · 不调用 provider/LLM…",
        },
      )
    AiHubExplainFinished(body) =>
      (
        none,
        {
          ..model,
          ai_hub_explain_note: if body.contains(
              "\"provider\":\"native-deterministic\"",
            ) {
            "解释候选已生成 · native-deterministic · 不持久化、不授权"
          } else {
            "解释候选响应已返回 · provider/LLM 未执行"
          },
          ai_hub_explain_text: ai_hub_explain_text_from_body(body),
        },
      )
    AiHubExplainFailed =>
      (
        none,
        {
          ..model,
          ai_hub_explain_note: "解释候选服务不可用 · provider/LLM 保持关闭",
          ai_hub_explain_text: "解释候选不可用",
        },
      )
    InputAiHubIntakeDescription(value) =>
      (none, { ..model, ai_hub_intake_description: value })
    InputAiHubIntakeBizHint(value) =>
      (none, { ..model, ai_hub_intake_biz_hint: value })
    AiHubFileSelected(value) =>
      (
        none,
        {
          ..model,
          ai_hub_file_name: value,
          ai_hub_command_note: if value.is_empty() {
            model.ai_hub_command_note
          } else {
            "已选择 AI 输入文件 " +
            value +
            " · 仍需 provider/AI 负责人确认"
          },
        },
      )
    InputAiHubQueryText(value) => (none, { ..model, ai_hub_query_text: value })
    InputAiHubCommandText(value) =>
      (none, { ..model, ai_hub_command_text: value })
    RunAiHubCommand(command_type) =>
      if command_type == "intake" &&
        model.ai_hub_intake_description.trim().is_empty() &&
        model.ai_hub_file_name.trim().is_empty() {
        (
          none,
          {
            ..model,
            ai_hub_command_note: "请先填写描述或选择输入文件",
          },
        )
      } else if (command_type == "query" || command_type == "query-session") &&
        model.ai_hub_query_text.trim().is_empty() {
        (none, { ..model, ai_hub_command_note: "请先输入查询问题" })
      } else {
        (
          issue_ai_hub_command(emit, model, command_type),
          {
            ..model,
            ai_hub_command_note: "正在提交 AI Hub " +
            command_type +
            " 候选 · 等待 AI 负责人确认…",
          },
        )
      }
    AiHubCommandFinished(command_type, body) =>
      (
        none,
        {
          ..model,
          ai_hub_command_note: if body.contains("\"code\":47001") &&
            body.contains("\"persisted\":false") {
            "AI Hub " +
            command_type +
            " 已到达授权门 · provider/query/persistence 均未执行"
          } else {
            "AI Hub " +
            command_type +
            " 候选已返回 · 请复核 AI 负责人边界"
          },
        },
      )
    AiHubCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          ai_hub_command_note: "AI Hub " +
          command_type +
          " 服务不可用或被网关拒绝",
        },
      )
    WebhookLoaded(body) => {
      let (loaded, rows, missing, note) = webhook_config_from_body(body)
      (
        none,
        {
          ..model,
          webhook_loaded: loaded,
          webhook_rows: rows,
          webhook_missing_table_count: missing,
          webhook_note: if loaded {
            note + " · 空源表 " + missing
          } else {
            "Webhook 配置响应无效 · 使用设计快照"
          },
        },
      )
    }
    WebhookLoadFailed =>
      (
        none,
        {
          ..model,
          webhook_loaded: false,
          webhook_rows: [],
          webhook_note: "Webhook 配置读模型不可用 · 使用设计快照",
        },
      )
    SaveWebhookConfig =>
      (
        issue_webhook_config_save(emit),
        {
          ..model,
          webhook_command_note: "正在写入 Webhook 配置候选…",
        },
      )
    WebhookConfigCommandFinished(body) =>
      (
        if body.contains("\"platform\":\"wecom\"") {
          load_webhook_config(emit)
        } else {
          none
        },
        {
          ..model,
          webhook_command_note: if body.contains("\"credentialsBound\":false") {
            "Webhook 配置候选已写入 PostgreSQL · 凭据未绑定 · provider 未执行"
          } else {
            "Webhook 配置命令已返回 · 请复核响应边界"
          },
        },
      )
    WebhookConfigCommandFailed =>
      (
        none,
        {
          ..model,
          webhook_command_note: "Webhook 配置候选服务不可用或被网关拒绝",
        },
      )
    TestWebhookDelivery =>
      (
        issue_webhook_test(emit),
        {
          ..model,
          webhook_command_note: "正在提交 Webhook 干运行测试…",
        },
      )
    WebhookCommandFinished(body) =>
      (
        none,
        {
          ..model,
          webhook_command_note: if body.contains("\"idempotent_replay\":true") {
            "Webhook 测试命令已幂等重放 · provider 未执行"
          } else {
            "Webhook 测试候选已记录 · 不发送外部请求 · 密钥未返回"
          },
        },
      )
    WebhookCommandFailed =>
      (
        none,
        {
          ..model,
          webhook_command_note: "Webhook 测试被服务、权限或配置拒绝",
        },
      )
    PreviewWebhookOverdue =>
      (
        issue_webhook_overdue_preview(emit),
        {
          ..model,
          webhook_command_note: "正在预览工单超期扫描 · 不发送、不修改工单…",
        },
      )
    WebhookOverduePreviewFinished(body) =>
      (
        none,
        {
          ..model,
          webhook_command_note: if body.contains("\"persisted\":false") &&
            body.contains("\"provider_execution\":false") {
            "工单超期扫描预览已返回 · 不发送、不修改工单、不调用 provider"
          } else {
            "工单超期扫描预览已返回 · 请复核执行边界"
          },
        },
      )
    WebhookOverduePreviewFailed =>
      (
        none,
        {
          ..model,
          webhook_command_note: "工单超期扫描预览服务不可用或被网关拒绝",
        },
      )
    ScanWebhookOverdue =>
      (
        issue_webhook_overdue_scan(emit),
        {
          ..model,
          webhook_command_note: "正在记录工单超期扫描候选 · 不发送、不修改工单…",
        },
      )
    WebhookOverdueScanFinished(body) =>
      (
        none,
        {
          ..model,
          webhook_command_note: if body.contains("\"ticketMutation\":false") &&
            body.contains("\"providerExecution\":false") {
            "工单超期扫描候选已记录 · dry-run · 不发送、不修改工单"
          } else {
            "工单超期扫描候选已返回 · 请复核执行边界"
          },
        },
      )
    WebhookOverdueScanFailed =>
      (
        none,
        {
          ..model,
          webhook_command_note: "工单超期扫描候选服务不可用或被网关拒绝",
        },
      )
    ReportBuilderMetaLoaded(body) => {
      let (loaded, rows, missing, note) = report_builder_meta_from_body(body)
      (
        if loaded {
          load_report_builder_templates(emit)
        } else {
          none
        },
        {
          ..model,
          report_builder_loaded: loaded,
          report_builder_table_rows: rows,
          report_builder_missing_table_count: missing,
          report_builder_note: if loaded {
            note
          } else {
            "报表元数据响应无效 · 使用设计快照"
          },
        },
      )
    }
    ReportBuilderTemplatesLoaded(body) => {
      let (loaded, rows, missing) = report_builder_templates_from_body(body)
      (
        none,
        {
          ..model,
          report_builder_template_rows: rows,
          report_builder_missing_table_count: missing,
          report_builder_note: if loaded {
            model.report_builder_note + " · 模板源表空记录 " + missing
          } else {
            "模板列表响应无效 · 使用设计快照"
          },
        },
      )
    }
    ReportBuilderLoadFailed =>
      (
        none,
        {
          ..model,
          report_builder_loaded: false,
          report_builder_table_rows: [],
          report_builder_template_rows: [],
          report_builder_note: "自定义报表读模型不可用 · 使用设计快照",
        },
      )
    CreateReportTemplate =>
      if model.report_builder_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_report_builder_create(emit),
          {
            ..model,
            report_builder_command_state: "pending",
            report_builder_command_note: "正在创建报表模板命令…",
          },
        )
      }
    RunReportTemplate =>
      if model.report_builder_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_report_builder_run(emit),
          {
            ..model,
            report_builder_command_state: "running",
            report_builder_command_note: "正在以内存导入源运行白名单报表…",
          },
        )
      }
    DeleteReportTemplate =>
      if model.report_builder_template_id == "" ||
        model.report_builder_command_state == "pending" {
        (none, model)
      } else {
        (
          issue_report_builder_delete(emit, model.report_builder_template_id),
          {
            ..model,
            report_builder_command_state: "pending",
            report_builder_command_note: "正在删除本地报表模板命令…",
          },
        )
      }
    ReportBuilderCommandFinished(body) => {
      let (loaded, state, template_id, note) = report_builder_command_from_body(
        body,
      )
      (
        if loaded {
          load_report_builder_templates(emit)
        } else {
          none
        },
        {
          ..model,
          report_builder_command_state: if loaded {
            state
          } else {
            "error"
          },
          report_builder_template_id: if state == "deleted" {
            ""
          } else {
            template_id
          },
          report_builder_command_note: note,
        },
      )
    }
    ReportBuilderRunFinished(body) => {
      let (loaded, rows, note) = report_builder_run_from_body(body)
      (
        none,
        {
          ..model,
          report_builder_command_state: if loaded {
            "ran"
          } else {
            "error"
          },
          report_builder_run_rows: rows,
          report_builder_command_note: note,
        },
      )
    }
    ReportBuilderCommandFailed =>
      (
        none,
        {
          ..model,
          report_builder_command_state: "error",
          report_builder_command_note: "报表模板命令服务不可用或拒绝了请求",
        },
      )
    UpdateProfile =>
      if model.profile_edit_name.trim().is_empty() {
        (none, { ..model, profile_command_note: "姓名不能为空" })
      } else {
        (
          issue_profile_update(emit, model),
          { ..model, profile_command_note: "正在保存个人资料…" },
        )
      }
    ChangePassword =>
      if model.profile_password_old.length() < 6 ||
        model.profile_password_new.length() < 6 {
        (
          none,
          {
            ..model,
            profile_command_note: "旧密码和新密码至少需要 6 位",
          },
        )
      } else if model.profile_password_new != model.profile_password_confirm {
        (none, { ..model, profile_command_note: "两次新密码不一致" })
      } else {
        (
          issue_password_change(emit, model),
          {
            ..model,
            profile_command_note: "正在验证旧密码并提交改密命令…",
          },
        )
      }
    ProfileCommandFinished(body) => {
      let credential_changed = body.contains("credentialChanged")
      (
        if credential_changed {
          logout_after_password_change(emit)
        } else {
          load_profile(emit, model.user_code)
        },
        {
          ..model,
          profile_password_old: if body.contains("credentialChanged") {
            ""
          } else {
            model.profile_password_old
          },
          profile_password_new: if body.contains("credentialChanged") {
            ""
          } else {
            model.profile_password_new
          },
          profile_password_confirm: if body.contains("credentialChanged") {
            ""
          } else {
            model.profile_password_confirm
          },
          profile_command_note: if body.contains("credentialChanged") {
            "密码已写入 PostgreSQL · 凭据值已脱敏；请用新密码重新登录"
          } else if body.contains("empName") {
            "个人资料命令已写入 PostgreSQL · 读模型正在刷新"
          } else {
            "个人资料命令已完成"
          },
        },
      )
    }
    ProfileCommandFailed =>
      (
        none,
        {
          ..model,
          profile_command_note: "个人资料/密码命令被服务拒绝或暂时不可用",
        },
      )
    ProfileLoaded(body) => {
      let values = profile_from_body(body)
      if values.length() == 11 {
        (
          load_profile_initiated(emit, values[1]),
          {
            ..model,
            profile_loaded: true,
            profile_user_id: values[0],
            profile_user_code: values[1],
            profile_user_name: values[2],
            profile_edit_name: values[3],
            profile_bu_guid: values[4],
            profile_bu_name: values[5],
            profile_dept_name: values[6],
            profile_super_user: values[7],
            profile_enabled: values[8],
            profile_last_login: values[9],
            profile_source_kind: values[10],
            profile_note: "已加载 PostgreSQL 个人资料 · 敏感认证字段未导入",
            profile_initiated_loaded: false,
            profile_initiated_rows: [],
            profile_initiated_note: "正在加载本人发起记录…",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            profile_loaded: false,
            profile_initiated_loaded: false,
            profile_initiated_rows: [],
            profile_note: "个人资料响应无效 · 使用设计快照",
            profile_initiated_note: "本人发起读模型不可用 · 使用设计快照",
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
          profile_initiated_loaded: false,
          profile_initiated_rows: [],
          profile_note: "个人资料读模型不可用 · 使用设计快照",
          profile_initiated_note: "本人发起读模型不可用 · 使用设计快照",
        },
      )
    ProfileInitiatedLoaded(body) =>
      (
        none,
        {
          ..model,
          profile_initiated_loaded: true,
          profile_initiated_rows: initiated_rows_from_body(body),
          profile_initiated_note: "已加载 PostgreSQL 本人发起记录 · 空表保持可见",
        },
      )
    ProfileInitiatedLoadFailed =>
      (
        none,
        {
          ..model,
          profile_initiated_loaded: false,
          profile_initiated_rows: [],
          profile_initiated_note: "本人发起读模型不可用 · 使用设计快照",
        },
      )
    UsersLoaded(body) =>
      (
        load_rbac_roles(emit),
        {
          ..model,
          users_loaded: true,
          user_roster_rows: user_roster_rows_from_body(body),
          users_note: "已加载 PostgreSQL 身份 roster · 角色源表缺失保持可见",
        },
      )
    UsersLoadFailed =>
      (
        load_rbac_roles(emit),
        {
          ..model,
          users_loaded: false,
          user_roster_rows: [],
          users_note: "身份读模型不可用 · 使用已审核快照",
        },
      )
    CreateLocalUser =>
      (
        issue_rbac_user_create(emit),
        {
          ..model,
          users_note: "正在创建本地 RBAC 用户候选 · 凭据只保留摘要…",
        },
      )
    RbacUserCommandFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_users(emit)
        } else {
          none
        },
        {
          ..model,
          users_note: if body.contains("\"credential_values_redacted\":true") {
            "本地用户候选已写入 PostgreSQL · 凭据已摘要化 · 不改变当前授权"
          } else {
            "本地用户命令已返回 · 请复核授权边界"
          },
        },
      )
    RbacUserCommandFailed =>
      (
        none,
        {
          ..model,
          users_note: "本地用户命令服务不可用或被网关拒绝",
        },
      )
    CreateLocalRole =>
      (
        issue_rbac_role_create(emit),
        {
          ..model,
          rbac_roles_note: "正在创建本地 RBAC 角色候选 · 不改变当前授权…",
        },
      )
    RbacRoleCommandFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_rbac_roles(emit)
        } else {
          none
        },
        {
          ..model,
          rbac_roles_note: if body.contains("\"authorizing\":false") {
            "本地角色候选已写入 PostgreSQL · 仍需安全负责人批准授权"
          } else {
            "本地角色命令已返回 · 请复核授权边界"
          },
        },
      )
    RbacRoleCommandFailed =>
      (
        none,
        {
          ..model,
          rbac_roles_note: "本地角色命令服务不可用或被网关拒绝",
        },
      )
    AssignLocalRole =>
      (
        issue_rbac_role_assignment(emit),
        {
          ..model,
          rbac_roles_note: "正在提交本地角色分配候选 · 不改变当前授权…",
        },
      )
    RbacAssignmentFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_users(emit)
        } else {
          none
        },
        {
          ..model,
          rbac_roles_note: if body.contains("\"authorizing\":false") {
            "本地角色分配候选已写入 PostgreSQL · 仍需安全负责人批准授权"
          } else {
            "本地角色分配命令已返回 · 请复核授权边界"
          },
        },
      )
    RbacAssignmentFailed =>
      (
        none,
        {
          ..model,
          rbac_roles_note: "本地角色分配服务不可用、角色不存在或被网关拒绝",
        },
      )
    ToggleAdminUser =>
      (
        issue_rbac_user_toggle(emit),
        {
          ..model,
          users_note: "正在提交用户启停候选 · 不改变认证状态…",
        },
      )
    RbacUserToggleFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_users(emit)
        } else {
          none
        },
        {
          ..model,
          users_note: if body.contains("\"authorizing\":false") {
            "用户启停候选已写入本地投影 · 认证授权仍未改变"
          } else {
            "用户启停命令已返回 · 请复核认证边界"
          },
        },
      )
    RbacUserToggleFailed =>
      (
        none,
        { ..model, users_note: "用户启停服务不可用或被网关拒绝" },
      )
    ResetAdminUserPassword =>
      (
        issue_rbac_user_reset(emit),
        {
          ..model,
          users_note: "正在提交密码重置候选 · 明文不会返回…",
        },
      )
    RbacUserResetFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_users(emit)
        } else {
          none
        },
        {
          ..model,
          users_note: if body.contains("\"credential_values_redacted\":true") {
            "密码重置候选已写入摘要 · 明文未返回 · 认证仍需生产授权"
          } else {
            "密码重置命令已返回 · 请复核凭据边界"
          },
        },
      )
    RbacUserResetFailed =>
      (
        none,
        { ..model, users_note: "密码重置服务不可用或被网关拒绝" },
      )
    DeleteLocalRole =>
      (
        issue_rbac_role_delete(emit),
        {
          ..model,
          rbac_roles_note: "正在删除本地 RBAC 角色候选 · 导入角色不会删除…",
        },
      )
    RbacRoleDeleteFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_rbac_roles(emit)
        } else {
          none
        },
        {
          ..model,
          rbac_roles_note: if body.contains("\"state\":\"deleted\"") {
            "本地角色删除候选已写入 PostgreSQL · 导入/system 角色保持只读"
          } else {
            "本地角色删除命令已返回 · 请复核保护边界"
          },
        },
      )
    RbacRoleDeleteFailed =>
      (
        none,
        {
          ..model,
          rbac_roles_note: "本地角色删除服务不可用、角色不存在或被网关拒绝",
        },
      )
    UpdateAdminUser =>
      (
        issue_rbac_user_update(emit),
        {
          ..model,
          users_note: "正在提交用户资料更新候选 · 不改变认证授权…",
        },
      )
    RbacUserUpdateFinished(body) =>
      (
        if body.contains("\"persisted\":true") {
          load_users(emit)
        } else {
          none
        },
        {
          ..model,
          users_note: if body.contains("\"authorizing\":false") {
            "用户资料更新候选已写入本地投影 · 认证授权仍未改变"
          } else {
            "用户资料更新命令已返回 · 请复核授权边界"
          },
        },
      )
    RbacUserUpdateFailed =>
      (
        none,
        {
          ..model,
          users_note: "用户资料更新服务不可用或被网关拒绝",
        },
      )
    RbacRolesLoaded(body) =>
      (
        load_rbac_catalog(emit),
        {
          ..model,
          rbac_roles_loaded: true,
          rbac_role_rows: rbac_role_rows_from_body(body),
          rbac_roles_note: "已加载 PostgreSQL 角色源读模型 · 空源表保持可见",
        },
      )
    RbacRolesLoadFailed =>
      (
        load_rbac_catalog(emit),
        {
          ..model,
          rbac_roles_loaded: false,
          rbac_role_rows: [],
          rbac_roles_note: "角色读模型不可用 · 使用设计快照",
        },
      )
    RbacCatalogLoaded(body) =>
      (
        none,
        {
          ..model,
          rbac_catalog_loaded: true,
          rbac_catalog_rows: rbac_catalog_rows_from_body(body),
          rbac_catalog_note: "已加载 PostgreSQL 权限定义 · 不授予目标权限",
        },
      )
    RbacCatalogLoadFailed =>
      (
        none,
        {
          ..model,
          rbac_catalog_loaded: false,
          rbac_catalog_rows: [],
          rbac_catalog_note: "权限目录读模型不可用 · 使用设计快照",
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
        load_health_inventory(emit),
        {
          ..model,
          health_bpm_instance_count: instance_count,
          health_bpm_action_count: action_count,
          health_note: "已加载 PostgreSQL 健康覆盖 · BPM 实例/动作保持源数据状态",
        },
      )
    }
    HealthInventoryLoaded(body) => {
      let (
        loaded,
        schema_count,
        snapshot_count,
        schema_only_count,
        export_state,
        snapshot_id,
        note,
      ) = health_inventory_from_body(body)
      (
        none,
        {
          ..model,
          health_loaded: true,
          health_inventory_loaded: loaded,
          health_inventory_schema_count: schema_count,
          health_inventory_snapshot_count: snapshot_count,
          health_inventory_schema_only_count: schema_only_count,
          health_inventory_export_state: export_state,
          health_inventory_snapshot_id: snapshot_id,
          health_inventory_note: note,
        },
      )
    }
    HealthInventoryLoadFailed =>
      (
        none,
        {
          ..model,
          health_loaded: true,
          health_inventory_loaded: false,
          health_inventory_note: "迁移源范围不可用 · 健康探针其余读数仍保持只读",
        },
      )
    HealthLoadFailed =>
      (
        none,
        {
          ..model,
          health_loaded: false,
          health_table_rows: [],
          health_inventory_loaded: false,
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
    BudgetScopeLoaded(body) =>
      (
        load_budget_loan_balance(emit, model.user_code),
        {
          ..model,
          budget_scope_loaded: true,
          budget_scope_users: budget_scope_users_from_body(body),
          budget_scope_note: "已加载 PostgreSQL 预算人员范围 · 仅作源观察，不授予范围权限",
        },
      )
    BudgetLoanBalanceLoaded(body) => {
      let (total, count) = budget_loan_balance_from_body(body)
      (
        none,
        {
          ..model,
          budget_loan_balance_loaded: true,
          budget_loan_balance_total: total,
          budget_loan_count: count,
          budget_loan_note: "已加载 PostgreSQL 个人借款余额 · 只读源观察",
        },
      )
    }
    BudgetScopeLoadFailed =>
      (
        none,
        {
          ..model,
          budget_scope_loaded: false,
          budget_scope_users: [],
          budget_scope_note: "预算范围源读模型不可用 · 使用设计快照",
          budget_loan_balance_loaded: false,
          budget_loan_balance_total: "0",
          budget_loan_count: "0",
          budget_loan_note: "个人借款余额源读模型不可用 · 使用设计快照",
        },
      )
    WorkflowLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_loaded: true,
          workflow_process_rows: workflow_rows_from_body(body),
          workflow_note: "已加载 PostgreSQL 工作流定义 · 正在读取实例与动作源观察",
        },
      )
    WorkflowLoadFailed =>
      (
        none,
        {
          ..model,
          workflow_loaded: false,
          workflow_process_rows: [],
          workflow_note: "工作流定义读模型不可用 · 仍尝试读取实例源观察",
        },
      )
    WorkflowObservationPendingLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_pending_rows: workflow_observation_rows_from_body(body),
          workflow_observation_note: "已读取 PostgreSQL 待办实例源观察 · 不产生审批权限",
        },
      )
    WorkflowObservationInitiatedLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_initiated_rows: workflow_observation_rows_from_body(body),
        },
      )
    WorkflowObservationHistoryLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_observation_loaded: true,
          workflow_history_rows: workflow_observation_rows_from_body(body),
          workflow_observation_note: "已加载 PostgreSQL 工作流实例/动作源观察 · 空源表保持为空",
        },
      )
    WorkflowTicketsLoaded(body) =>
      (
        none,
        {
          ..model,
          workflow_tickets_loaded: true,
          workflow_ticket_rows: workflow_ticket_rows_from_body(body),
          workflow_ticket_note: "已加载 PostgreSQL 告警工单源观察 · 命令仍受候选边界约束",
        },
      )
    WorkflowTicketsLoadFailed =>
      (
        none,
        {
          ..model,
          workflow_tickets_loaded: false,
          workflow_ticket_rows: [],
          workflow_ticket_note: "告警工单源读模型不可用 · 使用设计快照",
        },
      )
    SelectWorkflowTab(tab) => {
      let command = if tab == "initiated" &&
        model.workflow_initiated_rows.length() == 0 {
        load_workflow_observation_initiated(emit, model.user_code)
      } else if tab == "history" && model.workflow_history_rows.length() == 0 {
        load_workflow_observation_history(emit, model.user_code)
      } else if tab == "tickets" && !model.workflow_tickets_loaded {
        load_workflow_tickets(emit)
      } else {
        none
      }
      (command, { ..model, workflow_task_tab: tab })
    }
    WorkflowObservationLoadFailed =>
      (
        none,
        {
          ..model,
          workflow_observation_loaded: false,
          workflow_pending_rows: [],
          workflow_initiated_rows: [],
          workflow_history_rows: [],
          workflow_observation_note: "工作流实例源读模型不可用 · 使用设计快照",
        },
      )
    StartWorkflowCandidate =>
      (
        issue_workflow_command(emit, "start"),
        {
          ..model,
          workflow_command_note: "正在发起本地工作流候选 · 不同步业务单据、不触发通知…",
        },
      )
    ApproveWorkflowCandidate =>
      (
        issue_workflow_command(emit, "approve"),
        {
          ..model,
          workflow_command_note: "正在提交本地审批候选 · 仅写入工作流投影…",
        },
      )
    RejectWorkflowCandidate =>
      (
        issue_workflow_command(emit, "reject"),
        {
          ..model,
          workflow_command_note: "正在提交本地驳回候选 · 仅写入工作流投影…",
        },
      )
    CosignWorkflowCandidate =>
      (
        issue_workflow_command(emit, "cosign"),
        {
          ..model,
          workflow_command_note: "正在提交本地会签候选 · 不调用外部执行器…",
        },
      )
    TransferWorkflowCandidate =>
      (
        issue_workflow_command(emit, "transfer"),
        {
          ..model,
          workflow_command_note: "正在提交本地转办候选 · 仅写入动作审计…",
        },
      )
    WorkflowCommandFinished(command_type, body) =>
      (
        load_workflow_observation_pending(emit, model.user_code),
        {
          ..model,
          workflow_command_note: if body.contains("\"persisted\":true") {
            "工作流 " +
            command_type +
            " 候选已持久化 · provider/cash/accounting/tax 均未执行"
          } else {
            "工作流 " +
            command_type +
            " 候选已返回 · 请复核执行边界"
          },
        },
      )
    WorkflowCommandFailed(command_type) =>
      (
        none,
        {
          ..model,
          workflow_command_note: "工作流 " +
          command_type +
          " 服务不可用或被网关拒绝",
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
    ProjectStagesLoaded(body) =>
      (
        none,
        {
          ..model,
          project_stage_rows: project_stage_rows_from_body(body),
          project_note: "已加载 PostgreSQL 项目七阶段生命周期 · 导入记录保持只读",
        },
      )
    ProjectStagesLoadFailed =>
      (
        none,
        {
          ..model,
          project_stage_rows: [],
          project_note: "项目生命周期读模型不可用 · 使用设计阶段快照",
        },
      )
    ProjectKpiLoaded(body) =>
      match project_kpi_from_body(body) {
        Some(kpi) =>
          (
            none,
            {
              ..model,
              project_kpi_loaded: true,
              project_kpi: kpi,
              project_kpi_note: "已加载 PostgreSQL 项目八维 KPI · 仅作源观察",
            },
          )
        None =>
          (
            none,
            {
              ..model,
              project_kpi_loaded: false,
              project_kpi_note: "项目 KPI 响应无效 · 使用设计快照",
            },
          )
      }
    ProjectKpiLoadFailed =>
      (
        none,
        {
          ..model,
          project_kpi_loaded: false,
          project_kpi_note: "项目 KPI 读模型不可用 · 使用设计快照",
        },
      )
    ProjectAnomaliesLoaded(body) =>
      (
        none,
        {
          ..model,
          project_anomalies_loaded: true,
          project_anomaly_rows: project_anomaly_rows_from_body(body),
          project_anomaly_note: "已读取 PostgreSQL 项目异常观察 · 不触发 provider 或通知",
        },
      )
    ProjectAnomaliesLoadFailed =>
      (
        none,
        {
          ..model,
          project_anomalies_loaded: false,
          project_anomaly_rows: [],
          project_anomaly_note: "项目异常读模型不可用 · 使用设计快照",
        },
      )
    DownloadImportTemplate(biz_type) =>
      (
        issue_import_template(emit, biz_type),
        {
          ..model,
          import_template_note: (if biz_type == "project" {
            "项目"
          } else {
            "合同"
          }) +
          " CSV 模板下载中…",
        },
      )
    ImportTemplateDownloaded(biz_type, blob) =>
      (
        {
          download_blob(blob, biz_type + "_template.csv")
          none
        },
        {
          ..model,
          import_template_note: (if biz_type == "project" {
            "项目"
          } else {
            "合同"
          }) +
          " CSV 模板已下载 · 可提交至 native 批量导入边界",
        },
      )
    ImportTemplateDownloadFailed(biz_type) =>
      (
        none,
        {
          ..model,
          import_template_note: (if biz_type == "project" {
            "项目"
          } else {
            "合同"
          }) +
          " CSV 模板下载失败 · 服务或网关不可用",
        },
      )
    SelectImportFile(biz_type, file_name) =>
      (
        start_import_file_read(emit, biz_type),
        {
          ..model,
          import_biz_type: biz_type,
          import_file_name: file_name,
          import_state: "reading",
          import_note: "正在读取 CSV 文件…",
        },
      )
    ImportCsvLoaded(biz_type, text) => {
      let parsed = parse_import_csv(text)
      let has_rows = parsed.headers.length() > 0 &&
        parsed.row_count != "0" &&
        parsed.within_limit
      (
        none,
        {
          ..model,
          import_biz_type: biz_type,
          import_headers: parsed.headers,
          import_preview_rows: parsed.preview_rows,
          import_rows_json: parsed.rows_json,
          import_row_count: parsed.row_count,
          import_key: if has_rows {
            "rabbita-import-" + biz_type + "-" + import_nonce()
          } else {
            ""
          },
          import_state: if has_rows {
            "ready"
          } else {
            "idle"
          },
          import_note: if has_rows {
            "已解析 " + parsed.row_count + " 行 · 请先试运行校验"
          } else if parsed.row_count != "0" && !parsed.within_limit {
            "CSV 超过 500 行上限 · 请拆分批次"
          } else {
            "CSV 为空或缺少表头"
          },
        },
      )
    }
    RunImportDryRun =>
      if model.import_state == "ready" && model.import_rows_json != "[]" {
        (
          issue_import_command(emit, model, true),
          {
            ..model,
            import_state: "dry_run",
            import_note: "正在逐行校验并执行 PostgreSQL 导入试运行…",
          },
        )
      } else {
        (none, { ..model, import_note: "请先选择并解析 CSV 文件" })
      }
    CommitImportBatch =>
      if model.import_state == "dry_run_ok" && model.import_rows_json != "[]" {
        (
          issue_import_command(emit, model, false),
          {
            ..model,
            import_state: "committing",
            import_note: "正在事务提交导入批次…",
          },
        )
      } else {
        (none, { ..model, import_note: "请先完成通过的试运行校验" })
      }
    ImportCommandFinished(biz_type, body) => {
      let is_dry_run = body.contains("\"mode\":\"dryRun\"")
      let succeeded = body.contains("\"success\":true") &&
        body.contains("\"rowsAccepted\"")
      let next_command = if !is_dry_run && succeeded {
        if biz_type == "project" {
          load_projects(emit)
        } else {
          load_contracts(emit)
        }
      } else {
        none
      }
      (
        next_command,
        {
          ..model,
          import_biz_type: biz_type,
          import_state: if is_dry_run && succeeded {
            "dry_run_ok"
          } else if !is_dry_run && succeeded {
            "committed"
          } else {
            "error"
          },
          import_note: if is_dry_run && succeeded {
            "试运行通过 " +
            model.import_row_count +
            " 行 · 可以提交导入"
          } else if !is_dry_run && succeeded {
            "已提交 " +
            model.import_row_count +
            " 行 · 命令投影已写入 PostgreSQL"
          } else {
            "导入响应未通过校验 · 请复核返回内容"
          },
        },
      )
    }
    ImportCommandFailed(biz_type) =>
      (
        none,
        {
          ..model,
          import_biz_type: biz_type,
          import_state: "error",
          import_note: "导入命令被服务、权限或网关拒绝",
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
    SyncLoanWorkflow =>
      if model.loan_id == "" {
        (none, model)
      } else {
        (
          issue_loan_workflow_sync(emit, model),
          {
            ..model,
            loan_workflow_sync_note: "正在检查工作流同步边界 · 不写入借款、不触发审批…",
          },
        )
      }
    LoanWorkflowSyncFinished(body) =>
      (
        none,
        {
          ..model,
          loan_workflow_sync_note: if body.contains("workflow synchronization") {
            "工作流同步候选已验证 · wf_process_instance 源行不可用 · 未写入借款"
          } else {
            "工作流同步候选响应已返回 · 未触发审批"
          },
        },
      )
    LoanWorkflowSyncFailed =>
      (
        none,
        {
          ..model,
          loan_workflow_sync_note: "工作流同步候选服务不可用或被网关拒绝",
        },
      )
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
    CreatePlanTask =>
      if model.plan_task_id != "" || model.plan_task_state == "pending" {
        (none, model)
      } else if model.plan_create_task_name.trim().is_empty() {
        (none, { ..model, plan_task_command_note: "任务名称不能为空" })
      } else if model.plan_create_begin_date.trim().is_empty() ||
        model.plan_create_end_date.trim().is_empty() {
        (
          none,
          {
            ..model,
            plan_task_command_note: "计划开始/完成日期不能为空",
          },
        )
      } else {
        (
          issue_plan_task_command(emit, model, "create"),
          {
            ..model,
            plan_task_state: "pending",
            plan_task_command_note: "正在创建项目计划任务草稿…",
          },
        )
      }
    UpdatePlanTask =>
      if model.plan_task_id == "" || model.plan_task_state == "pending" {
        (none, model)
      } else {
        (
          issue_plan_task_command(emit, model, "update"),
          {
            ..model,
            plan_task_state: "pending",
            plan_task_command_note: "正在更新项目计划任务…",
          },
        )
      }
    DeletePlanTask =>
      if model.plan_task_id == "" || model.plan_task_state == "pending" {
        (none, model)
      } else {
        (
          issue_plan_task_command(emit, model, "delete"),
          {
            ..model,
            plan_task_state: "pending",
            plan_task_command_note: "正在作废项目计划任务…",
          },
        )
      }
    PlanTaskCommandFinished(body) => {
      let next_state = if body.contains("\"state\":\"deleted\"") {
        "deleted"
      } else if body.contains("\"state\":\"pending\"") {
        "pending"
      } else {
        "error"
      }
      if next_state == "error" {
        (
          none,
          { ..model, plan_task_state: "error", plan_task_command_note: body },
        )
      } else {
        (
          load_delivery_for_project(emit, model.project_plan_project_id),
          {
            ..model,
            plan_task_id: if next_state == "deleted" {
              ""
            } else {
              "PT-RABBITA-LOCAL"
            },
            plan_task_state: next_state,
            plan_task_command_note: "已写入 PostgreSQL 项目计划投影 · 任务状态/进度不触发现金、会计或税务",
          },
        )
      }
    }
    PlanTaskCommandFailed =>
      (
        none,
        {
          ..model,
          plan_task_state: "error",
          plan_task_command_note: "项目计划任务命令服务不可用或拒绝了请求",
        },
      )
    SuggestProjectPlan =>
      (
        issue_project_plan_suggestion(emit, model),
        {
          ..model,
          plan_ai_suggestion_note: "正在生成七节点确定性计划建议 · 不调用 provider/LLM…",
        },
      )
    ProjectPlanSuggestionFinished(body) => {
      let rows = plan_ai_suggestion_rows_from_body(body)
      (
        none,
        {
          ..model,
          plan_ai_suggestion_rows: rows,
          plan_ai_suggestion_note: if body.contains(
              "\"provider\":\"native-deterministic\"",
            ) {
            "七节点计划建议已生成 · native-deterministic · 不持久化、不修改计划"
          } else {
            "计划建议响应已返回 · provider/LLM 未执行"
          },
        },
      )
    }
    ProjectPlanSuggestionFailed =>
      (
        none,
        {
          ..model,
          plan_ai_suggestion_note: "计划建议服务不可用 · provider/LLM 保持关闭",
          plan_ai_suggestion_rows: [],
        },
      )
    PlanDelayImpactFinished(body) =>
      (
        none,
        {
          ..model,
          plan_delay_note: if body.contains("\"impactCount\"") {
            "延期影响已计算 · 仅提供计划分析，不修改任务"
          } else {
            "延期影响响应已返回 · 请复核源任务"
          },
          plan_delay_rows: plan_delay_rows_from_body(body),
        },
      )
    PlanDelayImpactFailed =>
      (
        none,
        {
          ..model,
          plan_delay_note: "延期影响服务不可用或任务不存在",
          plan_delay_rows: [],
        },
      )
    OpenDeliveryForm(kind) =>
      (
        none,
        {
          ..model,
          delivery_form_open: kind,
          delivery_progress_state: if kind == "progress" {
            "new"
          } else {
            model.delivery_progress_state
          },
          delivery_output_state: if kind == "output" {
            "new"
          } else {
            model.delivery_output_state
          },
        },
      )
    CloseDeliveryForm => (none, { ..model, delivery_form_open: "" })
    InputDeliveryField(field, value) =>
      (
        none,
        {
          ..model,
          delivery_building_no: if field == "building_no" {
            value
          } else {
            model.delivery_building_no
          },
          delivery_stage: if field == "stage" {
            value
          } else {
            model.delivery_stage
          },
          delivery_plan_date: if field == "plan_date" {
            value
          } else {
            model.delivery_plan_date
          },
          delivery_plan_pct: if field == "plan_pct" {
            value
          } else {
            model.delivery_plan_pct
          },
          delivery_contract_id: if field == "contract_id" {
            value
          } else {
            model.delivery_contract_id
          },
          delivery_remark: if field == "remark" {
            value
          } else {
            model.delivery_remark
          },
          delivery_report_actual_pct: if field == "report_actual_pct" {
            value
          } else {
            model.delivery_report_actual_pct
          },
          delivery_report_date: if field == "report_date" {
            value
          } else {
            model.delivery_report_date
          },
          delivery_report_remark: if field == "report_remark" {
            value
          } else {
            model.delivery_report_remark
          },
          delivery_progress_id: if field == "progress_id" {
            value
          } else {
            model.delivery_progress_id
          },
          delivery_output_contract_id: if field == "output_contract_id" {
            value
          } else {
            model.delivery_output_contract_id
          },
          delivery_output_period: if field == "output_period" {
            value
          } else {
            model.delivery_output_period
          },
          delivery_output_amount: if field == "output_amount" {
            value
          } else {
            model.delivery_output_amount
          },
          delivery_output_remark: if field == "output_remark" {
            value
          } else {
            model.delivery_output_remark
          },
        },
      )
    CreateDeliveryProgress =>
      if model.delivery_progress_state == "new" {
        (
          issue_delivery_command(emit, model, "create_progress"),
          {
            ..model,
            delivery_progress_state: "pending",
            delivery_form_open: "",
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
            delivery_form_open: "",
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
            delivery_form_open: "",
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
      if model.plan_report_task_id.trim().is_empty() {
        (none, { ..model, delivery_command_note: "请先选择任务" })
      } else if model.plan_report_progress.trim().is_empty() {
        (none, { ..model, delivery_command_note: "汇报进度不能为空" })
      } else {
        (
          issue_delivery_command(emit, model, "report_task"),
          {
            ..model,
            delivery_task_id: model.plan_report_task_id,
            delivery_command_note: "正在提交任务汇报（不直接修改导入任务状态）…",
          },
        )
      }
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
        @cmd.batch([
          load_delivery(emit, model.delivery_project_id),
          load_delivery_for_project(emit, model.project_plan_project_id),
        ]),
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
    ExpensesLoaded(body) =>
      (
        load_budget_scope(emit, model.profile_bu_guid),
        {
          ..model,
          expenses_loaded: true,
          expense_rows: expense_rows_from_body(body),
          expenses_note: "已加载 PostgreSQL 报销源表 · 空表与缺失字段保持可见",
        },
      )
    ExpensesLoadFailed =>
      (
        none,
        {
          ..model,
          expenses_loaded: false,
          expense_rows: [],
          expenses_note: "报销源读模型不可用 · 使用设计快照",
        },
      )
    ExpenseDetailLoaded(body) => {
      let (loaded, detail, note) = expense_detail_from_body(body)
      (
        none,
        {
          ..model,
          expense_detail_loaded: loaded,
          expense_detail: detail,
          expense_detail_note: note,
        },
      )
    }
    ExpenseDetailLoadFailed =>
      (
        none,
        {
          ..model,
          expense_detail_loaded: false,
          expense_detail: None,
          expense_detail_note: "报销详情源读模型不可用 · 使用设计快照",
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
    UpdateExpense =>
      if model.expense_id == "" || model.expense_state != "草稿" {
        (none, model)
      } else {
        (
          @http.put("/api/company/expenses/\{model.expense_id}")
          .with_text(
            "{\"idempotency_key\":\"rabbita-expense-update-v1\",\"subject\":\"成都项目现场出差（已补充说明）\"}",
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
            expense_note: "正在更新草稿并写入 PostgreSQL 投影…",
          },
        )
      }
    VoidExpense =>
      if model.expense_id == "" ||
        (model.expense_state != "草稿" && model.expense_state != "已驳回") {
        (none, model)
      } else {
        (
          @http.post("/api/company/expenses/\{model.expense_id}/void")
          .with_text(
            "{\"idempotency_key\":\"rabbita-expense-void-v1\",\"reason\":\"本地演示作废报销\"}",
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
            expense_note: "正在作废本地报销投影并写入审计…",
          },
        )
      }
    CheckExpenseBudget =>
      if model.expense_state == "未创建" || model.expense_state == "草稿" {
        (
          @http.post("/api/company/budget-check")
          .with_text(
            "{\"splits\":[{\"costSubjectCode\":\"CB-101\",\"amount\":8560}]}",
          )
          .expect_text(result => {
            match result {
              Ok(body) => emit(ExpenseBudgetCheckFinished(body))
              Err(_) => emit(ExpenseBudgetCheckFailed)
            }
          }),
          {
            ..model,
            expense_budget_check_note: "正在读取 PostgreSQL 预算余量…",
          },
        )
      } else {
        (none, model)
      }
    ExpenseBudgetCheckFinished(body) =>
      (
        none,
        {
          ..model,
          expense_budget_check_note: if body.contains("\"willOver\":true") {
            "预算预检：当前科目可能超预算 · 仅提示，不占用预算"
          } else if body.contains("\"matched\":false") {
            "预算预检：科目未在源 CBS 中匹配 · 仅提示，不占用预算"
          } else {
            "预算预检通过 · 仅提示，不占用预算"
          },
        },
      )
    ExpenseBudgetCheckFailed =>
      (
        none,
        {
          ..model,
          expense_budget_check_note: "预算预检不可用 · 未执行预算占用",
        },
      )
    SubmitExpense =>
      if model.expense_id == "" || model.expense_state != "草稿" {
        (none, model)
      } else {
        (
          @http.post(
            "/api/company/expenses/\{model.expense_id}/submit-for-approval",
          )
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
      if body.contains("\"state\":\"voided\"") {
        (
          none,
          {
            ..model,
            expense_state: "已作废",
            expense_note: "已写入 PostgreSQL · 本地报销已作废 · 未触发现金或会计处理",
          },
        )
      } else if body.contains("\"state\":\"approved\"") {
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
fn dashboard_v2_trend_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.dashboard_v2_trend_rows.length() == 0 {
    rows.push(["—", "0", "0"])
  } else {
    for row in model.dashboard_v2_trend_rows {
      rows.push([row.month, row.plan, row.actual])
    }
  }
  data_table(["月份", "计划付款", "实际付款"], rows)
}

///|
fn dashboard_v2_stage_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.dashboard_v2_stage_rows.length() == 0 {
    rows.push(["—", "0"])
  } else {
    for row in model.dashboard_v2_stage_rows {
      rows.push([row.stage, row.count])
    }
  }
  data_table(["阶段", "项目数"], rows)
}

///|
fn dashboard_v2_warning_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.dashboard_v2_warning_rows.length() == 0 {
    rows.push(["—", "0", "源表为空"])
  } else {
    for row in model.dashboard_v2_warning_rows {
      rows.push([row.title, row.severity, row.source_kind])
    }
  }
  data_table(["预警", "级别", "来源"], rows)
}

///|
fn dashboard_v2_panel(model : Model) -> @html.Html {
  if model.dashboard_v2_loaded {
    div(class="erp-dashboard-v2-grid") <| [
      table_panel(
        "驾驶舱 v2 · 经营指标",
        model.dashboard_v2_note +
        " · 缺失/空源表 " +
        model.dashboard_v2_missing_table_count,
        data_table(
          [
            "项目数", "在建项目", "进行中合同额", "未付金额", "开放预警",
            "运行流程",
          ],
          [
            [
              model.dashboard_v2_project_count,
              model.dashboard_v2_in_progress,
              model.dashboard_v2_contract_amount,
              model.dashboard_v2_unpaid_amount,
              model.dashboard_v2_open_warnings,
              model.dashboard_v2_running_processes,
            ],
          ],
        ),
      ),
      table_panel(
        "付款趋势",
        "源计划与已审核付款 · 仅读观察",
        dashboard_v2_trend_table(model),
      ),
      table_panel(
        "阶段分布",
        "按当前项目状态分组",
        dashboard_v2_stage_table(model),
      ),
      table_panel(
        "最新预警",
        "源预警行为空时保持空状态",
        dashboard_v2_warning_table(model),
      ),
    ]
  } else {
    div(class="erp-runtime-empty dashboard-v2-empty", model.dashboard_v2_note)
  }
}

///|
fn dashboard_v3_pair_table(
  headers : Array[String],
  rows : Array[DashboardV3PairRow],
) -> @html.Html {
  let rendered : Array[Array[String]] = []
  if rows.length() == 0 {
    rendered.push(["—", "源表为空"])
  } else {
    for row in rows {
      rendered.push([row.label, row.value])
    }
  }
  data_table(headers, rendered)
}

///|
fn dashboard_v3_panel(model : Model) -> @html.Html {
  if model.dashboard_v3_loaded {
    let snapshot = model.dashboard_v3
    let city_rows : Array[Array[String]] = []
    if snapshot.city_rows.length() == 0 {
      city_rows.push(["—", "0", "0"])
    } else {
      for row in snapshot.city_rows {
        city_rows.push([row.name, row.expense, row.revenue])
      }
    }
    let contract_rows : Array[Array[String]] = []
    for row in snapshot.top_unpaid_rows {
      contract_rows.push(["已签/付款", row.code, row.name, row.amount])
    }
    for row in snapshot.top_approving_rows {
      contract_rows.push(["审批中", row.code, row.name, row.amount])
    }
    if contract_rows.length() == 0 {
      contract_rows.push(["—", "—", "源表为空", "0"])
    }
    div(class="erp-dashboard-v2-grid") <| [
      table_panel(
        "驾驶舱 v3 · 综合指标",
        model.dashboard_v3_note +
        " · " +
        snapshot.scope +
        " · 缺失/空源表 " +
        snapshot.missing_table_count,
        data_table(
          [
            "健康评分", "收入", "支出", "净利润", "利润率", "现金月数",
            "客户", "签约", "放款", "进行中进度", "进行中招标", "开放预警",
            "运行流程",
          ],
          [
            [
              snapshot.health_score,
              snapshot.total_revenue,
              snapshot.total_expense,
              snapshot.net_profit,
              snapshot.net_profit_rate,
              snapshot.cashflow_months,
              snapshot.customer_count,
              snapshot.signed_count,
              snapshot.mortgage_count,
              snapshot.progress_active + "/" + snapshot.progress_done,
              snapshot.tender_active_count,
              snapshot.open_warnings,
              snapshot.running_processes,
            ],
          ],
        ),
      ),
      table_panel(
        "健康评分拆解",
        "评分 / 权重 · 源观察",
        dashboard_v3_pair_table(
          ["维度", "评分 / 权重"],
          snapshot.health_rows,
        ),
      ),
      table_panel(
        "费用按科目",
        "金额单位：万元 · 缺失科目保持空状态",
        dashboard_v3_pair_table(["科目", "金额"], snapshot.expense_rows),
      ),
      table_panel(
        "公司费用与收入",
        "公司级源行 · 金额单位：万元",
        data_table(["公司", "费用", "收入"], city_rows),
      ),
      table_panel(
        "销售漏斗",
        "客户、认筹、签约、放款、退房",
        dashboard_v3_pair_table(["阶段", "数量"], snapshot.funnel_rows),
      ),
      table_panel(
        "合同重点",
        "已签/付款与审批中合同 · 金额按源接口展示",
        data_table(
          ["状态", "合同号", "合同名称", "金额"],
          contract_rows,
        ),
      ),
      table_panel(
        "预算与资金缺口",
        "超预算与负向资金计划均为源观察",
        dashboard_v3_pair_table(
          ["项目", "数值"],
          snapshot.top_overbudget_rows,
        ),
      ),
      table_panel(
        "资金缺口周期",
        "计划净额 < 0 的周期",
        dashboard_v3_pair_table(["周期", "净额"], snapshot.top_gap_rows),
      ),
    ]
  } else {
    div(class="erp-runtime-empty dashboard-v2-empty", model.dashboard_v3_note)
  }
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
    if model.page == "/dashboard-v3" {
      dashboard_v3_panel(model)
    } else {
      dashboard_v2_panel(model)
    },
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
fn import_label(biz_type : String) -> String {
  if biz_type == "project" {
    "项目"
  } else {
    "合同"
  }
}

///|
fn import_preview_table(model : Model) -> @html.Html {
  if model.import_biz_type == "" || model.import_headers.length() == 0 {
    div(class="erp-runtime-empty", "选择 CSV 后显示前五行预览")
  } else {
    data_table(model.import_headers, model.import_preview_rows)
  }
}

///|
fn import_step_class(active_step : Int, step : Int) -> String {
  if step < active_step {
    "erp-import-step is-done"
  } else if step == active_step {
    "erp-import-step is-active"
  } else {
    "erp-import-step"
  }
}

///|
fn import_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
  biz_type : String,
) -> @html.Html {
  let active = model.import_biz_type == biz_type
  let selected_rows = if active { model.import_row_count } else { "0" }
  let note = if active {
    model.import_note
  } else {
    "尚未选择 " + import_label(biz_type) + " CSV 文件"
  }
  let active_step = if active &&
    (
      model.import_state == "dry_run" ||
      model.import_state == "dry_run_ok" ||
      model.import_state == "committing" ||
      model.import_state == "committed"
    ) {
    2
  } else if active && model.import_state != "idle" {
    1
  } else {
    0
  }
  section(class="erp-table-panel erp-import-panel") <| [
    div(class="erp-panel-heading") <| [
      div <| [
        h2("批量导入" + import_label(biz_type)),
        span(
          class="erp-panel-subtitle",
          "选择 CSV → 试运行 → 提交事务",
        ),
      ],
      span(class="erp-info-tag", note),
    ],
    div(class="erp-import-steps") <| [
      span(class=import_step_class(active_step, 0), "1 选择 CSV"),
      span(class=import_step_class(active_step, 1), "2 试运行校验"),
      span(class=import_step_class(active_step, 2), "3 提交导入"),
    ],
    div(class="erp-command-bar") <| [
      label(class="erp-import-file-picker") <| [
        input(
          input_type=@html.InputType::File,
          accept=".csv,text/csv",
          id=import_input_id(biz_type),
          class="erp-import-file-input",
          on_change=emit.map(file_name => SelectImportFile(biz_type, file_name)),
        ),
        span("选择 CSV 文件"),
      ],
      button(
        class="erp-secondary-btn",
        on_click=emit(DownloadImportTemplate(biz_type)),
        "下载模板",
      ),
      button(
        class="erp-secondary-btn",
        disabled=!(active && model.import_state == "ready"),
        on_click=emit(RunImportDryRun),
        "试运行校验",
      ),
      button(
        class="erp-primary-btn",
        disabled=!(active && model.import_state == "dry_run_ok"),
        on_click=emit(CommitImportBatch),
        "提交导入",
      ),
    ],
    div(class="erp-source-note", [
      span(
        if active && model.import_file_name != "" {
          model.import_file_name + " · " + selected_rows + " 行"
        } else {
          "单次最多 500 行；导入记录写入 command projection，不触发现金/会计/税务"
        },
      ),
    ]),
    import_preview_table(if active { model } else { initial_model() }),
  ]
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
      button(
        class="erp-secondary-btn",
        on_click=emit(DownloadImportTemplate("project")),
        "下载导入模板",
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
        span(" · " + model.import_template_note),
      ]),
      div(class="erp-stat-grid") <| [
        metric("项目总数", "15", "在建项目", "metric-blue"),
        metric("本月新增", "2", "较上月 +1", "metric-blue"),
        metric("建设中", "9", "占比 60%", "metric-green"),
      ],
      import_panel(emit, model, "project"),
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
  let source_row_count = if model.delivery_source_loaded {
    model.delivery_source_progress_count +
    "/" +
    model.delivery_source_output_count
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
    span(" · 源进度/产值 " + source_row_count + " 行"),
    span(" · " + model.delivery_source_note),
    span(" · " + model.delivery_note),
    span(" · " + model.delivery_command_note),
  ])
}

///|
fn plan_ai_suggestion_rows_from_body(body : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "nodes") {
            match value {
              Json::Object(node) =>
                rows.push([
                  json_object_text(node, "name", "—"),
                  json_object_text(node, "offsetDays", "0"),
                  json_object_text(node, "ownerRole", "—"),
                  json_object_text(node, "planEndDate", "—"),
                ])
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
fn plan_delay_rows_from_body(body : String) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "impact") {
            match value {
              Json::Object(item) =>
                rows.push([
                  json_object_text(item, "taskName", "—"),
                  json_object_text(item, "taskType", "task"),
                  json_object_text(item, "oldBegin", "—"),
                  json_object_text(item, "newBegin", "—"),
                  json_object_text(item, "oldEnd", "—"),
                  json_object_text(item, "newEnd", "—"),
                ])
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
fn project_plan_csv(model : Model) -> String {
  let mut csv = "编码,名称,类型,项目,计划开始,计划完成,实际开始,实际完成,进度,状态,责任人,来源\n"
  for task in model.delivery_task_rows {
    csv = csv +
      task.task_code +
      "," +
      task.task_name +
      "," +
      task.task_type +
      "," +
      task.project_id +
      "," +
      task.plan_begin_date +
      "," +
      task.plan_end_date +
      "," +
      task.actual_begin_date +
      "," +
      task.actual_end_date +
      "," +
      task.progress_pct +
      "," +
      project_plan_status_text(task.status) +
      "," +
      task.owner_name +
      "," +
      task.source_kind +
      "\n"
  }
  csv
}

///|
fn delivery_progress_table(model : Model) -> @html.Html {
  let rows_to_render = if model.delivery_source_progress_rows.length() > 0 {
    model.delivery_source_progress_rows
  } else {
    model.delivery_progress_rows
  }
  if !model.delivery_loaded && rows_to_render.length() == 0 {
    div(class="erp-runtime-empty", "等待 PostgreSQL 工程进度投影")
  } else {
    let rows : Array[Array[String]] = []
    for row in rows_to_render {
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
      if model.delivery_source_progress_rows.length() > 0 {
        "ERP 源工程进度"
      } else {
        "当前 PostgreSQL 工程进度"
      },
      if model.delivery_source_progress_rows.length() > 0 {
        "源记录只读 · 项目范围 " + model.delivery_project_id
      } else {
        "源记录只读 · 本地命令需要证据并保留审计"
      },
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
  let rows_to_render = if model.delivery_source_output_rows.length() > 0 {
    model.delivery_source_output_rows
  } else {
    model.delivery_output_rows
  }
  for row in rows_to_render {
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
    if model.delivery_source_output_rows.length() > 0 {
      "ERP 源产值确认"
    } else {
      "产值确认"
    },
    if model.delivery_source_output_rows.length() > 0 {
      "源记录只读 · 项目范围 " + model.delivery_project_id
    } else {
      "确认不等于入账 · 需要独立证据"
    },
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
fn plan_ai_suggestion_table(model : Model) -> @html.Html {
  let rows = if model.plan_ai_suggestion_rows.length() == 0 {
    [["—", "—", "—", "尚未生成"]]
  } else {
    model.plan_ai_suggestion_rows
  }
  table_panel(
    "AI 计划建议候选",
    model.plan_ai_suggestion_note + " · 不写入项目计划/工作流",
    data_table(["节点", "偏移天数", "责任角色", "计划完成"], rows),
  )
}

///|
fn project_plan_status_text(status : String) -> String {
  match status {
    "done" => "已完成"
    "in_progress" => "进行中"
    "pending" => "未开始"
    "overdue" => "已延期"
    "blocked" => "阻塞"
    "deleted" => "已作废"
    _ => status
  }
}

///|
fn project_plan_project_picker(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let buttons : Array[@html.Html] = []
  if model.project_rows.length() == 0 {
    buttons.push(
      span(
        class="erp-source-note",
        "项目列表尚未加载 · 当前范围 " +
        model.project_plan_project_id,
      ),
    )
  } else {
    for row in model.project_rows {
      buttons.push(
        button(
          class=if row.project_id == model.project_plan_project_id {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(InputProjectPlanProject(row.project_id)),
          row.project_code + " · " + row.project_name,
        ),
      )
    }
  }
  div(class="erp-project-picker") <| buttons
}

///|
fn project_plan_gantt(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  if model.delivery_task_rows.length() == 0 {
    rows.push(
      div(class="erp-runtime-empty", "当前项目暂无计划任务源记录"),
    )
  } else {
    for task in model.delivery_task_rows {
      let task_label = if task.task_type == "key_node" {
        "节点 · " + task.task_name
      } else {
        task.task_name
      }
      let width = if task.progress_pct == "0" {
        "8%"
      } else {
        task.progress_pct + "%"
      }
      rows.push(
        div(
          class="erp-gantt-row" +
            (if task.parent_task_id.is_empty() { "" } else { " is-subtask" }) +
            (if task.delayed { " is-delayed" } else { "" }),
        ) <| [
          div(class="erp-gantt-label") <| [
            strong(
              (if task.parent_task_id.is_empty() { "" } else { "↳ " }) +
              task_label,
            ),
            span(task.plan_begin_date + " → " + task.plan_end_date),
            if task.owner_name.is_empty() {
              span("")
            } else {
              span("@" + task.owner_name)
            },
          ],
          div(class="erp-gantt-track") <| [
            button(
              class="erp-gantt-bar status-" + task.status,
              style=["width: " + width],
              on_click=emit(SelectPlanTask(task.task_id, task.task_name)),
              task.progress_pct + "%",
            ),
          ],
        ],
      )
    }
  }
  section(class="erp-gantt") <| [
    div(class="erp-gantt-axis") <| [
      strong("任务 / 责任人"),
      span("计划时间轴 · " + model.project_plan_project_id),
    ],
    div(class="erp-gantt-body") <| rows,
  ]
}

///|
fn project_plan_task_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  for task in model.delivery_task_rows {
    rows.push(
      tr <| [
        td(task.task_code),
        td(task.task_name),
        td(task.task_type),
        td(task.project_id),
        td(task.plan_begin_date + " ~ " + task.plan_end_date),
        td(
          task.actual_begin_date +
          (if task.actual_end_date.is_empty() {
            ""
          } else {
            " ~ " + task.actual_end_date
          }),
        ),
        td(task.progress_pct + "%"),
        td(class="erp-status-tag", project_plan_status_text(task.status)),
        td(task.owner_name),
        td(task.source_kind),
        td <| [
          button(
            class="erp-link-btn",
            on_click=emit(SelectPlanTask(task.task_id, task.task_name)),
            "回填",
          ),
          button(
            class="erp-link-btn is-warning",
            on_click=emit(SelectPlanTask(task.task_id, task.task_name)),
            "延期影响",
          ),
        ],
      ],
    )
  }
  table_panel(
    "关键节点清单",
    "源计划任务只读 · 选择任务后可回填进度或计算延期影响",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "编码", "名称", "类型", "项目", "计划期间", "实际期间",
          "进度", "状态", "责任人", "来源", "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn project_plan_forms(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  div(class="erp-plan-form-grid") <| [
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("进度汇报"),
        span(class="erp-info-tag", model.delivery_command_note),
      ],
      form_field(
        "任务",
        model.plan_report_task_name,
        "先在表格中选择任务",
      ),
      div(class="erp-form-grid") <| [
        editable_form_field(
          "进度 %",
          model.plan_report_progress,
          "0 - 100",
          @html.InputType::Text,
          emit.map(value => InputPlanReportProgress(value)),
        ),
        editable_form_field(
          "汇报日期",
          model.plan_report_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputPlanReportDate(value)),
        ),
      ],
      editable_form_field(
        "工作说明",
        model.plan_report_summary,
        "本次汇报的工作内容",
        @html.InputType::Text,
        emit.map(value => InputPlanReportSummary(value)),
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(ReportTaskProgress),
        "提交汇报",
      ),
    ],
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新建任务 / 节点"),
        span(class="erp-info-tag", model.plan_task_command_note),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class=if model.plan_create_task_type == "task" {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(InputPlanCreateTaskType("task")),
          "普通任务",
        ),
        button(
          class=if model.plan_create_task_type == "key_node" {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(InputPlanCreateTaskType("key_node")),
          "关键节点",
        ),
      ],
      editable_form_field(
        "名称",
        model.plan_create_task_name,
        "任务名称",
        @html.InputType::Text,
        emit.map(value => InputPlanCreateTaskName(value)),
      ),
      div(class="erp-form-grid") <| [
        editable_form_field(
          "编码",
          model.plan_create_task_code,
          "可省略",
          @html.InputType::Text,
          emit.map(value => InputPlanCreateTaskCode(value)),
        ),
        editable_form_field(
          "责任人",
          model.plan_create_owner,
          "用户 ID",
          @html.InputType::Text,
          emit.map(value => InputPlanCreateOwner(value)),
        ),
        editable_form_field(
          "计划开始",
          model.plan_create_begin_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputPlanCreateBeginDate(value)),
        ),
        editable_form_field(
          "计划完成",
          model.plan_create_end_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputPlanCreateEndDate(value)),
        ),
      ],
      editable_form_field(
        "备注",
        model.plan_create_remarks,
        "任务备注",
        @html.InputType::Text,
        emit.map(value => InputPlanCreateRemarks(value)),
      ),
      button(class="erp-primary-btn", on_click=emit(CreatePlanTask), "创建"),
    ],
  ]
}

///|
fn project_plan_ai_and_delay(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let delay_rows : Array[@html.Html] = []
  for row in model.plan_delay_rows {
    delay_rows.push(table_row(row))
  }
  div(class="erp-plan-form-grid") <| [
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("AI 排程建议"),
        span(class="erp-info-tag", "native-deterministic · 不自动写入"),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "项目类型",
          model.plan_ai_proj_type,
          "住宅 / 商业",
          @html.InputType::Text,
          emit.map(value => InputPlanAiProjectType(value)),
        ),
        editable_form_field(
          "规模",
          model.plan_ai_scale,
          "小型 / 中型 / 大型",
          @html.InputType::Text,
          emit.map(value => InputPlanAiScale(value)),
        ),
        editable_form_field(
          "区域",
          model.plan_ai_region,
          "天津 / 重庆",
          @html.InputType::Text,
          emit.map(value => InputPlanAiRegion(value)),
        ),
        editable_form_field(
          "开始日期",
          model.plan_ai_begin_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputPlanAiBeginDate(value)),
        ),
      ],
      button(
        class="erp-secondary-btn",
        on_click=emit(SuggestProjectPlan),
        "生成 7 节点",
      ),
      plan_ai_suggestion_table(model),
    ],
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("延期影响分析"),
        span(class="erp-info-tag", "只读计算 · 不修改任务"),
      ],
      p(class="erp-source-note", "当前任务：" + model.plan_delay_task_id),
      editable_form_field(
        "延期天数",
        model.plan_delay_days,
        "1 - 365",
        @html.InputType::Text,
        emit.map(value => InputPlanDelayDays(value)),
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RunPlanDelayImpact),
        "计算影响",
      ),
      p(class="erp-dashboard-note", model.plan_delay_note),
      if model.plan_delay_rows.length() == 0 {
        div(class="erp-runtime-empty", "暂无后续任务影响")
      } else {
        table(class="erp-data-table") <| [
          thead <| [
            table_header([
              "后续任务", "类型", "原开始", "新开始", "原完成", "新完成",
            ]),
          ],
          tbody <| delay_rows,
        ]
      },
    ],
  ]
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
        on_click=emit(Navigate("/project-plan")),
        "刷新计划",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateDeliveryProgress),
        "＋ 新建进度记录",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExportPlanCsv),
        "导出 CSV",
      ),
      if model.plan_task_id != "" && model.plan_task_state != "pending" {
        button(
          class="erp-primary-btn",
          on_click=emit(UpdatePlanTask),
          "更新本地任务",
        )
      } else {
        span("")
      },
      if model.plan_task_id != "" && model.plan_task_state != "pending" {
        button(
          class="erp-secondary-btn",
          on_click=emit(DeletePlanTask),
          "作废本地任务",
        )
      } else {
        span("")
      },
    ],
    div <| [
      delivery_runtime_banner(model),
      div(class="erp-runtime-banner") <| [
        strong("PostgreSQL 项目计划"),
        span(" · 项目 " + model.project_plan_project_id),
        span(" · " + model.plan_task_command_note),
      ],
      project_plan_project_picker(emit, model),
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "计划总览"),
        button(class="erp-tab", "甘特图"),
        button(class="erp-tab", "关键节点"),
      ],
      project_plan_gantt(emit, model),
      project_plan_task_table(emit, model),
      project_plan_forms(emit, model),
      project_plan_ai_and_delay(emit, model),
    ],
  )
}

///|
fn delivery_form_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.delivery_form_open == "progress" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增进度节点"),
        span(
          class="erp-source-note",
          "写入本地进度命令投影 · 导入源行保持只读",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "楼栋号",
          model.delivery_building_no,
          "1-1",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("building_no", value)),
        ),
        editable_form_field(
          "阶段名",
          model.delivery_stage,
          "主体结构 / 竣工备案",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("stage", value)),
        ),
        editable_form_field(
          "计划日期",
          model.delivery_plan_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("plan_date", value)),
        ),
        editable_form_field(
          "计划完成%",
          model.delivery_plan_pct,
          "0 - 100",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("plan_pct", value)),
        ),
        editable_form_field(
          "关联合同",
          model.delivery_contract_id,
          "合同 GUID",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("contract_id", value)),
        ),
        editable_form_field(
          "备注",
          model.delivery_remark,
          "现场说明",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseDeliveryForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateDeliveryProgress),
          "新增进度节点",
        ),
      ],
    ]
  } else if model.delivery_form_open == "report" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("上报进度"),
        span(
          class="erp-source-note",
          "实际进度需要现场证据 · 不直接修改导入源状态",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "进度记录 ID",
          model.delivery_progress_id,
          "本地进度 GUID",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("progress_id", value)),
        ),
        editable_form_field(
          "实际完成%",
          model.delivery_report_actual_pct,
          "0 - 100",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("report_actual_pct", value)),
        ),
        editable_form_field(
          "实际日期",
          model.delivery_report_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("report_date", value)),
        ),
        editable_form_field(
          "说明",
          model.delivery_report_remark,
          "现场复核说明",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("report_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseDeliveryForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(ReportDeliveryProgress),
          "提交进度",
        ),
      ],
    ]
  } else if model.delivery_form_open == "output" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("上报产值"),
        span(class="erp-source-note", "确认后才可进入付款节点候选"),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "关联合同",
          model.delivery_output_contract_id,
          "合同 GUID",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("output_contract_id", value)),
        ),
        editable_form_field(
          "期间",
          model.delivery_output_period,
          "YYYY-MM",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("output_period", value)),
        ),
        editable_form_field(
          "产值金额（元）",
          model.delivery_output_amount,
          "125000",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("output_amount", value)),
        ),
        editable_form_field(
          "备注",
          model.delivery_output_remark,
          "计量说明",
          @html.InputType::Text,
          emit.map(value => InputDeliveryField("output_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseDeliveryForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateDeliveryOutput),
          "上报产值",
        ),
      ],
    ]
  } else {
    @html.nothing
  }
}

///|
fn progress_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let project_picker : Array[@html.Html] = []
  if model.project_rows.length() == 0 {
    project_picker.push(
      span(
        class="erp-source-note",
        "项目列表尚未加载 · 当前范围 " + model.delivery_project_id,
      ),
    )
  } else {
    for row in model.project_rows {
      project_picker.push(
        button(
          class=if row.project_id == model.delivery_project_id {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(SelectDeliveryProject(row.project_id)),
          row.project_code + " · " + row.project_name,
        ),
      )
    }
  }
  page_shell(
    "工程进度",
    "PROJECT PROGRESS",
    "对照计划日期与实际完成率跟踪楼栋、施工阶段和交付节点。",
    [
      button(class="erp-secondary-btn", "导出进度表"),
      button(
        class="erp-primary-btn",
        on_click=emit(OpenDeliveryForm("progress")),
        "＋ 更新进度",
      ),
    ],
    div <| [
      delivery_runtime_banner(model),
      delivery_form_view(emit, model),
      div(class="erp-project-picker") <| project_picker,
      div(class="erp-tabs") <| [
        button(
          class=if model.delivery_tab == "progress" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectDeliveryTab("progress")),
          "形象进度",
        ),
        button(
          class=if model.delivery_tab == "outputs" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectDeliveryTab("outputs")),
          "产值确认",
        ),
        button(
          class=if model.delivery_tab == "reports" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectDeliveryTab("reports")),
          "任务汇报",
        ),
      ],
      if model.delivery_tab == "progress" {
        div <| [
          delivery_progress_table(model),
          div(class="erp-inline-actions") <| [
            button(
              class="erp-secondary-btn",
              on_click=emit(OpenDeliveryForm("report")),
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
          ],
        ]
      } else if model.delivery_tab == "outputs" {
        div <| [
          delivery_outputs_table(model),
          div(class="erp-inline-actions") <| [
            button(
              class="erp-secondary-btn",
              on_click=emit(OpenDeliveryForm("output")),
              "登记产值",
            ),
            button(
              class="erp-secondary-btn",
              on_click=emit(ConfirmDeliveryOutput),
              "确认产值",
            ),
          ],
        ]
      } else {
        delivery_reports_table(model)
      },
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
fn workflow_observation_rows_for(
  rows : Array[WorkflowObservationRow],
) -> Array[Array[String]] {
  let result : Array[Array[String]] = []
  for row in rows {
    result.push([
      row.process_name +
      " · " +
      row.biz_type +
      " · " +
      row.process_instance_guid,
      row.current_step_order +
      (if row.current_step_name == "" {
        ""
      } else {
        " · " + row.current_step_name
      }),
      if row.initiator_name == "" {
        "—"
      } else {
        row.initiator_name
      },
      row.initiated_at,
      row.biz_data_guid,
      row.status + (if row.decision == "" { "" } else { " · " + row.decision }),
      if row.last_action_time == "" {
        row.completed_at
      } else {
        row.last_action_time
      },
      "观察 · " + row.source_kind,
    ])
  }
  if result.length() == 0 {
    result.push([
      "—", "—", "—", "—", "—", "无源实例", "—", "source rows=0",
    ])
  }
  result
}

///|
fn workflow_ticket_table_rows(model : Model) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  for ticket in model.workflow_ticket_rows {
    rows.push([
      ticket.ticket_id +
      (if ticket.warning_guid == "" {
        ""
      } else {
        " · " + ticket.warning_guid
      }),
      (if ticket.title == "" { ticket.rule_name } else { ticket.title }) +
      (if ticket.rule_code == "" { "" } else { " · " + ticket.rule_code }),
      ticket.severity,
      ticket.status,
      ticket.due_date,
      if ticket.assignee_user_id == "" {
        "—"
      } else {
        ticket.assignee_user_id
      },
      ticket.created_at +
      (if ticket.created_by == "" { "" } else { " · " + ticket.created_by }),
      if ticket.handled_at == "" {
        ticket.note
      } else {
        ticket.handled_at
      },
      ticket.source_kind +
      (if ticket.biz_type == "" {
        ""
      } else {
        " · " + ticket.biz_type + "/" + ticket.biz_data_guid
      }),
    ])
  }
  if rows.length() == 0 {
    rows.push([
      "—", "—", "—", "—", "—", "—", "—", "无源工单", "source rows=0",
    ])
  }
  rows
}

///|
fn workflow_task_table(
  title : String,
  subtitle : String,
  rows : Array[WorkflowObservationRow],
) -> @html.Html {
  table_panel(
    title,
    subtitle,
    data_table(
      [
        "流程 / 业务类型", "当前步骤", "发起人", "发起时间", "业务单据",
        "状态 / 我的决定", "最近动作", "来源",
      ],
      workflow_observation_rows_for(rows),
    ),
  )
}

///|
fn tasks_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let task_content = if model.workflow_task_tab == "initiated" {
    workflow_task_table(
      "已发起流程",
      "只显示当前用户发起的流程实例 · 源读模型不授予操作权限",
      model.workflow_initiated_rows,
    )
  } else if model.workflow_task_tab == "history" {
    workflow_task_table(
      "审批历史",
      "按当前用户动作过滤 · 详情与附件仍保持源观察边界",
      model.workflow_history_rows,
    )
  } else if model.workflow_task_tab == "tickets" {
    table_panel(
      "告警任务",
      model.workflow_ticket_note +
      " · 告警任务命令不会触发通知、资金、会计或税务",
      data_table(
        [
          "工单", "告警", "等级", "状态", "截止时间", "负责人", "创建时间",
          "处理备注", "来源",
        ],
        workflow_ticket_table_rows(model),
      ),
    )
  } else {
    workflow_task_table(
      "待办事项",
      "按 PostgreSQL 源任务观察展示 · 审批动作仍标记为候选",
      if model.workflow_observation_loaded ||
        model.workflow_pending_rows.length() > 0 {
        model.workflow_pending_rows
      } else {
        []
      },
    )
  }
  page_shell(
    "我的待办",
    "WORKFLOW",
    "集中处理报销、借款、付款申请与项目协同任务，查看发起记录和审批历史。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(StartWorkflowCandidate),
        "＋ 发起流程（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ApproveWorkflowCandidate),
        "审批（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RejectWorkflowCandidate),
        "驳回（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CosignWorkflowCandidate),
        "会签（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(TransferWorkflowCandidate),
        "转办（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateWarningTicket),
        "创建告警工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(HandleWarningTicket),
        "开始处理工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CompleteWarningTicket),
        "完成工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ReassignWarningTicket),
        "转派工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExtendWarningTicket),
        "延期工单（候选）",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.workflow_observation_loaded {
            "PostgreSQL 工作流定义与实例观察已连接"
          } else if model.workflow_loaded {
            "PostgreSQL 工作流定义已连接"
          } else {
            "工作流读模型"
          },
        ),
        span(
          " · " +
          model.workflow_note +
          " · " +
          model.workflow_observation_note +
          " · 待办 " +
          model.workflow_pending_rows.length().to_string() +
          " · 已发起 " +
          model.workflow_initiated_rows.length().to_string() +
          " · 历史 " +
          model.workflow_history_rows.length().to_string(),
        ),
        p(model.workflow_command_note),
      ]),
      div(class="erp-tabs") <| [
        button(
          class=if model.workflow_task_tab == "pending" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectWorkflowTab("pending")),
          "待办 (" + model.workflow_pending_rows.length().to_string() + ")",
        ),
        button(
          class=if model.workflow_task_tab == "initiated" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectWorkflowTab("initiated")),
          "已发起 (" +
          model.workflow_initiated_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.workflow_task_tab == "history" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectWorkflowTab("history")),
          "审批历史 (" +
          model.workflow_history_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.workflow_task_tab == "tickets" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectWorkflowTab("tickets")),
          "告警任务 (" +
          model.workflow_ticket_rows.length().to_string() +
          ")",
        ),
      ],
      task_content,
      workflow_runtime_table(model),
    ],
  )
}

///|
fn ai_hub_recent_rows(model : Model) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  for row in model.ai_hub_draft_rows {
    rows.push([
      "AI 起单 " + row.biz_type + " · " + row.draft_id,
      row.description,
      "置信度 " + row.confidence,
      row.created_at,
      row.status + " · " + row.source_kind,
    ])
  }
  for row in model.ai_hub_query_rows {
    rows.push([
      "AI 查询 · " + row.qid,
      row.question,
      if row.error == "" {
        row.explanation +
        " · " +
        row.row_count +
        " 行 · " +
        row.duration_ms +
        " ms"
      } else {
        "失败 · " + row.error
      },
      row.created_at,
      if row.error == "" {
        "已完成 · " + row.source_kind
      } else {
        "需复核 · " + row.source_kind
      },
    ])
  }
  for row in model.ai_hub_correction_rows {
    rows.push([
      "AI 修正 · " + row.biz_type,
      row.field_name,
      "历史值 " + row.llm_value + " → 人工值 " + row.user_value,
      row.created_at,
      "已记录 · " + row.source_kind,
    ])
  }
  rows
}

///|
fn ai_hub_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let recent_rows = if model.ai_hub_loaded {
    let source_rows = ai_hub_recent_rows(model)
    if source_rows.length() == 0 {
      [["—", "—", "—", "—", "无源记录"]]
    } else {
      source_rows
    }
  } else {
    [
      [
        "合同要素识别", "南山居施工合同.pdf", "识别 32 个字段",
        "今天 09:12", "设计快照",
      ],
      [
        "现金流问答", "未来 90 天资金缺口？", "预计峰值 ¥2,180 万",
        "昨天 17:06", "设计快照",
      ],
      [
        "发票 OCR", "invoice_20260712.jpg", "待确认 1 个税号", "昨天 15:44",
        "待处理",
      ],
    ]
  }
  page_shell(
    "AI 工作台",
    "AI HUB",
    "把文件、自然语言问题和业务动作放进同一个工作台，AI 结果仍需业务人员确认后写入。",
    [
      button(class="erp-primary-btn", "＋ 上传文件"),
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/ai-hub")),
        "刷新源读模型",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.ai_hub_loaded {
            "PostgreSQL AI Hub 已连接"
          } else {
            "AI Hub 读模型"
          },
        ),
        span(" · " + model.ai_hub_note),
        span(" · provider/LLM/OCR 执行：未授权"),
      ]),
      div(class="erp-stat-grid") <| [
        metric(
          "本月调用",
          if model.ai_hub_loaded {
            model.ai_hub_monthly_calls
          } else {
            "—"
          },
          if model.ai_hub_loaded {
            "源 audit/query 统计"
          } else {
            "等待源读模型"
          },
          "metric-blue",
        ),
        metric(
          "节省分钟",
          if model.ai_hub_loaded {
            model.ai_hub_minutes_saved
          } else {
            "—"
          },
          "按源调用记录估算",
          "metric-green",
        ),
        metric(
          "累计起单",
          if model.ai_hub_loaded {
            model.ai_hub_intake_total
          } else {
            "—"
          },
          "只读确认记录",
          "metric-blue",
        ),
        metric(
          "草稿/问数",
          if model.ai_hub_loaded {
            (model.ai_hub_draft_rows.length() + model.ai_hub_query_rows.length()).to_string()
          } else {
            "—"
          },
          if model.ai_hub_loaded {
            "修正 " +
            model.ai_hub_correction_total +
            " · 率 " +
            model.ai_hub_correction_rate
          } else {
            "源历史条目"
          },
          "metric-blue",
        ),
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("统一命令面板"),
          span(
            class="erp-info-tag",
            "自然语言 · 仍需 AI 负责人确认",
          ),
        ],
        div(class="erp-command-bar") <| [
          input(
            input_type=@html.InputType::Text,
            value=model.ai_hub_command_text,
            placeholder="例如：打开成本驾驶舱 / 海教园付款 540 万",
            class="erp-form-input erp-command-input",
            on_input=emit.map(value => InputAiHubCommandText(value)),
          ),
          button(
            class="erp-primary-btn",
            on_click=emit(RunAiHubCommand("command")),
            "执行候选",
          ),
        ],
        p(class="erp-source-note", model.ai_hub_command_note),
      ],
      div(class="erp-ai-grid") <| [
        section(class="erp-ai-card is-primary") <| [
          span(class="erp-ai-icon", "✦"),
          h2("AI 起单"),
          p(
            "拖入合同、发票或付款资料，自动识别业务类型并生成草稿。",
          ),
          input(
            input_type=@html.InputType::Text,
            value=model.ai_hub_intake_description,
            placeholder="描述业务，例如：海教园付款 540 万",
            class="erp-form-input",
            on_input=emit.map(value => InputAiHubIntakeDescription(value)),
          ),
          input(
            input_type=@html.InputType::Text,
            value=model.ai_hub_intake_biz_hint,
            placeholder="业务类型 expense / contract / loan",
            class="erp-form-input",
            on_input=emit.map(value => InputAiHubIntakeBizHint(value)),
          ),
          label(class="erp-import-file-picker") <| [
            input(
              input_type=@html.InputType::File,
              accept="image/*,.pdf,.xlsx,.doc,.docx",
              class="erp-import-file-input",
              on_change=emit.map(value => AiHubFileSelected(value)),
            ),
            span(
              if model.ai_hub_file_name.is_empty() {
                "选择输入文件"
              } else {
                model.ai_hub_file_name
              },
            ),
          ],
          button(
            class="erp-secondary-btn",
            on_click=emit(ExplainAiHub),
            "生成解释候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("intake")),
            "起单候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("confirm")),
            "确认候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("discard")),
            "丢弃候选",
          ),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⌁"),
          h2("AI 查询"),
          p(
            "用大白话查询项目、合同、成本和现金流，结果可追溯。",
          ),
          input(
            input_type=@html.InputType::Text,
            value=model.ai_hub_query_text,
            placeholder="例如：本月已签合同总额",
            class="erp-form-input",
            on_input=emit.map(value => InputAiHubQueryText(value)),
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("query")),
            "查询候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("query-session")),
            "会话查询候选",
          ),
        ],
        section(class="erp-ai-card") <| [
          span(class="erp-ai-icon", "⚑"),
          h2("风险洞察"),
          p("基于延期、成本偏差和付款异常生成风险清单。"),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("global-ask")),
            "全局问答候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("rule-from-nl")),
            "自然语言规则候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("approval-draft")),
            "审批草稿候选",
          ),
          button(
            class="erp-secondary-btn",
            on_click=emit(RunAiHubCommand("command")),
            "命令候选",
          ),
        ],
      ],
      table_panel(
        "最近 AI 任务",
        if model.ai_hub_loaded {
          "源历史只读 · 空源表 " +
          model.ai_hub_missing_table_count +
          " · 不触发起单、查询或命令"
        } else {
          "所有结果保留审计记录"
        },
        data_table(
          ["任务", "输入", "结果", "创建时间", "状态"],
          recent_rows,
        ),
      ),
      div(class="erp-runtime-banner", [
        strong("确定性解释候选"),
        span(" · " + model.ai_hub_explain_note),
      ]),
      div(class="erp-runtime-banner", [
        strong("AI Hub 命令门"),
        span(" · " + model.ai_hub_command_note),
        span(" · provider/LLM/query/业务写入均未授权"),
      ]),
      table_panel(
        "解释结果",
        "只读摘要 · 不持久化 prompt",
        data_table(["结果"], [[model.ai_hub_explain_text]]),
      ),
    ],
  )
}

///|
fn ai_stats_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let scene_rows = if model.ai_stats_loaded {
    if model.ai_stats_scene_rows.length() == 0 {
      [["—", "0", "—", "—", "—", "无源记录"]]
    } else {
      model.ai_stats_scene_rows
    }
  } else {
    [
      ["合同要素识别", "482", "418", "4.8s", "92.1%", "↑"],
      ["发票 OCR", "396", "324", "2.1s", "88.4%", "↑"],
      ["自然语言查询", "285", "—", "1.7s", "96.3%", "↑"],
      ["风险洞察", "123", "98", "6.2s", "79.7%", "→"],
    ]
  }
  let activity_rows = if model.ai_stats_loaded {
    if model.ai_stats_activity_rows.length() == 0 {
      [["—", "—", "—", "—", "无源记录"]]
    } else {
      model.ai_stats_activity_rows
    }
  } else {
    [
      [
        "intake", "AI 起单 contract", "置信度 96% · 由系统确认", "今天 09:12",
        "设计快照",
      ],
      [
        "query", "AI 智能问答", "未来 90 天资金缺口？ · 12 行", "昨天 17:06",
        "设计快照",
      ],
      [
        "skip", "AI 自动跳过审批步", "项目经理复核 — 条件满足",
        "昨天 15:44", "设计快照",
      ],
    ]
  }
  let intake = if model.ai_stats_loaded {
    model.ai_stats_intake_total
  } else {
    "1,286"
  }
  let accuracy = if model.ai_stats_loaded {
    model.ai_stats_accuracy + "%"
  } else {
    "86.2%"
  }
  let saved = if model.ai_stats_loaded {
    model.ai_stats_saved_hours + " 小时"
  } else {
    "214 小时"
  }
  let pending = if model.ai_stats_loaded {
    model.ai_stats_correction_total
  } else {
    "23"
  }
  page_shell(
    "AI 工作大盘",
    "AI ANALYTICS",
    "查看 AI 起单、查询、风险洞察的调用量、准确率和人工确认情况。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(ExportAiStats),
        "导出数据（XLSX）",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong("原生 XLSX 导出"),
        span(" · " + model.ai_stats_export_note),
      ]),
      div(class="erp-stat-grid") <| [
        metric(
          "本月调用",
          intake,
          if model.ai_stats_loaded {
            "源表起单记录"
          } else {
            "较上月 +18.4%"
          },
          "metric-blue",
        ),
        metric(
          "自动通过率",
          accuracy,
          if model.ai_stats_loaded {
            "源分析估算"
          } else {
            "目标 85%"
          },
          "metric-green",
        ),
        metric("节省人工", saved, "按确认记录估算", "metric-blue"),
        metric(
          "待确认",
          pending,
          if model.ai_stats_loaded {
            "修正记录"
          } else {
            "需要业务复核"
          },
          "metric-blue",
        ),
      ],
      table_panel(
        "场景使用情况",
        if model.ai_stats_loaded {
          model.ai_stats_note +
          " · 周期 " +
          model.ai_stats_period +
          " · 查询 " +
          model.ai_stats_query_total +
          " · 自动跳过 " +
          model.ai_stats_skip_total
        } else {
          "2026 年 7 月"
        },
        data_table(
          [
            "场景", "调用次数", "自动通过", "平均耗时", "准确率",
            "趋势",
          ],
          scene_rows,
        ),
      ),
      table_panel(
        "最近 AI 活动",
        if model.ai_stats_loaded {
          "来源活动只读 · provider 执行仍需授权 · 空源表 " +
          model.ai_stats_missing_table_count
        } else {
          "所有结果保留审计记录"
        },
        data_table(
          ["类型", "标题", "详情", "时间", "来源"],
          activity_rows,
        ),
      ),
    ],
  )
}

///|
fn sales_runtime_banner(model : Model, family : String) -> @html.Html {
  let active = if family == "subscriptions" {
    model.sales_subscription_loaded
  } else if family == "contracts" {
    model.sales_contract_loaded
  } else if family == "mortgages" {
    model.sales_mortgage_loaded
  } else if family == "revenues" {
    model.sales_revenue_loaded
  } else {
    model.sales_loaded && model.sales_family == family
  }
  let row_count = if active {
    if family == "subscriptions" {
      model.sales_subscription_rows.length().to_string()
    } else if family == "contracts" {
      model.sales_contract_rows.length().to_string()
    } else if family == "mortgages" {
      model.sales_mortgage_rows.length().to_string()
    } else if family == "revenues" {
      model.sales_revenue_rows.length().to_string()
    } else {
      model.sales_rows.length().to_string()
    }
  } else {
    "—"
  }
  let count_suffix = if active { " 条当前投影" } else { " 等待加载" }
  let sample = if family == "subscriptions" {
    match model.sales_subscription_rows.get(0) {
      Some(row) =>
        " · " + row.sub_code + " · " + row.state + " · " + row.source_kind
      None => ""
    }
  } else if family == "contracts" {
    match model.sales_contract_rows.get(0) {
      Some(row) =>
        " · " +
        row.scontract_code +
        " · " +
        row.state +
        " · " +
        row.source_kind
      None => ""
    }
  } else if family == "mortgages" {
    match model.sales_mortgage_rows.get(0) {
      Some(row) =>
        " · " +
        row.mortgage_code +
        " · " +
        row.state +
        " · " +
        row.source_kind
      None => ""
    }
  } else if family == "revenues" {
    match model.sales_revenue_rows.get(0) {
      Some(row) =>
        " · " +
        row.revenue_code +
        " · " +
        row.status +
        " · " +
        row.source_kind
      None => ""
    }
  } else {
    match model.sales_rows.get(0) {
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
    div(class="erp-runtime-empty", "等待 PostgreSQL 销售源观察")
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
      "当前 PostgreSQL 销售源观察",
      "源记录只读 · 本地命令保留审计凭证",
      data_table(
        ["记录", "主要信息", "关联客户", "金额", "状态", "来源"],
        rows,
      ),
    )
  }
}

///|
fn sales_customer_form_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.sales_customer_form_open {
    @html.nothing
  } else {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2(
          if model.sales_customer_edit_id.is_empty() {
            "新增客户"
          } else {
            "编辑客户"
          },
        ),
        span(class="erp-source-note", model.sales_customer_command_note),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "姓名",
          model.sales_customer_name,
          "客户姓名",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("name", value)),
        ),
        editable_form_field(
          "电话",
          model.sales_customer_phone,
          "手机号",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("phone", value)),
        ),
        editable_form_field(
          "身份证号",
          model.sales_customer_id_card_no,
          "可选",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("id_card_no", value)),
        ),
        editable_form_field(
          "意向项目",
          model.sales_customer_project_id,
          "项目 GUID，可选",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("project_id", value)),
        ),
        editable_form_field(
          "来源",
          model.sales_customer_source,
          "案场 / 渠道 / 网络",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("source", value)),
        ),
        editable_form_field(
          "备注",
          model.sales_customer_remark,
          "跟进说明",
          @html.InputType::Text,
          emit.map(value => InputSalesCustomerField("remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseSalesCustomerForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitSalesCustomerForm),
          if model.sales_customer_edit_id.is_empty() {
            "新增"
          } else {
            "保存"
          },
        ),
      ],
    ]
  }
}

///|
fn sales_customer_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  if model.sales_customer_rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("暂无客户源记录"),
      ],
    )
  } else {
    for row in model.sales_customer_rows {
      let actions : Array[@html.Html] = []
      if row.source_kind == "command" {
        actions.push(
          button(
            class="erp-link-btn",
            on_click=emit(OpenSalesCustomerEdit(row.customer_guid)),
            "编辑",
          ),
        )
        actions.push(
          button(
            class="erp-link-btn is-warning",
            on_click=emit(DeleteSalesCustomer(row.customer_guid)),
            "删除",
          ),
        )
      } else {
        actions.push(span(class="erp-source-note", "源行只读"))
      }
      rows.push(
        tr <| [
          td(row.customer_code),
          td(row.customer_name),
          td(row.phone),
          td(row.id_card_no),
          td(row.proj_guid),
          td(row.source),
          td(row.state),
          td(row.created_at),
          td <| actions,
        ],
      )
    }
  }
  table_panel(
    "客户列表",
    model.sales_note +
    " · " +
    model.sales_customer_rows.length().to_string() +
    " 条 · 导入客户保持只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "客户号", "姓名", "电话", "身份证", "意向项目", "来源",
          "状态", "登记时间", "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn sales_customers_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "客户档案",
    "SALES / CUSTOMERS",
    "维护客户、联系方式、认筹意向与跟进状态，贯通认筹、签约和回款。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(OpenSalesCustomerCreate),
        "＋ 新增客户",
      ),
    ],
    div <| [
      sales_runtime_banner(model, "customers"),
      div(class="erp-runtime-banner", [
        strong("本地客户命令"),
        span(" · " + model.sales_customer_command_note),
      ]),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目筛选:"),
        if model.project_rows.length() == 0 {
          span(
            class="erp-info-tag",
            if model.sales_customer_project_id.is_empty() {
              "全部项目"
            } else {
              model.sales_customer_project_id
            },
          )
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.sales_customer_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectSalesCustomerProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      div(class="erp-inline-actions") <| [
        input(
          input_type=@html.InputType::Text,
          value=model.sales_customer_keyword,
          placeholder="姓名 / 电话 / 身份证",
          class="erp-form-input",
          on_input=emit.map(value => InputSalesCustomerKeyword(value)),
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(Navigate("/sales/customers")),
          "查询",
        ),
      ],
      sales_customer_form_view(emit, model),
      sales_customer_table(emit, model),
    ],
  )
}

///|
fn sales_subscription_form_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.sales_subscription_form_open {
    @html.nothing
  } else {
    let customer_buttons : Array[@html.Html] = if model.sales_customer_rows.length() ==
      0 {
      [
        span(
          class="erp-source-note",
          "暂无客户源记录，请输入客户 GUID",
        ),
      ]
    } else {
      model.sales_customer_rows.map(row => {
        button(
          class="erp-tab",
          on_click=emit(
            InputSalesSubscriptionField("customer_guid", row.customer_guid),
          ),
          row.customer_name + " · " + row.phone,
        )
      })
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增认筹"),
        span(class="erp-source-note", model.sales_subscription_command_note),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "客户 GUID",
          model.sales_subscription_customer_guid,
          "选择或输入客户 GUID",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("customer_guid", value)),
        ),
        editable_form_field(
          "项目 GUID",
          model.sales_subscription_proj_guid,
          "项目 GUID",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("proj_guid", value)),
        ),
        editable_form_field(
          "楼栋号",
          model.sales_subscription_building_no,
          "例: 1-1",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("building_no", value)),
        ),
        editable_form_field(
          "房号",
          model.sales_subscription_unit_no,
          "例: 2301",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("unit_no", value)),
        ),
        editable_form_field(
          "面积㎡",
          model.sales_subscription_area,
          "数字",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("area", value)),
        ),
        editable_form_field(
          "单价(元/㎡)",
          model.sales_subscription_unit_price,
          "数字",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("unit_price", value)),
        ),
        editable_form_field(
          "总价(元)",
          model.sales_subscription_total_price,
          "可手工调整",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("total_price", value)),
        ),
        editable_form_field(
          "认筹金",
          model.sales_subscription_sub_amount,
          "元",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("sub_amount", value)),
        ),
        editable_form_field(
          "认筹日",
          model.sales_subscription_sub_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("sub_date", value)),
        ),
        editable_form_field(
          "付款方式",
          model.sales_subscription_payment_type,
          "按揭 / 一次性 / 分期",
          @html.InputType::Text,
          emit.map(value => InputSalesSubscriptionField("payment_type", value)),
        ),
      ],
      div(class="erp-source-note", "客户源档案"),
      div(class="erp-inline-actions") <| customer_buttons,
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseSalesSubscriptionForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitSalesSubscriptionForm),
          "认筹",
        ),
      ],
    ]
  }
}

///|
fn sales_subscription_state_label(state : String) -> String {
  match state {
    "subscribed" => "已认筹"
    "reserved" => "已认筹"
    "converted" => "已转签约"
    "cancelled" => "已取消"
    _ => state
  }
}

///|
fn sales_subscription_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  if model.sales_subscription_rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("暂无认筹源记录"),
        td("—"),
      ],
    )
  } else {
    for row in model.sales_subscription_rows {
      if !model.sales_subscription_state.is_empty() &&
        row.state != model.sales_subscription_state &&
        !(model.sales_subscription_state == "subscribed" &&
        row.state == "reserved") {
        continue
      }
      let action = if row.source_kind == "command" && row.state == "subscribed" {
        button(
          class="erp-link-btn is-success",
          on_click=emit(ConvertSalesSubscription(row.sub_guid)),
          "转签约",
        )
      } else if row.source_kind == "command" && row.state == "reserved" {
        button(
          class="erp-link-btn is-success",
          on_click=emit(ConvertSalesSubscription(row.sub_guid)),
          "转签约",
        )
      } else {
        span(class="erp-source-note", "源行只读")
      }
      rows.push(
        tr <| [
          td(row.sub_code),
          td(row.customer_name + " · " + row.customer_guid),
          td(row.phone),
          td(row.building_no + " - " + row.unit_no),
          td(row.area),
          td(row.unit_price),
          td(row.total_price),
          td(row.sub_amount),
          td(row.sub_date),
          td(
            sales_subscription_state_label(row.state) + " · " + row.source_kind,
          ),
          td(action),
        ],
      )
    }
  }
  table_panel(
    "认筹记录",
    model.sales_note +
    " · " +
    model.sales_subscription_rows.length().to_string() +
    " 条 · 导入认筹保持只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "认筹号", "客户", "电话", "房号", "面积㎡", "单价(元/㎡)",
          "总价(元)", "认筹金", "认筹日", "状态", "操作",
        ]),
      ],
      tbody <| rows,
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
      button(
        class="erp-primary-btn",
        on_click=emit(OpenSalesSubscriptionForm),
        "＋ 新建认筹",
      ),
    ],
    div <| [
      sales_runtime_banner(model, "subscriptions"),
      div(class="erp-runtime-banner", [
        strong("本地认筹命令"),
        span(" · " + model.sales_subscription_command_note),
      ]),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目筛选:"),
        if model.project_rows.length() == 0 {
          span(
            class="erp-info-tag",
            if model.sales_subscription_project_id.is_empty() {
              "全部项目"
            } else {
              model.sales_subscription_project_id
            },
          )
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.sales_subscription_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectSalesSubscriptionProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "状态筛选:"),
        button(
          class=if model.sales_subscription_state.is_empty() {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesSubscriptionState("")),
          "全部",
        ),
        button(
          class=if model.sales_subscription_state == "subscribed" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesSubscriptionState("subscribed")),
          "已认筹",
        ),
        button(
          class=if model.sales_subscription_state == "converted" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesSubscriptionState("converted")),
          "已转签约",
        ),
        button(
          class=if model.sales_subscription_state == "cancelled" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesSubscriptionState("cancelled")),
          "已取消",
        ),
      ],
      sales_subscription_form_view(emit, model),
      sales_subscription_table(emit, model),
      div(class="erp-stat-grid") <| [
        metric("本月认筹", "86", "认筹金 ¥516 万", "metric-blue"),
        metric("待转签", "24", "近 7 日新增 6", "metric-blue"),
        metric("转签率", "71.4%", "较上月 +4.2%", "metric-green"),
      ],
    ],
  )
}

///|
fn sales_contract_state_label(state : String) -> String {
  match state {
    "signed" => "已签约"
    "refunded" => "已退房"
    "completed" => "已完成"
    "draft" => "待备案"
    _ => state
  }
}

///|
fn sales_contract_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for row in model.sales_contract_rows {
    if !model.sales_contract_state.is_empty() &&
      row.state != model.sales_contract_state {
      continue
    }
    let actions : Array[@html.Html] = if row.source_kind == "command" &&
      row.state == "signed" {
      [
        button(
          class="erp-link-btn",
          on_click=emit(
            OpenSalesMortgageForm(
              row.scontract_guid,
              row.customer_guid,
              row.total_price,
            ),
          ),
          "办按揭",
        ),
        button(
          class="erp-link-btn is-warning",
          on_click=emit(
            OpenSalesRefundForm(
              row.scontract_guid,
              row.customer_guid,
              row.total_price,
            ),
          ),
          "退房",
        ),
      ]
    } else {
      [span(class="erp-source-note", "源行只读")]
    }
    rows.push(
      tr <| [
        td(row.scontract_code),
        td(row.customer_name + " · " + row.customer_guid),
        td(row.phone),
        td(row.building_no + " - " + row.unit_no),
        td(row.area),
        td(row.total_price),
        td(row.payment_type),
        td(row.signed_date),
        td(sales_contract_state_label(row.state) + " · " + row.source_kind),
        td <| actions,
      ],
    )
  }
  if rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("暂无签约源记录"),
        td("—"),
      ],
    )
  }
  table_panel(
    "销售合同",
    model.sales_note +
    " · " +
    model.sales_contract_rows.length().to_string() +
    " 条 · 导入合同保持只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "签约号", "客户", "电话", "房号", "面积㎡", "总价(元)",
          "付款方式", "签约日", "状态", "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn sales_contracts_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "签约管理",
    "SALES / CONTRACTS",
    "管理销售合同、付款方式、签约日期和回款状态，与销售回款和发票联动。",
    [],
    div <| [
      sales_runtime_banner(model, "contracts"),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目筛选:"),
        if model.project_rows.length() == 0 {
          span(
            class="erp-info-tag",
            if model.sales_contract_project_id.is_empty() {
              "全部项目"
            } else {
              model.sales_contract_project_id
            },
          )
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.sales_contract_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectSalesContractProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "状态筛选:"),
        button(
          class=if model.sales_contract_state.is_empty() {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesContractState("")),
          "全部",
        ),
        button(
          class=if model.sales_contract_state == "signed" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesContractState("signed")),
          "已签约",
        ),
        button(
          class=if model.sales_contract_state == "completed" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesContractState("completed")),
          "已完成",
        ),
        button(
          class=if model.sales_contract_state == "refunded" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesContractState("refunded")),
          "已退房",
        ),
      ],
      sales_contract_table(emit, model),
      div(class="erp-stat-grid") <| [
        metric("本月签约", "42", "签约金额 ¥8,640 万", "metric-blue"),
        metric("待备案", "8", "需补齐合同资料", "metric-blue"),
        metric("已完成", "126", "年度累计", "metric-green"),
      ],
    ],
  )
}

///|
fn sales_mortgage_actions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(CreateSalesMortgage),
      "＋ 新建按揭",
    ),
  ]
  if model.sales_mortgage_state == "applying" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(ApproveSalesMortgage),
        "记录批贷候选",
      ),
    )
  } else if model.sales_mortgage_state == "approved" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(ReleaseSalesMortgage),
        "记录放款候选",
      ),
    )
  }
  actions
}

///|
fn sales_mortgage_state_label(state : String) -> String {
  match state {
    "applying" => "申请中"
    "approved" => "已批贷"
    "released" => "已放款"
    "rejected" => "已拒贷"
    _ => state
  }
}

///|
fn sales_mortgage_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for row in model.sales_mortgage_rows {
    if !model.sales_mortgage_filter_state.is_empty() &&
      row.state != model.sales_mortgage_filter_state {
      continue
    }
    let actions : Array[@html.Html] = if row.source_kind == "command" &&
      row.state == "applying" {
      [
        button(
          class="erp-link-btn",
          on_click=emit(ApproveSalesMortgage),
          "批贷",
        ),
      ]
    } else if row.source_kind == "command" && row.state == "approved" {
      [
        button(
          class="erp-link-btn is-success",
          on_click=emit(ReleaseSalesMortgage),
          "放款",
        ),
      ]
    } else {
      [span(class="erp-source-note", "源行只读")]
    }
    rows.push(
      tr <| [
        td(row.mortgage_code),
        td(row.customer_name + " · " + row.customer_guid),
        td(row.bank_name),
        td(row.loan_amount),
        td(row.loan_years),
        td(row.rate),
        td(row.apply_date),
        td(row.approval_date),
        td(row.release_date),
        td(sales_mortgage_state_label(row.state) + " · " + row.source_kind),
        td <| actions,
      ],
    )
  }
  if rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("暂无按揭源记录"),
        td("—"),
      ],
    )
  }
  table_panel(
    "按揭申请",
    model.sales_note +
    " · " +
    model.sales_mortgage_rows.length().to_string() +
    " 条 · 导入按揭保持只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "按揭号", "客户", "银行", "贷款额(元)", "年限", "利率",
          "申请日", "批贷日", "放款日", "状态", "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn sales_mortgage_form_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.sales_mortgage_form_open {
    @html.nothing
  } else {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("申请按揭"),
        span(class="erp-source-note", model.sales_mortgage_command_note),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "销售合同号",
          model.sales_mortgage_form_contract,
          "必填",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("contract", value)),
        ),
        editable_form_field(
          "客户 GUID",
          model.sales_mortgage_form_customer,
          "可选",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("customer", value)),
        ),
        editable_form_field(
          "贷款银行",
          model.sales_mortgage_form_bank,
          "必填",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("bank", value)),
        ),
        editable_form_field(
          "贷款金额",
          model.sales_mortgage_form_amount,
          "元",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("amount", value)),
        ),
        editable_form_field(
          "贷款年限",
          model.sales_mortgage_form_years,
          "年",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("years", value)),
        ),
        editable_form_field(
          "利率",
          model.sales_mortgage_form_rate,
          "例如 0.0345",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("rate", value)),
        ),
        editable_form_field(
          "申请日期",
          model.sales_mortgage_form_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("date", value)),
        ),
        editable_form_field(
          "备注",
          model.sales_mortgage_form_remark,
          "可选",
          @html.InputType::Text,
          emit.map(value => InputSalesMortgageField("remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseSalesMortgageForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitSalesMortgageForm),
          "提交申请",
        ),
      ],
    ]
  }
}

///|
fn sales_mortgages_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "按揭办理",
    "SALES / MORTGAGES",
    "跟进按揭申请、银行审批与放款节点，及时发现资料缺失和逾期申请。",
    sales_mortgage_actions(emit, model),
    div <| [
      sales_runtime_banner(model, "mortgages"),
      div(class="erp-runtime-banner", [
        strong("本地按揭命令"),
        span(" · " + model.sales_mortgage_command_note),
      ]),
      sales_mortgage_form_view(emit, model),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "状态筛选:"),
        button(
          class=if model.sales_mortgage_filter_state.is_empty() {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesMortgageState("")),
          "全部",
        ),
        button(
          class=if model.sales_mortgage_filter_state == "applying" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesMortgageState("applying")),
          "申请中",
        ),
        button(
          class=if model.sales_mortgage_filter_state == "approved" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesMortgageState("approved")),
          "已批贷",
        ),
        button(
          class=if model.sales_mortgage_filter_state == "released" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesMortgageState("released")),
          "已放款",
        ),
      ],
      sales_mortgage_table(emit, model),
      div(class="erp-stat-grid") <| [
        metric("办理中", "68", "涉及 5 家银行", "metric-blue"),
        metric("本月放款", "¥3,860 万", "32 笔", "metric-green"),
        metric("资料待补", "7", "需客户跟进", "metric-blue"),
      ],
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
      button(
        class="erp-secondary-btn",
        on_click=emit(DownloadImportTemplate("contract")),
        "下载导入模板",
      ),
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
      import_panel(emit, model, "contract"),
      filter_bar("合同编号 / 项目 / 供应商"),
      table_panel(
        "合同列表",
        model.contract_note + " · " + model.import_template_note,
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
fn cost_dashboard_rows_table(rows : Array[CostDashboardRow]) -> @html.Html {
  let rendered : Array[Array[String]] = []
  if rows.length() == 0 {
    rendered.push([
      "—", "本次源导出没有 CBS 字典记录", "0", "0", "0", "0", "0", "0",
      "0", "源表为空",
    ])
  } else {
    for row in rows {
      let label = if row.level == "L2" {
        "  " + row.name
      } else if row.level == "L3" {
        "    " + row.name
      } else {
        row.name
      }
      rendered.push([
        row.code,
        label,
        row.target_cost,
        row.committed_cost,
        row.in_transit,
        row.planned_spare,
        row.estimated_change,
        row.dynamic_cost,
        row.layout_spare,
        row.level,
      ])
    }
  }
  data_table(
    [
      "CBS", "科目", "A 目标", "D 已成", "E 在途", "F 规划", "G 预估",
      "B 动态", "H 余量", "层级",
    ],
    rendered,
  )
}

///|
fn cost_dashboard_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let source_note = if model.cost_dashboard_loaded {
    model.cost_dashboard_note +
    " · " +
    model.cost_dashboard_project_name +
    " · 版本 " +
    model.cost_dashboard_plan_version
  } else {
    "成本驾驶舱 v3 源读模型不可用 · 使用设计快照"
  }
  page_shell(
    "成本驾驶舱",
    "COST DASHBOARD",
    "从目标成本、动态成本、合同和付款四个层面观察项目成本偏差。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/cost-dashboard-v3")),
        if model.cost_dashboard_loaded {
          "刷新源数据"
        } else {
          "读取源数据"
        },
      ),
      button(class="erp-secondary-btn", "导出分析"),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "目标成本",
          if model.cost_dashboard_loaded {
            model.cost_dashboard_target
          } else {
            "¥6.08 亿"
          },
          if model.cost_dashboard_loaded {
            "源 CBS 汇总"
          } else {
            "15 个项目"
          },
          "metric-blue",
        ),
        metric(
          "动态成本",
          if model.cost_dashboard_loaded {
            model.cost_dashboard_dynamic
          } else {
            "¥6.45 亿"
          },
          if model.cost_dashboard_loaded {
            "偏差 " + model.cost_dashboard_deviation + "%"
          } else {
            "偏差 +6.20%"
          },
          "metric-green",
        ),
        metric(
          "已签合同",
          if model.cost_dashboard_loaded {
            model.cost_dashboard_contract_count
          } else {
            "¥5.82 亿"
          },
          if model.cost_dashboard_loaded {
            "源合同行"
          } else {
            "覆盖率 90.2%"
          },
          "metric-blue",
        ),
        metric(
          "源费用/变更",
          if model.cost_dashboard_loaded {
            model.cost_dashboard_expense_count +
            " / " +
            model.cost_dashboard_change_count
          } else {
            "¥6,280 万"
          },
          if model.cost_dashboard_loaded {
            "报销 / 变更"
          } else {
            "需关注 4 项"
          },
          "metric-blue",
        ),
      ],
      if model.cost_dashboard_loaded {
        table_panel(
          "CBS 成本层级",
          source_note + " · B = D + E + F + G · H = A - B",
          cost_dashboard_rows_table(model.cost_dashboard_rows),
        )
      } else {
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
        ]
      },
      if model.cost_dashboard_loaded {
        div(class="erp-command-receipt") <| [
          strong("源数据状态"),
          span(
            source_note +
            " · 成本驾驶舱仅读，不执行预算/会计写入",
          ),
        ]
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn investment_runtime_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.investment_loaded {
    let rendered : Array[@html.Html] = []
    for row in model.investment_index_rows {
      rendered.push(
        tr <| [
          td(row.dimension),
          td(row.full_code),
          td(row.index_name),
          td(row.index_value),
          td(row.unit),
          td(row.source_kind + " · " + row.index_guid),
          td <| [
            button(
              class="erp-ghost-btn",
              on_click=emit(SelectInvestmentIndex(row.index_guid)),
              "选择指标",
            ),
          ],
        ],
      )
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
      ") · " +
      (if model.investment_index_selected.is_empty() {
        "未选择指标"
      } else {
        "已选择 " + model.investment_index_selected
      }),
      table(class="erp-data-table") <| [
        thead <| [
          table_header([
            "维度", "编码", "指标", "值", "单位", "来源 / ID", "操作",
          ]),
        ],
        tbody <| rendered,
      ],
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
fn investment_index_edit_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.investment_index_selected.is_empty() {
    @html.nothing
  } else {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("指标编辑候选"),
        span(
          class="erp-info-tag",
          "源指标 " +
          model.investment_index_selected +
          " · 保存仍需投资负责人确认",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "指标值",
          model.investment_index_edit_value,
          "例如 120.5",
          @html.InputType::Text,
          emit.map(value => InputInvestmentIndexEditValue(value)),
        ),
        editable_form_field(
          "备注",
          model.investment_index_edit_remark,
          "复核说明",
          @html.InputType::Text,
          emit.map(value => InputInvestmentIndexEditRemark(value)),
        ),
      ],
      div(class="erp-command-bar") <| [
        button(
          class="erp-primary-btn",
          on_click=emit(RequestInvestmentIndexUpdate),
          "提交更新候选",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(RequestInvestmentIndexDelete),
          "提交删除候选",
        ),
      ],
      p(class="erp-source-note", model.investment_command_note),
    ]
  }
}

///|
fn investment_import_history_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let rendered : Array[@html.Html] = []
  if model.investment_import_rows.length() == 0 {
    rendered.push(
      tr <| [
        td("暂无源导入记录"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("—"),
      ],
    )
  } else {
    for row in model.investment_import_rows {
      rendered.push(
        tr <| [
          td(row.file_name + " · " + row.import_guid),
          td(row.version_name + " · " + row.version_guid),
          td(row.file_size),
          td(row.sheet_count),
          td(row.non_empty_cells),
          td(row.formula_count),
          td(span(class="erp-status-tag is-info", row.status)),
          td(row.created_by_name),
          td(row.created_at + " · " + row.source_kind),
          td <| [
            button(
              class="erp-ghost-btn",
              on_click=emit(SelectInvestmentImport(row.import_guid)),
              "读取详情 / 预览",
            ),
          ],
        ],
      )
    }
  }
  table_panel(
    "Excel 导入历史（" +
    (if model.investment_imports_loaded {
      model.investment_import_rows.length().to_string()
    } else {
      "快照"
    }) +
    "）",
    model.investment_import_note +
    " · 仅显示元数据，不读取工作簿二进制",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "文件 / 导入 ID", "导入版本", "文件大小", "工作表", "非空单元格",
          "公式", "状态", "导入人", "导入时间 / 来源", "操作",
        ]),
      ],
      tbody <| rendered,
    ],
  )
}

///|
fn investment_import_read_panels(model : Model) -> @html.Html {
  if model.investment_import_selected.is_empty() {
    div(
      class="erp-runtime-empty",
      "选择一条 Excel 导入记录后查看详情、桥接、指标和计划预览",
    )
  } else {
    div(class="erp-runtime-banner", [
      strong("导入记录 " + model.investment_import_selected),
      span(" · " + model.investment_import_detail_note),
      span(" · " + model.investment_import_bridge_note),
      span(" · " + model.investment_import_index_preview_note),
      span(" · " + model.investment_import_profit_note),
      span(" · " + model.investment_import_plan_note),
    ])
  }
}

///|
fn investment_import_history_note(model : Model) -> String {
  if model.investment_import_selected.is_empty() {
    "未选择导入记录"
  } else {
    "已选择 " +
    model.investment_import_selected +
    " · 读取为只读预览"
  }
}

///|
fn investment_import_history_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  div <| [
    investment_import_history_table(emit, model),
    investment_import_read_panels(model),
    div(class="erp-source-note", investment_import_history_note(model)),
  ]
}

///|
fn investment_project_context(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.project_rows.length() == 0 {
    div(
      class="erp-runtime-empty",
      "项目主数据尚未返回 · 当前使用 " +
      model.investment_project_name +
      " (" +
      model.investment_project_id +
      ")",
    )
  } else {
    let controls : Array[@html.Html] = []
    for row in model.project_rows {
      controls.push(
        button(
          class=if row.project_id == model.investment_project_id {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectInvestmentProject(row.project_id)),
          row.project_name + " · " + row.project_id,
        ),
      )
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("项目上下文"),
        span(
          class="erp-info-tag",
          "当前 " +
          model.investment_project_name +
          " · 版本/导入读取随项目切换",
        ),
      ],
      div(class="erp-command-bar") <| controls,
    ]
  }
}

///|
fn investment_version_context(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.investment_version_rows.length() == 0 {
    div(
      class="erp-runtime-empty",
      "当前项目没有可显示的投资版本 · 版本写入仍需负责人授权",
    )
  } else {
    let controls : Array[@html.Html] = []
    for row in model.investment_version_rows {
      controls.push(
        button(
          class=if row.version_guid == model.investment_version_id {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectInvestmentVersion(row.version_guid)),
          row.version_name +
          " · v" +
          row.version_no +
          (if row.is_current { " · 当前" } else { "" }) +
          " · " +
          row.source_kind +
          (if row.creator_name.is_empty() {
            ""
          } else {
            " · " + row.creator_name
          }) +
          (if row.created_at.is_empty() { "" } else { " · " + row.created_at }) +
          (if row.remark.is_empty() { "" } else { " · " + row.remark }),
        ),
      )
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("测算版本"),
        span(
          class="erp-info-tag",
          "指标读取随版本切换 · 创建/激活/删除保持候选",
        ),
      ],
      div(class="erp-command-bar") <| controls,
    ]
  }
}

///|
fn investment_version_create_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  section(class="erp-detail-card") <| [
    div(class="erp-panel-heading") <| [
      h2("新建测算版本候选"),
      span(
        class="erp-info-tag",
        "复制指标、激活和持久化均需投资负责人确认",
      ),
    ],
    div(class="erp-form-grid") <| [
      editable_form_field(
        "版本名称",
        model.investment_new_version_name,
        "例如 2027 年 1 月调整版",
        @html.InputType::Text,
        emit.map(value => InputInvestmentVersionName(value)),
      ),
      editable_form_field(
        "复制来源",
        model.investment_new_version_copy_from,
        "可填 versionGuid；复制仍受门控",
        @html.InputType::Text,
        emit.map(value => InputInvestmentVersionCopyFrom(value)),
      ),
      editable_form_field(
        "备注",
        model.investment_new_version_remark,
        "版本说明",
        @html.InputType::Text,
        emit.map(value => InputInvestmentVersionRemark(value)),
      ),
    ],
    div(class="erp-command-bar") <| [
      button(
        class="erp-secondary-btn",
        on_click=emit(ToggleInvestmentVersionActivate),
        if model.investment_new_version_activate {
          "创建后激活：是"
        } else {
          "创建后激活：否"
        },
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(RequestInvestmentVersionCreate),
        "提交版本创建候选",
      ),
    ],
    p(class="erp-source-note", model.investment_command_note),
  ]
}

///|
fn investment_index_create_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  section(class="erp-detail-card") <| [
    div(class="erp-panel-heading") <| [
      h2("新建测算指标候选"),
      span(
        class="erp-info-tag",
        "编码/名称必填 · 指标写入和估值影响均需负责人确认",
      ),
    ],
    div(class="erp-form-grid") <| [
      editable_form_field(
        "维度",
        model.investment_new_index_dimension,
        "investment / tax / financing",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexDimension(value)),
      ),
      editable_form_field(
        "编码",
        model.investment_new_index_full_code,
        "例如 Tax.Local",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexFullCode(value)),
      ),
      editable_form_field(
        "名称",
        model.investment_new_index_name,
        "指标名称",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexName(value)),
      ),
      editable_form_field(
        "父级编码",
        model.investment_new_index_parent_code,
        "可省略",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexParentCode(value)),
      ),
      editable_form_field(
        "单位",
        model.investment_new_index_unit,
        "万元 / % / 日期序号",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexUnit(value)),
      ),
      editable_form_field(
        "指标值",
        model.investment_new_index_value,
        "例如 100",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexValue(value)),
      ),
      editable_form_field(
        "备注",
        model.investment_new_index_remark,
        "指标说明",
        @html.InputType::Text,
        emit.map(value => InputInvestmentIndexRemark(value)),
      ),
    ],
    div(class="erp-command-bar") <| [
      button(
        class="erp-primary-btn",
        on_click=emit(RequestInvestmentIndexCreate),
        "提交指标创建候选",
      ),
    ],
    p(class="erp-source-note", model.investment_command_note),
  ]
}

///|
fn investment_sensitivity_table(model : Model) -> @html.Html {
  if model.investment_sensitivity_loaded {
    let rows : Array[Array[String]] = []
    for row in model.investment_sensitivity_cases {
      rows.push([row.name, row.irr + "%", row.source_kind])
    }
    table_panel(
      "投资敏感性情景",
      model.investment_sensitivity_note,
      data_table(["情景", "IRR", "来源"], rows),
    )
  } else {
    @html.nothing
  }
}

///|
fn investment_profit_actual_panel(model : Model) -> @html.Html {
  if model.investment_actual_loaded {
    table_panel(
      "实际利润对比边界",
      model.investment_actual_note +
      " · 空/缺源表 " +
      model.investment_actual_missing_table_count,
      data_table(["源代码", "响应", "模拟", "授权状态"], [
        [
          model.investment_actual_code,
          if model.investment_actual_message == "" {
            "边界响应已读取"
          } else {
            model.investment_actual_message
          },
          model.investment_actual_simulation,
          "不授权 · 不持久化 · 不调用外部服务",
        ],
      ]),
    )
  } else {
    div(class="erp-runtime-empty", model.investment_actual_note)
  }
}

///|
fn investment_excel_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  section(class="erp-detail-card") <| [
    div(class="erp-panel-heading") <| [
      h2("Excel 测算导入"),
      span(
        class="erp-info-tag",
        "仅 .xlsx · 二进制解析与写入保持 gated",
      ),
    ],
    div(class="erp-command-bar") <| [
      label(class="erp-import-file-picker") <| [
        input(
          input_type=@html.InputType::File,
          accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          class="erp-import-file-input",
          on_change=emit.map(value => InputInvestmentExcelFileSelected(value)),
        ),
        span(
          if model.investment_excel_file_name.is_empty() {
            "选择 .xlsx 工作簿"
          } else {
            model.investment_excel_file_name
          },
        ),
      ],
      button(
        class="erp-secondary-btn",
        on_click=emit(ToggleInvestmentExcelActivate),
        if model.investment_excel_activate {
          "导入后激活：是"
        } else {
          "导入后激活：否"
        },
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(RequestInvestmentExcelUpload),
        "检查上传边界",
      ),
    ],
    div(class="erp-form-grid") <| [
      editable_form_field(
        "版本名称",
        model.investment_excel_version_name,
        "Excel 导入版",
        @html.InputType::Text,
        emit.map(value => InputInvestmentExcelVersionName(value)),
      ),
    ],
    p(class="erp-source-note", model.investment_upload_note),
  ]
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
      button(
        class="erp-secondary-btn",
        on_click=emit(ExplainInvestment),
        "生成可行性解释",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentExcelUpload),
        "检查 Excel 上传（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentSubjectMappings),
        "检查科目映射（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentPlanLineUpdate),
        "检查计划行编辑（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentIndexUpsert),
        "检查指标 upsert（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentPlanLineImport),
        "检查计划行导入（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentVersionCreate),
        "新建版本（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentVersionActivate),
        "激活版本（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentVersionDelete),
        "删除版本（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentIndexCreate),
        "新建指标（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentIndexUpdate),
        "更新指标（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestInvestmentIndexDelete),
        "删除指标（候选）",
      ),
    ],
    div <| [
      stats,
      investment_project_context(emit, model),
      investment_version_context(emit, model),
      investment_version_create_panel(emit, model),
      investment_index_create_panel(emit, model),
      investment_excel_panel(emit, model),
      investment_import_history_panel(emit, model),
      investment_runtime_table(emit, model),
      investment_index_edit_panel(emit, model),
      investment_sensitivity_table(model),
      investment_profit_actual_panel(model),
      div(class="erp-runtime-banner", [
        strong("投资解释候选"),
        span(" · " + model.investment_explain_note),
      ]),
      div(class="erp-runtime-banner", [
        strong("Excel 上传候选"),
        span(" · " + model.investment_upload_note),
        span(" · 项目 " + model.investment_project_id),
      ]),
      div(class="erp-runtime-banner", [
        strong("科目映射候选"),
        span(" · " + model.investment_mapping_note),
        span(" · 项目 " + model.investment_project_id),
      ]),
      div(class="erp-runtime-banner", [
        strong("计划行编辑候选"),
        span(" · " + model.investment_plan_line_note),
        span(" · 计划行 PLAN-RABBITA-LOCAL"),
      ]),
      div(class="erp-runtime-banner", [
        strong("Excel 指标 upsert 候选"),
        span(" · " + model.investment_index_upsert_note),
        span(" · 导入 IMPORT-RABBITA-LOCAL"),
      ]),
      div(class="erp-runtime-banner", [
        strong("Excel 计划行导入候选"),
        span(" · " + model.investment_plan_line_import_note),
        span(" · 导入 IMPORT-RABBITA-LOCAL"),
      ]),
      div(class="erp-runtime-banner", [
        strong("投资版本 / 指标命令候选"),
        span(" · " + model.investment_command_note),
        span(" · 本地投影不改变导入版本"),
      ]),
      table_panel(
        "解释结果",
        "只读摘要 · 不持久化 prompt",
        data_table(["结果"], [[model.investment_explain_text]]),
      ),
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
fn dynamic_cost_create_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  section(class="erp-detail-card") <| [
    div(class="erp-panel-heading") <| [
      h2("新增成本科目候选"),
      span(
        class="erp-info-tag",
        "源字段映射 · command 行可写，导入 cb_cost 行保持只读",
      ),
    ],
    div(class="erp-form-grid") <| [
      editable_form_field(
        "科目编码",
        model.dynamic_cost_create_code,
        "如 CB-107-XX",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateCode(value)),
      ),
      editable_form_field(
        "科目名称",
        model.dynamic_cost_create_name,
        "成本科目名称",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateName(value)),
      ),
      editable_form_field(
        "科目层级",
        model.dynamic_cost_create_level,
        "1 - 5",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateLevel(value)),
      ),
      editable_form_field(
        "父科目 GUID",
        model.dynamic_cost_create_parent,
        "可选 parentCostGuid",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateParent(value)),
      ),
      editable_form_field(
        "A 目标成本",
        model.dynamic_cost_create_target,
        "targetCost",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateTarget(value)),
      ),
      editable_form_field(
        "D 合约+变更",
        model.dynamic_cost_create_contract_change,
        "htAlterAmount",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateContractChange(value)),
      ),
      editable_form_field(
        "E 在途",
        model.dynamic_cost_create_in_transit,
        "ztCost",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateInTransit(value)),
      ),
      editable_form_field(
        "F 待发生",
        model.dynamic_cost_create_budget,
        "dfsBudget",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateBudget(value)),
      ),
      editable_form_field(
        "G 预估变更",
        model.dynamic_cost_create_estimate_change,
        "ygAlter",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateEstimateChange(value)),
      ),
      editable_form_field(
        "备注",
        model.dynamic_cost_create_remarks,
        "成本口径备注",
        @html.InputType::Text,
        emit.map(value => InputDynamicCostCreateRemarks(value)),
      ),
    ],
    div(class="erp-command-bar") <| [
      button(
        class="erp-primary-btn",
        on_click=emit(RequestDynamicCostCreate),
        "提交科目创建候选",
      ),
    ],
    p(class="erp-source-note", model.dynamic_cost_command_note),
  ]
}

///|
fn dynamic_cost_project_context(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.project_rows.length() == 0 {
    div(
      class="erp-runtime-empty",
      "项目主数据尚未返回 · 当前范围 " +
      model.dynamic_cost_project_id,
    )
  } else {
    let controls : Array[@html.Html] = []
    for row in model.project_rows {
      controls.push(
        button(
          class=if row.project_id == model.dynamic_cost_project_id {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(InputDynamicCostProject(row.project_id)),
          row.project_name + " · " + row.project_id,
        ),
      )
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("项目范围"),
        span(
          class="erp-info-tag",
          model.dynamic_cost_project_name + " · 切换后重读动态成本源",
        ),
      ],
      div(class="erp-command-bar") <| controls,
    ]
  }
}

///|
fn dynamic_cost_remark_actions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.dynamic_cost_loaded || model.dynamic_cost_rows.length() == 0 {
    div(
      class="erp-runtime-empty",
      "当前项目没有可查看备注的成本科目",
    )
  } else {
    let rendered : Array[@html.Html] = []
    for row in model.dynamic_cost_rows {
      rendered.push(
        tr <| [
          td(row.cost_code + " · " + row.cost_name),
          td(row.target_cost),
          td(row.dynamic_cost),
          td(row.layout_spare),
          td(
            button(
              class="erp-ghost-btn",
              on_click=emit(ViewDynamicCostRemarks(row.cost_guid)),
              "查看备注",
            ),
          ),
        ],
      )
    }
    table_panel(
      "科目备注",
      model.dynamic_cost_remark_note +
      " · imported/command 行均为只读观察",
      table(class="erp-data-table") <| [
        thead <| [
          table_header(["科目", "A 目标", "B 动态", "H 余量", "操作"]),
        ],
        tbody <| rendered,
      ],
    )
  }
}

///|
fn dynamic_cost_remark_panel(model : Model) -> @html.Html {
  if model.dynamic_cost_remark_loaded {
    table_panel(
      "当前科目备注",
      model.dynamic_cost_remark_note +
      " · " +
      model.dynamic_cost_remark_project +
      " · " +
      model.dynamic_cost_remark_source,
      data_table(["科目编码", "科目名称", "备注"], [
        [
          model.dynamic_cost_remark_code,
          model.dynamic_cost_remark_name,
          if model.dynamic_cost_remark_text.is_empty() {
            "无备注"
          } else {
            model.dynamic_cost_remark_text
          },
        ],
      ]),
    )
  } else {
    div(class="erp-source-note", model.dynamic_cost_remark_note)
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
      button(
        class="erp-secondary-btn",
        on_click=emit(ExportDynamicCostCsv),
        "导出 CSV",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExportDynamicCostXlsx),
        "导出 Excel",
      ),
    ],
    div <| [
      stats,
      dynamic_cost_project_context(emit, model),
      filter_bar("项目 / 成本科目 / 变更编号"),
      dynamic_cost_table(model),
      dynamic_cost_remark_actions(emit, model),
      dynamic_cost_remark_panel(model),
      dynamic_cost_create_panel(emit, model),
      div(class="erp-runtime-banner", [
        strong("动态成本导出"),
        span(" · " + model.dynamic_cost_export_note),
        span(" · 当前项目 " + model.dynamic_cost_project_id),
      ]),
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
fn tender_table_row(emit : @rabbita.Emit[Msg], row : TenderRow) -> @html.Html {
  let action = if row.source_kind != "command" {
    span(class="erp-source-note", "源行只读")
  } else if row.state == "planning" {
    button(
      class="erp-link-btn",
      on_click=emit(AdvanceTenderRow(row.tender_id, row.state, "publishing")),
      "发布",
    )
  } else if row.state == "publishing" {
    button(
      class="erp-link-btn is-warning",
      on_click=emit(AdvanceTenderRow(row.tender_id, row.state, "bidding")),
      "开标",
    )
  } else if row.state == "bidding" {
    button(
      class="erp-link-btn is-success",
      on_click=emit(
        SelectTenderRow(row.tender_id, row.name, row.state, row.source_kind),
      ),
      "定标",
    )
  } else if row.state == "awarded" {
    button(
      class="erp-link-btn",
      on_click=emit(AdvanceTenderRow(row.tender_id, row.state, "completed")),
      "完成",
    )
  } else {
    span(class="erp-source-note", "—")
  }
  tr <| [
    td <| [
      button(
        class="erp-link-btn",
        on_click=emit(
          SelectTenderRow(row.tender_id, row.name, row.state, row.source_kind),
        ),
        row.tender_id + " / " + row.source_kind,
      ),
    ],
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
    td(action),
  ]
}

///|
fn tender_table(
  emit : @rabbita.Emit[Msg],
  rows : Array[TenderRow],
) -> @html.Html {
  let rendered : Array[@html.Html] = []
  for row in rows {
    rendered.push(tender_table_row(emit, row))
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "规划编号 / 来源", "项目范围", "合约包", "CBS / 类别", "预算金额",
        "已定标", "投标证据", "状态 / 承诺", "操作",
      ]),
    ],
    tbody <| rendered,
  ]
}

///|
fn tender_award_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.tender_award_rows.length() == 0 {
    rows.push([
      "—", "—", "—", "—", "0", "—", "—", "无源定标记录",
    ])
  } else {
    for row in model.tender_award_rows {
      rows.push([
        row.award_code,
        row.tender_id,
        row.provider_name,
        row.provider_id,
        row.award_amount,
        row.award_date,
        row.remark,
        row.source_kind,
      ])
    }
  }
  table_panel(
    "定标记录",
    "PostgreSQL 源定标投影 · 资格校验与合同落地保持独立",
    data_table(
      [
        "编号", "所属招标", "中标供应商", "供应商 GUID", "中标金额（元）",
        "定标日", "备注", "来源",
      ],
      rows,
    ),
  )
}

///|
fn tender_actions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Array[@html.Html] {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(OpenTenderForm("tender")),
      "＋ 新建合约规划",
    ),
    button(
      class="erp-secondary-btn",
      on_click=emit(AdvanceSourceTender),
      "源状态推进（候选）",
    ),
    button(
      class="erp-secondary-btn",
      on_click=emit(AwardSourceTender),
      "源定标（候选）",
    ),
  ]
  if model.tender_selected_source_kind == "command" {
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
        actions.push(
          button(
            class="erp-secondary-btn",
            on_click=emit(OpenTenderForm("award")),
            "源定标表单",
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
  } else {
    ()
  }
  if model.tender_selected_source_kind != "command" &&
    model.tender_state == "bidding" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenTenderForm("award")),
        "源定标表单",
      ),
    )
  }
  actions
}

///|
fn tender_form_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.tender_form_open == "tender" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增招标"),
        span(
          class="erp-source-note",
          "金额按元输入 · 写入本地合约规划命令投影",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "招标名称",
          model.tender_name,
          "例：1-1 主体土建工程",
          @html.InputType::Text,
          emit.map(value => InputTenderField("name", value)),
        ),
        editable_form_field(
          "类别",
          model.tender_category,
          "建安工程 / 装修工程",
          @html.InputType::Text,
          emit.map(value => InputTenderField("category", value)),
        ),
        editable_form_field(
          "预算金额（元）",
          model.tender_estimated_amount,
          "0",
          @html.InputType::Text,
          emit.map(value => InputTenderField("estimated_amount", value)),
        ),
        editable_form_field(
          "计划发布",
          model.tender_plan_publish_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputTenderField("plan_publish_date", value)),
        ),
        editable_form_field(
          "计划定标",
          model.tender_plan_award_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputTenderField("plan_award_date", value)),
        ),
        editable_form_field(
          "备注",
          model.tender_remark,
          "招标说明",
          @html.InputType::Text,
          emit.map(value => InputTenderField("remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(class="erp-ghost-btn", on_click=emit(CloseTenderForm), "取消"),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitTenderForm),
          "提交招标",
        ),
      ],
    ]
  } else if model.tender_form_open == "award" {
    let provider_chips : Array[@html.Html] = []
    for provider in model.supplier_source_rows {
      provider_chips.push(
        button(
          class=if provider.supplier_id == model.tender_award_provider_guid {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(
            SelectTenderProvider(provider.supplier_id, provider.name),
          ),
          provider.name + " · " + provider.supplier_id,
        ),
      )
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("定标"),
        span(
          class="erp-source-note",
          "供应商资格由 PostgreSQL 源投影校验 · 不直接创建合同",
        ),
      ],
      if provider_chips.length() == 0 {
        span(
          class="erp-source-note",
          "供应商源列表尚未加载 · 可手填 GUID",
        )
      } else {
        div(class="erp-project-picker") <| provider_chips
      },
      div(class="erp-form-grid") <| [
        editable_form_field(
          "供应商 GUID",
          model.tender_award_provider_guid,
          "provider GUID",
          @html.InputType::Text,
          emit.map(value => InputTenderField("award_provider_guid", value)),
        ),
        editable_form_field(
          "供应商名称",
          model.tender_award_provider_name,
          "供应商名称",
          @html.InputType::Text,
          emit.map(value => InputTenderField("award_provider_name", value)),
        ),
        editable_form_field(
          "中标金额（元）",
          model.tender_award_amount,
          "0",
          @html.InputType::Text,
          emit.map(value => InputTenderField("award_amount", value)),
        ),
        editable_form_field(
          "定标日",
          model.tender_award_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputTenderField("award_date", value)),
        ),
        editable_form_field(
          "备注",
          model.tender_award_remark,
          "定标说明",
          @html.InputType::Text,
          emit.map(value => InputTenderField("award_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(class="erp-ghost-btn", on_click=emit(CloseTenderForm), "取消"),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitTenderForm),
          "提交定标",
        ),
      ],
    ]
  } else {
    @html.nothing
  }
}

///|
fn tender_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.tenders_loaded {
    model.tender_rows
  } else {
    fallback_tender_rows()
  }
  let project_picker : Array[@html.Html] = []
  if model.project_rows.length() == 0 {
    project_picker.push(
      span(
        class="erp-source-note",
        "项目列表尚未加载 · 当前范围 " + model.tender_project_id,
      ),
    )
  } else {
    for project in model.project_rows {
      project_picker.push(
        button(
          class=if project.project_id == model.tender_project_id {
            "erp-project-chip is-active"
          } else {
            "erp-project-chip"
          },
          on_click=emit(SelectTenderProject(project.project_id)),
          project.project_code + " · " + project.project_name,
        ),
      )
    }
  }
  page_shell(
    "合约规划",
    "COST / TENDER",
    "按项目和 CBS 科目编制合约规划，控制招采范围、预算和合同落地。",
    tender_actions(emit, model),
    div <| [
      div(class="erp-project-picker") <| project_picker,
      tender_form_view(emit, model),
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
          if model.tender_source_loaded {
            "PostgreSQL 源"
          } else if model.tenders_loaded {
            "PostgreSQL 读取中"
          } else {
            "快照"
          },
          model.tender_note +
          " · 定标/分判 " +
          model.tender_source_award_count +
          "/" +
          model.tender_source_split_count,
          "metric-blue",
        ),
      ],
      div(class="erp-tabs") <| [
        button(
          class=if model.tender_tab == "tenders" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectTenderTab("tenders")),
          "招标计划",
        ),
        button(
          class=if model.tender_tab == "awards" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectTenderTab("awards")),
          "定标记录",
        ),
      ],
      filter_bar("项目 / 合约包 / CBS 科目"),
      if model.tender_tab == "awards" {
        tender_award_table(model)
      } else {
        table_panel(
          "合约规划包",
          model.tender_note +
          " · " +
          model.tender_source_note +
          " · award 需通过供应商资格与投标匹配校验",
          tender_table(emit, rows),
        )
      },
      div(class="erp-runtime-banner", [
        strong("源招采命令门"),
        span(" · " + model.tender_source_command_note),
        span(
          " · 资格/状态候选不触发合同、workflow、cash、accounting、tax",
        ),
      ]),
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
  if rows.length() == 0 {
    rendered.push(
      tr <| [
        td("— / imported_or_empty"),
        td("本次 ERP 源导出没有供应商记录"),
        td("—"),
        td("源表为空或尚未导出"),
        td("—"),
        td("—"),
      ],
    )
  } else {
    for row in rows {
      rendered.push(
        tr <| [
          td(
            row.supplier_code +
            " · " +
            row.supplier_id +
            " / " +
            row.source_kind,
          ),
          td(row.name),
          td(row.category_code),
          td(row.scope),
          td(supplier_evaluation_label(row.evaluation)),
          td(supplier_state_label(row.state)),
        ],
      )
    }
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
  let rows = if model.supplier_source_loaded {
    model.supplier_source_rows
  } else if model.suppliers_loaded && model.supplier_rows.length() > 0 {
    model.supplier_rows
  } else {
    fallback_supplier_rows()
  }
  let source_note = if model.supplier_source_loaded {
    model.supplier_source_note +
    " · 缺失/空源表 " +
    model.supplier_source_missing_table_count +
    " · 来源字典 " +
    model.supplier_source_count +
    " 行"
  } else {
    model.supplier_note
  }
  let source_label = if model.supplier_source_loaded {
    if model.supplier_dict_loaded {
      "ERP 源表+字典"
    } else {
      "ERP 源表"
    }
  } else if model.suppliers_loaded {
    "PostgreSQL 投影"
  } else {
    "快照"
  }
  let actions : Array[@html.Html] = [
    nav_button(
      emit, "/srm/providers/SUP-00018", "erp-primary-btn", "＋ 新增供应商",
    ),
    button(
      class="erp-secondary-btn",
      on_click=emit(RescoreSuppliers),
      "重算风险评分（候选）",
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
          "集团供应商总数",
          if model.supplier_stats_loaded {
            model.supplier_stats_total
          } else {
            "—"
          },
          if model.supplier_stats_loaded {
            "TOP 合作 " + model.supplier_stats_top_business
          } else {
            "等待 ERP 源统计"
          },
          "metric-blue",
        ),
        metric(
          "源合同证据",
          if model.supplier_stats_loaded {
            model.supplier_stats_contract_rows
          } else {
            "—"
          },
          if model.supplier_stats_loaded {
            model.supplier_stats_note
          } else {
            "供应商统计尚未加载"
          },
          "metric-blue",
        ),
        metric(
          "本地命令",
          supplier_state_label(model.supplier_state),
          supplier_evaluation_label(model.supplier_evaluation),
          "metric-green",
        ),
        metric("数据来源", source_label, source_note, "metric-blue"),
      ],
      filter_bar("供应商名称 / 统一社会信用代码 / 类别"),
      table_panel(
        "供应商列表",
        source_note + " · " + rows.length().to_string() + " 家供应商",
        supplier_table(rows),
      ),
    ],
  )
}

///|
fn supplier_risk_table(rows : Array[SupplierRiskRow]) -> @html.Html {
  let rendered : Array[Array[String]] = []
  if rows.length() == 0 {
    rendered.push([
      "—", "—", "本次 ERP 源导出没有供应商风险记录", "—", "—",
      "—", "imported_or_empty",
    ])
  } else {
    for row in rows {
      rendered.push([
        row.provider_name +
        " · " +
        row.provider_code +
        " / " +
        row.provider_guid,
        if row.risk_tags == "" {
          "评级 " + row.rating
        } else {
          row.risk_tags
        },
        "评分 " +
        row.risk_score +
        " · 合同 " +
        row.contract_count +
        " 笔 · " +
        row.contract_total,
        row.overdue_count +
        " / " +
        row.contract_count +
        " · " +
        row.overdue_amount,
        row.main_category_code,
        if row.rating_updated_at == "" {
          row.short_name
        } else {
          row.rating_updated_at
        },
        row.rating + " · " + row.source_kind,
      ])
    }
  }
  data_table(
    [
      "供应商", "风险类型", "风险说明", "影响合同", "主营类别",
      "更新时间", "状态",
    ],
    rendered,
  )
}

///|
fn srm_risk_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let risk_table = if model.supplier_risk_loaded {
    supplier_risk_table(model.supplier_risk_rows)
  } else {
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
    )
  }
  let high_risk_count = if model.supplier_risk_loaded {
    model.supplier_risk_rows.length().to_string()
  } else {
    "6"
  }
  let distribution_total = if model.supplier_risk_loaded {
    model.supplier_risk_distribution_total
  } else {
    "18"
  }
  let expiring_count = if model.supplier_risk_loaded { "—" } else { "12" }
  page_shell(
    "供应商风险面板",
    "SRM / RISK",
    "集中查看资质到期、履约偏差、诉讼和集中度风险，支持责任人跟进。",
    [
      button(class="erp-secondary-btn", "导出风险清单"),
      button(
        class="erp-secondary-btn",
        on_click=emit(Navigate("/srm/risk-board")),
        "刷新风险清单",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.supplier_risk_loaded {
            "PostgreSQL 供应商风险源已连接"
          } else {
            "供应商风险源读模型"
          },
        ),
        span(" · " + model.supplier_risk_note),
        span(" · 缺失/空源表 " + model.supplier_risk_missing_table_count),
      ]),
      div(class="erp-stat-grid") <| [
        metric(
          "高风险",
          high_risk_count,
          if model.supplier_risk_loaded {
            "源 D/E 风险行"
          } else {
            "需在 7 日内处理"
          },
          "metric-blue",
        ),
        metric(
          "评级分布",
          distribution_total,
          if model.supplier_risk_loaded {
            "源供应商总数"
          } else {
            "较上周 -2"
          },
          "metric-blue",
        ),
        metric(
          "资质即将到期",
          expiring_count,
          if model.supplier_risk_loaded {
            "源未提供到期字段"
          } else {
            "未来 30 天"
          },
          "metric-green",
        ),
      ],
      table_panel(
        "风险清单",
        if model.supplier_risk_loaded {
          "按 ERP 源风险计算排序 · 源行只读"
        } else {
          "按风险等级排序 · 等待 PostgreSQL 源读模型"
        },
        risk_table,
      ),
    ],
  )
}

///|
fn cbs_runtime_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.cbs_loaded {
    if model.cbs_rows.length() == 0 {
      rows.push([
        "—", "—", "—", "本次导出没有 CBS 字典源记录", "—", "imported_or_empty",
      ])
    } else {
      for row in model.cbs_rows {
        rows.push([
          row.l3_code,
          row.r_code,
          row.l2_name,
          row.subject,
          row.plan_amount,
          row.src,
        ])
      }
    }
    table_panel(
      "PostgreSQL CBS 字典 (" + model.cbs_rows.length().to_string() + ")",
      model.cbs_note +
      " · 版本 " +
      model.cbs_plan_version +
      " · R0 待归类 " +
      model.cbs_r0_count +
      " · 空源表 " +
      model.cbs_missing_table_count,
      data_table(
        [
          "L3 编码", "R 编码", "L2 名称", "科目", "计划金额", "来源",
        ],
        rows,
      ),
    )
  } else {
    table_panel(
      "CBS 数据",
      "设计快照 · 等待 PostgreSQL 源读模型",
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
        ],
      ),
    )
  }
}

///|
fn cbs_view(model : Model, path : String) -> @html.Html {
  let title = title_for(path)
  page_shell(
    title,
    "CBS / MASTER DATA",
    "维护成本分解结构、目标版本和审批配置，确保项目成本口径一致。",
    [button(class="erp-primary-btn", "＋ 新建条目")],
    div <| [
      filter_bar("科目编码 / 科目名称 / 版本"),
      cbs_runtime_table(model),
    ],
  )
}

///|
fn fund_runtime_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.fund_tab == "gap" {
    let rows : Array[Array[String]] = []
    if model.fund_gap_rows.length() == 0 {
      rows.push(["—", "0", "0", "0", "0", "0"])
    } else {
      for row in model.fund_gap_rows {
        rows.push([
          row.period,
          row.plan_in,
          row.plan_out,
          row.net,
          row.cum_net,
          row.gap,
        ])
      }
    }
    table_panel(
      "缺口分析 (" + model.fund_gap_series_count + ")",
      "项目 " +
      model.fund_project_id +
      " · 空源表 " +
      model.fund_missing_table_count,
      data_table(
        [
          "期间", "计划收入(万)", "计划支出(万)", "本期净流(万)",
          "累计净流(万)", "缺口(万)",
        ],
        rows,
      ),
    )
  } else if model.fund_tab == "dispatches" {
    let rows : Array[@html.Html] = []
    if model.fund_dispatch_rows.length() == 0 {
      rows.push(
        tr <| [
          td("—"),
          td("—"),
          td("—"),
          td("—"),
          td("0"),
          td("无源记录"),
          td("—"),
          td("—"),
          td("—"),
        ],
      )
    } else {
      for row in model.fund_dispatch_rows {
        let action = if row.source_kind == "command" &&
          row.dispatch_guid != "" &&
          row.state == "pending" {
          button(
            class="erp-link-btn is-success",
            on_click=emit(SelectFundDispatch(row.dispatch_guid)),
            "批准",
          )
        } else {
          span(class="erp-source-note", "源行只读")
        }
        rows.push(
          tr <| [
            td(row.dispatch_code),
            td(row.dispatch_date),
            td(row.from_proj),
            td(row.to_proj),
            td(row.amount),
            td(row.reason),
            td(row.state),
            td(row.source_kind),
            td(action),
          ],
        )
      }
    }
    table_panel(
      "资金调度 (" + model.fund_dispatch_count + ")",
      "调度记录源读模型 · 空源表 " + model.fund_missing_table_count,
      table(class="erp-data-table") <| [
        thead <| [
          table_header([
            "编号", "调度日", "来源项目", "目标项目", "金额(万)",
            "原因", "状态", "来源", "操作",
          ]),
        ],
        tbody <| rows,
      ],
    )
  } else {
    let rows : Array[@html.Html] = []
    if model.fund_loaded && model.fund_rows.length() > 0 {
      for row in model.fund_rows {
        let actions : Array[@html.Html] = if row.source_kind == "command" &&
          row.plan_guid != "" {
          [
            button(
              class="erp-link-btn",
              on_click=emit(OpenFundPlanEdit(row.plan_guid)),
              "编辑",
            ),
            button(
              class="erp-link-btn is-warning",
              on_click=emit(DeleteFundPlanRow(row.plan_guid)),
              "作废",
            ),
          ]
        } else {
          [span(class="erp-source-note", "源行只读")]
        }
        rows.push(
          tr <| [
            td(row.plan_code),
            td(row.plan_period),
            td(row.direction),
            td(row.category),
            td(row.r_code),
            td(row.proj_name),
            td(row.plan_amount),
            td(row.actual_amount),
            td(row.remark),
            td(row.state),
            td(row.source_kind),
            td <| actions,
          ],
        )
      }
    } else if model.fund_loaded {
      rows.push(
        tr <| [
          td("—"),
          td("—"),
          td("本次导出没有资金计划源记录"),
          td("—"),
          td("—"),
          td("—"),
          td("0"),
          td("0"),
          td("—"),
          td("源表为空"),
          td("—"),
          td("—"),
        ],
      )
    } else {
      rows.push(
        tr <| [
          td("FP-DESIGN"),
          td("2026-08"),
          td("收入"),
          td("回款"),
          td("R6"),
          td("成都和锦里"),
          td("2460"),
          td("0"),
          td("设计快照"),
          td("设计快照"),
          td("—"),
          td("—"),
        ],
      )
      rows.push(
        tr <| [
          td("FP-DESIGN-OUT"),
          td("2026-08"),
          td("支出"),
          td("工程款"),
          td("R11"),
          td("成都和锦里"),
          td("2180"),
          td("0"),
          td("设计快照"),
          td("设计快照"),
          td("—"),
          td("—"),
        ],
      )
    }
    table_panel(
      "收支计划 (" + model.fund_rows.length().to_string() + ")",
      model.fund_note + " · 项目 " + model.fund_project_id,
      table(class="erp-data-table") <| [
        thead <| [
          table_header([
            "编号", "期间", "方向", "类别", "R 编码", "项目", "计划(万)",
            "实际(万)", "备注", "状态", "来源", "操作",
          ]),
        ],
        tbody <| rows,
      ],
    )
  }
}

///|
fn fund_actions(emit : @rabbita.Emit[Msg], model : Model) -> Array[@html.Html] {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(OpenFundForm("plan")),
      "＋ 编制计划",
    ),
  ]
  if model.fund_plan_id != "" && model.fund_command_state != "pending" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(UpdateFundPlan),
        "更新计划草稿",
      ),
    )
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(DeleteFundPlan),
        "作废计划草稿",
      ),
    )
  }
  if model.fund_dispatch_id == "" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenFundForm("dispatch")),
        "＋ 申请资金调度",
      ),
    )
  } else if model.fund_command_state == "pending" {
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(ApproveFundDispatch),
        "审批资金调度",
      ),
    )
  }
  actions
}

///|
fn fund_form_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.fund_form_open == "plan" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2(
          if model.fund_plan_id.is_empty() {
            "新增收支计划"
          } else {
            "编辑收支计划"
          },
        ),
        span(
          class="erp-source-note",
          "金额按万元输入 · 提交为本地计划命令",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "期间",
          model.fund_plan_period,
          "YYYY-MM",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_period", value)),
        ),
        editable_form_field(
          "方向",
          model.fund_plan_direction,
          "in / out",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_direction", value)),
        ),
        editable_form_field(
          "类别",
          model.fund_plan_category,
          "回款/工程款/营销费",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_category", value)),
        ),
        editable_form_field(
          "R 编码",
          model.fund_plan_r_code,
          "R11",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_r_code", value)),
        ),
        editable_form_field(
          "计划金额（万）",
          model.fund_plan_amount,
          "50",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_amount", value)),
        ),
        editable_form_field(
          "实际金额（万）",
          model.fund_plan_actual_amount,
          "0",
          @html.InputType::Text,
          emit.map(value => InputFundField("actual_amount", value)),
        ),
        editable_form_field(
          "备注",
          model.fund_plan_remark,
          "备注",
          @html.InputType::Text,
          emit.map(value => InputFundField("plan_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(class="erp-ghost-btn", on_click=emit(CloseFundForm), "取消"),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateFundPlan),
          if model.fund_plan_id.is_empty() {
            "提交计划"
          } else {
            "保存计划"
          },
        ),
      ],
    ]
  } else if model.fund_form_open == "dispatch" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增资金调度"),
        span(
          class="erp-source-note",
          "金额按万元输入 · 资金释放保持独立审批",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "来源项目",
          model.fund_dispatch_from,
          "项目 GUID",
          @html.InputType::Text,
          emit.map(value => InputFundField("dispatch_from", value)),
        ),
        editable_form_field(
          "目标项目",
          model.fund_dispatch_to,
          model.fund_project_id,
          @html.InputType::Text,
          emit.map(value => InputFundField("dispatch_to", value)),
        ),
        editable_form_field(
          "金额（万）",
          model.fund_dispatch_amount,
          "10",
          @html.InputType::Text,
          emit.map(value => InputFundField("dispatch_amount", value)),
        ),
        editable_form_field(
          "调度日",
          model.fund_dispatch_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputFundField("dispatch_date", value)),
        ),
        editable_form_field(
          "原因",
          model.fund_dispatch_reason,
          "资金缺口/项目周转",
          @html.InputType::Text,
          emit.map(value => InputFundField("dispatch_reason", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(class="erp-ghost-btn", on_click=emit(CloseFundForm), "取消"),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateFundDispatch),
          "提交调度",
        ),
      ],
    ]
  } else {
    @html.nothing
  }
}

///|
fn fund_plan_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let plan_outflow = if model.fund_loaded { "—" } else { "¥3,860 万" }
  let gap = if model.fund_loaded { "—" } else { "¥620 万" }
  page_shell(
    "资金计划",
    "FINANCE / FUND PLAN",
    "统筹项目回款、融资、付款与资金缺口，形成月度和滚动资金计划。",
    fund_actions(emit, model),
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.fund_loaded {
            "PostgreSQL 资金计划源已连接"
          } else {
            "资金计划设计快照"
          },
        ),
        span(" · " + model.fund_note),
        span(" · " + model.fund_command_note),
      ]),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目:"),
        if model.project_rows.length() == 0 {
          span(class="erp-info-tag", model.fund_project_id)
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.fund_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectFundProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      fund_form_view(emit, model),
      div(class="erp-stat-grid") <| [
        metric(
          "本月可用资金",
          if model.fund_loaded {
            "—"
          } else {
            "¥4,280 万"
          },
          if model.fund_loaded {
            "期初余额源未提供"
          } else {
            "含银行余额"
          },
          "metric-blue",
        ),
        metric(
          "本月计划流出",
          plan_outflow,
          if model.fund_loaded {
            "fund_plan 源读模型"
          } else {
            "付款 48 笔"
          },
          "metric-blue",
        ),
        metric(
          "资金缺口",
          gap,
          if model.fund_loaded {
            "gap-analysis 源读模型"
          } else {
            "预计 8 月出现"
          },
          "metric-green",
        ),
        metric(
          "缺口期间",
          model.fund_gap_series_count,
          "gap-analysis 源读模型",
          "metric-orange",
        ),
        metric(
          "资金调度",
          model.fund_dispatch_count,
          "dispatches 源读模型",
          "metric-purple",
        ),
      ],
      div(class="erp-tabs") <| [
        button(
          class=if model.fund_tab == "plans" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectFundTab("plans")),
          "收支计划",
        ),
        button(
          class=if model.fund_tab == "gap" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectFundTab("gap")),
          "缺口分析",
        ),
        button(
          class=if model.fund_tab == "dispatches" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectFundTab("dispatches")),
          "资金调度",
        ),
      ],
      fund_runtime_table(emit, model),
    ],
  )
}

///|
fn invoice_sum(rows : Array[InvoiceRow], tax : Bool) -> String {
  let mut total = 0.0
  for row in rows {
    let value = if tax { row.tax_amount } else { row.total_amount }
    let parsed = @json.parse(value) catch { _ => Json::null() }
    match parsed {
      Json::Number(number, ..) => total = total + number
      _ => ()
    }
  }
  total.to_string()
}

///|
fn invoice_runtime_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
  direction : String,
) -> @html.Html {
  let source_rows = if direction == "in" {
    model.invoice_in_rows
  } else {
    model.invoice_out_rows
  }
  let rows : Array[@html.Html] = []
  if source_rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("0"),
        td("0"),
        td("0"),
        td("—"),
        td("源表为空"),
        td("—"),
      ],
    )
  } else {
    for row in source_rows {
      let action = if row.source_kind == "command" &&
        !row.invoice_guid.is_empty() {
        button(
          class="erp-link-btn is-warning",
          on_click=emit(DeleteInvoice(direction, row.invoice_guid)),
          "删除",
        )
      } else {
        span(class="erp-source-note", "源行只读")
      }
      rows.push(
        tr <| [
          td(row.invoice_no),
          td(row.counterparty),
          td(row.invoice_date),
          td(row.total_amount),
          td(row.tax_amount),
          td(row.tax_rate),
          td(row.invoice_type),
          td(row.state),
          td(row.source_kind),
          td(action),
        ],
      )
    }
  }
  table_panel(
    if direction == "in" {
      "进项发票（采购）"
    } else {
      "销项发票（销售）"
    },
    "项目 " +
    model.invoice_project_id +
    " · " +
    source_rows.length().to_string() +
    " 条 · 导入行只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "发票号",
          if direction == "in" {
            "供应商"
          } else {
            "客户"
          },
          "开票日",
          "金额(含税)",
          "税额",
          "税率",
          "类型",
          "状态",
          "来源",
          "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn invoice_tax_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.invoice_tax_rows.length() == 0 {
    rows.push(["—", "0", "0", "0", "0", "0"])
  } else {
    for row in model.invoice_tax_rows {
      rows.push([
        row.period,
        row.total_in,
        row.tax_in,
        row.total_out,
        row.tax_out,
        row.net_tax,
      ])
    }
  }
  table_panel(
    "税务台账（月度）",
    "项目 " +
    model.invoice_project_id +
    " · " +
    model.invoice_source_tax_count +
    " 行",
    data_table(
      [
        "月份", "进项总额", "进项税额", "销项总额", "销项税额",
        "应缴增值税（销-进）",
      ],
      rows,
    ),
  )
}

///|
fn invoice_form_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.invoice_form_open == "in" || model.invoice_form_open == "out" {
    let direction = model.invoice_form_open
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2(
          if direction == "in" {
            "录入进项发票"
          } else {
            "开销项发票"
          },
        ),
        span(
          class="erp-source-note",
          "金额按元输入 · 写入本地发票命令投影",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "发票号",
          model.invoice_no,
          "发票号",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_no", value)),
        ),
        editable_form_field(
          if direction == "in" {
            "供应商"
          } else {
            "客户"
          },
          model.invoice_counterparty,
          "名称",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_counterparty", value)),
        ),
        editable_form_field(
          "开票日",
          model.invoice_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_date", value)),
        ),
        editable_form_field(
          "金额（含税）",
          model.invoice_total_amount,
          "10000",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_total_amount", value)),
        ),
        editable_form_field(
          "税率",
          model.invoice_tax_rate,
          "0.09",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_tax_rate", value)),
        ),
        editable_form_field(
          "发票类型",
          model.invoice_type,
          "增值税专用发票",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_type", value)),
        ),
        editable_form_field(
          "备注",
          model.invoice_remark,
          "备注",
          @html.InputType::Text,
          emit.map(value => InputInvoiceField("invoice_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(class="erp-ghost-btn", on_click=emit(CloseInvoiceForm), "取消"),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateInvoice(direction)),
          "提交",
        ),
      ],
    ]
  } else {
    @html.nothing
  }
}

///|
fn invoice_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let in_total = if model.invoice_source_loaded {
    "¥" + invoice_sum(model.invoice_in_rows, false)
  } else {
    "¥1,286 万"
  }
  let out_total = if model.invoice_source_loaded {
    "¥" + invoice_sum(model.invoice_out_rows, false)
  } else {
    "¥—"
  }
  let tax_total = if model.invoice_source_loaded {
    invoice_sum(model.invoice_out_rows, true)
  } else {
    "—"
  }
  page_shell(
    "发票管理",
    "FINANCE / INVOICE",
    "管理进项、销项发票的识别、验真、关联合同和入账状态。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(OpenInvoiceForm("in")),
        "＋ 录入进项",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenInvoiceForm("out")),
        "＋ 开销项",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.invoice_source_loaded {
            "PostgreSQL 发票/税务源已连接"
          } else {
            "发票源读模型"
          },
        ),
        span(
          " · " +
          model.invoice_source_note +
          " · 税务台账 " +
          model.invoice_source_tax_count +
          " 行",
        ),
      ]),
      sales_projection_table(model, "invoices"),
      div(class="erp-stat-grid") <| [
        metric(
          "进项总额",
          in_total,
          model.invoice_source_in_count + " 张",
          "metric-blue",
        ),
        metric(
          "销项总额",
          out_total,
          model.invoice_source_out_count + " 张",
          "metric-green",
        ),
        metric(
          "应缴增值税",
          "¥" + tax_total,
          "税务台账汇总",
          "metric-orange",
        ),
      ],
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目:"),
        if model.project_rows.length() == 0 {
          span(class="erp-info-tag", model.invoice_project_id)
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.invoice_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectInvoiceProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      invoice_form_view(emit, model),
      div(class="erp-tabs") <| [
        button(
          class=if model.invoice_tab == "in" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectInvoiceTab("in")),
          "进项发票（采购）",
        ),
        button(
          class=if model.invoice_tab == "out" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectInvoiceTab("out")),
          "销项发票（销售）",
        ),
        button(
          class=if model.invoice_tab == "tax" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectInvoiceTab("tax")),
          "税务台账（月度）",
        ),
      ],
      if model.invoice_tab == "in" {
        invoice_runtime_table(emit, model, "in")
      } else if model.invoice_tab == "out" {
        invoice_runtime_table(emit, model, "out")
      } else {
        invoice_tax_table(model)
      },
    ],
  )
}

///|
fn budget_scope_banner(model : Model) -> @html.Html {
  let scope_text = if model.budget_scope_loaded {
    "预算人员 " + model.budget_scope_users.length().to_string() + " 人"
  } else {
    "预算人员范围待加载"
  }
  let loan_text = if model.budget_loan_balance_loaded {
    "个人借款余额 ¥" +
    model.budget_loan_balance_total +
    "（" +
    model.budget_loan_count +
    " 笔）"
  } else {
    "个人借款余额待加载"
  }
  let scope_sample = match model.budget_scope_users.get(0) {
    Some(user) =>
      " · 示例 " +
      user.emp_name +
      " · " +
      user.user_id +
      " · BU " +
      user.bu_guid +
      " · 部门 " +
      user.dept_guid +
      " · " +
      user.source_kind
    None => ""
  }
  div(class="erp-runtime-banner", [
    strong(
      if model.budget_scope_loaded && model.budget_loan_balance_loaded {
        "PostgreSQL 预算范围观察已连接"
      } else {
        "预算范围读模型"
      },
    ),
    span(" · " + scope_text + " · " + loan_text),
    span(
      " · " +
      model.budget_scope_note +
      " · " +
      model.budget_loan_note +
      scope_sample,
    ),
  ])
}

///|
fn expense_runtime_table(model : Model) -> @html.Html {
  if model.expenses_loaded {
    let rows : Array[Array[String]] = []
    if model.expense_rows.length() == 0 {
      rows.push([
        "—", "—", "本次导出没有报销源记录", "—", "—", "—", "—",
        "imported_or_empty",
      ])
    } else {
      for row in model.expense_rows {
        rows.push([
          row.expense_code,
          "报销",
          row.subject,
          "¥" + row.expense_amount,
          row.apply_date,
          row.applied_by_name + " · " + row.apply_dept_name,
          row.apply_state + " / " + row.pay_state,
          row.source_kind + " · " + row.expense_id,
        ])
      }
    }
    table_panel(
      "PostgreSQL 报销记录 (" +
      model.expense_rows.length().to_string() +
      ")",
      model.expenses_note,
      data_table(
        [
          "报销单号", "费用类型", "摘要", "金额", "申请日期", "申请人",
          "状态", "来源",
        ],
        rows,
      ),
    )
  } else {
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
            "EXP-260628-011", "办公费", "项目打印及耗材", "¥1,860", "2026-06-28",
            "—", "已完成",
          ],
        ],
      ),
    )
  }
}

///|
fn expenses_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "我的报销",
    "FINANCE / EXPENSES",
    "发起差旅、招待和日常费用报销，查看预算占用、审批节点与付款进度。",
    [nav_button(emit, "/expenses/new", "erp-primary-btn", "＋ 新建报销")],
    div <| [
      budget_scope_banner(model),
      div(class="erp-stat-grid") <| [
        metric("本月报销", "¥28,560", "8 笔", "metric-blue"),
        metric("审批中", "5", "金额 ¥16,420", "metric-blue"),
        metric("已付款", "¥62,180", "本年度", "metric-green"),
      ],
      filter_bar("报销单号 / 摘要 / 申请日期"),
      expense_runtime_table(model),
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
    [
      nav_button(emit, "/loans/new", "erp-primary-btn", "＋ 新建借款"),
      button(
        class="erp-secondary-btn",
        on_click=emit(SyncLoanWorkflow),
        "检查工作流同步（待授权）",
      ),
    ],
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
      div(class="erp-runtime-banner", [
        strong("工作流同步候选"),
        span(" · " + model.loan_workflow_sync_note),
        span(" · 借款 " + model.loan_id),
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
    span(
      " · 常用偏好 " +
      (if model.report_favorite_loaded { "已连接" } else { "未加载" }),
    ),
  ])
}

///|
fn reports_data_tables(model : Model) -> @html.Html {
  let tab = model.report_tab
  let cost_rows : Array[Array[String]] = []
  for row in model.report_cost_rows {
    cost_rows.push([
      row.bu_name,
      row.proj_code,
      row.proj_name,
      row.target_cost,
      row.dynamic_cost,
      row.deviation_pct + "%",
      row.spare,
      row.d_amount,
      row.e_amount,
      row.f_amount,
      row.g_amount,
      row.source_kind,
    ])
  }
  let contract_rows : Array[Array[String]] = []
  for row in model.report_contract_rows {
    contract_rows.push([
      row.contract_code,
      row.contract_name,
      row.bu_name,
      row.proj_name,
      row.provider,
      row.sign_date,
      row.current_amount,
      row.applied_total,
      row.paid_total,
      row.remain_amount,
      row.paid_pct + "%",
      row.source_kind,
    ])
  }
  let stage_rows : Array[Array[String]] = []
  for row in model.report_stage_rows {
    let values : Array[String] = [
      row.proj_name + " · " + row.proj_guid,
      row.bu_name,
      row.proj_code,
      row.proj_status,
      row.begin_date + " → " + row.end_date,
    ]
    for cell in row.cells {
      values.push(
        cell.stage_code + " · " + cell.status + " " + cell.progress_pct + "%",
      )
    }
    values.push(row.source_kind)
    stage_rows.push(values)
  }
  let supplier_rows : Array[Array[String]] = []
  for row in model.report_supplier_rows {
    supplier_rows.push([
      row.provider_name,
      row.short_name,
      row.category_name,
      row.eval_result,
      row.contract_count,
      row.bu_count,
      row.proj_count,
      row.total_amount,
      row.recent_amount,
      row.source_kind,
    ])
  }
  let approval_rows : Array[Array[String]] = []
  for row in model.report_approval_rows {
    approval_rows.push([
      row.biz_type,
      row.total,
      row.completed,
      row.rejected,
      row.running,
      row.overdue,
      row.avg_days,
      row.reject_rate + "%",
    ])
  }
  let slow_rows : Array[Array[String]] = []
  for row in model.report_slow_step_rows {
    slow_rows.push([row.step_name, row.emp_name, row.avg_days, row.count])
  }
  if tab == "contract" {
    table_panel(
      "R2 合同付款台账",
      "滚动展示合同当前金额 / 已申请 / 已付 / 未付 / 付款率 · " +
      model.reports_note,
      data_table(
        [
          "合同", "名称", "公司", "项目", "乙方", "签订日期", "当前金额",
          "已申请", "已付", "未付", "付款率", "来源",
        ],
        contract_rows,
      ),
    )
  } else if tab == "supplier" {
    table_panel(
      "R3 供应商合作分析",
      "按累计合作金额排序 · 仅显示有合同的供应商",
      data_table(
        [
          "供应商", "简称", "类别", "评级", "合作笔数", "跨公司数",
          "跨项目数", "累计金额", "近 1 年", "来源",
        ],
        supplier_rows,
      ),
    )
  } else if tab == "approval" {
    div <| [
      table_panel(
        "R4 审批效率分析",
        "按业务类型汇总流程实例 · 空源表保持可见",
        data_table(
          [
            "业务类型", "总数", "已完成", "已驳回", "进行中", "超 7 天未结",
            "平均处理天数", "驳回率",
          ],
          approval_rows,
        ),
      ),
      table_panel(
        "最慢节点 TOP 10",
        "单步骤平均耗时 · 当前源数据可能没有足够样本",
        data_table(
          ["节点", "责任人", "平均耗时", "样本数"],
          slow_rows,
        ),
      ),
    ]
  } else if tab == "stage" {
    let headers : Array[String] = [
      "项目", "公司", "项目编码", "项目状态", "计划区间",
    ]
    for stage_name in model.report_stage_names {
      headers.push(stage_name)
    }
    headers.push("来源")
    table_panel(
      "R5 项目阶段进度大盘",
      "绿色已完成 / 黄色进行中 / 灰色待启动 · 阶段单元格保留进度证据",
      data_table(headers, stage_rows),
    )
  } else {
    table_panel(
      "R1 集团成本汇总",
      "按项目展示目标 vs 动态成本 (D+E+F+G) · 偏差小于 0 为超目标",
      data_table(
        [
          "公司", "项目编码", "项目名称", "目标 A", "动态 B", "偏差 C%",
          "余量 H", "D 合约", "E 在途", "F 未定", "G 预期", "来源",
        ],
        cost_rows,
      ),
    )
  }
}

///|
fn report_csv(model : Model) -> String {
  let lines : Array[String] = []
  if model.report_tab == "contract" {
    lines.push(
      "合同编号,合同名称,公司,项目,乙方,签订日期,当前金额,已申请,已付,未付,付款率,来源",
    )
    for row in model.report_contract_rows {
      lines.push(
        [
          row.contract_code,
          row.contract_name,
          row.bu_name,
          row.proj_name,
          row.provider,
          row.sign_date,
          row.current_amount,
          row.applied_total,
          row.paid_total,
          row.remain_amount,
          row.paid_pct,
          row.source_kind,
        ]
        .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
        .join(","),
      )
    }
  } else if model.report_tab == "supplier" {
    lines.push(
      "供应商,简称,类别,评级,合作笔数,跨公司数,跨项目数,累计金额,近1年,来源",
    )
    for row in model.report_supplier_rows {
      lines.push(
        [
          row.provider_name,
          row.short_name,
          row.category_name,
          row.eval_result,
          row.contract_count,
          row.bu_count,
          row.proj_count,
          row.total_amount,
          row.recent_amount,
          row.source_kind,
        ]
        .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
        .join(","),
      )
    }
  } else if model.report_tab == "approval" {
    lines.push(
      "业务类型,总数,已完成,已驳回,进行中,超7天未结,平均处理天数,驳回率",
    )
    for row in model.report_approval_rows {
      lines.push(
        [
          row.biz_type,
          row.total,
          row.completed,
          row.rejected,
          row.running,
          row.overdue,
          row.avg_days,
          row.reject_rate,
        ]
        .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
        .join(","),
      )
    }
  } else if model.report_tab == "stage" {
    lines.push(
      "项目,公司,项目编码,状态,计划区间,阶段进度,来源",
    )
    for row in model.report_stage_rows {
      lines.push(
        [
          row.proj_name + " · " + row.proj_guid,
          row.bu_name,
          row.proj_code,
          row.proj_status,
          row.begin_date + " → " + row.end_date,
          row.cells
          .map(fn(cell) {
            cell.stage_name + ":" + cell.status + " " + cell.progress_pct + "%"
          })
          .join(" · "),
          row.source_kind,
        ]
        .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
        .join(","),
      )
    }
  } else {
    lines.push(
      "公司,项目编码,项目名称,目标A,动态B,偏差C%,余量H,D合约,E在途,F未定,G预期,来源",
    )
    for row in model.report_cost_rows {
      lines.push(
        [
          row.bu_name,
          row.proj_code,
          row.proj_name,
          row.target_cost,
          row.dynamic_cost,
          row.deviation_pct,
          row.spare,
          row.d_amount,
          row.e_amount,
          row.f_amount,
          row.g_amount,
          row.source_kind,
        ]
        .map(value => "\"" + value.replace(old="\"", new="\"\"") + "\"")
        .join(","),
      )
    }
  }
  lines.join("\n")
}

///|
fn report_share_rows_from_body(body : String) -> Array[ReportShareRow] {
  let rows : Array[ReportShareRow] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match value {
          Json::Object(row) =>
            rows.push({
              token: json_object_text(row, "token", ""),
              report_key: json_object_text(row, "reportKey", ""),
              report_label: json_object_text(row, "reportLabel", ""),
              title: json_object_text(row, "title", ""),
              created_at: json_object_text(row, "createdAt", ""),
              expires_at: json_object_text(row, "expiresAt", ""),
              never_expires: if json_object_text(row, "neverExpires", "false") ==
                "true" {
                "永久"
              } else {
                ""
              },
              access_count: json_object_text(row, "accessCount", "0"),
              revoked: if json_object_text(row, "revoked", "false") == "true" {
                "已撤销"
              } else {
                ""
              },
              expired: if json_object_text(row, "expired", "false") == "true" {
                "已过期"
              } else {
                ""
              },
              source_kind: json_object_text(row, "sourceKind", "command"),
            })
          _ => ()
        }
      }
    _ => ()
  }
  rows
}

///|
fn report_share_token_from_body(body : String) -> String {
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => json_object_text(data, "token", "")
        _ => ""
      }
    _ => ""
  }
}

///|
fn report_share_create_body(model : Model) -> String {
  let expires = if model.report_share_days == "0" {
    "null"
  } else {
    model.report_share_days
  }
  "{\"reportKey\":\"" +
  model.report_tab +
  "\",\"title\":\"" +
  model.report_share_title.replace(old="\"", new="\\\"") +
  "\",\"expiresInDays\":" +
  expires +
  ",\"idempotency_key\":\"rabbita-report-share-create-v1\"}"
}

///|
fn load_report_shares(emit : @rabbita.Emit[Msg]) -> Cmd {
  @http.get("/api/company/reports/shares").expect_text(result => {
    match result {
      Ok(body) => emit(ReportSharesLoaded(body))
      Err(_) => emit(ReportSharesLoadFailed)
    }
  })
}

///|
fn report_favorite_keys_from_body(body : String) -> Array[String] {
  let keys : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) => {
      let data = match fields.get("data") {
        Some(Json::Object(value)) => value
        _ =>
          match fields.get("preference") {
            Some(Json::Object(value)) => value
            _ => {}
          }
      }
      let values = match data.get("fav_reports") {
        Some(Json::Array(items)) => items
        _ =>
          match data.get("value") {
            Some(Json::Array(items)) => items
            _ => []
          }
      }
      for value in values {
        match value {
          Json::String(key) => keys.push(key)
          _ => ()
        }
      }
    }
    _ => ()
  }
  keys
}

///|
fn load_report_preferences(
  emit : @rabbita.Emit[Msg],
  user_code : String,
) -> Cmd {
  @http.get("/api/company/auth/prefs?userCode=" + user_code).expect_text(result => {
    match result {
      Ok(body) => emit(ReportPreferencesLoaded(body))
      Err(_) => emit(ReportPreferencesLoadFailed)
    }
  })
}

///|
fn report_preference_body(model : Model) -> String {
  let keys = report_favorite_next_keys(model)
  let action = if model.report_favorite_keys.contains(model.report_tab) {
    "remove"
  } else {
    "add"
  }
  let encoded = keys.map(value => "\"" + value + "\"").join(",")
  "{\"value\":[" +
  encoded +
  "],\"idempotency_key\":\"rabbita-report-pref-fav-" +
  model.report_tab +
  "-" +
  action +
  "-v1\"}"
}

///|
fn report_favorite_next_keys(model : Model) -> Array[String] {
  let keys : Array[String] = []
  for key in model.report_favorite_keys {
    if key != model.report_tab {
      keys.push(key)
    }
  }
  if !model.report_favorite_keys.contains(model.report_tab) {
    keys.push(model.report_tab)
  }
  keys
}

///|
fn issue_report_preference_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> Cmd {
  @http.put("/api/company/source/auth/prefs/fav_reports")
  .with_text(report_preference_body(model))
  .expect_text(result => {
    match result {
      Ok(body) => emit(ReportPreferenceUpdated(body))
      Err(_) => emit(ReportPreferencesLoadFailed)
    }
  })
}

///|
fn issue_report_share_create(emit : @rabbita.Emit[Msg], model : Model) -> Cmd {
  @http.post("/api/company/reports/shares")
  .with_text(report_share_create_body(model))
  .expect_text(result => {
    match result {
      Ok(body) => emit(ReportShareCreated(body))
      Err(_) =>
        emit(ReportShareCreateFailed("分享服务不可用或被网关拒绝"))
    }
  })
}

///|
fn issue_report_share_revoke(emit : @rabbita.Emit[Msg], token : String) -> Cmd {
  @http.delete(
    "/api/company/reports/shares/" +
    token +
    "?idempotency_key=rabbita-report-share-revoke-" +
    token,
  ).expect_text(result => {
    match result {
      Ok(body) => emit(ReportShareRevoked(body))
      Err(_) =>
        emit(ReportShareRevokeFailed("撤销服务不可用或被网关拒绝"))
    }
  })
}

///|
fn share_token_from_path(path : String) -> String {
  if path.has_prefix("/share/") {
    path[7:].to_owned()
  } else {
    ""
  }
}

///|
fn load_share_meta(emit : @rabbita.Emit[Msg], token : String) -> Cmd {
  @http.get("/api/company/share/" + token + "/meta").expect_text(result => {
    match result {
      Ok(body) => emit(ShareMetaLoaded(body))
      Err(_) => emit(ShareLoadFailed("分享元数据加载失败"))
    }
  })
}

///|
fn load_share_data(emit : @rabbita.Emit[Msg], token : String) -> Cmd {
  @http.get("/api/company/share/" + token + "/data").expect_text(result => {
    match result {
      Ok(body) => emit(ShareDataLoaded(body))
      Err(_) => emit(ShareLoadFailed("分享报表数据加载失败"))
    }
  })
}

///|
fn share_cost_table(body : String) -> @html.Html {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "rows") {
            match report_cost_from_json(value) {
              Some(row) =>
                rows.push([
                  row.bu_name,
                  row.proj_code,
                  row.proj_name,
                  row.target_cost,
                  row.dynamic_cost,
                  row.deviation_pct + "%",
                  row.spare,
                ])
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  table_panel(
    "R1 集团成本汇总",
    "分享数据 · 只读公开快照",
    data_table(
      [
        "公司", "项目编码", "项目名称", "目标", "动态", "偏差%",
        "余量",
      ],
      rows,
    ),
  )
}

///|
fn share_contract_table(body : String) -> @html.Html {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match report_contract_from_json(value) {
          Some(row) =>
            rows.push([
              row.contract_code,
              row.contract_name,
              row.bu_name,
              row.provider,
              row.current_amount,
              row.paid_total,
              row.remain_amount,
              row.paid_pct + "%",
            ])
          None => ()
        }
      }
    _ => ()
  }
  table_panel(
    "R2 合同付款台账",
    "分享数据 · 只读公开快照",
    data_table(
      [
        "合同编号", "合同名称", "公司", "乙方", "合同金额", "已付",
        "未付", "付款率",
      ],
      rows,
    ),
  )
}

///|
fn share_supplier_table(body : String) -> @html.Html {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      for value in json_array_field(fields, "data") {
        match report_supplier_from_json(value) {
          Some(row) =>
            rows.push([
              row.provider_name,
              row.category_name,
              row.eval_result,
              row.contract_count,
              row.bu_count,
              row.proj_count,
              row.total_amount,
              row.recent_amount,
            ])
          None => ()
        }
      }
    _ => ()
  }
  table_panel(
    "R3 供应商合作分析",
    "分享数据 · 只读公开快照",
    data_table(
      [
        "供应商", "类别", "评级", "合作笔数", "跨公司", "跨项目",
        "累计金额", "近 1 年",
      ],
      rows,
    ),
  )
}

///|
fn share_approval_table(body : String) -> @html.Html {
  let rows : Array[Array[String]] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) =>
          for value in json_array_field(data, "byType") {
            match report_approval_from_json(value) {
              Some(row) =>
                rows.push([
                  row.biz_type,
                  row.total,
                  row.completed,
                  row.rejected,
                  row.running,
                  row.overdue,
                  row.avg_days,
                  row.reject_rate + "%",
                ])
              None => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  table_panel(
    "R4 审批效率分析",
    "分享数据 · 只读公开快照",
    data_table(
      [
        "业务类型", "总数", "已完成", "已驳回", "进行中", "超期",
        "平均天数", "驳回率",
      ],
      rows,
    ),
  )
}

///|
fn share_stage_table(body : String) -> @html.Html {
  let rows : Array[Array[String]] = []
  let stage_names : Array[String] = []
  let parsed = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(fields) =>
      match fields.get("data") {
        Some(Json::Object(data)) => {
          for value in json_array_field(data, "stages") {
            match value {
              Json::Object(stage) =>
                stage_names.push(
                  json_object_text(
                    stage,
                    "name",
                    json_object_text(stage, "code", ""),
                  ),
                )
              _ => ()
            }
          }
          for value in json_array_field(data, "projects") {
            match report_stage_from_json(value) {
              Some(project) => {
                let row : Array[String] = [
                  project.proj_name,
                  project.bu_name,
                  project.proj_status,
                ]
                for cell in project.cells {
                  row.push(cell.status + " " + cell.progress_pct + "%")
                }
                rows.push(row)
              }
              None => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }
  let headers : Array[String] = ["项目", "公司", "状态"]
  for name in stage_names {
    headers.push(name)
  }
  table_panel(
    "R5 项目阶段进度大盘",
    "分享数据 · 只读公开快照",
    data_table(headers, rows),
  )
}

///|
fn share_data_table(model : Model) -> @html.Html {
  if !model.share_loaded {
    div(class="erp-runtime-empty", model.share_note)
  } else if model.share_report_key == "cost" {
    share_cost_table(model.share_data_body)
  } else if model.share_report_key == "contract" {
    share_contract_table(model.share_data_body)
  } else if model.share_report_key == "supplier" {
    share_supplier_table(model.share_data_body)
  } else if model.share_report_key == "approval" {
    share_approval_table(model.share_data_body)
  } else if model.share_report_key == "stage" {
    share_stage_table(model.share_data_body)
  } else {
    div(class="erp-runtime-empty", "未知报表类型")
  }
}

///|
fn reports_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let share_panel = if model.report_share_dialog {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("生成分享链接"),
        span(class="erp-info-tag", "五类核心报表 · 只读公开快照"),
      ],
      editable_form_field(
        "分享标题",
        model.report_share_title,
        "给收件人看的标题（可空）",
        @html.InputType::Text,
        emit.map(value => InputReportShareTitle(value)),
      ),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "有效期"),
        button(
          class=if model.report_share_days == "1" {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectReportShareDays("1")),
          "1 天",
        ),
        button(
          class=if model.report_share_days == "7" {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectReportShareDays("7")),
          "7 天（默认）",
        ),
        button(
          class=if model.report_share_days == "30" {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectReportShareDays("30")),
          "30 天",
        ),
        button(
          class=if model.report_share_days == "0" {
            "erp-primary-btn"
          } else {
            "erp-secondary-btn"
          },
          on_click=emit(SelectReportShareDays("0")),
          "永久",
        ),
      ],
      div(class="erp-command-bar") <| [
        button(
          class="erp-primary-btn",
          on_click=emit(CreateReportShare),
          "生成链接",
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(CloseReportShare),
          "关闭",
        ),
      ],
      p(class="erp-source-note", model.report_share_note),
      if model.report_share_result_url == "" {
        div(class="erp-source-note", "")
      } else {
        table_panel(
          "分享链接已生成",
          "复制下面的只读路径；过期或撤销后自动失效",
          data_table(["报表", "链接", "token"], [
            [
              model.report_tab,
              model.report_share_result_url,
              model.report_share_result_token,
            ],
          ]),
        )
      },
    ]
  } else {
    div(class="erp-source-note", "")
  }
  let share_list_panel = if model.report_share_list_open {
    let rendered_rows : Array[@html.Html] = []
    for row in model.report_share_rows {
      let status = if row.revoked != "" {
        row.revoked
      } else if row.expired != "" {
        row.expired
      } else {
        "有效"
      }
      rendered_rows.push(
        tr <| [
          td(row.report_label + " · " + row.report_key),
          td(row.title),
          td(row.created_at),
          td(
            if row.never_expires == "永久" {
              "永久"
            } else {
              row.expires_at
            },
          ),
          td(row.access_count),
          td(status),
          td(row.token),
          td(row.source_kind),
          td(
            if row.revoked == "" && row.expired == "" {
              button(
                class="erp-ghost-btn",
                on_click=emit(RevokeReportShare(row.token)),
                "撤销",
              )
            } else {
              span("—")
            },
          ),
        ],
      )
    }
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("我的分享链接"),
        button(
          class="erp-secondary-btn",
          on_click=emit(CloseReportShareList),
          "关闭",
        ),
      ],
      table_panel(
        "分享记录",
        model.report_share_note +
        " · 撤销只写入分享投影，不改报表数据",
        table(class="erp-data-table") <| [
          thead <| [
            table_header([
              "报表", "标题", "创建时间", "到期", "访问数", "状态",
              "token", "来源", "操作",
            ]),
          ],
          tbody <| rendered_rows,
        ],
      ),
      div(class="erp-command-bar") <| [
        button(
          class="erp-secondary-btn",
          on_click=emit(Navigate("/reports")),
          "刷新分享列表",
        ),
      ],
    ]
  } else {
    div(class="erp-source-note", "")
  }
  page_shell(
    "报表中心",
    "ANALYSIS / REPORTS",
    "按主题打开经营、成本、资金、销售与项目报表，统一查看口径和更新时间。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(ToggleReportFavorite),
        if model.report_favorite_keys.contains(model.report_tab) {
          "★ 已收藏"
        } else {
          "☆ 加入常用"
        },
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenReportShare),
        "分享链接",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenReportShareList),
        "我的分享",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExportReportsCsv),
        "导出当前报表 CSV",
      ),
    ],
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
      div(class="erp-tabs") <| [
        button(
          class=if model.report_tab == "cost" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectReportTab("cost")),
          "R1 集团成本汇总 (" +
          model.report_cost_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.report_tab == "contract" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectReportTab("contract")),
          "R2 合同付款台账 (" +
          model.report_contract_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.report_tab == "supplier" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectReportTab("supplier")),
          "R3 供应商分析 (" +
          model.report_supplier_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.report_tab == "approval" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectReportTab("approval")),
          "R4 审批效率 (" +
          model.report_approval_rows.length().to_string() +
          ")",
        ),
        button(
          class=if model.report_tab == "stage" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectReportTab("stage")),
          "R5 项目阶段矩阵 (" +
          model.report_stage_rows.length().to_string() +
          ")",
        ),
      ],
      reports_data_tables(model),
      share_panel,
      share_list_panel,
    ],
  )
}

///|
fn share_view(model : Model, path : String) -> @html.Html {
  let token = if model.share_token == "" {
    share_token_from_path(path)
  } else {
    model.share_token
  }
  div(class="erp-share-page") <| [
    div(class="erp-share-bar") <| [
      div <| [
        span(class="erp-share-brand", "ERP · 分享报表"),
        span(class="erp-share-note", "只读公开快照 · 不需要登录"),
      ],
      span(class="erp-share-token", "链接 " + token),
    ],
    div(class="erp-share-meta") <| [
      h1(
        if model.share_title == "" {
          "分享报表"
        } else {
          model.share_title
        },
      ),
      span(
        class="erp-status-tag is-success",
        if model.share_report_label == "" {
          "加载中"
        } else {
          model.share_report_label
        },
      ),
      span(
        class="erp-share-expiry",
        if model.share_never_expires {
          "永不过期"
        } else if model.share_expires_at == "" {
          "等待元数据"
        } else {
          "到期 " + model.share_expires_at
        },
      ),
    ],
    if model.share_meta_loaded {
      share_data_table(model)
    } else {
      div(class="erp-runtime-empty", model.share_note)
    },
    div(
      class="erp-share-footer",
      "本页面由 ERP 报表分享链接生成 · 数据来自 PostgreSQL 投影读模型 · 仅链接持有者可访问",
    ),
  ]
}

///|
fn report_builder_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let actions : Array[@html.Html] = [
    button(
      class="erp-primary-btn",
      on_click=emit(CreateReportTemplate),
      "＋ 新建报表",
    ),
    button(
      class="erp-secondary-btn",
      on_click=emit(RunReportTemplate),
      "运行本地报表",
    ),
  ]
  if model.report_builder_template_id != "" &&
    model.report_builder_command_state != "pending" {
    actions.push(
      button(
        class="erp-ghost-btn",
        on_click=emit(DeleteReportTemplate),
        "删除本地模板",
      ),
    )
  }
  let meta_rows = if model.report_builder_loaded {
    if model.report_builder_table_rows.length() == 0 {
      [["—", "—", "0", "—", "无元数据"]]
    } else {
      model.report_builder_table_rows
    }
  } else {
    [
      ["项目", "ep_project", "5", "白名单", "设计快照"],
      ["合同", "cb_contract", "10", "白名单", "设计快照"],
      ["付款申请", "cb_htfk_apply", "6", "白名单", "设计快照"],
      ["报销", "vcb_expense", "5", "白名单", "设计快照"],
    ]
  }
  let template_rows = if model.report_builder_loaded {
    if model.report_builder_template_rows.length() == 0 {
      [["—", "—", "0", "0", "—", "—", "无源记录"]]
    } else {
      model.report_builder_template_rows
    }
  } else {
    [
      [
        "项目成本月度变化", "ep_project", "5", "1", "李明金", "今天 08:10",
        "设计快照",
      ],
      [
        "合同付款执行率", "cb_contract", "6", "2", "系统", "昨天 19:42",
        "设计快照",
      ],
      [
        "销售去化漏斗", "sale_revenue", "4", "0", "刘松", "2026-07-11", "设计快照",
      ],
    ]
  }
  page_shell(
    "自定义报表",
    "ANALYSIS / BUILDER",
    "选择数据主题、字段和筛选条件，保存为团队可复用的自定义报表。",
    actions,
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
        "可用数据源",
        if model.report_builder_loaded {
          model.report_builder_note +
          " · 表 " +
          model.report_builder_table_rows.length().to_string()
        } else {
          "字段白名单 · 设计快照"
        },
        data_table(
          ["数据集", "表名", "字段数", "约束", "来源"],
          meta_rows,
        ),
      ),
      section(class="erp-builder-card") <| [
        span(class="erp-page-eyebrow", "LOCAL COMMAND RUNTIME"),
        h2("模板命令与运行预览"),
        p(
          "状态：" +
          model.report_builder_command_state +
          " · " +
          model.report_builder_command_note,
        ),
        if model.report_builder_run_rows.length() == 0 {
          div(
            class="erp-empty-state",
            "尚未运行模板 · 运行只读取已导入合同源信封，不执行原始 SQL",
          )
        } else {
          data_table(
            ["合同号", "合同金额"],
            model.report_builder_run_rows,
          )
        },
      ],
      table_panel(
        "已保存报表",
        if model.report_builder_loaded {
          "源模板 " +
          model.report_builder_template_rows.length().to_string() +
          " · 本地命令/运行已接通（无外部效果） · 空源表 " +
          model.report_builder_missing_table_count
        } else {
          "共 12 个"
        },
        data_table(
          [
            "报表名称", "数据集", "字段数", "过滤数", "创建人", "最近运行",
            "来源",
          ],
          template_rows,
        ),
      ),
    ],
  )
}

///|
fn warning_runtime_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.warnings_loaded {
    if model.warning_rows.length() == 0 {
      rows.push([
        "—", "—", "本次源导出没有可观察预警", "—", "—", "—",
        "imported_or_empty", "imported_or_empty",
      ])
    } else {
      for row in model.warning_rows {
        rows.push([
          row.rule_code,
          row.rule_name,
          row.biz_type,
          row.title,
          row.detail,
          row.severity,
          row.status,
          row.source_kind,
        ])
      }
    }
    data_table(
      [
        "规则", "规则名称", "对象", "标题", "详情", "级别", "状态",
        "来源",
      ],
      rows,
    )
  } else {
    data_table(
      [
        "预警编号", "类型", "项目 / 对象", "预警内容", "触发时间",
        "责任人", "状态", "来源",
      ],
      [
        [
          "WARN-260713-006", "项目延期", "成都和锦里", "2# 楼砌体较计划晚 4 天",
          "今天 09:18", "陈志强", "待处理", "设计快照",
        ],
        [
          "WARN-260712-011", "成本偏差", "成都和锦里", "建安成本超目标 8.4%",
          "昨天 16:42", "李明金", "进行中", "设计快照",
        ],
      ],
    )
  }
}

///|
fn warning_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let open_total = if model.warnings_loaded {
    model.warning_rows.length().to_string()
  } else {
    "23"
  }
  page_shell(
    "异常预警中心",
    "ANALYSIS / WARNINGS",
    "集中处理成本偏差、项目延期、资金缺口、供应商和发票异常。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(ResolveWarning),
        "处理当前告警",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(IgnoreWarning),
        "忽略当前告警",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(PreviewWarningScan),
        "扫描预览（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateWarningTicket),
        "建工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(HandleWarningTicket),
        "开始处理（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CompleteWarningTicket),
        "完成工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ReassignWarningTicket),
        "转派工单（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExtendWarningTicket),
        "延期工单（候选）",
      ),
      button(class="erp-primary-btn", "配置规则"),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.warnings_loaded {
            "PostgreSQL 观察型预警已连接"
          } else {
            "预警设计快照"
          },
        ),
        span(
          " · " +
          model.warning_note +
          " · 规则 " +
          model.warning_rule_count +
          " · 空源表 " +
          model.warning_missing_table_count +
          " · 命令 " +
          model.warning_action_state +
          " · " +
          model.warning_action_note,
        ),
        p(model.warning_ticket_note),
      ]),
      div(class="erp-stat-grid") <| [
        metric(
          "未处理",
          open_total,
          if model.warnings_loaded {
            "源观察行"
          } else {
            "高优先级 6"
          },
          "metric-blue",
        ),
        metric(
          "规则数",
          if model.warnings_loaded {
            model.warning_rule_count
          } else {
            "12"
          },
          "内置规则",
          "metric-blue",
        ),
        metric(
          "持久化",
          if model.warnings_loaded {
            "否"
          } else {
            "—"
          },
          "观察读模型不写入告警",
          "metric-green",
        ),
      ],
      table_panel(
        "预警清单",
        if model.warnings_loaded {
          model.warning_note
        } else {
          "按优先级和更新时间"
        },
        warning_runtime_table(model),
      ),
    ],
  )
}

///|
fn warning_rules_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "告警规则 DSL",
    "ANALYSIS / RULES",
    "用可审计的规则表达式配置阈值、通知对象和自动关闭条件。",
    [
      button(class="erp-primary-btn", "＋ 新建规则"),
      button(
        class="erp-secondary-btn",
        on_click=emit(PreviewWarningCustomRule),
        "预览自定义规则（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateWarningCustomRule),
        "新建自定义规则（候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(DeleteWarningCustomRule),
        "删除本地规则（候选）",
      ),
    ],
    div <| [
      table_panel(
        "规则列表",
        if model.warnings_loaded {
          model.warning_rule_count + " 条源规则 · 自定义规则未导出"
        } else {
          "12 条内置规则 · 4 条自定义规则"
        },
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
        p(model.warning_rule_preview_note),
        p(model.warning_rule_command_note),
        p(
          "when project.cost_variance_ratio > 0.05 then warning('成本偏差', owner=project.cost_owner)",
        ),
      ],
    ],
  )
}

///|
fn cashflow_runtime_table(model : Model) -> @html.Html {
  let rows : Array[Array[String]] = []
  if model.cashflow_loaded {
    for row in model.cashflow_rows {
      rows.push([
        row.ym,
        row.planned,
        row.pending,
        row.confirmed,
        row.expense,
        row.loan,
        row.total_outflow,
        row.cumulative_outflow,
        row.actual_outflow,
        row.actual_cumulative,
      ])
    }
  } else {
    rows.push([
      "W29 · 07/13", "¥1,260 万", "—", "¥1,180 万", "—", "—", "¥1,180 万",
      "¥4,360 万", "¥1,180 万", "¥1,180 万",
    ])
    rows.push([
      "W30 · 07/20", "¥820 万", "—", "¥1,560 万", "—", "—", "¥1,560 万",
      "¥3,620 万", "¥1,560 万", "¥2,740 万",
    ])
  }
  table_panel(
    "滚动现金流",
    if model.cashflow_loaded {
      model.cashflow_note +
      " · 空源表 " +
      model.cashflow_missing_table_count
    } else {
      "设计快照 · 等待 PostgreSQL 源预测"
    },
    data_table(
      [
        "月份", "计划流出", "申请中", "已审核", "报销", "借款", "总流出",
        "累计流出", "实际流出", "实际累计",
      ],
      rows,
    ),
  )
}

///|
fn cashflow_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let planned = if model.cashflow_loaded {
    "¥" + model.cashflow_planned_total
  } else {
    "¥4,280 万"
  }
  let total_outflow = if model.cashflow_loaded {
    "¥" + model.cashflow_total_outflow
  } else {
    "¥9,180 万"
  }
  let inflow = if model.cashflow_inflow_loaded {
    "¥" + model.cashflow_inflow_total
  } else if model.cashflow_loaded {
    "—"
  } else {
    "¥4,900 万"
  }
  let confirmed = if model.cashflow_loaded {
    "¥" + model.cashflow_confirmed_total
  } else {
    "截至今天"
  }
  let minimum_balance = if model.cashflow_loaded { "—" } else { "¥380 万" }
  let minimum_note = if model.cashflow_loaded {
    "期初余额/回款源表未提供"
  } else {
    "8 月 18 日"
  }
  let source_note = if model.cashflow_loaded {
    model.cashflow_note
  } else {
    "现金流预测读模型尚未加载 · 使用设计快照"
  }
  page_shell(
    "现金流预测",
    "FINANCE / CASHFLOW",
    "综合回款、融资和付款计划，预测未来 90 天的每日资金余额和缺口。",
    [
      button(class="erp-secondary-btn", "切换 30 / 90 天"),
      button(class="erp-secondary-btn", "导出预测"),
      button(
        class="erp-secondary-btn",
        on_click=emit(ExplainCashflow),
        "生成缺口解释",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.cashflow_loaded {
            "PostgreSQL 现金流预测已连接"
          } else {
            "现金流预测设计快照"
          },
        ),
        span(
          " · " +
          source_note +
          (if model.cashflow_loaded {
            " · 申请中 " +
            model.cashflow_pending_total +
            " · 报销 " +
            model.cashflow_expense_total +
            " · 借款 " +
            model.cashflow_loan_total
          } else {
            ""
          }) +
          (if model.cashflow_inflow_loaded {
            " · 预计回款 " +
            model.cashflow_inflow_total +
            " · 空源表 " +
            model.cashflow_inflow_missing_table_count
          } else {
            ""
          }),
        ),
      ]),
      div(class="erp-stat-grid") <| [
        metric(
          "计划流出", planned, "付款计划源读模型", "metric-blue",
        ),
        metric(
          "已审核流出", confirmed, "付款申请源读模型", "metric-green",
        ),
        metric(
          "预测总流出", total_outflow, "计划 + 申请 + 借款", "metric-blue",
        ),
        metric(
          "预计回款",
          inflow,
          if model.cashflow_inflow_loaded {
            model.cashflow_inflow_note
          } else {
            "sale_revenue 源读模型"
          },
          "metric-green",
        ),
        metric("最低余额", minimum_balance, minimum_note, "metric-blue"),
      ],
      cashflow_runtime_table(model),
      div(class="erp-runtime-banner", [
        strong("现金流解释候选"),
        span(" · " + model.cashflow_explain_note),
      ]),
      table_panel(
        "解释结果",
        "只读摘要 · 不持久化 prompt",
        data_table(["结果"], [[model.cashflow_explain_text]]),
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
fn editable_form_field(
  label_text : String,
  value : String,
  placeholder : String,
  input_type : @html.InputType,
  on_input : @rabbita.Emit[String],
) -> @html.Html {
  div(class="erp-form-field") <| [
    label(class="erp-field-label", label_text),
    input(input_type~, value~, placeholder~, class="erp-form-input", on_input~),
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
fn project_stage_status_text(status : String) -> String {
  match status {
    "done" => "已完成"
    "in_progress" => "进行中"
    "pending" => "未开始"
    "blocked" => "阻塞"
    _ => status
  }
}

///|
fn project_lifecycle_panel(model : Model) -> @html.Html {
  if model.project_stage_rows.length() == 0 {
    table_panel(
      "生命周期节点",
      "项目生命周期源为空 · 使用设计快照",
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
    )
  } else {
    let rows : Array[Array[String]] = []
    for stage in model.project_stage_rows {
      rows.push([
        stage.stage_order,
        stage.stage_code + " · " + stage.stage_name,
        project_stage_status_text(stage.status),
        stage.progress_pct + "%",
        stage.planned_start + " → " + stage.planned_end,
        stage.actual_start + " → " + stage.actual_end,
        stage.source_kind,
      ])
    }
    table_panel(
      "项目全周期 7 阶段",
      model.project_note + " · 阶段状态与进度为 PostgreSQL 源观察",
      data_table(
        ["序号", "阶段", "状态", "进度", "计划", "实际", "来源"],
        rows,
      ),
    )
  }
}

///|
fn project_kpi_panel(model : Model) -> @html.Html {
  let kpi = model.project_kpi
  if model.project_kpi_loaded {
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "进度",
          kpi.progress_avg + "%",
          "关键节点 " +
          kpi.progress_done +
          "/" +
          kpi.progress_total_nodes +
          " 完成 · 延 " +
          kpi.progress_overdue_nodes,
          "metric-blue",
        ),
        metric(
          "成本",
          kpi.cost_deviation_pct + "%",
          "动态 " + kpi.cost_dynamic + " / 目标 " + kpi.cost_target,
          "metric-green",
        ),
        metric(
          "合同",
          kpi.contract_total,
          kpi.contract_count + " 笔合同",
          "metric-blue",
        ),
        metric(
          "付款",
          kpi.payment_paid_ratio + "%",
          "已付 " +
          kpi.payment_paid_total +
          " / 申请 " +
          kpi.payment_apply_total,
          "metric-blue",
        ),
        metric(
          "资金（本月计划）",
          kpi.cash_this_month_plan,
          "本月计划付款总额",
          "metric-blue",
        ),
        metric(
          "收益（IRR）",
          if kpi.profit_irr.is_empty() {
            "—"
          } else {
            kpi.profit_irr + "%"
          },
          if kpi.profit_net_profit.is_empty() {
            "净利 / NPV 暂无源值"
          } else {
            "净利 " + kpi.profit_net_profit + " · NPV " + kpi.profit_npv
          },
          "metric-green",
        ),
        metric("质量", "—", "质量指标留接入位", "metric-blue"),
        metric(
          "审批效率",
          if kpi.approval_avg_days.is_empty() {
            "—"
          } else {
            kpi.approval_avg_days + " 天"
          },
          model.project_kpi_note,
          "metric-blue",
        ),
      ],
    ]
  } else {
    table_panel(
      "当前阶段 KPI",
      model.project_kpi_note,
      data_table(["指标"], [["等待 PostgreSQL 项目 KPI"]]),
    )
  }
}

///|
fn project_anomaly_panel(model : Model) -> @html.Html {
  if model.project_anomalies_loaded && model.project_anomaly_rows.length() > 0 {
    let rows : Array[Array[String]] = []
    for anomaly in model.project_anomaly_rows {
      rows.push([
        anomaly.severity,
        anomaly.title,
        anomaly.detail,
        anomaly.suggestion,
      ])
    }
    table_panel(
      "AI 风险预警",
      model.project_anomaly_note + " · 规则触发版，provider 未执行",
      data_table(["级别", "标题", "详情", "建议"], rows),
    )
  } else if model.project_anomalies_loaded {
    div(class="erp-runtime-banner", [
      strong("AI 风险预警"),
      span(" · 当前项目无源异常 · " + model.project_anomaly_note),
    ])
  } else {
    div(class="erp-source-note", model.project_anomaly_note)
  }
}

///|
fn project_detail_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let detail = match model.project_detail {
    Some(row) => row
    None =>
      {
        project_id: "proj-0001",
        project_code: "CD-HJL",
        project_name: "成都和锦里",
        bu_name: "成都公司",
        proj_status: "开发建设",
        begin_date: "2024-03-18",
        current_stage: "开发建设",
        task_count: "0",
        source_kind: "snapshot",
        lifecycle_text: "等待 PostgreSQL 项目详情投影",
      }
  }
  page_shell(
    "项目全周期",
    "PROJECT DETAIL",
    detail.project_name +
    " · " +
    detail.project_code +
    " · 记录项目主数据、生命周期、计划、合同、成本与进度。",
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
          span(
            class="erp-status-tag is-success",
            project_stage_status_text(detail.proj_status),
          ),
        ],
        div(class="erp-form-grid") <| [
          form_field("项目编码", detail.project_code, "项目编码"),
          form_field("项目名称", detail.project_name, "项目名称"),
          form_field("项目简称", detail.project_name, "项目简称"),
          form_field("所属公司", detail.bu_name, "所属公司"),
          form_field("开始日期", detail.begin_date, "YYYY-MM-DD"),
          form_field("当前阶段", detail.current_stage, "项目阶段"),
        ],
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "项目概览"),
        button(class="erp-tab", "项目计划"),
        button(class="erp-tab", "合同与成本"),
        button(class="erp-tab", "工程进度"),
      ],
      project_lifecycle_panel(model),
      project_kpi_panel(model),
      project_anomaly_panel(model),
      project_detail_runtime_table(model),
    ],
  )
}

///|
fn contract_milestone_create_panel(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  section(class="erp-detail-card") <| [
    div(class="erp-panel-heading") <| [
      h2("新增付款节点候选"),
      span(
        class="erp-info-tag",
        "节点创建、事件打点和删除均保留 owner/付款边界",
      ),
    ],
    div(class="erp-form-grid") <| [
      editable_form_field(
        "节点名称",
        model.contract_milestone_node_name,
        "例如 主体结构 30%",
        @html.InputType::Text,
        emit.map(value => InputContractMilestoneNodeName(value)),
      ),
      editable_form_field(
        "触发类型",
        model.contract_milestone_trigger_type,
        "time / progress / event",
        @html.InputType::Text,
        emit.map(value => InputContractMilestoneTriggerType(value)),
      ),
      editable_form_field(
        "触发值",
        model.contract_milestone_trigger_value,
        "日期、进度或事件编码",
        @html.InputType::Text,
        emit.map(value => InputContractMilestoneTriggerValue(value)),
      ),
      editable_form_field(
        "计划日期",
        model.contract_milestone_plan_date,
        "YYYY-MM-DD",
        @html.InputType::Text,
        emit.map(value => InputContractMilestonePlanDate(value)),
      ),
      editable_form_field(
        "计划金额",
        model.contract_milestone_plan_amount,
        "例如 1200000",
        @html.InputType::Text,
        emit.map(value => InputContractMilestonePlanAmount(value)),
      ),
      editable_form_field(
        "计划比例",
        model.contract_milestone_plan_pct,
        "例如 30",
        @html.InputType::Text,
        emit.map(value => InputContractMilestonePlanPct(value)),
      ),
      editable_form_field(
        "备注",
        model.contract_milestone_notes,
        "节点说明",
        @html.InputType::Text,
        emit.map(value => InputContractMilestoneNotes(value)),
      ),
    ],
    div(class="erp-command-bar") <| [
      button(
        class="erp-primary-btn",
        on_click=emit(RequestContractMilestoneCreate),
        "提交节点创建候选",
      ),
    ],
    p(class="erp-source-note", model.contract_milestone_command_note),
  ]
}

///|
fn contract_milestone_action_table(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if model.contract_milestones.length() == 0 {
    div(
      class="erp-runtime-empty",
      "当前合同没有可操作的源付款节点",
    )
  } else {
    let rendered : Array[@html.Html] = []
    for row in model.contract_milestones {
      rendered.push(
        tr <| [
          td(row.node_name + " · " + row.milestone_id),
          td(row.trigger_type),
          td(row.plan_amount_display),
          td(row.plan_pct_bps + " bps"),
          td <| [
            button(
              class="erp-ghost-btn",
              on_click=emit(ContractMilestoneTrigger(row.milestone_id)),
              "事件打点候选",
            ),
            button(
              class="erp-ghost-btn",
              on_click=emit(ContractMilestoneDelete(row.milestone_id)),
              "删除候选",
            ),
          ],
        ],
      )
    }
    table_panel(
      "付款节点命令",
      model.contract_milestone_command_note +
      " · imported/command 行均受 owner 门控",
      table(class="erp-data-table") <| [
        thead <| [
          table_header([
            "节点 / ID", "触发", "计划金额", "比例", "操作",
          ]),
        ],
        tbody <| rendered,
      ],
    )
  }
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
      contract_milestone_action_table(emit, model),
      contract_milestone_create_panel(emit, model),
    ],
  )
}

///|
fn expense_state_label(state : String) -> String {
  match state {
    "Draft" => "草稿"
    "Approving" => "审批中"
    "Approved" => "已通过"
    "Rejected" => "已驳回"
    "Voided" => "已作废"
    "" => "—"
    _ => state
  }
}

///|
fn expense_editor_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  detail : Bool,
) -> @html.Html {
  let detail_values = if !detail || !model.expense_detail_loaded {
    [
      "EXP-260712-008", "差旅费", "成都项目现场出差", "8560", "2026-07-12",
      "程玉哲", "成都和锦里", "个人垫付",
    ]
  } else {
    match model.expense_detail {
      Some(row) =>
        [
          if row.expense_code == "" {
            if row.expense_id == "" {
              "—"
            } else {
              row.expense_id
            }
          } else {
            row.expense_code
          },
          "—",
          if row.subject == "" {
            "—"
          } else {
            row.subject
          },
          row.expense_amount,
          if row.apply_date == "" {
            "—"
          } else {
            row.apply_date
          },
          if row.applied_by_name == "" {
            "—"
          } else {
            row.applied_by_name
          },
          if row.apply_dept_name == "" {
            "—"
          } else {
            row.apply_dept_name
          },
          if row.pay_unit == "" {
            "—"
          } else {
            row.pay_unit
          },
        ]
      _ => ["—", "—", "—", "—", "—", "—", "—", "—"]
    }
  }
  let detail_state = if !detail || !model.expense_detail_loaded {
    "审批中"
  } else {
    match model.expense_detail {
      Some(row) => expense_state_label(row.apply_state)
      _ => "无源记录"
    }
  }
  let detail_rows = match model.expense_detail {
    Some(row) => row.details
    _ => []
  }
  let split_rows = match model.expense_detail {
    Some(row) => row.splits
    _ => []
  }
  let detail_source_note = match model.expense_detail {
    Some(row) =>
      model.expense_detail_note +
      " · " +
      row.source_kind +
      " · 付款状态 " +
      expense_state_label(row.pay_state) +
      " · 冲账 " +
      row.offset_amount +
      " · 应付 " +
      row.pay_amount
    _ => model.expense_detail_note
  }
  let title = if detail { "报销详情" } else { "新建报销" }
  let action = if detail { "只读源记录" } else { "提交审批" }
  let actions : Array[@html.Html] = [
    nav_button(emit, "/expenses", "erp-ghost-btn", "‹ 返回列表"),
  ]
  if detail {
    actions.push(button(class="erp-secondary-btn", action))
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
    if model.expense_state == "未创建" || model.expense_state == "草稿" {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(CheckExpenseBudget),
          "预算预检",
        ),
      )
    }
    if model.expense_state == "草稿" {
      actions.push(
        button(
          class="erp-secondary-btn",
          on_click=emit(UpdateExpense),
          "更新草稿",
        ),
      )
      actions.push(
        button(
          class="erp-danger-btn",
          on_click=emit(VoidExpense),
          "作废报销",
        ),
      )
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
          class="erp-danger-btn",
          on_click=emit(VoidExpense),
          "作废报销",
        ),
      )
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
      budget_scope_banner(model),
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("报销信息"),
          if detail {
            span(class="erp-status-tag is-pending", detail_state)
          } else {
            span(class="erp-info-tag", model.expense_state)
          },
          if detail {
            span(class="erp-source-note", detail_source_note)
          } else {
            span(class="erp-source-note", model.expense_note)
          },
        ],
        div(class="erp-form-grid") <| [
          form_field(
            "报销单号",
            if detail {
              detail_values[0]
            } else {
              model.expense_id
            },
            "报销单号",
          ),
          form_field(
            "费用类型",
            if detail {
              detail_values[1]
            } else {
              "差旅费"
            },
            "费用类型",
          ),
          form_field(
            "费用摘要",
            if detail {
              detail_values[2]
            } else {
              "成都项目现场出差"
            },
            "摘要",
          ),
          form_field(
            "费用金额",
            if detail {
              detail_values[3]
            } else {
              "8560"
            },
            "金额(元)",
          ),
          form_field(
            "发生日期",
            if detail {
              detail_values[4]
            } else {
              "2026-07-12"
            },
            "YYYY-MM-DD",
          ),
          form_field(
            "申请人",
            if detail {
              detail_values[5]
            } else {
              "—"
            },
            "申请人",
          ),
          form_field(
            "申请部门",
            if detail {
              detail_values[6]
            } else {
              "—"
            },
            "申请部门",
          ),
          form_field(
            "付款单位",
            if detail {
              detail_values[7]
            } else {
              "个人垫付"
            },
            "付款方式",
          ),
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
      div(class="erp-source-note", model.expense_budget_check_note),
      if detail && model.expense_detail_loaded {
        div <| [
          table_panel(
            "报销明细",
            "PostgreSQL cb_expense_detail · 空表保持可见",
            data_table(
              ["摘要", "金额", "发生日期", "明细编号"],
              if detail_rows.length() == 0 {
                [["—", "—", "—", "源表为空"]]
              } else {
                detail_rows
              },
            ),
          ),
          table_panel(
            "4 维归口分摊",
            "PostgreSQL cb_expense_split · 不在读取路径执行授权",
            data_table(
              [
                "费用使用人", "责任部门", "预算科目", "所属事项",
                "金额",
              ],
              if split_rows.length() == 0 {
                [["—", "—", "—", "—", "源表为空"]]
              } else {
                split_rows
              },
            ),
          ),
        ]
      } else {
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
                "住宿发票-02.pdf", "增值税发票", "¥4,020", "程玉哲",
                "已验真", "预览",
              ],
            ],
          ),
        )
      },
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
    actions.push(
      button(
        class="erp-secondary-btn",
        on_click=emit(SyncLoanWorkflow),
        "检查工作流同步（待授权）",
      ),
    )
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
      div(class="erp-runtime-banner", [
        strong("工作流同步候选"),
        span(" · " + model.loan_workflow_sync_note),
      ]),
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
fn fallback_supplier_detail() -> SupplierDetail {
  {
    provider_guid: "SUP-00018",
    provider_code: "SUP-00018",
    provider_name: "中建三局集团有限公司",
    short_name: "中建三局",
    legal_person: "",
    business_license: "91110000MA00XXXXXX",
    register_capital: "",
    business_scope: "工程施工",
    category_code: "construction",
    category_name: "工程施工",
    eval_result: "合格",
    inspect_state: "正常",
    audit_state: "已审核",
    source: "设计快照",
    contact_person: "周强",
    contact_phone: "138****9001",
    address: "",
    qualifications: "",
    enabled: "true",
    created_by: "",
    created_at: "",
    process_instance_guid: "",
    business_units: [],
    contracts: [
      {
        contract_guid: "CT-SNAPSHOT-001",
        contract_code: "HT-CD-260701",
        contract_name: "成都和锦里总包工程",
        amount: "86200000",
        sign_date: "2026-07-01",
        ht_cf_state: "履行中",
      },
      {
        contract_guid: "CT-SNAPSHOT-002",
        contract_code: "HT-TJ-260501",
        contract_name: "天津海教园一期工程",
        amount: "18600000",
        sign_date: "2026-05-01",
        ht_cf_state: "履行中",
      },
    ],
  }
}

///|
fn supplier_detail_business_unit_summary(
  rows : Array[SupplierDetailBusinessUnitRow],
) -> String {
  let mut summary = ""
  for row in rows {
    if summary != "" {
      summary = summary + "；"
    }
    let label = if row.bu_name == "" { row.bu_code } else { row.bu_name }
    let suffix = if row.bu_guid == "" { "" } else { " (" + row.bu_guid + ")" }
    summary = summary + label + suffix
  }
  if summary == "" {
    "源表未提供"
  } else {
    summary
  }
}

///|
fn supplier_source_eval_label(value : String) -> String {
  match value {
    "已评审" | "reviewed" => "已评审"
    "合格" | "qualified" => "合格"
    "不合格" | "unqualified" => "不合格"
    "战略" | "strategic" => "战略"
    "黑名单" => "黑名单"
    _ => "未定级"
  }
}

///|
fn supplier_risk_rating_label(value : String) -> String {
  match value {
    "A" | "B" | "C" | "D" | "E" => value
    _ => "未定级"
  }
}

///|
fn supplier_detail_contract_table(detail : SupplierDetail) -> @html.Html {
  let rows : Array[Array[String]] = []
  if detail.contracts.length() == 0 {
    rows.push([
      "—", "本次 ERP 源详情没有关联合同", "—", "—", "—", "—",
    ])
  } else {
    for row in detail.contracts {
      let date_suffix = if row.sign_date == "" {
        ""
      } else {
        " · " + row.sign_date
      }
      let contract_state = if row.ht_cf_state == "" {
        "—"
      } else {
        row.ht_cf_state
      }
      rows.push([
        row.contract_code + " · " + row.contract_guid,
        row.contract_name,
        row.amount + date_suffix,
        "—",
        supplier_source_eval_label(detail.eval_result),
        contract_state,
      ])
    }
  }
  data_table(
    [
      "合同编号", "合同名称", "合同金额", "已付款", "最近评价",
      "履约状态",
    ],
    rows,
  )
}

///|
fn supplier_detail_risk_table(model : Model) -> @html.Html {
  data_table(
    ["评级", "评分", "风险标签", "关联合同", "逾期节点"],
    [
      [
        supplier_risk_rating_label(model.supplier_detail_risk_rating),
        model.supplier_detail_risk_score,
        model.supplier_detail_risk_tags,
        model.supplier_detail_risk_contract_count,
        model.supplier_detail_risk_overdue_count,
      ],
    ],
  )
}

///|
fn provider_detail_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let detail = match model.supplier_detail {
    Some(value) => value
    None => fallback_supplier_detail()
  }
  let source_note = if model.supplier_detail_loaded {
    model.supplier_detail_note
  } else {
    "设计快照 · " + model.supplier_detail_note
  }
  let status = if detail.enabled == "true" || detail.enabled == "1" {
    "正常"
  } else {
    "暂停"
  }
  page_shell(
    "供应商详情",
    "SRM / PROVIDER DETAIL",
    detail.provider_code +
    " / " +
    detail.provider_guid +
    " · " +
    detail.provider_name +
    (if detail.short_name == "" {
      ""
    } else {
      "（" + detail.short_name + "）"
    }) +
    " · " +
    (if detail.category_name == "" {
      detail.category_code
    } else {
      detail.category_name
    }),
    [
      detail_toolbar(emit, "/srm/providers", "保存供应商"),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestSupplierCheckSign),
        "检查签约边界（待采购负责人）",
      ),
    ],
    div <| [
      div(class="erp-runtime-banner", [
        strong(
          if model.supplier_detail_loaded {
            "PostgreSQL 供应商源详情已连接"
          } else {
            "供应商详情设计快照"
          },
        ),
        span(" · " + source_note),
      ]),
      div(class="erp-runtime-banner", [
        strong("供应商签约校验"),
        span(" · " + model.supplier_check_sign_note),
        span(" · 不签署合同、不调用 provider、不改变采购授权"),
      ]),
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("供应商基本信息"),
          span(class="erp-status-tag is-success", status),
        ],
        div(class="erp-form-grid") <| [
          form_field("供应商编码", detail.provider_code, "供应商编码"),
          form_field("供应商名称", detail.provider_name, "供应商名称"),
          form_field(
            "类别",
            if detail.category_name == "" {
              detail.category_code
            } else {
              detail.category_name
            },
            "供应商类别",
          ),
          form_field(
            "统一社会信用代码",
            detail.business_license,
            "统一社会信用代码",
          ),
          form_field("联系人", detail.contact_person, "联系人"),
          form_field("联系电话", detail.contact_phone, "联系电话"),
          form_field("法人代表", detail.legal_person, "法人代表"),
          form_field("注册资本", detail.register_capital, "注册资本"),
          form_field(
            "服务组织",
            supplier_detail_business_unit_summary(detail.business_units),
            "关联组织",
          ),
          form_field("服务范围", detail.business_scope, "服务范围"),
          form_field(
            "资格评价",
            supplier_source_eval_label(detail.eval_result),
            "资格评价",
          ),
          form_field("考察状态", detail.inspect_state, "考察状态"),
          form_field("审核状态", detail.audit_state, "审核状态"),
          form_field("来源", detail.source, "来源"),
          form_field("地址", detail.address, "地址"),
          form_field("资质", detail.qualifications, "资质"),
          form_field("创建人", detail.created_by, "创建人"),
          form_field("创建时间", detail.created_at, "创建时间"),
          form_field(
            "流程实例",
            detail.process_instance_guid,
            "流程实例",
          ),
        ],
      ],
      table_panel(
        "风险评级",
        (if model.supplier_detail_risk_loaded {
          model.supplier_detail_risk_note
        } else {
          "设计快照 · " + model.supplier_detail_risk_note
        }) +
        " · 风险计算仅读取 ERP 源合同与里程碑，不生成授权状态",
        supplier_detail_risk_table(model),
      ),
      table_panel(
        "合作与评价",
        source_note +
        " · 合同关联 " +
        detail.contracts.length().to_string() +
        " 笔",
        supplier_detail_contract_table(detail),
      ),
    ],
  )
}

///|
fn sales_revenue_status_label(status : String) -> String {
  match status {
    "expected" => "预计"
    "received" => "已回款"
    "overdue" => "逾期"
    "pending" => "待确认"
    _ => status
  }
}

///|
fn sales_revenue_form_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.sales_revenue_form_open {
    @html.nothing
  } else {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2(
          if model.sales_revenue_editing_id.is_empty() {
            "新增回款"
          } else {
            "编辑回款"
          },
        ),
        span(class="erp-source-note", model.sales_revenue_command_note),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "项目 GUID",
          model.sales_revenue_form_project,
          "项目 GUID",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("project", value)),
        ),
        editable_form_field(
          "客户名",
          model.sales_revenue_form_customer,
          "客户或房号",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("customer", value)),
        ),
        editable_form_field(
          "金额(元)",
          model.sales_revenue_form_amount,
          "正数",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("amount", value)),
        ),
        editable_form_field(
          "到账日期",
          model.sales_revenue_form_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("date", value)),
        ),
        editable_form_field(
          "状态",
          model.sales_revenue_form_status,
          "expected / received",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("status", value)),
        ),
        editable_form_field(
          "付款类型",
          model.sales_revenue_form_payment_type,
          "首付 / 按揭 / 全款",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("payment_type", value)),
        ),
        editable_form_field(
          "销售合同号",
          model.sales_revenue_form_contract_no,
          "可选",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("contract_no", value)),
        ),
        editable_form_field(
          "备注",
          model.sales_revenue_form_remark,
          "收款说明",
          @html.InputType::Text,
          emit.map(value => InputSalesRevenueField("remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseSalesRevenueForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(SubmitSalesRevenueForm),
          "保存",
        ),
      ],
    ]
  }
}

///|
fn sales_revenue_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for row in model.sales_revenue_rows {
    if !model.sales_revenue_filter_status.is_empty() &&
      row.status != model.sales_revenue_filter_status {
      continue
    }
    if !model.sales_revenue_keyword.trim().is_empty() &&
      !(row.customer_name
      .to_lower()
      .contains(model.sales_revenue_keyword.to_lower()) ||
      row.revenue_code
      .to_lower()
      .contains(model.sales_revenue_keyword.to_lower()) ||
      row.contract_no
      .to_lower()
      .contains(model.sales_revenue_keyword.to_lower())) {
      continue
    }
    let actions : Array[@html.Html] = if row.source_kind == "command" {
      let command_buttons : Array[@html.Html] = [
        button(
          class="erp-link-btn",
          on_click=emit(OpenSalesRevenueEdit(row.revenue_guid)),
          "编辑",
        ),
      ]
      if row.status != "received" {
        command_buttons.push(
          button(
            class="erp-link-btn is-success",
            on_click=emit(ConfirmSalesRevenue),
            "确认到账",
          ),
        )
      }
      command_buttons.push(
        button(
          class="erp-link-btn is-warning",
          on_click=emit(DeleteSalesRevenue),
          "撤回",
        ),
      )
      command_buttons
    } else {
      [span(class="erp-source-note", "源行只读")]
    }
    rows.push(
      tr <| [
        td(row.revenue_code),
        td(row.customer_name),
        td(row.amount),
        td(row.receive_date),
        td(sales_revenue_status_label(row.status) + " · " + row.source_kind),
        td(row.payment_type),
        td(row.contract_no),
        td("R6"),
        td <| actions,
      ],
    )
  }
  if rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("—"),
        td("—"),
        td("暂无回款源记录"),
        td("—"),
        td("—"),
        td("R6"),
        td("—"),
      ],
    )
  }
  table_panel(
    "回款登记",
    model.sales_note +
    " · " +
    model.sales_revenue_rows.length().to_string() +
    " 条 · 导入回款保持只读",
    table(class="erp-data-table") <| [
      thead <| [
        table_header([
          "回款编号", "客户", "金额", "到账日期", "状态", "付款类型",
          "销售合同号", "R 编码", "操作",
        ]),
      ],
      tbody <| rows,
    ],
  )
}

///|
fn sales_refund_form_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if !model.sales_refund_form_open {
    @html.nothing
  } else {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("退房申请"),
        span(class="erp-source-note", model.sales_refund_command_note),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "销售合同号",
          model.sales_refund_form_contract,
          "必填",
          @html.InputType::Text,
          emit.map(value => InputSalesRefundField("contract", value)),
        ),
        editable_form_field(
          "客户 GUID",
          model.sales_refund_form_customer,
          "可选",
          @html.InputType::Text,
          emit.map(value => InputSalesRefundField("customer", value)),
        ),
        editable_form_field(
          "退房原因",
          model.sales_refund_form_reason,
          "必填",
          @html.InputType::Text,
          emit.map(value => InputSalesRefundField("reason", value)),
        ),
        editable_form_field(
          "退款金额",
          model.sales_refund_form_amount,
          "元",
          @html.InputType::Text,
          emit.map(value => InputSalesRefundField("amount", value)),
        ),
        editable_form_field(
          "退款日期",
          model.sales_refund_form_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputSalesRefundField("date", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseSalesRefundForm),
          "取消",
        ),
        button(
          class="erp-danger-btn",
          on_click=emit(SubmitSalesRefundForm),
          "提交退房",
        ),
      ],
    ]
  }
}

///|
fn sales_revenues_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "销售回款 (R6)",
    "SALES / REVENUES",
    "登记销售回款、到账日期、付款类型与销售合同号，保持回款与应收台帐可追溯。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(CreateSalesRevenue),
        "＋ 登记本地回款",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ConfirmSalesRevenue),
        "确认到账",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateSalesRefund),
        "＋ 新建退款",
      ),
      button(
        class="erp-danger-btn",
        on_click=emit(ApproveSalesRefund),
        "记录退款审批",
      ),
    ],
    div <| [
      sales_runtime_banner(model, "revenues"),
      sales_refund_form_view(emit, model),
      div(class="erp-inline-actions") <| [
        button(
          class="erp-secondary-btn",
          on_click=emit(UpdateSalesRevenue),
          "更新本地回款",
        ),
        button(
          class="erp-danger-btn",
          on_click=emit(DeleteSalesRevenue),
          "撤回本地回款",
        ),
      ],
      table_panel(
        "本地回款命令",
        "REV-RABBITA-LOCAL · 状态 " + model.sales_revenue_state,
        data_table(["命令", "状态", "边界"], [
          [
            "创建 / 更新 / 确认 / 撤回",
            model.sales_revenue_state,
            model.sales_revenue_command_note,
          ],
        ]),
      ),
      table_panel(
        "本地退款命令",
        "RF-RABBITA-LOCAL · 状态 " + model.sales_refund_state,
        data_table(["命令", "状态", "边界"], [
          [
            "创建 / 审批",
            model.sales_refund_state,
            model.sales_refund_command_note,
          ],
        ]),
      ),
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目筛选:"),
        if model.project_rows.length() == 0 {
          span(
            class="erp-info-tag",
            if model.sales_revenue_project_id.is_empty() {
              "全部项目"
            } else {
              model.sales_revenue_project_id
            },
          )
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.sales_revenue_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectSalesRevenueProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "状态筛选:"),
        button(
          class=if model.sales_revenue_filter_status.is_empty() {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesRevenueStatus("")),
          "全部",
        ),
        button(
          class=if model.sales_revenue_filter_status == "expected" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesRevenueStatus("expected")),
          "预计",
        ),
        button(
          class=if model.sales_revenue_filter_status == "received" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesRevenueStatus("received")),
          "已回款",
        ),
        button(
          class=if model.sales_revenue_filter_status == "pending" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectSalesRevenueStatus("pending")),
          "待确认",
        ),
      ],
      div(class="erp-inline-actions") <| [
        input(
          input_type=@html.InputType::Text,
          value=model.sales_revenue_keyword,
          placeholder="客户 / 回款编号 / 合同号",
          class="erp-form-input",
          on_input=emit.map(value => InputSalesRevenueKeyword(value)),
        ),
        button(
          class="erp-secondary-btn",
          on_click=emit(QuerySalesRevenue),
          "查询",
        ),
      ],
      sales_revenue_form_view(emit, model),
      div(class="erp-stat-grid") <| [
        metric("本月到账", "¥6,820 万", "126 笔", "metric-blue"),
        metric(
          "年度累计", "¥4.28 亿", "完成年度目标 68%", "metric-green",
        ),
        metric("待确认", "12", "金额 ¥380 万", "metric-blue"),
      ],
      sales_revenue_table(emit, model),
    ],
  )
}

///|
fn marketing_form_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.marketing_form_open == "campaign" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新建营销活动"),
        span(
          class="erp-source-note",
          "预算按万元输入 · 提交后写入本地命令投影",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "活动名称",
          model.marketing_campaign_name,
          "例：金秋盛典",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_name", value)),
        ),
        editable_form_field(
          "活动类型",
          model.marketing_campaign_type,
          "推广活动",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_type", value)),
        ),
        editable_form_field(
          "预算（万）",
          model.marketing_campaign_budget,
          "50",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_budget", value)),
        ),
        editable_form_field(
          "开始日",
          model.marketing_campaign_start,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_start", value)),
        ),
        editable_form_field(
          "结束日",
          model.marketing_campaign_end,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_end", value)),
        ),
        editable_form_field(
          "目标",
          model.marketing_campaign_goal,
          "到访/线索目标",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_goal", value)),
        ),
        editable_form_field(
          "备注",
          model.marketing_campaign_remark,
          "备注",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("campaign_remark", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseMarketingForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateMarketingCampaign),
          "提交活动",
        ),
      ],
    ]
  } else if model.marketing_form_open == "placement" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增投放"),
        span(
          class="erp-source-note",
          "金额按万元输入 · channelGuid 可留空并手填渠道",
        ),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "活动 GUID",
          model.marketing_placement_campaign,
          "CAMP-…",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_campaign", value)),
        ),
        editable_form_field(
          "渠道 GUID",
          model.marketing_placement_channel,
          "CH-…",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_channel", value)),
        ),
        editable_form_field(
          "渠道名称",
          model.marketing_placement_channel_name,
          "抖音/SEM",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_channel_name", value)),
        ),
        editable_form_field(
          "金额（万）",
          model.marketing_placement_amount,
          "10",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_amount", value)),
        ),
        editable_form_field(
          "投放日",
          model.marketing_placement_date,
          "YYYY-MM-DD",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_date", value)),
        ),
        editable_form_field(
          "时长（天）",
          model.marketing_placement_duration,
          "30",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("placement_duration", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseMarketingForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateMarketingPlacement),
          "提交投放",
        ),
      ],
    ]
  } else if model.marketing_form_open == "channel" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增渠道"),
        span(class="erp-source-note", "渠道记录写入本地命令投影"),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "渠道名",
          model.marketing_channel_name,
          "抖音 / 新浪",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("channel_name", value)),
        ),
        editable_form_field(
          "类型",
          model.marketing_channel_type,
          "线上",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("channel_type", value)),
        ),
        editable_form_field(
          "联系人",
          model.marketing_channel_contact,
          "联系人",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("channel_contact", value)),
        ),
        editable_form_field(
          "电话",
          model.marketing_channel_phone,
          "联系电话",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("channel_phone", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseMarketingForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateMarketingChannel),
          "提交渠道",
        ),
      ],
    ]
  } else if model.marketing_form_open == "material" {
    section(class="erp-detail-card") <| [
      div(class="erp-panel-heading") <| [
        h2("新增物料"),
        span(class="erp-source-note", "物料成本保持本地命令边界"),
      ],
      div(class="erp-form-grid") <| [
        editable_form_field(
          "物料名",
          model.marketing_material_name,
          "楼书 / 礼品袋",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("material_name", value)),
        ),
        editable_form_field(
          "类型",
          model.marketing_material_type,
          "现场包装",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("material_type", value)),
        ),
        editable_form_field(
          "单价（元）",
          model.marketing_material_unit_cost,
          "100",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("material_unit_cost", value)),
        ),
        editable_form_field(
          "数量",
          model.marketing_material_quantity,
          "1",
          @html.InputType::Text,
          emit.map(value => InputMarketingField("material_quantity", value)),
        ),
      ],
      div(class="erp-inline-actions") <| [
        button(
          class="erp-ghost-btn",
          on_click=emit(CloseMarketingForm),
          "取消",
        ),
        button(
          class="erp-primary-btn",
          on_click=emit(CreateMarketingMaterial),
          "提交物料",
        ),
      ],
    ]
  } else {
    @html.nothing
  }
}

///|
fn marketing_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let campaign_rows = if model.marketing_loaded {
    if model.marketing_campaign_rows.length() == 0 {
      [
        [
          "—", "—", "—", "0", "0", "—", "无源记录", "—", "", "imported",
        ],
      ]
    } else {
      model.marketing_campaign_rows
    }
  } else {
    [
      [
        "CAM-260701", "成都和锦里开盘推广", "开盘活动", "¥1,800,000",
        "¥680,000", "2026-07-01 ~ 08-20", "运行中", "04-03", "", "imported",
      ],
      [
        "CAM-260615", "南山居线上投放", "线上获客", "¥960,000", "¥812,000",
        "2026-06-15 ~ 07-31", "运行中", "04-03", "", "imported",
      ],
      [
        "CAM-260501", "沈阳和山苑暖场", "客户活动", "¥420,000", "¥420,000",
        "2026-05-01 ~ 06-30", "已结束", "04-03", "", "imported",
      ],
    ]
  }
  let placement_rows = if model.marketing_loaded {
    if model.marketing_placement_rows.length() == 0 {
      [["—", "—", "—", "0", "—", "0", "无源记录"]]
    } else {
      model.marketing_placement_rows
    }
  } else {
    [
      [
        "PLC-260712-008", "成都和锦里开盘推广", "抖音", "¥180,000", "2026-07-12",
        "286,000", "420",
      ],
      [
        "PLC-260708-004", "南山居线上投放", "SEM", "¥96,000", "2026-07-11",
        "112,000", "186",
      ],
      [
        "PLC-260701-012", "成都和锦里开盘推广", "渠道分销", "¥240,000",
        "—", "98", "—",
      ],
    ]
  }
  let channel_rows = if model.marketing_channel_rows.length() == 0 {
    [["—", "—", "—", "0", "0", "无源记录"]]
  } else {
    model.marketing_channel_rows
  }
  let material_rows = if model.marketing_material_rows.length() == 0 {
    [["—", "—", "—", "0", "0", "0", "—", "无源记录"]]
  } else {
    model.marketing_material_rows
  }
  let campaign_table_rows : Array[@html.Html] = []
  for row in campaign_rows {
    let action = if row.length() > 9 && row[8] != "" && row[9] == "command" {
      button(
        class="erp-link-btn is-warning",
        on_click=emit(DeleteMarketingCampaign(row[8])),
        "删除",
      )
    } else {
      span(class="erp-source-note", "源行只读")
    }
    campaign_table_rows.push(
      tr <| [
        td(row[0]),
        td(row[1]),
        td(row[2]),
        td(row[3]),
        td(row[4]),
        td(row[5]),
        td(row[6]),
        td(row[7]),
        td(if row.length() > 9 { row[9] } else { "imported" }),
        td(action),
      ],
    )
  }
  let campaign_count = if model.marketing_loaded {
    model.marketing_campaign_count
  } else {
    "18"
  }
  let budget_total = if model.marketing_loaded {
    marketing_sum(model.marketing_campaign_rows, 3)
  } else {
    "—"
  }
  let actual_total = if model.marketing_loaded {
    marketing_sum(model.marketing_campaign_rows, 4)
  } else {
    "—"
  }
  let placement_total = if model.marketing_loaded {
    marketing_sum(model.marketing_placement_rows, 3)
  } else {
    "—"
  }
  let lead_count = if model.marketing_loaded {
    marketing_sum(model.marketing_placement_rows, 6)
  } else {
    "3,842"
  }
  page_shell(
    "营销管理",
    "SALES / MARKETING",
    "管理营销活动、投放记录、渠道与营销物料，预算和实际花费挂接 CBS。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(OpenMarketingForm("campaign")),
        "＋ 新建营销活动",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenMarketingForm("placement")),
        "＋ 新增投放",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenMarketingForm("channel")),
        "＋ 新增渠道",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(OpenMarketingForm("material")),
        "＋ 新增物料",
      ),
    ],
    div <| [
      div(class="erp-command-bar") <| [
        span(class="erp-source-note", "项目:"),
        if model.project_rows.length() == 0 {
          span(class="erp-info-tag", model.marketing_project_id)
        } else {
          @html.fragment(
            model.project_rows.map(row => {
              button(
                class=if row.project_id == model.marketing_project_id {
                  "erp-tab is-active"
                } else {
                  "erp-tab"
                },
                on_click=emit(SelectMarketingProject(row.project_id)),
                row.project_name,
              )
            }),
          )
        },
      ],
      marketing_form_view(emit, model),
      div(class="erp-stat-grid") <| [
        metric(
          "营销活动数",
          campaign_count,
          if model.marketing_loaded {
            "源表导入记录"
          } else {
            "运行中 6 个"
          },
          "metric-blue",
        ),
        metric(
          "活动总预算",
          "¥" + budget_total,
          "源表预算合计（元）",
          "metric-green",
        ),
        metric(
          "活动已花",
          "¥" + actual_total,
          "源表已花合计（元）",
          "metric-orange",
        ),
        metric(
          "投放总额",
          "¥" + placement_total,
          "源表投放合计（元）",
          "metric-purple",
        ),
        metric(
          "有效线索",
          lead_count,
          if model.marketing_loaded {
            "源表未提供归因"
          } else {
            "转化率 12.6%"
          },
          "metric-green",
        ),
      ],
      div(class="erp-tabs") <| [
        button(
          class=if model.marketing_tab == "campaigns" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectMarketingTab("campaigns")),
          "营销活动",
        ),
        button(
          class=if model.marketing_tab == "placements" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectMarketingTab("placements")),
          "投放记录",
        ),
        button(
          class=if model.marketing_tab == "channels" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectMarketingTab("channels")),
          "营销渠道",
        ),
        button(
          class=if model.marketing_tab == "materials" {
            "erp-tab is-active"
          } else {
            "erp-tab"
          },
          on_click=emit(SelectMarketingTab("materials")),
          "营销物料",
        ),
      ],
      if model.marketing_tab == "campaigns" {
        table_panel(
          "营销活动",
          if model.marketing_loaded {
            model.marketing_note
          } else {
            "v3.8 · R19 营销费用 · " + model.marketing_note
          },
          table(class="erp-data-table") <| [
            thead <| [
              table_header([
                "编号", "活动名称", "类型", "预算(元)", "已花(元)",
                "周期", "状态", "挂 CBS", "来源", "操作",
              ]),
            ],
            tbody <| campaign_table_rows,
          ],
        )
      } else if model.marketing_tab == "placements" {
        table_panel(
          "投放记录",
          "渠道效果和实际花费 · " +
          model.marketing_placement_count +
          " 条",
          data_table(
            [
              "编号", "所属活动", "投放渠道", "金额(元)", "投放日",
              "曝光", "线索",
            ],
            placement_rows,
          ),
        )
      } else if model.marketing_tab == "channels" {
        table_panel(
          "营销渠道",
          "源表渠道与投放次数 · " +
          model.marketing_channel_count +
          " 条 · 空源表 " +
          model.marketing_missing_table_count,
          data_table(
            [
              "编号", "渠道名称", "类型", "投放金额", "投放次数",
              "状态",
            ],
            channel_rows,
          ),
        )
      } else {
        table_panel(
          "营销物料",
          "源表物料与成本 · " + model.marketing_material_count + " 条",
          data_table(
            [
              "编号", "物料名称", "类型", "单价", "数量", "总成本",
              "使用周期", "状态",
            ],
            material_rows,
          ),
        )
      },
    ],
  )
}

///|
fn inbox_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows = if model.inbox_loaded {
    if model.inbox_rows.length() == 0 {
      [["—", "—", "—", "—", "—", "无源记录", "—"]]
    } else {
      model.inbox_rows
    }
  } else {
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
    ]
  }
  let unread = if model.inbox_loaded { model.inbox_unread } else { "8" }
  let total = if model.inbox_loaded { model.inbox_total } else { "26" }
  let business = if model.inbox_loaded { model.inbox_total } else { "18" }
  page_shell(
    "站内信",
    "SYSTEM / INBOX",
    "统一接收审批、预警、系统和业务通知，保留已读状态与业务关联。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(MarkInboxReadAll),
        "全部标记已读（待授权）",
      ),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "未读消息",
          unread,
          if model.inbox_loaded {
            "源表未读计数"
          } else {
            "高优先级 2"
          },
          "metric-blue",
        ),
        metric(
          "本周新增",
          total,
          if model.inbox_loaded {
            "消息源总数"
          } else {
            "较上周 +4"
          },
          "metric-blue",
        ),
        metric(
          "业务通知",
          business,
          if model.inbox_loaded {
            "源表未提供分类统计"
          } else {
            "审批 / 预警"
          },
          "metric-green",
        ),
      ],
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "未读 (" + unread + ")"),
        button(class="erp-tab", "全部消息"),
        button(class="erp-tab", "审批通知"),
        button(class="erp-tab", "系统通知"),
      ],
      table_panel(
        "消息列表",
        if model.inbox_loaded {
          model.inbox_note + " · 空源表 " + model.inbox_missing_table_count
        } else {
          "按时间倒序"
        },
        data_table(
          ["", "标题", "内容", "业务", "时间", "状态", "操作"],
          rows,
        ),
      ),
    ],
  )
}

///|
fn attachment_biz_label(biz_type : String) -> String {
  match biz_type {
    "expense" => "报销"
    "contract" => "合同"
    "htfk_apply" => "付款申请"
    "loan" => "借款"
    "project" => "项目"
    "srm_provider" => "供应商"
    "wf_instance" => "BPM"
    "other" => "其它"
    _ => if biz_type.is_empty() { "未分类" } else { biz_type }
  }
}

///|
fn attachment_filtered_rows(model : Model) -> Array[AttachmentRow] {
  let result : Array[AttachmentRow] = []
  for row in model.attachment_rows {
    let biz_ok = model.attachment_biz_type.is_empty() ||
      row.biz_type == model.attachment_biz_type
    let keyword_ok = model.attachment_keyword.is_empty() ||
      row.file_name.contains(model.attachment_keyword)
    let ai_ok = model.attachment_ai_status.is_empty() ||
      row.ai_status == model.attachment_ai_status
    if biz_ok && keyword_ok && ai_ok {
      result.push(row)
    }
  }
  result
}

///|
fn attachment_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for row in attachment_filtered_rows(model) {
    rows.push(
      tr <| [
        td <| [
          strong(row.file_name),
          span(class="erp-source-note", row.att_guid),
        ],
        td(attachment_biz_label(row.biz_type) + " · " + row.biz_guid),
        td(row.file_size),
        td(row.mime_type),
        td(row.uploaded_by_name),
        td(row.uploaded_at),
        td(class="erp-status-tag", row.ai_status),
        td(row.source_kind + " · " + row.download_available),
        td <| [
          button(
            class="erp-link-btn",
            on_click=emit(AttachmentAction(row.att_guid, "download")),
            "下载",
          ),
          button(
            class="erp-link-btn",
            on_click=emit(AttachmentAction(row.att_guid, "reextract")),
            "重跑 AI",
          ),
          button(
            class="erp-link-btn is-warning",
            on_click=emit(AttachmentAction(row.att_guid, "delete")),
            "删除",
          ),
        ],
      ],
    )
  }
  if rows.length() == 0 {
    rows.push(
      tr <| [
        td("—"),
        td("—"),
        td("0"),
        td("—"),
        td("—"),
        td("—"),
        td("无匹配记录"),
        td("—"),
        td("—"),
      ],
    )
  }
  table(class="erp-data-table") <| [
    thead <| [
      table_header([
        "文件名", "业务", "大小", "类型", "上传人", "上传时间", "AI",
        "来源/下载", "操作",
      ]),
    ],
    tbody <| rows,
  ]
}

///|
fn attachments_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let total = if model.attachments_loaded {
    model.attachment_total
  } else {
    "2,846"
  }
  let pending = if model.attachments_loaded {
    model.attachment_pending
  } else {
    "14"
  }
  let linked = if model.attachments_loaded { "—" } else { "98.4%" }
  page_shell(
    "附件中心",
    "SYSTEM / ATTACHMENTS",
    "搜索合同、发票、报销和项目证据，查看 AI 识别状态与业务关联。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(RequestAttachmentUpload),
        "＋ 上传附件",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestAttachmentReextract),
        "检查 OCR 重提取",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestAttachmentDownload),
        "检查附件下载",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestAttachmentDelete),
        "检查附件删除",
      ),
    ],
    div <| [
      div(class="erp-stat-grid") <| [
        metric("附件总数", total, "源表元数据", "metric-blue"),
        metric("待 OCR", pending, "AI 状态 pending", "metric-blue"),
        metric(
          "已关联",
          linked,
          if model.attachments_loaded {
            "二进制文件未迁移"
          } else {
            "来源可追溯"
          },
          "metric-green",
        ),
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("附件搜索 / 批量上传"),
          span(
            class="erp-info-tag",
            "≤10 MB · 上传执行仍需对象存储授权",
          ),
        ],
        div(class="erp-form-grid") <| [
          editable_form_field(
            "业务类型",
            model.attachment_biz_type,
            "expense / contract / project",
            @html.InputType::Text,
            emit.map(value => InputAttachmentBizType(value)),
          ),
          editable_form_field(
            "AI 状态",
            model.attachment_ai_status,
            "pending / processed / failed",
            @html.InputType::Text,
            emit.map(value => InputAttachmentAiStatus(value)),
          ),
          editable_form_field(
            "文件名关键词",
            model.attachment_keyword,
            "按文件名搜索",
            @html.InputType::Text,
            emit.map(value => InputAttachmentKeyword(value)),
          ),
        ],
        div(class="erp-command-bar") <| [
          label(class="erp-import-file-picker") <| [
            input(
              input_type=@html.InputType::File,
              accept="image/*,.pdf,.xlsx,.xls,.doc,.docx",
              class="erp-import-file-input",
              on_change=emit.map(value => AttachmentFileSelected(value)),
            ),
            span(
              if model.attachment_file_name.is_empty() {
                "选择上传文件"
              } else {
                model.attachment_file_name
              },
            ),
          ],
          button(
            class="erp-secondary-btn",
            on_click=emit(SearchAttachments),
            "搜索",
          ),
          button(
            class="erp-primary-btn",
            on_click=emit(RequestAttachmentUpload),
            "上传并检查边界",
          ),
        ],
        p(class="erp-source-note", model.attachment_note),
      ],
      table_panel(
        "附件搜索结果",
        if model.attachments_loaded {
          model.attachment_note + " · 字节数 " + model.attachment_bytes
        } else {
          "最近上传 · " + model.attachment_note
        },
        attachment_table(emit, model),
      ),
      div(class="erp-runtime-banner", [
        strong("当前附件"),
        span(" · " + model.attachment_action_guid),
        span(" · " + model.attachment_action_note),
      ]),
      div(class="erp-runtime-banner", [
        strong("下载边界"),
        span(" · " + model.attachment_download_note),
        span(" · binary/object storage 未迁移"),
      ]),
      div(class="erp-runtime-banner", [
        strong("删除边界"),
        span(" · " + model.attachment_delete_note),
        span(" · 对象存储与负责人确认保持关闭"),
      ]),
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
fn health_inventory_panel(model : Model) -> @html.Html {
  if model.health_inventory_loaded {
    let snapshot_id = if model.health_inventory_snapshot_id == "" {
      "—"
    } else {
      model.health_inventory_snapshot_id
    }
    table_panel(
      "迁移源范围",
      model.health_inventory_note + " · " + model.health_inventory_export_state,
      data_table(["范围", "数量", "状态", "来源"], [
        [
          "ERP schema tables",
          model.health_inventory_schema_count,
          "权威 schema",
          "erp_new initializer",
        ],
        [
          "Rehearsal snapshot tables",
          model.health_inventory_snapshot_count,
          "已导入 envelope",
          snapshot_id,
        ],
        [
          "Schema-only tables",
          model.health_inventory_schema_only_count,
          "缺少源 payload · 保持 gated",
          model.health_inventory_export_state,
        ],
      ]),
    )
  } else {
    table_panel(
      "迁移源范围",
      model.health_inventory_note,
      data_table(["范围", "数量", "状态", "来源"], [
        ["—", "—", "等待源清单", "只读"],
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
      health_inventory_panel(model),
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
fn rbac_role_table(model : Model) -> @html.Html {
  if model.rbac_roles_loaded {
    let rows = if model.rbac_role_rows.length() == 0 {
      [["—", "源表无记录", "NO_SOURCE_ROWS", "—", "0", "0", "只读"]]
    } else {
      model.rbac_role_rows
    }
    table_panel(
      "角色管理",
      model.rbac_roles_note,
      data_table(
        [
          "编码", "名称", "描述", "数据范围", "权限数", "用户数",
          "状态",
        ],
        rows,
      ),
    )
  } else {
    table_panel(
      "角色管理",
      "角色源读模型尚未加载 · 设计快照不用于授权",
      data_table(
        [
          "编码", "名称", "描述", "数据范围", "权限数", "用户数",
          "状态",
        ],
        [
          [
            "super_admin", "超级管理员", "平台配置与运维", "全集团",
            "86", "1", "离线设计快照",
          ],
          [
            "expense_user", "费用使用人", "发起报销和借款", "所属组织",
            "12", "2", "离线设计快照",
          ],
          [
            "department_owner", "部门负责人", "部门预算与审批", "所属部门",
            "18", "1", "离线设计快照",
          ],
          [
            "general_manager", "综管负责人", "业务流程复核", "集团 / 项目",
            "24", "1", "离线设计快照",
          ],
        ],
      ),
    )
  }
}

///|
fn rbac_permission_catalog_table(model : Model) -> @html.Html {
  if model.rbac_catalog_loaded {
    let rows = if model.rbac_catalog_rows.length() == 0 {
      [["—", "0", "定义不可用"]]
    } else {
      model.rbac_catalog_rows
    }
    table_panel(
      "权限目录",
      model.rbac_catalog_note,
      data_table(["模块", "权限点数", "状态"], rows),
    )
  } else {
    table_panel(
      "权限目录",
      "权限目录读模型尚未加载 · 设计快照不用于授权",
      data_table(["模块", "权限点数", "状态"], [
        ["驾驶舱 / 项目 / 合同 / 付款", "—", "离线设计快照"],
      ]),
    )
  }
}

///|
fn users_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  page_shell(
    "用户/角色管理",
    "SYSTEM / USERS",
    "管理用户身份、组织范围和角色权限；超级用户标记不会直接迁移为目标权限。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(CreateLocalUser),
        "＋ 新建用户（本地候选）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(CreateLocalRole),
        "＋ 新建角色（本地候选）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(AssignLocalRole),
        "分配本地角色（候选）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(ToggleAdminUser),
        "启停用户（候选）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(ResetAdminUserPassword),
        "重置密码（候选）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(UpdateAdminUser),
        "更新用户资料（候选）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(DeleteLocalRole),
        "删除本地角色（候选）",
      ),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "用户管理"),
        button(class="erp-tab", "角色管理"),
        button(class="erp-tab", "权限目录"),
      ],
      user_roster_table(model),
      rbac_role_table(model),
      rbac_permission_catalog_table(model),
    ],
  )
}

///|
fn initiated_biz_label(biz : String) -> String {
  match biz {
    "vcb_expense" => "报销"
    "vcb_loan_simple" => "借款"
    "cb_htfk_apply" => "付款申请"
    _ => biz
  }
}

///|
fn profile_initiated_table(model : Model) -> @html.Html {
  if model.profile_initiated_loaded {
    let rows : Array[Array[String]] = []
    if model.profile_initiated_rows.length() == 0 {
      rows.push([
        "—", "当前用户在本次导出中没有发起记录", "—", "—",
        "—", "—",
      ])
    } else {
      for row in model.profile_initiated_rows {
        rows.push([
          row.code,
          initiated_biz_label(row.biz) +
          " · " +
          row.subject +
          " · " +
          row.source_kind,
          "¥" + row.amount,
          row.state,
          row.date,
          "查看 · " + row.id,
        ])
      }
    }
    table_panel(
      "我的发起 (" + model.profile_initiated_rows.length().to_string() + ")",
      "报销 / 借款 / 付款申请 · " + model.profile_initiated_note,
      data_table(
        ["编号", "类型 / 主题", "金额", "状态", "日期", "操作"],
        rows,
      ),
    )
  } else {
    table_panel(
      "我的发起 (6)",
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
            "PAY-260713-006", "主体结构施工合同付款", "¥1,280,000", "审批中",
            "2026-07-13", "查看",
          ],
        ],
      ),
    )
  }
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
      button(
        class="erp-secondary-btn",
        on_click=emit(UpdateProfile),
        "保存资料",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(ChangePassword),
        "修改密码",
      ),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "基本信息"),
        button(class="erp-tab", on_click=emit(ChangePassword), "修改密码"),
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
          editable_form_field(
            "姓名",
            model.profile_edit_name,
            "姓名",
            @html.InputType::Text,
            emit.map(value => InputProfileName(value)),
          ),
          form_field("显示名", model.profile_user_name, "用户名称"),
          form_field("所属公司", model.profile_bu_name, "所属公司"),
          form_field("所属部门", model.profile_dept_name, "所属部门"),
          form_field("管理员", model.profile_super_user, "超级用户"),
          form_field("状态", model.profile_enabled, "启用状态"),
          form_field("联系电话", "138****0000", "联系电话"),
          form_field("最后登录", model.profile_last_login, "最后登录"),
        ],
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("修改密码"),
          span(class="erp-info-tag", "旧密码校验 · PostgreSQL 凭据"),
        ],
        div(class="erp-form-grid") <| [
          editable_form_field(
            "旧密码",
            model.profile_password_old,
            "请输入当前密码",
            @html.InputType::Password,
            emit.map(value => InputProfilePasswordOld(value)),
          ),
          editable_form_field(
            "新密码",
            model.profile_password_new,
            "至少 6 位",
            @html.InputType::Password,
            emit.map(value => InputProfilePasswordNew(value)),
          ),
          editable_form_field(
            "确认新密码",
            model.profile_password_confirm,
            "再次输入新密码",
            @html.InputType::Password,
            emit.map(value => InputProfilePasswordConfirm(value)),
          ),
        ],
        div(class="erp-inline-actions") <| [
          button(
            class="erp-primary-btn",
            on_click=emit(ChangePassword),
            "更新密码",
          ),
        ],
        p(
          class="erp-source-note",
          "更新后将退出当前会话，请使用新密码重新登录。",
        ),
      ],
      p(
        class="erp-dashboard-note",
        model.profile_note + " · " + model.profile_command_note,
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
      profile_initiated_table(model),
    ],
  )
}

///|
fn notify_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let subscription_rows = if model.notify_loaded {
    if model.notify_subscription_rows.length() == 0 {
      [["—", "—", "—", "—", "无源记录"]]
    } else {
      model.notify_subscription_rows
    }
  } else {
    [
      [
        "cost_variance", "成本", "warning", "站内信 + 企业微信", "启用",
      ],
      ["task_overdue", "项目任务", "warning", "站内信", "启用"],
      ["cash_gap", "资金计划", "critical", "邮件 + 站内信", "启用"],
    ]
  }
  let config_rows = if model.notify_loaded {
    if model.notify_config_rows.length() == 0 {
      [["—", "无已配置键", "未导入"]]
    } else {
      model.notify_config_rows
    }
  } else {
    [["notify.webhook.url", "已配置", "设计快照"]]
  }
  let outbox_rows = if model.notify_loaded {
    if model.notify_outbox_rows.length() == 0 {
      [["—", "—", "—", "无源记录", "—"]]
    } else {
      model.notify_outbox_rows
    }
  } else {
    [
      [
        "Giant Claw", "成本偏差超过 5% · 成都和锦里", "今天 09:18",
        "已发送", "查看",
      ],
      ["陈志强", "2# 楼任务延期", "今天 08:42", "已发送", "查看"],
      ["刘松", "现金流缺口预测", "2026-07-11", "待发送", "重试"],
    ]
  }
  let digest_rows = if model.notify_loaded {
    if model.notify_digest_rows.length() == 0 {
      [["—", "—", "0", "0", "0", "0", "无源记录"]]
    } else {
      model.notify_digest_rows
    }
  } else {
    [
      ["2026-07-13", "09:20", "5", "0", "2", "8", "定时摘要"],
      ["2026-07-12", "18:00", "5", "0", "4", "26", "定时摘要"],
    ]
  }
  let source_note = if model.notify_loaded {
    model.notify_note +
    " · 订阅 " +
    model.notify_subscription_count +
    " · 配置 " +
    model.notify_configured_count +
    " · 队列 " +
    model.notify_outbox_count +
    " · 摘要 " +
    model.notify_digest_count +
    " · 空源表 " +
    model.notify_missing_table_count
  } else {
    "设计快照 · 生产通知投递与凭据仍需授权"
  }
  page_shell(
    "通知配置 / 订阅",
    "SYSTEM / NOTIFICATIONS",
    "配置站内信、邮件和 Webhook 的通知规则；敏感凭据只由生产密钥服务托管。",
    [
      button(
        class="erp-primary-btn",
        on_click=emit(CreateNotifySubscription),
        "＋ 新建规则（待授权）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(DispatchNotifyDigest),
        "检查摘要派发（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(TestNotifyEmail),
        "测试邮件（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(RedeliverNotifyEmail),
        "重投邮件（干运行）",
      ),
    ],
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("通知规则"),
          span(
            class="erp-info-tag",
            if model.notify_loaded {
              "PostgreSQL 源读"
            } else {
              "只读迁移快照"
            },
          ),
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
        "通知订阅",
        source_note,
        data_table(
          ["规则", "业务", "最低级别", "通道", "状态"],
          subscription_rows,
        ),
      ),
      table_panel(
        "源配置摘要",
        "仅显示配置键和状态 · 密码 / API Key / Token 永不返回",
        data_table(["配置键", "状态", "来源"], config_rows),
      ),
      table_panel(
        "通知队列",
        if model.notify_loaded {
          "源表邮件元数据 · 正文未导入 · " + model.notify_note
        } else {
          "最近发送记录"
        },
        data_table(
          ["收件人", "主题", "入队时间", "状态", "操作"],
          outbox_rows,
        ),
      ),
      table_panel(
        "通知日志",
        if model.notify_loaded {
          "每日摘要 · 只读日志 · 不触发发送"
        } else {
          "每日摘要"
        },
        data_table(
          [
            "日期", "发送时间", "接收人数", "错误", "警告", "新增",
            "触发",
          ],
          digest_rows,
        ),
      ),
      div(class="erp-runtime-banner", [
        strong("邮件投递命令门"),
        span(" · " + model.notify_email_note),
        span(" · outbox/provider/SMTP 均未执行"),
      ]),
    ],
  )
}

///|
fn ocr_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let provider_rows = if model.ocr_loaded {
    if model.ocr_provider_rows.length() == 0 {
      [["—", "—", "—", "—", "无源记录"]]
    } else {
      model.ocr_provider_rows
    }
  } else {
    [
      ["mock", "演示 Mock", "当前", "无需密钥", "设计快照"],
      ["paddle", "本地 PaddleOCR", "—", "无需密钥", "设计快照"],
      ["http", "自定义 HTTP 端点", "—", "需密钥", "设计快照"],
    ]
  }
  let task_rows = if model.ocr_loaded {
    [["—", "—", "—", "—", "—", "无源记录"]]
  } else {
    [
      [
        "OCR-260713-018", "主体结构施工合同.pdf", "合同", "32", "0.96",
        "已完成",
      ],
      [
        "OCR-260712-008", "成都出差发票-01.pdf", "发票", "18", "0.91", "待确认",
      ],
      [
        "OCR-260711-004", "销售合同扫描件.jpg", "合同", "26", "0.78", "需复核",
      ],
    ]
  }
  page_shell(
    "OCR 配置",
    "SYSTEM / OCR",
    "配置发票、合同和身份证的 OCR 服务方，并在写入业务单据前保留人工确认。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(TestOcrProvider),
        "测试连接（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(TestLlmProvider),
        "测试 LLM（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(TestNotifyLlmProvider),
        "测试通知 LLM（干运行）",
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(SaveOcrConfig),
        "保存配置（待授权）",
      ),
    ],
    div <| [
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("OCR 配置 / 测试"),
          span(
            class="erp-info-tag",
            if model.ocr_loaded {
              "PostgreSQL 源读"
            } else {
              "AI-4"
            },
          ),
        ],
        div(class="erp-form-grid") <| [
          form_field(
            "服务方",
            if model.ocr_loaded {
              model.ocr_provider
            } else {
              "本地 PaddleOCR"
            },
            "服务方",
          ),
          form_field(
            "远程 OCR URL",
            if model.ocr_loaded {
              "源配置已隐藏"
            } else {
              "https://ocr.internal.example/v1"
            },
            "远程 OCR URL",
          ),
          form_field(
            "API Key", "••••••••", "由密钥服务托管",
          ),
          form_field(
            "场景",
            if model.ocr_loaded {
              model.ocr_scene
            } else {
              "auto"
            },
            "识别场景",
          ),
          form_field(
            "已配置密钥",
            if model.ocr_loaded {
              model.ocr_configured_count
            } else {
              "—"
            },
            "只返回状态，不返回密钥",
          ),
          form_field("人工确认阈值", "0.85", "置信度"),
        ],
      ],
      table_panel(
        "OCR 服务方",
        if model.ocr_loaded {
          model.ocr_note +
          " · 空源表 " +
          model.ocr_missing_table_count +
          " · " +
          model.ocr_command_note
        } else {
          "provider 失败自动回退 mock · " + model.ocr_command_note
        },
        data_table(
          ["代码", "服务方", "当前", "密钥要求", "状态"],
          provider_rows,
        ),
      ),
      div(class="erp-runtime-banner", [
        strong("AI provider 命令门"),
        span(" · " + model.provider_test_note),
        span(" · OCR/LLM 均不调用外部 provider，不返回密钥"),
      ]),
      table_panel(
        "最近识别任务",
        if model.ocr_loaded {
          "源表未提供识别任务 · OCR 执行仍需授权"
        } else {
          "识别结果只产生草稿，不直接入账"
        },
        data_table(
          ["任务", "文件", "类型", "字段数", "置信度", "状态"],
          task_rows,
        ),
      ),
    ],
  )
}

///|
fn webhook_view(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  let config_rows = if model.webhook_loaded {
    if model.webhook_rows.length() == 0 {
      [["—", "—", "—", "—", "无源记录"]]
    } else {
      model.webhook_rows
    }
  } else {
    [
      [
        "企微", "已启用", "https://qyapi.weixin.qq.com/••••", "••••••••",
        "设计快照",
      ],
      ["飞书", "未启用", "— 未配置 —", "未设置", "设计快照"],
      ["钉钉", "未启用", "— 未配置 —", "未设置", "设计快照"],
    ]
  }
  let active_row = if model.webhook_loaded && model.webhook_rows.length() > 0 {
    model.webhook_rows[0]
  } else {
    [
      "企微", "已启用", "https://qyapi.weixin.qq.com/••••", "••••••••",
      "设计快照",
    ]
  }
  let recent_rows = if model.webhook_loaded {
    [["—", "—", "—", "—", "—", "无源记录"]]
  } else {
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
    ]
  }
  page_shell(
    "工单超期 Webhook",
    "SYSTEM / WEBHOOK",
    "为企业微信、飞书、钉钉配置工单超期通知；密钥和 URL 仅保留密文引用。",
    [
      button(
        class="erp-secondary-btn",
        on_click=emit(TestWebhookDelivery),
        "测试投递（干运行）",
      ),
      button(
        class="erp-secondary-btn",
        on_click=emit(PreviewWebhookOverdue),
        "预览超期扫描（干运行）",
      ),
      button(
        class="erp-ghost-btn",
        on_click=emit(ScanWebhookOverdue),
        "记录超期扫描候选",
      ),
      button(
        class="erp-primary-btn",
        on_click=emit(SaveWebhookConfig),
        "保存配置（待授权）",
      ),
    ],
    div <| [
      div(class="erp-tabs") <| [
        button(class="erp-tab is-active", "企业微信"),
        button(class="erp-tab", "飞书"),
        button(class="erp-tab", "钉钉"),
      ],
      section(class="erp-detail-card") <| [
        div(class="erp-panel-heading") <| [
          h2("企业微信配置"),
          span(class="erp-status-tag is-success", active_row[1]),
        ],
        div(class="erp-form-grid") <| [
          form_field("启用", active_row[1], "启用状态"),
          form_field("Webhook URL", active_row[2], "Webhook URL"),
          form_field("密钥", active_row[3], "由密钥服务托管"),
          form_field("超期阈值", "3 天", "工单超期"),
          form_field("通知范围", "项目任务", "业务范围"),
          form_field("重试策略", "3 次 / 5 分钟", "失败重试"),
        ],
      ],
      table_panel(
        "三平台配置源读",
        if model.webhook_loaded {
          model.webhook_note +
          " · 空源表 " +
          model.webhook_missing_table_count +
          " · " +
          model.webhook_command_note
        } else {
          "设计快照 · URL/密钥仅显示脱敏摘要 · " +
          model.webhook_command_note
        },
        data_table(
          ["平台", "状态", "Webhook URL", "密钥", "来源"],
          config_rows,
        ),
      ),
      table_panel(
        "最近发送",
        if model.webhook_loaded {
          "源表未提供投递记录 · provider 执行与扫描仍需授权"
        } else {
          "仅保留投递结果和摘要"
        },
        data_table(
          [
            "平台", "事件", "发送时间", "状态", "重试次数", "摘要",
          ],
          recent_rows,
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
fn error_view(model : Model) -> @html.Html {
  let rows = if model.error_loaded {
    if model.error_rows.length() == 0 {
      [["—", "—", "—", "—", "—", "无源记录", "—"]]
    } else {
      model.error_rows
    }
  } else {
    [
      [
        "ERR-260713-003", "今天 09:16", "GET", "/api/company/projections", "500",
        "projection query timeout", "已脱敏",
      ],
      [
        "ERR-260712-018", "昨天 17:20", "POST", "/api/ocr/recognize", "422", "confidence below threshold",
        "已脱敏",
      ],
      [
        "ERR-260711-004", "2026-07-11", "PUT", "/api/notify/config", "403", "authority denied",
        "已脱敏",
      ],
    ]
  }
  let total = if model.error_loaded { model.error_total } else { "3" }
  let today = if model.error_loaded { model.error_today_count } else { "3" }
  let five_xx = if model.error_loaded { model.error_five_xx_count } else { "1" }
  page_shell(
    "错误日志",
    "SYSTEM / ERRORS",
    "查看服务错误、HTTP 状态和业务上下文；原始网络标识不在公司投影中公开。",
    [button(class="erp-secondary-btn", "清理已处理（待授权）")],
    div <| [
      div(class="erp-stat-grid") <| [
        metric(
          "今日错误",
          today,
          if model.error_loaded {
            "源表计数"
          } else {
            "较昨日 -4"
          },
          "metric-blue",
        ),
        metric(
          "5xx",
          five_xx,
          if model.error_loaded {
            "源表计数"
          } else {
            "需运维关注"
          },
          "metric-blue",
        ),
        metric("已处理", "98.6%", "本周", "metric-green"),
      ],
      filter_bar("路径 / 方法 / 状态码 / 错误内容"),
      table_panel(
        "错误记录",
        if model.error_loaded {
          model.error_note +
          " · 空源表 " +
          model.error_missing_table_count +
          " · 总计 " +
          total
        } else {
          "最近发生"
        },
        data_table(
          ["ID", "时间", "方法", "路径", "状态码", "错误", "IP"],
          rows,
        ),
      ),
    ],
  )
}

///|
fn admin_dict_table(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  if model.admin_dict_loaded {
    let rows : Array[Array[String]] = []
    for row in model.admin_dict_option_rows {
      rows.push([
        row.group_name,
        row.code,
        row.value,
        row.display_order,
        row.enabled,
        if row.source_kind == "command" {
          "可编辑本地覆盖"
        } else {
          "只读 · " + row.source_kind
        },
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
    div <| [
      div(class="erp-command-bar") <| [
        button(
          class="erp-primary-btn",
          on_click=emit(CreateAdminDictOption),
          "＋ 新建本地字典",
        ),
        if admin_dict_editable_guid(model) == "" {
          span(class="erp-info-tag", "暂无本地覆盖项")
        } else {
          button(
            class="erp-secondary-btn",
            on_click=emit(UpdateAdminDictOption),
            "编辑本地覆盖",
          )
        },
        span(class="erp-info-tag", model.admin_dict_command_note),
      ],
      table_panel(
        "数据字典",
        group_note + " · " + model.admin_dict_command_note,
        data_table(
          ["分组", "编码", "值", "排序", "状态", "来源/操作"],
          rows,
        ),
      ),
    ]
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
      button(
        class="erp-secondary-btn",
        on_click=emit(RequestAdminBackup),
        "检查数据库备份边界",
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
      admin_dict_table(emit, model),
      admin_quality_table(model),
      div(class="erp-runtime-banner", [
        strong("PostgreSQL 备份边界"),
        span(" · " + model.admin_backup_note),
        span(" · 不调用 mysqldump、不导出二进制"),
      ]),
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
    share_view(model, path)
  } else if path.has_prefix("/projects/") {
    project_detail_view(emit, model)
  } else if path.has_prefix("/contracts/") {
    contract_detail_view(emit, model)
  } else if path.has_prefix("/expenses/") && path != "/expenses/new" {
    expense_editor_view(emit, model, true)
  } else if path.has_prefix("/loans/") && path != "/loans/new" {
    loan_editor_view(emit, model, true)
  } else if path.has_prefix("/srm/providers/") {
    provider_detail_view(emit, model)
  } else {
    match path {
      "/dashboard-v3" => dashboard_view(emit, initial_model())
      "/cockpit" => dashboard_view(emit, initial_model())
      "/ai-hub" => ai_hub_view(emit, model)
      "/ai-stats" => ai_stats_view(emit, model)
      "/projects" => project_view(emit, model)
      "/projects/CD-HJL" => project_detail_view(emit, model)
      "/project-plan" => project_plan_view(emit, model)
      "/project/progress" => progress_view(emit, model)
      "/tasks" => tasks_view(emit, model)
      "/sales/customers" => sales_customers_view(emit, model)
      "/sales/subscriptions" => sales_subscriptions_view(emit, model)
      "/sales/contracts" => sales_contracts_view(emit, model)
      "/sales/mortgages" => sales_mortgages_view(emit, model)
      "/sales/revenues" => sales_revenues_view(emit, model)
      "/marketing" => marketing_view(emit, model)
      "/contracts" => contracts_view(emit, model)
      "/contracts/HT-CD-260701" => contract_detail_view(emit, model)
      "/payment-applies" => payment_applies_view(emit, model)
      "/cost-dashboard-v3" => cost_dashboard_view(emit, model)
      "/investment" => investment_view(emit, model)
      "/dynamic-cost" => dynamic_cost_view(emit, model)
      "/tender" => tender_view(emit, model)
      "/srm/providers" => srm_providers_view(emit, model)
      "/srm/providers/SUP-00018" => provider_detail_view(emit, model)
      "/srm/risk-board" => srm_risk_view(emit, model)
      "/cbs/dict" => cbs_view(model, path)
      "/cbs/versions" => cbs_view(model, path)
      "/cbs/r0-queue" => cbs_view(model, path)
      "/cbs/approval-config" => cbs_view(model, path)
      "/fund/plan" => fund_plan_view(emit, model)
      "/invoice" => invoice_view(emit, model)
      "/expenses" => expenses_view(emit, model)
      "/expenses/new" => expense_editor_view(emit, model, false)
      "/expenses/EXP-260712-008" => expense_editor_view(emit, model, true)
      "/loans" => loans_view(emit, model)
      "/loans/new" => loan_editor_view(emit, model, false)
      "/loans/LOAN-260713-001" => loan_editor_view(emit, model, true)
      "/reports" => reports_view(emit, model)
      "/report-builder" => report_builder_view(emit, model)
      "/warning" => warning_view(emit, model)
      "/warning-rules" => warning_rules_view(emit, model)
      "/cashflow" => cashflow_view(emit, model)
      "/inbox" => inbox_view(emit, model)
      "/attachments" => attachments_view(emit, model)
      "/notify-config" => notify_view(emit, model)
      "/audit-log" => audit_view(emit, model)
      "/error-log" => error_view(model)
      "/system-health" => health_view(emit, model)
      "/users" => users_view(emit, model)
      "/admin" => admin_view(emit, model)
      "/ocr-config" => ocr_view(emit, model)
      "/webhook-config" => webhook_view(emit, model)
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
    share_view(model, model.page)
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
