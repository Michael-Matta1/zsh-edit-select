# Copyright (c) 2025 Michael Matta
# Version: 0.4.7
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

function _zes_get_primary() {
    return 1
}

function _zes_get_clipboard() {
    pbpaste 2>/dev/null
}

function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    printf '%s' "$1" | pbcopy 2>/dev/null
}

function _zes_clear_primary() {
    return 1
}

function _zes_start_monitor() { :; }
function _zes_stop_monitor() { :; }
