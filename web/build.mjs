// Bundles each page's script into a classic script (module scripts don't load from file:// in WKWebView).
import { build, context } from 'esbuild';
import { cpSync, mkdirSync } from 'node:fs';

const watch = process.argv.includes('--watch');
const staticFiles = {
    'index.html': 'dist/index.html',
    'settings.html': 'dist/settings.html',
    'src/style.css': 'dist/style.css',
    'src/settings.css': 'dist/settings.css',
};

mkdirSync('dist', { recursive: true });
const copyStatic = () => {
    for (const [from, to] of Object.entries(staticFiles)) cpSync(from, to);
};
const options = {
    entryPoints: ['src/main.ts', 'src/settings.ts'],
    bundle: true,
    format: 'iife',
    target: 'safari16',
    outdir: 'dist',
    sourcemap: true,
    logLevel: 'info',
};
copyStatic();
if (watch) {
    const ctx = await context(options);
    await ctx.watch();
    const { watch: fsWatch } = await import('node:fs');
    for (const f of Object.keys(staticFiles)) fsWatch(f, copyStatic);
} else {
    await build(options);
}
