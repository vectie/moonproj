///|
// Local file input only. Source URLs are displayed as text and never fetched.
extern "js" fn research_pick_file(receive : (String, String) -> Unit) =
  #| receive => {
  #|   if (globalThis.__moonprojResearchFileCancel) globalThis.__moonprojResearchFileCancel();
  #|   if (typeof document === 'undefined') { receive('', '本地文件选择器不可用。'); return; }
  #|   const input = document.createElement('input'); input.type = 'file'; input.accept = '.json,application/json'; input.style.display = 'none';
  #|   let done = false;
  #|   const cancel = () => finish('', '已取消文件选择。');
  #|   const finish = (text, error) => { if (done) return; done = true; input.remove(); if (globalThis.__moonprojResearchFileCancel === cancel) delete globalThis.__moonprojResearchFileCancel; receive(text, error); };
  #|   globalThis.__moonprojResearchFileCancel = cancel;
  #|   input.addEventListener('cancel', () => finish('', '已取消文件选择。'), {once: true});
  #|   input.addEventListener('change', () => {
  #|     const file = input.files && input.files[0];
  #|     if (!file) { finish('', '已取消文件选择。'); return; }
  #|     if (file.size > 8000000) { finish('', '文件超过 8 MB 读取上限。'); return; }
  #|     file.text().then(text => finish(text, '')).catch(() => finish('', '无法读取文件；请重新选择。'));
  #|   }, {once: true});
  #|   document.body.appendChild(input);
  #|   try { input.click(); } catch (_) { finish('', '无法打开文件选择器。'); }
  #| }

///|
extern "js" fn research_cancel_file() =
  #| () => { if (globalThis.__moonprojResearchFileCancel) globalThis.__moonprojResearchFileCancel(); }

///|
extern "js" fn research_download_packet(text : String) =
  #| text => {
  #|   const url = URL.createObjectURL(new Blob([text], {type:'text/markdown;charset=utf-8'}));
  #|   const a = document.createElement('a'); a.href = url; a.download = 'moonproj-founder-work-packet.md'; a.click();
  #|   setTimeout(() => URL.revokeObjectURL(url), 1000);
  #| }
