#!/usr/bin/env bash
# Put Focus Deck in ~/Applications, add an icon on the Desktop and install the CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Focus Deck.app"
TARGET_DIR="$HOME/Applications"
CLI_BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/focusdeck-cli"

if [[ ! -d "$APP" ]]; then
  echo "Build first: ./scripts/build_app.sh release"
  exit 1
fi

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_DIR/Focus Deck.app"
cp -R "$APP" "$TARGET_DIR/Focus Deck.app"

# Desktop icon. A Finder alias is nicer than a symlink (it survives the app moving),
# so try that first and say clearly when we fall back.
rm -rf "$HOME/Desktop/Focus Deck" "$HOME/Desktop/Focus Deck.app"    # drop older entries
osascript -e "tell application \"Finder\" to make new alias file at (POSIX file \"$HOME/Desktop\" as alias) to (POSIX file \"$TARGET_DIR/Focus Deck.app\" as alias) with properties {name:\"Focus Deck\"}" >/dev/null 2>&1
if [[ -e "$HOME/Desktop/Focus Deck" ]]; then
  DESKTOP="$HOME/Desktop/Focus Deck"
  ALIAS_KIND="Finder alias"
  # Give it the .app extension so Finder treats it as an application icon.
  mv "$HOME/Desktop/Focus Deck" "$HOME/Desktop/Focus Deck.app" && DESKTOP="$HOME/Desktop/Focus Deck.app"
else
  ln -sfn "$TARGET_DIR/Focus Deck.app" "$HOME/Desktop/Focus Deck.app"
  DESKTOP="$HOME/Desktop/Focus Deck.app"
  ALIAS_KIND="symbolic link (Finder alias could not be created; automation permission?)"
fi

# Command line helper for you and for other agents.
mkdir -p "$HOME/.local/bin"
cp "$CLI_BIN" "$HOME/.local/bin/focusdeck"
chmod +x "$HOME/.local/bin/focusdeck"

echo "App:    $TARGET_DIR/Focus Deck.app"
echo "Icon:   $DESKTOP  [$ALIAS_KIND]"
echo "CLI:    $HOME/.local/bin/focusdeck"
echo "Open with: open \"$TARGET_DIR/Focus Deck.app\""
