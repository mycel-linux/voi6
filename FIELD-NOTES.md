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

### F-03 — `needs` orders *started*, not *ready*  [GAP, anticipated] 🟢
**Service:** dbus consumers (bites later, with NetworkManager/compositor)
**What Void needs:** for v1 (dhcpcd/seatd) start-ordering is sufficient — dbus's
socket appears in milliseconds and clients retry. Recorded now because the
moment a desktop/NM lands it becomes real.
**Proposed mycel-compose change:** the roadmap's v3 `ready = "..."` →
`s6-notifyoncheck` wiring.

### Path-coupling (not schema gaps, but field-test data)
- `udevd`: MycelOS `/usr/lib/systemd/systemd-udevd` → Voi6 `/usr/bin/udevd` (eudev).
  The *declaration shape* is identical; only the exec target moves. Good news for
  portability: no schema change needed, just data.
- No `elogind` in Voi6 v1 (no desktop) — so `core` is smaller than MycelOS's.
