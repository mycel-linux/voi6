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

### F-01 — oneshot `up` can't express a multi-step sequence  [GAP] 🟡
**Service:** udev-trigger
**What Void needs:** coldplug is three ordered commands — `udevadm trigger
--type=subsystems`, then `--type=devices`, then `udevadm settle`.
**Why the schema fails:** a oneshot's `up` is a *single* command line (written
verbatim as execline). The README claims "a plain command line works as-is," but
any real coldplug/mount/modules oneshot is a sequence.
**Workaround used in Voi6:** hand-rolled `up = '/bin/sh -c "a; b; c"'`.
**Corroboration:** MycelOS's own `udev-trigger.toml` already does this exact
`/bin/sh -c` dance — so this gap is not Void-specific, it's latent in MycelOS too.
**Proposed mycel-compose change:** allow `up`/`down` to be a *list* of lines
(like longrun `setup`), emitted as an execline `foreground { } ...` block or a
generated `#!/bin/sh` oneshot script. Removes every `/bin/sh -c` from oneshots.

### F-02 — no way to attach a logger to a longrun  [GAP] 🟡
**Service:** dbus, udevd, dhcpcd (every supervised daemon)
**What Void needs:** s6's idiom for capturing a daemon's stdout/stderr is a
paired `s6-log` *consumer* service (`producer-for`/`consumer-for` files +
`notification-fd`). Under `s6-linux-init -B` (no catch-all logger), an
un-paired daemon's output is discarded.
**Why the schema fails:** `Service` has no `log` / `producer-for` /
`consumer-for` fields; the composer never emits logger service dirs.
**Workaround used in Voi6:** none yet — logs are simply lost (acceptable for a
v1 bring-up, not for anything real).
**Proposed mycel-compose change:** a `log = true` (or `log = "<s6-log script>"`)
field that emits a sibling `<name>-log` consumer service, wires
`producer-for`/`consumer-for`, and sets the producer's `notification-fd`.

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

### F-04 — serial consoles get no seat (environment note, not a gap) 🟢
A login on `ttyS0` is not VT-bound, so elogind assigns no seat (SEAT blank in
`loginctl`). The session stack still works (session + XDG_RUNTIME_DIR), but a
compositor needs `seat0`, which only a **tty1/VT** session gets. Compositor
bring-up must therefore run on tty1, captured via the QEMU display, not serial.
Also: seatd AND elogind both manage seat0 now — likely drop seatd (or point
libseat at one) once the compositor lands, to avoid two seat managers.

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
