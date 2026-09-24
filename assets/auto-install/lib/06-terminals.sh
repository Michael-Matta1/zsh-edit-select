#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Terminal configuration orchestration
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_TERMINALS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_TERMINALS_LOADED=1

_zes_call_terminal_handler() {
    local handler="$1"

    if declare -f "$handler" >/dev/null 2>&1; then
        "$handler"
        return $?
    fi

    print_warning "Terminal handler is unavailable: $handler"
    return 1
}

_zes_record_selected_terminal() {
    local terminal="$1"
    local existing

    [[ -z "$terminal" ]] && return 0

    for existing in "${TERMINALS_SELECTED_FOR_CONFIG[@]}"; do
        [[ "$existing" == "$terminal" ]] && return 0
    done

    TERMINALS_SELECTED_FOR_CONFIG+=("$terminal")
}

_zes_configure_terminal_for_os() {
    local terminal="$1"

    case "$terminal" in
    kitty)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            _zes_call_terminal_handler configure_kitty_macos
        else
            _zes_call_terminal_handler configure_kitty
        fi
        ;;
    alacritty)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            _zes_call_terminal_handler configure_alacritty_macos
        else
            _zes_call_terminal_handler configure_alacritty
        fi
        ;;
    wezterm)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            _zes_call_terminal_handler configure_wezterm_macos
        else
            _zes_call_terminal_handler configure_wezterm
        fi
        ;;
    foot)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            print_info "Foot is Linux-only; skipping on macOS."
            return 0
        fi
        _zes_call_terminal_handler configure_foot
        ;;
    konsole)
        if [[ "$DETECTED_OS" != "linux" ]]; then
            print_info "Konsole profile configuration is supported on native Linux only; skipping."
            return 0
        fi
        if ! _zes_call_terminal_handler configure_konsole; then
            FAILED_STEPS["konsole_config"]="Konsole profile, keytab, or shortcut configuration failed"
            return 1
        fi
        ;;
    ghostty)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            _zes_call_terminal_handler configure_ghostty_macos
        else
            _zes_call_terminal_handler configure_ghostty
        fi
        ;;
    iterm2)
        if [[ "$DETECTED_OS" == "macos" ]]; then
            _zes_call_terminal_handler configure_iterm2_macos
        else
            print_info "iTerm2 configuration is only available on macOS."
        fi
        ;;
    vscode)
        _zes_call_terminal_handler configure_vscode
        ;;
    windows-terminal)
        _zes_call_terminal_handler configure_windows_terminal
        ;;
    *)
        print_warning "No automated terminal handler for: $terminal"
        return 1
        ;;
    esac
}

configure_terminals() {
    # Track only terminals the user actually chose to configure in this run.
    TERMINALS_SELECTED_FOR_CONFIG=()

    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_info "No terminals to configure"
        return
    fi

    local -a selectable_terminals=()
    local -a ignored_terminals=()
    local -a manual_terminals=()
    local terminal

    for terminal in "${DETECTED_TERMINALS[@]}"; do
        case "$terminal" in
        kitty | alacritty | wezterm | foot | konsole | iterm2 | ghostty | vscode | windows-terminal)
            selectable_terminals+=("$terminal")
            ;;
        gnome-terminal | xfce4-terminal | terminator | tilix)
            ignored_terminals+=("$terminal")
            ;;
        *)
            manual_terminals+=("$terminal")
            ;;
        esac
    done

    if [[ ${#manual_terminals[@]} -gt 0 ]]; then
        print_info "Detected terminals that may require manual configuration:"
        for terminal in "${manual_terminals[@]}"; do
            print_substep "$terminal (see README.md)"
        done
    fi

    if [[ ${#ignored_terminals[@]} -gt 0 ]]; then
        print_info "Ignoring non-configurable terminals for this step:"
        for terminal in "${ignored_terminals[@]}"; do
            print_substep "$terminal"
        done
    fi

    if [[ ${#selectable_terminals[@]} -eq 0 ]]; then
        print_info "No configurable terminals were detected for this installer step."
        return
    fi

    # In non-interactive mode, configure every supported detected terminal.
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_info "Non-interactive mode: configuring all supported detected terminals."
        for terminal in "${selectable_terminals[@]}"; do
            _zes_record_selected_terminal "$terminal"
            _zes_configure_terminal_for_os "$terminal"
        done
        return
    fi

    local -a pending_terminals=("${selectable_terminals[@]}")

    while true; do
        if [[ ${#pending_terminals[@]} -eq 0 ]]; then
            print_success "All selected terminal configurations have been completed." "terminals_config"
            break
        fi

        local -a menu_options=()
        local -a option_terminals=()

        for terminal in "${pending_terminals[@]}"; do
            case "$terminal" in
            kitty) menu_options+=("Kitty") ;;
            alacritty) menu_options+=("Alacritty") ;;
            wezterm) menu_options+=("WezTerm") ;;
            foot) menu_options+=("Foot") ;;
            konsole) menu_options+=("Konsole") ;;
            iterm2) menu_options+=("iTerm2") ;;
            ghostty) menu_options+=("Ghostty") ;;
            vscode) menu_options+=("VS Code (Integrated Terminal)") ;;
            windows-terminal) menu_options+=("Windows Terminal (WSL)") ;;
            *) menu_options+=("$terminal") ;;
            esac
            option_terminals+=("$terminal")
        done

        menu_options+=("Configure all listed terminals")
        menu_options+=("Finish terminal configuration and continue installation")

        ask_choice "Select a terminal configuration action:" "${menu_options[@]}"
        local choice="$CHOICE_RESULT"
        local first_terminal_index=1
        local configure_all_index=$(( ${#option_terminals[@]} + 1 ))
        local finish_index=$(( ${#option_terminals[@]} + 2 ))

        if [[ "$choice" -eq "$configure_all_index" ]]; then
            for terminal in "${pending_terminals[@]}"; do
                _zes_record_selected_terminal "$terminal"
                _zes_configure_terminal_for_os "$terminal"
            done
            pending_terminals=()
            continue
        fi

        if [[ "$choice" -eq "$finish_index" ]]; then
            print_info "Terminal configuration step completed."
            break
        fi

        local selected_terminal_index=$((choice - first_terminal_index))
        local selected_terminal="${option_terminals[$selected_terminal_index]}"
        _zes_record_selected_terminal "$selected_terminal"
        _zes_configure_terminal_for_os "$selected_terminal"

        local -a next_pending=()
        local t
        for t in "${pending_terminals[@]}"; do
            [[ "$t" == "$selected_terminal" ]] && continue
            next_pending+=("$t")
        done
        pending_terminals=("${next_pending[@]}")

        if [[ ${#pending_terminals[@]} -gt 0 ]]; then
            if ! ask_yes_no "Would you like to configure another detected terminal?" "y"; then
                print_info "Terminal configuration step completed."
                break
            fi
        fi
    done
}


backup_config() {
    backup_file "$1"
}
