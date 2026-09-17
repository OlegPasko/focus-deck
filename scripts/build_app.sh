#!/usr/bin/env bash
# Build Focus Deck and assemble a real macOS .app bundle.
# Usage: ./scripts/build_app.sh [debug|release] [native|universal]
set -euo pipefail

CONFIG="${1:-release}"
ARCHITECTURES="${2:-native}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="FocusDeck"
BUNDLE="$ROOT/dist/Focus Deck.app"
ICON="$ROOT/assets/AppIcon.icns"

VERSION="$(cat "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must contain a semantic version, for example 1.2.0" >&2
  exit 1
fi

build_products() {
  swift build -c "$CONFIG" "$@" --product FocusDeck
  swift build -c "$CONFIG" "$@" --product focusdeck-cli
}

echo "==> building ($CONFIG, $ARCHITECTURES)"
case "$ARCHITECTURES" in
  native)
    build_products
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
    ;;
  universal)
    build_products --triple arm64-apple-macosx13.0
    ARM_BIN="$(swift build -c "$CONFIG" --triple arm64-apple-macosx13.0 --show-bin-path)"
    build_products --triple x86_64-apple-macosx13.0
    INTEL_BIN="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx13.0 --show-bin-path)"
    BIN_DIR="$ROOT/.build/universal/$CONFIG"
    mkdir -p "$BIN_DIR"
    for product in FocusDeck focusdeck-cli; do
      lipo -create "$ARM_BIN/$product" "$INTEL_BIN/$product" -output "$BIN_DIR/$product"
      lipo "$BIN_DIR/$product" -verify_arch arm64 x86_64
    done
    rm -rf "$BIN_DIR/FocusDeck_FocusDeck.bundle"
    cp -R "$ARM_BIN/FocusDeck_FocusDeck.bundle" "$BIN_DIR/FocusDeck_FocusDeck.bundle"
    ;;
  *) echo "Unknown architecture mode: $ARCHITECTURES" >&2; exit 1 ;;
esac

echo "==> assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/FocusDeck" "$BUNDLE/Contents/MacOS/FocusDeck"
# Package artwork with the installed app, independent of the build directory.
cp -R "$BIN_DIR/FocusDeck_FocusDeck.bundle" "$BUNDLE/Contents/Resources/"
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Focus Deck</string>
    <key>CFBundleDisplayName</key>       <string>Focus Deck</string>
    <key>CFBundleExecutable</key>        <string>FocusDeck</string>
    <key>CFBundleIdentifier</key>        <string>com.focusdeck.app</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Focus Deck shows the current Spotify track and controls Spotify playback.</string>
    <key>NSCalendarsUsageDescription</key><string>Focus Deck reads your selected calendars to show a quiet countdown before your next meeting. It does not change your events.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Focus Deck reads your selected calendars to show a quiet countdown before your next meeting. It does not change your events.</string>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
</dict>
</plist>
PLIST

# Keep certificate selection local to this checkout or its environment.
# New clones use ad-hoc signing until a developer configures their own identity.
SIGNING_IDENTITY="${FOCUSDECK_SIGNING_IDENTITY:-$(git config --local focusdeck.signingIdentity 2>/dev/null || true)}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
echo "==> signing"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

echo "==> done: $BUNDLE"
