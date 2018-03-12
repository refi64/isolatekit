$(shell mkdir -p bin man/out man/html)

VALAC=valac
override VALAFLAGS += \
	--pkg gio-2.0 \
	--pkg linux \
	--pkg posix \
	--pkg gee-0.8 \
	-X -D_GNU_SOURCE \
	-g

MRKD=mrkd

DESTDIR=
PREFIX=/usr

-include config.mk

export CC

override MAN=$(patsubst man/%.md,man/out/%,$(wildcard man/*.md))
override HTML=$(patsubst man/%.md,man/html/%.html,$(wildcard man/*.md))

.PHONY: all c clean install man

all: bin/ik

bin/ik: src/*.vala
	$(VALAC) $(VALAFLAGS) -o $@ $<

c:
	rm -rf bin/*.vala
	cp src/*.vala bin
	$(VALAC) $(VALAFLAGS) -C bin/*.vala

man: $(MAN)
html: $(HTML)

$(MAN): man/out/%: man/%.md
	$(MRKD) -index man/index.ini $^ $@

$(HTML): man/html/%.html: man/%.md
	$(MRKD) -index man/index.ini -format html $^ $@

clean:
	rm -rf bin man/out man/html

install: bin/ik
	@sh install.sh $(DESTDIR)$(PREFIX)
