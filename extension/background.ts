import { emptyState, transition, type TrackerState, type Action, type Tab } from './tracker';
import { allowedUrl, defaultPolicy, type Policy } from '../src/shared/policy';
type Settings = { enabled: boolean; token: string; policy: Policy };
const defaults: Settings = { enabled: false, token: '', policy: defaultPolicy };
let serial = Promise.resolve();
// Listeners are registered synchronously; every operation reloads durable state.
function enqueue(job: () => Promise<void>) {
  serial = serial.then(job).catch(async () => {
    await chrome.action.setBadgeText({ text: '!' });
  });
}
async function load() {
  const local = await chrome.storage.local.get(['settings', 'tracker', 'sessionId']);
  const session = await chrome.storage.session.get('sessionId');
  const sessionId = (session.sessionId as string | undefined) ?? crypto.randomUUID();
  if (!session.sessionId) await chrome.storage.session.set({ sessionId });
  const state = (local.tracker as TrackerState | undefined) ?? emptyState();
  if (local.sessionId !== sessionId) state.active = null; // Never count time while browser was closed.
  return {
    settings: (local.settings ?? defaults) as Settings,
    state,
    sessionId,
  };
}
async function focusedTab(): Promise<Tab | null> {
  if ((await chrome.idle.queryState(60)) !== 'active') return null;
  const w = await chrome.windows.getLastFocused();
  if (!w.focused || w.incognito) return null;
  const [tab] = await chrome.tabs.query({ active: true, windowId: w.id });
  return tab?.id !== undefined && !tab.incognito && tab.url
    ? { id: tab.id, url: tab.url, title: (tab.title ?? '').slice(0, 500) }
    : null;
}
async function update(reason: AttentionEventReason = 'switch', signal?: Action, flush = false) {
  const { settings, state, sessionId } = await load();
  const now = Date.now();
  const policy = settings.enabled && settings.token.length >= 32 ? settings.policy : defaultPolicy;
  // A signal belongs to the previous active page even when a queued handler
  // runs after navigation. Reconcile focus only after recording that signal.
  const beforeFocus = signal ? transition(state, signal, policy, now) : state;
  let next = transition(
    beforeFocus,
    { type: 'focus', tab: await focusedTab(), reason },
    policy,
    now,
  );
  // Save before network. A crash after delivery will replay the same UUIDs.
  await chrome.storage.local.set({ tracker: next, sessionId });
  if (flush && next.queue.length && settings.token) {
    try {
      const batch = next.queue.slice(0, 250);
      const response = await fetch('http://127.0.0.1:3030/events', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + settings.token,
        },
        body: JSON.stringify(batch),
        signal: AbortSignal.timeout(5000),
      });
      if (response.ok) {
        next.queue.splice(0, batch.length);
        await chrome.storage.local.set({ tracker: next, sessionId, lastDeliveryError: '' });
      } else
        await chrome.storage.local.set({
          lastDeliveryError: `Collector HTTP ${response.status}`,
        });
    } catch {
      await chrome.storage.local.set({
        lastDeliveryError: 'Collector offline; events retained locally.',
      });
    }
  }
  await chrome.action.setBadgeText({
    text: next.error ? '!' : settings.enabled ? 'ON' : '',
  });
}
type AttentionEventReason = 'switch' | 'close' | 'idle' | 'lock' | 'blur' | 'navigate';
async function setup() {
  await chrome.storage.local.setAccessLevel({
    accessLevel: 'TRUSTED_CONTEXTS',
  });
  chrome.idle.setDetectionInterval(60);
  await chrome.alarms.create('send', { periodInMinutes: 1 });
  await update();
}
chrome.runtime.onInstalled.addListener(() => enqueue(setup));
chrome.runtime.onStartup.addListener(() => enqueue(setup));
chrome.tabs.onActivated.addListener(() => enqueue(() => update()));
chrome.tabs.onUpdated.addListener((_id, info) => {
  if (info.url || info.status === 'complete') enqueue(() => update('navigate'));
});
chrome.tabs.onRemoved.addListener(() => enqueue(() => update('close')));
chrome.windows.onFocusChanged.addListener(() => enqueue(() => update('blur')));
chrome.idle.onStateChanged.addListener((state) =>
  enqueue(() => update(state === 'locked' ? 'lock' : 'idle')),
);
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'send') enqueue(() => update('switch', undefined, true));
});
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.settings)
    enqueue(async () => {
      const { state } = await load();
      state.error = undefined;
      await chrome.storage.local.set({ tracker: state });
      await update();
    });
});
chrome.tabs.onCreated.addListener((tab) =>
  enqueue(async () => {
    const { settings, state } = await load();
    const dest = tab.pendingUrl ?? tab.url;
    if (state.active?.tab.id === tab.openerTabId && dest && allowedUrl(dest, settings.policy))
      await update('switch', {
        type: 'signal',
        tabId: tab.openerTabId!,
        kind: 'open_link',
      });
  }),
);
chrome.runtime.onMessage.addListener((message, sender) => {
  if (
    sender.frameId !== 0 ||
    sender.tab?.id === undefined ||
    sender.tab.incognito ||
    !['scroll', 'select', 'copy'].includes(message?.kind)
  )
    return;
  const tabId = sender.tab.id,
    url = sender.url;
  enqueue(async () => {
    const { settings } = await load();
    if (!url || !allowedUrl(url, settings.policy)) return;
    const length = Number.isFinite(message.length)
      ? Math.max(0, Math.min(1_000_000, Math.floor(message.length)))
      : 0;
    const scroll = Number.isFinite(message.scroll) ? Math.max(0, Math.min(1, message.scroll)) : 0;
    await update('switch', {
      type: 'signal',
      tabId,
      url,
      kind: message.kind,
      length,
      scroll,
    });
  });
});
// Alarms can be cleared by browser restart; ensure the alarm exists on wake.
enqueue(async () => {
  if (!(await chrome.alarms.get('send'))) await setup();
});

chrome.action.onClicked.addListener(() => {
  void chrome.tabs.create({ url: chrome.runtime.getURL('pages.html') });
});
