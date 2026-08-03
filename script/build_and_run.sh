#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DontDieOnMeNow"
DISPLAY_NAME="Don't Die On Me Now"
BUNDLE_ID="com.josh.DontDieOnMeNow"
MIN_SYSTEM_VERSION="13.0"
BUILD_CONFIGURATION="release"
BUILD_ARCHITECTURES=("$(/usr/bin/uname -m)")
if [ -x "/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild" ]; then
  BUILD_ARCHITECTURES=(arm64 x86_64)
fi
BUILD_ARGUMENTS=(-c "$BUILD_CONFIGURATION")
for architecture in "${BUILD_ARCHITECTURES[@]}"; do
  BUILD_ARGUMENTS+=(--arch "$architecture")
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_PATH="$DIST_DIR/DontDieOnMeNow.icns"
VERSION_FILE="$ROOT_DIR/VERSION"

if [ ! -r "$VERSION_FILE" ]; then
  echo "Missing VERSION file: $VERSION_FILE" >&2
  exit 1
fi

APP_VERSION="$(/usr/bin/tr -d '\r\n[:space:]' < "$VERSION_FILE")"
if [ -z "$APP_VERSION" ]; then
  echo "VERSION must not be empty." >&2
  exit 1
fi
if ! [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must use semantic version format, for example 0.1.0." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build "${BUILD_ARGUMENTS[@]}"
BUILD_BINARY="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
touch "$DIST_DIR/.metadata_never_index"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/lipo "$APP_BINARY" -verify_arch "${BUILD_ARCHITECTURES[@]}"

mkdir -p "$APP_RESOURCES/script"
cp "$ROOT_DIR/uninstall.sh" "$APP_RESOURCES/uninstall.sh"
for script_name in \
  uninstall_app.sh \
  uninstall_failsafe_daemon.sh \
  uninstall_login_launcher.sh \
  uninstall_privileged_helper.sh \
  uninstall_opencode_plugin.sh; do
  cp "$ROOT_DIR/script/$script_name" "$APP_RESOURCES/script/$script_name"
done
cp "$ROOT_DIR/script/dont-die-on-me-now-opencode-plugin.js" "$APP_RESOURCES/script/dont-die-on-me-now-opencode-plugin.js"
chmod +x "$APP_RESOURCES/uninstall.sh" "$APP_RESOURCES/script"/*.sh

swift "$ROOT_DIR/script/generate_app_icon.swift" "$ICON_PATH"
cp "$ICON_PATH" "$APP_RESOURCES/DontDieOnMeNow.icns"

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
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>DontDieOnMeNow.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>Don't Die On Me Now OpenCode completion</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>dont-die-on-me-now</string>
      </array>
    </dict>
  </array>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

case "$MODE" in
  --build-only|build-only)
    echo "$APP_BUNDLE"
    ;;
  run)
    stop_running_app
    open_app
    ;;
  --debug|debug)
    stop_running_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_running_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_running_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_running_app
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    test -x "$APP_BINARY"
    plutil -lint "$INFO_PLIST" >/dev/null
    codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
