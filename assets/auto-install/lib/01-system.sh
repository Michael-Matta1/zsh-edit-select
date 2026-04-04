#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: System utility functions
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_SYSTEM_LOADED:-}" ]] && return 0
readonly _ZES_MOD_SYSTEM_LOADED=1

is_package_available() {
    local package="$1"
    case "$DETECTED_PACKAGE_MANAGER" in
    apt) apt-cache show "$package" &>/dev/null ;;
    dnf) dnf info "$package" &>/dev/null ;;
    yum) yum info "$package" &>/dev/null ;;
    pacman) pacman -Si "$package" &>/dev/null ;;
    zypper) zypper info "$package" &>/dev/null ;;
    apk) apk info "$package" &>/dev/null ;;
    *)
        # For unknown package managers, we can't verify availability
        # Return false to be safe rather than assuming success
        log_message "PKG_CHECK_UNKNOWN: Cannot verify package $package with unknown manager $DETECTED_PACKAGE_MANAGER"
        return 1
        ;;
    esac
}

command_exists() {
    command -v "$1" &>/dev/null
}

_zes_get_login_shell_for_user() {
    local shell_user="$1"
    local entry=""

    if [[ -n "$shell_user" ]]; then
        if command_exists getent; then
            entry=$(getent passwd "$shell_user" 2>/dev/null || true)
            if [[ -n "$entry" ]]; then
                printf '%s\n' "${entry##*:}"
                return 0
            fi
        fi

        if [[ -r "/etc/passwd" ]]; then
            entry=$(awk -F: -v user="$shell_user" '$1 == user { print $7; exit }' /etc/passwd 2>/dev/null || true)
            if [[ -n "$entry" ]]; then
                printf '%s\n' "$entry"
                return 0
            fi
        fi
    fi

    printf '%s\n' "${SHELL:-}"
}

_zes_resolve_login_zsh_path() {
    local shell_line=""
    local zsh_path=""

    if [[ -r "/etc/shells" ]]; then
        while IFS= read -r shell_line || [[ -n "$shell_line" ]]; do
            shell_line="${shell_line%%#*}"
            shell_line="${shell_line#"${shell_line%%[![:space:]]*}"}"
            shell_line="${shell_line%"${shell_line##*[![:space:]]}"}"
            [[ -z "$shell_line" ]] && continue

            if [[ "$shell_line" == */zsh ]] && [[ -x "$shell_line" ]]; then
                printf '%s\n' "$shell_line"
                return 0
            fi
        done </etc/shells
    fi

    zsh_path=$(command -v zsh 2>/dev/null || true)
    if [[ -n "$zsh_path" ]]; then
        printf '%s\n' "$zsh_path"
        return 0
    fi

    printf '%s\n' "/bin/zsh"
}

_zes_is_zsh_shell() {
    [[ "${1##*/}" == "zsh" ]]
}

# Verify that a package was successfully installed
verify_package_installed() {
    local package="$1"
    local pm="${2:-$DETECTED_PACKAGE_MANAGER}"

    case "$pm" in
    apt)
        dpkg -l "$package" 2>/dev/null | grep -q "^ii"
        return $?
        ;;
    dnf | yum)
        rpm -q "$package" &>/dev/null
        return $?
        ;;
    pacman)
        pacman -Q "$package" &>/dev/null
        return $?
        ;;
    zypper)
        rpm -q "$package" &>/dev/null
        return $?
        ;;
    apk)
        apk info -e "$package" &>/dev/null
        return $?
        ;;
    *)
        # For unknown package managers, return 0 (assume success)
        # This is to prevent false negatives
        log_message "PKG_VERIFY_UNKNOWN: Cannot verify $package with unknown manager $pm"
        return 0
        ;;
    esac
}

# Check if package manager command is available and functional
verify_package_manager() {
    local pm="$1"

    if ! command_exists "$pm"; then
        return 1
    fi

    # Verify it's actually executable
    if [[ ! -x "$(command -v "$pm")" ]]; then
        log_message "PKG_MGR_NOT_EXECUTABLE: $pm exists but is not executable"
        return 1
    fi

    # Quick sanity check (varies by package manager)
    case "$pm" in
    apt)
        apt-cache --version &>/dev/null || return 1
        ;;
    dnf | yum)
        "$pm" --version &>/dev/null || return 1
        ;;
    pacman)
        "$pm" --version &>/dev/null || return 1
        ;;
    zypper)
        "$pm" --version &>/dev/null || return 1
        ;;
    apk)
        "$pm" --version &>/dev/null || return 1
        ;;
    *)
        log_message "PKG_MGR_VERIFY: No specific check for $pm, assuming OK"
        ;;
    esac

    return 0
}

# Check network connectivity
check_network_connectivity() {
    local test_urls=("github.com" "google.com" "cloudflare.com")
    local connected=0

    # Try ping first (fastest) - with reduced timeout for quicker results
    for url in "${test_urls[@]}"; do
        # Linux: -c count, -W timeout (seconds)
        if command_exists timeout; then
            if timeout 3 ping -c 1 -W 2 "$url" &>/dev/null; then
                connected=1
                break
            fi
        else
            # Fallback without timeout command
            if ping -c 1 -W 2 "$url" &>/dev/null; then
                connected=1
                break
            fi
        fi
    done

    # If ping fails, try curl/wget as fallback
    if [[ $connected -eq 0 ]]; then
        for url in "${test_urls[@]}"; do
            if command_exists curl; then
                # Use shorter timeout and follow redirects
                if command_exists timeout; then
                    if timeout 5 curl --connect-timeout 3 --max-time 5 -fsSL -o /dev/null "https://$url" &>/dev/null; then
                        connected=1
                        break
                    fi
                else
                    # Fallback without timeout command
                    if curl --connect-timeout 3 --max-time 5 -fsSL -o /dev/null "https://$url" &>/dev/null; then
                        connected=1
                        break
                    fi
                fi
            elif command_exists wget; then
                if command_exists timeout; then
                    if timeout 5 wget --timeout=3 --tries=1 -q -O /dev/null "https://$url" &>/dev/null; then
                        connected=1
                        break
                    fi
                else
                    # Fallback without timeout command
                    if wget --timeout=3 --tries=1 -q -O /dev/null "https://$url" &>/dev/null; then
                        connected=1
                        break
                    fi
                fi
            fi
        done
    fi

    if [[ $connected -eq 1 ]]; then
        print_success "Network connectivity check passed"
        return 0
    else
        print_warning "No network connectivity detected"
        print_warning "Installation requires internet access to download dependencies"
        log_message "NETWORK_CHECK_FAILED: No connectivity to test URLs"

        # Additional diagnostic info
        if command_exists ip; then
            local has_route
            has_route=$(ip route show default 2>/dev/null | head -1)
            if [[ -z "$has_route" ]]; then
                print_info "Diagnostic: No default route found"
                log_message "NETWORK_DIAGNOSTIC: No default route"
            fi
        fi

        return 1
    fi
}

# Run command with sudo if available
run_with_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@" # Already root, no need for sudo
    elif [[ $SUDO_AVAILABLE -eq 1 ]]; then
        sudo "$@"
    else
        print_error "Cannot run command (sudo not available): $*"
        return 1
    fi
}

# Check sudo availability and request privileges
check_sudo() {
    print_step "Checking sudo privileges..."

    # Warn if running as root
    if [[ $EUID -eq 0 ]] || [[ "$(id -u)" -eq 0 ]]; then
        print_warning "Running as root user detected!"
        print_warning "This may cause permission issues for user-level configurations"
        print_warning "It's recommended to run this script as a normal user"
        log_message "WARNING: Script running as root (EUID=$EUID)"

        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            if ! ask_yes_no "Continue running as root anyway? (Not recommended)" "n"; then
                print_info "Installation cancelled. Please run as a normal user."
                exit 0
            fi
        fi
        SUDO_AVAILABLE=1 # Root doesn't need sudo
        return
    fi

    if ! command_exists sudo; then
        print_warning "sudo is not installed on this system"
        print_info "Package installation will be skipped if root privileges are required"
        SUDO_AVAILABLE=0
        return
    fi

    if sudo -n true 2>/dev/null; then
        print_success "Sudo privileges available (cached)" "sudo"
        SUDO_AVAILABLE=1
    else
        print_info "Requesting sudo privileges..."
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            print_warning "Non-interactive mode: cannot prompt for sudo"
            SUDO_AVAILABLE=0
        elif sudo -v 2>/dev/null; then
            print_success "Sudo privileges granted" "sudo"
            SUDO_AVAILABLE=1
        else
            print_warning "Sudo privileges not available"
            print_info "Package installation will be skipped"
            SUDO_AVAILABLE=0
        fi
    fi
    log_message "SUDO_AVAILABLE=$SUDO_AVAILABLE"
}

# Check if zsh is installed
check_zsh_installed() {
    print_step "Checking for zsh..."

    if ! command_exists zsh; then
        print_warning "zsh is not installed."

        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            print_error "zsh is required but not installed in non-interactive mode."
            print_info "Install zsh manually and re-run the installer."
            log_message "FATAL: zsh not installed (non-interactive mode)"
            exit 1
        fi

        if ! ask_yes_no "zsh is required. Install zsh now?" "y"; then
            print_error "zsh is required to continue."
            print_info "Install zsh manually and re-run the installer."
            log_message "FATAL: zsh installation declined by user"
            exit 1
        fi

        if [[ $EUID -ne 0 ]] && [[ $SUDO_AVAILABLE -eq 0 ]]; then
            print_error "Cannot install zsh automatically because sudo privileges are unavailable."
            print_info "Install zsh manually and re-run the installer."
            log_message "FATAL: zsh auto-install failed due to missing sudo"
            exit 1
        fi

        local install_ok=0
        local install_hint=""

        if command_exists apt-get; then
            install_hint="sudo apt-get install zsh"
            run_with_sudo apt-get install -y -qq zsh && install_ok=1
        elif command_exists dnf; then
            install_hint="sudo dnf install -y zsh"
            run_with_sudo dnf install -y -q zsh && install_ok=1
        elif command_exists yum; then
            install_hint="sudo yum install -y zsh"
            run_with_sudo yum install -y -q zsh && install_ok=1
        elif command_exists pacman; then
            install_hint="sudo pacman -S --noconfirm --needed zsh"
            run_with_sudo pacman -S --noconfirm --needed zsh && install_ok=1
        elif command_exists zypper; then
            install_hint="sudo zypper install -y zsh"
            run_with_sudo zypper install -y zsh && install_ok=1
        elif command_exists emerge; then
            install_hint="sudo emerge --ask=n app-shells/zsh"
            run_with_sudo emerge --ask=n app-shells/zsh && install_ok=1
        elif command_exists apk; then
            install_hint="sudo apk add zsh"
            run_with_sudo apk add zsh && install_ok=1
        elif command_exists xbps-install; then
            install_hint="sudo xbps-install -y zsh"
            run_with_sudo xbps-install -y zsh && install_ok=1
        elif command_exists eopkg; then
            install_hint="sudo eopkg install -y zsh"
            run_with_sudo eopkg install -y zsh && install_ok=1
        elif command_exists swupd; then
            install_hint="sudo swupd bundle-add os-core-shell"
            run_with_sudo swupd bundle-add os-core-shell && install_ok=1
        elif command_exists nix-env; then
            install_hint="nix-env -iA nixpkgs.zsh"
            nix-env -iA nixpkgs.zsh && install_ok=1
        elif command_exists brew; then
            install_hint="brew install zsh"
            brew install zsh && install_ok=1
        fi

        if [[ $install_ok -ne 1 ]] || ! command_exists zsh; then
            print_error "Failed to install zsh automatically."
            [[ -n "$install_hint" ]] && print_info "Try manually: $install_hint"
            log_message "FATAL: zsh auto-install failed"
            exit 1
        fi

        ZSH_INSTALLED_THIS_SESSION=1
        print_success "zsh installed successfully" "zsh_install"
    fi

    local zsh_version
    zsh_version=$(zsh --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    print_success "zsh is installed (version ${zsh_version:-unknown})" "zsh_check"
    log_message "ZSH_VERSION: $zsh_version"

    local zsh_path
    zsh_path="$(_zes_resolve_login_zsh_path)"

    local shell_user="${USER:-${LOGNAME:-$(id -un 2>/dev/null || true)}}"
    local current_login_shell=""
    current_login_shell="$(_zes_get_login_shell_for_user "$shell_user")"

    if [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && [[ -n "$zsh_path" ]] && ! _zes_is_zsh_shell "$current_login_shell"; then
        if command_exists chsh; then
            if [[ $NON_INTERACTIVE -eq 0 ]] && ask_yes_no "Set zsh as your default shell now? (recommended)" "y"; then
                local chsh_ok=0
                print_info "Changing default shell to $zsh_path for ${shell_user:-current user}."
                print_info "You may be prompted for your account password."

                if [[ -n "$shell_user" ]]; then
                    if chsh -s "$zsh_path" "$shell_user"; then
                        chsh_ok=1
                    elif [[ $SUDO_AVAILABLE -eq 1 ]] && command_exists usermod; then
                        print_info "chsh failed; trying sudo usermod fallback..."
                        if run_with_sudo usermod -s "$zsh_path" "$shell_user"; then
                            chsh_ok=1
                        fi
                    fi
                else
                    if chsh -s "$zsh_path"; then
                        chsh_ok=1
                    fi
                fi

                local updated_login_shell=""
                updated_login_shell="$(_zes_get_login_shell_for_user "$shell_user")"

                if _zes_is_zsh_shell "$updated_login_shell"; then
                    print_success "Default shell set to zsh (effective after next login)" "zsh_default_shell"
                elif [[ $chsh_ok -eq 1 ]] && [[ -z "$shell_user" ]]; then
                    print_success "Default shell set to zsh (effective after next login)" "zsh_default_shell"
                else
                    print_warning "Could not set default shell automatically."
                    [[ -n "$updated_login_shell" ]] && print_info "Detected login shell is still: $updated_login_shell"
                    print_info "Run manually: chsh -s $zsh_path"
                    MANUAL_STEPS+=("Set default shell manually: chsh -s $zsh_path")
                fi
            elif [[ $NON_INTERACTIVE -eq 1 ]]; then
                print_info "Non-interactive mode: skipping default shell change."
                MANUAL_STEPS+=("Set default shell manually: chsh -s $zsh_path")
            fi
        else
            print_warning "chsh is not available; cannot change default shell automatically."
            print_info "Run manually: chsh -s $zsh_path"
            MANUAL_STEPS+=("Set default shell manually: chsh -s $zsh_path")
        fi
    fi

    if [[ $ZSH_INSTALLED_THIS_SESSION -eq 1 ]]; then
        if [[ "$DETECTED_OS" == "linux" ]]; then
            print_warning "zsh was installed during this installer session."
            print_warning "Log out and log back in (or reboot) so the default shell change is fully applied."

            local shell_restart_step="Linux: Log out and log back in (or reboot) to apply the new default zsh shell"
            local existing_step
            local step_exists=0
            for existing_step in "${MANUAL_STEPS[@]}"; do
                if [[ "$existing_step" == "$shell_restart_step" ]]; then
                    step_exists=1
                    break
                fi
            done
            if [[ $step_exists -eq 0 ]]; then
                MANUAL_STEPS+=("$shell_restart_step")
            fi
        fi
    fi
}

check_essential_commands() {
    print_step "Checking for essential commands..."

    local missing_commands=()
    local optional_missing=()
    local cmd

    # Check for absolutely required commands
    local required_cmds=("grep" "sed" "awk" "mkdir" "cp" "mv" "rm" "cat" "date")
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    # Check for highly recommended commands
    local recommended_cmds=("curl" "wget" "make" "gcc")
    for cmd in "${recommended_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            optional_missing+=("$cmd")
        fi
    done

    # Report required missing commands
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        echo -e "${YELLOW}These commands are required for the installation to proceed.${NC}"
        echo -e "${YELLOW}Please install them using your package manager.${NC}"
        log_message "FATAL: Missing required commands: ${missing_commands[*]}"
        exit 1
    fi

    # Report optional missing commands
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        print_warning "Missing recommended commands: ${optional_missing[*]}"
        print_info "Some features may not work without these commands"
        log_message "WARNING: Missing optional commands: ${optional_missing[*]}"
    else
        print_success "All essential commands are available" "essential_commands"
    fi
}
