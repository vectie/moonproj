///|
fn dispatch_lesson_keys(value : Json, allowed : Array[String]) -> Bool {
  match value {
    Object(fields) =>
      fields.length() == allowed.length() &&
      fields.keys().all(key => allowed.contains(key))
    _ => false
  }
}

///|
fn dispatch_lesson_ref(value : Json) -> Bool {
  dispatch_lesson_keys(value, ["record_id", "record_version", "record_digest"]) &&
  ["record_id", "record_version", "record_digest"].all(key => {
    !dispatch_json_text(value, key).is_blank()
  })
}

///|
fn dispatch_lesson_optional_ref(value : Json) -> Bool {
  value == Json::null() || dispatch_lesson_ref(value)
}

///|
fn dispatch_lesson_integer(value : Json) -> Bool {
  match value {
    Number(number, ..) =>
      number >= 0.0 && number <= 9007199254740991.0 && number.trunc() == number
    _ => false
  }
}

///|
fn dispatch_lesson_receipt_decode(
  payload : Json,
  expected_origin : String,
  selected : Json?,
  text : String,
) -> Result[Json, String] {
  let value = @json.parse(text) catch {
    _ => return Err("收据不是可读取的 JSON。")
  }
  guard dispatch_lesson_keys(value, [
      "contract_version", "book_origin", "observed_at", "receipt",
    ]) &&
    dispatch_json_text(value, "contract_version") ==
    "moonbook.saved-lesson-return.v1" &&
    dispatch_lesson_integer(dispatch_json_field(value, "observed_at")) else {
    return Err("不是支持的最小 Book 经验收据。")
  }
  let origin = dispatch_json_text(value, "book_origin")
  guard !origin.is_empty() &&
    dispatch_lesson_origin(origin) == origin &&
    (expected_origin.is_empty() || origin == expected_origin) else {
    return Err("收据不是来自此次选择的 Book 地址。")
  }
  let receipt = dispatch_json_field(value, "receipt")
  guard dispatch_lesson_keys(receipt, [
      "contract_version", "source_product", "destination_product", "task", "report",
      "submission", "outcome", "assessment", "assessment_review", "lesson", "lesson_id",
      "title", "state", "review", "current", "selection_review", "currentness", "journal_sequence",
      "activation_authorized", "external_side_effects_applied", "customer_acceptance",
      "cash",
    ]) &&
    receipt
    is {
      "contract_version": "moonbook.saved-lesson-receipt.v1",
      "source_product": "moonbook",
      "destination_product": "moonproj",
      "activation_authorized": false,
      "external_side_effects_applied": false,
      "customer_acceptance": "not_asserted",
      "cash": "not_asserted",
      ..
    } else {
    return Err("经验收据的合同或非授权声明不符。")
  }
  guard [
      "task", "report", "submission", "outcome", "assessment", "assessment_review",
      "lesson",
    ].all(key => dispatch_lesson_ref(dispatch_json_field(receipt, key))) &&
    dispatch_json_field(receipt, "task") == dispatch_json_field(payload, "task") &&
    dispatch_json_field(receipt, "report") ==
    dispatch_json_field(payload, "report") else {
    return Err(
      "收据的准确任务、报告或来源引用不符；请重新准备当前任务。",
    )
  }
  let lesson = dispatch_json_field(receipt, "lesson")
  guard selected is None || selected == Some(lesson) else {
    return Err("Book 返回了其他经验版本；保留原来的选择。")
  }
  let current = dispatch_json_field(receipt, "current")
  let currentness = dispatch_json_text(receipt, "currentness")
  let state = dispatch_json_text(receipt, "state")
  let review = dispatch_json_field(receipt, "review")
  guard !dispatch_json_text(receipt, "lesson_id").is_blank() &&
    !dispatch_json_text(receipt, "title").is_blank() &&
    dispatch_lesson_integer(dispatch_json_field(receipt, "journal_sequence")) &&
    dispatch_lesson_optional_ref(current) &&
    dispatch_lesson_optional_ref(
      dispatch_json_field(receipt, "selection_review"),
    ) else {
    return Err("经验标题、版本或当前性引用不完整。")
  }
  if state == "pending" {
    guard review == Json::null() &&
      currentness == "not_retained" &&
      current != lesson else {
      return Err("待审核经验不能声明已保留。")
    }
  } else if state == "retained" || state == "rejected" {
    guard dispatch_lesson_keys(review, [
        "receipt", "disposition", "reviewer_id", "decided_at",
      ]) &&
      dispatch_lesson_ref(dispatch_json_field(review, "receipt")) &&
      !dispatch_json_text(review, "reviewer_id").is_blank() &&
      dispatch_lesson_integer(dispatch_json_field(review, "decided_at")) &&
      dispatch_json_text(review, "disposition") ==
      (if state == "retained" { "Accept" } else { "Reject" }) else {
      return Err("经验状态缺少准确的具名审核决定。")
    }
    if state == "rejected" &&
      (currentness != "not_retained" || current == lesson) {
      return Err("拒绝的经验不能声明已保留。")
    }
    if state == "retained" &&
      !((currentness == "current" && current == lesson) ||
      (
        currentness == "historical" &&
        dispatch_lesson_ref(current) &&
        current != lesson
      ) ||
      (
        currentness == "legacy_unselected" &&
        current == Json::null() &&
        dispatch_json_field(receipt, "selection_review") == Json::null()
      )) {
      return Err("已保留经验的当前版本关系不明确。")
    }
  } else {
    return Err("经验审核状态不可用。")
  }
  Ok(value)
}

///|
fn dispatch_lesson_receipt_update(
  emit : @rabbita.Emit[Msg],
  model : Model,
  action : DispatchLessonHandoffMsg,
) -> (Cmd, Model) {
  let state = model.dispatch_lesson_handoff
  match action {
    ImportReceipt => {
      guard dispatch_lesson_current(model) &&
        !state.pending &&
        state.payload is Some(_) else {
        return (none, model)
      }
      let request = state.request + 1
      (
        @cmd.custom_cmd(_ => {
          dispatch_lesson_pick_receipt(text => {
            ignore(
              emit(
                LessonHandoffAction(
                  ReceiptImported(state.task_id, state.selection, request, text),
                ),
              ),
            )
          })
        }),
        {
          ..model,
          dispatch_lesson_handoff: {
            ..state,
            request,
            pending: true,
            receipt_waiting: false,
            receipt_direct: false,
            receipt_target: None,
            receipt_notice: "请选择从 Book 下载的经验收据文件…",
          },
        },
      )
    }
    ReceiptImported(task, selection, request, text) => {
      guard dispatch_lesson_current(model) &&
        state.pending &&
        state.task_id == task &&
        state.selection == selection &&
        state.request == request &&
        state.payload is Some(payload) else {
        return (none, model)
      }
      let result = dispatch_lesson_receipt_decode(payload, "", None, text)
      (
        none,
        {
          ..model,
          dispatch_lesson_handoff: {
            ..state,
            pending: false,
            receipt_direct: false,
            receipt: match result {
              Ok(value) => Some(value)
              Err(_) => state.receipt
            },
            receipt_notice: match result {
              Ok(_) =>
                "文件收据仅记录当时观察到的状态。重新打开同一 Book 并明确返回状态，才能获得新的主机读回。"
              Err(error) => "未导入收据；原收据已保留。" + error
            },
          },
        },
      )
    }
    ReceiptReturned(task, selection, request, origin, text, acknowledge) => {
      guard dispatch_lesson_current(model) &&
        state.receipt_waiting &&
        state.task_id == task &&
        state.selection == selection &&
        state.request == request &&
        state.payload is Some(payload) else {
        return (none, model)
      }
      match
        dispatch_lesson_receipt_decode(
          payload,
          origin,
          state.receipt_target,
          text,
        ) {
        Err(error) =>
          (
            none,
            {
              ..model,
              dispatch_lesson_handoff: {
                ..state,
                receipt_notice: "未接受直接返回：" + error,
              },
            },
          )
        Ok(value) =>
          (
            @cmd.custom_cmd(_ => acknowledge(true)),
            {
              ..model,
              dispatch_lesson_handoff: {
                ..state,
                receipt: Some(value),
                receipt_direct: true,
                receipt_waiting: false,
                receipt_notice: "已读回此 Book 明确返回的所选经验状态。这是观察收据，不是签名、公司状态变更、客户接受或收款。",
              },
            },
          )
      }
    }
    ReceiptEnded(task, selection, request, reason) => {
      guard dispatch_lesson_current(model) &&
        state.task_id == task &&
        state.selection == selection &&
        state.request == request else {
        return (none, model)
      }
      (
        none,
        {
          ..model,
          dispatch_lesson_handoff: {
            ..state,
            receipt_waiting: false,
            receipt_notice: if reason == "received" {
              state.receipt_notice
            } else {
              "直接返回连接已结束或不可用。保留现有收据；可重新打开此 Book，或导入下载的收据文件。"
            },
          },
        },
      )
    }
    _ => (none, model)
  }
}

///|
fn dispatch_lesson_receipt_view(
  emit : @rabbita.Emit[Msg],
  state : DispatchLessonHandoff,
) -> @html.Html {
  div <| [
    match state.receipt {
      None => @html.nothing
      Some(value) => {
        let receipt = dispatch_json_field(value, "receipt")
        let lesson = dispatch_json_field(receipt, "lesson")
        let review = dispatch_json_field(receipt, "review")
        div <| [
          p(
            "Book 经验 · " +
            dispatch_json_text(receipt, "title") +
            " · 版本 " +
            dispatch_json_text(lesson, "record_version"),
          ),
          p(
            "审核状态 · " +
            dispatch_json_text(receipt, "state") +
            " / 当前性 · " +
            dispatch_json_text(receipt, "currentness"),
          ),
          p(
            "具名审核人 · " +
            (if review == Json::null() {
              "尚无最终决定"
            } else {
              dispatch_json_text(review, "reviewer_id")
            }),
          ),
          p(
            (if state.receipt_direct {
              "本次 Book 主机读回 · "
            } else {
              "导入 / 已缓存观察（不是当前实时状态）· "
            }) +
            dispatch_lesson_observed_label(
              dispatch_json_field(value, "observed_at").stringify(),
            ),
          ),
          p("此 Book · " + dispatch_json_text(value, "book_origin")),
          p("经验准确引用 · " + lesson.stringify()),
          details <| [
            summary("查看来源与审核引用"),
            p("任务 · " + dispatch_json_field(receipt, "task").stringify()),
            p(
              "已接受报告 · " +
              dispatch_json_field(receipt, "report").stringify(),
            ),
            p(
              "经验审核 · " +
              dispatch_json_field(review, "receipt").stringify(),
            ),
            p(
              "当前经验 · " +
              dispatch_json_field(receipt, "current").stringify(),
            ),
            p(
              "版本选择审核 · " +
              dispatch_json_field(receipt, "selection_review").stringify(),
            ),
          ],
          secondary_button(
            emit,
            LessonHandoffAction(ReopenLesson),
            "Reopen in this Book · 重新打开准确经验",
          ),
        ]
      }
    },
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      state.receipt_notice,
    ),
  ]
}
