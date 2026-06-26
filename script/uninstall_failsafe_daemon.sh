#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec /usr/bin/sudo /bin/bash "$0" "$@"
fi

LABEL="com.josh.DontDieOnMeNow.failsafe"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
HELPER="/Library/Application Support/DontDieOnMeNow/failsafe_check.sh"

/bin/launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST" "$HELPER"

echo "Removed timed-session failsafe daemon: $PLIST"
