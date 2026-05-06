# Reverie — meditative roulette-curve screensaver.
#
# This Makefile drives both day-to-day dev iteration AND the release
# pipeline. The release pipeline is delegated to the shared `release.mk`
# include (in PerpetualBeta/jorvik-release); the dev targets below are
# Reverie-specific and intentionally fast — no stamping, signing, or
# notarisation.

# ─── Project identity ────────────────────────────────────────────────────────
BUNDLE_NAME      := Reverie
BUNDLE_TYPE      := saver
PRODUCT_NAME     := Reverie.saver
BUNDLE_ID        := cc.jorviksoftware.Reverie
BUILD_SYSTEM     := swiftc

SWIFT_FRAMEWORKS := Cocoa ScreenSaver CoreGraphics
SWIFT_SOURCES    := ReverieView.swift \
                    ReverieEngine.swift \
                    Hypotrochoid.swift \
                    Palettes.swift \
                    Pulsation.swift

PACKAGE_TYPE     := pkg
ALSO_SHIP_PKG    := false

# Release.mk lives in a sibling repo (PerpetualBeta/jorvik-release). The
# relative path resolves correctly from any project under
# ~/Desktop/Jorvik Software/. We cannot use an env-var override because the
# absolute path contains a space — and Make's `include` treats whitespace
# as a path-list separator, so an unescaped space splits the include into
# multiple non-existent paths. RM-driven builds run with cwd = sourcePath,
# so the relative path works there too.
include ../jorvik-release/release.mk

# Override release.mk's default goal: a bare `make` should build a fast
# local saver, not run a full release pipeline.
.DEFAULT_GOAL := dev-build

# ─── Dev iteration targets (Reverie-specific, not part of release.mk) ────────
# These are *separate* from the `release.mk` pipeline. They build a fast,
# ad-hoc-signed bundle for installing into ~/Library/Screen Savers/ during
# development, and a plain NSWindow harness for visual iteration of the
# engine without touching the screensaver host.

.PHONY: dev-build dev-install testapp run icon

LOCAL_BUNDLE := Reverie.saver
LOCAL_INSTALL_DIR := $(HOME)/Library/Screen Savers

# Test app — same engine sources plus the NSWindow harness in TestApp/.
TESTAPP_SOURCES := TestApp/main.swift \
                   ReverieEngine.swift \
                   Hypotrochoid.swift \
                   Palettes.swift \
                   Pulsation.swift

# Single-arch fast build for local install. Bypasses release.mk's universal
# binary + version stamping for speed.
dev-build:
	@echo "→ dev build (arm64 only, ad-hoc)"
	@mkdir -p $(LOCAL_BUNDLE)/Contents/MacOS $(LOCAL_BUNDLE)/Contents/Resources
	swiftc -O -target arm64-apple-macos14.0 -sdk $(SDK) \
		-framework Cocoa -framework ScreenSaver -framework CoreGraphics \
		-emit-library -module-name $(BUNDLE_NAME) \
		-o $(LOCAL_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME) \
		$(SWIFT_SOURCES)
	cp Info.plist $(LOCAL_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(LOCAL_BUNDLE)/Contents/Resources/AppIcon.icns; \
	fi
	codesign --force --sign - $(LOCAL_BUNDLE)
	@echo "→ Done: $(LOCAL_BUNDLE)"

dev-install: dev-build
	@echo "→ Installing to $(LOCAL_INSTALL_DIR)..."
	@mkdir -p "$(LOCAL_INSTALL_DIR)"
	rm -rf "$(LOCAL_INSTALL_DIR)/$(LOCAL_BUNDLE)"
	cp -R $(LOCAL_BUNDLE) "$(LOCAL_INSTALL_DIR)/$(LOCAL_BUNDLE)"
	-killall ScreenSaverEngine 2>/dev/null || true
	-killall legacyScreenSaver 2>/dev/null || true
	@echo "→ Installed. Open System Settings → Screen Saver to activate."

testapp:
	@echo "→ Building test app..."
	swiftc -target arm64-apple-macos14.0 -sdk $(SDK) \
		-framework Cocoa -framework CoreGraphics \
		-module-name ReverieTest -Onone \
		$(TESTAPP_SOURCES) -o ReverieTest
	@echo "→ Done: ReverieTest"

run: testapp
	./ReverieTest

icon:
	@echo "→ Generating icon..."
	swift generate_icon.swift
