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


check_kitty_conflicts() {
    local config="$1"
    local line_num=0
    # Track whether we are inside the block our installer wrote.
    # The block starts at the "# Zsh Edit-Select" comment and may contain
    # blank lines, comments, and map directives spread across several
    # paragraphs.  We stay in the section as long as lines are blank,
    # comments, or map directives; anything else means we have left it.
    local in_zes_section=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect our section marker
        if [[ "$line" == *"Zsh Edit-Select"* ]]; then
            in_zes_section=1
            continue
        fi

        # If inside our section, stay there for blank lines, comments,
        # and map directives we wrote.  Anything else exits the section.
        if [[ $in_zes_section -eq 1 ]]; then
            local stripped_sec
            stripped_sec="$(strip_line "$line")"
            if [[ -z "${line//[[:space:]]/}" ]] ||
                [[ "$stripped_sec" =~ ^# ]] ||
                [[ "$stripped_sec" =~ ^map ]]; then
                continue
            fi
            in_zes_section=0
        fi

        # Skip blank lines outside our section
        [[ -z "${line//[[:space:]]/}" ]] && continue

        local stripped
        stripped="$(strip_line "$line")"

        # Skip lines that don't look like valid config (length check)
        [[ ${#stripped} -lt 3 || ${#stripped} -gt 200 ]] && continue

        # Skip comment lines
        [[ "$stripped" =~ ^# ]] && continue

        # Flag map lines that conflict with our bindings, but only if they are
        # NOT inside a block we wrote
        if [[ "$stripped" =~ ^map.*(ctrl\+c|ctrl\+shift\+c|ctrl\+shift\+z|ctrl\+shift\+left|ctrl\+shift\+right|ctrl\+shift\+home|ctrl\+shift\+end|shift\+left|shift\+right|shift\+up|shift\+down|shift\+home|shift\+end) ]]; then
            print_conflict "kitty.conf:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
        fi
    done <"$config"
}


check_alacritty_conflicts() {
    local config="$1"
    local is_yaml=0
    [[ "$config" == *.yml ]] && is_yaml=1

    if [[ $is_yaml -eq 1 ]]; then
        # YAML format: look for key-binding lines like  - { key: C, mods: Control|Shift, ... }
        if grep -qE '(key:[[:space:]]*(C|Z|Home|End),)' "$config" 2>/dev/null; then
            local our_section=0
            local line_num=0

            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_num++))
                if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                    our_section=1
                    continue
                fi
                if [[ $our_section -eq 1 ]]; then
                    local stripped
                    stripped="${line#"${line%%[![:space:]]*}"}"
                    stripped="${stripped%"${stripped##*[![:space:]]}"}"
                    # Stay in our section for blank lines, comments, and YAML
                    # binding entries we wrote
                    if [[ -z "$stripped" ]] ||
                        [[ "$stripped" == "#"* ]] ||
                        [[ "$stripped" == "key_bindings:"* ]] ||
                        [[ "$stripped" == "- {"* ]]; then
                        continue
                    fi
                    # Anything else means we've left our section
                    our_section=0
                fi
                if [[ $our_section -eq 0 ]] && [[ "$line" =~ key:[[:space:]]*(C|Z|Home|End), ]]; then
                    print_conflict "alacritty config:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            done <"$config"
        fi
    else
        # TOML format: look for key = "C" or key = "Z" or key = "Home" or key = "End" entries
        if grep -qE 'key.*=.*"(C|Z|Home|End)"' "$config" 2>/dev/null; then
            local our_section=0
            local line_num=0

            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_num++))
                if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                    our_section=1
                    continue
                fi
                if [[ $our_section -eq 1 ]]; then
                    local stripped
                    stripped="${line#"${line%%[![:space:]]*}"}"
                    stripped="${stripped%"${stripped##*[![:space:]]}"}"
                    # Stay in our section for blank lines, comments, and common
                    # TOML keyboard binding entries we wrote
                    if [[ -z "$stripped" ]] ||
                        [[ "$stripped" == "#"* ]] ||
                        [[ "$stripped" == "[[keyboard.bindings]]" ]] ||
                        [[ "$stripped" =~ ^(key|mods|chars|action)[[:space:]]*= ]]; then
                        continue
                    fi
                    # Anything else means we've left our section
                    our_section=0
                fi
                if [[ $our_section -eq 0 ]] && [[ "$line" =~ key.*=.*\"(C|Z|Home|End)\" ]]; then
                    print_conflict "alacritty config:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            done <"$config"
        fi
    fi
}


check_wezterm_conflicts() {
    local config="$1"

    # Check for conflicting WezTerm keybindings (Lua format)
    # Our bindings use key = 'C'/'Z'/'c' with CTRL|SHIFT or CTRL modifiers,
    # and LeftArrow/RightArrow with DisableDefaultAssignment
    if grep -qE "(key.*=.*['\"][CZcz]['\"]|DisableDefaultAssignment)" "$config" 2>/dev/null; then
        local our_section=0
        local line_num=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_num++))
            if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                our_section=1
                continue
            fi
            if [[ $our_section -eq 1 ]]; then
                local stripped
                stripped="${line#"${line%%[![:space:]]*}"}"
                stripped="${stripped%"${stripped##*[![:space:]]}"}"
                # Stay in our section for blank lines, comments, and Lua
                # keybinding entries we wrote
                if [[ -z "$stripped" ]] ||
                    [[ "$stripped" == "--"* ]] ||
                    [[ "$stripped" == "config.keys"* ]] ||
                    [[ "$stripped" == "config.mouse_bindings"* ]] ||
                    [[ "$stripped" == "local zes_"* ]] ||
                    [[ "$stripped" == "{"* ]] ||
                    [[ "$stripped" == "}"* ]] ||
                    [[ "$stripped" == "for "* ]] ||
                    [[ "$stripped" == "end" ]]; then
                    continue
                fi
                # Anything else means we've left our section
                our_section=0
            fi
            if [[ $our_section -eq 0 ]]; then
                # Ignore bindings generated by zsh-edit-select (legacy and
                # current WezTerm managed blocks), even when section detection
                # cannot fully track all Lua forms.
                if [[ "$line" == *"zes_wezterm"* ]] || [[ "$line" == *"zes_linux_"* ]] || [[ "$line" == *"zes_macos_"* ]] || [[ "$line" == *"zes_act"* ]]; then
                    continue
                fi

                # Check for key bindings that conflict with ours (C/Z with Ctrl modifiers)
                if [[ "$line" =~ key.*=.*[\'\"](C|c|Z|z)[\'\"].*CTRL ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]LeftArrow[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]RightArrow[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]Home[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]End[\'\"].*CTRL.*SHIFT ]]; then
                    print_conflict "wezterm.lua:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            fi
        done <"$config"
    fi
}


check_foot_conflicts() {
    local config="$1"

    # Check for conflicting key-bindings and text-bindings section entries
    local in_keybindings=0
    local in_textbindings=0
    local line_num=0
    local our_section=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue

        if [[ "$stripped" == *"Zsh Edit-Select"* ]]; then
            our_section=1
            continue
        fi
        if [[ $our_section -eq 1 ]] && [[ "$stripped" =~ ^\[ ]]; then
            our_section=0
        fi

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

        if [[ $our_section -eq 0 ]]; then
            if [[ $in_keybindings -eq 1 ]]; then
                if [[ "$stripped" =~ ^(clipboard-copy|prompt-prev)= ]]; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
                fi
            fi
            if [[ $in_textbindings -eq 1 ]]; then
                if [[ "$stripped" == *"Control+Shift+c"* ]] || [[ "$stripped" == *"Control+Shift+z"* ]]; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select text-bindings"
                fi
            fi
        fi
    done <"$config"
}


check_ghostty_conflicts() {
    local config="$1"
    local line_num=0
    local our_section=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue

        if [[ "$stripped" == *"Zsh Edit-Select"* ]]; then
            our_section=1
            continue
        fi

        if [[ $our_section -eq 1 ]]; then
            # Stay in our section for comments and the entries we add.
            # Anything else means we've left our managed block.
            if [[ "$stripped" == "#"* ]] ||
                [[ "$stripped" == keybind* ]] ||
                [[ "$stripped" == copy-on-select* ]]; then
                continue
            fi
            our_section=0
        fi

        if [[ $our_section -eq 0 ]] && [[ "$stripped" =~ ^keybind[[:space:]]*= ]]; then
            if [[ "$stripped" =~ (ctrl\+c|ctrl\+shift\+c|ctrl\+shift\+z|ctrl\+shift\+left|ctrl\+shift\+right|ctrl\+shift\+home|ctrl\+shift\+end|cmd\+a|cmd\+c|cmd\+x|cmd\+z|cmd\+shift\+z|shift\+up|shift\+down|cmd\+shift\+up|cmd\+shift\+down) ]]; then
                print_conflict "ghostty config:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
            fi
        fi
    done <"$config"
}


check_vscode_conflicts() {
    local config="$1"
    local line_num=0

    # VS Code keybindings.json is a JSON array of objects.
    # Each object spans multiple lines: { "key": ..., "command": ..., "args": ..., "when": ... }
    # We collect each object's lines, then check the full object to decide
    # whether it belongs to us (contains "Zsh Edit-Select" or our escape
    # sequences) BEFORE flagging any "key" line as a conflict.
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

        if [[ "$stripped" == *"}"* ]] && [[ $brace_depth -gt 0 ]]; then
            ((brace_depth--))
            if [[ $brace_depth -eq 0 ]]; then
                # We have a complete JSON object — check it
                local obj_text="${obj_lines[*]}"

                # Skip objects that belong to our installer.
                # configure_vscode() writes sendSequence bindings with specific
                # ZES escape sequences.  VS Code JSON has no comment syntax, so
                # we identify our objects by their "text" payload.  We require
                # BOTH "sendSequence" (so a binding to the right key but the
                # wrong command is still flagged) AND one of our known sequences.
                local skip_obj=0
                if [[ "$obj_text" == *"Zsh Edit-Select"* ]]; then
                    skip_obj=1
                elif [[ "$obj_text" == *"sendSequence"* ]]; then
                    # Each sequence below corresponds to a value written by configure_vscode():
                    #   67;6u  → Ctrl+Shift+C copy (CSI u)
                    #   90;6u  → Ctrl+Shift+Z redo (CSI u)
                    #   1;2D/C/A/B → Shift+Left/Right/Up/Down
                    #   1;2H/F → Shift+Home/End
                    #   1;6D/C → Ctrl+Shift+Left/Right
                    #   1;6H/F → Ctrl+Shift+Home/End
                    #   u001a  → Ctrl+Z undo (\u001a)
                    #   u0003  → Ctrl+C interrupt (\u0003)
                    if [[ "$obj_text" == *"67;6u"* ]] ||
                        [[ "$obj_text" == *"90;6u"* ]] ||
                        [[ "$obj_text" == *"1;2D"* ]] ||
                        [[ "$obj_text" == *"1;2C"* ]] ||
                        [[ "$obj_text" == *"1;2A"* ]] ||
                        [[ "$obj_text" == *"1;2B"* ]] ||
                        [[ "$obj_text" == *"1;2H"* ]] ||
                        [[ "$obj_text" == *"1;2F"* ]] ||
                        [[ "$obj_text" == *"1;6D"* ]] ||
                        [[ "$obj_text" == *"1;6C"* ]] ||
                        [[ "$obj_text" == *"1;6H"* ]] ||
                        [[ "$obj_text" == *"1;6F"* ]] ||
                        [[ "$obj_text" == *"u001a"* ]] ||
                        [[ "$obj_text" == *"u0003"* ]]; then
                        skip_obj=1
                    fi
                fi
                if [[ $skip_obj -eq 1 ]]; then
                    obj_lines=()
                    obj_line_nums=()
                    continue
                fi

                # Check if any line in this object has a conflicting "key"
                local idx
                for idx in "${!obj_lines[@]}"; do
                    local obj_stripped="${obj_lines[$idx]}"
                    if [[ "$obj_stripped" =~ \"key\" ]]; then
                        local lower_obj="${obj_stripped,,}"
                        if [[ "$lower_obj" == *"ctrl+shift+c"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+z"* ]] ||
                            [[ "$lower_obj" == *"ctrl+z"* ]] ||
                            [[ "$lower_obj" == *"shift+left"* ]] ||
                            [[ "$lower_obj" == *"shift+right"* ]] ||
                            [[ "$lower_obj" == *"shift+up"* ]] ||
                            [[ "$lower_obj" == *"shift+down"* ]] ||
                            [[ "$lower_obj" == *"shift+home"* ]] ||
                            [[ "$lower_obj" == *"shift+end"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+left"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+right"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+home"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+end"* ]]; then
                            print_conflict "keybindings.json:${obj_line_nums[$idx]}" "$obj_stripped" "May conflict with zsh-edit-select bindings"
                        fi
                    fi
                done
                obj_lines=()
                obj_line_nums=()
            fi
        fi
    done <"$config"
}
