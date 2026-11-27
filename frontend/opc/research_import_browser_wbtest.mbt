///|
extern "js" fn research_test_picker_setup() =
  #| () => {
  #|   globalThis.__researchPickerTest = { prior: globalThis.document, inputs: [] };
  #|   globalThis.document = { body: {appendChild: () => {}}, createElement: () => {
  #|     const item = {style: {}, events: {}, files: [], removed: false,
  #|       addEventListener(name, fn) { this.events[name] = fn; }, remove() { this.removed = true; }, click() {} };
  #|     globalThis.__researchPickerTest.inputs.push(item); return item;
  #|   }};
  #| }

///|
extern "js" fn research_test_picker_finish(
  index : Int32,
  text : String,
  size : Int32,
  failed : Bool,
) =
  #| (index,text,size,failed) => {
  #|   const input = globalThis.__researchPickerTest.inputs[index];
  #|   input.files = [{size, text: () => ({then(ok) { if (!failed) ok(text); return {catch(no) {if (failed) no();}}; }})}];
  #|   input.events.change();
  #| }

///|
extern "js" fn research_test_picker_removed(index : Int32) -> Bool =
  #| index => globalThis.__researchPickerTest.inputs[index].removed

///|
extern "js" fn research_test_picker_cleanup() =
  #| () => { if (globalThis.__moonprojResearchFileCancel) globalThis.__moonprojResearchFileCancel(); if (globalThis.__researchPickerTest.prior === undefined) delete globalThis.document; else globalThis.document = globalThis.__researchPickerTest.prior; delete globalThis.__researchPickerTest; }

///|
test "research actual local picker cancels replaced selection cleans up and handles read bounds" {
  research_test_picker_setup()
  defer research_test_picker_cleanup()
  let received : Array[(String, String)] = []
  research_pick_file((text, error) => received.push((text, error)))
  research_pick_file((text, error) => received.push((text, error)))
  assert_true(research_test_picker_removed(0))
  assert_eq(received.length(), 1)
  assert_eq(received[0].0, "")
  research_test_picker_finish(0, "stale", 5, false)
  assert_eq(received.length(), 1)
  research_test_picker_finish(1, "selected 学习", 30, false)
  assert_eq(received[1], ("selected 学习", ""))
  assert_true(research_test_picker_removed(1))
  research_pick_file((text, error) => received.push((text, error)))
  research_test_picker_finish(2, "too large", 8000001, false)
  assert_true(received[2].1.contains("8 MB"))
  research_pick_file((text, error) => received.push((text, error)))
  research_test_picker_finish(3, "not readable", 5, true)
  assert_true(received[3].1.contains("无法读取"))
  research_pick_file((text, error) => received.push((text, error)))
  research_cancel_file()
  assert_true(research_test_picker_removed(4))
  assert_true(received[4].1.contains("已取消"))
}

///|
test "research interrupted navigation executes picker cleanup and rejects late read" {
  research_test_picker_setup()
  defer research_test_picker_cleanup()
  let messages : Array[Msg] = []
  let (pick, choosing) = update(
    msg => {
      messages.push(msg)
      none
    },
    ResearchImportAction(Choose),
    { ..initial_model(), page: Dispatch, },
  )
  drafts_test_execute(pick)
  let (close, closed) = update(
    msg => {
      messages.push(msg)
      none
    },
    ResearchImportAction(Close),
    choosing,
  )
  drafts_test_execute(close)
  assert_true(research_test_picker_removed(0))
  assert_eq(messages.length(), 1)
  let (_, after) = update(_ => none, messages[0], closed)
  assert_false(after.research_import.open)
  assert_eq(after.research_import.brief, None)
}
