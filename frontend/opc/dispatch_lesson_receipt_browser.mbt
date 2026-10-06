///|
extern "js" fn dispatch_lesson_origin(value : String) -> String =
  #| value => {try {const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&!u.username&&!u.password&&u.pathname==='/'&&!u.search&&!u.hash?u.origin:'';}catch(_){return '';}}

///|
extern "js" fn dispatch_lesson_observed_label(value : String) -> String =
  #| value => {try{return new Date(Number(value)*1000).toISOString();}catch(_){return value;}}

///|
extern "js" fn dispatch_lesson_pick_receipt(done : (String) -> Unit) =
  #| done => {const input=document.createElement('input');input.type='file';input.accept='.json,application/json';let ended=false,timer;const finish=text=>{if(ended)return;ended=true;clearTimeout(timer);done(text);};timer=setTimeout(()=>finish(''),120000);input.oncancel=()=>finish('');input.onchange=async()=>{const file=input.files?.[0];if(!file||file.size>131072){finish('');return;}try{finish(await file.text());}catch(_){finish('');}};try{input.click();}catch(_){finish('');}}

///|
extern "js" fn dispatch_lesson_connect_book_on(
  browser : LessonHandoffBrowser,
  origin : String,
  payload : String,
  selected : String,
  receipt_mode : Bool,
  source_done : (String) -> Unit,
  returned : (String, (Bool) -> Unit) -> Unit,
  closed : (String) -> Unit,
) =
  #| (browser,origin,payload,selected,receiptMode,sourceDone,returned,closed) => {
  #|   let url,nonce,child,selectedLesson;
  #|   try {
  #|     url=new URL(origin);if(!['https:','http:'].includes(url.protocol)||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw Error();
  #|     nonce=browser.crypto.randomUUID();if(typeof nonce!=='string'||!nonce)throw Error();selectedLesson=JSON.parse(selected);
  #|     url.search=new URLSearchParams({proj_lesson_source:browser.location.origin,proj_lesson_nonce:nonce}).toString();url.hash='task-lesson-handoff';
  #|     child=browser.open(url.href,'_blank');if(!child)throw Error();
  #|   } catch(_){sourceDone('{}');if(receiptMode)closed('unavailable');return;}
  #|   let ended=false,sourceEnded=false,timer;
  #|   const finish=reason=>{if(ended)return;ended=true;browser.clearTimeout(timer);browser.removeEventListener('message',receive);if(!sourceEnded){sourceEnded=true;sourceDone('{}');}if(receiptMode)closed(reason);};
  #|   const receive=event=>{
  #|     if(ended||event.source!==child||event.origin!==url.origin||event.data?.nonce!==nonce)return;
  #|     if(event.data.kind==='moonbook.lesson-ready.v1'){
  #|       try{if(child.closed){finish('closed');return;}const message={kind:'moonproj.lesson-handoff.v1',nonce,payload};if(selectedLesson!==null)message.selected_lesson=selectedLesson;child.postMessage(message,url.origin);}catch(_){finish('unavailable');}return;
  #|     }
  #|     if(event.data.kind==='moonbook.lesson-readback.v1'&&typeof event.data.payload==='string'&&event.data.payload.length<=2097152&&!sourceEnded){
  #|       sourceEnded=true;sourceDone(event.data.payload);browser.clearTimeout(timer);if(!receiptMode){finish('source');return;}timer=browser.setTimeout(()=>finish('timeout'),600000);return;
  #|     }
  #|     if(receiptMode&&sourceEnded&&event.data.kind==='moonbook.saved-lesson-return.v1'&&typeof event.data.payload==='string'&&event.data.payload.length<=131072){
  #|       const text=event.data.payload;let answered=false;returned(text,accepted=>{if(ended||answered||!accepted)return;answered=true;try{if(child.closed){finish('closed');return;}child.postMessage({kind:'moonproj.saved-lesson-received.v1',nonce,payload:text},url.origin);finish('received');}catch(_){finish('unavailable');}});
  #|     }
  #|   };
  #|   browser.addEventListener('message',receive);timer=browser.setTimeout(()=>finish('timeout'),120000);
  #| }
