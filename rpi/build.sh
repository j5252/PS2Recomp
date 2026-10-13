#!/usr/bin/env bash
# Cross-builds the PS2 runtime (ps2xIOP + ps2xRuntime + ps2EntryRunner) for
# Raspberry Pi 2B (armhf, KMS/DRM + GLES2) inside the chroot from rpi/setup.sh.
#
# Usage:
#   sudo ./rpi/build.sh [boot_elf_path_on_pi]
#
# Environment overrides:
#   PS2X_BOOT_ELF     guest ELF path baked into the runner (default: none, pass it at runtime)
#   PS2X_RPI_SUITE    Debian release used by setup.sh (default: trixie)
#   PS2X_RPI_CHROOT   chroot location (default: /opt/ps2x-rpi/<suite>)
#   BUILD_DIR         build directory, relative to the repo (default: outrpi)
#   BUILD_TYPE        CMake build type (default: Release)
#   TESTS=1           also build ps2xTest for armhf and run it under qemu-arm
#   CLEAN=1           wipe the build directory before configuring
#   JOBS              parallel jobs (default: nproc)

set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="${PS2X_RPI_SUITE:-trixie}"
CHROOT="${PS2X_RPI_CHROOT:-/opt/ps2x-rpi/$SUITE}"
BUILD_DIR="${BUILD_DIR:-outrpi}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
BOOT_ELF="${1:-${PS2X_BOOT_ELF:-}}"
JOBS="${JOBS:-$(nproc)}"
TESTS="${TESTS:-0}"

[ "$(id -u)" -eq 0 ] || fail "run as root (sudo ./rpi/build.sh): the build runs inside a chroot"
[ -x "$CHROOT/usr/bin/arm-linux-gnueabihf-g++" ] || fail "missing cross chroot at $CHROOT. Run: sudo ./rpi/setup.sh"

if [ ! -f "$REPO_ROOT/ps2xRuntime/src/runner/register_functions.cpp" ]; then
    echo "warning: ps2xRuntime/src/runner/ has no recompiled game code; the runner will link without a game." >&2
fi

case "$REPO_ROOT" in
/mnt/*)
    echo "warning: building under /mnt/ (Windows filesystem) is slow in WSL; consider cloning into the Linux filesystem." >&2
    ;;
esac

# --- mount the repo inside the chroot ----------------------------------------

SRC_IN_CHROOT=/src
mkdir -p "$CHROOT$SRC_IN_CHROOT" "$CHROOT/proc" "$CHROOT/dev"
cleanup() {
    umount "$CHROOT$SRC_IN_CHROOT" 2>/dev/null || true
    umount "$CHROOT/proc" 2>/dev/null || true
    umount "$CHROOT/dev" 2>/dev/null || true
}
trap cleanup EXIT
mount --bind "$REPO_ROOT" "$CHROOT$SRC_IN_CHROOT"
mount -t proc proc "$CHROOT/proc"
mount --bind /dev "$CHROOT/dev"
cp -f /etc/resolv.conf "$CHROOT/etc/resolv.conf" # FetchContent needs DNS

if [ "$TESTS" = "1" ]; then
    BUILD_TEST=ON
else
    BUILD_TEST=OFF
fi

# --- configure + build -------------------------------------------------------

chroot "$CHROOT" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root \
    CLEAN="${CLEAN:-0}" BUILD_DIR="$BUILD_DIR" BUILD_TYPE="$BUILD_TYPE" \
    BOOT_ELF="$BOOT_ELF" JOBS="$JOBS" BUILD_TEST="$BUILD_TEST" \
    /bin/bash -euo pipefail -c '
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
    echo "==> running ps2xTest under qemu-arm"
    TEST_BIN="$(find "$BUILD_DIR" -type f -name ps2x_tests -print -quit)"
    [ -n "$TEST_BIN" ] || { echo "error: ps2x_tests not found" >&2; exit 1; }
    qemu-arm -L /usr/arm-linux-gnueabihf "$TEST_BIN"
fi
'

RUNNER="$(find "$REPO_ROOT/$BUILD_DIR" -type f -name ps2EntryRunner -print -quit)"
echo
if [ -n "$RUNNER" ]; then
    echo "==> done: $RUNNER"
    echo "    copy it to the Pi and run from a text console (no desktop session): ./ps2EntryRunner <game.elf>"
else
    echo "==> build finished, but ps2EntryRunner was not found under $BUILD_DIR"
fi
