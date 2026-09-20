import { test, expect } from 'bun:test';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { diagnose } from '../scripts/doctor';

test('doctor handles a missing configuration without creating files', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'attention-doctor-'));
  try {
    const result = await diagnose(directory, async () => {
      throw new Error('Must not fetch');
    });
    expect(result.ok).toBe(false);
    expect(result.checks[0].id).toBe('config');
    expect(await Bun.file(join(directory, 'config.json')).exists()).toBe(false);
  } finally {
    await rm(directory, { recursive: true });
  }
});

test('doctor checks only loopback and never prints token, URLs or provider key', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'attention-doctor-'));
  const token = 'private-collector-token-0000000000000000';
  try {
    await writeFile(
      join(directory, 'config.json'),
      JSON.stringify({
        token,
        policy: {
          mode: 'exclude',
          allowedDomains: [],
          excludedDomains: ['private.example.com'],
          excludedPrefixes: [],
        },
        jevEnabled: true,
      }),
      { mode: 0o600 },
    );
    await writeFile(join(directory, 'typesafe.env'), 'TYPESAFE_API_KEY=private-provider-key', {
      mode: 0o600,
    });
    const urls: string[] = [];
    const result = await diagnose(directory, async (url) => {
      urls.push(url);
      return Response.json({ ok: true });
    });
    expect(urls).toEqual(['http://127.0.0.1:3030/health']);
    expect(result.checks.find((c) => c.id === 'collector')?.status).toBe('ok');
    const output = JSON.stringify(result);
    for (const secret of [token, 'private-provider-key', 'private.example.com'])
      expect(output).not.toContain(secret);
    await writeFile(join(directory, 'config.json'), '{"token":"private-malformed-secret"');
    const invalid = await diagnose(directory);
    expect(JSON.stringify(invalid)).not.toContain('private-malformed-secret');
    expect(invalid.ok).toBe(false);
  } finally {
    await rm(directory, { recursive: true });
  }
});
