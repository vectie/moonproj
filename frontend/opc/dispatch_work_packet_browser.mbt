///|
extern "js" fn work_packet_pick_file(receive : (String, String) -> Unit) =
  #| receive => {
  #|   if (globalThis.__moonprojWorkPacketCancel) globalThis.__moonprojWorkPacketCancel();
  #|   if (typeof document === 'undefined') { receive('', '本地文件选择器不可用。'); return; }
  #|   const input = document.createElement('input'); input.type = 'file'; input.accept = '.json,application/json'; input.style.display = 'none';
  #|   let done = false;
  #|   const cancel = () => finish('', '已取消文件选择。');
  #|   const finish = (text, error) => { if (done) return; done = true; input.remove(); if (globalThis.__moonprojWorkPacketCancel === cancel) delete globalThis.__moonprojWorkPacketCancel; receive(text, error); };
  #|   globalThis.__moonprojWorkPacketCancel = cancel;
  #|   input.addEventListener('cancel', cancel, {once: true});
  #|   input.addEventListener('change', () => {
  #|     const file = input.files && input.files[0];
  #|     if (!file) { finish('', '已取消文件选择。'); return; }
  #|     if (file.size > 262144) { finish('', '工作简报超过 256 KiB 读取上限。'); return; }
  #|     file.text().then(text => finish(text, '')).catch(() => finish('', '无法读取文件；请重新选择。'));
  #|   }, {once: true});
  #|   document.body.appendChild(input);
  #|   try { input.click(); } catch (_) { finish('', '无法打开文件选择器。'); }
  #| }

///|
extern "js" fn work_packet_cancel_file() =
  #| () => { if (globalThis.__moonprojWorkPacketCancel) globalThis.__moonprojWorkPacketCancel(); }

///|
extern "js" fn work_packet_download(text : String) =
  #| text => {
  #|   const url = URL.createObjectURL(new Blob([text], {type:'application/json;charset=utf-8'}));
  #|   const a = document.createElement('a'); a.href = url; a.download = 'moonproj-work-brief.json'; a.click();
  #|   setTimeout(() => URL.revokeObjectURL(url), 1000);
  #| }
