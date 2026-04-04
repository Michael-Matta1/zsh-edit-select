#!/usr/bin/env bash
# zsh-edit-select auto-installer — Module 03-kitty.sh
# Kitty terminal installation and configuration functions
#
# Maintains: lib/03-kitty.sh from auto-install.sh extraction
# License: MIT
# shellcheck shell=bash
# shellcheck disable=SC2034
# Sourcing guard: Prevents accidental redeclaration within same shell session

# Guard to prevent redundant sourcing
if [[ -n "${_ZES_MOD_KITTY_LOADED:-}" ]]; then
    return
fi
readonly _ZES_MOD_KITTY_LOADED=1

install_kitty() {
    print_step "Installing Kitty terminal..."
    if [[ $SUDO_AVAILABLE -eq 0 ]]; then
        print_error "Cannot install Kitty without sudo"
        return 1
    fi

    local cmd=""
    case "$DETECTED_PACKAGE_MANAGER" in
    apt) cmd="apt-get install -y -qq kitty" ;;
    dnf) cmd="dnf install -y -q kitty" ;;
    yum) cmd="yum install -y -q kitty" ;;
    pacman) cmd="pacman -S --noconfirm --needed kitty" ;;
    zypper) cmd="zypper install -y kitty" ;;
    emerge) cmd="emerge --ask=n gui-apps/kitty" ;;
    apk) cmd="apk add kitty" ;;
    xbps) cmd="xbps-install -y kitty" ;;
    eopkg) cmd="eopkg install -y kitty" ;;
    nix) cmd="nix-env -iA nixos.kitty" ;;      # approximated
    swupd) cmd="swupd bundle-add terminals" ;; # might be broad
    *)
        print_warning "Cannot auto-install Kitty for $DETECTED_PACKAGE_MANAGER"
        return 1
        ;;
    esac

    if ! is_package_available "kitty"; then
        print_warning "Kitty package not found in repositories"
        return 1
    fi

    # shellcheck disable=SC2086 # Intentional word splitting
    if run_with_sudo $cmd; then
        # Flush stdin after package installation to prevent buffering issues
        flush_stdin
        print_success "Kitty installed" "kitty_install"
        # Add to detected terminals if not already there
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
            DETECTED_TERMINALS+=("kitty")
        fi
        KITTY_FRESHLY_INSTALLED=1
        return 0
    else
        print_error "Failed to install Kitty" "kitty_install"
        return 1
    fi
}

apply_kitty_downloaded_config() {
    local config_url="https://raw.githubusercontent.com/Michael-Matta1/dev-dotfiles/main/kitty.conf"
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    local config_dir
    config_dir="$(dirname "$config_file")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create config directory: $config_dir"
        return 1
    fi
    backup_file "$config_file"

    print_step "Downloading recommended Kitty config..."
    local download_success=0

    if command_exists curl; then
        if curl -fsSL -o "$config_file" "$config_url"; then
            download_success=1
        fi
    elif command_exists wget; then
        if wget -q -O "$config_file" "$config_url"; then
            download_success=1
        fi
    else
        print_error "Cannot download config: neither curl nor wget is installed"
        print_info "Please install curl or wget using your package manager"
        return 1
    fi

    if [[ $download_success -eq 0 ]] || [[ ! -f "$config_file" ]]; then
        print_error "Download failed: could not fetch $config_url"
        print_info "Please check your internet connection and try again"
        print_info "Or manually download from: $config_url"
        return 1
    fi
    print_success "Config downloaded" "kitty_dl"

    # Check for background_image configuration and warn user
    if grep -q "^background_image" "$config_file" 2>/dev/null; then
        echo ""
        print_warning "═══════════════════════════════════════════════════════════════"
        print_warning "IMPORTANT: The downloaded kitty.conf contains a background_image setting!"
        print_warning ""
        print_warning "The line looks like:"
        print_warning "  background_image  <path_to_your_kitty_background_image>"
        print_warning ""
        print_warning "You need to either:"
        print_warning "  1. Replace it with the actual path to your background image"
        print_warning "  2. Comment it out (add # at the start) if you don't want a background"
        print_warning "  3. Delete the line entirely"
        print_warning ""
        print_warning "If you added a path to a background image, uncomment the line:"
        print_warning "  background_opacity        0.1"
        print_warning "to make it transparent."
        print_warning ""
        print_warning "Edit: $config_file"
        print_warning "═══════════════════════════════════════════════════════════════"
        echo ""
    fi

    # Flush stdin after download and messages to prevent buffering issues
    flush_stdin
    # Give terminal time to settle after all the output
    sleep 0.5

    echo ""
    print_info "Note: This configuration uses a reversed copy/paste style where:"
    print_info "  - Ctrl+C = Copy (instead of interrupt)"
    print_info "  - Ctrl+Shift+C = Interrupt/Kill (SIGINT)"
    echo ""

    # Additional flush and sleep before interactive prompt to ensure clean stdin
    flush_stdin
    sleep 0.3

    # Call ask_choice - it sets CHOICE_RESULT global variable
    ask_choice "Would you like to keep this reversed style, or would you prefer the traditional keyboard shortcuts?" \
        "Keep reversed style (Ctrl+C for copy)" \
        "Use traditional style (Ctrl+Shift+C for copy)"

    local choice="$CHOICE_RESULT"

    if [[ "$choice" == "2" ]]; then
        print_substep "Applying traditional mappings..."
        # Apply traditional mappings: Ctrl+Shift+C sends escape sequence for plugin copy
        sed_inplace 's/map ctrl+shift+c.*send_text all .*/map ctrl+shift+c send_text all \\x1b[67;6u/' "$config_file"
        sed_inplace 's/map ctrl+c.*send_text all .*/map ctrl+c send_text all \\x03/' "$config_file"
        print_success "Reverted to traditional shortcuts" "kitty_keybinds"
    else
        print_info "Keeping reversed shortcuts"
    fi
}

offer_kitty_installation() {
    # Offer Kitty installation after dependencies are set up,
    # so package manager is ready and sudo is confirmed.
    # Only offer in interactive mode.
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        return
    fi

    # Skip if kitty is already detected
    if command_exists kitty || [[ " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
        return
    fi

    echo ""
    print_info "Optional: For maximum compatibility with the zsh plugin, I recommend installing the Kitty terminal emulator."
    if ask_yes_no "Would you like me to install it? (This is an optional step)" "y"; then
        if install_kitty; then
            # Add to detected terminals if not already there
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
                DETECTED_TERMINALS+=("kitty")
            fi
        fi
    fi
}

ask_kitty_configuration() {
    # Only show this prompt if:
    # 1. Kitty was just installed by this script (KITTY_FRESHLY_INSTALLED=1)
    # 2. We're in interactive mode (user can respond to prompts)
    if [[ $KITTY_FRESHLY_INSTALLED -ne 1 ]]; then
        return 0 # Skip if kitty wasn't freshly installed
    fi

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        return 0 # Skip in non-interactive mode
    fi

    echo ""
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║         OPTIONAL: Enhanced Kitty Configuration                ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}⚠ THIS IS COMPLETELY OPTIONAL AND NOT REQUIRED! ⚠${NC}"
    echo ""
    print_info "${BOLD}${GREEN}The zsh-edit-select plugin is ALREADY FULLY FUNCTIONAL!${NC}"
    print_info "You can start using it right away without any additional configuration."
    echo ""
    print_info "However, since you just installed Kitty terminal, there's an ${BOLD}optional${NC}"
    print_info "enhanced configuration available that includes:"
    echo ""
    print_info "  ${GREEN}•${NC} Optimized aesthetics and visual features"
    print_info "  ${GREEN}•${NC} Additional convenience settings"
    print_info "  ${GREEN}•${NC} Full compatibility with zsh-edit-select"
    echo ""
    print_info "${BOLD}Source:${NC} https://github.com/Michael-Matta1/dev-dotfiles/blob/main/kitty.conf"
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "${BOLD}Important:${NC} You can ${GREEN}safely skip${NC} this step."
    print_info "The plugin works ${BOLD}perfectly fine${NC} with Kitty's default configuration!"
    echo ""

    if ask_yes_no "Would you like to download this optional enhanced configuration?" "n"; then
        apply_kitty_downloaded_config
    else
        print_info "Skipped optional Kitty configuration."
        print_success "The plugin is ready to use with your current Kitty setup!"
    fi
}
