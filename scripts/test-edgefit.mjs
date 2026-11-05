// Tests for src/lib/edgefit.ts (keeps something drawn round a tile on the screen).   Run: npm test
import {build} from 'esbuild';
const out = new URL('../node_modules/.cache-edgefit-test.mjs', import.meta.url).pathname;
await build({entryPoints: [new URL('../src/lib/edgefit.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out, platform: 'node', logLevel: 'error'});
const t = await import(out);
let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };

eq(t.edgeShift(100, 258, 1920, 24), 0, 'fits on the screen: not moved');
eq(t.edgeShift(24, 258, 1920, 24), 0, 'starts right at the left margin: not moved');
eq(t.edgeShift(1920 - 24 - 258, 258, 1920, 24), 0, 'ends right at the right margin: not moved');
eq(t.edgeShift(-30, 258, 1920, 24), 54, 'over the left edge (first tile, three buttons): moved right to the margin');
eq(t.edgeShift(10, 172, 1920, 24), 14, 'inside the left margin: moved right to the margin');
eq(t.edgeShift(1800, 258, 1920, 24), -162, 'over the right edge: moved left to the margin');
eq(t.edgeShift(-10, 2000, 1920, 24), 34, 'wider than the screen: starts at the left margin');
eq(t.edgeShift(100, 2000, 1920, 24), -76, 'wider than the screen, starting further right: starts at the left margin');
eq(t.edgeShift(NaN, 258, 1920, 24), 0, 'no position measured: not moved');
eq(t.edgeShift(-30, 258, 0, 24), 0, 'no screen width: not moved');
eq(t.edgeShift(-30, 0, 1920, 24), 0, 'nothing drawn (no buttons): not moved');

console.log(fail ? `${fail} FAILED` : 'all passed');
process.exit(fail ? 1 : 0);
