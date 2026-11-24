// Presentation adapter only: SVG wires, short causal motion and warm app views.
// It never creates tasks, starts agents, accepts work or owns execution state.
const SVG = 'http://www.w3.org/2000/svg'
const sessions = new WeakMap()
let scheduled = false
let launchRect = null

export function jobAppURL(reference, pageURL) {
  try {
    const url = new URL(reference), page = new URL(pageURL)
    const loopback = host => ['127.0.0.1', 'localhost', '[::1]'].includes(host)
    if (url.protocol !== 'http:' || !loopback(url.hostname) || url.port !== '4201' || url.pathname !== '/' || url.username || url.password ||
        !url.searchParams.get('workspace')?.startsWith('book-') || !url.searchParams.get('path') ||
        !['wiki', 'code'].includes(url.searchParams.get('activity'))) return ''
    // Local companion apps follow the shell's loopback hostname. This also
    // permits independent IPv4/IPv6 desktop sessions without changing a Book.
    if (loopback(page.hostname)) url.hostname = page.hostname
    return url.href
  } catch { return '' }
}

export function newDeliveryReceipts(previous, next) {
  return next.filter(job => job.parent && job.receipt && previous.has(job.id) && previous.get(job.id) !== job.receipt)
}

function reduced(root) {
  return root.dataset.motion === 'paused' || window.matchMedia('(prefers-reduced-motion: reduce)').matches || document.hidden
}

function svg(tag, attrs) {
  const element = document.createElementNS(SVG, tag)
  for (const [key, value] of Object.entries(attrs || {})) element.setAttribute(key, value)
  return element
}

function drawWires(root, state) {
  const board = root.querySelector('.flow-board'), host = root.querySelector('.flow-wires')
  if (!board || !host || !board.getClientRects().length) return
  const box = board.getBoundingClientRect()
  const jobs = [...board.querySelectorAll('.flow-job')].map(node => ({ node, rect: node.getBoundingClientRect(), id: node.dataset.jobId, parent: node.dataset.parent, receipt: node.dataset.receipt }))
  const goals = new Map([...board.querySelectorAll('.flow-goal')].map(node => [node.dataset.goalId, node.getBoundingClientRect()]))
  const lines = jobs.flatMap(job => {
    const goal = goals.get(job.parent)
    if (!goal) return []
    const narrow = box.width < 650
    const x1 = (narrow ? job.rect.left : job.rect.right) - box.left
    const y1 = job.rect.top + job.rect.height / 2 - box.top
    const x2 = goal.left - box.left, y2 = goal.top + goal.height / 2 - box.top
    const middle = narrow ? Math.min(x1, x2) - 18 : (x1 + x2) / 2
    return [{ ...job, path: `M ${x1} ${y1} C ${middle} ${y1}, ${middle} ${y2}, ${x2} ${y2}` }]
  })
  const changed = newDeliveryReceipts(state.receipts, jobs)
  state.receipts = new Map(jobs.map(job => [job.id, job.receipt]))
  const signature = JSON.stringify([box.width, box.height, lines.map(line => [line.path, line.receipt])])
  if (signature !== state.wires || !host.shadowRoot?.querySelector('svg')) {
    state.wires = signature
    const shadow = host.shadowRoot || host.attachShadow({ mode: 'open' })
    const canvas = svg('svg', { width: '100%', height: '100%', viewBox: `0 0 ${box.width} ${box.height}`, 'aria-hidden': 'true' })
    canvas.style.cssText = 'position:absolute;inset:0;overflow:visible;pointer-events:none;color:var(--ink-muted)'
    const defs = svg('defs'), arrow = svg('marker', { id: 'job-contribution-arrow', markerWidth: 7, markerHeight: 7, refX: 6, refY: 3.5, orient: 'auto' })
    arrow.append(svg('path', { d: 'M 0 0 L 6 3.5 L 0 7', fill: 'none', stroke: 'currentColor', 'stroke-width': 1.2 }))
    defs.append(arrow); canvas.append(defs)
    for (const line of lines) canvas.append(svg('path', { d: line.path, fill: 'none', stroke: 'currentColor', 'stroke-width': 1.4, 'stroke-dasharray': line.receipt ? '' : '4 5', 'marker-end': 'url(#job-contribution-arrow)' }))
    shadow.replaceChildren(canvas)
  }
  if (!reduced(root)) {
    const canvas = host.shadowRoot?.querySelector('svg')
    for (const job of changed.slice(0, 2)) {
      const line = lines.find(line => line.id === job.id)
      if (!canvas || !line) continue
      const dot = svg('circle', { r: 4, fill: 'var(--accent)', 'data-transfer': 'true' })
      const motion = svg('animateMotion', { path: line.path, dur: '900ms', repeatCount: 1, fill: 'freeze' })
      dot.append(motion); canvas.append(dot)
      motion.beginElement?.()
      setTimeout(() => dot.remove(), 1000)
    }
  }
}

function appViews(root, state) {
  const host = root.querySelector('[data-job-app-host]')
  if (!host) return
  // The stable, childless virtual-DOM host owns these warm app frames. Keep
  // them in the light DOM so browser accessibility and frame tooling can reach
  // the editor normally; only the decorative SVG wires use a shadow root.
  const apps = host
  if (!state.appStyle) {
    const style = document.createElement('style')
    style.textContent = '.job-app-host iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:var(--paper,#fff)}.job-app-host [hidden]{display:none!important}.job-app-host .app-message{position:absolute;inset:0;display:grid;align-content:center;justify-items:center;padding:24px;color:var(--ink-soft,#48546a);font:14px/1.6 system-ui;text-align:center}.job-app-host .app-message p{max-width:440px}'
    const message = document.createElement('div'); message.className = 'app-message'
    const heading = document.createElement('strong'), body = document.createElement('p')
    message.append(heading, body); apps.append(style, message)
    state.appStyle = style; state.appMessage = message
  }
  const job = host.dataset.job, url = jobAppURL(host.dataset.source, window.location.href)
  const visible = host.dataset.visible === 'true' && root.dataset.active === 'true'
  const identity = JSON.stringify([root.dataset.project, job, url])
  // Changing focus hides apps, never unmounts their unsaved editor state.
  for (const [key, frame] of state.frames) frame.hidden = !visible || key !== identity
  state.appMessage.hidden = !visible || (url && state.frames.has(identity))
  if (visible && job && !url) {
    const loading = host.dataset.readState === 'loading', unavailable = host.dataset.readState === 'unavailable'
    state.appMessage.children[0].textContent = loading ? '正在读取这项工作…' : unavailable ? '这项工作尚未载入' : host.dataset.source ? '此任务关联了外部来源' : '这项工作尚未关联可编辑材料'
    state.appMessage.children[1].textContent = loading ? '保留已经打开的编辑器。' : unavailable ? '请刷新工作状态，或进入“团队与交付”核对读取结果。' : host.dataset.source ? '用“独立打开”查看来源，或进入“团队与交付”。' : '可以先在“团队与交付”中确认任务、工作区与交付要求。'
  }
  if (visible && job && url && !state.frames.has(identity)) {
    const frame = document.createElement('iframe')
    frame.src = url; frame.title = `MoonDesk · ${host.dataset.title || job}`
    frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-forms allow-downloads allow-modals allow-popups')
    frame.dataset.jobApp = job
    state.frames.set(identity, frame); apps.append(frame)
    state.appMessage.hidden = true
  }
  const external = root.querySelector('[data-workspace-source-link]')
  if (external && url) external.href = url
  if (visible && job !== state.lastJob && !reduced(root)) {
    const pane = root.querySelector('.job-app-window')
    for (const animation of pane.getAnimations()) animation.cancel()
    const box = pane.getBoundingClientRect()
    const origin = launchRect ? `${Math.max(0, launchRect.x + launchRect.width / 2 - box.x)}px ${box.height}px` : '50% 100%'
    pane.animate([{ opacity: .35, transform: 'translateY(12px) scale(.96)', transformOrigin: origin }, { opacity: 1, transform: 'none', transformOrigin: origin }], { duration: 240, easing: 'cubic-bezier(.2,.8,.2,1)' })
  }
  if (visible) state.lastJob = job
  if (!job) state.lastJob = ''
  if (state.appVisible && !job && root.dataset.active === 'true' && !reduced(root)) {
    root.querySelector('.company-flow')?.animate([{ opacity: .45 }, { opacity: 1 }], { duration: 180, easing: 'ease-out' })
  }
  state.appVisible = visible
}

function enhance() {
  scheduled = false
  const root = document.querySelector('[data-company-workspace]')
  if (!root) return
  let state = sessions.get(root)
  if (!state) {
    state = { actor: root.dataset.actor, frames: new Map(), receipts: new Map(), wires: '', lastJob: '' }
    sessions.set(root, state)
    try { root.dataset.motion = localStorage.getItem('moonproj.workspace.motion') === 'paused' ? 'paused' : 'enabled' } catch { root.dataset.motion = 'enabled' }
    const observer = new ResizeObserver(schedule)
    observer.observe(root); state.observer = observer
    root.addEventListener('click', event => {
      if (event.target.closest('.workspace-tools button')) root.querySelector('.workspace-tools')?.removeAttribute('open')
      if (event.target.closest('[data-workspace-motion-toggle]')) {
        const paused = root.dataset.motion !== 'paused'
        root.dataset.motion = paused ? 'paused' : 'enabled'
        try { localStorage.setItem('moonproj.workspace.motion', root.dataset.motion) } catch { /* Session preference still works. */ }
        if (paused) {
          for (const animation of root.getAnimations({ subtree: true })) animation.cancel()
          for (const dot of root.querySelector('.flow-wires')?.shadowRoot?.querySelectorAll('[data-transfer]') || []) dot.remove()
        }
        schedule()
      }
    })
  }
  if (state.actor !== root.dataset.actor) {
    for (const frame of state.frames.values()) frame.remove()
    state.frames.clear(); state.receipts.clear(); state.actor = root.dataset.actor
  }
  const toggle = root.querySelector('[data-workspace-motion-toggle]'), paused = root.dataset.motion === 'paused'
  if (toggle) {
    toggle.setAttribute('aria-pressed', String(paused))
    toggle.setAttribute('aria-label', paused ? '启用动态效果' : '暂停动态效果')
    toggle.title = paused ? '动态效果已暂停' : '暂停动态效果'
  }
  if (reduced(root)) {
    for (const animation of root.getAnimations({ subtree: true })) animation.cancel()
    for (const dot of root.querySelector('.flow-wires')?.shadowRoot?.querySelectorAll('[data-transfer]') || []) dot.remove()
  }
  appViews(root, state)
  for (const node of root.querySelectorAll('[data-live-motion]')) node.removeAttribute('data-live-motion')
  if (!reduced(root)) for (const node of [...root.querySelectorAll('.flow-job[data-stage="running"]')].slice(0, 2)) node.dataset.liveMotion = 'true'
  if (root.dataset.active === 'true') drawWires(root, state)
  const board = root.querySelector('.flow-board')
  if (board && state.board !== board) { if (state.board) state.observer.unobserve(state.board); state.observer.observe(board); state.board = board }
}

function schedule() {
  if (scheduled) return
  scheduled = true; requestAnimationFrame(enhance)
}

export function installCompanyWorkspace() {
  schedule()
  new MutationObserver(schedule).observe(document.getElementById('app') || document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-job', 'data-source', 'data-visible', 'data-active', 'data-parent', 'data-stage', 'data-receipt', 'data-project', 'data-actor', 'data-read-state'] })
  document.addEventListener('click', event => {
    const target = event.target.closest?.('[data-dock-job],.flow-job')
    if (target) launchRect = target.getBoundingClientRect()
  }, true)
  window.addEventListener('resize', schedule)
  document.addEventListener('visibilitychange', schedule)
  window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', schedule)
}

if (typeof document !== 'undefined') installCompanyWorkspace()
