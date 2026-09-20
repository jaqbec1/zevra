import type { Metrics, Page } from './store';
import type { Bucket } from './shared/contracts';
const weights: Record<string, number> = { copy: 2, select: 1, open_link: 1.5 };
export function heuristic(
  page: Pick<Page, 'word_count'>,
  m: Metrics,
): { score: number; bucket: Bucket; reason: string } {
  const expectedMs = (Math.max(page.word_count ?? 240, 150) / 240) * 60_000;
  const gestures = m.signals.reduce((n, s) => n + (weights[s.kind] ?? 0) * s.count, 0);
  const ratio = m.active_ms / expectedMs;
  const score = 2 * gestures + 1.2 * m.returns + 0.8 * Math.min(ratio, 2) + 0.5 * m.max_scroll;
  const bucket: Bucket =
    score >= 2 ? (ratio >= 0.8 && m.max_scroll >= 0.7 ? 'utrwal' : 'czytaj') : 'zapomnij';
  return {
    score,
    bucket,
    reason: `Heuristic: ${Math.round(m.active_ms / 1000)}s active, ${m.returns} returns, ${m.signals.reduce((n, s) => n + s.count, 0)} gestures.`,
  };
}
