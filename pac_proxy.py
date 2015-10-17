#!/usr/bin/python

"""pac_proxy - HTTP proxy that forwards requests as directed by a PAC file
               (proxy auto-configuration)."""

from twisted.internet import protocol, reactor
import pacparser
import urlparse
import urllib
import sys
import os.path
import time
import re
import hashlib
import argparse

DEFAULT_PORTS = { 'http': ':80', 'https': ':443' }

class PacManager(object):
    """Manage download of and lookup of URLs in PAC file."""
    def __init__(self, pacurl, interval=60):
        self.updatetime = None
        self.pacurl = pacurl
        self.interval = interval
        # Cache PAC file in XDG_CACHE_HOME (~/.cache)
        cachedir = os.environ.get('XDG_CACHE_HOME',
                                  os.path.expanduser('~/.cache'))
        cachedir = os.path.join(cachedir, 'pac_proxy')
        if not os.path.isdir(cachedir):
            os.makedirs(cachedir, 0700)
        # Create cache filename
        urlhash = hashlib.md5()
        urlhash.update(pacurl)
        self.pacfile = os.path.join(cachedir, urlhash.hexdigest() + '.pac')
        # Initial update of PAC file
        self.update_pacfile()

    def find_proxy_for_url(self, url):
        """Ask the PAC file for the proxy to use for the given URL."""
        self.update_pacfile()
        proxies = pacparser.just_find_proxy(self.pacfile, url)
        if proxies:
            for proxy in proxies.split(";"):
                proxy = proxy.strip()
                if proxy[0:6].upper() == 'DIRECT':
                    return None
                if proxy[0:5].upper() == 'PROXY':
                    return proxy[6:].strip()
        sys.stderr.write('No proxy offered for %s\n' % (url,))
        return None

    def update_pacfile(self):
        """Update the PAC file, if necessary."""
        try:
            exptime = 60*self.interval
            if abs(os.path.getmtime(self.pacfile)-time.time()) < exptime:
                return
        except os.error:
            pass
        try:
            print "Updating PAC file %s" % (self.pacurl,)
            response = urllib.urlopen(self.pacurl)
            with open(self.pacfile, 'w') as fh:
                fh.write(response.read())
        except Exception as exc:
            sys.stderr.write('Could not download PAC file %s\n' %
                             (self.pacurl,))
            sys.stderr.write(str(exc) + '\n')

class DummyPacManager(object):
    def __init__(self, pacurl=None, interval=None):
        pass

    def find_proxy_for_url(self, url):
        return None

REQUEST_MATCH = re.compile(r'([^\r\n]*).*?\r?\n\r?\n', re.DOTALL)

class ServerProtocol(protocol.Protocol):
    """Protocol for communicating with proxy client."""

    def __init__(self):
        self.buffer = ''
        self.client = None
        self.negotiating = True
        self.greeting = ''

    def connectionLost(self, reason):
        """Handle loss of connection to remote server."""
        msg = reason.getErrorMessage()
        if msg != "Connection was closed cleanly.":
            print "Connection closed:", msg
        if self.client:
            self.client.transport.loseConnection()

    def beginRelay(self, host, port):
        """Establish a client connection to remote host and relay traffic."""
        self.negotiating = False
        factory = protocol.ClientFactory.forProtocol(ClientProtocol)
        factory.server = self
        #print "Relaying to %s on port %d" % ( host, port )
        reactor.connectTCP(host, port, factory)

    def verify_dest(self, dest):
        host = dest[1] if ':' in dest[1] else dest[1] + DEFAULT_PORTS[dest[0]]
        host, port = host.split(':')
        port = int(port, 10)
        if port == self.factory.listenport:
            # FIXME: Check hostname? Return "it works" message?
            return (None, None)
        return (host, port)

    def dataReceived(self, data):
        """Handle data received from proxy client."""
        if self.negotiating:
            self.buffer += data
            # Check if buffer represents a completed HTTP request
            match = REQUEST_MATCH.match(self.buffer)
            if match:
                self.negotiating = False

                if self.factory.verbose:
                    print match.group(0)

                # Parse the request to determine the correct proxy to use
                request = match.group(1).split()
                request[0] = request[0].upper()
                if '//' not in request[1]:
                    request[1] = '//' + request[1]

                # Parse HTTP headers for remote URL and Host
                dest = list(urlparse.urlsplit(request[1], 'http'))
                for header in match.group(0).split('\n'):
                    if header.startswith('Host: '):
                        host = header[6:].strip()
                        if any(self.verify_dest((dest[0], host))):
                            dest[1] = host # Update hostname
                        break

                # Insert default port
                for proto, port in DEFAULT_PORTS.iteritems():
                    if dest[0] == proto and dest[1].endswith(port):
                        dest[1] = dest[1][:-len(port)] # Update hostname

                # Determine proxy for request
                url = urlparse.urlunsplit(dest)
                proxy = self.factory.pacmgr.find_proxy_for_url(url)
                if proxy:
                    # Forward request to upstream proxy
                    dest = urlparse.urlsplit('//' + proxy, 'http')
                elif request[0] == 'CONNECT':
                    # Remove request from buffer, since there is
                    # no upstream HTTP server/proxy to receive it
                    self.buffer = self.buffer[len(match.group(0)):]
                    self.greeting = "HTTP/1.0 200 OK\r\n\r\n"
                else:
                    # Sending request directly to target server.
                    # Remove protocol and host from request URI.
                    self.buffer = self.buffer[len(match.group(1)):]
                    request[1] = urlparse.urlunsplit(['', ''] + dest[2:])
                    self.buffer = ' '.join(request) + self.buffer

                # Create relay connection
                host, port = self.verify_dest(dest)
                if host is None:
                    raise Exception('Port banned to avoid loopback: %d' %
                                    (port,))
                print "%s: Using %s:%d" % (url, host, port)
                self.beginRelay(host, port)

            # HTTP request not yet complete, keep reading
            elif len(self.buffer) > 10*1024:
                raise Exception('Request too long')

        elif self.client:       # Relay connection open
            self.client.write(data)

        else:         # Done negotiating, waiting for relay connection
            self.buffer += data

    def write(self, data):
        """Transport data to proxy client."""
        self.transport.write(data)

# Adapted from http://www.mostthingsweb.com/2013/08/a-basic-man-in-the-middle-proxy-with-twisted/
class ClientProtocol(protocol.Protocol):
    """Protocol for communicating with remote server."""

    def connectionMade(self):
        """Connection established, send pending data to each end."""
        self.factory.server.client = self
        self.write(self.factory.server.buffer)
        self.factory.server.buffer = ''
        # Write header (e.g. HTTP/1.0 200 OK\n\n) to proxy client.
        # FIXME: What if connection not successfully established?
        self.factory.server.write(self.factory.server.greeting)
        self.factory.server.greeting = ''

    def connectionLost(self, reason):
        """Handle loss of connection to remote server."""
        msg = reason.getErrorMessage()
        if msg != "Connection was closed cleanly.":
            print "Connection closed:", msg
        self.factory.server.transport.loseConnection()

    def dataReceived(self, data):
        """Transport data from remote server to proxy client."""
        self.factory.server.write(data)

    def write(self, data):
        """Transport data from proxy client to remote server."""
        if data:
            self.transport.write(data)

def main():
    """Main entry point."""
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='HTTP proxy that forwards requests using PAC file')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')
    parser.add_argument('-p', '--port', type=int, default=5043,
                        help='Port number to listen on')
    parser.add_argument('pacfile', type=str,
                        help='URL of PAC file')
    args = parser.parse_args()

    # Create factory for the proxy server
    factory = protocol.ServerFactory.forProtocol(ServerProtocol)

    # Create PAC Manager for given PAC file
    factory.pacmgr = PacManager(args.pacfile) if args.pacfile else DummyPacManager()
    factory.verbose = args.verbose

    # Listen for HTTP connections
    factory.listenport = args.port
    print 'Listening on port %d' % (args.port,)
    reactor.listenTCP(args.port, factory, interface="127.0.0.1")
    reactor.run()

if __name__ == '__main__':
    main()
