import { timingSafeEqual } from 'node:crypto';
import { Store } from './store';
import { policySchema, type Config } from './config';
import { verdictSchema } from './shared/contracts';
import { allowedUrl } from './shared/policy';
import { heuristic } from './scoring';

export function handler(
  store: Store,
  config: Config,
  persistPolicy?: (policy: Config['policy']) => void,
) {
  return async (request: Request): Promise<Response> => {
    const url = new URL(request.url),
      origin = request.headers.get('origin');
    const extensionOrigin = origin !== null && /^chrome-extension:\/\/[a-p]{32}$/.test(origin);
    const headers: Record<string, string> = extensionOrigin
      ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' }
      : {};
    const json = (body: unknown, status = 200) =>
      Response.json(body, { status, headers: { ...headers, 'Cache-Control': 'no-store' } });
    if (!['127.0.0.1', 'localhost'].includes(url.hostname))
      return json({ error: 'Invalid host' }, 403);
    if (origin && !extensionOrigin) return json({ error: 'Origin rejected' }, 403);
    if (request.method === 'OPTIONS')
      return new Response(null, {
        status: 204,
        headers: {
          ...headers,
          'Access-Control-Allow-Methods': 'GET, POST',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        },
      });
    if (url.pathname === '/health' && request.method === 'GET') return json({ ok: true });
    const supplied = Buffer.from(request.headers.get('authorization') ?? ''),
      expected = Buffer.from('Bearer ' + config.token);
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected))
      return json({ error: 'Unauthorized' }, 401);
    if (request.method === 'GET' && url.pathname === '/pages') {
      const search = (url.searchParams.get('q') ?? '').slice(0, 200).toLowerCase();
      const rawOffset = Number(url.searchParams.get('offset') ?? 0);
      const offset = Number.isSafeInteger(rawOffset) && rawOffset >= 0 ? rawOffset : 0;
      const rows = store.db
        .query<
          {
            id: number;
            url_norm: string;
            title: string;
            domain: string;
            last_seen: number;
            fetch_status: string;
          },
          []
        >(
          'SELECT id,url_norm,title,domain,last_seen,fetch_status FROM pages ORDER BY last_seen DESC,id DESC',
        )
        .all()
        .filter(
          (p) =>
            allowedUrl(p.url_norm, config.policy) &&
            (!search || (p.title + ' ' + p.url_norm).toLowerCase().includes(search)),
        );
      return json({
        total: rows.length,
        offset,
        pages: rows
          .slice(offset, offset + 50)
          .map((p) => ({ ...p, ...store.metrics(p.id), verdict: store.verdict(p.id) })),
      });
    }
    if (request.method !== 'POST') return json({ error: 'Not found' }, 404);
    if (!request.headers.get('content-type')?.startsWith('application/json'))
      return json({ error: 'JSON required' }, 415);
    try {
      const reader = request.body?.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      if (reader)
        while (true) {
          const next = await reader.read();
          if (next.done) break;
          size += next.value.length;
          if (size > 1_000_000) {
            await reader.cancel();
            return json({ error: 'Batch too large' }, 413);
          }
          chunks.push(next.value);
        }
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (url.pathname === '/policy') {
        const policy = policySchema.parse(body);
        if (!persistPolicy) return json({ error: 'Policy updates unavailable' }, 503);
        try {
          persistPolicy(policy);
        } catch {
          return json({ error: 'Could not save policy; retry' }, 503);
        }
        // Keep the same object so in-flight background work sees new exclusions too.
        Object.assign(config.policy, { mode: undefined, excludedKeywords: undefined }, policy);
        return json({ ok: true });
      }
      if (url.pathname === '/events') return json(store.ingest(body, config.policy));
      if (url.pathname === '/verdict') {
        const v = verdictSchema.parse(body),
          page = store.page(v.page_id);
        if (!page || !allowedUrl(page.url_norm, config.policy))
          return json({ error: 'Page not found' }, 404);
        store.setVerdict({
          ...v,
          source: 'human',
          confidence: null,
          heur_score: heuristic(page, store.metrics(page.id)).score,
          needs_review: 0,
          decided_at: Date.now(),
        });
        return json({ ok: true });
      }
      return json({ error: 'Not found' }, 404);
    } catch {
      return json({ error: 'Invalid request or conflicting visit identity' }, 400);
    }
  };
}
