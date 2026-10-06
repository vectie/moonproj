///|
fn dispatch_human_revision_view(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @html.Html {
  let state = model.dispatch_continuation
  let candidate = state.human_revision_candidate
  details(class="journey-details", open=state.preview_revision != "") <| [
    summary("人工修订 · 查看并明确选择"),
    small(
      "人工保存的内容快照独立保留；原始执行、后续执行和已保存报告不会被改写。",
    ),
    div <| state.human_revisions.map(record => {
      div <| [
        strong("人工修订 · " + dispatch_json_text(record, "revision_id")),
        p(dispatch_json_text(dispatch_json_field(record, "output"), "path")),
        secondary_button(
          emit,
          ContinuationAction(
            PreviewHumanRevision(dispatch_json_text(record, "revision_id")),
          ),
          "查看此准确人工修订",
        ),
      ]
    }),
    if !(candidate is Null) {
      let content = dispatch_json_field(candidate, "content")
      let base = dispatch_json_field(candidate, "base")
      let output = dispatch_json_field(candidate, "output")
      details(open=true) <| [
        summary(
          "候选人工修订 · " +
          dispatch_json_text(candidate, "revision_id"),
        ),
        p(
          "作者类型 · 人工 / 保存时间 · " +
          dispatch_json_text(candidate, "created_at"),
        ),
        p("修改文件 · " + dispatch_json_text(output, "path")),
        p("不可变内容快照 · " + dispatch_json_text(content, "path")),
        p("内容 SHA-256 · " + dispatch_json_text(content, "sha256")),
        strong("准确人工修订内容 · 不可变快照"),
        if state.human_revision_content == "" {
          small("此人工修订保存了空文本（0 字节）。")
        } else {
          @html.nothing
        },
        @html.pre(class="human-revision-content", state.human_revision_content),
        p(
          "快照字节数 · " +
          dispatch_json_field(content, "size_bytes").stringify(),
        ),
        p(
          "基线 · 编辑开始时工作区的当前文件字节 / SHA-256 · " +
          dispatch_json_text(base, "sha256"),
        ),
        small(
          "原始运行 · " +
          dispatch_json_text(candidate, "original_run_id") +
          " / 历史输出命令 · " +
          dispatch_json_text(output, "command_id") +
          " / 历史输出证据 · " +
          dispatch_json_text(output, "evidence_id"),
        ),
        small(
          "此修订由人编辑保存，没有新的模型执行、命令或执行回执。返回链接只打开预览。",
        ),
        if state.phase == "ready" &&
          !state.accepted &&
          !dispatch_task_inspection_only(model) &&
          dispatch_human_revision_valid(model, candidate) &&
          dispatch_human_revision_content_valid(
            candidate,
            Json::string(state.human_revision_content),
          ) {
          secondary_button(
            emit,
            ContinuationAction(SelectHumanRevision),
            "明确选择此人工修订用于报告",
          )
        } else {
          small(
            "此处仅供查看；已接受任务的交付来源和报告不会改变。",
          )
        },
      ]
    } else if state.preview_revision != "" {
      p("等待服务端核实准确人工修订 · " + state.preview_revision)
    } else {
      @html.nothing
    },
  ]
}
