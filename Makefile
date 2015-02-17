PREFIX = $(HOME)/.local
BIN = $(PREFIX)/bin
MAN = $(PREFIX)/share/man
DBUSSERVICES = $(PREFIX)/share/dbus-1/services

all: \
	nandhp-volumed.all \
	usb-mount.all
clean: \
	nandhp-volumed.clean \
	usb-mount.clean

install: \
	auto-xrandr.install \
	autorec.install \
	calc.install \
	nandhp-volumed.install \
	hires-date.install \
	toggle-wifi.install \
	wait-for-window.install \
	usb-mount.install

# usb-mount
usb-mount.all: usb-mount.1
usb-mount.install: usb-mount.all
	install usb-mount $(BIN)
	ln -f -s usb-mount $(BIN)/usb-eject
	install -m0644 usb-mount.1 $(MAN)/man1
	ln -f -s usb-mount.1 $(MAN)/man1/usb-eject.1
usb-mount.clean:
	rm -f usb-mount.1
usb-mount.1: usb-mount
	pod2man usb-mount usb-mount.1

# nandhp-volumed
nandhp-volumed.all: nandhp-volumed.service
nandhp-volumed.install: nandhp-volumed.all
	install nandhp-volumed $(BIN)
	install -m0644 nandhp-volumed.service $(DBUSSERVICES)
nandhp-volumed.clean:
	rm -f nandhp-volumed.service
nandhp-volumed.service: nandhp-volumed.service.in
	sed 's|@@BIN@@|$(BIN)|g' < $^ > $@

# Generic installation rule
%.install: %
	install $< $(BIN)
