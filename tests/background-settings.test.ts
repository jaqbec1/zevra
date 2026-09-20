import { test, expect } from 'bun:test';
import type { Settings } from '../extension/settings';

test('background retries saved settings after offline and never acknowledges a newer revision with an older response', async () => {
  const originalChrome = globalThis.chrome;
  const originalFetch = globalThis.fetch;
  const listeners: Record<string, (...args: any[]) => void> = {};
  const event = (name: string) => ({
    addListener: (fn: (...args: any[]) => void) => {
      listeners[name] = fn;
    },
  });
  const data: Record<string, any> = {};
  const storage = {
    get: async (keys: string | string[]) =>
      Object.fromEntries(
        (typeof keys === 'string' ? [keys] : keys).map((k) => [k, structuredClone(data[k])]),
      ),
    set: async (values: Record<string, any>) => {
      const changes: Record<string, any> = {};
      for (const [k, v] of Object.entries(values)) {
        changes[k] = { oldValue: data[k], newValue: v };
        data[k] = structuredClone(v);
      }
      listeners.storage?.(changes, 'local');
    },
  };
  globalThis.chrome = {
    storage: {
      local: { ...storage, setAccessLevel: async () => {} },
      session: { get: async () => ({ sessionId: 'session' }) },
      onChanged: event('storage'),
    },
    alarms: { get: async () => ({}), onAlarm: event('alarm') },
    runtime: {
      onInstalled: event('installed'),
      onStartup: event('startup'),
      onMessage: event('message'),
    },
    tabs: {
      onActivated: event('active'),
      onUpdated: event('updated'),
      onRemoved: event('removed'),
      onCreated: event('created'),
    },
    windows: { onFocusChanged: event('focus') },
    idle: { queryState: async () => 'idle', onStateChanged: event('idle') },
    action: { setBadgeText: async () => {}, onClicked: event('clicked') },
  } as unknown as typeof chrome;
  const until = async (check: () => boolean) => {
    for (let i = 0; i < 500 && !check(); i++)
      await new Promise((resolve) => setTimeout(resolve, 1));
    expect(check()).toBe(true);
  };
  let calls = 0;
  let offline = true;
  let release: (() => void) | undefined;
  let hold = false;
  globalThis.fetch = (async () => {
    calls++;
    if (offline) throw new Error('offline');
    if (hold) {
      hold = false;
      await new Promise<void>((resolve) => {
        release = resolve;
      });
    }
    return Response.json({ ok: true });
  }) as unknown as typeof fetch;
  const settings: Settings = {
    revision: 'one',
    enabled: false,
    token: 'synthetic'.repeat(8),
    policy: {
      mode: 'exclude',
      allowedDomains: [],
      excludedDomains: ['example.com'],
      excludedPrefixes: [],
    },
  };
  try {
    await import('../extension/background');
    await storage.set({ settings });
    await until(() => data.policySync?.error?.includes('offline'));
    expect(calls).toBe(1);
    listeners.alarm({ name: 'send' });
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(calls).toBe(1); // Regular browser events cannot create a retry storm.
    offline = false;
    data.policySync.retryAt = 0;
    listeners.alarm({ name: 'send' });
    await until(() => data.policySync?.error === '');
    expect(calls).toBe(2);
    hold = true;
    await storage.set({ settings: { ...settings, revision: 'two' } });
    await until(() => !!release);
    await storage.set({ settings: { ...settings, revision: 'three' } });
    release!();
    await until(() => data.policySync?.revision === 'three' && !data.policySync.error);
    expect(calls).toBe(4);
    expect(data.settings.revision).toBe('three');
    await new Promise((resolve) => setTimeout(resolve, 10));
  } finally {
    globalThis.chrome = originalChrome;
    globalThis.fetch = originalFetch;
  }
});
