APP_NAME := hei
BUILD := build
APP := $(BUILD)/$(APP_NAME).app
BIN := $(APP)/Contents/MacOS/$(APP_NAME)
ICON := $(BUILD)/AppIcon.icns
ICONSET := $(BUILD)/AppIcon.iconset
SOURCES := $(wildcard Sources/*.swift)
MODCACHE := $(BUILD)/modulecache
ARCH := $(shell uname -m)
TARGET := $(ARCH)-apple-macos13.0

.PHONY: all build run selftest dump mock clean

all: build

build: $(BIN)

$(ICON): Resources/icon-source.png
	@rm -rf $(ICONSET)
	@mkdir -p $(ICONSET)
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $< --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) $< --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	@iconutil -c icns $(ICONSET) -o $@

$(BIN): $(SOURCES) Sources/Info.plist $(ICON)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(MODCACHE)
	swiftc -O -swift-version 5 -target $(TARGET) \
		-module-cache-path $(MODCACHE) \
		-framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement \
		-o $(BIN) $(SOURCES)
	@cp Sources/Info.plist $(APP)/Contents/Info.plist
	@cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	@codesign --force --sign - --timestamp=none $(APP)
	@echo "built $(APP)"

run: build
	@open $(APP)

selftest: build
	@$(BIN) --selftest

dump: build
	@$(BIN) --dump

mock: build
	@$(BIN) --demo --mock --quiet

clean:
	rm -rf $(BUILD)
