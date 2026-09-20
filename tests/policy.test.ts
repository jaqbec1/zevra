import { test, expect } from 'bun:test';
import { allowedUrl, normalizeUrl, publicAddress } from '../src/shared/policy';
const policy = {
  allowedDomains: ['example.com', '127.0.0.1', 'mail.google.com'],
  excludedDomains: ['private.example.com'],
  excludedPrefixes: ['https://example.com/company/'],
};
test('only explicitly allowed public non-secret pages pass', () => {
  expect(allowedUrl('https://example.com/article', policy)).toBe(true);
  for (const u of [
    'https://elsewhere.com',
    'http://127.0.0.1',
    'https://mail.google.com',
    'https://private.example.com',
    'https://example.com/company/secret',
    'https://example.com?access_token=x',
    'https://example.com#token=x',
    'https://user:pass@example.com',
    'file:///tmp/a',
    'https://example.com/login',
    'https://example.com:8443',
  ])
    expect(allowedUrl(u, policy)).toBe(false);
});
test('normalization removes tracking without merging meaningful parameters', () =>
  expect(normalizeUrl('https://EXAMPLE.com/a?utm_source=x&b=2&ref=x&a=1#part')).toBe(
    'https://example.com/a?a=1&b=2',
  ));
test('reject nonpublic IPv4, IPv6 and mapped addresses', () => {
  for (const a of [
    '127.0.0.1',
    '10.0.0.1',
    '169.254.169.254',
    '100.64.0.1',
    '::1',
    '::ffff:127.0.0.1',
    'fc00::1',
  ])
    expect(publicAddress(a)).toBe(false);
  expect(publicAddress('93.184.216.34')).toBe(true);
});

test('exclusion mode admits other sites but blocks private domains and decoded URL words', () => {
  const exclusions = {
    ...policy,
    mode: 'exclude' as const,
    excludedKeywords: ['settings', 'login', 'account'],
  };
  for (const url of [
    'https://wikipedia.org/wiki/Attention',
    'https://docs.cloudflare.com/',
    'https://blog.cloudflare.com/',
  ])
    expect(allowedUrl(url, exclusions)).toBe(true);
  for (const url of [
    'https://mail.google.com/mail/u/0/',
    'https://gmail.com/',
    'https://www.ing.pl/',
    'https://dash.cloudflare.com/',
    'https://one.dash.cloudflare.com/',
    'https://example.org/Settings/profile',
    'https://example.org/my-account',
    'https://example.org/?next=LOGIN',
    'https://example.org/#/settings',
    'https://example.org/%61ccount',
    'https://example.org/%2561ccount',
    'https://private.example.com/article',
    'https://example.com/company/secret',
  ])
    expect(allowedUrl(url, exclusions)).toBe(false);
});

test('missing mode remains allowlist-only and default policy stays disabled', () => {
  expect(
    allowedUrl('https://wikipedia.org/', {
      allowedDomains: [],
      excludedDomains: [],
      excludedPrefixes: [],
    }),
  ).toBe(false);
});
