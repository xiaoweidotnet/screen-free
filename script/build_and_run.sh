#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ScreenFree"

BUILD_CONFIGURATION="debug"
case "$MODE" in
  --package|package)
    BUILD_CONFIGURATION="release"
    ;;
esac
BUNDLE_ID="com.screenfree.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
BUILD_RESOURCE_BUNDLE="$(dirname "$BUILD_BINARY")/ScreenFree_ScreenFree.bundle"
if [[ -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  cp -R "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
for LOCALIZATION_DIR in "$ROOT_DIR"/Sources/ScreenFree/Resources/*.lproj; do
  if [[ -d "$LOCALIZATION_DIR" ]]; then
    cp -R "$LOCALIZATION_DIR" "$APP_RESOURCES/"
  fi
done
if [[ -f "$ROOT_DIR/Sources/ScreenFree/Resources/ScreenFree.icns" ]]; then
  cp "$ROOT_DIR/Sources/ScreenFree/Resources/ScreenFree.icns" "$APP_RESOURCES/"
fi
if [[ -f "$ROOT_DIR/Sources/ScreenFree/Resources/PrivacyInfo.xcprivacy" ]]; then
  cp "$ROOT_DIR/Sources/ScreenFree/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>ScreenFree.icns</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>ScreenFree Project</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.screenfree.project</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Movie</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.screenfree.project</string>
      <key>UTTypeDescription</key>
      <string>ScreenFree Project</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.json</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>screenfree</string>
        </array>
      </dict>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>ScreenFree records the display or window you choose.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>ScreenFree records microphone audio when enabled.</string>
  <key>NSCameraUsageDescription</key>
  <string>ScreenFree can place your camera over a screen recording.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>ScreenFree transcribes recorded audio locally to create editable captions.</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --package|package)
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
