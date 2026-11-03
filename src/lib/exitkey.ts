// A held Back: the TV turns a Back press held for 1 s into Exit, and Exit closes the app in front unless the app's
// window says that it takes the key itself (window property _WEBOS_ACCESS_POLICY_KEYS_EXIT = "true"; read in the
// compositor of webOS 10.3.0, KeyFilters/systemUi.js and preProcess.js). A home screen must not be closed that way,
// so the launcher takes the key. It does nothing with it.

import {KEY} from '../config/constants';

interface WebOSSystemWindow {
	setWindowProperty? (name: string, value: string): void;
}

export const EXIT_PROPERTY = '_WEBOS_ACCESS_POLICY_KEYS_EXIT';

/** Ask the TV to give the Exit key to the launcher instead of closing it. Returns a line for the log. */
export function keepExitKey (sys: WebOSSystemWindow | undefined = (window.webOSSystem || window.PalmSystem) as WebOSSystemWindow | undefined): string {
	if (!sys || typeof sys.setWindowProperty !== 'function') return 'exit key: setWindowProperty is not there, a held Back may close the launcher';
	try {
		sys.setWindowProperty(EXIT_PROPERTY, 'true');
		return 'exit key: asked the TV to give it to the launcher';
	} catch (e) {
		return `exit key: setWindowProperty failed (${e instanceof Error ? e.message : String(e)})`;
	}
}

const KNOWN = new Set<number>(Object.values(KEY));
/** At most this many other key codes are logged per run. */
export const OTHER_KEYS_LOGGED = 6;

/** Log the first few key codes the launcher gets that it has no use for (once each), so the code of Exit can be
 *  read from the helper log after a held Back. Returns an unsubscribe function. */
export function logOtherKeys (report: (text: string) => void): () => void {
	const seen = new Set<number>();
	const onKey = (e: KeyboardEvent) => {
		if (KNOWN.has(e.keyCode) || seen.has(e.keyCode) || seen.size >= OTHER_KEYS_LOGGED) return;
		seen.add(e.keyCode);
		report(`keys: code ${e.keyCode} (${e.key || '?'}) reached the launcher`);
	};
	window.addEventListener('keydown', onKey, true);
	return () => window.removeEventListener('keydown', onKey, true);
}
