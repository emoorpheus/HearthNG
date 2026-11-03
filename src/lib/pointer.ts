// Magic Remote pointer control.
//
// The pointer is drawn by the TV's compositor, not the page, so CSS `cursor: none` has
// no effect. webOS gives web apps `webOSSystem.setCursorHidden()` for this: it hides the
// pointer the same way pressing an arrow key does, and the system shows it again when
// the user shakes or moves the remote. So hiding on launch/foreground doesn't stop the
// user switching back to pointer mode.

interface WebOSSystemCursor {
	setCursorHidden? (hidden: boolean): void;
}

declare global {
	interface Window {
		webOSSystem?: WebOSSystemCursor;
		PalmSystem?: WebOSSystemCursor;
	}
}

/** Hide the pointer now. No-op off webOS or on firmware without the API. */
export function hidePointer (): void {
	const sys = window.webOSSystem || window.PalmSystem;
	if (!sys || typeof sys.setCursorHidden !== 'function') return;
	try { sys.setCursorHidden(true); }
	catch { /* best effort */ }
}

/** The TV turns the pointer on by itself about 140–250 ms after the Home button brings the launcher to the front
 *  (seen on OLED65M59LA, webOS 10.3.0: its compositor shows the pointer for that key, and a launch without the key
 *  showed none). One "shown" report this soon after coming to the front is hidden again; later ones are the user's
 *  own (shaking the remote) and are left alone. */
export const AUTO_SHOW_MS = 600;
/** What the pointer did after coming to the front goes to the helper log as one line this long after. */
export const REPORT_AFTER_MS = 3000;

export interface PointerFront {
	/** A front event (launch, relaunch, back from the background), or Exit (a held Back) while in front. */
	front (now: number, why?: string): void;
	/** The TV's report that the pointer appeared or went: `cursorStateChange`, or (`via` 'key') the key codes 1536 and
	 *  1537. Returns true when the pointer should be hidden again. */
	cursor (visible: boolean, now: number, via?: string): boolean;
	/** The line for the log (null when nothing happened). */
	line (): string | null;
}

/** The decisions, kept apart from the TV so they can be tested. */
export function pointerFront (): PointerFront {
	let frontAt = -1;
	let rehidden = false;
	let events: string[] = [];
	let cause = 'coming to the front';
	return {
		front (now, why = 'coming to the front') {
			// visibilitychange and webOSRelaunch can both come for one Home press: the first one counts
			if (frontAt >= 0 && now - frontAt < AUTO_SHOW_MS) return;
			frontAt = now;
			rehidden = false;
			events = [];
			cause = why;
		},
		cursor (visible, now, via = '') {
			if (frontAt < 0) return false;
			const after = now - frontAt;
			if (after > REPORT_AFTER_MS) return false;
			const what = (via ? via + ' ' : '') + (visible ? 'shown' : 'hidden');
			if (visible && !rehidden && after <= AUTO_SHOW_MS) {
				rehidden = true;
				events.push(`${what} ${after} ms - hidden again`);
				return true;
			}
			events.push(`${what} ${after} ms`);
			return false;
		},
		line () { return events.length ? `pointer after ${cause}: ${events.join(', ')}` : null; }
	};
}

/** The key code of Exit. The TV turns Back held for 1 s into it, and turns the pointer on with it, like with Home
 *  (seen on OLED65M59LA, webOS 10.3.0; the launcher takes Exit, see exitkey.ts). */
export const EXIT_KEY_CODE = 1001;
/** The key codes the TV sends to the page in front when the Magic Remote pointer appears and when it goes (LG's own
 *  Settings app on webOS 10.3.0 names them pointerShow 1536 and pointerHide 1537). After a held Back had closed an
 *  app, HearthNG got these two and no `cursorStateChange` (helper log, OLED65M59LA, 2026-11-04), so both count. */
export const POINTER_SHOWN_KEY = 1536;
export const POINTER_HIDDEN_KEY = 1537;

/** Hide the pointer on launch and every time the app comes back to the foreground (including relaunches while
 *  already running, e.g. from a remapped HOME button), and once more when the TV turns it on right after (reported
 *  by `cursorStateChange` or the key code 1536). The same for Exit (a held Back) while the app is in front. `report`
 *  gets one line about it a few seconds later. Returns an unsubscribe function. */
export function hidePointerOnForeground (report?: (text: string) => void): () => void {
	const state = pointerFront();
	let reportTimer = 0;
	const onFront = (why?: string) => {
		state.front(Date.now(), why);
		hidePointer();
		if (!report) return;
		window.clearTimeout(reportTimer);
		reportTimer = window.setTimeout(() => { const line = state.line(); if (line) report(line); }, REPORT_AFTER_MS + 100);
	};
	const onVisible = () => { if (!document.hidden) onFront(); };
	const onKey = (e: KeyboardEvent) => {
		if (document.hidden) return;
		if (e.keyCode === EXIT_KEY_CODE) onFront('a held Back');
		else if (e.keyCode === POINTER_SHOWN_KEY || e.keyCode === POINTER_HIDDEN_KEY) {
			if (state.cursor(e.keyCode === POINTER_SHOWN_KEY, Date.now(), 'key')) hidePointer();
		}
	};
	// webOS: `cursorStateChange` with detail.visibility when the pointer appears or goes
	const onCursor = (e: Event) => {
		const detail = (e as CustomEvent<{visibility?: boolean}>).detail;
		if (!detail || typeof detail.visibility !== 'boolean' || document.hidden) return;
		if (state.cursor(detail.visibility, Date.now())) hidePointer();
	};
	onFront();
	document.addEventListener('visibilitychange', onVisible);
	document.addEventListener('webOSRelaunch', onVisible);
	document.addEventListener('cursorStateChange', onCursor);
	window.addEventListener('keydown', onKey, true);
	return () => {
		window.clearTimeout(reportTimer);
		document.removeEventListener('visibilitychange', onVisible);
		document.removeEventListener('webOSRelaunch', onVisible);
		document.removeEventListener('cursorStateChange', onCursor);
		window.removeEventListener('keydown', onKey, true);
	};
}

// Hover-select guard for the home row. When the row glides, tiles slide under a pointer that is not moving
// and each one would "hover" and select itself, which scrolls the row further: a runaway. So a hover only
// selects when the pointer really moved lately, and not again until the glide has settled.
let lastX = -1;
let lastY = -1;
let movedAt = 0;
let selectedAt = 0;
let watching = false;
const HOVER_MOVE_MS = 120;
const HOVER_COOLDOWN_MS = 260;

function watchPointer (): void {
	if (watching || typeof window === 'undefined') return;
	watching = true;
	window.addEventListener('mousemove', (e: MouseEvent) => {
		if (e.screenX !== lastX || e.screenY !== lastY) { lastX = e.screenX; lastY = e.screenY; movedAt = Date.now(); }
	}, true);
}

/** Start listening (call once at start-up). */
export function startPointerGuard (): void { watchPointer(); }

/** May a hover on a home-row tile select it now? */
export function hoverMayselect (now: number = Date.now()): boolean {
	if (!watching) return true;
	if (now - movedAt > HOVER_MOVE_MS) return false;
	if (now - selectedAt < HOVER_COOLDOWN_MS) return false;
	selectedAt = now;
	return true;
}
