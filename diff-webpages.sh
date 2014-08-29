#!/bin/bash
#
# diff-webpages.sh - Report on changes to webpages
#

usage() {
    cat <<EOF >&2
Usage: $0 [-l] <url> [...]

  -l        Preprocess diff input with lynx(1) (don't output HTML)
EOF
}

LYNX='lynx -dump -stdin -nolist'
USE_LYNX=

# Parse command-line flags
while getopts hl OPTNAME; do
    case "$OPTNAME" in
        l)
            USE_LYNX=1
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done
shift $((OPTIND-1))

# Ensure at least one URL is provided
if [ "$#" -le 0 ]; then
    usage
    exit 1
fi

CACHEDIR=~/.cache/diff-webpages
[ -d "$CACHEDIR" ] || mkdir "$CACHEDIR" || exit 1
chmod 700 "$CACHEDIR"

for URL in "$@"; do
    CACHEFILE="$CACHEDIR/"$(printf "%s" "$URL" | md5sum | cut -d' ' -f1)
    TEMPFILE="$CACHEFILE.new"

    [ -f "$CACHEFILE" ] || : > "$CACHEFILE"
    if ! wget -q -O "$TEMPFILE" "$URL"; then
        printf "%s\n  Download failed.\n\n" "$URL"
        continue
    fi

    # Compare the checksum, size, and modification date
    OLDSUM=$(md5sum "$CACHEFILE" | cut -d' ' -f1)
    OLDLEN=$(wc -c "$CACHEFILE" | cut -d' ' -f1)
    OLDDAY=$(date -d @$(stat --format %Y "$CACHEFILE"))
    NEWSUM=$(md5sum "$TEMPFILE" | cut -d' ' -f1)
    NEWLEN=$(wc -c "$TEMPFILE" | cut -d' ' -f1)
    NEWDAY=$(date -d @$(stat --format %Y "$TEMPFILE"))

    if [ "$OLDSUM" != "$NEWSUM" ] || [ "$OLDLEN" != "$NEWLEN" ]; then
        # Report the change
        printf "%s\n  %s => %s\n  %32s    %32s\n  %32d    %32d\n\n" \
            "$URL" "$OLDSUM" "$NEWSUM" "$OLDDAY" "$NEWDAY" "$OLDLEN" "$NEWLEN"

        # Provide a diff
        if [ -n "$USE_LYNX" ]; then
            diff -u <($LYNX < "$CACHEFILE") <($LYNX < "$TEMPFILE")
        else
            diff -u "$CACHEFILE" "$TEMPFILE"
        fi
        printf "\n"
    fi
    mv "$TEMPFILE" "$CACHEFILE"
    sleep 2
done
