// Tests for the first start (src/lib/languages.ts languageFromLocale/menuLocaleOf, src/lib/tvlanguage.ts, FIRST_START and the
// fresh-install values in src/lib/storage.ts).   Run: npm test
import {build} from 'esbuild';
import {writeFileSync} from 'fs';
let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };
const bundle = async (entry, name, stub) => {
	const r = await build({entryPoints: [new URL(entry, import.meta.url).pathname], bundle: true, format: 'esm', write: false, platform: 'node', logLevel: 'error',
		plugins: stub ? [stub] : []});
	const out = new URL(`../node_modules/.cache-${name}-test.mjs`, import.meta.url).pathname;
	writeFileSync(out, r.outputFiles[0].text);
	return out;
};

const L = await import(await bundle('../src/lib/languages.ts', 'tvlanguage-languages'));
eq(L.languageFromLocale('ru-RU'), 'ru', 'ru-RU (the menu language of the test TV) -> ru');
eq(L.languageFromLocale('de-DE'), 'de', 'de-DE -> de');
eq(L.languageFromLocale('en-GB'), 'en', 'en-GB -> en');
eq(L.languageFromLocale('pt-BR'), 'en', 'a language that is not bundled -> English');
eq(L.languageFromLocale('PL_pl'), 'pl', 'upper case and an underscore are read too');
eq(L.languageFromLocale(''), 'en', 'empty -> English');
eq(L.languageFromLocale(undefined), 'en', 'nothing -> English');
eq(L.languageFromLocale('pack'), 'en', 'the id of an own language file is never taken from the TV');

const reply = {returnValue: true, method: 'getSystemSettings', settings: {localeInfo: {keyboards: ['en', 'ru'], locales: {UI: 'ru-RU', FMT: 'en-GB', TV: 'en-GB', AUD: 'ru-RU'}, clock: 'locale', timezone: ''}}};
eq(L.menuLocaleOf(reply), 'ru-RU', 'the UI locale out of the reply seen on OLED65M59LA, webOS 10.3.0 (FMT and TV were en-GB there)');
eq(L.menuLocaleOf(JSON.stringify(reply, null, 4)), 'ru-RU', 'the same out of the text luna-send -f prints');
eq(L.menuLocaleOf({returnValue: false, errorText: 'There is no matched result from DB'}), null, 'the error answer (seen with category option) -> null');
eq(L.menuLocaleOf('not json'), null, 'not JSON -> null');
eq(L.menuLocaleOf({settings: {localeInfo: {locales: {UI: 'ru-RU; rm -rf /'}}}}), null, 'a value that is not a locale -> null');

// tvlanguage.ts: the app's own request first, then the same through the Homebrew service
let execCalls = [];
let execAnswer = () => Promise.resolve(JSON.stringify(reply));
globalThis.__exec = (c, t) => { execCalls.push(c); return execAnswer(); };
const T = await import(await bundle('../src/lib/tvlanguage.ts', 'tvlanguage', {name: 'stub-apps', setup (b) {
	b.onResolve({filter: /\.\/apps$/}, () => ({path: 'apps-stub', namespace: 'stub'}));
	b.onLoad({filter: /.*/, namespace: 'stub'}, () => ({contents: 'export const exec = (c, t) => globalThis.__exec(c, t);', loader: 'js'}));
}}));
eq(T.MENU_LOCALE_COMMAND, `luna-send -n 1 -f luna://com.webos.settingsservice/getSystemSettings '{"keys":["localeInfo"]}'`, 'the command is the one that answered on the TV');
globalThis.window = globalThis;
globalThis.PalmServiceBridge = function () { this.call = () => setTimeout(() => this.onservicecallback(JSON.stringify(reply)), 1); };
eq(await T.readMenuLocale(), {locale: 'ru-RU', via: 'luna'}, 'the app may ask: read without the Homebrew service');
eq(execCalls.length, 0, 'and nothing is run through it');
globalThis.PalmServiceBridge = function () { this.call = () => setTimeout(() => this.onservicecallback(JSON.stringify({returnValue: false, errorText: 'Denied method call'})), 1); };
eq(await T.readMenuLocale(), {locale: 'ru-RU', via: 'luna-send'}, 'the app may not ask: read through the Homebrew service');
execAnswer = () => Promise.reject(new Error('no service'));
eq(await T.readMenuLocale().then(() => 'read', (e) => e.message), 'luna: Denied method call; luna-send: no service', 'neither answers: both reasons');

// storage.ts: FIRST_START is read when the module loads; the fresh-install values
const store = {};
globalThis.localStorage = {getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; }};
const storagePath = await bundle('../src/lib/storage.ts', 'tvlanguage-storage');
const S1 = await import(storagePath + '?fresh');
eq(S1.FIRST_START, true, 'nothing saved: a first start');
eq([S1.loadConfig().language, S1.loadConfig().screensaver, S1.loadConfig().background, S1.loadConfig().theme], ['en', false, 'theme', 'black'],
	'a fresh install: English until the TV answers, HearthNG screen saver off, the black theme\'s own plain black background');
store['customlauncher-config-v1'] = JSON.stringify({defaultsV: 1, language: 'ru', screensaver: true, background: 'photo-17'});
const S2 = await import(storagePath + '?saved');
eq(S2.FIRST_START, false, 'something saved: not a first start');
eq([S2.loadConfig().language, S2.loadConfig().screensaver, S2.loadConfig().background], ['ru', true, 'photo-17'], 'saved settings stay as they are (no reset for anyone who has them)');
process.exit(fail ? 1 : 0);
