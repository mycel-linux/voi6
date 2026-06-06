# Voi6 session entry, sourced by login shells via /etc/profile.
#
# tty1  -> launch the chosen Wayland session for the autologin user.
# ttyS0 -> print an elogind session diagnostic (the serial debug console).
# The DE is read from /etc/voi6/session (written by the installer); default cage.

case "$(tty 2>/dev/null)" in
    /dev/tty1)
        # Only from a real logind session, and not if a session is already up.
        [ -n "${WAYLAND_DISPLAY:-}" ] && return
        [ -z "${XDG_SESSION_ID:-}" ] && return
        export XDG_SESSION_TYPE=wayland
        de=$(cat /etc/voi6/session 2>/dev/null || echo cage)
        case "$de" in
            plasma)
                command -v startplasma-wayland >/dev/null 2>&1 || return
                export XDG_CURRENT_DESKTOP=KDE
                export QT_QPA_PLATFORM=wayland   # KDE apps use Wayland, not xcb/X11
                export LIBGL_ALWAYS_SOFTWARE=1   # llvmpipe — no GPU accel in the VM
                # Log the session so failures are inspectable (writable by the user).
                exec dbus-run-session startplasma-wayland >"$HOME/.voi6-plasma.log" 2>&1
                ;;
            gnome)
                command -v gnome-session >/dev/null 2>&1 || return
                export XDG_CURRENT_DESKTOP=GNOME
                export LIBGL_ALWAYS_SOFTWARE=1
                exec dbus-run-session gnome-session
                ;;
            cage|*)
                command -v cage >/dev/null 2>&1 || return
                export WLR_RENDERER=pixman           # no GL driver; software render
                export WLR_NO_HARDWARE_CURSORS=1
                exec cage -- foot
                ;;
        esac
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
