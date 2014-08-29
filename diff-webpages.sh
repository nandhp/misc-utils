#!/bin/sh

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

    OLDSUM=$(md5sum "$CACHEFILE" | cut -d' ' -f1)
    OLDLEN=$(wc -c "$CACHEFILE" | cut -d' ' -f1)
    OLDDAY=$(date -d @$(stat --format %Y "$CACHEFILE"))
    NEWSUM=$(md5sum "$TEMPFILE" | cut -d' ' -f1)
    NEWLEN=$(wc -c "$TEMPFILE" | cut -d' ' -f1)
    NEWDAY=$(date -d @$(stat --format %Y "$TEMPFILE"))

    if [ "$OLDSUM" != "$NEWSUM" ] || [ "$OLDLEN" != "$NEWLEN" ]; then
        printf "%s\n  %s => %s\n  %32s    %32s\n  %32d    %32d\n\n" \
            "$URL" "$OLDSUM" "$NEWSUM" "$OLDDAY" "$NEWDAY" "$OLDLEN" "$NEWLEN"
        diff -u "$CACHEFILE" "$TEMPFILE"
        printf "\n"
    fi
    mv "$TEMPFILE" "$CACHEFILE"
    sleep 2
done
