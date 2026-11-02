#!/bin/sh
# HearthNG helper: watches which app is in front and opens the launcher instead of LG Home.
# Written to the TV by the launcher (Settings -> Options -> "Replace LG Home"); nothing to copy by hand.
# Started by apply.sh (at boot through the link /var/lib/webosbrew/init.d/48-launcher-homehook, and whenever the launcher
# opens) and kept running by guard.sh. Log: /tmp/launcher-homehook.log (time = seconds since boot, from /proc/uptime).
#
#  - LG Home comes to the front (Home button, Back out of an app, boot), or the foreground stays empty for EMPTY_DELAY s
#    while the TV is on: the launcher is opened. Then, once a second, it checks that the launcher really is in front and
#    asks again (VERIFY_TRIES times). Still not there: the launcher is closed and started again (RESTART_WAIT s). Still
#    not there: FAILSAFE=1 opens LG Home the way the launcher's "LG Home" tile does; FAILSAFE=0 only shows a message.
#  - Where LG Home is its own process (webOS 25: "flutter-client -i com.webos.app.home", HOME_PROC), that process is
#    frozen (SIGSTOP) while the launcher is in front, so it cannot come back over the launcher. It is unfrozen (SIGCONT)
#    by stock.sh (the "LG Home" tile), by FAILSAFE, by stop.sh (emergency exit), when the helper is turned off and when
#    the launcher is uninstalled. Stopping the watcher does NOT unfreeze it (guard.sh starts the watcher again).
#    Without such a process (other webOS versions) nothing is frozen and an empty foreground is left alone
#    (EMPTY_AS_HOME=auto), as in Hearth's own helper.
#  - The TV is switched off with the remote (standby): nothing is launched while it is off. When it is on again and LG
#    Home, nothing or the launcher is in front, the launcher is opened (wake_loop); another app (HDMI, a cast) is left.
#  - A "Home screen is loading" notification is shown only if the launcher is not in front TOAST_DELAY s after it was
#    asked for, and closed as soon as it (or another app) is in front.
#  - The emergency exit file ($HOOK/stopped, made by stop.sh) exists: it does not start.
#  - webOS 4.x: com.webos.app.fullhome counts as LG Home. webOS 3 (no LG Home app): the home bar is seen in the
#    system log instead. If the "app in front" subscription keeps ending at once, it asks once a second instead.
#  - The subscription can also go quiet while luna-send keeps running (Hearth P0.6 on a webOS 25 TV: no report for
#    35 minutes after the first minute, the watcher alive, LG Home left on screen). check_loop asks once every
#    CHECK_EVERY s what is in front and compares it with the last report; CHECK_MISSES checks in a row that disagree
#    (or one report handled for HANDLE_MAX s): the subscription is ended and made again, and its first report (what is
#    in front now) is handled as usual. After SILENT_MAX such restarts it asks once a second instead.
#  - WATCH_STDIN=1 / WATCH_BAR_STDIN=1: test modes (reports from stdin; no pid file, no subscription, nothing frozen
#    at start). diagnose.sh uses WATCH_STDIN for its self-test.
# The line in open_launcher that launches the launcher must end in ">/dev/null 2>&1": diagnose.sh's self-test cuts that
# ending off to see the call. No other line may end like that.

LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"
APP_NAME="${APP_NAME:-HearthNG}"      # the launcher's name in notifications
LAUNCHER="${LAUNCHER:-/media/developer/apps/usr/palm/applications/$LAUNCHER_ID}"
HOOK="${HOOK:-/media/developer/launcher-homehook}"
LUNA="${LUNA_SEND:-luna-send}"
PIDFILE="${PIDFILE:-/tmp/launcher-homehook-watch.pid}"
LOG="${LOG:-/tmp/launcher-homehook.log}"
ALLOW="${ALLOW:-/tmp/launcher-allow-stock-home}"      # exists while the user asked for LG's own Home (stock.sh)
MARK="${MARK:-/tmp/launcher-launch-mark}"             # touched when the launcher is asked for
VLOCK="${VLOCK:-/tmp/launcher-verify-lock}"           # holds the time a check started: one check at a time
TAKEOVER_FLAG="${TAKEOVER_FLAG:-/media/developer/launcher-takeover/enabled}"   # the old "SAM" method of Hearth 1.x
TAKEOVER_PID="${TAKEOVER_PID:-/tmp/launcher-takeover-watch.pid}"
TAKEOVER_DIR="${TAKEOVER_DIR:-/usr/palm/applications/com.webos.app.home}"   # where that method mounted its stand-in
MOUNTS="${MOUNTS:-/proc/mounts}"
KEEP_FLAG="${KEEP_FLAG:-/media/developer/launcher-keepready/on}"   # "Keep Hearth ready" (written by keepready.sh)
UPTIME_FILE="${UPTIME_FILE:-/proc/uptime}"
STOPPED="${STOPPED:-$HOOK/stopped}"   # emergency exit (made by stop.sh)
STOP_HINT="${STOP_HINT:-sh $HOOK/stop.sh}"
HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
HOME_PROC="${HOME_PROC:-$HOME_PROC_DEFAULT}"   # LG Home's process (pgrep/pkill -f pattern), frozen and unfrozen
HOME_APP_DIR="${HOME_APP_DIR:-/usr/palm/applications/com.webos.app.home}"   # missing: webOS 3, watch the home bar
SYSLOG="${SYSLOG:-/var/log/messages}"
THAW_ON_LAUNCH="${THAW_ON_LAUNCH:-0}" # 1 = unfreeze LG Home before every launch of the launcher
EMPTY_AS_HOME="${EMPTY_AS_HOME:-auto}"   # 1 = an empty foreground counts as LG Home, 0 = ignored, auto = 1 while HOME_PROC runs
FAILSAFE="${FAILSAFE:-1}"             # 1 = the launcher did not open even after a restart: open LG Home; 0 = message only
FAILSAFE_TRIES="${FAILSAFE_TRIES:-3}"           # FAILSAFE=1: launches of LG Home
FAILSAFE_WAIT="${FAILSAFE_WAIT:-5}"             # FAILSAFE=1: seconds to wait for LG Home after each launch
FAILSAFE_EXIT_WAIT="${FAILSAFE_EXIT_WAIT:-5}"   # FAILSAFE=1: seconds to wait for an LG Home with SIGTERM pending to exit
THAW_ON_STANDBY="${THAW_ON_STANDBY:-0}"   # 1 = unfreeze LG Home when the TV goes to standby
WAKE_POLL="${WAKE_POLL:-3}"           # wake_loop step, s (whole number)
WAKE_POLL_STANDBY="${WAKE_POLL_STANDBY:-1}"   # wake_loop step while the TV is in standby, s (whole number)
WAKE_JUMP="${WAKE_JUMP:-15}"          # uptime moved on by more than the step + this many s: the system slept
WAKE_SETTLE="${WAKE_SETTLE:-1}"       # after the TV is on again, wait this many s before looking at what is in front
WAKE_ACTIVE_WAIT="${WAKE_ACTIVE_WAIT:-60}"   # after the system slept, wait up to this many steps for the TV to be Active
WAKE_NAP="${WAKE_NAP:-sleep}"
STANDBY_FLAG="${STANDBY_FLAG:-/tmp/launcher-standby}"   # exists = the TV went to standby, waiting for it to turn on
STANDBY_REF="${STANDBY_REF:-/tmp/launcher-standby-ref}" # touched when the TV went to standby
WAKE_REF="${WAKE_REF:-/tmp/launcher-wake-ref}"          # touched when wake_loop saw the TV turn on
EVENT_LOG="${EVENT_LOG:-1}"           # 1 = log every report about the app in front
CHECK_EVERY="${CHECK_EVERY:-5}"       # s (whole number): how often check_loop compares the app in front with the last report; 0 = never
CHECK_MISSES="${CHECK_MISSES:-2}"     # this many checks in a row disagree: the subscription has gone quiet, make it again
HANDLE_MAX="${HANDLE_MAX:-60}"        # one report handled for this many s: the reader is stuck, make the subscription again
SILENT_MAX="${SILENT_MAX:-3}"         # after this many quiet subscriptions: ask once a second instead (poll_loop)
CHECK_NAP="${CHECK_NAP:-sleep}"
LAST_REPORT="${LAST_REPORT:-/tmp/launcher-homehook-last-report}"   # the last report from the subscription
HANDLING="${HANDLING:-/tmp/launcher-homehook-handling}"            # while a report is handled: the uptime (whole s) it began
SILENT_FLAG="${SILENT_FLAG:-/tmp/launcher-homehook-silent}"        # check_loop ended a quiet subscription (holds why)
POLLING="${POLLING:-/tmp/launcher-homehook-polling}"               # exists while poll_loop asks once a second
# The loading notification: auto = in the TV's menu language (Russian or English), any other text = that text,
# empty = none. Empty by default in the WATCH_STDIN test mode (the self-test must not show notifications).
if [ -n "$WATCH_STDIN" ]; then LOADING_TOAST="${LOADING_TOAST-}"; else LOADING_TOAST="${LOADING_TOAST-auto}"; fi
TOAST_LANG="${TOAST_LANG:-auto}"      # ru, en, or auto (the TV's menu language: ru* = Russian, anything else = English)
TOAST_DELAY="${TOAST_DELAY:-3}"       # notify only if the launcher is not in front this many s after it was asked for
TOAST_HOLD="${TOAST_HOLD:-60}"        # wait this many s for the launcher (or another app) to close the notification
TOAST_NAP="${TOAST_NAP:-sleep}"
TLOCK="${TLOCK:-/tmp/launcher-toast-lock}"   # the notification helper is running (holds the uptime it started at)
ALIVE="${ALIVE:-/tmp/launcher-alive}"        # touched by the launcher whenever it becomes visible
EMPTY_DELAY="${EMPTY_DELAY:-0.5}"     # the foreground must stay empty this many s (a sleep without fractions waits 1 s)
GONE_DELAY="${GONE_DELAY:-5}"         # launcher not found: look again after this many s (files vanish during an update)
ALLOW_MAX_S="${ALLOW_MAX_S:-30}"      # ALLOW is dropped if LG Home did not come to the front within this time
VERIFY_TRIES="${VERIFY_TRIES:-8}"     # asks again this many times, then closes the launcher and starts it again
RESTART_WAIT="${RESTART_WAIT:-30}"    # seconds to wait for the launcher after that restart
# VERIFY_WINDOW, s: longer than a whole check, so checks never overlap. With the defaults a check takes
# (VERIFY_TRIES + 1) + 1 + RESTART_WAIT = 40 s, with FAILSAFE=1 up to FAILSAFE_EXIT_WAIT + FAILSAFE_TRIES * FAILSAFE_WAIT
# = 20 s more, plus the time the luna-send calls take.
VERIFY_WINDOW="${VERIFY_WINDOW:-90}"
NAP="${NAP:-sleep}"
POLL_NAP="${POLL_NAP:-sleep}"
FRONT_URI="luna://com.webos.applicationManager/getForegroundAppInfo"
RUNNING_URI="luna://com.webos.applicationManager/running"
POWER_URI="luna://com.webos.service.tvpower/power/getPowerState"
CLOSE_URI="luna://com.webos.applicationManager/closeByAppId"
TOAST_URI="luna://com.webos.notification/createToast"
CLOSE_TOAST_URI="luna://com.webos.notification/closeToast"

# Seconds since boot with hundredths: /proc/uptime does not depend on the TV's clock.
uptime_now () { _up=; read -r _up _rest 2>/dev/null < "$UPTIME_FILE"; echo "${_up:-0}"; }
log () { echo "$(uptime_now) watcher: $*" >> "$LOG"; }

# "1234.56" -> 123456 (hundredths of a second). Not a number -> 0: an error inside $(( )) would stop the watcher.
centis () {
    _ci="${1%%.*}"; _cf=
    case "$1" in *.*) _cf="${1#*.}" ;; esac
    _cf="${_cf}00"; _cf="${_cf%"${_cf#??}"}"
    case "$_ci$_cf" in *[!0-9]*) echo 0; return ;; esac
    _ci="${_ci#"${_ci%%[!0]*}"}"
    echo $(( ${_ci:-0} * 100 + 1$_cf - 100 ))
}
# Seconds (with hundredths) since $1 (a value of uptime_now).
elapsed () {
    _ed=$(( $(centis "$(uptime_now)") - $(centis "$1") ))
    [ "$_ed" -ge 0 ] || _ed=0
    printf '%d.%02d' $((_ed / 100)) $((_ed % 100))
}

# LG Home; on webOS 4.x the Home button opens com.webos.app.fullhome, which counts as LG Home too.
is_home () {
    case "$1" in
        *'"appId":"com.webos.app.home"'*|*'"appId": "com.webos.app.home"'*) return 0 ;;
        *'"appId":"com.webos.app.fullhome"'*|*'"appId": "com.webos.app.fullhome"'*) return 0 ;;
    esac
    return 1
}
is_empty () {
    case "$1" in *'"appId":""'*|*'"appId": ""'*) return 0 ;; esac
    return 1
}
is_launcher () {
    case "$1" in *"\"appId\":\"$LAUNCHER_ID\""*|*"\"appId\": \"$LAUNCHER_ID\""*) return 0 ;; esac
    return 1
}
sam_answered () {
    case "$1" in *'"returnValue":true'*|*'"returnValue": true'*) return 0 ;; esac
    return 1
}

freeze_home () { pkill -STOP -f "$HOME_PROC" 2>/dev/null; }
thaw_home () { pkill -CONT -f "$HOME_PROC" 2>/dev/null; }

front () { "$LUNA" -n 1 "$FRONT_URI" '{}' 2>/dev/null; }

# The TV is on and not turning off. No answer, or no "state" in it: taken as on.
tv_active () {
    p=$("$LUNA" -n 1 "$POWER_URI" '{}' 2>/dev/null)
    case "$p" in
        *'"processing"'*) return 1 ;;
        *'"state":"Active"'*|*'"state": "Active"'*) return 0 ;;
        *'"state"'*) return 1 ;;
    esac
    return 0
}

# The power state on one line, for the log; the appId out of a report.
power_line () { "$LUNA" -n 1 "$POWER_URI" '{}' 2>/dev/null | tr -d '\n' | tr -s ' ' | cut -c1-200; }
app_of () { a=$(echo "$1" | sed -n 's/.*"appId": *"\([^"]*\)".*/\1/p'); echo "${a:-(empty)}"; }

# Does an empty foreground count as LG Home? (auto: only while LG Home's own process exists, i.e. where it is frozen)
empty_counts () {
    case "$EMPTY_AS_HOME" in 1) return 0 ;; 0) return 1 ;; esac
    [ -n "$(home_pids)" ]
}

# The language of the notifications: ru when the TV's menu language is Russian, en otherwise.
toast_lang () {
    case "$TOAST_LANG" in ru|en) echo "$TOAST_LANG"; return ;; esac
    tl_loc=$("$LUNA" -n 1 luna://com.webos.settingsservice/getSystemSettings '{"keys":["localeInfo"]}' 2>/dev/null | tr -d '\n ' | sed -n 's/.*"UI":"\([^"]*\)".*/\1/p')
    case "$tl_loc" in ru*) echo ru ;; *) echo en ;; esac
}
# The text of a notification: msg loading | restarted | no_open | home_opened | none_open
msg () {
    if [ "$(toast_lang)" = ru ]; then
        case "$1" in
            loading) echo "Домашний экран загружается…" ;;
            restarted) echo "$APP_NAME не открывался и был перезапущен" ;;
            no_open) echo "$APP_NAME не открывается. Аварийный выход: $STOP_HINT" ;;
            home_opened) echo "$APP_NAME не открывается: открыт LG Home" ;;
            none_open) echo "$APP_NAME и LG Home не открываются. Аварийный выход: $STOP_HINT" ;;
        esac
    else
        case "$1" in
            loading) echo "Home screen is loading…" ;;
            restarted) echo "$APP_NAME did not open and was started again" ;;
            no_open) echo "$APP_NAME does not open. Emergency exit: $STOP_HINT" ;;
            home_opened) echo "$APP_NAME does not open: LG Home is open" ;;
            none_open) echo "$APP_NAME and LG Home do not open. Emergency exit: $STOP_HINT" ;;
        esac
    fi
}

# The TV goes to standby. LG Home stays frozen (THAW_ON_STANDBY=0): unfrozen, it came to the front during standby.
standby_begin () {
    [ -f "$STANDBY_FLAG" ] && return
    date +%s > "$STANDBY_FLAG"
    : > "$STANDBY_REF"
    if [ "$THAW_ON_STANDBY" = 1 ]; then thaw_home; th="LG Home unfrozen"; else th="LG Home left as it is"; fi
    log "standby: foreground is empty and the TV is not Active ($(power_line)): $th, waiting for the TV to turn on"
}

# The TV is on again. LG Home, nothing or the launcher in front: open the launcher (for the launcher itself that is a
# relaunch over itself: its window may not have come back), unless the launcher has already shown itself since the TV
# went to standby or turned on. Another app in front: left alone. The notification comes from start_toast, only if the
# launcher is still not in front TOAST_DELAY s later.
wake_open () {
    $WAKE_NAP "$WAKE_SETTLE"
    f=$(front)
    if [ -f "$ALLOW" ] || takeover_active || [ -f "$STOPPED" ]; then
        log "wake ($1): LG Home is allowed, takeover is active or the emergency exit is on: nothing to do"; return
    fi
    if [ ! -f "$LAUNCHER/appinfo.json" ]; then log "wake ($1): Hearth is not installed: nothing to do"; return; fi
    # (file times are compared to the second)
    if is_launcher "$f" && [ -f "$WAKE_REF" ] && [ "$ALIVE" -nt "$WAKE_REF" ]; then
        log "wake ($1): Hearth is in front and has shown itself since the TV turned on ($ALIVE is newer): nothing to do"; return
    fi
    if is_launcher "$f" && [ -f "$STANDBY_REF" ] && [ "$ALIVE" -nt "$STANDBY_REF" ]; then
        log "wake ($1): Hearth is in front and has shown itself since the TV went to standby ($ALIVE is newer): nothing to do"; return
    fi
    if is_home "$f" || is_empty "$f" || is_launcher "$f"; then
        open_launcher
        log "wake ($1): foreground $(app_of "$f"): opened the launcher (the request took $call_s s$keep_note)"
        touch "$MARK"
        start_verify
        start_toast
    else
        log "wake ($1): another app is in front ($(app_of "$f")): left as it is"
    fi
}

# Runs in the background as long as the watcher does. Costs next to nothing: reads /proc/uptime every WAKE_POLL s
# (WAKE_POLL_STANDBY s while the TV is in standby) and calls luna-send only after the TV went to standby or after a
# jump of the clock (the system slept).
wake_loop () {
    read -r wl_last _r < "$UPTIME_FILE"; wl_last=${wl_last%%.*}
    while kill -0 "$1" 2>/dev/null; do
        if [ -f "$STANDBY_FLAG" ]; then wl_poll=$WAKE_POLL_STANDBY; else wl_poll=$WAKE_POLL; fi
        $WAKE_NAP "$wl_poll"
        read -r wl_now _r < "$UPTIME_FILE"; wl_now=${wl_now%%.*}
        wl_jump=$((wl_now - wl_last - wl_poll)); wl_last=$wl_now
        [ -f "$STOPPED" ] && continue
        if [ "$wl_jump" -gt "$WAKE_JUMP" ]; then
            log "the system slept about $wl_jump s (uptime jumped): waiting for the TV to be Active"
            wl_n=0
            until tv_active; do
                wl_n=$((wl_n + 1)); [ "$wl_n" -ge "$WAKE_ACTIVE_WAIT" ] && break
                $WAKE_NAP 1
            done
            if tv_active; then rm -f "$STANDBY_FLAG"; : > "$WAKE_REF"; log "the TV is Active ($(power_line))"; wake_open "after sleep"; rm -f "$STANDBY_REF"
            else date +%s > "$STANDBY_FLAG"; log "the TV is still not Active ($(power_line)): waiting for it"; fi
            read -r wl_last _r < "$UPTIME_FILE"; wl_last=${wl_last%%.*}
        elif [ -f "$STANDBY_FLAG" ] && tv_active; then
            rm -f "$STANDBY_FLAG"; : > "$WAKE_REF"
            log "the TV is on again ($(power_line))"
            wake_open "after standby"
            rm -f "$STANDBY_REF"
            read -r wl_last _r < "$UPTIME_FILE"; wl_last=${wl_last%%.*}
        fi
    done
}

# The foreground is empty for a split second between two apps and when the TV goes to standby.
# A sleep that does not take "0.5" (an error) waits 1 s instead.
empty_for_real () {
    $NAP "$EMPTY_DELAY" 2>/dev/null || $NAP 1
    is_empty "$(front)" && tv_active
}

# LG Home still in front, or nothing while the TV is on: the launcher has not come to the front.
still_home () { is_home "$1" || { is_empty "$1" && tv_active; }; }

# launcher-takeover (Hearth 1.x) is on, its stand-in really is mounted over LG Home's folder and its watcher runs: it
# opens the launcher itself, a second watcher would only get in the way. LG Home is left alone then.
takeover_active () {
    [ -f "$TAKEOVER_FLAG" ] || return 1
    grep -qF " $TAKEOVER_DIR " "$MOUNTS" 2>/dev/null || return 1
    tp=$(cat "$TAKEOVER_PID" 2>/dev/null)
    [ -n "$tp" ] && kill -0 "$tp" 2>/dev/null
}

# A system notification (as the Homebrew Channel's own tools send them). The answer goes to the log.
toast () {
    r=$("$LUNA" -n 1 -a webosbrew "$TOAST_URI" "{\"sourceId\":\"webosbrew\",\"message\":\"$1\"}" 2>&1)
    log "toast \"$1\": ${r:-no reply}"
}

# Closes a notification by its toastId: first as webosbrew (like createToast), and if that is refused, without -a.
# Both answers go to the log.
close_toast () {
    ct=$("$LUNA" -n 1 -a webosbrew "$CLOSE_TOAST_URI" "{\"toastId\":\"$1\"}" 2>&1)
    if ! sam_answered "$ct"; then
        ct2=$("$LUNA" -n 1 "$CLOSE_TOAST_URI" "{\"toastId\":\"$1\"}" 2>&1)
        ct="${ct:-no reply}; without -a webosbrew: ${ct2:-no reply}"
    fi
    log "$2: closeToast $1: ${ct:-no reply}"
}

# The loading notification. Once a second for TOAST_DELAY s it looks at what is in front: the launcher or another app
# means no notification is needed. Still LG Home or nothing (and the TV on): the notification is shown; then, once a
# second for up to TOAST_HOLD s, it waits for something other than LG Home or nothing to be in front (or for the user to
# open LG Home with the tile, ALLOW) and closes the notification.
loading_toast () {
    lt_w=0; lt_f=
    while [ "$lt_w" -lt "$TOAST_DELAY" ]; do
        $TOAST_NAP 1; lt_w=$((lt_w + 1))
        lt_f=$(front)
        case "$lt_f" in *'"appId"'*) ;; *) continue ;; esac
        is_home "$lt_f" || is_empty "$lt_f" || return 0
    done
    case "$lt_f" in *'"appId"'*) ;; *) log "loading toast: no answer from SAM: no toast"; return 0 ;; esac
    if [ -f "$ALLOW" ] || [ -f "$STOPPED" ]; then return 0; fi
    if ! tv_active; then log "loading toast: the TV is not Active: no toast"; return 0; fi
    lt_txt="$LOADING_TOAST"; [ "$lt_txt" = auto ] && lt_txt=$(msg loading)
    r=$("$LUNA" -n 1 -a webosbrew "$TOAST_URI" "{\"sourceId\":\"webosbrew\",\"message\":\"$lt_txt\"}" 2>&1)
    lt_id=$(echo "$r" | tr -d '\n' | sed -n 's/.*"toastId": *"\([^"]*\)".*/\1/p')
    log "Hearth is not in front $TOAST_DELAY s after the request (foreground $(app_of "$lt_f")): toast \"$lt_txt\": ${r:-no reply}"
    [ -n "$lt_id" ] || return 0
    lt_w=0
    while [ "$lt_w" -lt "$TOAST_HOLD" ]; do
        $TOAST_NAP 1; lt_w=$((lt_w + 1))
        if [ -f "$ALLOW" ]; then close_toast "$lt_id" "LG Home is allowed (stock.sh)"; return 0; fi
        lt_f=$(front)
        case "$lt_f" in *'"appId"'*) ;; *) continue ;; esac
        if ! is_home "$lt_f" && ! is_empty "$lt_f"; then
            close_toast "$lt_id" "$(app_of "$lt_f") is in front $lt_w s after the toast"; return 0
        fi
    done
    log "toast $lt_id: Hearth is still not in front $TOAST_HOLD s after the toast: it is not closed"
}

# Starts the notification helper in the background, unless LOADING_TOAST is empty or a helper is already running
# (TLOCK younger than TOAST_DELAY + TOAST_HOLD + 5 s).
start_toast () {
    [ -n "$LOADING_TOAST" ] || return 0
    st_now=$(uptime_now); st_now="${st_now%%.*}"
    if [ -f "$TLOCK" ]; then
        st_began=$(cat "$TLOCK" 2>/dev/null)
        case "$st_began" in ''|*[!0-9]*) st_began=0 ;; esac
        st_age=$((st_now - st_began))
        [ "$st_age" -ge 0 ] && [ "$st_age" -lt $((TOAST_DELAY + TOAST_HOLD + 5)) ] && return 0
    fi
    echo "$st_now" > "$TLOCK"
    ( ( loading_toast; rm -f "$TLOCK" ) </dev/null >/dev/null 2>&1 & )
}

# ALLOW (written by stock.sh) = the user opened LG Home on purpose. It is dropped when the user leaves LG Home, or if LG
# Home never came to the front within ALLOW_MAX_S s. When ALLOW is gone (removed by FAILSAFE or by hand), the note
# "LG Home was on screen" is dropped too, or the next ALLOW would be dropped at once, before LG Home comes to the front.
allow_home_seen=0
clear_stale_allow () {
    [ -f "$ALLOW" ] || { allow_home_seen=0; return 0; }
    if [ "$allow_home_seen" = 1 ]; then
        rm -f "$ALLOW"; allow_home_seen=0
        log "LG Home was left: replacing it again"
        return 0
    fi
    now=$(date +%s)
    since=$(cat "$ALLOW" 2>/dev/null); since="${since:-0}"
    if [ $((now - since)) -gt "$ALLOW_MAX_S" ]; then
        rm -f "$ALLOW"
        log "LG Home was allowed but never came to the front: replacing it again"
    fi
}

# Opens the launcher; LG Home stays frozen meanwhile (THAW_ON_LAUNCH=0).
# With "Keep Hearth ready" on: keepAlive only when the launcher is not in memory (a relaunch of a kept page with launch
# parameters makes the TV load the page again; a plain launch just brings it to the front), as in Hearth's own helper.
# call_s = how long the request took (luna-send waits for SAM's answer; with Keep Hearth ready, the running query too),
# keep_note = which kind of launch it was (empty without Keep Hearth ready): for the callers' log lines.
open_launcher () {
    [ "$THAW_ON_LAUNCH" = 1 ] && thaw_home
    _t0=$(uptime_now)
    _ka=; keep_note=
    if [ -s "$KEEP_FLAG" ]; then
        case "$("$LUNA" -n 1 "$RUNNING_URI" '{}' 2>/dev/null)" in
            *"\"id\":\"$LAUNCHER_ID\""*|*"\"id\": \"$LAUNCHER_ID\""*) keep_note="; Keep Hearth ready: Hearth is in memory, plain launch" ;;
            *) _ka=',"keepAlive":true'; keep_note="; Keep Hearth ready: Hearth is not in memory, keepAlive launch" ;;
        esac
    fi
    "$LUNA" -n 1 -a com.webos.app.home luna://com.webos.applicationManager/launch "{\"id\":\"$LAUNCHER_ID\"$_ka}" >/dev/null 2>&1
    call_s=$(elapsed "$_t0")
}

# LG Home's processes: pid, state (R/S/D/T/Z) and a pending SIGTERM, from /proc/PID/status.
home_pids () { pgrep -f "$HOME_PROC" 2>/dev/null; }
proc_state () { sed -n 's/^State:[[:space:]]*\([A-Za-z]\).*/\1/p' "/proc/$1/status" 2>/dev/null; }
# The signal masks in /proc/PID/status are 16 hex digits. SIGTERM = 15 is bit 14 (0x4000): the 4th digit from the
# right, bit value 4 (digits 4-7, c-f). term_bit FIELD PID: is that bit set in the field?
# SigPnd/ShdPnd = pending signals: the launcher sends SIGTERM to an LG Home that is not on screen (Close LG Home), and a
# frozen process keeps it pending until SIGCONT. SigCgt = signals the process handles itself: without a handler the
# process ends after SIGCONT, with one it decides (on webOS 25 LG Home went on running).
term_bit () {
    for _m in $(sed -n "s/^$1:[[:space:]]*\([0-9a-fA-F]*\).*/\1/p" "/proc/$2/status" 2>/dev/null); do
        _m="${_m%???}"
        case "$_m" in *[4567cdefCDEF]) return 0 ;; esac
    done
    return 1
}
term_pending () { term_bit 'S[a-z]*Pnd' "$1"; }
term_caught () { term_bit SigCgt "$1"; }
# The pids out of $1 that are still alive: still an LG Home process, and not a zombie.
alive_home_pids () {
    _all=" $(echo $(home_pids)) "
    for _p in $1; do
        case "$_all" in *" $_p "*) ;; *) continue ;; esac
        [ "$(proc_state "$_p")" = Z ] || printf '%s ' "$_p"
    done
}
# A working LG Home (not frozen, not a zombie, not one that is about to end): prints its pid.
home_up () {
    for _p in $(home_pids); do
        case " $fs_doomed " in *" $_p "*) continue ;; esac
        case "$(proc_state "$_p")" in S|R|D) echo "$_p"; return 0 ;; esac
    done
    return 1
}

# FAILSAFE=1: open LG Home and check that it is on screen. First what stock.sh does (the "LG Home" tile): ALLOW and
# unfreeze. An LG Home with SIGTERM pending may end once unfrozen, and a launch sent to it would be lost: wait up to
# FAILSAFE_EXIT_WAIT s to see whether it ends. If it does not, SIGTERM did not stop it: it is not killed, it is opened.
# Then up to FAILSAFE_TRIES launches, each followed by up to FAILSAFE_WAIT s of waiting for LG Home to be in front with
# its process running. When the user leaves LG Home, ALLOW is dropped and the launcher replaces LG Home again.
failsafe_home () {
    date +%s > "$ALLOW"
    fs_doomed=; fs_any=
    for fs_p in $(home_pids); do
        fs_any=1
        if term_pending "$fs_p"; then
            fs_doomed="$fs_doomed $fs_p"
            if term_caught "$fs_p"; then fs_h=yes; else fs_h=no; fi
            log "FAILSAFE=1: LG Home pid $fs_p (state $(proc_state "$fs_p")) has SIGTERM pending (SIGTERM handler: $fs_h): waiting up to $FAILSAFE_EXIT_WAIT s to see whether it exits after SIGCONT"
        else
            log "FAILSAFE=1: LG Home pid $fs_p (state $(proc_state "$fs_p")), no SIGTERM pending"
        fi
    done
    [ -n "$fs_any" ] || log "FAILSAFE=1: no LG Home process is running"
    fs_c0=$(uptime_now)
    thaw_home
    $NAP 1
    if [ -n "$fs_doomed" ]; then
        fs_w=1
        fs_left=$(alive_home_pids "$fs_doomed")
        while [ -n "$fs_left" ] && [ "$fs_w" -lt "$FAILSAFE_EXIT_WAIT" ]; do
            $NAP 1
            fs_w=$((fs_w + 1))
            fs_left=$(alive_home_pids "$fs_doomed")
        done
        if [ -z "$fs_left" ]; then
            log "FAILSAFE=1: LG Home pid$fs_doomed has exited (checked $(elapsed "$fs_c0") s after SIGCONT)"
        else
            log "FAILSAFE=1: LG Home pid ${fs_left% } still runs $(elapsed "$fs_c0") s after SIGCONT: SIGTERM did not end it, it is not killed"
            fs_doomed=
        fi
    fi
    fs_n=0
    while [ "$fs_n" -lt "$FAILSAFE_TRIES" ]; do
        fs_n=$((fs_n + 1))
        date +%s > "$ALLOW"
        thaw_home
        fs_t0=$(uptime_now)
        r=$("$LUNA" -n 1 luna://com.webos.applicationManager/launch '{"id":"com.webos.app.home"}' 2>&1)
        log "FAILSAFE=1: LG Home is allowed (as with stock.sh) and unfrozen, launch $fs_n of $FAILSAFE_TRIES (the request took $(elapsed "$fs_t0") s): ${r:-no reply}"
        fs_w=0
        while [ "$fs_w" -lt "$FAILSAFE_WAIT" ]; do
            $NAP 1
            fs_w=$((fs_w + 1))
            fs_f=$(front)
            case "$fs_f" in *'"appId"'*) ;; *) continue ;; esac
            if is_home "$fs_f"; then
                fs_p=$(home_up) || continue
                log "FAILSAFE=1: LG Home is in front (pid $fs_p) $(elapsed "$fs_t0") s after launch $fs_n"
                toast "$(msg home_opened)"
                return
            elif is_launcher "$fs_f"; then
                rm -f "$ALLOW"
                freeze_home
                log "FAILSAFE=1: Hearth is in front after all: ALLOW removed, LG Home frozen again"
                return
            elif ! is_empty "$fs_f"; then
                log "FAILSAFE=1: another app is in front: no more waiting"
                return
            elif ! tv_active; then
                log "FAILSAFE=1: the TV is not on: no more waiting"
                return
            fi
        done
    done
    log "FAILSAFE=1: LG Home is not in front after $FAILSAFE_TRIES launches (it is not frozen, ALLOW stays). Emergency exit: $STOP_HINT"
    toast "$(msg none_open)"
}

# Against an endless loop: close the launcher, start it again and wait up to RESTART_WAIT s. Not there: FAILSAFE=1
# opens LG Home; FAILSAFE=0 leaves LG Home frozen (the way out is then stop.sh).
recover () {
    log "Hearth did not come to the front after $VERIFY_TRIES more tries: closing it and starting it again"
    r=$("$LUNA" -n 1 "$CLOSE_URI" "{\"id\":\"$LAUNCHER_ID\"}" 2>&1)
    log "closeByAppId: ${r:-no reply}"
    $NAP 1
    touch "$MARK"
    open_launcher
    log "Hearth started again (the request took $call_s s$keep_note): waiting for it up to $RESTART_WAIT s"
    waited=0
    while [ "$waited" -lt "$RESTART_WAIT" ]; do
        $NAP 1
        waited=$((waited + 1))
        [ -f "$ALLOW" ] && return
        takeover_active && return
        front=$(front)
        [ -n "$front" ] || continue
        if is_launcher "$front"; then
            freeze_home
            log "Hearth is in front after the restart (${waited} s)"
            toast "$(msg restarted)"
            return
        elif ! still_home "$front"; then
            log "another app is in front or the TV is not on: no more waiting"
            return
        fi
    done
    log "Hearth is still not in front $RESTART_WAIT s after the restart"
    if [ "$FAILSAFE" = 1 ] && tv_active; then
        failsafe_home
        return
    fi
    log "LG Home stays frozen. Emergency exit: $STOP_HINT"
    toast "$(msg no_open)"
}

# The launcher was asked for: once a second, check that it came to the front. While LG Home or nothing is in front,
# ask again (VERIFY_TRIES times), then restart the launcher (recover). LG Home is not unfrozen here.
verify () {
    [ -f "$MARK" ] || touch "$MARK"
    tries=0
    while :; do
        $NAP 1
        [ -f "$ALLOW" ] && return
        takeover_active && return
        front=$(front)
        if is_launcher "$front"; then
            freeze_home
            return
        elif still_home "$front"; then
            # the TV went to standby: no more tries, wake_loop opens the launcher when the TV is on again
            if [ -f "$STANDBY_FLAG" ] && ! tv_active; then
                log "the TV is not Active ($(power_line)): no more tries, Hearth is opened when the TV turns on"
                return
            fi
            if [ "$tries" -ge "$VERIFY_TRIES" ]; then recover; return; fi
            tries=$((tries + 1))
            open_launcher
            log "Foreground is still Home or empty: opened the launcher again (try $tries of $VERIFY_TRIES, the request took $call_s s$keep_note)"
        else
            return
        fi
    done
}

start_verify () {
    [ -n "$NO_VERIFY" ] && return
    now=$(uptime_now); now="${now%%.*}"
    if [ -f "$VLOCK" ]; then
        began=$(cat "$VLOCK" 2>/dev/null); began="${began:-0}"
        age=$((now - began))
        [ "$age" -ge 0 ] && [ "$age" -lt "$VERIFY_WINDOW" ] && return
    fi
    echo "$now" > "$VLOCK"
    ( ( verify; rm -f "$VLOCK" ) </dev/null >/dev/null 2>&1 & )
}

# The launcher was uninstalled while LG Home or nothing is in front: LG Home is unfrozen, or the TV would be left with
# no home screen at all. Looked at again after GONE_DELAY s, because the launcher's files vanish for a moment while it
# is being updated. 0 = uninstalled (LG Home unfrozen), 1 = back again.
gone_noted=0
launcher_gone () {
    if [ "$gone_noted" != 1 ]; then
        $NAP "$GONE_DELAY"
        [ -f "$LAUNCHER/appinfo.json" ] && return 1
        log "Hearth is not installed ($LAUNCHER/appinfo.json is missing): unfreezing LG Home, not opening the launcher"
        gone_noted=1
    fi
    thaw_home
    return 0
}

# One report from the TV about the app in front.
takeover_noted=0
asked=          # uptime_now when handle last asked for the launcher: for the "in front after N s" log line
handle () {
    line="$1"
    case "$line" in
        *'"appId"'*) ;;
        *'"returnValue":false'*|*'"returnValue": false'*)
            log "the subscription answered with an error: $(echo "$line" | cut -c1-200)"; return ;;
        *) return ;;
    esac
    if takeover_active; then
        if [ "$takeover_noted" != 1 ]; then
            log "launcher-takeover is on, mounted and its watcher runs: standing aside (LG Home is left as it is)"
            takeover_noted=1
        fi
        return
    fi
    takeover_noted=0
    # the power state only around standby (in normal use one more call would slow the hand-over down)
    if [ "$EVENT_LOG" = 1 ]; then
        if [ -f "$STANDBY_FLAG" ]; then log "event: foreground $(app_of "$line") ($(power_line))"; else log "event: foreground $(app_of "$line")"; fi
    fi
    # no LG Home process to freeze (EMPTY_AS_HOME=auto) or EMPTY_AS_HOME=0: an empty foreground is left alone, as in
    # Hearth's own helper
    if is_empty "$line" && ! empty_counts; then return; fi
    if is_home "$line" || is_empty "$line"; then
        if [ -f "$ALLOW" ]; then
            if is_home "$line"; then allow_home_seen=1; thaw_home; fi
            return
        fi
        if [ ! -f "$LAUNCHER/appinfo.json" ]; then
            launcher_gone && return
            line=$(front)                       # the launcher is back: what is in front now?
            is_home "$line" || is_empty "$line" || return
        fi
        gone_noted=0
        # the TV is in standby (switched off with the remote): nothing is launched, wake_loop opens the launcher later
        if [ -f "$STANDBY_FLAG" ] && ! tv_active; then
            log "the TV is not Active ($(power_line)): Hearth is opened when the TV turns on"
            return
        fi
        if is_empty "$line" && ! empty_for_real; then
            # empty because the TV is going to standby
            is_empty "$(front)" && ! tv_active && standby_begin
            return
        fi
        asked=$(uptime_now)
        rm -f "$STANDBY_FLAG" "$STANDBY_REF"    # the TV is on: any standby is over
        open_launcher
        log "Foreground is Home or empty: opened the launcher (the request took $call_s s$keep_note)"
        touch "$MARK"
        start_verify
        start_toast
    elif is_launcher "$line"; then
        if [ -n "$asked" ]; then log "Hearth is in front $(elapsed "$asked") s after the request"; asked=; fi
        clear_stale_allow
        [ -f "$ALLOW" ] || freeze_home
    else
        asked=
        clear_stale_allow
    fi
}

# webOS 3 has no LG Home app: Home shows a launcher bar over the app in front, which never changes the app in front.
# The surface manager logs each time the bar is shown. One such line: open the launcher, unless it is the app under the
# bar, or the user asked for LG's own Home in the last 10 seconds. (From Hearth's own helper.)
handle_bar () {
    case "$1" in *NL_HOME_SHOWN*) ;; *) return ;; esac
    case "$1" in *"\"foregroundId\":\"$LAUNCHER_ID\""*) return ;; esac
    if [ -f "$ALLOW" ]; then
        now="${FAKE_NOW:-$(date +%s)}"
        since=$(cat "$ALLOW" 2>/dev/null); since="${since:-0}"
        rm -f "$ALLOW"
        [ $((now - since)) -le 10 ] && return
    fi
    [ -f "$LAUNCHER/appinfo.json" ] || return
    open_launcher
    log "the home bar was shown: opened the launcher (the request took $call_s s$keep_note)"
    start_verify
}

# The subscription keeps ending at once on this TV: ask once a second instead. A report is handled only when the app in
# front has changed (the check after each launch asks again by itself).
poll_loop () {
    : > "$POLLING"                       # check_loop ends: there is no subscription to check any more
    pl_last=
    while :; do
        pl_f=$(front)
        case "$pl_f" in
            *'"appId"'*)
                pl_app=$(app_of "$pl_f")
                if [ "$pl_app" != "$pl_last" ]; then pl_last=$pl_app; handle "$pl_f"; fi ;;
        esac
        $POLL_NAP 1
    done
}

# Is the subscription still heard? 0 = no (why in sc_why): a report has been handled for HANDLE_MAX s, or the app in
# front is not the one in the last report. While a report is being handled (not for long), or SAM does not answer,
# there is nothing to compare: 1.
sub_check () {
    sc_h=; { read -r sc_h < "$HANDLING"; } 2>/dev/null
    if [ -n "$sc_h" ]; then
        sc_u=; { read -r sc_u _r < "$UPTIME_FILE"; } 2>/dev/null; sc_u=${sc_u%%.*}
        if [ $(( ${sc_u:-0} - sc_h )) -ge "$HANDLE_MAX" ]; then sc_why="one report has been handled for $(( ${sc_u:-0} - sc_h )) s"; return 0; fi
        return 1
    fi
    sc_f=$(front)
    case "$sc_f" in *'"appId"'*) ;; *) return 1 ;; esac
    sc_r=; { read -r sc_r < "$LAST_REPORT"; } 2>/dev/null
    sc_now=$(app_of "$sc_f"); sc_heard=$(app_of "$sc_r")
    [ "$sc_now" = "$sc_heard" ] && return 1
    sc_why="in front: $sc_now, the last report: $sc_heard"
    return 0
}

# Runs in the background as long as the watcher does ($1 = its pid). Every CHECK_EVERY s one question to SAM. The
# subscription has gone quiet: SILENT_FLAG is written (the watcher counts it) and the subscription's processes (luna-send
# and its reader: the watcher's only children while it waits) are killed; the watcher makes a new subscription. Ends
# after SILENT_MAX restarts or once poll_loop runs.
check_loop () {
    cl_miss=0; cl_n=0
    while kill -0 "$1" 2>/dev/null; do
        $CHECK_NAP "$CHECK_EVERY"
        kill -0 "$1" 2>/dev/null || return 0
        [ -f "$POLLING" ] && return 0
        [ -f "$STOPPED" ] && continue
        if sub_check; then cl_miss=$((cl_miss + 1)); else cl_miss=0; fi
        [ "$cl_miss" -ge "$CHECK_MISSES" ] || continue
        cl_miss=0; cl_n=$((cl_n + 1))
        log "the subscription has gone quiet ($sc_why; $CHECK_MISSES checks $CHECK_EVERY s apart): subscribing again ($cl_n of $SILENT_MAX)"
        echo "$sc_why" > "$SILENT_FLAG"
        # KILL at once (a quiet or stuck luna-send may not end on TERM): a second pass later could hit the new one
        pkill -9 -P "$1" 2>/dev/null
        [ "$cl_n" -ge "$SILENT_MAX" ] && return 0
    done
}

# At start LG Home is frozen at once, not only when the launcher first comes to the front.
freeze_at_start () {
    if [ ! -f "$LAUNCHER/appinfo.json" ]; then log "start: Hearth is not installed: LG Home is not frozen"; return; fi
    if [ -f "$ALLOW" ]; then log "start: LG Home is allowed (stock.sh): it is not frozen"; return; fi
    if takeover_active; then log "start: launcher-takeover is active: LG Home is left as it is"; return; fi
    if [ -z "$(home_pids)" ]; then log "start: no LG Home process ($HOME_PROC): nothing to freeze"; return; fi
    f=$(front)
    if ! sam_answered "$f"; then log "start: no answer from SAM: LG Home is not frozen yet"; return; fi
    if is_home "$f"; then log "start: LG Home is in front: it is frozen once Hearth is in front"; return; fi
    freeze_home
    log "start: LG Home frozen"
}

# Test modes (a line "TIME n" sets the clock of the home bar test).
if [ -n "$WATCH_STDIN" ]; then
    while IFS= read -r report; do handle "$report"; done
    exit 0
fi
if [ -n "$WATCH_BAR_STDIN" ]; then
    while IFS= read -r report; do
        case "$report" in
            "TIME "*) FAKE_NOW="${report#TIME }" ;;
            *) handle_bar "$report" ;;
        esac
    done
    exit 0
fi

if [ -f "$STOPPED" ]; then
    log "emergency exit is on ($STOPPED): not starting. To undo: $STOP_HINT resume"
    exit 0
fi
if [ -f "$PIDFILE" ]; then
    other=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$other" ] && [ "$other" != "$$" ] && kill -0 "$other" 2>/dev/null; then
        log "another watcher is already running (pid $other): exiting"
        exit 0
    fi
fi
echo $$ > "$PIDFILE"
rm -f "$VLOCK" "$TLOCK" "$STANDBY_FLAG" "$STANDBY_REF" "$SILENT_FLAG" "$POLLING"
# Stopping does not unfreeze LG Home: only stock.sh, stop.sh, FAILSAFE and turning the helper off do.
trap 'pkill -P $$ 2>/dev/null; log "stopped (pid $$), LG Home is left as it is"; [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"; exit 0' TERM INT
if [ -s "$KEEP_FLAG" ]; then _kr=on; else _kr=off; fi
log "started (pid $$, $APP_NAME $LAUNCHER_ID, THAW_ON_LAUNCH=$THAW_ON_LAUNCH, FAILSAFE=$FAILSAFE, THAW_ON_STANDBY=$THAW_ON_STANDBY, EMPTY_DELAY=$EMPTY_DELAY, EMPTY_AS_HOME=$EMPTY_AS_HOME, Keep Hearth ready: $_kr)"

if [ ! -d "$HOME_APP_DIR" ]; then
    # webOS 3: look at the end of the system log a few times a second. Reading the last lines (rather than following
    # the file) keeps working when the log is rotated.
    log "no LG Home app on this TV: watching the system log for the home bar"
    last=$(tail -n 40 "$SYSLOG" 2>/dev/null | grep NL_HOME_SHOWN | tail -n 1)
    while :; do
        usleep 400000 2>/dev/null || sleep 1
        line=$(tail -n 40 "$SYSLOG" 2>/dev/null | grep NL_HOME_SHOWN | tail -n 1)
        if [ -n "$line" ] && [ "$line" != "$last" ]; then
            last="$line"
            handle_bar "$line"
        fi
    done
fi

freeze_at_start
( wake_loop $$ </dev/null >/dev/null 2>&1 & )   # the TV turning on after standby
if [ "$CHECK_EVERY" -gt 0 ] 2>/dev/null; then
    ( check_loop $$ </dev/null >/dev/null 2>&1 & )   # is the subscription still heard?
fi

quick_ends=0; silent_ends=0
while :; do
    sub_t0=$(date +%s)
    rm -f "$SILENT_FLAG"; : > "$LAST_REPORT"; : > "$HANDLING"
    # the subscription in the background + wait: a kill (TERM) then works at once, not when the subscription ends.
    # For check_loop: each report is kept in LAST_REPORT, and HANDLING holds the uptime while it is handled (builtins
    # only: no extra process per report).
    "$LUNA" -i "$FRONT_URI" '{"subscribe":true}' 2>/dev/null | while IFS= read -r report; do
        kill -0 $$ 2>/dev/null || exit 0      # the main process was killed with kill -9: do not run on as an orphan
        hu=; { read -r hu _r < "$UPTIME_FILE"; } 2>/dev/null; echo "${hu%%.*}" > "$HANDLING"
        printf '%s\n' "$report" > "$LAST_REPORT"
        handle "$report"
        : > "$HANDLING"
    done &
    wait $!
    if [ -s "$SILENT_FLAG" ]; then
        # check_loop ended a quiet subscription (it has logged why): a new one at once, it does not count as ending
        rm -f "$SILENT_FLAG"; quick_ends=0; silent_ends=$((silent_ends + 1))
        if [ "$silent_ends" -ge "$SILENT_MAX" ]; then
            log "the subscription went quiet $silent_ends times: asking once a second instead"
            poll_loop
        fi
        continue
    fi
    if [ $(( $(date +%s) - sub_t0 )) -lt 5 ]; then quick_ends=$((quick_ends + 1)); else quick_ends=0; fi
    if [ "$quick_ends" -ge 3 ]; then
        log "the subscription keeps ending: asking once a second instead"
        poll_loop
    fi
    $NAP 2
done
