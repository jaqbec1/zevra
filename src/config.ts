import { chmodSync, mkdirSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { z } from 'zod';
const domain = z.string().regex(/^(?:[a-z0-9-]+\.)+[a-z0-9-]+$/);
export const configSchema = z
  .object({
    token: z.string().min(32),
    port: z.literal(3030).default(3030),
    policy: z.object({
      mode: z.enum(['allow', 'exclude']).optional(),
      excludedKeywords: z.array(z.string().trim().min(1)).optional(),
      allowedDomains: z.array(domain),
      excludedDomains: z.array(domain).default([]),
      excludedPrefixes: z.array(z.string().url()).default([]),
    }),
    jevEnabled: z.boolean().default(false),
    jevModel: z.string().default('jev-latest'),
    agentCommand: z.array(z.string()).min(1).optional(),
    digestDirectory: z.string().optional(),
  })
  .strict();
export type Config = z.infer<typeof configSchema>;
export function dataDirectory() {
  return resolve(process.env.ATTENTION_HOME || join(homedir(), '.local/share/attention-log'));
}
export function configPath() {
  return join(dataDirectory(), 'config.json');
}
export function initialize() {
  process.umask(0o077);
  mkdirSync(dataDirectory(), { recursive: true, mode: 0o700 });
  chmodSync(dataDirectory(), 0o700);
  if (!existsSync(configPath()))
    writeFileSync(
      configPath(),
      JSON.stringify(
        {
          token: crypto.randomUUID() + crypto.randomUUID(),
          port: 3030,
          policy: {
            allowedDomains: [],
            excludedDomains: [],
            excludedPrefixes: [],
          },
          jevEnabled: false,
        },
        null,
        2,
      ) + '\n',
      { mode: 0o600, flag: 'wx' },
    );
  return configPath();
}
export function readConfig(): Config {
  return configSchema.parse(JSON.parse(readFileSync(configPath(), 'utf8')));
}
