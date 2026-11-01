# Open the launcher instead of LG Home (helper)

Source of the **Settings → System → TV start → Replace LG Home (helper)** setting. The launcher writes these files to the TV itself
(`/media/developer/launcher-homehook`); you never need to copy them by hand. Tested on one TV only: LG OLED65M59LA,
webOS 25. Everything else (other models, webOS 3 to 24) is untested in HearthNG.

**Nothing on the TV's flash is replaced, mounted or modified.** A shell script (`watch.sh`) runs in the background and
watches which app the TV reports as being in front. When that becomes LG Home (Home button, leaving an app with Back,
boot), it asks the TV to open the launcher.

## The files

- `watch.sh`: the watcher.
  - Uses the TV's "app in front" subscription; if that keeps ending at once, it asks once a second instead.
  - After opening the launcher it checks, once a second, that the launcher really is in front, and asks again
    (`VERIFY_TRIES`, 8). Still not there: it closes the launcher and starts it again (`RESTART_WAIT`, 30 s). Still not
    there: it opens LG Home the way the launcher's "LG Home" tile does (`FAILSAFE=1`, the default) and shows a
    notification.
  - **Freezing LG Home.** Where LG Home is its own process (webOS 25: `flutter-client -i com.webos.app.home`), that
    process is frozen (`SIGSTOP`) while the launcher is in front, so it cannot come back over the launcher. It is unfrozen
    (`SIGCONT`) by `stock.sh` (the "LG Home" tile), by FAILSAFE, by `stop.sh`, by `guard.sh` when it gives up, when the
    setting is switched off and when the launcher is uninstalled. Stopping only the watcher does **not** unfreeze it.
    Without such a process nothing is frozen.
  - An empty foreground counts as LG Home only while that LG Home process exists (`EMPTY_AS_HOME=auto`); elsewhere it is
    left alone.
  - The TV switched off with the remote (standby): nothing is launched while it is off. When it is on again and LG Home,
    nothing or the launcher is in front, the launcher is opened; another app (HDMI, a cast) is left alone.
  - A notification "Home screen is loading…" appears only if the launcher is not in front 3 s after it was asked for,
    and is closed as soon as it (or another app) is in front. Notifications are in Russian when the TV's menu language is
    Russian, in English otherwise (`TOAST_LANG`).
  - webOS 4.x: `com.webos.app.fullhome` counts as LG Home. webOS 3 (no LG Home app): the home bar is seen in the system
    log instead (from Hearth's own helper).
- `guard.sh`: the watchdog, started together with the watcher. Every 10 s: if the watcher is not running (two checks in a
  row) it starts it again with `apply.sh`, at most 5 times per boot; then it gives up, unfreezes LG Home and shows a
  notification. If the launcher is uninstalled, or `watch.sh` is not HearthNG's (for example Hearth itself wrote its own
  helper into the same folder), it unfreezes LG Home and exits. It never freezes anything.
- `apply.sh`: starts the watcher and the guard if they are not running. Run at boot, whenever the launcher opens, and by
  the guard. If the launcher is no longer installed it unfreezes LG Home and, after 40 s, removes its own boot link and
  folder.
- `stock.sh`: "I want LG's own Home now": unfreezes LG Home; the watcher stands down until LG Home has been left again.
  The launcher's "LG Home" tile runs it.
- `stop.sh`: the emergency exit (below).
- `diagnose.sh`: collects what is needed to see why something isn't working. It changes nothing.

## The switch (Settings → System → TV start)

**Replace LG Home (helper)**: writes the scripts, adds a link in `/var/lib/webosbrew/init.d` (`48-launcher-homehook`) so
the helper starts at boot, and starts the watcher and the guard. Switching it on also undoes the emergency exit. Off:
stops everything, unfreezes LG Home and deletes the files and the link.

Only one launcher can use this folder. Hearth (`tld.my.customlauncher`) uses the same one: if Hearth is opened with its own
helper switched on, it rewrites the files with its own version, and HearthNG's guard then unfreezes LG Home and stops.
Uninstall Hearth before using HearthNG.

## Emergency exit

Over SSH (`ssh root@TV_IP`, with your TV's address):

```
sh /media/developer/launcher-homehook/stop.sh          # stop the watcher and the guard, unfreeze LG Home
sh /media/developer/launcher-homehook/stop.sh resume   # undo: start them again
```

`stop.sh` leaves a file `/media/developer/launcher-homehook/stopped`. It survives a restart: while it is there, nothing
starts the watcher (not the boot link, not the launcher, not the guard). `stop.sh resume`, or switching the setting on
again in the launcher, removes it.

## Removing it completely

1. In the launcher: **Settings → System → TV start → Replace LG Home (helper) → OK** (stops it, unfreezes LG Home, deletes the
   files and the boot link).
2. Or over SSH:
   ```
   sh /media/developer/launcher-homehook/stop.sh
   rm -f /var/lib/webosbrew/init.d/48-launcher-homehook
   rm -rf /media/developer/launcher-homehook
   ```

If the launcher is uninstalled with the setting still on, nothing breaks: the watcher and the guard check that the
launcher is installed, unfreeze LG Home, and `apply.sh` removes the link and the folder at the next boot.

## Seeing what is happening

Do this **while the problem is happening** (SSH still works with a black screen):

```
sh /media/developer/launcher-homehook/diagnose.sh
```

It prints the files, whether the watcher and the guard are running, whether the emergency exit is on, the frozen
processes, whether the scripts parse on the TV's shell, a self-test of the watcher's decision on the TV's own shell, the
app in front and the end of the log. The same text is saved in `/tmp/launcher-diagnose.txt`
(`scp root@TV_IP:/tmp/launcher-diagnose.txt .`).

To watch live: `tail -f /tmp/launcher-homehook.log`. Times are seconds since boot (`/proc/uptime`). Lines start with
`watcher:`, `guard:` or `stop:`.

## Tests

`npm test` runs `scripts/test-homehook.sh` (any POSIX shell) and `scripts/test-homehook-ng.sh` (Linux only: it uses a
real stand-in LG Home process and reads its state from `/proc`; skipped elsewhere). To run the second one with BusyBox,
as on the TV: `sh scripts/test-homehook-ng.sh /path/to/busybox`.
