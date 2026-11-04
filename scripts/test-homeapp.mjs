// Tests for "Set Hearth as the TV's Home app": reading the TV's replies, the messages, and the start-up check's install
// commands run against a fake TV folder.   Run: npm test
import {build} from 'esbuild';
import {execSync} from 'child_process';
import {existsSync, mkdtempSync, readFileSync, rmSync, lstatSync, readlinkSync} from 'fs';
import {tmpdir} from 'os';

const out = new URL('../node_modules/.cache-homeappcmd-test.mjs', import.meta.url).pathname;
await build({entryPoints: [new URL('../src/lib/homeappcmd.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out, platform: 'node', logLevel: 'error'});
const h = await import(out);
let fail = 0;
const eq = (a, b, m) => { const ok = a === b; if (!ok) fail++; console.log(ok ? 'ok  ' : 'FAIL', m, ok ? '' : `(${a} != ${b})`); };

// ---- the TV's replies (as luna-send prints them on a webOS 4.5 TV, and as a Luna call hands them over) ----
const printed = '{\n    "subscribed": false,\n    "category": "general",\n    "method": "getSystemSettings",\n    "settings": {\n        "defaultApps": {\n            "home": "com.webos.app.fullhome"\n        }\n    },\n    "returnValue": true\n}\n';
eq(h.parseHomeSetting(printed), 'com.webos.app.fullhome', 'the Home app is read from luna-send\'s output');
eq(h.parseHomeSetting({returnValue: true, settings: {defaultApps: {home: 'com.hearthng.launcher'}}}), 'com.hearthng.launcher', 'and from a Luna call\'s reply');
const missing = '{\n    "subscribed": false,\n    "returnValue": false,\n    "errorText": "There is no matched result from DB"\n}\n';
eq(h.parseHomeSetting(missing), '', 'a TV without the setting says so (no matched result): ""');
eq(h.parseHomeSetting({returnValue: true, settings: {}}), '', 'an answer without the setting: ""');
eq(h.parseHomeSetting({returnValue: false, errorText: 'Denied method call'}), null, 'a refusal is no answer: null');
eq(h.parseHomeSetting('garbage'), null, 'output that is not JSON: null');
eq(h.parseHomeSetting(''), null, 'no output: null');
eq(h.parseHomeSetting({returnValue: true, settings: {defaultApps: {home: "x'; reboot"}}}), '', 'a value that is not an app id is never used');
eq(h.isMissing('There is no matched result from DB'), true, 'the "no such setting" reply is recognised');
eq(h.isMissing('Denied method call'), false, 'and a refusal is not taken for it');

// ---- is the app from before still installed? (§10: the original Hearth was the Home app, then uninstalled) ----
eq(h.appStatusCommand('tld.my.customlauncher'), `luna-send -n 1 luna://com.webos.applicationManager/getAppLoadStatus '{"appId":"tld.my.customlauncher"}'`, 'the TV is asked with SAM\'s getAppLoadStatus');
let badIds = 0; for (const bad of ["x'; reboot; '", 'a b', '', '$(id)']) { try { h.appStatusCommand(bad); } catch { badIds++; } }
eq(badIds, 4, 'and only for a plain app id');
eq(h.saysNotInstalled('{"returnValue":true,"exist":false}'), true, 'a clear "exist": false (as webOS 10.3.0 answers for a removed app, 2026-11-04) means not installed');
eq(h.saysNotInstalled('{\n    "returnValue": true,\n    "exist": false\n}'), true, 'also as luna-send -f prints it');
eq(h.saysNotInstalled('{"returnValue":true,"exist":true}'), false, 'an installed app is kept');
eq([h.saysNotInstalled(''), h.saysNotInstalled('{"returnValue":false,"errorText":"Denied"}'), h.saysNotInstalled('garbage "exist":false')].join(), 'false,false,false', 'no answer or a refusal: the app is kept (never a guess)');

// ---- messages ----
eq(h.homeAppMessage('restored', 'com.webos.app.fullhome'), 'Turned off. The Home button opens LG Home again', 'LG\'s overlay is called LG Home');
eq(h.homeAppMessage('restored', 'com.example.home'), 'Turned off. The Home button opens com.example.home again', 'another app is named by its id');
eq(/no Home app setting/.test(h.homeAppMessage('unsupported')), true, 'without the setting, the message says so');
eq(/Nothing was changed/.test(h.homeAppMessage('refused')), true, 'a refusal says nothing was changed');

// ---- the start-up check: install and remove on a fake TV ----
let rejected = 0; for (const bad of ["x'; reboot; '", 'a b', '', '$(id)']) { try { h.guardSteps('#!/bin/sh\n', bad); } catch { rejected++; } }
eq(rejected, 4, 'only a plain app id is ever saved (no shell injection)');
const root = mkdtempSync(tmpdir() + '/homeapp-');
const onTv = (cmd) => cmd.split(h.HOME_APP_DIR).join(root + '/dir').split(h.HOME_APP_LINK).join(root + '/46-launcher-homeapp');
const guardSh = readFileSync(new URL('../src/homeapp/guard.sh', import.meta.url).pathname, 'utf8');
const steps = h.guardSteps(guardSh, 'com.webos.app.fullhome');
eq(steps[steps.length - 1].name, 'add the start-up link', 'the start-up link is added last, so a half-written check never runs');
for (const step of steps) execSync(onTv(step.command), {shell: '/bin/sh'});
eq(readFileSync(root + '/dir/guard.sh', 'utf8'), guardSh, 'the check is written to the TV as it is');
eq(readFileSync(root + '/dir/previous', 'utf8').trim(), 'com.webos.app.fullhome', 'with the app from before');
eq(lstatSync(root + '/46-launcher-homeapp').isSymbolicLink() && readlinkSync(root + '/46-launcher-homeapp'), root + '/dir/guard.sh', 'and linked from the startup folder');
eq(h.parseSaved(execSync(onTv(h.SAVED_COMMAND), {shell: '/bin/sh'}).toString()), 'com.webos.app.fullhome', 'the saved app can be read back');
eq(execSync(onTv(h.REMOVE_GUARD_COMMAND), {shell: '/bin/sh'}).toString().trim(), 'removed', 'removing it reports itself done');
eq(existsSync(root + '/dir') || existsSync(root + '/46-launcher-homeapp'), false, 'and leaves nothing behind');
eq(h.parseSaved(execSync(onTv(h.SAVED_COMMAND), {shell: '/bin/sh'}).toString()), '', 'nothing saved: ""');
rmSync(root, {recursive: true, force: true});

// ---- switching it on and off on a simulated TV (homeapp.ts with the TV's shell replaced): §10, an app from before that
// is not installed any more is not given back to the Home button ----
const flowOut = new URL('../node_modules/.cache-homeapp-flow-test.mjs', import.meta.url).pathname;
await build({
  entryPoints: [new URL('../src/lib/homeapp.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: flowOut, platform: 'node', logLevel: 'error',
  plugins: [{name: 'stub-tv', setup(b) {
    b.onResolve({filter: /\?raw$/}, () => ({path: 'raw-stub', namespace: 'stub'}));
    b.onResolve({filter: /^\.\/(apps|luna|launch|log)$/}, (a) => ({path: a.path.slice(2) + '-stub', namespace: 'stub'}));
    b.onLoad({filter: /.*/, namespace: 'stub'}, (a) => ({loader: 'js', contents: ({
      'raw-stub': 'export default "#!/bin/sh\\n";',
      'apps-stub': 'export const exec = (cmd) => globalThis.tvExec(cmd);',
      'luna-stub': 'export const isWebOS = () => true; export const lunaCall = () => Promise.reject(new Error("no luna here"));',
      'launch-stub': 'export const appExists = () => Promise.resolve(false);',
      'log-stub': 'export const log = () => undefined;'
    })[a.path]}));
  }}]
});
const flow = await import(flowOut);
const tv = {apps: {home: 'com.webos.app.home', MembershipApp: 'com.webos.app.overlaymembership'}, installed: new Set(['com.webos.app.home', 'com.hearthng.launcher']), writes: []};
globalThis.tvExec = (cmd) => {
  if (/getAppLoadStatus/.test(cmd)) { const id = /"appId":"([^"]+)"/.exec(cmd)[1]; return Promise.resolve(JSON.stringify({returnValue: true, exist: tv.installed.has(id)})); }
  if (/getSystemSettings/.test(cmd)) return Promise.resolve(JSON.stringify({returnValue: true, settings: {defaultApps: {...tv.apps}}}));
  const set = /setSystemSettings '(.*)'$/.exec(cmd);
  if (set) { tv.apps = JSON.parse(set[1]).settings.defaultApps; tv.writes.push(tv.apps.home); return Promise.resolve('{"returnValue":true}'); }
  return Promise.resolve('');                       // the start-up check's files, cat of a saved value: nothing there
};
// the original Hearth's start-up script had made it the Home app, then Hearth was uninstalled
tv.apps = {home: 'tld.my.customlauncher', MembershipApp: 'com.webos.app.overlaymembership'};
let r = await flow.setHearthAsHome();
eq([r.result, r.detail, tv.apps.home].join(' '), 'applied com.webos.app.home com.hearthng.launcher', 'on: the Home app named a removed app (the original Hearth): LG Home is kept as the one to put back');
eq(tv.apps.MembershipApp, 'com.webos.app.overlaymembership', 'and the other defaultApps entries stay');
r = await flow.restoreHomeApp('tld.my.customlauncher');
eq([r.result, r.detail, tv.apps.home].join(' '), 'restored com.webos.app.home com.webos.app.home', 'off with a saved app that is gone (an older setting): LG Home, not the removed app');
tv.installed.add('com.example.home');
tv.apps = {home: 'com.example.home'};
r = await flow.setHearthAsHome();
eq(r.detail, 'com.example.home', 'an installed app from before is kept');
r = await flow.restoreHomeApp(r.detail);
eq([r.result, tv.apps.home].join(' '), 'restored com.example.home', 'and given back when it is switched off');
tv.apps = {home: 'com.hearthng.launcher'};
const silent = globalThis.tvExec;
globalThis.tvExec = (cmd) => (/getAppLoadStatus/.test(cmd) ? Promise.reject(new Error('no answer')) : silent(cmd));
r = await flow.restoreHomeApp('com.example.gone');
eq(tv.apps.home, 'com.example.gone', 'the TV does not answer whether it is installed: the saved app is used as before (no guess)');
process.exit(fail ? 1 : 0);
