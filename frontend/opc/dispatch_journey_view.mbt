///|
fn dispatch_journey_record_view(record : DispatchJourneyRecord) -> @html.Html {
  li <| [
    strong(record.label),
    p(
      "记录者 · " +
      dispatch_journey_known(record.actor) +
      " · 记录时间 · " +
      dispatch_journey_known(record.recorded_at),
    ),
    if record.detail.is_empty() {
      @html.nothing
    } else {
      p(record.detail)
    },
    if record.reference.is_empty() {
      @html.nothing
    } else {
      p <| [
        dispatch_result_reference(record.reference),
      ]
    },
    small(
      "事件 · " +
      dispatch_journey_known(record.event_id) +
      " · 审计 · " +
      dispatch_journey_known(record.audit_id),
    ),
    small(
      if record.audit_state == "available" {
        "审计记录已关联"
      } else {
        "审计记录待核对 · " + dispatch_journey_known(record.audit_state)
      },
    ),
  ]
}

///|
fn dispatch_journey_view(model : Model) -> @html.Html {
  if model.dispatch_task_id.is_empty() || model.dispatch_task_stage == "loading" {
    return @html.nothing
  }
  section(
    class="journey-section commitment-journey",
    id="dispatch-commitment-journey",
  ) <| [
    h3("这项工作走到哪一步"),
    small(
      "任务 · " +
      model.dispatch_task_id +
      " · 按工作环节排列，不代表时间先后",
    ),
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      match model.dispatch_journey_read_state {
        "loading" => "正在刷新；下方保留上次成功读取的记录。"
        "older" =>
          "收到较旧版本，未覆盖已知记录；最新状态仍待核对。"
        "unconfirmed" =>
          "新的状态尚未确认；下方是上次成功读取的记录，可用现有刷新按钮重试。"
        _ =>
          "最近成功读取的任务记录；不保证此刻仍是最新状态。"
      },
    ),
    @html.ol(style=["display:grid", "gap:10px", "padding-left:24px"]) <| dispatch_journey_stages(
      model,
    ).map(stage => {
      li <| [
        strong(stage.title + " · " + stage.state),
        if stage.owner.is_empty() {
          @html.nothing
        } else {
          small(
            (if stage.id == "work" { "负责人 · " } else { "记录者 · " }) +
            stage.owner,
          )
        },
        if stage.anchor.is_empty() {
          @html.nothing
        } else {
          div <| [
            a(href=stage.anchor, stage.link_label),
          ]
        },
        details(class="journey-details") <| [
          summary(
            if stage.records.is_empty() {
              "查看已知信息与缺口"
            } else {
              "查看本环节依据 · " +
              stage.records.length().to_string() +
              " 条"
            },
          ),
          p(stage.detail),
          if stage.records.is_empty() {
            small(
              "本环节尚无可展示的操作收据；未记录的负责人和时间保持未知。",
            )
          } else {
            ul <| stage.records.map(dispatch_journey_record_view)
          },
        ],
      ]
    }),
  ]
}
