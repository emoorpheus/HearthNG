// Tests for src/lib/pointer.ts (pointer after coming to the front) and src/lib/exitkey.ts (a held Back).   Run: npm test
import {build} from 'esbuild';
const out = new URL('../node_modules/.cache-pointer-test.mjs', import.meta.url).pathname;
const out2 = new URL('../node_modules/.cache-exitkey-test.mjs', import.meta.url).pathname;
globalThis.window = globalThis;
await build({entryPoints: [new URL('../src/lib/pointer.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out, platform: 'node', logLevel: 'error'});
await build({entryPoints: [new URL('../src/lib/exitkey.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out2, platform: 'node', logLevel: 'error'});
const o = await import(out);
const x = await import(out2);
let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };

let s = o.pointerFront();
eq(s.cursor(true, 100), false, 'before any front event nothing is hidden');
s.front(1000);
eq(s.cursor(true, 1180), true, 'the TV turns it on 180 ms after the front: hidden again');
eq(s.cursor(false, 1200), false, 'its going away is only noted');
eq(s.cursor(true, 1450), false, 'a second show within 600 ms is the user: left alone');
eq(s.cursor(true, 5000), false, 'long after: left alone');
eq(s.line(), 'pointer after coming to the front: shown 180 ms - hidden again, hidden 200 ms, shown 450 ms', 'one line with the events in order (none after 3 s)');

s = o.pointerFront();
s.front(0);
eq(s.cursor(true, 700), false, 'shown 700 ms after the front: the user, left alone');
s.front(300);
eq(s.line(), 'pointer after coming to the front: shown 700 ms', 'a second front event within 600 ms (relaunch + visibility) does not start again');
s.front(10000);
eq(s.line(), null, 'a new front event starts a new line');
eq(s.cursor(true, 10600), true, 'exactly 600 ms still counts as the TV');

const calls = [];
eq(x.keepExitKey({setWindowProperty: (n, v) => calls.push([n, v])}), 'exit key: asked the TV to give it to the launcher', 'the property is set');
eq(calls, [['_WEBOS_ACCESS_POLICY_KEYS_EXIT', 'true']], 'with the name the compositor reads and the string "true"');
eq(x.keepExitKey({}), 'exit key: setWindowProperty is not there, a held Back may close the launcher', 'no API: said so');
eq(x.keepExitKey({setWindowProperty: () => { throw new Error('no'); }}), 'exit key: setWindowProperty failed (no)', 'a failure is said');
process.exit(fail ? 1 : 0);
