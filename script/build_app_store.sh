#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenFree"
BUNDLE_ID="${BUNDLE_ID:-com.screenfree.app}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/AppStore/Build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Config/AppStore.entitlements"
RESOLVED_ENTITLEMENTS="$BUILD_DIR/AppStore.resolved.entitlements"
PROFILE_PLIST="$BUILD_DIR/ProvisioningProfile.plist"
OUTPUT_PKG="$BUILD_DIR/$APP_NAME.pkg"

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "error: $name is required for a Mac App Store build" >&2
    exit 2
  fi
}

require_value "APP_SIGN_IDENTITY" "$APP_SIGN_IDENTITY"
require_value "INSTALLER_SIGN_IDENTITY" "$INSTALLER_SIGN_IDENTITY"
require_value "PROVISIONING_PROFILE" "$PROVISIONING_PROFILE"

if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
  echo "error: provisioning profile not found: $PROVISIONING_PROFILE" >&2
  exit 2
fi
if ! security find-identity -p codesigning -v | grep -Fq "$APP_SIGN_IDENTITY"; then
  echo "error: app signing identity is not installed: $APP_SIGN_IDENTITY" >&2
  exit 2
fi
if ! security find-identity -p basic -v | grep -Fq "$INSTALLER_SIGN_IDENTITY"; then
  echo "error: installer signing identity is not installed: $INSTALLER_SIGN_IDENTITY" >&2
  exit 2
fi

mkdir -p "$BUILD_DIR"
security cms -D -i "$PROVISIONING_PROFILE" >"$PROFILE_PLIST"
PROFILE_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c \
  'Print :Entitlements:com.apple.application-identifier' \
  "$PROFILE_PLIST")"
PROFILE_TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c \
  'Print :Entitlements:com.apple.developer.team-identifier' \
  "$PROFILE_PLIST")"
if [[ "$PROFILE_APP_IDENTIFIER" != "$PROFILE_TEAM_IDENTIFIER.$BUNDLE_ID" ]]; then
  echo "error: profile application identifier does not match $BUNDLE_ID" >&2
  echo "profile: $PROFILE_APP_IDENTIFIER" >&2
  exit 2
fi

cp "$ENTITLEMENTS" "$RESOLVED_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c \
  "Add :com.apple.application-identifier string $PROFILE_APP_IDENTIFIER" \
  "$RESOLVED_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c \
  "Add :com.apple.developer.team-identifier string $PROFILE_TEAM_IDENTIFIER" \
  "$RESOLVED_ENTITLEMENTS"

cd "$ROOT_DIR"
swift build -c release -Xswiftc -DAPP_STORE
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$OUTPUT_PKG"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

BUILD_RESOURCE_BUNDLE="$(dirname "$BUILD_BINARY")/ScreenFree_ScreenFree.bundle"
if [[ -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  cp -R "$BUILD_RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
for LOCALIZATION_DIR in "$ROOT_DIR"/Sources/ScreenFree/Resources/*.lproj; do
  [[ -d "$LOCALIZATION_DIR" ]] && cp -R "$LOCALIZATION_DIR" "$APP_RESOURCES/"
done
cp "$ROOT_DIR/Sources/ScreenFree/Resources/ScreenFree.icns" "$APP_RESOURCES/"
cp "$ROOT_DIR/Sources/ScreenFree/Resources/PrivacyInfo.xcprivacy" "$APP_RESOURCES/"
cp "$PROVISIONING_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>ScreenFree.icns</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>ScreenFree Project</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSItemContentTypes</key>
      <array><string>com.screenfree.project</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Movie</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
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
      <key>UTTypeIdentifier</key><string>com.screenfree.project</string>
      <key>UTTypeDescription</key><string>ScreenFree Project</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array><string>screenfree</string></array>
      </dict>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSScreenCaptureUsageDescription</key><string>ScreenFree records the display, window, or area you choose.</string>
  <key>NSMicrophoneUsageDescription</key><string>ScreenFree records your voice with the screen when you enable the microphone.</string>
  <key>NSCameraUsageDescription</key><string>ScreenFree places your camera over a screen recording when you enable the camera.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>ScreenFree transcribes your recording on this Mac to create editable captions.</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" "$APP_RESOURCES/PrivacyInfo.xcprivacy" \
  "$RESOLVED_ENTITLEMENTS"
codesign --force --timestamp --options runtime --sign "$APP_SIGN_IDENTITY" \
  --entitlements "$RESOLVED_ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -dvvv --entitlements :- "$APP_BUNDLE"

productbuild --component "$APP_BUNDLE" /Applications \
  --sign "$INSTALLER_SIGN_IDENTITY" "$OUTPUT_PKG"
pkgutil --check-signature "$OUTPUT_PKG"

echo "Mac App Store package: $OUTPUT_PKG"
echo "Next: upload with Transporter, or validate with xcrun altool using App Store Connect credentials."
