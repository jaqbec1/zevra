import { lookup } from 'node:dns/promises';
import http from 'node:http';
import https from 'node:https';
import { allowedUrl, publicAddress, type Policy } from './shared/policy';

export const MAX_HTML = 2_000_000;
export async function resolvePublic(hostname: string) {
  const addresses = await lookup(hostname.replace(/^\[|\]$/g, ''), {
    all: true,
  });
  if (!addresses.length || addresses.some((a) => !publicAddress(a.address)))
    throw new Error('Non-public destination');
  return addresses[0];
}
export async function fetchHtml(raw: string, policy: Policy): Promise<string> {
  let current = raw;
  const deadline = AbortSignal.timeout(15_000);
  for (let hop = 0; hop < 5; hop++) {
    if (!allowedUrl(current, policy)) throw new Error('Excluded destination');
    const url = new URL(current),
      address = await resolvePublic(url.hostname);
    deadline.throwIfAborted();
    const result = await new Promise<{
      status: number;
      location?: string;
      body: string;
    }>((resolve, reject) => {
      const req = (url.protocol === 'https:' ? https : http).request(
        url,
        {
          signal: deadline,
          method: 'GET',
          agent: false,
          headers: {
            'User-Agent': 'AttentionLog/0.1 (local personal reading log)',
            Accept: 'text/html',
            'Accept-Encoding': 'identity',
          },
          // Pin DNS once validated; TLS still verifies the original hostname.
          lookup: (_host, options, callback) =>
            options.all
              ? callback(null, [address])
              : callback(null, address.address, address.family),
        },
        (res) => {
          const status = res.statusCode ?? 0;
          if (status >= 300 && status < 400) {
            res.resume();
            resolve({ status, location: res.headers.location, body: '' });
            return;
          }
          if (status !== 200 || !res.headers['content-type']?.includes('text/html')) {
            res.destroy();
            reject(new Error('Not public HTML'));
            return;
          }
          const chunks: Buffer[] = [];
          let bytes = 0;
          res.on('data', (chunk: Buffer) => {
            bytes += chunk.length;
            if (bytes > MAX_HTML) {
              res.destroy(new Error('HTML too large'));
              return;
            }
            chunks.push(chunk);
          });
          res.on('end', () => resolve({ status, body: Buffer.concat(chunks).toString('utf8') }));
          res.on('error', reject);
        },
      );
      req.on('error', reject);
      req.end();
    });
    if (result.status === 200) return result.body;
    if (!result.location) throw new Error('Redirect missing location');
    current = new URL(result.location, current).toString();
  }
  throw new Error('Too many redirects');
}
