// Tests for toast/ (com.hearthng.toast, HearthNG's own notifications): appinfo.json, and toast.js run against a fake
// PalmSystem with fake timers (the window type and focus calls, the times, relaunch, close).   Run: npm test
import {readFileSync} from 'fs';
import vm from 'vm';

let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };
const dir = new URL('../toast/', import.meta.url);
const info = JSON.parse(readFileSync(new URL('appinfo.json', dir), 'utf8'));
const src = readFileSync(new URL('toast.js', dir), 'utf8');
const html = readFileSync(new URL('index.html', dir), 'utf8');
const css = readFileSync(new URL('toast.css', dir), 'utf8');

// ---- appinfo.json ----
eq(info.id, 'com.hearthng.toast', 'appinfo: id com.hearthng.toast (watch.sh and guard.sh launch this id)');
eq([info.type, info.main, info.visible, info.transparent, info.handlesRelaunch, info.noSplashOnLaunch, info.spinnerOnLaunch], ['web', 'index.html', false, true, true, true, false],
  'appinfo: web, index.html, no launch point (visible false), transparent, handles relaunch, no splash, no spinner');
eq([info.defaultWindowType, info.resolution], ['card', '1920x1080'], 'appinfo: a card window at 1920x1080 (toast.js makes it FLOATING), as eArcNG');
eq(/<script src="toast\.js"><\/script>/.test(html) && /id="toast"/.test(html), true, 'index.html loads toast.js and has the #toast box');
eq(/transform\s*:/.test(css.replace(/\/\*[\s\S]*?\*\//g, '')), false, 'toast.css has no CSS transform (with translateX(-50%) the TV showed the window only ~8 s after the launch)');
eq(/class="bar"><div id="toast"/.test(html) && /\.bar \{[^}]*text-align: center/.test(css) && /\.toast \{[^}]*display: inline-block/.test(css), true, 'the pill is centred by its .bar line (text-align, inline-block), not by a transform');
eq(/=>|\blet |\bconst |`/.test(src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '')), false, 'toast.js is ES5 (no arrow functions, let, const or template strings)');

// ---- toast.js in a fake TV ----
function run (launchParams) {
  const calls = [];
  let now = 0; let timers = []; let nextId = 1;
  const box = {textContent: '', className: 'toast'};
  const win = {
    closed: 0,
    setTimeout: (fn, ms) => { const id = nextId++; timers.push({id, at: now + ms, fn}); return id; },
    clearTimeout: (id) => { timers = timers.filter((t) => t.id !== id); },
    close: () => { win.closed++; calls.push('close@' + now); },
    location: {search: ''}
  };
  win.PalmSystem = {
    launchParams: JSON.stringify(launchParams),
    setWindowProperty: (k, v) => calls.push(`prop ${k}=${v}@${now}`),
    setInputRegion: (r) => calls.push(`region ${JSON.stringify(r)}@${now}`),
    setKeyMask: (m) => calls.push(`keymask ${m.join(',')}@${now}`),
    activate: () => calls.push('activate@' + now)
  };
  const listeners = {};
  const doc = {getElementById: () => box, addEventListener: (n, fn) => { listeners[n] = fn; }};
  win.window = win; win.document = doc;
  vm.runInNewContext(src, Object.assign(win, {document: doc, JSON, Number, Math, String}));
  const advance = (ms) => {
    const end = now + ms;
    for (;;) {
      timers.sort((a, b) => a.at - b.at);
      const t = timers[0];
      if (!t || t.at > end) break;
      timers.shift(); now = t.at; t.fn();
    }
    now = end;
  };
  const relaunch = (p) => { win.PalmSystem.launchParams = JSON.stringify(p); return win.webOSRelaunch(); };
  return {calls, box, win, advance, relaunch, now: () => now};
}

let r = run({text: 'Домашний экран загружается…', ms: 2000});
eq(r.box.textContent, 'Домашний экран загружается…', 'the text is shown');
eq(r.calls.slice(0, 5), ['prop needFocus=false@0', 'prop _WEBOS_WINDOW_TYPE=_WEBOS_WINDOW_TYPE_FLOATING@0', 'region [{"x":0,"y":0,"width":0,"height":0}]@0', 'keymask KeyMaskDefault@0', 'activate@0'],
  'at once: no focus, FLOATING, an empty input region, the default key mask, then activate() (as eArcNG)');
r.advance(60);
eq(r.calls.filter((c) => c.endsWith('@60')), ['prop needFocus=false@60', 'region [{"x":0,"y":0,"width":0,"height":0}]@60', 'keymask KeyMaskDefault@60'], 'after 60 ms the focus is given back again, no input region (as eArcNG)');
eq(r.box.className.indexOf('toast--show') !== -1, true, 'it fades in (toast--show)');
r.advance(3000);
eq([r.win.closed, r.box.className.indexOf('toast--show') !== -1], [0, true], '3060 ms: still on screen (2000 ms + 1100 ms for the window to come up)');
r.advance(40);
eq(r.box.className.indexOf('toast--show'), -1, '3100 ms: it fades out');
r.advance(150);
eq(r.win.closed, 1, '3250 ms: the window closes itself (1100 + 2000 ms + 150 ms fade)');
eq(r.calls.filter((c) => c.indexOf('activate') === 0).length, 1, 'activate() only once');

r = run({text: 'A', ms: 2000});
r.advance(1500);
eq(r.relaunch({params: {text: 'B', ms: 1000}}), true, 'relaunch is handled (webOSRelaunch returns true)');
eq(r.box.textContent, 'B', 'relaunch: the new text');
r.advance(900);
eq(r.win.closed, 0, 'relaunch: the time starts again (still there 900 ms later)');
r.advance(300);
eq(r.win.closed, 1, 'relaunch: closed 1000 + 150 ms after the relaunch');
eq(r.calls.filter((c) => c.indexOf('activate') === 0).length, 1, 'relaunch: no second activate() (it would take the focus)');

r = run({});
eq([r.win.closed, r.calls.filter((c) => c.indexOf('activate') === 0).length], [1, 0], 'no text: closes at once, never activated');
r = run({text: 'x', ms: 99999});
r.advance(3249);
eq(r.win.closed, 0, 'ms out of range (99999): the default 2000 ms');
r.advance(1);
eq(r.win.closed, 1, 'ms out of range: closed at 3250 ms');
r = run({text: 'x', ms: 'abc'});
r.advance(3250);
eq(r.win.closed, 1, 'ms not a number: the default 2000 ms');
r = run({text: 'x', ms: 1000, appearMs: 0});
r.advance(1149);
eq(r.win.closed, 0, 'appearMs 0: no time for the window to come up');
r.advance(1);
eq(r.win.closed, 1, 'appearMs 0: closed at 1000 + 150 ms');
r = run({text: 'x', ms: 1000, appearMs: 9999});
r.advance(2249);
eq(r.win.closed, 0, 'appearMs out of range (9999): the default 1100 ms');
r.advance(1);
eq(r.win.closed, 1, 'appearMs out of range: closed at 1100 + 1000 + 150 ms');
r = run({text: 'x'});
r.relaunch({close: true});
eq(r.win.closed, 1, '{"close":true}: closes at once');
r = run({text: 'x'.repeat(400), kind: 'error'});
eq([r.box.textContent.length, /toast--error/.test(r.box.className), /toast--long/.test(r.box.className)], [300, true, true], 'long text: cut to 300 characters, wrapped (toast--long); kind error: toast--error');

console.log(fail ? `\n${fail} failed` : '\nall passed');
process.exit(fail ? 1 : 0);
