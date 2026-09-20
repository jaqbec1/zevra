import { test, expect } from 'bun:test';
import { Store } from '../src/store';
import { classify } from '../src/jev';
const policy = {
  allowedDomains: ['example.com'],
  excludedDomains: [],
  excludedPrefixes: [],
};
function setup() {
  const s = new Store(),
    now = Date.now();
  s.ingest(
    [
      {
        id: crypto.randomUUID(),
        visit_id: crypto.randomUUID(),
        kind: 'visit',
        url: 'https://example.com/a',
        title: 'Article',
        started_at: now - 20_000,
        ts: now,
        active_ms: 20_000,
        max_scroll: 0.1,
      },
    ],
    policy,
  );
  s.db
    .query("UPDATE pages SET excerpt=?,word_count=500,fetched_at=?,fetch_status='ok'")
    .run('x'.repeat(2500), now);
  return s;
}
test('a new exclusion during classification prevents storing its result', async () => {
  const s = setup();
  const livePolicy = { ...policy, excludedDomains: [] as string[] };
  try {
    await classify(s, { enabled: true, apiKey: 'test', policy: livePolicy }, async () => {
      livePolicy.excludedDomains = ['example.com'];
      return new Response('', { status: 429 });
    });
    expect(s.verdict(1)).toBeNull();
    expect(s.db.query('SELECT COUNT(*) AS n FROM classifications').get()).toEqual({ n: 0 });
  } finally {
    s.close();
  }
});
test('Jev uses Choice API with capped state and escalates uncertainty without a score gate', async () => {
  const s = setup();
  let body: any;
  const mock = async (_url: any, options: any) => {
    body = JSON.parse(options.body);
    return Response.json({
      answers: {
        bucket: {
          type: 'choice',
          choice: 'czytaj',
          confidence: 0.4,
          probabilities: { czytaj: 0.5, utrwal: 0.2, zapomnij: 0.3 },
        },
      },
    });
  };
  await classify(s, { enabled: true, apiKey: 'test', policy }, mock);
  expect(body.questions.bucket.type).toBe('choice');
  expect(body.state.excerpt.length).toBe(2000);
  expect(body.state.url).toBeUndefined();
  expect(s.verdict(1)?.bucket).toBeNull();
  expect(s.verdict(1)?.needs_review).toBe(1);
  s.close();
});
test('errors use heuristic and wait before retry', async () => {
  const s = setup();
  let calls = 0;
  const mock = async () => {
    calls++;
    return new Response('', { status: 429 });
  };
  const config = { enabled: true, apiKey: 'test', policy };
  await classify(s, config, mock);
  await classify(s, config, mock);
  expect(calls).toBe(1);
  expect(s.verdict(1)?.source).toBe('heuristic');
  s.close();
});
test('disabled classifier and short articles do not send data', async () => {
  const s = setup();
  let calls = 0;
  const mock = async () => {
    calls++;
    throw new Error();
  };
  await classify(s, { enabled: false, policy }, mock);
  s.db.query('UPDATE pages SET word_count=100').run();
  await classify(s, { enabled: true, apiKey: 'test', policy }, mock);
  expect(calls).toBe(0);
  expect(s.verdict(1)?.bucket).toBe('zapomnij');
  s.close();
});
test('malformed typed answer falls back', async () => {
  const s = setup();
  await classify(s, { enabled: true, apiKey: 'test', policy }, async () =>
    Response.json({
      answers: { bucket: { choice: 'invented', confidence: 1 } },
    }),
  );
  expect(s.verdict(1)?.source).toBe('heuristic');
  s.close();
});
