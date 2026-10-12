#!/usr/bin/env node
// Exercise the actual production JS extern, not a separate parser copy.
// Node provides the runtime; the FileReader/document seam below is simulated.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const main = readFileSync(new URL('../frontend/main/main.mbt', import.meta.url), 'utf8');
const csv = readFileSync(new URL('../frontend/main/import_csv.mbt', import.meta.url), 'utf8');
const native = readFileSync(new URL('../cmd/postgres_company_service/import_commands.mbt', import.meta.url), 'utf8');
function extern(source, name, context = {}) {
  const start = source.indexOf(`extern "js" fn ${name}(`);
  assert.notEqual(start, -1, `missing production extern ${name}`);
  const block = source.slice(start).split('\n///|')[0];
  const lines = block.split('\n').filter(line => /^\s*#\|/.test(line));
  assert.ok(lines.length, `missing body for ${name}`);
  return vm.runInNewContext(`(${lines.map(line => line.replace(/^\s*#\| ?/, '')).join('\n')})`, context);
}
const parseRaw = extern(csv, 'parse_import_csv_json');
const parse = value => JSON.parse(parseRaw(value));
const values = value => JSON.parse(parse(value).rows_json);
const templateHeaders = [...native.matchAll(/\\u\{FEFF\}([^"\n]+)\\n"/g)].map(match => match[1]);
assert.equal(templateHeaders.length, 2, 'both actual service templates must be covered');
const [project, contract] = templateHeaders;
function reject(input, match) {
  const result = parse(input);
  assert.match(result.error, match);
  assert.equal(result.within_limit, false);
  assert.equal(result.rows_json, '[]', 'invalid input never exposes a partial batch');
  assert.deepEqual(result.preview_rows, []);
  assert.equal(result.row_count, '0');
}

test('legacy project template accepts BOM, trimming, and a trailing newline', () => {
  const result = parse(`\uFEFF${project}\n P-1 ,示例项目,Short,BU-1,initiation,2026-10-11\n`);
  assert.equal(result.error, '');
  assert.equal(result.within_limit, true);
  assert.deepEqual(result.headers, project.split(','));
  assert.deepEqual(JSON.parse(result.rows_json), [{ projCode: 'P-1', projName: '示例项目', projShortName: 'Short', buCode: 'BU-1', projStatus: 'initiation', beginDate: '2026-10-11' }]);
});

test('contract template keeps quoted names and amount strings for native validation', () => {
  const input = `${contract}\r\nC-1,"Legal, \"\"review\"\"",P-1,consulting,"供应商\r\n上海",00123.40,2026-10-11\r\n`;
  assert.deepEqual(values(input), [{ contractCode: 'C-1', contractName: 'Legal, "review"', projCode: 'P-1', htClass: 'consulting', yfProviderName: '供应商\n上海', htAmount: '00123.40', signDate: '2026-10-11' }]);
});

test('explicit optional business-unit column survives contract intake', () => {
  assert.match(native, /import_project_text\(row, "buCode", "bu_code"\)/);
  const input = `${contract},buCode\nC-1,Review,P-1,consulting,Vendor,123.40,2026-10-11,BU-1`;
  assert.equal(values(input)[0].buCode, 'BU-1');
});

test('empty optional values remain present, including trailing empty fields', () => {
  assert.deepEqual(values('a,b,c\n1,,\n2,"",last'), [{ a: '1', b: '', c: '' }, { a: '2', b: '', c: 'last' }]);
});

test('CR and CRLF records and embedded line endings normalize safely', () => {
  assert.deepEqual(values('a,b\r1,"two\rthree"\r2,four\r'), [{ a: '1', b: 'two\nthree' }, { a: '2', b: 'four' }]);
});

test('blank physical records are ignored without discarding quoted blank data', () => {
  assert.deepEqual(values('\n \t\r\na\n\n""\nvalue\n \n'), [{ a: '' }, { a: 'value' }]);
});

test('space after a closing quote is accepted, interior spaces retained', () => {
  assert.deepEqual(values('a,b\n"a  b" \t," c "'), [{ a: 'a  b', b: 'c' }]);
});

test('500 rows are accepted but only the first five are previewed', () => {
  const result = parse('id\n' + Array.from({ length: 500 }, (_, i) => `R-${i}`).join('\n'));
  assert.equal(result.row_count, '500');
  assert.equal(result.preview_rows.length, 5);
  assert.equal(JSON.parse(result.rows_json).length, 500);
  assert.match(native, /rows\.length\(\) > 500/);
});

test('501 rows reject the whole batch', () => reject('id\n' + 'row\n'.repeat(501), /500/));
test('a malformed late row discards earlier valid rows', () => reject('a,b\n1,2\n3', /第 3 行有 1 列/));
test('missing columns are repairable errors', () => reject('a,b,c\n1,2', /有 2 列，表头为 3 列/));
test('extra columns never truncate user input', () => reject('a,b\n1,2,3', /有 3 列，表头为 2 列/));
test('duplicate headers are rejected after trimming', () => reject('a, a\n1,2', /重复表头/));
test('empty header rejects', () => reject('a,\n1,2', /表头为空或无效/));
test('non-template header syntax rejects', () => reject('user email\nvalue', /表头为空或无效/));
test('empty file, BOM only, header only, and blank data reject', () => {
  for (const value of ['', '\uFEFF', '\n\r\n', 'a,b', 'a,b\n\n']) reject(value, /为空或没有数据/);
});
test('unclosed quoted field rejects with position', () => reject('a,b\n1,"open\nnext', /第 3 行.*未闭合/));
test('quote in a plain field rejects', () => reject('a,b\n1,ab"cd', /字段内的引号/));
test('non-whitespace after a closing quote rejects', () => reject('a,b\n1,"ok"garbage', /结束引号后/));
test('NUL rejects, including inside quotes', () => reject('a\n"b\0c"', /不支持 NUL/));
test('input and field size limits fail closed', () => {
  reject('a'.repeat(2 * 1024 * 1024 + 1), /2 Mi/);
  reject('a\n"' + 'b'.repeat(32769) + '"', /32768/);
  assert.equal(values('a\n"' + 'b'.repeat(32768) + '"')[0].a.length, 32768);
});
test('64 columns accepted, 65 rejected', () => {
  const header = Array.from({ length: 64 }, (_, i) => `field${i}`);
  assert.equal(parse(header.join(',') + '\n' + '1,'.repeat(63) + '1').error, '');
  reject([...header, 'extra'].join(',') + '\n1', /64/);
});
test('prototype-like property names remain ordinary own data', () => {
  const result = values('constructor,prototype\nx,y')[0];
  assert.equal(Object.hasOwn(result, 'constructor'), true);
  assert.equal(result.constructor, 'x');
  assert.equal(result.prototype, 'y');
  reject('__proto__\nvalue', /表头为空或无效/);
});

test('deterministic quoted CSV round-trip across mixed Unicode and delimiters', () => {
  const parts = ['alpha', '中文', 'a,b', 'a"b', 'x\ny', 'x\r\ny', 'x\ry', '', '  ', '\t', '🙂'];
  const quote = value => '"' + value.replaceAll('"', '""') + '"';
  for (let run = 0; run < 100; run++) {
    const expected = Array.from({ length: 6 }, (_, row) => ({
      a: parts[(run + row) % parts.length],
      b: parts[(run * 3 + row * 7) % parts.length],
    }));
    const text = 'a,b\r\n' + expected.map(row => [row.a, row.b].map(quote).join(',')).join('\r\n');
    assert.deepEqual(values(text), expected.map(row => Object.fromEntries(Object.entries(row).map(([key, value]) => [key, value.replace(/\r\n?/g, '\n').trim()]))));
  }
});

test('actual UTF-8 File bytes flow through the production file callback and parser', async () => {
  const bytes = new TextEncoder().encode(`\uFEFF${project}\r\nP-1,"规划, \"\"一期\"\"",一期,BU-1,,\r\n`);
  const file = new Blob([bytes], { type: 'text/csv' });
  let encoding;
  class FileReader {
    readAsText(blob, codec) {
      encoding = codec;
      blob.text().then(text => { this.result = text; this.onload(); });
    }
  }
  const read = extern(main, 'read_file_input_text', { FileReader, document: { getElementById: id => {
    assert.equal(id, 'erp-import-project-file');
    return { files: [file] };
  } } });
  const content = await new Promise(resolve => read('erp-import-project-file', resolve));
  assert.equal(encoding, 'utf-8');
  assert.equal(values(content)[0].projName, '规划, "一期"');
});

test('cancelled or failed file reads cannot produce a submit-ready batch', async () => {
  const cancelled = extern(main, 'read_file_input_text', { document: { getElementById: () => null } });
  reject(await new Promise(resolve => cancelled('none', resolve)), /为空或没有数据/);
  class FileReader { readAsText() { queueMicrotask(() => this.onerror()); } }
  const failed = extern(main, 'read_file_input_text', { FileReader, document: { getElementById: () => ({ files: [{}] }) } });
  reject(await new Promise(resolve => failed('file', resolve)), /为空或没有数据/);
});

test('the production adapter and reducer gate dry-run on parser success', () => {
  assert.match(main, /@json\.parse\(parse_import_csv_json\(text\)\)/);
  assert.match(main, /parsed\.within_limit &&\s*parsed\.error\.is_empty\(\)/);
  assert.match(main, /import_note: if !parsed\.error\.is_empty\(\) \{\s*parsed\.error/);
  assert.match(main, /RunImportDryRun =>\s*if model\.import_state == "ready"/);
  assert.match(main, /CommitImportBatch =>\s*if model\.import_state == "dry_run_ok"/);
});

test('valid, invalid, and corrected reselections do not retain a previous batch', () => {
  const first = parse('id,name\nold,"First, draft"');
  assert.equal(first.within_limit, true);
  reject('id,name\nnew,"unfinished', /未闭合/);
  const corrected = parse('id,name\nnew,"Corrected, draft"');
  assert.equal(corrected.error, '');
  assert.deepEqual(JSON.parse(corrected.rows_json), [{ id: 'new', name: 'Corrected, draft' }]);
  assert.deepEqual(corrected.preview_rows, [['new', 'Corrected, draft']]);
  assert.equal(corrected.row_count, '1');
  assert.deepEqual(parse('id,name\nnew,"Corrected, draft"'), corrected);
  assert.deepEqual(JSON.parse(first.rows_json), [{ id: 'old', name: 'First, draft' }]);
});
