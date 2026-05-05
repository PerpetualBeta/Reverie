#!/bin/bash
# Builds a distribution-ready .pkg installer that drops Reverie.saver into
# /Library/Screen Savers/ (system-wide). Single-component — no helper app,
# no productbuild distribution definition needed.
#
# Local builds are unsigned; the user has to right-click → Open the first
# time. Release Manager re-runs this with Developer ID Installer signing
# when cutting a release. RM passes its identity through the SIGN_ID env
# var if present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SAVER_BUNDLE="$PROJECT_DIR/Reverie.saver"
OUT_DIR="$PROJECT_DIR/_BuildOutput"
PKG_PATH="$OUT_DIR/Reverie.pkg"

if [ ! -d "$SAVER_BUNDLE" ]; then
    echo "ERROR: $SAVER_BUNDLE not found. Run 'make build' first."
    exit 1
fi

# Pull the marketing version straight out of the bundle so the pkg's
# version metadata always matches the .saver it carries.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$SAVER_BUNDLE/Contents/Info.plist")

mkdir -p "$OUT_DIR"
rm -f "$PKG_PATH"

PKG_ARGS=(
    --root "$SAVER_BUNDLE"
    --identifier "cc.jorviksoftware.Reverie"
    --version "$VERSION"
    --install-location "/Library/Screen Savers/Reverie.saver"
)

if [ -n "${SIGN_ID:-}" ]; then
    PKG_ARGS+=(--sign "$SIGN_ID")
    echo "==> Building signed pkg (identity: $SIGN_ID)..."
else
    echo "==> Building unsigned pkg (set SIGN_ID for Developer ID signing)..."
fi

pkgbuild "${PKG_ARGS[@]}" "$PKG_PATH"

echo ""
echo "==> Built: $PKG_PATH ($(du -h "$PKG_PATH" | cut -f1))"
echo "==> To verify: pkgutil --check-signature \"$PKG_PATH\""
echo "==> To install locally: open \"$PKG_PATH\""
