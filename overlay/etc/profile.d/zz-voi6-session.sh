# Voi6 session entry, sourced by login shells via /etc/profile.
#
# v1.5: on the console TTYs, verify the elogind session stack came up — proves
# pam_elogind created a logind session and exported XDG_RUNTIME_DIR.
# Later this is where we read the chosen DE and exec the compositor (cage today,
# Plasma/GNOME next), exactly like MycelOS's zz-mycel-session.sh.

case "$(tty 2>/dev/null)" in
    /dev/tty1|/dev/ttyS0)
        echo "── Voi6 session check ───────────────────────────────"
        echo "user            : $(id -un) (uid $(id -u))"
        echo "XDG_RUNTIME_DIR : ${XDG_RUNTIME_DIR:-<unset>}"
        echo "XDG_SESSION_ID  : ${XDG_SESSION_ID:-<unset>}"
        if loginctl list-sessions 2>/dev/null | grep -q .; then
            loginctl list-sessions 2>/dev/null
            loginctl session-status 2>/dev/null | head -6
        else
            echo "loginctl        : NO logind session (elogind not ready at login?)"
        fi
        echo "─────────────────────────────────────────────────────"
        ;;
esac
