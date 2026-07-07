#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.helper"
ROOT_DIR="/Library/Application Support/DontDieOnMeNow"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"
USER_REQUEST_DIR="$HOME/Library/Application Support/DontDieOnMeNow/helper"

/usr/bin/sudo /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/usr/bin/sudo /bin/rm -f "$PLIST_PATH"
/usr/bin/sudo /bin/rm -f \
  "$ROOT_DIR/privileged_helper.sh" \
  "$ROOT_DIR/helper.conf" \
  "$ROOT_DIR/helper-last-request"

/bin/rm -f "$USER_REQUEST_DIR/request" "$USER_REQUEST_DIR/response" "$USER_REQUEST_DIR"/request.*.tmp 2>/dev/null || true

echo "Uninstalled privileged helper."
echo "The app will fall back to macOS administrator prompts when changing sleep settings."
