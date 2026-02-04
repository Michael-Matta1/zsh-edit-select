# Copyright (c) 2025 Michael Matta
# Version: 0.4.7
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

typeset -g _EDIT_SELECT_MONITOR_BIN="$_EDIT_SELECT_PLUGIN_DIR/backends/x11/zes-selection-monitor"

function _zes_start_monitor() {
    [[ ! -x "$_EDIT_SELECT_MONITOR_BIN" ]] && return

    [[ ! -d "$_EDIT_SELECT_CACHE_DIR" ]] && mkdir -p "$_EDIT_SELECT_CACHE_DIR" 2>/dev/null

    # Check if already running (shared across all shells with same UID)
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi

    "$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
    local pid=$!
    echo "$pid" >"$_EDIT_SELECT_PID_FILE" 2>/dev/null
    disown
    _EDIT_SELECT_DAEMON_ACTIVE=1
}

function _zes_stop_monitor() {
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi
    _EDIT_SELECT_DAEMON_ACTIVE=0
}

function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Read from daemon cache (only called when hook detects change)
        local primary_data
        primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    xclip -selection primary -o 2>/dev/null
}

function _zes_get_clipboard() {
    xclip -selection clipboard -o 2>/dev/null
}

function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    printf '%s' "$1" | xclip -selection clipboard -in 2>/dev/null
}

function _zes_clear_primary() {
    printf '' | xclip -selection primary -in 2>/dev/null
}
