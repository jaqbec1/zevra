import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../src/store';
import { enrich } from '../src/enrich';
import { classify } from '../src/jev';
import { createDigest, localDay } from '../src/digest';
const directory = await mkdtemp(join(tmpdir(), 'attention-demo-')),
  store = new Store(join(directory, 'attention.db'));
const policy = {
    allowedDomains: ['example.com'],
    excludedDomains: [],
    excludedPrefixes: [],
  },
  now = Date.now();
for (let i = 0; i < 3; i++)
  store.ingest(
    [
      {
        id: crypto.randomUUID(),
        visit_id: crypto.randomUUID(),
        kind: 'copy',
        url: `https://example.com/reading-${i}`,
        title: [
          'Attention and deliberate reading',
          'Keeping a useful reading log',
          'Returning to unfinished ideas',
        ][i],
        started_at: now - 120_000,
        ts: now,
        active_ms: 120_000,
        max_scroll: 0.8,
        selection_length: 100,
      },
    ],
    policy,
  );
await enrich(
  store,
  policy,
  async () =>
    '<html lang="en"><body><article><h1>Thoughtful reading</h1>' +
    Array.from(
      { length: 10 },
      () => '<p>' + 'Reading deliberately helps connect ideas to decisions. '.repeat(10) + '</p>',
    ).join('') +
    '</article></body></html>',
);
await classify(store, { enabled: false, policy });
const result = await createDigest(store, localDay(), policy, join(directory, 'digests'));
console.log(await readFile(result.path, 'utf8'));
console.log(
  `Synthetic demo saved at ${directory}. No browser collection or provider requests were made.`,
);
store.close();
