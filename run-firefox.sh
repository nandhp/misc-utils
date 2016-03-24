#!/bin/bash
#
# run-firefox.sh - Run Firefox, but only if already running.
#

# $(type -P firefox) does not work if it is a wrapper script
FIREFOX=firefox

if pidof "$FIREFOX" >/dev/null || \
   zenity --question --title Firefox --text '<b><big>Firefox is not running</big></b>\n\nWould you like to start Firefox now?'; then
    exec "$FIREFOX" "$@"
fi
