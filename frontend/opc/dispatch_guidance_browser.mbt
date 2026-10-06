///|
// Deliberately separate from the accepted-report lesson/receipt bridge.
// The URL contains only source origin and a nonce; all content is postMessage.
extern "js" fn dispatch_guidance_connect_book_on(
  browser : LessonHandoffBrowser,
  origin : String,
  payload : String,
  returned : (String, (Bool) -> Unit) -> Unit,
  closed : (String) -> Unit,
) -> () -> Unit =
  #| (browser,origin,payload,returned,closed) => {
  #|   let url,nonce,child,timer,ended=false,ready=false;
  #|   const finish=reason=>{if(ended)return;ended=true;try{browser.clearTimeout(timer);browser.removeEventListener('message',receive);}catch(_){}closed(reason);};
  #|   const receive=event=>{
  #|     if(ended||event.source!==child||event.origin!==url.origin||event.data?.nonce!==nonce)return;
  #|     if(child.closed){finish('closed');return;}
  #|     if(event.data.kind==='moonbook.guidance-ready.v1'){
  #|       if(ready)return;ready=true;
  #|       try{child.postMessage({kind:'moonproj.guidance-query.v1',nonce,payload},url.origin);browser.clearTimeout(timer);timer=browser.setTimeout(()=>finish(child.closed?'closed':'timeout'),600000);}catch(_){finish('unavailable');}return;
  #|     }
  #|     if(ready&&event.data.kind==='moonbook.guidance-selection.v1'&&typeof event.data.payload==='string'&&event.data.payload.length<=131072){
  #|       const text=event.data.payload;let answered=false;
  #|       returned(text,accepted=>{if(ended||answered||!accepted)return;answered=true;try{if(child.closed){finish('closed');return;}child.postMessage({kind:'moonproj.guidance-received.v1',nonce,payload:text},url.origin);finish('received');}catch(_){finish('unavailable');}});
  #|     }
  #|   };
  #|   try{
  #|     url=new URL(origin);if(!['http:','https:'].includes(url.protocol)||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw Error();
  #|     nonce=browser.crypto.randomUUID();if(typeof nonce!=='string'||!nonce)throw Error();
  #|     const source=new URL(browser.location.origin);if(!['http:','https:'].includes(source.protocol)||source.origin!==browser.location.origin)throw Error();
  #|     url.pathname='/apps/moonbook/';
  #|     url.search=new URLSearchParams({proj_guidance_source:source.origin,proj_guidance_nonce:nonce}).toString();url.hash='task-guidance-query';
  #|     child=browser.open(url.href,'_blank');if(!child)throw Error();
  #|     browser.addEventListener('message',receive);timer=browser.setTimeout(()=>finish(child.closed?'closed':'timeout'),120000);
  #|   }catch(_){finish('unavailable');}
  #|   return ()=>finish('cancelled');
  #| }
