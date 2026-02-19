#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Lethe}"
APP_EXECUTABLE="${APP_EXECUTABLE:-LetheApp}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.lethe.app}"
VERSION="${VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
DMG_ROOT="$OUT_DIR/dmg-root"
DMG_PATH="$OUT_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building release binary"
cd "$ROOT_DIR"
swift build -c release --product "$APP_EXECUTABLE"

RELEASE_BIN="$ROOT_DIR/.build/release/$APP_EXECUTABLE"
if [[ ! -x "$RELEASE_BIN" ]]; then
  RELEASE_BIN="$ROOT_DIR/.build/apple/Products/Release/$APP_EXECUTABLE"
fi

if [[ ! -x "$RELEASE_BIN" ]]; then
  echo "error: release binary not found for $APP_EXECUTABLE" >&2
  exit 1
fi

echo "==> Preparing app bundle"
rm -rf "$APP_BUNDLE" "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${APP_BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Codesigning app bundle (identity: $SIGN_IDENTITY)"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "==> Building DMG"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null

echo
echo "Done."
echo "App: $APP_BUNDLE"
echo "DMG: $DMG_PATH"
