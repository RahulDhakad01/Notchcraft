#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/apple/Products/Release"
DIST_DIR="${NOTCHCRAFT_DIST_DIR:-$ROOT_DIR/dist}"
ENTITLEMENTS_PATH="$ROOT_DIR/scripts/NotchCraft.entitlements"
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
if swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT_DIR"; then
  :
else
  # A universal build needs full Xcode. With only the Command Line Tools, build each
  # architecture on its own and join them with lipo.
  echo "Universal build unavailable; building each architecture and joining them with lipo..."
  LIPO_DIR="$ROOT_DIR/.build/lipo-release"
  rm -rf "$LIPO_DIR"
  mkdir -p "$LIPO_DIR"
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path "$ROOT_DIR/.build/release-$arch" --package-path "$ROOT_DIR"
  done
  lipo -create \
    "$ROOT_DIR/.build/release-arm64/arm64-apple-macosx/release/$APP_NAME" \
    "$ROOT_DIR/.build/release-x86_64/x86_64-apple-macosx/release/$APP_NAME" \
    -output "$LIPO_DIR/$APP_NAME"
  EXECUTABLE_PATH="$LIPO_DIR/$APP_NAME"
  RESOURCE_BUNDLE_PATH="$ROOT_DIR/.build/release-arm64/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
fi
lipo -info "$EXECUTABLE_PATH"

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
  codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "No signing identity found. Falling back to ad-hoc signature."
  codesign --force --deep --entitlements "$ENTITLEMENTS_PATH" --sign - "$APP_DIR"
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
