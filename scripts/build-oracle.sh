#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/Starship"
BUILD="$ROOT/oracle/build-cmake"

[[ -d "$VENDOR/.git" ]] || { echo "FATAL: vendor/Starship missing — run scripts/bootstrap.sh" >&2; exit 1; }
[[ "${1:-}" == "--clean" ]] && rm -rf "$BUILD"

"$ROOT/scripts/apply-overlay.sh"

export CMAKE_POLICY_VERSION_MINIMUM=3.5

cmake -S "$VENDOR" -B "$BUILD" -GNinja -DCMAKE_BUILD_TYPE:STRING=Release
cmake --build "$BUILD" --target GeneratePortO2R --parallel 6
cmake --build "$BUILD" --parallel 6

BIN="$BUILD/Starship"
[[ -x "$BIN" ]] || { echo "FATAL: expected oracle binary at $BIN" >&2; exit 1; }
[[ -f "$BUILD/starship.o2r" ]] || { echo "FATAL: starship.o2r missing from build dir" >&2; exit 1; }
echo "oracle built: $BIN"
