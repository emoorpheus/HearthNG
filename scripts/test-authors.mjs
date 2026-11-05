// Authorship in the files that name a maker: every place says emoorpheus for HearthNG, and the notices the MIT licence
// requires (webos-launcher, Hearth by rudra-avatar) stay. src/config/version.ts holds the names the app shows.
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..') + '/';
const read = (f) => readFileSync(root + f, 'utf8');
const json = (f) => JSON.parse(read(f));
let fail = 0;
const eq = (got, want, name) => { const ok = JSON.stringify(got) === JSON.stringify(want); console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : `\n   got  ${JSON.stringify(got)}\n   want ${JSON.stringify(want)}`)); if (!ok) fail++; };
const has = (text, s) => text.indexOf(s) !== -1;

const ng = (read('src/config/version.ts').match(/NG_AUTHOR = '([^']+)'/) || [])[1];
const up = (read('src/config/version.ts').match(/UPSTREAM_AUTHOR = '([^']+)'/) || [])[1];
eq([ng, up], ['emoorpheus', 'rudra-avatar'], 'version.ts names emoorpheus (HearthNG) and rudra-avatar (Hearth)');
eq(json('public/appinfo.json').vendor, ng, 'the launcher\'s appinfo.json vendor is the HearthNG author');
eq(json('toast/appinfo.json').vendor, ng, 'the notification app\'s appinfo.json vendor is the HearthNG author');
eq(json('package.json').author, ng, 'package.json author is the HearthNG author');
eq(json('services/com.hearthng.launcher.ssap/package.json').author, ng, 'the service\'s package.json author is the HearthNG author');

const lic = read('LICENSE');
eq(has(lic, 'Copyright (c) 2026 ' + ng + ' (changes in the HearthNG fork)'), true, 'LICENSE: copyright line for HearthNG\'s changes names the author');
eq(has(lic, 'HearthNG contributors'), false, 'LICENSE: no anonymous "HearthNG contributors" line left');
eq(has(lic, 'Copyright (c) 2026 webos-launcher contributors'), true, 'LICENSE keeps the webos-launcher notice (MIT: the notice stays in copies)');
eq(has(lic, 'Copyright (c) 2026 ' + up + ' (changes in this fork)'), true, 'LICENSE keeps the Hearth (rudra-avatar) notice');

const tpn = read('THIRD_PARTY_NOTICES.md');
eq(has(tpn, '[Hearth for WebOS](https://github.com/rudra-avatar/Hearth)'), true, 'THIRD_PARTY_NOTICES names Hearth for WebOS with its link');
eq(has(tpn, 'partridgeworks/webos-launcher'), true, 'THIRD_PARTY_NOTICES still names webos-launcher');

const readme = read('README.md');
eq(has(readme, '- **HearthNG**: ' + ng + '.'), true, 'README Authors names the HearthNG author');
eq(has(readme, 'https://github.com/rudra-avatar/Hearth'), true, 'README links the original Hearth');

console.log(fail ? `\n${fail} FAILED` : '\nall ok');
process.exit(fail ? 1 : 0);
