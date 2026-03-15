# Copyright (c) 2025 Michael Matta
# Version: 0.6.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# macOS-native text selection and editing for Zsh command line.
#
# AX-ONLY PRIMARY SELECTION:
# Mouse selections are detected exclusively via CGEventTap+AX.
# NSPasteboard is NEVER polled. Plugin copy/cut operations write to
# NSPasteboard but produce zero daemon events — no suppression needed.
#
# Structure: x11 source order + WSL behavioral patterns for sync functions.

zmodload zsh/stat 2>/dev/null
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload zsh/datetime 2>/dev/null

# ── Selection tracking state ───────────────────────────────────────────
typeset -g  _EDIT_SELECT_LAST_PRIMARY=""
typeset -g  _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g  _EDIT_SELECT_PENDING_SELECTION=""
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
typeset -g  _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
# ${0:A:h} resolves symlinks then takes parent directory.
# For impl-macos/zsh-edit-select-macos.plugin.zsh → impl-macos/
typeset -g  _EDIT_SELECT_PLUGIN_DIR="${0:A:h}"
typeset -gi _EDIT_SELECT_LAST_MTIME=0
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
typeset -gi _ZES_LAST_PID_CHECK=0
typeset -gF _ZES_SELECTION_SET_TIME=0

# ── Cache directory and file paths ────────────────────────────────────
# macOS: $TMPDIR set by launchd to per-user directory (APFS, fast).
# XDG_RUNTIME_DIR is not set on macOS. /dev/shm does not exist on macOS.
typeset -g _EDIT_SELECT_CACHE_DIR="${TMPDIR:-/tmp}/zsh-edit-select-${UID}"
typeset -g _EDIT_SELECT_SEQ_FILE="$_EDIT_SELECT_CACHE_DIR/seq"
typeset -g _EDIT_SELECT_PRIMARY_FILE="$_EDIT_SELECT_CACHE_DIR/primary"
typeset -g _EDIT_SELECT_PID_FILE="$_EDIT_SELECT_CACHE_DIR/agent.pid"

# ── Default undo/redo key sequences (read-only) ────────────────────────
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'

# ─────────────────────────────────────────────────────────────────────
# edit-select::load-config
# Source user config and apply defaults for unset keys.
# ─────────────────────────────────────────────────────────────────────
function edit-select::load-config() {
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && \
        source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
    EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
    EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
}

# ─────────────────────────────────────────────────────────────────────
# _zes_sync_after_paste  [WSL PATTERN — Correction B]
# Reset selection state after paste or cut, with cache re-read.
# Re-reading LAST_PRIMARY and updating LAST_MTIME is critical: without
# it, two consecutive copies of the same text produce only one detectable
# mtime change and a spurious event fires after every paste.
# ─────────────────────────────────────────────────────────────────────
function _zes_sync_after_paste() {
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _ZES_SELECTION_SET_TIME=0
    _EDIT_SELECT_LAST_PRIMARY=""
    _zes_clear_primary
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && \
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
    fi
}

# ─────────────────────────────────────────────────────────────────────
# _zes_sync_selection_state  [x11 PATTERN — already correct for macOS]
# Called by ZLE widgets before acting on a keypress.
# Reads seq mtime via zstat (1 stat syscall, no fork).
# On mtime change: reads primary file, sets NEW_SELECTION_EVENT.
# On same mtime: suppresses event if EVENT_FIRED_FOR_MTIME.
#
# NO SUPPRESSION BLOCK: Unlike WSL, no _ZES_SELF_WRITE_CONTENT check is
# needed. The daemon only watches mouse button releases. Plugin copies
# write to NSPasteboard but produce zero daemon events.
# ─────────────────────────────────────────────────────────────────────
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

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
            # Empty primary: selection cleared (e.g. after paste/click-deselect).
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

# ─────────────────────────────────────────────────────────────────────
# _zes_detect_mouse_selection
# Determine whether an AX-sourced selection is active.
# Returns 0 when a selection is active, sets _EDIT_SELECT_ACTIVE_SELECTION.
# Identical logic to x11/WSL — no macOS-specific changes.
# ─────────────────────────────────────────────────────────────────────
function _zes_detect_mouse_selection() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return 1
    [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 0

    if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && \
       ((!_EDIT_SELECT_NEW_SELECTION_EVENT)); then
        if [[ -n "$_EDIT_SELECT_LAST_PRIMARY" ]] && \
           [[ "$_EDIT_SELECT_LAST_PRIMARY" == "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
            if [[ "$BUFFER" == *"$_EDIT_SELECT_ACTIVE_SELECTION"* ]]; then
                return 0
            fi
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
        if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            zle -M ""
            zle -R
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        if [[ -n "$mouse_sel" ]] && \
           ((${#mouse_sel} <= ${#BUFFER})) && \
           [[ "$BUFFER" == *"$mouse_sel"* ]]; then
            _EDIT_SELECT_ACTIVE_SELECTION="$mouse_sel"
            _ZES_SELECTION_SET_TIME=$EPOCHREALTIME
            return 0
        fi
        return 1
    fi

    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        local sel="$_EDIT_SELECT_PENDING_SELECTION" \
              sel_len=${#_EDIT_SELECT_PENDING_SELECTION}
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

# ─────────────────────────────────────────────────────────────────────
# _zes_delete_mouse_selection  [WSL PATTERN — Correction A]
# Remove active selection from BUFFER at occurrence closest to CURSOR.
# Uses complete ZLE state cleanup (WSL pattern):
#   REGION_ACTIVE=0, _zes_sync_after_paste, deactivate-region, -K main.
# ─────────────────────────────────────────────────────────────────────
function _zes_delete_mouse_selection() {
    [[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1

    local sel="$_EDIT_SELECT_ACTIVE_SELECTION" \
          sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
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
        # WSL pattern (Correction A): full ZLE state cleanup.
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

# ── ZLE Widgets ───────────────────────────────────────────────────────

function edit-select::select-all() {
    MARK=0
    CURSOR=${#BUFFER}
    REGION_ACTIVE=1
    zle -K edit-select
}
zle -N edit-select::select-all

function _zes_delete_selected_region() {
    zle kill-region -w
    zle -K main
}
zle -N edit-select::kill-region _zes_delete_selected_region

function edit-select::delete-mouse-or-backspace() {
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
zle -N edit-select::delete-mouse-or-backspace

function edit-select::delete-mouse-or-delete() {
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
zle -N edit-select::delete-mouse-or-delete

function edit-select::handle-char() {
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w
                return
            fi
            # Block typing on failure (disambiguation pending).
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle self-insert -w
}
zle -N edit-select::handle-char

function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w
    zle -K main
    zle -U -- "$KEYS"
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
zle -N edit-select::replace-selection

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
zle -N edit-select::copy-region

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
            # Delete FIRST for instant visual feedback, THEN copy async.
            _zes_delete_mouse_selection && _zes_copy_to_clipboard "$sel"
        fi
    fi
}
zle -N edit-select::cut-region

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
            if _zes_delete_mouse_selection; then
                :  # deletion succeeded; fall through to paste
            else
                return  # disambiguation pending; abort paste
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
zle -N edit-select::paste-clipboard

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
            if _zes_delete_mouse_selection; then
                :
            else
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle .bracketed-paste
    _zes_sync_after_paste
}
zle -N edit-select::bracketed-paste-replace

function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

function _zes_activate_region_and_dispatch() {
    zle -c
    if ((!REGION_ACTIVE)); then
        zle set-mark-command -w
        zle -K edit-select
    fi
    zle "${WIDGET#edit-select::}" -w
}

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

function _zes_terminal_focus_out() { : }
zle -N _zes_terminal_focus_out

# Keymap setup in anonymous function (avoids leaking loop variables).
function { emulate -L zsh
    bindkey -N edit-select
    bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
    bindkey -M edit-select -R ' '-'~'   edit-select::replace-selection

    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char'
        'kRIT' '^[[1;2C' 'forward-char'
        'kri'  '^[[1;2A' 'up-line'
        'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line'
        'kEND' '^[[1;2F' 'end-of-line'
        ''     '^[[1;6H' 'beginning-of-buffer'
        ''     '^[[1;6F' 'end-of-buffer'
        ''     '^[[1;6D' 'backward-word'
        ''     '^[[1;6C' 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}
        esc=${nav_bind[i + 1]}
        wid=${nav_bind[i + 2]}
        seq=${terminfo[$ti]:-$esc}
        zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs       "$seq" "edit-select::${wid}"
        bindkey -M edit-select "$seq" "edit-select::${wid}"
    done

    local -a dest_bind=(
        'kdch1' '^[[3~' 'edit-select::kill-region'
        'bs'    '^?'    'edit-select::kill-region'
    )
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}
        bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    bindkey -M edit-select '^[[67;6u' edit-select::copy-region
    bindkey -M edit-select '^X'       edit-select::cut-region
    bindkey -M edit-select '^[[200~'  edit-select::bracketed-paste-replace
    bindkey -M emacs '^A'             edit-select::select-all
    bindkey -M emacs '^[[67;6u'       edit-select::copy-region
    bindkey -M emacs '^X'             edit-select::cut-region
    bindkey '^X'                      edit-select::cut-region
    bindkey -M emacs '^[[1;5D'        backward-word
    bindkey -M emacs '^[[1;5C'        forward-word
    bindkey -M edit-select '\e[I'     _zes_terminal_focus_in
    bindkey -M edit-select '\e[O'     _zes_terminal_focus_out
}

# ─────────────────────────────────────────────────────────────────────
# edit-select::zle-line-pre-redraw  [WSL PATTERN — Correction C]
# ZLE hook: fires AFTER every widget, BEFORE the display redraws.
# Must be fast — no forks.  Detects AX selection changes via seq-file
# mtime (one stat syscall).  Daemon liveness checked at most once
# every 30s.
#
# EMPTY-PRIMARY HANDLING (WSL pattern — Correction C):
# When primary is empty, clear active selections and do NOT set
# NEW_SELECTION_EVENT.  x11's pre-redraw sets it unconditionally — wrong.
#
# EVENT_FIRED_FOR_MTIME RESET:
# When this hook detects a new mtime it MUST set
# _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0.  Without this reset, the next
# keypress's _zes_sync_selection_state would see the same (already-
# consumed) mtime with a stale EVENT_FIRED_FOR_MTIME==1 and enter the
# suppression branch, clearing NEW_SELECTION_EVENT and
# ACTIVE_SELECTION before any widget can act on the selection.
# Resetting to 0 ensures the suppression branch is skipped.
# _zes_sync_selection_state is then the only one that sets it to 1
# (after the widget has consumed the event).
#
# NO SUPPRESSION BLOCK: Unlike WSL, no _ZES_SELF_WRITE_CONTENT check
# is needed. The daemon never fires on clipboard writes.
# ─────────────────────────────────────────────────────────────────────
function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return

    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Liveness probe: at most once every 30s (amortised).
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

        local -a stat_info
        zstat -A stat_info +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null || {
            _EDIT_SELECT_DAEMON_ACTIVE=0
            return
        }

        if ((stat_info[1] != _EDIT_SELECT_LAST_MTIME)); then
            _EDIT_SELECT_LAST_MTIME=${stat_info[1]}
            _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=0
            local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)

            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then
                _EDIT_SELECT_NEW_SELECTION_EVENT=1
            else
                # Empty primary: selection was cleared (click-deselect, paste).
                # WSL pattern (Correction C): do NOT fire NEW_SELECTION_EVENT.
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _ZES_SELECTION_SET_TIME=0
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
            fi
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────
# edit-select::apply-mouse-replacement-config
# Apply keybindings and ZLE hook based on EDIT_SELECT_MOUSE_REPLACEMENT.
# Called once at startup and by wizard when toggling.
# ─────────────────────────────────────────────────────────────────────
function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" \
            edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        bindkey -M emacs '^V' edit-select::paste-clipboard
        bindkey -M edit-select '^V' edit-select::paste-clipboard
        _zes_start_monitor
        add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
        # Enable terminal focus reporting (DECSET 1004).
        # Written to /dev/tty to avoid Powerlevel10k instant-prompt warnings.
        printf '\e[?1004h' >/dev/tty 2>/dev/null
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
    else
        bindkey -M emacs -R ' '-'~' self-insert
        bindkey -M emacs '^?' backward-delete-char
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
        bindkey -M emacs '^[[200~' bracketed-paste
        bindkey -M emacs '^V' edit-select::paste-clipboard
        bindkey -M edit-select '^V' edit-select::paste-clipboard
        add-zle-hook-widget -d line-pre-redraw \
            edit-select::zle-line-pre-redraw 2>/dev/null
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

# ─────────────────────────────────────────────────────────────────────
# edit-select (public CLI)  [x11 PATTERN — Correction E]
# Source wizard then explicitly call edit-select::config-wizard.
# Also provides: setup-ax (Accessibility permission prompt).
# ─────────────────────────────────────────────────────────────────────
function edit-select() {
    if [[ $1 == conf || $1 == config ]]; then
        local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard-macos.zsh"
        if [[ -f "$wizard_file" ]]; then
            source "$wizard_file" 2>/dev/null || {
                print -u2 "Error: Failed to load configuration wizard"
                return 1
            }
            edit-select::config-wizard   # explicit call required (x11 pattern)
        else
            print -u2 "Error: Configuration wizard not found at: $wizard_file"
            return 1
        fi
    elif [[ $1 == setup-ax ]]; then
        # Prompt for Accessibility permission required for true PRIMARY
        # selection (AX mouse selection). One-time setup.
        if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
            print "Requesting Accessibility permission for mouse selection..."
            print "A system dialog will appear. Click 'Open System Settings',"
            print "then enable the toggle next to your terminal application."
            if "$_EDIT_SELECT_MONITOR_BIN" --request-ax 2>/dev/null; then
                print "✓ Accessibility permission granted. Mouse selection is now active."
                print "  Restart the daemon: source ~/.zshrc"
            else
                print "⚠ Permission not yet granted."
                print "  Open: System Settings → Privacy & Security → Accessibility"
                print "  Enable the toggle for your terminal application."
                print "  Then restart: source ~/.zshrc"
            fi
        else
            print -u2 "Error: agent binary not found."
            print -u2 "Build it: cd <plugin-dir>/impl-macos/backends/macos && make"
            return 1
        fi
    else
        print "edit-select - Text selection and clipboard management for Zsh (macOS)"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
        print "  setup-ax        Grant Accessibility permission for mouse selection"
    fi
}

# ── Source backend (x11 pattern: after all function definitions — Correction G) ──
# Sets _EDIT_SELECT_MONITOR_BIN and defines the 6 backend functions.
source "$_EDIT_SELECT_PLUGIN_DIR/backends/macos/macos-backend.zsh"

# ── Load user configuration ─────────────────────────────────────────────
edit-select::load-config

# ── Undo/redo keybindings (x11 pattern: direct bindings — Correction F) ─
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# ── Config migration: normalize legacy "enabled"/"disabled" to 1/0 ──────
if [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]]; then
    local _zes_cfg=$(<"$_EDIT_SELECT_CONFIG_FILE")
    if [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="enabled"'* ]] || \
       [[ "$_zes_cfg" == *'EDIT_SELECT_MOUSE_REPLACEMENT="disabled"'* ]]; then
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"enabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=1}"
        _zes_cfg="${_zes_cfg//EDIT_SELECT_MOUSE_REPLACEMENT=\"disabled\"/EDIT_SELECT_MOUSE_REPLACEMENT=0}"
        print -r -- "$_zes_cfg" >"$_EDIT_SELECT_CONFIG_FILE"
    fi
    source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
fi

# ── Normalize MOUSE_REPLACEMENT value ──────────────────────────────────
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1)  EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*)            EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# ── Startup: pre-populate LAST_PRIMARY and LAST_MTIME (x11 pattern) ────
# Prevents spurious empty→non-empty mtime transition on first ZLE callback.
if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        local -a _zes_init_st
        zstat -A _zes_init_st +mtime "$_EDIT_SELECT_SEQ_FILE" 2>/dev/null && \
            _EDIT_SELECT_LAST_MTIME=${_zes_init_st[1]}
        _EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1
    fi
fi

# ── Apply keybindings ──────────────────────────────────────────────────
edit-select::apply-mouse-replacement-config
