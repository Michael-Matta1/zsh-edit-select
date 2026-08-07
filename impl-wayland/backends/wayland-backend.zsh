# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland backend — auto-detects XWayland (invisible) vs pure Wayland monitor.
# Daemon writes to cache files; shell reads via builtins (zero forks during typing).

# Resolve this backend's own directory once.  `:A` is syscall-bearing (one
# readlink per path component) and all the agent-path tests below resolve the
# same file, so the expansion is hoisted here and dropped after the last use.
# Plain assignment — `local` is a no-op at file scope.
_zes_backend_dir="${${(%):-%x}:A:h}"

# PRIMARY selection binary — desktop-environment-aware selection.
# Mutter-based DEs (GNOME and its forks) restrict background Wayland clients
# from reading PRIMARY but faithfully sync it to XWayland, so we use the
# xwayland agent there.
# KDE/KWin and wlroots compositors do NOT bridge PRIMARY to X11 but
# support data-control protocols, so we use the native Wayland agent.
_uses_xwayland_primary=0
case "${XDG_CURRENT_DESKTOP:-}" in
    # Desktop environments that use Mutter (or its forks) restrict background
    # Wayland clients from reading PRIMARY but heavily synchronize it to XWayland.
    *GNOME*|*gnome*|*Cinnamon*|*cinnamon*|*Pantheon*|*pantheon*)
        _uses_xwayland_primary=1
        ;;
esac

if (( _uses_xwayland_primary )) && [[ -n "${DISPLAY:-}" ]] && [[ -x "$_zes_backend_dir/xwayland/zes-xwayland-agent" ]]; then
    typeset -g _ZES_PRIMARY_BINARY="$_zes_backend_dir/xwayland/zes-xwayland-agent"
    typeset -g _ZES_PRIMARY_TYPE="x11"
elif [[ -x "$_zes_backend_dir/wayland/zes-wl-selection-agent" ]]; then
    typeset -g _ZES_PRIMARY_BINARY="$_zes_backend_dir/wayland/zes-wl-selection-agent"
    typeset -g _ZES_PRIMARY_TYPE="wayland"
else
    typeset -g _ZES_PRIMARY_BINARY=""
    typeset -g _ZES_PRIMARY_TYPE=""
fi

# CLIPBOARD binary — must follow the same rule as PRIMARY above.
#
# On Mutter-based desktops the xwayland agent is the right choice for both:
# direct X11 atom access, no Wayland protocol objects, no surfaces, and it
# avoids a second Wayland client connection for ZLE copy/paste.
#
# Everywhere else it is the wrong choice, and keying this off `$DISPLAY` alone
# picked it far too often — every KDE/wlroots session runs XWayland, so DISPLAY
# is set there too.  The X11 CLIPBOARD atom is not the Wayland clipboard: KWin
# bridges Wayland→X11 lazily, only when an XWayland client actually asks, so an
# atom read returns whatever was last written to X11 rather than what the user
# just copied.  In practice that is the plugin's own previous copy, since the
# plugin was the last thing to take X11 CLIPBOARD ownership — copying in Firefox
# and pasting in the terminal silently produced the earlier terminal text.
# Reading through the native agent's data-control path instead sees the real
# selection whoever set it (verified on Plasma 6: the agent returns the current
# clipboard while an X11 atom read does not).
#
# GNOME and friends are unaffected: `_uses_xwayland_primary` is 1 there, so they
# keep the xwayland agent exactly as before — which also preserves the reason it
# was preferred, GNOME < 47 having no data-control protocol for the native agent
# to use.
if (( _uses_xwayland_primary )) && [[ -n "${DISPLAY:-}" ]] \
   && [[ -x "$_zes_backend_dir/xwayland/zes-xwayland-agent" ]]; then
    typeset -g _ZES_CLIPBOARD_BINARY="$_zes_backend_dir/xwayland/zes-xwayland-agent"
elif [[ -x "$_zes_backend_dir/wayland/zes-wl-selection-agent" ]]; then
    # Native Wayland sessions (KDE/KWin, wlroots), and any tree where only the
    # Wayland binary was built.
    typeset -g _ZES_CLIPBOARD_BINARY="$_zes_backend_dir/wayland/zes-wl-selection-agent"
else
    # Neither binary available — clipboard falls back to wl-paste / wl-copy.
    # Build the appropriate agent with make in backends/xwayland/ or backends/wayland/.
    typeset -g _ZES_CLIPBOARD_BINARY=""
fi

unset _uses_xwayland_primary
unset _zes_backend_dir

# Public surface for the configuration wizard and external scripts:
# _ZES_MONITOR_TYPE  – the active PRIMARY backend type ("x11", "wayland", or "").
# _ZES_MONITOR_BINARY – path to the active PRIMARY agent binary.
# These mirror the internal _ZES_PRIMARY_* variables set above; the wizard
# and the WSL-tailored backend read _ZES_MONITOR_* exclusively.
typeset -g _ZES_MONITOR_TYPE="${_ZES_PRIMARY_TYPE}"
typeset -g _ZES_MONITOR_BINARY="${_ZES_PRIMARY_BINARY}"

# SSH mode flag — detected once at load time for zero per-call overhead.
# 1 = SSH session detected and OSC 52 clipboard passthrough is active.
# 0 = native clipboard backend in use (local session or user opt-out).
# ZES_SSH_CLIPBOARD=0 in ~/.zshrc before plugin load disables SSH mode.
typeset -gi _ZES_SSH_MODE=0
[[ "${ZES_SSH_CLIPBOARD:-1}" != "0" ]] && \
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] && \
    _ZES_SSH_MODE=1

# Start the background selection agent and wait until it signals readiness.
# The agent writes an initial seq file on startup, before daemonising; waiting
# for that file avoids a fixed sleep and verifies the agent is live.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    # || true: the directory create and the two cache cleanups below are
    # best-effort — their status is never read, and every check that follows
    # re-derives state from the filesystem.  Under an inherited err_return an
    # unwritable cache path would otherwise abort this function before the
    # DAEMON_ACTIVE resolution at the bottom, leaving the flag at its previous
    # value (stale 1) while no daemon runs, so the pre-redraw hook would keep
    # taking its daemon-active fast path against a cache nobody writes.  These
    # are simple commands, so the trailing guard is effective even when the
    # caller observes this function's status.  Unchanged under normal options.
    [[ -d "$_EDIT_SELECT_CACHE_DIR" ]] || mkdir -p -m 0700 "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1 || true

    if [[ -z "$_ZES_PRIMARY_BINARY" ]] || [[ ! -x "$_ZES_PRIMARY_BINARY" ]]; then
        # No PRIMARY agent binary available — fall back to wl-paste / wl-copy.
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        { pid=$(<"$_EDIT_SELECT_PID_FILE") || true } 2>/dev/null
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Daemon already running; reuse it.
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        # Stale PID file from a crashed or killed daemon.
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null || true
    fi

    # Remove stale cache files so the readiness check below cannot succeed
    # on data written by a previous daemon instance.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true

    # Launch the agent in a disowned background subshell so it survives
    # shell exit and does not generate job-control noise.
    (
        "$_ZES_PRIMARY_BINARY" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null || true
    )

    # Poll for the seq file to appear (agent readiness signal); give up
    # after 1 s (40 × 25 ms).
    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((++wait_count))
    done

    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
        return 0
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi
}

# Return the current PRIMARY selection text to stdout.
# Three-level priority:
#   1. Daemon cache file — zero forks, optimal hot path during typing.
#   2. Agent --oneshot mode — used when daemon is off but the binary exists;
#      on Mutter the agent briefly maps a tiny unfocused surface so the
#      compositor delivers the selection to it.
#   3. wl-paste — last resort when no agent binary is available.
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        local primary_data
        { primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    if [[ -n "$_ZES_PRIMARY_BINARY" ]] && [[ -x "$_ZES_PRIMARY_BINARY" ]]; then
        "$_ZES_PRIMARY_BINARY" --oneshot 2>/dev/null
    else
        wl-paste --primary --no-newline 2>/dev/null
    fi
}

# Return the current clipboard (CLIPBOARD selection) text to stdout.
# In SSH mode (_ZES_SSH_MODE=1), returns 1 — paste via terminal native keybinding.
function _zes_get_clipboard() {
    ((_ZES_SSH_MODE)) && return 1
    if [[ -n "$_ZES_CLIPBOARD_BINARY" ]] && [[ -x "$_ZES_CLIPBOARD_BINARY" ]]; then
        "$_ZES_CLIPBOARD_BINARY" --get-clipboard 2>/dev/null
    else
        wl-paste --no-newline 2>/dev/null
    fi
}

# Place $1 into the clipboard.  The agent forks a background child that serves
# paste requests until another application takes ownership, returning immediately
# so the shell is never blocked waiting for a paste to occur.
# In SSH mode (_ZES_SSH_MODE=1), uses OSC 52 to tunnel the write to the local terminal.
function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if ((_ZES_SSH_MODE)); then
        local _zes_encoded _zes_copy_rc
        # -w 0: suppress GNU base64 line-wrapping (default is 76 chars).
        # Embedded newlines in the encoded output would corrupt the OSC 52 sequence.
        _zes_encoded=$(printf '%s' "$1" | base64 -w 0) || return $?
        if [[ -n "${TMUX:-}" ]]; then
            # tmux requires DCS passthrough wrapping with doubled inner ESC.
            printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        elif [[ -n "${STY:-}" ]]; then
            # GNU Screen requires DCS passthrough wrapping.
            printf '\033P\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        else
            printf '\033]52;c;%s\a' "$_zes_encoded" > /dev/tty
        fi
        # Propagate the tty-write status so a failed OSC 52 copy surfaces as a
        # nonzero rc to the cut widget (which gates deletion on it) instead of
        # deleting text that was never copied.  No change on the success path.
        _zes_copy_rc=$?
        return $_zes_copy_rc
    fi
    if [[ -n "$_ZES_CLIPBOARD_BINARY" ]] && [[ -x "$_ZES_CLIPBOARD_BINARY" ]]; then
        printf '%s' "$1" | "$_ZES_CLIPBOARD_BINARY" --copy-clipboard 2>/dev/null
    else
        printf '%s' "$1" | wl-copy 2>/dev/null
    fi
}

# Clear the PRIMARY selection.  Called after a mouse-selected region is
# consumed to prevent accidental reuse of the highlighted text.
function _zes_clear_primary() {
    if [[ -n "$_ZES_PRIMARY_BINARY" ]] && [[ -x "$_ZES_PRIMARY_BINARY" ]]; then
        "$_ZES_PRIMARY_BINARY" --clear-primary 2>/dev/null || true
    else
        printf '' | wl-copy --primary 2>/dev/null || true
    fi
}
