$(shell mkdir -p bin)

VALAC=valac
override VALAFLAGS += \
	--pkg gio-2.0 \
	--pkg linux \
	--pkg posix \
	--pkg gee-0.8 \
	-X -D_GNU_SOURCE \
	-g

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
	@sh install.sh $(DESTDIR)$(PREFIX)
