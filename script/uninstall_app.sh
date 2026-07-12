#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="Don't Die On Me Now"
APP_PROCESS_NAME="DontDieOnMeNow"
BUNDLE_ID="com.josh.DontDieOnMeNow"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CUSTOM_INSTALL_DIR=""
KEEP_SETTINGS=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
DESKTOP_DIR="${DDONMN_DESKTOP_DIR:-$HOME/Desktop}"
DESKTOP_SHORTCUT="$DESKTOP_DIR/$APP_DISPLAY_NAME.app"

usage() {
  cat <<USAGE
Usage: ./uninstall.sh [options]

Stops awake mode, removes the helper and login launcher, and deletes the app.

Options:
  --install-dir X  Also remove the app from a custom Applications directory.
  --keep-settings  Keep the user's saved duration and Application Support files.
  -h, --help       Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir)
      if [ "$#" -lt 2 ]; then
        echo "--install-dir needs a path." >&2
        exit 2
      fi
      CUSTOM_INSTALL_DIR="$2"
      shift
      ;;
    --keep-settings)
      KEEP_SETTINGS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -n "$CUSTOM_INSTALL_DIR" ]; then
  case "$CUSTOM_INSTALL_DIR" in
    /*) ;;
    *)
      echo "Install directory must be an absolute path: $CUSTOM_INSTALL_DIR" >&2
      exit 2
      ;;
  esac
fi

APP_PATHS=(
  "$HOME/Applications/$APP_DISPLAY_NAME.app"
  "/Applications/$APP_DISPLAY_NAME.app"
)
if [ -n "$CUSTOM_INSTALL_DIR" ]; then
  APP_PATHS+=("$CUSTOM_INSTALL_DIR/$APP_DISPLAY_NAME.app")
fi

"$ROOT_DIR/script/uninstall_login_launcher.sh"
"$ROOT_DIR/script/uninstall_privileged_helper.sh"
/usr/bin/pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true

if [ -L "$DESKTOP_SHORTCUT" ]; then
  desktop_target="$(/usr/bin/readlink "$DESKTOP_SHORTCUT" 2>/dev/null || true)"
  case "$desktop_target" in
    */"$APP_DISPLAY_NAME.app")
      /bin/rm -f "$DESKTOP_SHORTCUT"
      echo "Removed: $DESKTOP_SHORTCUT"
      ;;
  esac
elif [ -d "$DESKTOP_SHORTCUT" ]; then
  desktop_bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$DESKTOP_SHORTCUT/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$desktop_bundle_id" = "$BUNDLE_ID" ]; then
    /bin/rm -rf "$DESKTOP_SHORTCUT"
    echo "Removed: $DESKTOP_SHORTCUT"
  fi
fi

# Older builds installed a global failsafe daemon; current builds use per-session restore jobs.
if [ -e "/Library/LaunchDaemons/com.josh.DontDieOnMeNow.failsafe.plist" ] \
  || [ -e "/Library/Application Support/DontDieOnMeNow/failsafe_check.sh" ]; then
  "$ROOT_DIR/script/uninstall_failsafe_daemon.sh"
fi

for app_path in "${APP_PATHS[@]}"; do
  if [ ! -e "$app_path" ]; then
    continue
  fi

  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  fi

  case "$app_path" in
    /Applications/*)
      /usr/bin/sudo /bin/rm -rf "$app_path"
      ;;
    *)
      /bin/rm -rf "$app_path"
      ;;
  esac
  echo "Removed: $app_path"
done

if [ "$KEEP_SETTINGS" -eq 0 ]; then
  /bin/rm -rf "$HOME/Library/Application Support/DontDieOnMeNow"
  /usr/bin/defaults delete com.josh.DontDieOnMeNow >/dev/null 2>&1 || true
fi

/usr/bin/sudo /bin/rmdir "/Library/Application Support/DontDieOnMeNow" >/dev/null 2>&1 || true

echo "Uninstall complete. Normal sleep is on."
