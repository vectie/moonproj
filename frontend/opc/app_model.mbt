///|
enum Page {
  Workspace
  Overview
  Fleet
  Dispatch
  Projects
  Products
  Objectives
  MoonSuite
  Quality
  Observe
  Operate
  Company
  PolicyRadar
  Evidence
  Guide
  Market
  Delivery
  Commerce
  Finance
  Assurance
  Extensions
} derive(Debug, Eq)

///|
struct NavItem {
  page : Page
  group : String
  label : String
  short_label : String
  description : String
}

///|
struct Model {
  page : Page
  workspace : CompanyWorkspace
  charter : CompanyCharterState
  moon_mode : Bool
  products : ProductsState
  today : TodayState
  plan : PlanWorkbench
  engineering_project : String
  engineering_audit_state : String
  engineering_audit_id : String
  engineering_task_id : String
  engineering_branch : String
  engineering_version : String
  engineering_tag : String
  engineering_commit : String
  engineering_repository : String
  engineering_review : String
  engineering_gate_states : Array[String]
  engineering_progress : String
  engineering_health : String
  engineering_production : String
  engineering_freshness : String
  engineering_findings : Int32
  engineering_poll_attempts : Int32
  product_in_gate_decision : String
  product_in_gate_primary_value : String
  product_in_gate_segment : String
  product_in_gate_workflow : String
  product_in_gate_problem_evidence : String
  product_in_gate_commitment_evidence : String
  product_in_gate_current_behavior_cost : String
  product_in_gate_outcome_metric : String
  product_in_gate_adoption_path : String
  product_in_gate_unresolved_risks : String
  product_in_gate_next_experiment : String
  product_in_gate_review_by : String
  product_in_gate_owner : String
  product_in_gate_persisted : Bool
  policy_radar_state : String
  policy_radar_projection : PolicyRadarProjection?
  policy_radar_error : String
  policy_review_kind : String
  policy_review_target_id : String
  policy_review_decision : String
  policy_review_evidence : String
  policy_review_pending : Bool
  policy_last_audit_id : String
  policy_last_review_target : String
  mobile_nav : Bool
  dispatch_drafts : Array[DispatchDraft]
  work_packet : WorkPacketState
  research_import : ResearchImportState
  dispatch_offer_drafts : Array[DispatchOfferDraft]
  dispatch_offer_task : Json
  dispatch_offer_storage : String
  dispatch_reply_drafts : Array[DispatchReplyDraft]
  dispatch_reply_storage : String
  dispatch_reply_generation : Int32
  dispatch_draft_id : String
  dispatch_draft_storage : String
  dispatch_recent_tasks : Array[String]
  dispatch_task_product_id : String
  dispatch_report_product_id : String
  dispatch_task_selection : Int32
  dispatch_desk_handoff : DispatchDeskHandoff
  dispatch_lesson_handoff : DispatchLessonHandoff
  dispatch_guidance : DispatchGuidanceState
  dispatch_outcome_drafts : Array[DispatchOutcomeDraft]
  dispatch_outcome_sequence : Int32
  dispatch_accepted_human_export : DispatchAcceptedHumanExport
  dispatch_client_delivery : DispatchClientDelivery
  dispatch_continuation : DispatchContinuationState
  delivery : DeliveryState
  office : OfficeState
  dispatch_task_open_id : String
  dispatch_task_workspace : String
  dispatch_task_model : String
  dispatch_run : DispatchRun?
  dispatch_task_form_open : Bool
  dispatch_task_title : String
  dispatch_task_acceptance : String
  dispatch_task_source_context : Json
  dispatch_task_commitment : Json
  dispatch_journey_read_state : String
  dispatch_task_project_id : String
  dispatch_task_owner_id : String
  dispatch_task_actor_id : String
  dispatch_task_begin_date : String
  dispatch_task_end_date : String
  dispatch_task_evidence_id : String
  dispatch_task_id : String
  dispatch_task_report_summary : String
  dispatch_task_report_id : String
  dispatch_task_stage : String
  dispatch_task_pending_action : String
  dispatch_task_event_id : String
  dispatch_task_audit_id : String
  dispatch_task_blocked : Bool
  dispatch_task_note : String
  company_form_open : Bool
  company_setup : CompanySetupState
  company_name : String
  company_saved : Bool
  market_form_open : Bool
  market_party : String
  market_problem : String
  market_saved : Bool
  work_form_open : Bool
  work_title : String
  work_acceptance : String
  work_saved : Bool
  work_stage : Int32
  commitment_form_open : Bool
  commitment_title : String
  commitment_counterparty : String
  commitment_saved : Bool
  commitment_stage : Int32
  constitution_ready : Bool
  authority_ready : Bool
  resource_register_ready : Bool
  offer_register_ready : Bool
  workflow_ready : Bool
  attention_ready : Bool
  procurement_ready : Bool
  expense_register_ready : Bool
  budget_ready : Bool
  ledger_ready : Bool
  treasury_ready : Bool
  tax_ready : Bool
  financing_ready : Bool
  investment_ready : Bool
  control_ready : Bool
  learning_ready : Bool
  continuity_ready : Bool
  notice : String
}

///|
enum Msg {
  WorkspaceAction(WorkspaceMsg)
  CharterAction(CharterMsg)
  AcceptedHumanExportAction(DispatchAcceptedHumanExportMsg)
  ClientDeliveryAction(DispatchClientDeliveryMsg)
  OutcomeAction(Json, DispatchOutcomeMsg)
  LessonHandoffAction(DispatchLessonHandoffMsg)
  GuidanceAction(DispatchGuidanceMsg)
  Navigate(Page)
  SetMoonMode(Bool)
  ProductsAction(ProductsMsg)
  TodayAction(TodayMsg)
  PlanAction(PlanMsg)
  SelectEngineeringProject(String)
  InputEngineeringBranch(String)
  InputEngineeringVersion(String)
  InputEngineeringTag(String)
  RequestEngineeringAudit
  EngineeringAuditSubmitted(String, Int32, String, String)
  EngineeringAuditStatus(String, Int32, String)
  EngineeringProjectionLoaded(
    String,
    String,
    String,
    String,
    String,
    String,
    Int32,
    String,
    String,
    String,
    String,
    Array[String]
  )
  SelectProductInGateDecision(String)
  SelectProductInGatePrimaryValue(String)
  InputProductInGateSegment(String)
  InputProductInGateWorkflow(String)
  InputProductInGateProblemEvidence(String)
  InputProductInGateCommitmentEvidence(String)
  InputProductInGateCurrentBehaviorCost(String)
  InputProductInGateOutcomeMetric(String)
  InputProductInGateAdoptionPath(String)
  InputProductInGateUnresolvedRisks(String)
  InputProductInGateNextExperiment(String)
  InputProductInGateReviewBy(String)
  SaveProductInGate
  ProductInGateSaved(String)
  ProductInGateLoaded(
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    String,
    Bool
  )
  ProductInGateFailed(String)
  RefreshPolicyRadar
  PolicyRadarLoaded(PolicyRadarProjection)
  PolicyRadarFailed(String)
  OpenPolicyReview(String, String, String)
  SelectPolicyReviewDecision(String)
  InputPolicyReviewEvidence(String)
  SubmitPolicyReview
  CancelPolicyReview
  PolicyReviewSaved(String, String)
  PolicyReviewFailed(String)
  PreparePolicyValidationTask(String)
  OpenPolicyEvidence
  RequestEngineeringRemediation
  EngineeringRemediationCreated(String, Int32)
  EngineeringAuditFailed(String, Int32)
  RecordDecision(String)
  ToggleMobileNav
  OpenDispatchTaskForm
  DraftAction(DispatchDraftMsg)
  ExportFounderPacket
  FounderPacketDownloaded(String, Int32, Int32, Page, String, Bool)
  WorkPacketAction(WorkPacketMsg)
  ResearchImportAction(ResearchImportMsg)
  OfferAction(DispatchOfferMsg)
  ReplyAction(DispatchReplyMsg)
  SelectDispatchTask(String)
  InputDispatchTaskWorkspace(String)
  InputDispatchTaskModel(String)
  InputDispatchTaskOpenId(String)
  OpenDispatchTask
  DeskHandoffAction(DispatchDeskHandoffMsg)
  ContinuationAction(DispatchContinuationMsg)
  RefreshDispatchTask(String, Int32)
  DispatchTaskLoaded(String, Int32, DispatchSnapshot)
  DispatchSessionLoaded(String)
  LoadDispatchSession
  RestoreDispatchTask(String)
  RestorePageRoute(Page, String)
  RestoreProductPageRoute(Page, String, String)
  InputDispatchTaskEvidenceId(String)
  CreateDispatchTask
  SaveDispatchExecutionSettings
  DispatchExecutionSettingsSaved(String, Int32)
  StartDispatchTask
  DeliveryAction(DeliveryMsg)
  OfficeAction(OfficeMsg)
  SubmitDispatchTask
  DispatchTaskSubmitted(String, Int32, String, String, String)
  AcceptDispatchTask
  DispatchTaskAccepted(String, Int32, String, String)
  DispatchTaskCommandFailed(String, Int32, String, String)
  OpenCompanyForm
  InputCompanyName(String)
  SaveCompany
  CompanySetupAction(CompanySetupMsg)
  OpenMarketForm
  InputMarketParty(String)
  InputMarketProblem(String)
  SaveMarket
  OpenWorkForm
  InputWorkTitle(String)
  InputWorkAcceptance(String)
  SaveWork
  StartWork
  SubmitWork
  AcceptWork
  OpenCommitmentForm
  InputCommitmentTitle(String)
  InputCommitmentCounterparty(String)
  SaveCommitment
  ApproveCommitment
  SignCommitment
  CompleteCommitment
  SettleCommitment
  RecognizeCommitment
  SetupConstitution
  SetupAuthority
  SetupResourceRegister
  SetupOfferRegister
  SetupWorkflow
  SetupAttention
  SetupProcurement
  SetupExpenseRegister
  SetupBudget
  SetupLedger
  SetupTreasury
  SetupTax
  SetupFinancing
  SetupInvestment
  SetupControls
  SetupLearning
  SetupContinuity
  DismissNotice
}

///|
fn initial_model() -> Model {
  {
    page: Workspace,
    workspace: workspace_initial(),
    charter: charter_initial(),
    moon_mode: false,
    products: products_initial(),
    today: today_initial(),
    plan: plan_initial(),
    engineering_project: "",
    engineering_audit_state: "idle",
    engineering_audit_id: "",
    engineering_task_id: "",
    engineering_branch: "main",
    engineering_version: "0.1.0-preview.1",
    engineering_tag: "v0.1.0-preview.1",
    engineering_commit: "unknown",
    engineering_repository: "unknown",
    engineering_review: "needs_evidence",
    engineering_gate_states: [
      "unknown", "unknown", "unknown", "unknown", "unknown", "unknown", "unknown",
      "unknown", "unknown",
    ],
    engineering_progress: "unknown",
    engineering_health: "unknown",
    engineering_production: "unknown",
    engineering_freshness: "missing",
    engineering_findings: 0,
    engineering_poll_attempts: 0,
    product_in_gate_decision: "unknown",
    product_in_gate_primary_value: "solution",
    product_in_gate_segment: "",
    product_in_gate_workflow: "",
    product_in_gate_problem_evidence: "",
    product_in_gate_commitment_evidence: "",
    product_in_gate_current_behavior_cost: "",
    product_in_gate_outcome_metric: "",
    product_in_gate_adoption_path: "",
    product_in_gate_unresolved_risks: "",
    product_in_gate_next_experiment: "",
    product_in_gate_review_by: "",
    product_in_gate_owner: "",
    product_in_gate_persisted: false,
    policy_radar_state: "idle",
    policy_radar_projection: None,
    policy_radar_error: "",
    policy_review_kind: "",
    policy_review_target_id: "",
    policy_review_decision: "",
    policy_review_evidence: "",
    policy_review_pending: false,
    policy_last_audit_id: "",
    policy_last_review_target: "",
    mobile_nav: false,
    dispatch_drafts: [],
    work_packet: empty_work_packet(0),
    research_import: empty_research_import(0),
    dispatch_offer_drafts: [],
    dispatch_offer_task: Json::null(),
    dispatch_offer_storage: "未保存到此浏览器",
    dispatch_reply_drafts: [],
    dispatch_reply_storage: "尚未保留到当前标签页",
    dispatch_reply_generation: 0,
    dispatch_draft_id: "",
    dispatch_draft_storage: "未保存到此浏览器",
    dispatch_recent_tasks: [],
    dispatch_task_product_id: "",
    dispatch_report_product_id: "",
    dispatch_task_selection: 0,
    dispatch_desk_handoff: empty_dispatch_desk_handoff(),
    dispatch_lesson_handoff: empty_dispatch_lesson_handoff(),
    dispatch_guidance: empty_dispatch_guidance(),
    dispatch_outcome_drafts: [],
    dispatch_outcome_sequence: 0,
    dispatch_accepted_human_export: empty_dispatch_accepted_human_export(),
    dispatch_client_delivery: empty_dispatch_client_delivery(),
    dispatch_continuation: empty_dispatch_continuation(),
    delivery: delivery_initial(),
    office: office_initial(),
    dispatch_task_open_id: "",
    dispatch_task_workspace: "",
    dispatch_task_model: "",
    dispatch_run: None,
    dispatch_task_form_open: false,
    dispatch_task_title: "",
    dispatch_task_acceptance: "",
    dispatch_task_source_context: Json::null(),
    dispatch_task_commitment: Json::null(),
    dispatch_journey_read_state: "",
    dispatch_task_project_id: "",
    dispatch_task_owner_id: "",
    dispatch_task_actor_id: "",
    dispatch_task_begin_date: "",
    dispatch_task_end_date: "",
    dispatch_task_evidence_id: "",
    dispatch_task_id: "",
    dispatch_task_report_summary: "",
    dispatch_task_report_id: "",
    dispatch_task_stage: "empty",
    dispatch_task_pending_action: "",
    dispatch_task_event_id: "",
    dispatch_task_audit_id: "",
    dispatch_task_blocked: false,
    dispatch_task_note: "尚未向 MoonProj 持久化任务。创建动作只在签名网关返回审计收据后推进。",
    company_form_open: false,
    company_setup: company_setup_initial(),
    company_name: "",
    company_saved: false,
    market_form_open: false,
    market_party: "",
    market_problem: "",
    market_saved: false,
    work_form_open: false,
    work_title: "",
    work_acceptance: "",
    work_saved: false,
    work_stage: 0,
    commitment_form_open: false,
    commitment_title: "",
    commitment_counterparty: "",
    commitment_saved: false,
    commitment_stage: 0,
    constitution_ready: false,
    authority_ready: false,
    resource_register_ready: false,
    offer_register_ready: false,
    workflow_ready: false,
    attention_ready: false,
    procurement_ready: false,
    expense_register_ready: false,
    budget_ready: false,
    ledger_ready: false,
    treasury_ready: false,
    tax_ready: false,
    financing_ready: false,
    investment_ready: false,
    control_ready: false,
    learning_ready: false,
    continuity_ready: false,
    notice: "",
  }
}

