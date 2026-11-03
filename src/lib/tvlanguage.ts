// HearthNG: the TV's menu language, for the first start (the interface language then follows it instead of being English).
// The settings service answers it to the app itself; where the app may not ask, the same request goes through the Homebrew service.

import {lunaCall} from './luna';
import {exec} from './apps';
import {menuLocaleOf} from './languages';

const SETTINGS_URI = 'luna://com.webos.settingsservice/getSystemSettings';
const PARAMS = {keys: ['localeInfo']};
export const MENU_LOCALE_COMMAND = `luna-send -n 1 -f ${SETTINGS_URI} '${JSON.stringify(PARAMS)}'`;

const reason = (e: unknown): string => (e instanceof Error ? e.message : String(e));

/** The TV's menu language (e.g. "ru-RU") and the way it was read; rejects with both reasons when neither way answers. */
export function readMenuLocale (): Promise<{locale: string; via: string}> {
	return lunaCall(SETTINGS_URI, PARAMS).then((r) => {
		const locale = menuLocaleOf(r);
		if (!locale) throw new Error('no localeInfo in the answer');
		return {locale, via: 'luna'};
	}).catch((first: unknown) => exec(MENU_LOCALE_COMMAND, 6000).then((out) => {
		const locale = menuLocaleOf(out);
		if (!locale) throw new Error('no localeInfo in the answer');
		return {locale, via: 'luna-send'};
	}).catch((second: unknown) => { throw new Error(`luna: ${reason(first)}; luna-send: ${reason(second)}`); }));
}
