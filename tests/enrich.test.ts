import { test, expect } from 'bun:test';
import { extract, enrich } from '../src/enrich';
import { fetchHtml, resolvePublic } from '../src/net';
import { Store } from '../src/store';
const policy = {
  allowedDomains: ['example.com', '127.0.0.1'],
  excludedDomains: [],
  excludedPrefixes: [],
};
export const article =
  '<html lang="en"><head><title>Reading</title></head><body><article><h1>Reading</h1>' +
  Array.from(
    { length: 12 },
    () =>
      '<p>' +
      'Substantive public reading material about attention and thoughtful decisions. '.repeat(12) +
      '</p>',
  ).join('') +
  '</article></body></html>';
test('Readability extracts a bounded excerpt and full word count', () => {
  const x = extract(article);
  expect(x.excerpt.length).toBe(2000);
  expect(x.word_count).toBeGreaterThan(150);
  expect(x.lang).toBe('en');
  expect(() => extract('<html><body></body></html>')).toThrow();
});
test('private-network URLs and DNS answers are rejected', async () => {
  await expect(fetchHtml('http://127.0.0.1/', policy)).rejects.toThrow();
  await expect(resolvePublic('localhost')).rejects.toThrow();
});
test('dwell threshold, extraction and retry state use real SQLite', async () => {
  const s = new Store(),
    now = Date.now();
  for (let i = 1; i <= 3; i++)
    s.ingest(
      [
        {
          id: crypto.randomUUID(),
          visit_id: crypto.randomUUID(),
          kind: 'visit',
          url: `https://example.com/${i}`,
          title: 'Article',
          started_at: now - 20_000,
          ts: now,
          active_ms: i === 1 ? 10000 : 20000,
          max_scroll: 0.5,
        },
      ],
      policy,
    );
  const result = await enrich(
    s,
    policy,
    async (url) => {
      if (url.endsWith('/3')) throw new Error('offline');
      return article;
    },
    now,
  );
  expect(result.enriched).toBe(1);
  expect(s.page(1)?.fetched_at).toBeNull();
  expect(s.page(2)?.word_count).toBeGreaterThan(150);
  expect(s.page(3)?.fetch_status).toBe('failed');
  expect(s.page(3)?.next_fetch_at).toBeGreaterThan(now);
  s.close();
});
