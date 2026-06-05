#!/bin/bash
# Boot Voi6 in QEMU via direct kernel boot, serial console on stdio.
#   ./run-qemu.sh            # interactive, serial on this terminal
#   ./run-qemu.sh --timeout 60   # auto-quit after N s (for unattended boot tests)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/build"

TIMEOUT=0
[ "${1:-}" = "--timeout" ] && TIMEOUT="${2:-0}"

[ -f "$B/voi6.img" ]    || { echo "no image — run build-image.sh"; exit 1; }
[ -f "$B/vmlinuz" ]     || { echo "no kernel — run build-image.sh"; exit 1; }

KVM=()
[ -e /dev/kvm ] && KVM=(-enable-kvm -cpu host)

CMD=(qemu-system-x86_64
    "${KVM[@]}"
    -m 1024 -smp 2
    -kernel "$B/vmlinuz"
    -initrd "$B/initramfs.img"
    -append "root=/dev/vda rw init=/sbin/init console=ttyS0 loglevel=4 rd.shell=0"
    -drive "file=$B/voi6.img,format=raw,if=virtio"
    -netdev user,id=n0 -device virtio-net,netdev=n0
    -nographic -no-reboot)

if [ "$TIMEOUT" -gt 0 ]; then
    exec timeout --foreground "$TIMEOUT" "${CMD[@]}"
else
    exec "${CMD[@]}"
fi
