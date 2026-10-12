///|
fn brief_owner(d : Draft, id : String) -> String {
  if id.is_empty() {
    return "未分配"
  }
  match d.owners.filter(o => o.id == id).get(0) {
    Some(o) => o.name + " [" + id + "]"
    None => "未找到负责人 [" + id + "]"
  }
}

///|
fn brief_task(d : Draft, id : String) -> String {
  match d.tasks.filter(t => t.id == id).get(0) {
    Some(t) => t.name + " [" + t.id + "] · " + brief_owner(d, t.owner)
    None => "未找到任务 [" + id + "]"
  }
}

///|
/// Read-only planning context for one declared owner, retaining authored text.
pub fn owner_brief(
  d : Draft,
  owner : String,
  project_name : String,
) -> String raise InputError {
  let owners = d.owners.filter(o => o.id == owner)
  guard owners.length() == 1 else {
    raise Invalid("请选择一个当前计划中唯一的负责人。")
  }
  let who = owners[0]
  let tasks = d.tasks.filter(t => t.owner == owner)
  let ids = tasks.map(t => t.id)
  let out : Array[String] = [
    "负责人计划简报 / Owner planning brief",
    "项目：" + project_name,
    "负责人：" + who.name + " [" + who.id + "]",
    "职责：" + who.role,
    "仅为当前草稿的计划上下文；不是任务派发、工作完成、审批或付款凭证。",
    "日期与金额按原文保留；未推断工期、工作量或完成状态。分享前请检查自由文本。",
    "",
    "范围与依据",
    d.notes,
    "",
    "分配给此负责人的任务（" + tasks.length().to_string() + "）",
  ]
  if tasks.is_empty() {
    out.push("无已分配任务。")
  }
  for t in tasks {
    out.push("任务：" + t.name + " [" + t.id + "]")
    out.push("计划成本（原文）：" + t.cost + " " + d.currency)
    out.push("里程碑引用：" + t.milestone)
    out.push("直接前置任务：")
    if t.dependencies.is_empty() {
      out.push("无。")
    }
    for id in t.dependencies {
      out.push("- " + brief_task(d, id))
    }
    out.push("")
  }
  out.push("跨负责人交接：需要他人的前置任务")
  let mut incoming = 0
  for t in tasks {
    for id in t.dependencies {
      let other = d.tasks.filter(row => row.id == id).get(0)
      if !other.map(row => row.owner == owner).unwrap_or(false) {
        out.push(brief_task(d, id) + " → " + brief_task(d, t.id))
        incoming += 1
      }
    }
  }
  if incoming == 0 {
    out.push("无。")
  }
  out.push("")
  out.push("跨负责人交接：依赖此负责人工作的任务")
  let mut outgoing = 0
  for t in d.tasks {
    if t.owner != owner {
      for id in t.dependencies {
        if ids.contains(id) {
          out.push(brief_task(d, id) + " → " + brief_task(d, t.id))
          outgoing += 1
        }
      }
    }
  }
  if outgoing == 0 {
    out.push("无。")
  }
  out.push("")
  out.push("负责或任务涉及的里程碑")
  let milestones = d.milestones.filter(m => {
    m.owner == owner || tasks.any(t => t.milestone == m.id)
  })
  if milestones.is_empty() {
    out.push("无。")
  }
  for m in milestones {
    out.push(
      (if m.owner == owner { "本人负责：" } else { "任务上下文：" }) +
      m.name +
      " [" +
      m.id +
      "]",
    )
    out.push("负责人：" + brief_owner(d, m.owner))
    out.push("目标日期（原文）：" + m.date)
    out.push("验收条件：\n" + m.criteria)
    out.push("所需证据：\n" + m.evidence)
    out.push("")
  }
  for t in tasks {
    if !t.milestone.is_empty() && !d.milestones.any(m => m.id == t.milestone) {
      out.push("未找到里程碑 [" + t.milestone + "]，任务：" + t.id)
    }
  }
  out.push("")
  out.push("负责或任务涉及的风险")
  let risks = d.risks.filter(r => {
    r.owner == owner || r.tasks.any(id => ids.contains(id))
  })
  if risks.is_empty() {
    out.push("无。")
  }
  for r in risks {
    out.push(
      (if r.owner == owner { "本人负责：" } else { "任务上下文：" }) +
      r.summary +
      " [" +
      r.id +
      "]",
    )
    out.push("负责人：" + brief_owner(d, r.owner))
    out.push("程度（原文）：" + r.severity)
    out.push("应对措施：\n" + r.mitigation)
    out.push("涉及任务：")
    for id in r.tasks {
      out.push("- " + brief_task(d, id))
    }
    out.push("")
  }
  out.join("\n") + "\n"
}
