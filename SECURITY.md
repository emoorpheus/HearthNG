# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x (pre-release) | yes |
| older | no |

## Reporting a vulnerability

Please report privately through GitHub: **Security**, **Report a vulnerability** on this repository (private
vulnerability reporting). Do not open a public issue. Include the HearthNG version, the TV model and webOS version,
and the steps. You get an answer when the report has been read; a fix goes into the next release and the advisory
names you unless you ask otherwise.

## What HearthNG can do on a TV

Knowing this helps to judge a report:

- On a **rooted** TV, HearthNG runs shell commands as root through the Homebrew Channel service. All of them are built
  in `exec` callers (`src/lib/apps.ts`). Values are quoted with `shellQuote` or checked against strict patterns (app
  IDs, theme names, release addresses) before they go into a command. The helper scripts it installs
  (`src/homehook/`, `src/homeapp/`, `src/poweron/`) run as root at start-up.
- Files it reads from USB drives or `/media/developer` (wallpapers, themes, language files) are checked before use:
  theme and language files have size, type and content limits (`src/lib/themefile.ts`, `src/lib/langpack.ts`).
- HearthNG opens no network port. Its background service connects only to the TV itself (`127.0.0.1`, the TV's
  remote-control port) to read the app list.
- Network requests: the weather (Open-Meteo, `api.open-meteo.com` and `geocoding-api.open-meteo.com`; the build
  switch `HEARTH_WEATHER=0` leaves the weather out) and a download test in the Debug tab's probes
  (`raw.githubusercontent.com`, GitHub release files). No analytics, no accounts.
