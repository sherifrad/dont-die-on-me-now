#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/Library/Application Support/DontDieOnMeNow"
SESSION_FILE="$STATE_DIR/session"
DEADLINE_FILE="$STATE_DIR/deadline"
DEADLINE_TEMP_FILE="$STATE_DIR/deadline.tmp"

if [ ! -f "$DEADLINE_FILE" ]; then
  exit 0
fi

deadline="$(/bin/cat "$DEADLINE_FILE" 2>/dev/null || true)"
case "$deadline" in
  ""|*[!0-9]*)
    /usr/bin/pmset -a disablesleep 0
    /bin/rm -f "$SESSION_FILE" "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
    echo "DontDieOnMeNow failsafe: restored normal sleep after invalid deadline: $deadline" >&2
    exit 0
    ;;
esac

now="$(/bin/date +%s)"
if [ "$now" -lt "$deadline" ]; then
  exit 0
fi

/usr/bin/pmset -a disablesleep 0
/bin/rm -f "$SESSION_FILE" "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
echo "DontDieOnMeNow failsafe: restored normal sleep after deadline $deadline"
