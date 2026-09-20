import { mkdir, copyFile } from 'node:fs/promises';
await mkdir('dist/extension', { recursive: true });
for (const entry of ['background', 'content', 'options', 'pages']) {
  const result = await Bun.build({
    entrypoints: [`extension/${entry}.ts`],
    outdir: 'dist/extension',
    target: 'browser',
    format: entry !== 'content' ? 'esm' : 'iife',
    minify: false,
  });
  if (!result.success) throw new Error(result.logs.join('\n'));
}
for (const f of ['manifest.json', 'options.html', 'pages.html'])
  await copyFile(`extension/${f}`, `dist/extension/${f}`);
console.log('Built dist/extension');
