///|
fn plan_test_draft() -> @plan_workbench.Draft {
  {
    key: "plan-fixture",
    project_id: "company-actual",
    prepared_at: "2026-10-07T04:00:00Z",
    notes: "Synthetic UI fixture, not company evidence",
    currency: "CNY",
    limit: "1000.00",
    contingency: "100.00",
    owners: [{ id: "owner-test", name: "Test owner", role: "Plan preparer", }],
    milestones: [
      {
        id: "milestone-one",
        name: "Reviewable result",
        owner: "owner-test",
        date: "2026-10-31",
        criteria: "Traceable requirements\nReviewable deliverable",
        evidence: "Named reviewer receipt",
      },
    ],
    tasks: [
      {
        id: "task-design",
        name: "Design",
        owner: "owner-test",
        milestone: "milestone-one",
        cost: "200.25",
        dependencies: [],
      },
      {
        id: "task-review",
        name: "Review",
        owner: "owner-test",
        milestone: "milestone-one",
        cost: "300.00",
        dependencies: ["task-design"],
      },
    ],
    risks: [],
  }
}

///|
fn plan_test_model() -> Model {
  {
    ..initial_model(),
    page: Projects,
    dispatch_task_actor_id: "owner-test",
    plan: {
      ..plan_initial(),
      actor: "owner-test",
      selected: "company-actual",
      epoch: 1,
      phase: "editing",
      draft: Some(plan_test_draft()),
      projects: [
        {
          id: "company-actual",
          name: "Synthetic test project",
          source: "command",
        },
        {
          id: "company-second",
          name: "Second test project",
          source: "command",
        },
      ],
    },
  }
}

///|
extern "js" fn plan_test_browser() =
  #| () => { globalThis.__planTest={window:globalThis.window,fetch:globalThis.fetch,document:globalThis.document,Blob:globalThis.Blob,create:URL.createObjectURL,revoke:URL.revokeObjectURL,requests:[],downloads:[],store:new Map(),blobs:new Map()}; const s=globalThis.__planTest; globalThis.window={localStorage:{setItem:(k,v)=>s.store.set(k,v),getItem:k=>s.store.get(k)}}; globalThis.fetch=(url,options)=>{s.requests.push({url,...options});return {then:()=>({catch:()=>{}})}}; globalThis.Blob=class {constructor(parts,opts){this.text=parts.join('');this.type=opts.type}}; URL.createObjectURL=blob=>{const key='blob:test-'+s.blobs.size;s.blobs.set(key,blob);return key};URL.revokeObjectURL=()=>{}; globalThis.document={createElement:()=>({click(){const b=s.blobs.get(this.href);s.downloads.push({name:this.download,text:b.text,type:b.type})}})}; }

///|
extern "js" fn plan_test_cleanup() =
  #| () => {const s=globalThis.__planTest;globalThis.window=s.window;globalThis.fetch=s.fetch;globalThis.document=s.document;globalThis.Blob=s.Blob;URL.createObjectURL=s.create;URL.revokeObjectURL=s.revoke;delete globalThis.__planTest;}

///|
extern "js" fn plan_test_downloads() -> String =
  #| () => JSON.stringify(globalThis.__planTest.downloads)

///|
extern "js" fn plan_test_requests() -> String =
  #| () => JSON.stringify(globalThis.__planTest.requests)

///|
extern "js" fn plan_test_file(name : String, text : String) -> String =
  #| (name,text) => {const fs=require('fs'),p=process.env.MOONPROJ_PLAN_FIXTURE_DIR;if(!p)return ''; const path=p+'/'+name;if(text){fs.mkdirSync(p,{recursive:true});fs.writeFileSync(path,text);return text;}return fs.existsSync(path)?fs.readFileSync(path,'utf8'):'';}

///|
test "actual UI prepare transport emits scoped typed draft and repeat is blocked" {
  plan_test_browser()
  defer plan_test_cleanup()
  assert_true(plan_store("a.b", "c", "first"))
  assert_true(plan_store("a", "b.c", "second"))
  assert_eq(plan_restore("a.b", "c"), "first")
  assert_eq(plan_restore("a", "b.c"), "second")
  let model = plan_test_model()
  assert_eq(
    plan_url("company:actual"),
    "/api/company/projects/company:actual/prepared-plans",
  )
  ignore(plan_test_file("ui-colon-url.txt", plan_url("company:actual")))
  let (command, pending) = plan_update(_ => none, Prepare, model)
  drafts_test_execute(command)
  let calls = @json.parse(plan_test_requests())
  guard calls is Array(items) && items.length() == 1 else {
    fail("missing UI request")
  }
  assert_eq(
    products_text(items[0], "url"),
    "/api/company/projects/company-actual/prepared-plans",
  )
  let body = products_text(items[0], "body")
  assert_eq(@json.parse(body), ToJson::to_json(plan_test_draft()))
  ignore(plan_test_file("ui-request.json", body))
  let (repeat, unchanged) = plan_update(_ => none, Prepare, pending)
  assert_eq(products_test_effect_count(repeat), 0)
  assert_eq(unchanged.plan, pending.plan)
  let (_, edit) = plan_update(
    _ => none,
    Edit("task", "task-design", "name", "Changed design"),
    pending,
  )
  assert_eq(edit.plan.draft.unwrap().tasks[0].name, "Changed design")
  assert_true(edit.plan.prepared is None)
  assert_eq(edit.plan.phase, "editing")
  let (_, stale) = plan_update(
    _ => none,
    Read("owner-test", 1, 0, "plan-fixture", body, 200, "{}"),
    edit,
  )
  assert_eq(stale.plan, edit.plan)
  let (_, switched) = plan_update(_ => none, Choose("company-second"), edit)
  let (_, late) = plan_update(
    _ => none,
    Read("owner-test", 1, 0, "plan-fixture", body, 200, "{}"),
    switched,
  )
  assert_eq(late.plan, switched.plan)
  let (_, restored) = plan_update(_ => none, Choose("company-actual"), switched)
  assert_eq(restored.plan.draft.unwrap().tasks[0].name, "Changed design")
  let other_actor = plan_reconcile({
    ..restored,
    dispatch_task_actor_id: "different",
  })
  assert_true(other_actor.plan.draft is None)
  assert_true(other_actor.plan.prepared is None)
  let history_model = {
    ..model,
    plan: {
      ..model.plan,
      history_request: 2,
      history: [{ "key": "new-plan" }],
    },
  }
  let (_, old_history) = plan_update(
    _ => none,
    History(
      "owner-test", 1, "company-actual", 1, 200, "{\"project_id\":\"company-actual\",\"items\":[]}",
    ),
    history_model,
  )
  assert_eq(old_history.plan, history_model.plan)
}

///|
test "Projects renders real selection ordinary editor and explicit unavailable state" {
  let html = products_test_html(plan_test_model())
  for
    title in [
      "Synthetic test project", "范围、依据与排除项", "添加任务", "添加里程碑",
      "原生准备并保存计划", "保存历史",
    ] {
    assert_true(html.contains(title))
  }
  assert_false(html.contains("OPC Core v0.9"))
  let (_, failed) = plan_update(
    _ => none,
    Read("owner-test", 1, 0, "plan-fixture", "", 0, ""),
    {
      ..plan_test_model(),
      plan: { ..plan_test_model().plan, phase: "saving", },
    },
  )
  assert_eq(failed.plan.draft, plan_test_model().plan.draft)
  assert_true(failed.plan.prepared is None)
  assert_true(failed.plan.note.contains("网关"))
}

///|
test "actual native saved reply renders exact plan and download commands after reload" {
  let body = plan_test_file("gateway-response.json", "")
  if body.is_empty() {
    return
  }
  plan_test_browser()
  defer plan_test_cleanup()
  let model = plan_test_model()
  let pending = { ..model, plan: { ..model.plan, phase: "opening", }, }
  let (_, saved) = plan_update(
    _ => none,
    Read("owner-test", 1, 0, "plan-fixture", "", 200, body),
    pending,
  )
  assert_eq(saved.plan.phase, "prepared")
  let record = saved.plan.prepared.unwrap()
  assert_eq(
    products_text(record, "artifact_json"),
    plan_test_file("native-artifact.json", ""),
  )
  let html = products_test_html(saved)
  for
    text in [
      "Design", "Review", "Reviewable result", "50025", "39975", "下载可读计划",
      "下载类型化原生 artifact",
    ] {
    assert_true(html.contains(text))
  }
  ignore(plan_test_file("ui-render.html", html))
  ignore(plan_test_file("ui-readable.txt", products_text(record, "readable")))
  for typed in [false, true] {
    let (command, _) = plan_update(_ => none, Download(typed), saved)
    drafts_test_execute(command)
  }
  let downloads = @json.parse(plan_test_downloads())
  guard downloads is Array(files) && files.length() == 2 else {
    fail("missing download commands")
  }
  assert_eq(
    products_text(files[0], "text"),
    plan_test_file("native-readable.txt", ""),
  )
  assert_eq(
    products_text(files[1], "text"),
    plan_test_file("native-artifact.json", ""),
  )
  ignore(plan_test_file("ui-downloads.json", downloads.stringify(indent=2)))
  let (_, edited) = plan_update(
    _ => none,
    Edit("plan", "", "notes", "New scope"),
    saved,
  )
  let (download, _) = plan_update(_ => none, Download(true), edited)
  assert_eq(products_test_effect_count(download), 0)
  assert_true(edited.plan.prepared is None)
}
