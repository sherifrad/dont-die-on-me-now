#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="Don't Die On Me Now"
APP_PROCESS_NAME="DontDieOnMeNow"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_AT_LOGIN=1
INSTALL_HELPER=0
LAUNCH_APP=1
USE_SUDO_FOR_COPY=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  cat <<USAGE
Usage: ./script/install_app.sh [options]

Builds, installs, registers, and launches $APP_DISPLAY_NAME.

Options:
  --at-login       Open the menu bar app automatically when you log in.
  --no-at-login    Do not install the login launcher.
  --helper         Install the optional privileged helper for fewer password prompts.
  --system         Install to /Applications instead of ~/Applications.
  --install-dir X  Install to a custom Applications directory.
  --no-launch      Install but do not launch the app.
  -h, --help       Show this help.

Default:
  ./script/install_app.sh
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --at-login)
      INSTALL_AT_LOGIN=1
      ;;
    --no-at-login)
      INSTALL_AT_LOGIN=0
      ;;
    --helper)
      INSTALL_HELPER=1
      ;;
    --system)
      INSTALL_DIR="/Applications"
      USE_SUDO_FOR_COPY=1
      ;;
    --install-dir)
      if [ "$#" -lt 2 ]; then
        echo "--install-dir needs a path." >&2
        exit 2
      fi
      INSTALL_DIR="$2"
      shift
      ;;
    --no-launch)
      LAUNCH_APP=0
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

APP_PATH="$INSTALL_DIR/$APP_DISPLAY_NAME.app"

copy_app() {
  if [ "$USE_SUDO_FOR_COPY" -eq 1 ] || { [ -e "$INSTALL_DIR" ] && [ ! -w "$INSTALL_DIR" ]; }; then
    /usr/bin/sudo /bin/mkdir -p "$INSTALL_DIR"
    /usr/bin/sudo /bin/rm -rf "$APP_PATH"
    /usr/bin/sudo /usr/bin/ditto "$DIST_APP" "$APP_PATH"
    /usr/bin/sudo /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
  else
    /bin/mkdir -p "$INSTALL_DIR"
    /bin/rm -rf "$APP_PATH"
    /usr/bin/ditto "$DIST_APP" "$APP_PATH"
    /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
  fi
}

register_app() {
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
  fi

  /usr/bin/mdimport "$APP_PATH" >/dev/null 2>&1 || true
}

cd "$ROOT_DIR"
./script/build_and_run.sh --build-only >/dev/null
copy_app
/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null
register_app

if [ "$INSTALL_AT_LOGIN" -eq 1 ]; then
  ./script/install_login_launcher.sh "$APP_PATH"
fi

if [ "$INSTALL_HELPER" -eq 1 ]; then
  ./script/install_privileged_helper.sh
fi

if [ "$LAUNCH_APP" -eq 1 ]; then
  /usr/bin/pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
  /usr/bin/open "$APP_PATH"
fi

echo "Installed: $APP_PATH"
echo "Spotlight: registered with Launch Services and requested Spotlight indexing."
if [ "$INSTALL_AT_LOGIN" -eq 1 ]; then
  echo "Startup: enabled for this user."
else
  echo "Startup: not enabled. Add --at-login to enable it."
fi
if [ "$INSTALL_HELPER" -eq 1 ]; then
  echo "Helper: installed."
else
  echo "Helper: not installed. Add --helper for fewer password prompts."
fi
