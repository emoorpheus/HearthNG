// Small system helpers that go through the Homebrew Channel's root shell.

import {exec} from './apps';
import {isWebOS} from './luna';

/** Ends LG's own home app so its memory is free. The pattern matches the exact app id (not
 *  look-alikes such as com.webos.app.homeconnect), and the leading "[c]" stops the pattern
 *  from matching the very shell command that carries it. webOS starts the home app again
 *  by itself the next time it is needed (for example the "LG Home" tile). */
export const CLOSE_HOME_COMMAND = `H=com.webos.app; front=$(luna-send -n 1 luna://com.webos.applicationManager/getForegroundAppInfo '{}' 2>/dev/null); case "$front" in *"\\"appId\\":\\"$H.home\\""*) echo skipped;; *) pkill -f '[c]om\\.webos\\.app\\.home([^A-Za-z0-9._-]|$)'; echo done;; esac`;

export function closeLgHome (): Promise<void> {
	if (!isWebOS()) return Promise.resolve();
	return exec(CLOSE_HOME_COMMAND, 5000).then(() => undefined);
}

// ---------- which app the Home button (and leaving an app with Back) opens ----------
// webOS keeps this in a system setting, defaultApps.home. LG's default is com.webos.app.home.
// defaultApps holds more than home (webOS 25: "MembershipApp": "com.webos.app.overlaymembership"), and setSystemSettings
// replaces the whole object: a call with home alone deleted MembershipApp on a webOS 10.3 TV (2026-11-03). So the object
// is read first and only home is changed.

export const LG_HOME_ID = 'com.webos.app.home';
const APP_ID_PATTERN = /^[A-Za-z0-9._-]+$/;
const KEY_PATTERN = /^[A-Za-z0-9_]+$/;

/** The TV's whole defaultApps object out of getSystemSettings' reply (only entries whose name and value are plain ids),
 *  or null when the reply has none. */
export function parseDefaultApps (output: string): Record<string, string> | null {
	const match = /"defaultApps"\s*:\s*(\{[^{}]*\})/.exec(output);
	if (!match) return null;
	let parsed: unknown;
	try { parsed = JSON.parse(match[1]); } catch { return null; }
	if (!parsed || typeof parsed !== 'object') return null;
	const apps: Record<string, string> = {};
	const all = parsed as Record<string, unknown>;
	Object.keys(all).forEach((k) => { const v = all[k]; if (KEY_PATTERN.test(k) && typeof v === 'string' && APP_ID_PATTERN.test(v)) apps[k] = v; });
	return apps;
}

/** The shell command that sets the home app and keeps the other entries of `current` (what the TV has now). Throws for
 *  anything that isn't a plain app id. */
export function homeSettingCommand (appId: string, current: Record<string, string> | null = null): string {
	if (!APP_ID_PATTERN.test(appId)) throw new Error('Invalid app id');
	const apps: Record<string, string> = {home: appId};
	if (current) Object.keys(current).forEach((k) => { if (k !== 'home' && KEY_PATTERN.test(k) && APP_ID_PATTERN.test(current[k])) apps[k] = current[k]; });
	return `luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings '{"category":"general","settings":{"defaultApps":${JSON.stringify(apps)}}}'`;
}

const GET_HOME_COMMAND = `luna-send -n 1 -f luna://com.webos.settingsservice/getSystemSettings '{"category":"general","keys":["defaultApps"]}'`;

/** Reads the app id out of getSystemSettings' reply, or null. */
export function parseHomeApp (output: string): string | null {
	const match = /"home"\s*:\s*"([^"]+)"/.exec(output);
	return match ? match[1] : null;
}

export function getHomeApp (): Promise<string | null> {
	if (!isWebOS()) return Promise.resolve(null);
	return exec(GET_HOME_COMMAND, 6000).then(parseHomeApp).catch(() => null);
}

/** Sets the home app, keeping the other defaultApps entries the TV has. Resolves with the TV's reply. */
export function writeHomeSetting (appId: string): Promise<string> {
	return exec(GET_HOME_COMMAND, 6000).then(parseDefaultApps, () => null).then((current) => exec(homeSettingCommand(appId, current), 6000));
}

/** Sets the home app. Resolves true when the TV accepted it. */
export function setHomeApp (appId: string): Promise<boolean> {
	if (!isWebOS()) return Promise.resolve(false);
	return writeHomeSetting(appId).then((out) => /"returnValue"\s*:\s*true/.test(out)).catch(() => false);
}

// ---------- the LG logo when the TV starts ----------
// LG's hidden menu (press Mute repeatedly on an input with no signal) has "Show LG logo when turning on".
// It is the system setting other.lgLogoDisplay, "on" or "off" (found by watching what the TV changed).

export type LogoState = 'on' | 'off' | 'unsupported';

export const GET_LOGO_COMMAND = `luna-send -n 1 -f luna://com.webos.settingsservice/getSystemSettings '{"category":"other","keys":["lgLogoDisplay"]}'`;

export function setLogoCommand (on: boolean): string {
	return `luna-send -n 1 -f luna://com.webos.settingsservice/setSystemSettings '{"category":"other","settings":{"lgLogoDisplay":"${on ? 'on' : 'off'}"}}'`;
}

/** Reads the setting out of getSystemSettings' reply: 'unsupported' when the TV answered but has no such setting, null when the reply isn't an answer. */
export function parseLogo (output: string): LogoState | null {
	const value = /"lgLogoDisplay"\s*:\s*"([^"]*)"/.exec(output);
	if (value) return value[1] === 'off' ? 'off' : value[1] === 'on' ? 'on' : 'unsupported';
	return /"returnValue"\s*:\s*true/.test(output) ? 'unsupported' : null;
}

export function getLogo (): Promise<LogoState | null> {
	if (!isWebOS()) return Promise.resolve(null);
	return exec(GET_LOGO_COMMAND, 6000).then(parseLogo).catch(() => null);
}

/** Sets it, then reads it back. Resolves true only when the TV now reports the wanted value. */
export function setLogo (on: boolean): Promise<boolean> {
	if (!isWebOS()) return Promise.resolve(false);
	return exec(setLogoCommand(on), 6000).then(() => getLogo()).then((now) => now === (on ? 'on' : 'off')).catch(() => false);
}

// ---------- apps the TV keeps ready (experimental) ----------

// ---------- storage figures for the Debug tab (read once when that tab opens) ----------

export interface DiskInfo {mount: string; totalMB: number; freeMB: number}
export interface SystemStats {disks: DiskInfo[]}

export const STATS_COMMAND = 'echo ---; df -k / /var /tmp /media/internal 2>/dev/null';

/** The output of STATS_COMMAND as figures (-1 where a figure is missing). */
export function parseStats (out: string): SystemStats {
	const disks: DiskInfo[] = [];
	const seen: Record<string, boolean> = {};
	const lines = out.split('---')[1] ? out.split('---')[1].split('\n') : [];
	for (const line of lines) {
		const f = line.trim().split(/\s+/);
		if (f.length < 6 || !/^\d+$/.test(f[1]) || !/^\d+$/.test(f[3]) || f[5].charAt(0) !== '/') continue;
		const key = f[0] + ':' + f[1];
		if (seen[key]) continue;                                  // the same disk listed for several folders
		seen[key] = true;
		disks.push({mount: f[5], totalMB: Math.round(Number(f[1]) / 1024), freeMB: Math.round(Number(f[3]) / 1024)});
	}
	return {disks};
}

export function readStats (): Promise<SystemStats | null> {
	if (!isWebOS()) return Promise.resolve(null);
	return exec(STATS_COMMAND, 5000).then(parseStats).catch(() => null);
}
