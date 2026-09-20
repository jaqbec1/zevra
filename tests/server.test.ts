import { test, expect } from 'bun:test';
import { handler } from '../src/server';
import { Store } from '../src/store';
import { savePolicy, type Config } from '../src/config';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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
test('saving policy applies to the running collector without restart and survives restart', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'zevra-policy-'));
  const file = join(directory, 'config.json');
  const live = structuredClone(config);
  writeFileSync(file, JSON.stringify(live));
  const s = new Store();
  const run = handler(s, live, (policy) => savePolicy(policy, file));
  const headers = { Authorization: 'Bearer ' + config.token, 'Content-Type': 'application/json' };
  const save = (body: unknown, extra = headers) =>
    run(
      new Request('http://127.0.0.1/policy', {
        method: 'POST',
        headers: extra,
        body: JSON.stringify(body),
      }),
    );
  try {
    s.ingest([event()], live.policy);
    const policy = { ...live.policy, excludedDomains: ['example.com'] };
    expect((await save(policy, { ...headers, Authorization: '' })).status).toBe(401);
    expect((await save({ ...policy, token: 'cannot-change-token' })).status).toBe(400);
    expect((await save(policy)).status).toBe(200);
    expect(live.policy).toEqual(policy);
    const pages = await run(new Request('http://127.0.0.1/pages', { headers }));
    expect((await pages.json()).total).toBe(0);
    await run(
      new Request('http://127.0.0.1/events', {
        method: 'POST',
        headers,
        body: JSON.stringify([event()]),
      }),
    );
    expect(s.metrics(1).active_ms).toBe(20_000);
    expect(JSON.parse(readFileSync(file, 'utf8'))).toEqual({ ...config, policy });
    const unavailable = handler(s, live, () => {
      throw new Error('disk full');
    });
    expect(
      (
        await unavailable(
          new Request('http://127.0.0.1/policy', {
            method: 'POST',
            headers,
            body: JSON.stringify(config.policy),
          }),
        )
      ).status,
    ).toBe(503);
    expect(live.policy.excludedDomains).toEqual(['example.com']);
    const restarted = handler(s, JSON.parse(readFileSync(file, 'utf8')));
    expect(
      (await (await restarted(new Request('http://127.0.0.1/pages', { headers }))).json()).total,
    ).toBe(0);
  } finally {
    s.close();
    rmSync(directory, { recursive: true });
  }
});
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
