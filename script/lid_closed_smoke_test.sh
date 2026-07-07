#!/usr/bin/env bash
set -euo pipefail

DURATION_MINUTES=35
INTERVAL_SECONDS=60
EXPECT_SLEEP_AFTER_MINUTES=""
OUTPUT_PATH="$HOME/Desktop/dont-die-on-me-now-lid-test-$(/bin/date +%Y%m%d-%H%M%S).log"

usage() {
  cat <<USAGE
Usage: ./script/lid_closed_smoke_test.sh [options]

Logs a passive heartbeat so you can verify Don't Die On Me Now while the lid is closed.
This script does not keep the Mac awake by itself.

Options:
  --minutes N                     How long to run. Default: 35.
  --interval N                    Seconds between heartbeats. Default: 60.
  --expect-sleep-after-minutes N  Treat a large heartbeat gap after N minutes as success.
  --output PATH                   Log path. Default: ~/Desktop/dont-die-on-me-now-lid-test-<timestamp>.log
  -h, --help                      Show this help.

Suggested manual test:
  1. Start a 10-minute Keep Awake session in the app.
  2. Run: ./script/lid_closed_smoke_test.sh --minutes 15 --expect-sleep-after-minutes 10
  3. Close the lid for about 13 minutes.
  4. Open the lid and read the summary at the end of the log.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --minutes)
      if [ "$#" -lt 2 ]; then
        echo "--minutes needs a value." >&2
        exit 2
      fi
      DURATION_MINUTES="$2"
      shift
      ;;
    --interval)
      if [ "$#" -lt 2 ]; then
        echo "--interval needs a value." >&2
        exit 2
      fi
      INTERVAL_SECONDS="$2"
      shift
      ;;
    --expect-sleep-after-minutes)
      if [ "$#" -lt 2 ]; then
        echo "--expect-sleep-after-minutes needs a value." >&2
        exit 2
      fi
      EXPECT_SLEEP_AFTER_MINUTES="$2"
      shift
      ;;
    --output)
      if [ "$#" -lt 2 ]; then
        echo "--output needs a path." >&2
        exit 2
      fi
      OUTPUT_PATH="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$DURATION_MINUTES" in
  ""|*[!0-9]*)
    echo "--minutes must be a positive integer." >&2
    exit 2
    ;;
esac

case "$INTERVAL_SECONDS" in
  ""|*[!0-9]*)
    echo "--interval must be a positive integer." >&2
    exit 2
    ;;
esac

if [ "$DURATION_MINUTES" -lt 1 ] || [ "$INTERVAL_SECONDS" -lt 1 ]; then
  echo "--minutes and --interval must be positive." >&2
  exit 2
fi

if [ -n "$EXPECT_SLEEP_AFTER_MINUTES" ]; then
  case "$EXPECT_SLEEP_AFTER_MINUTES" in
    ""|*[!0-9]*)
      echo "--expect-sleep-after-minutes must be a positive integer." >&2
      exit 2
      ;;
  esac

  if [ "$EXPECT_SLEEP_AFTER_MINUTES" -lt 1 ]; then
    echo "--expect-sleep-after-minutes must be positive." >&2
    exit 2
  fi
fi

/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT_PATH")"

sleep_disabled_value() {
  /usr/bin/pmset -g | /usr/bin/awk 'tolower($1) == "sleepdisabled" || tolower($1) == "disablesleep" { print $2; found = 1; exit } END { if (!found) print "missing" }'
}

power_source_summary() {
  /usr/bin/pmset -g batt | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/[[:space:]]\{1,\}/ /g'
}

assertion_summary() {
  /usr/bin/pmset -g assertions \
    | /usr/bin/awk '/PreventSystemSleep|PreventUserIdleSystemSleep|NoIdleSleepAssertion|Listed by owning process|pid / { print }' \
    | /usr/bin/tr '\n' ' ' \
    | /usr/bin/sed 's/[[:space:]]\{1,\}/ /g'
}

start_epoch="$(/bin/date +%s)"
end_epoch="$((start_epoch + (DURATION_MINUTES * 60)))"
last_epoch=0
max_gap_seconds=0
large_gap_started_after_seconds=""
normal_sleep_seen_after_expected=0
heartbeat_count=0

{
  echo "Don't Die On Me Now lid-closed smoke test"
  echo "started_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "duration_minutes=$DURATION_MINUTES"
  echo "interval_seconds=$INTERVAL_SECONDS"
  echo "expected_sleep_after_minutes=${EXPECT_SLEEP_AFTER_MINUTES:-none}"
  echo "This script is passive. It does not use any system awake command."
  echo
} >> "$OUTPUT_PATH"

echo "Logging to: $OUTPUT_PATH"

while :; do
  now_epoch="$(/bin/date +%s)"
  current_sleep_disabled="$(sleep_disabled_value)"
  gap_seconds=0

  if [ -n "$EXPECT_SLEEP_AFTER_MINUTES" ] \
    && [ "$current_sleep_disabled" = "0" ] \
    && [ "$((now_epoch - start_epoch))" -ge "$((EXPECT_SLEEP_AFTER_MINUTES * 60))" ]; then
    normal_sleep_seen_after_expected=1
  fi

  if [ "$last_epoch" -gt 0 ]; then
    gap_seconds="$((now_epoch - last_epoch))"
    if [ "$gap_seconds" -gt "$max_gap_seconds" ]; then
      max_gap_seconds="$gap_seconds"
      if [ "$gap_seconds" -gt "$((INTERVAL_SECONDS + 20))" ]; then
        large_gap_started_after_seconds="$((last_epoch - start_epoch))"
      fi
    fi
  fi

  heartbeat_count="$((heartbeat_count + 1))"
  {
    echo "AWAKE HEARTBEAT $heartbeat_count"
    echo "  utc=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "  epoch=$now_epoch"
    echo "  elapsed_seconds=$((now_epoch - start_epoch))"
    echo "  gap_since_last_seconds=$gap_seconds"
    echo "  sleep_disabled=$current_sleep_disabled"
    echo "  power=$(power_source_summary)"
    echo "  assertions=$(assertion_summary)"
    echo
  } >> "$OUTPUT_PATH"

  last_epoch="$now_epoch"

  if [ "$now_epoch" -ge "$end_epoch" ]; then
    break
  fi

  remaining_seconds="$((end_epoch - now_epoch))"
  if [ "$remaining_seconds" -lt "$INTERVAL_SECONDS" ]; then
    /bin/sleep "$remaining_seconds"
  else
    /bin/sleep "$INTERVAL_SECONDS"
  fi
done

threshold_seconds="$((INTERVAL_SECONDS + 20))"
result="review"
interpretation="A large heartbeat gap was detected. The Mac likely slept or the process was paused."

if [ -n "$EXPECT_SLEEP_AFTER_MINUTES" ]; then
  expected_sleep_after_seconds="$((EXPECT_SLEEP_AFTER_MINUTES * 60))"
  early_tolerance_seconds="$((INTERVAL_SECONDS + 30))"
  earliest_expected_gap_start="$((expected_sleep_after_seconds - early_tolerance_seconds))"
  if [ "$earliest_expected_gap_start" -lt 0 ]; then
    earliest_expected_gap_start=0
  fi

  if [ "$max_gap_seconds" -gt "$threshold_seconds" ] && [ -n "$large_gap_started_after_seconds" ] && [ "$large_gap_started_after_seconds" -ge "$earliest_expected_gap_start" ]; then
    result="pass"
    interpretation="A large heartbeat gap appeared after the expected timer expiry. The Mac likely returned to normal sleep."
  elif [ "$max_gap_seconds" -gt "$threshold_seconds" ]; then
    result="review"
    interpretation="A large heartbeat gap appeared before the expected timer expiry. Check whether the Mac slept too early."
  elif [ "$normal_sleep_seen_after_expected" -eq 1 ]; then
    result="blocked"
    interpretation="Normal sleep returned, but no sleep gap was detected. Another app or system assertion may be keeping the Mac awake."
  else
    result="fail"
    interpretation="No large heartbeat gap was detected after the timer expiry, and normal sleep was not observed."
  fi
elif [ "$max_gap_seconds" -le "$threshold_seconds" ]; then
  result="pass"
  interpretation="No large heartbeat gap was detected."
fi

{
  echo "SUMMARY"
  echo "  finished_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "  heartbeat_count=$heartbeat_count"
  echo "  max_gap_seconds=$max_gap_seconds"
  echo "  large_gap_started_after_seconds=${large_gap_started_after_seconds:-none}"
  echo "  expected_interval_seconds=$INTERVAL_SECONDS"
  echo "  expected_sleep_after_minutes=${EXPECT_SLEEP_AFTER_MINUTES:-none}"
  echo "  normal_sleep_seen_after_expected=$normal_sleep_seen_after_expected"
  echo "  result=$result"
  echo "  interpretation=$interpretation"
  echo "  final_assertions=$(assertion_summary)"
} >> "$OUTPUT_PATH"

echo "Done. Summary:"
/usr/bin/tail -n 8 "$OUTPUT_PATH"
