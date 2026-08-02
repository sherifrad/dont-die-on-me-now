#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="Don't Die On Me Now"
APP_PROCESS_NAME="DontDieOnMeNow"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/$APP_DISPLAY_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_AT_LOGIN=0
INSTALL_HELPER=1
INSTALL_OPENCODE=1
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
  --helper         Install the privileged helper (the default).
  --no-helper      Skip the helper and use an administrator prompt on each change.
  --opencode       Install the OpenCode completion integration (the default).
  --no-opencode    Skip the OpenCode completion integration.
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
    --no-helper)
      INSTALL_HELPER=0
      ;;
    --opencode)
      INSTALL_OPENCODE=1
      ;;
    --no-opencode)
      INSTALL_OPENCODE=0
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

case "$INSTALL_DIR" in
  /*) ;;
  *)
    echo "Install directory must be an absolute path: $INSTALL_DIR" >&2
    exit 2
    ;;
esac

install_dir_needs_sudo() {
  local existing_path="$INSTALL_DIR"

  while [ ! -e "$existing_path" ]; do
    existing_path="$(/usr/bin/dirname "$existing_path")"
  done

  [ ! -w "$existing_path" ]
}

copy_app() {
  if [ "$USE_SUDO_FOR_COPY" -eq 1 ] || install_dir_needs_sudo; then
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

if [ ! -d "$DIST_APP" ]; then
  echo "App bundle not found: $DIST_APP" >&2
  exit 1
fi

copy_app
/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null
register_app

if [ "$INSTALL_HELPER" -eq 1 ]; then
  ./script/install_privileged_helper.sh
fi

if [ "$INSTALL_OPENCODE" -eq 1 ]; then
  /bin/bash ./script/install_opencode_plugin.sh
fi

if [ "$INSTALL_AT_LOGIN" -eq 1 ]; then
  ./script/install_login_launcher.sh "$APP_PATH"
else
  ./script/uninstall_login_launcher.sh
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
  echo "Helper: skipped. macOS will request administrator approval when sleep settings change."
fi
if [ "$INSTALL_OPENCODE" -eq 1 ]; then
  echo "OpenCode: completion integration installed."
else
  echo "OpenCode: completion integration skipped."
fi
