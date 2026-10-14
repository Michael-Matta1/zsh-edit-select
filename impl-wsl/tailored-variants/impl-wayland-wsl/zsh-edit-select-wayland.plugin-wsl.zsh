# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# WSL-tailored text selection and editing for Zsh command line.
# Fork of the Wayland implementation, adapted for WSLg/Windows Terminal.

# Load zsh/datetime for EPOCHSECONDS / EPOCHREALTIME used in liveness probes
# and timing.  (zsh/stat was previously loaded for zstat-based mtime
# detection; detection now uses the fork-free $(<seq) builtin instead.)
zmodload zsh/datetime 2>/dev/null

# Selection tracking state.
typeset -g _EDIT_SELECT_LAST_PRIMARY=""
typeset -g _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g _EDIT_SELECT_PENDING_SELECTION=""
# Public config: 1 enables mouse-selection-aware typing (type-to-replace); 0 disables.
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
# Path to the user's persistent configuration file (sourced at startup).
typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
# Absolute directory of this plugin file; used to locate backend scripts.
typeset -g _EDIT_SELECT_PLUGIN_DIR="${${(%):-%x}:A:h}"
# Last-observed content of the seq file; compared (as an opaque string) on each
# ZLE callback to detect agent writes.  Content comparison catches intra-second
# events that integer-second mtime would alias, and is faster (no stat syscall).
typeset -g _EDIT_SELECT_LAST_SEQ=""
# Agent / detection state flags.
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=0
typeset -gi _ZES_LAST_PID_CHECK=0
typeset -gi _ZES_MOUSE_SELECTION_START=-1
typeset -gi _ZES_MOUSE_SELECTION_LEN=0
# Cache directory and file paths written by the selection agent.
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
    # || true: a failing config source (malformed hand-edit, transient read
    # error) must not abort this function under inherited err_return/err_exit —
    # the abort would skip apply-key-defaults and cascade out of the plugin
    # load.  The rc is unobserved; behaviour is unchanged under normal options.
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null || true
    edit-select::apply-key-defaults
}

# Clear all in-flight selection state after a paste or cut operation.
function _zes_sync_after_paste() {
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _ZES_MOUSE_SELECTION_START=-1
    _ZES_MOUSE_SELECTION_LEN=0
    _zes_clear_primary
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Guards go INSIDE the brace groups.  A trailing `|| true` on a brace
        # group stops suppressing an inherited err_return abort as soon as any
        # enclosing frame's status is observed, and that is the case here:
        # `_zes_delete_mouse_selection` calls this mid-body and is itself invoked
        # as `if _zes_delete_mouse_selection; then`.  With the outside form a
        # daemon that unlinked its cache made this function abort, so the delete
        # helper returned FAILURE after having already mutated BUFFER — verified
        # in a real ZLE widget: the region was removed but the caller took its
        # failure branch, so `handle-char` skipped `zle self-insert` and the
        # typed character was LOST (type-to-replace deleted without replacing);
        # `paste-clipboard` and `bracketed-paste-replace` likewise `return`
        # before inserting.  The keymap itself is fine — the callers that reset
        # it do so on their own line — so this is a lost-keystroke bug, not a
        # stuck-keymap one.  Both reads are best-effort re-baselining and their
        # own status is never inspected.
        { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
    else
        local current_primary
        current_primary=$(_zes_get_primary 2>/dev/null) && _EDIT_SELECT_LAST_PRIMARY="$current_primary" || true
    fi
}

# Called by ZLE widgets before acting on a keypress.
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        return
    fi

    # Read the seq file's content via the fork-free, redirect-free $(<file)
    # builtin and compare as an opaque string.  Content comparison is exact and
    # catches intra-second events that integer-second mtime would alias.
    local current_seq
    # Trailing `|| true`: the `[[ -r ]] &&` list only escapes err_return when the
    # TEST fails.  When the test passes and the read then fails — the daemon
    # unlinking seq between the two, the same TOCTOU the if-form read below
    # guards — the failing right-hand side aborts this function under a user's
    # inherited err_return, stranding LAST_SEQ and skipping the event handling.
    # A simple command (not a brace group) keeps the trailing guard effective in
    # every caller context, so this stays on the fd-cost-free guarded-bare form
    # (no 2>/dev/null on the hot path).  Byte-identical in every file state.
    [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
    [[ -z "$current_seq" ]] && return

    if [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
        _EDIT_SELECT_LAST_SEQ="$current_seq"
        _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=0
        { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY="$new_primary"

        if [[ -n "$new_primary" ]]; then
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
            _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
        else
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
        fi
    else
        if ((_EDIT_SELECT_EVENT_FIRED_FOR_SEQ)); then
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
            fi
        fi
    fi
}

# Determine whether a mouse text selection is currently active.
function _zes_detect_mouse_selection() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return 1

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
            [[ -z "$mouse_sel" ]] && return 1
            if [[ -n "$_ZES_SELF_WRITE_CONTENT" ]] && [[ "$mouse_sel" == "$_ZES_SELF_WRITE_CONTENT" ]]; then
                _ZES_SELF_WRITE_CONTENT=""
                return 1
            fi
        else
            # No new selection event: the matcher below runs only under
            # is_new_selection=1, and the PENDING disambiguation path uses
            # _EDIT_SELECT_PENDING_SELECTION, so mouse_sel is unused here.
            # Check the emptiness guard and the self-write dedup directly
            # against the cached primary instead of copying it into mouse_sel
            # first (avoids an O(selection-size) copy on every no-event
            # keystroke — the hottest path).  The two presence tests use
            # ${var:+x} rather than "$var" so they stay O(1): a plain [[ -z
            # "$var" ]] materialises the whole cached selection, which on WSL
            # can be a multi-hundred-KB clipboard payload bridged in by WSLg.
            [[ -z "${_EDIT_SELECT_LAST_PRIMARY:+x}" ]] && return 1
            if [[ -n "${_ZES_SELF_WRITE_CONTENT:+x}" ]] && [[ "$_EDIT_SELECT_LAST_PRIMARY" == "$_ZES_SELF_WRITE_CONTENT" ]]; then
                _ZES_SELF_WRITE_CONTENT=""
                return 1
            fi
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
            return 0
        fi
        return 1
    fi

    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        local sel="$_EDIT_SELECT_PENDING_SELECTION" sel_len=${#_EDIT_SELECT_PENDING_SELECTION}
        if [[ "$BUFFER" == *"$sel"* ]]; then
            local buf="$BUFFER" idx=0
            while [[ "$buf" == *"$sel"* ]]; do
                local prefix="${buf%%"$sel"*}"
                idx=$((idx + ${#prefix}))
                local end_pos=$((idx + sel_len))
                if ((CURSOR >= idx && CURSOR <= end_pos)); then
                    _EDIT_SELECT_ACTIVE_SELECTION="$sel"
                    _EDIT_SELECT_PENDING_SELECTION=""
                    zle -M ""
                    zle -R
                    return 0
                fi
                # Occurrences are produced left to right, so once one starts
                # past the cursor no later occurrence can contain it either.
                ((idx > CURSOR)) && break
                idx=$((idx + sel_len))
                buf="${BUFFER:$idx}"
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

# Remove the active mouse selection from BUFFER.
function _zes_delete_mouse_selection() {
    [[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1

    local sel="$_EDIT_SELECT_ACTIVE_SELECTION" sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
    ((sel_len > ${#BUFFER})) && { _EDIT_SELECT_ACTIVE_SELECTION=""; return 1; }
    [[ "$BUFFER" != *"$sel"* ]] && { _EDIT_SELECT_ACTIVE_SELECTION=""; return 1; }

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
                _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
                zle deactivate-region -w 2>/dev/null
                zle -K main 2>/dev/null
                return 0
            fi
        fi
    fi

    # Occurrences are produced left to right, so the scan can stop as soon as
    # the answer is fixed: either the cursor falls inside the occurrence just
    # found, or a second occurrence already starts past the cursor (no later
    # one can contain it either).  first_pos covers the single-occurrence case,
    # which is deleted unconditionally.
    local buf="$BUFFER" idx=0
    local -i num_occurrences=0 first_pos=-1 target_pos=-1
    while [[ "$buf" == *"$sel"* ]]; do
        local prefix="${buf%%"$sel"*}"
        idx=$((idx + ${#prefix}))
        (( ++num_occurrences == 1 )) && first_pos=$idx
        if ((CURSOR >= idx && CURSOR <= idx + sel_len)); then
            target_pos=$idx
            break
        fi
        (( num_occurrences > 1 && idx > CURSOR )) && break
        idx=$((idx + sel_len))
        buf="${BUFFER:$idx}"
    done
    (( target_pos < 0 && num_occurrences == 1 )) && target_pos=$first_pos

    if ((target_pos >= 0)); then
        BUFFER="${BUFFER:0:$target_pos}${BUFFER:$((target_pos + sel_len))}"
        CURSOR=$target_pos
        REGION_ACTIVE=0
        _zes_sync_after_paste
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
        zle deactivate-region -w 2>/dev/null
        zle -K main 2>/dev/null
        return 0
    fi

    zle -M "Duplicate text: place cursor inside the occurrence you want to modify"
    _EDIT_SELECT_PENDING_SELECTION="$_EDIT_SELECT_ACTIVE_SELECTION"
    _EDIT_SELECT_ACTIVE_SELECTION=""
    return 1
}

function edit-select::select-all() {
    MARK=0; CURSOR=${#BUFFER}; REGION_ACTIVE=1; zle -K edit-select;
}
zle -N edit-select::select-all

function _zes_clear_selection_state() {
    REGION_ACTIVE=0; _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
    _EDIT_SELECT_LAST_PRIMARY=""; _ZES_MOUSE_SELECTION_START=-1; _ZES_MOUSE_SELECTION_LEN=0;
    _EDIT_SELECT_NEW_SELECTION_EVENT=0; _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1;
    # `|| true` on both ZLE calls: outside ZLE they return 1 ("widgets can only
    # be called when ZLE is active"), and `edit-select mode` reaches this from the
    # command line.  No call site inspects this function's status, but under a
    # user's inherited err_return the first failure aborted the function and
    # propagated to the caller — skipping `_zes_refresh_wsl_mouse_mode` after the
    # mode switch, so the reported mode and the live bindings disagreed.
    _zes_clear_primary; zle deactivate-region -w 2>/dev/null || true; zle -K main 2>/dev/null || true;
}

# Cancel any in-flight pending-selection disambiguation.  When a mouse
# selection matches multiple BUFFER occurrences, the user is prompted to
# position the cursor; during that state ALL keystrokes are swallowed.
# This widget provides an Escape-to-cancel escape hatch so the user is
# never stuck in the disambiguation prompt.
function edit-select::cancel-pending-or-escape() {
    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_LAST_PRIMARY=""
        _zes_clear_primary
        zle -M ""
        zle -R
    elif [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        _zes_clear_selection_state
    fi
}
zle -N edit-select::cancel-pending-or-escape

function edit-select::copy-or-interrupt() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then zle edit-select::copy-region
    elif [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        _zes_copy_to_clipboard "$_EDIT_SELECT_ACTIVE_SELECTION" || {
            zle -M "Copy failed: clipboard unavailable"
            return
        }
        _zes_clear_selection_state
    else _zes_clear_selection_state; zle send-break; fi
}
zle -N edit-select::copy-or-interrupt

function _zes_delete_selected_region() { zle kill-region -w; zle -K main; }
zle -N edit-select::kill-region _zes_delete_selected_region

function edit-select::delete-mouse-or-backspace() {
    zle -c; _zes_resume_tracking_if_needed
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
zle -N edit-select::delete-mouse-or-backspace

function edit-select::delete-mouse-or-delete() {
    zle -c; _zes_resume_tracking_if_needed
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
zle -N edit-select::delete-mouse-or-delete

function edit-select::handle-char() {
    zle -c; _zes_resume_tracking_if_needed
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w; return;
            fi
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle self-insert -w
}
zle -N edit-select::handle-char

function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w; zle -K main; zle -U -- "$KEYS";
}
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

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

function edit-select::copy-region() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}" || { zle -M "Copy failed: clipboard unavailable"; return; }
        _zes_sync_after_paste; zle deactivate-region -w; zle -K main;
    else
        local primary_sel; primary_sel=$(_zes_get_primary) || return
        _zes_copy_to_clipboard "$primary_sel" || { zle -M "Copy failed: clipboard unavailable"; return; }
        _zes_sync_after_paste
    fi
}
zle -N edit-select::copy-region

function edit-select::cut-region() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}" || { zle -M "Cut failed: clipboard unavailable"; return; }
        _zes_sync_after_paste; zle kill-region -w; zle -K main;
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
zle -N edit-select::cut-region

function edit-select::paste-clipboard() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start; REGION_ACTIVE=0; zle -K main;
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                :
            else
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    local clipboard_content; clipboard_content=$(_zes_get_clipboard) || return
    [[ -n "$clipboard_content" ]] && LBUFFER="${LBUFFER}${clipboard_content}"
    _zes_sync_after_paste
}
zle -N edit-select::paste-clipboard

function edit-select::bracketed-paste-replace() {
    _zes_resume_tracking_if_needed
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start; REGION_ACTIVE=0; zle -K main;
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                :
            else
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle .bracketed-paste; _zes_sync_after_paste;
}
zle -N edit-select::bracketed-paste-replace

function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

function _zes_activate_region_and_dispatch() {
    zle -c; _zes_resume_tracking_if_needed
    if ((!REGION_ACTIVE)); then zle set-mark-command -w; zle -K edit-select; fi
    zle "${WIDGET#edit-select::}" -w
}

function _zes_terminal_focus_in() {
    # Focus-in can arrive immediately after a terminal-native selection path.
    # Clearing state here would discard a daemon-detected selection before the
    # next widget can act on it, so autosuspended handoffs only refresh the
    # seq-file baseline and leave selection ownership unchanged.
    #
    # || true on both reads: the daemon can unlink its cache between panes, and
    # the read's status is unobserved either way.  Without the guard, inherited
    # err_return/err_exit aborts the widget on a missing seq file, stranding the
    # state this handler exists to reset.
    if ((_ZES_MOUSE_AUTOSUSPENDED)); then
        if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
            local current_seq
            { current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
            if [[ -n "$current_seq" ]]; then
                _EDIT_SELECT_LAST_SEQ="$current_seq"; _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1;
            fi
        fi
        return
    fi
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local current_seq
        { current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
        if [[ -n "$current_seq" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"; _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1;
        fi
    fi
    _EDIT_SELECT_NEW_SELECTION_EVENT=0; _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
}
zle -N _zes_terminal_focus_in

function _zes_terminal_focus_out() { : }
zle -N _zes_terminal_focus_out

function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return
    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        _EDIT_SELECT_NEW_SELECTION_EVENT=0; return;
    fi
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        if ((EPOCHSECONDS > _ZES_LAST_PID_CHECK + 30)); then
            _ZES_LAST_PID_CHECK=$EPOCHSECONDS; local pid
            # `|| true`: the [[ -r ]] test and the read are not atomic, so a
            # daemon that unlinks its pid file in between leaves a failing
            # substitution whose rc escapes (`local` is on the line above).
            # The abort would land BEFORE the DAEMON_ACTIVE=0 + restart below,
            # so the flag would stay stale at 1 and the daemon never restart —
            # this is not the "abort is equivalent to the return" case.
            [[ -r "$_EDIT_SELECT_PID_FILE" ]] && pid=$(<"$_EDIT_SELECT_PID_FILE") || true
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                _EDIT_SELECT_DAEMON_ACTIVE=0; _zes_start_monitor; return
            fi
        fi
        local current_seq
        if [[ -r "$_EDIT_SELECT_SEQ_FILE" ]]; then current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
        else _EDIT_SELECT_DAEMON_ACTIVE=0; return; fi
        if [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"
            { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null
            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then _EDIT_SELECT_NEW_SELECTION_EVENT=1
                 # Leave EVENT_FIRED_FOR_SEQ alone: clearing the latch here re-arms an
                 # already-consumed selection.  A click that clears the selection emits
                 # cursor-movement keys (one redraw each) but no agent event, so this
                 # branch cannot tell "still selected" from "cleared by that click" —
                 # the cache and every state flag are identical.  Leaving the latch set
                 # lets the widget sync suppress the stale event, keeping a visually
                 # cleared selection from being deleted (invariants 3, 4, 6, 7).
            else _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
                 _EDIT_SELECT_NEW_SELECTION_EVENT=0; fi
        fi
    fi
}

function _zes_apply_wsl_mouse_mode() {
    ((!_ZES_ON_WSL)) && return; _zes_refresh_wsl_mouse_mode
    if [[ "$_ZES_WSL_MOUSE_MODE" == "terminal" ]]; then _zes_disable_mouse_tracking
    else _zes_enable_mouse_tracking; fi
}

function edit-select::refresh-runtime() {
    if ((_ZES_ON_WSL)); then _zes_apply_wsl_mouse_mode; fi
    edit-select::apply-mouse-replacement-config
}

function edit-select::set-mouse-mode() {
    local mode="$1"
    if ((!_ZES_ON_WSL)); then print -u2 "edit-select: mouse mode switching is only available on WSL"; return 1; fi
    case "$mode" in
        auto) unset ZES_WSL_MOUSE_MODE ;;
        terminal|tracking) export ZES_WSL_MOUSE_MODE="$mode" ;;
        toggle)
            _zes_refresh_wsl_mouse_mode
            if [[ "$_ZES_WSL_MOUSE_MODE" == "terminal" ]]; then
                export ZES_WSL_MOUSE_MODE="tracking"
            else
                export ZES_WSL_MOUSE_MODE="terminal"
            fi
            ;;
        *) print -u2 "Usage: edit-select mode <auto|terminal|tracking|toggle>"; return 1 ;;
    esac
    _zes_clear_selection_state; edit-select::refresh-runtime
    _zes_refresh_wsl_mouse_mode
    print "edit-select: active mouse mode -> $_ZES_WSL_MOUSE_MODE"
}

function edit-select::toggle-mouse-mode-widget() {
    edit-select::set-mouse-mode toggle >/dev/null
    zle -M "Mouse mode: $_ZES_WSL_MOUSE_MODE"
    zle -R
}
zle -N edit-select::toggle-mouse-mode-widget

# Focus-reporting state.  The latch records the last mode write so neither
# wrapper nor hook rewrites a mode the terminal already holds; the remaining
# variables carry the transient accept-observer state (see
# _zes_focus_lifecycle).  Re-sourcing must not re-zero any of them.
(( $+_ZES_FOCUS_REPORTING_ON )) || typeset -gi _ZES_FOCUS_REPORTING_ON=0
(( $+_ZES_ACCEPT_PENDING )) || typeset -gi _ZES_ACCEPT_PENDING=0
(( $+_ZES_ACCEPT_AT_DEPTH )) || typeset -gi _ZES_ACCEPT_AT_DEPTH=0
(( $+_ZES_TOP_SEEN )) || typeset -gi _ZES_TOP_SEEN=0
(( $+_ZES_FOCUS_OBSERVER_ARMED )) || typeset -gi _ZES_FOCUS_OBSERVER_ARMED=0
(( $+_ZES_LI_GEN )) || typeset -gi _ZES_LI_GEN=0
(( $+_ZES_AC_MINTS )) || typeset -gi _ZES_AC_MINTS=0
(( $+_ZES_AC_STANDING )) || typeset -g _ZES_AC_STANDING=''

# The machinery classification: made exactly once per shell (at the first
# precmd, when the deferred registration runs) and cached, so re-sources,
# re-applies and later widget rebinds can never re-classify a plain shell
# mid-life.  A feature toggle never resets it -- it describes the shell's
# prompt stack, not the feature.
(( $+_ZES_FOCUS_MACHINERY_DECIDED )) || typeset -gi _ZES_FOCUS_MACHINERY_DECIDED=0
(( $+_ZES_FOCUS_MACHINERY_ON )) || typeset -gi _ZES_FOCUS_MACHINERY_ON=0

# Enable DECSET 1004 while the line editor is live so focus-in/out
# escape sequences (\e[I / \e[O) reach the bound ZLE widgets instead of
# printing as raw text.  Gated on mouse replacement so a wrapper that
# survives buried inside a third-party chain stays inert while the
# feature is off.
function _zes_enable_focus_reporting() {
    if (( ! EDIT_SELECT_MOUSE_REPLACEMENT )); then
        return 0
    fi
    if (( _ZES_FOCUS_REPORTING_ON )); then
        return 0
    fi
    print -n '\e[?1004h' >$TTY || true
    _ZES_FOCUS_REPORTING_ON=1
}
# The plain-shell twins: the shipped plugin's own enable/disable bodies,
# byte for byte.  Shells with no line-init widget owner register THESE
# (never the machinery's latched forms), so their focus lifecycle is
# identical to the shipped plugin's in every observable: same writes, same
# tests, same moments.  The machinery branch never registers them.
function _zes_enable_focus_reporting_plain() {
    print -n '\e[?1004h' >$TTY || true
}

function _zes_disable_focus_reporting_plain() {
    print -n '\e[?1004l' >$TTY || true
}

# Disable DECSET 1004 before command execution so focus events are not
# printed as raw text while a foreground process is running.
function _zes_disable_focus_reporting() {
    if (( ! _ZES_FOCUS_REPORTING_ON )); then
        return 0
    fi
    print -n '\e[?1004l' >$TTY || true
    _ZES_FOCUS_REPORTING_ON=0
}

# Finish-site disable.  A session that ended without running a command - an
# empty or whitespace-only accept, or a PS2 fragment whose editing continues
# in the next zleread - leaves reporting on, exactly as today: no foreground
# program follows such an accept, and the next session re-arms without a
# write.  vared sessions are excluded: a successful vared return is followed
# by script code that may exec, and the v2 assessment requires OFF there.
function _zes_finish_disable() {
    if [[ $CONTEXT == vared ]]; then
        _zes_disable_focus_reporting
        return
    fi
    if [[ -n "$PREBUFFER" ]] || [[ -z "$BUFFER" || $BUFFER =~ '^[[:space:]]*$' ]]; then
        return
    fi
    _zes_disable_focus_reporting
}

# The transient pre-redraw observer.  Registered by the chain-scoped accept
# wrapper for accepts dispatched inside a session-widget chain (an
# OMP-transient-style line-init owner whose handoff can be preceded by
# in-widget rendering work), and self-removed as soon as it is quiescent.
# Ordinary editing therefore runs with no observer registered and the
# selection pre-redraw hook's per-redraw work is untouched.  D: the
# dispatch's own iteration-tail redraw (depth unchanged from the recorded
# dispatch depth) drops reporting before any render the chain may perform.
# E: a live editor's redraw restores it before any continuation keystroke;
# the dead-session zleread-entry redraw after a session widget's final
# accept fails both the zr and _ZES_TOP_SEEN gates (OMP's top-level zlecore
# never iterates), so the observer stays silent there without depending on
# LASTWIDGET, whose value earlier hooks can clobber on zsh 5.8.
function _zes_focus_observer_arm() {
    if (( ! _ZES_FOCUS_OBSERVER_ARMED )); then
        _ZES_FOCUS_OBSERVER_ARMED=1
        _ZES_TOP_SEEN=0
        add-zle-hook-widget line-pre-redraw _zes_focus_lifecycle || true
    fi
}

function _zes_focus_observer_disarm() {
    if (( _ZES_FOCUS_OBSERVER_ARMED )); then
        _ZES_FOCUS_OBSERVER_ARMED=0
        add-zle-hook-widget -d line-pre-redraw _zes_focus_lifecycle 2>/dev/null || true
    fi
}

function _zes_focus_lifecycle() {
    if (( _ZES_ACCEPT_PENDING )); then
        if (( ZLE_RECURSIVE && ZLE_RECURSIVE == _ZES_ACCEPT_AT_DEPTH )); then
            _zes_disable_focus_reporting
        fi
        _ZES_ACCEPT_PENDING=0
    elif (( ! _ZES_FOCUS_REPORTING_ON )); then
        if (( ZLE_RECURSIVE || _ZES_TOP_SEEN )) && [[ $LASTWIDGET != zle-line-init ]]; then
            _zes_enable_focus_reporting
        fi
    fi
    (( ZLE_RECURSIVE )) || _ZES_TOP_SEEN=1
    if (( ! _ZES_ACCEPT_PENDING )) && (( _ZES_FOCUS_REPORTING_ON )); then
        _zes_focus_observer_disarm
    fi
}

# The chain-scoped accept wrappers.  They are installed by the line-init
# wrapper only for the duration of a preserved line-init chain call (i.e.
# only while a session widget owns the session), so an accept handled by one
# is by construction in-chain; the depth check still guards against a
# preserved chain that opens a nested .recursive-edit whose entry redraw
# would otherwise look like the dispatch's own tail redraw.
#
# Cycle safety: each mint's saved alias is written exactly once, at minting,
# with the owner that existed before the mint itself existed, and a mint
# wrapper only ever calls its own frozen alias.  A wrapper captured by a
# third party therefore calls a snapshot that predates it, so call chains
# through our wrappers strictly descend in mint order and cannot cycle -
# unlike a shared alias rewritten per window, which a decorator holding an
# older wrapper can turn into an infinite self-call.  Boundedness: an
# unchanged owner rebinds the previous mint instead of growing one wrapper
# per session.  The one shell-unobservable case: swapping accept-line
# between two different builtin widgets keeps the same "builtin" spec, so
# the reused mint calls the earlier builtin until the next configuration
# apply re-mints from the live owner (all builtins report "builtin" in
# $widgets - there is no identity comparison in shell).
function _zes_ac_arm_window() {
    local owner="${widgets[accept-line]:-}"
    if (( _ZES_AC_MINTS )) && [[ "$owner" == "$_ZES_AC_STANDING" ]]; then
        zle -N accept-line _zes_ac_wrap_win${_ZES_AC_MINTS}
        return 0
    fi
    integer acn=$(( _ZES_AC_MINTS + 1 ))
    zle -A accept-line ._zes_ac_win${acn}
    eval "function _zes_ac_wrap_win${acn}() {
        _ZES_ACCEPT_PENDING=1
        _ZES_ACCEPT_AT_DEPTH=\$ZLE_RECURSIVE
        _zes_focus_observer_arm
        zle ._zes_ac_win${acn} -- \"\$@\"
        return \$?
    }"
    zle -N accept-line _zes_ac_wrap_win${acn}
    _ZES_AC_STANDING="$owner"
    _ZES_AC_MINTS=$acn
    return 0
}

function _zes_ac_restore_window() {
    local kind="${widgets[accept-line]:-}"
    if [[ $kind == user:_zes_ac_wrap_win* ]]; then
        local acn=${kind#user:_zes_ac_wrap_win}
        zle -A ._zes_ac_win${acn} accept-line
    fi
    return 0
}

# Install the line-init wrapper for a new generation: the wrapper enables
# reporting at session start, then installs the accept wrapper ONLY around
# the preserved line-init chain call.  Plain sessions never see an accept
# wrapper at all: when no preserved chain exists the wrapper body reduces
# to the enable, so the plain accept path is the builtin, byte-for-byte as
# with main.  Alias names bake the per-generation snapshot chain so an
# older generation surviving under a decorator keeps calling its own
# snapshot; a generation whose snapshot equals the current top widget is
# re-bound instead of minted, so plain off/on cycles do not grow retained
# resources.
function _zes_install_line_init_wrapper() {
    local top="${widgets[zle-line-init]:-}"
    integer g=${_ZES_LI_GEN}
    while (( g > 0 )); do
        if [[ "${widgets[._zes_li$g]:-}" == "$top" ]]; then
            zle -N zle-line-init _zes_li_wrap_gen$g
            return
        fi
        (( g-- ))
    done
    integer gen=$(( _ZES_LI_GEN + 1 ))
    if [[ -n "$top" ]]; then
        zle -A zle-line-init ._zes_li$gen
    fi
    eval "function _zes_li_wrap_gen${gen}() {
        _zes_enable_focus_reporting
        if [[ -n \"\${widgets[._zes_li${gen}]:-}\" ]]; then
            integer -i armed_here=0
            if (( EDIT_SELECT_MOUSE_REPLACEMENT )) && (( ! \${_ZES_AC_BORROWED:-0} )); then
                _zes_ac_arm_window
                armed_here=1
                integer -i _ZES_AC_BORROWED=1
            fi
            integer -i rc
            {
                zle ._zes_li${gen} -- \"\$@\"
                rc=\$?
            } always {
                if (( armed_here )); then
                    _zes_ac_restore_window
                fi
            }
            return rc
        fi
        return 0
    }"
    zle -N zle-line-init _zes_li_wrap_gen${gen}
    _ZES_LI_GEN=$gen
}

# Session-owner detector.  A session-owner is a line-init WIDGET owner: it
# rebinds zle-line-init directly (widgets[zle-line-init] is a user widget
# other than azhw's dispatcher and other than our own generation wrapper),
# or it sits snapshotted inside azhw's hook list as a `user:` entry -- the
# form azhw gives a pre-existing widget when it takes the hook over.
# azhw-managed hook functions, ours included, are ordinary hooks, not
# owners.  Plain shells (no binding, or azhw with hook functions only)
# install none of the machinery.
function _zes_focus_machinery_needed() {
    local w="${widgets[zle-line-init]:-}"
    [[ -n "$w" ]] || return 1
    [[ "$w" == user:_zes_li_wrap_gen* ]] && return 0
    if [[ "$w" == user:azhw:zle-line-init ]]; then
        local -a hook_list
        zstyle -a zle-line-init widgets hook_list
        (( ${#hook_list} )) && [[ -n "${(M)hook_list[@]:#<->:user:*}" ]] && return 0
        return 1
    fi
    return 0
}

# One-shot precmd that registers the deferred ZLE hooks, then removes itself.
# Registration is deferred to the first precmd (which runs only after the whole
# ~/.zshrc has finished sourcing) so these widgets are created AFTER other
# plugins have done their one-time ZLE widget binding.  In particular
# zsh-syntax-highlighting (on zsh < 5.9, or its legacy code path) wraps every
# pre-existing user widget at load time; a wrapped zle-line-pre-redraw makes
# _zsh_highlight run a full re-highlight on EVERY redraw (every cursor step of a
# click-to-move burst — the visible mouse-repositioning slowdown), and a wrapped
# zle-line-init adds redundant re-highlight passes on every prompt (proven to
# produce byte-identical region_highlight, i.e. pure waste).  Deferring means
# z-sy-h never sees either widget to wrap.  Both hooks still become active before
# the first prompt is drawn (precmd precedes line-init and line-pre-redraw), so
# selection detection and focus reporting are unchanged.
function _zes_register_redraw_hook() {
    autoload -Uz add-zle-hook-widget add-zsh-hook
    add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
    # Focus reporting is enabled from the line-init wrapper and disabled from
    # the transient pre-redraw observer plus line-finish/preexec fallbacks,
    # all installed here (deferred, so zsh-syntax-highlighting cannot wrap
    # them at load time).  The wrapper runs AHEAD of any pre-existing
    # line-init owner in the dispatch chain in both source orders — even
    # when a later decorator (a prompt that wraps widgets at its own first
    # precmd, for example) sits outside ours, the chain it preserved runs
    # through us first — so the terminal's immediate CSI I reply is still
    # consumed by the already-bound widgets instead of printing as raw
    # ^[[I on VTE terminals.  The accept wrapper is not a permanent
    # binding: the line-init wrapper installs it solely around a
    # session-widget chain call.
    #
    # The machinery decision is made exactly ONCE per shell, here at the
    # first precmd, and cached: re-sources, re-applies and later widget
    # rebinds (a syntax highlighter re-wrapping zle-line-init, for example)
    # can never re-classify a plain shell mid-life.  With no line-init
    # binding at all -- or only azhw-managed hook functions like this
    # plugin's own -- a plain shell keeps the SHIPPED lifecycle: the
    # shipped bodies (the _plain twins), the shipped azhw line-init hook,
    # the shipped preexec handoff.  It carries none of this fix's machinery
    # and no cost of any kind.
    if (( ! _ZES_FOCUS_MACHINERY_DECIDED )); then
        typeset -gi _ZES_FOCUS_MACHINERY_DECIDED=1
        if _zes_focus_machinery_needed; then
            typeset -gi _ZES_FOCUS_MACHINERY_ON=1
        else
            typeset -gi _ZES_FOCUS_MACHINERY_ON=0
        fi
    fi
    if (( _ZES_FOCUS_MACHINERY_ON )); then
        if [[ ${widgets[zle-line-init]:-} != user:_zes_li_wrap_gen* ]]; then
            _zes_install_line_init_wrapper
        fi
        add-zle-hook-widget zle-line-finish _zes_finish_disable
        add-zsh-hook preexec _zes_disable_focus_reporting
    else
        add-zle-hook-widget zle-line-init _zes_enable_focus_reporting_plain
        add-zsh-hook preexec _zes_disable_focus_reporting_plain
    fi
    add-zsh-hook -d precmd _zes_register_redraw_hook
}

function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        if ((_ZES_ON_WSL)); then _zes_refresh_wsl_mouse_mode; fi
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        _zes_start_monitor || true
        # Register the pre-redraw + line-init (focus-reporting) hooks on the first
        # precmd (see _zes_register_redraw_hook) so zsh-syntax-highlighting cannot
        # wrap our dispatcher widgets and re-highlight redundantly.
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _zes_register_redraw_hook
        autoload -Uz add-zsh-hook
        # The preexec disable is registered by the deferred, branch-aware
        # _zes_register_redraw_hook (once per shell, at the first precmd):
        # plain shells get the shipped body under its _plain twin; machinery
        # shells get the latched disable.  Registering it here would force
        # the branch choice before the first precmd has evaluated it.
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
        # Ctrl-G cancels pending-selection disambiguation and clears active
        # mouse selections so the user is never stuck in a blocking state.
        bindkey -M emacs '^g' edit-select::cancel-pending-or-escape
        if ((_ZES_ON_WSL)); then _zes_apply_wsl_mouse_mode; fi
    else
        bindkey -M emacs -R ' '-'~' self-insert
        bindkey -M emacs '^?' backward-delete-char
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
        bindkey -M emacs '^[[200~' bracketed-paste
        # Ctrl-G was bound to edit-select::cancel-pending-or-escape in the
        # enable branch; restore its zsh emacs default (send-break) so it is
        # not left as an inert no-op after mouse-replacement is disabled.
        bindkey -M emacs '^g' send-break
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        autoload -Uz add-zsh-hook
        add-zsh-hook -d precmd _zes_register_redraw_hook 2>/dev/null
        add-zle-hook-widget -d line-pre-redraw edit-select::zle-line-pre-redraw 2>/dev/null
        add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting 2>/dev/null
        add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting_plain 2>/dev/null
        add-zle-hook-widget -d line-pre-redraw _zes_focus_lifecycle 2>/dev/null
        add-zle-hook-widget -d zle-line-finish _zes_finish_disable 2>/dev/null
        # Restore the generation that actually owns the outermost slot
        # (parsed from the owned widget's own name), but only when ours is
        # still outermost: a later decorator's chain must not be clobbered.
        if [[ ${widgets[zle-line-init]:-} == user:_zes_li_wrap_gen* ]]; then
            integer li_gen=${widgets[zle-line-init]#user:_zes_li_wrap_gen}
            if [[ -n "${widgets[._zes_li${li_gen}]:-}" ]]; then
                zle -A ._zes_li${li_gen} zle-line-init
            else
                zle -D zle-line-init
            fi
        fi
        _zes_ac_restore_window
        _ZES_AC_STANDING=''
        _ZES_FOCUS_REPORTING_ON=0
        _ZES_ACCEPT_PENDING=0
        _ZES_TOP_SEEN=0
        _ZES_FOCUS_OBSERVER_ARMED=0
        autoload -Uz add-zsh-hook
        add-zsh-hook -d preexec _zes_disable_focus_reporting 2>/dev/null
        add-zsh-hook -d preexec _zes_disable_focus_reporting_plain 2>/dev/null
        print -n '\e[?1004l' >$TTY || true
        bindkey -M emacs -r '\e[I' 2>/dev/null; bindkey -M emacs -r '\e[O' 2>/dev/null;
        bindkey -r '\e[I' 2>/dev/null; bindkey -r '\e[O' 2>/dev/null;
        if ((_ZES_ON_WSL)); then _zes_disable_mouse_tracking; fi
        _EDIT_SELECT_LAST_PRIMARY=""; _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
    fi
}

function edit-select::run-installer-mode() {
    local mode="$1"
    local installer="$_EDIT_SELECT_PLUGIN_DIR/../../../assets/auto-install/install.sh"

    if ! (( ${+commands[bash]} )); then
        print -u2 "Error: bash is required to run installer modes."
        return 1
    fi
    if [[ ! -r "$installer" ]]; then
        print -u2 "Error: Installer not found at: $installer"
        return 1
    fi

    command bash "$installer" --local --mode "$mode"
}

function edit-select() {
    case "$1" in
    conf | config)
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
        ;;
    refresh)
        edit-select::refresh-runtime
        ;;
    mode)
        edit-select::set-mouse-mode "$2"
        ;;
    conflicts)
        edit-select::run-installer-mode conflicts
        ;;
    integrate)
        edit-select::run-installer-mode integrate
        ;;
    update)
        edit-select::run-installer-mode update
        ;;
    build)
        edit-select::run-installer-mode build
        ;;
    uninstall)
        edit-select::run-installer-mode uninstall
        ;;
    setup-hooks)
        edit-select::setup-hooks
        ;;
    remove-hooks)
        edit-select::remove-hooks
        ;;
    *)
        print "edit-select - Text selection and clipboard management for Zsh"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
        print "  refresh         Re-apply runtime mouse/clipboard integration state"
        print "  mode            Set WSL mouse mode: auto|terminal|tracking|toggle"
        print "  conflicts       Run installer conflict detection mode"
        print "  integrate       Run installer terminal configuration mode"
        print "  update          Run installer update mode"
        print "  build           Run installer build-agents mode"
        print "  uninstall       Run installer uninstall mode"
        print "  setup-hooks     Install git hooks for automatic update notifications"
        print "  remove-hooks    Remove git hooks"
        ;;
    esac
}

source "$_EDIT_SELECT_PLUGIN_DIR/backends-wsl/wayland-backend-core-wsl.zsh"

edit-select::load-config

function { emulate -L zsh
    bindkey -N edit-select
    bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
    bindkey -M edit-select -R ' '-'~' edit-select::replace-selection
    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char' 'kRIT' '^[[1;2C' 'forward-char'
        'kri' '^[[1;2A' 'up-line' 'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line' 'kEND' '^[[1;2F' 'end-of-line'
        '' "$EDIT_SELECT_KEY_BUFFER_START" 'beginning-of-buffer'
        '' "$EDIT_SELECT_KEY_BUFFER_END" 'end-of-buffer'
        '' "$EDIT_SELECT_KEY_SEL_WORD_LEFT" 'backward-word' '' "$EDIT_SELECT_KEY_SEL_WORD_RIGHT" 'forward-word'
    )
    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}; esc=${nav_bind[i + 1]}; wid=${nav_bind[i + 2]}
        [[ -z "$esc" ]] && continue
        seq=${terminfo[$ti]:-$esc}; zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs "$seq" "edit-select::${wid}"; bindkey -M edit-select "$seq" "edit-select::${wid}"
    done
    local -a dest_bind=('kdch1' '^[[3~' 'edit-select::kill-region' 'bs' '^?' 'edit-select::kill-region')
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}; bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    bindkey -M edit-select '^C' edit-select::copy-region
    [[ -n "$EDIT_SELECT_KEY_CUT" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    bindkey -M edit-select '^[[200~' edit-select::bracketed-paste-replace

    [[ -n "$EDIT_SELECT_KEY_SELECT_ALL" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    bindkey -M emacs '^C' edit-select::copy-or-interrupt
    if [[ -n "$EDIT_SELECT_KEY_CUT" ]]; then
        bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
        bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    fi

    bindkey -M emacs '^[[77;6u' edit-select::toggle-mouse-mode-widget
    bindkey -M edit-select '^[[77;6u' edit-select::toggle-mouse-mode-widget
    function _zes_move_and_resume_tracking() { _zes_resume_tracking_if_needed; zle "${WIDGET#edit-select-move::}" -w; }
    # Home/End are deliberately absent here: the broad Home/End loop below
    # binds plain beginning/end-of-line over the same sequences, so move
    # widgets for them would be shadowed (dead) from the start.
    local -a move_bind=('kcub1' '^[[D' 'backward-char' 'kcuf1' '^[[C' 'forward-char' '' "$EDIT_SELECT_KEY_WORD_LEFT" 'backward-word' '' "$EDIT_SELECT_KEY_WORD_RIGHT" 'forward-word')
    local mi mti mesc mwid mseq
    for ((mi = 1; mi <= ${#move_bind}; mi += 3)); do
        mti=${move_bind[mi]}; mesc=${move_bind[mi + 1]}; mwid=${move_bind[mi + 2]}
        [[ -z "$mesc" ]] && continue
        mseq=${terminfo[$mti]:-$mesc}
        zle -N "edit-select-move::${mwid}" _zes_move_and_resume_tracking; bindkey -M emacs "$mseq" "edit-select-move::${mwid}"
    done

    # Home / End → move to line start / end (plain navigation, no selection).
    # Provide broad defaults covering normal, application, and rxvt/xterm modes
    # so these keys work regardless of the terminal's key-reporting mode.
    local _zes_k
    for _zes_k in "${terminfo[khome]:-^[[H}" '^[[H' '^[OH' '^[[1~' '^[[7~'; do
        bindkey -M emacs "$_zes_k" beginning-of-line
    done
    for _zes_k in "${terminfo[kend]:-^[[F}" '^[[F' '^[OF' '^[[4~' '^[[8~'; do
        bindkey -M emacs "$_zes_k" end-of-line
    done

    bindkey -M edit-select '\e[I' _zes_terminal_focus_in; bindkey -M edit-select '\e[O' _zes_terminal_focus_out
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

# ── macOS SSH key remapping ──────────────────────────────────────────
# When SSH mode is active, also bind macOS Cmd/Option CSI-u sequences
# to the Linux widgets. This allows macOS terminal users (iTerm2,
# Ghostty, Kitty, WezTerm) to SSH into this Linux box and have their
# Cmd+C, Cmd+X, Option+Arrow, etc. work transparently — provided
# the terminal is configured to forward Cmd sequences as CSI-u.
# These are additive bindings — they do not overwrite any existing keys.
# The ((_ZES_SSH_MODE)) guard ensures zero overhead on non-SSH sessions.
if ((_ZES_SSH_MODE)); then
    # Clipboard operations (Cmd = modifier 9 in CSI-u)
    bindkey -M emacs       '^[[99;9u'  edit-select::copy-region     # Cmd+C
    bindkey -M edit-select '^[[99;9u'  edit-select::copy-region
    bindkey -M emacs       '^[[120;9u' edit-select::cut-region      # Cmd+X
    bindkey -M edit-select '^[[120;9u' edit-select::cut-region
    bindkey -M emacs       '^[[97;9u'  edit-select::select-all      # Cmd+A
    bindkey -M edit-select '^[[97;9u'  edit-select::select-all
    # Undo/Redo (Cmd+Z = modifier 9, Cmd+Shift+Z = modifier 10)
    bindkey -M emacs       '^[[122;9u'  undo                        # Cmd+Z
    bindkey                '^[[122;9u'  undo
    bindkey -M emacs       '^[[122;10u' redo                        # Cmd+Shift+Z
    bindkey                '^[[122;10u' redo
    # Line / buffer navigation (Cmd = modifier 9)
    bindkey -M emacs       '^[[1;9D' beginning-of-line              # Cmd+Left
    bindkey -M emacs       '^[[1;9C' end-of-line                    # Cmd+Right
    bindkey -M emacs       '^[[1;9A' beginning-of-buffer-or-history # Cmd+Up
    bindkey -M emacs       '^[[1;9B' end-of-buffer-or-history       # Cmd+Down
    # Word navigation (Option = modifier 3)
    bindkey -M emacs       '^[[1;3D' backward-word                  # Option+Left
    bindkey -M emacs       '^[[1;3C' forward-word                   # Option+Right
    # Line / buffer selection (Cmd+Shift = modifier 10)
    bindkey -M emacs       '^[[1;10D' edit-select::beginning-of-line   # Cmd+Shift+Left
    bindkey -M edit-select '^[[1;10D' edit-select::beginning-of-line
    bindkey -M emacs       '^[[1;10C' edit-select::end-of-line         # Cmd+Shift+Right
    bindkey -M edit-select '^[[1;10C' edit-select::end-of-line
    bindkey -M emacs       '^[[1;10A' edit-select::beginning-of-buffer # Cmd+Shift+Up
    bindkey -M edit-select '^[[1;10A' edit-select::beginning-of-buffer
    bindkey -M emacs       '^[[1;10B' edit-select::end-of-buffer       # Cmd+Shift+Down
    bindkey -M edit-select '^[[1;10B' edit-select::end-of-buffer
    # Word selection (Option+Shift = modifier 4)
    bindkey -M emacs       '^[[1;4D' edit-select::backward-word     # Option+Shift+Left
    bindkey -M edit-select '^[[1;4D' edit-select::backward-word
    bindkey -M emacs       '^[[1;4C' edit-select::forward-word      # Option+Shift+Right
    bindkey -M edit-select '^[[1;4C' edit-select::forward-word
fi

case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor || true
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        # || true on both cache reads: the daemon can die and unlink its cache
        # files between the -f probe and the read; under inherited
        # err_return/err_exit a failed read would abort the load before
        # apply-mouse-replacement-config runs.  The rc is unobserved;
        # behaviour is unchanged under normal options.
        [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]] && { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null || true
        { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") } 2>/dev/null || true
        _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
    fi
fi

edit-select::apply-mouse-replacement-config
