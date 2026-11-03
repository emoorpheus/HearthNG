// HearthNG: look presets (Settings -> Look -> Preset). One row sets the colours and decorations of the home screen in one go:
// theme, background, icon style, icon outline, names, widget colour, shadow and weight, bottom fade, quiet mode. Sizes and
// places (icon size and gap, name size and font, widget size, place and font, margins, rows) are not changed, except by
// OLED (minimal): it also sets four settings outside the look (EXTRAS: icon size, the widget, the weather, Hearth's screen
// saver), notes what they were (UserConfig.presetExtras) and puts back each one not changed since when it is left.
// A look that matches no preset reads "Your own"; leaving it for a preset keeps a copy (UserConfig.presetStash), and stepping
// back to "Your own" brings that copy back. Pure: no TV access (app.tsx turns the screen saver off or on through the TV).

import {PHOTO_SHOW} from './backgrounds';
import {DEFAULT_CONFIG, PRESET_CLOCK_KEYS, PRESET_KEYS, lookOf, type PresetClockKey, type PresetExtras, type PresetKey, type PresetLook, type UserConfig} from './storage';
import {td} from '../i18n';

export type PresetId = 'standard' | 'oled' | 'oledMinimal' | 'night' | 'minimal' | 'gallery';
export const PRESET_IDS: readonly PresetId[] = ['standard', 'oled', 'oledMinimal', 'night', 'minimal', 'gallery'];
/** the row's value for a look that is not a preset */
export const CUSTOM = 'custom';
export type PresetChoice = PresetId | typeof CUSTOM;

type Values = Pick<UserConfig, PresetKey> & {clock: Pick<UserConfig['clock'], PresetClockKey>};
type Patch = Partial<Pick<UserConfig, PresetKey>> & {clock?: Partial<Pick<UserConfig['clock'], PresetClockKey>>};

/** Standard = the values of a fresh install, so the defaults and "Reset visual settings" read Standard. */
function standard (): Values {
	const d = lookOf(DEFAULT_CONFIG) as unknown as Record<string, unknown>;
	const out: Record<string, unknown> = {};
	PRESET_KEYS.forEach((k) => { out[k] = d[k]; });
	const clock: Record<string, unknown> = {};
	PRESET_CLOCK_KEYS.forEach((k) => { clock[k] = DEFAULT_CONFIG.clock[k]; });
	out.clock = clock;
	return out as unknown as Values;
}

// pure black and nothing lit that does not need to be: flat #000 (no photo, no gradient, no fade), grey one-colour icons with no
// outline (the selected one keeps its ring), names only under the selected icon, a thinner widget without shadow, quiet mode dims more
const OLED: Patch = {
	theme: 'black', background: 'theme', fadeStrength: 0, iconStyle: 'mono', minimal: false, iconLight: false, iconColor: 'theme',
	tileFrame: false, showLabels: true, labelsOnFocus: true, quietSec: 20, quietDimSec: 20, quietDimLevel: 50, oledShift: true,
	clock: {shadow: false, opacity: 80, weight: 300}
};

/** What each preset changes from Standard (the reasons are in docs/features/look.md). */
const PATCHES: Record<PresetId, Patch> = {
	standard: {},
	oled: OLED,
	// the owner's OLED (2026-11-03): the OLED look; smaller icons and no widget are in EXTRAS
	oledMinimal: OLED,
	// for a dark room: like OLED, but dimmer: Soft mono icons at 70 %, a grey widget at 60 %, quiet mode sooner and darker
	night: {
		theme: 'black', background: 'theme', fadeStrength: 0, iconStyle: 'soft', minimal: false, iconLight: false, iconColor: 'theme', iconOpacity: 70,
		tileFrame: false, showLabels: true, labelsOnFocus: true, labelColor: 'grey', quietSec: 10, quietDimSec: 10, quietDimLevel: 70, oledShift: true,
		clock: {color: 'grey', shadow: false, opacity: 60, weight: 300}
	},
	// the theme's calm graphite background, the original artwork with no borders (Hearth's Minimalist), no names, no fade, no shadow
	minimal: {
		theme: 'graphite', background: 'theme', fadeStrength: 0, iconStyle: 'original', minimal: true, showLabels: false, labelsOnFocus: false,
		clock: {shadow: false, weight: 300}
	},
	// the built-in photos as a slideshow; the apps hide after 10 seconds without a key, the screen is not dimmed
	gallery: {
		theme: 'black', background: PHOTO_SHOW, iconStyle: 'original', minimal: false, quietSec: 10, quietDimSec: 0,
		clock: {shadow: true, shadowStrength: 100, weight: 500}
	}
};

/** HearthNG: what a preset sets outside the look. OLED (minimal): icons at 70 %, no widget, no weather, only the TV's own screen
 *  saver (Hearth's is off). The other presets leave these four alone. */
const EXTRAS: Partial<Record<PresetId, PresetExtras>> = {
	oledMinimal: {iconScale: 70, clockShow: false, weatherOn: false, screensaver: false}
};
const EXTRA_KEYS = ['iconScale', 'clockShow', 'weatherOn', 'screensaver'] as const;
/** the presets with extras are matched first: OLED (minimal) is OLED plus extras, so the same look reads OLED (minimal) when they match */
const MATCH_ORDER: readonly PresetId[] = PRESET_IDS.filter((id) => EXTRAS[id]).concat(PRESET_IDS.filter((id) => !EXTRAS[id]));

/** The four settings outside the look, as a preset sees them. */
export function extrasOf (c: UserConfig): PresetExtras {
	return {iconScale: c.iconScale, clockShow: c.clock.show, weatherOn: c.weather.on, screensaver: c.screensaver};
}

function withExtras (c: UserConfig, e: PresetExtras): UserConfig {
	return {...c, iconScale: e.iconScale, screensaver: e.screensaver, clock: {...c.clock, show: e.clockShow}, weather: {...c.weather, on: e.weatherOn && c.weather.city !== null}};
}

/** The settings with what a preset set outside the look put back: each one that still has the preset's value gets its earlier
 *  value again; one changed since stays as it is. */
function givenBack (c: UserConfig): UserConfig {
	const k = c.presetExtras;
	if (!k) return c;
	const now = extrasOf(c) as unknown as Record<string, unknown>;
	const was = k.was as unknown as Record<string, unknown>;
	const set = k.set as unknown as Record<string, unknown>;
	const out: Record<string, unknown> = {};
	EXTRA_KEYS.forEach((key) => { out[key] = now[key] === set[key] ? was[key] : now[key]; });
	return {...withExtras(c, out as unknown as PresetExtras), presetExtras: null};
}

/** The full values of a preset. */
export function presetValues (id: PresetId): Values {
	const base = standard();
	const patch = PATCHES[id];
	return {...base, ...patch, clock: {...base.clock, ...(patch.clock || {})}};
}

/** The preset the settings match exactly (the built-in background, no widget ink of a theme; for a preset with extras, those
 *  too), or CUSTOM. */
export function presetOf (c: UserConfig): PresetChoice {
	if (c.wallpaper.mode !== 'gradient' || c.clock.ink) return CUSTOM;
	const own = c as unknown as Record<string, unknown>;
	const ownClock = c.clock as unknown as Record<string, unknown>;
	const ownExtras = extrasOf(c) as unknown as Record<string, unknown>;
	for (const id of MATCH_ORDER) {
		const v = presetValues(id) as unknown as Record<string, unknown> & {clock: Record<string, unknown>};
		const e = EXTRAS[id] as unknown as Record<string, unknown> | undefined;
		if (e && !EXTRA_KEYS.every((k) => ownExtras[k] === e[k])) continue;
		if (PRESET_KEYS.every((k) => own[k] === v[k]) && PRESET_CLOCK_KEYS.every((k) => ownClock[k] === v.clock[k])) return id;
	}
	return CUSTOM;
}

/** The settings with a kept look put back (the kept copy is used up). */
function withLook (c: UserConfig, look: PresetLook): UserConfig {
	const out = {...c, ...(look as unknown as Partial<UserConfig>), wallpaper: {...look.wallpaper}, presetStash: null} as UserConfig;
	const clock = {...c.clock, ...look.clock};
	if (!look.clock.ink) delete clock.ink;
	return {...out, clock};
}

/** The settings after choosing a preset (or CUSTOM: the kept own look). Leaving a look that is not a preset keeps it first.
 *  A preset with extras sets them and notes what they were (the first time); any other choice puts them back (givenBack). */
export function choosePreset (c: UserConfig, id: PresetChoice): UserConfig {
	if (id === CUSTOM) return givenBack(c.presetStash ? withLook(c, c.presetStash) : c);
	const stash = presetOf(c) === CUSTOM ? lookOf(c) : c.presetStash;
	const v = presetValues(id);
	const clock = {...c.clock, ...v.clock};
	delete clock.ink;
	const out: UserConfig = {...c, ...v, clock, wallpaper: {...c.wallpaper, mode: 'gradient', path: '', recursive: false}, presetStash: stash};
	const extras = EXTRAS[id];
	if (!extras) return givenBack(out);
	return {...withExtras(out, extras), presetExtras: {was: c.presetExtras ? c.presetExtras.was : extrasOf(c), set: {...extras}}};
}

/** The values the row steps through: "Your own" first while there is one (the current look or a kept one), then the presets. */
export function presetChoices (c: UserConfig): readonly PresetChoice[] {
	return presetOf(c) === CUSTOM || c.presetStash ? [CUSTOM as PresetChoice].concat(PRESET_IDS) : PRESET_IDS;
}

export function presetText (id: PresetChoice): string {
	return td(`preset.${id}`);
}
