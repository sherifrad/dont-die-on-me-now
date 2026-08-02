#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins"
PLUGIN_PATH="$PLUGIN_DIR/dont-die-on-me-now.js"
SOURCE_PLUGIN="$SCRIPT_DIR/dont-die-on-me-now-opencode-plugin.js"

if [ ! -f "$SOURCE_PLUGIN" ] || [ -L "$SOURCE_PLUGIN" ]; then
  echo "Missing or unsafe OpenCode plugin source: $SOURCE_PLUGIN" >&2
  exit 1
fi

/bin/mkdir -p "$PLUGIN_DIR"
/usr/bin/install -m 600 "$SOURCE_PLUGIN" "$PLUGIN_PATH"
echo "Installed OpenCode shutdown integration: $PLUGIN_PATH"
