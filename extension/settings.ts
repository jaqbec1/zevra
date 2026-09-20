import type { Policy } from '../src/shared/policy';

export type Settings = { enabled: boolean; token: string; policy: Policy; revision?: string };
export async function sendPolicy(
  settings: Settings,
  send: (url: string, init: RequestInit) => Promise<Response> = fetch,
): Promise<string> {
  try {
    const response = await send('http://127.0.0.1:3030/policy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + settings.token },
      body: JSON.stringify(settings.policy),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok)
      return `Collector HTTP ${response.status}. Settings pending; retrying automatically.`;
    if ((await response.json()).ok !== true)
      return 'Collector did not confirm settings; retrying automatically.';
    return '';
  } catch {
    return 'Collector offline. Settings saved locally; retrying automatically.';
  }
}

export type SyncState = { revision: string; error: string; retryAt?: number };
