#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: System detection functions
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_DETECT_LOADED:-}" ]] && return 0
readonly _ZES_MOD_DETECT_LOADED=1

# System Detection Functions

detect_os() {
    print_step "Detecting operating system..."
    local _uname
    _uname="$(uname -s 2>/dev/null)"
    case "$_uname" in
    Darwin)
        DETECTED_OS="macos"
        DETECTED_DISPLAY_SERVER="macos"
        print_success "Detected macOS" "detect_os"
        ;;
    Linux)
        if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]] ||
            { [[ -r /proc/version ]] && grep -qi 'microsoft\|WSL' /proc/version 2>/dev/null; }; then
            DETECTED_OS="wsl"
        else
            DETECTED_OS="linux"
        fi
        ;;
    MSYS* | MINGW* | CYGWIN*)
        DETECTED_OS="windows"
        print_error "Git Bash/MSYS is not supported directly. Please run the installer inside WSL."
        exit 1
        ;;
    *)
        DETECTED_OS="linux"
        ;;
    esac
}

detect_display_server() {
    print_step "Detecting display server..."

    # macOS uses its own native display system — skip all Linux detection
    if [[ "$DETECTED_OS" == "macos" ]]; then
        DETECTED_DISPLAY_SERVER="macos"
        print_success "Display server: macOS (CoreGraphics + Accessibility API)" "display_server"
        return
    fi

    # Method 1: XDG_SESSION_TYPE (most reliable)
    if [[ -n "${XDG_SESSION_TYPE:-}" ]]; then
        case "${XDG_SESSION_TYPE,,}" in
        wayland)
            DETECTED_DISPLAY_SERVER="wayland"
            print_success "Detected Wayland (via XDG_SESSION_TYPE)" "display_server"
            return
            ;;
        x11)
            DETECTED_DISPLAY_SERVER="x11"
            print_success "Detected X11 (via XDG_SESSION_TYPE)" "display_server"
            return
            ;;
        esac
    fi

    # Method 2: WAYLAND_DISPLAY / DISPLAY environment variables
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if [[ -n "${DISPLAY:-}" ]]; then
            DETECTED_DISPLAY_SERVER="wayland"
            # We detected Wayland, but X11 (XWayland) is also available
            # We will handle this in the dependency phase
            print_success "Detected Wayland + XWayland (via WAYLAND_DISPLAY & DISPLAY)" "display_server"
        else
            DETECTED_DISPLAY_SERVER="wayland"
            print_success "Detected Wayland (via WAYLAND_DISPLAY)" "display_server"
        fi
        return
    elif [[ -n "${DISPLAY:-}" ]]; then
        DETECTED_DISPLAY_SERVER="x11"
        print_success "Detected X11 (via DISPLAY)" "display_server"
        return
    fi

    # Method 3: loginctl
    if command_exists loginctl; then
        local session_id
        local _current_user
        _current_user=$(whoami 2>/dev/null || echo "")
        if [[ -n "$_current_user" ]]; then
            session_id=$(loginctl 2>/dev/null | grep -F "$_current_user" | awk '{print $1}' | head -1 || true)
        fi
        if [[ -n "$session_id" ]]; then
            local session_type
            session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || true)
            if [[ -n "$session_type" ]]; then
                DETECTED_DISPLAY_SERVER="${session_type,,}"
                print_success "Detected $DETECTED_DISPLAY_SERVER (via loginctl)" "display_server"
                return
            fi
        fi
    fi

    # Method 4: Check running processes (expanded list of Wayland compositors)
    if pgrep -x "sway" &>/dev/null || pgrep -x "kwin_wayland" &>/dev/null ||
        pgrep -x "weston" &>/dev/null || pgrep -x "Hyprland" &>/dev/null ||
        pgrep -x "river" &>/dev/null || pgrep -x "wayfire" &>/dev/null ||
        pgrep -x "labwc" &>/dev/null || pgrep -x "dwl" &>/dev/null ||
        pgrep -x "hikari" &>/dev/null || pgrep -x "cage" &>/dev/null; then
        DETECTED_DISPLAY_SERVER="wayland"
        print_success "Detected Wayland (via processes)" "display_server"
        return
    elif pgrep -x "X" &>/dev/null || pgrep -x "Xorg" &>/dev/null; then
        DETECTED_DISPLAY_SERVER="x11"
        print_success "Detected X11 (via processes)" "display_server"
        return
    fi

    # Method 5: Fallback — ask user
    print_warning "Could not automatically detect display server"
    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        ask_choice "Select your display server:" "X11" "Wayland" "TTY (Headless)"
        local choice="$CHOICE_RESULT"
        case "$choice" in
        1) DETECTED_DISPLAY_SERVER="x11" ;;
        2) DETECTED_DISPLAY_SERVER="wayland" ;;
        3) DETECTED_DISPLAY_SERVER="tty" ;;
        *)
            DETECTED_DISPLAY_SERVER="x11"
            print_warning "Invalid choice, defaulting to X11"
            ;;
        esac
        print_info "Using: $DETECTED_DISPLAY_SERVER"
    else
        DETECTED_DISPLAY_SERVER="x11"
        print_info "Defaulting to: x11"
    fi
}

detect_package_manager() {
    # Detect based on distro ID first
    case "${DETECTED_DISTRO_ID,,}" in
    ubuntu | debian | linuxmint | pop | elementary | zorin | kali | raspbian | parrot | deepin | mx | \
        peppermint | lmde | bunsen | devuan | neon | trisquel | pureos | bodhi | antix | sparky | q4os | \
        siduction | neptune)
        DETECTED_PACKAGE_MANAGER="apt"
        ;;
    fedora | rhel | centos | rocky | almalinux | oracle | nobara | ultramarine | qubes)
        if command_exists dnf; then
            DETECTED_PACKAGE_MANAGER="dnf"
        else
            DETECTED_PACKAGE_MANAGER="yum"
        fi
        ;;
    arch | manjaro | endeavouros | garuda | artix | arcolinux | cachyos | archcraft | rebornos | \
        archbang | bluestar | parabola | hyperbola)
        DETECTED_PACKAGE_MANAGER="pacman"
        ;;
    opensuse* | sles | suse)
        DETECTED_PACKAGE_MANAGER="zypper"
        ;;
    gentoo | funtoo | calculate)
        DETECTED_PACKAGE_MANAGER="emerge"
        ;;
    alpine)
        DETECTED_PACKAGE_MANAGER="apk"
        ;;
    void)
        DETECTED_PACKAGE_MANAGER="xbps"
        ;;
    solus)
        DETECTED_PACKAGE_MANAGER="eopkg"
        ;;
    nixos)
        DETECTED_PACKAGE_MANAGER="nix"
        ;;
    clear-linux*)
        DETECTED_PACKAGE_MANAGER="swupd"
        ;;
    *)
        # Fallback: detect by checking which commands exist
        if command_exists apt-get; then
            DETECTED_PACKAGE_MANAGER="apt"
        elif command_exists dnf; then
            DETECTED_PACKAGE_MANAGER="dnf"
        elif command_exists yum; then
            DETECTED_PACKAGE_MANAGER="yum"
        elif command_exists pacman; then
            DETECTED_PACKAGE_MANAGER="pacman"
        elif command_exists zypper; then
            DETECTED_PACKAGE_MANAGER="zypper"
        elif command_exists emerge; then
            DETECTED_PACKAGE_MANAGER="emerge"
        elif command_exists apk; then
            DETECTED_PACKAGE_MANAGER="apk"
        elif command_exists xbps-install; then
            DETECTED_PACKAGE_MANAGER="xbps"
        elif command_exists eopkg; then
            DETECTED_PACKAGE_MANAGER="eopkg"
        elif command_exists nix-env; then
            DETECTED_PACKAGE_MANAGER="nix"
        elif command_exists swupd; then
            DETECTED_PACKAGE_MANAGER="swupd"
        elif command_exists brew; then
            DETECTED_PACKAGE_MANAGER="brew"
        elif command_exists port; then
            DETECTED_PACKAGE_MANAGER="port"
        else
            DETECTED_PACKAGE_MANAGER="unknown"
        fi
        ;;
    esac

    # Verify logic: mismatch between detected distro logic and actual command existence
    if [[ "$DETECTED_PACKAGE_MANAGER" != "unknown" ]]; then
        local check_cmd="$DETECTED_PACKAGE_MANAGER"
        [[ "$DETECTED_PACKAGE_MANAGER" == "apt" ]] && check_cmd="apt-get"
        [[ "$DETECTED_PACKAGE_MANAGER" == "xbps" ]] && check_cmd="xbps-install"
        [[ "$DETECTED_PACKAGE_MANAGER" == "nix" ]] && check_cmd="nix-env"

        if ! command_exists "$check_cmd"; then
            print_warning "Detected package manager '$DETECTED_PACKAGE_MANAGER' but command '$check_cmd' not found"
            DETECTED_PACKAGE_MANAGER="unknown"
        else
            # Additionally verify the package manager is functional
            if ! verify_package_manager "$check_cmd"; then
                print_warning "Package manager '$check_cmd' exists but is not functional"
                DETECTED_PACKAGE_MANAGER="unknown"
            fi
        fi
    fi
}

detect_linux_distro() {
    print_step "Detecting Linux distribution..."

    # macOS: set distro fields and exit early
    if [[ "$DETECTED_OS" == "macos" ]]; then
        DETECTED_DISTRO_ID="macos"
        DETECTED_DISTRO_NAME="macOS"
        DETECTED_DISTRO_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
        print_success "macOS ${DETECTED_DISTRO_VERSION}" "distro"
        detect_package_manager
        print_substep "Package Manager: ${DETECTED_PACKAGE_MANAGER:-none}"
        return
    fi

    # Method 1: /etc/os-release (standard)
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DETECTED_DISTRO_ID="${ID:-unknown}"
        DETECTED_DISTRO_NAME="${NAME:-Unknown}"
        DETECTED_DISTRO_VERSION="${VERSION_ID:-unknown}"
        DETECTED_DISTRO_CODENAME="${VERSION_CODENAME:-}"

        # Use ID_LIKE as fallback family hint
        if [[ -n "${ID_LIKE:-}" ]]; then
            print_substep "ID_LIKE: $ID_LIKE"
        fi

    # Method 2: /usr/lib/os-release (alternative location)
    elif [[ -f /usr/lib/os-release ]]; then
        # shellcheck source=/dev/null
        source /usr/lib/os-release
        DETECTED_DISTRO_ID="${ID:-unknown}"
        DETECTED_DISTRO_NAME="${NAME:-Unknown}"
        DETECTED_DISTRO_VERSION="${VERSION_ID:-unknown}"
        DETECTED_DISTRO_CODENAME="${VERSION_CODENAME:-}"

    # Method 3: lsb_release command
    elif command_exists lsb_release; then
        DETECTED_DISTRO_ID=$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')
        DETECTED_DISTRO_NAME=$(lsb_release -ds 2>/dev/null | tr -d '"')
        DETECTED_DISTRO_VERSION=$(lsb_release -rs 2>/dev/null)
        DETECTED_DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null)

    # Method 4: Specific distro files
    elif [[ -f /etc/debian_version ]]; then
        DETECTED_DISTRO_ID="debian"
        DETECTED_DISTRO_NAME="Debian"
        DETECTED_DISTRO_VERSION=$(cat /etc/debian_version)
    elif [[ -f /etc/redhat-release ]]; then
        DETECTED_DISTRO_NAME=$(cat /etc/redhat-release)
        if [[ "$DETECTED_DISTRO_NAME" == *"Fedora"* ]]; then
            DETECTED_DISTRO_ID="fedora"
        elif [[ "$DETECTED_DISTRO_NAME" == *"CentOS"* ]]; then
            DETECTED_DISTRO_ID="centos"
        elif [[ "$DETECTED_DISTRO_NAME" == *"Red Hat"* ]]; then
            DETECTED_DISTRO_ID="rhel"
        else
            DETECTED_DISTRO_ID="redhat"
        fi
    elif [[ -f /etc/arch-release ]]; then
        DETECTED_DISTRO_ID="arch"
        DETECTED_DISTRO_NAME="Arch Linux"
    elif [[ -f /etc/gentoo-release ]]; then
        DETECTED_DISTRO_ID="gentoo"
        DETECTED_DISTRO_NAME="Gentoo"
    elif [[ -f /etc/SuSE-release ]]; then
        DETECTED_DISTRO_ID="suse"
        DETECTED_DISTRO_NAME="SUSE Linux"
    elif [[ -f /etc/alpine-release ]]; then
        DETECTED_DISTRO_ID="alpine"
        DETECTED_DISTRO_NAME="Alpine Linux"
        DETECTED_DISTRO_VERSION=$(cat /etc/alpine-release)
    else
        DETECTED_DISTRO_ID="unknown"
        DETECTED_DISTRO_NAME="Unknown Linux"
        DETECTED_DISTRO_VERSION="unknown"
    fi

    # Detect package manager
    detect_package_manager

    print_success "Distribution: $DETECTED_DISTRO_NAME ${DETECTED_DISTRO_VERSION:-} (ID: $DETECTED_DISTRO_ID)" "distro"
    print_substep "Package Manager: $DETECTED_PACKAGE_MANAGER"
}
