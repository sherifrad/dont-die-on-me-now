#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="/Library/Application Support/DontDieOnMeNow"
HELPER="$STATE_DIR/failsafe_check.sh"
LABEL="com.josh.DontDieOnMeNow.failsafe"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

/bin/mkdir -p "$STATE_DIR"
/usr/sbin/chown root:wheel "$STATE_DIR"
/bin/chmod 700 "$STATE_DIR"
/usr/bin/install -m 755 -o root -g wheel "$ROOT_DIR/script/failsafe_check.sh" "$HELPER"
HELPER_XML="$(xml_escape "$HELPER")"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_XML</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>/var/log/dont-die-on-me-now-failsafe.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/dont-die-on-me-now-failsafe.log</string>
</dict>
</plist>
PLIST

/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
/usr/bin/plutil -lint "$PLIST" >/dev/null
/bin/launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$PLIST"
/bin/launchctl enable "system/$LABEL"
/bin/launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true

echo "Installed timed-session failsafe daemon: $PLIST"
echo "It restores normal sleep after a timed session deadline, even if the app is not running."
