///|
struct WorkPacketState {
  generation : Int
  open : Bool
  loading : Bool
  actor : String
  draft_id : String
  project_id : String
  text : String
  packet : @work_packet.Packet?
  notice : String
} derive(Debug, Eq)

///|
enum WorkPacketMsg {
  Export
  Choose
  Loaded(Int, String, String)
  Source(String)
  Preview
  Apply
  Close
}

///|
fn empty_work_packet(generation : Int) -> WorkPacketState {
  {
    generation,
    open: false,
    loading: false,
    actor: "",
    draft_id: "",
    project_id: "",
    text: "",
    packet: None,
    notice: "",
  }
}

///|
fn work_packet_scope(model : Model) -> Bool {
  let s = model.work_packet
  model.page == Dispatch &&
  model.dispatch_task_form_open &&
  s.actor == model.dispatch_task_actor_id &&
  dispatch_active_draft(model)
  .map(d => d.id == s.draft_id && d.project_id == s.project_id)
  .unwrap_or(false)
}

///|
fn work_packet_reconcile(model : Model) -> Model {
  if model.work_packet.open && !work_packet_scope(model) {
    {
      ..model,
      work_packet: empty_work_packet(model.work_packet.generation + 1),
    }
  } else {
    model
  }
}

///|
fn work_packet_from_draft(d : DispatchDraft) -> @work_packet.Packet {
  {
    title: d.title,
    acceptance: d.acceptance,
    source_reference: d.source_reference.unwrap_or(""),
    observed_problem: d.observed_problem.unwrap_or(""),
    begin_date: d.begin_date,
    end_date: d.end_date,
  }
}

///|
fn work_packet_preview(
  state : WorkPacketState,
  text : String,
) -> WorkPacketState {
  let packet = @work_packet.decode(text) catch {
    @work_packet.Invalid(error) =>
      return { ..state, loading: false, text, packet: None, notice: error, }
  }
  {
    ..state,
    loading: false,
    text,
    packet: Some(packet),
    notice: "核对下列六项文本；日期按原文保留，请在新草稿中确认或修正。",
  }
}

///|
fn work_packet_update(
  emit : @rabbita.Emit[Msg],
  action : WorkPacketMsg,
  model : Model,
) -> (Cmd, Model) {
  guard model.page == Dispatch &&
    model.dispatch_task_form_open &&
    dispatch_active_draft(model) is Some(draft) else {
    return (none, model)
  }
  let state = model.work_packet
  match action {
    Export => {
      let text = work_packet_from_draft(draft).encode() catch {
        @work_packet.Invalid(error) =>
          return (none, { ..model, notice: error, })
      }
      (
        @cmd.custom_cmd(_ => work_packet_download(text)),
        {
          ..model,
          notice: "已下载可重用工作简报。仅包含六项任务文本，请检查自由文本后再分享。",
        },
      )
    }
    Choose | Source(_) => {
      let generation = state.generation + 1
      let next = {
        ..empty_work_packet(generation),
        open: true,
        actor: model.dispatch_task_actor_id,
        draft_id: draft.id,
        project_id: draft.project_id,
      }
      match action {
        Choose =>
          (
            @cmd.custom_cmd(scheduler => {
              work_packet_pick_file((text, error) => {
                scheduler.add(
                  emit(WorkPacketAction(Loaded(generation, text, error))),
                )
              })
            }),
            {
              ..model,
              work_packet: {
                ..next,
                loading: true,
                notice: "选择之前导出的工作简报 JSON。",
              },
            },
          )
        Source(text) =>
          (
            none,
            {
              ..model,
              work_packet: if text.length() > 262144 {
                {
                  ..next,
                  notice: "工作简报超过 256 KiB 读取上限。",
                }
              } else {
                { ..next, text, }
              },
            },
          )
        _ => (none, model)
      }
    }
    Loaded(generation, text, error) => {
      if !state.open ||
        !state.loading ||
        state.generation != generation ||
        !work_packet_scope(model) {
        return (none, model)
      }
      let next = if !error.is_empty() {
        { ..state, loading: false, packet: None, notice: error, }
      } else {
        work_packet_preview(state, text)
      }
      (none, { ..model, work_packet: next, })
    }
    Preview => {
      if !state.open || state.loading || !work_packet_scope(model) {
        return (none, model)
      }
      (none, { ..model, work_packet: work_packet_preview(state, state.text), })
    }
    Apply => {
      guard state.open &&
        !state.loading &&
        work_packet_scope(model) &&
        state.packet is Some(packet) else {
        return (none, model)
      }
      // Never overwrite the source draft or copy its identity/authority/settings.
      let (_, prepared) = dispatch_prepare_draft(
        emit,
        model,
        "",
        draft.project_id,
        None,
        true,
      )
      let fresh = dispatch_active_draft(prepared).unwrap()
      dispatch_save_draft(
        emit,
        {
          ..prepared,
          work_packet: empty_work_packet(state.generation + 1),
          notice: "已另建普通本地草稿，原草稿保留。请填写负责人和执行设置，检查日期；尚未创建正式任务。",
        },
        {
          ..fresh,
          title: packet.title,
          acceptance: packet.acceptance,
          source_reference: Some(packet.source_reference),
          observed_problem: Some(packet.observed_problem),
          begin_date: packet.begin_date,
          end_date: packet.end_date,
          note: "来自可重用工作简报的本地草稿；项目沿用目标草稿，负责人和执行设置需重新填写。",
        },
      )
    }
    Close =>
      (none, { ..model, work_packet: empty_work_packet(state.generation + 1), })
  }
}
