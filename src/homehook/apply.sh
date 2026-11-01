#!/bin/sh
# Makes sure the watcher (watch.sh) and its watchdog (guard.sh) are running, so that LG Home is replaced by the
# launcher. Safe to run again and again. Prints one word: applied, stopped, launcher-missing or files-missing.
# If the launcher is no longer installed, LG Home is unfrozen, and the helper removes its own link and folder after 40 s.
# Run at boot by a link in /var/lib/webosbrew/init.d, by the launcher whenever it opens, and by guard.sh.

APP_QML="${APP_QML:-/usr/palm/applications/com.webos.app.home/qml}"
HOOK="${HOOK:-/media/developer/launcher-homehook}"
LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"
LAUNCHER="${LAUNCHER:-/media/developer/apps/usr/palm/applications/$LAUNCHER_ID}"
PIDFILE="${PIDFILE:-/tmp/launcher-homehook-watch.pid}"
GUARD_PIDFILE="${GUARD_PIDFILE:-/tmp/launcher-homehook-guard.pid}"
LOG="${LOG:-/tmp/launcher-homehook.log}"
LINK="${LINK:-/var/lib/webosbrew/init.d/48-launcher-homehook}"
STOPPED="${STOPPED:-$HOOK/stopped}"
HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
HOME_PROC="${HOME_PROC:-$HOME_PROC_DEFAULT}"

log () { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }
alive () { p=$(cat "$1" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }

# Earlier versions put a stand-in over LG Home's QML. Take it off if it is still there.
if [ -z "$DRY_RUN" ]; then
    while grep -q " $APP_QML " /proc/mounts; do
        umount "$APP_QML" || break
    done
fi

# The launcher must be installed (if it was uninstalled, LG Home is unfrozen and left alone).
if [ ! -f "$LAUNCHER/appinfo.json" ]; then
    log "launcher not installed: not starting the watcher, LG Home unfrozen"
    # Uninstalled without switching this off: after a wait (the app storage can be slow to appear at start-up) the helper
    # removes its own link and folder. Not while testing.
    if [ -z "$DRY_RUN" ]; then
        pkill -CONT -f "$HOME_PROC" 2>/dev/null
        ( nohup sh -c "sleep 40; [ -f '$LAUNCHER/appinfo.json' ] || { rm -f '$LINK'; rm -rf '$HOOK'; pkill -CONT -f '$HOME_PROC'; }" >/dev/null 2>&1 </dev/null & )
    fi
    echo launcher-missing
    exit 2
fi

# The emergency exit (stop.sh) is on: nothing is started until "stop.sh resume" (or the helper is switched on again).
if [ -f "$STOPPED" ]; then
    log "emergency exit is on ($STOPPED): not starting the watcher (undo: sh $HOOK/stop.sh resume)"
    echo stopped
    exit 0
fi

if [ ! -f "$HOOK/watch.sh" ]; then
    log "watch.sh missing: not starting the watcher"
    echo files-missing
    exit 4
fi

if alive "$PIDFILE"; then
    log "watcher already running (pid $(cat "$PIDFILE"))"
else
    [ -z "$DRY_RUN" ] && ( nohup sh "$HOOK/watch.sh" >/dev/null 2>&1 </dev/null & )
    log "watcher started"
fi
if [ -f "$HOOK/guard.sh" ] && ! alive "$GUARD_PIDFILE"; then
    [ -z "$DRY_RUN" ] && ( nohup sh "$HOOK/guard.sh" >/dev/null 2>&1 </dev/null & )
    log "guard started"
fi
echo applied
