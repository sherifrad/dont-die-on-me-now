#!/usr/bin/env bash
set -euo pipefail

/usr/bin/osascript <<'OSA'
do shell script "/usr/bin/pmset -a disablesleep 0; /bin/launchctl bootout system '/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist' >/dev/null 2>&1 || /bin/launchctl bootout 'system/com.josh.DontDieOnMeNow.restore' >/dev/null 2>&1 || true; /bin/rm -f '/Library/Application Support/DontDieOnMeNow/session' '/Library/Application Support/DontDieOnMeNow/deadline' '/Library/Application Support/DontDieOnMeNow/deadline.tmp' '/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist' '/Library/Application Support/DontDieOnMeNow/restore_once.sh'" with administrator privileges
OSA

echo "Normal sleep restored."
