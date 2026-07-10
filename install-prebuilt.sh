#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT_DIR/script/install_app.sh" \
  --prebuilt-app "$ROOT_DIR/Don't Die On Me Now.app" \
  "$@"
