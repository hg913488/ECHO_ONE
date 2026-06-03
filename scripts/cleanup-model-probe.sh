#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${CLEANUP_MODEL_PROBE_DERIVED_DATA:-$ROOT_DIR/build/cleanup-probe-cli}"
PRODUCT_PATH="$BUILD_DIR/Build/Products/Debug/CleanupModelProbe"

if [ ! -x "$PRODUCT_PATH" ]; then
  xcodebuild \
    -project "$ROOT_DIR/EchoOne.xcodeproj" \
    -scheme CleanupModelProbe \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -skipMacroValidation \
    build
fi

exec "$PRODUCT_PATH" "$@"
