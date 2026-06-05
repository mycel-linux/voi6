#!/bin/bash
# Boot Voi6 with a virtio-GPU, wait for the compositor, and grab a PNG via QMP.
# Headless: no UI window — QEMU renders into its console surface and we dump it.
#   ./shoot.sh [out.png] [delay_seconds]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$HERE/build"
OUT="${1:-$B/voi6-screen.png}"
DELAY="${2:-35}"
QMP="$B/qmp.sock"; SER="$B/serial.log"
rm -f "$QMP" "$SER" "$OUT"

KVM=(); [ -e /dev/kvm ] && KVM=(-enable-kvm -cpu host)

qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 2 \
    -kernel "$B/vmlinuz" -initrd "$B/initramfs.img" \
    -append "root=/dev/vda rw init=/sbin/init console=ttyS0 loglevel=4" \
    -drive "file=$B/voi6.img,format=raw,if=virtio" \
    -device virtio-gpu-pci \
    -netdev user,id=n0 -device virtio-net,netdev=n0 \
    -display none -serial "file:$SER" \
    -qmp "unix:$QMP,server,nowait" -no-reboot &
QPID=$!

# Give it time to boot + autologin + bring the compositor up.
sleep "$DELAY"

python3 - "$QMP" "$OUT" <<'PY'
import socket, sys, json
qmp, out = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.connect(qmp)
f = s.makefile("rw")
f.readline()                                            # QMP greeting
def cmd(o): f.write(json.dumps(o) + "\n"); f.flush(); return f.readline().strip()
cmd({"execute": "qmp_capabilities"})
print("screendump:", cmd({"execute": "screendump",
                          "arguments": {"filename": out, "format": "png"}}))
PY

kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true
echo "── serial tail ──"; tail -n 20 "$SER" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
echo "── screenshot ──"; ls -l "$OUT" 2>&1
