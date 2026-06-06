# Voi6 field notes — mycel-compose under a real Void boot

The point of Voi6: run mycel-compose against Void's service set and record
every place the schema can't express what s6/s6-rc actually needs. Each finding
is a mycel-compose feature request, paid for in real boot pain.

Legend:
- **GAP** — the schema cannot express this; forced to the `run`/escape hatch or a workaround.
- **OK** — the schema handled it as-is (a win worth recording too).
- severity: 🔴 blocks a clean declaration · 🟡 works but ugly · 🟢 cosmetic

Each finding links the proposed mycel-compose change.

---

## Findings

### F-01 — oneshot `up` can't express a multi-step sequence  [FIXED] 🟡
**Service:** udev-trigger
**Was:** a oneshot's `up` was a single execline line, so coldplug's three steps
needed a hand-rolled `up = '/bin/sh -c "a; b; c"'` (latent in MycelOS too).
**FIXED IN THE COMPOSER:** `up`/`down` now accept a *list*; mycel-compose renders
it as one `/bin/sh -c` script (valid execline). Voi6's udev-trigger is now a clean
`up = ["udevadm trigger ...", "udevadm trigger ...", "udevadm settle ..."]`.
Verified: cage gets /dev/dri after coldplug, so the sequence ran.

### F-02 — no way to attach a logger to a longrun  [FIXED] 🟡
**Service:** dbus, udevd, elogind (every supervised daemon)
**Was:** under `s6-linux-init -B` (no catch-all logger), a daemon's output was
discarded; the schema couldn't express an s6-log consumer.
**FIXED IN THE COMPOSER:** `log = true` on a longrun emits a generated
`<name>-log` consumer (`consumer-for`), sets `producer-for` on the daemon, appends
`2>&1` so stderr is captured too, and folds the logger into the producer's bundles.
The logger runs `s6-log` into /var/log/<name>. Verified: elogind's `New
seat`/`New session` messages vanished from the console (diverted into the pipe),
and /var/log/{udevd,dbus,elogind} were created. Also works combined with `ready`
(notification-fd 3 + log pipe fd 1 coexist on elogind).

### F-03 — `needs` orders *started*, not *ready*  [GAP, CONFIRMED+fixed] 🔴
**Service:** elogind / its consumers (gettys doing pam_elogind login)
**What happened (v1.5):** with `getty needs ["elogind"]`, autologin still raced
elogind — login fired before elogind owned `org.freedesktop.login1`, so
pam_elogind (`-session optional`) silently no-op'd: **no logind session, no
XDG_RUNTIME_DIR**. Boot log proved the ordering (autologin before elogind's
"New seat seat0").
**Why the schema fails:** `needs` only guarantees *started* (process exec'd), not
*ready* (bus name owned). s6-rc has no readiness concept by default.
**First workaround (now removed):** a hand-rolled `elogind-ready` oneshot that
polled `dbus NameHasOwner login1`; gettys depended on it.
**FIXED IN THE COMPOSER:** mycel-compose now has a `ready = "dbus:..."` field
(also `path:`/`exec:`) that emits the s6 readiness wiring automatically —
`notification-fd` (3) + a `data/check` probe + an `s6-notifyoncheck` wrap of the
daemon. Voi6's elogind.toml is now just `ready = "dbus:org.freedesktop.login1"`,
the oneshot is deleted, and gettys just `need ["elogind"]`. Verified on a real
boot: elogind reaches readiness *before* autologin, `New session 1`,
`XDG_RUNTIME_DIR=/run/user/1000`, active session. ✓
**Status:** the highest-value Voi6 finding, shipped back into mycelinux — the
field test's whole reason for existing, demonstrated once end-to-end.

### F-04 — serial consoles get no seat (environment note, not a gap) 🟢 [resolved]
A login on `ttyS0` is not VT-bound, so elogind assigns no seat (SEAT blank). The
session stack still works there, but a compositor needs `seat0`, which only a
**tty1/VT** session gets. RESOLVED: getty-tty1 autologins `voi` (→ VT-bound seat0
session, confirmed `2 1000 voi seat0 tty1`), and the profile.d launcher execs
`cage -- foot` on tty1. **seatd was removed entirely** — elogind is the sole seat
manager; libseat uses its logind backend. Running both fought over seat0.
Verified: cage (wlroots, `WLR_RENDERER=pixman`, no GL driver in the VM) renders
foot on a virtio-GPU, captured headless via QMP `screendump`. v1.5 graphical
session works end to end.

### Voi6 launcher gotcha (not a finding, just a scar): a non-root login shell
can't write `/dev/console` — `exec cage 2>/dev/console` failed *before* exec, so
the compositor silently never started. Let compositor stderr stay on its tty.

## Desktop bring-up findings (Plasma on Voi6)

### D-01 — KDE components default to the xcb (X11) Qt plugin  🔴
plasmashell/kded6 tried the `xcb` platform plugin and died ("no Qt platform
plugin could be initialized") on a Wayland-only system. Fix: export
`QT_QPA_PLATFORM=wayland` in the session launcher's plasma branch.

### D-02 — /tmp/.X11-unix missing → Xwayland fails  🟡
Same as MycelOS: without `/tmp/.X11-unix` (and .ICE-unix), kwin can't start
Xwayland ("does not exist"). rc.init now creates them 1777 (the tmpfiles a
systemd distro would auto-create).

### D-03 — no GPU render node in QEMU  🟢
kwin logs "Failed to open drm node" / "No render nodes" and falls back to
software (kms_swrast); with `LIBGL_ALWAYS_SOFTWARE=1` + mesa-dri it composites
fine (cursor + shell render). Slow first boot (QML cache build under llvmpipe).
Session model: autologin tty1 → profile.d reads /etc/voi6/session → `exec
dbus-run-session startplasma-wayland`. No display manager.

## Installer integration findings (voi6-install → /mnt + GRUB)

The installer is bootstrap.sh retargeted to /mnt with partitioning + GRUB + users.
Bugs the install-then-boot loop surfaced:

### I-05 — last writes lost without an explicit sync  🔴
grub-mkconfig writes `grub.cfg.new` then renames to `grub.cfg`. The rename
happened in the guest but wasn't flushed to the disk image before the VM stopped,
so the installed disk had only `grub.cfg.new` → GRUB loaded `normal` but found no
config → dropped to `grub>`. Fix: the installer must `sync` + `umount -R /mnt` at
the end. (Symptom that pinned it: full `grub>` with `normal` loaded, not `grub
rescue>` — proves the fs was readable, so it wasn't a driver/feature problem.)

### I-06 — e2fsprogs 1.47 ext4 features vs GRUB  🟡
mkfs.ext4 defaults enable `orphan_file` / `metadata_csum_seed`; disable them
(`-O ^orphan_file,^metadata_csum_seed`) for the root fs so older GRUB readers stay
happy. (Not the cause of I-05, but a real compat fix worth keeping.)

### I-08 — installed root boots read-only (s6 must remount)  🔴
GRUB passes `root=… ro` (the standard convention: init fsck's then remounts rw).
The live image booted with `rw` on the cmdline, so it never showed — but the
installed disk came up with **/ read-only**, and nothing remounted it. Plasma's
session-log write failed → the session never launched (`Read-only file system`).
Fix: rc.init does `mount -o remount,rw /` early. Also hardened the launcher to log
to tmpfs (`$XDG_RUNTIME_DIR`) so a log write can never block the session. Verified:
installed disk now boots GRUB→s6→elogind→Plasma fully.

### I-07 — installed payload ≠ live payload  🟡
The live image bundles cage/foot/font (bootstrap PKGS); the *installer's* base set
didn't, and `install_de cage` wrongly assumed "already in base" → installed system
hit `exec: cage: not found` in a getty respawn loop. Fix: install_de installs the
compositor stack; launcher guards `command -v cage` so a missing compositor falls
back to a shell instead of looping. Also: branding (/etc/issue, os-release) must be
written by the INSTALLER too, not just bootstrap.

### Path-coupling (not schema gaps, but field-test data)
- `udevd`: MycelOS `/usr/lib/systemd/systemd-udevd` → Voi6 `/usr/bin/udevd` (eudev).
  The *declaration shape* is identical; only the exec target moves. Good news for
  portability: no schema change needed, just data.
- No `elogind` in Voi6 v1 (no desktop) — so `core` is smaller than MycelOS's.

## Void integration findings (putting s6 on Void — not mycel-compose gaps)

These are about displacing runit on Void; they don't touch the composer, but
they're the real cost of "s6 on Void" and worth recording.

### I-01 — `s6-linux-init` hard-conflicts with `runit-void`  🔴
Both claim PID 1, so xbps refuses to install s6-linux-init alongside runit-void.
Removing runit-void is blocked by the meta that pins it (`base-container-full`
in the ROOTFS; `base-system` on disk images). Fix: `xbps-remove` the meta (no
`-R` — that would orphan-remove glibc), then `runit-void`, then install s6.

### I-02 — Void's `s6-linux-init` package ships no skel  🔴
The package installs only the binaries. `s6-linux-init-maker`'s compiled-in
default skeldir (`/usr/etc/s6-linux-init/skel`) doesn't exist, so the maker dies
copying `skel/runlevel`. Fix: vendor the upstream 1.1.3.0 skel in the repo
(`s6-linux-init/skel/`) and restore it to the default location before running the
maker. (MycelOS never hits this — it builds the suite from skarnet source, which
includes the skel.)

### I-03 — stale ROOTFS + current repo = ABI mismatch  🔴
The published ROOTFS is ~16 months old; installing current-repo packages onto it
breaks ABI. Concretely: `dracut-109`'s `dracut-install` links `LIBKMOD_33`, but
the base ships an older `libkmod`, so EVERY `dracut-install` fails and initramfs
generation dies (`installkernel failed in module drm`). Fix: `xbps-install -Suy`
(full upgrade) BEFORE adding packages — standard Void practice (no partial
upgrades). Side note: `mknod` of device nodes fails under `unshare --map-auto`
(unprivileged userns forbids it), but dracut treats those as non-fatal.
