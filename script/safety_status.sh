#!/usr/bin/env bash
set -euo pipefail

LOGIN_LABEL="com.josh.DontDieOnMeNow.login"
RESTORE_LABEL="com.josh.DontDieOnMeNow.restore"
HELPER_LABEL="com.josh.DontDieOnMeNow.helper"
DEADLINE_FILE="/Library/Application Support/DontDieOnMeNow/deadline"

echo "pmset:"
/usr/bin/pmset -g | /usr/bin/grep -i SleepDisabled || echo "  SleepDisabled not present"

echo
echo "app:"
if /usr/bin/pgrep -x DontDieOnMeNow >/dev/null; then
  echo "  running"
else
  echo "  not running"
fi

echo
echo "login launcher:"
if /bin/launchctl print "gui/$UID/$LOGIN_LABEL" >/dev/null 2>&1; then
  echo "  loaded"
else
  echo "  not loaded"
fi

echo
echo "timed restore job:"
if /bin/launchctl print "system/$RESTORE_LABEL" >/dev/null 2>&1; then
  echo "  loaded"
else
  echo "  not loaded"
fi

echo
echo "privileged helper:"
if /bin/launchctl print "system/$HELPER_LABEL" >/dev/null 2>&1; then
  echo "  loaded"
else
  echo "  not loaded"
fi

echo
echo "timed deadline:"
if [ -r "$DEADLINE_FILE" ]; then
  deadline="$(/bin/cat "$DEADLINE_FILE" 2>/dev/null || true)"
  case "$deadline" in
    ""|*[!0-9]*)
      echo "  invalid: $deadline"
      ;;
    *)
      now="$(/bin/date +%s)"
      echo "  $deadline ($((deadline - now))s remaining)"
      ;;
  esac
else
  echo "  none or root-only"
fi
