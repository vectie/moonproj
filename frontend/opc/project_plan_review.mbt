///|
// Offline reviewer annotations; source is produced by export_template.
extern "js" fn plan_review_html(source : String) -> String =
  #| source => {
  #|   function worksheet(source) {
  #|     'use strict';
  #|     const plan = JSON.parse(source), root = document.getElementById('review');
  #|     const el = (tag, text, parent = root) => { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; parent.appendChild(n); return n; };
  #|     const status = document.getElementById('status');
  #|     const fields = [];
  #|     const addReview = (kind, id, title, detail) => {
  #|       const section = el('section'); el('h2', title, section); el('pre', detail, section);
  #|       const key = 'review-' + fields.length;
  #|       const label = el('label', 'Review state', section); label.htmlFor = key;
  #|       const state = el('select', undefined, section); state.id = key;
  #|       for (const value of ['not-reviewed', 'no-change-requested', 'question', 'change-requested']) { const option = el('option', value, state); option.value = value; }
  #|       state.value = 'not-reviewed';
  #|       const noteLabel = el('label', 'Review notes', section); noteLabel.htmlFor = key + '-note';
  #|       const note = el('textarea', undefined, section); note.id = key + '-note'; note.value = ''; note.maxLength = 16384;
  #|       const reply = el('div', undefined, section), history = el('div', undefined, section);
  #|       history.addEventListener('input', event => event.stopPropagation());
  #|       history.addEventListener('change', event => event.stopPropagation());
  #|       fields.push({kind, id, state, note, reply, history});
  #|     };
  #|     addReview('scope', '', 'Scope and budget', JSON.stringify({notes:plan.notes,currency:plan.currency,limit:plan.limit,contingency:plan.contingency},null,2));
  #|     for (const kind of ['owners','tasks','milestones','risks']) for (const row of plan[kind]) {
  #|       addReview(kind, row.id, kind + ': ' + (row.name || row.summary || row.id), JSON.stringify(row,null,2));
  #|     }
  #|     const reviewer = document.getElementById('reviewer');
  #|     let dirty = false, importGeneration = 0;
  #|     root.addEventListener('input', () => { dirty = true; importGeneration++; });
  #|     root.addEventListener('change', () => { dirty = true; importGeneration++; });
  #|     reviewer.addEventListener('input', () => { dirty = true; importGeneration++; });
  #|     window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
  #|     const packet = () => ({schema:'moonproj.plan-review-notes.v1', source_template:source, reviewer:reviewer.value,
  #|       annotations:fields.map(f => ({kind:f.kind,id:f.id,state:f.state.value,note:f.note.value}))});
  #|     const validate = (input, expectedSource = source, expectedFields = fields) => {
  #|       const exact = (obj, keys) => obj && typeof obj === 'object' && !Array.isArray(obj) && Object.keys(obj).sort().join('|') === keys.sort().join('|');
  #|       if (!exact(input,['schema','source_template','reviewer','annotations']) || input.schema !== 'moonproj.plan-review-notes.v1') throw Error('Expected MoonProj review-notes JSON.');
  #|       if (input.source_template !== expectedSource) throw Error('This feedback belongs to a different exact plan snapshot. Open its original review sheet.');
  #|       if (typeof input.reviewer !== 'string' || input.reviewer.length > 1000) throw Error('Reviewer label must be text up to 1,000 characters.');
  #|       if (!Array.isArray(input.annotations) || input.annotations.length !== expectedFields.length) throw Error('The review rows are incomplete.');
  #|       input.annotations.forEach((row,i) => {
  #|         const field = expectedFields[i];
  #|         if (!exact(row,['kind','id','state','note']) || row.kind !== field.kind || row.id !== field.id || !['not-reviewed','no-change-requested','question','change-requested'].includes(row.state) || typeof row.note !== 'string' || row.note.length > 16384) throw Error('Invalid review row ' + (i+1) + '.');
  #|       });
  #|       return input;
  #|     };
  #|     document.getElementById('save').addEventListener('click', () => {
  #|       try {
  #|         const data = validate(packet());
  #|         const url = URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json;charset=utf-8'}));
  #|         const a = document.createElement('a'); a.href = url; a.download = 'plan-review-notes.json'; a.click();
  #|         setTimeout(() => URL.revokeObjectURL(url),1000);
  #|         status.textContent = 'Download requested. Verify the file was saved before closing. No approval or company state changed.';
  #|         // A download request cannot prove the user saved a file: keep the close warning.
  #|       } catch(error) { status.textContent = error.message; }
  #|     });
  #|     document.getElementById('load').addEventListener('change', async event => {
  #|       const file = event.target.files?.[0]; const generation = ++importGeneration;
  #|       if (!file) return;
  #|       try {
  #|         if (file.size > 40000000) throw Error('Review notes exceed 40 MB.');
  #|         const data = validate(JSON.parse(await file.text()));
  #|         if (generation !== importGeneration) return;
  #|         if (dirty && !window.confirm('Replace current review notes with this saved file?')) return;
  #|         reviewer.value = data.reviewer;
  #|         fields.forEach((field,i) => { field.state.value = data.annotations[i].state; field.note.value = data.annotations[i].note; });
  #|         clearReplies();
  #|         dirty = false; status.textContent = 'Saved review restored for this exact plan snapshot. It is not a company approval.';
  #|       } catch(error) { if (generation === importGeneration) status.textContent = error.message; }
  #|       finally { if (generation === importGeneration) event.target.value = ''; }
  #|     });
  #|     // The preparer's inbox is separate from this tab's individual reviewer draft.
  #|     const inbox = document.getElementById('inbox');
  #|     const inboxStatus = document.getElementById('inbox-status');
  #|     const summary = document.getElementById('inbox-summary');
  #|     const preparer = document.getElementById('preparer');
  #|     const filter = document.getElementById('inbox-filter');
  #|     const maxBytes = 40000000, dispositions = ['open','answered','change-planned','not-adopted'];
  #|     let reviews = [], responses = [], inboxDirty = false, inboxGeneration = 0;
  #|     const exact = (obj, keys) => obj && typeof obj === 'object' && !Array.isArray(obj) && Object.keys(obj).sort().join('|') === [...keys].sort().join('|');
  #|     const needsResponse = row => row.state === 'question' || row.state === 'change-requested' || row.note.trim() !== '';
  #|     const unresolved = row => row.disposition === 'open' || row.disposition === 'change-planned' || !row.response.trim();
  #|     const canonicalReview = input => {
  #|       const data = validate(input);
  #|       return {schema:data.schema,source_template:data.source_template,reviewer:data.reviewer,
  #|         annotations:data.annotations.map(row => ({kind:row.kind,id:row.id,state:row.state,note:row.note}))};
  #|     };
  #|     const freshResponses = items => items.flatMap((item,review_index) => item.review.annotations.flatMap((row,annotation_index) =>
  #|       needsResponse(row) ? [{review_index,annotation_index,disposition:'open',response:''}] : []));
  #|     const currentInbox = () => ({schema:'moonproj.plan-review-inbox.v1',source_template:source,preparer:preparer.value,reviews,responses});
  #|     const validateInbox = (data, allowUnfinished = false) => {
  #|       if (!exact(data,['schema','source_template','preparer','reviews','responses']) || data.schema !== 'moonproj.plan-review-inbox.v1') throw Error('Expected MoonProj feedback-inbox JSON.');
  #|       if (data.source_template !== source) throw Error('This inbox belongs to a different exact plan snapshot. Open its original review sheet.');
  #|       if (typeof data.preparer !== 'string' || data.preparer.length > 1000) throw Error('Preparer label must be text up to 1,000 characters.');
  #|       if (!Array.isArray(data.reviews) || data.reviews.length > 12) throw Error('An inbox supports at most 12 distinct review files.');
  #|       const seen = new Set();
  #|       const checkedReviews = data.reviews.map(item => {
  #|         if (!exact(item,['label','review']) || typeof item.label !== 'string' || item.label.length > 1000) throw Error('Invalid review file label.');
  #|         const review = canonicalReview(item.review), key = JSON.stringify(review);
  #|         if (seen.has(key)) throw Error('Duplicate review in saved inbox.');
  #|         seen.add(key); return {label:item.label,review};
  #|       });
  #|       const expected = freshResponses(checkedReviews);
  #|       if (!Array.isArray(data.responses) || data.responses.length !== expected.length) throw Error('Inbox responses are incomplete.');
  #|       const checkedResponses = data.responses.map((row,i) => {
  #|         const target = expected[i];
  #|         if (!exact(row,['review_index','annotation_index','disposition','response']) || row.review_index !== target.review_index || row.annotation_index !== target.annotation_index || !dispositions.includes(row.disposition) || typeof row.response !== 'string' || row.response.length > 16384) throw Error('Invalid preparer response ' + (i+1) + '.');
  #|         if (!allowUnfinished && row.disposition !== 'open' && !row.response.trim()) throw Error('Add a preparer explanation for response ' + (i+1) + ', or leave it open.');
  #|         return {...row};
  #|       });
  #|       const result = {schema:data.schema,source_template:source,preparer:data.preparer,reviews:checkedReviews,responses:checkedResponses};
  #|       if (new Blob([JSON.stringify(result)]).size > maxBytes) throw Error('Combined inbox exceeds 40 MB. Use separate inboxes with fewer reviews.');
  #|       return result;
  #|     };
  #|     const changed = () => { inboxDirty = true; inboxGeneration++; };
  #|     const updateSummary = () => {
  #|       const count = responses.filter(unresolved).length;
  #|       summary.textContent = reviews.length + ' review files; ' + responses.length + ' feedback items; ' + count + ' need action. Answered/not-adopted are preparer labels, not reviewer agreement or approval.';
  #|     };
  #|     const rowDetail = index => {
  #|       if (index === 0) return JSON.stringify({notes:plan.notes,currency:plan.currency,limit:plan.limit,contingency:plan.contingency},null,2);
  #|       const field = fields[index]; return JSON.stringify(plan[field.kind].find(row => row.id === field.id),null,2);
  #|     };
  #|     const renderInbox = () => {
  #|       inbox.replaceChildren(); updateSummary();
  #|       const overview = el('div',undefined,inbox);
  #|       reviews.forEach((item,i) => {
  #|         const counts = item.review.annotations.reduce((all,row) => { all[row.state] = (all[row.state] || 0) + 1; return all; },{});
  #|         el('p','Review ' + (i+1) + ': ' + (item.review.reviewer || '(blank reviewer label)') + ' / ' + item.label + ' — ' + JSON.stringify(counts),overview);
  #|         const sendReply = el('button','Download response packet for review ' + (i+1),overview); sendReply.type = 'button'; sendReply.id = 'reply-export-' + i;
  #|         sendReply.addEventListener('click',() => exportReply(i));
  #|       });
  #|       let visible = 0;
  #|       fields.forEach((field,index) => {
  #|         const items = responses.filter(row => row.annotation_index === index && (filter.value !== 'needs-action' || unresolved(row)));
  #|         if (!items.length) return;
  #|         const group = el('section',undefined,inbox);
  #|         el('h3',field.kind + (field.id ? ': ' + field.id : ': scope and budget'),group);
  #|         el('pre',rowDetail(index),group);
  #|         for (const item of items) {
  #|           visible++;
  #|           const review = reviews[item.review_index], original = review.review.annotations[index];
  #|           const card = el('article',undefined,group);
  #|           el('h4','Review ' + (item.review_index+1) + ': ' + (review.review.reviewer || '(blank reviewer label)'),card);
  #|           el('p','Reviewer state: ' + original.state,card); el('pre',original.note || '(no note supplied)',card);
  #|           const id = 'response-' + item.review_index + '-' + index;
  #|           const stateLabel = el('label','Preparer disposition',card); stateLabel.htmlFor = id;
  #|           const state = el('select',undefined,card); state.id = id;
  #|           for (const value of dispositions) { const option = el('option',value,state); option.value = value; }
  #|           state.value = item.disposition;
  #|           const noteLabel = el('label','Preparer response / planned change',card); noteLabel.htmlFor = id + '-text';
  #|           const note = el('textarea',undefined,card); note.id = id + '-text'; note.value = item.response; note.maxLength = 16384;
  #|           state.addEventListener('change',() => { item.disposition = state.value; changed(); updateSummary(); });
  #|           note.addEventListener('input',() => { item.response = note.value; changed(); updateSummary(); });
  #|         }
  #|       });
  #|       if (!visible) el('p',reviews.length ? 'No feedback items in this view. Review coverage is listed above; this is not approval.' : 'Import returned review-notes JSON files to start.',inbox);
  #|     };
  #|     preparer.addEventListener('input',changed);
  #|     filter.addEventListener('change',renderInbox);
  #|     document.getElementById('inbox-refresh').addEventListener('click',renderInbox);
  #|     window.addEventListener('beforeunload',event => { if (inboxDirty) { event.preventDefault(); event.returnValue = ''; } });
  #|     const readInboxFile = async file => {
  #|       if (file.size > maxBytes) throw Error('A feedback file exceeds 40 MB.');
  #|       return JSON.parse(await file.text());
  #|     };
  #|     document.getElementById('inbox-import').addEventListener('change',async event => {
  #|       const files = Array.from(event.target.files || []), generation = ++inboxGeneration;
  #|       event.target.value = '';
  #|       if (!files.length) return;
  #|       try {
  #|         if (files.length > 12 || files.reduce((n,file) => n + file.size,0) > maxBytes) throw Error('Choose at most 12 files totaling 40 MB.');
  #|         const additions = [];
  #|         for (const file of files) additions.push({label:file.name || 'unnamed review file',review:canonicalReview(await readInboxFile(file))});
  #|         if (generation !== inboxGeneration) return;
  #|         const keys = new Set(reviews.map(item => JSON.stringify(item.review))), next = [...reviews];
  #|         for (const item of additions) { const key = JSON.stringify(item.review); if (!keys.has(key)) { keys.add(key); next.push(item); } }
  #|         const candidate = {...currentInbox(),reviews:next,responses:[...responses,...freshResponses(next).filter(row => row.review_index >= reviews.length)]};
  #|         // Import does not require unfinished local responses to be completed first.
  #|         const checked = validateInbox(candidate,true);
  #|         const added = next.length - reviews.length;
  #|         reviews = checked.reviews; responses = checked.responses;
  #|         if (added) changed();
  #|         renderInbox(); inboxStatus.textContent = 'Added ' + added + ' review files; skipped ' + (files.length-added) + ' identical copies. Original reviews are retained. No plan or approval changed.';
  #|       } catch(error) { if (generation === inboxGeneration) inboxStatus.textContent = error.message; }
  #|     });
  #|     document.getElementById('inbox-save').addEventListener('click',() => {
  #|       try {
  #|         const data = validateInbox(currentInbox());
  #|         const url = URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json;charset=utf-8'}));
  #|         const a = document.createElement('a'); a.href = url; a.download = 'plan-review-inbox.json'; a.click();
  #|         setTimeout(() => URL.revokeObjectURL(url),1000);
  #|         inboxStatus.textContent = 'Inbox download requested. Verify it was saved; keep this HTML to reopen it. No approval or company state changed.';
  #|       } catch(error) { inboxStatus.textContent = error.message; }
  #|     });
  #|     document.getElementById('inbox-load').addEventListener('change',async event => {
  #|       const file = event.target.files?.[0], generation = ++inboxGeneration;
  #|       event.target.value = '';
  #|       if (!file) return;
  #|       try {
  #|         const data = validateInbox(await readInboxFile(file));
  #|         if (generation !== inboxGeneration) return;
  #|         if (inboxDirty && !window.confirm('Replace the current feedback inbox and preparer responses with this saved file?')) return;
  #|         reviews = data.reviews; responses = data.responses; preparer.value = data.preparer;
  #|         inboxDirty = false; renderInbox(); inboxStatus.textContent = 'Saved feedback inbox restored for this exact snapshot. Preparer dispositions are not approval.';
  #|       } catch(error) { if (generation === inboxGeneration) inboxStatus.textContent = error.message; }
  #|     });
  #|     document.getElementById('inbox-clear').addEventListener('click',() => {
  #|       if ((reviews.length || preparer.value) && !window.confirm('Clear the feedback inbox and preparer responses in this tab? Keep a downloaded copy if needed.')) return;
  #|       reviews = []; responses = []; preparer.value = ''; changed(); renderInbox();
  #|       inboxStatus.textContent = 'Inbox cleared in this tab. Previously downloaded files are unchanged.';
  #|     });
  #|     // A reviewer gets only their selected review and its preparer responses.
  #|     const replyStatus = document.getElementById('reply-status');
  #|     const clearReplies = () => { fields.forEach(field => field.reply.replaceChildren()); replyStatus.textContent = ''; };
  #|     const validateReply = data => {
  #|       if (!exact(data,['schema','preparer','review','responses']) || data.schema !== 'moonproj.plan-review-response.v1') throw Error('Expected MoonProj reviewer-response packet.');
  #|       const checked = validateInbox({schema:'moonproj.plan-review-inbox.v1',source_template:source,preparer:data.preparer,
  #|         reviews:[{label:'',review:data.review}],responses:data.responses});
  #|       return {schema:data.schema,preparer:checked.preparer,review:checked.reviews[0].review,responses:checked.responses};
  #|     };
  #|     const exportReply = index => {
  #|       try {
  #|         const data = validateReply({schema:'moonproj.plan-review-response.v1',preparer:preparer.value,review:reviews[index].review,
  #|           responses:responses.filter(row => row.review_index === index).map(row => ({...row,review_index:0}))});
  #|         const blob = new Blob([JSON.stringify(data)],{type:'application/json;charset=utf-8'});
  #|         if (blob.size > maxBytes) throw Error('Response packet exceeds 40 MB.');
  #|         const url = URL.createObjectURL(blob), a = document.createElement('a');
  #|         a.href = url; a.download = 'plan-review-response-' + (index+1) + '.json'; a.click();
  #|         setTimeout(() => URL.revokeObjectURL(url),1000);
  #|         inboxStatus.textContent = 'Response packet download requested for review ' + (index+1) + '. Verify the file. It includes the complete plan and only this review and its responses. Share manually with the original worksheet; no message was sent.';
  #|       } catch(error) { inboxStatus.textContent = error.message; }
  #|     };
  #|     document.getElementById('reply-load').addEventListener('change',async event => {
  #|       const file = event.target.files?.[0], generation = ++importGeneration;
  #|       event.target.value = '';
  #|       if (!file) return;
  #|       try {
  #|         const data = validateReply(await readInboxFile(file));
  #|         if (generation !== importGeneration) return;
  #|         if (dirty && !window.confirm('Replace current review notes with the original review in this response packet? Save your edits first.')) return;
  #|         clearReplies(); reviewer.value = data.review.reviewer;
  #|         fields.forEach((field,i) => { field.state.value = data.review.annotations[i].state; field.note.value = data.review.annotations[i].note; });
  #|         for (const response of data.responses) {
  #|           const field = fields[response.annotation_index], original = data.review.annotations[response.annotation_index];
  #|           el('h3','Preparer response to the original submitted review',field.reply);
  #|           el('p','Original reviewer state: ' + original.state,field.reply); el('pre',original.note || '(no note supplied)',field.reply);
  #|           el('p','Self-declared preparer: ' + (data.preparer || '(blank label)') + '; disposition: ' + response.disposition,field.reply);
  #|           el('pre',response.response || '(no response supplied yet)',field.reply);
  #|         }
  #|         dirty = false;
  #|         replyStatus.textContent = 'Responses loaded for ' + (data.review.reviewer || '(blank reviewer label)') + '. Edit review states/notes above each reply, then download review notes JSON. Replies refer to the original submission; no change is applied to the plan and no agreement or approval is inferred. Keep this response packet for reply context.';
  #|         status.textContent = 'Original submitted review restored. Save revised notes separately before closing.';
  #|       } catch(error) { if (generation === importGeneration) replyStatus.textContent = error.message; }
  #|     });
  #|     // Previous-plan feedback is reference-only. Template IDs are positional slots,
  #|     // so reviewers pair rows explicitly; equal slot IDs never establish identity.
  #|     const revisionStatus = document.getElementById('revision-status');
  #|     const revisionSummary = document.getElementById('revision-summary');
  #|     const previousRoot = document.getElementById('revision-previous');
  #|     const rowKinds = ['owners','tasks','milestones','risks'];
  #|     const rowsFor = value => [{kind:'scope',id:'',position:0,data:{notes:value.notes,currency:value.currency,limit:value.limit,contingency:value.contingency}},
  #|       ...rowKinds.flatMap(kind => value[kind].map((data,position) => ({kind,id:data.id,position,data})))];
  #|     const currentRows = rowsFor(plan);
  #|     const templateForReview = text => {
  #|       if (typeof text !== 'string' || text.length > 1000000) throw Error('Previous template must be text up to 1,000,000 code units.');
  #|       const value = JSON.parse(text);
  #|       if (!exact(value,['format','notes','currency','limit','contingency',...rowKinds]) || value.format !== 'moonproj-plan-template/v1' || ['notes','currency','limit','contingency'].some(k => typeof value[k] !== 'string')) throw Error('Unsupported previous plan template.');
  #|       const keys = {owners:['id','name','role'],tasks:['id','name','owner','milestone','cost','dependencies'],milestones:['id','name','owner','date','criteria','evidence'],risks:['id','summary','severity','owner','mitigation','tasks']};
  #|       const limits = {owners:40,tasks:100,milestones:40,risks:100}, ids = {};
  #|       for (const kind of rowKinds) {
  #|         if (!Array.isArray(value[kind]) || value[kind].length > limits[kind] || (kind === 'owners' && !value[kind].length)) throw Error('Previous template row limits exceeded.');
  #|         ids[kind] = new Set();
  #|         for (const row of value[kind]) {
  #|           if (!exact(row,keys[kind])) throw Error('Unsupported previous ' + kind + ' row.');
  #|           for (const key of keys[kind]) {
  #|             if (key === 'dependencies' || key === 'tasks') {
  #|               if (!Array.isArray(row[key]) || row[key].some(id => typeof id !== 'string' || !id.trim()) || new Set(row[key]).size !== row[key].length) throw Error('Invalid previous row references.');
  #|             } else if (typeof row[key] !== 'string') throw Error('Previous template fields must be text.');
  #|           }
  #|           if (!row.id.trim() || ids[kind].has(row.id)) throw Error('Previous row IDs must be nonempty and unique.');
  #|           ids[kind].add(row.id);
  #|         }
  #|       }
  #|       const ref = (id,kind) => { if (id !== '' && !ids[kind].has(id)) throw Error('Missing previous ' + kind + ' reference: ' + id); };
  #|       for (const row of value.tasks) { ref(row.owner,'owners'); ref(row.milestone,'milestones'); row.dependencies.forEach(id => ref(id,'tasks')); }
  #|       value.milestones.forEach(row => ref(row.owner,'owners'));
  #|       value.risks.forEach(row => { ref(row.owner,'owners'); row.tasks.forEach(id => ref(id,'tasks')); });
  #|       return value;
  #|     };
  #|     const priorReview = input => {
  #|       const previous = templateForReview(input?.source_template), rows = rowsFor(previous);
  #|       return {review:validate(input,input.source_template,rows),plan:previous,rows};
  #|     };
  #|     let revision = null, pairing = [], removed = [], revisionDirty = false, revisionGeneration = 0;
  #|     const revisionPacket = () => ({schema:'moonproj.plan-review-revision.v1',source_template:source,previous_review:revision.review,pairing,removed});
  #|     const validateRevision = data => {
  #|       if (!exact(data,['schema','source_template','previous_review','pairing','removed']) || data.schema !== 'moonproj.plan-review-revision.v1') throw Error('Expected MoonProj revision comparison JSON.');
  #|       if (data.source_template !== source) throw Error('This comparison belongs to a different exact current plan snapshot.');
  #|       const previous = priorReview(data.previous_review), used = new Set();
  #|       if (!Array.isArray(data.pairing) || data.pairing.length !== currentRows.length || data.pairing[0] !== 0) throw Error('Revision pairings are incomplete.');
  #|       data.pairing.forEach((index,i) => {
  #|         if (i > 0 && (index === null || index === 'added')) return;
  #|         if (!Number.isInteger(index) || index < 0 || index >= previous.rows.length || previous.rows[index].kind !== currentRows[i].kind || used.has(index)) throw Error('Invalid or repeated previous row pairing.');
  #|         used.add(index);
  #|       });
  #|       if (!Array.isArray(data.removed) || new Set(data.removed).size !== data.removed.length || data.removed.some(index => !Number.isInteger(index) || index <= 0 || index >= previous.rows.length || used.has(index))) throw Error('Removed rows must be unique unpaired previous rows.');
  #|       return {previous,pairing:[...data.pairing],removed:[...data.removed]};
  #|     };
  #|     const associated = (value,row) => {
  #|       const result = {};
  #|       if ('owner' in row.data) result.owner = value.owners.find(v => v.id === row.data.owner) || null;
  #|       if ('milestone' in row.data) result.milestone = value.milestones.find(v => v.id === row.data.milestone) || null;
  #|       if ('dependencies' in row.data) result.dependencies = row.data.dependencies.map(id => value.tasks.find(v => v.id === id));
  #|       if (row.kind === 'risks') result.tasks = row.data.tasks.map(id => value.tasks.find(v => v.id === id));
  #|       return result;
  #|     };
  #|     const titleFor = row => row.kind + ': ' + (row.data.name || row.data.summary || row.id || 'scope and budget');
  #|     const difference = (before,after) => {
  #|       const keys = [...new Set([...Object.keys(before.data),...Object.keys(after.data)])];
  #|       const changed = keys.filter(key => JSON.stringify(before.data[key]) !== JSON.stringify(after.data[key]));
  #|       return changed.length ? 'Literal fields differ: ' + changed.join(', ') + '.' : 'No literal row-field differences. This does not establish unchanged meaning or review validity.';
  #|     };
  #|     const changedRevision = () => { revisionDirty = true; revisionGeneration++; };
  #|     const renderRevision = () => {
  #|       fields.forEach(field => field.history.replaceChildren()); previousRoot.replaceChildren();
  #|       if (!revision) { revisionSummary.textContent = 'No previous review loaded. Current review decisions are independent.'; return; }
  #|       const used = new Set(pairing.filter(Number.isInteger));
  #|       revisionSummary.textContent = 'Historical reviewer: ' + (revision.review.reviewer || '(blank label)') + '. ' + (used.size-1) + ' paired rows; ' + pairing.filter(v => v === 'added').length + ' marked added; ' + removed.length + ' marked removed; ' + pairing.filter(v => v === null).length + ' unresolved current rows; ' + (revision.rows.length-used.size-removed.length) + ' unresolved previous rows. Labels and relationships are reviewer assertions, not verified provenance. No current review state was copied.';
  #|       currentRows.forEach((row,i) => {
  #|         const panel = fields[i].history; el('h3','Previous-plan review comparison',panel);
  #|         if (i > 0) {
  #|           const id = 'revision-pair-' + i, label = el('label','Explicitly pair this current row with a previous row',panel); label.htmlFor = id;
  #|           const choice = el('select',undefined,panel); choice.id = id;
  #|           for (const [value,text] of [['','Unresolved: no previous row selected'],['added','Mark as added in this revision']]) { const option=el('option',text,choice); option.value=value; }
  #|           revision.rows.forEach((old,j) => { if (old.kind === row.kind) { const option=el('option','Previous #' + (old.position+1) + ' / ' + old.id + ' / ' + (old.data.name || old.data.summary || ''),choice); option.value=String(j); } });
  #|           choice.value = pairing[i] === null ? '' : String(pairing[i]);
  #|           choice.addEventListener('change',event => {
  #|             event.stopPropagation?.(); const next = choice.value === '' ? null : choice.value === 'added' ? 'added' : Number(choice.value);
  #|             try {
  #|               const candidate = revisionPacket(); candidate.pairing = pairing.map((v,j) => j === i ? next : v);
  #|               const checked = validateRevision(candidate); pairing=checked.pairing; changedRevision(); renderRevision();
  #|               revisionStatus.textContent = 'Pairing changed. Inspect both complete rows and their linked context. Current review notes and states are unchanged.';
  #|             } catch(error) { choice.value = pairing[i] === null ? '' : String(pairing[i]); revisionStatus.textContent = error.message + ' Unpair or unmark the previous row first.'; }
  #|           });
  #|         }
  #|         const index = pairing[i];
  #|         if (!Number.isInteger(index)) { el('p',index === 'added' ? 'Marked ADDED by reviewer. This row still needs a fresh review.' : 'UNRESOLVED current row. Matching template IDs do not establish identity.',panel); return; }
  #|         const old=revision.rows[index], annotation=revision.review.annotations[index];
  #|         el('p','Explicit reference pairing only. Historical state: ' + annotation.state + '; never a decision on this current plan.',panel);
  #|         el('pre','Historical reviewer note:\n' + (annotation.note || '(no note supplied)'),panel);
  #|         el('p',difference(old,row),panel);
  #|         if (i > 0) el('p','Previous ' + row.kind + ' position ' + (old.position+1) + ' → current position ' + (row.position+1) + (old.position !== row.position ? ' (POSITION CHANGED).' : ' (same position; not identity proof).'),panel);
  #|         el('pre','PREVIOUS row:\n' + JSON.stringify(old.data,null,2),panel);
  #|         el('pre','CURRENT row:\n' + JSON.stringify(row.data,null,2),panel);
  #|         if (i > 0) {
  #|           el('pre','PREVIOUS linked context:\n' + JSON.stringify(associated(revision.plan,old),null,2),panel);
  #|           el('pre','CURRENT linked context:\n' + JSON.stringify(associated(plan,row),null,2),panel);
  #|         }
  #|       });
  #|       revision.rows.forEach((row,index) => {
  #|         if (used.has(index)) return;
  #|         const card=el('section',undefined,previousRoot), isRemoved=removed.includes(index), annotation=revision.review.annotations[index];
  #|         el('h3',(isRemoved ? 'REMOVED (reviewer assertion): ' : 'UNPAIRED previous row: ') + titleFor(row),card);
  #|         el('pre',JSON.stringify(row.data,null,2),card); el('p','Historical state: ' + annotation.state,card); el('pre',annotation.note || '(no note supplied)',card);
  #|         const button=el('button',isRemoved ? 'Undo removed label' : 'Mark previous row as removed',card); button.id='revision-remove-' + index; button.type='button';
  #|         button.addEventListener('click',() => { removed=isRemoved ? removed.filter(v => v !== index) : [...removed,index].sort((a,b) => a-b); changedRevision(); renderRevision(); revisionStatus.textContent='Previous row label changed. No plan row or review decision was changed.'; });
  #|       });
  #|     };
  #|     const loadRevision = async (event,session) => {
  #|       const file=event.target.files?.[0], generation=++revisionGeneration; event.target.value=''; if (!file) return;
  #|       try {
  #|         const data=await readInboxFile(file);
  #|         const checked=session ? validateRevision(data) : {previous:priorReview(data),pairing:currentRows.map((_,i) => i === 0 ? 0 : null),removed:[]};
  #|         if (generation !== revisionGeneration) return;
  #|         if (revisionDirty && !window.confirm('Replace unsaved revision pairings? Current review notes will remain unchanged.')) return;
  #|         revision=checked.previous; pairing=checked.pairing; removed=checked.removed; revisionDirty=false; renderRevision();
  #|         revisionStatus.textContent='Historical feedback loaded as reference only. Template IDs are regenerated positional slots. Pair rows explicitly and review the current plan independently; no approval or current decision was carried forward.';
  #|       } catch(error) { if (generation === revisionGeneration) revisionStatus.textContent=error.message; }
  #|     };
  #|     document.getElementById('revision-load').addEventListener('change',event => loadRevision(event,false));
  #|     document.getElementById('revision-resume').addEventListener('change',event => loadRevision(event,true));
  #|     document.getElementById('revision-save').addEventListener('click',() => {
  #|       try {
  #|         if (!revision) throw Error('Load a previous review first.');
  #|         const data=revisionPacket(); validateRevision(data); const blob=new Blob([JSON.stringify(data)],{type:'application/json;charset=utf-8'});
  #|         if (blob.size > maxBytes) throw Error('Revision comparison exceeds 40 MB.');
  #|         const url=URL.createObjectURL(blob), a=document.createElement('a'); a.href=url; a.download='plan-review-revision.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url),1000);
  #|         revisionStatus.textContent='Comparison download requested. Verify the file. It contains both full plans, historical notes and your pairings. Save current review notes separately. Nothing is sent automatically.';
  #|       } catch(error) { revisionStatus.textContent=error.message; }
  #|     });
  #|     document.getElementById('revision-clear').addEventListener('click',() => {
  #|       if (revisionDirty && !window.confirm('Clear unsaved revision pairings? Current review notes will remain unchanged.')) return;
  #|       revisionGeneration++; revision=null; pairing=[]; removed=[]; revisionDirty=false; renderRevision(); revisionStatus.textContent='Historical reference cleared. Current review notes remain unchanged.';
  #|     });
  #|     window.addEventListener('beforeunload',event => { if (revisionDirty) { event.preventDefault(); event.returnValue=''; } });
  #|     renderRevision();
  #|     renderInbox();
  #|   }
  #|   const encoded = JSON.stringify(source).replace(/</g,'\\u003c').replace(/>/g,'\\u003e').replace(/&/g,'\\u0026').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
  #|   return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; connect-src \'none\'; img-src \'none\'; form-action \'none\'; base-uri \'none\'"><title>MoonProj plan review</title><style>body{max-width:900px;margin:2rem auto;padding:1rem;font:16px system-ui}section{border-top:1px solid #aaa;padding:1rem 0}pre{white-space:pre-wrap;overflow-wrap:anywhere}label{display:block;margin-top:1rem}textarea{display:block;width:95%;min-height:6rem}button,input,select{font:inherit;margin:.5rem 0}#status{min-height:2rem}</style><h1>Plan review worksheet</h1><p>Editable planning snapshot, not a saved company plan or approval. All amounts, dates and assignments are proposals. No-change-requested is feedback only. Review each source row below.</p><p>Notes stay in this tab. Download JSON before closing; reopen this HTML and load that JSON to resume. Keep both files. Sharing either file reveals the complete plan and its free text. Nothing is sent automatically.</p><label for="reviewer">Reviewer label (self-declared)</label><input id="reviewer" maxlength="1000"><br><button id="save" type="button">Download review notes JSON</button><label for="load">Load saved review notes for this snapshot</label><input id="load" type="file" accept=".json,application/json"><p id="status" role="status" aria-live="polite"></p><label for="reply-load">Load preparer response packet and resume original review</label><input id="reply-load" type="file" accept=".json,application/json"><p id="reply-status" role="status" aria-live="polite"></p><section aria-labelledby="revision-heading"><h2 id="revision-heading">Re-review a revised plan</h2><p>Load a previous review as historical reference. Template IDs are regenerated positional slots, not stable project IDs. Choose each old/current row pairing explicitly. Added/removed labels are your assertions. No historical state or note is copied into the current review. Inspect scope, row order and linked context independently.</p><label for="revision-load">Load previous plan review notes JSON</label><input id="revision-load" type="file" accept=".json,application/json"><label for="revision-resume">Resume saved revision comparison for this exact current snapshot</label><input id="revision-resume" type="file" accept=".json,application/json"><button id="revision-save" type="button">Download revision comparison JSON</button><button id="revision-clear" type="button">Clear previous-plan reference</button><p>Keep this current HTML, comparison JSON and your separately saved current review notes. Both full plans and historical feedback are included in the comparison. Nothing is sent automatically.</p><p id="revision-status" role="status" aria-live="polite"></p><p id="revision-summary"></p><h3>Unpaired or removed previous rows</h3><div id="revision-previous"></div></section><main id="review"></main><section aria-labelledby="inbox-heading"><h2 id="inbox-heading">Preparer feedback inbox</h2><p>Collect returned review-notes JSON for this exact snapshot. Reviewer labels are self-declared. Original feedback stays separate from your responses; nothing changes the plan. All notes and question/change-requested rows become feedback items. Empty not-reviewed/no-change-requested rows remain in the coverage counts.</p><p>Open and change-planned items need action. Answered and not-adopted need your explanation; they do not establish reviewer agreement, applied changes or approval. Filtered items stay visible while editing; refresh the view when ready.</p><label for="preparer">Preparer label (self-declared)</label><input id="preparer" maxlength="1000"><label for="inbox-import">Add returned review-notes JSON files</label><input id="inbox-import" type="file" accept=".json,application/json" multiple><label for="inbox-filter">Feedback view</label><select id="inbox-filter"><option value="all">All feedback</option><option value="needs-action">Needs action</option></select><button id="inbox-refresh" type="button">Refresh feedback view</button><p id="inbox-summary" role="status" aria-live="polite"></p><button id="inbox-save" type="button">Download feedback inbox JSON</button><label for="inbox-load">Reopen saved feedback inbox</label><input id="inbox-load" type="file" accept=".json,application/json"><button id="inbox-clear" type="button">Clear inbox in this tab</button><p>Download before closing and keep the original HTML. Sharing the inbox reveals the complete plan, every imported review and your responses. Nothing is sent automatically.</p><p id="inbox-status" role="status" aria-live="polite"></p><div id="inbox"></div></section><script>(' + worksheet.toString() + ')(' + encoded + ');</script></html>';
  #| }
