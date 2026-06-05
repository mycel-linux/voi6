#!/bin/bash
# Voi6 image builder — pack the bootstrapped rootfs into a raw ext4 disk and
# extract the kernel + initramfs for QEMU direct-kernel boot.
#
# Runs inside unshare --map-auto so the ext4 image records real uid/gid 0 for
# files the namespace owns as root (otherwise everything would be owned by the
# host subuid range and the booted system would be broken).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
ROOTFS="$BUILD/rootfs"
IMG="$BUILD/voi6.img"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${BLUE}::${NC} $1"; }
ok()   { echo -e "   ${GREEN}ok${NC} $1"; }
die()  { echo -e "   ${RED}!!${NC} $1"; exit 1; }

if [ -z "${VOI6_NS:-}" ]; then
    [ -d "$ROOTFS" ] || die "no rootfs — run bootstrap.sh first"
    exec env VOI6_NS=1 unshare --map-auto --map-root-user "${BASH_SOURCE[0]}" "$@"
fi

# ── Kernel + initramfs for direct-kernel boot ─────────────────────────────────
step "extracting kernel + initramfs..."
KERNEL=$(ls -1 "$ROOTFS"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1) \
    || die "no kernel in rootfs/boot — did 'linux' install?"
INITRD=$(ls -1 "$ROOTFS"/boot/initramfs-*.img 2>/dev/null | sort -V | tail -1) \
    || die "no initramfs in rootfs/boot"
cp "$KERNEL" "$BUILD/vmlinuz"
cp "$INITRD" "$BUILD/initramfs.img"
ok "kernel $(basename "$KERNEL"), initramfs $(basename "$INITRD")"

# ── ext4 image from the rootfs directory ──────────────────────────────────────
step "building ext4 image..."
# Size = rootfs usage + 40% slack, min 1 GiB.
used_mb=$(du -sm "$ROOTFS" | cut -f1)
size_mb=$(( used_mb * 14 / 10 ))
[ "$size_mb" -lt 1024 ] && size_mb=1024
rm -f "$IMG"
truncate -s "${size_mb}M" "$IMG"
mke2fs -q -t ext4 -L voi6root -d "$ROOTFS" -F "$IMG" \
    || die "mke2fs failed"
ok "voi6.img (${size_mb} MiB, from ${used_mb} MiB rootfs)"

echo
ok "image ready — boot with ./run-qemu.sh"
