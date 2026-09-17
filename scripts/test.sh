#!/usr/bin/env bash
# Run the unit tests. Xcode's toolchain is needed for XCTest, so set DEVELOPER_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi

echo "==> DEVELOPER_DIR=$DEVELOPER_DIR"
swift test "$@"
