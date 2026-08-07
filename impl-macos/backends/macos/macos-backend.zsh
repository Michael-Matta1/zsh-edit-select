# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# macOS pasteboard backend for zsh-edit-select.
# Provides the 5 required backend functions and _EDIT_SELECT_MONITOR_BIN.
#
# Selection capture uses two paths:
#   Path A (AX): read kAXSelectedTextAttribute in Terminal.app, iTerm2, kitty, and AppKit apps.
#   Path B (Cmd+C): inject Cmd+C with a reactive changeCount watcher when AX selection is
#                   unavailable (for example, in WezTerm, Alacritty, and Ghostty).
# This backend does not implement self-write suppression (_ZES_SELF_WRITE_CONTENT) because
# the daemon watches only mouse button releases (CGEventTap) and never polls
# NSPasteboard. Plugin copy/cut writes to NSPasteboard produce no daemon events.
#
# Sourced by zsh-edit-select-macos.plugin.zsh after that file has set
# _EDIT_SELECT_PLUGIN_DIR to the impl-macos directory.

# Absolute path to the compiled macOS clipboard agent binary.
typeset -g _EDIT_SELECT_MONITOR_BIN="${_EDIT_SELECT_PLUGIN_DIR}/backends/macos/zes-macos-clipboard-agent"

# SSH mode flag — detected once at load time for zero per-call overhead.
# 1 = SSH session detected and OSC 52 clipboard passthrough is active.
# 0 = native clipboard backend in use (local session or user opt-out).
# ZES_SSH_CLIPBOARD=0 in ~/.zshrc before plugin load disables SSH mode.
typeset -gi _ZES_SSH_MODE=0
[[ "${ZES_SSH_CLIPBOARD:-1}" != "0" ]] && \
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] && \
    _ZES_SSH_MODE=1

# ─────────────────────────────────────────────────────────────────────
# _zes_start_monitor
# Start the macOS clipboard daemon and wait for its readiness signal.
#
# READINESS SIGNAL: The launcher writes the child pid, then an empty seq file
# after posix_spawn().
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

    # || true: the directory create and the two cache cleanups below are
    # best-effort — their status is never read, and the checks that follow
    # re-derive state from the filesystem.  Under inherited err_return/err_exit
    # an unwritable cache path would otherwise abort this function midway,
    # leaving _EDIT_SELECT_DAEMON_ACTIVE at its previous value (stale 1) while
    # no daemon is running.  Behaviour is unchanged under normal options.
    [[ ! -d "$_EDIT_SELECT_CACHE_DIR" ]] && \
        mkdir -p -m 0700 "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1 || true

    # Reuse if a daemon is already alive.
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        { pid=$(<"$_EDIT_SELECT_PID_FILE") || true } 2>/dev/null
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null || true
    fi

    # Remove stale cache files so the readiness poll cannot succeed
    # on data from a previous daemon instance.  Include the reactive-capture
    # `pending` marker: this point is reached only when no daemon is alive (the
    # reuse path above returns first), so any leftover `pending` is from a dead
    # daemon whose capture can never complete -- leaving it would make
    # _zes_wait_for_reactive_capture spin a full second on the next keypress.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" "$_EDIT_SELECT_PENDING_FILE" 2>/dev/null || true

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
        disown 2>/dev/null || true
    )

    # Poll for readiness: seq file written by the launcher after posix_spawn().
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

# ─────────────────────────────────────────────────────────────────────
# _zes_get_primary
# Return primary cache text (= AX-selected text) to stdout.
#
# HOT PATH (daemon active): reads from the primary cache file via
# zsh built-in redirection — zero forks, zero subprocess overhead.
# Content may come from Path A (AX) or Path B (reactive Cmd+C).
# FALLBACK: pbpaste — always present on macOS.
# ─────────────────────────────────────────────────────────────────────
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local primary_data
        { primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
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
# In SSH mode (_ZES_SSH_MODE=1), returns 1 — paste via terminal native keybinding.
# ─────────────────────────────────────────────────────────────────────
function _zes_get_clipboard() {
    ((_ZES_SSH_MODE)) && return 1
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
# The agent is called asynchronously via a disowned background pipeline (&!).
# This offloads the write delay so that the terminal immediately
# regains responsiveness at the Zsh prompt after a Ctrl+C/Ctrl+X command.
# In SSH mode (_ZES_SSH_MODE=1), uses OSC 52 to tunnel the write to the local terminal.
# ─────────────────────────────────────────────────────────────────────
function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if ((_ZES_SSH_MODE)); then
        local _zes_encoded _zes_copy_rc
        # -b 0: suppress macOS base64 line-wrapping (macOS flag; Linux equivalent is -w 0).
        # Embedded newlines in the encoded output would corrupt the OSC 52 sequence.
        _zes_encoded=$(printf '%s' "$1" | base64 -b 0) || return $?
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
# Clear the local primary cache file so the shell does not see stale selected text.
#
# IMPORTANT: Does NOT call [NSPasteboard clearContents].
# Clearing NSPasteboard would destroy content the user copied from
# other apps. Only the local primary file is cleared; the seq counter is
# left to the daemon (see the inline note below).
# ─────────────────────────────────────────────────────────────────────
function _zes_clear_primary() {
    # Do not touch the seq counter here.
    # The daemon owns sequence progression; local seq writes can desync
    # daemon g_seq from seq-file state and cause every-other-event misses.
    [[ -n "${_EDIT_SELECT_PRIMARY_FILE:-}" ]] && [[ -d "${_EDIT_SELECT_PRIMARY_FILE:h}" ]] && \
        : >"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true
}
