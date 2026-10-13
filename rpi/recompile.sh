#!/usr/bin/env bash
# Builds the host (x86-64) recompiler tools inside the chroot from rpi/setup.sh,
# then runs ps2_analyzer + ps2_recomp on a PS2 ELF and installs the generated C++
# into ps2xRuntime/src/runner/, ready for ./rpi/build.sh.
#
# Usage:
#   sudo ./rpi/recompile.sh <path/to/game.elf> [config.toml]
#
# Without config.toml, ps2_analyzer generates one under rpi/work/<elf-name>/.
# Pass your own (e.g. exported from Ghidra) to skip the analyzer. Its `input`
# and `output` fields are rewritten to the chroot paths used here.
#
# Game ELFs and generated code are user data: rpi/work/ is git-ignored and the
# generated ps2xRuntime/src/runner/ files must not be committed.
#
# Environment overrides:
#   PS2X_RPI_SUITE / PS2X_RPI_CHROOT / JOBS   as in rpi/build.sh
#   HOST_BUILD_DIR   host tools build dir inside the chroot (default: /build/host)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/chroot_common.sh"

[ $# -ge 1 ] || fail "usage: sudo ./rpi/recompile.sh <path/to/game.elf> [config.toml]"
ELF="$(realpath "$1")"
[ -f "$ELF" ] || fail "ELF not found: $1"
USER_TOML=""
if [ $# -ge 2 ]; then
    USER_TOML="$(realpath "$2")"
    [ -f "$USER_TOML" ] || fail "config not found: $2"
fi

ELF_NAME="$(basename "$ELF")"
WORK_REL="rpi/work/$ELF_NAME"
mkdir -p "$REPO_ROOT/$WORK_REL"
if [ -n "$USER_TOML" ]; then
    cp -f "$USER_TOML" "$REPO_ROOT/$WORK_REL/config.toml"
fi

ps2x_enter_chroot
ps2x_mount "$(dirname "$ELF")" /input ro

ps2x_run HOST_BUILD_DIR="${HOST_BUILD_DIR:-/build/host}" ELF_NAME="$ELF_NAME" \
    WORK="/src/$WORK_REL" HAVE_TOML="$([ -n "$USER_TOML" ] && echo 1 || echo 0)" -- '
cd /src
echo "==> building host recompiler tools"
cmake -S . -B "$HOST_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPS2X_BUILD_RUNTIME=OFF \
    -DPS2X_BUILD_TEST=OFF \
    -DPS2X_BUILD_STUDIO=OFF \
    -DPS2X_BUILD_RECOMP=ON \
    -DPS2X_BUILD_ANALYZER=ON
cmake --build "$HOST_BUILD_DIR" -j"$JOBS" --target ps2_analyzer ps2_recomp

ANALYZER="$(find "$HOST_BUILD_DIR" -type f -name ps2_analyzer -perm -u+x -print -quit)"
RECOMP="$(find "$HOST_BUILD_DIR" -type f -name ps2_recomp -perm -u+x -print -quit)"

# Work on a chroot-local copy of the output: thousands of small files on /mnt/c are slow.
SCRATCH="/build/work/$ELF_NAME"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"

if [ "$HAVE_TOML" = "1" ]; then
    cp "$WORK/config.toml" "$SCRATCH/config.toml"
else
    echo "==> analyzing /input/$ELF_NAME"
    "$ANALYZER" "/input/$ELF_NAME" "$SCRATCH/config.toml"
fi

# Point input/output at the chroot paths regardless of where the TOML came from.
sed -i -E \
    -e "s|^input = .*|input = \"/input/$ELF_NAME\"|" \
    -e "s|^output = .*|output = \"$SCRATCH/output\"|" \
    "$SCRATCH/config.toml"

echo "==> recompiling"
"$RECOMP" "$SCRATCH/config.toml"

cp -f "$SCRATCH/config.toml" "$WORK/config.toml"

echo "==> installing generated code (sources -> src/runner/, headers -> include/)"
find ps2xRuntime/src/runner -maxdepth 1 -type f \( -name "*.cpp" -o -name "*.h" \) -delete
rm -f ps2xRuntime/include/ps2_recompiled_functions.h ps2xRuntime/include/ps2_recompiled_stubs.h
cp -f "$SCRATCH"/output/*.cpp ps2xRuntime/src/runner/
cp -f "$SCRATCH"/output/*.h ps2xRuntime/include/
echo "    $(ls ps2xRuntime/src/runner | wc -l) source files"
'

echo
echo "==> done. Config kept at $WORK_REL/config.toml"
echo "    next: sudo ./rpi/build.sh"
echo "    restore the stock runner with: git checkout -- ps2xRuntime/src/runner && git clean -fX ps2xRuntime/src/runner ps2xRuntime/include"
