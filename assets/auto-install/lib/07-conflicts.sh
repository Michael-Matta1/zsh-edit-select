#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Conflict detection orchestration and terminal checks
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_CONFLICTS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_CONFLICTS_LOADED=1

check_conflicts() {
    local conflict_mode_context="${1:-post-config}"

    if [[ $SKIP_CONFLICTS -eq 1 ]]; then
        print_info "Skipping conflict detection (--skip-conflicts flag)"
        return
    fi

    local terminal_conflicts_status=0
    local terminal_conflicts_partial=0

    print_step "Checking for Zsh keybinding conflicts..."
    check_zsh_conflicts

    print_step "Checking for terminal configuration conflicts..."
    check_terminal_conflicts
    terminal_conflicts_status=$?
    if [[ $terminal_conflicts_status -eq 10 ]]; then
        terminal_conflicts_partial=1
    fi

    if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
        echo ""
        echo ""
        sleep 0.1

        # Use terminal width for the box (cap 42–78) so it never overflows
        local term_cols box_width
        term_cols=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
        [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80
        [[ "$term_cols" -lt 42 ]] && term_cols=42
        [[ "$term_cols" -gt 78 ]] && term_cols=78
        box_width=$((term_cols - 2)) # -2 for the ║ on each side
        # Use [!] instead of ⚠ (U+26A0): ⚠ is ambiguous-width and renders as
        # 2 columns in many terminals, causing printf padding to be off by 1
        # and the closing ║ to visually overlap the next output line.
        local conflict_msg="[!] Found $TOTAL_CONFLICTS potential configuration conflict(s)"
        local padded_msg
        if ((${#conflict_msg} > box_width)); then
            box_width=${#conflict_msg}
        fi
        padded_msg=$(zes_center_text "$box_width" "$conflict_msg")
        echo -e "${BOLD}${YELLOW}╔$(printf '═%.0s' $(seq 1 $box_width))╗${NC}"
        echo -e "${BOLD}${YELLOW}║${padded_msg}║${NC}"
        echo -e "${BOLD}${YELLOW}╚$(printf '═%.0s' $(seq 1 $box_width))╝${NC}"
        echo ""
        echo -e "${BOLD}Conflict Resolution Guide:${NC}"
        echo ""
        echo -e "  ${CYAN}1.${NC} Review each conflict listed above"
        echo -e "  ${CYAN}2.${NC} Open the affected configuration file(s):"
        for file in "${!CONFLICTS[@]}"; do
            echo -e "     ${BOLD}→${NC} $file"
        done
        echo -e "  ${CYAN}3.${NC} For each conflict, either:"
        echo -e "     • ${GREEN}Remove${NC} the old binding (recommended)"
        echo -e "     • ${GREEN}Comment out${NC} the old binding (add # at the start)"
        echo -e "     • ${GREEN}Remap${NC} the old binding to a different key"
        if [[ "$conflict_mode_context" == "scan-only" ]]; then
            echo -e "  ${CYAN}4.${NC} Resolve these conflicts before applying or reapplying terminal configuration"
            echo ""
            echo -e "  ${DIM}This mode only scans existing configuration files."
            echo -e "  Existing conflicting bindings may still override desired behavior until resolved.${NC}"
        else
            echo -e "  ${CYAN}4.${NC} Keep the zsh-edit-select bindings for the best experience"
            echo ""
            echo -e "  ${DIM}The zsh-edit-select bindings were already added to your config."
            echo -e "  Conflicting bindings may override them if not resolved.${NC}"
        fi
        echo ""
    else
        if [[ $terminal_conflicts_partial -eq 1 ]]; then
            print_success "No configuration conflicts detected for checked terminals" "conflicts_check"
            print_warning "Conflict checks were skipped for one or more detected terminals"
        else
            print_success "No configuration conflicts detected" "conflicts_check"
        fi
    fi
}


check_zsh_conflicts() {
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"

    if [[ ! -f "$zshrc" ]]; then
        print_warning ".zshrc not found, skipping Zsh conflict check"
        return
    fi

    # Keybinding patterns that may conflict with zsh-edit-select
    local -a conflict_patterns=(
        'bindkey.*["'"'"']\^C["'"'"']'
        'bindkey.*["'"'"']\^X["'"'"']'
        'bindkey.*["'"'"']\^V["'"'"']'
        'bindkey.*["'"'"']\^Z["'"'"']'
        'bindkey.*["'"'"']\^\[\[3~["'"'"'].*delete-char'
        'bindkey.*["'"'"']\^\[\[1;2["'"'"']'
        'bindkey.*["'"'"']\^\[\[1;5["'"'"']'
        'bindkey.*["'"'"']\^\[\[1;6["'"'"']'
    )

    local found_conflicts=0
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"

        # Skip empty lines and comments
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        # Skip lines that are part of zsh-edit-select itself
        [[ "$stripped" =~ zsh-edit-select ]] && continue

        for pattern in "${conflict_patterns[@]}"; do
            if [[ "$stripped" =~ $pattern ]]; then
                print_conflict ".zshrc:$line_num" "$stripped" "zsh-edit-select uses this key"
                found_conflicts=1
            fi
        done
    done <"$zshrc"

    if [[ $found_conflicts -eq 0 ]]; then
        print_success "No Zsh keybinding conflicts found"
    fi
}


_zes_conflict_terminal_label() {
    local terminal="$1"

    case "$terminal" in
    kitty) echo "Kitty" ;;
    alacritty) echo "Alacritty" ;;
    wezterm) echo "WezTerm" ;;
    foot) echo "Foot" ;;
    iterm2) echo "iTerm2" ;;
    ghostty) echo "Ghostty" ;;
    vscode) echo "VS Code (Integrated Terminal)" ;;
    windows-terminal) echo "Windows Terminal (WSL)" ;;
    *) echo "$terminal" ;;
    esac
}


_zes_check_terminal_conflicts_for_terminal() {
    local terminal="$1"
    local config=""

    case "$terminal" in
    kitty)
        config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
        [[ -f "$config" ]] || return 2
        check_kitty_conflicts "$config"
        ;;
    alacritty)
        config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
        [[ ! -f "$config" ]] && config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
        [[ -f "$config" ]] || return 2
        check_alacritty_conflicts "$config"
        ;;
    wezterm)
        config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
        [[ ! -f "$config" ]] && config="$HOME/.wezterm.lua"
        [[ -f "$config" ]] || return 2
        check_wezterm_conflicts "$config"
        ;;
    foot)
        config="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
        [[ -f "$config" ]] || return 2
        check_foot_conflicts "$config"
        ;;
    ghostty)
        config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
        [[ -f "$config" ]] || return 2
        check_ghostty_conflicts "$config"
        ;;
    iterm2)
        # iTerm2 keybinding conflict detection is not yet implemented.
        return 2
        ;;
    vscode)
        if declare -f _zes_resolve_vscode_keybindings_path >/dev/null 2>&1; then
            config="$(_zes_resolve_vscode_keybindings_path 2>/dev/null || true)"
        else
            config="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
        fi
        [[ -f "$config" ]] || return 2
        check_vscode_conflicts "$config"
        ;;
    windows-terminal)
        config="${WT_SETTINGS_PATH:-}"
        [[ -f "$config" ]] || return 2
        check_windows_terminal_conflicts
        ;;
    *)
        return 1
        ;;
    esac

    return 0
}


_zes_check_terminal_conflicts_with_report() {
    local terminal="$1"
    local label
    label="$(_zes_conflict_terminal_label "$terminal")"

    local before_conflicts=$TOTAL_CONFLICTS
    _zes_check_terminal_conflicts_for_terminal "$terminal"
    local rc=$?
    local after_conflicts=$TOTAL_CONFLICTS

    if [[ $rc -eq 2 ]]; then
        print_info "No conflict-checkable config found for ${label}; skipping."
        return 0
    fi

    if [[ $rc -ne 0 ]]; then
        print_warning "Unsupported terminal for conflict detection: ${label}"
        return 1
    fi

    local new_conflicts=$((after_conflicts - before_conflicts))
    if [[ $new_conflicts -gt 0 ]]; then
        print_warning "Detected ${new_conflicts} potential conflict(s) for ${label}"
    else
        print_success "No conflicts found for ${label}"
    fi

    return 0
}


check_terminal_conflicts() {
    local -a selectable_terminals=()
    local -a ignored_terminals=()
    local -a manual_terminals=()
    local terminal

    for terminal in "${DETECTED_TERMINALS[@]}"; do
        case "$terminal" in
        kitty | alacritty | wezterm | foot | iterm2 | ghostty | vscode | windows-terminal)
            selectable_terminals+=("$terminal")
            ;;
        konsole | gnome-terminal | xfce4-terminal | terminator | tilix)
            ignored_terminals+=("$terminal")
            ;;
        *)
            manual_terminals+=("$terminal")
            ;;
        esac
    done

    if [[ ${#manual_terminals[@]} -gt 0 ]]; then
        print_info "Detected terminals that may require manual conflict checks:"
        for terminal in "${manual_terminals[@]}"; do
            print_substep "$terminal (see README.md)"
        done
    fi

    if [[ ${#ignored_terminals[@]} -gt 0 ]]; then
        print_info "Ignoring unsupported terminals for this conflict check step:"
        for terminal in "${ignored_terminals[@]}"; do
            print_substep "$terminal"
        done
    fi

    if [[ ${#selectable_terminals[@]} -eq 0 ]]; then
        print_info "No supported detected terminals available for conflict detection."
        return 0
    fi

    # In non-interactive mode, check every supported detected terminal.
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_info "Non-interactive mode: checking all supported detected terminals."
        for terminal in "${selectable_terminals[@]}"; do
            _zes_check_terminal_conflicts_with_report "$terminal"
        done
        return 0
    fi

    local -a pending_terminals=("${selectable_terminals[@]}")

    while true; do
        if [[ ${#pending_terminals[@]} -eq 0 ]]; then
            print_success "Terminal conflict checks completed for all selected terminals."
            break
        fi

        local -a menu_options=()
        local -a option_terminals=()

        for terminal in "${pending_terminals[@]}"; do
            menu_options+=("$(_zes_conflict_terminal_label "$terminal")")
            option_terminals+=("$terminal")
        done

        menu_options+=("Check all listed terminals")
        menu_options+=("Proceed without checking more terminals")

        ask_choice "Select a terminal conflict detection action:" "${menu_options[@]}"
        local choice="$CHOICE_RESULT"
        local check_all_index=$(( ${#option_terminals[@]} + 1 ))
        local proceed_index=$(( ${#option_terminals[@]} + 2 ))

        if [[ "$choice" -eq "$check_all_index" ]]; then
            for terminal in "${pending_terminals[@]}"; do
                _zes_check_terminal_conflicts_with_report "$terminal"
            done
            pending_terminals=()
            continue
        fi

        if [[ "$choice" -eq "$proceed_index" ]]; then
            if [[ ${#pending_terminals[@]} -gt 0 ]]; then
                print_info "Skipped terminal conflict checks for:"
                for terminal in "${pending_terminals[@]}"; do
                    print_substep "$(_zes_conflict_terminal_label "$terminal")"
                done
            fi
            print_info "Terminal conflict detection step completed."
            return 10
        fi

        local selected_terminal_index=$((choice - 1))
        local selected_terminal="${option_terminals[$selected_terminal_index]}"
        _zes_check_terminal_conflicts_with_report "$selected_terminal"

        local -a next_pending=()
        local t
        for t in "${pending_terminals[@]}"; do
            [[ "$t" == "$selected_terminal" ]] && continue
            next_pending+=("$t")
        done
        pending_terminals=("${next_pending[@]}")

        if [[ ${#pending_terminals[@]} -gt 0 ]]; then
            if ! ask_yes_no "Would you like to check conflicts for another detected terminal?" "y"; then
                print_info "Skipped terminal conflict checks for:"
                for terminal in "${pending_terminals[@]}"; do
                    print_substep "$(_zes_conflict_terminal_label "$terminal")"
                done
                print_info "Terminal conflict detection step completed."
                return 10
            fi
        fi
    done

    return 0
}


_zes_compact_lower() {
    local value="${1,,}"
    value="${value//[[:space:]]/}"
    printf '%s' "$value"
}


_zes_normalize_escape_value() {
    local value="$( _zes_compact_lower "$1" )"
    value="${value//$'\x1b'/\\x1b}"
    value="${value//\\u001b/\\x1b}"
    value="${value//\\e/\\x1b}"
    printf '%s' "$value"
}


_zes_value_has_csi_code() {
    local value
    value="$(_zes_normalize_escape_value "$1")"
    [[ "$value" == *"[$2"* ]]
}


_zes_value_is_interrupt_code() {
    local value
    value="$(_zes_normalize_escape_value "$1")"
    [[ "$value" == *"\\x03"* ]] || [[ "$value" == *"\\u0003"* ]]
}


_zes_kitty_key_is_watched() {
    local key="$1"
    case "$key" in
    ctrl+c | ctrl+shift+c | ctrl+shift+z | shift+left | shift+right | shift+up | shift+down | shift+home | shift+end | ctrl+shift+left | ctrl+shift+right | ctrl+shift+home | ctrl+shift+end)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}


_zes_kitty_binding_is_expected() {
    local key="$1"
    local action
    action="$(_zes_normalize_escape_value "$2")"

    case "$key" in
    shift+left | shift+right | shift+up | shift+down | shift+home | shift+end | ctrl+shift+left | ctrl+shift+right | ctrl+shift+home | ctrl+shift+end)
        [[ "$action" == "no_op" ]]
        return
        ;;
    ctrl+shift+z)
        [[ "$action" == send_textall* ]] && _zes_value_has_csi_code "$action" "90;6u"
        return
        ;;
    ctrl+c)
        [[ "$action" == send_textall* ]] && _zes_value_has_csi_code "$action" "67;6u"
        return
        ;;
    ctrl+shift+c)
        [[ "$action" == send_textall* ]] && {
            _zes_value_has_csi_code "$action" "67;6u" || _zes_value_is_interrupt_code "$action"
        }
        return
        ;;
    esac

    return 1
}


check_kitty_conflicts() {
    local config="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        local stripped
        stripped="$(strip_line "$line")"

        # Skip empty and comment lines.
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        # Only evaluate map directives for watched keys.
        if ! [[ "$stripped" =~ ^map[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
            continue
        fi

        local key="${BASH_REMATCH[1],,}"
        local action="${BASH_REMATCH[2]}"

        _zes_kitty_key_is_watched "$key" || continue

        if ! _zes_kitty_binding_is_expected "$key" "$action"; then
            print_conflict "kitty.conf:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
        fi
    done <"$config"
}


_zes_unquote_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" == \"*\" ]] && [[ "$value" == *\" ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' ]] && [[ "$value" == *\' ]]; then
        value="${value:1:${#value}-2}"
    fi

    printf '%s' "$value"
}


_zes_mods_equals_any() {
    local mods
    mods="$(_zes_compact_lower "$1")"
    shift

    local candidate
    for candidate in "$@"; do
        [[ "$mods" == "$candidate" ]] && return 0
    done

    return 1
}


_zes_alacritty_binding_is_monitored() {
    local key="${1,,}"
    local mods="$2"

    case "$key" in
    c)
        _zes_mods_equals_any "$mods" "control|shift" "shift|control" "control"
        return
        ;;
    z)
        _zes_mods_equals_any "$mods" "control|shift" "shift|control" "command" "command|shift" "shift|command"
        return
        ;;
    home | end)
        _zes_mods_equals_any "$mods" "shift"
        return
        ;;
    a | v | x)
        _zes_mods_equals_any "$mods" "command"
        return
        ;;
    esac

    return 1
}


_zes_alacritty_binding_is_expected() {
    local key="${1,,}"
    local mods="$2"
    local chars="$3"
    local action="$4"

    local chars_norm
    chars_norm="$(_zes_normalize_escape_value "$chars")"
    local action_norm
    action_norm="$(_zes_compact_lower "$action")"

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "control|shift" "shift|control"; then
        _zes_value_has_csi_code "$chars_norm" "67;6u" || _zes_value_is_interrupt_code "$chars_norm"
        return
    fi

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "control"; then
        _zes_value_has_csi_code "$chars_norm" "67;6u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "control|shift" "shift|control"; then
        _zes_value_has_csi_code "$chars_norm" "90;6u"
        return
    fi

    if [[ "$key" == "home" ]] && _zes_mods_equals_any "$mods" "shift"; then
        [[ "$action_norm" == "receivechar" ]] || [[ "$action_norm" == "\"receivechar\"" ]]
        return
    fi

    if [[ "$key" == "end" ]] && _zes_mods_equals_any "$mods" "shift"; then
        [[ "$action_norm" == "receivechar" ]] || [[ "$action_norm" == "\"receivechar\"" ]]
        return
    fi

    if [[ "$key" == "a" ]] && _zes_mods_equals_any "$mods" "command"; then
        _zes_value_has_csi_code "$chars_norm" "97;9u"
        return
    fi

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "command"; then
        _zes_value_has_csi_code "$chars_norm" "99;9u"
        return
    fi

    if [[ "$key" == "v" ]] && _zes_mods_equals_any "$mods" "command"; then
        _zes_value_has_csi_code "$chars_norm" "118;9u"
        return
    fi

    if [[ "$key" == "x" ]] && _zes_mods_equals_any "$mods" "command"; then
        _zes_value_has_csi_code "$chars_norm" "120;9u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "command"; then
        _zes_value_has_csi_code "$chars_norm" "122;9u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "command|shift" "shift|command"; then
        _zes_value_has_csi_code "$chars_norm" "122;10u"
        return
    fi

    return 1
}


_zes_alacritty_report_conflict_if_needed() {
    local line_num="$1"
    local key="$2"
    local mods="$3"
    local chars="$4"
    local action="$5"
    local display_line="$6"

    _zes_alacritty_binding_is_monitored "$key" "$mods" || return 0
    _zes_alacritty_binding_is_expected "$key" "$mods" "$chars" "$action" && return 0

    if [[ -z "$display_line" ]]; then
        display_line="key=$key mods=$mods chars=$chars action=$action"
    fi

    print_conflict "alacritty config:$line_num" "$display_line" "May conflict with zsh-edit-select bindings"
}


check_alacritty_conflicts() {
    local config="$1"
    local line_num=0

    if [[ "$config" == *.yml ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_num++))
            local stripped
            stripped="$(strip_line "$line")"
            [[ -z "$stripped" ]] && continue
            [[ "$stripped" =~ ^# ]] && continue

            if [[ "$stripped" =~ ^-[[:space:]]*\{ ]]; then
                local key=""
                local mods=""
                local chars=""
                local action=""

                if [[ "$stripped" =~ key:[[:space:]]*([^,}]+) ]]; then
                    key="$(_zes_unquote_value "${BASH_REMATCH[1]}")"
                fi
                if [[ "$stripped" =~ mods:[[:space:]]*([^,}]+) ]]; then
                    mods="$(_zes_unquote_value "${BASH_REMATCH[1]}")"
                fi
                if [[ "$stripped" =~ chars:[[:space:]]*([^,}]+) ]]; then
                    chars="$(_zes_unquote_value "${BASH_REMATCH[1]}")"
                fi
                if [[ "$stripped" =~ action:[[:space:]]*([^,}]+) ]]; then
                    action="$(_zes_unquote_value "${BASH_REMATCH[1]}")"
                fi

                _zes_alacritty_report_conflict_if_needed "$line_num" "$key" "$mods" "$chars" "$action" "$stripped"
            fi
        done <"$config"

        return
    fi

    local in_binding=0
    local binding_start_line=0
    local binding_key=""
    local binding_mods=""
    local binding_chars=""
    local binding_action=""
    local binding_display=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"

        if [[ "$stripped" == "[[keyboard.bindings]]" ]]; then
            if [[ $in_binding -eq 1 ]]; then
                _zes_alacritty_report_conflict_if_needed "$binding_start_line" "$binding_key" "$binding_mods" "$binding_chars" "$binding_action" "$binding_display"
            fi

            in_binding=1
            binding_start_line="$line_num"
            binding_key=""
            binding_mods=""
            binding_chars=""
            binding_action=""
            binding_display="$stripped"
            continue
        fi

        [[ $in_binding -eq 0 ]] && continue
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        binding_display+=" ${stripped}"

        if [[ "$stripped" =~ ^key[[:space:]]*= ]]; then
            binding_key="$(_zes_unquote_value "${stripped#*=}")"
            continue
        fi
        if [[ "$stripped" =~ ^mods[[:space:]]*= ]]; then
            binding_mods="$(_zes_unquote_value "${stripped#*=}")"
            continue
        fi
        if [[ "$stripped" =~ ^chars[[:space:]]*= ]]; then
            binding_chars="$(_zes_unquote_value "${stripped#*=}")"
            continue
        fi
        if [[ "$stripped" =~ ^action[[:space:]]*= ]]; then
            binding_action="$(_zes_unquote_value "${stripped#*=}")"
        fi
    done <"$config"

    if [[ $in_binding -eq 1 ]]; then
        _zes_alacritty_report_conflict_if_needed "$binding_start_line" "$binding_key" "$binding_mods" "$binding_chars" "$binding_action" "$binding_display"
    fi
}


_zes_wezterm_binding_is_monitored() {
    local key="${1,,}"
    local mods="$2"

    case "$key" in
    c)
        _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl" "ctrl" "cmd"
        return
        ;;
    z)
        _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl" "cmd" "cmd|shift" "shift|cmd"
        return
        ;;
    leftarrow | rightarrow)
        _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl" "cmd" "cmd|shift" "shift|cmd"
        return
        ;;
    home | end)
        _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"
        return
        ;;
    uparrow | downarrow)
        _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"
        return
        ;;
    a | v | x)
        _zes_mods_equals_any "$mods" "cmd"
        return
        ;;
    esac

    return 1
}


_zes_wezterm_binding_is_expected() {
    local key="${1,,}"
    local mods="$2"
    local action_blob
    action_blob="$(_zes_normalize_escape_value "$3")"

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        (_zes_value_has_csi_code "$action_blob" "67;6u") || (_zes_value_is_interrupt_code "$action_blob")
        return
    fi

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "ctrl"; then
        _zes_value_has_csi_code "$action_blob" "67;6u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        _zes_value_has_csi_code "$action_blob" "90;6u"
        return
    fi

    if [[ "$key" == "leftarrow" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        [[ "$action_blob" == *"disabledefaultassignment"* ]]
        return
    fi

    if [[ "$key" == "rightarrow" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        [[ "$action_blob" == *"disabledefaultassignment"* ]]
        return
    fi

    if [[ "$key" == "home" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        [[ "$action_blob" == *"disabledefaultassignment"* ]]
        return
    fi

    if [[ "$key" == "end" ]] && _zes_mods_equals_any "$mods" "ctrl|shift" "shift|ctrl"; then
        [[ "$action_blob" == *"disabledefaultassignment"* ]]
        return
    fi

    if [[ "$key" == "a" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "97;9u"
        return
    fi

    if [[ "$key" == "c" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "99;9u"
        return
    fi

    if [[ "$key" == "v" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "118;9u"
        return
    fi

    if [[ "$key" == "x" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "120;9u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "122;9u"
        return
    fi

    if [[ "$key" == "z" ]] && _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"; then
        _zes_value_has_csi_code "$action_blob" "122;10u"
        return
    fi

    if [[ "$key" == "leftarrow" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;9d"
        return
    fi

    if [[ "$key" == "rightarrow" ]] && _zes_mods_equals_any "$mods" "cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;9c"
        return
    fi

    if [[ "$key" == "leftarrow" ]] && _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;10d"
        return
    fi

    if [[ "$key" == "rightarrow" ]] && _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;10c"
        return
    fi

    if [[ "$key" == "uparrow" ]] && _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;10a"
        return
    fi

    if [[ "$key" == "downarrow" ]] && _zes_mods_equals_any "$mods" "cmd|shift" "shift|cmd"; then
        _zes_value_has_csi_code "$action_blob" "1;10b"
        return
    fi

    return 1
}


_zes_wezterm_report_conflict_if_needed() {
    local line_num="$1"
    local key="$2"
    local mods="$3"
    local action_blob="$4"

    _zes_wezterm_binding_is_monitored "$key" "$mods" || return 0
    _zes_wezterm_binding_is_expected "$key" "$mods" "$action_blob" && return 0

    print_conflict "wezterm.lua:$line_num" "$action_blob" "May conflict with zsh-edit-select bindings"
}


check_wezterm_conflicts() {
    local config="$1"
    local line_num=0

    local in_binding=0
    local binding_key=""
    local binding_mods=""
    local binding_start_line=0
    local binding_blob=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        local regex_line
        regex_line="${stripped//\'/\"}"
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^-- ]] && continue

        if [[ $in_binding -eq 0 ]]; then
            if [[ "$regex_line" =~ key[[:space:]]*=[[:space:]]\"([^\"]+)\" ]]; then
                in_binding=1
                binding_start_line="$line_num"
                binding_key="${BASH_REMATCH[1]}"
                binding_mods=""
                binding_blob="$stripped"

                if [[ "$regex_line" =~ mods[[:space:]]*=[[:space:]]\"([^\"]+)\" ]]; then
                    binding_mods="${BASH_REMATCH[1]}"
                fi

                if [[ "$stripped" == *"},"* ]]; then
                    _zes_wezterm_report_conflict_if_needed "$binding_start_line" "$binding_key" "$binding_mods" "$binding_blob"
                    in_binding=0
                fi
            fi
            continue
        fi

        binding_blob+=" ${stripped}"

        if [[ -z "$binding_mods" ]] && [[ "$regex_line" =~ mods[[:space:]]*=[[:space:]]\"([^\"]+)\" ]]; then
            binding_mods="${BASH_REMATCH[1]}"
        fi

        if [[ "$stripped" == *"},"* ]] || [[ "$stripped" == "}" ]]; then
            _zes_wezterm_report_conflict_if_needed "$binding_start_line" "$binding_key" "$binding_mods" "$binding_blob"
            in_binding=0
        fi
    done <"$config"

    if [[ $in_binding -eq 1 ]]; then
        _zes_wezterm_report_conflict_if_needed "$binding_start_line" "$binding_key" "$binding_mods" "$binding_blob"
    fi
}


_zes_foot_text_binding_is_expected() {
    local lhs="$1"
    local rhs
    rhs="$(_zes_compact_lower "$2")"

    case "$rhs" in
    control+shift+c)
        _zes_value_has_csi_code "$lhs" "67;6u" || _zes_value_is_interrupt_code "$lhs"
        return
        ;;
    control+c)
        _zes_value_has_csi_code "$lhs" "67;6u"
        return
        ;;
    control+shift+z)
        _zes_value_has_csi_code "$lhs" "90;6u"
        return
        ;;
    esac

    return 1
}


check_foot_conflicts() {
    local config="$1"
    local in_keybindings=0
    local in_textbindings=0
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        if [[ "$stripped" == "[key-bindings]" ]]; then
            in_keybindings=1
            in_textbindings=0
            continue
        fi
        if [[ "$stripped" == "[text-bindings]" ]]; then
            in_textbindings=1
            in_keybindings=0
            continue
        fi
        if [[ "$stripped" =~ ^\[ ]] && [[ "$stripped" != "[key-bindings]" ]] && [[ "$stripped" != "[text-bindings]" ]]; then
            in_keybindings=0
            in_textbindings=0
        fi

        if [[ $in_keybindings -eq 1 ]] && [[ "$stripped" =~ ^([^=]+)=(.+)$ ]]; then
            local key_name
            key_name="$(_zes_compact_lower "${BASH_REMATCH[1]}")"
            local key_value
            key_value="$(_zes_compact_lower "${BASH_REMATCH[2]}")"

            if [[ "$key_name" == "clipboard-copy" ]] || [[ "$key_name" == "prompt-prev" ]]; then
                if [[ "$key_value" != "none" ]]; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
                fi
            fi
            continue
        fi

        if [[ $in_textbindings -eq 1 ]] && [[ "$stripped" =~ ^([^=]+)=(.+)$ ]]; then
            local lhs
            lhs="$(_zes_unquote_value "${BASH_REMATCH[1]}")"
            local rhs
            rhs="$(_zes_unquote_value "${BASH_REMATCH[2]}")"
            local rhs_norm
            rhs_norm="$(_zes_compact_lower "$rhs")"

            if [[ "$rhs_norm" == "control+shift+c" ]] || [[ "$rhs_norm" == "control+c" ]] || [[ "$rhs_norm" == "control+shift+z" ]]; then
                if ! _zes_foot_text_binding_is_expected "$lhs" "$rhs"; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select text-bindings"
                fi
            fi
        fi
    done <"$config"
}


_zes_ghostty_binding_is_watched() {
    local key="$1"
    case "$key" in
    ctrl+c | ctrl+shift+c | ctrl+shift+z | ctrl+shift+left | ctrl+shift+right | ctrl+shift+home | ctrl+shift+end | cmd+a | cmd+c | cmd+x | cmd+z | cmd+shift+z | shift+up | shift+down | cmd+shift+up | cmd+shift+down)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}


_zes_ghostty_binding_is_expected() {
    local key="$1"
    local value
    value="$(_zes_normalize_escape_value "$2")"

    case "$key" in
    ctrl+shift+c)
        [[ "$value" == "csi:67;6u" ]] || [[ "$value" == "text:\\x03" ]]
        return
        ;;
    ctrl+c)
        [[ "$value" == "csi:67;6u" ]]
        return
        ;;
    ctrl+shift+z)
        [[ "$value" == "csi:90;6u" ]]
        return
        ;;
    ctrl+shift+left | ctrl+shift+right | ctrl+shift+home | ctrl+shift+end)
        [[ "$value" == "unbind" ]]
        return
        ;;
    cmd+a)
        [[ "$value" == "csi:97;9u" ]]
        return
        ;;
    cmd+c)
        [[ "$value" == "csi:99;9u" ]]
        return
        ;;
    cmd+x)
        [[ "$value" == "csi:120;9u" ]]
        return
        ;;
    cmd+z)
        [[ "$value" == "csi:122;9u" ]]
        return
        ;;
    cmd+shift+z)
        [[ "$value" == "csi:122;10u" ]]
        return
        ;;
    shift+up)
        [[ "$value" == "csi:1;2a" ]]
        return
        ;;
    shift+down)
        [[ "$value" == "csi:1;2b" ]]
        return
        ;;
    cmd+shift+up)
        [[ "$value" == "csi:1;10a" ]]
        return
        ;;
    cmd+shift+down)
        [[ "$value" == "csi:1;10b" ]]
        return
        ;;
    esac

    return 1
}


check_ghostty_conflicts() {
    local config="$1"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        if [[ "$stripped" =~ ^keybind[[:space:]]*= ]]; then
            local payload
            payload="$(_zes_compact_lower "${stripped#*=}")"
            local binding_key="${payload%%=*}"
            local binding_value="${payload#*=}"

            _zes_ghostty_binding_is_watched "$binding_key" || continue

            if ! _zes_ghostty_binding_is_expected "$binding_key" "$binding_value"; then
                print_conflict "ghostty config:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
            fi
        fi
    done <"$config"
}


_zes_vscode_key_is_watched() {
    local key="$1"
    case "$key" in
    ctrl+shift+c | ctrl+c | ctrl+z | ctrl+shift+z | shift+left | shift+right | shift+up | shift+down | shift+home | shift+end | ctrl+shift+left | ctrl+shift+right | ctrl+shift+home | ctrl+shift+end | cmd+a | cmd+c | cmd+x | cmd+z | cmd+shift+z | cmd+left | cmd+right | alt+left | alt+right | cmd+shift+left | cmd+shift+right | alt+shift+left | alt+shift+right | cmd+shift+up | cmd+shift+down)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}


_zes_vscode_when_targets_terminal() {
    local when
    when="$(_zes_compact_lower "$1")"

    [[ -z "$when" ]] && return 0
    [[ "$when" == *"!terminalfocus"* ]] && return 1
    [[ "$when" == *"terminalfocus"* ]]
}


_zes_vscode_binding_is_expected() {
    local key="$1"
    local command="$2"
    local text="$3"

    if [[ "$command" != "workbench.action.terminal.sendSequence" ]]; then
        return 1
    fi

    local text_norm
    text_norm="$(_zes_normalize_escape_value "$text")"

    case "$key" in
    ctrl+shift+c)
        _zes_value_has_csi_code "$text_norm" "67;6u" || _zes_value_is_interrupt_code "$text_norm"
        ;;
    ctrl+c)
        _zes_value_has_csi_code "$text_norm" "67;6u"
        ;;
    ctrl+z)
        [[ "$text_norm" == *"001a"* ]]
        ;;
    ctrl+shift+z)
        _zes_value_has_csi_code "$text_norm" "90;6u"
        ;;
    shift+left)
        _zes_value_has_csi_code "$text_norm" "1;2d"
        ;;
    shift+right)
        _zes_value_has_csi_code "$text_norm" "1;2c"
        ;;
    shift+up)
        _zes_value_has_csi_code "$text_norm" "1;2a"
        ;;
    shift+down)
        _zes_value_has_csi_code "$text_norm" "1;2b"
        ;;
    shift+home)
        _zes_value_has_csi_code "$text_norm" "1;2h"
        ;;
    shift+end)
        _zes_value_has_csi_code "$text_norm" "1;2f"
        ;;
    ctrl+shift+left)
        _zes_value_has_csi_code "$text_norm" "1;6d"
        ;;
    ctrl+shift+right)
        _zes_value_has_csi_code "$text_norm" "1;6c"
        ;;
    ctrl+shift+home)
        _zes_value_has_csi_code "$text_norm" "1;6h"
        ;;
    ctrl+shift+end)
        _zes_value_has_csi_code "$text_norm" "1;6f"
        ;;
    cmd+a)
        _zes_value_has_csi_code "$text_norm" "97;9u"
        ;;
    cmd+c)
        _zes_value_has_csi_code "$text_norm" "99;9u"
        ;;
    cmd+x)
        _zes_value_has_csi_code "$text_norm" "120;9u"
        ;;
    cmd+z)
        _zes_value_has_csi_code "$text_norm" "122;9u"
        ;;
    cmd+shift+z)
        _zes_value_has_csi_code "$text_norm" "122;10u"
        ;;
    cmd+left)
        _zes_value_has_csi_code "$text_norm" "1;9d"
        ;;
    cmd+right)
        _zes_value_has_csi_code "$text_norm" "1;9c"
        ;;
    alt+left)
        _zes_value_has_csi_code "$text_norm" "1;3d"
        ;;
    alt+right)
        _zes_value_has_csi_code "$text_norm" "1;3c"
        ;;
    cmd+shift+left)
        _zes_value_has_csi_code "$text_norm" "1;10d"
        ;;
    cmd+shift+right)
        _zes_value_has_csi_code "$text_norm" "1;10c"
        ;;
    alt+shift+left)
        _zes_value_has_csi_code "$text_norm" "1;4d"
        ;;
    alt+shift+right)
        _zes_value_has_csi_code "$text_norm" "1;4c"
        ;;
    cmd+shift+up)
        _zes_value_has_csi_code "$text_norm" "1;10a"
        ;;
    cmd+shift+down)
        _zes_value_has_csi_code "$text_norm" "1;10b"
        ;;
    *)
        return 1
        ;;
    esac
}


check_vscode_conflicts() {
    local config="$1"
    local line_num=0
    local -a obj_lines=()
    local -a obj_line_nums=()
    local brace_depth=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue

        # Track JSON object boundaries
        if [[ "$stripped" == "{"* ]]; then
            ((brace_depth++))
            obj_lines=()
            obj_line_nums=()
        fi

        if [[ $brace_depth -gt 0 ]]; then
            obj_lines+=("$stripped")
            obj_line_nums+=("$line_num")
        fi

        # Only treat structural object-closing lines as depth decrements.
        # This avoids prematurely closing on nested inline braces such as:
        #   "args": { "text": "..." }
        if [[ "$stripped" =~ ^\}[[:space:]]*,?[[:space:]]*$ ]] && [[ $brace_depth -gt 0 ]]; then
            ((brace_depth--))
            if [[ $brace_depth -eq 0 ]]; then
                local obj_text="${obj_lines[*]}"

                local key=""
                local command=""
                local text=""
                local when_expr=""

                if [[ "$obj_text" =~ \"key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    key="${BASH_REMATCH[1],,}"
                fi

                _zes_vscode_key_is_watched "$key" || {
                    obj_lines=()
                    obj_line_nums=()
                    continue
                }

                if [[ "$obj_text" =~ \"when\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    when_expr="${BASH_REMATCH[1]}"
                fi

                if ! _zes_vscode_when_targets_terminal "$when_expr"; then
                    obj_lines=()
                    obj_line_nums=()
                    continue
                fi

                if [[ "$obj_text" =~ \"command\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    command="${BASH_REMATCH[1]}"
                fi
                if [[ "$obj_text" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    text="${BASH_REMATCH[1]}"
                fi

                if ! _zes_vscode_binding_is_expected "$key" "$command" "$text"; then
                    local key_line_num="${obj_line_nums[0]}"
                    local idx
                    for idx in "${!obj_lines[@]}"; do
                        if [[ "${obj_lines[$idx]}" =~ \"key\" ]]; then
                            key_line_num="${obj_line_nums[$idx]}"
                            break
                        fi
                    done

                    print_conflict "keybindings.json:${key_line_num}" "$obj_text" "May conflict with zsh-edit-select bindings"
                fi

                obj_lines=()
                obj_line_nums=()
            fi
        fi
    done <"$config"
}
