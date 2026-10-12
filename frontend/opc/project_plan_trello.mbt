///|
// Local board data conversion only; the existing template reader remains authoritative.
extern "js" fn plan_trello_convert_json(source : String) -> String =
  #| source => {
  #|   const fail = message => { throw new Error(message); };
  #|   const obj = (v, label) => { if (!v || typeof v !== "object" || Array.isArray(v)) fail(label + ": expected object"); return v; };
  #|   const text = (v, label, blank = true) => { if (typeof v !== "string" || (!blank && !v.trim())) fail(label + ": expected " + (blank ? "text" : "nonempty text")); return v; };
  #|   const arr = (v, label) => { if (!Array.isArray(v)) fail(label + ": expected array"); return v; };
  #|   const optionalText = (v, label) => v == null ? "" : text(v, label);
  #|   const closed = (v, label) => { if (typeof v !== "boolean") fail(label + ": expected boolean"); return v; };
  #|   const index = (rows, label) => {
  #|     const result = new Map();
  #|     rows.forEach((row, i) => {
  #|       obj(row, label + " " + (i + 1));
  #|       const id = text(row.id, label + " id", false);
  #|       if (result.has(id)) fail(label + ": duplicate id " + id);
  #|       result.set(id, row);
  #|     });
  #|     return result;
  #|   };
  #|   const position = row => typeof row.pos === "number" && Number.isFinite(row.pos) ? row.pos : Number.MAX_VALUE;
  #|   try {
  #|     if (source.length > 1000000) fail("Board exceeds 1,000,000 text code units");
  #|     const board = obj(JSON.parse(source.replace(/^\uFEFF/, "")), "Board");
  #|     text(board.id, "Board id", false);
  #|     text(board.name, "Board name", false);
  #|     if (closed(board.closed, "Board closed")) fail("Archived board: restore or choose an open board before planning");
  #|     const lists = index(arr(board.lists, "Board lists"), "List");
  #|     const cards = index(arr(board.cards, "Board cards"), "Card");
  #|     const members = index(arr(board.members || [], "Board members"), "Member");
  #|     const checklists = index(arr(board.checklists || [], "Board checklists"), "Checklist");
  #|     for (const list of lists.values()) { text(list.name, "List name", false); closed(list.closed, "List closed"); }
  #|     const active = [];
  #|     let excluded = 0;
  #|     for (const card of cards.values()) {
  #|       text(card.idList, "Card list", false);
  #|       if (!lists.has(card.idList)) fail("Card " + card.id + ": missing list " + card.idList);
  #|       if (closed(card.closed, "Card closed") || lists.get(card.idList).closed) { excluded++; continue; }
  #|       text(card.name, "Card name", false);
  #|       if (card.idBoard != null && card.idBoard !== board.id) fail("Card " + card.id + ": belongs to another board");
  #|       active.push(card);
  #|     }
  #|     if (!active.length) fail("No open cards in open lists to import");
  #|     if (active.length > 100) fail("Plan limit: at most 100 open cards");
  #|     const orderedLists = [...lists.values()].sort((a,b) => position(a)-position(b));
  #|     const rank = new Map(orderedLists.map((v,i) => [v.id,i]));
  #|     active.sort((a,b) => rank.get(a.idList)-rank.get(b.idList) || position(a)-position(b));
  #|     const notes = ["Trello board import: " + board.name, "Board ID: " + board.id,
  #|       "Board URL: " + optionalText(board.url, "Board URL"), optionalText(board.desc, "Board description"),
  #|       "Planning-only snapshot. " + active.length + " open cards imported; " + excluded + " archived cards/cards in archived lists excluded.",
  #|       "Card membership, due/completion flags, labels and checklist states below are unverified source context, not MoonProj assignment, milestones, acceptance or execution evidence.",
  #|       "Set owners, milestones, dependencies, costs, currency and budgets explicitly. Comments, attachments, actions, custom fields and other export fields are not imported. Keep the original export."];
  #|     const tasks = active.map(card => {
  #|       const label = "Card " + card.id;
  #|       const assigned = arr(card.idMembers || [], label + " members").map(id => {
  #|         text(id, label + " member id", false);
  #|         const member = members.get(id);
  #|         return { id, name: member ? optionalText(member.fullName, "Member name") || optionalText(member.username, "Member username") : "(not present in export)" };
  #|       });
  #|       const labels = arr(card.labels || [], label + " labels").map(v => { obj(v, "Label"); return { name: optionalText(v.name, "Label name"), color: optionalText(v.color, "Label color") }; });
  #|       const checks = arr(card.idChecklists || [], label + " checklist IDs").map(id => {
  #|         text(id, "Checklist id", false);
  #|         const cl = checklists.get(id);
  #|         if (!cl) fail(label + ": missing checklist " + id + "; export a complete board");
  #|         if (cl.idCard != null && cl.idCard !== card.id) fail(label + ": checklist belongs to another card");
  #|         return { name: text(cl.name, "Checklist name"), items: arr(cl.checkItems, "Checklist items").map(item => { obj(item, "Checklist item"); return { name: text(item.name, "Checklist item name"), state: text(item.state, "Checklist item state") }; }) };
  #|       });
  #|       if (card.dueComplete != null && typeof card.dueComplete !== "boolean") fail(label + ": dueComplete must be boolean");
  #|       notes.push("\nSource card " + card.id + " (task ID in this preview: " + card.id + ")", JSON.stringify({
  #|         title: card.name, list: lists.get(card.idList).name, url: optionalText(card.url, label + " URL"),
  #|         description: optionalText(card.desc, label + " description"), due: optionalText(card.due, label + " due"),
  #|         dueComplete: card.dueComplete == null ? null : card.dueComplete, members: assigned, labels, checklists: checks
  #|       }, null, 2));
  #|       return { id: card.id, name: card.name, owner: "", milestone: "", cost: "", dependencies: [] };
  #|     });
  #|     const template = JSON.stringify({ format: "moonproj-plan-template/v1", notes: notes.join("\n"),
  #|       currency: "", limit: "", contingency: "", owners: [{ id: "planning-owner", name: "Planning preparer", role: "Review imported work and assign owners explicitly" }],
  #|       tasks, milestones: [], risks: [] });
  #|     if (template.length > 1000000) fail("Converted plan exceeds 1,000,000 text code units; split the source board");
  #|     return JSON.stringify({ error: "", template });
  #|   } catch (error) {
  #|     return JSON.stringify({ error: "Trello import: " + error.message, template: "" });
  #|   }
  #| }

///|
fn plan_trello_read_template(
  source : String,
) -> @plan_workbench.Template raise @plan_workbench.InputError {
  let result = @json.parse(plan_trello_convert_json(source)) catch {
    _ => raise @plan_workbench.Invalid("Trello import returned invalid JSON")
  }
  guard result is { "error": String(error), "template": String(template), .. } else {
    raise @plan_workbench.Invalid("Trello import returned an invalid result")
  }
  if !error.is_empty() {
    raise @plan_workbench.Invalid(error)
  }
  @plan_workbench.read_template(template)
}
