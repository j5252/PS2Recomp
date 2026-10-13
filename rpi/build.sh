#!/usr/bin/env bash
# Cross-builds the PS2 runtime (ps2xIOP + ps2xRuntime + ps2EntryRunner) for
# Raspberry Pi 2B (armhf, KMS/DRM + GLES2) inside the chroot from rpi/setup.sh.
# Recompiled game code is taken from ps2xRuntime/src/runner/ (see rpi/recompile.sh).
#
# Usage:
#   sudo ./rpi/build.sh [boot_elf_path_on_pi]
#
# Environment overrides:
#   PS2X_BOOT_ELF     guest ELF path baked into the runner (default: none, pass it at runtime)
#   PS2X_RPI_SUITE    Debian release used by setup.sh (default: trixie)
#   PS2X_RPI_CHROOT   chroot location (default: /opt/ps2x-rpi/<suite>)
#   BUILD_DIR         build directory inside the chroot (default: /build/rpi; the
#                     runner is copied to <repo>/outrpi/ afterwards)
#   BUILD_TYPE        CMake build type (default: Release)
#   TESTS=1           also build ps2x_tests for armhf and run it under qemu-arm
#   CLEAN=1           wipe the build directory before configuring
#   JOBS              parallel jobs (default: nproc)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chroot_common.sh"

BUILD_DIR="${BUILD_DIR:-/build/rpi}" # chroot-local: much faster than /mnt/c in WSL
BUILD_TYPE="${BUILD_TYPE:-Release}"
BOOT_ELF="${1:-${PS2X_BOOT_ELF:-}}"
BUILD_TEST=OFF
[ "${TESTS:-0}" = "1" ] && BUILD_TEST=ON

if [ ! -f "$REPO_ROOT/ps2xRuntime/src/runner/register_functions.cpp" ]; then
    echo "warning: ps2xRuntime/src/runner/ has no recompiled game code; the runner will link without a game." >&2
fi

ps2x_enter_chroot

ps2x_run CLEAN="${CLEAN:-0}" BUILD_DIR="$BUILD_DIR" BUILD_TYPE="$BUILD_TYPE" \
    BOOT_ELF="$BOOT_ELF" BUILD_TEST="$BUILD_TEST" -- '
cd /src
if [ "$CLEAN" = "1" ]; then rm -rf "$BUILD_DIR"; fi

# A cache configured outside the chroot is unusable here.
if [ -f "$BUILD_DIR/CMakeCache.txt" ] &&
    ! grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=/src\$" "$BUILD_DIR/CMakeCache.txt"; then
    echo "stale CMake cache from another environment detected; recreating $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

echo "==> configuring ($BUILD_TYPE, armhf, DRM/GLES2)"
cmake -S . -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=/src/rpi/toolchain-armhf.cmake \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DPS2X_RPI_DRM=ON \
    -DPS2X_BUILD_RECOMP=OFF \
    -DPS2X_BUILD_ANALYZER=OFF \
    -DPS2X_BUILD_STUDIO=OFF \
    -DPS2X_BUILD_TEST="$BUILD_TEST" \
    -DPS2X_ENABLE_SCCACHE=OFF \
    -DPS2X_ENABLE_FFMPEG=OFF \
    -DPS2X_ENABLE_AGRESSIVE_LOGS=OFF \
    -DPS2X_DEFAULT_BOOT_ELF="$BOOT_ELF"

echo "==> building"
cmake --build "$BUILD_DIR" -j"$JOBS"

if [ "$BUILD_TEST" = "ON" ]; then
    echo "==> running ps2x_tests under qemu-arm"
    TEST_BIN="$(find "$BUILD_DIR" -type f -name ps2x_tests -print -quit)"
    [ -n "$TEST_BIN" ] || { echo "error: ps2x_tests not found" >&2; exit 1; }
    qemu-arm -L /usr/arm-linux-gnueabihf "$TEST_BIN"
fi

RUNNER="$(find "$BUILD_DIR" -type f -name ps2EntryRunner -print -quit)"
if [ -z "$RUNNER" ]; then
    echo "error: build finished, but ps2EntryRunner was not found under $BUILD_DIR" >&2
    exit 1
fi
mkdir -p /src/outrpi
cp -f "$RUNNER" /src/outrpi/ps2EntryRunner
'

echo
echo "==> done: $REPO_ROOT/outrpi/ps2EntryRunner"
echo "    copy it to the Pi and run from a text console (no desktop session): ./ps2EntryRunner <game.elf>"
