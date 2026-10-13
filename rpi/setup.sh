#!/usr/bin/env bash
# One-time setup of a Debian cross-build environment for Raspberry Pi 2B (armhf).
#
# Builds an amd64 Debian chroot matching the Pi's OS release, with the armhf
# cross compiler and the armhf -dev packages raylib needs for KMS/DRM + GLES2.
# Building inside a chroot of the *same* Debian release keeps the binary's glibc
# requirement compatible with the Pi (a newer host glibc would not run there).
#
#   Prerequisites: Debian/Ubuntu/Kali host (WSL works), sudo, debootstrap.
#   Usage:  sudo ./rpi/setup.sh
#
# Environment overrides:
#   PS2X_RPI_SUITE    Debian release of the Pi's OS (default: trixie;
#                     use bookworm for Raspberry Pi OS 12)
#   PS2X_RPI_CHROOT   chroot location (default: /opt/ps2x-rpi/<suite>)
#   PS2X_RPI_MIRROR   Debian mirror (default: http://deb.debian.org/debian)

set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

SUITE="${PS2X_RPI_SUITE:-trixie}"
CHROOT="${PS2X_RPI_CHROOT:-/opt/ps2x-rpi/$SUITE}"
MIRROR="${PS2X_RPI_MIRROR:-http://deb.debian.org/debian}"

[ "$(id -u)" -eq 0 ] || fail "run as root (sudo ./rpi/setup.sh)"
command -v debootstrap >/dev/null || fail "debootstrap not found (apt install debootstrap)"

if [ ! -x "$CHROOT/usr/bin/apt-get" ]; then
    echo "==> [1/3] debootstrap $SUITE (amd64) into $CHROOT"
    mkdir -p "$CHROOT"
    debootstrap --variant=minbase "$SUITE" "$CHROOT" "$MIRROR"
else
    echo "==> [1/3] reusing existing chroot $CHROOT"
fi

echo "==> [2/3] enabling armhf multiarch"
chroot "$CHROOT" dpkg --add-architecture armhf

echo "==> [3/3] installing cross toolchain and armhf dependencies"
chroot "$CHROOT" apt-get update
chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates git cmake ninja-build pkg-config python3 \
    build-essential \
    crossbuild-essential-armhf \
    libdrm-dev:armhf libgbm-dev:armhf libegl-dev:armhf libgles-dev:armhf \
    libasound2-dev:armhf \
    qemu-user

echo
echo "Done. Build with: ./rpi/build.sh"
echo "(chroot: $CHROOT)"
