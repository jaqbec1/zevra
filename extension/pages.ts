import {
  createElement,
  Clock,
  ArrowDownToLine,
  RotateCcw,
  CalendarClock,
  Table2,
  LayoutGrid,
  CircleHelp,
  BookOpen,
  Bookmark,
  CircleMinus,
  type IconNode,
} from 'lucide';
import type { Metrics, Verdict } from '../src/store';
type SavedPage = Metrics & {
  id: number;
  url_norm: string;
  title: string;
  domain: string;
  last_seen: number;
  fetch_status: string;
  verdict: Verdict | null;
};
const get = (id: string) => document.getElementById(id)!;
let offset = 0,
  total = 0,
  requestNumber = 0;
const label: Record<string, string> = {
  czytaj: 'Read',
  utrwal: 'Keep',
  zapomnij: 'Skip',
  doczytaj: 'Read more',
};
const source: Record<string, string> = {
  heuristic: 'local rules',
  jev: 'Jev',
  agent: 'agent',
  human: 'Your decision',
};
function element(tag: string, text: string, className = '') {
  const node = document.createElement(tag);
  node.textContent = text;
  node.className = className;
  return node;
}
let currentPages: SavedPage[] = [];
let view: 'table' | 'cards' = 'table';
function icon(node: IconNode) {
  return createElement(node, { 'aria-hidden': 'true', width: 16, height: 16, 'stroke-width': 1.7 });
}
function metric(node: IconNode, value: string, description: string) {
  const el = element('span', '', 'metric');
  el.title = description;
  el.setAttribute('aria-label', description + ': ' + value);
  el.append(icon(node), document.createTextNode(value));
  return el;
}
function duration(ms: number) {
  const seconds = Math.round(ms / 1000);
  return seconds < 60 ? `${seconds} s` : `${Math.floor(seconds / 60)} min ${seconds % 60} s`;
}
function decision(page: SavedPage) {
  const v = page.verdict,
    wrap = element('div', '', 'classification');
  const badge = element(
    'span',
    '',
    'badge ' + (v?.needs_review ? 'review' : (v?.bucket ?? 'pending')),
  );
  badge.append(
    icon(
      v?.needs_review || !v
        ? CircleHelp
        : v.bucket === 'utrwal'
          ? Bookmark
          : v.bucket === 'zapomnij'
            ? CircleMinus
            : BookOpen,
    ),
    document.createTextNode(
      v?.needs_review ? 'Needs review' : (label[v?.bucket ?? ''] ?? 'Pending'),
    ),
  );
  wrap.append(badge);
  if (v) {
    const text =
      v.source === 'jev'
        ? `Jev · confidence ${Math.round((v.confidence ?? 0) * 100)}%`
        : (source[v.source] ?? v.source);
    wrap.append(element('small', text, 'source'));
    const details = document.createElement('details'),
      summary = element('summary', 'Details');
    let reason = v.reason;
    if (v.source === 'jev')
      reason = v.needs_review
        ? 'Classification confidence is too low to assign a category without review.'
        : `Jev classification: ${label[v.bucket ?? ''] ?? 'no decision'}.`;
    else if (v.source === 'heuristic')
      reason = v.reason.includes('Below 150')
        ? 'The extracted content contains fewer than 150 words.'
        : `Based on active time, scroll depth, return visits and gestures.${v.reason.includes('Jev unavailable') ? ' Jev did not return a valid response.' : ''}`;
    details.append(summary, element('p', reason));
    wrap.append(details);
  }
  return wrap;
}
function pageLink(page: SavedPage) {
  const wrap = element('div', '', 'page-title'),
    link = document.createElement('a'),
    url = new URL(page.url_norm);
  if (['http:', 'https:'].includes(url.protocol)) link.href = url.href;
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  link.textContent = page.title || page.url_norm;
  wrap.append(link, element('div', page.domain, 'domain'));
  return wrap;
}
function render() {
  get('pages').replaceChildren();
  get('table-body').replaceChildren();
  get('pages').hidden = view !== 'cards';
  get('table-view').hidden = view !== 'table';
  for (const name of ['table', 'cards'])
    get('view-' + name).setAttribute('aria-pressed', String(view === name));
  for (const page of currentPages) {
    const date = new Date(page.last_seen);
    const values = [
      metric(Clock, duration(page.active_ms), 'Active time'),
      metric(ArrowDownToLine, `${Math.round(page.max_scroll * 100)}%`, 'Maximum scroll depth'),
      metric(RotateCcw, String(page.returns), 'Returns'),
      metric(
        CalendarClock,
        date.toLocaleString('en-GB', {
          day: '2-digit',
          month: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
        }),
        'Last active',
      ),
    ];
    if (view === 'table') {
      const row = document.createElement('tr'),
        title = document.createElement('td');
      title.append(pageLink(page));
      row.append(title);
      for (const value of values) {
        const cell = document.createElement('td');
        cell.append(value);
        row.append(cell);
      }
      const cell = document.createElement('td');
      cell.append(decision(page));
      row.append(cell);
      get('table-body').append(row);
    } else {
      const li = document.createElement('li'),
        article = document.createElement('article');
      article.append(pageLink(page));
      const metrics = element('div', '', 'metrics');
      metrics.append(...values);
      article.append(metrics, decision(page));
      li.append(article);
      get('pages').append(li);
    }
  }
}
for (const [id, node] of [
  ['table', Table2],
  ['cards', LayoutGrid],
] as const) {
  get('view-' + id).prepend(icon(node));
  get('view-' + id).addEventListener('click', () => {
    view = id;
    render();
    void chrome.storage.local.set({ pagesView: view });
  });
}
async function load() {
  const request = ++requestNumber;
  get('status').textContent = 'Loading saved pages…';
  (get('previous') as HTMLButtonElement).disabled = true;
  (get('next') as HTMLButtonElement).disabled = true;
  try {
    const { settings } = (await chrome.storage.local.get('settings')) as {
      settings?: { token?: string };
    };
    if (!settings?.token) throw new Error('Open Settings and save your local collector token.');
    const query = (get('query') as HTMLInputElement).value;
    let response: Response;
    try {
      response = await fetch(
        `http://127.0.0.1:3030/pages?${new URLSearchParams({ q: query, offset: String(offset) })}`,
        {
          headers: { Authorization: 'Bearer ' + settings.token },
          signal: AbortSignal.timeout(5000),
        },
      );
    } catch {
      throw new Error('Cannot connect to the local collector. Start it and select Refresh.');
    }
    if (!response.ok)
      throw new Error(
        response.status === 401
          ? 'Invalid token. Check Settings.'
          : `Collector returned error ${response.status}.`,
      );
    const body = (await response.json()) as { pages: SavedPage[]; total: number };
    if (request !== requestNumber) return;
    total = body.total;
    currentPages = body.pages;
    render();
    get('empty').hidden = body.pages.length !== 0;
    get('status').textContent =
      `Saved pages: ${total}. Updated ${new Date().toLocaleTimeString('en-GB')}.`;
    get('range').textContent = total
      ? `${offset + 1}–${offset + body.pages.length} of ${total}`
      : '0';
    (get('previous') as HTMLButtonElement).disabled = offset === 0;
    (get('next') as HTMLButtonElement).disabled = offset + 50 >= total;
  } catch (error) {
    if (request === requestNumber) {
      currentPages = [];
      render();
      get('empty').hidden = true;
      get('range').textContent = '';
      get('status').textContent = error instanceof Error ? error.message : 'Could not load pages.';
    }
  }
}
get('search').addEventListener('submit', (e) => {
  e.preventDefault();
  offset = 0;
  void load();
});
get('refresh').addEventListener('click', () => {
  offset = 0;
  void load();
});
get('previous').addEventListener('click', () => {
  offset = Math.max(0, offset - 50);
  void load();
});
get('next').addEventListener('click', () => {
  if (offset + 50 < total) {
    offset += 50;
    void load();
  }
});
const preference = await chrome.storage.local.get('pagesView');
view = preference.pagesView === 'cards' ? 'cards' : 'table';
render();
void load();
