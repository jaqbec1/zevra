import { test, expect } from 'bun:test';
import { Store, DAY } from '../src/store';
export const policy = {
  allowedDomains: ['example.com'],
  excludedDomains: [],
  excludedPrefixes: [],
};
export function event(overrides: Record<string, unknown> = {}) {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    visit_id: crypto.randomUUID(),
    kind: 'visit',
    url: 'https://example.com/a',
    title: 'Example',
    started_at: now - 20_000,
    ts: now,
    active_ms: 20_000,
    max_scroll: 0.5,
    ...overrides,
  };
}
test('duplicates and reordering never inflate active time', () => {
  const s = new Store();
  const e = event();
  s.ingest([e], policy);
  s.ingest([e], policy);
  s.ingest([{ ...e, id: crypto.randomUUID(), active_ms: 10_000, ts: e.ts - 5000 }], policy);
  expect(s.metrics(1).active_ms).toBe(20_000);
  s.close();
});
test('excluded URL is never persisted and invalid batch rolls back', () => {
  const s = new Store();
  expect(s.ingest([event({ url: 'https://example.com?token=secret' })], policy).excluded).toBe(1);
  expect(s.query()).toHaveLength(0);
  const e = event();
  expect(() =>
    s.ingest([e, { ...e, id: crypto.randomUUID(), url: 'https://example.com/b' }], policy),
  ).toThrow();
  expect(s.query()).toHaveLength(0);
  s.close();
});
test('human corrections survive and retain machine evidence', () => {
  const s = new Store();
  s.ingest([event()], policy);
  const v = {
    page_id: 1,
    bucket: 'utrwal' as const,
    source: 'human' as const,
    confidence: null,
    heur_score: 2,
    reason: 'keep',
    needs_review: 0,
    decided_at: Date.now(),
  };
  s.setVerdict(v);
  expect(s.setVerdict({ ...v, source: 'jev', bucket: 'zapomnij', heur_score: 4 })).toBe(false);
  expect(s.verdict(1)?.bucket).toBe('utrwal');
  expect(s.history(0, Date.now() + 1)).toHaveLength(2);
  s.prune(Date.now() + 91 * DAY);
  expect(s.page(1)).not.toBeNull();
  expect(s.metrics(1).active_ms).toBe(0);
  s.close();
});
