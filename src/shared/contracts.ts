import { z } from 'zod';
export const buckets = ['czytaj', 'utrwal', 'doczytaj', 'zapomnij'] as const;
export const bucketSchema = z.enum(buckets);
export type Bucket = z.infer<typeof bucketSchema>;
export const eventSchema = z
  .object({
    id: z.string().uuid(),
    visit_id: z.string().uuid(),
    kind: z.enum(['visit', 'select', 'copy', 'open_link']),
    url: z.string().url().max(4096),
    title: z.string().max(500).default(''),
    started_at: z.number().int().nonnegative(),
    ts: z.number().int().nonnegative(),
    active_ms: z.number().int().nonnegative().max(86_400_000),
    max_scroll: z.number().min(0).max(1),
    selection_length: z.number().int().min(0).max(1_000_000).optional(),
    end_reason: z
      .enum(['switch', 'close', 'idle', 'lock', 'blur', 'navigate', 'restart', 'sleep'])
      .optional(),
  })
  .strict()
  .refine(
    (e) => e.ts >= e.started_at && e.active_ms <= e.ts - e.started_at + 1000,
    'Invalid visit timing',
  );
export type AttentionEvent = z.infer<typeof eventSchema>;
export const batchSchema = z.array(eventSchema).min(1).max(250);
export const verdictSchema = z
  .object({
    page_id: z.number().int().positive(),
    bucket: bucketSchema,
    reason: z.string().min(1).max(500),
  })
  .strict();
export type Source = 'heuristic' | 'jev' | 'agent' | 'human';
