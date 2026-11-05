// Runs the real CLOSE_HOME_COMMAND against look-alike processes.   Run: npm test
import {build} from 'esbuild';
import {execSync} from 'child_process';
const out = new URL('../node_modules/.cache-system-test.mjs', import.meta.url).pathname;
await build({entryPoints: [new URL('../src/lib/system.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out, platform: 'node', logLevel: 'error',
  plugins: [{name: 'stub', setup(b) { b.onResolve({filter: /\.\/(apps|luna)$/}, (a) => ({path: a.path, namespace: 'stub'})); b.onLoad({filter: /.*/, namespace: 'stub'}, () => ({contents: 'export const exec = () => Promise.resolve(""); export const isWebOS = () => false;', loader: 'js'})); }}]});
const {CLOSE_HOME_COMMAND, homeSettingCommand, parseHomeApp, parseDefaultApps} = await import(out);
let fail = 0;
const eq = (a, b, m) => { const ok = a === b; if (!ok) fail++; console.log(ok ? 'ok  ' : 'FAIL', m, ok ? '' : `(${a} != ${b})`); };
import {startLookalike as start} from './lookalike.mjs';
const alive = (p) => { try { process.kill(p.pid, 0); return true; } catch { return false; } };
const home = await start('/usr/bin/qml-runner --app com.webos.app.home');
const homeEnd = await start('qml-runner com.webos.app.home');
const connect = await start('/usr/bin/qml-runner --app com.webos.app.homeconnect');
const other = await start('com.webos.app.settings');
const web = await start('WebAppMgr --app com.hearthng.launcher');
await new Promise((r) => setTimeout(r, 400));
const result = execSync(CLOSE_HOME_COMMAND, {shell: '/bin/sh'}).toString();   // runs as `sh -c`, like the TV's exec
await new Promise((r) => setTimeout(r, 400));
eq(result.trim(), 'done', 'the command itself survives and finishes (it does not kill its own shell)');
eq(alive(home), false, 'LG Home process ended');
eq(alive(homeEnd), false, 'LG Home ended when the id is the last word');
eq(alive(connect), true, 'com.webos.app.homeconnect left alone');
eq(alive(other), true, 'other system apps left alone');
eq(alive(web), true, 'our own launcher left alone');
// ---- LG Home is not ended while it is the app in front (that would leave a black screen) ----
import {mkdtempSync, writeFileSync as wf, chmodSync, rmSync as rm} from 'fs';
import {tmpdir} from 'os';
const bin = mkdtempSync(tmpdir() + '/fakeluna-');
wf(bin + '/luna-send', '#!/bin/sh\necho "$FAKE_FRONT"\n'); chmodSync(bin + '/luna-send', 0o755);
const front = (appId) => JSON.stringify({returnValue: true, appId, processId: '', windowId: ''});
const run2 = (appId) => execSync(CLOSE_HOME_COMMAND, {shell: '/bin/sh', env: {...process.env, PATH: bin + ':' + process.env.PATH, FAKE_FRONT: front(appId)}}).toString().trim();
const homeA = await start('/usr/bin/qml-runner --app com.webos.app.home');
await new Promise((r) => setTimeout(r, 300));
eq(run2('com.webos.app.home'), 'skipped', 'LG Home in front: it is left running');
await new Promise((r) => setTimeout(r, 200));
eq(alive(homeA), true, 'and its process is still there');
eq(run2('com.hearthng.launcher'), 'done', 'the launcher in front: LG Home is ended');
await new Promise((r) => setTimeout(r, 300));
eq(alive(homeA), false, 'and its process is gone');
rm(bin, {recursive: true, force: true});

// ---- the home-app setting commands ----
eq(homeSettingCommand('com.hearthng.launcher').includes('"home":"com.hearthng.launcher"'), true, 'home-app command carries the app id');
eq(homeSettingCommand('com.webos.app.home').includes('setSystemSettings'), true, 'home-app command uses setSystemSettings');
let rejected = 0; for (const bad of ["x'; reboot; '", 'a b', '', 'a"b', '$(id)']) { try { homeSettingCommand(bad); } catch { rejected++; } }
eq(rejected, 5, 'anything that is not a plain app id is refused (no shell injection)');
eq(parseHomeApp('{\n "returnValue": true,\n "settings": {"defaultApps": {"home": "com.hearthng.launcher"}}\n}'), 'com.hearthng.launcher', 'reads the home app out of the reply');
eq(parseHomeApp('{"returnValue": false}'), null, 'no home app in the reply -> null');
// webOS 25 (OLED65M59LA, webOS 10.3.0, 2026-11-03): defaultApps has a second entry, and setSystemSettings replaces the object
const tvReply = '{\n    "subscribed": false,\n    "category": "general",\n    "method": "getSystemSettings",\n    "returnValue": true,\n    "settings": {\n        "defaultApps": {\n            "home": "com.webos.app.home",\n            "MembershipApp": "com.webos.app.overlaymembership"\n        }\n    }\n}';
const apps = parseDefaultApps(tvReply);
eq(JSON.stringify(apps), '{"home":"com.webos.app.home","MembershipApp":"com.webos.app.overlaymembership"}', 'reads the whole defaultApps object');
eq(homeSettingCommand('com.hearthng.launcher', apps).includes('"defaultApps":{"home":"com.hearthng.launcher","MembershipApp":"com.webos.app.overlaymembership"}'), true, 'the new home keeps the other entry');
eq(JSON.stringify(parseDefaultApps('{"settings":{"defaultApps":{"home":"com.webos.app.home","x y":"a","Bad":"$(id)","n":5}}}')), '{"home":"com.webos.app.home"}', 'entries that are not plain ids are dropped');
eq(homeSettingCommand('com.webos.app.home', {MembershipApp: "x'; reboot; '"}).includes('reboot'), false, 'a bad value in the current object never reaches the command');
eq(parseDefaultApps('{"returnValue": false}'), null, 'no defaultApps in the reply -> null');
eq(homeSettingCommand('com.webos.app.home', null).includes('"defaultApps":{"home":"com.webos.app.home"}'), true, 'nothing read: only home');
for (const p of [home, homeEnd, connect, other, web]) { try { process.kill(p.pid); } catch {} }
process.exit(fail ? 1 : 0);
