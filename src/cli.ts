import { join } from 'node:path';
import { initialize, readConfig, dataDirectory, savePolicy } from './config';
import { Store } from './store';
import { handler } from './server';
import { enrich } from './enrich';
import { classify } from './jev';
import { createDigest, localDay, dayRange } from './digest';
import { verdictSchema } from './shared/contracts';
import { heuristic } from './scoring';
import { allowedUrl } from './shared/policy';
const [command, ...args] = process.argv.slice(2);
process.umask(0o077);
if (command === 'init') {
  console.log(
    `Config created at ${initialize()}. Choose the site policy and exclusions before starting. Collection and external classification are off by default.`,
  );
  process.exit(0);
}
if (!['serve', 'sweep', 'digest', 'verdict', 'feedback', 'stats'].includes(command)) {
  console.log(
    'Usage: bun src/cli.ts init|serve|sweep|digest [YYYY-MM-DD]|verdict <id> <bucket> <reason>|feedback <day> yes|no|stats',
  );
  process.exit(command ? 1 : 0);
}
const config = readConfig(),
  store = new Store(join(dataDirectory(), 'attention.db'));
async function sweep() {
  store.prune();
  await enrich(store, config.policy);
  await classify(store, {
    enabled: config.jevEnabled,
    apiKey: process.env.TYPESAFE_API_KEY,
    model: config.jevModel,
    policy: config.policy,
  });
}
if (command === 'serve') {
  let running = false;
  const work = async () => {
    if (running) return;
    running = true;
    try {
      await sweep();
    } catch {
      console.error('Background sweep failed; it will retry.');
    } finally {
      running = false;
    }
  };
  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: config.port,
    maxRequestBodySize: 1_000_000,
    fetch: handler(store, config, savePolicy),
  });
  console.error(`Attention Log listening on ${server.url}`);
  void work();
  const timer = setInterval(work, 300_000);
  for (const signal of ['SIGINT', 'SIGTERM'] as const)
    process.on(signal, () => {
      clearInterval(timer);
      server.stop(true);
      process.exit(0);
    });
} else {
  try {
    if (command === 'sweep') await sweep();
    if (command === 'digest') {
      await sweep();
      const today = new Date();

      console.log(
        await createDigest(
          store,
          args[0] ?? localDay(today),
          config.policy,
          config.digestDirectory ?? join(dataDirectory(), 'digests'),
          config.agentCommand,
        ),
      );
    }
    if (command === 'verdict') {
      const v = verdictSchema.parse({
          page_id: Number(args[0]),
          bucket: args[1],
          reason: args.slice(2).join(' '),
        }),
        page = store.page(v.page_id);
      if (!page || !allowedUrl(page.url_norm, config.policy)) throw new Error('Page not found');
      store.setVerdict({
        ...v,
        source: 'human',
        confidence: null,
        heur_score: heuristic(page, store.metrics(page.id)).score,
        needs_review: 0,
        decided_at: Date.now(),
      });
      console.log('Human verdict saved.');
    }
    if (command === 'feedback') {
      dayRange(args[0]);
      if (!['yes', 'no'].includes(args[1])) throw new Error('Use yes or no');
      const result = store.db
        .query('UPDATE digests SET useful=? WHERE day=?')
        .run(args[1] === 'yes' ? 1 : 0, args[0]);
      if (!result.changes) throw new Error('Digest not found');
      console.log('Feedback saved.');
    }
    if (command === 'stats')
      console.log(
        store.db
          .query(
            'SELECT COUNT(*) AS digests,COUNT(useful) AS evaluated,SUM(useful) AS useful,ROUND(AVG(useful)*100,1) AS useful_percent FROM (SELECT useful FROM digests ORDER BY day DESC LIMIT 14)',
          )
          .get(),
      );
  } finally {
    store.close();
  }
}
