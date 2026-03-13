# Copyright (c) 2025 Michael Matta
# Version: 0.6.1
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland-native text selection and editing for Zsh command line.

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
typeset -gi _ZES_MOUSE_SELECTION_START=-1
typeset -gi _ZES_MOUSE_SELECTION_LEN=0
# Cache directory and file paths written by the selection agent.
# XDG_RUNTIME_DIR is preferred (tmpfs, private to UID on systemd systems);
# TMPDIR is a fallback for environments that do not set it.
typeset -g _EDIT_SELECT_CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${UID}"
typeset -g _EDIT_SELECT_SEQ_FILE="$_EDIT_SELECT_CACHE_DIR/seq"
typeset -g _EDIT_SELECT_PRIMARY_FILE="$_EDIT_SELECT_CACHE_DIR/primary"
typeset -g _EDIT_SELECT_PID_FILE="$_EDIT_SELECT_CACHE_DIR/agent.pid"
# Default undo/redo key sequences (read-only).  The +x test allows a
# previously defined value to persist across re-source.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'

# Source user config and apply compiled-in defaults for any key not explicitly
# set.  Defaults are declared read-only above so they cannot be overridden by
# the config file; user values shadow them via the := operator.
function edit-select::load-config() {
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
    EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
    EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
}

# Clear all in-flight selection state after a paste or cut operation.
# Clearing LAST_PRIMARY prevents the just-consumed selection from being
# re-detected on the next ZLE callback.  After clearing, LAST_PRIMARY is
# re-synced from the cache (daemon path) or re-read directly so that the
# next mtime-change comparison has a current baseline; without this re-read
# the agent's next write would not produce a detectable mtime difference.
function _zes_sync_after_paste() {
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _ZES_SELECTION_SET_TIME=0
    _EDIT_SELECT_LAST_PRIMARY=""
    _ZES_MOUSE_SELECTION_START=-1
    _ZES_MOUSE_SELECTION_LEN=0
    _zes_clear_primary
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
    else
        local current_primary
        current_primary=$(_zes_get_primary 2>/dev/null) && _EDIT_SELECT_LAST_PRIMARY="$current_primary"
    fi
}

# Called by ZLE widgets before acting on a keypress.
# Reads the seq file's mtime via zstat (one stat syscall, no fork) to detect
# whether the agent has written a new PRIMARY selection since the last check.
# EVENT_FIRED_FOR_MTIME prevents the same mtime update from triggering more
# than once: the first ZLE callback fires the selection event; subsequent
# callbacks at the same mtime suppress it until the next real agent write.
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

    # In WSL tracking mode, selection is owned by ZLE mouse tracking state.
    # Ignore daemon clipboard/PRIMARY sync events to avoid re-arming a
    # just-consumed duplicate selection on the next keypress.
    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        return
    fi

    local -a stat_info
    zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || return

    if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
        # New mtime: agent wrote a new primary value.  Read and record it.
        _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
        local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        _EDIT_SELECT_LAST_PRIMARY="$new_primary"

        if [[ -n "$new_primary" ]]; then
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
            _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
        else
            # Empty primary: selection was cleared (e.g. after paste).
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            _ZES_SELECTION_SET_TIME=0
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
        fi
    else
        if ((_EDIT_SELECT_EVENT_FIRED_FOR_MTIME)); then
            # Same mtime: event already fired; suppress until next agent write.
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _ZES_SELECTION_SET_TIME=0
            fi
        fi
    fi
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

    # In WSL tracking mode, selection comes from in-shell mouse tracking.
    # Do not fall back to daemon-reported clipboard/PRIMARY changes.
    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && ((_ZES_MOUSE_SELECTION_START >= 0)) && ((_ZES_MOUSE_SELECTION_LEN > 0)); then
            if ((_ZES_MOUSE_SELECTION_START + _ZES_MOUSE_SELECTION_LEN <= ${#BUFFER})) && [[ "${BUFFER:$_ZES_MOUSE_SELECTION_START:$_ZES_MOUSE_SELECTION_LEN}" == "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                return 0
            fi
        fi
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _ZES_MOUSE_SELECTION_START=-1
        _ZES_MOUSE_SELECTION_LEN=0
        return 1
    fi

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

        # Self-write suppression (WSL CLIPBOARD monitoring):  when the
        # plugin copies text to the clipboard, WSLg round-trips it back
        # as an X11 CLIPBOARD change.  If the detected text matches what
        # we just wrote, suppress it — it is not a mouse selection.
        if [[ -n "$_ZES_SELF_WRITE_CONTENT" ]] && [[ "$mouse_sel" == "$_ZES_SELF_WRITE_CONTENT" ]]; then
            _ZES_SELF_WRITE_CONTENT=""
            return 1
        fi
    else
        return 1
    fi

    if ((is_new_selection)); then
        _EDIT_SELECT_LAST_PRIMARY="$mouse_sel"

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

    return 1
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

    # In WSL tracking mode, prefer the exact range produced by the custom
    # mouse tracker to avoid ambiguity when duplicate text exists.
    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        if ((_ZES_MOUSE_SELECTION_START >= 0)) && ((_ZES_MOUSE_SELECTION_LEN > 0)); then
            local exact_start=$_ZES_MOUSE_SELECTION_START
            local exact_len=$_ZES_MOUSE_SELECTION_LEN
            if ((exact_start + exact_len <= ${#BUFFER})) && [[ "${BUFFER:$exact_start:$exact_len}" == "$sel" ]]; then
                BUFFER="${BUFFER:0:$exact_start}${BUFFER:$((exact_start + exact_len))}"
                CURSOR=$exact_start
                _ZES_MOUSE_SELECTION_START=-1
                _ZES_MOUSE_SELECTION_LEN=0
                REGION_ACTIVE=0
                _zes_sync_after_paste
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
                _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
                zle deactivate-region -w 2>/dev/null
                zle -K main 2>/dev/null
                return 0
            fi
        fi
    fi

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

# Select the entire command-line buffer (MARK=0, CURSOR=end) and activate
# the edit-select keymap so subsequent navigation extends the selection.
function edit-select::select-all() {
    MARK=0
    CURSOR=${#BUFFER}
    REGION_ACTIVE=1
    zle -K edit-select
}
# Register select-all as a ZLE widget.
zle -N edit-select::select-all

# Clear all active visual/mouse selection state.
function _zes_clear_selection_state() {
    REGION_ACTIVE=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _ZES_MOUSE_SELECTION_START=-1
    _ZES_MOUSE_SELECTION_LEN=0
    _ZES_SELECTION_SET_TIME=0
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
    _zes_clear_primary
    zle deactivate-region -w 2>/dev/null
    zle -K main 2>/dev/null
}

# Ctrl+C handler for the emacs keymap: copy the region to clipboard when
# a selection is active (desktop UX); otherwise send a normal interrupt.
function edit-select::copy-or-interrupt() {
    if ((REGION_ACTIVE)); then
        # Delegate to copy-region
        zle edit-select::copy-region
    elif [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        _zes_copy_to_clipboard "$_EDIT_SELECT_ACTIVE_SELECTION" || {
            zle -M "Copy failed: clipboard unavailable"
            return
        }
        _zes_clear_selection_state
    else
        # No selection active: send interrupt (Ctrl+C default behavior)
        _zes_clear_selection_state
        zle send-break
    fi
}
zle -N edit-select::copy-or-interrupt

# Kill the active ZLE region and return to the main keymap.
# Used as the backing function for the edit-select::kill-region widget.
function _zes_delete_selected_region() {
    zle kill-region -w
    zle -K main
}
# Register kill-region widget backed by _zes_delete_selected_region.
zle -N edit-select::kill-region _zes_delete_selected_region

# Backspace handler: if a mouse selection is active, delete it instead of
# the character behind the cursor; otherwise fall through to backward-delete-char.
function edit-select::delete-mouse-or-backspace() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c

    _zes_resume_tracking_if_needed

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

# Delete-key handler: if a mouse selection is active, delete it; otherwise
# fall through to delete-char.
function edit-select::delete-mouse-or-delete() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c

    _zes_resume_tracking_if_needed

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

# Self-insert override: delete the active mouse selection then insert the
# typed character (type-to-replace behavior).  Blocks input when a
# pending disambiguation is active.
function edit-select::handle-char() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c

    _zes_resume_tracking_if_needed

    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w
                return
            fi
            # Block typing on failure
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle self-insert -w
}
# Register as ZLE widget; bound to printable chars in emacs keymap.
zle -N edit-select::handle-char

# Deactivate the ZLE region, return to the main keymap, and replay the
# keystrokes that caused the widget to fire so they are processed normally.
function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w
    zle -K main
    zle -U -- "$KEYS"
}
# Register deselect-and-input widget; bound to all keys in edit-select
# keymap as default handler.
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

# If a keyboard region is selected, delete it and insert the typed
# character.  Otherwise forward to self-insert unchanged.
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
# clipboard, then deselect and return to the main keymap.
function edit-select::copy-region() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        local text="${BUFFER:$start:$length}"
        if ! _zes_copy_to_clipboard "$text"; then
            zle -M "Copy failed: clipboard unavailable"
            return
        fi
        _zes_sync_after_paste
        zle deactivate-region -w
        zle -K main
    else
        local primary_sel
        primary_sel=$(_zes_get_primary) || return
        if ! _zes_copy_to_clipboard "$primary_sel"; then
            zle -M "Copy failed: clipboard unavailable"
            return
        fi
        _zes_sync_after_paste
    fi
}
# Register copy-region as a ZLE widget (Ctrl+Shift+C).
zle -N edit-select::copy-region

# Copy and delete the active keyboard region.  When no region is active,
# cut the mouse-selected text instead.
function edit-select::cut-region() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        local text="${BUFFER:$start:$length}"
        if ! _zes_copy_to_clipboard "$text"; then
            zle -M "Cut failed: clipboard unavailable"
            return
        fi
        _zes_sync_after_paste
        zle kill-region -w
        zle -K main
    else
        ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            local sel="$_EDIT_SELECT_ACTIVE_SELECTION"
            if _zes_copy_to_clipboard "$sel"; then
                _zes_delete_mouse_selection
            else
                zle -M "Cut failed: clipboard unavailable"
            fi
        fi
    fi
}
# Register cut-region as a ZLE widget (Ctrl+X).
zle -N edit-select::cut-region

# Paste the system clipboard into BUFFER.  Replaces the active keyboard
# region or mouse selection first if either is present.
function edit-select::paste-clipboard() {
    _zes_resume_tracking_if_needed
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
            if _zes_delete_mouse_selection; then
                # Deletion succeeded; fall through to paste below.
                :
            else
                # Deletion failed (e.g. disambiguation pending); abort paste.
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    local clipboard_content
    clipboard_content=$(_zes_get_clipboard) || return
    [[ -n "$clipboard_content" ]] && LBUFFER="${LBUFFER}${clipboard_content}"
    _zes_sync_after_paste
}
# Register paste-clipboard as a ZLE widget (Ctrl+V).
zle -N edit-select::paste-clipboard

# Handle bracketed-paste events from the terminal.  Replaces any active
# keyboard region or mouse selection before inserting the pasted text.
function edit-select::bracketed-paste-replace() {
    _zes_resume_tracking_if_needed
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
            if _zes_delete_mouse_selection; then
                # Deletion succeeded; fall through to paste below.
                :
            else
                # Deletion failed (e.g. disambiguation pending); abort paste.
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    # Invoke the built-in .bracketed-paste (dot-prefix bypasses user overrides).
    zle .bracketed-paste
    _zes_sync_after_paste
}
# Register bracketed-paste-replace as a ZLE widget (^[[200~ escape).
zle -N edit-select::bracketed-paste-replace

# Lightweight movement widgets: move cursor to absolute buffer boundaries.
# Used by nav_bind so that _zes_activate_region_and_dispatch can dispatch
# them by name, the same way it dispatches built-in widgets like
# beginning-of-line or forward-word.
function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

# Wrapper for shift-arrow navigation widgets: start a new selection if
# none is active, switch to the edit-select keymap, then dispatch the
# underlying cursor-movement widget.
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
        local -a stat_info
        if zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null; then
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
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
    :
}
zle -N _zes_terminal_focus_out

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
        '' '^[[1;6H' 'beginning-of-buffer'
        '' '^[[1;6F' 'end-of-buffer'
        '' '^[[1;6D' 'backward-word'
        '' '^[[1;6C' 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}
        esc=${nav_bind[i + 1]}
        wid=${nav_bind[i + 2]}
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

    # Clipboard operations in both edit-select and emacs keymaps.
    # Ctrl+Shift+C  → copy
    bindkey -M edit-select '^[[67;6u' edit-select::copy-region
    # Ctrl+C  → copy (when region active, this overrides the catch-all
    # deselect-and-input binding so that Ctrl+C copies like desktop UX).
    bindkey -M edit-select '^C' edit-select::copy-region
    # Ctrl+X  → cut
    bindkey -M edit-select '^X' edit-select::cut-region
    bindkey -M edit-select '^[[200~' edit-select::bracketed-paste-replace
    # Ctrl+A  → select-all (emacs keymap)
    bindkey -M emacs '^A' edit-select::select-all
    # Ctrl+Shift+C  → copy (emacs keymap)
    bindkey -M emacs '^[[67;6u' edit-select::copy-region
    # Ctrl+C  → copy if selection active, otherwise interrupt (emacs keymap)
    bindkey -M emacs '^C' edit-select::copy-or-interrupt
    # Ctrl+X  → cut (emacs keymap)
    bindkey -M emacs '^X' edit-select::cut-region
    # Ctrl+X  → cut (main keymap)
    bindkey '^X' edit-select::cut-region
    # Ctrl+Shift+M  → toggle WSL mouse mode (terminal <-> tracking)
    bindkey -M emacs '^[[77;6u' edit-select::toggle-mouse-mode-widget
    bindkey -M edit-select '^[[77;6u' edit-select::toggle-mouse-mode-widget

    # Word navigation in emacs keymap.
    # Ctrl+Left  → backward-word
    bindkey -M emacs '^[[1;5D' backward-word
    # Ctrl+Right  → forward-word
    bindkey -M emacs '^[[1;5C' forward-word

    # Terminal focus events in edit-select keymap — suppress stale
    # cross-pane selection events.
    bindkey -M edit-select '\e[I' _zes_terminal_focus_in
    bindkey -M edit-select '\e[O' _zes_terminal_focus_out
}

# ZLE hook: called before every prompt redraw.  Must be fast — no forks.
# Detects PRIMARY selection changes via seq-file mtime (one stat syscall).
# Daemon liveness is checked at most once every 30 s to avoid a kill -0 on
# every keypress; if the agent has died it is restarted automatically.
function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return

    # In WSL tracking mode, avoid daemon clipboard/PRIMARY event ingestion;
    # selection changes are produced directly by mouse tracking widgets.
    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        return
    fi

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

        # zstat reads mtime in a single stat() syscall, avoiding a file read.
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || {
            _EDIT_SELECT_DAEMON_ACTIVE=0
            return
        }

        if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
            # New mtime: agent wrote a selection change.  Read and signal it.
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
            local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then
                _EDIT_SELECT_NEW_SELECTION_EVENT=1
            else
                # Empty primary: selection was cleared.
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _ZES_SELECTION_SET_TIME=0
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
            fi
        fi
    fi
}

function _zes_apply_wsl_mouse_mode() {
    ((!_ZES_ON_WSL)) && return
    _zes_refresh_wsl_mouse_mode
    if [[ "$_ZES_WSL_MOUSE_MODE" == "terminal" ]]; then
        _zes_disable_mouse_tracking
    else
        _zes_enable_mouse_tracking
    fi
}

# Re-apply the current runtime mouse strategy without requiring a new shell.
function edit-select::refresh-runtime() {
    if ((_ZES_ON_WSL)); then
        _zes_apply_wsl_mouse_mode
    fi
    edit-select::apply-mouse-replacement-config
}

# Runtime mouse mode control for WSL sessions.
# Modes:
#   auto     -> derive mode from copyOnSelect (recommended with copyOnSelect=false)
#   terminal -> always native terminal selection mode
#   tracking -> always ZLE tracking mode
#   toggle   -> switch between terminal and tracking
function edit-select::set-mouse-mode() {
    local mode="$1"
    if ((!_ZES_ON_WSL)); then
        print -u2 "edit-select: mouse mode switching is only available on WSL"
        return 1
    fi

    case "$mode" in
        auto)
            unset ZES_WSL_MOUSE_MODE
            ;;
        terminal|tracking)
            export ZES_WSL_MOUSE_MODE="$mode"
            ;;
        toggle)
            _zes_refresh_wsl_mouse_mode
            if [[ "$_ZES_WSL_MOUSE_MODE" == "terminal" ]]; then
                export ZES_WSL_MOUSE_MODE="tracking"
            else
                export ZES_WSL_MOUSE_MODE="terminal"
            fi
            ;;
        *)
            print -u2 "Usage: edit-select mode <auto|terminal|tracking|toggle>"
            return 1
            ;;
    esac

    _zes_clear_selection_state
    edit-select::refresh-runtime
    _zes_refresh_wsl_mouse_mode
    print "edit-select: active mouse mode -> $_ZES_WSL_MOUSE_MODE"
}

# ZLE widget: quick toggle between terminal and tracking modes on WSL.
function edit-select::toggle-mouse-mode-widget() {
    edit-select::set-mouse-mode toggle >/dev/null
    zle -M "Mouse mode: $_ZES_WSL_MOUSE_MODE"
    zle -R
}
zle -N edit-select::toggle-mouse-mode-widget

# Apply keybindings and ZLE hook registration to reflect the current value of
# EDIT_SELECT_MOUSE_REPLACEMENT.  Called once at startup and again when the
# configuration wizard changes the setting.  When the feature is disabled,
# all custom bindings are reverted to their ZLE defaults.
function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        if ((_ZES_ON_WSL)); then
            _zes_refresh_wsl_mouse_mode
        fi
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        bindkey -M emacs '^V' edit-select::paste-clipboard
        bindkey -M edit-select '^V' edit-select::paste-clipboard
        _zes_start_monitor
        add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
        # Enable terminal focus reporting (DECSET 1004) and bind focus
        # event handlers so cross-pane selection changes are suppressed.
        # Written to /dev/tty to avoid triggering Powerlevel10k instant-prompt
        # console-output warnings during zsh initialization.
        printf '\e[?1004h' >/dev/tty 2>/dev/null
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
        if ((_ZES_ON_WSL)); then
            _zes_apply_wsl_mouse_mode
        fi
    else
        bindkey -M emacs -R ' '-'~' self-insert
        bindkey -M emacs '^?' backward-delete-char
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
        bindkey -M emacs '^[[200~' bracketed-paste
        bindkey -M emacs '^V' edit-select::paste-clipboard
        bindkey -M edit-select '^V' edit-select::paste-clipboard
        add-zle-hook-widget -d line-pre-redraw edit-select::zle-line-pre-redraw 2>/dev/null
        printf '\e[?1004l' >/dev/tty 2>/dev/null
        bindkey -M emacs -r '\e[I' 2>/dev/null
        bindkey -M emacs -r '\e[O' 2>/dev/null
        bindkey -r '\e[I' 2>/dev/null
        bindkey -r '\e[O' 2>/dev/null
        # Disable WSL mouse tracking if it was enabled.
        if ((_ZES_ON_WSL)); then
            _zes_disable_mouse_tracking
        fi
        _EDIT_SELECT_LAST_PRIMARY=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
    fi
}

# Public CLI entry-point.  Dispatches subcommands (currently only
# "conf"/"config" which launches the interactive wizard).
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
    elif [[ $1 == refresh ]]; then
        edit-select::refresh-runtime
    elif [[ $1 == mode ]]; then
        edit-select::set-mouse-mode "$2"
    else
        print "edit-select - Text selection and clipboard management for Zsh"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
        print "  refresh         Re-apply runtime mouse/clipboard integration state"
        print "  mode            Set WSL mouse mode: auto|terminal|tracking|toggle"
    fi
}

# Load the Wayland-specific clipboard backend (agent start/stop,
# get/set primary/clipboard).
source "$_EDIT_SELECT_PLUGIN_DIR/backends-wsl/wayland-backend-core-wsl.zsh"

# Read user config and populate undo/redo key bindings.
edit-select::load-config

# Apply user-configured or default undo/redo keybindings in both
# emacs and main keymaps.
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# Migrate config files written by 0.4.x and earlier that stored
# EDIT_SELECT_MOUSE_REPLACEMENT as the strings "enabled"/"disabled".
# Rewrite them to integers so subsequent sourcing reads cleanly.
if [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]]; then
    local _zes_cfg=$(<"$_EDIT_SELECT_CONFIG_FILE")
    if [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="enabled"'* ]] ||
        [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="disabled"'* ]]; then
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"enabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=1}"
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"disabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=0}"
        print -r -- "$_zes_cfg" >"$_EDIT_SELECT_CONFIG_FILE"
    fi
fi

# Normalise any residual string value that may still be in the live env.
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# Pre-populate LAST_MTIME before the first ZLE callback fires so the initial
# redraw does not see a spurious empty-to-non-empty mtime transition.
if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
    fi
fi

# Activate or deactivate mouse-replacement bindings based on the final
# normalised setting.
edit-select::apply-mouse-replacement-config
