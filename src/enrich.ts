import { Readability } from '@mozilla/readability';
import { parseHTML } from 'linkedom';
import { Store, type Page } from './store';
import { allowedUrl, type Policy } from './shared/policy';
import { fetchHtml, MAX_HTML } from './net';
export function extract(html: string) {
  if (Buffer.byteLength(html) > MAX_HTML) throw new Error('HTML too large');
  const { document } = parseHTML(html);
  const article = new Readability(document as unknown as Document).parse();
  if (!article?.textContent?.trim()) throw new Error('No readable content');
  const text = article.textContent.replace(/\s+/g, ' ').trim();
  return {
    excerpt: text.slice(0, 2000),
    word_count: text.split(/\s+/u).length,
    lang: document.documentElement.lang || null,
  };
}
export async function enrich(store: Store, policy: Policy, fetcher = fetchHtml, now = Date.now()) {
  const candidates = store.db
    .query<
      Page,
      [number]
    >(`SELECT p.* FROM pages p WHERE fetched_at IS NULL AND fetch_attempts<3 AND next_fetch_at<=? AND (SELECT COALESCE(SUM(active_ms),0) FROM visits WHERE page_id=p.id)>10000 ORDER BY first_seen LIMIT 20`)
    .all(now);
  let enriched = 0;
  for (const page of candidates) {
    if (!allowedUrl(page.url_norm, policy)) continue;
    try {
      const content = extract(await fetcher(page.url_norm, policy));
      if (!allowedUrl(page.url_norm, policy)) continue;
      store.db
        .query(
          "UPDATE pages SET excerpt=?,word_count=?,lang=?,fetched_at=?,fetch_status='ok',fetch_attempts=fetch_attempts+1 WHERE id=?",
        )
        .run(content.excerpt, content.word_count, content.lang, now, page.id);
      enriched++;
    } catch {
      store.db
        .query(
          "UPDATE pages SET fetch_status='failed',fetch_attempts=fetch_attempts+1,next_fetch_at=? WHERE id=?",
        )
        .run(now + 300_000 * 2 ** page.fetch_attempts, page.id);
    }
  }
  return { enriched };
}
