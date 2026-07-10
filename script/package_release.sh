#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./script/build_and_run.sh --verify
pkill -x DontDieOnMeNow >/dev/null 2>&1 || true

VERSION="$(/usr/bin/tr -d '\r\n[:space:]' < VERSION)"
STAGE_DIR="dist/installer-$VERSION"
ARCHIVE_PATH="dist/DontDieOnMeNow-$VERSION.zip"

/bin/rm -rf "$STAGE_DIR" "$ARCHIVE_PATH"
/bin/mkdir -p "$STAGE_DIR/script"
/usr/bin/ditto "dist/Don't Die On Me Now.app" "$STAGE_DIR/Don't Die On Me Now.app"
/usr/bin/ditto install-prebuilt.sh "$STAGE_DIR/install.sh"
/usr/bin/ditto uninstall.sh "$STAGE_DIR/uninstall.sh"
/usr/bin/ditto README.md "$STAGE_DIR/README.md"
/usr/bin/ditto LICENSE "$STAGE_DIR/LICENSE"

for script_name in \
  install_app.sh \
  install_login_launcher.sh \
  install_privileged_helper.sh \
  privileged_helper.sh \
  restore_sleep_now.sh \
  safety_status.sh \
  uninstall_app.sh \
  uninstall_failsafe_daemon.sh \
  uninstall_login_launcher.sh \
  uninstall_privileged_helper.sh; do
  /usr/bin/ditto "script/$script_name" "$STAGE_DIR/script/$script_name"
done

/bin/chmod +x "$STAGE_DIR/install.sh" "$STAGE_DIR/uninstall.sh" "$STAGE_DIR/script"/*.sh
/usr/bin/ditto -c -k --norsrc --keepParent "$STAGE_DIR" "$ARCHIVE_PATH"
echo "$ARCHIVE_PATH"
