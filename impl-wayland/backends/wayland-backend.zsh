# Copyright (c) 2025 Michael Matta
# Version: 0.5.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland backend — auto-detects XWayland (invisible) vs pure Wayland monitor.
# Daemon writes to cache files; shell reads via builtins (zero forks during typing).

if [[ -n "${DISPLAY:-}" ]] && [[ -x "${0:A:h}/x11/zes-xwayland-monitor" ]]; then
    typeset -g _ZES_MONITOR_BINARY="${0:A:h}/x11/zes-xwayland-monitor"
    typeset -g _ZES_MONITOR_TYPE="x11"
elif [[ -x "${0:A:h}/wayland/zes-wl-selection-monitor" ]]; then
    typeset -g _ZES_MONITOR_BINARY="${0:A:h}/wayland/zes-wl-selection-monitor"
    typeset -g _ZES_MONITOR_TYPE="wayland"
else
    typeset -g _ZES_MONITOR_BINARY=""
    typeset -g _ZES_MONITOR_TYPE=""
fi

function _zes_start_monitor() {
    [[ -d "$_EDIT_SELECT_CACHE_DIR" ]] || mkdir -p "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1

    if [[ -z "$_ZES_MONITOR_BINARY" ]] || [[ ! -x "$_ZES_MONITOR_BINARY" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi

    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null

    (
        "$_ZES_MONITOR_BINARY" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        disown 2>/dev/null
    )

    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((wait_count++))
    done

    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
        return 0
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi
}

function _zes_stop_monitor() {
    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        pid=$(<"$_EDIT_SELECT_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null
    fi
    _EDIT_SELECT_DAEMON_ACTIVE=0
}

function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        local primary_data
        primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null)
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --oneshot 2>/dev/null
    else
        wl-paste --primary --no-newline 2>/dev/null
    fi
}

function _zes_get_clipboard() {
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --get-clipboard 2>/dev/null
    else
        wl-paste --no-newline 2>/dev/null
    fi
}

function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        printf '%s' "$1" | "$_ZES_MONITOR_BINARY" --copy-clipboard 2>/dev/null
    else
        printf '%s' "$1" | wl-copy 2>/dev/null
    fi
}

function _zes_clear_primary() {
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -x "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --clear-primary 2>/dev/null
    else
        printf '' | wl-copy --primary 2>/dev/null
    fi
}
