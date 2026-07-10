#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.helper"
RESTORE_LABEL="com.josh.DontDieOnMeNow.restore"
ROOT_DIR="/Library/Application Support/DontDieOnMeNow"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"
RESTORE_PLIST_PATH="/Library/LaunchDaemons/$RESTORE_LABEL.plist"
USER_REQUEST_DIR="$HOME/Library/Application Support/DontDieOnMeNow/helper"

echo "Administrator approval is needed to restore normal sleep and remove the helper."
/usr/bin/sudo -v

/usr/bin/sudo /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/usr/bin/sudo /bin/launchctl bootout "system/$RESTORE_LABEL" >/dev/null 2>&1 \
  || /usr/bin/sudo /bin/launchctl bootout system "$RESTORE_PLIST_PATH" >/dev/null 2>&1 \
  || true
/usr/bin/sudo /usr/bin/pmset -a disablesleep 0
/usr/bin/sudo /bin/rm -f "$PLIST_PATH"
/usr/bin/sudo /bin/rm -f \
  "$ROOT_DIR/privileged_helper.sh" \
  "$ROOT_DIR/helper.conf" \
  "$ROOT_DIR/helper-last-request" \
  "$ROOT_DIR/session" \
  "$ROOT_DIR/deadline" \
  "$ROOT_DIR/deadline.tmp" \
  "$ROOT_DIR/restore_once.sh" \
  "$RESTORE_PLIST_PATH" \
  "/var/log/dont-die-on-me-now-helper.log" \
  "/var/log/dont-die-on-me-now-restore.log"

/bin/rm -f "$USER_REQUEST_DIR/request" "$USER_REQUEST_DIR/response" "$USER_REQUEST_DIR"/request.*.tmp 2>/dev/null || true

echo "Uninstalled privileged helper."
echo "Normal sleep is on."
