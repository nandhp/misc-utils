PREFIX = $(HOME)/.local
BIN = $(PREFIX)/bin
MAN = $(PREFIX)/share/man

all: usb-mount.1

install: auto-xrandr.install calc.install hires-date.install usb-mount.install

# usb-mount
usb-mount.install:
	install usb-mount $(BIN)
	ln -f -s usb-mount $(BIN)/usb-eject
	install -m0644 usb-mount.1 $(MAN)/man1
	ln -f -s usb-mount.1 $(MAN)/man1/usb-eject.1
usb-mount.1: usb-mount
	pod2man usb-mount usb-mount.1

# Generic installation rule
%.install: %
	install $< $(BIN)
