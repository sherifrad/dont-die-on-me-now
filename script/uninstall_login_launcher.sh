#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.login"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

/bin/launchctl bootout "gui/$UID" "$PLIST" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST"

echo "Removed login launcher: $PLIST"
