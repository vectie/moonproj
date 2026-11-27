///|
fn workbench_key(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 100 &&
  value
  .iter()
  .all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-')
}

///|
fn workbench_base(actor : String, project : String) -> String {
  ".moonsuite/products/moonproj/project-plans/" +
  sha256_text(actor)[7:].to_owned() +
  "/" +
  sha256_text(project)[7:].to_owned()
}

///|
fn workbench_project(project : Json, id : String) -> Json raise {
  guard project
    is {
      "project_id": String(actual),
      "project_name": String(name),
      "project_code": String(code),
      "bu_guid": String(unit),
      ..
    } &&
    actual == id &&
    !name.trim().is_empty() &&
    !code.trim().is_empty() &&
    !unit.trim().is_empty() else {
    fail(
      "Selected company project identity or business-unit scope is unavailable; refresh Projects",
    )
  }
  // The observed business-unit scope is a workspace identity, never a claim of legal registration.
  { "project_id": id, "principal_id": unit, "code": code, "name": name }
}

///|
pub async fn prepare_workbench(
  workspace : String,
  actor : String,
  project : Json,
  input : Json,
) -> Json {
  let draft : @plan_workbench.Draft = @json.from_json(input)
  guard workbench_key(draft.key) && !actor.trim().is_empty() else {
    fail("Invalid planning request identity")
  }
  let root = resolve_workspace(workspace)
  let identity = workbench_project(project, draft.project_id)
  let base = workbench_base(actor, draft.project_id) + "/" + draft.key
  let source_ref = base + "/source.json"
  let source : Json = {
    "actor": actor,
    "project": identity,
    "draft": ToJson::to_json(draft),
  }
  let source_text = source.stringify(indent=2) + "\n"
  let request_json = @plan_workbench.request(
    draft,
    actor,
    identity,
    source_ref,
    sha256_text(source_text),
  )
  let request = @project_plan.decode_request(request_json)
  let artifact = @project_plan.prepare(
    request,
    draft.key,
    sha256_text(request_json.stringify()),
    draft.prepared_at,
  )
  let artifact_json = ToJson::to_json(artifact)
  let artifact_text = artifact_json.stringify(indent=2) + "\n"
  let envelope : Json = {
    "contract": "moonproj.project-plan-workbench.v1",
    "actor": actor,
    "draft": ToJson::to_json(draft),
    "source": source,
    "request": request_json,
    "artifact": artifact_json,
    "artifact_json": artifact_text,
    "artifact_sha256": sha256_text(artifact_text),
    "readable": "Scope and source notes (author-supplied)\n" +
    draft.notes +
    "\n\n" +
    @plan_workbench.readable(artifact_json),
    "key": draft.key,
    "project_id": draft.project_id,
    "persisted": true,
  }
  // Reuse the adapter's immutable create-only, synced workspace artifact store.
  // Native validation completes before any persistence. A repeat must match all bytes.
  ignore(immutable_text_ref(root, source_ref, source_text))
  ignore(immutable_json_ref(root, base + "/plan.json", envelope))
  read_workbench(workspace, actor, draft.project_id, draft.key)
}

///|
pub async fn read_workbench(
  workspace : String,
  actor : String,
  project : String,
  key : String,
) -> Json {
  guard workbench_key(key) else { fail("Invalid planning request identity") }
  let root = resolve_workspace(workspace)
  let base = workbench_base(actor, project) + "/" + key
  let envelope = read_json_ref(root, base + "/plan.json")
  guard envelope
    is {
      "contract": "moonproj.project-plan-workbench.v1",
      "actor": String(saved_actor),
      "key": String(saved_key),
      "project_id": String(saved_project),
      "persisted": true,
      "draft": input,
      "source": source,
      "request": request_json,
      "artifact": artifact_json,
      "artifact_json": String(artifact_text),
      "artifact_sha256": String(digest),
      "readable": String(readable),
      ..
    } &&
    saved_actor == actor &&
    saved_key == key &&
    saved_project == project else {
    fail("Saved plan identity mismatch")
  }
  let draft : @plan_workbench.Draft = @json.from_json(input)
  let source_text = read_text_ref(root, base + "/source.json")
  let identity = @plan_workbench.field(source, "project")
  guard @json.parse(source_text) == source &&
    draft.project_id == project &&
    draft.key == key &&
    @plan_workbench.text(identity, "project_id") == project &&
    source == ({ "actor": actor, "project": identity, "draft": input } : Json) &&
    request_json ==
    @plan_workbench.request(
      draft,
      actor,
      identity,
      base + "/source.json",
      sha256_text(source_text),
    ) else {
    fail("Saved planning source has changed")
  }
  let request = @project_plan.decode_request(request_json)
  let expected = ToJson::to_json(
    @project_plan.prepare(
      request,
      key,
      sha256_text(request_json.stringify()),
      draft.prepared_at,
    ),
  )
  guard expected == artifact_json &&
    @json.parse(artifact_text) == expected &&
    digest == sha256_text(artifact_text) &&
    readable ==
    "Scope and source notes (author-supplied)\n" +
    draft.notes +
    "\n\n" +
    @plan_workbench.readable(expected) else {
    fail("Saved plan no longer matches its exact native prepared result")
  }
  envelope
}

///|
pub async fn list_workbench(
  workspace : String,
  actor : String,
  project : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let reference = workbench_base(actor, project)
  if !@fs.exists(scoped_path(root, reference)) {
    return { "items": [], "project_id": project }
  }
  let directory = checked_input_path(root, reference)
  let summaries : Map[String, Json] = Map([])
  let order : Array[((Int64, Int32), String)] = []
  for key in @fs.readdir(directory) {
    if !workbench_key(key) {
      continue
    }
    let path = reference + "/" + key + "/plan.json"
    if !@fs.exists(scoped_path(root, path)) {
      continue
    }
    // A corrupt saved plan is an error, never a silently missing result.
    let saved = read_workbench(workspace, actor, project, key)
    let artifact = @plan_workbench.field(saved, "artifact")
    summaries[key] = {
      "key": key,
      "recorded_at": @plan_workbench.text(artifact, "recorded_at"),
      "status": "pending_review",
    }
    order.push((@fs.mtime(checked_input_path(root, path)), key))
  }
  order.sort()
  let newest : Array[Json] = []
  for i in 0..<order.length() {
    if i >= 100 {
      break
    }
    newest.push(summaries[order[order.length() - i - 1].1])
  }
  {
    "items": Json::array(newest),
    "project_id": project,
    "limit": 100,
    "total_count": order.length(),
    "truncated": order.length() > 100,
  }
}
