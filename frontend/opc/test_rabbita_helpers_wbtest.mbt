///|
#cfg(target="js")
extern "js" fn opc_with_render_dom(mount : () -> Unit) -> String =
  #| mount => {
  #|   const hadWindow = Object.prototype.hasOwnProperty.call(globalThis, "window");
  #|   const prevWindow = globalThis.window;
  #|   const hadDocument = Object.prototype.hasOwnProperty.call(globalThis, "document");
  #|   const prevDocument = globalThis.document;
  #|   const hadHTMLElement = Object.prototype.hasOwnProperty.call(globalThis, "HTMLElement");
  #|   const prevHTMLElement = globalThis.HTMLElement;
  #|   const hadSVGElement = Object.prototype.hasOwnProperty.call(globalThis, "SVGElement");
  #|   const prevSVGElement = globalThis.SVGElement;
  #|
  #|   const S_TYPE = Symbol("type");
  #|   const S_TAG = Symbol("tag");
  #|   const S_NS = Symbol("ns");
  #|   const S_CHILDREN = Symbol("children");
  #|   const S_ATTRS = Symbol("attrs");
  #|   const S_STYLES = Symbol("styles");
  #|   const S_STYLE_OBJ = Symbol("styleObj");
  #|   const S_INNER = Symbol("innerHTML");
  #|   const S_TEXT = Symbol("textContent");
  #|   const S_DATA = Symbol("data");
  #|   const S_PARENT = Symbol("parent");
  #|
  #|   const VOID_TAGS = new Set([
  #|     "area", "base", "br", "col", "embed", "hr", "img", "input",
  #|     "link", "meta", "param", "source", "track", "wbr",
  #|   ]);
  #|   const RAW_TEXT_TAGS = new Set([
  #|     "script", "style", "xmp", "iframe", "noembed", "noframes", "plaintext",
  #|   ]);
  #|
  #|   const escapeText = s =>
  #|     String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  #|   const escapeAttr = s =>
  #|     String(s)
  #|       .replace(/&/g, "&amp;")
  #|       .replace(/</g, "&lt;")
  #|       .replace(/>/g, "&gt;")
  #|       .replace(/"/g, "&quot;")
  #|       .replace(/'/g, "&#39;");
  #|
  #|   class MockNode {
  #|     constructor(nodeType) {
  #|       this[S_TYPE] = nodeType;
  #|       this[S_CHILDREN] = [];
  #|       this[S_PARENT] = null;
  #|     }
  #|     get nodeType() { return this[S_TYPE]; }
  #|     get parentNode() { return this[S_PARENT]; }
  #|     get childNodes() { return this[S_CHILDREN]; }
  #|     get nextSibling() {
  #|       const p = this[S_PARENT];
  #|       if (!p) return null;
  #|       const idx = p[S_CHILDREN].indexOf(this);
  #|       return idx >= 0 && idx + 1 < p[S_CHILDREN].length ? p[S_CHILDREN][idx + 1] : null;
  #|     }
  #|     get previousSibling() {
  #|       const p = this[S_PARENT];
  #|       if (!p) return null;
  #|       const idx = p[S_CHILDREN].indexOf(this);
  #|       return idx > 0 ? p[S_CHILDREN][idx - 1] : null;
  #|     }
  #|     isSameNode(other) { return this === other; }
  #|     appendChild(child) {
  #|       return this.insertBefore(child, null);
  #|     }
  #|     removeChild(child) {
  #|       const idx = this[S_CHILDREN].indexOf(child);
  #|       if (idx >= 0) {
  #|         this[S_CHILDREN].splice(idx, 1);
  #|         child[S_PARENT] = null;
  #|       }
  #|       return child;
  #|     }
  #|     insertBefore(child, before) {
  #|       if (child[S_TYPE] === 11) {
  #|         const moved = child[S_CHILDREN].slice();
  #|         child[S_CHILDREN].length = 0;
  #|         for (const item of moved) {
  #|           item[S_PARENT] = null;
  #|           this.insertBefore(item, before);
  #|         }
  #|         return child;
  #|       }
  #|       if (child[S_PARENT]) {
  #|         child[S_PARENT].removeChild(child);
  #|       }
  #|       child[S_PARENT] = this;
  #|       if (before == null) {
  #|         this[S_CHILDREN].push(child);
  #|       } else {
  #|         const idx = this[S_CHILDREN].indexOf(before);
  #|         if (idx >= 0) this[S_CHILDREN].splice(idx, 0, child);
  #|         else this[S_CHILDREN].push(child);
  #|       }
  #|       return child;
  #|     }
  #|     addEventListener() {}
  #|     removeEventListener() {}
  #|   }
  #|
  #|   class MockElement extends MockNode {
  #|     constructor(tag, ns) {
  #|       super(1);
  #|       this[S_TAG] = tag;
  #|       this[S_NS] = ns || null;
  #|       this[S_ATTRS] = new Map();
  #|       this[S_STYLES] = new Map();
  #|       this[S_INNER] = null;
  #|       this[S_TEXT] = null;
  #|       this[S_STYLE_OBJ] = {
  #|         setProperty: (k, v) => { this[S_STYLES].set(String(k), String(v)); },
  #|         removeProperty: k => { this[S_STYLES].delete(String(k)); },
  #|         getPropertyValue: k => this[S_STYLES].get(String(k)) || "",
  #|       };
  #|     }
  #|     get style() { return this[S_STYLE_OBJ]; }
  #|     get innerHTML() { return this[S_INNER] || ""; }
  #|     set innerHTML(v) {
  #|       this[S_INNER] = String(v);
  #|       this[S_CHILDREN].length = 0;
  #|     }
  #|     get textContent() { return this[S_TEXT] == null ? "" : String(this[S_TEXT]); }
  #|     set textContent(v) { this[S_TEXT] = v; }
  #|     setAttribute(k, v) { this[S_ATTRS].set(String(k), String(v)); }
  #|     getAttribute(k) { return this[S_ATTRS].has(String(k)) ? this[S_ATTRS].get(String(k)) : null; }
  #|     hasAttribute(k) { return this[S_ATTRS].has(String(k)); }
  #|     removeAttribute(k) { this[S_ATTRS].delete(String(k)); }
  #|   }
  #|
  #|   class MockHTMLElement extends MockElement {}
  #|   class MockSVGElement extends MockElement {}
  #|   class MockText extends MockNode {
  #|     constructor(data) {
  #|       super(3);
  #|       this[S_DATA] = String(data);
  #|     }
  #|   }
  #|   class MockComment extends MockNode {
  #|     constructor(data) {
  #|       super(8);
  #|       this[S_DATA] = String(data);
  #|     }
  #|   }
  #|   class MockFragment extends MockNode {
  #|     constructor() { super(11); }
  #|   }
  #|
  #|   const serializeNode = (node, inRawText) => {
  #|     if (node[S_TYPE] === 3) {
  #|       return inRawText ? node[S_DATA] : escapeText(node[S_DATA]);
  #|     }
  #|     if (node[S_TYPE] === 8) {
  #|       if (node[S_DATA] === "[" || node[S_DATA] === "]") return "";
  #|       return "<!--" + node[S_DATA] + "-->";
  #|     }
  #|     if (node[S_TYPE] === 11) {
  #|       return node[S_CHILDREN].map(c => serializeNode(c, inRawText)).join("");
  #|     }
  #|     if (node[S_TYPE] !== 1) return "";
  #|     const tag = node[S_TAG];
  #|     const rawChild = RAW_TEXT_TAGS.has(tag);
  #|     const attrs = node[S_ATTRS];
  #|     const styles = node[S_STYLES];
  #|     let out = "<" + tag;
  #|     if (node[S_NS] && tag === "svg" && !attrs.has("xmlns")) {
  #|       out += ' xmlns="' + escapeAttr(node[S_NS]) + '"';
  #|     }
  #|     for (const [k, v] of attrs.entries()) {
  #|       if (k === "innerHTML" || k === "style") continue;
  #|       out += " " + k + '="' + escapeAttr(v) + '"';
  #|     }
  #|     if (attrs.has("style") || styles.size > 0) {
  #|       let styleStr = "";
  #|       let needSep = false;
  #|       if (attrs.has("style")) {
  #|         const s = attrs.get("style");
  #|         styleStr += escapeAttr(s);
  #|         needSep = s.length > 0 && !s.endsWith(";");
  #|       }
  #|       for (const [k, v] of styles.entries()) {
  #|         if (needSep) styleStr += ";";
  #|         styleStr += k + ":" + escapeAttr(v);
  #|         needSep = true;
  #|       }
  #|       out += ' style="' + styleStr + '"';
  #|     }
  #|     for (const [prop, val] of Object.entries(node)) {
  #|       if (prop === "textContent" || prop === "innerHTML" || prop === "style") continue;
  #|       if (tag === "textarea" && prop === "value") continue;
  #|       const name = prop === "className" ? "class" : prop.toLowerCase();
  #|       if (attrs.has(name)) continue;
  #|       if (typeof val === "boolean") {
  #|         if (val) out += " " + name;
  #|       } else if (typeof val === "number" || typeof val === "string") {
  #|         out += " " + name + '="' + escapeAttr(String(val)) + '"';
  #|       }
  #|     }
  #|     out += ">";
  #|     if (VOID_TAGS.has(tag)) return out;
  #|     if (node[S_INNER]) out += node[S_INNER];
  #|     if (node[S_TEXT] != null) {
  #|       out += rawChild ? String(node[S_TEXT]) : escapeText(node[S_TEXT]);
  #|     }
  #|     if (tag === "textarea" && typeof node.value === "string") {
  #|       out += escapeText(node.value);
  #|     } else {
  #|       for (const c of node[S_CHILDREN]) out += serializeNode(c, rawChild);
  #|     }
  #|     out += "</" + tag + ">";
  #|     return out;
  #|   };
  #|
  #|   const root = new MockHTMLElement("div", null);
  #|   const mockDoc = {
  #|     baseURI: "http://localhost/",
  #|     getElementById: id => id === "__opc_render_root" ? root : null,
  #|     createElement: tag => new MockHTMLElement(String(tag), null),
  #|     createElementNS: (ns, tag) =>
  #|       String(ns).includes("svg")
  #|         ? new MockSVGElement(String(tag), String(ns))
  #|         : new MockHTMLElement(String(tag), String(ns)),
  #|     createTextNode: s => new MockText(s),
  #|     createComment: s => new MockComment(s),
  #|     createDocumentFragment: () => new MockFragment(),
  #|   };
  #|   const mockWin = {
  #|     location: { href: "http://localhost/", origin: "http://localhost" },
  #|     queueMicrotask: () => {},
  #|     requestAnimationFrame: () => 0,
  #|     document: mockDoc,
  #|   };
  #|
  #|   globalThis.HTMLElement = MockHTMLElement;
  #|   globalThis.SVGElement = MockSVGElement;
  #|   globalThis.document = mockDoc;
  #|   globalThis.window = mockWin;
  #|   try {
  #|     mount();
  #|     return root[S_CHILDREN].map(c => serializeNode(c, false)).join("");
  #|   } finally {
  #|     if (hadWindow) globalThis.window = prevWindow; else delete globalThis.window;
  #|     if (hadDocument) globalThis.document = prevDocument; else delete globalThis.document;
  #|     if (hadHTMLElement) globalThis.HTMLElement = prevHTMLElement; else delete globalThis.HTMLElement;
  #|     if (hadSVGElement) globalThis.SVGElement = prevSVGElement; else delete globalThis.SVGElement;
  #|   }
  #| }

///|
fn opc_render_cell(cell : () -> @rabbita.Val[@html.Html]) -> String {
  opc_with_render_dom(() => @rabbita.new(cell).mount("__opc_render_root"))
}

///|
priv struct OpcTestScheduler {}

///|
#warnings("-alert_experimental")
impl @cmd.Context for OpcTestScheduler with fn get_base_uri(_) {
  "http://localhost/"
}

///|
#warnings("-alert_experimental")
impl @cmd.Context for OpcTestScheduler with fn inject_url_changed(_, _) {
  none
}

///|
#warnings("-alert_experimental")
impl @cmd.Context for OpcTestScheduler with fn inject_url_request(_, _) {
  none
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for OpcTestScheduler with fn queue_command(self, cmd) {
  opc_run_cmd_with_scheduler(self, cmd)
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for OpcTestScheduler with fn set_url_changed_injector(_, _) {
  ()
}

///|
#warnings("-alert_experimental")
impl @cmd.Scheduler for OpcTestScheduler with fn set_url_request_injector(_, _) {
  ()
}

///|
fn opc_http_body_parts(body : @http.Body) -> (Bool, String, String) {
  match body {
    @http.Body::Json(json) => (true, json.stringify(), "application/json")
    @http.Body::Text(text) => (true, text, "text/plain")
    @http.Body::BytesBody(ct, _) => (true, "", ct)
    @http.Body::BlobBody(ct, _) => (true, "", ct)
    @http.Body::Empty => (false, "", "")
  }
}

///|
fn opc_deliver_http_text(
  cb : (Result[String, @http.HttpError]) -> Cmd,
  ok : Bool,
  payload : String,
) -> Cmd {
  if ok {
    cb(Ok(payload))
  } else {
    cb(Err(@http.HttpError::RequestError(payload)))
  }
}

///|
fn opc_deliver_http_json(
  cb : (Result[Json, @http.HttpError]) -> Cmd,
  ok : Bool,
  payload : String,
) -> Cmd {
  if ok {
    let parsed : Result[Json, @http.HttpError] = Ok(@json.parse(payload)) catch {
      err => Err(@http.HttpError::RequestError(err.to_string()))
    }
    cb(parsed)
  } else {
    cb(Err(@http.HttpError::RequestError(payload)))
  }
}

///|
fn opc_cmd_array_each(cmds : Array[Cmd], f : (Cmd) -> Unit) -> Unit {
  for item in cmds {
    f(item)
  }
}

///|
#cfg(target="js")
extern "js" fn opc_run_cmd_js(
  scheduler : &@cmd.Scheduler,
  command : Cmd,
  each_cmd : (Array[Cmd], (Cmd) -> Unit) -> Unit,
  body_has : (@http.Body) -> Bool,
  body_text : (@http.Body) -> String,
  body_ct : (@http.Body) -> String,
  deliver_text : ((Result[String, @http.HttpError]) -> Cmd, Bool, String) -> Cmd,
  deliver_json : ((Result[Json, @http.HttpError]) -> Cmd, Bool, String) -> Cmd,
) -> Unit =
  #| (scheduler, command, eachCmd, bodyHas, bodyText, bodyCt, deliverText, deliverJson) => {
  #|   const deliver = (expect, ok, payload) => {
  #|     if (!expect || typeof expect._0 !== "function") return null;
  #|     if (expect.$tag === 0) {
  #|       return deliverJson(expect._0, ok, payload);
  #|     }
  #|     return deliverText(expect._0, ok, payload);
  #|   };
  #|   const walk = c => {
  #|     if (!c || typeof c !== "object") return;
  #|     if (c.$tag === 0) {
  #|       eachCmd(c._0, walk);
  #|       return;
  #|     }
  #|     const ext = c._1;
  #|     const cname = ext && ext.constructor && ext.constructor.name ? ext.constructor.name : "";
  #|     if (cname.endsWith("Extension_2eLegacyEffect")) {
  #|       if (typeof ext._1 === "function") ext._1(scheduler);
  #|       return;
  #|     }
  #|     if (cname.endsWith("Extension_2eLegacyMessage")) {
  #|       if (typeof ext._0 === "function") ext._0(scheduler);
  #|       return;
  #|     }
  #|     if (cname.endsWith("Extension_2eDelay")) {
  #|       if (typeof globalThis.setTimeout === "function") {
  #|         globalThis.setTimeout(() => walk(ext._0), ext._1);
  #|       }
  #|       return;
  #|     }
  #|     let httpMethod = null;
  #|     let hasBodyArg = false;
  #|     if (cname.endsWith("Extension_2eGet")) { httpMethod = "GET"; }
  #|     else if (cname.endsWith("Extension_2eDelete")) { httpMethod = "DELETE"; }
  #|     else if (cname.endsWith("Extension_2ePost")) { httpMethod = "POST"; hasBodyArg = true; }
  #|     else if (cname.endsWith("Extension_2ePut")) { httpMethod = "PUT"; hasBodyArg = true; }
  #|     else if (cname.endsWith("Extension_2ePatch")) { httpMethod = "PATCH"; hasBodyArg = true; }
  #|     if (httpMethod !== null) {
  #|       const url = ext._0;
  #|       const expect = hasBodyArg ? ext._2 : ext._1;
  #|       const config = { method: httpMethod };
  #|       if (hasBodyArg && bodyHas(ext._1)) {
  #|         config.body = bodyText(ext._1);
  #|         const ct = bodyCt(ext._1);
  #|         if (ct) config.headers = { "Content-Type": ct };
  #|       }
  #|       if (typeof globalThis.fetch !== "function") return;
  #|       const p = globalThis.fetch(url, config);
  #|       if (p && typeof p.then === "function") {
  #|         const p2 = p.then(res => {
  #|           if (res && typeof res.text === "function") {
  #|             const tp = res.text();
  #|             if (tp && typeof tp.then === "function") {
  #|               tp.then(text => {
  #|                 const follow = deliver(expect, true, String(text));
  #|                 if (follow) walk(follow);
  #|               });
  #|             }
  #|           }
  #|         });
  #|         if (p2 && typeof p2.catch === "function") {
  #|           p2.catch(err => {
  #|             const msg = err && err.message ? String(err.message) : String(err);
  #|             const follow = deliver(expect, false, msg);
  #|             if (follow) walk(follow);
  #|           });
  #|         }
  #|       }
  #|       return;
  #|     }
  #|   };
  #|   walk(command);
  #| }

///|
fn opc_run_cmd_with_scheduler(
  scheduler : &@cmd.Scheduler,
  command : Cmd,
) -> Unit {
  opc_run_cmd_js(
    scheduler,
    command,
    opc_cmd_array_each,
    b => opc_http_body_parts(b).0,
    b => opc_http_body_parts(b).1,
    b => opc_http_body_parts(b).2,
    opc_deliver_http_text,
    opc_deliver_http_json,
  )
}

///|
fn opc_run_cmd(command : Cmd) -> Unit {
  let scheduler = OpcTestScheduler::{ }
  opc_run_cmd_with_scheduler(scheduler, command)
}

///|
#cfg(target="js")
extern "js" fn opc_count_cmd_js(
  command : Cmd,
  each_cmd : (Array[Cmd], (Cmd) -> Unit) -> Unit,
) -> Int32 =
  #| (cmd, eachCmd) => {
  #|   let total = 0;
  #|   const count = c => {
  #|     if (!c || typeof c !== "object") return;
  #|     if (c.$tag === 0) {
  #|       eachCmd(c._0, count);
  #|       return;
  #|     }
  #|     total += 1;
  #|   };
  #|   count(cmd);
  #|   return total;
  #| }

///|
fn opc_count_cmd(command : Cmd) -> Int32 {
  opc_count_cmd_js(command, opc_cmd_array_each)
}
