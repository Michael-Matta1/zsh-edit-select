# Copyright (c) 2025 Michael Matta
# Version: 0.5.6
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

typeset -g _EDIT_SELECT_MONITOR_BIN="$_EDIT_SELECT_PLUGIN_DIR/backends/x11/zes-x11-selection-monitor"

function _zes_start_monitor() {
    if [[ ! -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        # Silent fallback - will use xclip instead
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    [[ ! -d "$_EDIT_SELECT_CACHE_DIR" ]] && mkdir -p "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi

    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null

    (
        "$_EDIT_SELECT_MONITOR_BIN" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null
    )

    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((wait_count++))
    done

    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
    fi
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
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --get-clipboard 2>/dev/null
    else
        xclip -selection clipboard -o 2>/dev/null
    fi
}

function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        printf '%s' "$1" | "$_EDIT_SELECT_MONITOR_BIN" --copy-clipboard 2>/dev/null
    else
        printf '%s' "$1" | xclip -selection clipboard -in 2>/dev/null
    fi
}

function _zes_clear_primary() {
    if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
        "$_EDIT_SELECT_MONITOR_BIN" --clear-primary 2>/dev/null
    else
        printf '' | xclip -selection primary -in 2>/dev/null
    fi
}
