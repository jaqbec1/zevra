import { test, expect } from 'bun:test';
import { sendPolicy, type Settings } from '../extension/settings';

test('settings synchronization sends only policy and requires collector acknowledgement', async () => {
  const settings: Settings = {
    token: 'synthetic-token'.repeat(4),
    enabled: true,
    revision: 'test',
    policy: {
      mode: 'exclude',
      allowedDomains: [],
      excludedDomains: ['example.com'],
      excludedPrefixes: [],
    },
  };
  const send = async (url: string, init: RequestInit) => {
    expect(url).toBe('http://127.0.0.1:3030/policy');
    expect(JSON.parse(init!.body as string)).toEqual(settings.policy);
    return Response.json({ ok: true });
  };
  expect(await sendPolicy(settings, send)).toBe('');
  expect(
    await sendPolicy(settings, async () => {
      throw new Error('offline');
    }),
  ).toContain('retrying automatically');
  expect(await sendPolicy(settings, async () => new Response('', { status: 401 }))).toContain(
    '401',
  );
  expect(await sendPolicy(settings, async () => Response.json({}))).toContain('did not confirm');
});
