#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Plugin manager and terminal detection
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_DETECT_PLUGIN_LOADED:-}" ]] && return 0
readonly _ZES_MOD_DETECT_PLUGIN_LOADED=1

_zes_detect_existing_standalone_plugin_dir() {
    local candidate=""
    local source_line=""
    local source_dir=""
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"

    local -a candidates=(
        "${PLUGIN_INSTALL_DIR:-}"
        "$HOME/.local/share/zsh/plugins/zsh-edit-select"
        "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins/zsh-edit-select"
        "$HOME/.local/share/zsh-edit-select"
        "$HOME/.zsh/plugins/zsh-edit-select"
        "$HOME/.config/zsh/plugins/zsh-edit-select"
    )

    for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        if [[ -f "$candidate/zsh-edit-select.plugin.zsh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if [[ -f "$zshrc" ]]; then
        source_line=$(grep -E '^[[:space:]]*source[[:space:]]+.*zsh-edit-select\.plugin\.zsh' "$zshrc" 2>/dev/null | tail -n 1)
        if [[ -n "$source_line" ]]; then
            source_line="${source_line%%#*}"
            source_line=$(printf '%s\n' "$source_line" | sed -E 's/^[[:space:]]*source[[:space:]]+//')

            source_line="${source_line#\"}"
            source_line="${source_line%\"}"
            source_line="${source_line#\'}"
            source_line="${source_line%\'}"

            source_line="${source_line/#\~/$HOME}"
            source_line=$(printf '%s\n' "$source_line" | sed 's#//*#/#g')
            source_dir="${source_line%/zsh-edit-select.plugin.zsh}"

            if [[ -n "$source_dir" ]] && [[ -f "$source_dir/zsh-edit-select.plugin.zsh" ]]; then
                printf '%s\n' "$source_dir"
                return 0
            fi
        fi
    fi

    return 1
}

_zes_set_standalone_plugin_path() {
    local existing_dir=""

    DETECTED_PLUGIN_MANAGER="manual"
    existing_dir="$(_zes_detect_existing_standalone_plugin_dir 2>/dev/null || true)"

    if [[ -n "$existing_dir" ]]; then
        PLUGIN_INSTALL_DIR="$existing_dir"
        print_info "Detected existing standalone plugin path: $PLUGIN_INSTALL_DIR"
    else
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
        print_info "Using standalone plugin path: $PLUGIN_INSTALL_DIR"
    fi
}

detect_plugin_manager() {
    local detection_mode="${1:-bootstrap}"

    case "$detection_mode" in
    bootstrap | passive) ;;
    *) detection_mode="bootstrap" ;;
    esac

    DETECTED_PLUGIN_MANAGER=""
    PLUGIN_INSTALL_DIR=""

    if [[ "$detection_mode" == "passive" ]]; then
        print_step "Detecting plugin manager (passive mode)..."
    else
        print_step "Detecting Zsh plugin manager..."
    fi

    # Check for Oh My Zsh (directory + env var)
    if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
        # Verify it's actually Oh My Zsh
        if [[ -f "${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh" ]]; then
            DETECTED_PLUGIN_MANAGER="oh-my-zsh"
            PLUGIN_INSTALL_DIR="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-edit-select"
            print_success "Detected: Oh My Zsh" "plugin_manager"
            return
        else
            log_message "DETECTION_WARNING: Directory ${ZSH:-$HOME/.oh-my-zsh} exists but doesn't contain oh-my-zsh.sh"
        fi
    fi

    # Check for Zinit (directory or env var)
    if [[ -d "${ZINIT_HOME:-}" ]] || [[ -d "$HOME/.zinit" ]] || [[ -d "$HOME/.local/share/zinit" ]] ||
        [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit" ]]; then
        DETECTED_PLUGIN_MANAGER="zinit"
        PLUGIN_INSTALL_DIR="${ZINIT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/zinit}/plugins/zsh-edit-select"
        print_success "Detected: Zinit" "plugin_manager"
        return
    fi

    # Check for Zplug
    if [[ -d "${ZPLUG_HOME:-$HOME/.zplug}" ]] || command_exists zplug; then
        DETECTED_PLUGIN_MANAGER="zplug"
        PLUGIN_INSTALL_DIR="${ZPLUG_HOME:-$HOME/.zplug}/repos/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Zplug" "plugin_manager"
        return
    fi

    # Check for Antigen
    if [[ -f "$HOME/.antigen.zsh" ]] || [[ -d "$HOME/.antigen" ]] || command_exists antigen; then
        DETECTED_PLUGIN_MANAGER="antigen"
        PLUGIN_INSTALL_DIR="$HOME/.antigen/bundles/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Antigen" "plugin_manager"
        return
    fi

    # Check for Antibody (deprecated — succeeded by Antidote)
    if command_exists antibody; then
        DETECTED_PLUGIN_MANAGER="antibody"
        PLUGIN_INSTALL_DIR="$HOME/.cache/antibody/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Antibody" "plugin_manager"
        print_warning "Antibody is archived and no longer maintained. Consider migrating to Antidote: https://github.com/mattmc3/antidote"
        return
    fi

    # Check for Zgenom (check before Zgen — Zgenom is the maintained successor)
    if [[ -d "${ZGENOM_DIR:-$HOME/.zgenom}" ]] || command_exists zgenom; then
        DETECTED_PLUGIN_MANAGER="zgenom"
        PLUGIN_INSTALL_DIR="${ZGENOM_DIR:-$HOME/.zgenom}/Michael-Matta1/zsh-edit-select-master"
        print_success "Detected: Zgenom" "plugin_manager"
        return
    fi

    # Check for Zgen (deprecated — succeeded by Zgenom)
    if [[ -d "${ZGEN_DIR:-$HOME/.zgen}" ]] || command_exists zgen; then
        DETECTED_PLUGIN_MANAGER="zgen"
        PLUGIN_INSTALL_DIR="${ZGEN_DIR:-$HOME/.zgen}/Michael-Matta1/zsh-edit-select-master"
        print_success "Detected: Zgen" "plugin_manager"
        print_warning "Zgen is no longer maintained. Consider migrating to Zgenom: https://github.com/jandamm/zgenom"
        return
    fi

    # Check for Sheldon
    if command_exists sheldon || [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml" ]]; then
        DETECTED_PLUGIN_MANAGER="sheldon"
        PLUGIN_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon/repos/github.com/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Sheldon" "plugin_manager"
        return
    fi

    # Check .zshrc for plugin manager signatures
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    if [[ -f "$zshrc" ]]; then
        local zshrc_content
        zshrc_content=$(cat "$zshrc" 2>/dev/null || true)

        if echo "$zshrc_content" | grep -qE "zinit|zi " 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zinit"
            PLUGIN_INSTALL_DIR="${ZINIT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/zinit}/plugins/zsh-edit-select"
            print_success "Detected: Zinit (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "antigen" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="antigen"
            PLUGIN_INSTALL_DIR="$HOME/.antigen/bundles/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Antigen (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zplug" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zplug"
            PLUGIN_INSTALL_DIR="${ZPLUG_HOME:-$HOME/.zplug}/repos/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Zplug (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "antibody" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="antibody"
            PLUGIN_INSTALL_DIR="$HOME/.cache/antibody/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Antibody (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zgenom" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zgenom"
            PLUGIN_INSTALL_DIR="${ZGENOM_DIR:-$HOME/.zgenom}/Michael-Matta1/zsh-edit-select-master"
            print_success "Detected: Zgenom (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zgen" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zgen"
            PLUGIN_INSTALL_DIR="${ZGEN_DIR:-$HOME/.zgen}/Michael-Matta1/zsh-edit-select-master"
            print_success "Detected: Zgen (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "sheldon" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="sheldon"
            PLUGIN_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon/repos/github.com/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Sheldon (via .zshrc)" "plugin_manager"
            return
        fi
    fi

    # No plugin manager detected.
    if [[ "$detection_mode" == "passive" ]]; then
        print_info "No known Zsh plugin manager detected; probing standalone plugin paths."
        _zes_set_standalone_plugin_path
        return
    fi

    # Bootstrap mode: offer to install Oh My Zsh.
    print_warning "No Zsh plugin manager detected"

    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        echo ""
        print_info "I noticed you don't have a zsh plugin manager installed."
        if ask_yes_no "Would you like me to install oh-my-zsh? This will enable better plugin management and is recommended for beginners (You can refuse if you prefer manual installation)" "y"; then
            install_oh_my_zsh
            if [[ -d "$HOME/.oh-my-zsh" ]] && [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
                DETECTED_PLUGIN_MANAGER="oh-my-zsh"
                PLUGIN_INSTALL_DIR="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-edit-select"
            fi
        else
            # Fallback to manual choice
            ask_choice "How would you like to install the plugin instead?" \
                "Manual installation (~/.local/share/zsh/plugins)" \
                "Custom path (you will be prompted)"

            local choice="$CHOICE_RESULT"

            case "$choice" in
            1)
                _zes_set_standalone_plugin_path
                ;;
            2)
                echo -ne "${YELLOW}?${NC} Enter custom installation path: "
                local custom_path
                read -r custom_path

                # Validate custom path
                if [[ -z "$custom_path" ]]; then
                    print_error "Empty path provided, using default"
                    _zes_set_standalone_plugin_path
                elif [[ "$custom_path" == "/" ]] || [[ "$custom_path" == "/bin" ]] ||
                    [[ "$custom_path" == "/usr" ]] || [[ "$custom_path" == "/etc" ]]; then
                    print_error "Invalid system path provided, using default"
                    log_message "SECURITY: Rejected invalid path: $custom_path"
                    _zes_set_standalone_plugin_path
                else
                    DETECTED_PLUGIN_MANAGER="manual"
                    # Expand ~ to HOME and escape for safety
                    custom_path="${custom_path/#\~/$HOME}"
                    # Basic sanitization - remove multiple slashes, trailing slashes
                    custom_path=$(printf '%s\n' "$custom_path" | sed 's#//*#/#g' | sed 's#/$##')
                    PLUGIN_INSTALL_DIR="${custom_path}/zsh-edit-select"
                    print_info "Using custom path: $PLUGIN_INSTALL_DIR"
                    log_message "CUSTOM_PATH: $PLUGIN_INSTALL_DIR"
                fi
                ;;
            *)
                _zes_set_standalone_plugin_path
                ;;
            esac
        fi
    else
        print_info "Installing as standalone plugin (non-interactive mode)"
        _zes_set_standalone_plugin_path
    fi

    print_info "Plugin will be installed to: $PLUGIN_INSTALL_DIR"
}


install_oh_my_zsh() {
    print_step "Installing Oh My Zsh..."

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        print_info "Oh My Zsh is already installed"
        return
    fi

    # Check if git is installed (required by Oh My Zsh installer)
    if ! command_exists git; then
        print_warning "Git is required for Oh My Zsh installation"

        if [[ $SUDO_AVAILABLE -eq 1 ]] && [[ "$DETECTED_PACKAGE_MANAGER" != "unknown" ]]; then
            print_step "Attempting to install git..."

            # Install git based on package manager
            local git_install_success=0
            case "$DETECTED_PACKAGE_MANAGER" in
            apt)
                if run_with_sudo apt-get install -y -qq git; then
                    git_install_success=1
                fi
                ;;
            dnf)
                if run_with_sudo dnf install -y -q git; then
                    git_install_success=1
                fi
                ;;
            yum)
                if run_with_sudo yum install -y -q git; then
                    git_install_success=1
                fi
                ;;
            pacman)
                if run_with_sudo pacman -S --noconfirm --needed git; then
                    git_install_success=1
                fi
                ;;
            zypper)
                if run_with_sudo zypper install -y git; then
                    git_install_success=1
                fi
                ;;
            emerge)
                if run_with_sudo emerge --ask=n dev-vcs/git; then
                    git_install_success=1
                fi
                ;;
            apk)
                if run_with_sudo apk add git; then
                    git_install_success=1
                fi
                ;;
            xbps)
                if run_with_sudo xbps-install -y git; then
                    git_install_success=1
                fi
                ;;
            eopkg)
                if run_with_sudo eopkg install -y git; then
                    git_install_success=1
                fi
                ;;
            *)
                print_warning "Cannot auto-install git for $DETECTED_PACKAGE_MANAGER"
                ;;
            esac

            # Verify git installation succeeded
            if [[ $git_install_success -eq 1 ]] && command_exists git; then
                print_success "Git installed" "git_install"
            else
                print_error "Failed to install git" "git_install"
                print_info "Falling back to manual plugin installation mode"
                DETECTED_PLUGIN_MANAGER="manual"
                PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                MANUAL_STEPS+=("Install git, then optionally install Oh My Zsh: https://ohmyz.sh/")
                return
            fi
        else
            print_error "Cannot install git without sudo privileges" "git_install"
            print_info "Falling back to manual plugin installation mode"
            DETECTED_PLUGIN_MANAGER="manual"
            PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
            MANUAL_STEPS+=("Install git: sudo <package-manager> install git")
            MANUAL_STEPS+=("Then optionally install Oh My Zsh: https://ohmyz.sh/")
            return
        fi
    fi

    if command_exists curl; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    elif command_exists wget; then
        sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        print_error "Neither curl nor wget found. Cannot install Oh My Zsh." "omz_install"
        MANUAL_STEPS+=("Install Oh My Zsh manually: https://ohmyz.sh/")
        DETECTED_PLUGIN_MANAGER="manual"
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
        return
    fi

    # Verify Oh My Zsh installation succeeded
    if [[ ! -d "$HOME/.oh-my-zsh" ]] || [[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
        print_error "Oh My Zsh installation failed" "omz_install"
        print_info "Falling back to manual plugin installation mode"
        DETECTED_PLUGIN_MANAGER="manual"
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
        MANUAL_STEPS+=("Install Oh My Zsh manually: https://ohmyz.sh/")
        return
    fi

    # Flush stdin after installation to prevent buffering issues
    flush_stdin

    print_success "Oh My Zsh installed" "omz_install"
}


detect_terminals() {
    print_step "Detecting terminal emulators..."

    DETECTED_TERMINALS=()

    # Check via command lookup
    local term
    local terminals=(
        "kitty"
        "alacritty"
        "wezterm"
        "ghostty"
        "foot"
        "urxvt"
        "st"
        "termite"
        "hyper"
        "xterm"
    )

    for term in "${terminals[@]}"; do
        if command_exists "$term"; then
            DETECTED_TERMINALS+=("$term")
            print_substep "Found: $term ($(get_full_path "$term"))"
        fi
    done

    # Check via environment variables (terminal currently running in)
    if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
            DETECTED_TERMINALS+=("kitty")
            print_substep "Found: kitty (via KITTY_WINDOW_ID)"
        fi
    fi

    if [[ -n "${ALACRITTY_WINDOW_ID:-}" ]] || [[ -n "${ALACRITTY_LOG:-}" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " alacritty " ]]; then
            DETECTED_TERMINALS+=("alacritty")
            local _alacritty_hint="ALACRITTY_WINDOW_ID"
            [[ -z "${ALACRITTY_WINDOW_ID:-}" ]] && _alacritty_hint="ALACRITTY_LOG"
            print_substep "Found: alacritty (via $_alacritty_hint)"
        fi
    fi

    if [[ -n "${WEZTERM_EXECUTABLE:-}" ]]; then
        # Validate that WEZTERM_EXECUTABLE actually points to wezterm
        if [[ -x "$WEZTERM_EXECUTABLE" ]] && [[ -f "$WEZTERM_EXECUTABLE" ]]; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " wezterm " ]]; then
                DETECTED_TERMINALS+=("wezterm")
                print_substep "Found: wezterm (via WEZTERM_EXECUTABLE: $WEZTERM_EXECUTABLE)"
            fi
        else
            print_warning "WEZTERM_EXECUTABLE is set but not a valid executable: $WEZTERM_EXECUTABLE"
            log_message "WEZTERM_INVALID: WEZTERM_EXECUTABLE=$WEZTERM_EXECUTABLE not valid"
        fi
    fi

    if [[ "${TERM:-}" == "foot" ]] || [[ "${TERM:-}" == foot-* ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " foot " ]]; then
            DETECTED_TERMINALS+=("foot")
            print_substep "Found: foot (via TERM)"
        fi
    fi

    # VS Code terminal
    if command_exists code || command_exists code-insiders ||
        [[ -n "${VSCODE_INJECTION:-}" ]] || [[ "${TERM_PROGRAM:-}" == "vscode" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " vscode " ]]; then
            DETECTED_TERMINALS+=("vscode")
            print_substep "Found: VS Code (integrated terminal)"
        fi
    fi

    # Windows Terminal (specifically on WSL)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]]; then
        if find_windows_terminal_settings >/dev/null; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " windows-terminal " ]]; then
                DETECTED_TERMINALS+=("windows-terminal")
                print_substep "Found: Windows Terminal (via WSL interop)"
            fi
        fi
    fi

    # macOS-specific terminal detection (iTerm2, Ghostty)
    if [[ "$DETECTED_OS" == "macos" ]]; then
        # iTerm2
        if [[ -d "/Applications/iTerm.app" ]] || [[ -d "$HOME/Applications/iTerm.app" ]]; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " iterm2 " ]]; then
                DETECTED_TERMINALS+=("iterm2")
                print_substep "Found: iTerm2"
            fi
        fi
        # Ghostty
        if command_exists ghostty || [[ -d "/Applications/Ghostty.app" ]]; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " ghostty " ]]; then
                DETECTED_TERMINALS+=("ghostty")
                print_substep "Found: Ghostty"
            fi
        fi
    fi

    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_warning "No known terminal emulators detected"
        print_info "Terminal configuration will need to be done manually"
        MANUAL_STEPS+=("Configure your terminal emulator manually (see README.md)")
    else
        print_success "Detected ${#DETECTED_TERMINALS[@]} terminal(s)" "terminals"
    fi
}
