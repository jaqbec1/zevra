import { allowedUrl, normalizeUrl, type Policy } from '../src/shared/policy';
import type { AttentionEvent } from '../src/shared/contracts';
export type Tab = { id: number; url: string; title: string };
type Active = {
  tab: Tab;
  visit_id: string;
  started_at: number;
  last_tick: number;
  active_ms: number;
  max_scroll: number;
};
export type TrackerState = {
  active: Active | null;
  queue: AttentionEvent[];
  error?: string;
};
export const emptyState = (): TrackerState => ({ active: null, queue: [] });
export type Action =
  | { type: 'focus'; tab: Tab | null; reason?: AttentionEvent['end_reason'] }
  | { type: 'tick' }
  | {
      type: 'signal';
      tabId: number;
      url?: string;
      kind: 'select' | 'copy' | 'open_link' | 'scroll';
      length?: number;
      scroll?: number;
    };
const MAX_QUEUE = 4000;
export function transition(
  state: TrackerState,
  action: Action,
  policy: Policy,
  now: number,
): TrackerState {
  const s = structuredClone(state);
  now = Math.max(now, s.active?.last_tick ?? now);
  s.queue = s.queue.filter((e) => allowedUrl(e.url, policy));
  if (s.active && !allowedUrl(s.active.tab.url, policy)) s.active = null;
  if (s.error) return s;
  function emit(
    kind: AttentionEvent['kind'] = 'visit',
    reason?: AttentionEvent['end_reason'],
    length?: number,
  ) {
    const a = s.active;
    if (!a) return;
    if (s.queue.length >= MAX_QUEUE) {
      s.error =
        'Queue full: capture paused. Restore collector connection, then save options to resume.';
      s.active = null;
      return;
    }
    s.queue.push({
      id: crypto.randomUUID(),
      visit_id: a.visit_id,
      kind,
      url: a.tab.url,
      title: a.tab.title,
      started_at: a.started_at,
      ts: Math.max(now, a.started_at),
      active_ms: a.active_ms,
      max_scroll: a.max_scroll,
      ...(reason ? { end_reason: reason } : {}),
      ...(length !== undefined ? { selection_length: length } : {}),
    });
  }
  if (s.active) {
    const delta = now - s.active.last_tick;
    if (delta >= 0 && delta <= 90_000)
      s.active.active_ms = Math.min(86_400_000, s.active.active_ms + delta);
    s.active.last_tick = now;
    // Possible laptop sleep. Keep the previous checkpoint and begin a new visit.
    if (delta > 90_000 || now - s.active.started_at >= 86_400_000) {
      emit('visit', delta > 90_000 ? 'sleep' : 'restart');
      s.active = null;
    }
  }
  if (action.type === 'focus') {
    const tab =
      action.tab && allowedUrl(action.tab.url, policy)
        ? { ...action.tab, url: normalizeUrl(action.tab.url) }
        : null;
    if (s.active && (s.active.tab.id !== tab?.id || s.active.tab.url !== tab?.url)) {
      emit('visit', action.reason ?? 'switch');
      s.active = null;
    }
    if (tab && !s.active && !s.error)
      s.active = {
        tab,
        visit_id: crypto.randomUUID(),
        started_at: now,
        last_tick: now,
        active_ms: 0,
        max_scroll: 0,
      };
    if (s.active && tab) s.active.tab.title = tab.title;
    emit();
  } else if (action.type === 'tick') emit();
  else if (
    s.active?.tab.id === action.tabId &&
    (!action.url || s.active.tab.url === normalizeUrl(action.url))
  ) {
    if (action.kind === 'scroll') {
      s.active.max_scroll = Math.max(
        s.active.max_scroll,
        Math.max(0, Math.min(1, action.scroll ?? 0)),
      );
    } else if (action.kind !== 'select' || (action.length ?? 0) > 40)
      emit(action.kind, undefined, action.length);
  }
  return s;
}
