import type { Policy } from '../src/shared/policy';
const field = (id: string) => document.getElementById(id) as HTMLInputElement;
const lines = (id: string) =>
  field(id)
    .value.split('\n')
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
const status = document.getElementById('status')!;
const stored = (await chrome.storage.local.get(['settings', 'tracker', 'lastDeliveryError'])) as {
  settings?: { token: string; enabled: boolean; policy: Policy };
  tracker?: { error?: string };
  lastDeliveryError?: string;
};
if (stored.settings) {
  field('mode').value = stored.settings.policy.mode ?? 'allow';
  field('keywords').value = (stored.settings.policy.excludedKeywords ?? []).join('\n');
  field('token').value = stored.settings.token;
  field('enabled').checked = stored.settings.enabled;
  field('allowed').value = stored.settings.policy.allowedDomains.join('\n');
  field('excluded').value = stored.settings.policy.excludedDomains.join('\n');
  field('prefixes').value = stored.settings.policy.excludedPrefixes.join('\n');
}
status.textContent =
  stored.tracker?.error ||
  stored.lastDeliveryError ||
  (stored.settings?.enabled ? 'Collection is enabled.' : 'Collection is off until enabled.');
document.getElementById('settings')!.addEventListener('submit', async (event) => {
  event.preventDefault();
  const allowedDomains = lines('allowed'),
    excludedDomains = lines('excluded');
  if (
    [...allowedDomains, ...excludedDomains].some((x) => !/^(?:[a-z0-9-]+\.)+[a-z0-9-]+$/.test(x))
  ) {
    status.textContent = 'Use domains only, without https://, paths, or wildcards.';
    return;
  }
  const mode = field('mode').value === 'exclude' ? 'exclude' : 'allow';
  if (field('enabled').checked && mode === 'allow' && !allowedDomains.length) {
    status.textContent = 'Add at least one allowed domain.';
    return;
  }
  const excludedPrefixes = field('prefixes')
    .value.split('\n')
    .map((x) => x.trim())
    .filter(Boolean);
  try {
    for (const p of excludedPrefixes) new URL(p);
  } catch {
    status.textContent = 'Excluded prefixes must be full URLs.';
    return;
  }
  await chrome.storage.local.set({
    settings: {
      enabled: field('enabled').checked,
      token: field('token').value.trim(),
      policy: {
        mode,
        allowedDomains,
        excludedDomains,
        excludedPrefixes,
        excludedKeywords: lines('keywords'),
      },
    },
  });
  status.textContent =
    'Saved. Collector policy also applies; restart the collector after changing its config.';
});
