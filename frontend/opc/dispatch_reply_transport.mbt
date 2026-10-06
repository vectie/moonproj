///|
fn dispatch_reply_store(model : Model) -> String {
  ToJson::to_json(DispatchReplyStore::{
    version: 1,
    drafts: model.dispatch_reply_drafts,
  }).stringify()
}

///|
fn dispatch_reply_persist(
  emit : @rabbita.Emit[Msg],
  model : Model,
  task : String,
  key : String,
) -> Cmd {
  let actor = model.dispatch_task_actor_id
  let text = dispatch_reply_store(model)
  let generation = model.dispatch_reply_generation
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      emit(
        ReplyAction(
          Scoped(
            generation,
            ReplyStored(
              actor,
              task,
              key,
              dispatch_reply_storage_write(actor, generation, text),
            ),
          ),
        ),
      ),
    )
  })
}

///|
extern "js" fn dispatch_reply_storage_write(
  actor : String,
  generation : Int,
  text : String,
) -> Bool =
  #| (actor,generation,text)=>{if(!actor||typeof window==='undefined'||window.__moonprojReplyActor!==actor||window.__moonprojReplyGeneration!==generation)return false;try{window.sessionStorage.setItem('moonproj.dispatch.offer-replies.v1.'+encodeURIComponent(actor),text);return true;}catch(_){return false;}}

///|
extern "js" fn dispatch_reply_storage_read(actor : String) -> String =
  #| actor=>{if(!actor||typeof window==='undefined')return '';try{return window.sessionStorage.getItem('moonproj.dispatch.offer-replies.v1.'+encodeURIComponent(actor))||'';}catch(_){return 'storage-unavailable';}}

///|
extern "js" fn dispatch_reply_storage_clear(actor : String) -> Bool =
  #| actor=>{if(!actor||typeof window==='undefined')return false;try{window.sessionStorage.removeItem('moonproj.dispatch.offer-replies.v1.'+encodeURIComponent(actor));return true;}catch(_){return false;}}

///|
extern "js" fn dispatch_reply_storage_session(actor : String, generation : Int) =
  #| (actor,generation)=>{if(typeof window!=='undefined'){window.__moonprojReplyActor=actor;window.__moonprojReplyGeneration=generation;}}

///|
fn dispatch_reply_session(
  emit : @rabbita.Emit[Msg],
  previous : String,
  actor : String,
  generation : Int,
) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    dispatch_reply_storage_session(actor, generation)
    let cleared = previous.is_empty() ||
      previous == actor ||
      dispatch_reply_storage_clear(previous)
    if !actor.is_empty() {
      scheduler.add(
        emit(
          ReplyAction(
            Scoped(
              generation,
              ReplyRestored(actor, dispatch_reply_storage_read(actor)),
            ),
          ),
        ),
      )
    }
    if !cleared {
      scheduler.add(
        emit(
          ReplyAction(
            Scoped(
              generation,
              StorageStatus(
                actor, "浏览器未确认清除旧账号的本地草稿；当前账号的草稿仍独立隔离。",
              ),
            ),
          ),
        ),
      )
    }
  })
}

///|
fn dispatch_reply_update_body(
  actor : String,
  draft : DispatchReplyDraft,
) -> Json {
  {
    "idempotency_key": draft.operation_key,
    "authority": {
      "active": true,
      "principal_id": "principal-opc-dispatch",
      "actor_id": actor,
      "capability": "project:task:update",
      "scope": "project:" + draft.project_id,
    },
    "reply_base_revision": draft.operation_revision,
    "offer_reply": draft.operation_reply.unwrap_or(Json::null()),
  }
}

///|
fn dispatch_reply_write(
  emit : @rabbita.Emit[Msg],
  actor : String,
  draft : DispatchReplyDraft,
  generation : Int,
) -> Cmd {
  let body = dispatch_reply_update_body(actor, draft).stringify()
  @cmd.custom_cmd(scheduler => {
    dispatch_offer_put_request(
      "/api/company/plan/tasks/" + dispatch_url_encode(draft.task_id),
      body,
      (status, text) => {
        scheduler.add(
          emit(
            ReplyAction(
              Scoped(
                generation,
                Written(actor, draft.task_id, draft.operation_key, status, text),
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
fn dispatch_reply_read(
  emit : @rabbita.Emit[Msg],
  actor : String,
  draft : DispatchReplyDraft,
  generation : Int,
) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    dispatch_offer_get_request(
      "/api/company/tasks/" + dispatch_url_encode(draft.task_id),
      (status, text) => {
        scheduler.add(
          emit(
            ReplyAction(
              Scoped(
                generation,
                Read(actor, draft.task_id, draft.operation_key, status, text),
              ),
            ),
          ),
        )
      },
    )
  })
}
