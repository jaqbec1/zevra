import { Database } from 'bun:sqlite';
import { allowedUrl, normalizeUrl, type Policy } from './shared/policy';
import { batchSchema, type Bucket, type Source } from './shared/contracts';

export type Page = {
  id: number;
  url_norm: string;
  domain: string;
  title: string;
  excerpt: string | null;
  word_count: number | null;
  lang: string | null;
  first_seen: number;
  last_seen: number;
  fetched_at: number | null;
  fetch_status: string;
  fetch_attempts: number;
  next_fetch_at: number;
};
export type Metrics = {
  active_ms: number;
  max_scroll: number;
  returns: number;
  signals: { kind: string; count: number }[];
};
export type Verdict = {
  page_id: number;
  bucket: Bucket | null;
  source: Source;
  confidence: number | null;
  heur_score: number;
  reason: string;
  needs_review: number;
  decided_at: number;
};
export type Summary = Omit<Page, 'excerpt'> & Metrics & { verdict: Verdict | null };
export type Query = {
  since?: number;
  until?: number;
  min_score?: number;
  bucket?: Bucket;
  domain?: string;
  limit?: number;
};
const priority: Record<Source, number> = {
  heuristic: 0,
  jev: 1,
  agent: 2,
  human: 3,
};
export const DAY = 86_400_000;

export class Store {
  db: Database;
  constructor(path = ':memory:') {
    this.db = new Database(path, { create: true });
    this.db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS pages (
        id INTEGER PRIMARY KEY, url_norm TEXT UNIQUE NOT NULL, domain TEXT NOT NULL, title TEXT NOT NULL,
        excerpt TEXT, word_count INTEGER, lang TEXT, first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
        fetched_at INTEGER, fetch_status TEXT NOT NULL DEFAULT 'pending', fetch_attempts INTEGER NOT NULL DEFAULT 0, next_fetch_at INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS visits (
        id TEXT PRIMARY KEY, page_id INTEGER NOT NULL REFERENCES pages(id), started_at INTEGER NOT NULL,
        last_event_at INTEGER NOT NULL, active_ms INTEGER NOT NULL DEFAULT 0, max_scroll REAL NOT NULL DEFAULT 0, end_reason TEXT);
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, ts INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS signals (id TEXT PRIMARY KEY, visit_id TEXT NOT NULL REFERENCES visits(id) ON DELETE CASCADE, kind TEXT NOT NULL, ts INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS verdicts (page_id INTEGER PRIMARY KEY REFERENCES pages(id), bucket TEXT, source TEXT NOT NULL,
        confidence REAL, heur_score REAL NOT NULL, reason TEXT NOT NULL, needs_review INTEGER NOT NULL, decided_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS verdict_history (id INTEGER PRIMARY KEY, page_id INTEGER NOT NULL REFERENCES pages(id), bucket TEXT, source TEXT NOT NULL,
        confidence REAL, heur_score REAL NOT NULL, reason TEXT NOT NULL, needs_review INTEGER NOT NULL, decided_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS classifications (page_id INTEGER PRIMARY KEY REFERENCES pages(id), fingerprint TEXT NOT NULL, attempted_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS digests (day TEXT PRIMARY KEY, created_at INTEGER NOT NULL, mode TEXT NOT NULL, items TEXT NOT NULL, markdown TEXT NOT NULL, useful INTEGER);
      CREATE TABLE IF NOT EXISTS digest_seen (page_id INTEGER PRIMARY KEY REFERENCES pages(id), fingerprint TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS visits_page ON visits(page_id, started_at);
      CREATE INDEX IF NOT EXISTS visits_time ON visits(started_at);
      CREATE INDEX IF NOT EXISTS history_time ON verdict_history(decided_at);
      CREATE INDEX IF NOT EXISTS pages_domain ON pages(domain);
      PRAGMA user_version=1;`);
  }
  close() {
    this.db.close();
  }
  page(id: number) {
    return this.db.query<Page, [number]>('SELECT * FROM pages WHERE id=?').get(id);
  }
  pageByUrl(url: string) {
    return this.db
      .query<Page, [string]>('SELECT * FROM pages WHERE url_norm=?')
      .get(normalizeUrl(url));
  }
  ingest(input: unknown, policy: Policy, now = Date.now()) {
    const events = batchSchema.parse(input);
    if (events.some((e) => e.ts > now + 60_000 || e.started_at < now - 90 * DAY))
      throw new Error('Event outside retention window');
    return this.db.transaction(() => {
      const result = { accepted: 0, duplicate: 0, excluded: 0 };
      for (const e of events) {
        if (!allowedUrl(e.url, policy)) {
          result.excluded++;
          continue;
        }
        if (this.db.query('SELECT 1 FROM events WHERE id=?').get(e.id)) {
          result.duplicate++;
          continue;
        }
        const url = normalizeUrl(e.url);
        this.db
          .query(
            `INSERT INTO pages(url_norm,domain,title,first_seen,last_seen) VALUES(?,?,?,?,?)
          ON CONFLICT(url_norm) DO UPDATE SET last_seen=MAX(last_seen,excluded.last_seen),first_seen=MIN(first_seen,excluded.first_seen),
          title=CASE WHEN excluded.last_seen >= last_seen AND excluded.title != '' THEN excluded.title ELSE title END`,
          )
          .run(url, new URL(url).hostname, e.title, e.started_at, e.ts);
        const page = this.pageByUrl(url)!;
        const existing = this.db
          .query<
            { page_id: number; started_at: number },
            [string]
          >('SELECT page_id,started_at FROM visits WHERE id=?')
          .get(e.visit_id);
        if (existing && (existing.page_id !== page.id || existing.started_at !== e.started_at))
          throw new Error('Visit identity conflict');
        this.db
          .query(
            `INSERT INTO visits(id,page_id,started_at,last_event_at,active_ms,max_scroll,end_reason) VALUES(?,?,?,?,?,?,?)
          ON CONFLICT(id) DO UPDATE SET active_ms=MAX(active_ms,excluded.active_ms), max_scroll=MAX(max_scroll,excluded.max_scroll),
          end_reason=CASE WHEN excluded.last_event_at >= last_event_at THEN COALESCE(excluded.end_reason,end_reason) ELSE end_reason END,
          last_event_at=MAX(last_event_at,excluded.last_event_at)`,
          )
          .run(
            e.visit_id,
            page.id,
            e.started_at,
            e.ts,
            e.active_ms,
            e.max_scroll,
            e.end_reason ?? null,
          );
        if (e.kind !== 'visit' && (e.kind !== 'select' || (e.selection_length ?? 0) > 40))
          this.db
            .query('INSERT INTO signals(id,visit_id,kind,ts) VALUES(?,?,?,?)')
            .run(e.id, e.visit_id, e.kind, e.ts);
        this.db.query('INSERT INTO events(id,ts) VALUES(?,?)').run(e.id, e.ts);
        result.accepted++;
      }
      return result;
    })();
  }
  metrics(pageId: number, since = 0, until = Number.MAX_SAFE_INTEGER): Metrics {
    const visits = this.db
      .query<
        { started_at: number; active_ms: number; max_scroll: number },
        [number, number, number]
      >('SELECT started_at,active_ms,max_scroll FROM visits WHERE page_id=? AND started_at>=? AND started_at<? ORDER BY started_at')
      .all(pageId, since, until);
    // Sessions inside an hour are one cluster; each later cluster is one return.
    let returns = 0,
      previous: number | undefined;
    for (const v of visits) {
      if (previous !== undefined && v.started_at - previous >= 3_600_000) returns++;
      previous = v.started_at;
    }
    const signals = this.db
      .query<
        { kind: string; count: number },
        [number, number, number]
      >(`SELECT s.kind,COUNT(*) AS count FROM signals s JOIN visits v ON v.id=s.visit_id WHERE v.page_id=? AND s.ts>=? AND s.ts<? GROUP BY s.kind`)
      .all(pageId, since, until);
    return {
      active_ms: visits.reduce((n, v) => n + v.active_ms, 0),
      max_scroll: Math.max(0, ...visits.map((v) => v.max_scroll)),
      returns,
      signals,
    };
  }
  verdict(pageId: number) {
    return this.db.query<Verdict, [number]>('SELECT * FROM verdicts WHERE page_id=?').get(pageId);
  }
  setVerdict(v: Verdict) {
    if (!this.page(v.page_id)) throw new Error('Page not found');
    return this.db.transaction(() => {
      const args = [
        v.page_id,
        v.bucket,
        v.source,
        v.confidence,
        v.heur_score,
        v.reason,
        v.needs_review,
        v.decided_at,
      ] as const;
      this.db
        .query(
          'INSERT INTO verdict_history(page_id,bucket,source,confidence,heur_score,reason,needs_review,decided_at) VALUES(?,?,?,?,?,?,?,?)',
        )
        .run(...args);
      const current = this.verdict(v.page_id);
      if (
        current &&
        priority[current.source] >= 2 &&
        priority[current.source] > priority[v.source]
      ) {
        this.db
          .query('UPDATE verdicts SET heur_score=? WHERE page_id=?')
          .run(v.heur_score, v.page_id);
        return false;
      }
      this.db
        .query(
          `INSERT INTO verdicts(page_id,bucket,source,confidence,heur_score,reason,needs_review,decided_at) VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(page_id) DO UPDATE SET bucket=excluded.bucket,source=excluded.source,confidence=excluded.confidence,heur_score=excluded.heur_score,reason=excluded.reason,needs_review=excluded.needs_review,decided_at=excluded.decided_at`,
        )
        .run(...args);
      return true;
    })();
  }
  query(q: Query = {}): Summary[] {
    return this.summaries(q).slice(0, Math.max(1, Math.min(q.limit ?? 50, 500)));
  }
  summaries(q: Query = {}): Summary[] {
    const since = q.since ?? 0,
      until = q.until ?? Number.MAX_SAFE_INTEGER;
    const pages = this.db
      .query<
        Page,
        [number, number, string | null, string | null]
      >(`SELECT p.* FROM pages p WHERE EXISTS (SELECT 1 FROM visits v WHERE v.page_id=p.id AND v.started_at>=? AND v.started_at<?) AND (? IS NULL OR p.domain=?)`)
      .all(since, until, q.domain ?? null, q.domain ?? null);
    return pages
      .map(({ excerpt, ...p }) => ({
        ...p,
        ...this.metrics(p.id, since, until),
        verdict: this.verdict(p.id),
      }))
      .filter(
        (p) =>
          (q.min_score === undefined || (p.verdict?.heur_score ?? 0) >= q.min_score) &&
          (!q.bucket || p.verdict?.bucket === q.bucket),
      )
      .sort(
        (a, b) =>
          (b.verdict?.heur_score ?? 0) - (a.verdict?.heur_score ?? 0) ||
          b.last_seen - a.last_seen ||
          a.id - b.id,
      );
  }
  details(id: number) {
    const page = this.page(id);
    if (!page) return null;
    return {
      ...page,
      ...this.metrics(id),
      verdict: this.verdict(id),
      visits: this.db
        .query('SELECT * FROM visits WHERE page_id=? ORDER BY started_at DESC LIMIT 500')
        .all(id),
      signals: this.db
        .query(
          'SELECT s.* FROM signals s JOIN visits v ON v.id=s.visit_id WHERE v.page_id=? ORDER BY ts DESC LIMIT 500',
        )
        .all(id),
    };
  }
  history(since: number, until = Date.now()) {
    return this.db
      .query(
        'SELECT h.*,p.title,p.domain,p.url_norm FROM verdict_history h JOIN pages p ON p.id=h.page_id WHERE decided_at>=? AND decided_at<? ORDER BY decided_at DESC LIMIT 500',
      )
      .all(since, until);
  }
  prune(now = Date.now()) {
    this.db.transaction(() => {
      this.db.query('DELETE FROM visits WHERE started_at<?').run(now - 90 * DAY);
      this.db.query('DELETE FROM events WHERE ts<?').run(now - 90 * DAY);
    })();
  }
}
