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

s = o.pointerFront();
s.front(20000, 'a held Back');
eq(s.cursor(true, 20150), true, 'Exit (a held Back) counts like a front event: shown 150 ms after, hidden again');
eq(s.line(), 'pointer after a held Back: shown 150 ms - hidden again', 'the line names the held Back');
s.front(20400);
eq(s.line(), 'pointer after a held Back: shown 150 ms - hidden again', 'a front event right after Exit does not start again');
eq(o.EXIT_KEY_CODE, 1001, 'the key code of Exit is 1001 (what the launcher got after a held Back)');

// the key codes 1536 / 1537 (pointer shown / gone) count like cursorStateChange
s = o.pointerFront();
s.front(30000);
eq(s.cursor(true, 30120, 'key'), true, 'key code 1536 120 ms after the front: hidden again');
eq(s.cursor(false, 30140, 'key'), false, 'key code 1537 is only noted');
eq(s.cursor(true, 30160), false, 'the same show reported by cursorStateChange too: noted, not hidden twice');
eq(s.line(), 'pointer after coming to the front: key shown 120 ms - hidden again, key hidden 140 ms, shown 160 ms', 'the line says which came as a key');
eq([o.POINTER_SHOWN_KEY, o.POINTER_HIDDEN_KEY], [1536, 1537], 'the codes are 1536 and 1537 (pointerShow / pointerHide in LG\'s Settings app)');

const calls = [];
eq(x.keepExitKey({setWindowProperty: (n, v) => calls.push([n, v])}), 'exit key: asked the TV to give it to the launcher', 'the property is set');
eq(calls, [['_WEBOS_ACCESS_POLICY_KEYS_EXIT', 'true']], 'with the name the compositor reads and the string "true"');
eq(x.keepExitKey({}), 'exit key: setWindowProperty is not there, a held Back may close the launcher', 'no API: said so');
eq(x.keepExitKey({setWindowProperty: () => { throw new Error('no'); }}), 'exit key: setWindowProperty failed (no)', 'a failure is said');
// hidePointerOnForeground on a stand-in TV: Exit hides the pointer, and the TV's "shown" right after is hidden again
{
	const docH = {}; const winH = {}; let hides = 0; const lines = [];
	globalThis.document = {hidden: false, addEventListener: (t, f) => { docH[t] = f; }, removeEventListener: () => {}};
	globalThis.addEventListener = (t, f) => { winH[t] = f; };
	globalThis.removeEventListener = () => {};
	globalThis.webOSSystem = {setCursorHidden: v => { if (v) hides++; }};
	const stop = o.hidePointerOnForeground(l => lines.push(l));
	eq(hides, 1, 'hidden at the start');
	winH.keydown({keyCode: 461});
	eq(hides, 1, 'Back does nothing to the pointer');
	await new Promise(r => setTimeout(r, 650));
	winH.keydown({keyCode: 1001});
	eq(hides, 2, 'Exit hides it');
	docH.cursorStateChange({detail: {visibility: true}});
	eq(hides, 3, 'the TV shows it right after Exit: hidden again');
	docH.cursorStateChange({detail: {visibility: true}});
	eq(hides, 3, 'a second show is the user: left alone');
	document.hidden = true; winH.keydown({keyCode: 1001});
	eq(hides, 3, 'Exit while in the background: nothing');
	stop();
	delete globalThis.webOSSystem;
}

// on a stand-in TV: the key code 1536 right after coming to the front hides the pointer again, once; the line comes 3 s later
{
	const docH = {}; const winH = {}; let hides = 0; const lines = [];
	globalThis.document = {hidden: false, addEventListener: (t, f) => { docH[t] = f; }, removeEventListener: () => {}};
	globalThis.addEventListener = (t, f) => { winH[t] = f; };
	globalThis.removeEventListener = () => {};
	globalThis.webOSSystem = {setCursorHidden: v => { if (v) hides++; }};
	const stop = o.hidePointerOnForeground(l => lines.push(l));
	eq(hides, 1, 'keys: hidden at the start');
	winH.keydown({keyCode: 1536});
	eq(hides, 2, 'keys: 1536 right after the front: hidden again');
	winH.keydown({keyCode: 1537});
	winH.keydown({keyCode: 1536});
	eq(hides, 2, 'keys: a second 1536 is the user: left alone');
	document.hidden = true; winH.keydown({keyCode: 1536}); document.hidden = false;
	eq(hides, 2, 'keys: 1536 while in the background: nothing');
	await new Promise(r => setTimeout(r, o.REPORT_AFTER_MS + 200));
	eq(lines.length === 1 && /^pointer after coming to the front: key shown \d+ ms - hidden again, key hidden \d+ ms, key shown \d+ ms$/.test(lines[0]), true, 'keys: one line with the three key reports: ' + lines[0]);
	stop();
	delete globalThis.webOSSystem;
}

// Exit and the pointer codes are known keys, so they are not logged as unknown ones
const keys = [];
const handlers = [];
globalThis.addEventListener = (t, f) => handlers.push(f);
globalThis.removeEventListener = () => {};
x.logOtherKeys(l => keys.push(l));
for (const code of [1001, 1536, 1537, 461, 1234]) handlers.forEach(f => f({keyCode: code, key: ''}));
eq(keys, ['keys: code 1234 (?) reached the launcher'], 'Exit (1001), Back (461) and the pointer codes (1536, 1537) are known keys, 1234 is logged');
process.exit(fail ? 1 : 0);
