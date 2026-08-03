#!/usr/bin/env bash
set -euo pipefail

LABEL="com.josh.DontDieOnMeNow.helper"
HELPER_VERSION="11"
ROOT_DIR="/Library/Application Support/DontDieOnMeNow"
CONFIG_FILE="$ROOT_DIR/helper.conf"
RESTORE_LABEL="com.josh.DontDieOnMeNow.restore"
RESTORE_PLIST="/Library/LaunchDaemons/$RESTORE_LABEL.plist"
RESTORE_SCRIPT="$ROOT_DIR/restore_once.sh"
SESSION_FILE="$ROOT_DIR/session"
DEADLINE_FILE="$ROOT_DIR/deadline"
DEADLINE_TEMP_FILE="$ROOT_DIR/deadline.tmp"
LAST_REQUEST_FILE="$ROOT_DIR/helper-last-request"
HELPER_LOG="/var/log/dont-die-on-me-now-helper.log"

REQUEST_DIR=""
USER_SUPPORT_DIR=""
USER_UID=""
USER_GID=""

read_config_value() {
  local key="$1"
  /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$CONFIG_FILE"
}

load_config() {
  if [ ! -r "$CONFIG_FILE" ]; then
    echo "Missing helper config: $CONFIG_FILE" >&2
    exit 1
  fi

  REQUEST_DIR="$(read_config_value REQUEST_DIR)"
  USER_SUPPORT_DIR="$(read_config_value USER_SUPPORT_DIR)"
  USER_UID="$(read_config_value USER_UID)"
  USER_GID="$(read_config_value USER_GID)"

  if [ -z "$REQUEST_DIR" ] || [ -z "$USER_SUPPORT_DIR" ] || [ -z "$USER_UID" ] || [ -z "$USER_GID" ]; then
    echo "Invalid helper config." >&2
    exit 1
  fi
}

shell_single_quote() {
  local value="$1"
  /usr/bin/printf "'%s'" "$(/usr/bin/printf '%s' "$value" | /usr/bin/sed "s/'/'\\\\''/g")"
}

read_request_value() {
  local key="$1"
  /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$REQUEST_DIR/request"
}

is_safe_identifier() {
  local value="$1"
  local maximum_length="$2"

  if [ "${#value}" -gt "$maximum_length" ]; then
    return 1
  fi

  case "$value" in
    ""|*[!A-Za-z0-9._-]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

request_directory_is_safe() {
  local owner
  local mode

  if [ ! -d "$REQUEST_DIR" ] || [ -L "$REQUEST_DIR" ]; then
    return 1
  fi

  owner="$(/usr/bin/stat -f '%u' "$REQUEST_DIR" 2>/dev/null || true)"
  mode="$(/usr/bin/stat -f '%Lp' "$REQUEST_DIR" 2>/dev/null || true)"
  [ "$owner" = "$USER_UID" ] && [ "$mode" = "700" ]
}

request_file_is_safe() {
  local owner
  local mode
  local link_count
  local size
  local request_file="$REQUEST_DIR/request"

  if [ ! -f "$request_file" ] || [ -L "$request_file" ]; then
    return 1
  fi

  owner="$(/usr/bin/stat -f '%u' "$request_file" 2>/dev/null || true)"
  mode="$(/usr/bin/stat -f '%Lp' "$request_file" 2>/dev/null || true)"
  link_count="$(/usr/bin/stat -f '%l' "$request_file" 2>/dev/null || true)"
  size="$(/usr/bin/stat -f '%z' "$request_file" 2>/dev/null || true)"
  case "$size" in
    ""|*[!0-9]*) return 1 ;;
  esac

  [ "$owner" = "$USER_UID" ] \
    && [ "$mode" = "600" ] \
    && [ "$link_count" = "1" ] \
    && [ "$size" -le 4096 ]
}

is_safe_path() {
  local value="$1"
  case "$value" in
    "")
      return 0
      ;;
    "$USER_SUPPORT_DIR"/*)
      case "$value" in
        *$'\n'*|*..*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

current_sleep_disabled() {
  if /usr/bin/pmset -g | /usr/bin/awk 'tolower($1) == "sleepdisabled" || tolower($1) == "disablesleep" { print $2; found = 1; exit } END { if (!found) print "0" }'; then
    return 0
  fi
  echo "unknown"
}

write_response() {
  local request_id="$1"
  local status="$2"
  local message="$3"
  local response_tmp="$ROOT_DIR/response.tmp.$$"

  if ! request_directory_is_safe; then
    echo "DontDieOnMeNow helper: unsafe request directory; response not written." >&2
    return 1
  fi

  {
    echo "request_id=$request_id"
    echo "status=$status"
    echo "message=$message"
    echo "sleep_disabled=$(current_sleep_disabled)"
  } > "$response_tmp"
  /bin/chmod 600 "$response_tmp"
  /usr/sbin/chown "$USER_UID:$USER_GID" "$response_tmp"
  /bin/mv -f "$response_tmp" "$REQUEST_DIR/response"
}

clear_restore_job() {
  /bin/launchctl bootout system "$RESTORE_PLIST" >/dev/null 2>&1 || /bin/launchctl bootout "system/$RESTORE_LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$RESTORE_PLIST" "$RESTORE_SCRIPT"
}

write_restore_plist() {
  /bin/cat > "$RESTORE_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$RESTORE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RESTORE_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>/var/log/dont-die-on-me-now-restore.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/dont-die-on-me-now-restore.log</string>
</dict>
</plist>
PLIST
}

write_restore_script() {
  local token="$1"
  local cancel_file="$2"
  local quoted_token
  local quoted_cancel_file
  quoted_token="$(shell_single_quote "$token")"
  quoted_cancel_file="$(shell_single_quote "$cancel_file")"

  /bin/cat > "$RESTORE_SCRIPT" <<SCRIPT
#!/bin/sh
set -eu
SESSION_FILE='${SESSION_FILE}'
DEADLINE_FILE='${DEADLINE_FILE}'
DEADLINE_TEMP_FILE='${DEADLINE_TEMP_FILE}'
RESTORE_LABEL='${RESTORE_LABEL}'
RESTORE_PLIST='${RESTORE_PLIST}'
RESTORE_SCRIPT='${RESTORE_SCRIPT}'
TOKEN=${quoted_token}
CANCEL_FILE=${quoted_cancel_file}
sleep_interval=2
deadline="\$(/bin/cat "\$DEADLINE_FILE" 2>/dev/null || true)"
case "\$deadline" in ''|*[!0-9]*) echo "DontDieOnMeNow restore: invalid deadline; restoring normal sleep."; /usr/bin/pmset -a disablesleep 0; echo "DontDieOnMeNow restore: normal sleep restored after invalid deadline."; if [ -n "\$CANCEL_FILE" ]; then /bin/rm -f "\$CANCEL_FILE"; fi; /bin/rm -f "\$SESSION_FILE" "\$DEADLINE_FILE" "\$DEADLINE_TEMP_FILE" "\$RESTORE_PLIST" "\$RESTORE_SCRIPT"; /bin/launchctl bootout "system/\$RESTORE_LABEL" >/dev/null 2>&1 || true; exit 0 ;; esac
restore_reason=deadline
while :; do
  if [ -n "\$CANCEL_FILE" ] && [ "\$(/bin/cat "\$CANCEL_FILE" 2>/dev/null || true)" = "\$TOKEN" ]; then restore_reason=stop; break; fi
  now="\$(/bin/date +%s)"
  if [ "\$now" -ge "\$deadline" ]; then break; fi
  remaining=\$((deadline - now))
  if [ "\$remaining" -gt "\$sleep_interval" ]; then /bin/sleep "\$sleep_interval"; elif [ "\$remaining" -gt 0 ]; then /bin/sleep "\$remaining"; fi
done
if [ "\$(/bin/cat "\$SESSION_FILE" 2>/dev/null || true)" = "\$TOKEN" ]; then if [ "\$restore_reason" = stop ]; then echo "DontDieOnMeNow restore: stop requested; restoring normal sleep."; else echo "DontDieOnMeNow restore: deadline reached; restoring normal sleep."; fi; /usr/bin/pmset -a disablesleep 0; echo "DontDieOnMeNow restore: normal sleep restored."; if [ -n "\$CANCEL_FILE" ]; then /bin/rm -f "\$CANCEL_FILE"; fi; /bin/rm -f "\$SESSION_FILE" "\$DEADLINE_FILE" "\$DEADLINE_TEMP_FILE"; else echo "DontDieOnMeNow restore: session token changed; leaving sleep setting unchanged."; fi
/bin/rm -f "\$RESTORE_PLIST" "\$RESTORE_SCRIPT"
/bin/launchctl bootout "system/\$RESTORE_LABEL" >/dev/null 2>&1 || true
SCRIPT
}

start_awake() {
  local seconds="$1"
  local token="$2"
  local cancel_file="$3"

  /bin/mkdir -p "$ROOT_DIR"
  /usr/sbin/chown root:wheel "$ROOT_DIR"
  /bin/chmod 700 "$ROOT_DIR"
  clear_restore_job

  echo "$token" > "$SESSION_FILE"
  /bin/chmod 600 "$SESSION_FILE"

  if [ "$seconds" -gt 0 ]; then
    echo "$(( $(/bin/date +%s) + seconds ))" > "$DEADLINE_TEMP_FILE"
    /bin/chmod 600 "$DEADLINE_TEMP_FILE"
    /bin/mv -f "$DEADLINE_TEMP_FILE" "$DEADLINE_FILE"
    write_restore_script "$token" "$cancel_file"
    /bin/chmod 700 "$RESTORE_SCRIPT"
    write_restore_plist
    /usr/sbin/chown root:wheel "$RESTORE_PLIST" "$RESTORE_SCRIPT"
    /bin/chmod 644 "$RESTORE_PLIST"
    /usr/bin/plutil -lint "$RESTORE_PLIST" >/dev/null
    /bin/launchctl bootstrap system "$RESTORE_PLIST"
  else
    /bin/rm -f "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
  fi

  /usr/bin/pmset -a disablesleep 1
}

stop_awake() {
  /bin/mkdir -p "$ROOT_DIR"
  /usr/sbin/chown root:wheel "$ROOT_DIR"
  /bin/chmod 700 "$ROOT_DIR"
  echo "off" > "$SESSION_FILE"
  /bin/chmod 600 "$SESSION_FILE"
  /usr/bin/pmset -a disablesleep 0
  clear_restore_job
  /bin/rm -f "$SESSION_FILE" "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
}

schedule_shutdown() {
  local seconds="$1"
  local quiet="$2"
  local minutes=$((seconds / 60))

  /sbin/shutdown -c >/dev/null 2>&1 || true
  if [ "$quiet" = "1" ]; then
    /sbin/shutdown -h -q "+$minutes"
  else
    /sbin/shutdown -h "+$minutes"
  fi
}

cancel_shutdown() {
  /sbin/shutdown -c
}

restore_expired_deadline() {
  local deadline
  local now

  if [ ! -f "$DEADLINE_FILE" ]; then
    return 0
  fi

  deadline="$(/bin/cat "$DEADLINE_FILE" 2>/dev/null || true)"
  case "$deadline" in
    ""|*[!0-9]*)
      echo "DontDieOnMeNow helper: invalid deadline; restoring normal sleep."
      /usr/bin/pmset -a disablesleep 0
      clear_restore_job
      /bin/rm -f "$SESSION_FILE" "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
      return 0
      ;;
  esac

  now="$(/bin/date +%s)"
  if [ "$now" -lt "$deadline" ]; then
    return 0
  fi

  echo "DontDieOnMeNow helper: deadline reached; restoring normal sleep."
  /usr/bin/pmset -a disablesleep 0
  clear_restore_job
  /bin/rm -f "$SESSION_FILE" "$DEADLINE_FILE" "$DEADLINE_TEMP_FILE"
}

process_request() {
  local request_id
  local last_request_id
  local action
  local seconds
  local token
  local cancel_file
  local quiet_shutdown

  if [ ! -e "$REQUEST_DIR/request" ]; then
    return 0
  fi

  if ! request_directory_is_safe; then
    echo "DontDieOnMeNow helper: rejected an unsafe request directory." >&2
    return 0
  fi

  if ! request_file_is_safe; then
    echo "DontDieOnMeNow helper: rejected an unsafe request file." >&2
    /bin/rm -f "$REQUEST_DIR/request" 2>/dev/null || true
    return 0
  fi

  request_id="$(read_request_value request_id)"
  action="$(read_request_value action)"
  seconds="$(read_request_value seconds)"
  token="$(read_request_value token)"
  cancel_file="$(read_request_value cancel_file)"
  quiet_shutdown="$(read_request_value quiet_shutdown)"
  if [ -z "$quiet_shutdown" ]; then
    quiet_shutdown=0
  fi
  last_request_id="$(/bin/cat "$LAST_REQUEST_FILE" 2>/dev/null || true)"

  if [ "$request_id" = "$last_request_id" ]; then
    return 0
  fi

  if ! is_safe_identifier "$request_id" 80; then
    write_response "invalid" "error" "Invalid request id."
    /bin/rm -f "$REQUEST_DIR/request"
    return 0
  fi

  if ! is_safe_identifier "$token" 128; then
    write_response "$request_id" "error" "Invalid token."
    echo "$request_id" > "$LAST_REQUEST_FILE"
    return 0
  fi

  case "$seconds" in
    ""|*[!0-9]*)
      write_response "$request_id" "error" "Invalid duration."
      echo "$request_id" > "$LAST_REQUEST_FILE"
      return 0
      ;;
  esac

  if [ "${#seconds}" -gt 5 ] || [ "$seconds" -gt 86400 ]; then
    write_response "$request_id" "error" "Duration must be 24 hours or less."
    echo "$request_id" > "$LAST_REQUEST_FILE"
    return 0
  fi

  case "$quiet_shutdown" in
    0|1) ;;
    *)
      write_response "$request_id" "error" "Invalid quiet shutdown setting."
      echo "$request_id" > "$LAST_REQUEST_FILE"
      return 0
      ;;
  esac

  case "$action" in
    start)
      if ! is_safe_path "$cancel_file"; then
        write_response "$request_id" "error" "Invalid cancel file."
        echo "$request_id" > "$LAST_REQUEST_FILE"
        return 0
      fi
      if start_awake "$seconds" "$token" "$cancel_file"; then
        write_response "$request_id" "ok" "Started."
      else
        write_response "$request_id" "error" "Could not start awake mode."
      fi
      ;;
    stop)
      if stop_awake; then
        write_response "$request_id" "ok" "Stopped."
      else
        write_response "$request_id" "error" "Could not stop awake mode."
      fi
      ;;
    schedule_shutdown)
      if [ "$seconds" -lt 60 ] || [ "$seconds" -gt 86400 ] || [ "$((seconds % 60))" -ne 0 ]; then
        write_response "$request_id" "error" "Shutdown duration must be between 1 minute and 24 hours."
        echo "$request_id" > "$LAST_REQUEST_FILE"
        return 0
      fi
      if schedule_shutdown "$seconds" "$quiet_shutdown"; then
        write_response "$request_id" "ok" "Shutdown scheduled."
      else
        write_response "$request_id" "error" "Could not schedule shutdown."
      fi
      ;;
    cancel_shutdown)
      if cancel_shutdown; then
        write_response "$request_id" "ok" "Shutdown canceled."
      else
        write_response "$request_id" "error" "Could not cancel shutdown."
      fi
      ;;
    *)
      write_response "$request_id" "error" "Invalid action."
      ;;
  esac

  echo "$request_id" > "$LAST_REQUEST_FILE"
}

main() {
  load_config

  case "$USER_UID:$USER_GID" in
    *[!0-9:]*|:*|*:) echo "Invalid helper user ids." >&2; exit 1 ;;
  esac
  if [ "$REQUEST_DIR" != "$USER_SUPPORT_DIR/helper" ] \
    || ! request_directory_is_safe; then
    echo "Unsafe helper request directory: $REQUEST_DIR" >&2
    exit 1
  fi

  while true; do
    process_request >> "$HELPER_LOG" 2>&1 || true
    restore_expired_deadline >> "$HELPER_LOG" 2>&1 || true
    /bin/sleep 0.5
  done
}

case "${1:-}" in
  --once)
    load_config
    process_request
    restore_expired_deadline
    /bin/sleep 1
    ;;
  ""|--watch)
    main
    ;;
  *)
    echo "Usage: $0 [--watch|--once]" >&2
    exit 64
    ;;
esac
