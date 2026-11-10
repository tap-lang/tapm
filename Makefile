PREFIX ?= /usr/local

# `tap build` 在包模式下把产物写到 <包根>/build/<包名>，Windows 上带 .exe。
EXE :=
ifeq ($(OS),Windows_NT)
    EXE = .exe
endif

TARGET = ./build/tapm$(EXE)

all: $(TARGET)

$(TARGET):
	tap build

test: $(TARGET)
	$(TARGET) test

install: $(TARGET)
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/tapm$(EXE) $(DESTDIR)$(PREFIX)/bin/tapm$(EXE)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/tapm$(EXE)

# 清理生成的文件
clean:
	rm -rf ./build
