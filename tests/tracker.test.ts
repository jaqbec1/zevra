import { test, expect } from 'bun:test';
import { transition, emptyState } from '../extension/tracker';
const policy = {
  allowedDomains: ['example.com'],
  excludedDomains: [],
  excludedPrefixes: [],
};
const tab = { id: 1, url: 'https://example.com/a', title: 'Article' };
test('worker restart preserves visit; focus blur stops time', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  s = transition(JSON.parse(JSON.stringify(s)), { type: 'tick' }, policy, 21000);
  expect(s.active?.active_ms).toBe(20000);
  s = transition(s, { type: 'focus', tab: null, reason: 'blur' }, policy, 31000);
  s = transition(s, { type: 'tick' }, policy, 61000);
  expect(s.active).toBeNull();
  expect(Math.max(...s.queue.map((e) => e.active_ms))).toBe(30000);
});
test('navigation creates a new visit; background updates keep current visit', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  const id = s.active?.visit_id;
  s = transition(s, { type: 'focus', tab }, policy, 2000);
  expect(s.active?.visit_id).toBe(id);
  s = transition(
    s,
    {
      type: 'focus',
      tab: { ...tab, url: 'https://example.com/b' },
      reason: 'navigate',
    },
    policy,
    3000,
  );
  expect(s.active?.visit_id).not.toBe(id);
  expect(s.queue.find((e) => e.end_reason === 'navigate')?.active_ms).toBe(2000);
});
test('long sleep and backwards clock do not inflate attention', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  s = transition(s, { type: 'focus', tab }, policy, 3_601_000);
  expect(s.active?.active_ms).toBe(0);
  expect(s.queue.every((e) => e.active_ms === 0)).toBe(true);
});
test('policy change purges queued data and private visits never start', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  s = transition(s, { type: 'tick' }, { ...policy, allowedDomains: [] }, 2000);
  expect(s.queue).toHaveLength(0);
  expect(s.active).toBeNull();
  s = transition(
    s,
    { type: 'focus', tab: { ...tab, url: 'https://example.com?token=x' } },
    policy,
    3000,
  );
  expect(s.active).toBeNull();
});
test('gestures belong only to the active visit and scroll is cumulative', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  s = transition(s, { type: 'signal', tabId: 2, kind: 'copy', length: 100 }, policy, 2000);
  s = transition(s, { type: 'signal', tabId: 1, kind: 'select', length: 20 }, policy, 3000);
  s = transition(s, { type: 'signal', tabId: 1, kind: 'scroll', scroll: 0.9 }, policy, 4000);
  s = transition(s, { type: 'signal', tabId: 1, kind: 'copy', length: 100 }, policy, 5000);
  expect(s.queue.filter((e) => e.kind === 'copy')).toHaveLength(1);
  expect(s.queue.filter((e) => e.kind === 'select')).toHaveLength(0);
  expect(s.queue.at(-1)?.max_scroll).toBe(0.9);
});
test('overflow preserves queued evidence and visibly stops capture', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  s.queue = Array.from({ length: 4000 }, () => ({
    ...s.queue[0],
    id: crypto.randomUUID(),
  }));
  s = transition(s, { type: 'tick' }, policy, 2000);
  expect(s.queue.length).toBe(4000);
  expect(s.error).toContain('Queue full');
  expect(s.active).toBeNull();
});

test('backwards wall clock does not count the same interval twice', () => {
  let s = transition(emptyState(), { type: 'focus', tab }, policy, 10_000);
  s = transition(s, { type: 'tick' }, policy, 20_000);
  s = transition(s, { type: 'tick' }, policy, 15_000);
  s = transition(s, { type: 'tick' }, policy, 25_000);
  expect(s.active?.active_ms).toBe(15_000);
});

test('a delayed gesture cannot attach to a different URL in the same tab', () => {
  const s = transition(emptyState(), { type: 'focus', tab }, policy, 1000);
  const next = transition(
    s,
    { type: 'signal', tabId: tab.id, url: 'https://example.com/other', kind: 'copy', length: 100 },
    policy,
    2000,
  );
  expect(next.queue.some((e) => e.kind === 'copy')).toBe(false);
});
