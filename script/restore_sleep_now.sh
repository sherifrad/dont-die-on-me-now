#!/usr/bin/env bash
set -euo pipefail

/usr/bin/osascript <<'OSA'
do shell script "/usr/bin/pmset -a disablesleep 0; /bin/rm -f '/Library/Application Support/DontDieOnMeNow/session' '/Library/Application Support/DontDieOnMeNow/deadline' '/Library/Application Support/DontDieOnMeNow/deadline.tmp'" with administrator privileges
OSA

echo "Normal sleep restored."
