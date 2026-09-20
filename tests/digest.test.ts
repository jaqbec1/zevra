import { test, expect } from 'bun:test';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../src/store';
import { createDigest, dayRange, localDay, runAgent } from '../src/digest';
const policy = {
  allowedDomains: ['example.com'],
  excludedDomains: [],
  excludedPrefixes: [],
};
function setup(count = 8) {
  const s = new Store(),
    now = Date.now();
  for (let i = 0; i < count; i++) {
    s.ingest(
      [
        {
          id: crypto.randomUUID(),
          visit_id: crypto.randomUUID(),
          kind: 'visit',
          url: `https://example.com/${i}`,
          title: `Article ${i}`,
          started_at: now - 20000,
          ts: now,
          active_ms: 20000,
          max_scroll: 0.5,
        },
      ],
      policy,
    );
    s.setVerdict({
      page_id: i + 1,
      bucket: 'czytaj',
      source: 'heuristic',
      confidence: null,
      heur_score: i,
      needs_review: 0,
      reason: 'Useful',
      decided_at: now,
    });
  }
  return s;
}
test('fallback digest is capped, durable, and rerun is identical', async () => {
  const s = setup(),
    dir = await mkdtemp(join(tmpdir(), 'attention-test-'));
  try {
    const one = await createDigest(s, localDay(), policy, dir);
    const text = await readFile(one.path, 'utf8');
    expect(text.match(/^- \*\*/gm)?.length).toBe(6);
    expect(one.mode).toBe('local rules');
    const two = await createDigest(s, localDay(), policy, dir);
    expect(two.reused).toBe(true);
    expect(await readFile(two.path, 'utf8')).toBe(text);
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});
test('agent gets history and capped excerpts; only validated recurring decisions land', async () => {
  const s = setup(2),
    dir = await mkdtemp(join(tmpdir(), 'attention-test-'));
  s.db.query('UPDATE pages SET excerpt=?').run('x'.repeat(3000));
  try {
    let packet: any;
    const result = await createDigest(s, localDay(), policy, dir, ['test'], async (_command, p) => {
      packet = p;
      return {
        items: [
          {
            page_id: 2,
            bucket: 'doczytaj',
            reason: 'Topic recurs.',
            related_page_ids: [1],
          },
        ],
      };
    });
    expect(packet.candidates[0].excerpt.length).toBe(2000);
    expect(packet.candidates[0].url_norm).toBeUndefined();
    expect(packet.history.length).toBe(2);
    expect(result.mode).toBe('agent');
    expect(s.verdict(2)?.bucket).toBe('doczytaj');
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});
test('invalid agent output falls back without changing current verdict', async () => {
  const s = setup(1),
    dir = await mkdtemp(join(tmpdir(), 'attention-test-'));
  try {
    const result = await createDigest(s, localDay(), policy, dir, ['test'], async () => ({
      items: [
        {
          page_id: 1,
          bucket: 'doczytaj',
          reason: 'Unsupported',
          related_page_ids: [],
        },
      ],
    }));
    expect(result.mode).toContain('fallback');
    expect(s.verdict(1)?.source).toBe('heuristic');
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});
test('empty day creates honest empty digest', async () => {
  const s = setup(0),
    dir = await mkdtemp(join(tmpdir(), 'attention-test-'));
  try {
    const result = await createDigest(s, localDay(), policy, dir);
    expect(await readFile(result.path, 'utf8')).toContain('No eligible pages');
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});
test('date validation and midnight boundaries', () => {
  expect(() => dayRange('2026-02-30')).toThrow();
  expect(() => dayRange('../secret')).toThrow();
  const range = dayRange('2026-09-19');
  expect(new Date(range.since).getHours()).toBe(0);
  expect(new Date(range.until).getDate()).toBe(20);
});
test('runner handles a real subprocess and timeout', async () => {
  expect(
    await runAgent([process.execPath, '-e', 'console.log(JSON.stringify({items:[]}))'], {}, 2000),
  ).toEqual({ items: [] });
  await expect(
    runAgent([process.execPath, '-e', 'setInterval(()=>{},1000)'], {}, 50),
  ).rejects.toThrow();
});

test('rerun includes new and updated pages, then skips unchanged data', async () => {
  const s = setup(1),
    dir = await mkdtemp(join(tmpdir(), 'attention-incremental-'));
  try {
    const first = await createDigest(s, localDay(), policy, dir);
    const now = Date.now();
    s.ingest(
      [
        {
          id: crypto.randomUUID(),
          visit_id: crypto.randomUUID(),
          kind: 'visit',
          url: 'https://example.com/new',
          title: 'New after first run',
          started_at: now - 1000,
          ts: now,
          active_ms: 1000,
          max_scroll: 0.2,
        },
      ],
      policy,
    );
    s.setVerdict({
      page_id: 2,
      bucket: 'czytaj',
      source: 'heuristic',
      confidence: null,
      heur_score: 2,
      reason: 'New evidence',
      needs_review: 0,
      decided_at: now,
    });
    const second = await createDigest(s, localDay(), policy, dir);
    expect(second.reused).toBe(false);
    expect(await readFile(second.path, 'utf8')).toContain('New after first run');
    expect(await readFile(second.path, 'utf8')).toContain('Article 0');
    expect((await createDigest(s, localDay(), policy, dir)).reused).toBe(true);
    s.setVerdict({
      page_id: 2,
      bucket: 'utrwal',
      source: 'human',
      confidence: null,
      heur_score: 2,
      reason: 'Changed decision',
      needs_review: 0,
      decided_at: now + 1,
    });
    expect((await createDigest(s, localDay(), policy, dir)).reused).toBe(false);
    expect(await readFile(first.path, 'utf8')).toContain('Changed decision');
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});

test('updated active visit is new evidence and more than 500 pages are not stranded', async () => {
  const s = setup(505),
    dir = await mkdtemp(join(tmpdir(), 'attention-many-'));
  try {
    for (let i = 0; i < 13; i++) await createDigest(s, localDay(), policy, dir);
    expect(s.db.query<{ n: number }, []>('SELECT count(*) n FROM digest_seen').get()?.n).toBe(505);
    expect((await createDigest(s, localDay(), policy, dir)).reused).toBe(true);
    s.db.query('UPDATE visits SET active_ms=active_ms+1000 WHERE page_id=1').run();
    const next = await createDigest(s, localDay(), policy, dir);
    expect(next.reused).toBe(false);
    expect(next.changed).toBe(1);
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});

test('a failed output write can recover without consuming later evidence', async () => {
  const s = setup(1),
    dir = await mkdtemp(join(tmpdir(), 'attention-write-'));
  try {
    await Bun.write(join(dir, 'blocked'), 'not a directory');
    await expect(createDigest(s, localDay(), policy, join(dir, 'blocked'))).rejects.toThrow();
    const recovered = await createDigest(s, localDay(), policy, dir);
    expect(recovered.reused).toBe(true);
    expect(await readFile(recovered.path, 'utf8')).toContain('Article 0');
  } finally {
    s.close();
    await rm(dir, { recursive: true });
  }
});
