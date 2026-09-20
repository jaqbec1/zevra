import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { configSchema, dataDirectory } from '../src/config';

type Check = { id: string; status: 'ok' | 'warn' | 'error'; message: string };
type Probe = (url: string) => Promise<Response>;
export async function diagnose(
  directory: string,
  probe: Probe = (url) => fetch(url, { signal: AbortSignal.timeout(2000) }),
) {
  const checks: Check[] = [];
  const add = (id: string, status: Check['status'], message: string) =>
    checks.push({ id, status, message });
  let config;
  try {
    config = configSchema.parse(JSON.parse(await readFile(join(directory, 'config.json'), 'utf8')));
    add('config', 'ok', 'Konfiguracja poprawna.');
  } catch {
    add(
      'config',
      'error',
      'Brak poprawnej konfiguracji. Uruchom bun run init lub popraw config.json.',
    );
    return { ok: false, checks };
  }
  for (const name of ['config.json', 'attention.db', 'typesafe.env']) {
    try {
      const info = await stat(join(directory, name));
      add(
        name,
        info.mode & 0o077 ? 'warn' : 'ok',
        info.mode & 0o077
          ? `${name}: dostęp także dla grupy lub innych użytkowników.`
          : `${name}: dostęp tylko właściciela.`,
      );
    } catch {
      add(name, 'warn', `${name}: plik nie istnieje lub jest niedostępny.`);
    }
  }
  const configured = config.policy.mode === 'exclude' || config.policy.allowedDomains.length > 0;
  add(
    'policy',
    configured ? 'ok' : 'warn',
    configured
      ? 'Polityka stron skonfigurowana; sprawdź zgodność z rozszerzeniem.'
      : 'Pusta lista dozwolonych stron blokuje zbieranie.',
  );
  add(
    'jev',
    'ok',
    config.jevEnabled
      ? 'Jev włączony. Diagnostyka nie sprawdza klucza u dostawcy.'
      : 'Jev wyłączony.',
  );
  add(
    'digest',
    'ok',
    config.agentCommand
      ? 'Podsumowania używają skonfigurowanego agenta.'
      : 'Podsumowania wybierane lokalnie.',
  );
  try {
    const response = await probe(`http://127.0.0.1:${config.port}/health`);
    const body = response.ok ? await response.json() : null;
    if (body?.ok !== true) throw new Error('Unhealthy');
    add(
      'collector',
      'ok',
      'Serwis odpowiada. To nie potwierdza dostarczania wizyt z rozszerzenia.',
    );
  } catch {
    add('collector', 'error', 'Serwis nie odpowiada poprawnie na 127.0.0.1:3030.');
  }
  return { ok: !checks.some((c) => c.status === 'error'), checks };
}

if (import.meta.main) {
  const result = await diagnose(dataDirectory());
  if (process.argv.includes('--json')) console.log(JSON.stringify(result, null, 2));
  else for (const check of result.checks) console.log(`[${check.status}] ${check.message}`);
  process.exitCode = result.ok ? 0 : 1;
}
