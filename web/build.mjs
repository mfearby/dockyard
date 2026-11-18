// Bundles src/main.ts into a classic script (module scripts don't load from file:// in WKWebView).
import { build, context } from 'esbuild';
import { cpSync, mkdirSync } from 'node:fs';

const watch = process.argv.includes('--watch');
mkdirSync('dist', { recursive: true });
const copyStatic = () => {
  cpSync('index.html', 'dist/index.html');
  cpSync('src/style.css', 'dist/style.css');
};
const options = {
  entryPoints: ['src/main.ts'],
  bundle: true,
  format: 'iife',
  target: 'safari16',
  outfile: 'dist/main.js',
  sourcemap: true,
  logLevel: 'info',
};
copyStatic();
if (watch) {
  const ctx = await context(options);
  await ctx.watch();
  const { watch: fsWatch } = await import('node:fs');
  for (const f of ['index.html', 'src/style.css']) fsWatch(f, copyStatic);
} else {
  await build(options);
}
