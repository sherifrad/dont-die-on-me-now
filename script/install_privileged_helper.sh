#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.helper"
HELPER_VERSION="10"
ROOT_DIR="/Library/Application Support/DontDieOnMeNow"
HELPER_PATH="$ROOT_DIR/privileged_helper.sh"
CONFIG_PATH="$ROOT_DIR/helper.conf"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/install_privileged_helper.sh"
SOURCE_HELPER="$SCRIPT_DIR/privileged_helper.sh"

fail() {
  echo "$1" >&2
  exit 1
}

plist_value() {
  local key="$1"
  local value

  if [ ! -f "$PLIST_PATH" ]; then
    return 0
  fi

  if value="$(/usr/bin/plutil -extract "$key" raw -o - "$PLIST_PATH" 2>/dev/null)"; then
    /usr/bin/printf '%s' "$value"
  fi
}

shell_single_quote() {
  local value="$1"
  /usr/bin/printf "'%s'" "$(/usr/bin/printf '%s' "$value" | /usr/bin/sed "s/'/'\\\\''/g")"
}

validate_user_context() {
  local user_support_dir="$1"
  local user_uid="$2"
  local user_gid="$3"

  case "$user_uid:$user_gid" in
    *[!0-9:]*|:*|*:)
      fail "Invalid helper user ids."
      ;;
  esac

  case "$user_support_dir" in
    /*"/Library/Application Support/DontDieOnMeNow") ;;
    *) fail "Invalid helper user support path: $user_support_dir" ;;
  esac

  case "$user_support_dir" in
    *[[:cntrl:]]*|*..*) fail "Unsafe helper user support path: $user_support_dir" ;;
  esac
}

install_as_root() {
  local user_support_dir="$1"
  local user_uid="$2"
  local user_gid="$3"
  local request_dir="$user_support_dir/helper"
  local helper_sha256

  if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    fail "The privileged helper installer must be authorized by macOS."
  fi

  validate_user_context "$user_support_dir" "$user_uid" "$user_gid"

  if [ ! -f "$SOURCE_HELPER" ] || [ -L "$SOURCE_HELPER" ]; then
    fail "Unsafe helper source: $SOURCE_HELPER"
  fi

  if [ ! -d "$request_dir" ] || [ -L "$request_dir" ]; then
    fail "Unsafe helper request path: $request_dir"
  fi

  if [ "$(/usr/bin/stat -f '%u' "$request_dir")" != "$user_uid" ]; then
    fail "The helper request directory is not owned by macOS user id $user_uid."
  fi

  /bin/mkdir -p "$ROOT_DIR"
  /usr/sbin/chown root:wheel "$ROOT_DIR"
  /bin/chmod 700 "$ROOT_DIR"
  /usr/bin/install -m 700 -o root -g wheel "$SOURCE_HELPER" "$HELPER_PATH"
  helper_sha256="$(/usr/bin/shasum -a 256 "$HELPER_PATH" | /usr/bin/awk '{print $1}')"

  /bin/cat > "$CONFIG_PATH" <<CONFIG
REQUEST_DIR=$request_dir
USER_SUPPORT_DIR=$user_support_dir
USER_UID=$user_uid
USER_GID=$user_gid
CONFIG
  /usr/sbin/chown root:wheel "$CONFIG_PATH"
  /bin/chmod 600 "$CONFIG_PATH"

  /bin/rm -f "$PLIST_PATH"
  /usr/bin/plutil -create xml1 "$PLIST_PATH"
  /usr/bin/plutil -insert Label -string "$LABEL" "$PLIST_PATH"
  /usr/bin/plutil -insert ProgramArguments -array "$PLIST_PATH"
  /usr/bin/plutil -insert ProgramArguments.0 -string "$HELPER_PATH" "$PLIST_PATH"
  /usr/bin/plutil -insert ProgramArguments.1 -string --once "$PLIST_PATH"
  /usr/bin/plutil -insert ThrottleInterval -integer 0 "$PLIST_PATH"
  /usr/bin/plutil -insert EnvironmentVariables -dictionary "$PLIST_PATH"
  /usr/bin/plutil -insert EnvironmentVariables.DDONMN_HELPER_VERSION -string "$HELPER_VERSION" "$PLIST_PATH"
  /usr/bin/plutil -insert EnvironmentVariables.DDONMN_HELPER_SHA256 -string "$helper_sha256" "$PLIST_PATH"
  /usr/bin/plutil -insert EnvironmentVariables.DDONMN_USER_UID -string "$user_uid" "$PLIST_PATH"
  /usr/bin/plutil -insert EnvironmentVariables.DDONMN_USER_SUPPORT_DIR -string "$user_support_dir" "$PLIST_PATH"
  /usr/bin/plutil -insert StandardOutPath -string /var/log/dont-die-on-me-now-helper.log "$PLIST_PATH"
  /usr/bin/plutil -insert StandardErrorPath -string /var/log/dont-die-on-me-now-helper.log "$PLIST_PATH"

  /usr/sbin/chown root:wheel "$PLIST_PATH"
  /bin/chmod 644 "$PLIST_PATH"
  /usr/bin/plutil -lint "$PLIST_PATH" >/dev/null
  /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap system "$PLIST_PATH"
}

if [ "${1:-}" = "--install-as-root" ]; then
  if [ "$#" -ne 4 ]; then
    fail "Invalid privileged helper installer arguments."
  fi
  install_as_root "$2" "$3" "$4"
  exit 0
fi

if [ "$#" -ne 0 ]; then
  fail "Usage: $0"
fi

if [ ! -f "$SOURCE_HELPER" ] || [ -L "$SOURCE_HELPER" ]; then
  fail "Missing or unsafe helper source: $SOURCE_HELPER"
fi

USER_SUPPORT_DIR="$HOME/Library/Application Support/DontDieOnMeNow"
REQUEST_DIR="$USER_SUPPORT_DIR/helper"
USER_UID="$(/usr/bin/id -u)"
USER_GID="$(/usr/bin/id -g)"
validate_user_context "$USER_SUPPORT_DIR" "$USER_UID" "$USER_GID"

if [ -L "$REQUEST_DIR" ] || { [ -e "$REQUEST_DIR" ] && [ ! -d "$REQUEST_DIR" ]; }; then
  fail "Unsafe helper request path: $REQUEST_DIR"
fi

/bin/mkdir -p "$REQUEST_DIR"
/bin/chmod 700 "$REQUEST_DIR"

if [ "$(/usr/bin/stat -f '%u' "$REQUEST_DIR")" != "$USER_UID" ]; then
  fail "The helper request directory is not owned by the current user: $REQUEST_DIR"
fi

INSTALLED_VERSION="$(plist_value EnvironmentVariables.DDONMN_HELPER_VERSION)"
INSTALLED_SHA256="$(plist_value EnvironmentVariables.DDONMN_HELPER_SHA256)"
INSTALLED_UID="$(plist_value EnvironmentVariables.DDONMN_USER_UID)"
INSTALLED_USER_SUPPORT_DIR="$(plist_value EnvironmentVariables.DDONMN_USER_SUPPORT_DIR)"
SOURCE_HELPER_SHA256="$(/usr/bin/shasum -a 256 "$SOURCE_HELPER" | /usr/bin/awk '{print $1}')"

if [ -n "$INSTALLED_UID" ] && [ "$INSTALLED_UID" != "$USER_UID" ]; then
  echo "A helper is already installed for macOS user id $INSTALLED_UID." >&2
  fail "Remove that helper first, or install with --no-helper."
fi

if [ "$INSTALLED_VERSION" = "$HELPER_VERSION" ] \
  && [ "$INSTALLED_SHA256" = "$SOURCE_HELPER_SHA256" ] \
  && [ "$INSTALLED_USER_SUPPORT_DIR" = "$USER_SUPPORT_DIR" ] \
  && /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
  echo "Privileged helper is already installed and current (version $HELPER_VERSION)."
  exit 0
fi

STAGING_DIR="$(/usr/bin/mktemp -d /tmp/DontDieOnMeNow-helper.XXXXXX)"
cleanup_staging() {
  /bin/rm -rf "$STAGING_DIR"
}
trap cleanup_staging EXIT

/bin/chmod 700 "$STAGING_DIR"
/usr/bin/install -m 700 "$SCRIPT_PATH" "$STAGING_DIR/install_privileged_helper.sh"
/usr/bin/install -m 700 "$SOURCE_HELPER" "$STAGING_DIR/privileged_helper.sh"

STAGED_INSTALLER="$STAGING_DIR/install_privileged_helper.sh"
ADMIN_COMMAND="$(shell_single_quote /bin/bash) $(shell_single_quote "$STAGED_INSTALLER") --install-as-root $(shell_single_quote "$USER_SUPPORT_DIR") $(shell_single_quote "$USER_UID") $(shell_single_quote "$USER_GID")"

echo "macOS will ask once for administrator approval to install the sleep helper."
if ! /usr/bin/osascript \
  -e 'on run argv' \
  -e 'do shell script (item 1 of argv) with administrator privileges' \
  -e 'end run' \
  "$ADMIN_COMMAND"; then
  fail "The privileged helper was not installed."
fi

if ! /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
  fail "The helper was copied but did not load. Run ./script/safety_status.sh for details."
fi

echo "Installed privileged helper version $HELPER_VERSION."
echo "The app can now start and stop awake mode without asking for your password each time."
