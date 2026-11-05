// HearthNG: what runs on the TV names HearthNG's own ID (public/appinfo.json), never the original Hearth's
// (tld.my.customlauncher) by mistake. Code taken over from Hearth carries Hearth's ID; this catches what the rename missed.   Run: npm test
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {join} from 'node:path';
const root = new URL('..', import.meta.url).pathname;
const read = (p) => readFileSync(join(root, p), 'utf8');
let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };
const walk = (dir, out = []) => { readdirSync(join(root, dir)).forEach((n) => { const p = dir + '/' + n; if (statSync(join(root, p)).isDirectory()) walk(p, out); else out.push(p); }); return out; };

const ID = JSON.parse(read('public/appinfo.json')).id;
const ORIGINAL = 'tld.my.customlauncher';
eq(ID, 'com.hearthng.launcher', 'appinfo.json: the HearthNG ID');
eq(/export const APP_ID = '([^']+)'/.exec(read('src/config/constants.ts'))[1], ID, 'constants.ts APP_ID = appinfo.json id');

// the service: its name, the origin it connects with, and every app it asks the TV to open
const svcDirs = readdirSync(join(root, 'services'));
eq(svcDirs, [ID + '.ssap'], 'one service folder, named after the app');
const svc = read('services/' + ID + '.ssap/service.js');
eq((/new Service\('([^']+)'\)/.exec(svc) || [])[1], ID + '.ssap', 'service.js registers under the app\'s service name');
eq((/origin: 'file:\/\/([^']+)'/.exec(svc) || [])[1], ID, 'service.js connects to the TV with the app\'s origin');
eq(svc.indexOf(ORIGINAL), -1, 'service.js never names the original Hearth');
const launches = svc.match(/applicationManager\/launch', \{id: [^}]+\}/g) || [];
eq(launches.length > 0 && launches.every((l) => /\{id: LAUNCHER_ID\}/.test(l)), true, 'service.js opens only LAUNCHER_ID (' + launches.length + ' call(s))');
eq((/var LAUNCHER_ID = '([^']+)'/.exec(svc) || [])[1], ID, 'LAUNCHER_ID in service.js = appinfo.json id');

// the start-up scripts: their default launcher ID
const shells = walk('src').filter((p) => p.endsWith('.sh'));
const defaults = [];
shells.forEach((p) => { const re = /^\s*(APP_ID|LAUNCHER_ID)="\$\{\1:-([^}]*)\}"/gm; let m; while ((m = re.exec(read(p)))) defaults.push(p + ' ' + m[1] + '=' + m[2]); });
eq(defaults.length >= 3, true, 'start-up scripts with a default launcher ID found (' + defaults.length + ')');
eq(defaults.filter((d) => !d.endsWith('=' + ID)), [], 'every default launcher ID in src/**/*.sh is HearthNG\'s');

// the page code: the original Hearth's ID as a quoted value only where HearthNG means the original on purpose
const quoted = new RegExp('[\'"`]' + ORIGINAL.replace(/\./g, '\\.') + '[\'"`]');
const allowed = ['src/lib/homehookcmd.ts', 'src/lib/uninstall.ts'];
const code = walk('src').filter((p) => /\.(ts|tsx)$/.test(p) && quoted.test(read(p)));
eq(code.filter((p) => allowed.indexOf(p) < 0), [], 'the original Hearth\'s ID is a value only in ORIGINAL_HEARTH_ID and the uninstall guard');

console.log(fail ? `\n${fail} FAILED` : '\nall passed');
process.exit(fail ? 1 : 0);
