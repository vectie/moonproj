import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { jobAppURL, newDeliveryReceipts } from './company_workspace.js'

test('desktop opens in an ordinary resizable window, not a screen-sized surface', () => {
  const { window } = JSON.parse(readFileSync(new URL('../../lepusa.json', import.meta.url), 'utf8'))
  assert.equal(window.titleBar, 'native')
  assert.equal(window.resizable, true)
  assert.equal(window.width, 1040)
  assert.equal(window.height, 680)
  assert.notEqual(window.fullscreen, true)
  assert.notEqual(window.maximized, true)
})

test('job apps keep exact Book/path and follow the local shell hostname', () => {
  const reference = 'http://127.0.0.1:4201/?activity=wiki&workspace=book-research&path=wiki%2Fproposal.md'
  const url = new URL(jobAppURL(reference, 'http://localhost:4283/?page=workspace&task=T'))
  assert.equal(url.origin, 'http://localhost:4201')
  assert.equal(url.searchParams.get('workspace'), 'book-research')
  assert.equal(url.searchParams.get('path'), 'wiki/proposal.md')
  for (const value of ['javascript:alert(1)', 'https://example.com/?workspace=book-a&path=x&activity=wiki', 'http://127.0.0.1:4201/', 'http://user:secret@127.0.0.1:4201/?workspace=book-a&path=x&activity=wiki', 'http://127.0.0.1:8888/?workspace=book-a&path=x&activity=wiki']) assert.equal(jobAppURL(value, 'http://localhost:4283'), '')
})

test('animated transfers require a newly observed exact contribution receipt', () => {
  const next = [{ id: 'A', parent: 'G', receipt: 'R1' }]
  assert.deepEqual(newDeliveryReceipts(new Map(), next), [])
  assert.deepEqual(newDeliveryReceipts(new Map([['A', '']]), next), next)
  assert.deepEqual(newDeliveryReceipts(new Map([['A', 'R1']]), next), [])
  assert.deepEqual(newDeliveryReceipts(new Map([['A', '']]), [{ id: 'A', parent: '', receipt: 'R1' }]), [])
})

test('reduced motion and manual pause retain readable static relationships', () => {
  const css = readFileSync(new URL('./company_workspace.css', import.meta.url), 'utf8')
  assert.match(css, /prefers-reduced-motion: reduce/)
  assert.match(css, /data-motion="paused"/)
  assert.match(css, /grid-template-rows: 48px minmax\(0,1fr\) 100px/)
})
