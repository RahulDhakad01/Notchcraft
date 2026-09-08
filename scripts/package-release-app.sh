#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/apple/Products/Release"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="NotchCraft"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
INFO_PLIST_PATH="$ROOT_DIR/Sources/NotchCraft/Resources/NotchCraft-Info.plist"
ICON_PATH="$ROOT_DIR/Sources/NotchCraft/Resources/AppIcon.icns"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-macOS.dmg"

detect_signing_identity() {
  if [[ -n "${NOTCHCRAFT_SIGN_IDENTITY:-}" ]]; then
    echo "$NOTCHCRAFT_SIGN_IDENTITY"
    return
  fi

  local developer_id
  developer_id="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)"/\1/p' | head -n 1)"
  if [[ -n "$developer_id" ]]; then
    echo "$developer_id"
    return
  fi
}

echo "Building $APP_NAME as a universal release app..."
swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT_DIR"

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_PATH" "$CONTENTS_DIR/Info.plist"
cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"

chmod +x "$MACOS_DIR/$APP_NAME"

SIGN_IDENTITY="$(detect_signing_identity || true)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Applying signature with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "No signing identity found. Falling back to ad-hoc signature."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Validating signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Creating zip archive..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Creating DMG archive..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

echo
echo "Done."
echo "App bundle: $APP_DIR"
echo "Zip archive: $ZIP_PATH"
echo "DMG archive: $DMG_PATH"
