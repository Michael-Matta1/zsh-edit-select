# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# Absolute path to the compiled X11 selection agent binary.
typeset -g _EDIT_SELECT_MONITOR_BIN="$_EDIT_SELECT_PLUGIN_DIR/backends/x11/zes-x11-selection-agent"

# SSH mode flag — detected once at load time for zero per-call overhead.
# 1 = SSH session detected and OSC 52 clipboard passthrough is active.
# 0 = native clipboard backend in use (local session or user opt-out).
# ZES_SSH_CLIPBOARD=0 in ~/.zshrc before plugin load disables SSH mode.
typeset -gi _ZES_SSH_MODE=0
[[ "${ZES_SSH_CLIPBOARD:-1}" != "0" ]] && \
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] && \
    _ZES_SSH_MODE=1

# Start the background X11 selection agent and wait until it is ready.
# The agent writes a seq file on startup; presence of that file is the
# readiness signal — no fixed sleep, no polling the PID file.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    if [[ ! -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        # Agent binary absent — fall back to xclip for all clipboard ops.
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    # Ensure the cache directory exists.  || true: this create and the two
    # cleanups below are best-effort — their status is never read, and every
    # check that follows re-derives state from the filesystem.  Under an
    # inherited err_return an unwritable cache path would otherwise abort
    # before the DAEMON_ACTIVE resolution at the bottom, leaving the flag at
    # its previous value (a stale 1) while no daemon runs — the pre-redraw
    # hook would then keep taking its daemon-active fast path against a cache
    # nobody writes.  These are simple commands, so the guard is effective
    # even when the caller observes this function's status.
    [[ ! -d "$_EDIT_SELECT_CACHE_DIR" ]] && mkdir -p -m 0700 "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1 || true

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        { pid=$(<"$_EDIT_SELECT_PID_FILE") || true } 2>/dev/null
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Daemon already running; reuse it.
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return
        fi
        # Stale PID file — previous daemon died without cleanup.
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null || true
    fi

    # Remove stale cache files so the post-launch wait loop cannot mistake
    # an old seq file from a previous session for the new daemon's readiness
    # signal.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true

    # The agent's very first statement is `if (!getenv("DISPLAY")) return 1`,
    # so with no DISPLAY it exits before creating any cache file and the wait
    # below can only ever run out its full 1 s budget.  Resolve that case here
    # instead: identical end state (DAEMON_ACTIVE=0, no cache files, clipboard
    # operations fall back to xclip) reached immediately.  A live daemon is
    # still adopted first — the reuse path above returns before this point.
    if [[ -z "${DISPLAY:-}" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 0
    fi

    # Launch the agent in a disowned background subshell so it persists
    # beyond shell exit without job-control noise.
    (
        "$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null || true
    )

    # Wait up to 1 second (40 × 25 ms) for the agent's pre-daemon cache
    # initialization to create the seq file.  This bounds startup waiting;
    # daemonization, PID publication, and X event setup continue afterward.
    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((++wait_count))
    done

    # Mark daemon active if the seq file appeared; otherwise mark inactive.
    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
    fi
}

# Return the current PRIMARY selection text to stdout.
# When the daemon is active, the file read avoids forking a subprocess when
# an operation requests PRIMARY — zsh reads the file using a built-in redirection.
# Falls back to xclip only when the daemon is not running.
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local primary_data
        { primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    xclip -selection primary -o 2>/dev/null
}

# Return the current clipboard (CLIPBOARD selection) text to stdout.
# Uses the agent's --get-clipboard mode instead of spawning a separate
# xclip process.  (Like all short-lived agent modes, this is a fresh
# process that opens its own X connection and exits after the read.)
# In SSH mode (_ZES_SSH_MODE=1), returns 1 — paste via terminal native keybinding.
function _zes_get_clipboard() {
    ((_ZES_SSH_MODE)) && return 1
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --get-clipboard 2>/dev/null
    else
        xclip -selection clipboard -o 2>/dev/null
    fi
}

# Place $1 into the clipboard.  The agent forks a background child that
# serves paste requests until another application takes ownership, so this
# function returns immediately without blocking the shell.
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
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        printf '%s' "$1" | "$_EDIT_SELECT_MONITOR_BIN" --copy-clipboard 2>/dev/null
    else
        printf '%s' "$1" | xclip -selection clipboard -in 2>/dev/null
    fi
}

# Clear the PRIMARY selection.  Called after a mouse-selected region is
# consumed (pasted into the command line) to prevent accidental reuse of
# old highlighted text on the next keypress.
function _zes_clear_primary() {
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --clear-primary 2>/dev/null || true
    else
        printf '' | xclip -selection primary -in 2>/dev/null || true
    fi
}
