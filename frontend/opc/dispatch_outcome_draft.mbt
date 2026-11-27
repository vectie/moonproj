///|
// These drafts live only in this tab's model. Exact captured source identity is
// part of the key; notes are never silently moved onto a refreshed source.
#derive(Eq)
struct DispatchOutcomeGap {
  choice : String
  summary : String
  severity : String
  evidence_refs : Array[String]
}

///|
struct DispatchOutcomeDraft {
  handoff : Json
  outcome_summary : String
  observed_at : String
  owner_route : String
  gaps : Array[DispatchOutcomeGap]
  capability_id : String
  capability_version : String
  capability_summary : String
  change_text : String
  recorded_at : Int32
  request : Int32
  pending_selection : Int32
  pending : Bool
  prepared : Json?
  notice : String
}

///|
enum DispatchOutcomeMsg {
  Edit(String, String)
  GapEdit(Int32, String, String)
  Evidence(Int32, String)
  Preview
  Loaded(String, Int32, Int32, Json, Result[String, String])
  Download(String)
}

///|
fn dispatch_outcome_empty(handoff : Json) -> DispatchOutcomeDraft {
  {
    handoff,
    outcome_summary: "",
    observed_at: "",
    owner_route: dispatch_outcome_owner_route(
      dispatch_handoff_current_page(),
      dispatch_json_text(dispatch_json_field(handoff, "task"), "record_id"),
    ),
    gaps: Array::makei(3, _ => {
      choice: "",
      summary: "",
      severity: "",
      evidence_refs: [],
    }),
    capability_id: "",
    capability_version: "",
    capability_summary: "",
    change_text: "",
    recorded_at: 0,
    request: 0,
    pending_selection: -1,
    pending: false,
    prepared: None,
    notice: "",
  }
}

///|
fn dispatch_outcome_draft(
  model : Model,
  handoff : Json,
) -> DispatchOutcomeDraft {
  model.dispatch_outcome_drafts
  .filter(draft => draft.handoff == handoff)
  .get(0)
  .unwrap_or(dispatch_outcome_empty(handoff))
}

///|
fn dispatch_outcome_store(model : Model, draft : DispatchOutcomeDraft) -> Model {
  let drafts = model.dispatch_outcome_drafts.filter(item => {
    item.handoff != draft.handoff
  })
  drafts.push(draft)
  { ..model, dispatch_outcome_drafts: drafts, }
}

///|
fn dispatch_outcome_changed(
  model : Model,
  draft : DispatchOutcomeDraft,
) -> Model {
  dispatch_outcome_store(
    { ..model, dispatch_outcome_sequence: model.dispatch_outcome_sequence + 1, },
    {
      ..draft,
      recorded_at: 0,
      request: model.dispatch_outcome_sequence + 1,
      pending: false,
      prepared: None,
      notice: "草稿只保留在此标签页；编辑后请重新预览。",
    },
  )
}

///|
fn dispatch_outcome_refreshing_source(model : Model) -> Model {
  let request = model.dispatch_outcome_sequence + 1
  {
    ..model,
    dispatch_outcome_sequence: request,
    dispatch_outcome_drafts: model.dispatch_outcome_drafts.map(draft => {
      if Some(draft.handoff) == model.dispatch_lesson_handoff.payload {
        {
          ..draft,
          pending: false,
          request,
          prepared: None,
          notice: "草稿已保留；来源准备完成后请重新预览。",
        }
      } else {
        draft
      }
    }),
  }
}

///|
fn dispatch_outcome_gap_label(index : Int32) -> String {
  match index {
    0 => "信息缺口"
    1 => "识别缺口"
    _ => "决断缺口"
  }
}

///|
fn dispatch_outcome_has_gap(draft : DispatchOutcomeDraft) -> Bool {
  draft.gaps.any(gap => gap.choice == "present")
}

///|
fn dispatch_outcome_evidence(handoff : Json) -> Array[String] {
  [
    dispatch_json_text(dispatch_json_field(handoff, "task"), "record_id"),
    dispatch_json_text(dispatch_json_field(handoff, "report"), "record_id"),
  ].filter(id => !id.is_empty())
}

///|
fn dispatch_outcome_severity(value : String) -> Int32 {
  match value {
    "1" => 1
    "2" => 2
    "3" => 3
    "4" => 4
    "5" => 5
    _ => 0
  }
}

///|
fn dispatch_outcome_validation(draft : DispatchOutcomeDraft) -> String {
  if draft.outcome_summary.trim().is_empty() {
    return "请写下实际观察到的结果，不要只重复内部接受状态。"
  }
  if dispatch_outcome_time(draft.observed_at) <= 0 {
    return "请填写有效的观察时间（UTC）。"
  }
  if dispatch_outcome_time(draft.observed_at) > dispatch_outcome_now() {
    return "观察时间不能晚于现在；请检查 UTC 时间。"
  }
  if dispatch_outcome_text_bytes(draft.outcome_summary) > 8192 {
    return "结果说明过长，请缩短至 8192 个 UTF-8 字节以内。"
  }
  if draft.owner_route.is_empty() ||
    dispatch_outcome_owner_route(
      draft.owner_route,
      dispatch_json_text(
        dispatch_json_field(draft.handoff, "task"),
        "record_id",
      ),
    ) !=
    draft.owner_route {
    return "无法确认此 Proj 页面地址；请从实际 HTTP(S) 页面重新准备来源。"
  }
  let allowed = dispatch_outcome_evidence(draft.handoff)
  for index, gap in draft.gaps {
    let title = dispatch_outcome_gap_label(index)
    if gap.choice != "absent" && gap.choice != "present" {
      return title +
        "：请明确选择未发现或发现；尚未选择不能导出。"
    }
    if gap.summary.trim().is_empty() {
      return title +
        "：请说明判断依据，包括明确未发现时的依据。"
    }
    if dispatch_outcome_text_bytes(gap.summary) > 4096 {
      return title +
        "：判断依据过长，请缩短至 4096 个 UTF-8 字节以内。"
    }
    if gap.evidence_refs.is_empty() ||
      gap.evidence_refs.any(id => !allowed.contains(id)) {
      return title + "：请从此次捕获的任务或报告中选择证据。"
    }
    if gap.choice == "present" && dispatch_outcome_severity(gap.severity) == 0 {
      return title + "：请选择 1–5 级严重程度。"
    }
  }
  if dispatch_outcome_has_gap(draft) &&
    [
      draft.capability_id,
      draft.capability_version,
      draft.capability_summary,
      draft.change_text,
    ].any(value => value.trim().is_empty()) {
    return "发现缺口时，请填写真实能力 ID、版本、拟议改进摘要和详细内容；不要使用任务 ID 代替。"
  }
  if dispatch_outcome_has_gap(draft) {
    for
      (label, value, limit) in [
        ("能力 ID", draft.capability_id, 256),
        ("能力版本", draft.capability_version, 128),
        ("拟议改进摘要", draft.capability_summary, 4096),
        ("拟议改进内容", draft.change_text, 65536),
      ] {
      if dispatch_outcome_text_bytes(value) > limit {
        return label +
          "过长，请缩短至 " +
          limit.to_string() +
          " 个 UTF-8 字节以内。"
      }
    }
  }
  ""
}

///|
fn dispatch_outcome_gap_json(gap : DispatchOutcomeGap) -> Json {
  {
    "present": gap.choice == "present",
    "severity": if gap.choice == "present" {
      dispatch_outcome_severity(gap.severity)
    } else {
      0
    },
    "summary": gap.summary,
    "evidence_refs": gap.evidence_refs,
  }
}

///|
fn dispatch_outcome_draft_json(draft : DispatchOutcomeDraft) -> Json {
  {
    "outcome_summary": draft.outcome_summary,
    "observed_at": dispatch_outcome_time(draft.observed_at),
    "recorded_at": draft.recorded_at,
    "owner_route": draft.owner_route,
    "information_gap": dispatch_outcome_gap_json(draft.gaps[0]),
    "recognition_gap": dispatch_outcome_gap_json(draft.gaps[1]),
    "decisiveness_gap": dispatch_outcome_gap_json(draft.gaps[2]),
    "capability": if dispatch_outcome_has_gap(draft) {
      {
        "id": draft.capability_id,
        "version": draft.capability_version,
        "summary": draft.capability_summary,
        "change_text": draft.change_text,
      }
    } else {
      Json::null()
    },
  }
}

///|
extern "js" fn dispatch_outcome_now() -> Int32 =
  #| () => Math.floor(Date.now() / 1000)

///|
extern "js" fn dispatch_outcome_text_bytes(value : String) -> Int32 =
  #| value => new TextEncoder().encode(value).length

///|
extern "js" fn dispatch_outcome_time(value : String) -> Int32 =
  #| value => { if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(value)) return 0; const ms=Date.parse(value+'Z'); if(!Number.isFinite(ms)||new Date(ms).toISOString().slice(0,value.length)!==value) return 0; const seconds=ms/1000; return seconds>0&&seconds<=2147483647?seconds:0; }

///|
// Reopen the actual mounted task screen. Only its origin/path and the two
// navigation parameters survive; credentials, other queries and fragments do not.
extern "js" fn dispatch_outcome_owner_route(
  page : String,
  task : String,
) -> String =
  #| (page,task)=>{try{if(!task)return '';const source=new URL(page);if(!['http:','https:'].includes(source.protocol))return '';const route=new URL(source.origin+source.pathname);route.searchParams.set('page','dispatch');route.searchParams.set('task',task);return route.href;}catch(_){return '';}}
