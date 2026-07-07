#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.helper"
ROOT_DIR="/Library/Application Support/DontDieOnMeNow"
HELPER_PATH="$ROOT_DIR/privileged_helper.sh"
CONFIG_PATH="$ROOT_DIR/helper.conf"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HELPER="$SCRIPT_DIR/privileged_helper.sh"
USER_SUPPORT_DIR="$HOME/Library/Application Support/DontDieOnMeNow"
REQUEST_DIR="$USER_SUPPORT_DIR/helper"
USER_UID="$(/usr/bin/id -u)"
USER_GID="$(/usr/bin/id -g)"

if [ ! -r "$SOURCE_HELPER" ]; then
  echo "Missing helper source: $SOURCE_HELPER" >&2
  exit 1
fi

/bin/mkdir -p "$REQUEST_DIR"
/bin/chmod 700 "$REQUEST_DIR"

/usr/bin/sudo /bin/mkdir -p "$ROOT_DIR"
/usr/bin/sudo /usr/sbin/chown root:wheel "$ROOT_DIR"
/usr/bin/sudo /bin/chmod 700 "$ROOT_DIR"
/usr/bin/sudo /usr/bin/install -m 700 -o root -g wheel "$SOURCE_HELPER" "$HELPER_PATH"

/usr/bin/sudo /usr/bin/tee "$CONFIG_PATH" >/dev/null <<CONFIG
REQUEST_DIR=$REQUEST_DIR
USER_SUPPORT_DIR=$USER_SUPPORT_DIR
USER_UID=$USER_UID
USER_GID=$USER_GID
CONFIG
/usr/bin/sudo /usr/sbin/chown root:wheel "$CONFIG_PATH"
/usr/bin/sudo /bin/chmod 600 "$CONFIG_PATH"

/usr/bin/sudo /usr/bin/tee "$PLIST_PATH" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_PATH</string>
    <string>--watch</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>/var/log/dont-die-on-me-now-helper.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/dont-die-on-me-now-helper.log</string>
</dict>
</plist>
PLIST

/usr/bin/sudo /usr/sbin/chown root:wheel "$PLIST_PATH"
/usr/bin/sudo /bin/chmod 644 "$PLIST_PATH"
/usr/bin/sudo /usr/bin/plutil -lint "$PLIST_PATH" >/dev/null
/usr/bin/sudo /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/usr/bin/sudo /bin/launchctl bootstrap system "$PLIST_PATH"
/usr/bin/sudo /bin/launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true

echo "Installed privileged helper."
echo "The app can now start and stop awake mode without asking for your password each time."
