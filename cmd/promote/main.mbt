///|
pub(all) suberror PromotionError {
  InvalidArguments
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Erp(@erp.ErpImportError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise PromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise PromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise PromotionError {
  match value {
    Object(value) => value
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn required(obj : Map[String, Json], key : String) -> Json raise PromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise PromotionError::InvalidInput
  }
}

///|
fn string_value(value : Json) -> String raise PromotionError {
  match value {
    String(value) => value
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise PromotionError {
  string_value(required(obj, key))
}

///|
fn optional_string(
  obj : Map[String, Json],
  key : String,
) -> String? raise PromotionError {
  match obj.get(key) {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise PromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn optional_int(
  obj : Map[String, Json],
  key : String,
) -> Int? raise PromotionError {
  match obj.get(key) {
    None | Some(Null) => None
    Some(Number(value, ..)) if value == value.trunc() => Some(value.to_int())
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise PromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn required_object(
  obj : Map[String, Json],
  key : String,
) -> Map[String, Json] raise PromotionError {
  object(required(obj, key))
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise PromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn strings_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn ints_json(values : Array[Int]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::number(value.to_double(), repr=value.to_string()))
  }
  Json::array(encoded)
}

///|
fn typed_evidence_class_allowed(
  source_table : String,
  evidence_class : String,
) -> Bool {
  (source_table == "jd_task" && evidence_class == "task_record_snapshot") ||
  (source_table == "jd_task_report" && evidence_class == "task_progress_report") ||
  (
    source_table == "wf_step_assignee" &&
    evidence_class == "workflow_assignment"
  ) ||
  (
    source_table == "proj_lifecycle_instance" &&
    evidence_class == "lifecycle_instance_history"
  ) ||
  (
    source_table == "proj_lifecycle_stage" &&
    evidence_class == "lifecycle_stage_catalog"
  ) ||
  (
    source_table == "vys_proceeding" &&
    evidence_class == "expense_proceeding_catalog"
  )
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  max_amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id,
    capability,
    scope,
    max_amount_minor,
    active: true,
  }
}

///|
fn run(plan_path : String, output_path : String) -> Unit raise PromotionError {
  let root = object(read_json(plan_path))
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = required_array(root, "items")
  let actor_id = "migration"
  let business_units : Array[@erp.LegacyBusinessUnitRow] = []
  let business_unit_mappings : Array[@erp.LegacyBusinessUnitMapping] = []
  let business_unit_grants : Array[@foundation.AuthorityGrant] = []
  let user_rows : Array[@erp.LegacyUserRow] = []
  let user_mappings : Array[@erp.LegacyUserMapping] = []
  let user_grants : Array[@foundation.AuthorityGrant] = []
  let audit_rows : Array[@erp.LegacyAuditRow] = []
  let audit_mappings : Array[@erp.LegacyAuditMapping] = []
  let audit_grants : Array[@foundation.AuthorityGrant] = []
  let parameter_rows : Array[Array[@erp.LegacyParameterRow]] = []
  let parameter_mappings : Array[@erp.LegacyParameterMapping] = []
  let parameter_grants : Array[@foundation.AuthorityGrant] = []
  let typed_evidence_ids : Array[String] = []
  let projects : Array[@erp.LegacyProjectRow] = []
  let project_mappings : Array[@erp.LegacyProjectMapping] = []
  let project_grants : Array[@foundation.AuthorityGrant] = []
  let contracts : Array[@erp.LegacyContractRow] = []
  let contract_mappings : Array[@erp.LegacyContractMapping] = []
  let contract_grants : Array[@foundation.AuthorityGrant] = []
  let commitment_state_ids : Array[String] = []
  let commitment_state_targets : Array[@commitment.CommitmentState] = []
  let payment_application_rows : Array[@erp.LegacyPaymentApplicationRow] = []
  let payment_application_commitment_ids : Array[String] = []
  let payment_application_currencies : Array[String] = []
  let milestone_rows : Array[@erp.LegacyMilestoneRow] = []
  let milestone_commitment_ids : Array[String] = []
  let costs : Array[@erp.LegacyCostPromotionRow] = []
  let advances : Array[@erp.LegacyAdvanceRow] = []
  let advance_mappings : Array[@erp.LegacyAdvanceMapping] = []
  let advance_grants : Array[@foundation.AuthorityGrant] = []
  let advance_offset_rows : Array[@erp.LegacyAdvanceOffsetRow] = []
  let advance_offset_mappings : Array[@erp.LegacyAdvanceOffsetMapping] = []
  let advance_offset_grants : Array[@foundation.AuthorityGrant] = []
  let advance_offset_ids : Array[String] = []
  let advance_offset_amounts : Array[Int] = []
  let workflow_definitions : Array[@erp.LegacyWorkflowDefinitionRow] = []
  let workflow_steps : Array[@erp.LegacyWorkflowStepRow] = []
  let workflow_capabilities : Array[@erp.LegacyWorkflowCapability] = []
  let lifecycle_project_ids : Array[String] = []
  let lifecycle_rows : Array[Array[@erp.LegacyLifecycleInstanceRow]] = []
  let lifecycle_mappings : Array[Array[@erp.LegacyLifecycleMapping]] = []
  let lifecycle_grants : Array[@foundation.AuthorityGrant] = []
  let lifecycle_final_stages : Array[String] = []
  let task_rows : Array[Array[@erp.LegacyTaskRow]] = []
  let task_grants : Array[@foundation.AuthorityGrant] = []
  let task_plan_project_ids : Array[String] = []
  let task_plan_task_counts : Array[Int] = []
  let task_plans : Array[@project.ProjectPlan] = []
  let task_state_project_ids : Array[String] = []
  let task_state_rows : Array[Array[@erp.LegacyTaskRow]] = []
  let task_state_start_grants : Array[@foundation.AuthorityGrant] = []
  let task_state_progress_grants : Array[@foundation.AuthorityGrant] = []
  let task_state_block_grants : Array[@foundation.AuthorityGrant] = []
  let investment_versions : Array[@erp.LegacyInvestmentVersionRow] = []
  let investment_indexes : Array[@erp.LegacyInvestmentIndexRow] = []
  let investment_mappings : Array[@erp.LegacyInvestmentModelMapping] = []
  let accepted_items : Array[Json] = []
  for item_value in items {
    let item = object(item_value)
    let disposition = required_string(item, "disposition")
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    let target_type = required_string(item, "target_type")
    let target_id = required_string(item, "target_id")
    if disposition != "ready_for_domain_import" {
      raise PromotionError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = required_object(item, "target_candidate")
    accepted_items.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string(target_type),
        "target_id": Json::string(target_id),
        "target_candidate": candidate,
      }),
    )
    match target_type {
      "organization_unit" => {
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        business_units.push({
          bu_guid: required_string(candidate, "unit_id"),
          parent_guid: optional_string(candidate, "parent_id"),
          bu_code: required_string(candidate, "code"),
          bu_name: required_string(candidate, "name"),
          bu_type: required_string(candidate, "kind"),
        })
        business_unit_mappings.push({
          bu_guid: required_string(candidate, "unit_id"),
          principal_id,
          authority_scope: scope,
        })
        business_unit_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "organization:create",
            scope,
            0L,
          ),
        )
      }
      "user_account" => {
        let user_id = required_string(candidate, "user_id")
        let principal_id = required_string(candidate, "principal_id")
        let bu_id = required_string(candidate, "business_unit_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, user_id)
        user_rows.push({
          user_id,
          user_code: required_string(candidate, "user_code"),
          user_name: required_string(candidate, "display_name"),
          emp_name: Some(required_string(candidate, "display_name")),
          super_user: false,
          bu_guid: Some(bu_id),
          dept_guid: optional_string(candidate, "department_id"),
          enabled: required_bool(candidate, "enabled"),
          fail_login_count: 0,
          last_login_time: None,
        })
        user_mappings.push({ user_id, principal_id, authority_scope: scope })
        user_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "identity:user:create",
            scope,
            0L,
          ),
        )
      }
      "audit_record" => {
        let audit_id = required_string(candidate, "audit_id")
        let actor_id = required_string(candidate, "user_id")
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "scope")
        project_id_check(target_id, audit_id)
        audit_rows.push({
          log_id: audit_id,
          user_id: Some(actor_id),
          action: required_string(candidate, "action"),
          target_type: None,
          target_id: None,
          ip: None,
          created_at: required_string(candidate, "created_at"),
        })
        audit_mappings.push({
          audit_id,
          principal_id,
          scope,
          target_type: required_string(candidate, "target_type"),
          target_id: required_string(candidate, "target_id"),
          outcome: required_string(candidate, "outcome"),
        })
        audit_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "audit:append",
            scope,
            0L,
          ),
        )
      }
      "parameter_dictionary" => {
        let parameter_name = required_string(candidate, "parameter_name")
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, parameter_name)
        let options : Array[@erp.LegacyParameterRow] = []
        for option_value in required_array(candidate, "options") {
          let option = object(option_value)
          options.push({
            parameter_id: required_string(option, "parameter_id"),
            parameter_name: required_string(option, "parameter_name"),
            parameter_code: required_string(option, "parameter_code"),
            parameter_value: required_string(option, "parameter_value"),
            display_order: required_int64(option, "display_order").to_int(),
            enabled: required_bool(option, "enabled"),
          })
        }
        parameter_rows.push(options)
        parameter_mappings.push({ parameter_name, principal_id, scope })
        parameter_grants.push(
          grant(
            "promotion/" + source_id + "/create",
            principal_id,
            actor_id,
            "parameter:create",
            scope,
            0L,
          ),
        )
        parameter_grants.push(
          grant(
            "promotion/" + source_id + "/edit",
            principal_id,
            actor_id,
            "parameter:edit",
            scope,
            0L,
          ),
        )
      }
      "typed_evidence" => {
        let evidence_id = required_string(candidate, "evidence_id")
        let evidence_class = required_string(candidate, "evidence_class")
        let candidate_source_table = required_string(candidate, "source_table")
        let candidate_source_id = required_string(candidate, "source_id")
        let _ = required_object(candidate, "evidence_payload")
        if evidence_id != target_id ||
          candidate_source_table != source_table ||
          candidate_source_id != source_id {
          raise PromotionError::InvalidInput
        }
        if !typed_evidence_class_allowed(source_table, evidence_class) {
          raise PromotionError::InvalidInput
        }
        if required_string(candidate, "evidence_policy") !=
          "typed-preservation-only" {
          raise PromotionError::InvalidInput
        }
        typed_evidence_ids.push(evidence_id)
      }
      "project" => {
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, required_string(candidate, "project_id"))
        projects.push({
          proj_guid: required_string(candidate, "project_id"),
          bu_guid: required_string(candidate, "business_unit_id"),
          proj_code: required_string(candidate, "code"),
          proj_name: required_string(candidate, "name"),
        })
        project_mappings.push({
          project_id: target_id,
          principal_id,
          authority_scope: scope,
        })
        project_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "project:create",
            scope,
            0L,
          ),
        )
      }
      "commitment" => {
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "project_scope")
        let amount = required_int64(candidate, "amount_minor")
        contracts.push({
          contract_guid: required_string(candidate, "commitment_id"),
          bu_guid: required_string(candidate, "business_unit_id"),
          proj_guid: project_id_from_scope(scope),
          provider_guid: required_string(candidate, "counterparty_id"),
          ht_amount_minor: amount,
          currency: required_string(candidate, "currency"),
        })
        contract_mappings.push({
          contract_id: target_id,
          principal_id,
          project_scope: scope,
          counterparty_id: required_string(candidate, "counterparty_id"),
        })
        contract_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "commitment:create",
            scope,
            amount,
          ),
        )
      }
      "commitment_state" => {
        commitment_state_ids.push(required_string(candidate, "commitment_id"))
        commitment_state_targets.push(
          commitment_state(required_string(candidate, "target_state")),
        )
      }
      "dynamic_cost" => {
        let components = required_object(candidate, "components_minor")
        costs.push({
          cost_id: required_string(candidate, "cost_id"),
          project_scope: required_string(candidate, "project_scope"),
          cost: {
            currency: required_string(candidate, "currency"),
            direct_minor: required_int64(components, "direct"),
            indirect_minor: required_int64(components, "indirect"),
            contingency_minor: required_int64(components, "contingency"),
            other_minor: required_int64(components, "other"),
          },
        })
      }
      "employee_advance" => {
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        let amount = required_int64(candidate, "amount_minor")
        advances.push({
          loan_guid: required_string(candidate, "advance_id"),
          bu_guid: required_string(candidate, "business_unit_id"),
          employee_guid: required_string(candidate, "employee_id"),
          amount_minor: amount,
          currency: required_string(candidate, "currency"),
        })
        advance_mappings.push({
          advance_id: target_id,
          principal_id,
          employee_id: required_string(candidate, "employee_id"),
          authority_scope: scope,
        })
        advance_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "advance:create",
            scope,
            amount,
          ),
        )
      }
      "employee_advance_offset" => {
        let offset_id = required_string(candidate, "offset_id")
        let advance_id = required_string(candidate, "advance_id")
        let principal_id = required_string(candidate, "principal_id")
        let employee_id = required_string(candidate, "employee_id")
        let scope = required_string(candidate, "authority_scope")
        let amount = required_int64(candidate, "amount_minor")
        advance_offset_rows.push({
          offset_guid: offset_id,
          loan_guid: advance_id,
          amount_minor: amount,
          offset_date: required_string(candidate, "offset_date"),
          related_expense_guid: optional_string(candidate, "related_expense_id"),
          operator_guid: required_string(candidate, "operator_id"),
        })
        advance_offset_mappings.push({
          offset_id,
          principal_id,
          employee_id,
          authority_scope: scope,
        })
        advance_offset_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "advance:offset",
            scope,
            amount,
          ),
        )
        advance_offset_ids.push(offset_id)
        advance_offset_amounts.push(amount.to_int())
      }
      "workflow_definition" => {
        let process_id = required_string(candidate, "process_id")
        let steps = required_array(candidate, "steps")
        workflow_definitions.push({
          process_guid: process_id,
          process_key: required_string(candidate, "process_key"),
          process_name: required_string(candidate, "process_name"),
          biz_type: required_string(candidate, "biz_type"),
          active: true,
          mandatory: true,
          bu_guid: None,
        })
        for step_value in steps {
          let step = object(step_value)
          let step_id = required_string(step, "step_id")
          workflow_steps.push({
            step_guid: step_id,
            process_guid: process_id,
            step_key: required_string(step, "step_key"),
            step_order: required_int64(step, "step_order").to_int(),
            step_type: required_int64(step, "step_type").to_int(),
            step_name: required_string(step, "step_name"),
            threshold: required_int64(step, "threshold").to_int(),
            remind_days: optional_int(step, "remind_days"),
            warn_days: optional_int(step, "warn_days"),
          })
          workflow_capabilities.push({
            step_guid: step_id,
            capability: required_string(step, "capability"),
          })
        }
      }
      "project_lifecycle" => {
        let project_id = required_string(candidate, "project_id")
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, project_id)
        let rows : Array[@erp.LegacyLifecycleInstanceRow] = []
        for row_value in required_array(candidate, "rows") {
          let row = object(row_value)
          rows.push({
            instance_id: required_string(row, "instance_id"),
            proj_guid: required_string(row, "proj_guid"),
            stage_code: required_string(row, "stage_code"),
            planned_start: optional_string(row, "planned_start"),
            planned_end: optional_string(row, "planned_end"),
            actual_start: optional_string(row, "actual_start"),
            actual_end: optional_string(row, "actual_end"),
            status: required_string(row, "status"),
            progress_bps: required_int64(row, "progress_bps"),
          })
        }
        let mappings : Array[@erp.LegacyLifecycleMapping] = []
        for mapping_value in required_array(candidate, "stage_mappings") {
          let mapping = object(mapping_value)
          mappings.push({
            source_code: required_string(mapping, "source_code"),
            target_stage: lifecycle_stage(
              required_string(mapping, "target_stage"),
            ),
          })
        }
        lifecycle_project_ids.push(project_id)
        lifecycle_rows.push(rows)
        lifecycle_mappings.push(mappings)
        lifecycle_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "project:advance",
            scope,
            0L,
          ),
        )
      }
      "project_task_plan" => {
        let project_id = required_string(candidate, "project_id")
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, project_id)
        let rows : Array[@erp.LegacyTaskRow] = []
        for row_value in required_array(candidate, "rows") {
          let row = object(row_value)
          rows.push({
            task_guid: required_string(row, "task_guid"),
            proj_guid: required_string(row, "proj_guid"),
            bu_guid: required_string(row, "bu_guid"),
            parent_task_guid: optional_string(row, "parent_task_guid"),
            task_code: optional_string(row, "task_code"),
            task_name: required_string(row, "task_name"),
            task_type: required_string(row, "task_type"),
            plan_begin_date: required_string(row, "plan_begin_date"),
            plan_end_date: required_string(row, "plan_end_date"),
            actual_begin_date: optional_string(row, "actual_begin_date"),
            actual_end_date: optional_string(row, "actual_end_date"),
            progress_bps: required_int64(row, "progress_bps"),
            owner_guid: optional_string(row, "owner_guid"),
            status: required_string(row, "status"),
            sort_order: required_int64(row, "sort_order").to_int(),
          })
        }
        task_plan_project_ids.push(project_id)
        task_rows.push(rows)
        task_grants.push(
          grant(
            "promotion/" + source_id,
            principal_id,
            actor_id,
            "project:task:add",
            scope,
            0L,
          ),
        )
      }
      "project_task_state" => {
        let project_id = required_string(candidate, "project_id")
        let principal_id = required_string(candidate, "principal_id")
        let scope = required_string(candidate, "authority_scope")
        project_id_check(target_id, project_id)
        let rows : Array[@erp.LegacyTaskRow] = []
        for row_value in required_array(candidate, "rows") {
          let row = object(row_value)
          rows.push({
            task_guid: required_string(row, "task_guid"),
            proj_guid: required_string(row, "proj_guid"),
            bu_guid: required_string(row, "bu_guid"),
            parent_task_guid: optional_string(row, "parent_task_guid"),
            task_code: optional_string(row, "task_code"),
            task_name: required_string(row, "task_name"),
            task_type: required_string(row, "task_type"),
            plan_begin_date: required_string(row, "plan_begin_date"),
            plan_end_date: required_string(row, "plan_end_date"),
            actual_begin_date: optional_string(row, "actual_begin_date"),
            actual_end_date: optional_string(row, "actual_end_date"),
            progress_bps: required_int64(row, "progress_bps"),
            owner_guid: optional_string(row, "owner_guid"),
            status: required_string(row, "status"),
            sort_order: required_int64(row, "sort_order").to_int(),
          })
        }
        task_state_project_ids.push(project_id)
        task_state_rows.push(rows)
        task_state_start_grants.push(
          grant(
            "promotion/" + source_id + "/start",
            principal_id,
            actor_id,
            "project:task:start",
            scope,
            0L,
          ),
        )
        task_state_progress_grants.push(
          grant(
            "promotion/" + source_id + "/progress",
            principal_id,
            actor_id,
            "project:task:progress",
            scope,
            0L,
          ),
        )
        task_state_block_grants.push(
          grant(
            "promotion/" + source_id + "/block",
            principal_id,
            actor_id,
            "project:task:block",
            scope,
            0L,
          ),
        )
      }
      "investment_model" => {
        let version = required_object(candidate, "version")
        let principal_id = required_string(candidate, "principal_id")
        let version_scope = required_string(candidate, "authority_scope")
        let version_id = required_string(version, "version_guid")
        let project_id = required_string(version, "proj_guid")
        investment_versions.push({
          version_guid: version_id,
          proj_guid: project_id,
          bu_guid: required_string(version, "bu_guid"),
          version_name: required_string(version, "version_name"),
          version_no: required_int64(version, "version_no").to_int(),
          current: required_bool(version, "current"),
          created_by: required_string(version, "created_by"),
          created_at: required_string(version, "created_at"),
          remark: optional_string(version, "remark"),
        })
        for index_value in required_array(candidate, "indexes") {
          let index = object(index_value)
          investment_indexes.push({
            index_guid: required_string(index, "index_guid"),
            version_guid: required_string(index, "version_guid"),
            proj_guid: required_string(index, "proj_guid"),
            dimension: required_string(index, "dimension"),
            full_code: required_string(index, "full_code"),
            index_name: required_string(index, "index_name"),
            parent_code: optional_string(index, "parent_code"),
            unit: optional_string(index, "unit"),
            value_repr: optional_string(index, "value_repr"),
            remark: optional_string(index, "remark"),
            sort_order: required_int64(index, "sort_order").to_int(),
          })
        }
        let version_grant = grant(
          "promotion/" + source_id + "/version",
          principal_id,
          actor_id,
          "investment:model:version:create",
          version_scope,
          0L,
        )
        let index_grant = grant(
          "promotion/" + source_id + "/index",
          principal_id,
          actor_id,
          "investment:model:index:add",
          version_scope,
          0L,
        )
        investment_mappings.push({
          version_id,
          principal_id,
          version_grant,
          index_grant,
        })
      }
      "payment_application" => {
        let application = required_object(candidate, "application")
        let commitment_id = required_string(candidate, "commitment_id")
        payment_application_rows.push({
          apply_guid: required_string(application, "apply_guid"),
          apply_code: required_string(application, "apply_code"),
          contract_guid: required_string(application, "contract_guid"),
          plan_guid: optional_string(application, "plan_guid"),
          apply_class: required_int64(application, "apply_class").to_int(),
          apply_type_code: optional_string(application, "apply_type_code"),
          apply_state: required_string(application, "apply_state"),
          pay_state: required_string(application, "pay_state"),
          subject: optional_string(application, "subject"),
          apply_dept_guid: required_string(application, "apply_dept_guid"),
          applied_by: required_string(application, "applied_by"),
          apply_date: required_string(application, "apply_date"),
          amount_minor: required_int64(application, "amount_minor"),
          amount_bz_minor: required_int64(application, "amount_bz_minor"),
          proj_guid: optional_string(application, "proj_guid"),
          proj_type: optional_string(application, "proj_type"),
          contract_class: optional_int(application, "contract_class"),
          bu_guid: required_string(application, "bu_guid"),
        })
        payment_application_commitment_ids.push(commitment_id)
        payment_application_currencies.push(
          required_string(candidate, "currency"),
        )
      }
      "contract_milestone" => {
        let milestone = required_object(candidate, "milestone")
        let commitment_id = required_string(candidate, "commitment_id")
        milestone_rows.push({
          milestone_guid: required_string(milestone, "milestone_guid"),
          contract_guid: required_string(milestone, "contract_guid"),
          sequence: required_int64(milestone, "sequence").to_int(),
          node_name: required_string(milestone, "node_name"),
          trigger_type: required_string(milestone, "trigger_type"),
          plan_amount_minor: required_int64(milestone, "plan_amount_minor"),
          plan_pct_bps: required_int64(milestone, "plan_pct_bps"),
        })
        milestone_commitment_ids.push(commitment_id)
      }
      _ => raise PromotionError::InvalidInput
    }
  }
  let registry = @erp.import_business_units(
    business_units,
    business_unit_mappings,
    business_unit_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_users = @erp.import_users(
    user_rows,
    user_mappings,
    user_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_audits = @erp.import_audit_records(
    audit_rows, audit_mappings, audit_grants,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_parameters = @erp.import_parameter_dictionaries(
    parameter_rows,
    parameter_mappings,
    parameter_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_projects = @erp.import_projects(
    projects,
    project_mappings,
    project_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_contracts = @erp.import_contracts(
    contracts,
    contract_mappings,
    contract_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let promoted_commitments = imported_contracts.copy()
  for index in 0..<commitment_state_ids.length() {
    let commitment_id = commitment_state_ids[index]
    let mut found_index : Int? = None
    for position in 0..<promoted_commitments.length() {
      if promoted_commitments[position].commitment_id == commitment_id {
        found_index = Some(position)
      }
    }
    let position = match found_index {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let commitment = promoted_commitments[position]
    let transitioned = @erp.import_commitment_state(
      commitment,
      commitment_state_targets[index],
      commitment_transition_grants("promotion/" + commitment_id, commitment),
      actor_id~,
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    promoted_commitments[position] = transitioned
  }
  let payment_application_ids : Array[String] = []
  let milestone_ids : Array[String] = []
  for index in 0..<milestone_rows.length() {
    let commitment_id = milestone_commitment_ids[index]
    let mut found : @commitment.Commitment? = None
    for commitment in promoted_commitments {
      if commitment.commitment_id == commitment_id {
        found = Some(commitment)
      }
    }
    let commitment = match found {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let milestone = @erp.import_milestone(
      milestone_rows[index],
      commitment,
      actor_id~,
      grant=grant(
        "promotion/" + milestone_rows[index].milestone_guid,
        commitment.principal_id,
        actor_id,
        "milestone:create",
        commitment.project_scope,
        milestone_rows[index].plan_amount_minor,
      ),
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    milestone_ids.push(milestone.milestone_id)
  }
  for index in 0..<payment_application_rows.length() {
    let commitment_id = payment_application_commitment_ids[index]
    let mut found : @commitment.Commitment? = None
    for commitment in promoted_commitments {
      if commitment.commitment_id == commitment_id {
        found = Some(commitment)
      }
    }
    let commitment = match found {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let payment = @erp.import_payment_application(
      payment_application_rows[index],
      commitment,
      currency=payment_application_currencies[index],
      actor_id~,
      grant=grant(
        "promotion/" + payment_application_rows[index].apply_guid,
        commitment.principal_id,
        actor_id,
        "settlement:request",
        commitment.project_scope,
        payment_application_rows[index].amount_minor,
      ),
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    payment_application_ids.push(payment.settlement_id)
  }
  let imported_costs = @erp.import_costs(costs) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_advances = @erp.import_advances(
    advances,
    advance_mappings,
    advance_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let promoted_advances = @erp.import_advance_offsets(
    imported_advances,
    advance_offset_rows,
    advance_offset_mappings,
    advance_offset_grants,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let imported_workflows = @erp.import_workflow_definitions(
    workflow_definitions, workflow_steps, workflow_capabilities,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  for index in 0..<task_plan_project_ids.length() {
    let project_id = task_plan_project_ids[index]
    let mut found : @project.Project? = None
    for project in imported_projects {
      if project.project_id == project_id {
        found = Some(project)
      }
    }
    let project = match found {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let plan = @erp.import_project_tasks(
      project,
      task_rows[index],
      actor_id~,
      grant=task_grants[index],
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    task_plan_task_counts.push(plan.tasks.length())
    task_plans.push(plan)
  }
  let task_state_project_counts : Array[Int] = []
  for index in 0..<task_state_project_ids.length() {
    let project_id = task_state_project_ids[index]
    let mut found : @project.ProjectPlan? = None
    for plan in task_plans {
      if plan.project_id == project_id {
        found = Some(plan)
      }
    }
    let plan = match found {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let replayed = @erp.import_project_task_states(
      plan,
      task_state_rows[index],
      actor_id~,
      start_grant=task_state_start_grants[index],
      progress_grant=task_state_progress_grants[index],
      block_grant=task_state_block_grants[index],
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    task_state_project_counts.push(replayed.tasks.length())
  }
  let imported_investment_models = @erp.import_investment_models(
    investment_versions,
    investment_indexes,
    investment_mappings,
    actor_id~,
  ) catch {
    error => raise PromotionError::Erp(error)
  }
  let promoted_investment_ids : Array[String] = []
  let promoted_investment_counts : Array[Int] = []
  for model in imported_investment_models {
    promoted_investment_ids.push(model.version.version_id)
    promoted_investment_counts.push(model.indexes.length())
  }
  for index in 0..<lifecycle_project_ids.length() {
    let project_id = lifecycle_project_ids[index]
    let mut found : @project.Project? = None
    for project in imported_projects {
      if project.project_id == project_id {
        found = Some(project)
      }
    }
    let project = match found {
      Some(value) => value
      None => raise PromotionError::InvalidInput
    }
    let advanced = @erp.import_project_lifecycle(
      project,
      lifecycle_rows[index],
      lifecycle_mappings[index],
      actor_id~,
      grant=lifecycle_grants[index],
    ) catch {
      error => raise PromotionError::Erp(error)
    }
    lifecycle_final_stages.push(project_stage_name(advanced.stage))
  }
  let unit_ids : Array[String] = []
  for unit in registry.units {
    unit_ids.push(unit.unit_id)
  }
  let user_ids : Array[String] = []
  let user_states : Array[String] = []
  for user in imported_users.users {
    user_ids.push(user.user_id)
    user_states.push(user_state_name(user.state))
  }
  let audit_ids : Array[String] = []
  for record in imported_audits.records {
    audit_ids.push(record.audit_id)
  }
  let parameter_names : Array[String] = []
  let parameter_option_counts : Array[Int] = []
  for dictionary in imported_parameters {
    parameter_names.push(dictionary.parameter_name)
    parameter_option_counts.push(dictionary.options.length())
  }
  let project_ids : Array[String] = []
  for project in imported_projects {
    project_ids.push(project.project_id)
  }
  let contract_ids : Array[String] = []
  for contract in promoted_commitments {
    contract_ids.push(contract.commitment_id)
  }
  let cost_ids : Array[String] = []
  for cost in imported_costs {
    cost_ids.push(cost.cost_id)
  }
  let advance_ids : Array[String] = []
  for advance in promoted_advances {
    advance_ids.push(advance.advance_id)
  }
  let workflow_ids : Array[String] = []
  for workflow in imported_workflows {
    workflow_ids.push(workflow.process_id)
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "accepted_items": Json::array(accepted_items),
    "organization_unit_ids": strings_json(unit_ids),
    "user_ids": strings_json(user_ids),
    "user_states": strings_json(user_states),
    "audit_ids": strings_json(audit_ids),
    "parameter_names": strings_json(parameter_names),
    "parameter_option_counts": ints_json(parameter_option_counts),
    "typed_evidence_ids": strings_json(typed_evidence_ids),
    "project_ids": strings_json(project_ids),
    "commitment_ids": strings_json(contract_ids),
    "payment_application_ids": strings_json(payment_application_ids),
    "milestone_ids": strings_json(milestone_ids),
    "cost_ids": strings_json(cost_ids),
    "advance_ids": strings_json(advance_ids),
    "advance_offset_ids": strings_json(advance_offset_ids),
    "advance_offset_amounts": ints_json(advance_offset_amounts),
    "workflow_definition_ids": strings_json(workflow_ids),
    "lifecycle_project_ids": strings_json(lifecycle_project_ids),
    "lifecycle_final_stages": strings_json(lifecycle_final_stages),
    "task_plan_project_ids": strings_json(task_plan_project_ids),
    "task_plan_task_counts": ints_json(task_plan_task_counts),
    "task_state_project_ids": strings_json(task_state_project_ids),
    "task_state_task_counts": ints_json(task_state_project_counts),
    "investment_model_ids": strings_json(promoted_investment_ids),
    "investment_index_counts": ints_json(promoted_investment_counts),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise PromotionError::Io(error)
  }
}

///|
fn commitment_transition_grants(
  source_id : String,
  commitment : @commitment.Commitment,
) -> Array[@foundation.AuthorityGrant] {
  [
    grant(
      source_id + "/submit",
      commitment.principal_id,
      "migration",
      "commitment:submit",
      commitment.project_scope,
      commitment.amount.minor,
    ),
    grant(
      source_id + "/approve",
      commitment.principal_id,
      "migration",
      "commitment:approve",
      commitment.project_scope,
      commitment.amount.minor,
    ),
    grant(
      source_id + "/perform",
      commitment.principal_id,
      "migration",
      "commitment:perform",
      commitment.project_scope,
      commitment.amount.minor,
    ),
    grant(
      source_id + "/settle",
      commitment.principal_id,
      "migration",
      "commitment:settle",
      commitment.project_scope,
      commitment.amount.minor,
    ),
    grant(
      source_id + "/cancel",
      commitment.principal_id,
      "migration",
      "commitment:cancel",
      commitment.project_scope,
      commitment.amount.minor,
    ),
  ]
}

///|
fn commitment_state(
  value : String,
) -> @commitment.CommitmentState raise PromotionError {
  match value.to_lower() {
    "draft" => @commitment.CommitmentState::Draft
    "submitted" => @commitment.CommitmentState::Submitted
    "approved" => @commitment.CommitmentState::Approved
    "performed" => @commitment.CommitmentState::Performed
    "settled" => @commitment.CommitmentState::Settled
    "cancelled" | "canceled" => @commitment.CommitmentState::Cancelled
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn user_state_name(state : @foundation.UserAccountState) -> String {
  match state {
    @foundation.UserAccountState::Active => "active"
    @foundation.UserAccountState::Disabled => "disabled"
  }
}

///|
fn lifecycle_stage(
  value : String,
) -> @project.ProjectStage raise PromotionError {
  match value.to_lower() {
    "initiation" => @project.ProjectStage::Initiation
    "planning" => @project.ProjectStage::Planning
    "design" => @project.ProjectStage::Design
    "development" => @project.ProjectStage::Development
    "sales" => @project.ProjectStage::Sales
    "delivery" => @project.ProjectStage::Delivery
    "settlement" => @project.ProjectStage::Settlement
    "closed" => @project.ProjectStage::Closed
    _ => raise PromotionError::InvalidInput
  }
}

///|
fn project_stage_name(stage : @project.ProjectStage) -> String {
  match stage {
    @project.ProjectStage::Initiation => "initiation"
    @project.ProjectStage::Planning => "planning"
    @project.ProjectStage::Design => "design"
    @project.ProjectStage::Development => "development"
    @project.ProjectStage::Sales => "sales"
    @project.ProjectStage::Delivery => "delivery"
    @project.ProjectStage::Settlement => "settlement"
    @project.ProjectStage::Closed => "closed"
  }
}

///|
fn project_id_check(
  actual : String,
  expected : String,
) -> Unit raise PromotionError {
  if actual != expected {
    raise PromotionError::InvalidInput
  }
}

///|
fn project_id_from_scope(scope : String) -> String raise PromotionError {
  if !scope.has_prefix("project:") || scope.length() <= 8 {
    raise PromotionError::InvalidInput
  }
  scope[8:].to_owned()
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: promote <promotion-plan.json> <output.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      PromotionError::Quarantined(source) => {
        println("promotion refused quarantined item: " + source)
        @sys.exit(1)
      }
      PromotionError::InvalidInput => {
        println("promotion failed: invalid input")
        @sys.exit(1)
      }
      PromotionError::Io(_) => {
        println("promotion failed: filesystem error")
        @sys.exit(1)
      }
      PromotionError::Erp(error) => {
        println("promotion failed: domain invariant \{to_repr(error)}")
        @sys.exit(1)
      }
      _ => {
        println("promotion failed")
        @sys.exit(1)
      }
    }
  }
}
