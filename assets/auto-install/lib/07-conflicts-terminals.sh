#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Windows Terminal conflict checks
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_CONFLICTS_TERMINALS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_CONFLICTS_TERMINALS_LOADED=1

check_windows_terminal_conflicts() {
    local config="$WT_SETTINGS_PATH"
    if [[ -z "$config" ]] || [[ ! -f "$config" ]]; then
        return
    fi

    # Conflict: if they already have ctrl+c mapped to something else that we didn't add
    if grep -qi "\"keys\":.*\"ctrl+c\"" "$config" 2>/dev/null; then
        if ! grep -q "\"id\":.*\"User.copy.644BA8F2\"" "$config" 2>/dev/null; then
            # This isn't perfect since JSON is multi-line, but grep works for basic sanity
            print_conflict "Windows Terminal" "ctrl+c binding" "Custom ctrl+c binding found that may conflict with zsh-edit-select's copy action"
        fi
    fi

    # Check for other terminal copy shortcuts that might conflict with reversed mode
    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        if grep -qi "\"keys\":.*\"ctrl+shift+c\"" "$config" 2>/dev/null; then
            if ! grep -q "\"id\":.*\"User.sendIntr\"" "$config" 2>/dev/null; then
                print_conflict "Windows Terminal" "ctrl+shift+c binding" "Existing ctrl+shift+c binding conflicts with reversed copy interrupt mode"
            fi
        fi
    fi
}

# Verification Functions


