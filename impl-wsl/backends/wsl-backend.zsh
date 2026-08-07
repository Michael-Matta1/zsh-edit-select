# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# Absolute path to the compiled WSL selection agent binary.
typeset -g _EDIT_SELECT_MONITOR_BIN="$_EDIT_SELECT_PLUGIN_DIR/backends/wsl/zes-wsl-selection-agent"

# Self-write suppression: records the text most recently written to the
# clipboard by the plugin itself (copy/cut).  When the daemon detects
# the resulting clipboard change and writes it to cache, the shell
# compares the new content against this value and suppresses the event
# so it is not misidentified as a mouse selection.  Necessary because
# Windows has only a single CLIPBOARD (no PRIMARY) — copy operations
# and mouse selections share the same channel.
typeset -g _ZES_SELF_WRITE_CONTENT=""

# SSH mode flag — detected once at load time for zero per-call overhead.
# 1 = SSH session detected and OSC 52 clipboard passthrough is active.
# 0 = native clipboard backend in use (local session or user opt-out).
# ZES_SSH_CLIPBOARD=0 in ~/.zshrc before plugin load disables SSH mode.
typeset -gi _ZES_SSH_MODE=0
[[ "${ZES_SSH_CLIPBOARD:-1}" != "0" ]] && \
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] && \
    _ZES_SSH_MODE=1

# Start the background WSL selection agent and wait until it is ready.
# The agent writes a seq file on startup; presence of that file is the
# readiness signal — no fixed sleep, no polling the PID file.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    # Use -s (non-empty file) instead of -x for DrvFs mount compatibility
    # on WSL2 where the POSIX execute bit may not be set.
    [[ -s "$_EDIT_SELECT_MONITOR_BIN" ]] && [[ ! -x "$_EDIT_SELECT_MONITOR_BIN" ]] && chmod +x "$_EDIT_SELECT_MONITOR_BIN" 2>/dev/null || true
    if [[ ! -s "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        # Agent binary absent — fall back to powershell.exe for all clipboard ops.
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    # Ensure the cache directory exists.  `|| true`: the status is unobserved
    # (the tests below re-derive state from the filesystem), and a failed mkdir
    # must not abort before the readiness resolution at the end of this
    # function under an inherited err_return/err_exit — that would leave
    # _EDIT_SELECT_DAEMON_ACTIVE at its previous value with no daemon running.
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
    # signal.  Removal status is likewise unobserved — the wait loop tests file
    # presence — so it is guarded for the same reason as the mkdir above.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true

    # Launch the agent in a disowned background subshell so it persists
    # beyond shell exit without job-control noise.
    (
        "$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null || true
    )

    # Wait up to 1 second (40 × 25 ms) for the agent's pre-daemon cache
    # initialization to create the seq file.  This bounds startup waiting;
    # the PID file and Windows-helper handshake happen later in the child.
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

# Return the current PRIMARY (clipboard) selection text to stdout.
# When the daemon is active, the file read avoids forking a subprocess when
# an operation requests PRIMARY — zsh reads the file using a built-in redirection.
# Falls back to powershell.exe only when the daemon is not running.
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local primary_data
        { primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    powershell.exe -NoProfile -Command 'Get-Clipboard' 2>/dev/null
}

# Return the current clipboard text to stdout.
# On WSL, CLIPBOARD and PRIMARY are the same (Windows has only CLIPBOARD).
# Uses the agent's --get-clipboard mode to avoid spawning powershell.exe.
# In SSH mode (_ZES_SSH_MODE=1), returns 1 — paste via terminal native keybinding.
function _zes_get_clipboard() {
    ((_ZES_SSH_MODE)) && return 1
    if [[ -s "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --get-clipboard 2>/dev/null
    else
        powershell.exe -NoProfile -Command 'Get-Clipboard' 2>/dev/null
    fi
}

# Place $1 into the clipboard.  Records the written content in
# _ZES_SELF_WRITE_CONTENT so the next agent event for this same text
# is suppressed (self-write suppression).
# In SSH mode (_ZES_SSH_MODE=1), uses OSC 52 to tunnel the write to the local terminal.
# NOTE: _ZES_SELF_WRITE_CONTENT is intentionally NOT set in SSH mode — the write
# goes via OSC 52 and never reaches the Windows clipboard, so there is nothing to
# suppress. Setting it would cause the suppression logic in _zes_sync_selection_state
# to incorrectly swallow the next real mouse selection event.
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
    _ZES_SELF_WRITE_CONTENT="$1"
    # Capture the copy status in the OR-branch rather than from a following
    # `$?` assignment: under an inherited err_return/err_exit the failing
    # pipeline aborts the function before the assignment runs, so the rollback
    # below never executes and the marker stays set — suppressing the next real
    # mouse selection of this same text.  The initialiser carries the success
    # path (where the OR-branch does not run).
    local _zes_copy_rc=0
    if [[ -s "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        printf '%s' "$1" | "$_EDIT_SELECT_MONITOR_BIN" --copy-clipboard 2>/dev/null || _zes_copy_rc=$?
    else
        printf '%s' "$1" | clip.exe 2>/dev/null || _zes_copy_rc=$?
    fi
    # Roll back the self-write marker if the copy failed; otherwise a failed copy would
    # leave the marker set and suppress the next REAL mouse selection of the same text
    # (the WSLg round-trip that would have justified suppression never happened).
    (( _zes_copy_rc )) && _ZES_SELF_WRITE_CONTENT=""
    return $_zes_copy_rc
}

# Clear the PRIMARY cache.  Windows has no PRIMARY selection; this only
# clears the local cache files so the shell does not see stale text.
# The daemon is the sole owner of seq progression.  Clear only the primary
# cache here; advancing seq from a short-lived process can collide with the
# daemon's in-memory counter and hide the next selection event.
function _zes_clear_primary() {
    [[ -n "${_EDIT_SELECT_PRIMARY_FILE:-}" ]] && \
        : > "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true
}
