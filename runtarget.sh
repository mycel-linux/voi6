#!/bin/bash
# Boot the INSTALLED disk standalone — no -kernel, so SeaBIOS -> GRUB (on the
# disk) -> s6. Proves the installer produced a self-booting system. Screenshots
# the result via QMP (virtio-GPU) and tails the serial.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; B="$HERE/build"
OUT="${1:-$B/voi6-installed.png}"; DELAY="${2:-45}"
QMP="$B/qmp-t.sock"; SER="$B/target-serial.log"
rm -f "$QMP" "$SER" "$OUT"
KVM=(); [ -e /dev/kvm ] && KVM=(-enable-kvm -cpu host)
qemu-system-x86_64 "${KVM[@]}" -m "${VOI6_RAM:-2048}" -smp 2 \
    -drive "file=$B/target.img,format=raw,if=virtio" \
    -device virtio-gpu-pci \
    -netdev user,id=n0 -device virtio-net,netdev=n0 \
    -display none -serial "file:$SER" \
    -qmp "unix:$QMP,server,nowait" -no-reboot &
QPID=$!
sleep "$DELAY"
python3 - "$QMP" "$OUT" <<'PY'
import socket, sys, json
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
f.readline()
def cmd(o): f.write(json.dumps(o)+"\n"); f.flush(); return f.readline().strip()
cmd({"execute": "qmp_capabilities"})
print("screendump:", cmd({"execute": "screendump",
                          "arguments": {"filename": sys.argv[2], "format": "png"}}))
PY
kill "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true
echo "── target serial tail ──"
sed 's/\x1b\[[0-9;]*m//g' "$SER" | tail -25
echo "── screenshot ──"; ls -l "$OUT" 2>&1
