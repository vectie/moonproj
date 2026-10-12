const STORAGE_KEY = "moonproj.prd-workspace.v1";
export const HEADERS = ["Product", "Requirement ID", "Scope", "Priority", "Requirement title", "Evidence assessment", "Current assessment", "Requirement statement", "Acceptance criteria", "Evidence and sources", "Dependencies"];
export const PRODUCTS = ["LunaChip", "LunaFlex", "LunaFlux", "LunaNexa", "LunaRein", "MoonBook", "MoonCast", "MoonChat", "MoonClaw", "MoonDesk", "MoonEdit", "MoonFind", "MoonFish", "MoonFlow", "MoonFort", "MoonGate", "MoonLeaf", "MoonLib", "MoonMold", "MoonMoon", "MoonPoly", "MoonProj", "MoonRobo", "MoonStat", "MoonTown", "MoonVis"];
const SCOPES = new Set(["baseline", "roadmap", "quality", "retirement"]);
const ASSESSMENTS = new Set(["Proposed", "Source documented", "Partial", "Verified contract", "Blocked", "Verified local", "Unknown"]);

export function parseCsv(text) {
  if (typeof text !== "string" || text.length > 3_000_000) throw new Error("CSV is empty or exceeds the 3 MB limit");
  text = text.replace(/^\uFEFF/, "");
  const records = [], row = [];
  let value = "", quoted = false, closed = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { value += '"'; i++; }
      else if (c === '"') { quoted = false; closed = true; }
      else value += c;
    } else if (c === '"') {
      if (value !== "" || closed) throw new Error(`Unexpected quote near character ${i}`);
      quoted = true;
    } else if (c === "," || c === "\n" || c === "\r") {
      row.push(value); value = ""; closed = false;
      if (c !== ",") { if (row.some(x => x !== "")) records.push([...row]); row.length = 0; if (c === "\r" && text[i + 1] === "\n") i++; }
    } else {
      if (closed) throw new Error(`Unexpected text after quote near character ${i}`);
      value += c;
    }
  }
  if (quoted) throw new Error("Unclosed CSV quote");
  if (value !== "" || row.length) { row.push(value); records.push(row); }
  if (!records.length) throw new Error("CSV is empty");
  const headers = records.shift();
  if (headers.length !== HEADERS.length || headers.some((h, i) => h !== HEADERS[i])) throw new Error("Unexpected PRD columns; expected the 11-column OPC_OS_Requirements.csv schema");
  if (!records.length || records.length > 2000) throw new Error("CSV must contain 1–2000 requirement rows");
  const ids = new Set();
  return records.map((values, i) => {
    if (values.length !== HEADERS.length) throw new Error(`Row ${i + 2} has ${values.length} fields; expected ${HEADERS.length}`);
    const row = Object.fromEntries(HEADERS.map((h, j) => [h, values[j].trim()]));
    const product = row.Product, id = row["Requirement ID"], scope = row.Scope;
    if (!PRODUCTS.includes(product)) throw new Error(`Row ${i + 2}: unknown product ${product}`);
    if (!new RegExp(`^${product.toUpperCase()}-[BRN][0-9]{2,}$`).test(id)) throw new Error(`Row ${i + 2}: requirement ID does not match product`);
    if (ids.has(id)) throw new Error(`Duplicate requirement ID: ${id}`);
    ids.add(id);
    if (!SCOPES.has(scope) || (product === "MoonStat") !== (scope === "retirement") || (scope !== "retirement" && id.split("-")[1][0] !== ({ baseline: "B", roadmap: "R", quality: "N" })[scope])) throw new Error(`Row ${i + 2}: invalid scope for ${product}`);
    if (!(["", "P0", "P1", "P2"].includes(row.Priority))) throw new Error(`Row ${i + 2}: invalid priority`);
    if (!ASSESSMENTS.has(row["Evidence assessment"]) || !ASSESSMENTS.has(row["Current assessment"])) throw new Error(`Row ${i + 2}: invalid imported assessment`);
    for (const key of ["Requirement title", "Requirement statement", "Acceptance criteria"]) if (!row[key]) throw new Error(`Row ${i + 2}: missing ${key}`);
    return row;
  });
}

export function emptyWorkspace() { return { schema: "moonproj.prd-workspace.v1", versions: [], activeDigest: "", plans: {} }; }
const DIGEST = /^[0-9a-f]{64}$/;
const VERSION_LABEL = /^[A-Za-z0-9][A-Za-z0-9_. -]{0,79}$/;
const TASK_ID = /^OPC-TASK-[A-Za-z0-9-]{1,100}$/;
const PLAN_FIELDS = ["owner", "priority", "plannedWork", "taskRef", "proposedEvidence", "sourceFingerprint"];
const plainObject = value => value !== null && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const exactKeys = (value, keys) => Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
const sameRows = (a, b) => a.length === b.length && a.every((row, i) => rowFingerprint(row) === rowFingerprint(b[i]));
const samePlan = (a, b) => PLAN_FIELDS.every(key => a[key] === b[key]);

function validateRows(rows, context) {
  if (!Array.isArray(rows) || rows.length < 1 || rows.length > 2000) throw new Error(`${context}: expected 1–2000 requirement rows`);
  const seen = new Set();
  for (const row of rows) {
    if (!plainObject(row) || !exactKeys(row, HEADERS) || !HEADERS.every(key => typeof row[key] === "string" && row[key].length <= 50000)) throw new Error(`${context}: invalid requirement fields`);
    const product = row.Product, id = row["Requirement ID"], scope = row.Scope;
    if (!PRODUCTS.includes(product) || !new RegExp(`^${product.toUpperCase()}-[BRN][0-9]{2,}$`).test(id) || seen.has(id)) throw new Error(`${context}: invalid or duplicate requirement ID ${id}`);
    seen.add(id);
    if (!SCOPES.has(scope) || (product === "MoonStat") !== (scope === "retirement") || (scope !== "retirement" && id.split("-")[1][0] !== ({ baseline: "B", roadmap: "R", quality: "N" })[scope])) throw new Error(`${context}: invalid requirement scope ${id}`);
    if (!["", "P0", "P1", "P2"].includes(row.Priority) || !ASSESSMENTS.has(row["Evidence assessment"]) || !ASSESSMENTS.has(row["Current assessment"])) throw new Error(`${context}: invalid source assessment ${id}`);
    for (const key of ["Requirement title", "Requirement statement", "Acceptance criteria"]) if (!row[key].trim()) throw new Error(`${context}: missing ${key} for ${id}`);
  }
}

export function validateWorkspace(store) {
  if (!plainObject(store) || !exactKeys(store, ["schema", "versions", "activeDigest", "plans"]) || store.schema !== "moonproj.prd-workspace.v1") throw new Error("Unknown PRD workspace schema or extra root fields");
  if (!Array.isArray(store.versions) || store.versions.length > 100 || typeof store.activeDigest !== "string" || !plainObject(store.plans)) throw new Error("Malformed PRD version history or plans");
  const digests = new Set(), labels = new Set();
  let prior = [];
  for (const [index, version] of store.versions.entries()) {
    if (!plainObject(version) || ![5, 6].includes(Object.keys(version).length) || !["digest", "label", "importedAt", "touched", "rows"].every(key => Object.hasOwn(version, key)) || (Object.keys(version).length === 6 && !Object.hasOwn(version, "sourceName"))) throw new Error(`Version ${index + 1}: malformed provenance fields`);
    if (!DIGEST.test(version.digest) || digests.has(version.digest) || !VERSION_LABEL.test(version.label) || labels.has(version.label)) throw new Error(`Version ${index + 1}: duplicate or invalid digest/label`);
    if (typeof version.importedAt !== "string" || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(version.importedAt) || !Number.isFinite(Date.parse(version.importedAt))) throw new Error(`Version ${index + 1}: invalid import time`);
    if (version.sourceName !== undefined && (typeof version.sourceName !== "string" || version.sourceName.length > 200)) throw new Error(`Version ${index + 1}: invalid source filename`);
    if (!Array.isArray(version.touched) || !version.touched.length || new Set(version.touched).size !== version.touched.length || !version.touched.every(product => PRODUCTS.includes(product))) throw new Error(`Version ${index + 1}: invalid touched products`);
    validateRows(version.rows, `Version ${index + 1}`);
    const touched = new Set(version.touched), current = new Map(version.rows.map(row => [row["Requirement ID"], row]));
    for (const row of prior) {
      const next = current.get(row["Requirement ID"]);
      if (!next || next.Product !== row.Product || (!touched.has(row.Product) && rowFingerprint(next) !== rowFingerprint(row))) throw new Error(`Version ${index + 1}: removed or changed an untouched requirement ${row["Requirement ID"]}`);
    }
    for (const row of version.rows) if (!prior.some(old => old["Requirement ID"] === row["Requirement ID"]) && !touched.has(row.Product)) throw new Error(`Version ${index + 1}: new row without touched product ${row["Requirement ID"]}`);
    prior = version.rows;
    digests.add(version.digest); labels.add(version.label);
  }
  if ((store.versions.length === 0 && store.activeDigest !== "") || (store.versions.length > 0 && !digests.has(store.activeDigest))) throw new Error("Active PRD version is absent from history");
  const latestIds = new Set(prior.map(row => row["Requirement ID"]));
  for (const [id, plan] of Object.entries(store.plans)) {
    if (!latestIds.has(id) || !plainObject(plan) || !exactKeys(plan, PLAN_FIELDS)) throw new Error(`Invalid plan for ${id}`);
    for (const key of PLAN_FIELDS) if (typeof plan[key] !== "string") throw new Error(`Invalid ${key} for ${id}`);
    if (plan.owner.length > 120 || plan.plannedWork.length > 2000 || plan.proposedEvidence.length > 2000 || !["", "P0", "P1", "P2"].includes(plan.priority) || (plan.taskRef && !TASK_ID.test(plan.taskRef))) throw new Error(`Invalid plan content for ${id}`);
    if (!store.versions.some(version => version.rows.some(row => row["Requirement ID"] === id && rowFingerprint(row) === plan.sourceFingerprint))) throw new Error(`Plan ${id} has no matching source requirement`);
  }
  return store;
}
export function validWorkspace(store) { try { validateWorkspace(store); return true; } catch { return false; } }
export function activeVersion(store) { return store.versions.find(v => v.digest === store.activeDigest) || store.versions.at(-1) || null; }
export function latestVersion(store) { return store.versions.at(-1) || null; }
export function rowFingerprint(row) { return JSON.stringify(HEADERS.map(h => row[h])); }
export function previewImport(store, rows, digest, label, sourceName = "") {
  if (!validWorkspace(store)) throw new Error("Stored workspace schema is invalid; export/recover it before importing");
  label = label.trim();
  if (!VERSION_LABEL.test(label)) throw new Error("Enter a version label (1–80 letters, digits, spaces, dots, hyphens or underscores)");
  if (store.versions.some(v => v.digest === digest)) return { duplicate: true, digest, label, sourceName, rows, added: 0, changed: 0, touched: [] };
  const old = latestVersion(store)?.rows || [], oldById = new Map(old.map(r => [r["Requirement ID"], r]));
  const touched = [...new Set(rows.map(r => r.Product))].sort();
  const newById = new Map(rows.map(r => [r["Requirement ID"], r]));
  for (const prior of old) {
    if (touched.includes(prior.Product) && !newById.has(prior["Requirement ID"])) throw new Error(`Version conflict: ${prior["Requirement ID"]} would disappear. Import an additive update or reconcile IDs explicitly.`);
  }
  const added = rows.filter(r => !oldById.has(r["Requirement ID"])).length;
  const changed = rows.filter(r => oldById.has(r["Requirement ID"]) && rowFingerprint(oldById.get(r["Requirement ID"])) !== rowFingerprint(r)).length;
  if (old.length && added === 0 && changed === 0) return { duplicate: true, digest, label, sourceName, rows, added, changed, touched };
  if (store.versions.some(v => v.label === label)) throw new Error(`Version label “${label}” already exists with different content`);
  const merged = [...old.filter(r => !touched.includes(r.Product)), ...rows].sort((a, b) => a.Product.localeCompare(b.Product) || a["Requirement ID"].localeCompare(b["Requirement ID"]));
  return { duplicate: false, digest, label, sourceName: sourceName.slice(0, 200), rows: merged, added, changed, touched };
}
export function commitImport(store, preview, importedAt) {
  if (preview.duplicate) return store;
  return { ...store, versions: [...store.versions, { digest: preview.digest, label: preview.label, importedAt, sourceName: preview.sourceName, touched: preview.touched, rows: preview.rows }], activeDigest: preview.digest };
}
export function savePlan(store, id, plan) {
  const row = latestVersion(store)?.rows.find(r => r["Requirement ID"] === id);
  if (!row) throw new Error("Requirement is absent from the latest PRD version");
  const next = {
    owner: String(plan.owner || "").trim().slice(0, 120),
    priority: String(plan.priority || "").trim(),
    plannedWork: String(plan.plannedWork || "").trim().slice(0, 2000),
    taskRef: String(plan.taskRef || "").trim().slice(0, 160),
    proposedEvidence: String(plan.proposedEvidence || "").trim().slice(0, 2000),
    sourceFingerprint: rowFingerprint(row),
  };
  if (!["", "P0", "P1", "P2"].includes(next.priority)) throw new Error("Invalid priority override");
  if (next.taskRef && !TASK_ID.test(next.taskRef)) throw new Error("Formal task reference must be an OPC-TASK identifier, never a URL or credential");
  return { ...store, plans: { ...store.plans, [id]: next } };
}
export function totals(rows) { return { rows: rows.length, products: new Set(rows.map(r => r.Product)).size, baseline: rows.filter(r => r.Scope === "baseline").length, roadmap: rows.filter(r => r.Scope === "roadmap").length, quality: rows.filter(r => r.Scope === "quality").length, retirement: rows.filter(r => r.Scope === "retirement").length }; }

const escapeHtml = x => String(x ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const selector = (options, current) => options.map(x => `<option value="${escapeHtml(x)}" ${x === current ? "selected" : ""}>${escapeHtml(x || "All")}</option>`).join("");
async function sha256(text) { const bytes = new TextEncoder().encode(text); const hash = await crypto.subtle.digest("SHA-256", bytes); return [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, "0")).join(""); }
export async function createBackup(store, exportedAt = new Date().toISOString()) {
  validateWorkspace(store);
  const digest = await sha256(JSON.stringify(store));
  return JSON.stringify({ schema: "moonproj.prd-backup.v1", exportedAt, digest, workspace: store }, null, 2);
}
export async function parseBackup(text) {
  if (typeof text !== "string" || text.length > 12_000_000) throw new Error("JSON backup exceeds the 12 MB limit");
  let payload;
  try { payload = JSON.parse(text); } catch { throw new Error("JSON backup cannot be parsed"); }
  if (plainObject(payload) && payload.schema === "moonproj.prd-workspace.v1") return { workspace: validateWorkspace(payload), integrity: "legacy-unchecked" };
  if (!plainObject(payload) || !exactKeys(payload, ["schema", "exportedAt", "digest", "workspace"]) || payload.schema !== "moonproj.prd-backup.v1" || !DIGEST.test(payload.digest) || typeof payload.exportedAt !== "string") throw new Error("Unknown or malformed PRD backup envelope");
  if (await sha256(JSON.stringify(payload.workspace)) !== payload.digest) throw new Error("Backup checksum mismatch; no local data changed");
  return { workspace: validateWorkspace(payload.workspace), integrity: "checksum-matched" };
}
function sameVersion(a, b) {
  return a.digest === b.digest && a.label === b.label && a.importedAt === b.importedAt && (a.sourceName || "") === (b.sourceName || "") && JSON.stringify(a.touched) === JSON.stringify(b.touched) && sameRows(a.rows, b.rows);
}
export function previewRestore(local, incoming) {
  validateWorkspace(local); validateWorkspace(incoming);
  const shared = Math.min(local.versions.length, incoming.versions.length);
  for (let i = 0; i < shared; i++) if (!sameVersion(local.versions[i], incoming.versions[i])) throw new Error(`Version history diverges at ${i + 1}; neither history was overwritten`);
  const versions = local.versions.length < incoming.versions.length ? incoming.versions : local.versions;
  const plans = { ...incoming.plans, ...local.plans };
  const conflicts = Object.keys(incoming.plans).filter(id => local.plans[id] && !samePlan(local.plans[id], incoming.plans[id]));
  const addedPlans = Object.keys(incoming.plans).filter(id => !local.plans[id]).length;
  const addedVersions = Math.max(0, incoming.versions.length - local.versions.length);
  const candidate = { schema: local.schema, versions, activeDigest: local.versions.length ? (addedVersions ? versions.at(-1).digest : local.activeDigest) : incoming.activeDigest, plans };
  validateWorkspace(candidate);
  return { candidate, addedVersions, addedPlans, conflicts, noop: !addedVersions && !addedPlans && !conflicts.length };
}
export function commitRestore(preview, keepLocalConflicts = false) {
  if (preview.conflicts.length && !keepLocalConflicts) throw new Error("Choose explicitly to keep current local plans for every conflict");
  return preview.candidate;
}
export function persistWorkspace(storage, next) {
  validateWorkspace(next);
  storage.setItem(STORAGE_KEY, JSON.stringify(next));
  return next;
}
function download(text, filename) { const url = URL.createObjectURL(new Blob([text], { type: "application/json;charset=utf-8" })); const link = document.createElement("a"); link.href = url; link.download = filename; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 10000); }

// Keeps unfinished form text during Rabbita page changes in this tab only.
// Saved plans alone enter localStorage and backup files.
const viewSession = { product: "MoonProj", scope: "", query: "", selected: "MOONPROJ-B01", drafts: new Map() };
export function mountWorkspace(host, storage = localStorage) {
  let store, error = "", notice = "", pending = null, restorePending = null, recoveryAcknowledged = false;
  let { product, scope, query, selected } = viewSession;
  try { const raw = storage.getItem(STORAGE_KEY); store = raw ? validateWorkspace(JSON.parse(raw)) : emptyWorkspace(); }
  catch (e) { store = null; error = `Cannot open stored workspace: ${e.message}`; }
  function save(next) { store = persistWorkspace(storage, next); }
  function rememberView() { Object.assign(viewSession, { product, scope, query, selected }); }
  function planInput() {
    return { owner: host.querySelector("#prd-owner").value, priority: host.querySelector("#prd-priority").value, plannedWork: host.querySelector("#prd-work").value, taskRef: host.querySelector("#prd-task").value, proposedEvidence: host.querySelector("#prd-evidence").value };
  }
  function render() {
    if (!host.isConnected) return;
    const version = store && activeVersion(store), latest = store && latestVersion(store), rows = version?.rows || [], counts = totals(rows);
    const filtered = rows.filter(r => (!product || r.Product === product) && (!scope || r.Scope === scope) && (!query || `${r["Requirement ID"]} ${r["Requirement title"]} ${r["Requirement statement"]}`.toLowerCase().includes(query.toLowerCase())));
    const row = rows.find(r => r["Requirement ID"] === selected), draft = viewSession.drafts.get(selected);
    const storedPlan = store?.plans[selected] || {}, plan = draft || storedPlan;
    const stale = row && storedPlan.sourceFingerprint && storedPlan.sourceFingerprint !== rowFingerprint(row);
    const focusRows = rows.filter(r => !product || r.Product === product);
    const p0NoPlan = focusRows.filter(r => r.Priority === "P0" && !(store?.plans[r["Requirement ID"]]?.plannedWork)).length;
    host.innerHTML = `<div class="prd-workspace">
      <div class="prd-heading"><h2>PRD 工作台</h2><span class="prd-warning">本浏览器本地工作记录 · 非正式公司收据</span></div>
      <p>把产品 PRD 变成可追踪的需求、责任人与计划。导入时的“Verified”只是来源评估；任务完成或在此填写验证建议不会放行版本。</p>
      ${error ? `<p role="alert" class="prd-error">${escapeHtml(error)}</p>` : ""}${notice ? `<p role="status">${escapeHtml(notice)}</p>` : ""}
      <div class="prd-toolbar"><label>版本标签 <input id="prd-version-label" value="${escapeHtml(pending?.label || "")}" placeholder="例如 2026-10-01-portfolio"></label>
      <label>导入 OPC_OS_Requirements.csv <input id="prd-file" type="file" accept=".csv,text/csv" ${store ? "" : "disabled"}></label>
      <button id="prd-export" ${store ? "" : "disabled"}>导出完整 JSON 备份</button>
      <label>恢复 JSON 备份 <input id="prd-restore-file" type="file" accept=".json,application/json"></label>
      ${store ? "" : `<button id="prd-export-raw">先导出原始损坏记录</button>`}</div>
      ${pending ? `<div class="prd-preview"><strong>待确认版本 ${escapeHtml(pending.label)}</strong> · ${pending.touched.length} 产品 · ${pending.added} 新增 · ${pending.changed} 改动 · 导入后 ${pending.rows.length} 行。旧版本保留；计划不会被删除。<div><button id="prd-confirm">确认导入</button><button id="prd-cancel">取消</button></div></div>` : ""}
      ${restorePending ? `<div class="prd-preview"><strong>待确认 JSON 恢复</strong> · ${restorePending.addedVersions} 个新版本 · ${restorePending.addedPlans} 项新增计划 · ${restorePending.conflicts.length} 项计划冲突。${restorePending.integrity === "legacy-unchecked" ? "旧格式无校验和；仅通过结构校验。" : "文件校验和匹配；这不是独立来源认证。"}${store ? "当前版本和计划不会被删除；冲突计划保留当前本地值。" : "本地记录不可读；只有在已导出原始记录后才可显式替换。"}${restorePending.conflicts.length ? `<p>冲突 ID：${escapeHtml(restorePending.conflicts.slice(0, 25).join(", "))}${restorePending.conflicts.length > 25 ? " …" : ""}</p>` : ""}<div><button id="prd-restore-confirm">${store ? `合并；保留本地 ${restorePending.conflicts.length} 项冲突计划` : "替换不可读记录并恢复"}</button><button id="prd-restore-cancel">取消恢复</button></div></div>` : ""}
      <p class="prd-summary">${counts.products} 产品 · ${counts.rows} 需求 · baseline ${counts.baseline} · roadmap ${counts.roadmap} · quality ${counts.quality} · retirement ${counts.retirement} · ${Object.keys(store?.plans || {}).length} 项本地计划</p>
      <div class="prd-toolbar"><label>查看版本 <select id="prd-history">${(store?.versions || []).map(v => `<option value="${escapeHtml(v.digest)}" ${v.digest === version?.digest ? "selected" : ""}>${escapeHtml(v.label)} · ${escapeHtml(v.digest.slice(0, 8))}</option>`).join("")}</select></label><span>${version ? `${escapeHtml(version.label)} · SHA-256 ${escapeHtml(version.digest.slice(0, 12))} · ${escapeHtml(version.importedAt)} · ${escapeHtml(version.sourceName || "CSV")}` : "尚未导入 PRD"}</span></div>
      <p class="prd-warning">发布就绪：未独立验证。当前筛选产品有 ${p0NoPlan} 项 P0 尚无计划工作；正式发布仍需受权 Gate 与独立证据。</p>
      <div class="prd-toolbar"><label>产品 <select id="prd-product">${selector(["", ...PRODUCTS], product)}</select></label><label>范围 <select id="prd-scope">${selector(["", "baseline", "roadmap", "quality", "retirement"], scope)}</select></label><label>搜索 <input id="prd-search" value="${escapeHtml(query)}" placeholder="ID / 标题 / 文字"></label></div>
      <div class="prd-layout"><div class="prd-list"><strong>${filtered.length} 条匹配</strong>${filtered.slice(0, 100).map(r => `<button class="prd-row ${r["Requirement ID"] === selected ? "active" : ""}" data-prd-id="${escapeHtml(r["Requirement ID"])}"><b>${escapeHtml(r["Requirement ID"])}</b> ${escapeHtml(r["Requirement title"])} <small>${escapeHtml(r.Scope)} · ${escapeHtml(r.Priority || "未定优先级")} ${store.plans[r["Requirement ID"]] ? "· 已计划" : ""}</small></button>`).join("")}${filtered.length > 100 ? "<p>仅显示前 100 条；用产品、范围或搜索缩小结果。</p>" : ""}</div>
      <div class="prd-detail">${row ? `<h3>${escapeHtml(row["Requirement ID"])} · ${escapeHtml(row["Requirement title"])}</h3><p><b>${escapeHtml(row.Product)}</b> · ${escapeHtml(row.Scope)} · 来源优先级 ${escapeHtml(row.Priority || "未定")}</p>
      <p><b>来源评估（未重新验证）：</b> ${escapeHtml(row["Evidence assessment"])} / ${escapeHtml(row["Current assessment"])}</p><p><b>需求：</b> ${escapeHtml(row["Requirement statement"])}</p><p><b>验收标准：</b> ${escapeHtml(row["Acceptance criteria"])}</p><p><b>原始依据：</b> ${escapeHtml(row["Evidence and sources"])}</p><p><b>依赖：</b> ${escapeHtml(row.Dependencies)}</p>
      ${stale ? `<p class="prd-error">来源需求在更新版本中发生变化；请重新检查此计划与验证建议。</p>` : ""}
      <div class="prd-plan"><h3>本地管理计划</h3><p>所填证据是待复核建议，不能自行把需求变为已验证。任务引用只是链接，不会创建正式任务。</p>${draft ? `<p class="prd-warning">此需求有未保存的表单草稿；离开页面后仍保留在此标签页内存，重新加载会丢失。<button id="prd-discard">放弃草稿</button></p>` : ""}
      <label>责任人 <input id="prd-owner" value="${escapeHtml(plan.owner || "")}" maxlength="120"></label>
      <label>优先级调整 <select id="prd-priority">${selector(["", "P0", "P1", "P2"], plan.priority || "")}</select></label>
      <label>计划工作 <textarea id="prd-work" maxlength="2000">${escapeHtml(plan.plannedWork || "")}</textarea></label>
      <label>正式任务 ID（可选） <input id="prd-task" value="${escapeHtml(plan.taskRef || "")}" maxlength="160" placeholder="例如 OPC-TASK-123"></label>${/^OPC-TASK-[A-Za-z0-9-]{1,100}$/.test(plan.taskRef || "") ? `<a href="./index.html?opc_task=${escapeHtml(plan.taskRef)}">在任务编排中读取正式任务收据</a>` : ""}
      <label>拟提交的验证依据 <textarea id="prd-evidence" maxlength="2000">${escapeHtml(plan.proposedEvidence || "")}</textarea></label>
      <button id="prd-save" ${version?.digest === latest?.digest ? "" : "disabled"}>保存本地计划</button></div>` : "选择需求查看详情。"}</div></div>
      <p class="prd-warning">仅保存在此浏览器 origin；换设备或清除站点数据会失去记录。定期导出 JSON 备份，并在恢复预览中检查版本和冲突。不要输入凭据、客户敏感内容或声称已收款的事实。</p></div>`;
    host.querySelector("#prd-file")?.addEventListener("change", async event => {
      try {
        const file = event.target.files?.[0]; if (!file) return;
        if (file.size > 3_000_000) throw new Error("CSV exceeds 3 MB");
        const label = host.querySelector("#prd-version-label").value;
        const csv = new TextDecoder("utf-8", { fatal: true }).decode(await file.arrayBuffer());
        const parsed = parseCsv(csv), candidate = previewImport(store, parsed, await sha256(csv), label, file.name);
        restorePending = null;
        if (candidate.duplicate) { notice = "相同内容已导入；未产生重复版本或计划。"; pending = null; }
        else { pending = candidate; notice = "检查变化后确认导入；该步骤不会覆盖旧版本。"; }
        error = "";
      } catch (e) { pending = null; error = e.message; notice = ""; }
      render();
    });
    host.querySelector("#prd-confirm")?.addEventListener("click", () => { try { save(commitImport(store, pending, new Date().toISOString())); selected = pending.rows.find(r => r.Product === "MoonProj")?.["Requirement ID"] || pending.rows[0]["Requirement ID"]; product = "MoonProj"; rememberView(); notice = `导入 ${pending.label} 已保存；来源评估未提升为新验证。`; pending = null; error = ""; } catch (e) { error = `保存失败：${e.message}。原数据未改动。`; } render(); });
    host.querySelector("#prd-cancel")?.addEventListener("click", () => { pending = null; render(); });
    host.querySelector("#prd-export")?.addEventListener("click", async () => { try { download(await createBackup(store), "moonproj-prd-workspace-backup.json"); notice = "已导出带校验和的完整 JSON 备份。"; error = ""; } catch (e) { error = `导出失败：${e.message}`; } render(); });
    host.querySelector("#prd-export-raw")?.addEventListener("click", () => { try { download(storage.getItem(STORAGE_KEY) || "", "moonproj-prd-workspace-unreadable.json"); recoveryAcknowledged = true; notice = "原始损坏记录已导出；现在可以预览 JSON 恢复。"; error = ""; } catch (e) { error = `原始记录导出失败：${e.message}`; } render(); });
    host.querySelector("#prd-restore-file")?.addEventListener("change", async event => {
      try {
        const file = event.target.files?.[0]; if (!file) return;
        if (!store && !recoveryAcknowledged) throw new Error("先导出原始损坏记录，再恢复备份");
        if (file.size > 12_000_000) throw new Error("JSON backup exceeds the 12 MB limit");
        const text = new TextDecoder("utf-8", { fatal: true }).decode(await file.arrayBuffer());
        const backup = await parseBackup(text);
        const preview = previewRestore(store || emptyWorkspace(), backup.workspace);
        pending = null;
        if (preview.noop && store) { notice = "备份与当前记录相同；无需重复恢复。"; restorePending = null; }
        else { restorePending = { ...preview, integrity: backup.integrity }; notice = "检查版本与冲突，再显式确认恢复。"; }
        error = "";
      } catch (e) { restorePending = null; error = `恢复预览失败：${e.message}`; notice = ""; }
      render();
    });
    host.querySelector("#prd-restore-confirm")?.addEventListener("click", () => {
      try {
        const next = commitRestore(restorePending, true);
        save(next); selected = "MOONPROJ-B01"; product = "MoonProj"; rememberView();
        notice = `已恢复并合并；保留 ${restorePending.conflicts.length} 项当前本地冲突计划。来源评估仍非新验证。`;
        restorePending = null; recoveryAcknowledged = false; error = "";
      } catch (e) { error = `恢复保存失败：${e.message}。原数据未改动。`; }
      render();
    });
    host.querySelector("#prd-restore-cancel")?.addEventListener("click", () => { restorePending = null; render(); });
    host.querySelector("#prd-history")?.addEventListener("change", e => { try { save({ ...store, activeDigest: e.target.value }); selected = ""; rememberView(); error = ""; } catch (x) { error = x.message; } render(); });
    host.querySelector("#prd-product")?.addEventListener("change", e => { product = e.target.value; selected = ""; rememberView(); render(); });
    host.querySelector("#prd-scope")?.addEventListener("change", e => { scope = e.target.value; selected = ""; rememberView(); render(); });
    host.querySelector("#prd-search")?.addEventListener("change", e => { query = e.target.value; selected = ""; rememberView(); render(); });
    host.querySelectorAll("[data-prd-id]").forEach(button => button.addEventListener("click", () => { selected = button.dataset.prdId; rememberView(); render(); }));
    for (const id of ["#prd-owner", "#prd-priority", "#prd-work", "#prd-task", "#prd-evidence"]) {
      host.querySelector(id)?.addEventListener("input", () => viewSession.drafts.set(selected, planInput()));
      host.querySelector(id)?.addEventListener("change", () => viewSession.drafts.set(selected, planInput()));
    }
    host.querySelector("#prd-discard")?.addEventListener("click", () => { viewSession.drafts.delete(selected); render(); });
    host.querySelector("#prd-save")?.addEventListener("click", () => { try { save(savePlan(store, selected, planInput())); viewSession.drafts.delete(selected); notice = `${selected} 的计划已保存；验证仍待独立复核。`; error = ""; } catch (e) { error = `保存失败：${e.message}。原数据未改动。`; } render(); });
  }
  host.addEventListener?.("moonproj:open-prd", event => {
    const requested = event.detail?.product;
    if (!PRODUCTS.includes(requested)) return;
    product = requested; scope = ""; query = "";
    selected = store ? (activeVersion(store)?.rows.find(row => row.Product === product)?.["Requirement ID"] || "") : "";
    rememberView(); render();
  });
  render();
}

if (typeof document !== "undefined") {
  let mounted = null;
  const observe = () => {
    const host = document.getElementById("prd-workspace");
    if (host && host !== mounted) { mounted = host; mountWorkspace(host); }
    if (!host) mounted = null;
  };
  new MutationObserver(observe).observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", observe); else observe();
}
