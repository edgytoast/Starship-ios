#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build-visionos"
PREFIX="$ROOT/work/vision-deps/prefix"
SHIP_O2R="$ROOT/oracle/build-cmake/starship.o2r"
TEAM="${SOH_IOS_TEAM:?set your Apple Developer team id (see README)}"

[[ -d "$ROOT/vendor/Starship/.git" ]] || "$ROOT/scripts/bootstrap.sh"
"$ROOT/scripts/apply-overlay.sh"
[[ -f "$PREFIX/lib/libvorbisfile.a" ]] || SOH_IOS_SDK=visionos "$ROOT/scripts/build-audio-deps-ios.sh"
[[ -f "$SHIP_O2R" ]] || "$ROOT/scripts/build-oracle.sh"

rm -rf "$BUILD/Release-xros" "$BUILD/Starship.xcarchive" "$BUILD/export"

export CMAKE_POLICY_VERSION_MINIMUM=3.5

SOH_IOS_BUNDLE_VERSION=$(awk -F. '{print (NF>=4)?$4+1:1}' "$ROOT/VERSION" 2>/dev/null || echo 1)

cmake --no-warn-unused-cli -S "$ROOT/vendor/Starship" -B "$BUILD" -GXcode \
    -DCMAKE_SYSTEM_NAME=visionOS -DPLATFORM=VISIONOS \
    -DCMAKE_OSX_SYSROOT=xros \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=2.0 -DDEPLOYMENT_TARGET=2.0 \
    -DCMAKE_BUILD_TYPE:STRING=Release \
    -DCMAKE_IGNORE_PREFIX_PATH="$HOME/Miniforge3" \
    -DSOH_VISIONOS=1 \
    -DCMAKE_XCODE_ATTRIBUTE_XROS_DEPLOYMENT_TARGET=2.0 \
    -DCMAKE_XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY=7 \
    -DCMAKE_XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT=NO \
    -DSDL_OPENGLES=OFF -DSDL_OPENGL=OFF \
    "-DSOH_IOS_DEPS_PREFIX=$PREFIX" \
    "-DSOH_O2R_PATH=$SHIP_O2R" \
    "-DSOH_IOS_SHELL_DIR=$ROOT/app/ios" \
    "-DSOH_IOS_BUNDLE_VERSION=$SOH_IOS_BUNDLE_VERSION" \
    "-DSOH_REMOTE_CONSOLE=${SOH_IOS_CONSOLE:-0}" \
    `# D-040: console/bridge OFF by default (public release safe); OTA/dev: SOH_IOS_CONSOLE=1` \
    "-DSOH_IOS_MENU_DIR=$ROOT/app/menu" \
    -DSOH_IOS_BUNDLE_IDENTIFIER=com.rebelancap.starship \
    "-DSOH_IOS_DEVELOPMENT_TEAM=$TEAM"

cmake --build "$BUILD" --config Release --target Starship --parallel 6 -- -allowProvisioningUpdates

APP="$BUILD/Release-xros/Starship.app"
[[ -d "$APP" ]] || { echo "FATAL: expected app at $APP" >&2; exit 1; }
codesign -dv "$APP" 2>&1 | sed -n '1,3p'
echo "built (visionOS device): $APP"
