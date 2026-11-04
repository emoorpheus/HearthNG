#!/bin/sh
# Tests for the "Replace LG Home" helper (src/homehook) with real processes: freezing LG Home, the checks after each
# launch, FAILSAFE, notifications, standby and wake, apply.sh, stock.sh, stop.sh, guard.sh and diagnose.sh's self-test.
# Run: npm test, or by hand:
#   sh scripts/test-homehook-ng.sh                    with the system's sh, pkill, grep...
#   sh scripts/test-homehook-ng.sh /path/to/busybox   everything through BusyBox (ash, pkill, grep...), as on webOS
# A stand-in "flutter-client -i com.webos.app.home" is a real process: its State (T = frozen) and a pending SIGTERM are
# read from /proc, so these tests need Linux. Elsewhere (macOS) they are skipped with exit code 0; the portable tests are
# in scripts/test-homehook.sh. Never run on a TV (the script refuses).
# Stand-ins: luna-send (the TV's state is kept in files), the LG Home process (it ends on SIGTERM; with the file
# home_term_survive it handles SIGTERM and runs on, as LG Home did on a webOS 25 TV), a pkill wrapper (logs every call),
# /proc/mounts, /proc/uptime. Everything is in a temporary folder: the real /tmp/launcher-* and /media/developer are
# never touched.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/src/homehook"
BB="${1:-}"
if [ "$(uname -s 2>/dev/null)" != Linux ] || [ ! -r /proc/self/status ] || [ ! -r /proc/self/cmdline ]; then
    echo "skipped: these tests need Linux with /proc (here: $(uname -s 2>/dev/null || echo '?')); scripts/test-homehook.sh runs everywhere"
    exit 0
fi
if [ -n "$BB" ] && [ -z "${IN_BB:-}" ]; then
    case "$BB" in /*) ;; *) BB="$(pwd)/$BB" ;; esac
    [ -x "$BB" ] || { echo "no BusyBox at $BB"; exit 2; }
    IN_BB=1 exec "$BB" sh "$0" "$BB"
fi
if [ -d /var/lib/webosbrew ] || [ -d /media/developer ]; then
    echo "This looks like a TV: not running the tests."; exit 2
fi
if pgrep -f '[f]lutter-client -i com.webos.app.home' >/dev/null 2>&1 || pgrep -f '[l]auncher-homehook/(watch|guard).sh' >/dev/null 2>&1; then
    echo "A 'flutter-client -i com.webos.app.home', launcher-homehook/watch.sh or guard.sh process is running here: not running the tests."; exit 2
fi

T=$(mktemp -d /tmp/hearthng-test.XXXXXX) || exit 2
mkdir -p "$T/bin"
if [ -n "$BB" ]; then
    REAL_PKILL="$BB pkill"
    mkdir -p "$T/bb"
    for a in sh ash pkill pgrep grep sed cat sleep kill ps tail head cut tr touch rm mkdir cp mv cmp wc date \
             nohup dirname basename env printf echo test expr ls chmod ln timeout usleep; do
        ln -s "$BB" "$T/bb/$a"
    done
    PATH="$T/bin:$T/bb:$PATH"
    SHEBANG="#!$BB sh"
    echo "Shell and tools: $("$BB" | head -n 1)"
else
    REAL_PKILL=$(command -v pkill)
    PATH="$T/bin:$PATH"
    SHEBANG="#!/bin/sh"
    echo "Shell: $(readlink -f /bin/sh 2>/dev/null || echo /bin/sh), pkill: $REAL_PKILL"
fi
export PATH
echo "Temporary folder: $T"

ID=com.hearthng.launcher
S=$T/state; W=$T/work
HOOKD=$T/media/launcher-homehook
APPD=$T/apps/$ID

# ---------- stand-ins ----------
{ echo "$SHEBANG"; cat <<'MOCK'
# luna-send stand-in: the TV's state is in the files of $MOCK_STATE, every call is written to $MOCK_STATE/calls
S="$MOCK_STATE"
ID=com.hearthng.launcher
caller=; sub=0; uri=; payload=
while [ $# -gt 0 ]; do
    case "$1" in
        -n|-w) shift ;;
        -a) caller="$2"; shift ;;
        -i) sub=1 ;;
        -f) ;;
        luna://*) uri="$1"; payload="${2:-}"; [ $# -ge 2 ] && shift ;;
    esac
    shift
done
home_state () {
    p=$(cat "$S/home_pid" 2>/dev/null)
    [ -n "$p" ] && sed -n 's/^State:[[:space:]]*\([A-Za-z]\).*/\1/p' "/proc/$p/status" 2>/dev/null
}
front_json () {
    # $S/front_toast_n: that many answers name HearthNG's own notification window (com.hearthng.toast) instead
    ftn=$(cat "$S/front_toast_n" 2>/dev/null)
    if [ "${ftn:-0}" -gt 0 ]; then
        echo $((ftn - 1)) > "$S/front_toast_n"; echo "fronttoast" >> "$S/calls"
        printf '{"returnValue":true,"appId":"com.hearthng.toast","processId":"","windowId":""}\n'; return
    fi
    printf '{"returnValue":true,"appId":"%s","processId":"","windowId":""}\n' "$(cat "$S/front" 2>/dev/null)"
}
case "$uri" in
    */getForegroundAppInfo)
        if [ "$sub" = 1 ]; then
            echo sub >> "$S/subs"
            # $S/sub_ends: the subscription ends at once, without a report
            if [ -f "$S/sub_ends" ]; then echo end >> "$S/sub_ends"; exit 0; fi
            # $S/sub_error_once: this subscription answers with an error and then says nothing (as a cancelled one)
            if [ -f "$S/sub_error_once" ]; then
                rm -f "$S/sub_error_once"
                echo '{"returnValue":false,"errorCode":-1,"errorText":"cancelled (mock)"}'
                exec "$(dirname "$0")/hold" subscription
            fi
            # $S/sub_live: a report for every change of $S/front, as SAM does
            if [ -f "$S/sub_live" ]; then
                last=$(cat "$S/front" 2>/dev/null); front_json || exit 0
                while :; do
                    sleep 0.1; cur=$(cat "$S/front" 2>/dev/null)
                    if [ "$cur" != "$last" ]; then last=$cur; front_json || exit 0; fi
                done
            fi
            # otherwise one report (none with $S/sub_mute or $S/sam_down), then nothing: a quiet subscription
            [ -f "$S/sam_down" ] || [ -f "$S/sub_mute" ] || front_json
            exec "$(dirname "$0")/hold" subscription
        fi
        [ -f "$S/sam_down" ] && exit 1
        front_json ;;
    */getPowerState) printf '{"returnValue":true,"state":"%s"}\n' "$(cat "$S/power" 2>/dev/null || echo Active)" ;;
    */running)
        # apps in memory (shaped like SAM's answer): the launcher is listed if $S/launcher_running exists;
        # $S/running_reply = a whole answer of its own
        echo "running caller=$caller" >> "$S/calls"
        if [ -f "$S/running_reply" ]; then cat "$S/running_reply"
        elif [ -f "$S/launcher_running" ]; then
            echo "{\"returnValue\":true,\"running\":[{\"id\":\"com.webos.app.home\",\"processid\":\"1001\"},{\"id\":\"$ID\",\"processid\":\"1002\"}]}"
        else
            echo '{"returnValue":true,"running":[{"id":"com.webos.app.home","processid":"1001"}]}'
        fi ;;
    */launch)
        # HearthNG's own notification app: counted apart ("owntoast"); $S/owntoast_deny: the launch is refused
        case "$payload" in *'"com.hearthng.toast"'*)
            echo "owntoast caller=$caller $payload" >> "$S/calls"
            if [ -f "$S/owntoast_deny" ]; then echo '{"returnValue":false,"errorCode":-101,"errorText":"not found (mock)"}'
            else echo '{"returnValue":true,"processId":"","instanceId":"t1"}'; fi
            exit 0 ;;
        esac
        n=$(( $(cat "$S/launch_count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/launch_count"
        echo "launch caller=$caller home=$(home_state) $payload" >> "$S/calls"
        # $S/launch_hang: the request never comes back (the watcher's reader stays inside handle)
        [ -f "$S/launch_hang" ] && exec "$(dirname "$0")/hold" launch
        # the request "took" until this time (uptime): the test sees how long watch.sh says the request took
        [ -f "$S/uptime_after_launch" ] && cp "$S/uptime_after_launch" "$S/uptime"
        case "$payload" in *'"com.webos.app.home"'*)
            # LG Home. home_swallow: that many launches are lost (an answer, but nothing changes on screen);
            # launcher_on_home_launch: the launcher comes to the front instead; no LG Home process (it ended): a new one
            # is started, as SAM does; otherwise the running process comes to the front.
            sw=$(cat "$S/home_swallow" 2>/dev/null)
            if [ "${sw:-0}" -gt 0 ]; then echo $((sw - 1)) > "$S/home_swallow"; echo '{"returnValue":true}'; exit 0; fi
            if [ -f "$S/launcher_on_home_launch" ]; then echo "$ID" > "$S/front"; echo '{"returnValue":true}'; exit 0; fi
            hs=$(home_state)
            if [ -z "$hs" ] || [ "$hs" = Z ]; then
                ( "$(dirname "$0")/flutter-client" -i com.webos.app.home </dev/null >/dev/null 2>&1 & echo $! > "$S/home_pid" )
                echo "start $(cat "$S/home_pid")" >> "$S/home.log"
            fi
            echo com.webos.app.home > "$S/front"; echo '{"returnValue":true}'; exit 0 ;;
        esac
        a=$(cat "$S/appear_after" 2>/dev/null)
        if [ -n "$a" ] && [ "$n" -ge "$a" ]; then echo "$ID" > "$S/front"; fi
        if [ -f "$S/appear_after_close" ] && [ -f "$S/closed" ]; then echo "$ID" > "$S/front"; fi
        echo '{"returnValue":true}' ;;
    */closeByAppId) echo "close $payload" >> "$S/calls"; touch "$S/closed"; echo '{"returnValue":true}' ;;
    */getSystemSettings)
        if [ -f "$S/locale" ]; then printf '{"returnValue":true,"settings":{"localeInfo":{"locales":{"UI":"%s","TV":"%s"}}}}\n' "$(cat "$S/locale")" "$(cat "$S/locale")"
        else echo '{"returnValue":false}'; fi ;;
    */createToast)
        # as on a webOS 25 TV: {"returnValue":true,"toastId":"webosbrew-..."}
        tn=$(( $(cat "$S/toast_count" 2>/dev/null || echo 0) + 1 )); echo "$tn" > "$S/toast_count"
        echo "toast caller=$caller $payload" >> "$S/calls"; echo "{\"returnValue\":true,\"toastId\":\"webosbrew-$tn\"}" ;;
    */closeToast)
        # $S/closetoast_deny: refused for webosbrew (to test the second call without -a)
        echo "closetoast caller=$caller $payload" >> "$S/calls"
        if [ -f "$S/closetoast_deny" ] && [ "$caller" = webosbrew ]; then echo '{"returnValue":false,"errorCode":-1,"errorText":"denied (mock)"}'
        else echo '{"returnValue":true}'; fi ;;
    *) echo "other $uri $payload" >> "$S/calls"; echo '{"returnValue":false}' ;;
esac
MOCK
} > "$T/bin/luna-send"
# "LG Home": a real process with the right command line. On SIGTERM (a frozen one: after SIGCONT) it waits
# $S/home_term_delay s (if that file exists), leaves the screen (empty foreground) and ends.
# With $S/home_term_survive it handles SIGTERM and runs on.
{ echo "$SHEBANG"; echo "S='$S'"; cat <<'MOCK'
bye () {
    if [ -f "$S/home_term_survive" ]; then echo "term $$: handled, still running" >> "$S/home.log"; return 0; fi
    d=$(cat "$S/home_term_delay" 2>/dev/null); i=0
    while [ "$i" -lt "${d:-0}" ]; do sleep 1; i=$((i + 1)); done
    [ "$(cat "$S/front" 2>/dev/null)" = com.webos.app.home ] && : > "$S/front"
    echo "exit $$" >> "$S/home.log"
    exit 0
}
trap bye TERM
while :; do sleep 1 & wait $!; done
MOCK
} > "$T/bin/flutter-client"
# pkill wrapper: logs every call (STOP/CONT/-9...) and runs the real pkill
printf '%s\n' "$SHEBANG" '[ -n "${MOCK_STATE:-}" ] && echo "$*" >> "$MOCK_STATE/pkill.log"' "exec $REAL_PKILL \"\$@\"" > "$T/bin/pkill"
# a sleep during GONE_DELAY in which the launcher is "reinstalled"
printf '%s\n' "$SHEBANG" "mkdir -p '$APPD' && echo '{}' > '$APPD/appinfo.json'" > "$T/bin/nap-reinstall"
# just a live process with a recognisable command line: "hold subscription", "hold takeover"...
printf '%s\n' "$SHEBANG" 'while :; do sleep 1; done' > "$T/bin/hold"
# NAP for the FAILSAFE checks: a pause of "N s" takes 0.2 s (the LG Home process needs time to end), and the fake
# /proc/uptime moves on by N s: the times in the log are as on a TV, without the time the requests take
printf '%s\n' "$SHEBANG" 'sleep 0.2' 'u=; read -r u _r < "$MOCK_STATE/uptime"' \
    'echo "$(( ${u%%.*} + ${1:-0} )).${u#*.} 999.00" > "$MOCK_STATE/uptime"' > "$T/bin/nap-short"
# NAP with steps: call N runs $S/step.N if it exists, so the TV's state changes while one process runs
printf '%s\n' "$SHEBANG" 'n=$(( $(cat "$MOCK_STATE/nap_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MOCK_STATE/nap_n"' \
    '[ -f "$MOCK_STATE/step.$n" ] && . "$MOCK_STATE/step.$n"' 'exit 0' > "$T/bin/nap-steps"
# WAKE_NAP for the wake_loop step: writes the length of each pause to $S/wake_naps and waits 0.2 s
printf '%s\n' "$SHEBANG" 'echo "$1" >> "$MOCK_STATE/wake_naps"' 'sleep 0.2' > "$T/bin/nap-log"
# a NAP that, like a sleep without fractions, refuses "0.2" (an error) and writes every pause to $S/naps
printf '%s\n' "$SHEBANG" 'case "$1" in *.*) echo "bad $1" >> "$MOCK_STATE/naps"; echo "sleep: invalid number" >&2; exit 1 ;; esac' \
    'echo "nap $1" >> "$MOCK_STATE/naps"' > "$T/bin/nap-int"
chmod +x "$T/bin/"*

# ---------- helpers ----------
pass=0; fail=0
ok () { pass=$((pass + 1)); echo "  ok   $1"; }
bad () { fail=$((fail + 1)); echo "  FAIL $1"; }
check () { d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
section () { echo; echo "== $1"; }
waitfor () { i=0; while [ "$i" -lt 100 ]; do "$@" && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }
count () { n=$(grep -c -- "$1" "$2" 2>/dev/null); echo "${n:-0}"; }
eq () { [ "$1" = "$2" ] || { echo "       (got: '$1', wanted: '$2')"; return 1; }; }
has () { grep -q -- "$1" "$2" 2>/dev/null; }
hasnt () { ! grep -q -- "$1" "$2" 2>/dev/null; }
hasline () { grep -qxF -- "$1" "$2" 2>/dev/null; }
gone () { [ ! -e "$1" ]; }
dead () { ! kill -0 "$1" 2>/dev/null || grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null; }
no_proc () { ! pgrep -f "$1" >/dev/null 2>&1; }
has_proc () { pgrep -f "$1" >/dev/null 2>&1; }
pid_alive () { p=$(cat "$1" 2>/dev/null); [ -n "$p" ] && ! dead "$p"; }
pid_alive_not () { p=$(cat "$1" 2>/dev/null); [ -n "$p" ] && [ "$p" != "$2" ] && ! dead "$p"; }
no_thaw () { hasnt '^-CONT' "$S/pkill.log"; }
calls () { count "$1" "$S/calls"; }
launcher_launches () { count "^launch.*\"id\":\"$ID\"" "$S/calls"; }
home_launches () { count '^launch.*"id":"com.webos.app.home"' "$S/calls"; }

start_home () {   # in a subshell: not a child of the test, no "Killed" messages
    ( "$T/bin/flutter-client" -i com.webos.app.home </dev/null >/dev/null 2>&1 & echo $! > "$S/home_pid" )
    HP=$(cat "$S/home_pid")
    waitfor grep -q flutter-client "/proc/$HP/cmdline"
}
hold () { ( "$T/bin/hold" "$1" </dev/null >/dev/null 2>&1 & echo $! > "$2" ); }   # hold TAG PIDFILE
home_state () { sed -n 's/^State:[[:space:]]*\([A-Za-z]\).*/\1/p' "/proc/$HP/status" 2>/dev/null; }
home_frozen () { [ "$(home_state)" = T ]; }
home_running () { case "$(home_state)" in S|R|D) return 0 ;; esac; return 1; }
freeze_now () { kill -STOP "$HP"; waitfor home_frozen; : > "$S/pkill.log"; }

cleanup_procs () {
    pkill -9 -f "$T/" 2>/dev/null
    sleep 0.3
}
reset () {
    cleanup_procs
    rm -rf "$S" "$W" "$T/media" "$T/apps"
    mkdir -p "$S" "$W/homeapp" "$HOOKD" "$APPD"
    echo '{}' > "$APPD/appinfo.json"
    for f in watch apply stock guard stop diagnose; do cp "$SRC/$f.sh" "$HOOKD/$f.sh"; done
    echo "1234.56 999.00" > "$S/uptime"
    : > "$S/mounts"; : > "$S/calls"; : > "$S/pkill.log"
    echo com.webos.app.home > "$S/front"
    echo ru-RU > "$S/locale"    # the TV's menu language: notifications in Russian (H1a, E6b: English)
    HP=
}
run_env () {
    env LUNA_SEND="$T/bin/luna-send" MOCK_STATE="$S" LAUNCHER="$APPD" HOOK="$HOOKD" \
        PIDFILE="$W/watch.pid" GUARD_PIDFILE="$W/guard.pid" RESTARTS="$W/restarts" STOPPED="$HOOKD/stopped" \
        ALLOW="$W/allow" MARK="$W/mark" VLOCK="$W/vlock" TLOCK="$W/tlock" ALIVE="$W/alive" \
        TAKEOVER_FLAG="$W/takeover-enabled" TAKEOVER_PID="$W/takeover.pid" MOUNTS="$S/mounts" \
        KEEP_FLAG="$W/keep-on" STANDBY_FLAG="$W/standby" STANDBY_REF="$W/standby-ref" WAKE_REF="$W/wake-ref" \
        LINK="$W/link" APP_QML="$W/no-such-qml" HOME_APP_DIR="$W/homeapp" SYSLOG="$W/messages" \
        LAST_REPORT="$W/last-report" HANDLING="$W/handling" SILENT_FLAG="$W/silent" POLLING="$W/polling" \
        UPTIME_FILE="$S/uptime" LOADING_TOAST= NAP=true FAILSAFE=0 CHECK_EVERY=0 TOAST_APP="$W/toastapp" \
        "$@"
}
# waitfor, but up to 30 s (check_loop with CHECK_EVERY=1 needs about 2 s for each quiet subscription)
waitlong () { i=0; while [ "$i" -lt 300 ]; do "$@" && return 0; sleep 0.1; i=$((i + 1)); done; return 1; }
subs () { count '^sub$' "$S/subs"; }
sub_procs () { pgrep -f "$T/bin/hold subscription" 2>/dev/null | wc -l | tr -d ' '; }
rep () { printf '{"returnValue":true,"appId":"%s","processId":"","windowId":""}\n' "$1"; }
stdin_watch () { app="$1"; shift; rep "$app" | run_env LOG="$W/watch.log" WATCH_STDIN=1 "$@" sh "$HOOKD/watch.sh"; }
bg_watch () { ( run_env LOG="$W/watch.log" "$@" sh "$HOOKD/watch.sh" </dev/null >/dev/null 2>&1 & ); }
stop_bg_watch () { p=$(cat "$W/watch.pid" 2>/dev/null); [ -n "$p" ] && kill -TERM "$p" 2>/dev/null; [ -n "$p" ] && waitfor dead "$p"; }
bg_guard () { ( run_env LOG="$W/guard.log" NAP=sleep INTERVAL=1 "$@" sh "$HOOKD/guard.sh" </dev/null >/dev/null 2>&1 & ); }
grun () { n="$1"; shift; run_env LOG="$W/guard.log" MAX_LOOPS="$n" CONFIRM=2 "$@" sh "$HOOKD/guard.sh"; }
# Hearth's own watch.sh (no freezing): what Hearth writes into the same folder when it is opened
hearth_watch () { printf '%s\n' '#!/bin/sh' "# Hearth's own watch.sh (test stand-in)" 'LAUNCHER_ID="${LAUNCHER_ID:-tld.my.customlauncher}"' 'while :; do sleep 1; done' > "$HOOKD/watch.sh"; }
# Hearth P0.x's watch.sh (test stand-in): it freezes LG Home too
p0_watch () { printf '%s\n' '#!/bin/sh' "# Hearth P0.x's watch.sh (test stand-in)" 'LAUNCHER_ID="${LAUNCHER_ID:-tld.my.customlauncher}"' 'freeze_home () { pkill -STOP -f "$HOME_PROC" 2>/dev/null; }' 'while :; do sleep 1; done' > "$HOOKD/watch.sh"; }

# ---------- A. syntax and fixed values ----------
section "A. sh -n of every script, and the defaults"
for f in "$SRC"/*.sh "$ROOT"/scripts/test-homehook*.sh; do
    check "sh -n ${f#$ROOT/}" sh -n "$f"
done
WS="$SRC/watch.sh"
check "watch.sh freezes LG Home (has 'pkill -STOP')" has 'pkill -STOP' "$WS"
check "watch.sh opens com.hearthng.launcher by default (guard.sh tells HearthNG's watch.sh from another launcher's by that line)" hasline 'LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"' "$WS"
check "guard.sh looks for that line" hasline "WATCH_MARK='LAUNCHER_ID:-com.hearthng.launcher}'" "$SRC/guard.sh"
HP_LINE="HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|\$)'"
for f in watch apply stock guard stop; do
    check "$f.sh: the same LG Home process pattern" hasline "$HP_LINE" "$SRC/$f.sh"
done
check "diagnose.sh: the same pattern" hasline "HOME_PROC='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|\$)'" "$SRC/diagnose.sh"
for f in watch apply guard; do
    check "$f.sh: the launcher is $ID by default" hasline 'LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"' "$SRC/$f.sh"
done
check "diagnose.sh: the launcher is $ID" hasline "LAUNCHER_ID=$ID" "$SRC/diagnose.sh"
check "defaults: THAW_ON_LAUNCH=0, FAILSAFE=1, THAW_ON_STANDBY=0, EMPTY_AS_HOME=auto, TOAST_LANG=auto" eval \
    'has "THAW_ON_LAUNCH=\"\${THAW_ON_LAUNCH:-0}\"" "$WS" && has "FAILSAFE=\"\${FAILSAFE:-1}\"" "$WS" && has "THAW_ON_STANDBY=\"\${THAW_ON_STANDBY:-0}\"" "$WS" && has "EMPTY_AS_HOME=\"\${EMPTY_AS_HOME:-auto}\"" "$WS" && has "TOAST_LANG=\"\${TOAST_LANG:-auto}\"" "$WS"'
check "defaults: EMPTY_DELAY=0.2, WAKE_SETTLE=1, WAKE_POLL_STANDBY=1, TOAST_DELAY=3" eval \
    'has "EMPTY_DELAY=\"\${EMPTY_DELAY:-0.2}\"" "$WS" && has "WAKE_SETTLE=\"\${WAKE_SETTLE:-1}\"" "$WS" && has "WAKE_POLL_STANDBY=\"\${WAKE_POLL_STANDBY:-1}\"" "$WS" && has "TOAST_DELAY=\"\${TOAST_DELAY:-3}\"" "$WS"'
check "only one line of watch.sh ends with >/dev/null 2>&1 (diagnose.sh's self-test needs that)" eq "$(count '>/dev/null 2>&1$' "$WS")" 1
check "defaults: CHECK_EVERY=5, CHECK_MISSES=2, HANDLE_MAX=60, SILENT_MAX=3" eval \
    'has "CHECK_EVERY=\"\${CHECK_EVERY:-5}\"" "$WS" && has "CHECK_MISSES=\"\${CHECK_MISSES:-2}\"" "$WS" && has "HANDLE_MAX=\"\${HANDLE_MAX:-60}\"" "$WS" && has "SILENT_MAX=\"\${SILENT_MAX:-3}\"" "$WS"'
check "check_loop's files are in /tmp/launcher-homehook-*" eval \
    'has "LAST_REPORT=\"\${LAST_REPORT:-/tmp/launcher-homehook-last-report}\"" "$WS" && has "HANDLING=\"\${HANDLING:-/tmp/launcher-homehook-handling}\"" "$WS" && has "SILENT_FLAG=\"\${SILENT_FLAG:-/tmp/launcher-homehook-silent}\"" "$WS" && has "POLLING=\"\${POLLING:-/tmp/launcher-homehook-polling}\"" "$WS"'
check "guard.sh: every 10 s, 2 checks in a row, at most 5 restarts" eval \
    'has "INTERVAL=\"\${INTERVAL:-10}\"" "$SRC/guard.sh" && has "CONFIRM=\"\${CONFIRM:-2}\"" "$SRC/guard.sh" && has "MAX_RESTARTS=\"\${MAX_RESTARTS:-5}\"" "$SRC/guard.sh"'
mkdir -p "$T/fake-macos"; printf '%s\n' "$SHEBANG" 'echo Darwin' > "$T/fake-macos/uname"; chmod +x "$T/fake-macos/uname"
out=$(PATH="$T/fake-macos:$PATH" sh "$0" 2>&1); rc=$?
check "not Linux (uname says Darwin): skipped at once with exit code 0" eval '[ "$rc" = 0 ] && echo "$out" | grep -q "^skipped: "'

section "A2. The LG Home pattern on real processes: LG Home only, not look-alikes"
reset; start_home
( "$T/bin/flutter-client" -i com.webos.app.homeconnect </dev/null >/dev/null 2>&1 & echo $! > "$W/hc.pid" )
( "$T/bin/flutter-client" -i com.webos.app.home2 </dev/null >/dev/null 2>&1 & echo $! > "$W/h2.pid" )
( "$T/bin/flutter-client" -i com.webos.app.home --flag </dev/null >/dev/null 2>&1 & echo $! > "$W/hf.pid" )
waitfor grep -q home2 "/proc/$(cat "$W/h2.pid")/cmdline"; waitfor grep -q flag "/proc/$(cat "$W/hf.pid")/cmdline"
HPD=$(sed -n "s/^HOME_PROC_DEFAULT='\(.*\)'$/\1/p" "$WS")
got=$(pgrep -f "$HPD" | sort | tr '\n' ' ')
want=$(printf '%s\n' "$HP" "$(cat "$W/hf.pid")" | sort | tr '\n' ' ')
check "pgrep -f finds 'flutter-client -i com.webos.app.home' (with and without more arguments), not homeconnect or home2" eq "$got" "$want"

# ---------- B. watch.sh, decisions (WATCH_STDIN mode) ----------
section "B1. The launcher is opened while LG Home stays frozen (THAW_ON_LAUNCH=0, the default)"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1
check "the launcher is asked for exactly once" eq "$(calls '^launch')" 1
check "LG Home is frozen (State T) at the moment of the launch" eq "$(calls 'home=T')" 1
check "the request is made on behalf of com.webos.app.home" has 'caller=com.webos.app.home' "$S/calls"
check "no SIGCONT was sent" no_thaw
check "LG Home is still frozen afterwards" home_frozen
check "the time in the log comes from /proc/uptime" has '^1234.56 watcher: Foreground is Home or empty: opened the launcher' "$W/watch.log"

section "B2. THAW_ON_LAUNCH=1: LG Home is unfrozen before the launch"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1 THAW_ON_LAUNCH=1
check "LG Home is running (State S/R) at the moment of the launch" eq "$(calls 'home=[SR]')" 1
check "SIGCONT was sent" has '^-CONT' "$S/pkill.log"

section "B3. The launcher came to the front: LG Home is frozen"
reset; start_home; echo 1 > "$S/appear_after"
stdin_watch com.webos.app.home
check "the check has ended" waitfor gone "$W/vlock"
check "LG Home is frozen" waitfor home_frozen
check "one launch, no closeByAppId, no notification" eq "$(calls '^launch'),$(calls '^close'),$(calls '^toast')" "1,0,0"

section "B3a. LG's full-screen Home (com.webos.app.fullhome, webOS 4.x) counts as LG Home"
reset; start_home; freeze_now
stdin_watch com.webos.app.fullhome NO_VERIFY=1
check "the launcher is asked for once, LG Home stays frozen" eval '[ "$(launcher_launches),$(calls "home=T")" = "1,1" ] && home_frozen && no_thaw'

section "B4. Against an endless loop: the launcher never comes to the front (VERIFY_TRIES=3, RESTART_WAIT=4, FAILSAFE=0)"
reset; start_home; freeze_now
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4
check "the check has ended" waitfor gone "$W/vlock"
check "5 launches = 1 + 3 tries + 1 after the restart" eq "$(calls '^launch')" 5
check "all 5 launches with LG Home frozen" eq "$(calls 'home=T')" 5
check "closeByAppId once, after the 4th launch" eq "$(calls '^close'),$(sed -n 5p "$S/calls" | cut -c1-5)" "1,close"
check "one notification, with the emergency exit command" eq "$(calls '^toast.*HearthNG не открывается. Аварийный выход: sh .*/launcher-homehook/stop.sh')" 1
check "the notification is sent as webosbrew" has '^toast caller=webosbrew {"sourceId":"webosbrew"' "$S/calls"
check "no SIGCONT was sent, LG Home is still frozen" eval 'no_thaw && home_frozen'
check "in the log: try 3 of 3 and the outcome" eq "$(count 'try 3 of 3' "$W/watch.log"),$(count 'still not in front' "$W/watch.log")" "1,1"
check "FAILSAFE=0: no ALLOW, LG Home not launched" eval 'gone "$W/allow" && [ "$(home_launches)" = 0 ]'

section "B4D. FAILSAFE not set: the default (1) opens LG Home"
reset; start_home; freeze_now
rep com.webos.app.home | run_env LOG="$W/watch.log" WATCH_STDIN=1 VERIFY_TRIES=1 RESTART_WAIT=2 NAP="$T/bin/nap-short" env -u FAILSAFE sh "$HOOKD/watch.sh"
check "the check has ended" waitfor gone "$W/vlock"
check "ALLOW made, LG Home launched once, notification \"LG Home is open\"" eval 'test -f "$W/allow" && [ "$(home_launches),$(calls "^toast.*HearthNG не открывается: открыт LG Home")" = "1,1" ]'
check "in the log: FAILSAFE=1, LG Home in front (the same process)" has "FAILSAFE=1: LG Home is in front (pid $HP)" "$W/watch.log"

section "B4F. FAILSAFE=1: the launcher did not come even after the restart: LG Home is opened, as by the LG Home tile"
reset; start_home; freeze_now
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4 FAILSAFE=1
check "the check has ended" waitfor gone "$W/vlock"
check "the launcher asked for 5 times, closeByAppId once" eq "$(launcher_launches),$(calls '^close')" "5,1"
check "all 5 launches of the launcher with LG Home frozen" eq "$(count "home=T {\"id\":\"$ID\"}" "$S/calls")" 5
check "ALLOW made (as by stock.sh)" test -f "$W/allow"
check "LG Home unfrozen (SIGCONT)" eval 'has "^-CONT" "$S/pkill.log" && waitfor home_running'
check "LG Home launched once, already unfrozen" eq "$(home_launches),$(count 'home=[SR] {"id":"com.webos.app.home"}' "$S/calls")" "1,1"
check "notification \"LG Home is open\", without the stop.sh command" eq "$(calls '^toast.*открыт LG Home'),$(calls '^toast.*stop.sh')" "1,0"
check "in the log: FAILSAFE=1" has 'FAILSAFE=1: LG Home is allowed' "$W/watch.log"
check "no SIGTERM waited for, LG Home seen in front, the same process" eval 'has "pid $HP (state T), no SIGTERM pending" "$W/watch.log" && has "LG Home is in front (pid $HP)" "$W/watch.log" && [ "$(cat "$S/home_pid")" = "$HP" ]'

section "B4G. FAILSAFE=1, but the TV is no longer Active: LG Home is not opened"
reset; start_home; freeze_now; echo Suspend > "$S/power"
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1
check "the check has ended" waitfor gone "$W/vlock"
check "no ALLOW, LG Home neither launched nor unfrozen" eval 'gone "$W/allow" && [ "$(home_launches)" = 0 ] && no_thaw && home_frozen'

section "B4H. FAILSAFE=1, the frozen LG Home has SIGTERM pending: it ends after SIGCONT, a new one is started"
reset; start_home; freeze_now; kill -TERM "$HP"; OLDHP=$HP
check "before: LG Home frozen, SIGTERM pending (bit 0x4000 in ShdPnd)" eval 'home_frozen && grep -q "^ShdPnd:[[:space:]]*[0-9a-f]*[4567cdef][0-9a-f][0-9a-f][0-9a-f]$" "/proc/$HP/status"'
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4 FAILSAFE=1 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "the old LG Home ended by itself after SIGCONT" eval 'dead "$OLDHP" && has "pid $OLDHP (state T) has SIGTERM pending (SIGTERM handler: yes): waiting up to 5 s" "$W/watch.log" && has "pid $OLDHP has exited (checked 1.00 s after SIGCONT)" "$W/watch.log" && hasnt "did not end it" "$W/watch.log"'
check "LG Home asked for once, when the old process was gone" eq "$(home_launches),$(count 'home= {"id":"com.webos.app.home"}' "$S/calls")" "1,1"
check "a new LG Home process runs and is in front (log)" eval 'pid_alive_not "$S/home_pid" "$OLDHP" && has "LG Home is in front (pid $(cat "$S/home_pid")) 1.00 s after launch 1" "$W/watch.log"'
check "notification \"LG Home is open\", ALLOW is there" eval '[ "$(calls "^toast.*открыт LG Home"),$(calls "^toast.*не открываются")" = "1,0" ] && test -f "$W/allow"'

section "B4I. FAILSAFE=1, LG Home handles SIGTERM and runs on: it is not killed, it is opened"
reset; start_home; freeze_now; touch "$S/home_term_survive"; kill -STOP "$HP"; kill -TERM "$HP"; OLDHP=$HP
check "before: State T, ShdPnd 0000000000044000 (SIGTERM + another SIGSTOP)" eval 'home_frozen && grep -q "^ShdPnd:[[:space:]]*0000000000044000$" "/proc/$HP/status"'
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4 FAILSAFE=1 FAILSAFE_EXIT_WAIT=2 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "in the log: SIGTERM pending, handler present" has "pid $OLDHP (state T) has SIGTERM pending (SIGTERM handler: yes): waiting up to 2 s" "$W/watch.log"
check "LG Home not killed: the same pid runs; log: still runs 2.00 s after SIGCONT ... not killed" eval '[ "$(cat "$S/home_pid")" = "$OLDHP" ] && home_running && has "term $OLDHP: handled" "$S/home.log" && has "pid $OLDHP still runs 2.00 s after SIGCONT: SIGTERM did not end it, it is not killed" "$W/watch.log"'
check "LG Home asked for once, while running; the same one is in front" eval '[ "$(home_launches),$(count "home=[SR] {\"id\":\"com.webos.app.home\"}" "$S/calls")" = "1,1" ] && has "LG Home is in front (pid $OLDHP) 1.00 s after launch 1" "$W/watch.log"'
check "notification \"LG Home is open\", none \"do not open\"" eq "$(calls '^toast.*открыт LG Home'),$(calls '^toast.*не открываются')" "1,0"

section "B4J. FAILSAFE=1, every launch of LG Home is lost (empty screen): FAILSAFE_TRIES=2, then a notification"
reset; start_home; freeze_now; echo "" > "$S/front"; echo 99 > "$S/home_swallow"
stdin_watch "" VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1 FAILSAFE_TRIES=2 FAILSAFE_WAIT=2 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "LG Home asked for twice" eq "$(home_launches)" 2
check "one notification \"HearthNG and LG Home do not open\" with the stop.sh command" eq "$(calls '^toast'),$(calls '^toast.*HearthNG и LG Home не открываются. Аварийный выход: sh .*/launcher-homehook/stop.sh')" "1,1"
check "ALLOW stays, LG Home unfrozen" eval 'test -f "$W/allow" && home_running'
check "in the log: not in front after 2 launches" has 'LG Home is not in front after 2 launches' "$W/watch.log"

section "B4K. FAILSAFE=1, the first launch of LG Home is lost: second launch, LG Home in front"
reset; start_home; freeze_now; echo "" > "$S/front"; echo 1 > "$S/home_swallow"
stdin_watch "" VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1 FAILSAFE_WAIT=2 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "LG Home asked for twice, notification \"LG Home is open\"" eq "$(home_launches),$(calls '^toast.*открыт LG Home'),$(calls '^toast.*не открываются')" "2,1,0"
check "in the log: launch 2 of 3, LG Home in front 1.00 s later (the same process)" eval 'has "launch 2 of 3" "$W/watch.log" && has "LG Home is in front (pid $HP) 1.00 s after launch 2" "$W/watch.log" && home_running'

section "B4L. FAILSAFE=1, the launcher comes to the front when LG Home is launched: ALLOW removed, LG Home frozen again"
reset; start_home; freeze_now; touch "$S/launcher_on_home_launch"
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "ALLOW removed, LG Home frozen" eval 'gone "$W/allow" && waitfor home_frozen'
check "in the log: in front after all; no notification" eval 'has "Hearth is in front after all" "$W/watch.log" && [ "$(calls "^toast")" = 0 ]'

section "B4M. FAILSAFE=1, SAM reports LG Home but there is no process (the first launch was lost): launched again"
reset; echo 1 > "$S/home_swallow"
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1 FAILSAFE_WAIT=2 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "LG Home asked for twice, notification \"LG Home is open\"" eq "$(home_launches),$(calls '^toast.*открыт LG Home')" "2,1"
check "success only after the 2nd launch, with a new process" eval 'pid_alive "$S/home_pid" && has "LG Home is in front (pid $(cat "$S/home_pid")) 1.00 s after launch 2" "$W/watch.log" && hasnt "after launch 1" "$W/watch.log"'

section "B4N. FAILSAFE=1, no LG Home process at all: launching LG Home starts a new one"
reset
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=2 FAILSAFE=1 NAP="$T/bin/nap-short"
check "the check has ended" waitfor gone "$W/vlock"
check "log: no LG Home process; LG Home asked for once, the new process is in front" eval 'has "no LG Home process is running" "$W/watch.log" && [ "$(home_launches)" = 1 ] && pid_alive "$S/home_pid" && has "LG Home is in front (pid $(cat "$S/home_pid")) 1.00 s after launch 1" "$W/watch.log"'

section "B5. Against an endless loop: the launcher came to the front after the restart"
reset; start_home; freeze_now; touch "$S/appear_after_close"
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4
check "the check has ended" waitfor gone "$W/vlock"
check "closeByAppId once, notification \"was started again\" once" eq "$(calls '^close'),$(calls '^toast.*HearthNG не открывался и был перезапущен')" "1,1"
check "LG Home frozen, no SIGCONT" eval 'home_frozen && no_thaw'

section "B5F. FAILSAFE=1, the launcher came to the front after the restart: LG Home is left alone"
reset; start_home; freeze_now; touch "$S/appear_after_close"
stdin_watch com.webos.app.home VERIFY_TRIES=3 RESTART_WAIT=4 FAILSAFE=1
check "the check has ended" waitfor gone "$W/vlock"
check "no ALLOW, LG Home not launched, no SIGCONT" eval 'gone "$W/allow" && [ "$(home_launches)" = 0 ] && no_thaw && home_frozen'

section "B6. takeover (Hearth 1.x): flag and live pid, but the stand-in is NOT mounted"
reset; start_home; freeze_now
touch "$W/takeover-enabled"; hold takeover "$W/takeover.pid"
stdin_watch com.webos.app.home NO_VERIFY=1
check "the watcher does not stand aside: the launcher is asked for" eq "$(calls '^launch')" 1

section "B7. takeover mounted (/proc/mounts) and its watcher alive"
reset; start_home; freeze_now
touch "$W/takeover-enabled"; hold takeover "$W/takeover.pid"
echo "tmpfs /usr/palm/applications/com.webos.app.home tmpfs rw,relatime 0 0" > "$S/mounts"
stdin_watch com.webos.app.home NO_VERIFY=1
check "stands aside: the launcher is not asked for" eq "$(calls '^launch')" 0
check "without unfreezing: LG Home frozen, no SIGCONT" eval 'home_frozen && no_thaw'
check "in the log: standing aside" has 'standing aside' "$W/watch.log"

section "B8. takeover mounted, but its watcher is not running"
reset; start_home
touch "$W/takeover-enabled"; sh -c 'exit 0' & wait $!; echo $! > "$W/takeover.pid"
echo "tmpfs /usr/palm/applications/com.webos.app.home tmpfs rw,relatime 0 0" > "$S/mounts"
stdin_watch com.webos.app.home NO_VERIFY=1
check "the launcher is asked for" eq "$(calls '^launch')" 1

section "B9. The launcher was uninstalled, LG Home in front"
reset; start_home; freeze_now; rm -f "$APPD/appinfo.json"
stdin_watch com.webos.app.home NO_VERIFY=1
check "the launcher is not asked for" eq "$(calls '^launch')" 0
check "LG Home unfrozen" waitfor home_running
check "in the log: not installed" has 'Hearth is not installed' "$W/watch.log"

section "B10. The launcher's files vanished during an update and came back within GONE_DELAY"
reset; start_home; freeze_now; rm -f "$APPD/appinfo.json"
stdin_watch com.webos.app.home NO_VERIFY=1 NAP="$T/bin/nap-reinstall"
check "the launcher is asked for" eq "$(calls '^launch')" 1
check "LG Home was not unfrozen" eval 'home_frozen && no_thaw'

section "B11. ALLOW (stock.sh, the LG Home tile)"
reset; start_home; freeze_now; date +%s > "$W/allow"
stdin_watch com.webos.app.home NO_VERIFY=1
check "the launcher is not asked for" eq "$(calls '^launch')" 0
check "LG Home unfrozen" waitfor home_running

section "B12. Empty foreground, the TV not Active (THAW_ON_STANDBY=0, the default)"
reset; start_home; freeze_now; echo "" > "$S/front"; echo Suspend > "$S/power"
stdin_watch "" NO_VERIFY=1
check "the launcher is not asked for" eq "$(calls '^launch')" 0
check "LG Home stays frozen, no SIGCONT" eval 'home_frozen && no_thaw'
check "standby mark and standby time mark made; log: standby: ... LG Home left as it is" eval 'test -f "$W/standby" && test -f "$W/standby-ref" && has "watcher: standby: foreground is empty.*LG Home left as it is" "$W/watch.log"'
check "in the log: the event" has 'event: foreground (empty)' "$W/watch.log"

section "B12a. THAW_ON_STANDBY=1: LG Home is unfrozen during standby"
reset; start_home; freeze_now; echo "" > "$S/front"; echo Suspend > "$S/power"
stdin_watch "" NO_VERIFY=1 THAW_ON_STANDBY=1
check "LG Home unfrozen, mark made" eval 'waitfor home_running && test -f "$W/standby"'

section "B12b. Going to standby as on a webOS 25 TV (empty, then LG Home in Active Standby): the launcher is not launched"
reset; start_home; freeze_now; echo "" > "$S/front"; echo "Active Standby" > "$S/power"
{ rep ""; rep com.webos.app.home; } | run_env LOG="$W/watch.log" WATCH_STDIN=1 sh "$HOOKD/watch.sh"
check "the launcher is not asked for" eq "$(launcher_launches)" 0
check "in the log: the TV is not Active ... opened when the TV turns on" has 'the TV is not Active (.*Active Standby.*): Hearth is opened when the TV turns on' "$W/watch.log"
check "the standby mark stays (turning the TV on removes it), LG Home frozen" eval 'test -f "$W/standby" && home_frozen && no_thaw'

section "B12c. Standby mark, but the TV is already Active: LG Home in front opens the launcher at once, the marks go"
reset; start_home; freeze_now; date +%s > "$W/standby"; : > "$W/standby-ref"
stdin_watch com.webos.app.home NO_VERIFY=1
check "the launcher asked for once, both marks removed" eval '[ "$(launcher_launches)" = 1 ] && gone "$W/standby" && gone "$W/standby-ref"'

section "B12d. The check does not launch again once the TV went to standby"
reset; start_home; freeze_now
printf '%s\n' "echo Suspend > '$S/power'" "date +%s > '$W/standby'" > "$S/step.1"
stdin_watch com.webos.app.home NAP="$T/bin/nap-steps"
check "in the log: no more tries" waitfor has 'the TV is not Active (.*Suspend.*): no more tries, Hearth is opened when the TV turns on' "$W/watch.log"
check "the launcher asked for only once" eq "$(launcher_launches)" 1

section "B13. Times in the log: how long the request took, and how soon the launcher came to the front"
reset; start_home; freeze_now; echo "1236.06 999.00" > "$S/uptime_after_launch"
{ rep com.webos.app.home; rep "$ID"; } | run_env LOG="$W/watch.log" WATCH_STDIN=1 NO_VERIFY=1 sh "$HOOKD/watch.sh"
check "the request took 1.50 s (1236.06 - 1234.56 by /proc/uptime)" has 'opened the launcher (the request took 1.50 s)' "$W/watch.log"
check "the launcher came to the front 1.50 s after the request" has 'watcher: Hearth is in front 1.50 s after the request' "$W/watch.log"
check "LG Home frozen, no SIGCONT" eval 'home_frozen && no_thaw'

section "B14. Hundredths of a second (centis, elapsed from watch.sh)"
sed -n '/^uptime_now ()/p; /^centis ()/,/^}/p; /^elapsed ()/,/^}/p' "$WS" > "$W/timefn.sh"
echo "1236.06 999.00" > "$W/up"
out=$(UPTIME_FILE="$W/up" sh -c '. "$1"; for v in 1234.56 0.09 5 7.5 "" abc 0123.40 -1.00; do printf "%s;" "$(centis "$v")"; done; elapsed 1234.56; printf ";"; elapsed 1300.00; printf ";"; elapsed garbage' sh "$W/timefn.sh")
check "centis of 1234.56 0.09 5 7.5 empty abc 0123.40 -1.00; elapsed: 1.50, from the future 0.00, from garbage" eq "$out" "123456;9;500;750;0;0;12340;0;1.50;0.00;1236.06"

section "B15. Pending and handled SIGTERM (proc_state, term_pending, term_caught from watch.sh) on real processes"
reset; start_home; freeze_now
sed -n '/^proc_state ()/p; /^term_bit ()/,/^}/p; /^term_pending ()/p; /^term_caught ()/p' "$WS" > "$W/sigfn.sh"
cg () { sh -c '. "$1"; if term_caught "$2"; then echo caught; else echo default; fi' sh "$W/sigfn.sh" "$1"; }
( sleep 30 </dev/null >/dev/null 2>&1 & echo $! > "$W/sleep.pid" ); SP=$(cat "$W/sleep.pid")
check "SigCgt: the LG Home stand-in (trap TERM) handles SIGTERM, sleep does not" eq "$(cg "$HP");$(cg "$SP")" "caught;default"
kill -9 "$SP" 2>/dev/null
st () { sh -c '. "$1"; printf "%s:" "$(proc_state "$2")"; if term_pending "$2"; then echo pending; else echo none; fi' sh "$W/sigfn.sh" "$HP"; }
r1=$(st); kill -HUP "$HP"; kill -USR2 "$HP"; sleep 0.2; r2=$(st); kill -TERM "$HP"; sleep 0.2; r3=$(st)
check "frozen: none; + SIGHUP and SIGUSR2 (0x801): none; + SIGTERM (0x4801): pending" eq "$r1;$r2;$r3" "T:none;T:none;T:pending"
kill -CONT "$HP"
check "after SIGCONT the process ended" waitfor dead "$HP"

section "B16. ALLOW removed by someone else: the note \"LG Home was on screen\" is dropped too"
reset; start_home; date +%s > "$W/allow"
{ rep com.webos.app.home; sleep 0.3; rm -f "$W/allow"; rep com.netflix.app; sleep 0.3; date +%s > "$W/allow"; rep com.netflix.app; } |
    run_env LOG="$W/watch.log" WATCH_STDIN=1 NO_VERIFY=1 sh "$HOOKD/watch.sh"
check "a new ALLOW is not dropped at once: LG Home has not been on screen since" eval 'test -f "$W/allow" && hasnt "LG Home was left" "$W/watch.log"'

section "B17. Keep Hearth ready on, the launcher not in memory: launched with keepAlive"
reset; start_home; freeze_now; echo on > "$W/keep-on"
stdin_watch com.webos.app.home NO_VERIFY=1
check "first the running query, then one launch with keepAlive (as com.webos.app.home, LG Home frozen)" eq "$(sed -n 1p "$S/calls" | cut -c1-7),$(calls '^running'),$(calls '^launch'),$(count "^launch caller=com.webos.app.home home=T {\"id\":\"$ID\",\"keepAlive\":true}\$" "$S/calls")" "running,1,1,1"
check "in the log: which kind of launch" has 'opened the launcher (the request took 0.00 s; Keep Hearth ready: Hearth is not in memory, keepAlive launch)' "$W/watch.log"
check "no SIGCONT, LG Home frozen" eval 'home_frozen && no_thaw'

section "B18. Keep Hearth ready on, the launcher in memory: a plain launch, without keepAlive"
reset; start_home; freeze_now; echo on > "$W/keep-on"; touch "$S/launcher_running"
stdin_watch com.webos.app.home NO_VERIFY=1
check "one running query, one launch without keepAlive" eq "$(calls '^running'),$(calls '^launch'),$(calls 'keepAlive'),$(count "^launch caller=com.webos.app.home home=T {\"id\":\"$ID\"}\$" "$S/calls")" "1,1,0,1"
check "in the log: in memory, plain launch" has '(the request took 0.00 s; Keep Hearth ready: Hearth is in memory, plain launch)' "$W/watch.log"
rm -f "$S/launcher_running"; : > "$S/calls"
echo "{\"returnValue\": true, \"running\": [{\"id\": \"$ID\", \"processid\": \"1002\"}]}" > "$S/running_reply"
stdin_watch com.webos.app.home NO_VERIFY=1
check "an answer with spaces (\"id\": \"$ID\"): a plain launch too" eq "$(calls '^running'),$(calls '^launch'),$(calls 'keepAlive')" "1,1,0"

section "B19. The Keep Hearth ready file is empty or missing: no running query, a plain launch"
reset; start_home; freeze_now; : > "$W/keep-on"
stdin_watch com.webos.app.home NO_VERIFY=1
check "empty file: no running query, no keepAlive, no note in the log" eq "$(calls '^running'),$(calls '^launch'),$(calls 'keepAlive'),$(count 'opened the launcher (the request took 0.00 s)$' "$W/watch.log")" "0,1,0,1"
rm -f "$W/keep-on"; : > "$S/calls"
stdin_watch com.webos.app.home NO_VERIFY=1
check "no file: the same" eq "$(calls '^running'),$(calls '^launch'),$(calls 'keepAlive')" "0,1,0"

section "B20. Keep Hearth ready, the launcher never comes (VERIFY_TRIES=1, RESTART_WAIT=2): the try and the restart use keepAlive too"
reset; start_home; freeze_now; echo on > "$W/keep-on"
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=2
check "the check has ended" waitfor gone "$W/vlock"
check "3 launches (1 + 1 try + 1 after the restart), all with keepAlive, each after a running query" eq "$(launcher_launches),$(calls '"keepAlive":true'),$(calls '^running')" "3,3,3"
check "the note in the log for the try and for the restart" eval 'has "(try 1 of 1, the request took 0.00 s; Keep Hearth ready: Hearth is not in memory, keepAlive launch)" "$W/watch.log" && has "Hearth started again (the request took 0.00 s; Keep Hearth ready: Hearth is not in memory, keepAlive launch)" "$W/watch.log"'
check "no SIGCONT, LG Home frozen" eval 'home_frozen && no_thaw'

section "B21. EMPTY_DELAY=0.2; a sleep that refuses fractions waits 1 s instead"
reset; start_home; freeze_now; echo "" > "$S/front"
stdin_watch "" NO_VERIFY=1 NAP="$T/bin/nap-int"
check "first 0.2 (an error), then 1" eq "$(cat "$S/naps" 2>/dev/null | tr '\n' ' ')" "bad 0.2 nap 1 "
check "the launcher is asked for (still empty, the TV Active)" eq "$(launcher_launches)" 1
reset; start_home; freeze_now; echo "" > "$S/front"
stdin_watch "" NO_VERIFY=1 NAP="$T/bin/nap-int" EMPTY_DELAY=1
check "EMPTY_DELAY=1: one pause of 1 s" eq "$(cat "$S/naps" 2>/dev/null | tr '\n' ' ')" "nap 1 "
reset; start_home; freeze_now; echo "" > "$S/front"
out=$(rep "" | run_env LOG="$W/watch.log" WATCH_STDIN=1 NO_VERIFY=1 NAP=sleep sh "$HOOKD/watch.sh" 2>&1)
check "the real sleep 0.2: no error output, the launcher asked for" eval '[ -z "$out" ] && [ "$(launcher_launches)" = 1 ]'

section "B21a. EMPTY_AS_HOME: when does an empty foreground count as LG Home?"
reset; echo "" > "$S/front"
stdin_watch "" NO_VERIFY=1
check "auto (default), no LG Home process (other webOS versions): left alone, no standby mark" eval '[ "$(launcher_launches)" = 0 ] && gone "$W/standby"'
reset; start_home; freeze_now; echo "" > "$S/front"
stdin_watch "" NO_VERIFY=1 EMPTY_AS_HOME=0
check "EMPTY_AS_HOME=0 with an LG Home process: left alone" eq "$(launcher_launches)" 0
reset; echo "" > "$S/front"
stdin_watch "" NO_VERIFY=1 EMPTY_AS_HOME=1
check "EMPTY_AS_HOME=1 without an LG Home process: the launcher is opened" eq "$(launcher_launches)" 1

section "B22. The launcher came within TOAST_DELAY: no notification"
reset; start_home; freeze_now; echo 1 > "$S/appear_after"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=2
check "the helper has ended (TLOCK removed)" waitfor gone "$W/tlock"
check "no notification" eq "$(calls '^toast')" 0

section "B23. The launcher not there after TOAST_DELAY: notification; once it is in front: closeToast with the toastId"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1
check "notification as webosbrew, in Russian (menu language ru-RU)" waitfor has 'toast caller=webosbrew .*Домашний экран загружается…' "$S/calls"
check "the toastId of the answer in the log" waitfor has 'Hearth is not in front 1 s after the request (foreground com.webos.app.home): toast "Домашний экран загружается…": {"returnValue":true,"toastId":"webosbrew-1"}' "$W/watch.log"
sleep 1.2; echo "$ID" > "$S/front"
check "closeToast as webosbrew with that toastId" waitfor has 'closetoast caller=webosbrew {"toastId":"webosbrew-1"}' "$S/calls"
check "the answer of closeToast in the log" waitfor has "$ID is in front [0-9]* s after the toast: closeToast webosbrew-1: {\"returnValue\":true}" "$W/watch.log"
check "TLOCK removed, one closeToast" eval 'waitfor gone "$W/tlock" && [ "$(calls "^closetoast")" = 1 ]'

section "B23a. The language of the notification: no answer about the menu language = English; TOAST_LANG=ru wins"
reset; start_home; freeze_now; rm -f "$S/locale"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1
check "menu language unknown: in English" waitfor has 'toast caller=webosbrew .*"Home screen is loading…"' "$S/calls"
waitfor gone "$W/tlock"
reset; start_home; freeze_now; echo en-US > "$S/locale"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1 TOAST_LANG=ru
check "menu in English, TOAST_LANG=ru: in Russian" waitfor has 'toast caller=webosbrew .*Домашний экран загружается…' "$S/calls"
waitfor gone "$W/tlock"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST="Custom text" TOAST_DELAY=1 TOAST_HOLD=1
check "LOADING_TOAST with a text of its own: that text" waitfor has 'toast caller=webosbrew .*"Custom text"' "$S/calls"
waitfor gone "$W/tlock"

section "B24. closeToast refused for webosbrew: tried again without -a, both answers in the log"
reset; start_home; freeze_now; touch "$S/closetoast_deny"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1
waitfor has '^toast' "$S/calls"; echo com.netflix.app > "$S/front"
check "two closeToast calls: with -a webosbrew and without" waitfor eval '[ "$(calls "^closetoast caller=webosbrew")" = 1 ] && [ "$(calls "^closetoast caller= ")" = 1 ]'
check "in the log: com.netflix.app is in front ... without -a webosbrew: {\"returnValue\":true}" waitfor has 'com.netflix.app is in front .*denied (mock).*without -a webosbrew: {"returnValue":true}' "$W/watch.log"

section "B25. Two requests in a row: one helper and one notification"
reset; start_home; freeze_now
{ rep com.webos.app.home; rep com.webos.app.home; } | run_env LOG="$W/watch.log" WATCH_STDIN=1 NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1 sh "$HOOKD/watch.sh"
check "the launcher asked for twice" eq "$(launcher_launches)" 2
check "the helper has ended" waitfor gone "$W/tlock"
check "one notification" eq "$(calls '^toast')" 1

section "B26. The launcher never came within TOAST_HOLD: the notification is not closed, the log says so"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1
check "in the log: it is not closed" waitfor has 'toast webosbrew-1: Hearth is still not in front 1 s after the toast: it is not closed' "$W/watch.log"
check "no closeToast" eq "$(calls '^closetoast')" 0

section "B27. By the time of the notification the TV went to standby: no notification"
reset; start_home; freeze_now
printf '%s\n' "echo Suspend > '$S/power'" > "$S/step.1"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_NAP="$T/bin/nap-steps"
check "in the log: the TV is not Active: no toast" waitfor has 'loading toast: the TV is not Active: no toast' "$W/watch.log"
check "no notification" eq "$(calls '^toast')" 0

section "B28. The user opened LG Home with the tile (ALLOW) while the notification is shown: it is closed"
reset; start_home; freeze_now
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1
waitfor has '^toast' "$S/calls"; date +%s > "$W/allow"
check "closeToast, in the log: LG Home is allowed" waitfor has 'LG Home is allowed (stock.sh): closeToast webosbrew-1' "$W/watch.log"

# ---------- C. watch.sh, started for real (subscription) ----------
section "C1. Frozen at start; TERM stops the watcher without unfreezing"
reset; start_home; echo com.netflix.app > "$S/front"
bg_watch
check "the watcher runs (pid file)" waitfor pid_alive "$W/watch.pid"
check "LG Home frozen at start (another app in front)" waitfor home_frozen
check "in the log: start: LG Home frozen" waitfor has 'watcher: start: LG Home frozen' "$W/watch.log"
check "the started line: HearthNG, the id, the settings, Keep Hearth ready: off" has "started (pid [0-9]*, HearthNG $ID, THAW_ON_LAUNCH=0, FAILSAFE=0, THAW_ON_STANDBY=0, EMPTY_DELAY=0.2, EMPTY_AS_HOME=auto, Keep Hearth ready: off)" "$W/watch.log"
check "the luna-send subscription runs" waitfor has_proc "$T/bin/hold subscription"
P=$(cat "$W/watch.pid"); : > "$S/pkill.log"
kill -TERM "$P"
check "after TERM the watcher has ended" waitfor dead "$P"
check "after TERM LG Home is NOT unfrozen (no SIGCONT)" eval 'home_frozen && no_thaw'
check "pid file removed" gone "$W/watch.pid"
check "subscription stopped" waitfor no_proc "$T/bin/hold subscription"

section "C2. LG Home in front at start: frozen only once the launcher is in front"
reset; start_home; echo 1 > "$S/appear_after"
bg_watch
check "in the log: LG Home is in front" waitfor has 'start: LG Home is in front' "$W/watch.log"
check "the launcher is asked for" waitfor eval '[ "$(calls ^launch)" = 1 ]'
check "the launcher in front: LG Home frozen" waitfor home_frozen
stop_bg_watch

section "C3. SAM does not answer at start"
reset; start_home; touch "$S/sam_down"
bg_watch
check "in the log: no answer from SAM" waitfor has 'no answer from SAM' "$W/watch.log"
check "LG Home not frozen" home_running
stop_bg_watch

section "C4. The emergency exit is on (file stopped)"
reset; start_home; echo com.netflix.app > "$S/front"; touch "$HOOKD/stopped"
run_env LOG="$W/watch.log" timeout 5 sh "$HOOKD/watch.sh"; rc=$?
check "watch.sh ended at once with exit code 0" eq "$rc" 0
check "no pid file, LG Home not frozen" eval 'gone "$W/watch.pid" && home_running'
check "in the log: emergency exit is on, and how to undo it" has "emergency exit is on ($HOOKD/stopped): not starting. To undo: sh $HOOKD/stop.sh resume" "$W/watch.log"

section "C5. The launcher not installed at start"
reset; start_home; echo com.netflix.app > "$S/front"; rm -f "$APPD/appinfo.json"
bg_watch
check "in the log: not installed" waitfor has 'start: Hearth is not installed' "$W/watch.log"
check "LG Home not frozen" home_running
stop_bg_watch

section "C6. ALLOW at start"
reset; start_home; echo com.netflix.app > "$S/front"; date +%s > "$W/allow"
bg_watch
check "in the log: LG Home is allowed" waitfor has 'start: LG Home is allowed' "$W/watch.log"
check "LG Home not frozen" home_running
stop_bg_watch

section "C7. Keep Hearth ready on: the started line says so"
reset; start_home; echo com.netflix.app > "$S/front"; echo on > "$W/keep-on"
bg_watch
check "in the log: Keep Hearth ready: on" waitfor has 'EMPTY_AS_HOME=auto, Keep Hearth ready: on)' "$W/watch.log"
stop_bg_watch

section "C8. No LG Home process at start (other webOS versions): nothing to freeze"
reset; echo com.netflix.app > "$S/front"
bg_watch
check "in the log: no LG Home process: nothing to freeze" waitfor has 'start: no LG Home process (.*): nothing to freeze' "$W/watch.log"
check "no SIGSTOP sent" hasnt '^-STOP' "$S/pkill.log"
stop_bg_watch

section "C9. The subscription keeps ending at once: the watcher asks once a second instead"
reset; start_home; echo com.netflix.app > "$S/front"; : > "$S/sub_ends"
bg_watch NO_VERIFY=1 POLL_NAP="$T/bin/nap-short"
check "in the log: the subscription keeps ending: asking once a second instead" waitfor has 'the subscription keeps ending: asking once a second instead' "$W/watch.log"
check "after 3 subscriptions that ended at once" eq "$(count end "$S/sub_ends")" 3
echo com.webos.app.home > "$S/front"
check "LG Home in front: the launcher is asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
sleep 1
check "LG Home still reported: not asked for again (only a change of app counts)" eq "$(launcher_launches)" 1
echo "$ID" > "$S/front"; sleep 0.6; echo com.webos.app.home > "$S/front"
check "the launcher, then LG Home again: asked for again" waitfor eval '[ "$(launcher_launches)" = 2 ]'
stop_bg_watch

section "C10. webOS 3 (no LG Home app): the home bar in the system log opens the launcher"
reset; echo com.webos.app.hdmi1 > "$S/front"
echo '2026-10-20T12:20:00Z [1.0] user.info surface-manager-starfish [] LSM NL_HOME_SHOWN {"CLOCK":1.0,"foregroundId":"com.webos.app.hdmi1","wedge_image":""}' > "$W/messages"
bg_watch NO_VERIFY=1 HOME_APP_DIR="$W/no-home-app"
check "in the log: watching the system log" waitfor has 'no LG Home app on this TV: watching the system log for the home bar' "$W/watch.log"
sleep 1.5
check "a home bar line from before the start is not acted on" eq "$(launcher_launches)" 0
echo '2026-10-20T12:26:20Z [30.1] user.info surface-manager-starfish [] LSM NL_HOME_SHOWN {"CLOCK":30.1,"foregroundId":"com.webos.app.hdmi1","wedge_image":""}' >> "$W/messages"
check "a new home bar line: the launcher is asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "nothing frozen, no subscription" eval 'hasnt "^-STOP" "$S/pkill.log" && no_proc "$T/bin/hold subscription"'
stop_bg_watch

# ---------- C11-C16. The subscription goes quiet (Hearth P0.6, webOS 25: no report for 35 min, LG Home left on screen) ----------
section "C11. A quiet subscription: check_loop notices it and subscribes again; the first new report is acted on"
reset; start_home; echo "$ID" > "$S/front"; echo 1 > "$S/appear_after"
bg_watch NO_VERIFY=1 CHECK_EVERY=1
check "the watcher runs, one subscription" waitfor eval 'pid_alive "$W/watch.pid" && [ "$(subs)" = 1 ]'
P_C11=$(cat "$W/watch.pid")
waitfor has "event: foreground $ID" "$W/watch.log"
check "the report is kept in LAST_REPORT, HANDLING is empty again" waitfor eval 'has "\"appId\":\"$ID\"" "$W/last-report" && [ ! -s "$W/handling" ]'
sleep 2.5
check "the app in front is the one in the last report: nothing done (no 'gone quiet', one subscription)" eval 'hasnt "gone quiet" "$W/watch.log" && [ "$(subs)" = 1 ]'
OLD=$(pgrep -f "$T/bin/hold subscription" | head -n 1)
echo com.webos.app.home > "$S/front"     # LG Home comes to the front, the subscription says nothing
check "in the log: gone quiet, with the app in front and the last report" waitfor has "the subscription has gone quiet (in front: com.webos.app.home, the last report: $ID; 2 checks 1 s apart): subscribing again (1 of 3)" "$W/watch.log"
check "the quiet subscription's luna-send is gone (KILL)" waitfor dead "$OLD"
check "a second subscription" waitfor eval '[ "$(subs)" -ge 2 ]'
check "its first report (LG Home in front) is handled: the launcher is asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "in the log: event: foreground com.webos.app.home after the restart" has 'event: foreground com.webos.app.home' "$W/watch.log"
check "the launcher in front again (no report from the quiet stand-in): one more restart, then its report freezes LG Home" waitlong has "subscribing again (2 of 3)" "$W/watch.log"
check "the main watcher is still the same process" eq "$(cat "$W/watch.pid")" "$P_C11"
stop_bg_watch
check "after TERM: no watch.sh process is left (check_loop ends with the watcher)" waitlong no_proc "$HOOKD/watch.sh"
check "and no subscription process" waitfor eval '[ "$(sub_procs)" = 0 ]'

section "C12. A subscription that reports every change is left alone"
reset; start_home; echo com.netflix.app > "$S/front"; : > "$S/sub_live"
bg_watch NO_VERIFY=1 CHECK_EVERY=1
waitfor has 'event: foreground com.netflix.app' "$W/watch.log"
echo com.webos.app.hdmi1 > "$S/front"; sleep 1.3; echo youtube.leanback.v4 > "$S/front"; sleep 1.3; echo com.netflix.app > "$S/front"; sleep 3
check "every change is reported (4 events)" eq "$(count 'event: foreground' "$W/watch.log")" 4
check "no 'gone quiet', still one subscription" eval 'hasnt "gone quiet" "$W/watch.log" && [ "$(subs)" = 1 ]'
stop_bg_watch

section "C13. A subscription that never reports: after SILENT_MAX (3) restarts the watcher asks once a second"
reset; start_home; echo com.webos.app.home > "$S/front"; : > "$S/sub_mute"; echo 1 > "$S/appear_after"
bg_watch NO_VERIFY=1 CHECK_EVERY=1
check "in the log: gone quiet, the last report: (empty)" waitlong has 'gone quiet (in front: com.webos.app.home, the last report: (empty); 2 checks 1 s apart): subscribing again (1 of 3)' "$W/watch.log"
check "in the log: went quiet 3 times: asking once a second instead" waitlong has 'the subscription went quiet 3 times: asking once a second instead' "$W/watch.log"
check "3 'gone quiet' lines (1, 2 and 3 of 3), 3 subscriptions" eq "$(count 'gone quiet' "$W/watch.log"),$(count '(3 of 3)' "$W/watch.log"),$(subs)" "3,1,3"
check "the polling file is there" test -f "$W/polling"
check "the poll sees LG Home: the launcher is asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "the launcher in front: LG Home frozen" waitfor home_frozen
sleep 3
check "check_loop has ended: no 4th 'gone quiet', no new subscription" eq "$(count 'gone quiet' "$W/watch.log"),$(subs)" "3,3"
out=$(run_env LOG="$W/stop.log" sh "$HOOKD/stop.sh")
check "stop.sh: stopped, no watch.sh process left" eval '[ "$out" = stopped ] && waitfor no_proc "$HOOKD/watch.sh"'

section "C14. The subscription answers with an error: logged, then made again"
reset; start_home; echo com.webos.app.home > "$S/front"; : > "$S/sub_error_once"; echo 1 > "$S/appear_after"
bg_watch NO_VERIFY=1 CHECK_EVERY=1
check "in the log: the subscription answered with an error" waitfor has 'the subscription answered with an error: {"returnValue":false,"errorCode":-1,"errorText":"cancelled (mock)"}' "$W/watch.log"
check "gone quiet (the last report has no app) and made again" waitlong has 'gone quiet (in front: com.webos.app.home, the last report: (empty); 2 checks 1 s apart): subscribing again (1 of 3)' "$W/watch.log"
check "the new subscription's report: the launcher is asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
stop_bg_watch

section "C15. One report handled for HANDLE_MAX s (the reader is stuck): the subscription is made again"
reset; start_home; echo com.webos.app.home > "$S/front"; : > "$S/launch_hang"
bg_watch NO_VERIFY=1 CHECK_EVERY=1 HANDLE_MAX=30
check "the launch request hangs (the reader is inside handle)" waitfor has_proc "$T/bin/hold launch"
check "HANDLING holds the uptime (whole s) the report came at" eq "$(cat "$W/handling")" 1234
sleep 2.5
check "while it is handled (less than HANDLE_MAX), it is not counted as quiet" hasnt 'gone quiet' "$W/watch.log"
echo "1300.00 999.00" > "$S/uptime"     # 66 s later
check "in the log: one report has been handled for 66 s" waitlong has 'gone quiet (one report has been handled for 66 s; 2 checks 1 s apart): subscribing again (1 of 3)' "$W/watch.log"
check "a second subscription" waitfor eval '[ "$(subs)" -ge 2 ]'
rm -f "$S/launch_hang"
stop_bg_watch

section "C16. CHECK_EVERY=0: no checks"
reset; start_home; echo "$ID" > "$S/front"
bg_watch NO_VERIFY=1 CHECK_EVERY=0
waitfor has "event: foreground $ID" "$W/watch.log"
echo com.webos.app.home > "$S/front"; sleep 3
check "no 'gone quiet', one subscription, the launcher not asked for" eval 'hasnt "gone quiet" "$W/watch.log" && [ "$(subs)" = 1 ] && [ "$(launcher_launches)" = 0 ]'
stop_bg_watch

# ---------- P. apply.sh and stock.sh, for real ----------
section "P1. apply.sh: starts the watcher and the guard"
reset; start_home; echo com.netflix.app > "$S/front"
out=$(run_env LOG="$W/apply.log" NAP=sleep INTERVAL=1 sh "$HOOKD/apply.sh")
check "answer: applied" eq "$out" applied
check "the watcher runs" waitfor pid_alive "$W/watch.pid"
check "the guard runs" waitfor pid_alive "$W/guard.pid"
check "LG Home frozen by the watcher" waitfor home_frozen
check "in the log: watcher started, guard started" eval 'has "watcher started" "$W/apply.log" && has "guard started" "$W/apply.log"'
WP=$(cat "$W/watch.pid"); GP=$(cat "$W/guard.pid")
out=$(run_env LOG="$W/apply.log" NAP=sleep INTERVAL=1 sh "$HOOKD/apply.sh")
check "run again: applied, the same watcher and guard, nothing new started" eval '[ "$out" = applied ] && [ "$(cat "$W/watch.pid")" = "$WP" ] && [ "$(cat "$W/guard.pid")" = "$GP" ] && has "watcher already running (pid $WP)" "$W/apply.log" && [ "$(count "guard started" "$W/apply.log")" = 1 ]'

section "P2. apply.sh: the launcher was uninstalled"
reset; start_home; freeze_now; rm -f "$APPD/appinfo.json"
out=$(run_env LOG="$W/apply.log" sh "$HOOKD/apply.sh"); rc=$?
check "answer launcher-missing, exit code 2" eq "$out,$rc" "launcher-missing,2"
check "LG Home unfrozen" waitfor home_running
check "the self-removal waits in the background (sleep 40, then the link and the folder)" has_proc "sleep 40; \[ -f '$APPD/appinfo.json' \]"
check "no watcher started" gone "$W/watch.pid"

section "P3. apply.sh: the emergency exit is on"
reset; start_home; freeze_now; touch "$HOOKD/stopped"
out=$(run_env LOG="$W/apply.log" sh "$HOOKD/apply.sh"); rc=$?
check "answer stopped, exit code 0" eq "$out,$rc" "stopped,0"
sleep 0.5
check "neither watcher nor guard started, LG Home untouched" eval 'gone "$W/watch.pid" && gone "$W/guard.pid" && home_frozen && no_thaw'

section "P4. stock.sh: LG Home is unfrozen and allowed"
reset; start_home; freeze_now
out=$(run_env sh "$HOOKD/stock.sh")
check "answer stock, ALLOW made" eval '[ "$out" = stock ] && test -f "$W/allow"'
check "LG Home unfrozen (SIGCONT)" eval 'has "^-CONT" "$S/pkill.log" && waitfor home_running'

# ---------- D. stop.sh ----------
section "D1. stop.sh: the emergency exit"
reset; start_home; echo com.netflix.app > "$S/front"
bg_watch
waitfor pid_alive "$W/watch.pid"; waitfor home_frozen
bg_guard
check "the guard runs" waitfor pid_alive "$W/guard.pid"
P=$(cat "$W/watch.pid"); G=$(cat "$W/guard.pid")
mkdir -p "$W/stray/launcher-homehook"
printf '%s\n' 'while :; do sleep 1; done' > "$W/stray/launcher-homehook/watch.sh"
printf '%s\n' 'while :; do sleep 1; done' > "$W/stray/launcher-homehook/guard.sh"
( sh "$W/stray/launcher-homehook/watch.sh" </dev/null >/dev/null 2>&1 & )
( sh "$W/stray/launcher-homehook/guard.sh" </dev/null >/dev/null 2>&1 & )
waitfor has_proc "$W/stray/launcher-homehook/guard.sh"
STRAYW=$(pgrep -f "$W/stray/launcher-homehook/watch.sh" | head -n 1); STRAYG=$(pgrep -f "$W/stray/launcher-homehook/guard.sh" | head -n 1)
out=$(run_env LOG="$W/stop.log" sh "$HOOKD/stop.sh")
check "stop.sh answers stopped" eq "$out" stopped
check "the file stopped is there" test -f "$HOOKD/stopped"
check "the guard has stopped" waitfor dead "$G"
check "the watcher has stopped" waitfor dead "$P"
check "stray watch.sh and guard.sh processes stopped too (kill -9 by pattern)" eval 'waitfor dead "$STRAYW" && waitfor dead "$STRAYG"'
check "both pid files removed" eval 'gone "$W/watch.pid" && gone "$W/guard.pid"'
check "LG Home unfrozen" waitfor home_running
check "in the log: emergency exit, and how to undo it" has "stop: emergency exit: watcher and guard stopped, LG Home unfrozen, $HOOKD/stopped created (undo: sh $HOOKD/stop.sh resume)" "$W/stop.log"

section "D2. After stop.sh nothing starts the watcher (apply.sh, guard.sh, watch.sh itself)"
out=$(run_env LOG="$W/stop.log" NAP=sleep INTERVAL=1 sh "$HOOKD/apply.sh")
check "apply.sh answers stopped" eq "$out" stopped
grun 2
check "guard.sh ends at once: in the log emergency exit is on" has 'guard: emergency exit is on' "$W/guard.log"
run_env LOG="$W/watch.log" timeout 5 sh "$HOOKD/watch.sh"
check "watch.sh ends at once" has 'emergency exit is on' "$W/watch.log"
check "no watch.sh or guard.sh running, LG Home not frozen" eval 'waitfor no_proc "$HOOKD/watch.sh" && no_proc "$HOOKD/guard.sh" && home_running'

section "D3. stop.sh resume"
out=$(run_env LOG="$W/stop.log" NAP=sleep INTERVAL=1 sh "$HOOKD/stop.sh" resume)
check "answer: resumed (apply.sh: applied)" eq "$out" "resumed (apply.sh: applied)"
check "the file stopped is removed" gone "$HOOKD/stopped"
check "the watcher runs again" waitfor pid_alive "$W/watch.pid"
check "the guard runs again" waitfor pid_alive "$W/guard.pid"
check "LG Home frozen again (at the watcher's start)" waitfor home_frozen

section "D4. stop.sh with nothing running"
reset; start_home; freeze_now
out=$(run_env LOG="$W/stop.log" sh "$HOOKD/stop.sh")
check "answer stopped, LG Home unfrozen" eval '[ "$out" = stopped ] && waitfor home_running'

# ---------- E. guard.sh ----------
section "E1. guard: the watcher is not running"
reset; start_home; echo com.netflix.app > "$S/front"
grun 1
check "after 1 check apply.sh not yet run (CONFIRM=2 in a row)" gone "$W/watch.pid"
grun 2
check "after 2 checks in a row the watcher runs" waitfor pid_alive "$W/watch.pid"
check "in the log: the watcher was not running: apply.sh: applied (restart 1 of 5 since boot)" has 'guard: the watcher was not running: apply.sh: applied (restart 1 of 5 since boot)' "$W/guard.log"
check "the count of restarts is 1" eq "$(cat "$W/restarts")" 1
check "the guard removed its pid file when it ended" gone "$W/guard.pid"

section "E2. guard: the watcher stops again while the guard runs: started again"
reset; start_home; echo com.netflix.app > "$S/front"
w_up="i=0; while [ \$i -lt 50 ] && ! { p=\$(cat '$W/watch.pid' 2>/dev/null); [ -n \"\$p\" ] && kill -0 \"\$p\" 2>/dev/null; }; do sleep 0.1; i=\$((i + 1)); done"
echo "$w_up" > "$S/step.2"
echo "p=\$(cat '$W/watch.pid'); kill -9 \"\$p\"; i=0; while [ \$i -lt 50 ] && kill -0 \"\$p\" 2>/dev/null; do sleep 0.1; i=\$((i + 1)); done" > "$S/step.3"
echo "$w_up" > "$S/step.5"
grun 6 NAP="$T/bin/nap-steps"
check "two restarts, the second one logged as 2 of 5" eval '[ "$(cat "$W/restarts")" = 2 ] && [ "$(count "the watcher was not running: apply.sh: applied" "$W/guard.log")" = 2 ] && has "(restart 2 of 5 since boot)" "$W/guard.log"'
check "the watcher runs" waitfor pid_alive "$W/watch.pid"

section "E3. guard: watch.sh is Hearth's own (Hearth was opened and rewrote the helper): LG Home unfrozen, the guard exits"
reset; start_home; freeze_now; hearth_watch
grun 3
check "LG Home unfrozen at the first check" eval 'waitfor home_running && [ "$(count "is not HearthNG" "$W/guard.log")" = 1 ]'
check "in the log: not HearthNG's: LG Home unfrozen, exiting" has "guard: $HOOKD/watch.sh is not HearthNG's (another launcher's helper, e.g. the original Hearth's): LG Home unfrozen, exiting" "$W/guard.log"
check "no watcher started" gone "$W/watch.pid"
check "one notification in Russian, as webosbrew: why LG Home is back" eq "$(calls '^toast caller=webosbrew .*Помощник HearthNG заменён помощником другого лаунчера: LG Home снова работает')" 1
reset; start_home; freeze_now; hearth_watch; echo en-GB > "$S/locale"
grun 1
check "menu in English: the notification in English" eq "$(calls '^toast caller=webosbrew .*Another launcher.s helper replaced the HearthNG helper: LG Home works again')" 1
reset; start_home; freeze_now; p0_watch
grun 1
check "Hearth P0.x's watch.sh (it freezes LG Home too): also not HearthNG's, LG Home unfrozen" eval 'waitfor home_running && [ "$(count "is not HearthNG" "$W/guard.log")" = 1 ]'
check "and the notification" eq "$(calls '^toast caller=webosbrew .*Помощник HearthNG заменён помощником другого лаунчера')" 1
reset; start_home; freeze_now; rm -f "$HOOKD/watch.sh"
grun 1
check "watch.sh missing: LG Home unfrozen too" eval 'waitfor home_running && has "guard: $HOOKD/watch.sh is missing: LG Home unfrozen, exiting" "$W/guard.log"'
check "but no notification (switching the helper off removes it)" eq "$(calls '^toast ')" 0

section "E4. guard: the launcher was uninstalled"
reset; start_home; freeze_now; rm -f "$APPD/appinfo.json"
grun 1
check "after 1 check nothing done" eval 'home_frozen && no_thaw'
grun 2
check "after 2 checks in a row LG Home unfrozen" waitfor home_running
check "no watcher started; in the log: HearthNG is not installed" eval 'gone "$W/watch.pid" && has "guard: HearthNG is not installed" "$W/guard.log"'

section "E5. guard: the emergency exit is on"
reset; start_home; freeze_now; touch "$HOOKD/stopped"
grun 3
check "no watcher started, LG Home untouched" eval 'gone "$W/watch.pid" && home_frozen && no_thaw'
check "in the log: emergency exit is on" has 'guard: emergency exit is on' "$W/guard.log"

section "E6. guard: too many restarts since boot (MAX_RESTARTS=5): gives up, LG Home unfrozen, a notification"
reset; start_home; freeze_now; echo 5 > "$W/restarts"
grun 2
check "LG Home unfrozen, no watcher started, the count stays 5" eval 'waitfor home_running && gone "$W/watch.pid" && [ "$(cat "$W/restarts")" = 5 ]'
check "one notification in Russian, as webosbrew" eq "$(calls '^toast caller=webosbrew .*Помощник HearthNG несколько раз останавливался: LG Home снова работает')" 1
check "in the log: after 5 restarts since boot" has 'guard: the watcher has stopped again after 5 restarts since boot: LG Home unfrozen, exiting' "$W/guard.log"
reset; start_home; freeze_now; echo 5 > "$W/restarts"; echo en-GB > "$S/locale"
grun 2
check "menu in English: the notification in English" eq "$(calls '^toast caller=webosbrew .*The HearthNG helper keeps stopping: LG Home works again')" 1

section "E7. guard: one at a time"
reset; hold guard "$W/guard.pid"; H=$(cat "$W/guard.pid")
grun 1
check "a second guard ends at once, the first one's pid file stays" eval 'has "another guard is already running (pid $H)" "$W/guard.log" && [ "$(cat "$W/guard.pid")" = "$H" ]'

section "E8. guard: TERM stops it"
reset; start_home; echo com.netflix.app > "$S/front"; bg_watch; waitfor pid_alive "$W/watch.pid"
bg_guard
waitfor pid_alive "$W/guard.pid"; G=$(cat "$W/guard.pid")
kill -TERM "$G"
check "the guard has ended, its pid file removed" eval 'waitfor dead "$G" && gone "$W/guard.pid"'
check "in the log: stopped" has "guard: stopped (pid $G)" "$W/guard.log"
check "the watcher still runs" pid_alive "$W/watch.pid"
stop_bg_watch

# ---------- F. diagnose.sh's self-test ----------
section "F. diagnose.sh's self-test (the same code as on the TV): without and with Keep Hearth ready"
reset
{ echo "HOOK='$HOOKD'"; echo "ST='$W/selftest'"; sed -n '/^if grep -q WATCH_STDIN/,/^fi$/p' "$SRC/diagnose.sh"; } > "$W/selftest.sh"
out=$(sh "$W/selftest.sh" 2>&1)
check "exactly two lines starting with WOULD OPEN" eq "$(echo "$out" | grep -c '^WOULD OPEN')" 2
check "the first: a plain launch of the launcher" eq "$(echo "$out" | grep '^WOULD OPEN' | sed -n 1p)" "WOULD OPEN: -n 1 -a com.webos.app.home luna://com.webos.applicationManager/launch {\"id\":\"$ID\"}"
check "the second: after the line about Keep Hearth ready, with keepAlive" eq "$(echo "$out" | sed -n '/^-- the same with Keep Hearth ready on/{n;p;}')" "WOULD OPEN: -n 1 -a com.webos.app.home luna://com.webos.applicationManager/launch {\"id\":\"$ID\",\"keepAlive\":true}"
check "the self-test's files removed" eval '[ -z "$(ls -d "$W"/selftest?* 2>/dev/null | grep -v "/selftest.sh$")" ]'
touch "$HOOKD/stopped"
out=$(sh "$W/selftest.sh" 2>&1)
check "the emergency exit on: the self-test still works (it has its own stopped file)" eq "$(echo "$out" | grep -c '^WOULD OPEN')" 2

# ---------- H. the TV turning on after standby ----------
wake_watch () { bg_watch NO_VERIFY=1 WAKE_POLL=1 WAKE_POLL_STANDBY=1 WAKE_SETTLE=0 WAKE_NAP=sleep "$@"; }
section "H1. Standby, then the TV Active with LG Home in front: launcher opened; notification after TOAST_DELAY, closeToast once it is in front"
reset; start_home; echo com.netflix.app > "$S/front"
wake_watch LOADING_TOAST=auto TOAST_DELAY=1
check "the watcher runs" waitfor pid_alive "$W/watch.pid"
waitfor has 'start: LG Home frozen' "$W/watch.log"
echo Suspend > "$S/power"; date +%s > "$W/standby"; echo com.webos.app.home > "$S/front"
sleep 2
check "while the TV is not Active, the launcher is not asked for" eq "$(launcher_launches)" 0
echo Active > "$S/power"
check "the launcher asked for after the TV turned on" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "in the log: wake (after standby): foreground com.webos.app.home" waitfor has 'wake (after standby): foreground com.webos.app.home: opened the launcher' "$W/watch.log"
check "the notification not before the launch (order in calls)" waitfor eval 'grep -n "" "$S/calls" | grep -E "^[0-9]+:(launch|toast)" | cut -d: -f2 | cut -c1-6 | tr "\n" " " | grep -q "^launch toast "'
check "notification \"Домашний экран загружается…\" as webosbrew" has 'toast caller=webosbrew .*Домашний экран загружается…' "$S/calls"
check "the standby mark removed" gone "$W/standby"
echo "$ID" > "$S/front"
check "the launcher in front: closeToast webosbrew-1" waitfor has 'closetoast caller=webosbrew {"toastId":"webosbrew-1"}' "$S/calls"
sleep 2
check "one launch (not asked for again), one notification" eq "$(launcher_launches),$(calls '^toast')" "1,1"
stop_bg_watch

section "H1a. The TV turns on, menu in English: Home screen is loading…, without the launcher's name"
reset; start_home; echo com.netflix.app > "$S/front"; echo en-GB > "$S/locale"
wake_watch LOADING_TOAST=auto TOAST_DELAY=1
waitfor has 'start: LG Home frozen' "$W/watch.log"
echo com.webos.app.home > "$S/front"; date +%s > "$W/standby"
check "notification in English" waitfor has 'toast caller=webosbrew .*"Home screen is loading…"' "$S/calls"
check "no Hearth in the notifications" hasnt 'toast.*Hearth' "$S/calls"
stop_bg_watch

section "H1b. The TV turns on and the launcher comes at once: no notification"
reset; start_home; echo com.netflix.app > "$S/front"; echo 1 > "$S/appear_after"
wake_watch LOADING_TOAST=auto TOAST_DELAY=2
waitfor has 'start: LG Home frozen' "$W/watch.log"
echo "" > "$S/front"; date +%s > "$W/standby"
check "the launcher asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "the helper ended without a notification" eval 'sleep 1; waitfor gone "$W/tlock" && [ "$(calls "^toast")" = 0 ]'
stop_bg_watch

section "H1c. In standby the wake_loop step is WAKE_POLL_STANDBY (1 s), after that WAKE_POLL again"
reset; start_home; echo com.netflix.app > "$S/front"
bg_watch NO_VERIFY=1 WAKE_POLL=3 WAKE_SETTLE=0 WAKE_NAP="$T/bin/nap-log"
waitfor has 'start: LG Home frozen' "$W/watch.log"
check "without standby: pauses of 3" waitfor eval 'grep -qx 3 "$S/wake_naps"'
echo Suspend > "$S/power"; date +%s > "$W/standby"; echo com.webos.app.home > "$S/front"
check "in standby: pauses of 1" waitfor eval 'grep -qx 1 "$S/wake_naps"'
: > "$S/wake_naps"; echo Active > "$S/power"
check "the TV turning on is seen, the launcher asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "after that: pauses of 3 again" waitfor eval '[ "$(tail -n 1 "$S/wake_naps")" = 3 ]'
stop_bg_watch

section "H2. The TV turns on with HDMI in front: left alone"
reset; start_home; echo com.netflix.app > "$S/front"
wake_watch LOADING_TOAST=auto TOAST_DELAY=1
waitfor has 'start: LG Home frozen' "$W/watch.log"
date +%s > "$W/standby"; echo com.webos.app.hdmi2 > "$S/front"
check "in the log: another app is in front (com.webos.app.hdmi2)" waitfor has 'another app is in front (com.webos.app.hdmi2): left as it is' "$W/watch.log"
sleep 1.5
check "the launcher not asked for, no notification" eq "$(launcher_launches),$(calls '^toast')" "0,0"
stop_bg_watch

section "H3. The TV turns on with the launcher itself in front (its window may not be back): launched over itself, no notification"
reset; start_home; echo "$ID" > "$S/front"
wake_watch LOADING_TOAST=auto TOAST_DELAY=1
waitfor has 'start: LG Home frozen' "$W/watch.log"
date +%s > "$W/standby"
check "the launcher asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "in the log: foreground $ID" waitfor has "wake (after standby): foreground $ID" "$W/watch.log"
check "no notification (the launcher is in front)" eval 'waitfor gone "$W/tlock" && [ "$(calls "^toast")" = 0 ]'
stop_bg_watch

section "H3a. The launcher in front and it showed itself after the TV turned on (launcher-alive newer): no launch, no notification"
reset; start_home; echo "$ID" > "$S/front"
wake_watch LOADING_TOAST=auto TOAST_DELAY=1 WAKE_SETTLE=1
waitfor has 'start: LG Home frozen' "$W/watch.log"
date +%s > "$W/standby"
waitfor has 'the TV is on again' "$W/watch.log"; touch -t 209901010000 "$W/alive"   # it "showed itself" during WAKE_SETTLE
check "in the log: has shown itself since the TV turned on: nothing to do" waitfor has 'wake (after standby): Hearth is in front and has shown itself since the TV turned on' "$W/watch.log"
sleep 1.5
check "the launcher not asked for, no notification" eq "$(launcher_launches),$(calls '^toast')" "0,0"
stop_bg_watch

section "H3b. The launcher in front, launcher-alive older than standby: launched over itself"
reset; start_home; echo "$ID" > "$S/front"; touch -t 200001010000 "$W/alive"
wake_watch
waitfor has 'start: LG Home frozen' "$W/watch.log"
touch -t 200101010000 "$W/standby-ref"; date +%s > "$W/standby"
check "the launcher asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
stop_bg_watch

section "H3c. The launcher in front and it showed itself after the TV went to standby (before it turned on): no launch"
reset; start_home; echo "$ID" > "$S/front"
wake_watch
waitfor has 'start: LG Home frozen' "$W/watch.log"
touch -t 200001010000 "$W/standby-ref"; touch -t 200101010000 "$W/alive"; date +%s > "$W/standby"
check "in the log: has shown itself since the TV went to standby: nothing to do" waitfor has 'wake (after standby): Hearth is in front and has shown itself since the TV went to standby' "$W/watch.log"
sleep 1.5
check "the launcher not asked for; the standby time mark removed" eval '[ "$(launcher_launches)" = 0 ] && gone "$W/standby-ref"'
stop_bg_watch

section "H4. The system slept (uptime jumped) without a standby event: the launcher is opened"
reset; start_home; echo com.netflix.app > "$S/front"
wake_watch
waitfor has 'start: LG Home frozen' "$W/watch.log"
echo com.webos.app.home > "$S/front"; echo "1600.00 999.00" > "$S/uptime"
check "in the log: the system slept" waitfor has 'the system slept about' "$W/watch.log"
check "the launcher asked for" waitfor eval '[ "$(launcher_launches)" = 1 ]'
check "in the log: wake (after sleep)" has 'wake (after sleep): foreground com.webos.app.home' "$W/watch.log"
stop_bg_watch

section "H5. The TV turns on with ALLOW (the user opened LG Home): nothing done"
reset; start_home; echo com.netflix.app > "$S/front"
wake_watch
waitfor has 'start: LG Home frozen' "$W/watch.log"
date +%s > "$W/allow"; echo com.webos.app.home > "$S/front"; date +%s > "$W/standby"
check "in the log: nothing to do" waitfor has 'wake (after standby): LG Home is allowed' "$W/watch.log"
check "the launcher not asked for" eq "$(launcher_launches)" 0
stop_bg_watch

section "H6. A normal event (the TV on): the power state is not asked for"
reset; start_home; freeze_now; echo 1 > "$S/appear_after"
: > "$S/calls"
stdin_watch com.webos.app.home NO_VERIFY=1
check "in the log: the event without a power state" has 'event: foreground com.webos.app.home$' "$W/watch.log"
check "no power state before the launch (the stand-in does not log getPowerState: checked in the log)" hasnt 'event: foreground com.webos.app.home (' "$W/watch.log"

section "H7. The watcher stopped: its background loop ends too"
reset; start_home; echo com.netflix.app > "$S/front"
wake_watch
waitfor has 'start: LG Home frozen' "$W/watch.log"
stop_bg_watch
sleep 2.5
check "no watch.sh process left" no_proc "$HOOKD/watch.sh"

section "N1. Own notifications: the defaults in watch.sh and guard.sh"
for f in watch guard; do
    check "$f.sh: TOAST_STYLE=auto, TOAST_MS=2000, the app com.hearthng.toast" eval \
        'hasline "TOAST_APP_ID=\"\${TOAST_APP_ID:-com.hearthng.toast}\"" "$SRC/$f.sh" && has "TOAST_STYLE=\"\${TOAST_STYLE:-auto}\"" "$SRC/$f.sh" && has "TOAST_MS=\"\${TOAST_MS:-2000}\"" "$SRC/$f.sh"'
done
check "watch.sh: the last report naming the own notification is not compared (check_loop)" has 'is_toast_app "$sc_r" && return 1' "$WS"
own_app () { mkdir -p "$W/toastapp"; echo '{}' > "$W/toastapp/appinfo.json"; }

section "N2. Loading notification with the app installed: own, 2000 ms, no system notification"
reset; start_home; own_app
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1
check "own notification launched with the text and ms 2000" waitfor has 'owntoast caller= {"id":"com.hearthng.toast","params":{"text":"Домашний экран загружается…","ms":2000}}' "$S/calls"
check "in the log: own toast shown" waitfor has 'own toast shown' "$W/watch.log"
check "TLOCK removed; no createToast, no closeToast" eval 'waitfor gone "$W/tlock" && [ "$(calls "^toast"),$(calls "^closetoast")" = "0,0" ]'
check "the launcher is asked for once (the own notification is not a launcher launch)" eq "$(launcher_launches)" 1

section "N3. TOAST_STYLE=system: the TV's notification even with the app installed"
reset; start_home; own_app
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1 TOAST_STYLE=system
check "createToast as webosbrew" waitfor has 'toast caller=webosbrew .*Домашний экран загружается…' "$S/calls"
check "no own notification" eval 'waitfor gone "$W/tlock" && [ "$(calls "^owntoast")" = 0 ]'

section "N4. The app not installed (auto): the TV's notification, as before"
reset; start_home
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1
check "createToast, no own notification" eval 'waitfor has "toast caller=webosbrew .*Домашний экран загружается…" "$S/calls" && waitfor gone "$W/tlock" && [ "$(calls "^owntoast")" = 0 ]'

section "N5. The launch of the own notification is refused: the TV's notification instead"
reset; start_home; own_app; touch "$S/owntoast_deny"
stdin_watch com.webos.app.home NO_VERIFY=1 LOADING_TOAST=auto TOAST_DELAY=1 TOAST_HOLD=1
check "one try of the own one, then createToast" eval 'waitfor has "toast caller=webosbrew .*Домашний экран загружается…" "$S/calls" && [ "$(calls "^owntoast")" = 1 ]'
check "in the log: refused, with the answer" waitfor has 'own toast "Домашний экран загружается…" refused: {"returnValue":false,"errorCode":-101,"errorText":"not found (mock)"}: the TV.s notification instead' "$W/watch.log"

section "N6. TOAST_MS: a number is passed on, anything else is 2000"
reset; start_home; own_app
rep com.webos.app.home | run_env LOG="$W/watch.log" WATCH_TOAST="x" TOAST_MS=1500 sh "$HOOKD/watch.sh"
check "ms 1500" has '"ms":1500}}' "$S/calls"
: > "$S/calls"
rep com.webos.app.home | run_env LOG="$W/watch.log" WATCH_TOAST="x" TOAST_MS=abc sh "$HOOKD/watch.sh"
check "TOAST_MS=abc: ms 2000" has '"ms":2000}}' "$S/calls"

section "N7. WATCH_TOAST: one notification and exit, nothing else runs"
reset; start_home; freeze_now; own_app
run_env LOG="$W/watch.log" WATCH_TOAST="Проверка" sh "$HOOKD/watch.sh" </dev/null
check "one own notification with that text" eq "$(calls '^owntoast.*"text":"Проверка"')" 1
check "no subscription, no pid file, no launch of the launcher, LG Home left frozen" eval 'gone "$S/subs" && gone "$W/watch.pid" && [ "$(launcher_launches)" = 0 ] && home_frozen && no_thaw'
check "in the log: own toast with the time the request took" has 'watcher: own toast "Проверка" (2000 ms, the request took [0-9.]* s): {"returnValue":true' "$W/watch.log"
rm -rf "$W/toastapp"; : > "$S/calls"
run_env LOG="$W/watch.log" WATCH_TOAST="Проверка" sh "$HOOKD/watch.sh" </dev/null
check "without the app: one createToast as webosbrew" eq "$(calls '^owntoast'),$(calls '^toast caller=webosbrew .*"Проверка"')" "0,1"

section "N8. A report naming the own notification window: ignored"
reset; start_home; freeze_now; own_app
stdin_watch com.hearthng.toast
check "no launch, no notification, LG Home left frozen" eval '[ "$(calls "^launch"),$(calls "^owntoast"),$(calls "^toast")" = "0,0,0" ] && home_frozen && no_thaw'
check "the event is in the log, nothing else happened" eval 'has "event: foreground com.hearthng.toast" "$W/watch.log" && hasnt "opened the launcher" "$W/watch.log"'

section "N9. The check after a launch: SAM names the own notification twice, then LG Home: the check goes on"
reset; start_home; freeze_now; echo 2 > "$S/front_toast_n"
stdin_watch com.webos.app.home VERIFY_TRIES=1 RESTART_WAIT=1
check "the check has ended" waitfor gone "$W/vlock"
check "both answers naming the notification were asked past" eq "$(calls '^fronttoast')" 2
check "the launcher asked for again (verify did not stop at the notification): 3 launches = 1 + 1 try + 1 restart" eq "$(launcher_launches)" 3

section "N10. guard gives up: own notification when the app is installed"
reset; start_home; freeze_now; echo 5 > "$W/restarts"; own_app
grun 2
check "LG Home unfrozen" waitfor home_running
check "one own notification (2000 ms), no createToast" eq "$(calls '^owntoast.*Помощник HearthNG несколько раз останавливался: LG Home снова работает.*"ms":2000'),$(calls '^toast')" "1,0"
check "in the log: own toast" has 'guard: own toast "Помощник HearthNG' "$W/guard.log"
reset; start_home; freeze_now; echo 5 > "$W/restarts"; own_app; touch "$S/owntoast_deny"
grun 2
check "refused: createToast instead" eq "$(calls '^owntoast'),$(calls '^toast caller=webosbrew .*Помощник HearthNG')" "1,1"

cleanup_procs
echo
echo "Result: $pass passed, $fail failed"
if [ "$fail" = 0 ]; then rm -rf "$T"; else echo "The files of the last test are left in $T"; fi
[ "$fail" = 0 ]
