# Copyright (c) 2025 Michael Matta
# Version: 0.6.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# X11-only text selection and editing for Zsh command line.

# Load zsh/stat for zero-fork file stat via zstat, and zsh/datetime for
# EPOCHSECONDS / EPOCHREALTIME used in liveness probes and timing.
zmodload zsh/stat 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload zsh/datetime 2>/dev/null

# Selection tracking state.
# LAST_PRIMARY: last text written to the agent cache (used for change detection).
# ACTIVE_SELECTION: the selection text currently matched in BUFFER (deletion pending).
# PENDING_SELECTION: ambiguous selection awaiting cursor disambiguation.
typeset -g _EDIT_SELECT_LAST_PRIMARY=""
typeset -g _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g _EDIT_SELECT_PENDING_SELECTION=""
typeset -g _EDIT_SELECT_FOCUS_OUT_SEQ=""
# Public config: 1 enables mouse-selection-aware typing (type-to-replace); 0 disables.
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
# Path to the user's persistent configuration file (sourced at startup).
typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
# Absolute directory of this plugin file; used to locate backend scripts.
typeset -g _EDIT_SELECT_PLUGIN_DIR="${0:A:h}"
# Last-observed mtime of the seq file; compared on each ZLE callback to detect agent writes.
typeset -gi _EDIT_SELECT_LAST_MTIME=0
# Agent / detection state flags.
# DAEMON_ACTIVE: set when the selection agent process is confirmed running.
# NEW_SELECTION_EVENT: pulsed to 1 when a new mtime is detected; cleared after
#   one ZLE callback so the same change cannot fire the selection twice.
# EVENT_FIRED_FOR_MTIME: gate to avoid re-triggering on the same mtime.
# LAST_PID_CHECK: epoch seconds of the last kill -0 liveness probe.
# SELECTION_SET_TIME: EPOCHREALTIME when ACTIVE_SELECTION was last set.
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
typeset -gi _ZES_LAST_PID_CHECK=0
typeset -gF _ZES_SELECTION_SET_TIME=0
# Cache directory and file paths written by the selection agent.
# XDG_RUNTIME_DIR is preferred (tmpfs, private to UID on systemd systems);
# TMPDIR is a fallback for environments that do not set it.
typeset -g _EDIT_SELECT_CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${UID}"
typeset -g _EDIT_SELECT_SEQ_FILE="$_EDIT_SELECT_CACHE_DIR/seq"
typeset -g _EDIT_SELECT_PRIMARY_FILE="$_EDIT_SELECT_CACHE_DIR/primary"
typeset -g _EDIT_SELECT_PID_FILE="$_EDIT_SELECT_CACHE_DIR/agent.pid"
# Default key sequences (read-only).
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^V'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^X'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_COPY+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_COPY='^[[67;6u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_LEFT='^[[1;5D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT='^[[1;5C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT+x} ]]  && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT='^[[1;6D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT='^[[1;6C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_START+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_START='^[[1;6H'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_END+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_END='^[[1;6F'

# Apply default values for any key not explicitly set by the user.
function edit-select::apply-key-defaults() {
    EDIT_SELECT_KEY_SELECT_ALL="${EDIT_SELECT_KEY_SELECT_ALL:-$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL}"
    EDIT_SELECT_KEY_PASTE="${EDIT_SELECT_KEY_PASTE:-$_EDIT_SELECT_DEFAULT_KEY_PASTE}"
    EDIT_SELECT_KEY_CUT="${EDIT_SELECT_KEY_CUT:-$_EDIT_SELECT_DEFAULT_KEY_CUT}"
    EDIT_SELECT_KEY_COPY="${EDIT_SELECT_KEY_COPY:-$_EDIT_SELECT_DEFAULT_KEY_COPY}"
    EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
    EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
    EDIT_SELECT_KEY_WORD_LEFT="${EDIT_SELECT_KEY_WORD_LEFT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT}"
    EDIT_SELECT_KEY_WORD_RIGHT="${EDIT_SELECT_KEY_WORD_RIGHT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT}"
    EDIT_SELECT_KEY_SEL_WORD_LEFT="${EDIT_SELECT_KEY_SEL_WORD_LEFT:-$_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT}"
    EDIT_SELECT_KEY_SEL_WORD_RIGHT="${EDIT_SELECT_KEY_SEL_WORD_RIGHT:-$_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT}"
    EDIT_SELECT_KEY_BUFFER_START="${EDIT_SELECT_KEY_BUFFER_START:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START}"
    EDIT_SELECT_KEY_BUFFER_END="${EDIT_SELECT_KEY_BUFFER_END:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END}"
}

# Source user config and apply defaults.
function edit-select::load-config() {
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
    edit-select::apply-key-defaults
}

# Clear all in-flight selection state after a paste or cut operation.
# Clearing LAST_PRIMARY prevents the just-consumed selection from being
# re-detected on the next ZLE callback.  _zes_clear_primary instructs the
# agent to wipe the PRIMARY cache so a subsequent selection starts fresh.
function _zes_sync_after_paste() {
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _EDIT_SELECT_FOCUS_OUT_SEQ=""
    _zes_clear_primary
}

# Determine whether a mouse text selection is currently active and populate
# _EDIT_SELECT_ACTIVE_SELECTION if so.  Returns 0 when a selection is active.
#
# State machine:
#   is_new_selection=1  A NEW_SELECTION_EVENT arrived; the selection is matched
#                       against BUFFER and recorded as ACTIVE if found.
#   PENDING_SELECTION   The selection text appears more than once in BUFFER;
#                       the cursor position will disambiguate which occurrence
#                       the user intends to modify.
function _zes_detect_mouse_selection() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return 1
    if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        if ((!_EDIT_SELECT_NEW_SELECTION_EVENT)) && [[ -n "$_EDIT_SELECT_LAST_PRIMARY" ]] && [[ "$_EDIT_SELECT_LAST_PRIMARY" == "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && [[ "$BUFFER" == *"$_EDIT_SELECT_ACTIVE_SELECTION"* ]]; then
            return 0
        fi
        _EDIT_SELECT_ACTIVE_SELECTION=""
        return 1
    fi

    local mouse_sel
    local is_new_selection=0

    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        if ((_EDIT_SELECT_NEW_SELECTION_EVENT)); then
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            is_new_selection=1
            mouse_sel="$_EDIT_SELECT_LAST_PRIMARY"
        else
            mouse_sel="$_EDIT_SELECT_LAST_PRIMARY"
        fi

        [[ -z "$mouse_sel" ]] && return 1
    else
        return 1
    fi

    if ((is_new_selection)); then
        _EDIT_SELECT_LAST_PRIMARY="$mouse_sel"
        _EDIT_SELECT_FOCUS_OUT_SEQ=""

        if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            zle -M ""
            zle -R
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        if [[ -n "$mouse_sel" ]] && ((${#mouse_sel} <= ${#BUFFER})) && [[ "$BUFFER" == *"$mouse_sel"* ]]; then
            _EDIT_SELECT_ACTIVE_SELECTION="$mouse_sel"
            _ZES_SELECTION_SET_TIME=$EPOCHREALTIME
            return 0
        fi
        return 1
    fi

    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        local sel="$_EDIT_SELECT_PENDING_SELECTION" sel_len=${#_EDIT_SELECT_PENDING_SELECTION}
        if [[ "$BUFFER" == *"$sel"* ]]; then
            local idx=0
            while ((idx <= ${#BUFFER} - sel_len)); do
                if [[ "${BUFFER:$idx:$sel_len}" == "$sel" ]]; then
                    local end_pos=$((idx + sel_len))
                    if ((CURSOR >= idx && CURSOR <= end_pos)); then
                        _EDIT_SELECT_ACTIVE_SELECTION="$sel"
                        _EDIT_SELECT_PENDING_SELECTION=""
                        zle -M ""
                        zle -R
                        return 0
                    fi
                    ((idx += sel_len))
                else
                    ((idx++))
                fi
            done
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_LAST_PRIMARY=""
        _zes_clear_primary
        zle -M ""
        zle -R
    fi

    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -n "$_EDIT_SELECT_FOCUS_OUT_SEQ" ]]; then
        local curr_seq
        curr_seq=$(<"$_EDIT_SELECT_SEQ_FILE" 2>/dev/null)
        if [[ -n "$curr_seq" ]] && [[ "$curr_seq" == "$_EDIT_SELECT_LAST_MTIME" ]] && [[ "$curr_seq" != "$_EDIT_SELECT_FOCUS_OUT_SEQ" ]]; then
            mouse_sel=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
            if [[ -n "$mouse_sel" ]] && ((${#mouse_sel} <= ${#BUFFER})) && [[ "$BUFFER" == *"$mouse_sel"* ]]; then
                _EDIT_SELECT_LAST_PRIMARY="$mouse_sel"
                _EDIT_SELECT_ACTIVE_SELECTION="$mouse_sel"
                _EDIT_SELECT_PENDING_SELECTION=""
                _EDIT_SELECT_FOCUS_OUT_SEQ=""
                _ZES_SELECTION_SET_TIME=$EPOCHREALTIME
                return 0
            fi
        fi
    fi

    return 1
}

# Called by ZLE widgets before acting on a keypress.
# Reads the seq file's mtime via zstat (one stat syscall, no fork) to detect
# whether the agent has written a new PRIMARY selection since the last check.
# EVENT_FIRED_FOR_MTIME prevents the same mtime update from triggering more
# than once: the first ZLE callback fires the selection event; subsequent
# callbacks at the same mtime suppress it until the next real agent write.
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

    local curr_seq=""
    curr_seq=$(<"$_EDIT_SELECT_SEQ_FILE" 2>/dev/null)
    [[ -z "$curr_seq" ]] && return

    if [[ "$curr_seq" != "$_EDIT_SELECT_LAST_MTIME" ]]; then
        _EDIT_SELECT_LAST_MTIME="$curr_seq"
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
        local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        _EDIT_SELECT_LAST_PRIMARY="$new_primary"

        if [[ -n "$new_primary" ]]; then
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
            _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
        else
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            _ZES_SELECTION_SET_TIME=0
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
        fi
    else
        if ((_EDIT_SELECT_EVENT_FIRED_FOR_MTIME)); then
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _ZES_SELECTION_SET_TIME=0
            fi
        fi
    fi
}

# Remove the active mouse selection from BUFFER at the occurrence closest to
# CURSOR.  If the text appears exactly once it is deleted unconditionally.
# If it appears multiple times, the occurrence that contains CURSOR is deleted;
# if no occurrence contains the cursor, PENDING_SELECTION is set and the user
# is prompted to position the cursor inside their intended occurrence.
function _zes_delete_mouse_selection() {
    [[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1

    local sel="$_EDIT_SELECT_ACTIVE_SELECTION" sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
    ((sel_len > ${#BUFFER})) && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
        return 1
    }
    [[ "$BUFFER" != *"$sel"* ]] && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
        return 1
    }

    local -a positions=()
    local buf="$BUFFER" idx=0
    while ((idx <= ${#buf} - sel_len)); do
        if [[ "${buf:$idx:$sel_len}" == "$sel" ]]; then
            positions+=($idx)
            ((idx += sel_len))
        else
            ((idx++))
        fi
    done

    local num_occurrences=${#positions[@]}
    local target_pos=-1

    if ((num_occurrences > 1)); then
        local pos end_pos
        for pos in "${positions[@]}"; do
            end_pos=$((pos + sel_len))
            if ((CURSOR >= pos && CURSOR <= end_pos)); then
                target_pos=$pos
                break
            fi
        done
    else
        target_pos=${positions[1]}
    fi

    if ((target_pos >= 0)); then
        BUFFER="${BUFFER:0:$target_pos}${BUFFER:$((target_pos + sel_len))}"
        CURSOR=$target_pos
        REGION_ACTIVE=0
        _zes_sync_after_paste
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
        zle deactivate-region -w 2>/dev/null
        zle -K main 2>/dev/null
        return 0
    fi

    zle -M "Duplicate text: place cursor inside the occurrence you want to modify"
    _EDIT_SELECT_PENDING_SELECTION="$_EDIT_SELECT_ACTIVE_SELECTION"
    _EDIT_SELECT_ACTIVE_SELECTION=""
    return 1
}

# Select the entire command-line buffer and activate the edit-select keymap.
function edit-select::select-all() {
    MARK=0
    CURSOR=${#BUFFER}
    REGION_ACTIVE=1
    zle -K edit-select
}
# Register select-all as a ZLE widget.
zle -N edit-select::select-all

# Kill the active ZLE region and return to the main keymap.
function _zes_delete_selected_region() {
    zle kill-region -w
    zle -K main
}
# Register kill-region widget backed by _zes_delete_selected_region.
zle -N edit-select::kill-region _zes_delete_selected_region

# Backspace handler: delete mouse selection if active, else backward-delete-char.
function edit-select::delete-mouse-or-backspace() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle backward-delete-char -w
}
# Register as ZLE widget for binding to Backspace.
zle -N edit-select::delete-mouse-or-backspace

# Delete-key handler: delete mouse selection if active, else delete-char.
function edit-select::delete-mouse-or-delete() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle delete-char -w
}
# Register as ZLE widget for binding to Delete.
zle -N edit-select::delete-mouse-or-delete

# Self-insert override: delete active mouse selection then insert the typed
# character (type-to-replace).  Blocks input during pending disambiguation.
function edit-select::handle-char() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w
                return
            fi
            # Block typing on failure (e.g. disambiguation pending).
            return
        fi
    fi
    zle self-insert -w
}
# Register as ZLE widget; bound to printable chars in emacs keymap.
zle -N edit-select::handle-char

# Deactivate the ZLE region, return to main keymap, and replay the
# triggering keystrokes.
function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w
    zle -K main
    zle -U -- "$KEYS"
}
# Register deselect-and-input as default handler in edit-select keymap.
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

# If a keyboard region is selected, delete it and insert the typed char;
# else self-insert.
function edit-select::replace-selection() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
        zle self-insert -w
        return
    fi
    zle self-insert -w
}
# Register as ZLE widget; bound to printable chars in edit-select keymap.
zle -N edit-select::replace-selection

# Copy the active keyboard region (or PRIMARY selection) to the system
# clipboard, then deselect.
function edit-select::copy-region() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}"
        _zes_sync_after_paste
        zle deactivate-region -w
        zle -K main
    else
        local primary_sel
        primary_sel=$(_zes_get_primary) || return
        _zes_copy_to_clipboard "$primary_sel"
        _zes_sync_after_paste
    fi
}
# Register copy-region as a ZLE widget (Ctrl+Shift+C).
zle -N edit-select::copy-region

# Copy the active keyboard/mouse selection to clipboard and delete it.
function edit-select::cut-region() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}"
        _zes_sync_after_paste
        zle kill-region -w
        zle -K main
    else
        ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            local sel="$_EDIT_SELECT_ACTIVE_SELECTION"
            _zes_copy_to_clipboard "$sel" && _zes_delete_mouse_selection
        fi
    fi
}
# Register cut-region as a ZLE widget (Ctrl+X).
zle -N edit-select::cut-region

# Paste system clipboard into BUFFER; replaces active selection first if present.
function edit-select::paste-clipboard() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            _zes_delete_mouse_selection || return
        fi
    fi
    local clipboard_content
    clipboard_content=$(_zes_get_clipboard) || return
    [[ -n "$clipboard_content" ]] && LBUFFER="${LBUFFER}${clipboard_content}"
    _zes_sync_after_paste
}
# Register paste-clipboard as a ZLE widget (Ctrl+V).
zle -N edit-select::paste-clipboard

# Handle bracketed-paste: replace active selection then insert pasted text.
function edit-select::bracketed-paste-replace() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            _zes_delete_mouse_selection || return
        fi
    fi
    # Invoke the built-in .bracketed-paste (dot-prefix bypasses user overrides).
    zle .bracketed-paste
    _zes_sync_after_paste
}
# Register bracketed-paste-replace as a ZLE widget.
zle -N edit-select::bracketed-paste-replace

# Lightweight movement widgets: move cursor to absolute buffer boundaries.
# Used by nav_bind so that _zes_activate_region_and_dispatch can dispatch
# them by name, the same way it dispatches built-in widgets like
# beginning-of-line or forward-word.
function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

# Wrapper for shift-arrow navigation: start a selection if none, switch to
# edit-select keymap, dispatch the cursor-movement widget.
function _zes_activate_region_and_dispatch() {
    # Dismiss any active completion menu before starting selection.
    zle -c
    if ((!REGION_ACTIVE)); then
        zle set-mark-command -w
        zle -K edit-select
    fi
    zle "${WIDGET#edit-select::}" -w
}

# Terminal focus-in handler: when this pane gains focus, sync the seq-file
# mtime as "already seen" so that selection events from other panes are
# not mistakenly treated as new.  Requires the terminal (or tmux with
# `focus-events on`) to send CSI I / CSI O focus sequences.  Terminals
# that do not support DECSET 1004 silently ignore the enable request and
# these widgets simply never fire — no regression in that case.
function _zes_terminal_focus_in() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local curr_seq
        curr_seq=$(<"$_EDIT_SELECT_SEQ_FILE" 2>/dev/null)
        if [[ -n "$curr_seq" ]]; then
            _EDIT_SELECT_LAST_MTIME="$curr_seq"
            _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
        fi
    fi
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
}
zle -N _zes_terminal_focus_in

# Terminal focus-out handler: no-op widget that consumes the CSI O
# escape sequence so it is not interpreted as keystrokes.
function _zes_terminal_focus_out() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        _EDIT_SELECT_FOCUS_OUT_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE" 2>/dev/null)
    fi
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
}
zle -N _zes_terminal_focus_out



# ZLE hook: called before every prompt redraw.  Must be fast — no forks.
# Detects PRIMARY selection changes via seq-file mtime (one stat syscall).
# Daemon liveness is checked at most once every 30 s to avoid a kill -0 on
# every keypress; if the agent has died it is restarted automatically.
function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return

    # Fast path: daemon is running, use mtime-based change detection
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Liveness probe: at most once every 30 s to amortise syscall overhead.
        if ((EPOCHSECONDS > _ZES_LAST_PID_CHECK + 30)); then
            _ZES_LAST_PID_CHECK=$EPOCHSECONDS
            local pid
            [[ -r "$_EDIT_SELECT_PID_FILE" ]] && pid=$(<"$_EDIT_SELECT_PID_FILE")
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                _EDIT_SELECT_DAEMON_ACTIVE=0
                _zes_start_monitor
                return
            fi
        fi

        # zstat reads mtime in a single stat() syscall, avoiding a file read
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || {
            _EDIT_SELECT_DAEMON_ACTIVE=0
            return
        }

        # New mtime: agent wrote a selection change.  Read the primary and signal it.
        if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
            _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
        else
            # Same mtime: no new agent write.  Clear any active selection so
            # stale highlights don't persist across multiple keystrokes.
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
            fi
        fi
        return
    fi
}

function _zes_enable_focus_reporting() {
    printf '\e[?1004h' >/dev/tty 2>/dev/null
    add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting 2>/dev/null
}
zle -N _zes_enable_focus_reporting

# Apply keybindings and ZLE hook registration to reflect the current value of
# EDIT_SELECT_MOUSE_REPLACEMENT.  Called once at startup and again when the
# configuration wizard changes the setting.  When the feature is disabled,
# all custom bindings are reverted to their ZLE defaults.
function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        _zes_start_monitor
        add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
        # Enable terminal focus reporting (DECSET 1004) and bind focus
        # event handlers so cross-pane selection changes are suppressed.
        # Deferred to the first ZLE prompt via zle-line-init so that the
        # terminal's immediate CSI I reply is consumed by the already-bound
        # widgets instead of printing as raw ^[[I on VTE-based terminals.
        add-zle-hook-widget zle-line-init _zes_enable_focus_reporting
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
    else
        bindkey -M emacs -R ' '-'~' self-insert
        bindkey -M emacs '^?' backward-delete-char
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
        bindkey -M emacs '^[[200~' bracketed-paste
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        add-zle-hook-widget -d line-pre-redraw edit-select::zle-line-pre-redraw 2>/dev/null
        add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting 2>/dev/null
        printf '\e[?1004l' >/dev/tty 2>/dev/null
        bindkey -M emacs -r '\e[I' 2>/dev/null
        bindkey -M emacs -r '\e[O' 2>/dev/null
        bindkey -r '\e[I' 2>/dev/null
        bindkey -r '\e[O' 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
    fi
}

# Public CLI entry-point.  Dispatches subcommands ("conf"/"config" → wizard).
function edit-select() {
    if [[ $1 == conf || $1 == config ]]; then
        local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/../../edit-select-wizard-wsl.zsh"
        if [[ -f "$wizard_file" ]]; then
            source "$wizard_file" 2>/dev/null || {
                print -u2 "Error: Failed to load configuration wizard"
                return 1
            }
            edit-select::config-wizard
        else
            print -u2 "Error: Configuration wizard not found at: $wizard_file"
            return 1
        fi
    else
        print "edit-select - Text selection and clipboard management for Zsh"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
    fi
}

# Load the X11-specific clipboard backend (agent start/stop,
# get/set primary/clipboard).
source "$_EDIT_SELECT_PLUGIN_DIR/../../../impl-x11/backends/x11/x11.zsh"

# Migrate config files written by 0.4.x and earlier that stored
# EDIT_SELECT_MOUSE_REPLACEMENT as the strings "enabled"/"disabled".
# Rewrite them to integers so subsequent sourcing reads cleanly.
if [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]]; then
    local _zes_cfg=$(<"$_EDIT_SELECT_CONFIG_FILE")
    local _zes_cfg_changed=0
    local _zes_keys_changed=0

    if [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="enabled"'* ]] ||
        [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="disabled"'* ]]; then
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"enabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=1}"
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"disabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=0}"
        _zes_cfg_changed=1
    fi

    if [[ "$_zes_cfg" == *'EDIT_SELECT_KEY_SELECT_ALL="^[[65;5u"'* ]] || \
       [[ "$_zes_cfg" == *'EDIT_SELECT_KEY_PASTE="^[[86;5u"'* ]]   || \
       [[ "$_zes_cfg" == *'EDIT_SELECT_KEY_CUT="^[[88;5u"'* ]]; then
        _zes_cfg="${_zes_cfg//EDIT_SELECT_KEY_SELECT_ALL=\"^[[65;5u\"/EDIT_SELECT_KEY_SELECT_ALL=\"^[[65;6u\"}"
        _zes_cfg="${_zes_cfg//EDIT_SELECT_KEY_PASTE=\"^[[86;5u\"/EDIT_SELECT_KEY_PASTE=\"^[[86;6u\"}"
        _zes_cfg="${_zes_cfg//EDIT_SELECT_KEY_CUT=\"^[[88;5u\"/EDIT_SELECT_KEY_CUT=\"^[[88;6u\"}"
        _zes_cfg_changed=1
        _zes_keys_changed=1
    fi

    if ((_zes_cfg_changed)); then
        print -r -- "$_zes_cfg" >"$_EDIT_SELECT_CONFIG_FILE"
    fi
    if ((_zes_keys_changed)); then
        unset EDIT_SELECT_KEY_SELECT_ALL EDIT_SELECT_KEY_PASTE EDIT_SELECT_KEY_CUT
    fi
fi

# Read user config and populate undo/redo key bindings.
edit-select::load-config

# Establish the edit-select keymap and all related bindings inside an anonymous
# function so that the local loop variables do not pollute the global scope.
# nav_bind entries are triples: terminfo-key, fallback-escape, widget-name.
# terminfo is preferred so the correct sequences are used for each terminal;
# the hardcoded fallback handles terminals that do not report via terminfo.
function { emulate -L zsh
    # Create a new "edit-select" keymap for active-selection mode.
    bindkey -N edit-select
    # Default: any control character deselects and replays into main keymap.
    bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
    # Any printable character replaces the current selection.
    bindkey -M edit-select -R ' '-'~' edit-select::replace-selection

    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char'
        'kRIT' '^[[1;2C' 'forward-char'
        'kri' '^[[1;2A' 'up-line'
        'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line'
        'kEND' '^[[1;2F' 'end-of-line'
        # Ctrl+Shift modified keys for extended selection.
        # Ctrl+Shift+Home / End  → beginning / end-of-buffer
        # Ctrl+Shift+Left / Right  → backward / forward-word
        '' "$EDIT_SELECT_KEY_BUFFER_START" 'beginning-of-buffer'
        '' "$EDIT_SELECT_KEY_BUFFER_END" 'end-of-buffer'
        '' "$EDIT_SELECT_KEY_SEL_WORD_LEFT" 'backward-word'
        '' "$EDIT_SELECT_KEY_SEL_WORD_RIGHT" 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}; esc=${nav_bind[i + 1]}; wid=${nav_bind[i + 2]}
        [[ -z "$esc" ]] && continue
        seq=${terminfo[$ti]:-$esc}
        zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs "$seq" "edit-select::${wid}"
        bindkey -M edit-select "$seq" "edit-select::${wid}"
    done

    local -a dest_bind=(
        'kdch1' '^[[3~' 'edit-select::kill-region'
        'bs' '^?' 'edit-select::kill-region'
    )
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}
        bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    [[ -n "$EDIT_SELECT_KEY_CUT" ]]  && bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    bindkey -M edit-select '^[[200~' edit-select::bracketed-paste-replace

    [[ -n "$EDIT_SELECT_KEY_SELECT_ALL" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
    [[ -n "$EDIT_SELECT_KEY_COPY" ]]       && bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    if [[ -n "$EDIT_SELECT_KEY_CUT" ]]; then
        bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
        bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    fi

    [[ -n "$EDIT_SELECT_KEY_WORD_LEFT" ]]  && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_LEFT" backward-word
    [[ -n "$EDIT_SELECT_KEY_WORD_RIGHT" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_RIGHT" forward-word

    bindkey -M edit-select '\e[I' _zes_terminal_focus_in
    bindkey -M edit-select '\e[O' _zes_terminal_focus_out
}

# Undo/redo widgets: reuse native ZLE undo with keymap integration.
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# Normalise any residual string value that may still be in the live env.
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# Pre-populate LAST_PRIMARY and LAST_MTIME before the first ZLE callback fires
# so the initial redraw does not see a spurious empty-to-non-empty transition.
if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        local -a _zes_init_st
        zstat -A _zes_init_st +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && _EDIT_SELECT_LAST_MTIME=${_zes_init_st[1]}
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
    fi
fi

# Activate or deactivate mouse-replacement bindings based on the final
# normalised setting.
edit-select::apply-mouse-replacement-config
