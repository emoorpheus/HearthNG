// Shell commands for "Open this launcher instead of LG Home". Pure string-building (no imports of
// the bundled files), so it can be tested on its own. See homehook.ts for the part that runs them.
//
// How it works: a small watcher script (src/homehook/watch.sh) runs in the background and, whenever
// the TV brings LG Home to the front (Home button, leaving an app with Back), opens the launcher.
// Where LG Home is its own process (webOS 25) the watcher also freezes it while the launcher is in front.
// Nothing of LG Home is replaced or mounted. A link in the startup folder starts the watcher at boot
// (always added; the watcher is also started whenever the launcher opens), and a small watchdog
// (guard.sh) starts it again if it stops. stop.sh is the emergency exit (run by hand over SSH).

/** Bump when the scripts change: the launcher then rewrites the installed copy and restarts the watcher. */
export const HOOK_VERSION = '18-ng1';
export const HOOK_DIR = '/media/developer/launcher-homehook';
export const HOOK_LINK = '/var/lib/webosbrew/init.d/48-launcher-homehook';
export const APP_QML = '/usr/palm/applications/com.webos.app.home/qml';
export const PID_FILE = '/tmp/launcher-homehook-watch.pid';
export const GUARD_PID_FILE = '/tmp/launcher-homehook-guard.pid';
/** The emergency exit (stop.sh): while it exists nothing of the helper starts. In HOOK_DIR, so it survives a restart. */
export const STOPPED_FILE = `${HOOK_DIR}/stopped`;
/** LG Home's own process on webOS 25 (the one the watcher freezes). "[f]" keeps the pattern from matching the shell
 *  that carries this command. */
export const HOME_PROC_PATTERN = '[f]lutter-client -i com\\.webos\\.app\\.home([^A-Za-z0-9._-]|$)';
export const ALLOW_FILE = '/tmp/launcher-allow-stock-home';
export const ALIVE_FILE = '/tmp/launcher-alive';

export type HookResult = 'applied' | 'stopped' | 'launcher-missing' | 'files-missing' | 'failed';

/** What is in place on the TV right now. */
export interface HookStatus {
	/** the watcher is running */
	running: boolean;
	/** the start-at-boot link exists */
	linked: boolean;
	/** the emergency exit (stop.sh) is on */
	stopped?: boolean;
}

const RESULTS: HookResult[] = ['applied', 'stopped', 'launcher-missing', 'files-missing'];

/** Looks for the apply script's result word in its output (the last one wins); anything else is a failure. */
export function parseHookResult (output: string): HookResult {
	const lines = output.split('\n').map((l) => l.trim()).filter((l) => (RESULTS as string[]).indexOf(l) !== -1);
	return lines.length ? (lines[lines.length - 1] as HookResult) : 'failed';
}

/** Runs `command` so that its output (errors included) always comes back, with the exit code on the last line. */
export function withStatus (command: string): string {
	return `{ ${command}; } 2>&1; echo "[exit $?]"`;
}

/** The exit code from the last line of withStatus output, or null. */
export function parseExit (output: string): number | null {
	const match = /\[exit (\d+)\]\s*$/.exec(output);
	return match ? Number(match[1]) : null;
}

/** The last meaningful line of some output, for telling the user what went wrong. */
export function lastLine (output: string): string {
	const lines = output.split('\n').map((l) => l.trim()).filter((l) => l.length > 0 && !/^\[exit \d+\]$/.test(l));
	return lines.length ? lines[lines.length - 1].slice(0, 140) : '';
}

/** `text` as UTF-8, base64-encoded (btoa alone only takes Latin-1; the helper's notifications are also in Russian). */
export function utf8Base64 (text: string): string {
	return btoa(unescape(encodeURIComponent(text)));
}

/** Commands that write `text` (as UTF-8) to `path`, carried as base64 so nothing needs quoting, in
 *  pieces of at most ~4000 characters (the first piece creates the file, the rest append). Each piece
 *  is a multiple of 4 base64 characters, so each decodes on its own. */
export function writeFileCommands (path: string, text: string): string[] {
	const encoded = utf8Base64(text);
	const pieces: string[] = [];
	for (let i = 0; i < encoded.length; i += 4000) pieces.push(encoded.slice(i, i + 4000));
	if (!pieces.length) pieces.push('');
	return pieces.map((piece, n) => `echo '${piece}' | base64 -d ${n === 0 ? '>' : '>>'} '${path}'`);
}

export interface HookFiles {
	watchSh: string;
	applySh: string;
	stockSh: string;
	diagnoseSh: string;
	guardSh: string;
	stopSh: string;
}

export interface InstallOptions {
	/** the user switched the helper on: an emergency exit that is still on is undone */
	resume?: boolean;
}

/** Every script of the helper, in the order they are written. */
export const SCRIPT_NAMES = ['watch.sh', 'apply.sh', 'stock.sh', 'diagnose.sh', 'guard.sh', 'stop.sh'];

export interface InstallStep {
	name: string;
	command: string;
}

// kill -9, not a polite stop: the watcher is busy listening and would only notice a polite stop much later.
// The pattern also catches a watcher whose pid file is lost; its leading [l] stops it matching this command itself.
// The guard goes first, so it cannot start the watcher again in between.
const STOP_WATCHER = `gp="$(cat '${GUARD_PID_FILE}' 2>/dev/null)"; [ -n "$gp" ] && kill -9 "$gp" 2>/dev/null; pkill -9 -f '[l]auncher-homehook/guard.sh' 2>/dev/null; rm -f '${GUARD_PID_FILE}'; pid="$(cat '${PID_FILE}' 2>/dev/null)"; if [ -n "$pid" ]; then pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; fi; pkill -9 -f '[l]auncher-homehook/watch.sh' 2>/dev/null; rm -f '${PID_FILE}'; true`;

/** The install, in small steps (one piece of a file per call), so a failure says which step it was.
 *  The start-at-boot link is always added. The last step starts the watcher (and its guard). */
export function installSteps (files: HookFiles, options: InstallOptions = {}): InstallStep[] {
	const write = (name: string, path: string, text: string): InstallStep[] => {
		const commands = writeFileCommands(path, text);
		return commands.map((command, i) => ({name: commands.length > 1 ? `write ${name} (${i + 1}/${commands.length})` : `write ${name}`, command}));
	};
	return [
		{name: 'create the folder', command: `mkdir -p '${HOOK_DIR}'`},
		{name: 'clear out older files', command: `rm -rf '${HOOK_DIR}/overlay'; rm -f '${HOOK_DIR}'/*.new; true`},
		...write('watch.sh', `${HOOK_DIR}/watch.sh.new`, files.watchSh),
		...write('apply.sh', `${HOOK_DIR}/apply.sh.new`, files.applySh),
		...write('stock.sh', `${HOOK_DIR}/stock.sh.new`, files.stockSh),
		...write('diagnose.sh', `${HOOK_DIR}/diagnose.sh.new`, files.diagnoseSh),
		...write('guard.sh', `${HOOK_DIR}/guard.sh.new`, files.guardSh),
		...write('stop.sh', `${HOOK_DIR}/stop.sh.new`, files.stopSh),
		// written under a temporary name and moved into place, so a running script is never overwritten half-way
		{name: 'put the files in place', command: SCRIPT_NAMES.map((f) => `mv -f '${HOOK_DIR}/${f}.new' '${HOOK_DIR}/${f}'`).join(' && ')},
		{name: 'write the version', command: `echo '${HOOK_VERSION}' > '${HOOK_DIR}/version'`},
		{name: 'make the scripts runnable', command: `chmod +x ${SCRIPT_NAMES.map((f) => `'${HOOK_DIR}/${f}'`).join(' ')}`},
		{name: 'add the start-at-boot link', command: `ln -sf '${HOOK_DIR}/apply.sh' '${HOOK_LINK}'`},
		...(options.resume ? [{name: 'undo the emergency exit', command: `rm -f '${STOPPED_FILE}'`}] : []),
		{name: 'stop an older watcher', command: STOP_WATCHER},
		{name: 'start the watcher', command: `sh '${HOOK_DIR}/apply.sh'`}
	];
}

// if/else, not `a && b || c`: the apply script exits non-zero when it refuses, and that must not also print the fallback
export const APPLY_COMMAND = withStatus(`if [ -f '${HOOK_DIR}/apply.sh' ]; then sh '${HOOK_DIR}/apply.sh'; else echo files-missing; fi`);
/** LG's own Home is wanted: the watcher stands down until it is left again. */
export const STOCK_COMMAND = `[ -f '${HOOK_DIR}/stock.sh' ] && sh '${HOOK_DIR}/stock.sh'; echo stock`;
/** Stops the watcher and its guard, deletes everything the setting added (and any stand-in an earlier version mounted)
 *  and unfreezes LG Home. */
export const REMOVE_COMMAND = `${STOP_WATCHER}; rm -f '${ALLOW_FILE}' '${ALIVE_FILE}' '${HOOK_LINK}'; while grep -q ' ${APP_QML} ' /proc/mounts; do umount '${APP_QML}' || break; done; rm -rf '${HOOK_DIR}'; pkill -CONT -f '${HOME_PROC_PATTERN}' 2>/dev/null; echo removed`;
export const VERSION_COMMAND = `cat '${HOOK_DIR}/version' 2>/dev/null; true`;
export const STATUS_COMMAND = `if [ -f '${PID_FILE}' ] && kill -0 "$(cat '${PID_FILE}')" 2>/dev/null; then echo running; fi; if [ -L '${HOOK_LINK}' ]; then echo linked; fi; if [ -f '${STOPPED_FILE}' ]; then echo stopped; fi; true`;

export function parseHookStatus (output: string): HookStatus {
	return {running: /^running$/m.test(output), linked: /^linked$/m.test(output), stopped: /^stopped$/m.test(output)};
}
