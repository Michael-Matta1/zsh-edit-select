#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Dependency installation for alternative package managers
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_DEPS_ALT_LOADED:-}" ]] && return 0
readonly _ZES_MOD_DEPS_ALT_LOADED=1

install_deps_dnf() {
    print_substep "Using DNF package manager..."

    local packages=("gcc" "make" "pkgconfig" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libX11-devel" "libXfixes-devel" "xclip")
    else
        packages+=("wayland-devel" "wayland-protocols-devel" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libX11-devel" "libXfixes-devel")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do echo -e "    ${DIM}•${NC} ${_pkg}"; done
    echo ""
    run_with_sudo dnf install -y "${packages[@]}" 2>&1 |
        grep --line-buffered -E "^(Installing|Upgrading|Downloading)" |
        while IFS= read -r _line; do echo -e "  ${DIM}${BLUE}→${NC} ${_line}"; done
    local dnf_status="${PIPESTATUS[0]}"
    if [[ "$dnf_status" -eq 0 ]]; then
        print_success "Dependencies installed via DNF" "deps_install"
    else
        print_error "Failed to install some dependencies via DNF" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo dnf install ${packages[*]}")
    fi
}

install_deps_yum() {
    print_substep "Using YUM package manager..."

    local packages=("gcc" "gcc-c++" "make" "pkg-config" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libX11-devel" "libXfixes-devel" "xclip")
    else
        packages+=("wayland-devel" "wayland-protocols-devel" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libX11-devel" "libXfixes-devel")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do echo -e "    ${DIM}•${NC} ${_pkg}"; done
    echo ""
    run_with_sudo yum install -y "${packages[@]}" 2>&1 |
        grep --line-buffered -E "^(Installing|Updating|Downloading)" |
        while IFS= read -r _line; do echo -e "  ${DIM}${BLUE}→${NC} ${_line}"; done
    local yum_status="${PIPESTATUS[0]}"
    if [[ "$yum_status" -eq 0 ]]; then
        print_success "Dependencies installed via YUM" "deps_install"
    else
        print_error "Failed to install some dependencies via YUM" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo yum install ${packages[*]}")
    fi
}

install_deps_pacman() {
    print_substep "Using Pacman package manager..."

    # Note: We avoid pacman -Sy (partial sync) which is an unsupported anti-pattern
    # on Arch-based systems. The -S --needed below uses the existing package database.
    # Users should run 'pacman -Syu' separately to keep their system up to date.

    local packages=("base-devel" "pkgconf" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libx11" "libxfixes" "xclip")
    else
        packages+=("wayland" "wayland-protocols" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libx11" "libxfixes")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do echo -e "    ${DIM}•${NC} ${_pkg}"; done
    echo ""
    if run_with_sudo pacman -S --noconfirm --needed "${packages[@]}"; then
        print_success "Dependencies installed via Pacman" "deps_install"
    else
        print_error "Failed to install some dependencies via Pacman" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo pacman -S ${packages[*]}")
    fi
}

install_deps_zypper() {
    print_substep "Using Zypper package manager..."

    local packages=("patterns-devel-base-devel_basis" "pkg-config" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libX11-devel" "libXfixes-devel" "xclip")
    else
        packages+=("wayland-devel" "wayland-protocols-devel" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libX11-devel" "libXfixes-devel")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do echo -e "    ${DIM}•${NC} ${_pkg}"; done
    echo ""
    run_with_sudo zypper install -y "${packages[@]}" 2>&1 |
        grep --line-buffered -E "^(Installing:|Updating|Downloading)" |
        while IFS= read -r _line; do echo -e "  ${DIM}${BLUE}→${NC} ${_line}"; done
    local zypper_status="${PIPESTATUS[0]}"
    if [[ "$zypper_status" -eq 0 ]]; then
        print_success "Dependencies installed via Zypper" "deps_install"
    else
        print_error "Failed to install some dependencies via Zypper" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo zypper install ${packages[*]}")
    fi
}

install_deps_emerge() {
    print_substep "Using Emerge package manager..."

    local packages=(
        "sys-devel/gcc" "sys-devel/make" "virtual/pkgconfig"
        "dev-vcs/git" "app-shells/zsh"
    )

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("x11-libs/libX11" "x11-libs/libXfixes" "x11-misc/xclip")
    else
        packages+=("dev-libs/wayland" "dev-libs/wayland-protocols" "gui-apps/wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("x11-libs/libX11" "x11-libs/libXfixes")
        fi
    fi

    print_substep "Installing: ${packages[*]}"
    if run_with_sudo emerge --ask=n "${packages[@]}"; then
        print_success "Dependencies installed via Emerge" "deps_install"
    else
        print_error "Failed to install some dependencies via Emerge" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo emerge ${packages[*]}")
    fi
}

install_deps_apk() {
    print_substep "Using APK package manager..."

    run_with_sudo apk update 2>/dev/null || true

    local packages=("build-base" "pkgconf" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libx11-dev" "libxfixes-dev" "xclip")
    else
        packages+=("wayland-dev" "wayland-protocols" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libx11-dev" "libxfixes-dev")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do echo -e "    ${DIM}•${NC} ${_pkg}"; done
    echo ""
    run_with_sudo apk add "${packages[@]}" 2>&1 |
        grep --line-buffered -E "^(Installing|Upgrading|Fetching)" |
        while IFS= read -r _line; do echo -e "  ${DIM}${BLUE}→${NC} ${_line}"; done
    local apk_status="${PIPESTATUS[0]}"
    if [[ "$apk_status" -eq 0 ]]; then
        print_success "Dependencies installed via APK" "deps_install"
    else
        print_error "Failed to install some dependencies via APK" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo apk add ${packages[*]}")
    fi
}

install_deps_xbps() {
    print_substep "Using XBPS package manager..."

    # Note: We avoid xbps-install -Sy (partial sync) which can cause dependency
    # issues on Void Linux. The -y below uses the existing package database.
    # Users should run 'xbps-install -Su' separately to keep their system up to date.

    local packages=("base-devel" "pkg-config" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libX11-devel" "libXfixes-devel" "xclip")
    else
        packages+=("wayland-devel" "wayland-protocols" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libX11-devel" "libXfixes-devel")
        fi
    fi

    print_substep "Installing: ${packages[*]}"
    if run_with_sudo xbps-install -y "${packages[@]}"; then
        print_success "Dependencies installed via XBPS" "deps_install"
    else
        print_error "Failed to install some dependencies via XBPS" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo xbps-install -y ${packages[*]}")
    fi
}

install_deps_eopkg() {
    print_substep "Using Eopkg package manager..."

    local packages=("system.devel" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libx11-devel" "libxfixes-devel" "xclip")
    else
        packages+=("wayland-devel" "wayland-protocols-devel" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libx11-devel" "libxfixes-devel")
        fi
    fi

    print_substep "Installing: ${packages[*]}"
    if run_with_sudo eopkg install -y "${packages[@]}"; then
        print_success "Dependencies installed via Eopkg" "deps_install"
    else
        print_error "Failed to install some dependencies via Eopkg" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo eopkg install ${packages[*]}")
    fi
}

install_deps_nix() {
    print_substep "Using Nix package manager..."
    print_warning "NixOS detected — please ensure dependencies are declared in your configuration.nix"
    print_info "Required: gcc, gnumake, pkg-config, git, zsh, and display server libraries"
    MANUAL_STEPS+=("Add zsh-edit-select dependencies to your NixOS configuration")
}

install_deps_swupd() {
    print_substep "Using swupd package manager..."

    local bundles=("c-basic" "git" "zsh")

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        bundles+=("devpkg-libX11" "devpkg-libXfixes")
    else
        bundles+=("devpkg-wayland" "devpkg-wayland-protocols")
    fi

    print_substep "Installing bundles: ${bundles[*]}"
    if run_with_sudo swupd bundle-add "${bundles[@]}"; then
        print_success "Dependencies installed via swupd" "deps_install"
    else
        print_error "Failed to install some dependencies via swupd" "deps_install"
        MANUAL_STEPS+=("Install missing bundles: sudo swupd bundle-add ${bundles[*]}")
    fi

    # swupd bundles may not include clipboard tools (xclip / wl-clipboard).
    # Warn the user so they can install them manually if needed.
    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        if ! command -v xclip &>/dev/null; then
            print_warning "xclip not found — clipboard integration requires xclip"
            MANUAL_STEPS+=("Install xclip for clipboard support (may need a manual build on Clear Linux)")
        fi
    else
        if ! command -v wl-copy &>/dev/null; then
            print_warning "wl-clipboard not found — clipboard integration requires wl-clipboard"
            MANUAL_STEPS+=("Install wl-clipboard for clipboard support (may need a manual build on Clear Linux)")
        fi
    fi
}
