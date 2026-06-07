#!/bin/bash
# Build a Ventoy-compatible hybrid ISO from the Voi6 rootfs.
# Drop the result on your Ventoy USB and boot it, or burn it to a DVD.
#
#   ./build-iso.sh              # output: build/voi6.iso
#   ./build-iso.sh /tmp/out.iso # custom path
#
# Requires: mksquashfs xorriso grub-mkrescue  (host tools)
# Run bootstrap.sh first to populate build/rootfs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
ROOTFS="$BUILD/rootfs"
ISODIR="$BUILD/iso-staging"
OUT="${1:-$BUILD/voi6.iso}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${BLUE}::${NC} $1"; }
ok()   { echo -e "   ${GREEN}ok${NC} $1"; }
die()  { echo -e "   ${RED}!!${NC} $1"; exit 1; }

for cmd in mksquashfs grub-mkrescue xorriso mformat; do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "$cmd not found — install mtools squashfs-tools grub xorriso on the host"
done
[ -d "$ROOTFS" ] || die "no rootfs — run bootstrap.sh first"

# Re-exec inside a user+mount namespace so mksquashfs/chroot see uid 0.
if [ -z "${VOI6_NS:-}" ]; then
    SELF="$(readlink -f "${BASH_SOURCE[0]}")"
    exec env VOI6_NS=1 unshare --map-auto --map-root-user --mount --fork \
        "$SELF" "$@"
fi

# ── Locate kernel ─────────────────────────────────────────────────────────────
KVER=$(ls "$ROOTFS/lib/modules/" 2>/dev/null | sort -V | tail -1)
KERNEL=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1)
[ -n "$KVER"   ] || die "no kernel modules in rootfs — did 'linux' install?"
[ -n "$KERNEL" ] || die "no vmlinuz in rootfs/boot"

# ── Rebuild initramfs with dmsquash-live ──────────────────────────────────────
step "building live initramfs (dmsquash-live, kernel $KVER)..."
mount --rbind /dev  "$ROOTFS/dev"  2>/dev/null
mount --rbind /proc "$ROOTFS/proc" 2>/dev/null
mount --rbind /sys  "$ROOTFS/sys"  2>/dev/null
trap 'umount -R "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" 2>/dev/null || true' EXIT

chroot "$ROOTFS" dracut \
    --add "dmsquash-live" \
    --install "getfattr setfattr" \
    --no-hostonly \
    --force \
    "/boot/initramfs-live.img" "$KVER" \
    2>&1 | grep -vE '^dracut: \+\+|^\+' || true
[ -f "$ROOTFS/boot/initramfs-live.img" ] || die "dracut produced no output"
ok "live initramfs: $(du -sh "$ROOTFS/boot/initramfs-live.img" | cut -f1)"

umount -R "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" 2>/dev/null || true
trap - EXIT

# ── Squashfs the rootfs (exclude boot blobs — they're in the ISO directly) ───
step "packing rootfs into squashfs..."
rm -rf "$ISODIR"
mkdir -p "$ISODIR/LiveOS" "$ISODIR/boot/grub"

mksquashfs "$ROOTFS" "$ISODIR/LiveOS/rootfs.img" \
    -comp gzip \
    -no-xattrs \
    -e "$ROOTFS/boot" \
    -noappend -quiet \
    || die "mksquashfs failed"
ok "squashfs: $(du -sh "$ISODIR/LiveOS/rootfs.img" | cut -f1)"

cp "$KERNEL"                           "$ISODIR/boot/vmlinuz"
cp "$ROOTFS/boot/initramfs-live.img"   "$ISODIR/boot/initramfs.img"
ok "kernel $(basename "$KERNEL") + live initramfs copied"

# ── GRUB config ───────────────────────────────────────────────────────────────
step "writing grub.cfg..."
cat > "$ISODIR/boot/grub/grub.cfg" << 'GRUBEOF'
set default=0
set timeout=5

menuentry "Voi6 Live" {
    linux  /boot/vmlinuz root=live:LABEL=VOI6 rd.live.image rd.live.dir=LiveOS rd.live.squashimg=rootfs.img quiet loglevel=4
    initrd /boot/initramfs.img
}

menuentry "Voi6 Live (verbose)" {
    linux  /boot/vmlinuz root=live:LABEL=VOI6 rd.live.image rd.live.dir=LiveOS rd.live.squashimg=rootfs.img loglevel=7
    initrd /boot/initramfs.img
}
GRUBEOF
ok "grub.cfg written"

# ── Hybrid ISO (BIOS + UEFI + El Torito) ─────────────────────────────────────
step "building hybrid ISO..."
grub-mkrescue -o "$OUT" "$ISODIR" -- -volid VOI6 2>/dev/null \
    || die "grub-mkrescue failed"

ok "$(du -sh "$OUT" | cut -f1)  →  $OUT"
echo
echo "   Ventoy:  copy $(basename "$OUT") to the Ventoy data partition"
echo "   Bare:    dd if=$OUT of=/dev/sdX bs=4M status=progress && sync"
