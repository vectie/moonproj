///|
// Keep assessment data out of ProductDefinition and persisted draft snapshots.
// A large packaged backlog is neither company state nor a user's editable draft.
fn products_decode_inventories(
  body : String,
) -> Array[@work_inventory.Inventory]? {
  let root = @json.parse(body) catch { _ => return None }
  let values = match products_field(root, "products") {
    Array(values) => values
    _ => return None
  }
  let inventories : Array[@work_inventory.Inventory] = []
  for value in values {
    if !products_has(value, "work_inventory") {
      continue
    }
    let inventory = @work_inventory.parse(
      products_field(value, "work_inventory"),
      products_text(value, "id"),
    ) catch {
      _ => return None
    }
    inventories.push(inventory)
  }
  Some(inventories)
}

///|
fn products_inventory(
  state : ProductsState,
  id : String,
) -> @work_inventory.Inventory? {
  state.inventories.filter(item => item.product_id == id).get(0)
}

///|
fn products_inventory_read_state(body : String) -> String {
  let root = @json.parse(body) catch { _ => return "invalid" }
  let state = products_text(root, "work_inventory_state")
  if ["ready", "missing", "invalid"].contains(state) {
    state
  } else {
    "unavailable"
  }
}

///|
fn products_inventory_status(status : String) -> String {
  match status {
    "verified" => "已验证（声明范围）"
    "partial" => "部分实现 / 待完整验收"
    "planned" => "已规划 / 待实现核对"
    "missing" => "已确认缺失"
    "unverified" => "当前未验证"
    _ => "全部"
  }
}

///|
fn products_inventory_estimate(group : @work_inventory.WorkGroup) -> String {
  products_inventory_range(group.estimate_low_days, group.estimate_high_days)
}

///|
fn products_inventory_range(low : Int32?, high : Int32?) -> String {
  match (low, high) {
    (Some(low), Some(high)) =>
      "估计 " + low.to_string() + "–" + high.to_string() + " 工程人日"
    _ => "工作量未定：先补齐证据"
  }
}

///|
fn products_inventory_summary(inventory : @work_inventory.Inventory) -> String {
  inventory.requirements.length().to_string() +
  " 项 PRD 要求 · " +
  inventory.count("partial").to_string() +
  " 部分 · " +
  inventory.count("planned").to_string() +
  " 规划 · " +
  inventory.count("unverified").to_string() +
  " 未验证 · " +
  inventory.count("verified").to_string() +
  " 已验证 · " +
  inventory.count("missing").to_string() +
  " 已知缺失"
}

///|
fn products_inventory_visible(
  state : ProductsState,
  inventory : @work_inventory.Inventory,
) -> Array[@work_inventory.Requirement] {
  let query = state.inventory_query.trim().to_owned().to_lower()
  inventory.requirements.filter(row => {
    (state.inventory_filter == "all" || row.status == state.inventory_filter) &&
    (
      query.is_empty() ||
      (row.id + " " + row.title + " " + row.statement)
      .to_lower()
      .contains(query)
    )
  })
}

///|
fn products_pending_work(state : ProductsState) -> @work_inventory.WorkGroup? {
  if state.state != "ready" || state.pending_work_group_id.is_empty() {
    return None
  }
  match products_inventory(state, state.selected_id) {
    Some(inventory) =>
      inventory.groups
      .filter(group => group.id == state.pending_work_group_id)
      .get(0)
    None => None
  }
}

///|
fn products_prepare_inventory_work(
  emit : @rabbita.Emit[Msg],
  model : Model,
  product_id : String,
  group_id : String,
) -> (Cmd, Model) {
  let state = model.products
  if state.state != "ready" || state.selected_id != product_id {
    return (none, model)
  }
  let row = match products_selected(state) {
    Some(row) => row
    None => return (none, model)
  }
  let inventory = match products_inventory(state, product_id) {
    Some(inventory) => inventory
    None => return (none, model)
  }
  let group = match
    inventory.groups.filter(group => group.id == group_id).get(0) {
    Some(group) => group
    None => return (none, model)
  }
  if !products_project_exists(state) {
    let chosen = {
      ..model,
      products: { ..state, pending_work_group_id: group.id, },
      notice: "已保留所选工作。读取公司项目并选择本次归属后，继续准备同一工作；尚未创建草稿或正式任务。",
    }
    // Read the existing project picker once. Repeated choices while loading
    // never restart the request; failures retain an explicit retry action.
    return if state.project_state == "idle" {
      products_update(emit, LoadProjects, chosen)
    } else {
      (none, chosen)
    }
  }
  let (_, prepared) = dispatch_prepare_draft(
    emit,
    { ..model, products: { ..state, pending_work_group_id: "", }, },
    row.id,
    state.project_id,
    Some(row),
    false,
  )
  let draft = dispatch_active_draft(prepared).unwrap()
  if draft.state != "editing" ||
    draft.attempted ||
    !(draft.title == row.name + " · " && draft.acceptance.is_empty()) {
    // Resume exactly what the user has already written or attempted. Never
    // replace it with a newly selected requirement or create a duplicate.
    return (
      none,
      {
        ..prepared,
        notice: "已打开此产品和项目的已有草稿，保留你的修改与请求身份。若要另做此工作，请先明确新建草稿；清单没有提交正式任务。",
      },
    )
  }
  let acceptance = "PRD 工作清单：" +
    group.id +
    " · " +
    inventory.as_of +
    "\n" +
    "范围：" +
    group.requirement_ids.join(", ") +
    "\n" +
    "下一步：" +
    group.next_action +
    "\n" +
    "验收：\n" +
    group.acceptance.join("\n") +
    "\n" +
    "依赖：" +
    group.dependencies.join("; ") +
    "\n" +
    "完整要求以产品 PRD 为准；清单状态不代表任务或客户验收。"
  let (save, next) = dispatch_save_draft(emit, prepared, {
    ..draft,
    title: row.name + " · " + group.id + " · " + group.title,
    acceptance,
  })
  (
    save,
    {
      ..next,
      notice: "已按所选工作范围准备本地草稿。请检查验收标准、日期、负责人和授权工作区；尚未创建或启动正式任务。",
    },
  )
}
