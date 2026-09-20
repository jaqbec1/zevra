import { test, expect } from 'bun:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Store } from '../src/store';
test('real stdio handshake exposes bounded summaries/details and protects human verdicts', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attention-mcp-'));
  const policy = {
    allowedDomains: ['example.com'],
    excludedDomains: [],
    excludedPrefixes: [],
  };
  await writeFile(join(dir, 'config.json'), JSON.stringify({ token: 'x'.repeat(64), policy }));
  const s = new Store(join(dir, 'attention.db'));
  const now = Date.now();
  s.ingest(
    [
      {
        id: crypto.randomUUID(),
        visit_id: crypto.randomUUID(),
        kind: 'visit',
        url: 'https://example.com/a',
        title: 'Article',
        started_at: now - 20000,
        ts: now,
        active_ms: 20000,
        max_scroll: 0.8,
      },
    ],
    policy,
  );
  s.db.query('UPDATE pages SET excerpt=?').run('Public excerpt');
  s.setVerdict({
    page_id: 1,
    bucket: 'utrwal',
    source: 'human',
    confidence: null,
    heur_score: 3,
    reason: 'Keep',
    needs_review: 0,
    decided_at: now,
  });
  const client = new Client({ name: 'test', version: '1.0.0' }),
    transport = new StdioClientTransport({
      command: process.execPath,
      args: [resolve('src/mcp.ts')],
      env: { ATTENTION_HOME: dir, PATH: process.env.PATH ?? '' },
      stderr: 'pipe',
    });
  const payload = (result: any) => JSON.parse(result.content[0].text);
  try {
    await client.connect(transport);
    expect((await client.listTools()).tools.map((t) => t.name)).toEqual([
      'query_visits',
      'get_page',
      'set_verdict',
    ]);
    const summaries = payload(await client.callTool({ name: 'query_visits', arguments: {} }));
    expect(summaries).toHaveLength(1);
    expect(summaries[0].excerpt).toBeUndefined();
    expect(
      payload(await client.callTool({ name: 'get_page', arguments: { page_id: 1 } })).excerpt,
    ).toBe('Public excerpt');
    expect(
      payload(
        await client.callTool({
          name: 'set_verdict',
          arguments: {
            page_id: 1,
            bucket: 'zapomnij',
            reason: 'Agent opinion',
          },
        }),
      ).applied,
    ).toBe(false);
    expect(s.verdict(1)?.bucket).toBe('utrwal');
    expect((await client.callTool({ name: 'get_page', arguments: { page_id: 999 } })).isError).toBe(
      true,
    );
  } finally {
    await client.close();
    s.close();
    await rm(dir, { recursive: true });
  }
});
