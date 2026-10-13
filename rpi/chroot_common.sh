# Shared helpers for rpi/*.sh: locate the chroot from rpi/setup.sh and bind-mount
# the repo (at /src) and, optionally, an input directory (read-only, at /input).
# Source this file; do not execute it.

fail() { echo "error: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="${PS2X_RPI_SUITE:-trixie}"
CHROOT="${PS2X_RPI_CHROOT:-/opt/ps2x-rpi/$SUITE}"
JOBS="${JOBS:-$(nproc)}"

[ "$(id -u)" -eq 0 ] || fail "run as root: the build runs inside a chroot"
[ -x "$CHROOT/usr/bin/arm-linux-gnueabihf-g++" ] || fail "missing cross chroot at $CHROOT. Run: sudo ./rpi/setup.sh"

case "$REPO_ROOT" in
/mnt/*)
    echo "warning: building under /mnt/ (Windows filesystem) is slow in WSL; consider cloning into the Linux filesystem." >&2
    ;;
esac

PS2X_MOUNTS=()

ps2x_mount() { # <source> <target-in-chroot> [ro]
    mkdir -p "$CHROOT$2"
    mount --bind "$1" "$CHROOT$2"
    if [ "${3:-}" = "ro" ]; then
        mount -o remount,bind,ro "$CHROOT$2"
    fi
    PS2X_MOUNTS+=("$CHROOT$2")
}

ps2x_cleanup_mounts() {
    local i
    for ((i = ${#PS2X_MOUNTS[@]} - 1; i >= 0; i--)); do
        umount "${PS2X_MOUNTS[$i]}" 2>/dev/null || true
    done
}

ps2x_enter_chroot() { # mounts /src, /proc, /dev; registers cleanup
    trap ps2x_cleanup_mounts EXIT
    ps2x_mount "$REPO_ROOT" /src
    mkdir -p "$CHROOT/proc"
    mount -t proc proc "$CHROOT/proc"
    PS2X_MOUNTS+=("$CHROOT/proc")
    ps2x_mount /dev /dev
    cp -f /etc/resolv.conf "$CHROOT/etc/resolv.conf" # FetchContent needs DNS
}

ps2x_run() { # <env assignments...> -- <bash script>
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    chroot "$CHROOT" /usr/bin/env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        HOME=/root JOBS="$JOBS" "${envs[@]}" \
        /bin/bash -euo pipefail -c "$1"
}
