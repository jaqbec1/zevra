import { test, expect } from 'bun:test';
import { handler } from '../src/server';
import { Store } from '../src/store';
import type { Config } from '../src/config';
const config: Config = {
  token: 'test-token'.repeat(8),
  port: 3030,
  policy: {
    allowedDomains: ['example.com'],
    excludedDomains: [],
    excludedPrefixes: [],
  },
  jevEnabled: false,
  jevModel: 'jev-latest',
};
function event() {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    visit_id: crypto.randomUUID(),
    kind: 'visit',
    url: 'https://example.com/article',
    title: 'Article',
    started_at: now - 20_000,
    ts: now,
    active_ms: 20_000,
    max_scroll: 0.5,
  };
}
test('HTTP auth, origin and host boundaries reject untrusted writes', async () => {
  const s = new Store(),
    run = handler(s, config);
  for (const headers of [
    {},
    { Authorization: 'Bearer ' + config.token, Origin: 'https://evil.example' },
  ] as Record<string, string>[])
    expect(
      (await run(new Request('http://127.0.0.1/events', { method: 'POST', headers }))).status,
    ).toBe(headers.Authorization ? 403 : 401);
  expect((await run(new Request('http://evil.example/health'))).status).toBe(403);
  s.close();
});
test('real HTTP event delivery retries are idempotent and human verdict is stored', async () => {
  const s = new Store(),
    server = Bun.serve({
      hostname: '127.0.0.1',
      port: 0,
      fetch: handler(s, config),
    });
  try {
    const headers = {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + config.token,
    };
    const e = event();
    for (let n = 0; n < 2; n++)
      expect(
        (
          await fetch(new URL('/events', server.url), {
            method: 'POST',
            headers,
            body: JSON.stringify([e]),
          })
        ).status,
      ).toBe(200);
    expect(s.metrics(1).active_ms).toBe(20_000);
    expect(
      (
        await fetch(new URL('/verdict', server.url), {
          method: 'POST',
          headers,
          body: JSON.stringify({
            page_id: 1,
            bucket: 'utrwal',
            reason: 'Useful',
          }),
        })
      ).status,
    ).toBe(200);
    expect(s.verdict(1)?.source).toBe('human');
    expect(
      (
        await fetch(new URL('/events', server.url), {
          method: 'POST',
          headers,
          body: JSON.stringify([e, { bad: 1 }]),
        })
      ).status,
    ).toBe(400);
    expect(
      (
        await fetch(new URL('/events', server.url), {
          method: 'POST',
          headers,
          body: ' '.repeat(1_000_001),
        })
      ).status,
    ).toBe(413);
  } finally {
    server.stop(true);
    s.close();
  }
});

test('saved pages require auth, escape no data into HTML, and respect new exclusions', async () => {
  const s = new Store();
  try {
    s.ingest([event()], config.policy);
    const run = handler(s, config),
      url = 'http://127.0.0.1/pages';
    expect((await run(new Request(url))).status).toBe(401);
    const headers = { Authorization: 'Bearer ' + config.token };
    const response = await run(new Request(url, { headers }));
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.total).toBe(1);
    expect(body.pages[0].url_norm).toBe('https://example.com/article');
    expect(body.pages[0].excerpt).toBeUndefined();
    const excluded = handler(s, {
      ...config,
      policy: { ...config.policy, excludedDomains: ['example.com'] },
    });
    expect((await (await excluded(new Request(url, { headers }))).json()).total).toBe(0);
    expect(
      (await run(new Request(url, { headers: { ...headers, Origin: 'https://evil.example' } })))
        .status,
    ).toBe(403);
  } finally {
    s.close();
  }
});
