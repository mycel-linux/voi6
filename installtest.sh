#!/bin/bash
# Drive the installer unattended: boot the live image with the target disk as a
# second drive and voi6.autoinstall on the cmdline. Captures serial; stops when
# the install reports done (or after the timeout).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; B="$HERE/build"
SER="$B/install-serial.log"; MAX="${1:-420}"
rm -f "$SER"
KVM=(); [ -e /dev/kvm ] && KVM=(-enable-kvm -cpu host)
qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 2 \
    -kernel "$B/vmlinuz" -initrd "$B/initramfs.img" \
    -append "root=/dev/vda rw init=/sbin/init console=ttyS0 loglevel=4 voi6.autoinstall=/dev/vdb voi6.de=${VOI6_DE:-cage}" \
    -drive "file=$B/voi6.img,format=raw,if=virtio" \
    -drive "file=$B/target.img,format=raw,if=virtio" \
    -netdev user,id=n0 -device virtio-net,netdev=n0 \
    -display none -serial "file:$SER" -no-reboot &
QPID=$!
for _ in $(seq 1 "$MAX"); do
    grep -q 'VOI6-AUTOINSTALL:' "$SER" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 1
done
sleep 1
kill "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true
echo "── install serial tail ──"
sed 's/\x1b\[[0-9;]*m//g' "$SER" | grep -vE 'ETA:|avg rate|verifying RSA|\.sig2|: unpacking|collecting files|configuring \.\.\.' | tail -40
