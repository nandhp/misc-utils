#!/usr/bin/env python2
#
# Extract list of sites from a KeepassX CSV export. Output is
# formatted for grepping in a list of domains. Written for Cloudbleed.
#
# This script makes some assumptions on how your Title and URL fields
# are filled out, but if one or both is a URL or hostname, it should
# work for you.
#
# Usage:
#   # Use KeepassX to create a CSV export /tmp/kpx.csv
#   wget -O ~/Downloads/sites-using-cloudflare.zip https://github.com/pirate/sites-using-cloudflare/archive/master.zip
#   python keepassx_domains.py < /tmp/kpx.csv > /tmp/kpx.sites
#   unzip -c ~/Downloads/sites-using-cloudflare.zip sites-using-cloudflare-master/sorted_unique_cf.txt | grep -f /tmp/kpx.sites

import csv
import urlparse
import sys, os

# Per http://stackoverflow.com/questions/2850893/reading-binary-data-from-stdin
# Because csv apparently wants binary data
sys.stdin = os.fdopen(sys.stdin.fileno(), 'rb', 0)
mycsv = csv.DictReader(sys.stdin)

sites = {}
for data in mycsv:
    isites = set()
    warnings = set()
    for d in data['Title'], data['URL']:
        if not d: continue

        # Auto-generated passwords from LastPass that were never renamed
        if d.lower().startswith('generated password for '):
            d = d[len('generated password for '):]
        #if 'sample entry' in d.lower() or d.lower().startswith('sample '):
        #    continue

        # Parenthetical comments trailing the domain name
        if '(' in d:
            d = d[0:d.find('(')].strip()

        # Strip URL components, keep hostname only
        if '://' in d:
            d = urlparse.urlparse(d).netloc
        elif '/' in d:
            d = d[0:d.find('/')].strip()
        if ':' in d:
            d = d[0:d.rfind(':')].strip()
        if not d: continue

        # Skip private IP addresses
        if d.startswith('192.') or d.startswith('10.'):
            warnings.add("Skipping private IP address '%s'" % (d,))
            continue

        # Handle '<realm> <hostname>' entries
        if ' ' in d:
            lw = d[d.rfind(' ')+1:]
            if not d.endswith('.') and '.' in lw:
                warnings.add("Taking last word from name '%s'" % (d,))
                d = lw
            else:
                warnings.add("Not parsing name '%s'" % (d,))
                continue

        c = d.strip().split('.')

        # Better handling of ccTLDs
        tldsize = 1
        if len(c[-1]) == 2 and c[-2] in ('co', 'com'):
            tldsize = 2

        for i in range(len(c)-tldsize):
            s = '.'.join(c[i:])
            isites.add(s)

    if warnings:
        sys.stderr.write('%d warnings, found %d domains\n  %s\n' %
                         (len(warnings), len(isites), '\n  '.join(warnings)))
    for s in isites:
        if s not in sites:
            sites[s] = []
        sites[s].append(data['Username'])

for site, usernames in sorted(sites.items(), key=lambda x: '.'.join(reversed(x[0].split('.')))):
    print '\\(^\\|\\.\\)%s$' % (site,)
    #print "%s\t%s" % (site, ' '.join(usernames))
