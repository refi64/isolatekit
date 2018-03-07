$(shell mkdir -p bin)

VALAC=valac
VALAFLAGS+=--pkg gio-2.0 --pkg linux --pkg gee-0.8 -X -D_GNU_SOURCE -g
CC=clang

export CC

DESTDIR=
PREFIX=/usr

.PHONY: all c install install-tmpfiles

all: bin/ik

bin/ik: src/*.vala
	$(VALAC) $(VALAFLAGS) -o $@ $<

c:
	rm -rf bin/*.vala; cp src/*.vala bin; $(VALAC) $(VALAFLAGS) -C bin/*.vala

install: bin/ik install-tmpfiles

install-tmpfiles:
	install -m 644 misc/isolatekit-tmpfiles.conf $(DESTDIR)/$(PREFIX)/lib/tmpfiles.d
