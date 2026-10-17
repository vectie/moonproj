import assert from 'node:assert/strict';

// Event-capable DOM substitute discovers controls from actual production markup.
// It exercises mounted handlers, not graphical browser layout or accessibility.
export function harness() {
  let html = '', nodes = [];
  const unescape = text => text.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const matches = (node, selector) => { const m = selector.match(/^\[([^=\]]+)(?:="([^"]*)")?\]$/); return m && Object.hasOwn(node.attrs, m[1]) && (m[2] === undefined || node.attrs[m[1]] === m[2]); };
  const host = {
    get innerHTML() { return html; }, set innerHTML(value) {
      html = value; nodes = [];
      for (const match of html.matchAll(/<(input|textarea|button|select|div)\b([^>]*)>/g)) {
        const attrs = Object.fromEntries([...match[2].matchAll(/([\w-]+)(?:="([^"]*)")?/g)].map(m => [m[1], unescape(m[2] || '')]));
        const dataset = Object.fromEntries(Object.entries(attrs).filter(([k]) => k.startsWith('data-')).map(([k, v]) => [k.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase()), v]));
        nodes.push({ attrs, dataset, disabled: Object.hasOwn(attrs, 'disabled'), checked: Object.hasOwn(attrs, 'checked'), value: attrs.value || unescape(match[1] === 'textarea' ? html.slice(match.index + match[0].length, html.indexOf('</textarea>', match.index)) : ''), events: {}, addEventListener(type, handler) { this.events[type] = handler; } });
      }
    }, querySelectorAll(selector) { return nodes.filter(node => matches(node, selector)); }, querySelector(selector) { return this.querySelectorAll(selector)[0] || null; },
  };
  const get = selector => { const found = host.querySelector(selector); assert.ok(found, `Missing ${selector}`); return found; };
  const input = (name, value) => { const n = get(`[data-field="${name}"]`); n.value = value; n.events.input({ target: n }); if (n.events.change) n.events.change({ target: n }); };
  const check = (selector, checked = true) => { const n = get(selector); n.checked = checked; n.events.change({ target: n }); };
  const acceptance = (id, field, value) => { const n = host.querySelectorAll('[data-acceptance-field]').find(n => n.dataset.acceptanceTask === id && n.dataset.acceptanceField === field); assert.ok(n); n.value = value; n.events.input({ target: n }); };
  const loadPlan = files => { const n = get('[data-plan-file]'); n.files = files; return n.events.change({ target: n }); };
  return { host, get, input, check, acceptance, loadPlan, click: action => get(`[data-action="${action}"]`).events.click(), upload: files => { const n = get('[data-evidence-files]'); n.files = files; return n.events.change({ target: n }); } };
}
