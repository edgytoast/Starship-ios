#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/Starship"
BUILD="$ROOT/oracle/build-cmake"
ROM="$ROOT/work/gamedata/sf64-us-v1.1.z64"
WANT_SHA="09f0d105f476b00efa5303a3ebc42e60a7753b7a" # Star Fox 64 (U) (V1.1), upstream-supported

[[ -f "$ROM" ]] || { echo "FATAL: ROM missing at $ROM" >&2; exit 1; }
GOT_SHA=$(shasum -a 1 "$ROM" | awk '{print $1}')
[[ "$GOT_SHA" == "$WANT_SHA" ]] || { echo "FATAL: ROM sha1 $GOT_SHA != supported $WANT_SHA" >&2; exit 1; }
[[ -d "$BUILD" ]] || { echo "FATAL: configure the oracle first (scripts/build-oracle.sh)" >&2; exit 1; }

cp "$ROM" "$VENDOR/baserom.z64"
cmake --build "$BUILD" --target ExtractAssets --parallel 6

[[ -f "$BUILD/sf64.o2r" ]] || { echo "FATAL: sf64.o2r missing from build dir" >&2; exit 1; }
echo "sf64.o2r: $(stat -f%z "$BUILD/sf64.o2r") bytes, sha1 $(shasum -a 1 "$BUILD/sf64.o2r" | awk '{print $1}')"
