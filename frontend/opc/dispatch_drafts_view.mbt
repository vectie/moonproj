///|
fn dispatch_product_label(model : Model, id : String) -> String {
  if id.is_empty() {
    "未关联"
  } else {
    match model.products.rows.filter(row => row.id == id).get(0) {
      Some(row) => row.name + " (" + id + ")"
      None => id
    }
  }
}

///|
fn dispatch_draft_note(model : Model) -> String {
  match dispatch_active_draft(model) {
    Some(draft) =>
      draft.note +
      " · " +
      model.dispatch_draft_storage +
      " · 保留任务 ID：" +
      draft.task_id
    None => "没有打开的本地草稿"
  }
}

///|
fn dispatch_draft_create_button(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  match dispatch_active_draft(model) {
    Some(draft) =>
      match draft.state {
        "editing" =>
          primary_button(
            emit,
            CreateDispatchTask,
            if draft.task_type == Some("key_node") {
              "保存目标"
            } else {
              "保存工作"
            },
          )
        "retryable" =>
          primary_button(emit, CreateDispatchTask, "重试同一创建请求")
        "rejected" =>
          primary_button(
            emit,
            DraftAction(Revise(draft.id)),
            "修订为新草稿",
          )
        "uncertain" =>
          primary_button(
            emit,
            DraftAction(Recover(draft.id)),
            "先恢复创建结果",
          )
        _ => status_badge(draft.note, tone="warning")
      }
    None => @html.nothing
  }
}

///|
fn dispatch_draft_list(emit : @rabbita.Emit[Msg], model : Model) -> @html.Html {
  details(open=true) <| [
    summary("此浏览器草稿与最近任务"),
    p(
      "草稿尚未成为公司任务。打开正式任务只会暂存草稿，不会取消执行或接受结果。",
    ),
    small(model.dispatch_draft_storage),
    div <| model.dispatch_drafts.map(draft => {
      div(class="inline-form") <| [
        strong(
          if draft.title.is_empty() {
            "未命名草稿"
          } else {
            draft.title
          },
        ),
        small(
          "产品 · " +
          dispatch_product_label(model, draft.product_id) +
          " / 公司项目 · " +
          draft.project_id,
        ),
        small("本地状态 · " + draft.state),
        secondary_button(
          emit,
          DraftAction(Resume(draft.id)),
          if draft.state == "created" {
            "打开正式任务"
          } else {
            "恢复草稿"
          },
        ),
        if draft.state == "editing" ||
          draft.state == "created" ||
          draft.state == "rejected" {
          secondary_button(
            emit,
            DraftAction(Discard(draft.id)),
            "移除此本地草稿",
          )
        } else {
          @html.nothing
        },
      ]
    }),
    div <| model.dispatch_recent_tasks.map(id => {
      div <| [
        a(href="?task=" + dispatch_url_encode(id), id),
        secondary_button(emit, SelectDispatchTask(id), "恢复正式记录"),
      ]
    }),
  ]
}
