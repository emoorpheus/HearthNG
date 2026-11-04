#!/bin/sh
# Tests for src/homehook/*.sh (the "Replace LG Home" helper) with fake folders and a fake luna-send. Run: npm test
# Works with any POSIX sh (macOS too): nothing here needs /proc. The tests that freeze and unfreeze a real process are in
# scripts/test-homehook-ng.sh (Linux only).
S="$(cd "$(dirname "$0")/../src/homehook" && pwd)"
T="$(mktemp -d)"; fail=0
check () { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2', wanted '$3')"; fail=1; fi; }
mkdir -p "$T/hook" "$T/launcher"
echo '{}' > "$T/launcher/appinfo.json"
printf '%s\n' '#!/bin/sh' '# test stand-in' 'LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"' > "$T/hook/watch.sh"
echo "1234.56 999.00" > "$T/uptime"
NOPROC='[n]o-such-process-for-hearthng-tests'

for f in watch.sh apply.sh stock.sh guard.sh stop.sh diagnose.sh homehook.sh; do
    check "$f is valid shell" "$(sh -n "$S/$f" && echo ok)" "ok"
done
check "watch.sh opens com.hearthng.launcher by default" "$(grep -c '^LAUNCHER_ID="${LAUNCHER_ID:-com.hearthng.launcher}"$' "$S/watch.sh")" "1"
check "only one line of watch.sh ends with >/dev/null 2>&1 (diagnose.sh's self-test needs that)" "$(grep -c '>/dev/null 2>&1$' "$S/watch.sh")" "1"

# ---- apply.sh ----
runapply () { DRY_RUN=1 APP_QML="$T/qml" HOOK="$T/hook" LAUNCHER="$T/launcher" PIDFILE="$T/pid" GUARD_PIDFILE="$T/gpid" STOPPED="$T/hook/stopped" LINK="$T/link" LOG="$T/log" HOME_PROC="$NOPROC" sh "$S/apply.sh"; }
check "apply starts the watcher when everything is in place" "$(runapply)" "applied"
mv "$T/launcher/appinfo.json" "$T/launcher/x"
check "apply refuses when the launcher is not installed" "$(runapply)" "launcher-missing"
runapply >/dev/null; check "with exit code 2" "$?" "2"
mv "$T/launcher/x" "$T/launcher/appinfo.json"
mv "$T/hook/watch.sh" "$T/hook/x"
check "apply refuses when watch.sh is missing" "$(runapply)" "files-missing"
runapply >/dev/null; check "with exit code 4" "$?" "4"
mv "$T/hook/x" "$T/hook/watch.sh"
echo "$$" > "$T/pid"
: > "$T/log"
check "apply recognises a watcher that is already running" "$(runapply)" "applied"
check "and says so in the log" "$(grep -c 'already running' "$T/log")" "1"
check "no guard.sh in the folder: no guard is started" "$(grep -c 'guard started' "$T/log")" "0"
echo '#!/bin/sh' > "$T/hook/guard.sh"
: > "$T/log"; runapply >/dev/null
check "guard.sh in the folder and no guard running: the guard is started" "$(grep -c 'guard started' "$T/log")" "1"
echo "$$" > "$T/gpid"
: > "$T/log"; runapply >/dev/null
check "a guard that is already running is left alone" "$(grep -c 'guard started' "$T/log")" "0"
rm -f "$T/pid" "$T/gpid"
touch "$T/hook/stopped"
: > "$T/log"
check "the emergency exit is on: apply starts nothing" "$(runapply)" "stopped"
runapply >/dev/null; check "with exit code 0" "$?" "0"
check "and the log says how to undo it" "$(grep -c 'stop.sh resume' "$T/log")" "2"
check "neither the watcher nor the guard is started" "$(grep -c 'started' "$T/log")" "0"
rm -f "$T/hook/stopped"

# ---- stock.sh ----
check "stock.sh reports itself done" "$(DRY_RUN=1 ALLOW="$T/allow" HOME_PROC="$NOPROC" sh "$S/stock.sh")" "stock"
check "stock.sh asks the watcher to stand down (the time in seconds)" "$(grep -c '^[0-9][0-9]*$' "$T/allow" 2>/dev/null)" "1"
rm -f "$T/allow"

# ---- watch.sh: when does it open the launcher? ----
cat > "$T/luna.sh" <<'LUNA'
#!/bin/sh
case "$*" in
  *getForegroundAppInfo*) [ -f "$FRONT_FILE" ] && cat "$FRONT_FILE" ;;
  *getPowerState*) [ -f "$POWER_FILE" ] && cat "$POWER_FILE" ;;
  *applicationManager/running*) echo '{"returnValue":true,"running":[{"id":"com.webos.app.home","processid":"1001"}]}' ;;
  *launch*) printf '%s\n' "$*" >> "$LAUNCH_LOG" ;;
esac
LUNA
chmod +x "$T/luna.sh"
rm -f "$T/launches" "$T/allow"
watch () {
    env NO_VERIFY=1 WATCH_STDIN=1 LUNA_SEND="$T/luna.sh" LAUNCH_LOG="$T/launches" FRONT_FILE="$T/front" POWER_FILE="$T/power" \
    ALLOW="$T/allow" MARK="$T/mark" VLOCK="$T/vlock" LAUNCHER="$T/launcher" LOG="$T/log" PIDFILE="$T/pid" \
    STANDBY_FLAG="$T/standby" STANDBY_REF="$T/standby-ref" KEEP_FLAG="$T/keep" TAKEOVER_FLAG="$T/no-takeover" \
    UPTIME_FILE="$T/uptime" STOPPED="$T/hook/stopped" HOME_PROC="$NOPROC" NAP=true "$@" sh "$S/watch.sh"
}
launches () { if [ -f "$T/launches" ]; then wc -l < "$T/launches" | tr -d ' '; else echo 0; fi; }
fresh () { rm -f "$T/launches"; : > "$T/log"; }
rep () { printf '{"returnValue":true,"appId":"%s","processId":"","windowId":""}\n' "$1"; }
HOME_REPORT=$(rep com.webos.app.home)
APP_REPORT='{"returnValue":true,"appId":"youtube.leanback.v4","processId":"123","windowId":"4"}'
LAUNCHER_REPORT=$(rep com.hearthng.launcher)
EMPTY_REPORT=$(rep "")
SUB_HOME='{"returnValue":true,"subscribed":true,"appId":"com.webos.app.home","processId":"","windowId":""}'

fresh; echo "$APP_REPORT" | watch
check "another app in front: nothing happens" "$(launches)" "0"
fresh; echo '{"returnValue":true,"subscribed":true}' | watch
check "a report without an app is ignored" "$(launches)" "0"
fresh; echo "$HOME_REPORT" | watch
check "LG Home in front: the launcher is opened" "$(launches)" "1"
check "and it is HearthNG that is opened, on behalf of LG Home" "$(grep -c -- '-a com.webos.app.home luna://com.webos.applicationManager/launch {"id":"com.hearthng.launcher"}' "$T/launches")" "1"
check "and the log says so" "$(grep -c 'opened the launcher' "$T/log")" "1"
fresh; printf '%s\n' "$HOME_REPORT" "$APP_REPORT" "$HOME_REPORT" | watch
check "LG Home, another app, LG Home again: opened both times" "$(launches)" "2"
fresh; echo "$SUB_HOME" | watch
check "a subscription report with extra fields works too" "$(launches)" "1"
fresh; echo '{"returnValue": true, "appId": "com.webos.app.home"}' | watch
check "a report with spaces after the colons works too" "$(launches)" "1"
fresh; echo "$LAUNCHER_REPORT" | watch
check "the launcher reported in front: nothing is opened by that alone" "$(launches)" "0"
fresh; rep com.webos.app.fullhome | watch
check "LG's full-screen Home (webOS 4.x) in front: the launcher is opened, as for LG Home" "$(launches)" "1"
fresh; rep com.webos.app.homeconnect | watch
check "a look-alike id (com.webos.app.homeconnect) is not LG Home" "$(launches)" "0"

# an empty foreground (between two apps, at boot, going to standby)
echo "$EMPTY_REPORT" > "$T/front"
fresh; echo "$EMPTY_REPORT" | watch EMPTY_AS_HOME=1
check "EMPTY_AS_HOME=1: nothing in front (and still nothing, the TV on): the launcher is opened" "$(launches)" "1"
fresh; echo "$EMPTY_REPORT" | watch EMPTY_AS_HOME=0
check "EMPTY_AS_HOME=0: nothing in front is left alone" "$(launches)" "0"
fresh; echo "$EMPTY_REPORT" | watch
check "EMPTY_AS_HOME=auto (default) and no LG Home process to freeze: nothing in front is left alone" "$(launches)" "0"
echo '{"returnValue":true,"state":"Active Standby"}' > "$T/power"
fresh; echo "$EMPTY_REPORT" | watch EMPTY_AS_HOME=1
check "nothing in front and the TV is not on: not opened" "$(launches)" "0"
check "the TV is marked as in standby" "$([ -f "$T/standby" ] && echo yes)" "yes"
fresh; echo "$HOME_REPORT" | watch
check "in standby, LG Home in front: not opened yet (it is opened when the TV turns on)" "$(launches)" "0"
check "and the log says so" "$(grep -c 'Hearth is opened when the TV turns on' "$T/log")" "1"
rm -f "$T/power"
fresh; echo "$HOME_REPORT" | watch
check "the TV is on again: LG Home in front opens the launcher" "$(launches)" "1"
check "and the standby mark is gone" "$([ -f "$T/standby" ] && echo yes || echo no)" "no"
rm -f "$T/front"

# the user asked for LG's own Home (the LG Home tile)
fresh; date +%s > "$T/allow"
echo "$HOME_REPORT" | watch
check "while LG's own Home is wanted, the watcher stands down" "$(launches)" "0"
check "the request stays while LG Home is in front" "$([ -f "$T/allow" ] && echo kept)" "kept"
printf '%s\n' "$HOME_REPORT" "$APP_REPORT" | watch
check "once LG Home has been left, the request ends" "$([ -f "$T/allow" ] && echo kept || echo ended)" "ended"
echo "$HOME_REPORT" | watch
check "and the next time LG Home comes to the front it is taken over again" "$(launches)" "1"
fresh; echo 1000 > "$T/allow"
echo "$APP_REPORT" | watch
check "a request for LG Home that never came to the front is dropped after a while" "$([ -f "$T/allow" ] && echo kept || echo ended)" "ended"
rm -f "$T/allow"

# Keep Hearth ready: a launcher that is not in memory is launched with keepAlive
fresh; echo on > "$T/keep"
echo "$HOME_REPORT" | watch
check "Keep Hearth ready on, the launcher not in memory: launched with keepAlive" "$(grep -c '"keepAlive":true' "$T/launches")" "1"
rm -f "$T/keep"

# nothing to open
fresh; mv "$T/launcher/appinfo.json" "$T/launcher/x"
echo "$HOME_REPORT" | watch
check "launcher uninstalled: nothing is opened (LG Home stays)" "$(launches)" "0"
check "and the log says so" "$(grep -c 'is not installed' "$T/log")" "1"
mv "$T/launcher/x" "$T/launcher/appinfo.json"

# ---- watch.sh: when it does not start at all ----
cat > "$T/quiet.sh" <<'Q'
#!/bin/sh
exit 0
Q
chmod +x "$T/quiet.sh"
start_watch () { timeout 10 env LUNA_SEND="$T/quiet.sh" PIDFILE="$T/pid" LOG="$T/log" LAUNCHER="$T/launcher" ALLOW="$T/allow" STOPPED="$T/hook/stopped" UPTIME_FILE="$T/uptime" HOME_PROC="$NOPROC" sh "$S/watch.sh"; }
: > "$T/log"; echo "$$" > "$T/pid"
start_watch
check "a second watcher exits at once when one is already running" "$(grep -c 'another watcher is already running' "$T/log")" "1"
check "and leaves the first one's pid file alone" "$(cat "$T/pid")" "$$"
rm -f "$T/pid"; touch "$T/hook/stopped"; : > "$T/log"
start_watch
check "the emergency exit is on: the watcher does not start" "$(grep -c 'emergency exit is on' "$T/log")" "1"
check "and writes no pid file" "$([ -f "$T/pid" ] && echo yes || echo no)" "no"
rm -f "$T/hook/stopped"

# ---- watch.sh on webOS 3: the home bar in the system log ----
bar () { NO_VERIFY=1 WATCH_BAR_STDIN=1 LUNA_SEND="$T/luna.sh" LAUNCH_LOG="$T/launches" ALLOW="$T/allow" LAUNCHER="$T/launcher" LOG="$T/log" UPTIME_FILE="$T/uptime" HOME_PROC="$NOPROC" sh "$S/watch.sh"; }
BAR_HDMI='2026-10-20T12:26:20Z [30.1] user.info surface-manager-starfish [] LSM NL_HOME_SHOWN {"CLOCK":30.1,"foregroundId":"com.webos.app.hdmi1","wedge_image":""}'
BAR_SELF='2026-10-20T12:26:50Z [60.0] user.info surface-manager-starfish [] LSM NL_HOME_SHOWN {"CLOCK":60.0,"foregroundId":"com.hearthng.launcher","wedge_image":""}'
OTHER='2026-10-20T12:26:23Z [32.9] user.info surface-manager-starfish [] LSM NL_APP_LAUNCH {"app_id":"com.webos.app.hdmi1"}'
fresh; printf '%s\n' "$BAR_HDMI" | bar
check "the home bar over another app opens the launcher" "$(launches)" "1"
fresh; printf '%s\n' "$BAR_SELF" | bar
check "the home bar over the launcher itself does not" "$(launches)" "0"
fresh; printf '%s\n' "$OTHER" | bar
check "other log lines are ignored" "$(launches)" "0"
fresh; echo 100 > "$T/allow"; printf 'TIME 105\n%s\n' "$BAR_HDMI" | bar
check "the home bar right after asking for LG Home is left alone" "$(launches)" "0"
check "and that request is used up" "$([ -f "$T/allow" ] && echo still || echo gone)" "gone"
fresh; echo 100 > "$T/allow"; printf 'TIME 200\n%s\n' "$BAR_HDMI" | bar
check "an old request for LG Home does not stop it" "$(launches)" "1"
rm -f "$T/allow"

# ---- guard.sh: the checks that do not need a real watcher ----
guard () { MAX_LOOPS=1 NAP=true HOOK="$T/hook" LAUNCHER="$T/launcher" PIDFILE="$T/pid" GUARD_PIDFILE="$T/gpid" RESTARTS="$T/restarts" STOPPED="$T/hook/stopped" LOG="$T/log" UPTIME_FILE="$T/uptime" LUNA_SEND="$T/quiet.sh" HOME_PROC="$NOPROC" sh "$S/guard.sh"; }
: > "$T/log"; touch "$T/hook/stopped"; guard
check "guard: the emergency exit is on: it exits" "$(grep -c 'guard: emergency exit is on' "$T/log")" "1"
check "guard: and removes its pid file" "$([ -f "$T/gpid" ] && echo yes || echo no)" "no"
rm -f "$T/hook/stopped"
: > "$T/log"; printf '%s\n' '#!/bin/sh' "# another launcher's watch.sh (Hearth P0.x's freezes LG Home too)" 'LAUNCHER_ID="${LAUNCHER_ID:-tld.my.customlauncher}"' 'freeze_home () { pkill -STOP -f "$HOME_PROC" 2>/dev/null; }' > "$T/hook/w2"; mv "$T/hook/watch.sh" "$T/hook/w1"; mv "$T/hook/w2" "$T/hook/watch.sh"; guard
check "guard: watch.sh is not HearthNG's (it freezes LG Home, but opens another launcher): LG Home is unfrozen and the guard exits" "$(grep -c "is not HearthNG's (another launcher's helper, e.g. the original Hearth's): LG Home unfrozen, exiting" "$T/log")" "1"
mv "$T/hook/w1" "$T/hook/watch.sh"
: > "$T/log"; echo "$$" > "$T/gpid"; guard
check "guard: a second guard exits at once" "$(grep -c 'another guard is already running' "$T/log")" "1"
check "guard: and leaves the first one's pid file alone" "$(cat "$T/gpid")" "$$"
rm -f "$T/gpid"

# ---- stop.sh ----
stopsh () { HOOK="$T/hook" STOPPED="$T/hook/stopped" PIDFILE="$T/pid" GUARD_PIDFILE="$T/gpid" WATCH_PATTERN="[n]o-watcher-$$" GUARD_PATTERN="[n]o-guard-$$" HOME_PROC="$NOPROC" LOG="$T/log" UPTIME_FILE="$T/uptime" NAP=true sh "$S/stop.sh" "$@"; }
check "stop.sh: prints stopped" "$(stopsh)" "stopped"
check "stop.sh: the emergency exit file is there" "$([ -f "$T/hook/stopped" ] && echo yes)" "yes"
cp "$S/apply.sh" "$T/hook/apply.sh"
check "stop.sh resume: the file is removed and apply.sh is run" "$(DRY_RUN=1 APP_QML="$T/qml" LAUNCHER="$T/launcher" LINK="$T/link" stopsh resume)" "resumed (apply.sh: applied)"
check "stop.sh resume: no emergency exit file" "$([ -f "$T/hook/stopped" ] && echo yes || echo no)" "no"
check "stop.sh with an unknown word: usage" "$(stopsh nonsense | cut -c1-6)" "usage:"

rm -rf "$T"
exit $fail
