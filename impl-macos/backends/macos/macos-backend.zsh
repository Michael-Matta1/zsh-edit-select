# Copyright (c) 2025 Michael Matta
# Version: 0.6.4
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# macOS pasteboard backend for zsh-edit-select.
# Provides the 6 required backend functions and _EDIT_SELECT_MONITOR_BIN.
#
# AX-ONLY DESIGN: This backend has NO self-write suppression variable
# (_ZES_SELF_WRITE_CONTENT). It is not needed because the daemon only
# watches for mouse button releases (CGEventTap) and never monitors
# NSPasteboard changes. Plugin copy/cut operations write to NSPasteboard
# but produce zero daemon events — no spurious selection detection occurs.
#
# Sourced by zsh-edit-select-macos.plugin.zsh AFTER _EDIT_SELECT_PLUGIN_DIR
# has been set (${0:A:h} of the plugin file = impl-macos/).

# Absolute path to the compiled macOS clipboard agent binary.
typeset -g _EDIT_SELECT_MONITOR_BIN="${_EDIT_SELECT_PLUGIN_DIR}/backends/macos/zes-macos-clipboard-agent"

# ─────────────────────────────────────────────────────────────────────
# _zes_check_ax_permission
# Returns 0 if Accessibility permission has been granted, 1 if not.
# Used by the wizard to show current AX status.
# ─────────────────────────────────────────────────────────────────────
function _zes_check_ax_permission() {
    [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]] && \
        "$_EDIT_SELECT_MONITOR_BIN" --check-ax 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────
# _zes_request_ax_permission
# Triggers the macOS system Accessibility permission dialog.
# Returns 0 if permission was granted, 1 if denied or still pending.
# ─────────────────────────────────────────────────────────────────────
function _zes_request_ax_permission() {
    [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]] && \
        "$_EDIT_SELECT_MONITOR_BIN" --request-ax 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────
# _zes_start_monitor
# Start the macOS clipboard daemon and wait for its readiness signal.
#
# READINESS SIGNAL: The daemon writes an empty seq file BEFORE posix_spawn().
# Poll for the seq file's existence (up to 40×25ms = 1s).
#
# TMUX BOOTSTRAP NAMESPACE FIX:
# Inside tmux, the shell may be in tmux's bootstrap namespace without
# pboard. If reattach-to-user-namespace is available, wrap the launch.
# The ${+commands[...]} lookup is a zero-cost zsh hash table probe.
# This check fires only once at startup, not per keypress.
# ─────────────────────────────────────────────────────────────────────
function _zes_start_monitor() {
    if [[ ! -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    [[ ! -d "$_EDIT_SELECT_CACHE_DIR" ]] && \
        mkdir -p "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1

    # Reuse if a daemon is already alive.
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi

    # Remove stale cache files so the readiness poll cannot succeed
    # on data from a previous daemon instance.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null

    # Build launch command with optional tmux namespace fix.
    local -a _zes_launch_cmd=("$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR")
    if [[ -n "${TMUX:-}" ]] && (( ${+commands[reattach-to-user-namespace]} )); then
        _zes_launch_cmd=(reattach-to-user-namespace \
            "$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR")
    fi

    # Launch in disowned background subshell.
    # subshell + disown: no job-control noise, persists beyond shell exit.
    (
        "${_zes_launch_cmd[@]}" &>/dev/null &
        disown 2>/dev/null
    )

    # Poll for readiness: seq file written by daemon BEFORE posix_spawn().
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

# ─────────────────────────────────────────────────────────────────────
# _zes_stop_monitor
# Send SIGTERM to the daemon and mark it inactive.
# ─────────────────────────────────────────────────────────────────────
function _zes_stop_monitor() {
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi
    _EDIT_SELECT_DAEMON_ACTIVE=0
}

# ─────────────────────────────────────────────────────────────────────
# _zes_get_primary
# Return primary cache text (= AX-selected text) to stdout.
#
# HOT PATH (daemon active): reads from the in-memory cache file via
# zsh built-in redirection — zero forks, zero subprocess overhead.
# FALLBACK: pbpaste — always present on macOS.
# ─────────────────────────────────────────────────────────────────────
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local primary_data
        primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi
    pbpaste 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────
# _zes_get_clipboard
# Return clipboard text (NSPasteboard generalPasteboard) to stdout.
#
# Uses the agent --get-clipboard. The agent is invoked without Cocoa
# UI initialization overhead, executing in ~15ms (indistinguishable
# from 0ms for manual keyboard pasting), ensuring 100% correct
# synchronization with external clipboard tools.
#
# FALLBACK: pbpaste if daemon is not running.
# ─────────────────────────────────────────────────────────────────────
function _zes_get_clipboard() {
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --get-clipboard 2>/dev/null
    else
        pbpaste 2>/dev/null
    fi
}

# ─────────────────────────────────────────────────────────────────────
# _zes_copy_to_clipboard
# Write $1 to NSPasteboard generalPasteboard.
#
# The agent is called asynchronously via background job { ... & }.
# This offloads the write delay so that the terminal immediately
# regains responsiveness at the Zsh prompt after a Ctrl+C/Ctrl+X command.
# ─────────────────────────────────────────────────────────────────────
function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        # &! = background + disown: no subshell fork, no job table entry,
        # no completion notifications. Zsh-specific operator.
        printf '%s' "$1" | "$_EDIT_SELECT_MONITOR_BIN" --copy-clipboard 2>/dev/null &!
    else
        printf '%s' "$1" | pbcopy 2>/dev/null
    fi
}

# ─────────────────────────────────────────────────────────────────────
# _zes_clear_primary
# Clear local cache files so the shell does not see stale selected text.
#
# IMPORTANT: Does NOT call [NSPasteboard clearContents].
# Clearing NSPasteboard would destroy content the user copied from
# other apps. Only the local seq/primary files are cleared.
#
# The double-clear pattern (agent --clear-primary + truncate locally)
# ensures the shell sees the cleared state immediately, before any
# async agent update is observable via zstat.
# ─────────────────────────────────────────────────────────────────────
function _zes_clear_primary() {
    # Increment sequence file purely in zsh to avoid forking the daemon binary
    if [[ -w "$_EDIT_SELECT_SEQ_FILE" ]]; then
        local current_seq=0
        [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && current_seq=$(<"$_EDIT_SELECT_SEQ_FILE" 2>/dev/null)
        ((current_seq++))
        printf '%d\n' "$current_seq" > "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null
    fi

    # Truncate locally immediately for instant visibility.
    [[ -n "${_EDIT_SELECT_PRIMARY_FILE:-}" ]] && \
        : >"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null
}
