///|
struct ResearchImportState {
  generation : Int32
  open : Bool
  loading : Bool
  brief : @research_handoff.Brief?
  notice : String
}

///|
enum ResearchImportMsg {
  Choose
  Loaded(Int32, String, String, String)
  Close
  Prepare
  ExportDraft(String)
}

///|
fn empty_research_import(generation : Int32) -> ResearchImportState {
  { generation, open: false, loading: false, brief: None, notice: "", }
}

///|
fn research_import_reconcile(before : Model, after : Model) -> Model {
  if before.page != after.page ||
    before.dispatch_task_actor_id != after.dispatch_task_actor_id ||
    before.dispatch_task_selection != after.dispatch_task_selection ||
    before.products.selected_id != after.products.selected_id {
    {
      ..after,
      research_import: empty_research_import(
        after.research_import.generation + 1,
      ),
    }
  } else {
    after
  }
}

///|
fn research_import_update(
  emit : @rabbita.Emit[Msg],
  action : ResearchImportMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.research_import
  match action {
    Choose => {
      if model.page != Dispatch {
        return (none, model)
      }
      let generation = state.generation + 1
      let actor = model.dispatch_task_actor_id
      (
        @cmd.custom_cmd(scheduler => {
          research_pick_file((text, error) => {
            scheduler.add(
              emit(ResearchImportAction(Loaded(generation, actor, text, error))),
            )
          })
        }),
        {
          ..model,
          research_import: {
            ..state,
            generation,
            open: true,
            loading: true,
            notice: "选择 MoonFind 导出的 decision JSON；当前草稿保持不变。",
          },
        },
      )
    }
    Loaded(generation, actor, text, error) => {
      if !state.open ||
        !state.loading ||
        model.page != Dispatch ||
        generation != state.generation ||
        actor != model.dispatch_task_actor_id {
        return (none, model)
      }
      let result = if !error.is_empty() {
        Err(error)
      } else {
        @research_handoff.decode(text)
      }
      let next = match result {
        Err(error) =>
          {
            ..state,
            loading: false,
            notice: error + " 之前的预览和草稿未被替换。",
          }
        Ok(brief) => {
          let conflict = model.dispatch_drafts.any(draft => {
            match draft.research_brief {
              Some(old) =>
                old.worksheet.evidence.run_id == brief.worksheet.evidence.run_id &&
                old.worksheet.revision == brief.worksheet.revision &&
                old.worksheet != brief.worksheet
              None => false
            }
          })
          if conflict {
            {
              ..state,
              loading: false,
              notice: "同一研究运行和版本已有不同内容。请在 MoonFind 保存新版本后重新导出；之前的预览和草稿未被替换。",
            }
          } else {
            {
              ..state,
              loading: false,
              brief: Some(brief),
              notice: "仅预览保留的研究。请核对来源、选择和下一步；这里没有检查来源的当前版本。",
            }
          }
        }
      }
      (none, { ..model, research_import: next, })
    }
    Close =>
      (
        none,
        {
          ..model,
          research_import: empty_research_import(state.generation + 1),
        },
      )
    Prepare => {
      guard state.open &&
        !state.loading &&
        model.page == Dispatch &&
        state.brief is Some(brief) else {
        return (none, model)
      }
      let blocker = brief.preparation_blocker()
      if !blocker.is_empty() {
        return (
          none,
          { ..model, research_import: { ..state, notice: blocker, }, },
        )
      }
      let existing = model.dispatch_drafts
        .filter(draft => {
          draft.research_brief
          .map(old => old.worksheet == brief.worksheet)
          .unwrap_or(false)
        })
        .get(0)
      if existing is Some(draft) {
        // Never reapply source fields over later edits or open a formal task.
        return (
          none,
          {
            ..model,
            dispatch_draft_id: draft.id,
            dispatch_task_form_open: true,
            research_import: {
              ..state,
              notice: "这份研究已有本地草稿。已恢复原草稿，保留你的修改；没有重复创建或发送请求。",
            },
          },
        )
      }
      let (_, prepared) = dispatch_prepare_draft(
        emit,
        model,
        "",
        "",
        None,
        true,
      )
      let draft = dispatch_active_draft(prepared).unwrap()
      let next = {
        ..draft,
        title: brief.worksheet.next_action,
        source_reference: Some(
          "MoonFind " +
          brief.worksheet.evidence.run_id +
          " / worksheet revision " +
          brief.worksheet.revision.to_string(),
        ),
        observed_problem: Some(brief.worksheet.question),
        research_brief: Some(brief),
        note: "研究已保留在可编辑本地草稿中。请补充验收标准、项目与日期；需求未证实，尚未创建正式任务。",
      }
      dispatch_save_draft(
        emit,
        {
          ..prepared,
          research_import: {
            ..state,
            notice: "已另建本地草稿，原有草稿保持不变。可导出工作包保留决策和完整来源文本。",
          },
        },
        next,
      )
    }
    ExportDraft(id) => {
      guard dispatch_draft_by_id(model, id) is Some(draft) else {
        return (none, model)
      }
      (
        @cmd.custom_cmd(_ => {
          research_download_packet(research_founder_packet(draft))
        }),
        {
          ..model,
          notice: "已导出本地工作包，保留研究来源和草稿内容；没有创建任务或发送给第三方。",
        },
      )
    }
  }
}

///|
fn research_founder_packet(draft : DispatchDraft) -> String {
  let out = StringBuilder()
  out.write_string(
    "# Founder work packet\n\nLocal planning copy. No signed company receipt, validated demand, customer acceptance or payment is implied.\n\n",
  )
  for
    (label, value) in [
      ("Title", draft.title),
      ("Acceptance criterion", draft.acceptance),
      ("Source reference", draft.source_reference.unwrap_or("")),
      (
        "Observed problem / research question",
        draft.observed_problem.unwrap_or(""),
      ),
      ("Project reference", draft.project_id),
      ("Owner reference", draft.owner_id),
      ("Planned start", draft.begin_date),
      ("Planned end", draft.end_date),
    ] {
    out.write_string(
      label +
      ": " +
      (if value.is_blank() { "Unknown / not recorded" } else { value }) +
      "\n\n",
    )
  }
  if draft.research_brief is Some(brief) {
    out.write_string(brief.markdown())
  }
  if draft.offer_draft is Some(value) {
    let offer = @task_evidence.offer_draft_markdown(
      value,
      task_id="",
      project_id=draft.project_id,
      revision=0,
    ) catch {
      @task_evidence.InvalidOfferDraft(error) =>
        "Offer draft could not be exported: " + error
    }
    out.write_string("\n\n" + offer)
  }
  out.to_string()
}
