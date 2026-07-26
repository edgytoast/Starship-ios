#!/bin/bash
set -euo pipefail

PIN="6202c44356fee70dd23e80a16933b211863d3e2d" # main, 2026-06-15, HEAD at clone time (2026-07-10)
REPO="https://github.com/HarbourMasters/Starship.git"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/Starship"

if [[ ! -d "$VENDOR/.git" ]]; then
    git clone "$REPO" "$VENDOR"
fi
git -C "$VENDOR" fetch --tags origin
git -C "$VENDOR" checkout --detach "$PIN"
git -C "$VENDOR" submodule update --init --recursive

echo "vendor pinned: $(git -C "$VENDOR" rev-parse HEAD)"
echo "submodules:"
git -C "$VENDOR" submodule status --recursive
