#!/bin/sh
# Collects what is needed to see why the launcher does not open when LG Home comes to the front.
# Run it on the TV over SSH and paste the output:   sh /media/developer/launcher-homehook/diagnose.sh
# (the same text is saved in /tmp/launcher-diagnose.txt). It changes nothing.

HOOK=/media/developer/launcher-homehook
LAUNCHER_ID=com.hearthng.launcher
APP_QML=/usr/palm/applications/com.webos.app.home/qml
PIDFILE=/tmp/launcher-homehook-watch.pid
GUARD_PIDFILE=/tmp/launcher-homehook-guard.pid
HOME_PROC='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
ST=/tmp/launcher-selftest
KEEP_FLAG=/media/developer/launcher-keepready/on
KEYS=/home/root/.config/lginputhook/keybinds.json
running () { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

{
echo "== time";                       date; cat /proc/uptime
echo "== files";                      ls -l "$HOOK" 2>&1
echo "== version";                    cat "$HOOK/version" 2>&1
echo "== emergency exit (stop.sh)";   if [ -f "$HOOK/stopped" ]; then echo "ON since $(ls -l "$HOOK/stopped" | sed 's/  */ /g' | cut -d' ' -f6-8): undo with sh $HOOK/stop.sh resume"; else echo "off"; fi
echo "== startup links";              ls -l /var/lib/webosbrew/init.d/ 2>&1
echo "-- names run-parts may skip (only a-z A-Z 0-9 _ - are safe; dots are skipped by BusyBox before 1.34):"
ls /var/lib/webosbrew/init.d/ 2>/dev/null | grep '[^A-Za-z0-9_-]' || echo "none"
echo "-- busybox version (run-parts comes from it):"; busybox 2>&1 | head -n 1
echo "== watcher"
if running "$PIDFILE"; then echo "running, pid $(cat "$PIDFILE")"; else echo "NOT running (pid file: $(cat "$PIDFILE" 2>&1))"; fi
echo "== guard"
if running "$GUARD_PIDFILE"; then echo "running, pid $(cat "$GUARD_PIDFILE")"; else echo "NOT running (pid file: $(cat "$GUARD_PIDFILE" 2>&1))"; fi
echo "watcher restarts by the guard since boot: $(cat /tmp/launcher-homehook-restarts 2>/dev/null || echo 0)"
echo "-- every watch.sh / guard.sh / luna-send subscription process (one watcher shows as several watch.sh: itself, the"
echo "   reader of its subscription and its background checks; only the pid above is the watcher):"
ps 2>&1 | grep -E "[w]atch.sh|[g]uard.sh|[g]etForegroundAppInfo"
echo "== does the watcher still hear the subscription? (its last report should name the app in front now)"
echo "last report: $(cut -c1-160 /tmp/launcher-homehook-last-report 2>&1)"
echo "a report is being handled since (uptime s; empty = none): $(cat /tmp/launcher-homehook-handling 2>&1)"
if [ -f /tmp/launcher-homehook-polling ]; then echo "asking once a second (no subscription): yes"; else echo "asking once a second (no subscription): no"; fi
echo "the subscription went quiet and was made again, this boot: $(grep -c 'subscription has gone quiet' /tmp/launcher-homehook.log 2>/dev/null)"
echo "== old launcher-takeover (Hearth 1.x; while it is on, watch.sh stands aside)"
ls -l /media/developer/launcher-takeover/enabled /var/lib/webosbrew/init.d/47-launcher-takeover 2>&1
echo "== do the scripts parse on this TV's shell?"
for f in watch.sh apply.sh stock.sh guard.sh stop.sh; do if sh -n "$HOOK/$f" 2>&1; then echo "$f: syntax OK"; else echo "$f: SYNTAX PROBLEM"; fi; done
echo "== does the watcher's decision logic work on this TV's shell? (should say WOULD OPEN, once)"
if grep -q WATCH_STDIN "$HOOK/watch.sh" 2>/dev/null; then
    # Everything the test touches is its own: it never sees the real pid file, LG Home, the launcher or Keep Hearth ready.
    mkdir -p "$ST-app" && echo '{}' > "$ST-app/appinfo.json"
    printf '#!/bin/sh\necho "WOULD OPEN: $*"\n' > "$ST-luna.sh"; chmod +x "$ST-luna.sh"
    sed 's#>/dev/null 2>&1$##' "$HOOK/watch.sh" > "$ST-watch.sh"
    echo on > "$ST-keep"
    for k in "$ST-no-keep" "$ST-keep"; do
        [ "$k" = "$ST-keep" ] && echo "-- the same with Keep Hearth ready on (should say WOULD OPEN once, with keepAlive):"
        echo '{"returnValue":true,"appId":"com.webos.app.home","processId":"","windowId":""}' |
            NO_VERIFY=1 WATCH_STDIN=1 LUNA_SEND="$ST-luna.sh" LOG=/dev/null ALLOW="$ST-allow" \
            PIDFILE="$ST.pid" MARK="$ST-mark" VLOCK="$ST-vlock" LAUNCHER="$ST-app" STOPPED="$ST-stopped" \
            TAKEOVER_FLAG="$ST-no-takeover" KEEP_FLAG="$k" HOME_PROC=selftest-no-such-process \
            sh "$ST-watch.sh" 2>&1 || echo "(self-test failed)"
    done
    rm -rf "$ST-luna.sh" "$ST-watch.sh" "$ST-app" "$ST-allow" "$ST.pid" "$ST-mark" "$ST-vlock" "$ST-keep"
else
    echo "skipped: this watch.sh has no WATCH_STDIN test mode"
fi
echo "== has the launcher shown itself recently? (the launcher touches this file when it is on screen)"; ls -l /tmp/launcher-alive /tmp/launcher-launch-mark 2>&1
echo "== is a launcher process running? (pgrep -f)"; p=$(pgrep -f "$LAUNCHER_ID" 2>&1); if [ -n "$p" ]; then echo "$p" | head -5; else echo "none found"; fi
echo "== files in /tmp";                ls -l /tmp/launcher-* 2>&1
echo "== stand-in still mounted over LG Home's QML? (should be 'no')"; grep " $APP_QML " /proc/mounts || echo "no"
echo "== user asked for LG's own Home? (file exists = yes)"; ls -l /tmp/launcher-allow-stock-home 2>&1
echo "== LG Home process(es)";        ps 2>&1 | grep -iE "[c]om.webos.app.(full)?home([^A-Za-z0-9._-]|$)"
echo "-- processes the watcher freezes ($HOME_PROC; State T = frozen; none = nothing is frozen on this TV):"
p=$(pgrep -f "$HOME_PROC" 2>/dev/null); [ -n "$p" ] || echo "none"
for i in $p; do echo "pid $i: $(grep '^State' /proc/$i/status 2>&1) $(grep '^VmRSS' /proc/$i/status 2>&1)"; done
echo "== which app the Home button opens (defaultApps.home; com.webos.app.fullhome on webOS 4.x)"
luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{"category":"general","keys":["defaultApps"]}' 2>&1
echo "== other Hearth parts that also open the launcher or keep it in memory"
echo "-- Keep Hearth ready (file not empty = on):"; ls -l "$KEEP_FLAG" 2>&1
echo "-- Home button key hook (/tmp/inputhook = injected this boot):"; ls -l /tmp/inputhook /media/developer/launcher-homekey 2>&1
echo "-- buttons ($KEYS):"; cat "$KEYS" 2>&1; echo
echo "-- power-on app (bootd override; missing = the TV's own choice):"; ls -l /var/luna/preferences/bootd.json 2>&1
echo "== TV power state";             luna-send -n 1 luna://com.webos.service.tvpower/power/getPowerState '{}' 2>&1
echo "== TV menu language (notifications are in Russian for ru*, English otherwise)"
luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{"keys":["localeInfo"]}' 2>&1 | tr -d '\n' | cut -c1-200; echo
echo "== launcher installed?";        ls /media/developer/apps/usr/palm/applications/$LAUNCHER_ID 2>&1 | head -5
echo "== app in front right now";     luna-send -n 1 luna://com.webos.applicationManager/getForegroundAppInfo '{}' 2>&1
echo "== log (/tmp/launcher-homehook.log)";  tail -n 80 /tmp/launcher-homehook.log 2>&1
echo "== end"
} 2>&1 | tee /tmp/launcher-diagnose.txt
