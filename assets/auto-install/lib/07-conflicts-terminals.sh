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

    if command_exists python3; then
        local conflicts
        conflicts=$(
            python3 - "$config" "$USER_WANTS_REVERSED_COPY" <<'PYTHON_WT_CONFLICTS'
import json
import sys

config_path = sys.argv[1]
reversed_mode = (sys.argv[2].lower() == 'y')


def command_is_copy(cmd):
    if isinstance(cmd, str):
        return cmd.lower() == 'copy'
    if isinstance(cmd, dict):
        return str(cmd.get('action', '')).lower() == 'copy'
    return False


def command_is_send_intr(cmd):
    if not isinstance(cmd, dict):
        return False
    action = str(cmd.get('action', '')).lower()
    if action != 'sendinput':
        return False
    user_input = str(cmd.get('input', ''))
    return user_input in ('\u001d', '\x1d', ']') or (len(user_input) == 1 and ord(user_input) == 0x1D)


def binding_command(binding, actions_by_id):
    if 'command' in binding:
        return binding.get('command')
    binding_id = binding.get('id')
    if binding_id:
        return actions_by_id.get(binding_id)
    return None


def normalize_key(raw):
    return str(raw).strip().lower()


try:
    with open(config_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    # If JSON is invalid/unreadable, keep legacy behavior by not emitting parser noise.
    sys.exit(0)

actions_by_id = {}
for action in data.get('actions', []):
    action_id = action.get('id')
    if action_id:
        actions_by_id[action_id] = action.get('command')

for binding in data.get('keybindings', []):
    key = normalize_key(binding.get('keys', ''))

    if key == 'ctrl+c':
        cmd = binding_command(binding, actions_by_id)
        if binding.get('id') == 'User.copy.644BA8F2' or command_is_copy(cmd):
            continue
        print('ctrl+c|Existing ctrl+c binding may conflict with zsh-edit-select copy action')

    if reversed_mode and key == 'ctrl+shift+c':
        cmd = binding_command(binding, actions_by_id)
        if binding.get('id') == 'User.sendIntr' or command_is_send_intr(cmd):
            continue
        print('ctrl+shift+c|Existing ctrl+shift+c binding conflicts with reversed copy interrupt mode')
PYTHON_WT_CONFLICTS
        )

        if [[ -n "$conflicts" ]]; then
            while IFS='|' read -r existing issue || [[ -n "$existing" ]]; do
                [[ -z "$existing" ]] && continue
                print_conflict "Windows Terminal" "$existing binding" "$issue"
            done <<<"$conflicts"
        fi

        return
    fi

    # Fallback when python3 is unavailable.
    if grep -qi "\"keys\":.*\"ctrl+c\"" "$config" 2>/dev/null; then
        if ! grep -q "\"id\":.*\"User.copy.644BA8F2\"" "$config" 2>/dev/null; then
            print_conflict "Windows Terminal" "ctrl+c binding" "Custom ctrl+c binding found that may conflict with zsh-edit-select's copy action"
        fi
    fi

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        if grep -qi "\"keys\":.*\"ctrl+shift+c\"" "$config" 2>/dev/null; then
            if ! grep -q "\"id\":.*\"User.sendIntr\"" "$config" 2>/dev/null; then
                print_conflict "Windows Terminal" "ctrl+shift+c binding" "Existing ctrl+shift+c binding conflicts with reversed copy interrupt mode"
            fi
        fi
    fi
}

# Verification Functions
