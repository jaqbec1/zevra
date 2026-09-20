import ipaddr from 'ipaddr.js';

export type Policy = {
  mode?: 'allow' | 'exclude';
  excludedKeywords?: string[];
  allowedDomains: string[];
  excludedDomains: string[];
  excludedPrefixes: string[];
};
export const defaultPolicy: Policy = {
  allowedDomains: [],
  excludedDomains: [],
  excludedPrefixes: [],
};
const blocked = [
  'localhost',
  'local',
  'internal',
  'lan',
  'home.arpa',
  'mail.google.com',
  'gmail.com',
  'dash.cloudflare.com',
  'outlook.com',
  'outlook.office.com',
  'office.com',
  'live.com',
  'proton.me',
  'protonmail.com',
  '1password.com',
  'bitwarden.com',
  'lastpass.com',
  'paypal.com',
  'stripe.com',
  'revolut.com',
  'wise.com',
  'ing.pl',
  'mbank.pl',
  'ipko.pl',
  'pekao24.pl',
  'santander.pl',
  'aliorbank.pl',
  'wakacje.pl',
  'atlassian.net',
  'figma.com',
];
export const domainMatches = (host: string, rule: string) =>
  host === rule || host.endsWith('.' + rule);
export function publicAddress(address: string): boolean {
  try {
    return ipaddr.process(address.replace(/^\[|\]$/g, '')).range() === 'unicast';
  } catch {
    return false;
  }
}
export function allowedUrl(raw: string, policy: Policy): boolean {
  try {
    const u = new URL(raw);
    const host = u.hostname.toLowerCase().replace(/\.$/, '');
    // Decode nested encodings before matching; reject excessively encoded URLs.
    let decoded = raw;
    for (let i = 0; i < 8; i++) {
      const next = decodeURIComponent(decoded);
      if (next === decoded) break;
      decoded = next;
      if (i === 7) return false;
    }
    if (
      policy.excludedKeywords?.some(
        (word) => word.trim() && decoded.toLowerCase().includes(word.trim().toLowerCase()),
      )
    )
      return false;
    if (!['https:', 'http:'].includes(u.protocol) || u.username || u.password || u.port)
      return false;
    if (
      !host.includes('.') ||
      host.endsWith('.local') ||
      blocked.some((d) => domainMatches(host, d))
    )
      return false;
    if (ipaddr.isValid(host.replace(/^\[|\]$/g, '')) && !publicAddress(host)) return false;
    if (
      /(^|[.\/-])(login|signin|oauth|auth|bank|banking|checkout|payments?|jira|mail|webmail)([.\/-]|$)/i.test(
        host + u.pathname,
      )
    )
      return false;
    for (const key of u.searchParams.keys())
      if (
        /(token|secret|password|passwd|session|auth|api.?key|signature|credential|sso|code)/i.test(
          key,
        )
      )
        return false;
    // Fragments are removed for identity, but must be checked before doing so.
    if (/(token|secret|password|session|auth|api.?key|credential|code)=/i.test(u.hash))
      return false;
    if (
      policy.excludedDomains.some((d) => domainMatches(host, d)) ||
      policy.excludedPrefixes.some((p) => raw.startsWith(p))
    )
      return false;
    return policy.mode === 'exclude' || policy.allowedDomains.some((d) => domainMatches(host, d));
  } catch {
    return false;
  }
}
export function normalizeUrl(raw: string): string {
  const u = new URL(raw);
  u.hash = '';
  u.hostname = u.hostname.toLowerCase().replace(/\.$/, '');
  for (const k of [...u.searchParams.keys()])
    if (/^utm_/i.test(k) || ['fbclid', 'gclid', 'ref'].includes(k.toLowerCase()))
      u.searchParams.delete(k);
  u.searchParams.sort();
  return u.toString();
}
