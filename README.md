<p align="center">
  <img src="assets/logo.png" alt="Voi6 logo" width="140">
</p>

<h1 align="center">Voi6</h1>

<p align="center">
  <strong>Void Linux with s6 — a field test for mycel-compose, the mycelinux service composer.</strong>
</p>

---

Void ships [runit](http://smarden.org/runit/). Voi6 replaces it with the
[skarnet s6 suite](https://skarnet.org/software/) (`s6` + `s6-rc` +
`s6-linux-init`), and — this is the point — it generates the *entire* s6-rc
service layer with **mycel-compose**, the declarative service composer built for
MycelOS.

## Why this exists

Voi6 is not trying to be a distro you install. It is a **stepping stone to
MycelOS**, with one job: prove that mycel-compose is distro-agnostic by running
it against a service set it was *not* designed around (Void's, not Artix's).

Every Void service that the current mycel-compose schema *can't* express
cleanly — and so forces the `run = """..."""` escape hatch — is a finding. Those
findings live in [`FIELD-NOTES.md`](FIELD-NOTES.md) and are the real deliverable:
they become the mycel-compose backlog, paid for in real boot pain instead of
guessed at.

What transfers to MycelOS: the s6 knowledge (service graphs, `s6-linux-init` as
PID 1, supervision, shutdown sequencing, eudev/seatd wiring) **and** a harder
mycel-compose. What deliberately does *not* transfer: XBPS / `xbps-src`
packaging muscle — MycelOS is Arch/Artix-based.

## How it differs from the MycelOS bootstrap

MycelOS builds the s6 suite from skarnet source because Arch/Artix don't package
it cleanly. **Void packages the whole suite** (`s6`, `s6-rc`, `s6-linux-init`,
`execline`, `skalibs`) — so here s6 comes from `xbps-install`, and the work is
*displacing runit as PID 1*, not sourcing s6.

## Layout

    services/                  one .toml per service — the mycel-compose input
    s6-linux-init/scripts/     rc.init (stage 2) + rc.shutdown
    bootstrap.sh               Void ROOTFS -> s6 rootfs (rootless, via unshare -r)
    build-image.sh            rootfs -> bootable raw disk for QEMU
    FIELD-NOTES.md             running log of mycel-compose schema gaps
    build/                     downloaded rootfs + generated artifacts (untracked)

## Scope

**Design principle: keep everything that makes Void *Void* — change only the
service layer.** Keep XBPS, the Void mirrors, rolling release, and
install-it-yourself DEs (no pre-baked per-DE ISOs). Replace only runit's service
model (`ln -s /etc/sv/foo /var/service/`) with mycel-compose `.toml` → s6-rc.

- **v1 (current):** Void base + mycel-compose-generated s6-rc tree booting under
  `s6-linux-init` to a TTY login, with `udevd`, `dbus`, `seatd`, and networking
  (`dhcpcd`) supervised.
- **next:** full DEs (Plasma, GNOME, …) working — the real workout for
  mycel-compose (elogind + dbus + seatd + pipewire + display-manager + session
  graph). Installed the Void way: `xbps-install plasma`, not a bespoke ISO.
- **install path:** a patched `void-installer` — the official ncurses TUI, forked
  so its final service-enable step drives mycel-compose/s6-rc instead of runit
  `/var/service` symlinks. *Not* a Calamares clone (that would be drift toward
  competing with MycelOS).
