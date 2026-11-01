#!/bin/sh
# HearthNG helper: emergency exit. Run by hand over SSH:
#   sh /media/developer/launcher-homehook/stop.sh          stop the watcher and its guard, unfreeze LG Home
#   sh /media/developer/launcher-homehook/stop.sh resume   undo: the watcher and the guard run again
# The file "stopped" survives a restart. While it is there, watch.sh, guard.sh and apply.sh start nothing, whoever runs
# them (the boot link, the launcher, the guard). Switching "Replace LG Home" on again in the launcher also undoes it.

HOOK="${HOOK:-/media/developer/launcher-homehook}"
STOPPED="${STOPPED:-$HOOK/stopped}"
PIDFILE="${PIDFILE:-/tmp/launcher-homehook-watch.pid}"
GUARD_PIDFILE="${GUARD_PIDFILE:-/tmp/launcher-homehook-guard.pid}"
WATCH_PATTERN="${WATCH_PATTERN:-[l]auncher-homehook/watch.sh}"
GUARD_PATTERN="${GUARD_PATTERN:-[l]auncher-homehook/guard.sh}"
HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
HOME_PROC="${HOME_PROC:-$HOME_PROC_DEFAULT}"
LOG="${LOG:-/tmp/launcher-homehook.log}"
UPTIME_FILE="${UPTIME_FILE:-/proc/uptime}"
NAP="${NAP:-sleep}"

uptime_now () { _up=; read -r _up _rest 2>/dev/null < "$UPTIME_FILE"; echo "${_up:-0}"; }
log () { echo "$(uptime_now) stop: $*" >> "$LOG"; }

case "${1:-stop}" in
    stop)
        # 1. The file first: a watcher or guard started in this very second exits at once.
        mkdir -p "$HOOK" 2>/dev/null
        touch "$STOPPED" 2>/dev/null || echo "warning: could not create $STOPPED (the watcher may be started again)"
        # 2. The guard, so it does not start the watcher again.
        gp=$(cat "$GUARD_PIDFILE" 2>/dev/null)
        [ -n "$gp" ] && kill "$gp" 2>/dev/null
        pkill -9 -f "$GUARD_PATTERN" 2>/dev/null
        rm -f "$GUARD_PIDFILE"
        # 3. The watcher: TERM (it ends its own subscription), then KILL for every copy and every running check.
        wp=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null; then
            kill "$wp" 2>/dev/null
            i=0
            while [ "$i" -lt 3 ] && kill -0 "$wp" 2>/dev/null; do $NAP 1; i=$((i + 1)); done
        fi
        pkill -9 -f "$WATCH_PATTERN" 2>/dev/null
        rm -f "$PIDFILE"
        # 4. LG Home last, when nothing is left to freeze it again.
        pkill -CONT -f "$HOME_PROC" 2>/dev/null
        log "emergency exit: watcher and guard stopped, LG Home unfrozen, $STOPPED created (undo: sh $0 resume)"
        echo stopped ;;
    resume)
        rm -f "$STOPPED"
        r=$(sh "$HOOK/apply.sh" 2>&1 | tail -n 1)
        log "resume: $STOPPED removed, apply.sh: ${r:-no answer}"
        echo "resumed (apply.sh: ${r:-no answer})" ;;
    *) echo "usage: sh $0 [stop | resume]"; exit 1 ;;
esac
