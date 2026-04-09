#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: VS Code and Windows Terminal configuration
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_TERMINALS_VSCODE_LOADED:-}" ]] && return 0
readonly _ZES_MOD_TERMINALS_VSCODE_LOADED=1

_zes_vscode_keybindings_candidates() {
    local -a candidates=()

    if [[ "$DETECTED_OS" == "macos" ]]; then
        candidates+=(
            "$HOME/Library/Application Support/Code/User/keybindings.json"
            "$HOME/Library/Application Support/Code - Insiders/User/keybindings.json"
            "$HOME/Library/Application Support/VSCodium/User/keybindings.json"
        )
    elif [[ "$DETECTED_OS" == "wsl" ]]; then
        local win_user
        if command_exists cmd.exe; then
            win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
            if [[ -n "$win_user" ]]; then
                candidates+=(
                    "/mnt/c/Users/${win_user}/AppData/Roaming/Code/User/keybindings.json"
                    "/mnt/c/Users/${win_user}/AppData/Roaming/Code - Insiders/User/keybindings.json"
                    "/mnt/c/Users/${win_user}/AppData/Roaming/VSCodium/User/keybindings.json"
                )
            fi
        fi
        # Fallback for Edge cases or native wayland setups in WSL sharing config
        candidates+=(
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code - OSS/User/keybindings.json"
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/keybindings.json"
            "$HOME/.config/Code/User/keybindings.json"
            "$HOME/.config/Code - OSS/User/keybindings.json"
            "$HOME/.config/Code - Insiders/User/keybindings.json"
        )
    else
        candidates+=(
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code - OSS/User/keybindings.json"
            "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/keybindings.json"
            "$HOME/.config/Code/User/keybindings.json"
            "$HOME/.config/Code - OSS/User/keybindings.json"
            "$HOME/.config/Code - Insiders/User/keybindings.json"
        )
    fi

    printf '%s\n' "${candidates[@]}"
}

_zes_resolve_vscode_keybindings_path() {
    local -a candidates=()
    local candidate

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && candidates+=("$candidate")
    done < <(_zes_vscode_keybindings_candidates)

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    for candidate in "${candidates[@]}"; do
        if [[ -d "$(dirname "$candidate")" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if [[ ${#candidates[@]} -gt 0 ]]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi

    return 1
}

configure_vscode() {
    print_step "Configuring VS Code..."

    local config
    config="$(_zes_resolve_vscode_keybindings_path 2>/dev/null || true)"
    if [[ -z "$config" ]]; then
        print_info "VS Code keybindings path could not be resolved."
        MANUAL_STEPS+=("Configure VS Code keybindings manually (see README)")
        return
    fi

    local config_dir
    config_dir="$(dirname "$config")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_info "VS Code configuration directory is unavailable: $config_dir"
        MANUAL_STEPS+=("Configure VS Code keybindings manually (see README)")
        return
    fi

    # Create file if it doesn't exist
    if [[ ! -f "$config" ]]; then
        echo "[]" >"$config"
        print_substep "Created new keybindings.json"
    else
        backup_config "$config"
    fi

    local is_macos=0
    if [[ "$DETECTED_OS" == "macos" ]]; then
        is_macos=1
    fi

    # Check if already configured (use an OS-specific sentinel sequence)
    if [[ $is_macos -eq 1 ]]; then
        if grep -q "u001b\[122;10u" "$config" 2>/dev/null; then
            print_info "VS Code already configured for zsh-edit-select"
            return
        fi
    else
        if grep -q "u001b\[90;6u" "$config" 2>/dev/null; then
            print_info "VS Code already configured for zsh-edit-select"
            return
        fi
    fi

    local common_bindings=""
    local copy_bindings=""

    if [[ $is_macos -eq 1 ]]; then
        common_bindings=$(
            cat <<EOF
    {
        "key": "cmd+a",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[97;9u" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[99;9u" },
        "when": "terminalFocus && isMac && !terminalTextSelected"
    },
    {
        "key": "cmd+v",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[118;9u" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+x",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[120;9u" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[122;9u" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+shift+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[122;10u" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;9D" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;9C" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "alt+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;3D" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "alt+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;3C" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2D" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2C" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "shift+up",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2A" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "shift+down",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2B" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;10D" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;10C" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "alt+shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;4D" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "alt+shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;4C" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+shift+up",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;10A" },
        "when": "terminalFocus && isMac"
    },
    {
        "key": "cmd+shift+down",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;10B" },
        "when": "terminalFocus && isMac"
    }
EOF
        )
    else
        common_bindings=$(
            cat <<EOF
    {
        "key": "ctrl+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001a" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[90;6u" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2D" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2C" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+up",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2A" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+down",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2B" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+home",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2H" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+end",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2F" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6D" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6C" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+home",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6H" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+end",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6F" },
        "when": "terminalFocus"
    }
EOF
        )

        if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
            copy_bindings=$(
                cat <<EOF
    {
        "key": "ctrl+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[67;6u" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u0003" },
        "when": "terminalFocus"
    }
EOF
            )
        else
            copy_bindings=$(
                cat <<EOF
    {
        "key": "ctrl+shift+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[67;6u" },
        "when": "terminalFocus"
    }
EOF
            )
        fi
    fi

    local shell_insert_block="$common_bindings"
    if [[ -n "$copy_bindings" ]]; then
        shell_insert_block="$shell_insert_block, $copy_bindings"
    fi

    if [[ $is_macos -eq 1 ]] && ! command_exists python3; then
        print_warning "Python3 not found on macOS; VS Code JSON update will use shell fallback."
        print_info "For safer JSON edits, install Python3 (example: brew install python)."
    fi

    # Use python3 to merge JSON if available.
    if command_exists python3; then
        # Write new bindings to a temp file to avoid shell injection issues
        local bindings_tmpfile
        bindings_tmpfile=$(mktemp 2>/dev/null) || {
            print_warning "Failed to create temp file for VS Code config, using shell fallback"
            bindings_tmpfile=""
        }

        if [[ -n "$bindings_tmpfile" ]]; then
            echo "[$shell_insert_block]" >"$bindings_tmpfile"

            local result
            # Pass filepaths as arguments to Python instead of embedding in code
            result=$(
                python3 - "$config" "$bindings_tmpfile" <<'PYTHON_SCRIPT'
import json, sys

config_file = sys.argv[1]
bindings_file = sys.argv[2]

try:
    with open(config_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = []

    if not isinstance(data, list):
        data = []

    with open(bindings_file, 'r') as f:
        new_bindings = json.load(f)

    data.extend(new_bindings)

    with open(config_file, 'w') as f:
        json.dump(data, f, indent=4)

    print('OK')
except Exception as e:
    print('ERROR: ' + str(e))
PYTHON_SCRIPT
                2>&1
            )
            rm -f "$bindings_tmpfile"

            if [[ "$result" == *"OK"* ]]; then
                print_success "VS Code configured successfully (via Python)" "vscode_config"
                return 0
            else
                print_warning "Python update failed: $result"
                print_warning "Falling back to shell method..."
            fi
        fi
    fi

    # Shell fallback (if Python not available or Python method failed)
    print_info "Using shell fallback for JSON update"

    # Shell fallback (sed/echo)
    if grep -q "^[[:space:]]*\[[[:space:]]*\][[:space:]]*$" "$config" 2>/dev/null; then
        # Empty array - replace with our bindings
        echo "[$shell_insert_block]" >"$config" || {
            print_error "Failed to write VS Code config"
            return 1
        }
    else
        # Non-empty array - need to insert before the closing bracket
        local tmpfile
        tmpfile=$(mktemp 2>/dev/null) || {
            print_error "Cannot create temp file for VS Code config"
            return 1
        }

        local found_closing=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Check if this line contains the closing bracket (possibly with whitespace)
            if [[ "$line" =~ ^[[:space:]]*\][[:space:]]*$ ]] && [[ $found_closing -eq 0 ]]; then
                # Insert comma + new bindings before the closing bracket
                echo ",$shell_insert_block" >>"$tmpfile"
                echo "$line" >>"$tmpfile"
                found_closing=1
            else
                echo "$line" >>"$tmpfile"
            fi
        done <"$config"

        if [[ -f "$tmpfile" ]] && [[ -s "$tmpfile" ]] && [[ $found_closing -eq 1 ]]; then
            mv "$tmpfile" "$config" 2>/dev/null || {
                print_error "Failed to update VS Code config with shell fallback"
                rm -f "$tmpfile"
                return 1
            }
        else
            rm -f "$tmpfile"
            print_warning "Could not properly insert into JSON. Please add bindings manually."
            MANUAL_STEPS+=("Add zsh-edit-select keybindings to VS Code keybindings.json (see README)")
            return 1
        fi
    fi
    print_success "VS Code configured successfully (via Shell fallback)" "vscode_config"
}

configure_windows_terminal() {
    print_step "Configuring Windows Terminal..."

    local config="${WT_SETTINGS_PATH:-}"
    if [[ -z "$config" ]] || [[ ! -f "$config" ]]; then
        if find_windows_terminal_settings >/dev/null; then
            config="$WT_SETTINGS_PATH"
        else
            print_error "Cannot find Windows Terminal settings.json"
            return 1
        fi
    fi

    backup_config "$config"

    # Use Python for robust JSON parsing on WSL
    if ! command_exists python3; then
        print_error "Python 3 is required to modify Windows Terminal settings.json"
        MANUAL_STEPS+=("Add zsh-edit-select settings to Windows Terminal manually (see README)")
        return 1
    fi

    local reversed_copy="False"
    [[ "$USER_WANTS_REVERSED_COPY" == "y" ]] && reversed_copy="True"

    # Python script to update settings.json atomically and format safely
    local update_script
    update_script=$(
        cat <<'EOF'
import json
import sys
import os
import shutil
import tempfile

def update_json(file_path, reversed_copy):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # Check if already fully configured
        if data.get('_zes_configured') == True:
            # Need to double check if mode matches preference
            is_reversed = any(a.get('id') == 'User.sendIntr' for a in data.get('actions', []))
            if is_reversed == reversed_copy:
                print("ALREADY_CONFIGURED")
                return 0

        # Mark as configured
        data['_zes_configured'] = True

        # 1. Update copyOnSelect
        data['copyOnSelect'] = False

        # 2. Add/update actions
        if 'actions' not in data:
            data['actions'] = []

        actions = data['actions']
        # Remove any existing zsh-edit-select actions
        actions = [a for a in actions if a.get('id') not in ('User.copy.644BA8F2', 'User.sendIntr')]

        # Add basic copy action
        actions.append({"command": {"action": "copy", "singleLine": False}, "id": "User.copy.644BA8F2"})

        # Add reversed mode action if requested
        if reversed_copy:
            actions.append({"command": {"action": "sendInput", "input": "\u001d"}, "id": "User.sendIntr"})

        data['actions'] = actions

        # 3. Add/update keybindings
        if 'keybindings' not in data:
            data['keybindings'] = []

        keybindings = data['keybindings']
        # Remove existing zsh-edit-select config keybindings
        keybindings = [k for k in keybindings if k.get('id') not in ('User.copy.644BA8F2', 'User.sendIntr')]

        # Add bindings based on mode
        keybindings.append({"id": "User.copy.644BA8F2", "keys": "ctrl+c"})
        if reversed_copy:
            keybindings.append({"id": "User.sendIntr", "keys": "ctrl+shift+c"})

        data['keybindings'] = keybindings

        # Write safely to temp file, then replace
        fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(file_path))
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            # Indent handles multiline pretty-printing
            json.dump(data, f, indent=4, ensure_ascii=False)

        shutil.move(temp_path, file_path)
        print("SUCCESS")
        return 0

    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(update_json(sys.argv[1], sys.argv[2] == "True"))
EOF
    )

    local result
    result=$(python3 -c "$update_script" "$config" "$reversed_copy" 2>&1)
    local py_status=$?

    if [[ $py_status -ne 0 ]]; then
        print_error "Failed to modify Windows Terminal config."
        log_message "WT_CONFIG_ERROR: $result"
        MANUAL_STEPS+=("Add zsh-edit-select settings to Windows Terminal manually (see README)")
        return 1
    fi

    if [[ "$result" == *"ALREADY_CONFIGURED"* ]]; then
        print_info "Windows Terminal already configured for zsh-edit-select"
    else
        # If successfully configured and reversed copy enabled, ensure stty is in .zshrc
        if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
            local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
            if [[ -f "$zshrc" ]] && ! grep -q "stty intr \^\]" "$zshrc" 2>/dev/null; then
                backup_file "$zshrc"
                echo "" >>"$zshrc"
                echo "# Zsh Edit-Select: Required for WSL reversed copy mode (Ctrl+C to copy, Ctrl+Shift+C to interrupt)" >>"$zshrc"
                echo "stty intr ^]" >>"$zshrc"
                print_substep "Added 'stty intr ^]' to .zshrc for Windows Terminal reversed copy mode"
            fi
        fi
        print_success "Windows Terminal configured successfully" "windows_terminal_config"
    fi
}

# Conflict Detection Functions
