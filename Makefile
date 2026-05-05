BUNDLE_NAME    = Reverie
SAVER_NAME     = $(BUNDLE_NAME).saver
INSTALL_DIR    = $(HOME)/Library/Screen\ Savers

ARCH           = arm64
MIN_MACOS      = 14.0
SDK            = $(shell xcrun --sdk macosx --show-sdk-path)
SWIFT          = swiftc

# Saver sources — every .swift in Sources/ except the TestApp harness.
SAVER_SOURCES  = Sources/ReverieView.swift \
                 Sources/ReverieEngine.swift \
                 Sources/Hypotrochoid.swift \
                 Sources/Palettes.swift \
                 Sources/Pulsation.swift

# Test app — same engine, plain NSWindow harness, no ScreenSaver framework.
TESTAPP_SOURCES = Sources/TestApp/main.swift \
                  Sources/ReverieEngine.swift \
                  Sources/Hypotrochoid.swift \
                  Sources/Palettes.swift \
                  Sources/Pulsation.swift

SWIFT_FLAGS    = \
    -target $(ARCH)-apple-macos$(MIN_MACOS) \
    -sdk $(SDK) \
    -framework Cocoa \
    -framework ScreenSaver \
    -framework CoreGraphics \
    -emit-library \
    -module-name $(BUNDLE_NAME) \
    -O

TESTAPP_FLAGS  = \
    -target $(ARCH)-apple-macos$(MIN_MACOS) \
    -sdk $(SDK) \
    -framework Cocoa \
    -framework CoreGraphics \
    -module-name ReverieTest \
    -Onone

BUNDLE_MACOS   = $(SAVER_NAME)/Contents/MacOS
BUNDLE_RES     = $(SAVER_NAME)/Contents/Resources

.PHONY: build install clean testapp run icon pkg

build: $(SAVER_NAME)

$(SAVER_NAME): $(SAVER_SOURCES) Info.plist
	@echo "→ Compiling saver..."
	@mkdir -p $(BUNDLE_MACOS) $(BUNDLE_RES)
	$(SWIFT) $(SWIFT_FLAGS) $(SAVER_SOURCES) -o $(BUNDLE_MACOS)/$(BUNDLE_NAME)
	@echo "→ Copying Info.plist..."
	cp Info.plist $(SAVER_NAME)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		echo "→ Copying icon..."; \
		cp Resources/AppIcon.icns $(BUNDLE_RES)/AppIcon.icns; \
	fi
	@echo "→ Done: $(SAVER_NAME)"

install: build
	@echo "→ Ad-hoc signing..."
	xattr -cr $(SAVER_NAME)
	find $(SAVER_NAME) -name "._*" -delete 2>/dev/null || true
	codesign --force --sign - $(SAVER_NAME)
	@echo "→ Installing to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(SAVER_NAME)
	cp -R $(SAVER_NAME) $(INSTALL_DIR)/$(SAVER_NAME)
	@echo "→ Restarting screensaver host..."
	-killall ScreenSaverEngine 2>/dev/null || true
	-killall legacyScreenSaver 2>/dev/null || true
	@echo "→ Installed. Open System Settings → Screen Saver to activate."

testapp: $(TESTAPP_SOURCES)
	@echo "→ Building test app..."
	$(SWIFT) $(TESTAPP_FLAGS) $(TESTAPP_SOURCES) -o ReverieTest
	@echo "→ Done: ReverieTest"

run: testapp
	./ReverieTest

icon:
	@echo "→ Generating icon..."
	swift generate_icon.swift

pkg: build
	@echo "→ Building installer pkg..."
	bash Installer/build_pkg.sh

clean:
	rm -rf $(SAVER_NAME) ReverieTest Resources/Reverie.iconset _BuildOutput
