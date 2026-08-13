#!/usr/bin/env bash
set -euo pipefail

# Package dist/ScreenFree.app into an installable DMG with an Applications shortcut.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/ScreenFree.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: $APP_BUNDLE not found, run ./script/build_and_run.sh --package first" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST")"
STAGING_DIR="$(mktemp -d)"
DMG_PATH="$DIST_DIR/ScreenFree-$VERSION.dmg"

trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "ScreenFree" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
