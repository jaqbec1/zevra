import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { join } from 'node:path';
import { Store } from './store';
import { readConfig, dataDirectory } from './config';
import { allowedUrl, type Policy } from './shared/policy';
import { bucketSchema } from './shared/contracts';
import { heuristic } from './scoring';
const content = (value: unknown) => ({
  content: [{ type: 'text' as const, text: JSON.stringify(value) }],
});
export function makeMcp(store: Store, policy: Policy) {
  const server = new McpServer({ name: 'attention-log', version: '0.1.0' });
  server.registerTool(
    'query_visits',
    {
      description:
        'Summaries of recently visited public pages, without excerpts. Times are Unix milliseconds; until is exclusive. Metrics cover visits beginning in the window, verdict score is current lifetime score.',
      inputSchema: {
        since: z.number().int().nonnegative().optional(),
        until: z.number().int().nonnegative().optional(),
        min_score: z.number().nonnegative().optional(),
        bucket: bucketSchema.optional(),
        domain: z.string().max(253).optional(),
        limit: z.number().int().min(1).max(100).default(25),
      },
    },
    async (q) =>
      content(
        store
          .query({ ...q, limit: 500 })
          .filter((p) => allowedUrl(p.url_norm, policy))
          .slice(0, q.limit),
      ),
  );
  server.registerTool(
    'get_page',
    {
      description:
        'Get a page excerpt, current verdict, and bounded visit/signal history. Provide page_id or URL.',
      inputSchema: {
        page_id: z.number().int().positive().optional(),
        url: z.string().url().optional(),
      },
    },
    async (q) => {
      const page = q.page_id ? store.page(q.page_id) : q.url ? store.pageByUrl(q.url) : null;
      return page && allowedUrl(page.url_norm, policy)
        ? content(store.details(page.id))
        : { ...content({ error: 'Page not found' }), isError: true };
    },
  );
  server.registerTool(
    'set_verdict',
    {
      description: 'Record an agent verdict; human corrections always win.',
      inputSchema: {
        page_id: z.number().int().positive(),
        bucket: bucketSchema,
        reason: z.string().min(1).max(500),
      },
    },
    async (q) => {
      const page = store.page(q.page_id);
      if (!page || !allowedUrl(page.url_norm, policy))
        return { ...content({ error: 'Page not found' }), isError: true };
      const applied = store.setVerdict({
        ...q,
        source: 'agent',
        confidence: null,
        heur_score: heuristic(page, store.metrics(page.id)).score,
        needs_review: 0,
        decided_at: Date.now(),
      });
      return content({ applied, verdict: store.verdict(page.id) });
    },
  );
  return server;
}
if (import.meta.main) {
  process.umask(0o077);
  const config = readConfig(),
    store = new Store(join(dataDirectory(), 'attention.db'));
  await makeMcp(store, config.policy).connect(new StdioServerTransport());
}
