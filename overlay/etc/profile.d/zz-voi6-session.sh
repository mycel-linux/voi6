# Voi6 session entry, sourced by login shells via /etc/profile.
#
# tty1  -> launch the Wayland compositor (cage) for the autologin user.
# ttyS0 -> print an elogind session diagnostic (the serial debug console).
# Later, the tty1 branch reads the chosen DE and execs it (Plasma/GNOME), exactly
# like MycelOS's zz-mycel-session.sh — cage is just the first compositor.

case "$(tty 2>/dev/null)" in
    /dev/tty1)
        # Only from a real logind session, and not if a compositor is already up.
        [ -n "${WAYLAND_DISPLAY:-}" ] && return
        [ -z "${XDG_SESSION_ID:-}" ] && return
        export XDG_SESSION_TYPE=wayland
        export WLR_RENDERER=pixman           # no GL driver in the VM; software render
        export WLR_NO_HARDWARE_CURSORS=1     # QEMU virtio-gpu has no HW cursor
        # stderr stays on tty1 (the controlling terminal) so a failed compositor
        # leaves its error on screen; on success cage takes over the display.
        exec cage -- foot
        ;;
    /dev/ttyS0)
        echo "── Voi6 session check ───────────────────────────────"
        echo "user            : $(id -un) (uid $(id -u))"
        echo "XDG_RUNTIME_DIR : ${XDG_RUNTIME_DIR:-<unset>}"
        echo "XDG_SESSION_ID  : ${XDG_SESSION_ID:-<unset>}"
        if loginctl list-sessions 2>/dev/null | grep -q .; then
            loginctl list-sessions 2>/dev/null
        else
            echo "loginctl        : NO logind session"
        fi
        echo "─────────────────────────────────────────────────────"
        ;;
esac
