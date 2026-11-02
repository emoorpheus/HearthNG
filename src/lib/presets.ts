// HearthNG: look presets (Settings -> Look -> Preset). One row sets the colours and decorations of the home screen in one go:
// theme, background, icon style, icon outline, names, widget colour, shadow and weight, bottom fade, quiet mode. Sizes and
// places (icon size and gap, name size and font, widget size, place and font, margins, rows) are never changed.
// A look that matches no preset reads "Your own"; leaving it for a preset keeps a copy (UserConfig.presetStash), and stepping
// back to "Your own" brings that copy back. Pure: no TV access.

import {PHOTO_SHOW} from './backgrounds';
import {DEFAULT_CONFIG, PRESET_CLOCK_KEYS, PRESET_KEYS, lookOf, type PresetClockKey, type PresetKey, type PresetLook, type UserConfig} from './storage';
import {td} from '../i18n';

export type PresetId = 'standard' | 'oled' | 'night' | 'minimal' | 'gallery';
export const PRESET_IDS: readonly PresetId[] = ['standard', 'oled', 'night', 'minimal', 'gallery'];
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

/** What each preset changes from Standard (the reasons are in docs/features/look.md). */
const PATCHES: Record<PresetId, Patch> = {
	standard: {},
	// pure black and nothing lit that does not need to be: flat #000 (no photo, no gradient, no fade), grey one-colour icons with no
	// outline (the selected one keeps its ring), names only under the selected icon, a thinner widget without shadow, quiet mode dims more
	oled: {
		theme: 'black', background: 'theme', fadeStrength: 0, iconStyle: 'mono', minimal: false, iconLight: false, iconColor: 'theme',
		tileFrame: false, showLabels: true, labelsOnFocus: true, quietSec: 20, quietDimSec: 20, quietDimLevel: 50, oledShift: true,
		clock: {shadow: false, opacity: 80, weight: 300}
	},
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

/** The full values of a preset. */
export function presetValues (id: PresetId): Values {
	const base = standard();
	const patch = PATCHES[id];
	return {...base, ...patch, clock: {...base.clock, ...(patch.clock || {})}};
}

/** The preset the settings match exactly (the built-in background, no widget ink of a theme), or CUSTOM. */
export function presetOf (c: UserConfig): PresetChoice {
	if (c.wallpaper.mode !== 'gradient' || c.clock.ink) return CUSTOM;
	const own = c as unknown as Record<string, unknown>;
	const ownClock = c.clock as unknown as Record<string, unknown>;
	for (const id of PRESET_IDS) {
		const v = presetValues(id) as unknown as Record<string, unknown> & {clock: Record<string, unknown>};
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

/** The settings after choosing a preset (or CUSTOM: the kept own look). Leaving a look that is not a preset keeps it first. */
export function choosePreset (c: UserConfig, id: PresetChoice): UserConfig {
	if (id === CUSTOM) return c.presetStash ? withLook(c, c.presetStash) : c;
	const stash = presetOf(c) === CUSTOM ? lookOf(c) : c.presetStash;
	const v = presetValues(id);
	const clock = {...c.clock, ...v.clock};
	delete clock.ink;
	return {...c, ...v, clock, wallpaper: {...c.wallpaper, mode: 'gradient', path: '', recursive: false}, presetStash: stash};
}

/** The values the row steps through: "Your own" first while there is one (the current look or a kept one), then the presets. */
export function presetChoices (c: UserConfig): readonly PresetChoice[] {
	return presetOf(c) === CUSTOM || c.presetStash ? [CUSTOM as PresetChoice].concat(PRESET_IDS) : PRESET_IDS;
}

export function presetText (id: PresetChoice): string {
	return td(`preset.${id}`);
}
