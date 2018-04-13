#!/bin/bash
#
# usb-anacron - Anacron to run jobs when a USB disk is plugged in
#

usage() {
    echo "Usage: $0 [-c <cachedir>] <target> <cronbase>" >&2
}

CACHEDIR=

# Parse command-line flags
while getopts c:h OPTNAME; do
    case "$OPTNAME" in
        c)
            CACHEDIR="$OPTARG"
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))


if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

TARGET="$1"
CRONBASE="$2"

if [ -z "$TARGET" ] || [ "$TARGET" = "UUID" ] || \
       ! [ "${TARGET%%=?*}=" = "UUID=" ]; then
    echo "$0: Target must be a partition UUID in the form UUID=..."
    exit 1
fi

if [ -z "$CRONBASE" ] || ! [ -d "$CRONBASE" ]; then
    echo "$0: $CRONBASE: Specified base is not a directory" >&2
    exit 1
fi

# findmnt from util-linux
USB="$(findmnt -ln -o TARGET -S "$TARGET")"
[ -n "$USB" ] || exit 0

if ! [ -e "$USB/lost+found" ]; then
    echo "USB detected, but not mounted? this should never happen" >&2
    exit 1
fi

# Locate cache directory
# if [ -z "$CACHEDIR" ]; then
#     CACHEDIR="$HOME/.usb-anacron"
#     [ -d "$CACHEDIR" ] || mkdir -m 0700 "$CACHEDIR"
# fi
[ -z "$CACHEDIR" ] && CACHEDIR="$CRONBASE"

check_stamp() {
    local STAMPFILE DURATION DIFF
    STAMPFILE="$CACHEDIR/$TARGET.$1-stamp"
    DURATION=$2
    if [ -e "$STAMPFILE" ]; then
        DIFF=$(($(date +%s) - $(stat -c %Y "$STAMPFILE")))
        [ "$DIFF" -lt $DURATION ] && exit 0
    fi
    # It's been long enough, OK to continue
    touch "$STAMPFILE"
}

run_frequency() {
    local FREQUENCY INTERVAL CRONDIR
    FREQUENCY="$1"
    INTERVAL="$2"
    CRONDIR="$CRONBASE/cron.$FREQUENCY"
    [ -d "$CRONDIR" ] || return 0
    [ "$INTERVAL" -ge 1 ] && check_stamp "$FREQUENCY" "$INTERVAL"
    run-parts --arg="$USB" "$CRONDIR"
}

run_frequency always       0
run_frequency hourly    3600
run_frequency daily    86400
run_frequency weekly  604800
