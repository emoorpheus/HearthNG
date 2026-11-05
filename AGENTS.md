# AGENTS.md

Guide for coding agents (and people) working on **HearthNG**: a home screen launcher for LG webOS TVs, a fork of
[Hearth for WebOS](https://github.com/rudra-avatar/Hearth) 2.1.3. Author of the fork: emoorpheus. Licence: MIT
(`LICENSE` keeps the webos-launcher, rudra-avatar and emoorpheus notices; keep all three).

## What is where

| Path | What |
|---|---|
| `src/` | The app: Preact + TypeScript, built by Vite into `dist/` |
| `src/i18n/en.ts` | The string table: every text the user sees |
| `src/lib/prefs.ts` | Every setting in one table; the Settings lists and keys come from it |
| `src/lib/apps.ts` | `exec`: the one place that runs shell commands (as root, through the Homebrew Channel) |
| `src/homehook/`, `src/homeapp/`, `src/poweron/` | POSIX shell helpers that run as root on the TV (busybox `sh`) |
| `toast/` | `com.hearthng.toast`, the small notification app |
| `services/com.hearthng.launcher.ssap/` | Node service that talks to the TV's local remote-control port (app list without root) |
| `scripts/` | Build helpers and the tests (`test-*.mjs`, `test-*.sh`) |
| `docs/` | Guides (MkDocs), language files (`docs/languages/`), compatibility table |
| `public/` | `appinfo.json`, icons, bundled binaries listed in `THIRD_PARTY_NOTICES.md` |
| `tools/` | Developer scripts that run on a computer or the TV |

## Commands

```sh
npm install
npm test            # every unit test and the shell tests of the TV scripts
npm run build       # type-check, then dist/ (Chrome 53 build and a webOS 3 / Chromium 38 build)
npm run package     # build/com.hearthng.launcher_<version>_all.ipk (+ the toast ipk)
node scripts/test-<name>.mjs   # one test file
```

`scripts/test-langscan.mjs` needs the TypeScript 5 API (the project's compiler is TypeScript 7). Install it outside
the repo once: `npm i --prefix /tmp/ast typescript@5`.

Shell scripts are POSIX `sh` (busybox on the TV). Check them with `shellcheck -s sh FILE`.

## Rules

1. **Tests first.** Write the failing test, run it and see it fail for the right reason, then change the code, then
   run the **whole** suite (`npm test`). For a new check, break the code on purpose once and see the test catch it.
2. **Small commits.** One change per commit. The message says why, what, and how it was proved (which tests, whether
   it ran on a TV). Author: `emoorpheus <41639142+emoorpheus@users.noreply.github.com>`.
3. **Old browsers.** The same sources must run on Chrome 53 (webOS 4+) and Chromium 38 (webOS 3). No CSS grid, `gap`
   or `inset`; one classic script (module scripts do not load from `file://` on webOS). CSS custom properties only
   through `src/lib/cssvars.ts`.
4. **Texts.** Every visible text goes through `tt()` and `src/i18n/en.ts`; `scripts/test-langscan.mjs` and
   `scripts/test-i18n.mjs` fail otherwise. Keep `docs/languages/` in step (see `docs/language_packs.md`).
5. **Shell commands.** Build them only in `exec` callers; quote every value with `shellQuote` or check it against a
   strict pattern first (app IDs: `isAppId`; theme names: `slugOk`). Never put text from a file, the network or
   launch parameters into a command unchecked.
6. **Version.** `package.json`, `public/appinfo.json` and `src/config/version.ts` move together
   (`scripts/test-about.mjs` checks). Note user-visible changes in `CHANGELOG.md`.
7. **Facts only.** Say "not tested on a TV" when a change was only checked with tests or stubs.

## Working on a real TV

- Never send `KEY_EXIT` (code 174) through uinput: webOS closes the app in front with it, a home screen included.
  For Back use the BACK special key of `com.webos.service.networkinput`.
- Before changing a file on the TV, copy it. Before removing apps, copy `/var/lib/wam/Default`.
- Do not modify or flash LG's own Home app. Leave apps that are not part of this project alone.
- The TV address goes in `tv.env` (git-ignored; see `tv.env.example`), never in a commit.

## Privacy

Never commit IP addresses, host names, user names, serial numbers, tokens or paths of your own computers. Write
`TV_IP` (or `root@<tv-ip>`) in docs and examples.
