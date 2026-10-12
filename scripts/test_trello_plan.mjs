import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
const root = new URL('../', import.meta.url);
const read = p => readFileSync(new URL(p, root), 'utf8');
const converter = read('frontend/opc/project_plan_trello.mbt');
const body = converter.split('\n///|')[0].split('\n').filter(l => /^\s*#\|/.test(l)).map(l => l.replace(/^\s*#\| ?/, '')).join('\n');
const convert = vm.runInNewContext(`(${body})`);
function board() { return { id: 'b1', name: 'Client roadmap', closed: false, desc: 'Source scope', url: 'https://trello.com/b/example', lists: [
  { id: 'later', name: 'Later', closed: false, pos: 20 }, { id: 'now', name: 'Now', closed: false, pos: 10 }, { id: 'old', name: 'Archive', closed: true, pos: 0 }
], cards: [
  { id: 'C', idBoard: 'b1', name: 'Ship', closed: false, idList: 'later', pos: 10 },
  { id: 'B', name: 'Review', closed: false, idList: 'now', pos: 20, dueComplete: true },
  { id: 'A', name: 'Research, 中文', closed: false, idList: 'now', pos: 10, desc: 'Line one\nLine two', due: '2026-11-01T12:00:00.000Z', idMembers: ['m1','missing'], labels: [{ name: 'Customer', color: 'green' }], idChecklists: ['cl1'] },
  { id: 'X', name: 'Archived card', closed: true, idList: 'now' }, { id: 'Y', name: 'Archived list card', closed: false, idList: 'old' }
], members: [{ id: 'm1', fullName: 'Sam' }], checklists: [{ id: 'cl1', idCard: 'A', name: 'Preparation', checkItems: [{ name: 'Read brief', state: 'complete' }, { name: 'Check sources', state: 'incomplete' }] }] }; }
const result = input => JSON.parse(convert(typeof input === 'string' ? input : JSON.stringify(input)));
function success(input) { const r = result(input); assert.equal(r.error, ''); return JSON.parse(r.template); }
function rejects(input, match) { const r = result(input); assert.match(r.error, match); assert.equal(r.template, ''); }
function checkTemplate(t) {
  // The exact field/reference contract in product/plan_workbench/template.mbt.
  assert.deepEqual(Object.keys(t).sort(), ['format','notes','currency','limit','contingency','owners','tasks','milestones','risks'].sort());
  assert.equal(t.format, 'moonproj-plan-template/v1');
  for (const key of ['notes','currency','limit','contingency']) assert.equal(typeof t[key], 'string');
  assert.ok(t.owners.length >= 1 && t.owners.length <= 40);
  assert.ok(t.tasks.length <= 100);
  assert.equal(new Set(t.tasks.map(v => v.id)).size, t.tasks.length);
  for (const row of t.tasks) {
    assert.deepEqual(Object.keys(row).sort(), ['id','name','owner','milestone','cost','dependencies'].sort());
    for (const key of ['id','name','owner','milestone','cost']) assert.equal(typeof row[key], 'string');
    assert.ok(row.owner === '' || t.owners.some(v => v.id === row.owner));
    assert.ok(row.milestone === '' || t.milestones.some(v => v.id === row.milestone));
    for (const id of row.dependencies) assert.ok(t.tasks.some(v => v.id === id));
  }
}

test('board converts to existing editable template with list/card order and exact source IDs', () => {
  const t = success(board()); checkTemplate(t);
  assert.deepEqual(t.tasks.map(v => v.id), ['A','B','C']);
  assert.equal(t.tasks[0].name, 'Research, 中文');
  assert.match(t.notes, /3 open cards imported; 2 archived/);
});
test('details survive in source notes without inferred assignment or execution facts', () => {
  const t = success(board());
  for (const text of ['Sam', 'missing', '(not present in export)', 'Line one\\nLine two', '2026-11-01T12:00:00.000Z', 'Customer', 'Preparation', 'Read brief', 'incomplete', '"dueComplete": true']) assert.ok(t.notes.includes(text), text);
  for (const task of t.tasks) assert.deepEqual({ ...task, id: '', name: '' }, { id:'', name:'', owner:'', milestone:'', cost:'', dependencies:[] });
  assert.deepEqual(t.milestones, []); assert.deepEqual(t.risks, []);
  assert.equal(t.currency, ''); assert.equal(t.limit, ''); assert.equal(t.contingency, '');
});
test('unsupported sensitive export details are not imported and omissions are explicit', () => {
  const b = board(); b.actions = [{ text: 'PRIVATE_COMMENT_MARKER' }]; b.cards[2].attachments = [{ name: 'PRIVATE_ATTACHMENT_MARKER' }];
  const t = success(b); assert.ok(!t.notes.includes('PRIVATE_')); assert.match(t.notes, /Comments, attachments, actions, custom fields/);
});
test('conversion is deterministic and source object is unchanged', () => {
  const b = board(), before = JSON.stringify(b); assert.deepEqual(success(b), success(b)); assert.equal(JSON.stringify(b), before);
});
test('BOM and Unicode JSON paste are accepted', () => checkTemplate(success('\uFEFF'+JSON.stringify(board()))));
test('empty/open and archived boards are repairable failures', () => {
  const b = board(); b.closed = true; rejects(b, /Archived board/); b.closed = false; b.cards = []; rejects(b, /No open cards/);
});
test('incomplete board references fail with no partial template', () => {
  const b = board(); b.cards[2].idList = 'missing'; rejects(b, /missing list/);
  const c = board(); c.checklists = []; rejects(c, /missing checklist/);
  const d = board(); d.checklists[0].idCard = 'B'; rejects(d, /another card/);
});
test('duplicate identities and foreign-board cards require correction', () => {
  const b = board(); b.cards.push({...b.cards[0]}); rejects(b, /duplicate id/);
  const c = board(); c.cards[0].idBoard = 'elsewhere'; rejects(c, /another board/);
});
test('wrong types and malformed JSON yield repairable errors', () => {
  rejects('{', /Trello import/); rejects('null', /expected object/);
  const b = board(); delete b.cards[1].closed; rejects(b, /expected boolean/);
  const c = board(); c.cards[2].desc = {}; rejects(c, /expected text/);
});
test('100-card bound produces a usable template; 101-card board cannot partially import', () => {
  const b = board(); b.cards = Array.from({length:100}, (_,i) => ({id:'c'+i,name:'Task '+i,idList:'now',closed:false,pos:i}));
  checkTemplate(success(b)); b.cards.push({...b.cards[0],id:'overflow'}); rejects(b, /100 open cards/);
});
test('input size and expanded output have bounded failure', () => {
  rejects('x'.repeat(1000001), /1,000,000/);
  const b = board(); b.cards[2].desc = '\\'.repeat(300000); assert.ok(JSON.stringify(b).length < 1000000); rejects(b, /Converted plan exceeds/);
});
test('missing positions retain export order within each list', () => {
  const b = board(); b.cards.forEach(c => delete c.pos); assert.deepEqual(success(b).tasks.map(v => v.id), ['B','A','C']);
});
test('source wiring only: adapter calls template validation and explicit local preview/apply paths', () => {
  assert.match(converter, /@plan_workbench\.read_template\(template\)/);
  assert.match(converter, /raise @plan_workbench\.Invalid\(error\)/);
  const ui = read('frontend/opc/project_plan_template.mbt');
  assert.match(ui, /Template\(PreviewTrello\)/);
  assert.match(ui, /Preview \| PreviewTrello =>/);
  assert.match(ui, /plan_trello_read_template\(t\.source\)/);
  assert.match(ui, /trello: action == PreviewTrello/);
  assert.match(ui, /if t\.trello \{\s*\{ \.\.after, notes: d\.notes \+ "\\n\\n" \+ preview\.notes/);
  assert.match(ui, /before == d/);
  assert.match(ui, /@plan_workbench\.apply_template/);
  assert.match(ui, /@plan_workbench\.append_template/);
  assert.match(ui, /plan_save_edit\(s, (draft|after)\)/);
  assert.match(ui, /Source\(source\) => \{ \.\.plan_template_initial\(\), source/);
  const core = read('product/plan_workbench/template.mbt');
  assert.match(core, /Blank assignments remain editable blanks/);
  assert.match(core, /pub fn read_template/);
  assert.match(core, /template_validate\(t\)/);
});

test('invalid and unusual due text stays exact source context without generated milestones', () => {
  for (const due of ['2026-02-30T25:99:00Z', 'next Tuesday after review', '']) {
    const b = board(); b.cards[2].due = due;
    const t = success(b);
    const cardContext = JSON.parse(t.notes.split('Source card A (task ID in this preview: A)\n')[1].split('\n\nSource card B')[0]);
    assert.equal(cardContext.due, due);
    assert.deepEqual(t.milestones, []);
    assert.ok(t.tasks.every(task => task.milestone === ''));
  }
});
