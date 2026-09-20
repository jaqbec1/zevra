import { test, expect } from 'bun:test';
import { heuristic } from '../src/scoring';
const metrics = { active_ms: 60_000, max_scroll: 1, returns: 0, signals: [] };
test('normalized time caps at twice expected and empty text stays finite', () => {
  expect(heuristic({ word_count: 240 }, { ...metrics, active_ms: 600_000 }).score).toBe(2.1);
  expect(Number.isFinite(heuristic({ word_count: 0 }, metrics).score)).toBe(true);
});
test('copy and returns are independently weighted', () => {
  const base = heuristic({ word_count: 240 }, metrics).score;
  expect(
    heuristic(
      { word_count: 240 },
      { ...metrics, returns: 1, signals: [{ kind: 'copy', count: 1 }] },
    ).score - base,
  ).toBeCloseTo(5.2);
});
