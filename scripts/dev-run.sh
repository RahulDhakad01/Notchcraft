#!/bin/zsh
# Quick dev loop: rebuild (debug) and relaunch NotchCraft from this checkout.
#
# The debug build is wrapped in a real, signed .app bundle and opened through Launch Services.
# macOS only shows Calendar / Automation permission prompts for a real app with its own
# Info.plist (a bare binary borrows its parent's identity, so the prompt never appears), and a
# stable signature keeps those permissions across rebuilds.
#
# Only stops a previous dev instance started from .build/, never your installed
# /Applications/NotchCraft.app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build

BIN_DIR="$(swift build --show-bin-path)"
APP_NAME="NotchCraft"
APP_DIR="$ROOT_DIR/.build/dev/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"

pkill -f "$ROOT_DIR/.build/.*/NotchCraft" 2>/dev/null || true
sleep 0.3

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS_DIR/MacOS/$APP_NAME"
cp "$ROOT_DIR/Sources/NotchCraft/Resources/NotchCraft-Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/NotchCraft/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
if [[ -d "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" ]]; then
  cp -R "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" "$CONTENTS_DIR/Resources/"
fi

# A real certificate keeps the app's identity (and its permissions) the same on every rebuild.
SIGN_IDENTITY="${NOTCHCRAFT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -n 1)}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Launching $APP_DIR"
open -n "$APP_DIR"
