import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const directory = await mkdtemp(join(tmpdir(), 'attention-check-'));
const env: Record<string, string | undefined> = { ...process.env, ATTENTION_HOME: directory };
delete env.TYPESAFE_API_KEY;
delete env.OPENAI_API_KEY;
delete env.ANTHROPIC_API_KEY;
const steps = ['format:check', 'typecheck', 'test', 'build', 'demo'];
try {
  for (const step of steps) {
    console.log(`\nSprawdzanie: ${step}`);
    const child = Bun.spawn([process.execPath, '--no-env-file', 'run', step], {
      cwd: new URL('..', import.meta.url).pathname,
      env,
      stdin: 'ignore',
      stdout: 'inherit',
      stderr: 'inherit',
    });
    const code = await child.exited;
    if (code !== 0) {
      process.exitCode = code;
      break;
    }
  }
} finally {
  await rm(directory, { recursive: true, force: true });
}
