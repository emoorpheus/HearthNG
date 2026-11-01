#!/bin/sh
# Lets LG's own Home be shown: the watcher stands down until the user leaves LG Home again.
# The launcher runs this before opening LG Home from its "LG Home" tile.

APP_QML="${APP_QML:-/usr/palm/applications/com.webos.app.home/qml}"
ALLOW="${ALLOW:-/tmp/launcher-allow-stock-home}"
HOME_PROC_DEFAULT='flutter-client -i com\.webos\.app\.home([^A-Za-z0-9._-]|$)'
HOME_PROC="${HOME_PROC:-$HOME_PROC_DEFAULT}"

# (earlier versions put a stand-in over LG Home's QML: take it off if it is still there)
if [ -z "$DRY_RUN" ]; then
    while grep -q " $APP_QML " /proc/mounts; do
        umount "$APP_QML" || break
    done
fi
date +%s > "$ALLOW"
# The watcher keeps LG Home frozen (SIGSTOP) while the launcher is in front; frozen, it could not be shown.
if [ -z "$DRY_RUN" ]; then
    pkill -CONT -f "$HOME_PROC" 2>/dev/null
fi
echo stock
