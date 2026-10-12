///|
fn dispatch_client_delivery_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  if dispatch_accepted_human_record(model) is None {
    return @html.nothing
  }
  let state = model.dispatch_client_delivery
  let send = emit.map(action => ClientDeliveryAction(action))
  section(class="journey-section client-delivery") <| [
    h3("准备客户交付包"),
    p(
      "将已接受的人工修订文本与简短交付说明一起下载。请检查正文是否适合分享；不会自动发送。",
    ),
    if state.pending {
      div <| [
        p("正在读取，请稍候…"),
        secondary_button(emit, ClientDeliveryAction(Close), "关闭预览"),
      ]
    } else if state.source.is_empty() {
      primary_button(emit, ClientDeliveryAction(Prepare), "预览交付包")
    } else {
      div <| [
        dispatch_task_input(
          "delivery-title",
          "交付标题",
          state.note.title,
          "客户看到的标题",
          send.map(value => Edit("title", value)),
        ),
        dispatch_task_input(
          "delivery-filename",
          "结果文件名",
          state.note.filename,
          "例如：市场建议.md",
          send.map(value => Edit("filename", value)),
        ),
        small(
          "UTF-8 文本保持原字节，扩展名不会转换文件格式。",
        ),
        div <| [
          ("summary", "交付说明", state.note.summary),
          ("review_request", "审阅请求", state.note.review_request),
        ].map(item => {
          let (field, title, value) = item
          div(class="field") <| [
            label(for_="delivery-" + field, title),
            @html.textarea(
              id="delivery-" + field,
              value~,
              rows=3,
              on_input=send.map(value => Edit(field, value)),
              "",
            ),
          ]
        }),
        details(class="journey-details", open=true) <| [
          summary("结果正文预览"),
          if state.body.is_empty() {
            p("此结果是空文本（0 字节）。")
          } else {
            @html.pre(class="human-revision-content", state.body)
          },
        ],
        details(class="journey-details") <| [
          summary("交付说明预览 · README.txt"),
          @html.pre(@client_delivery.readme(state.note)),
        ],
        details(class="journey-details") <| [
          summary("可选技术来源"),
          label(for_="delivery-include-source") <| [
            input(
              id="delivery-include-source",
              input_type=Checkbox,
              checked=state.include_source,
              on_change=send.map(_ => ToggleSource),
            ),
            span("附上 source-observation.json（含内部记录标识）"),
          ],
          small(
            "这是未签名的捕获来源，供技术核对；不证明客户接受或付款。",
          ),
        ],
        p(
          "ZIP 包含 " +
          state.note.filename +
          "、README.txt" +
          (if state.include_source { "、source-observation.json" } else { "" }),
        ),
        if @client_delivery.validate_note(state.note).is_empty() {
          primary_button(
            emit,
            ClientDeliveryAction(Download),
            "下载交付包 ZIP",
          )
        } else {
          p(@client_delivery.validate_note(state.note))
        },
        secondary_button(emit, ClientDeliveryAction(Close), "关闭预览"),
        small(
          "说明仅保留在本页；关闭预览、切换任务或刷新页面后重新准备。",
        ),
      ]
    },
    if state.notice.is_empty() {
      @html.nothing
    } else {
      p(
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        state.notice,
      )
    },
  ]
}
