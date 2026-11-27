///|
fn update(emit : @rabbita.Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  let (command, next) = update_model(emit, msg, model)
  let next = work_packet_reconcile(next)
  let command = if model.work_packet.loading &&
    model.work_packet.generation != next.work_packet.generation {
    @cmd.batch([@cmd.custom_cmd(_ => work_packet_cancel_file()), command])
  } else {
    command
  }
  let next = research_import_reconcile(model, next)
  let command = if model.research_import.open && !next.research_import.open {
    @cmd.batch([@cmd.custom_cmd(_ => research_cancel_file()), command])
  } else {
    command
  }
  let (command, next) = today_reconcile(emit, command, next)
  let command = workspace_observe(emit, model, next, msg, command)
  let next = plan_reconcile(next)
  let next = dispatch_guidance_reconcile(next)
  let next = dispatch_accepted_human_export_reconcile(next)
  let next = dispatch_client_delivery_reconcile(next)
  let command = dispatch_guidance_transition(model, next, command)
  // Only an explicit product choice pushes history. Catalog reads and route
  // restoration use the same read-only selection reducer without adding entries.
  let product_navigation = match msg {
    ProductsAction(Select(_)) | SelectEngineeringProject(_) => true
    _ => false
  }
  if product_navigation &&
    next.products.selected_id != model.products.selected_id {
    return (
      @cmd.batch([
        remember_product_route(next.page, next.products.selected_id),
        command,
      ]),
      next,
    )
  }
  // Only deliberate page changes add history. Task selection owns its single
  // combined page/task entry; hydration and async replies never push a page.
  let navigation = match msg {
    Navigate(_)
    | SetMoonMode(_)
    | OpenPolicyEvidence
    | OpenCompanyForm
    | OpenDispatchTaskForm
    | PreparePolicyValidationTask(_)
    | ProductsAction(
      Prepare
      | PrepareWork(_, _)
      | CancelPreparation
      | OpenEngineering(_),
    )
    | DraftAction(New | Resume(_) | Revise(_))
    | PlanAction(Handoff(CreateDraft)) => true
    _ => false
  }
  if navigation &&
    next.page != model.page &&
    next.dispatch_task_selection == model.dispatch_task_selection {
    (
      @cmd.batch([
        remember_page_route(
          next.page,
          if next.page == Workspace {
            next.workspace.job
          } else {
            next.dispatch_task_id
          },
          push=true,
        ),
        command,
      ]),
      next,
    )
  } else {
    (command, next)
  }
}

///|
fn update_model(
  emit : @rabbita.Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model) {
  match msg {
    WorkspaceAction(action) => workspace_update(emit, model, action)
    CharterAction(action) => charter_update(emit, action, model)
    DeliveryAction(action) => delivery_update(emit, model, action)
    OfficeAction(action) => office_update(emit, model, action)
    AcceptedHumanExportAction(action) =>
      dispatch_accepted_human_export_update(emit, model, action)
    ClientDeliveryAction(action) =>
      dispatch_client_delivery_update(emit, model, action)
    CompanySetupAction(action) => company_setup_update(emit, action, model)
    ProductsAction(action) => products_update(emit, action, model)
    TodayAction(action) => today_update(emit, action, model)
    PlanAction(action) => plan_update(emit, action, model)
    Navigate(Projects) =>
      plan_update(emit, Refresh, { ..model, page: Projects, mobile_nav: false, })
    Navigate(page) if [Workspace, Overview, Objectives, Fleet].contains(page) =>
      today_update(emit, Refresh, {
        ..model,
        page,
        mobile_nav: false,
        dispatch_desk_handoff: {
          ..model.dispatch_desk_handoff,
          pending: false,
        },
        dispatch_continuation: {
          ..model.dispatch_continuation,
          request: model.dispatch_continuation.request + 1,
          phase: "idle",
        },
      })
    Navigate(page) if page == model.page =>
      (none, { ..model, mobile_nav: false, })
    Navigate(page) =>
      (
        if page == Products ||
          (
            (page == Quality || page == MoonSuite) &&
            model.products.state != "ready"
          ) {
          products_load_catalog(emit, model.products.request + 1)
        } else if page == PolicyRadar {
          load_policy_radar(emit)
        } else if page == MoonSuite && products_engineering_enrolled(model) {
          @cmd.batch([
            load_engineering_projection(
              emit,
              engineering_project_name(model.engineering_project),
              model.products.selection,
            ),
            load_product_in_gate(
              emit,
              engineering_project_name(model.engineering_project),
              model.products.selection,
            ),
          ])
        } else if page == Dispatch {
          @cmd.batch([
            emit(CompanySetupAction(Refresh)),
            emit(
              RefreshDispatchTask(
                model.dispatch_task_id,
                model.dispatch_task_selection,
              ),
            ),
          ])
        } else if page == Quality && products_engineering_enrolled(model) {
          load_engineering_projection(
            emit,
            engineering_project_name(model.engineering_project),
            model.products.selection,
          )
        } else {
          none
        },
        {
          ..model,
          page,
          dispatch_desk_handoff: {
            ..model.dispatch_desk_handoff,
            pending: false,
          },
          dispatch_continuation: {
            ..model.dispatch_continuation,
            request: model.dispatch_continuation.request + 1,
            phase: "idle",
          },
          products: if page == Products ||
            (
              (page == Quality || page == MoonSuite) &&
              model.products.state != "ready"
            ) {
            {
              ..model.products,
              state: "loading",
              request: model.products.request + 1,
            }
          } else {
            model.products
          },
          policy_radar_state: if page == PolicyRadar {
            "loading"
          } else {
            model.policy_radar_state
          },
          policy_radar_error: if page == PolicyRadar {
            ""
          } else {
            model.policy_radar_error
          },
          mobile_nav: false,
          notice: "",
        },
      )
    SetMoonMode(enabled) =>
      (
        none,
        {
          ..model,
          moon_mode: enabled,
          page: if !enabled && model.page == MoonSuite {
            Overview
          } else {
            model.page
          },
          mobile_nav: false,
          notice: if enabled {
            "Moon 专案视图已启用；它是基础 OPC 的产品线投影，不改变公司事实。"
          } else {
            "已返回通用 OPC；Moon Suite 依赖不会阻断基础公司运行。"
          },
        },
      )
    SelectEngineeringProject(id) => products_update(emit, Select(id), model)
    InputEngineeringBranch(value) =>
      (none, { ..model, engineering_branch: value, })
    InputEngineeringVersion(value) =>
      (none, { ..model, engineering_version: value, })
    InputEngineeringTag(value) => (none, { ..model, engineering_tag: value, })
    RequestEngineeringAudit =>
      if !products_can_audit(model) {
        (
          none,
          {
            ..model,
            notice: "此产品未登记可用的工程审计仓库；没有启动审计。",
          },
        )
      } else {
        (
          request_engineering_audit(emit, model),
          {
            ..model,
            engineering_audit_state: "submitting",
            engineering_audit_id: "",
            engineering_task_id: "",
            notice: "正在通过 MoonProj 请求独立的 MoonClaw 生产者与复核者生成一份工程证据。",
          },
        )
      }
    EngineeringAuditSubmitted(project, selection, audit_id, task_id) =>
      if project != model.engineering_project ||
        selection != model.products.selection {
        (none, model)
      } else {
        (
          @cmd.delay(
            poll_engineering_audit(
              emit,
              engineering_project_name(model.engineering_project),
              audit_id,
              task_id,
              model.products.selection,
            ),
            2000,
          ),
          {
            ..model,
            engineering_audit_state: "submitted",
            engineering_audit_id: audit_id,
            engineering_task_id: task_id,
            engineering_poll_attempts: 1,
            notice: "MoonClaw 审计任务已提交。独立复核完成前，结论仍为未知。",
          },
        )
      }
    EngineeringAuditStatus(project, selection, state) =>
      if project != engineering_project_name(model.engineering_project) ||
        selection != model.products.selection {
        (none, model)
      } else if state == "ingested" {
        (
          load_engineering_projection(
            emit,
            engineering_project_name(model.engineering_project),
            model.products.selection,
          ),
          {
            ..model,
            engineering_audit_state: "ingested",
            notice: "证据已通过服务端验证并写入 PostgreSQL。",
          },
        )
      } else if (state == "running" || state == "awaiting_artifact") &&
        model.engineering_poll_attempts < 600 {
        (
          @cmd.delay(
            poll_engineering_audit(
              emit,
              engineering_project_name(model.engineering_project),
              model.engineering_audit_id,
              model.engineering_task_id,
              model.products.selection,
            ),
            2000,
          ),
          {
            ..model,
            engineering_audit_state: state,
            engineering_poll_attempts: model.engineering_poll_attempts + 1,
          },
        )
      } else {
        (
          none,
          {
            ..model,
            engineering_audit_state: "failed",
            notice: "审计没有形成可接受证据；未更新任何工程结论。",
          },
        )
      }
    EngineeringProjectionLoaded(
      project,
      progress,
      health,
      production,
      freshness,
      audit_id,
      findings,
      repository,
      branch,
      commit,
      review,
      gate_states,
    ) =>
      if project != engineering_project_name(model.engineering_project) {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            engineering_progress: progress,
            engineering_health: health,
            engineering_production: production,
            engineering_freshness: freshness,
            engineering_audit_id: audit_id,
            engineering_findings: findings,
            engineering_repository: repository,
            engineering_branch: if branch == "unknown" {
              model.engineering_branch
            } else {
              branch
            },
            engineering_commit: commit,
            engineering_review: review,
            engineering_gate_states: gate_states,
            engineering_audit_state: if freshness == "missing" {
              "idle"
            } else {
              "ready"
            },
            notice: if freshness == "stale" {
              "证据已过期；界面保留历史结果，但不把它当作当前可信结论。"
            } else {
              model.notice
            },
          },
        )
      }
    SelectProductInGateDecision(value) =>
      (none, { ..model, product_in_gate_decision: value, })
    SelectProductInGatePrimaryValue(value) =>
      (none, { ..model, product_in_gate_primary_value: value, })
    InputProductInGateSegment(value) =>
      (none, { ..model, product_in_gate_segment: value, })
    InputProductInGateWorkflow(value) =>
      (none, { ..model, product_in_gate_workflow: value, })
    InputProductInGateProblemEvidence(value) =>
      (none, { ..model, product_in_gate_problem_evidence: value, })
    InputProductInGateCommitmentEvidence(value) =>
      (none, { ..model, product_in_gate_commitment_evidence: value, })
    InputProductInGateCurrentBehaviorCost(value) =>
      (none, { ..model, product_in_gate_current_behavior_cost: value, })
    InputProductInGateOutcomeMetric(value) =>
      (none, { ..model, product_in_gate_outcome_metric: value, })
    InputProductInGateAdoptionPath(value) =>
      (none, { ..model, product_in_gate_adoption_path: value, })
    InputProductInGateUnresolvedRisks(value) =>
      (none, { ..model, product_in_gate_unresolved_risks: value, })
    InputProductInGateNextExperiment(value) =>
      (none, { ..model, product_in_gate_next_experiment: value, })
    InputProductInGateReviewBy(value) =>
      (none, { ..model, product_in_gate_review_by: value, })
    SaveProductInGate =>
      (
        request_product_in_gate_mark(emit, model),
        {
          ..model,
          notice: "正在持久化 Product In-Gate 组合决策；这不会改变出厂 G1-G9。",
        },
      )
    ProductInGateSaved(project) =>
      if project != engineering_project_name(model.engineering_project) {
        (none, model)
      } else {
        (
          load_product_in_gate(emit, project, model.products.selection),
          {
            ..model,
            notice: "Product In-Gate 已写入 PostgreSQL；出厂 G1-G9 保持独立。",
          },
        )
      }
    ProductInGateLoaded(
      project,
      decision,
      primary_value,
      segment,
      workflow,
      problem_evidence,
      commitment_evidence,
      current_behavior_cost,
      outcome_metric,
      adoption_path,
      unresolved_risks,
      next_experiment,
      review_by,
      owner,
      persisted,
    ) =>
      if project != engineering_project_name(model.engineering_project) {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            product_in_gate_decision: decision,
            product_in_gate_primary_value: if primary_value == "unknown" {
              "solution"
            } else {
              primary_value
            },
            product_in_gate_segment: segment,
            product_in_gate_workflow: workflow,
            product_in_gate_problem_evidence: problem_evidence,
            product_in_gate_commitment_evidence: commitment_evidence,
            product_in_gate_current_behavior_cost: current_behavior_cost,
            product_in_gate_outcome_metric: outcome_metric,
            product_in_gate_adoption_path: adoption_path,
            product_in_gate_unresolved_risks: unresolved_risks,
            product_in_gate_next_experiment: next_experiment,
            product_in_gate_review_by: review_by,
            product_in_gate_owner: owner,
            product_in_gate_persisted: persisted,
          },
        )
      }
    ProductInGateFailed(project) =>
      if project != engineering_project_name(model.engineering_project) {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            notice: "Product In-Gate 未写入。请补齐字段与证据要求，并确认登录、网关和 PostgreSQL 可用。",
          },
        )
      }
    RefreshPolicyRadar =>
      (
        load_policy_radar(emit),
        {
          ..model,
          policy_radar_state: "loading",
          policy_radar_error: "",
          notice: "正在读取经过认证网关的政策投影；旧数据不会被冒充为最新。",
        },
      )
    PolicyRadarLoaded(projection) =>
      (
        none,
        {
          ..model,
          policy_radar_state: "ready",
          policy_radar_projection: Some(projection),
          policy_radar_error: "",
          policy_last_audit_id: policy_projection_latest_audit(projection),
          notice: "政策投影已加载；来源采集状态、人工复核与商业门禁仍分别显示。",
        },
      )
    PolicyRadarFailed(message) =>
      (
        none,
        {
          ..model,
          policy_radar_state: "error",
          policy_radar_error: message,
          notice: "政策投影读取失败；界面没有回退到虚构的成功数据。",
        },
      )
    OpenPolicyReview(kind, target_id, default_decision) =>
      (
        none,
        {
          ..model,
          policy_review_kind: kind,
          policy_review_target_id: target_id,
          policy_review_decision: default_decision,
          policy_review_evidence: "",
          policy_review_pending: false,
          policy_radar_error: "",
        },
      )
    SelectPolicyReviewDecision(value) =>
      (none, { ..model, policy_review_decision: value, })
    InputPolicyReviewEvidence(value) =>
      (none, { ..model, policy_review_evidence: value, })
    SubmitPolicyReview =>
      if model.policy_review_pending {
        (none, model)
      } else if model.policy_review_kind.is_empty() ||
        model.policy_review_target_id.is_empty() ||
        model.policy_review_decision.is_empty() {
        (
          none,
          {
            ..model,
            policy_radar_error: "复核对象和结论不能为空。",
          },
        )
      } else if model.policy_review_evidence.trim().is_empty() {
        (
          none,
          {
            ..model,
            policy_radar_error: "必须填写可追溯的复核依据。",
          },
        )
      } else {
        (
          request_policy_review(emit, model),
          {
            ..model,
            policy_review_pending: true,
            policy_radar_error: "",
            notice: "正在写入政策复核命令和审计收据；成功响应前状态保持不变。",
          },
        )
      }
    CancelPolicyReview =>
      (
        none,
        {
          ..model,
          policy_review_kind: "",
          policy_review_target_id: "",
          policy_review_decision: "",
          policy_review_evidence: "",
          policy_review_pending: false,
          policy_radar_error: "",
        },
      )
    PolicyReviewSaved(target_id, audit_id) =>
      (
        load_policy_radar(emit),
        {
          ..model,
          policy_radar_state: "loading",
          policy_review_kind: "",
          policy_review_target_id: "",
          policy_review_decision: "",
          policy_review_evidence: "",
          policy_review_pending: false,
          policy_last_audit_id: audit_id,
          policy_last_review_target: target_id,
          policy_radar_error: "",
          notice: "政策复核已持久化并返回审计收据；正在刷新投影。",
        },
      )
    PolicyReviewFailed(message) =>
      (
        none,
        {
          ..model,
          policy_review_pending: false,
          policy_radar_error: message,
          notice: "政策复核被安全阻断；原有状态没有改变。",
        },
      )
    PreparePolicyValidationTask(opportunity_id) =>
      match
        policy_opportunity_by_id(model.policy_radar_projection, opportunity_id) {
        Some(opportunity) if policy_opportunity_actionable(
            model.policy_radar_projection,
            opportunity,
          ) => {
          let (_, prepared) = dispatch_prepare_draft(
            emit,
            model,
            "",
            "policy-intelligence",
            None,
            true,
          )
          match dispatch_active_draft(prepared) {
            Some(draft) =>
              dispatch_save_draft(emit, prepared, {
                ..draft,
                title: "政策验证 · " + opportunity.title,
                source_reference: Some(
                  "policy-change:" + opportunity.source_change_id,
                ),
                observed_problem: Some(opportunity.title),
                acceptance: opportunity.next_validation +
                "；记录反证、责任主体和是否继续。",
                begin_date: policy_today(),
                end_date: policy_validation_end_date(),
              })
            None => (none, model)
          }
        }
        _ =>
          (
            none,
            {
              ..model,
              notice: "政策机会不存在或关联变化尚未确认。",
            },
          )
      }
    OpenPolicyEvidence =>
      (
        none,
        {
          ..model,
          page: Evidence,
          mobile_nav: false,
          notice: if model.policy_last_audit_id.is_empty() {
            "尚无政策复核审计收据。"
          } else {
            "已定位最近的政策复核审计收据。"
          },
        },
      )
    RequestEngineeringRemediation =>
      (
        request_engineering_remediation(emit, model),
        {
          ..model,
          notice: "正在从已接受的审计发现创建整改项。",
        },
      )
    EngineeringRemediationCreated(project, selection) =>
      if project != model.engineering_project ||
        selection != model.products.selection {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            notice: "整改项已从已接受证据创建；没有接受证据时服务端会拒绝此操作。",
          },
        )
      }
    EngineeringAuditFailed(project, selection) =>
      if project != model.engineering_project ||
        selection != model.products.selection {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            engineering_audit_state: "failed",
            engineering_audit_id: "",
            engineering_task_id: "",
            notice: "候选测试请求失败；未生成任何结论。请确认已登录，并检查 MoonClaw daemon 与 MoonProj gateway。",
          },
        )
      }
    RecordDecision(label) =>
      (
        none,
        {
          ..model,
          notice: "已记录「\{label}」界面意图；证据写入 PostgreSQL 前不会产生正式业务影响。",
        },
      )
    ToggleMobileNav => (none, { ..model, mobile_nav: !model.mobile_nav, })
    DraftAction(action) => {
      let (command, next) = dispatch_draft_update(emit, action, model)
      match action {
        Restored(actor, text) => {
          let (compatibility, imported) = founder_after_draft_restore(
            emit, next, actor, text,
          )
          (@cmd.batch([command, compatibility]), imported)
        }
        _ => (command, next)
      }
    }
    ExportFounderPacket => founder_export_packet(emit, model)
    FounderPacketDownloaded(actor, epoch, selection, page, draft_id, ok) =>
      if actor != model.dispatch_task_actor_id ||
        actor != model.company_setup.actor ||
        epoch != model.company_setup.epoch ||
        model.company_setup.session_state != "ready" ||
        selection != model.dispatch_task_selection ||
        page != model.page ||
        draft_id != model.dispatch_draft_id {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            notice: if ok {
              "已下载 Markdown 工作包；可手动带入 MoonBook、MoonDesk 或 MoonFind。下载不等于自动同步、客户接受、发票或到账。"
            } else {
              "浏览器未完成 Markdown 工作包下载；当前草稿和正式记录未改写。"
            },
          },
        )
      }
    WorkPacketAction(action) => work_packet_update(emit, action, model)
    ResearchImportAction(action) => research_import_update(emit, action, model)
    OfferAction(action) => dispatch_offer_update(emit, model, action)
    ReplyAction(action) => dispatch_reply_update(emit, model, action)
    SelectDispatchTask(id) =>
      open_dispatch_task(emit, { ..model, dispatch_task_open_id: id, })
    OpenDispatchTaskForm =>
      dispatch_prepare_draft(emit, model, "", "", None, true)
    InputDispatchTaskWorkspace(value) =>
      (none, { ..model, dispatch_task_workspace: value, })
    InputDispatchTaskModel(value) =>
      (none, { ..model, dispatch_task_model: value, })
    InputDispatchTaskOpenId(value) =>
      (none, { ..model, dispatch_task_open_id: value, })
    InputDispatchTaskEvidenceId(value) =>
      (none, { ..model, dispatch_task_evidence_id: value, })
    CreateDispatchTask => dispatch_draft_update(emit, Create, model)
    SaveDispatchExecutionSettings =>
      if model.dispatch_run is Some(_) ||
        !model.dispatch_task_pending_action.is_empty() ||
        model.dispatch_task_workspace.trim().is_empty() ||
        model.dispatch_task_id.is_empty() {
        (none, model)
      } else {
        (
          save_dispatch_execution_settings(emit, model),
          {
            ..model,
            dispatch_task_pending_action: "settings",
            dispatch_task_note: "正在保存原生执行工作区。",
          },
        )
      }
    DispatchExecutionSettingsSaved(task_id, selection) =>
      if !dispatch_response_matches(model, task_id, selection) ||
        model.dispatch_task_pending_action != "settings" {
        (none, model)
      } else {
        (
          load_dispatch_task(emit, task_id, selection),
          { ..model, dispatch_task_pending_action: "load", },
        )
      }
    StartDispatchTask =>
      if !dispatch_can_start(model) {
        (none, model)
      } else if !dispatch_guidance_start_blocker(model).is_empty() {
        (
          none,
          {
            ..model,
            notice: dispatch_guidance_start_blocker(model),
            dispatch_task_note: dispatch_guidance_start_blocker(model),
          },
        )
      } else {
        let model = dispatch_guidance_capture_start(model)
        (
          request_dispatch_task_start(emit, model),
          {
            ..model,
            dispatch_task_pending_action: "start",
            dispatch_task_blocked: false,
            dispatch_task_note: "正在将正式任务交给 MoonClaw 原生执行；等待执行回执。",
          },
        )
      }
    SubmitDispatchTask =>
      if !dispatch_can_submit(model) {
        (none, model)
      } else if dispatch_report_evidence(model).is_empty() {
        (
          none,
          {
            ..model,
            dispatch_task_note: "提交验收前必须提供真实证据 ID 或可追溯引用。",
          },
        )
      } else {
        dispatch_begin_report(emit, model)
      }
    DispatchTaskSubmitted(task_id, selection, report_id, event_id, audit_id) =>
      if !dispatch_response_matches(model, task_id, selection) ||
        model.dispatch_task_pending_action != "submit" {
        (none, model)
      } else {
        (
          load_dispatch_task(emit, task_id, selection),
          {
            ..model,
            dispatch_task_report_id: report_id,
            dispatch_continuation: dispatch_record_acknowledged_report(
              model, report_id,
            ),
            dispatch_task_stage: "submitted",
            dispatch_task_pending_action: "load",
            dispatch_task_event_id: event_id,
            dispatch_task_audit_id: audit_id,
            dispatch_task_blocked: false,
            dispatch_task_note: "任务报告已持久化；结果等待具名人员接受，不会自动完成。",
            notice: "报告 \{report_id} 已提交验收；尚未形成接受事实。",
          },
        )
      }
    AcceptDispatchTask =>
      if !dispatch_can_accept_report(model) {
        (
          none,
          {
            ..model,
            notice: "本次未接受：" + dispatch_accept_report_blocker(model),
          },
        )
      } else {
        (
          request_dispatch_task_accept(emit, model),
          {
            ..model,
            dispatch_task_pending_action: "accept",
            dispatch_task_blocked: false,
            dispatch_task_note: "正在通过签名身份接受结果；命令被拒绝时任务会保持待验收。",
          },
        )
      }
    DispatchTaskAccepted(task_id, selection, event_id, audit_id) =>
      if !dispatch_response_matches(model, task_id, selection) ||
        model.dispatch_task_pending_action != "accept" {
        (none, model)
      } else {
        (
          load_dispatch_task(emit, task_id, selection),
          {
            ..model,
            dispatch_task_stage: "accepted",
            dispatch_task_pending_action: "load",
            dispatch_task_event_id: event_id,
            dispatch_task_audit_id: audit_id,
            dispatch_task_blocked: false,
            dispatch_task_note: "任务已通过正式状态命令标记为完成；该收据不产生现金、会计或税务影响。",
            notice: "任务已接受，Start → Submit → Accept 闭环完成。",
          },
        )
      }
    DispatchTaskCommandFailed(task_id, selection, action, detail) =>
      if !dispatch_response_matches(model, task_id, selection) {
        (none, model)
      } else {
        (
          none,
          {
            ..model,
            dispatch_task_pending_action: "",
            dispatch_task_blocked: true,
            dispatch_journey_read_state: "unconfirmed",
            dispatch_task_note: action + "失败：" + detail,
            notice: "未确认新的任务状态；可以刷新正式记录后重试。",
          },
        )
      }
    LoadDispatchSession => company_setup_update(emit, Refresh, model)
    DispatchSessionLoaded(actor) =>
      if actor == model.dispatch_task_actor_id && !actor.is_empty() {
        (none, model)
      } else {
        company_setup_session(emit, model, actor)
      }
    RestoreDispatchTask(task_id) => {
      let (_, model) = products_restore_route(emit, "", model)
      if task_id.is_empty() {
        (
          none,
          {
            ..model,
            page: Workspace,
            workspace: { ..model.workspace, job: "", },
            dispatch_task_form_open: false,
            dispatch_task_selection: model.dispatch_task_selection + 1,
            dispatch_task_id: "",
            dispatch_task_pending_action: "",
            dispatch_run: None,
            products: products_clear_preparation(model.products),
          },
        )
      } else {
        open_dispatch_task(
          emit,
          { ..model, dispatch_task_open_id: task_id, },
          push=false,
        )
      }
    }
    RestorePageRoute(page, task_id) =>
      restore_page_route(emit, page, task_id, model)
    RestoreProductPageRoute(page, task_id, product) =>
      restore_page_route(emit, page, task_id, model, product~)
    OpenDispatchTask => open_dispatch_task(emit, model)
    DeskHandoffAction(action) =>
      dispatch_desk_handoff_update(emit, action, model)
    LessonHandoffAction(action) =>
      dispatch_lesson_handoff_update(emit, model, action)
    GuidanceAction(action) => dispatch_guidance_update(emit, model, action)
    OutcomeAction(source, action) =>
      dispatch_outcome_update(emit, model, source, action)
    ContinuationAction(action) =>
      dispatch_continuation_update(emit, action, model)
    RefreshDispatchTask(task_id, selection) =>
      if task_id.is_empty() ||
        !dispatch_response_matches(model, task_id, selection) ||
        !model.dispatch_task_pending_action.is_empty() ||
        !dispatch_work_page(model) {
        (none, model)
      } else {
        (
          load_dispatch_task(emit, task_id, selection),
          {
            ..model,
            dispatch_task_pending_action: "load",
            dispatch_journey_read_state: "loading",
          },
        )
      }
    DispatchTaskLoaded(task_id, selection, snapshot) =>
      if !dispatch_response_matches(model, task_id, selection) ||
        snapshot.task_id != task_id {
        (none, model)
      } else if model.dispatch_continuation.task_id == task_id &&
        snapshot.revision < model.dispatch_continuation.revision {
        if model.dispatch_task_pending_action == "load" {
          (
            @cmd.delay(emit(RefreshDispatchTask(task_id, selection)), 200),
            {
              ..model,
              dispatch_task_pending_action: "",
              dispatch_journey_read_state: "older",
            },
          )
        } else {
          (none, model)
        }
      } else {
        let loaded = dispatch_guidance_after_read(
          apply_dispatch_snapshot(model, snapshot),
        )
        let (read, next) = if loaded.page == Objectives &&
          (
            loaded.today.project_id != snapshot.project_id ||
            loaded.today.scope != "project"
          ) {
          today_update(emit, Refresh, {
            ..loaded,
            today: {
              ..loaded.today,
              project_id: snapshot.project_id,
              scope: "project",
            },
          })
        } else if loaded.page == Objectives &&
          loaded.today.work_state == "ready" &&
          loaded.today.tasks.any(t => {
            t.id == snapshot.task_id && t.status != snapshot.state
          }) {
          today_update(emit, RefreshTasks, loaded)
        } else {
          (none, loaded)
        }
        (
          @cmd.batch([
            read,
            if delivery_coordinated(next) &&
              ["stopping", "stopped", "revising"].contains(
                delivery_control(next),
              ) {
              none
            } else {
              emit(ContinuationAction(Refresh))
            },
            if delivery_pollable(next) && dispatch_work_page(next) {
              @cmd.delay(
                emit(RefreshDispatchTask(task_id, selection)),
                if delivery_coordinated(next) {
                  5000
                } else {
                  2000
                },
              )
            } else {
              none
            },
          ]),
          next,
        )
      }
    OpenCompanyForm =>
      (
        emit(CompanySetupAction(Refresh)),
        { ..model, page: Company, company_form_open: true, mobile_nav: false, },
      )
    InputCompanyName(value) =>
      company_setup_update(emit, Input("company_name", value), model)
    SaveCompany => company_setup_update(emit, Save("company"), model)
    OpenMarketForm => (none, { ..model, market_form_open: true, })
    InputMarketParty(value) => (none, { ..model, market_party: value, })
    InputMarketProblem(value) => (none, { ..model, market_problem: value, })
    SaveMarket =>
      if model.market_party.trim().is_empty() ||
        model.market_problem.trim().is_empty() {
        (
          none,
          {
            ..model,
            notice: "请填写客户或买方，以及需要验证的问题。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            market_saved: true,
            market_form_open: false,
            notice: "客户机会已加入当前界面会话，尚未产生合同或收入事实。",
          },
        )
      }
    OpenWorkForm => (none, { ..model, work_form_open: true, })
    InputWorkTitle(value) => (none, { ..model, work_title: value, })
    InputWorkAcceptance(value) => (none, { ..model, work_acceptance: value, })
    SaveWork =>
      if model.work_title.trim().is_empty() ||
        model.work_acceptance.trim().is_empty() {
        (
          none,
          {
            ..model,
            notice: "工作项需要名称和可检查的验收标准。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            work_saved: true,
            work_stage: 0,
            work_form_open: false,
            notice: "工作项已加入当前界面会话，尚未授权智能体执行。",
          },
        )
      }
    StartWork =>
      if can_start_work(model) {
        (
          none,
          {
            ..model,
            work_stage: 1,
            notice: "工作已进入执行；完成声明不会自动构成验收。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            notice: "请先建立工作流并保存可验收工作。",
          },
        )
      }
    SubmitWork =>
      if can_submit_work(model) {
        (
          none,
          {
            ..model,
            work_stage: 2,
            notice: "结果已提交验收；尚未被公司接受或产生结算事实。",
          },
        )
      } else {
        (
          none,
          { ..model, notice: "只有进行中的工作可以提交验收。", },
        )
      }
    AcceptWork =>
      if can_accept_work(model) {
        (
          none,
          {
            ..model,
            work_stage: 3,
            notice: "交付已按当前界面标准接受；正式证据仍需写入 PostgreSQL。",
          },
        )
      } else {
        (none, { ..model, notice: "只有待验收结果可以被接受。", })
      }
    OpenCommitmentForm => (none, { ..model, commitment_form_open: true, })
    InputCommitmentTitle(value) => (none, { ..model, commitment_title: value, })
    InputCommitmentCounterparty(value) =>
      (none, { ..model, commitment_counterparty: value, })
    SaveCommitment =>
      if model.commitment_title.trim().is_empty() ||
        model.commitment_counterparty.trim().is_empty() {
        (none, { ..model, notice: "承诺需要事项和交易对手。", })
      } else {
        (
          none,
          {
            ..model,
            commitment_saved: true,
            commitment_stage: 0,
            commitment_form_open: false,
            notice: "承诺草案已加入当前界面会话，尚未签署或产生会计影响。",
          },
        )
      }
    ApproveCommitment =>
      if can_approve_commitment(model) {
        (
          none,
          {
            ..model,
            commitment_stage: 1,
            notice: "承诺草案已记录为内部批准；这不是签署或对外承诺。",
          },
        )
      } else {
        (
          none,
          { ..model, notice: "批准前需要承诺草案和授权台账。", },
        )
      }
    SignCommitment =>
      if can_sign_commitment(model) {
        (
          none,
          {
            ..model,
            commitment_stage: 2,
            notice: "界面已记录签署状态；本地会话不构成真实电子签名或法律承诺。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            notice: "签署状态需要已批准草案和公司档案。",
          },
        )
      }
    CompleteCommitment =>
      if can_complete_commitment(model) {
        (
          none,
          {
            ..model,
            commitment_stage: 3,
            notice: "履约状态已与被接受的交付关联；尚未结算或入账。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            notice: "履约完成需要已签署承诺和已接受交付。",
          },
        )
      }
    SettleCommitment =>
      if can_settle_commitment(model) {
        (
          none,
          {
            ..model,
            commitment_stage: 4,
            notice: "界面已记录结算检查点；没有银行流水或真实资金移动。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            notice: "结算检查点需要履约完成和现金银行台账。",
          },
        )
      }
    RecognizeCommitment =>
      if can_recognize_commitment(model) {
        (
          none,
          {
            ..model,
            commitment_stage: 5,
            notice: "界面已记录入账检查点；没有生成或过账任何正式会计分录。",
          },
        )
      } else {
        (
          none,
          {
            ..model,
            notice: "入账检查点需要结算状态和基础账簿。",
          },
        )
      }
    SetupConstitution =>
      (
        none,
        {
          ..model,
          constitution_ready: true,
          notice: "章程与保留事项台账已在当前界面会话中启用；正式规则仍需负责人签发。",
        },
      )
    SetupAuthority =>
      (
        none,
        {
          ..model,
          authority_ready: true,
          notice: "授权台账已在当前界面会话中启用；任何授权仍需明确主体、范围、期限和撤销条件。",
        },
      )
    SetupResourceRegister =>
      (
        none,
        {
          ..model,
          resource_register_ready: true,
          notice: "资源台账已在当前界面会话中启用；尚未登记任何资产、账户或数据资源。",
        },
      )
    SetupOfferRegister =>
      (
        none,
        {
          ..model,
          offer_register_ready: true,
          notice: "报价与续购台账已启用；尚未生成报价、订单或收入事实。",
        },
      )
    SetupWorkflow =>
      (
        none,
        {
          ..model,
          workflow_ready: true,
          notice: "交付工作流已启用；执行、验收与变更仍保持为不同状态。",
        },
      )
    SetupAttention =>
      (
        none,
        {
          ..model,
          attention_ready: true,
          notice: "负责人关注预算已启用；尚未记录审批、例外、返工或上下文恢复时间。",
        },
      )
    SetupProcurement =>
      (
        none,
        {
          ..model,
          procurement_ready: true,
          notice: "供应商与采购台账已启用；尚未选择供应商或形成采购承诺。",
        },
      )
    SetupExpenseRegister =>
      (
        none,
        {
          ..model,
          expense_register_ready: true,
          notice: "费用、借款与报销台账已启用；尚未产生付款、报销或会计影响。",
        },
      )
    SetupBudget =>
      (
        none,
        {
          ..model,
          budget_ready: true,
          notice: "预算与资源保留台账已启用；尚未批准额度、预留资源或消耗预算。",
        },
      )
    SetupLedger =>
      (
        none,
        {
          ..model,
          ledger_ready: true,
          notice: "基础账簿界面已启用；正式科目、期间和期初余额仍需财务负责人确认。",
        },
      )
    SetupTreasury =>
      (
        none,
        {
          ..model,
          treasury_ready: true,
          notice: "现金与银行台账已启用；尚未连接账户、导入流水或释放付款。",
        },
      )
    SetupTax =>
      (
        none,
        {
          ..model,
          tax_ready: true,
          notice: "税务义务台账已启用；税种、申报、支付与对账仍需正式配置。",
        },
      )
    SetupFinancing =>
      (
        none,
        {
          ..model,
          financing_ready: true,
          notice: "融资台账已启用；尚未建立授信、提款、还款或契约记录。",
        },
      )
    SetupInvestment =>
      (
        none,
        {
          ..model,
          investment_ready: true,
          notice: "原生投资台账已启用；Moonfish 分析只能形成建议，不能直接交易。",
        },
      )
    SetupControls =>
      (
        none,
        {
          ..model,
          control_ready: true,
          notice: "控制、风险与事件台账已启用；尚未记录风险、例外或事件。",
        },
      )
    SetupLearning =>
      (
        none,
        {
          ..model,
          learning_ready: true,
          notice: "复盘与程序台账已启用；尚未提升或废止任何标准程序。",
        },
      )
    SetupContinuity =>
      (
        none,
        {
          ..model,
          continuity_ready: true,
          notice: "连续性清单已启用；备份恢复和受托人演练仍需真实验证。",
        },
      )
    DismissNotice => (none, { ..model, notice: "", })
  }
}
