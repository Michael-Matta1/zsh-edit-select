# Copyright (c) 2025 Michael Matta
# Version: 0.6.4
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland-native text selection and editing for Zsh command line.

# Load zsh/stat for zero-fork file stat via zstat, and zsh/datetime for
# EPOCHSECONDS / EPOCHREALTIME used in liveness probes and timing.
zmodload zsh/stat 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
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
typeset -g _EDIT_SELECT_PLUGIN_DIR="${0:A:h}"
# Last-observed mtime of the seq file; compared on each ZLE callback to detect agent writes.
typeset -gi _EDIT_SELECT_LAST_MTIME=0
# Agent / detection state flags.
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
typeset -gi _ZES_LAST_PID_CHECK=0
typeset -gF _ZES_SELECTION_SET_TIME=0
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
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
    edit-select::apply-key-defaults
}

# Clear all in-flight selection state after a paste or cut operation.
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
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

    if ((_ZES_ON_WSL)) && [[ "${_ZES_WSL_MOUSE_MODE:-}" == "tracking" ]] && ((_ZES_MOUSE_TRACKING)); then
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        return
    fi

    local -a stat_info
    zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || return

    if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
        _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
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
        else
            mouse_sel="$_EDIT_SELECT_LAST_PRIMARY"
        fi
        [[ -z "$mouse_sel" ]] && return 1
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

function edit-select::select-all() {
    MARK=0; CURSOR=${#BUFFER}; REGION_ACTIVE=1; zle -K edit-select;
}
zle -N edit-select::select-all

function _zes_clear_selection_state() {
    REGION_ACTIVE=0; _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
    _EDIT_SELECT_LAST_PRIMARY=""; _ZES_MOUSE_SELECTION_START=-1; _ZES_MOUSE_SELECTION_LEN=0;
    _ZES_SELECTION_SET_TIME=0; _EDIT_SELECT_NEW_SELECTION_EVENT=0; _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1;
    _zes_clear_primary; zle deactivate-region -w 2>/dev/null; zle -K main 2>/dev/null;
}

function edit-select::copy-or-interrupt() {
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
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local -a stat_info
        if zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null; then
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}; _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1;
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
            [[ -r "$_EDIT_SELECT_PID_FILE" ]] && pid=$(<"$_EDIT_SELECT_PID_FILE")
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                _EDIT_SELECT_DAEMON_ACTIVE=0; _zes_start_monitor; return
            fi
        fi
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || { _EDIT_SELECT_DAEMON_ACTIVE=0; return; }
        if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
            local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then _EDIT_SELECT_NEW_SELECTION_EVENT=1
            else _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
                 _ZES_SELECTION_SET_TIME=0; _EDIT_SELECT_NEW_SELECTION_EVENT=0; fi
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

# Re-enable DECSET 1004 on every new prompt so focus events are captured
# by the bound ZLE widgets.  Persistent (not one-shot) because
# _zes_disable_focus_reporting suppresses it before every command.
function _zes_enable_focus_reporting() {
    print -n '\e[?1004h' >$TTY
}
zle -N _zes_enable_focus_reporting

# Disable DECSET 1004 before command execution so focus-in/out
# escape sequences (\e[I / \e[O) are not printed as raw text
# while a foreground process is running.
function _zes_disable_focus_reporting() {
    print -n '\e[?1004l' >$TTY
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
        _zes_start_monitor; add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
        # Deferred to the first ZLE prompt via zle-line-init so that the
        # terminal's immediate CSI I reply is consumed by the already-bound
        # widgets instead of printing as raw ^[[I on VTE-based terminals.
        add-zle-hook-widget zle-line-init _zes_enable_focus_reporting
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _zes_disable_focus_reporting
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
        if ((_ZES_ON_WSL)); then _zes_apply_wsl_mouse_mode; fi
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
        autoload -Uz add-zsh-hook
        add-zsh-hook -d preexec _zes_disable_focus_reporting 2>/dev/null
        print -n '\e[?1004l' >$TTY
        bindkey -M emacs -r '\e[I' 2>/dev/null; bindkey -M emacs -r '\e[O' 2>/dev/null;
        bindkey -r '\e[I' 2>/dev/null; bindkey -r '\e[O' 2>/dev/null;
        if ((_ZES_ON_WSL)); then _zes_disable_mouse_tracking; fi
        _EDIT_SELECT_LAST_PRIMARY=""; _EDIT_SELECT_ACTIVE_SELECTION=""; _EDIT_SELECT_PENDING_SELECTION="";
    fi
}

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

source "$_EDIT_SELECT_PLUGIN_DIR/backends-wsl/wayland-backend-core-wsl.zsh"

if [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]]; then
    local _zes_cfg=$(<"$_EDIT_SELECT_CONFIG_FILE")
    local _zes_cfg_changed=0
    local _zes_keys_changed=0

    if [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="enabled"'* ]] || \
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
    local -a move_bind=('kcub1' '^[[D' 'backward-char' 'kcuf1' '^[[C' 'forward-char' 'khome' '^[[H' 'beginning-of-line' 'kend' '^[[F' 'end-of-line' '' "$EDIT_SELECT_KEY_WORD_LEFT" 'backward-word' '' "$EDIT_SELECT_KEY_WORD_RIGHT" 'forward-word')
    local mi mti mesc mwid mseq
    for ((mi = 1; mi <= ${#move_bind}; mi += 3)); do
        mti=${move_bind[mi]}; mesc=${move_bind[mi + 1]}; mwid=${move_bind[mi + 2]}
        [[ -z "$mesc" ]] && continue
        mseq=${terminfo[$mti]:-$mesc}
        zle -N "edit-select-move::${mwid}" _zes_move_and_resume_tracking; bindkey -M emacs "$mseq" "edit-select-move::${mwid}"
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

case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]] && _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
    fi
fi

edit-select::apply-mouse-replacement-config
