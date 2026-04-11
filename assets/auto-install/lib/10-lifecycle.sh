#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Update and uninstall lifecycle actions
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_LIFECYCLE_LOADED:-}" ]] && return 0
readonly _ZES_MOD_LIFECYCLE_LOADED=1

run_plugin_update() {
    print_header "Plugin Update Mode"

    # Init
    check_essential_commands
    acquire_lock

    local mode_status="success"
    local mode_log_size_before=0
    mode_log_size_before="$(_zes_get_log_file_size_bytes)"

    # Detect plugin location
    print_step "Detecting plugin installation..."
    detect_plugin_manager "passive"

    if [[ -z "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Could not determine plugin installation directory"
        print_info "Plugin installation path detection failed. Please run Full Install first."
        _zes_print_mode_completion "Plugin update mode" "warning"
        _zes_prompt_delete_mode_logs "update mode" "$mode_log_size_before"
        return
    fi

    if [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory does not exist: $PLUGIN_INSTALL_DIR"
        print_info "Please run Full Install to install the plugin first."
        _zes_print_mode_completion "Plugin update mode" "warning"
        _zes_prompt_delete_mode_logs "update mode" "$mode_log_size_before"
        return
    fi

    # Check if it's a git repository
    if [[ ! -d "$PLUGIN_INSTALL_DIR/.git" ]]; then
        print_error "Plugin directory is not a git repository: $PLUGIN_INSTALL_DIR"
        print_info "The plugin may have been installed manually or is corrupted."
        print_info "Recommendation: Run Full Install to reinstall from git."
        _zes_print_mode_completion "Plugin update mode" "warning"
        _zes_prompt_delete_mode_logs "update mode" "$mode_log_size_before"
        return
    fi

    # Update the plugin
    print_step "Updating plugin at $PLUGIN_INSTALL_DIR..."

    # Check for network connectivity before attempting pull
    if ! check_network_connectivity; then
        print_error "No network connectivity - cannot update plugin"
        print_info "Please check your internet connection and try again."
        _zes_print_mode_completion "Plugin update mode" "warning"
        _zes_prompt_delete_mode_logs "update mode" "$mode_log_size_before"
        return
    fi

    # Stash any local changes to prevent merge conflicts
    local had_changes=0
    # git diff --quiet returns 0 (success) if there are NO changes
    # Returns non-zero if there ARE changes
    if git -C "$PLUGIN_INSTALL_DIR" diff --quiet 2>/dev/null &&
        git -C "$PLUGIN_INSTALL_DIR" diff --cached --quiet 2>/dev/null; then
        : # No changes - both diff commands succeeded (returned 0)
    else
        had_changes=1
        print_warning "Local changes detected, stashing them before update..."
        git -C "$PLUGIN_INSTALL_DIR" stash push -m "Auto-stash before installer update" 2>&1 | tee -a "$LOG_FILE"
    fi

    # Perform the update (capture output to avoid tee masking git exit status)
    local pull_output
    if pull_output=$(git -C "$PLUGIN_INSTALL_DIR" pull --rebase 2>&1); then
        echo "$pull_output" | tee -a "$LOG_FILE"
        print_success "Plugin updated successfully" "plugin_update"

        # Restore stashed changes if any
        if [[ $had_changes -eq 1 ]]; then
            print_info "Restoring local changes..."
            local stash_output
            if stash_output=$(git -C "$PLUGIN_INSTALL_DIR" stash pop 2>&1); then
                echo "$stash_output" | tee -a "$LOG_FILE"
                print_success "Local changes restored"
            else
                echo "$stash_output" | tee -a "$LOG_FILE"
                print_warning "Could not restore local changes automatically"
                print_info "Your changes are saved in stash: git -C $PLUGIN_INSTALL_DIR stash list"
                mode_status="warning"
            fi
        fi

        # Detect OS/display server for runtime agent refresh
        detect_os
        detect_display_server

        # Stop old agents, clear caches, delete binaries/.zwc, then reinstall and run.
        print_header "Refreshing Agent Runtime"
        reinstall_agents_after_update
    else
        mode_status="warning"
        echo "$pull_output" | tee -a "$LOG_FILE"
        print_error "Failed to update plugin" "plugin_update"
        print_info "Check the log file for details: $LOG_FILE"

        # Try to recover from failed pull
        print_info "Attempting to reset to remote state..."
        local fetch_output reset_output
        local default_branch
        default_branch=$(git -C "$PLUGIN_INSTALL_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        default_branch="${default_branch:-main}"
        if fetch_output=$(git -C "$PLUGIN_INSTALL_DIR" fetch origin 2>&1) &&
            reset_output=$(git -C "$PLUGIN_INSTALL_DIR" reset --hard "origin/$default_branch" 2>&1); then
            echo "$fetch_output" | tee -a "$LOG_FILE"
            echo "$reset_output" | tee -a "$LOG_FILE"
            print_success "Reset to remote state successful"

            # Restore stashed changes if any
            if [[ $had_changes -eq 1 ]]; then
                print_info "Restoring local changes after reset..."
                local stash_output
                if stash_output=$(git -C "$PLUGIN_INSTALL_DIR" stash pop 2>&1); then
                    echo "$stash_output" | tee -a "$LOG_FILE"
                    print_success "Local changes restored"
                else
                    echo "$stash_output" | tee -a "$LOG_FILE"
                    print_warning "Could not restore local changes automatically"
                    print_info "Your changes are saved in stash: git -C $PLUGIN_INSTALL_DIR stash list"
                    mode_status="warning"
                fi
            fi

            # Detect OS/display server for runtime agent refresh
            detect_os
            detect_display_server

            # Stop old agents, clear caches, delete binaries/.zwc, then reinstall and run.
            print_header "Refreshing Agent Runtime"
            reinstall_agents_after_update
        else
            [[ -n "${fetch_output:-}" ]] && echo "$fetch_output" | tee -a "$LOG_FILE"
            [[ -n "${reset_output:-}" ]] && echo "$reset_output" | tee -a "$LOG_FILE"
            print_error "Could not recover from failed update"
            print_info "Manual intervention required. Consider reinstalling the plugin."
            if [[ $had_changes -eq 1 ]]; then
                print_info "Local edits remain in stash. Review with: git -C $PLUGIN_INSTALL_DIR stash list"
            fi
        fi
    fi

    _zes_print_mode_completion "Plugin update mode" "$mode_status"
    _zes_prompt_delete_mode_logs "update mode" "$mode_log_size_before"
}

run_uninstall() {
    print_header "Uninstall Mode"
    acquire_lock
    echo ""
    print_warning "This will remove zsh-edit-select from your system."
    echo ""

    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        if ! ask_yes_no "Are you sure you want to uninstall zsh-edit-select?" "n"; then
            print_info "Uninstall cancelled."
            return
        fi
    fi

    # Detect where the plugin is installed
    print_step "Detecting plugin installation..."
    detect_plugin_manager "passive"

    local uninstall_success=0

    # Step 1: Kill running agents
    print_step "Stopping running agents..."
    if declare -F _zes_stop_agent_processes >/dev/null 2>&1; then
        _zes_stop_agent_processes
    else
        local agents=(
            "zes-macos-clipboard-agent"
            "zes-x11-selection-agent"
            "zes-wl-selection-agent"
            "zes-xwayland-agent"
            "zes-wsl-selection-agent"
            "zes-wsl-clipboard-helper.exe"
            "zes-wsl-xwayland-agent"
        )
        for agent in "${agents[@]}"; do
            if pgrep -f "$agent" &>/dev/null; then
                pkill -f "$agent" 2>/dev/null && print_success "Stopped $agent" || print_warning "Could not stop $agent"
            fi
        done
    fi

    # Step 2: Remove plugin directory/directories
    local -a uninstall_targets=()
    local target_dir=""

    if [[ ${#_ZES_FOUND_PLUGIN_DIRS[@]} -gt 0 ]]; then
        uninstall_targets=("${_ZES_FOUND_PLUGIN_DIRS[@]}")
    elif [[ -n "$PLUGIN_INSTALL_DIR" ]]; then
        uninstall_targets=("$PLUGIN_INSTALL_DIR")
    fi

    if [[ ${#uninstall_targets[@]} -eq 0 ]]; then
        print_warning "Plugin directory not found or not set"
    else
        if [[ ${#uninstall_targets[@]} -gt 1 ]]; then
            print_info "Detected multiple plugin installations; each path will be removed separately."
        fi

        for target_dir in "${uninstall_targets[@]}"; do
            if [[ ! -d "$target_dir" ]]; then
                print_warning "Plugin directory not found: $target_dir"
                continue
            fi

            print_step "Removing plugin directory: $target_dir"

            # Safety checks
            if [[ "$target_dir" == "/" ]] || [[ "$target_dir" == "$HOME" ]] || [[ "$target_dir" == "$HOME/" ]]; then
                print_error "Refusing to remove unsafe path: $target_dir"
                continue
            fi

            if [[ "$target_dir" != *"zsh-edit-select"* ]] && [[ ! -f "$target_dir/zsh-edit-select.plugin.zsh" ]]; then
                print_error "Refusing to remove path that does not look like zsh-edit-select: $target_dir"
                continue
            fi

            if ask_yes_no "Remove plugin directory $target_dir?" "y"; then
                if rm -rf "$target_dir" 2>/dev/null; then
                    print_success "Plugin directory removed" "uninstall_plugin_dir"
                    ((uninstall_success++))
                else
                    print_error "Failed to remove plugin directory"
                    FAILED_STEPS["uninstall_plugin_dir"]="Could not remove $target_dir"
                fi
            else
                print_info "Skipped removing plugin directory: $target_dir"
            fi
        done
    fi

    # Step 3: Remove zshrc entries
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    if [[ -f "$zshrc" ]]; then
        if ask_yes_no "Clean .zshrc?" "y"; then
            print_step "Cleaning .zshrc..."

            if grep -qF "zsh-edit-select" "$zshrc" 2>/dev/null; then
                backup_file "$zshrc"

                # First: clean Oh My Zsh plugin array lines (plugins= and plugins+=).
                if grep -qE '^[[:space:]]*plugins[+]*=.*zsh-edit-select' "$zshrc" 2>/dev/null; then
                    sed_inplace '/^[[:space:]]*plugins[+]*=/s/zsh-edit-select//g' "$zshrc"
                    # Clean up extra spaces in plugin declaration lines.
                    sed_inplace '/^[[:space:]]*plugins[+]*=/s/  */ /g' "$zshrc"
                    # Clean up "( " or " )" left by removed plugin name.
                    sed_inplace '/^[[:space:]]*plugins[+]*=/s/( /(/g; /^[[:space:]]*plugins[+]*=/s/ )/)/g' "$zshrc"
                    # Drop empty plugin declarations that can be left after removal.
                    sed_inplace '/^[[:space:]]*plugins[+]*=[[:space:]]*([[:space:]]*)[[:space:]]*$/d' "$zshrc"
                    print_success "Removed from Oh My Zsh plugins array"
                fi

                # Second: remove standalone lines referencing zsh-edit-select
                # (source lines, zinit/antigen lines, comments, etc.)
                # But NOT the plugins=(...) line which we already cleaned above
                local tmp_zshrc
                tmp_zshrc=$(mktemp) || {
                    print_error "Failed to create temp file for .zshrc cleanup"
                    FAILED_STEPS["uninstall_zshrc"]="Temp file creation failed"
                }

                if [[ -n "$tmp_zshrc" ]]; then
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        # Keep lines that are part of plugins= or plugins+=(...) declarations.
                        if [[ "$line" =~ ^[[:space:]]*plugins[+]*= ]]; then
                            echo "$line" >>"$tmp_zshrc"
                            continue
                        fi
                        # Skip lines that reference zsh-edit-select (source, zinit, etc.)
                        if [[ "$line" == *"zsh-edit-select"* ]]; then
                            continue
                        fi
                        # Skip orphan "# Zsh Edit-Select" comments (with or without suffix)
                        if [[ "$line" =~ ^[[:space:]]*#\ Zsh\ Edit-Select ]]; then
                            continue
                        fi
                        echo "$line" >>"$tmp_zshrc"
                    done <"$zshrc"

                    copy_file_permissions "$zshrc" "$tmp_zshrc"
                    if mv "$tmp_zshrc" "$zshrc" 2>/dev/null; then
                        print_success "Removed plugin entries from .zshrc" "uninstall_zshrc"
                        ((uninstall_success++))
                    else
                        print_error "Failed to update .zshrc"
                        rm -f "$tmp_zshrc"
                        FAILED_STEPS["uninstall_zshrc"]="Could not write to $zshrc"
                    fi
                fi
            else
                print_info "No zsh-edit-select entries found in .zshrc"
            fi
        else
            print_info "Skipped cleaning .zshrc"
        fi
    fi

    # Step 4: Remove terminal config entries
    if ask_yes_no "Clean terminal configurations?" "y"; then
        print_step "Cleaning terminal configurations..."
        local -a terminal_configs=(
            "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
            "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
            "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
            "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
            "$HOME/.wezterm.lua"
            "${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
            "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
        )

        for config_file in "${terminal_configs[@]}"; do
            if [[ -f "$config_file" ]] && grep -qF "Zsh Edit-Select" "$config_file" 2>/dev/null; then
                local basename_file
                basename_file=$(basename "$config_file")
                if ask_yes_no "Remove zsh-edit-select config from $basename_file?" "y"; then
                    backup_file "$config_file"

                    # Remove the block between "# Zsh Edit-Select" / "-- Zsh Edit-Select" marker
                    # and the next empty line or section marker
                    local tmp_config
                    tmp_config=$(mktemp) || {
                        print_error "Failed to create temp file for $basename_file"
                        continue
                    }

                    local in_our_section=0
                    local empty_line_buffer=""
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        if [[ "$line" == *"Zsh Edit-Select"* ]]; then
                            in_our_section=1
                            empty_line_buffer=""
                            continue
                        fi
                        if [[ $in_our_section -eq 1 ]]; then
                            local stripped
                            stripped="$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

                            # Buffer empty lines instead of skipping them outright
                            if [[ -z "$stripped" ]]; then
                                empty_line_buffer+=$'\n'
                                continue
                            fi

                            # Check if it looks like a line we added
                            if [[ "$stripped" == "map "* ]] || [[ "$stripped" == "# Copy"* ]] ||
                                [[ "$stripped" == "# Ctrl+"* ]] || [[ "$stripped" == "# Redo"* ]] ||
                                [[ "$stripped" == "# Cmd"* ]] || [[ "$stripped" == "# Shift"* ]] ||
                                [[ "$stripped" == "# Needed for mouse integration"* ]] ||
                                [[ "$stripped" == "# Disable"* ]] || [[ "$stripped" == "# Pass"* ]] ||
                                [[ "$stripped" == "# (overrides"* ]] ||
                                [[ "$stripped" == "map ctrl+"* ]] ||
                                [[ "$stripped" == "map shift+"* ]] || [[ "$stripped" == "[[keyboard"* ]] ||
                                [[ "$stripped" == "keybind ="* ]] || [[ "$stripped" == "copy-on-select ="* ]] ||
                                [[ "$stripped" == "key ="* ]] || [[ "$stripped" == "mods ="* ]] ||
                                [[ "$stripped" == "chars ="* ]] || [[ "$stripped" == "action ="* ]] ||
                                [[ "$stripped" == "key_bindings:"* ]] ||
                                [[ "$stripped" == "- {"* ]] || [[ "$stripped" == "config.keys"* ]] ||
                                [[ "$stripped" == "local zes_keys"* ]] || [[ "$stripped" == "for _, k"* ]] ||
                                [[ "$stripped" == "{"* && "$stripped" == *"SendString"* ]] ||
                                [[ "$stripped" == "{"* && "$stripped" == *"DisableDefault"* ]] ||
                                [[ "$stripped" == "}" ]] || [[ "$stripped" == "end" ]] ||
                                [[ "$stripped" == "-- "* ]] ||
                                [[ "$stripped" == "clipboard-copy="* ]] ||
                                [[ "$stripped" == "prompt-prev="* ]] ||
                                [[ "$stripped" == "\\x1b["* ]] ||
                                [[ "$stripped" == "\\x03"* ]]; then
                                # Still our config — discard buffered empty lines and skip
                                empty_line_buffer=""
                                continue
                            fi

                            # Not our line — output buffered empty lines and exit section
                            in_our_section=0
                            if [[ -n "$empty_line_buffer" ]]; then
                                printf '%s' "$empty_line_buffer" >>"$tmp_config"
                            fi
                            empty_line_buffer=""
                            echo "$line" >>"$tmp_config"
                        else
                            echo "$line" >>"$tmp_config"
                        fi
                    done <"$config_file"

                    copy_file_permissions "$config_file" "$tmp_config"
                    if mv "$tmp_config" "$config_file" 2>/dev/null; then
                        print_success "Cleaned $basename_file" "uninstall_$basename_file"
                        ((uninstall_success++))
                    else
                        print_error "Failed to update $basename_file"
                        rm -f "$tmp_config"
                    fi
                fi
            fi
        done
    else
        print_info "Skipped cleaning terminal configurations"
    fi

    # Step 5: VS Code keybindings (special handling for JSON)
    local vscode_config=""
    if declare -f _zes_resolve_vscode_keybindings_path >/dev/null 2>&1; then
        vscode_config="$(_zes_resolve_vscode_keybindings_path 2>/dev/null || true)"
    fi
    [[ -z "$vscode_config" ]] && vscode_config="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"

    if [[ -f "$vscode_config" ]] && grep -q "Zsh Edit-Select\|90;6u\|67;6u" "$vscode_config" 2>/dev/null; then
        backup_file "$vscode_config"
        # Try auto-removal with Python (same approach as configure_vscode)
        if command_exists python3; then
            local result
            result=$(
                python3 - "$vscode_config" <<'PYTHON_UNINSTALL'
import json, sys

config_file = sys.argv[1]
try:
    with open(config_file, 'r') as f:
        data = json.load(f)

    if not isinstance(data, list):
        print('SKIP')
        sys.exit(0)

    # Remove entries that contain our escape sequences or marker
    markers = ['67;6u', '90;6u', 'Zsh Edit-Select']
    filtered = []
    for entry in data:
        entry_str = json.dumps(entry)
        if not any(m in entry_str for m in markers):
            filtered.append(entry)

    removed = len(data) - len(filtered)
    if removed > 0:
        with open(config_file, 'w') as f:
            json.dump(filtered, f, indent=4)
        print('REMOVED:' + str(removed))
    else:
        print('NONE')
except Exception as e:
    print('ERROR:' + str(e))
PYTHON_UNINSTALL
                2>&1
            )
            if [[ "$result" == REMOVED:* ]]; then
                local count="${result#REMOVED:}"
                print_success "Removed $count VS Code keybinding(s)" "uninstall_vscode"
                ((uninstall_success++))
            elif [[ "$result" == "NONE" ]] || [[ "$result" == "SKIP" ]]; then
                print_info "No zsh-edit-select VS Code keybindings found to remove"
            else
                print_warning "Auto-removal failed: $result"
                print_info "Please remove entries manually from: $vscode_config"
                MANUAL_STEPS+=("Remove zsh-edit-select keybindings from VS Code: $vscode_config")
            fi
        else
            print_info "VS Code keybindings contain zsh-edit-select entries."
            print_info "Please remove them manually from: $vscode_config"
            print_info "Look for entries containing '67;6u' or '90;6u' escape sequences."
            MANUAL_STEPS+=("Remove zsh-edit-select keybindings from VS Code: $vscode_config")
        fi
    fi

    # Step 6: Remove config directory
    local plugin_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select"
    if [[ -d "$plugin_config_dir" ]]; then
        if ask_yes_no "Remove plugin configuration directory ($plugin_config_dir)?" "y"; then
            rm -rf "$plugin_config_dir" 2>/dev/null && {
                print_success "Plugin config directory removed" "uninstall_config_dir"
                ((uninstall_success++))
            } || {
                print_error "Failed to remove plugin config directory"
            }
        fi
    fi

    # Step 7: Remove Sheldon config entry if applicable
    local sheldon_config="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
    if [[ -f "$sheldon_config" ]] && grep -qF "zsh-edit-select" "$sheldon_config" 2>/dev/null; then
        backup_file "$sheldon_config"
        # Remove any [plugins.*] section that references zsh-edit-select.
        local tmp_sheldon
        tmp_sheldon=$(mktemp) || true
        if [[ -n "$tmp_sheldon" ]]; then
            local line=""
            local section_buffer=""
            local section_is_plugins=0
            local section_has_target=0
            local removed_sections=0

            _zes_flush_sheldon_section() {
                if [[ -n "$section_buffer" ]]; then
                    if [[ $section_is_plugins -eq 1 ]] && [[ $section_has_target -eq 1 ]]; then
                        ((removed_sections++))
                    else
                        printf '%s' "$section_buffer" >>"$tmp_sheldon"
                    fi
                fi
                section_buffer=""
                section_is_plugins=0
                section_has_target=0
            }

            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^\[[^]]+\]$ ]]; then
                    _zes_flush_sheldon_section

                    section_is_plugins=0
                    section_has_target=0

                    if [[ "$line" == "[plugins."* ]]; then
                        section_is_plugins=1
                        if [[ "$line" == *"zsh-edit-select"* ]]; then
                            section_has_target=1
                        fi
                    fi
                fi

                if [[ $section_is_plugins -eq 1 ]] && [[ "$line" == *"zsh-edit-select"* ]]; then
                    section_has_target=1
                fi

                section_buffer+="$line"
                section_buffer+=$'\n'
            done <"$sheldon_config"

            _zes_flush_sheldon_section
            unset -f _zes_flush_sheldon_section

            copy_file_permissions "$sheldon_config" "$tmp_sheldon"
            if mv "$tmp_sheldon" "$sheldon_config" 2>/dev/null; then
                if [[ $removed_sections -gt 0 ]]; then
                    print_success "Cleaned Sheldon config" "uninstall_sheldon"
                    ((uninstall_success++))
                else
                    print_info "No matching Sheldon plugin section found to remove"
                fi
            else
                print_error "Failed to update Sheldon config"
                rm -f "$tmp_sheldon"
            fi
        fi
    fi

    local uninstall_status="success"
    if [[ $uninstall_success -eq 0 ]]; then
        uninstall_status="warning"
    fi

    print_info "Please restart your terminal for changes to take effect."

    _zes_print_mode_completion "Uninstall mode" "$uninstall_status"
}
