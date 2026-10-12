///|
// The picker decodes this small JSON envelope in parse_import_csv. Keeping the
// parser at the browser boundary supports quoted CSV without adding a runtime
// dependency or weakening the signed service's dry-run and commit checks.
#cfg(target="js")
extern "js" fn parse_import_csv_json(text : String) -> String =
  #| (text) => {
  #|   const empty = { headers: [], preview_rows: [], rows_json: '[]', row_count: '0', within_limit: false, error: '' };
  #|   const fail = (message) => JSON.stringify({ ...empty, error: message });
  #|   if (text.length > 2 * 1024 * 1024) return fail('CSV 超过 2 Mi 字符上限 · 请拆分文件');
  #|   if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);
  #|   let headers = null, row = [], field = '', state = 'start', touched = false;
  #|   let line = 1, column = 1, recordLine = 1;
  #|   const rows = [], preview = [];
  #|   const problem = (message) => `CSV 第 ${line} 行，第 ${column} 列：${message}`;
  #|   const finishField = () => { row.push(field.trim()); field = ''; state = 'start'; };
  #|   const finishRecord = () => {
  #|     finishField();
  #|     if (touched) {
  #|       if (headers === null) {
  #|         if (row.length > 64) return 'CSV 表头超过 64 列上限';
  #|         if (row.some(value => !/^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(value))) return 'CSV 表头为空或无效 · 请使用下载模板的字段名';
  #|         if (new Set(row).size !== row.length) return 'CSV 包含重复表头 · 每个字段只能出现一次';
  #|         headers = row;
  #|       } else {
  #|         if (row.length !== headers.length) return `CSV 第 ${recordLine} 行有 ${row.length} 列，表头为 ${headers.length} 列 · 请补齐空值或用双引号包围逗号`;
  #|         if (rows.length === 500) return 'CSV 超过 500 行上限 · 请拆分批次';
  #|         const fields = Object.create(null);
  #|         headers.forEach((header, index) => { fields[header] = row[index]; });
  #|         rows.push(fields);
  #|         if (preview.length < 5) preview.push(row);
  #|       }
  #|     }
  #|     row = []; touched = false;
  #|     return '';
  #|   };
  #|   for (let index = 0; index < text.length; index++) {
  #|     let char = text[index];
  #|     if (char === '\0') return fail(problem('不支持 NUL 字符'));
  #|     const newline = char === '\r' || char === '\n';
  #|     if (state === 'quoted') {
  #|       if (char === '"') {
  #|         if (text[index + 1] === '"') { field += '"'; index++; column++; }
  #|         else state = 'closed';
  #|       } else if (newline) {
  #|         field += '\n';
  #|       } else field += char;
  #|     } else if (char === ',') {
  #|       finishField(); touched = true;
  #|       if (row.length >= 64) return fail(problem('超过 64 列上限'));
  #|     } else if (newline) {
  #|       const error = finishRecord();
  #|       if (error) return fail(error);
  #|     } else if (state === 'closed') {
  #|       if (char !== ' ' && char !== '\t') return fail(problem('结束引号后只允许逗号、换行或空白'));
  #|     } else if (char === '"') {
  #|       if (state !== 'start') return fail(problem('字段内的引号必须转义，或用双引号包围整个字段'));
  #|       state = 'quoted'; touched = true;
  #|     } else {
  #|       field += char; state = 'plain';
  #|       if (char.trim() !== '') touched = true;
  #|     }
  #|     if (field.length > 32768) return fail(problem('字段超过 32768 字符上限'));
  #|     if (newline) {
  #|       if (char === '\r' && text[index + 1] === '\n') index++;
  #|       line++; column = 1;
  #|       if (state === 'start') recordLine = line;
  #|     } else column++;
  #|   }
  #|   if (state === 'quoted') return fail(problem('双引号未闭合'));
  #|   if (touched || row.length || field.length) {
  #|     const error = finishRecord();
  #|     if (error) return fail(error);
  #|   }
  #|   if (!headers || rows.length === 0) return fail('CSV 为空或没有数据行');
  #|   return JSON.stringify({ headers, preview_rows: preview, rows_json: JSON.stringify(rows), row_count: String(rows.length), within_limit: true, error: '' });
  #| }
