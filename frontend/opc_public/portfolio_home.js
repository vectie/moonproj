const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let catalogPromise;
const catalog = () => catalogPromise ||= fetch('./portfolio_catalog.json').then(response => { if (!response.ok) throw Error('Bundled product catalog unavailable'); return response.json(); });

export function mountPortfolio(host, deps = {}) {
  const getCatalog = deps.catalog || catalog;
  const getState = deps.getState || (() => fetch('/api/portfolio/state').then(response => { if (!response.ok) throw Error(`Local portfolio host returned ${response.status}`); return response.json(); }));
  const post = deps.post || (async (route, body) => { const response = await fetch(`/api/portfolio/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }); const value = await response.json(); if (!response.ok) throw Error(value.error || `HTTP ${response.status}`); return value; });
  let products = [], selected = 'moonproj', query = '', group = '', chosenRequirement = '', jobs = [], executionConfigured = false, hostError = '', error = '', notice = '', output = null;
  let disposed = false;
  const product = () => products.find(item => item.id === selected);
  async function refresh() { try { const value = await getState(); if (disposed) return; jobs = value.jobs || []; executionConfigured = value.executionConfigured === true; hostError = ''; render(); } catch (e) { if (disposed) return; hostError = e.message; render(); } }
  function render() {
    if (disposed || !host.isConnected) return;
    const item = product();
    const filtered = products.filter(p => (!group || p.group === group) && (!query || `${p.name} ${p.job} ${p.role_intent?.role || ''}`.toLowerCase().includes(query.toLowerCase())));
    const reqs = item?.requirements || [];
    if (item && !reqs.some(r => r['Requirement ID'] === chosenRequirement)) chosenRequirement = reqs.find(r => r.Scope === 'baseline' && r.Priority === 'P0')?.['Requirement ID'] || reqs[0]?.['Requirement ID'] || '';
    const selectedRow = reqs.find(r => r['Requirement ID'] === chosenRequirement);
    const recent = jobs.filter(j => j.productId === selected).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    const current = recent.find(j => j.requirementId === chosenRequirement);
    const busy = current?.status === 'running';
    const implementation = current?.implementation;
    host.innerHTML = `<div class="portfolio-home">
      <header class="portfolio-hero"><div><p class="portfolio-eyebrow">MoonProj · company portfolio</p><h2>Products → chosen work → a reviewable plan</h2><p>25 active products and MoonStat retirement. The accountable founder chooses what matters; MoonProj can prepare a real plan artifact locally. Producing a code or customer result needs a connected MoonClaw/MoonFlow execution path.</p></div><strong>25 active · 1 retired</strong></header>
      ${error ? `<p role="alert" class="prd-error">${esc(error)}</p>` : ''}${notice ? `<p role="status">${esc(notice)}</p>` : ''}
      ${hostError ? `<p role="status" class="prd-warning">Local execution host disconnected: ${esc(hostError)}. Product information still works. Run scripts/run_portfolio_workspace.sh to enable durable work and artifacts.</p>` : ''}
      <div class="portfolio-layout"><aside class="portfolio-list"><label>Find a product <input id="portfolio-query" value="${esc(query)}" placeholder="name or purpose"></label><label>Group <select id="portfolio-group"><option value="">All groups</option>${[...new Set(products.map(p => p.group))].map(g => `<option value="${esc(g)}" ${group === g ? 'selected' : ''}>${esc(g)}</option>`).join('')}</select></label><strong>${filtered.length} products</strong>${filtered.map(p => `<button type="button" data-product="${esc(p.id)}" class="portfolio-product ${selected === p.id ? 'active' : ''}"><b>${esc(p.name)}</b><small>${p.lifecycle === 'retired' ? 'retired · ' : ''}${esc(p.group)}</small></button>`).join('')}</aside>
      <main class="portfolio-detail">${item ? `<p class="portfolio-eyebrow">${esc(item.lifecycle)} · ${esc(item.group)} · ${esc(item.class)}</p><h2>${esc(item.name)}</h2><p><b>For:</b> ${esc(item.users.join(', '))}</p><p><b>Job:</b> ${esc(item.job)}</p><section class="portfolio-philosophy"><h3>Its place in the OPC system</h3><p>${esc(item.role_intent?.role || item.philosophy_recommendation)}</p><p>${esc(item.role_intent?.handoff || '')}</p><small>${esc(item.role_intent?.status || 'Source analysis; founder review needed')}</small></section><details><summary>Boundaries and known gaps</summary><ul>${item.boundaries.map(s => `<li>${esc(s)}</li>`).join('')}${item.known_gaps.map(s => `<li>${esc(s)}</li>`).join('')}</ul></details>
      <section class="portfolio-actions"><h3>Produce a bounded result</h3><p>Choose an existing requirement. The local MoonProj adapter creates a dependency and acceptance plan artifact. It does not execute code, verify the PRD, approve spending, or create company facts.</p><label>Requirement <select id="portfolio-requirement" ${item.lifecycle !== 'active' ? 'disabled' : ''}>${reqs.map(r => `<option value="${esc(r['Requirement ID'])}" ${chosenRequirement === r['Requirement ID'] ? 'selected' : ''}>${esc(r['Requirement ID'])} · ${esc(r['Requirement title'])}</option>`).join('')}</select></label>${selectedRow ? `<p><b>${esc(selectedRow.Scope)} · ${esc(selectedRow.Priority || 'unprioritized')}</b> — ${esc(selectedRow['Requirement statement'])}</p><p>Acceptance: ${esc(selectedRow['Acceptance criteria'])}</p><small>Imported assessment: ${esc(selectedRow['Current assessment'])}. This is source provenance, not independent verification.</small>` : ''}<div class="portfolio-buttons"><button id="portfolio-plan" ${!selectedRow || item.lifecycle !== 'active' || !!hostError || busy ? 'disabled' : ''}>${current?.status === 'produced' ? 'Open existing result' : current?.status === 'failed' || current?.status === 'cancelled' || current?.status === 'interrupted' ? 'Retry same plan' : 'Generate review-pending plan'}</button>${busy ? '<button id="portfolio-cancel">Cancel local run</button>' : ''}<button id="portfolio-prd">Open detailed PRD</button></div>${current ? `<p class="portfolio-run"><b>${esc(current.status)}</b> · ${esc(current.message)} · ${esc(current.updatedAt)}</p>` : ''}${output ? `<div class="portfolio-output"><h4>Produced plan</h4><p>${esc(output.project?.name)} · ${esc(output.workflow?.status)}</p><ul>${(output.tasks || []).map(t => `<li>${esc(t.task_id)} — ${esc(t.name)} · owner: ${esc(t.owner_id)}</li>`).join('')}</ul><p>Next: ${esc((output.workflow?.next_actions || []).join(' / '))}</p><a target="_blank" rel="noopener" href="/api/portfolio/artifact/${encodeURIComponent(current?.id || '')}">Open exact JSON artifact</a></div>` : ''}<div class="portfolio-output"><h4>Implementation work</h4><p>${implementation ? `${esc(implementation.status)}${implementation.blocker ? ` · ${esc(implementation.blocker)}` : ''}` : 'Choose a requirement and produce its plan first.'}</p>${executionConfigured && current?.status === 'produced' && implementation?.status === 'awaiting_approved_handoff' ? '<button id="portfolio-handoff">Prepare approved MoonFlow work</button>' : ''}${implementation?.runId ? `<p>MoonFlow run: ${esc(implementation.runId)} · MoonClaw session: ${esc(implementation.sessionId || '')} · goal: ${esc(implementation.goalId || '')}</p><a target="_blank" rel="noopener" href="/api/portfolio/handoff/${encodeURIComponent(current.id)}">Open exact handoff</a>` : ''}${implementation?.resultId ? `<p>Result: ${esc(implementation.resultId)} · attempt: ${esc(implementation.attemptId)} · digest: ${esc(implementation.outputDigest)}</p><ul>${(implementation.artifacts || []).map(ref => `<li>${esc(ref)}</li>`).join('')}</ul>` : ''}${implementation?.accepted ? `<p>Accepted by ${esc(implementation.reviewerId)} in review ${esc(implementation.reviewId)}.</p>` : ''}</div></section>
      <section class="portfolio-activity"><h3>Local work history</h3>${recent.length ? recent.map(j => `<p><b>${esc(j.requirementId)}</b> · ${esc(j.status)} · ${esc(j.message)}</p>`).join('') : '<p>No local work has run for this product.</p>'}<p>MoonClaw agent work and signed company operations are disconnected in this local host. The adapter result remains a proposal until a named review.</p></section>` : '<p>Product catalog unavailable.</p>'}</main></div></div>`;
    const activityNote = host.querySelector('.portfolio-activity > p:last-child');
    if (activityNote) activityNote.textContent = 'MoonClaw work requires separately approved provider and sandbox routes. Only MoonFlow receipts bound to the exact plan appear as implementation results.';
    const implementationPanel = host.querySelector('.portfolio-actions > .portfolio-output:last-child');
    if (implementationPanel && executionConfigured && implementation?.status === 'ready_for_moonflow') {
      const button = document.createElement('button');
      button.textContent = 'Import approved work into MoonFlow';
      button.addEventListener('click', async () => { try { await post('flow', { id: current.id }); notice = 'MoonFlow imported the exact work graph and prepared its attempt. No model call was made.'; await refresh(); } catch (e) { error = e.message; render(); } });
      implementationPanel.append(button);
    }
    if (implementationPanel && implementation?.requestId && !implementation.invocationPrepared) {
      const button = document.createElement('button');
      button.textContent = 'Prepare MoonClaw dispatch packet';
      button.addEventListener('click', async () => { try { await post('invocation', { id: current.id }); notice = 'Exact MoonFlow attempt bound to a MoonClaw dispatch packet. No model call was made.'; await refresh(); } catch (e) { error = e.message; render(); } });
      implementationPanel.append(button);
    }
    if (implementationPanel && implementation?.invocationPrepared) {
      const detail = document.createElement('p');
      detail.textContent = implementation.providerCallsForbidden ? 'Dispatch packet prepared; provider calls are forbidden.' : 'Dispatch packet prepared; provider use still requires operator submission.';
      const link = document.createElement('a');
      link.href = `/api/portfolio/invocation/${encodeURIComponent(current.id)}`;
      link.target = '_blank'; link.rel = 'noopener'; link.textContent = 'Open exact dispatch packet';
      implementationPanel.append(detail, link);
    }
    host.querySelector('#portfolio-query')?.addEventListener('change', e => { query = e.target.value; render(); });
    host.querySelector('#portfolio-group')?.addEventListener('change', e => { group = e.target.value; render(); });
    host.querySelectorAll('[data-product]').forEach(button => button.addEventListener('click', () => { selected = button.dataset.product; chosenRequirement = ''; output = null; render(); }));
    host.querySelector('#portfolio-requirement')?.addEventListener('change', e => { chosenRequirement = e.target.value; output = null; render(); });
    host.querySelector('#portfolio-prd')?.addEventListener('click', () => { const detail = document.querySelector('#portfolio-prd-detail'); if (detail) detail.open = true; document.getElementById('prd-workspace')?.dispatchEvent(new CustomEvent('moonproj:open-prd', { detail: { product: item.name } })); detail?.scrollIntoView({ behavior: 'smooth' }); });
    host.querySelector('#portfolio-plan')?.addEventListener('click', async () => {
      try {
        error = ''; output = null;
        if (current?.status === 'produced') { output = await fetch(`/api/portfolio/artifact/${encodeURIComponent(current.id)}`).then(r => { if (!r.ok) throw Error(`Artifact unavailable: ${r.status}`); return r.json(); }); }
        else { const result = await post('plan', { productId: selected, requirementId: chosenRequirement }); notice = result.duplicate ? 'Existing attempt retained; no duplicate was created.' : 'Local MoonProj adapter started. Its produced result will appear here.'; await refresh(); }
      } catch (e) { error = e.message; } render();
    });
    host.querySelector('#portfolio-cancel')?.addEventListener('click', async () => { try { await post('cancel', { id: current.id }); await refresh(); } catch (e) { error = e.message; render(); } });
    host.querySelector('#portfolio-handoff')?.addEventListener('click', async () => { try { await post('handoff', { id: current.id }); notice = 'Exact approved plan bound to a MoonFlow work graph. Provider calls and code promotion remain separate gates.'; await refresh(); } catch (e) { error = e.message; render(); } });
  }
  getCatalog().then(value => { if (disposed) return; products = value.products; render(); refresh(); }).catch(e => { error = e.message; render(); });
  const timer = setInterval(() => { if (!host.isConnected) { clearInterval(timer); disposed = true; return; } if (jobs.some(j => j.status === 'running')) refresh(); }, 1800);
  return () => { disposed = true; clearInterval(timer); };
}

if (typeof document !== 'undefined') {
  let mounted = null, dispose = null;
  const observe = () => { const host = document.getElementById('portfolio-home'); if (host && host !== mounted) { dispose?.(); mounted = host; dispose = mountPortfolio(host); } if (!host && mounted) { dispose?.(); mounted = null; dispose = null; } };
  new MutationObserver(observe).observe(document.documentElement, { childList: true, subtree: true });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', observe); else observe();
}
