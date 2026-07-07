#!/usr/bin/env bash
set -euo pipefail

USER_APP_PATH="$HOME/Applications/Don't Die On Me Now.app"
SYSTEM_APP_PATH="/Applications/Don't Die On Me Now.app"

default_app_path() {
  if [ -d "$USER_APP_PATH" ]; then
    printf '%s\n' "$USER_APP_PATH"
  else
    printf '%s\n' "$SYSTEM_APP_PATH"
  fi
}

APP_PATH="${1:-$(default_app_path)}"
LABEL="com.josh.DontDieOnMeNow.login"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

if [ ! -d "$APP_PATH" ]; then
  echo "App not found: $APP_PATH" >&2
  echo "Build and install it first:" >&2
  echo "  ./script/install_app.sh" >&2
  exit 1
fi

/bin/mkdir -p "$HOME/Library/LaunchAgents"
APP_PATH_XML="$(xml_escape "$APP_PATH")"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$APP_PATH_XML</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$PLIST" >/dev/null
/bin/launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$UID" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null 2>&1 || true

echo "Installed login launcher: $PLIST"
echo "It opens: $APP_PATH"
