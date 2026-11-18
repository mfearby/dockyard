#!/usr/bin/env bash
# Runs the Swift and TypeScript unit tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# With only the Command Line Tools installed (no Xcode), SwiftPM can't find the
# Swift Testing macro plugin or framework on its own, so point it at them.
SWIFT_FLAGS=()
DEV_DIR="$(xcode-select -p)"
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  SWIFT_FLAGS=(
    -Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing"
    -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/Frameworks"
  )
fi

echo "== Swift =="
swift test ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

echo "== TypeScript =="
cd web
[ -d node_modules ] || npm install
npx tsc --noEmit
npm test
