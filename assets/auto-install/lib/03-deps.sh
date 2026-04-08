#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Dependency installation logic
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_DEPS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_DEPS_LOADED=1

install_dependencies() {
    local force_build_deps_install="${_ZES_FORCE_BUILD_DEPS_INSTALL:-0}"

    if [[ $SKIP_DEPS -eq 1 ]]; then
        print_info "Skipping dependency installation (--skip-deps flag)"
        return
    fi

    # Ask the user whether they want to install build deps at all.
    # Pre-built binaries are installed by the auto-installer during the Agents phase.
    # Local compilation remains optional.
    if [[ "$force_build_deps_install" == "1" ]]; then
        print_info "Ensuring build dependencies are installed for source agent compilation..."
        _ZES_USER_SKIPPED_DEPS=0
    elif [[ $NON_INTERACTIVE -eq 0 ]]; then
        echo ""
        print_info "Pre-built agent binaries are installed automatically from GitHub Releases"
        print_info "during this installer run — no build tools required for normal use."
        echo ""
        if ! ask_yes_no "Install build dependencies to compile agents from source? (optional)" "n"; then
            print_info "Skipping dependency installation."
            print_info "Pre-built binaries will be installed in the upcoming Agents phase."
            _ZES_USER_SKIPPED_DEPS=1
            return
        fi
        _ZES_USER_SKIPPED_DEPS=0
    else
        print_info "Non-interactive mode defaults to using pre-built binaries."
        print_info "Skipping local compilation dependencies."
        _ZES_USER_SKIPPED_DEPS=1
        return
    fi

    print_step "Installing dependencies..."

    if [[ $SUDO_AVAILABLE -eq 0 ]] && [[ "$DETECTED_OS" != "macos" ]]; then
        print_warning "Cannot install dependencies without sudo privileges"
        MANUAL_STEPS+=("Install dependencies manually based on your distribution")
        return
    fi

    case "$DETECTED_PACKAGE_MANAGER" in
    apt) install_deps_apt ;;
    dnf) install_deps_dnf ;;
    yum) install_deps_yum ;;
    pacman) install_deps_pacman ;;
    zypper) install_deps_zypper ;;
    emerge) install_deps_emerge ;;
    apk) install_deps_apk ;;
    xbps) install_deps_xbps ;;
    eopkg) install_deps_eopkg ;;
    nix) install_deps_nix ;;
    swupd) install_deps_swupd ;;
    brew | port) install_deps_macos ;;
    *)
        print_warning "Unknown package manager: $DETECTED_PACKAGE_MANAGER"
        print_info "Please install dependencies manually:"
        print_info "  - C compiler toolchain (gcc, make)"
        if [[ "$DETECTED_OS" == "wsl" ]]; then
            print_info "  - libx11-dev libxfixes-dev (WSL XWayland build libraries)"
            print_info "  - build-essential gcc-mingw-w64-x86-64 (WSL source-build toolchain)"
            print_info "  - Optional: libwayland-dev wayland-protocols wl-clipboard (WSL Wayland companion)"
        elif [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
            print_info "  - libx11-dev libxfixes-dev (X11 libraries)"
            print_info "  - xclip (clipboard tool, optional)"
        elif [[ "$DETECTED_DISPLAY_SERVER" == "macos" ]]; then
            print_info "  - Xcode Command Line Tools: xcode-select --install"
        else
            print_info "  - wayland-dev wayland-protocols (Wayland libraries)"
            print_info "  - wl-clipboard (clipboard tool, optional)"
            print_info "  - libx11-dev libxfixes-dev (Optional: for XWayland support)"
        fi
        print_info "  - pkg-config, git, zsh"
        MANUAL_STEPS+=("Install build dependencies for your distribution")
        return
        ;;
    esac

    _zes_wsl_build_toolchain_postcheck
}


install_deps_macos() {
    print_substep "macOS: checking Xcode Command Line Tools..."

    # Xcode Command Line Tools provide clang + all required SDK headers
    # (AppKit, ApplicationServices, CoreGraphics). No Homebrew packages needed.
    if ! xcode-select -p &>/dev/null 2>&1; then
        print_step "Installing Xcode Command Line Tools (provides clang + SDK headers)..."
        print_info "A system dialog will appear. Click 'Install' and wait to complete."
        xcode-select --install 2>/dev/null || true
        echo ""
        print_info "After the CLT installation completes, press Enter to continue..."
        flush_stdin
        read -r
    else
        print_success "Xcode Command Line Tools already installed: $(xcode-select -p)" "xcode_clt"
    fi

    # Optional: tmux users benefit from reattach-to-user-namespace for
    # proper pasteboard namespace access inside tmux sessions.
    if command_exists tmux && command_exists brew; then
        echo ""
        print_info "tmux detected. 'reattach-to-user-namespace' improves clipboard inside tmux."
        if ask_yes_no "Install reattach-to-user-namespace via brew? (optional)" "n"; then
            brew install reattach-to-user-namespace 2>/dev/null || \
                print_warning "brew install failed; run manually: brew install reattach-to-user-namespace"
        fi
    fi

    echo ""
    if command_exists python3; then
        print_success "Python3 available: $(python3 --version 2>/dev/null | head -1)" "python3_check"
    else
        print_warning "Python3 not found. VS Code JSON updates will use a less robust shell fallback."

        if command_exists brew && [[ $NON_INTERACTIVE -eq 0 ]]; then
            if ask_yes_no "Install Python3 via brew for safer VS Code JSON updates? (optional)" "n"; then
                if brew install python 2>/dev/null && command_exists python3; then
                    print_success "Python3 installed via brew: $(python3 --version 2>/dev/null | head -1)" "python3_check"
                else
                    print_warning "brew install python failed; continue with shell fallback or install Python3 manually."
                    MANUAL_STEPS+=("Install Python3 for robust VS Code JSON edits: brew install python")
                fi
            fi
        elif [[ $NON_INTERACTIVE -eq 1 ]]; then
            print_info "Non-interactive mode: skipping optional Python3 installation."
            MANUAL_STEPS+=("Install Python3 for robust VS Code JSON edits: brew install python")
        else
            print_info "Install Python3 manually (example: brew install python) if you plan to configure VS Code automatically."
            MANUAL_STEPS+=("Install Python3 for robust VS Code JSON edits")
        fi
    fi

    print_success "macOS build dependencies ready" "deps_install"
}


_zes_wsl_build_toolchain_postcheck() {
    if [[ "$DETECTED_OS" != "wsl" ]]; then
        return 0
    fi

    if command_exists x86_64-w64-mingw32-gcc || command_exists mingw-w64-gcc; then
        return 0
    fi

    print_warning "WSL source builds require a MinGW x86_64 cross-compiler for zes-wsl-clipboard-helper.exe"

    if [[ "$DETECTED_PACKAGE_MANAGER" == "apt" ]]; then
        print_info "Install WSL build deps: sudo apt-get install build-essential gcc-mingw-w64-x86-64 libx11-dev libxfixes-dev pkg-config"
        MANUAL_STEPS+=("Install WSL build deps: sudo apt-get install build-essential gcc-mingw-w64-x86-64 libx11-dev libxfixes-dev pkg-config")
    else
        print_info "Install a package that provides x86_64-w64-mingw32-gcc, then rerun: edit-select build"
        MANUAL_STEPS+=("Install WSL cross-compiler (x86_64-w64-mingw32-gcc), then rerun: edit-select build")
    fi
}


ask_xwayland_deps() {
    # WSL source builds include the WSL XWayland companion toolchain.
    if [[ "$DETECTED_OS" == "wsl" ]]; then
        return 0 # yes
    fi

    # Always install X11 dev headers for Wayland users (XWayland compatibility)
    if [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        return 0 # yes
    fi
    return 1 # no
}


identify_broken_apt_repos() {
    if [[ ! -d "/etc/apt/sources.list.d" ]]; then
        return
    fi

    print_info "Checking for broken repository sources..."
    local broken_repos=()

    # Common problematic repositories
    local -A common_issues=(
        ["cursor"]="Cursor editor repository (often becomes inaccessible)"
        ["chrome"]="Google Chrome repository (sometimes has signing issues)"
        ["docker"]="Docker repository (may need key updates)"
        ["vscode"]="VS Code repository (occasionally has issues)"
    )

    for repo_file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        if [[ -f "$repo_file" ]]; then
            local repo_name
            repo_name=$(basename "$repo_file")
            repo_name="${repo_name%.list}"
            repo_name="${repo_name%.sources}"
            # Check if it matches known problematic patterns
            for pattern in "${!common_issues[@]}"; do
                if [[ "$repo_name" == *"$pattern"* ]]; then
                    broken_repos+=("$repo_file: ${common_issues[$pattern]}")
                fi
            done
        fi
    done

    if [[ ${#broken_repos[@]} -gt 0 ]]; then
        echo ""
        print_warning "Potentially problematic repositories detected:"
        for repo in "${broken_repos[@]}"; do
            echo "  • $repo"
        done
        echo ""
        print_info "To fix: You can temporarily disable these by adding # at the start of lines in the .list files"
        print_info "Or remove them: sudo rm /etc/apt/sources.list.d/[problematic-file].list"
        echo ""
    fi
}


install_deps_apt() {
    print_substep "Using APT package manager..."

    # Update package lists — run in background and show a live elapsed timer so
    # the user gets immediate feedback during what can be a 20-60 second fetch.
    print_substep "Updating package lists..."
    local _upd_tmp
    _upd_tmp=$(mktemp /tmp/apt-update-XXXXXX 2>/dev/null) || {
        print_error "Failed to create temporary file"
        return 1
    }
    run_with_sudo apt-get update >"$_upd_tmp" 2>&1 &
    local _upd_pid=$!
    local _upd_elapsed=0
    while kill -0 "$_upd_pid" 2>/dev/null; do
        printf "\r  ${DIM}fetching repository metadata... [%ds]${NC}" "$_upd_elapsed"
        sleep 1
        ((_upd_elapsed++)) || true
    done
    wait "$_upd_pid"
    local _upd_exit=$?
    printf "\r\033[K" # erase the timer line
    local update_output
    update_output=$(cat "$_upd_tmp" 2>/dev/null)
    rm -f "$_upd_tmp"
    if [[ $_upd_exit -ne 0 ]]; then
        # apt update failed - check if it's due to broken third-party repos
        if echo "$update_output" | grep -qi "failed to fetch\|403\|repository.*no longer signed"; then
            print_warning "Some repository sources failed to update"
            echo "$update_output" | grep -i "failed\|403\|no longer signed" | head -5
            echo ""

            # Identify specific broken repositories
            identify_broken_apt_repos

            print_info "This is likely due to third-party repositories (e.g., Cursor, Chrome, etc.)"
            print_info "The main system repositories should still work fine."
            echo ""

            if [[ $NON_INTERACTIVE -eq 0 ]]; then
                if ask_yes_no "Continue with installation anyway? (Recommended: Yes)" "y"; then
                    print_info "Continuing with available repositories..."
                else
                    print_info "Installation cancelled. To fix repository issues:"
                    print_info "  1. Check /etc/apt/sources.list.d/ for broken repositories"
                    print_info "  2. Remove or fix the problematic .list files"
                    print_info "  3. Run: sudo apt-get update"
                    print_info "  4. Re-run this installer"
                    FAILED_STEPS["APT repository update"]="Fix broken repositories in /etc/apt/sources.list.d/"
                    return 1
                fi
            else
                print_info "Non-interactive mode: continuing despite repository warnings..."
            fi
        else
            # Other apt update error
            print_error "Failed to update package lists"
            log_message "APT_UPDATE_FAILED: $update_output"
            MANUAL_STEPS+=("Fix apt sources and run: sudo apt-get update")
            return 1
        fi
    else
        print_success "Package lists updated (${_upd_elapsed}s)" "apt_update"
    fi

    local packages=("build-essential" "pkg-config" "git" "zsh")

    if [[ "$DETECTED_OS" == "wsl" ]]; then
        # WSL source builds require:
        #  - WSL native agent toolchain (build-essential)
        #  - WSL Windows helper cross-compiler (gcc-mingw-w64-x86-64)
        #  - XWayland build headers (libx11-dev/libxfixes-dev)
        packages+=("libx11-dev" "libxfixes-dev" "gcc-mingw-w64-x86-64")

        # Optional WSL Wayland companion build path.
        if [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
            packages+=("libwayland-dev" "wayland-protocols" "wl-clipboard")
        fi
    elif [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        packages+=("libx11-dev" "libxfixes-dev" "xclip")
    else
        packages+=("libwayland-dev" "wayland-protocols" "wl-clipboard")
        if ask_xwayland_deps; then
            packages+=("libx11-dev" "libxfixes-dev")
        fi
    fi

    print_info "Packages to install:"
    for _pkg in "${packages[@]}"; do
        echo -e "    ${DIM}•${NC} ${_pkg}"
    done
    echo ""

    # Dry-run first to learn the exact number of packages apt will install,
    # so we can show a meaningful 0→100% progress bar during the real install.
    local _total
    _total=$(run_with_sudo apt-get install -s "${packages[@]}" 2>/dev/null |
        grep -c "^Inst ")
    [[ "${_total:-0}" -lt 1 ]] && _total=1 # guard against already-installed

    # Run apt-get install in two visible phases:
    #   1. Download  — --download-only streamed; Get:N lines drive a 0→100% bar
    #   2. Install   — plain lines: Installing X... / Configuring X... / triggers
    local _bar_width=30

    # Helper: render the bar in-place (overwrites current terminal line)
    _apt_bar() {
        local _n=$1 _tot=$2 _label=${3:-}
        local _pct=$((_n * 100 / _tot))
        local _filled=$((_n * _bar_width / _tot))
        local _empty=$((_bar_width - _filled))
        local _bar="" _i
        for ((_i = 0; _i < _filled; _i++)); do _bar+="█"; done
        for ((_i = 0; _i < _empty; _i++)); do _bar+="░"; done
        printf "\r  \033[0;34m[%s]\033[0m %3d%%%s" "$_bar" "$_pct" "$_label"
    }

    # Phase 1 — download with live progress bar
    printf "  Downloading packages...\n"
    local _dl_n=0
    run_with_sudo apt-get install -y --download-only "${packages[@]}" 2>&1 |
        grep --line-buffered "^Get:[0-9]" |
        while IFS= read -r _line; do
            if [[ "$_line" =~ ^Get:([0-9]+) ]]; then
                _dl_n="${BASH_REMATCH[1]}"
                _apt_bar "$_dl_n" "$_total" ""
            fi
        done
    # Print the completed bar then move to a new line
    _apt_bar "$_total" "$_total" ""
    printf "\r\033[K"
    echo "  Downloading packages... done"

    # Phase 2 — install: plain lines streamed live
    run_with_sudo apt-get install -y "${packages[@]}" 2>&1 |
        grep --line-buffered -E \
            "^(Unpacking |Setting up |Processing triggers )" |
        while IFS= read -r _line; do
            if [[ "$_line" =~ ^Unpacking\ ([^\ :]+) ]]; then
                echo "  Installing ${BASH_REMATCH[1]}..."
            elif [[ "$_line" =~ ^"Setting up "([^\ :]+) ]]; then
                echo "  Configuring ${BASH_REMATCH[1]}..."
            elif [[ "$_line" =~ ^"Processing triggers for "([^\ \(]+) ]]; then
                echo "  Processing triggers for ${BASH_REMATCH[1]}..."
            fi
        done
    local apt_install_status="${PIPESTATUS[0]}"
    flush_stdin

    if [[ "$apt_install_status" -eq 0 ]]; then
        # Verify critical packages were actually installed
        local failed_packages=()
        for pkg in "${packages[@]}"; do
            if ! verify_package_installed "$pkg" "apt"; then
                failed_packages+=("$pkg")
            fi
        done

        if [[ ${#failed_packages[@]} -eq 0 ]]; then
            print_success "Dependencies installed via APT" "deps_install"
        else
            print_warning "Some packages may not have installed: ${failed_packages[*]}" "deps_install"
            MANUAL_STEPS+=("Verify these packages: sudo apt-get install ${failed_packages[*]}")
        fi
    else
        print_error "Failed to install some dependencies via APT" "deps_install"
        MANUAL_STEPS+=("Install missing packages: sudo apt-get install ${packages[*]}")
    fi
}
