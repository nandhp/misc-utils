#!/bin/sh
#
# better-apod.sh - Scrape APOD website to build a better Atom feed.
#

usage() {
    cat <<EOF >&2
Usage: $0 [-m] [-n] [-q]

  -m        Only fetch current day if missing, do not attempt to update
  -n        Do not fetch data or expire old data
  -q        Quiet mode, do not output feed
EOF
}

APODHOST="https://apod.nasa.gov/"
APODBASE="${APODHOST%/}/apod/"
CACHEDIR="$HOME/.cache/apod"
NKEEP=10
MISSING_ONLY=
NO_FETCH=
QUIET=

# Parse command-line flags
while getopts mnql OPTNAME; do
    case "$OPTNAME" in
        m)
            MISSING_ONLY=1
            ;;
        n)
            NO_FETCH=1
            ;;
        q)
            QUIET=1
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[ -d "$CACHEDIR" ] || mkdir "$CACHEDIR" || exit 1
cd "$CACHEDIR"

if [ -z "$NO_FETCH" ]; then
    # Update today's APOD
    TODAYFN="ap$(date +%y%m%d).html"
    if [ -z "$MISSING_ONLY" ] || ! [ -e "$TODAYFN" ]; then
        if curl --fail --silent --show-error "$APODBASE$TODAYFN" \
                > "$TODAYFN.tmp" &&
                ( ! [ -f "$TODAYFN" ] ||
                        ! cmp -s "$TODAYFN.tmp" "$TODAYFN" >/dev/null ); then
            mv "$TODAYFN".tmp "$TODAYFN"
        else
            rm "$TODAYFN".tmp
        fi
    fi

    # Clean up old APODs
    EXPIRED="$(ls -t ap??????.html|tail -n +$((NKEEP+1)))"
    [ -n "$EXPIRED" ] && rm $EXPIRED
fi

[ -n "$QUIET" ] && exit 0

# Write feed header
# http://www.atomenabled.org/developers/syndication/
cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Better APOD (Astronomy Picture of the Day)</title>
  <id>tag:nandhp@gmail.com,2018:better-apod</id>
  <updated>$(date --utc +%Y-%m-%dT%H:%M:%SZ)</updated>
  <link rel="alternate" type="text/html"
        hreflang="en" href="${APODBASE%/}/astropix.html" />
  <icon>${APODHOST%/}/favicon.ico</icon>
EOF

# Enumerate APODs and write an entry for each one
for APODFN in $(ls -t ap??????.html); do
    APODURL="$APODBASE$APODFN"
    APODTIME=$(date --utc +%Y-%m-%dT%H:%M:%SZ -d@$(stat -c %Y "$APODFN"))
    perl - "$APODURL" "$APODFN" <<'EOF'
#!perl
use HTML::Entities qw(:DEFAULT encode_entities_numeric);
use URI;
use warnings;
use strict;

my ($url, $fn) = @ARGV;
my @mtime = gmtime((stat($fn))[9]);
my $mtime = sprintf("%d-%02d-%02dT%02d:%02d:%02dZ", $mtime[5]+1900,
                    $mtime[4]+1, $mtime[3], $mtime[2], $mtime[1], $mtime[0]);
open F, '<', $fn or die "open: $fn: $!";
my $content = join('', <F>);
my ($title) = $content =~ /<title>\s*([^<>]+?)\s*<\/title>/;
$title =~ s/APOD:\s*//;
($content) = $content =~ /<p>.*?(<p>.*?)(?:\s*<p>\s*)*<hr>/si;
$content =~ s/((?:href|src)=")([^'"]+)(")/$1 . encode_entities(URI->new(decode_entities($2))->abs($url)->as_string) . $3/gei;
my $author = 'Unknown author';
if ( $content =~ /<b>\s*(Image Credit.*?)\s*<(\/center|p|br)>/si ) {
    $author = $1;
    $author =~ s/<[^>]*>//g;
    $author =~ s/\s+/ /g;
    #$author =~ s/^[^:]*:\s*//;
    $author = encode_entities_numeric(decode_entities($author));
}
$content = encode_entities($content); # HTML in Atom is entity-encoded
close F;

print "  <entry>\n";
print "    <id>$url</id>\n";
print "    <link rel=\"alternate\" type=\"text/html\" hreflang=\"en\"\n";
print "          href=\"$url\" />\n";
print "    <updated>$mtime</updated>\n";
print "    <title>$title</title>\n";
print "    <author><name>$author</name></author>\n";
print "    <content type=\"html\">$content</content>\n";
print "  </entry>\n";
EOF
done
cat <<EOF
</feed>
EOF
# FIXME: Ping FeedBurner http://feedburner.google.com/fb/a/ping
