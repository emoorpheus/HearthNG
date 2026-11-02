// Tests for the look presets (Settings -> Look -> Preset): src/lib/presets.ts through the Settings model (prefs.ts) and loadConfig (storage.ts).
// Run: node scripts/test-presets.mjs (part of npm test)
import {build} from 'esbuild';
import {writeFileSync} from 'fs';

const stubApps = {name: 'stub-apps', setup (b) {
	b.onResolve({filter: /\.\/apps$/}, () => ({path: 'apps-stub', namespace: 'stub'}));
	b.onLoad({filter: /.*/, namespace: 'stub'}, () => ({contents: 'export const exec = () => Promise.resolve(""); export const shellQuote = (v) => v;', loader: 'js'}));
}};
const bundle = async (src, name) => {
	const out = new URL(`../node_modules/.cache-presets-${name}.mjs`, import.meta.url).pathname;
	const r = await build({entryPoints: [new URL(src, import.meta.url).pathname], bundle: true, format: 'esm', write: false, platform: 'node', logLevel: 'error', plugins: [stubApps]});
	writeFileSync(out, r.outputFiles[0].text);
	return out;
};

const store = {};
globalThis.localStorage = {getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; }};

const p = await import(await bundle('../src/lib/prefs.ts', 'prefs'));
const s = await import(await bundle('../src/lib/storage.ts', 'storage'));
const ps = await import(await bundle('../src/lib/presets.ts', 'presets'));
let fail = 0;
const eq = (a, b, m) => { const ok = JSON.stringify(a) === JSON.stringify(b); if (!ok) { fail++; console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); } else console.log('ok  ', m); };
const row = (c, id) => p.optionsFor('look', c).filter((o) => o.id === id)[0];
const text = (c) => { const r = row(c, 'preset'); return r ? r.valueText : '(no row)'; };
const press = (c, k, n = 1) => { let x = c; for (let i = 0; i < n; i++) x = p.applyPref(x, 'preset', k); return x; };

// ---- 1. the row: first on the Look tab, a stepper, and a fresh install reads "Standard" ----
const d = {...s.DEFAULT_CONFIG};
const look = p.optionsFor('look', d);
eq(look.length > 0 && look[0].id, 'preset', 'Preset is the first row of the Look tab (always shown, no group)');
eq(!!(row(d, 'preset') && row(d, 'preset').stepper), true, 'Preset is a stepper (← → and OK step the presets)');
eq(text(d), 'Standard', 'a fresh install reads Standard (the defaults are the Standard preset)');
eq(text(p.resetLook({...d, theme: 'teal', iconStyle: 'mono'})), 'Standard', 'after Reset visual settings it reads Standard again');
eq(text({...d, iconScale: 120, iconGap: 150, labelSize: 120, clock: {...d.clock, size: 200, top: 40}}), 'Standard', 'sizes and positions are not part of a preset: Standard still');
eq(text({...d, theme: 'teal'}), 'Your own', 'a look that matches no preset reads Your own');


// ---- 2. choosing a preset: OLED is one step right of Standard ----
const photo = {...d, wallpaper: {...d.wallpaper, mode: 'image', path: '/tmp/usb/fish.jpg'}, iconScale: 120, labelSize: 120, clock: {...d.clock, size: 200, ink: '#123456', color: 'theme'}};
const o = press(ps.choosePreset(photo, 'standard'), 'right');
eq(text(o), 'OLED', '→ from Standard: OLED');
eq([o.theme, o.background, o.wallpaper.mode, o.wallpaper.path, o.fadeStrength], ['black', 'theme', 'gradient', '', 0], 'OLED: OLED black theme, the theme\'s own background (flat #000), no picture, no bottom fade');
eq([o.iconStyle, o.minimal, o.iconLight, o.tileFrame], ['mono', false, false, false], 'OLED: one-colour icons on the black tile, no outline round them');
eq([o.showLabels, o.labelsOnFocus], [true, true], 'OLED: names only under the selected icon');
eq([o.clock.shadow, o.clock.opacity, o.clock.weight, 'ink' in o.clock], [false, 80, 300, false], 'OLED: thinner widget without shadow at 80 %, a theme\'s widget ink is dropped');
eq([o.quietSec, o.quietDimSec, o.quietDimLevel, o.oledShift], [20, 20, 50, true], 'OLED: quiet mode hides the apps after 20 s, dims 50 % after 20 s more; OLED shift on');
eq([o.iconScale, o.labelSize, o.clock.size, o.clock.align, o.clock.top], [120, 120, 200, photo.clock.align, photo.clock.top], 'OLED: sizes and places are left alone');
eq(press(o, 'right') && text(press(o, 'right')), 'Night', '→ from OLED: Night');
eq(text(press(o, 'right', 3)), 'Gallery', '→ three times from OLED: Gallery (the last one)');
eq(text(press(o, 'right', 9)), 'Gallery', '→ stops at the last preset');
eq(text(press(press(d, 'right', 4), 'ok')), 'Standard', 'OK wraps round from Gallery to Standard (no own look kept)');
eq(text(press(press(o, 'right', 3), 'ok')), 'Your own', 'with an own look kept (the photo look above), OK wraps round from Gallery to Your own');
const n = press(o, 'right');
eq([n.iconStyle, n.iconOpacity, n.labelColor, n.clock.color, n.clock.opacity, n.quietSec, n.quietDimLevel], ['soft', 70, 'grey', 'grey', 60, 10, 70], 'Night: Soft mono at 70 %, grey names and widget at 60 %, quiet after 10 s, 70 % darker');
const m = press(o, 'right', 2);
eq([m.theme, m.background, m.iconStyle, m.minimal, m.showLabels], ['graphite', 'theme', 'original', true, false], 'Minimal: graphite background, original artwork without borders, no names');
const g = press(o, 'right', 3);
eq([g.background, g.wallpaper.mode, g.iconStyle, g.quietSec, g.quietDimSec], ['photo-show', 'gradient', 'original', 10, 0], 'Gallery: the built-in photos as a slideshow, apps hide after 10 s, no dimming');

// every preset's values are values the Settings rows can show (no hidden or out-of-range value)
const presets = ['standard', 'oled', 'night', 'minimal', 'gallery'];
for (const id of presets) {
	const c = ps.choosePreset(d, id);
	const inRange = ['wallpaperOpacity', 'fadeStrength', 'fadeHeight', 'iconOpacity', 'quietSec', 'quietDimSec', 'quietDimLevel'].every((k) => s.rangeValues(k).indexOf(c[k]) !== -1)
		&& s.rangeValues('clockOpacity').indexOf(c.clock.opacity) !== -1 && s.rangeValues('clockShadow').indexOf(c.clock.shadowStrength) !== -1;
	eq(inRange, true, `${id}: every number is on its row's scale`);
	eq(s.LABEL_WEIGHTS.indexOf(c.labelWeight) !== -1 && [200, 300, 400, 500, 600, 700].indexOf(c.clock.weight) !== -1, true, `${id}: name and widget weights are choices of their rows`);
	eq(c.theme === 'black' && c.iconStyle === 'accent', false, `${id}: no Accent mono on OLED black (not offered there)`);
	store['customlauncher-config-v1'] = JSON.stringify(c);
	eq(text(s.loadConfig()), text(c), `${id}: saved and read back, it is still ${text(c)}`);
}

// ---- 3. your own look is kept and comes back ----
const own = {...d, theme: 'teal', iconStyle: 'gradient', wallpaper: {...d.wallpaper, mode: 'folder', path: '/tmp/usb/Photos', recursive: true}, clock: {...d.clock, color: 'theme', ink: '#ABCDEF', shadow: false}};
eq(text(own), 'Your own', 'a look of your own reads Your own');
const toStd = press(own, 'right');
eq(text(toStd), 'Standard', '→ from Your own: Standard');
eq(row(toStd, 'preset') && p.optionsFor('look', toStd).length > 0, true, 'the row is still there');
const back = press(toStd, 'left');
eq(text(back), 'Your own', '← from Standard: Your own again (it was kept)');
eq([back.theme, back.iconStyle, back.wallpaper.mode, back.wallpaper.path, back.wallpaper.recursive, back.clock.ink, back.clock.shadow], ['teal', 'gradient', 'folder', '/tmp/usb/Photos', true, '#ABCDEF', false], 'Your own: theme, icons, slideshow folder and the theme\'s widget ink are back');
eq(back.presetStash, null, 'the kept copy is used up once it is back');
eq(text(press(press(own, 'right', 3), 'left', 9)), 'Your own', 'many ← from a preset end on Your own');
const tweaked = {...press(own, 'right', 2), iconScale: 70, iconStyle: 'gradient'};
eq(text(tweaked), 'Your own', 'a preset changed afterwards is a look of your own');
const again = press(press(tweaked, 'right'), 'left');
eq([again.iconStyle, again.theme, again.iconScale], ['gradient', 'black', 70], 'leaving the changed preset keeps the changed look (the newest own look), not the older one');
eq(text(ps.choosePreset(d, 'custom')), 'Standard', 'Your own without a kept look changes nothing');

// ---- 4. the two new rows: icon outline and names under the selected icon only ----
const all = p.optionsFor('look', d);
eq(!!all.filter((r) => r.id === 'tileFrame')[0], true, 'Look has an Icon outline row');
eq(!!all.filter((r) => r.id === 'labelsOnFocus')[0], true, 'Look has a Name only under the selected icon row');
eq(p.applyPref(d, 'tileFrame', 'ok').tileFrame, false, 'OK turns the outline off');
eq(p.applyPref(d, 'tileFrame', 'left').tileFrame, true, '← → leave the switch alone');
eq(p.applyPref(d, 'labelsOnFocus', 'ok').labelsOnFocus, true, 'OK turns names-only-when-selected on');
eq(!!p.optionsFor('look', {...d, showLabels: false}).filter((r) => r.id === 'labelsOnFocus')[0], false, 'hidden while app names are off');
const grouped = p.optionsFor('look', d, undefined, 'Icons').map((r) => r.id);
eq(grouped.indexOf('tileFrame') !== -1, true, 'the outline row sits in the Icons group');
eq(p.optionsFor('look', d, undefined, 'Labels').map((r) => r.id).indexOf('labelsOnFocus') !== -1, true, 'the names row sits in the Labels group');
const rl = p.resetLook({...d, tileFrame: false, labelsOnFocus: true});
eq([rl.tileFrame, rl.labelsOnFocus], [true, false], 'Reset visual settings puts both back (outline on, all names)');

// ---- 5. reading saved settings ----
store['customlauncher-config-v1'] = JSON.stringify({defaultsV: 1});
const fresh = s.loadConfig();
eq([fresh.tileFrame, fresh.labelsOnFocus, fresh.presetStash], [true, false, null], 'settings saved before these rows: outline on, all names, no kept look');
store['customlauncher-config-v1'] = JSON.stringify({defaultsV: 1, tileFrame: false, labelsOnFocus: true});
eq([s.loadConfig().tileFrame, s.loadConfig().labelsOnFocus], [false, true], 'both switches are read back');
store['customlauncher-config-v1'] = JSON.stringify({...toStd});
const rb = s.loadConfig();
eq([rb.presetStash && rb.presetStash.theme, rb.presetStash && rb.presetStash.wallpaper.path, rb.presetStash && rb.presetStash.clock.ink], ['teal', '/tmp/usb/Photos', '#ABCDEF'], 'the kept own look is saved and read back');
eq(text(press(rb, 'left')), 'Your own', 'and still comes back after a restart');
store['customlauncher-config-v1'] = JSON.stringify({defaultsV: 1, presetStash: 'junk'});
eq(s.loadConfig().presetStash, null, 'a broken kept look is dropped');
store['customlauncher-config-v1'] = JSON.stringify({defaultsV: 1, theme: 'grey', presetStash: {theme: 'neon', iconOpacity: 7, quietSec: 999, wallpaper: {mode: 'folder', path: ''}, clock: {weight: 1, color: 'x'}}});
const bad = s.loadConfig().presetStash;
eq([bad.theme, bad.iconOpacity, bad.quietSec, bad.wallpaper.mode, bad.clock.weight, bad.clock.color], ['black', 30, 60, 'gradient', 400, 'white'], 'wrong values in a kept look fall back by the same rules as saved settings');

if (fail) { console.log(`\n${fail} FAILED`); process.exit(1); }
console.log('\nall presets tests passed');
