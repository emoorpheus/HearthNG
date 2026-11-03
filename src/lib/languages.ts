/** Hearth's interface languages (T0, T4). The saved id is `UserConfig.language`; an unknown id reads as English. */
export interface Language { id: string; name: string }

import {BUNDLED_LANGUAGES} from '../config/bundledlanguages';

/** English plus the languages shipped inside the app (T4; accepted packs from docs/languages/packs, loaded only when picked). */
export const LANGUAGES: readonly Language[] = [{id: 'en', name: 'English'} as Language].concat(BUNDLED_LANGUAGES.map(({id, name}) => ({id, name})));
export const isBundledLanguage = (id: string): boolean => id !== 'en' && languageOf(id).id === id;

export const DEFAULT_LANGUAGE = 'en';

/** HearthNG: the interface language for the TV's menu language (its locale, e.g. "ru-RU"): the language part when it is one of
 *  the languages above, otherwise English. Pure. */
export function languageFromLocale (locale: unknown): string {
	if (typeof locale !== 'string') return DEFAULT_LANGUAGE;
	const code = locale.trim().toLowerCase().split(/[-_]/)[0];
	return code && LANGUAGES.some((l) => l.id === code) ? code : DEFAULT_LANGUAGE;
}

/** The TV's menu language out of a settingsservice getSystemSettings {keys: ['localeInfo']} reply (settings.localeInfo.locales.UI,
 *  "ru-RU" on OLED65M59LA, webOS 10.3.0), or null. Accepts the reply as an object or as the text luna-send prints. */
export function menuLocaleOf (reply: unknown): string | null {
	let r: unknown = reply;
	if (typeof r === 'string') { try { r = JSON.parse(r); } catch { return null; } }
	const settings = r && typeof r === 'object' ? (r as {settings?: {localeInfo?: {locales?: {UI?: unknown}}}}).settings : undefined;
	const ui = settings && settings.localeInfo && settings.localeInfo.locales ? settings.localeInfo.locales.UI : undefined;
	return typeof ui === 'string' && /^[A-Za-z]{2,3}([-_][A-Za-z0-9]+)*$/.test(ui) ? ui : null;
}

/** T2b: the id saved while the user's own language file is the language in use (the name shown comes from `lib/langpack.ts`). */
export const PACK_ID = 'pack';
export const languageId = (id: string): string => (id === PACK_ID ? PACK_ID : languageOf(id).id);

export function languageOf (id: string): Language {
	for (let i = 0; i < LANGUAGES.length; i++) if (LANGUAGES[i].id === id) return LANGUAGES[i];
	return LANGUAGES[0];
}

/** User 2026-11-01: every bundled language except English is shown on the language row with this suffix (the packs are machine-made; own files are not marked). */
export const MACHINE_SUFFIX = ' (machine translated)';
/** 2.0.2 (user 2026-11-02): packs written or reviewed by a native speaker (fr #33, pl #35) carry no suffix. */
export const HUMAN_LANGUAGES: readonly string[] = ['fr', 'pl'];
export const languageLabel = (id: string): string => { const l = languageOf(id); return l.id === 'en' || HUMAN_LANGUAGES.indexOf(l.id) >= 0 ? l.name : l.name + MACHINE_SUFFIX; };
