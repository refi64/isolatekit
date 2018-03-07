$(shell mkdir -p bin)

VALAC=valac
override VALAFLAGS+=--pkg gio-2.0 --pkg linux --pkg gee-0.8 -X -D_GNU_SOURCE -g

-include config.mk

export CC

DESTDIR=
PREFIX=/usr

.PHONY: all c install

all: bin/ik

bin/ik: src/*.vala
	$(VALAC) $(VALAFLAGS) -o $@ $<

c:
	rm -rf bin/*.vala
	cp src/*.vala bin
	$(VALAC) $(VALAFLAGS) -C bin/*.vala

install: bin/ik
	@\
	if touch $(DESTDIR)$(PREFIX) >/dev/null 2>&1; then \
	 set -ex; \
	 install -m 755 bin/ik $(DESTDIR)$(PREFIX)/bin/ik; \
	 install -m 755 misc/ik-update-version $(DESTDIR)$(PREFIX)/bin/ik-update-version; \
	 install -m 644 misc/isolatekit-tmpfiles.conf $(DESTDIR)$(PREFIX)/lib/tmpfiles.d; \
	else \
	 pkexec $(MAKE) -C "`pwd`" install; \
	fi
