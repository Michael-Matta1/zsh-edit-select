# Copyright (c) 2025 Michael Matta
# Version: 0.6.4
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

# ── Default key sequences (macOS-native) ─────────────────────────────
# Clipboard: Cmd key via CSI-u / kitty keyboard protocol.
# Requires a terminal that forwards Cmd sequences (iTerm2 with CSI-u enabled,
# WezTerm, Ghostty, Kitty). Terminal.app intercepts Cmd at the OS level and
# cannot forward these sequences — use 'edit-select config' to set fallbacks.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^[[97;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]]       && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^[[118;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]]         && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^[[120;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_COPY+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_COPY='^[[99;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^[[122;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[122;10u'

# Word navigation: Option+Left / Option+Right (xterm modifier form, modifier 3 = Alt/Option).
# Terminal.app users who have "Use Option as Meta Key" enabled receive \eb / \ef instead.
# Both forms are bound — see the secondary alias registration in the anonymous keybinding function.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT+x} ]]      && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_LEFT='^[[1;3D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT+x} ]]     && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT='^[[1;3C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT+x} ]]  && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT='^[[1;4D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT='^[[1;4C'

# Buffer navigation: Cmd+Shift+Up / Cmd+Shift+Down selects to start/end of buffer.
# This replaces the non-native Shift+Ctrl+Home / Shift+Ctrl+End used on Linux.
# Modifier 10 = Super(8) + Shift(1) + 1 in xterm encoding.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_START+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_START='^[[1;10A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_END+x} ]]   && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_END='^[[1;10B'

# ─────────────────────────────────────────────────────────────────────
# edit-select::apply-key-defaults
# Apply default key sequences if not already set by user config.
# ─────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────
# edit-select::load-config
# Source user config and apply defaults for unset keys.
# ─────────────────────────────────────────────────────────────────────
function edit-select::load-config() {
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
    edit-select::apply-key-defaults
}

# ─────────────────────────────────────────────────────────────────────
# _zes_sync_after_paste
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

    if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        if ((!_EDIT_SELECT_NEW_SELECTION_EVENT)); then
            if [[ -n "$_EDIT_SELECT_LAST_PRIMARY" ]] && \
               [[ "$_EDIT_SELECT_LAST_PRIMARY" == "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && \
               [[ "$BUFFER" == *"$_EDIT_SELECT_ACTIVE_SELECTION"* ]]; then
                return 0
            fi
            _EDIT_SELECT_ACTIVE_SELECTION=""
            return 1
        fi
        return 0
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
# _zes_delete_mouse_selection
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
        # WSL pattern: full ZLE state cleanup.
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

# ─────────────────────────────────────────────────────────────────────
# edit-select::zle-line-pre-redraw
# ZLE hook: fires AFTER every widget, BEFORE the display redraws.
# Must be fast — no forks.  Detects AX selection changes via seq-file
# mtime (one stat syscall).  Daemon liveness checked at most once
# every 30s.
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
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _ZES_SELECTION_SET_TIME=0
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
            fi
        fi
    fi
}


# Public CLI entry-point.
function edit-select() {
    if [[ $1 == conf || $1 == config ]]; then
        local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard-macos.zsh"
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
    elif [[ $1 == setup-ax ]]; then
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

# Source backend
source "$_EDIT_SELECT_PLUGIN_DIR/backends/macos/macos-backend.zsh"

# Migrate config files
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

# Read user config
edit-select::load-config

# Establish keymap. NOTE: Requires edit-select::load-config to have run first.
function { emulate -L zsh
    bindkey -N edit-select
    bindkey -M edit-select -R '^@'-'^Z' edit-select::deselect-and-input
    bindkey -M edit-select -R '^\'-'^?' edit-select::deselect-and-input
    bindkey -M edit-select -R ' '-'~'   edit-select::replace-selection

    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char'
        'kRIT' '^[[1;2C' 'forward-char'
        'kri'  '^[[1;2A' 'up-line'
        'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line'
        'kEND' '^[[1;2F' 'end-of-line'
        ''     '^[[1;10D' 'beginning-of-line'
        ''     '^[[1;10C' 'end-of-line'
        ''     "$EDIT_SELECT_KEY_BUFFER_START" 'beginning-of-buffer'
        ''     "$EDIT_SELECT_KEY_BUFFER_END"   'end-of-buffer'
        ''     "$EDIT_SELECT_KEY_SEL_WORD_LEFT" 'backward-word'
        ''     "$EDIT_SELECT_KEY_SEL_WORD_RIGHT" 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}
        esc=${nav_bind[i + 1]}
        wid=${nav_bind[i + 2]}
        [[ -z "$esc" ]] && continue
        seq=${terminfo[$ti]:-$esc}
        zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs       "$seq" "edit-select::${wid}"
        bindkey -M edit-select "$seq" "edit-select::${wid}"
    done

    # Standard macOS movement bindings (non-selecting): Cmd+Left/Right moves to line start/end.
    bindkey -M emacs       '^[[1;9D' beginning-of-line
    bindkey -M emacs       '^[[1;9C' end-of-line
    bindkey -M edit-select '^[[1;9D' beginning-of-line
    bindkey -M edit-select '^[[1;9C' end-of-line

    # Secondary Option+Left / Option+Right aliases for Terminal.app "Use Option as Meta Key" mode.
    # Intentionally hardcoded (not user-configurable) — Terminal.app-specific alternate encoding.
    bindkey -M emacs '\eb' backward-word
    bindkey -M emacs '\ef' forward-word

    local -a dest_bind=(
        'kdch1' '^[[3~' 'edit-select::kill-region'
        'bs'    '^?'    'edit-select::kill-region'
    )
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}
        bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    [[ -n "$EDIT_SELECT_KEY_CUT" ]]  && bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    bindkey -M edit-select '^[[200~'  edit-select::bracketed-paste-replace

    [[ -n "$EDIT_SELECT_KEY_SELECT_ALL" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
    [[ -n "$EDIT_SELECT_KEY_COPY" ]]       && bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    if [[ -n "$EDIT_SELECT_KEY_CUT" ]]; then
        bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
        bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    fi

    [[ -n "$EDIT_SELECT_KEY_WORD_LEFT" ]]  && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_LEFT" backward-word
    [[ -n "$EDIT_SELECT_KEY_WORD_RIGHT" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_RIGHT" forward-word
    bindkey -M edit-select '\e[I'     _zes_terminal_focus_in
    bindkey -M edit-select '\e[O'     _zes_terminal_focus_out
}

# Undo/redo
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# Normalize MOUSE_REPLACEMENT
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1)  EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*)            EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# Startup pre-populate
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

# Apply config
# Re-enable DECSET 1004 on every new prompt so focus events are captured
# by the bound ZLE widgets.  Must be persistent (not one-shot) because
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
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" \
            edit-select::delete-mouse-or-delete
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
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _zes_disable_focus_reporting
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
        add-zle-hook-widget -d line-pre-redraw \
            edit-select::zle-line-pre-redraw 2>/dev/null
        add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting 2>/dev/null
        autoload -Uz add-zsh-hook
        add-zsh-hook -d preexec _zes_disable_focus_reporting 2>/dev/null
        print -n '\e[?1004l' >$TTY
        bindkey -M emacs -r '\e[I' 2>/dev/null
        bindkey -M emacs -r '\e[O' 2>/dev/null
        bindkey -r '\e[I' 2>/dev/null
        bindkey -r '\e[O' 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
    fi
}
edit-select::apply-mouse-replacement-config
