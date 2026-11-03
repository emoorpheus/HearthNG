#!/bin/sh
# HearthNG helper watchdog. Started by apply.sh (at boot and whenever the launcher opens); one at a time. Written to
# the TV by the launcher together with the other helper files. Log: /tmp/launcher-homehook.log (lines "guard:").
# Every INTERVAL s, in this order:
#   1. the emergency exit is on ($HOOK/stopped): exits (stop.sh also stops it);
#   2. watch.sh is missing or is not HearthNG's (it has no LG Home freeze, e.g. Hearth itself wrote its own helper
#      into the same folder): unfreezes LG Home and exits. Nothing else would ever unfreeze it;
#   3. the launcher is not installed (CONFIRM checks in a row): unfreezes LG Home and exits;
#   4. the watcher is not running (CONFIRM checks in a row): starts it again with apply.sh. After MAX_RESTARTS restarts
#      since boot it gives up: unfreezes LG Home, shows a notification and exits (the launcher, when it next opens,
#      starts the watcher and this guard again).
# It never freezes LG Home itself.
# Usage: sh guard.sh   (MAX_LOOPS=n: only n checks, for tests)

HOOK="${HOOK:-/media/developer/launcher-homehook}"
LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"
APP_NAME="${APP_NAME:-HearthNG}"
LAUNCHER="${LAUNCHER:-/media/developer/apps/usr/palm/applications/$LAUNCHER_ID}"
PIDFILE="${PIDFILE:-/tmp/launcher-homehook-watch.pid}"
GUARD_PIDFILE="${GUARD_PIDFILE:-/tmp/launcher-homehook-guard.pid}"
RESTARTS="${RESTARTS:-/tmp/launcher-homehook-restarts}"   # watcher restarts since boot (/tmp is emptied at boot)
STOPPED="${STOPPED:-$HOOK/stopped}"
LOG="${LOG:-/tmp/launcher-homehook.log}"
UPTIME_FILE="${UPTIME_FILE:-/proc/uptime}"
HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
HOME_PROC="${HOME_PROC:-$HOME_PROC_DEFAULT}"
WATCH_MARK='pkill -STOP'              # only HearthNG's watch.sh freezes LG Home
TOAST_LANG="${TOAST_LANG:-auto}"
LUNA="${LUNA_SEND:-luna-send}"
NAP="${NAP:-sleep}"
INTERVAL="${INTERVAL:-10}"
CONFIRM="${CONFIRM:-2}"
MAX_RESTARTS="${MAX_RESTARTS:-5}"
MAX_LOOPS="${MAX_LOOPS:-0}"           # 0 = no end
TOAST_URI="luna://com.webos.notification/createToast"
LAUNCH_URI="luna://com.webos.applicationManager/launch"
TOAST_STYLE="${TOAST_STYLE:-auto}"    # as in watch.sh: auto = HearthNG's own notification when installed; own; system
TOAST_APP_ID="${TOAST_APP_ID:-com.hearthng.toast}"
TOAST_APP="${TOAST_APP:-/media/developer/apps/usr/palm/applications/$TOAST_APP_ID}"
TOAST_MS="${TOAST_MS:-2000}"
case "$TOAST_MS" in ''|*[!0-9]*) TOAST_MS=2000 ;; esac

uptime_now () { _up=; read -r _up _rest 2>/dev/null < "$UPTIME_FILE"; echo "${_up:-0}"; }
log () { echo "$(uptime_now) guard: $*" >> "$LOG"; }
thaw_home () { pkill -CONT -f "$HOME_PROC" 2>/dev/null; }
alive () { p=$(cat "$1" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
# A notification: HearthNG's own (com.hearthng.toast, TOAST_MS ms, as in watch.sh), else the TV's.
toast () {
    case "$TOAST_STYLE" in system) ot=no ;; own) ot=yes ;; *) if [ -f "$TOAST_APP/appinfo.json" ]; then ot=yes; else ot=no; fi ;; esac
    if [ "$ot" = yes ]; then
        r=$("$LUNA" -n 1 "$LAUNCH_URI" "{\"id\":\"$TOAST_APP_ID\",\"params\":{\"text\":\"$1\",\"ms\":$TOAST_MS}}" 2>&1)
        case "$r" in
            *'"returnValue":true'*|*'"returnValue": true'*) log "own toast \"$1\" ($TOAST_MS ms): $(echo "$r" | tr -d '\n' | tr -s ' ' | cut -c1-200)"; return 0 ;;
        esac
        log "own toast \"$1\" refused: $(echo "${r:-no reply}" | tr -d '\n' | tr -s ' ' | cut -c1-200): the TV's notification instead"
    fi
    r=$("$LUNA" -n 1 -a webosbrew "$TOAST_URI" "{\"sourceId\":\"webosbrew\",\"message\":\"$1\"}" 2>&1)
    log "toast \"$1\": ${r:-no reply}"
}
gave_up_text () {
    tl="$TOAST_LANG"
    if [ "$tl" != ru ] && [ "$tl" != en ]; then
        tl=$("$LUNA" -n 1 luna://com.webos.settingsservice/getSystemSettings '{"keys":["localeInfo"]}' 2>/dev/null | tr -d '\n ' | sed -n 's/.*"UI":"\([^"]*\)".*/\1/p')
    fi
    case "$tl" in
        ru*) echo "Помощник $APP_NAME несколько раз останавливался: LG Home снова работает" ;;
        *) echo "The $APP_NAME helper keeps stopping: LG Home works again" ;;
    esac
}
quit () {
    [ "$(cat "$GUARD_PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$GUARD_PIDFILE"
    exit 0
}

if alive "$GUARD_PIDFILE" && [ "$(cat "$GUARD_PIDFILE")" != "$$" ]; then
    log "another guard is already running (pid $(cat "$GUARD_PIDFILE")): exiting"
    exit 0
fi
echo $$ > "$GUARD_PIDFILE"
trap 'log "stopped (pid $$)"; quit' TERM INT
log "started (pid $$, every $INTERVAL s)"

cand=; seen=0
# confirmed STATE: STATE has been seen CONFIRM checks in a row
confirmed () {
    if [ "$cand" = "$1" ]; then seen=$((seen + 1)); else cand="$1"; seen=1; fi
    [ "$seen" -ge "$CONFIRM" ]
}

loops=0
while :; do
    if [ -f "$STOPPED" ]; then log "emergency exit is on ($STOPPED): exiting"; quit; fi
    if [ ! -f "$HOOK/watch.sh" ] || ! grep -q -- "$WATCH_MARK" "$HOOK/watch.sh" 2>/dev/null; then
        thaw_home
        log "$HOOK/watch.sh is missing or is not HearthNG's: LG Home unfrozen, exiting"
        quit
    fi
    if [ ! -f "$LAUNCHER/appinfo.json" ]; then
        if confirmed gone; then
            thaw_home
            log "$APP_NAME is not installed ($LAUNCHER/appinfo.json is missing): LG Home unfrozen, exiting"
            quit
        fi
    elif ! alive "$PIDFILE"; then
        if confirmed dead; then
            n=$(( $(cat "$RESTARTS" 2>/dev/null || echo 0) + 1 ))
            if [ "$n" -gt "$MAX_RESTARTS" ]; then
                thaw_home
                log "the watcher has stopped again after $MAX_RESTARTS restarts since boot: LG Home unfrozen, exiting"
                toast "$(gave_up_text)"
                quit
            fi
            echo "$n" > "$RESTARTS"
            r=$(sh "$HOOK/apply.sh" 2>&1 | tail -n 1)
            log "the watcher was not running: apply.sh: ${r:-no answer} (restart $n of $MAX_RESTARTS since boot)"
            cand=; seen=0
        fi
    else
        cand=; seen=0
    fi
    loops=$((loops + 1))
    [ "$MAX_LOOPS" -gt 0 ] && [ "$loops" -ge "$MAX_LOOPS" ] && quit
    $NAP "$INTERVAL"
done
