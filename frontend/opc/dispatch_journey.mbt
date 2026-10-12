///|
// A read-only view of the selected task's last successful readback. Stages are
// causal, never a chronology inferred from missing or incomparable timestamps.
struct DispatchJourneyRecord {
  label : String
  actor : String
  recorded_at : String
  event_id : String
  audit_id : String
  audit_state : String
  reference : String
  detail : String
} derive(Debug, Eq)

///|
struct DispatchJourneyStage {
  id : String
  title : String
  state : String
  detail : String
  owner : String
  anchor : String
  link_label : String
  records : Array[DispatchJourneyRecord]
} derive(Debug, Eq)

///|
fn dispatch_journey_known(value : String) -> String {
  if value.is_empty() {
    "未记录"
  } else {
    value
  }
}

///|
fn dispatch_journey_history(model : Model) -> Json {
  if !model.dispatch_task_id.is_empty() &&
    dispatch_json_text(model.dispatch_task_commitment, "task_id") ==
    model.dispatch_task_id {
    model.dispatch_task_commitment
  } else {
    Json::null()
  }
}

///|
fn dispatch_journey_receipts(model : Model, action : String) -> Array[Json] {
  dispatch_continuation_array(dispatch_journey_history(model), "receipts").filter(row => {
      dispatch_json_text(row, "action") == action
    },
  )
}

///|
fn dispatch_journey_record(
  row : Json,
  label : String,
  detail? : String = "",
  reference? : String = "",
) -> DispatchJourneyRecord {
  {
    label,
    actor: dispatch_json_text(row, "actor_id"),
    recorded_at: dispatch_json_text(row, "recorded_at"),
    event_id: dispatch_json_text(row, "event_id"),
    audit_id: dispatch_json_text(row, "audit_id"),
    audit_state: dispatch_json_text(row, "audit_state"),
    reference,
    detail,
  }
}

///|
fn dispatch_journey_continuation_current(model : Model) -> Bool {
  let state = model.dispatch_continuation
  state.task_id == model.dispatch_task_id &&
  state.selection == model.dispatch_task_selection &&
  state.actor == model.dispatch_task_actor_id
}

///|
fn dispatch_journey_source(model : Model, source : Json) -> String {
  if source is Null {
    return "来源未记录"
  }
  let label = dispatch_delivery_source_label(source)
  if dispatch_json_text(source, "type") != "human_revision" {
    return label
  }
  if model.dispatch_run.map(run => run.run_id).unwrap_or("") !=
    dispatch_json_text(source, "original_run_id") {
    return label + " · 保留正文摘要待核对"
  }
  let records = model.dispatch_continuation.human_revisions.filter(record => {
    dispatch_human_revision_valid(model, record) &&
    dispatch_json_text(record, "revision_id") ==
    dispatch_json_text(source, "revision_id")
  })
  if records.length() == 1 {
    label +
    " · 保留正文 SHA-256 " +
    dispatch_json_text(dispatch_json_field(records[0], "content"), "sha256")
  } else {
    label + " · 保留正文摘要待核对"
  }
}

///|
fn dispatch_journey_offer_current(
  row : Json,
  offer : Json,
  revision : Int,
) -> Bool {
  guard revision > 0 &&
    dispatch_offer_revision(row) == revision &&
    dispatch_json_text(row, "audit_state") == "available" else {
    return false
  }
  let saved = @task_evidence.normalize_offer_draft(
    dispatch_json_field(row, "offer_draft"),
  ) catch {
    _ => return false
  }
  let current = @task_evidence.normalize_offer_draft(offer) catch {
    _ => return false
  }
  saved == current
}

///|
fn dispatch_journey_reply_superseded(
  history : Array[Json],
  original : Json,
) -> Bool {
  let id = dispatch_json_text(original, "reply_id")
  let revision = dispatch_reply_number(
    dispatch_json_field(original, "offer_reply"),
    "offer_revision",
  )
  !id.is_empty() &&
  revision > 0 &&
  history.any(row => {
    let value = dispatch_json_field(row, "offer_reply")
    dispatch_json_text(row, "audit_state") == "available" &&
    !dispatch_json_text(row, "reply_id").is_empty() &&
    dispatch_json_text(value, "supersedes_reply_id") == id &&
    dispatch_reply_number(value, "offer_revision") == revision
  })
}

///|
fn dispatch_journey_stages(model : Model) -> Array[DispatchJourneyStage] {
  let history = dispatch_journey_history(model)
  let receipts = dispatch_continuation_array(history, "receipts")
  let creates = dispatch_journey_receipts(model, "create")
  let source = model.dispatch_task_source_context
  let reference = dispatch_json_text(source, "reference")
  let problem = dispatch_json_text(source, "problem")
  let source_present = !reference.is_empty() || !problem.is_empty()
  let original_source = dispatch_json_field(
    dispatch_json_field(history, "original_brief"),
    "source_context",
  )
  let source_records = creates.map(row => {
    dispatch_journey_record(
      row,
      "创建时来源记录",
      reference=dispatch_json_text(original_source, "reference"),
      detail=dispatch_json_text(original_source, "problem"),
    )
  })
  if source_records.is_empty() && source_present {
    source_records.push(
      dispatch_journey_record(
        Json::null(),
        "任务快照中的来源",
        reference~,
      ),
    )
  }
  let offer = if dispatch_json_text(model.dispatch_offer_task, "taskGuid") ==
    model.dispatch_task_id {
    dispatch_json_field(model.dispatch_offer_task, "offer_draft")
  } else {
    Json::null()
  }
  let offer_revision = dispatch_offer_canonical_revision(model)
  let offers = dispatch_continuation_array(history, "offer_history")
  let replies = dispatch_reply_history(model)
  let current_replies = replies.filter(row => {
    let value = dispatch_json_field(row, "offer_reply")
    offer_revision > 0 &&
    dispatch_reply_number(value, "offer_revision") == offer_revision &&
    dispatch_json_text(row, "audit_state") == "available" &&
    !dispatch_json_text(row, "reply_id").is_empty() &&
    !dispatch_journey_reply_superseded(replies, row)
  })
  let offer_records = offers.map(row => {
    let event = dispatch_json_text(row, "event_id")
    let receipt = receipts
      .filter(item => {
        !event.is_empty() && dispatch_json_text(item, "event_id") == event
      })
      .get(0)
      .unwrap_or(Json::null())
    let record = dispatch_journey_record(
      row,
      "已保存方案 · 版本 " + dispatch_offer_revision(row).to_string(),
      detail=if dispatch_journey_offer_current(row, offer, offer_revision) {
        "与当前方案内容一致"
      } else {
        "历史方案；不替代当前内容"
      },
    )
    { ..record, actor: dispatch_json_text(receipt, "actor_id"), }
  })
  for row in replies {
    let value = dispatch_json_field(row, "offer_reply")
    let id = dispatch_json_text(row, "reply_id")
    let record = dispatch_journey_record(
      row,
      "方案版本 " +
      dispatch_reply_number(value, "offer_revision").to_string() +
      " 的回复 · " +
      dispatch_reply_kind_label(dispatch_json_text(value, "kind")),
      reference=dispatch_json_text(value, "source_reference"),
      detail="回复记录 " +
        dispatch_journey_known(id) +
        (if dispatch_journey_reply_superseded(replies, row) {
          " · 已有更正，保留原记录"
        } else {
          ""
        }) +
        " · 转述回复者：" +
        dispatch_journey_known(dispatch_json_text(value, "respondent")) +
        " · 声称收到时间：" +
        dispatch_journey_known(dispatch_json_text(value, "received_at")),
    )
    offer_records.push({
      ..record,
      actor: dispatch_json_text(row, "recorded_by"),
    })
  }
  let continuation_current = dispatch_journey_continuation_current(model)
  let reports = if continuation_current {
    model.dispatch_continuation.report_records.filter(row => {
      !dispatch_json_text(row, "reportGuid").is_empty() &&
      (
        dispatch_json_text(row, "taskGuid").is_empty() ||
        dispatch_json_text(row, "taskGuid") == model.dispatch_task_id
      )
    })
  } else {
    []
  }
  let report_receipts = dispatch_journey_receipts(model, "report")
  let report_records : Array[DispatchJourneyRecord] = []
  for report in reports {
    let id = dispatch_json_text(report, "reportGuid")
    let matched = report_receipts.filter(row => {
      dispatch_json_text(row, "report_id") == id
    })
    let records = if matched.is_empty() { [Json::null()] } else { matched }
    for row in records {
      report_records.push(
        dispatch_journey_record(
          row,
          "报告 · " + id,
          detail="报告固定来源 · " +
            dispatch_journey_source(
              model,
              dispatch_json_field(report, "delivery_source"),
            ),
        ),
      )
    }
  }
  let accepted_id = if continuation_current {
    model.dispatch_continuation.accepted_report_id
  } else {
    ""
  }
  let acceptance = dispatch_journey_receipts(model, "internal_acceptance")
  let exact_acceptance = acceptance.filter(row => {
    !accepted_id.is_empty() &&
    dispatch_json_text(row, "report_id") == accepted_id &&
    dispatch_json_text(row, "audit_state") == "available" &&
    !dispatch_json_text(row, "event_id").is_empty() &&
    dispatch_json_field(row, "delivery_source") ==
    model.dispatch_continuation.accepted_delivery_source
  })
  let accepted_report_present = reports.any(report => {
    dispatch_json_text(report, "reportGuid") == accepted_id &&
    dispatch_json_field(report, "delivery_source") ==
    model.dispatch_continuation.accepted_delivery_source
  })
  let acceptance_linked = model.dispatch_task_stage == "accepted" &&
    model.dispatch_continuation.source_verified &&
    accepted_report_present &&
    !exact_acceptance.is_empty()
  let run = model.dispatch_run.filter(run => {
    run.task_id == model.dispatch_task_id
  })
  let work_records = creates.map(row => {
    dispatch_journey_record(row, "创建正式任务")
  })
  for row in dispatch_journey_receipts(model, "update") {
    work_records.push(
      dispatch_journey_record(row, "任务更新（历史操作）"),
    )
  }
  let has_outputs = run
    .map(run => !run.artifacts.is_empty() || !run.output_urls.is_empty())
    .unwrap_or(false)
  let report_anchor = if run is Some(_) {
    "#dispatch-result-choice"
  } else {
    "#dispatch-task-receipts"
  }
  [
    {
      id: "source",
      title: "来源与问题",
      state: if source_present {
        "已保留来源"
      } else {
        "来源尚未记录"
      },
      detail: if problem.is_empty() {
        "来源引用只说明工作从哪里来，不代表已验证其内容。"
      } else {
        problem
      },
      owner: if source == original_source {
        creates
        .get(0)
        .map(row => dispatch_json_text(row, "actor_id"))
        .unwrap_or("")
      } else {
        ""
      },
      anchor: "#dispatch-source-context",
      link_label: "查看原始问题",
      records: source_records,
    },
    {
      id: "offer",
      title: "方案与反馈",
      state: if offer is Null {
        "尚无已保存方案"
      } else if offer_revision == 0 {
        "方案已读回，版本关联待核对"
      } else {
        "方案版本 " +
        offer_revision.to_string() +
        " · " +
        (if current_replies.is_empty() {
          "此版本尚无已核对回复"
        } else {
          current_replies.length().to_string() + " 条回复记录"
        })
      },
      detail: "报价、人工记录的反馈和已授权订单分别核对；本地未保存编辑不进入此记录。",
      owner: "",
      anchor: "#dispatch-offer",
      link_label: "查看方案与回复",
      records: offer_records,
    },
    {
      id: "work",
      title: "正式工作",
      state: if ["pending", "in_progress", "submitted", "accepted"].contains(
          model.dispatch_task_stage,
        ) {
        dispatch_task_stage_label(model.dispatch_task_stage)
      } else {
        "任务状态待核对"
      },
      detail: run
      .map(run => {
        if run.state == "completed" {
          "最近读取的原生执行已完成；结果与验收分别核对。"
        } else {
          dispatch_native_label(Some(run))
        }
      })
      .unwrap_or(
        "尚未读到执行记录；创建任务不等于已经开始执行。",
      ),
      owner: model.dispatch_task_owner_id,
      anchor: "#dispatch-execution",
      link_label: "查看执行与现有操作",
      records: work_records,
    },
    {
      id: "result",
      title: "结果与报告",
      state: if !reports.is_empty() {
        reports.length().to_string() + " 份已保存报告"
      } else if has_outputs {
        "有执行输出，尚未读到报告"
      } else {
        "尚未读到结果或报告"
      },
      detail: "报告保留提交时的来源；当前选择或后来修订不会替换已保存报告。",
      owner: "",
      anchor: report_anchor,
      link_label: "查看结果与准确报告",
      records: report_records,
    },
    {
      id: "acceptance",
      title: "内部验收",
      state: if acceptance_linked {
        "已关联内部验收收据"
      } else if !accepted_id.is_empty() ||
        model.dispatch_task_stage == "accepted" {
        "任务显示已接受，完整收据关联待核对"
      } else {
        "尚未读到内部接受记录"
      },
      detail: if accepted_id.is_empty() {
        "接受报告需要独立记录，不能由执行完成推断。"
      } else {
        "接受的报告 · " +
        accepted_id +
        "。当前浏览的其他报告不会改变它。"
      },
      owner: exact_acceptance
      .get(0)
      .map(row => dispatch_json_text(row, "actor_id"))
      .unwrap_or(""),
      anchor: report_anchor,
      link_label: "核对报告与接受记录",
      records: acceptance.map(row => {
        dispatch_journey_record(
          row,
          "内部验收 · " +
          dispatch_journey_known(dispatch_json_text(row, "report_id")),
        )
      }),
    },
    {
      id: "customer",
      title: "客户交付与验收",
      state: "外部凭据尚未接入此视图",
      detail: "准备或下载交付包只产生本地文件；方案回复与内部验收都不能证明已交付或客户已接受。",
      owner: "",
      anchor: if !accepted_id.is_empty() &&
        run is Some(_) &&
        dispatch_json_text(
          model.dispatch_continuation.accepted_delivery_source,
          "type",
        ) ==
        "human_revision" {
        report_anchor
      } else {
        ""
      },
      link_label: "查看结果与交付包入口",
      records: [],
    },
    {
      id: "cash",
      title: "发票与收款",
      state: "财务凭据尚未接入此视图",
      detail: "这里不推断是否开票、欠款或已收款；需要独立的发票及银行或支付凭据。",
      owner: "",
      anchor: "",
      link_label: "",
      records: [],
    },
  ]
}
