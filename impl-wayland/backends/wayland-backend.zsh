# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland backend — auto-detects XWayland (invisible) vs pure Wayland monitor.
# Daemon writes to cache files; shell reads via builtins (zero forks during typing).

# PRIMARY selection binary — always the Wayland agent when available.
# The xwayland agent cannot detect PRIMARY from Wayland-native apps (e.g.
# Ghostty, VSCode in Wayland mode) on compositors such as KDE/KWin that do
# not bridge zwp_primary_selection_unstable_v1 to X11 PRIMARY.  The Wayland
# agent uses the official Wayland protocol and works on all compositors.
local _uses_xwayland_primary=0
case "${XDG_CURRENT_DESKTOP:-}" in
    # Desktop environments that use Mutter (or its forks) restrict background
    # Wayland clients from reading PRIMARY but heavily synchronize it to XWayland.
    *GNOME*|*gnome*|*Budgie*|*budgie*|*Cinnamon*|*cinnamon*|*Pantheon*|*pantheon*|*Unity*|*unity*|*Mutter*|*mutter*)
        _uses_xwayland_primary=1
        ;;
esac

if (( _uses_xwayland_primary )) && [[ -n "${DISPLAY:-}" ]] && [[ -x "${0:A:h}/xwayland/zes-xwayland-agent" ]]; then
    typeset -g _ZES_PRIMARY_BINARY="${0:A:h}/xwayland/zes-xwayland-agent"
    typeset -g _ZES_PRIMARY_TYPE="x11"
elif [[ -x "${0:A:h}/wayland/zes-wl-selection-agent" ]]; then
    typeset -g _ZES_PRIMARY_BINARY="${0:A:h}/wayland/zes-wl-selection-agent"
    typeset -g _ZES_PRIMARY_TYPE="wayland"
else
    typeset -g _ZES_PRIMARY_BINARY=""
    typeset -g _ZES_PRIMARY_TYPE=""
fi

# CLIPBOARD binary — prefer the xwayland agent when XWayland is present.
# The xwayland agent uses direct X11 atom access for clipboard read/write,
# requires no Wayland protocol objects, creates no surfaces, and is purely
# event-driven (no polling).  Using it for clipboard avoids adding a second
# Wayland client connection for ZLE copy/paste operations.
# Falls back to the Wayland agent on pure Wayland sessions without XWayland.
if [[ -n "${DISPLAY:-}" ]] && [[ -x "${0:A:h}/xwayland/zes-xwayland-agent" ]]; then
    typeset -g _ZES_CLIPBOARD_BINARY="${0:A:h}/xwayland/zes-xwayland-agent"
    typeset -g _ZES_CLIPBOARD_TYPE="x11"
elif [[ -x "${0:A:h}/wayland/zes-wl-selection-agent" ]]; then
    # XWayland binary not found; fall back to the Wayland agent for clipboard.
    # This covers pure Wayland sessions where only the Wayland binary was built.
    typeset -g _ZES_CLIPBOARD_BINARY="${0:A:h}/wayland/zes-wl-selection-agent"
    typeset -g _ZES_CLIPBOARD_TYPE="wayland"
else
    # Neither binary available — clipboard falls back to wl-paste / wl-copy.
    # Build the appropriate agent with make in backends/xwayland/ or backends/wayland/.
    typeset -g _ZES_CLIPBOARD_BINARY=""
    typeset -g _ZES_CLIPBOARD_TYPE=""
fi

# Backward-compatibility aliases consumed by the configuration wizard and any
# external scripts that may reference these variables.
# _ZES_MONITOR_TYPE reflects the PRIMARY monitoring backend (wayland or "").
# _ZES_MONITOR_BINARY mirrors _ZES_PRIMARY_BINARY for external compatibility.
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
# The agent writes an initial seq file immediately after daemonising; waiting
# for that file avoids a fixed sleep and verifies the agent is live.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    # Ensure the cache directory exists (created once per session).
    [[ -d "$_EDIT_SELECT_CACHE_DIR" ]] || mkdir -p "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1

    if [[ -z "$_ZES_PRIMARY_BINARY" ]] || [[ ! -x "$_ZES_PRIMARY_BINARY" ]]; then
        # No PRIMARY agent binary available — fall back to wl-paste / wl-copy.
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Daemon already running; reuse it.
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        # Stale PID file from a crashed or killed daemon.
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi

    # Remove stale cache files so the readiness check below cannot succeed
    # on data written by a previous daemon instance.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null

    # Launch the agent in a disowned background subshell so it survives
    # shell exit and does not generate job-control noise.
    (
        "$_ZES_PRIMARY_BINARY" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null
    )

    # Poll for the seq file to appear (agent readiness signal); give up
    # after 1 s (40 × 25 ms).
    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((wait_count++))
    done

    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
        return 0
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi
}

# Send SIGTERM to the running agent and mark the daemon inactive.
function _zes_stop_monitor() {
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi
    _EDIT_SELECT_DAEMON_ACTIVE=0
}

# Return the current PRIMARY selection text to stdout.
# Three-level priority:
#   1. Daemon cache file — zero forks, optimal hot path during typing.
#   2. Agent --oneshot mode — used when daemon is off but the binary exists;
#      on Mutter the agent briefly creates a popup surface to gain focus.
#   3. wl-paste — last resort when no agent binary is available.
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        local primary_data
        primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
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
        local _zes_encoded
        # -w 0: suppress GNU base64 line-wrapping (default is 76 chars).
        # Embedded newlines in the encoded output would corrupt the OSC 52 sequence.
        _zes_encoded=$(printf '%s' "$1" | base64 -w 0)
        if [[ -n "${TMUX:-}" ]]; then
            # tmux requires DCS passthrough wrapping with doubled inner ESC.
            printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        elif [[ -n "${STY:-}" ]]; then
            # GNU Screen requires DCS passthrough wrapping.
            printf '\033P\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        else
            printf '\033]52;c;%s\a' "$_zes_encoded" > /dev/tty
        fi
        return 0
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
        "$_ZES_PRIMARY_BINARY" --clear-primary 2>/dev/null
    else
        printf '' | wl-copy --primary 2>/dev/null
    fi
}
