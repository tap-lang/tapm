PREFIX ?= /usr/local

TARGET = ./build/tap

all: $(TARGET)

$(TARGET):
	tap build

test: $(TARGET)
	./build/tapm test

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/tapm $(DESTDIR)$(PREFIX)/bin/tapm

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/tapm