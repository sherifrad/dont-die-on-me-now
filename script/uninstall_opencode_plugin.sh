#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins"
PLUGIN_PATH="$PLUGIN_DIR/dont-die-on-me-now.js"

if [ -f "$PLUGIN_PATH" ] && [ ! -L "$PLUGIN_PATH" ]; then
  /bin/rm -f "$PLUGIN_PATH"
  echo "Removed OpenCode shutdown integration: $PLUGIN_PATH"
fi
