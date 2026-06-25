#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./script/build_and_run.sh --verify
pkill -x DontDieOnMeNow >/dev/null 2>&1 || true

ditto -c -k --keepParent "dist/Don't Die On Me Now.app" "dist/DontDieOnMeNow.zip"
echo "dist/DontDieOnMeNow.zip"

