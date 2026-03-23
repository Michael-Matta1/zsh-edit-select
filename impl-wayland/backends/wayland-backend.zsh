# Copyright (c) 2025 Michael Matta
# Version: 0.6.4
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland backend — auto-detects XWayland (invisible) vs pure Wayland monitor.
# Daemon writes to cache files; shell reads via builtins (zero forks during typing).

# XWayland is preferred over pure Wayland when $DISPLAY is set, because the
# XWayland agent skips the Wayland protocol stack entirely and reads selection
# state directly through X11 atoms.  This is simpler and avoids the surface
# mapping requirement that Mutter imposes on Wayland clients.
if [[ -n "${DISPLAY:-}" ]] && [[ -x "${0:A:h}/xwayland/zes-xwayland-agent" ]]; then
    typeset -g _ZES_MONITOR_BINARY="${0:A:h}/xwayland/zes-xwayland-agent"
    typeset -g _ZES_MONITOR_TYPE="x11"
elif [[ -x "${0:A:h}/wayland/zes-wl-selection-agent" ]]; then
    typeset -g _ZES_MONITOR_BINARY="${0:A:h}/wayland/zes-wl-selection-agent"
    typeset -g _ZES_MONITOR_TYPE="wayland"
else
    # Neither binary was found — clipboard functions will fall back to
    # wl-paste / wl-copy.  The agent can be built by running make in the
    # appropriate backends/ subdirectory.
    typeset -g _ZES_MONITOR_BINARY=""
    typeset -g _ZES_MONITOR_TYPE=""
fi

# Start the background selection agent and wait until it signals readiness.
# The agent writes an initial seq file immediately after daemonising; waiting
# for that file avoids a fixed sleep and verifies the agent is live.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    # Ensure the cache directory exists (created once per session).
    [[ -d "$_EDIT_SELECT_CACHE_DIR" ]] || mkdir -p "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1

    if [[ -z "$_ZES_MONITOR_BINARY" ]] || [[ ! -x "$_ZES_MONITOR_BINARY" ]]; then
        # No agent binary available — fall back to wl-paste / wl-copy.
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
        "$_ZES_MONITOR_BINARY" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
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

    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --oneshot 2>/dev/null
    else
        wl-paste --primary --no-newline 2>/dev/null
    fi
}

# Return the current clipboard (CLIPBOARD selection) text to stdout.
function _zes_get_clipboard() {
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --get-clipboard 2>/dev/null
    else
        wl-paste --no-newline 2>/dev/null
    fi
}

# Place $1 into the clipboard.  The agent forks a background child that serves
# paste requests until another application takes ownership, returning immediately
# so the shell is never blocked waiting for a paste to occur.
function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        printf '%s' "$1" | "$_ZES_MONITOR_BINARY" --copy-clipboard 2>/dev/null
    else
        printf '%s' "$1" | wl-copy 2>/dev/null
    fi
}

# Clear the PRIMARY selection.  Called after a mouse-selected region is
# consumed to prevent accidental reuse of the highlighted text.
function _zes_clear_primary() {
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --clear-primary 2>/dev/null
    else
        printf '' | wl-copy --primary 2>/dev/null
    fi
}
