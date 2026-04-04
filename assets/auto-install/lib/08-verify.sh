#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Post-installation verification suite
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_VERIFY_LOADED:-}" ]] && return 0
readonly _ZES_MOD_VERIFY_LOADED=1

verify_installation() {
    if [[ $SKIP_VERIFY -eq 1 ]]; then
        print_info "Skipping post-installation verification (--skip-verify flag)"
        return
    fi

    verify_plugin_files
    verify_zshrc_config
    verify_dependencies
    verify_monitor_daemons
    verify_terminal_config
    verify_plugin_loads          # Test that plugin actually loads
    verify_terminal_capabilities # Test terminal supports required escape sequences

    if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
        test_warning "Configuration conflicts detected ($TOTAL_CONFLICTS)" "Scroll up to Phase 6 conflict report and apply the listed fixes"
    else
        test_pass "No configuration conflicts detected"
    fi

    echo ""
    local total_tests=$((PASSED_TESTS + FAILED_TESTS + WARNING_TESTS))
    echo -e "${BOLD}Verification Summary:${NC}"
    echo -e "  ${GREEN}✓ Passed:${NC}   $PASSED_TESTS / $total_tests"
    echo -e "  ${RED}✗ Failed:${NC}   $FAILED_TESTS / $total_tests"
    echo -e "  ${YELLOW}⚠ Warnings:${NC} $WARNING_TESTS / $total_tests"
}


verify_plugin_files() {
    print_step "Verifying plugin installation..."

    if [[ -d "$PLUGIN_INSTALL_DIR" ]]; then
        test_pass "Plugin directory exists: $PLUGIN_INSTALL_DIR"
    else
        test_fail "Plugin directory not found" "Check installation process"
        return
    fi

    local -a required_files=(
        "zsh-edit-select.plugin.zsh"
    )

    # Check for implementation directories (display-server specific)
    local -a required_dirs=(
        "impl-x11"
        "impl-wayland"
        "impl-macos"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$PLUGIN_INSTALL_DIR/$file" ]]; then
            test_pass "Found: $file"
        else
            test_fail "Missing file: $file" "Plugin may not function correctly"
        fi
    done

    for dir in "${required_dirs[@]}"; do
        if [[ -d "$PLUGIN_INSTALL_DIR/$dir" ]]; then
            test_pass "Found directory: $dir/"
        else
            test_warning "Missing directory: $dir/" "May affect display server support"
        fi
    done
}


verify_zshrc_config() {
    print_step "Verifying .zshrc configuration..."

    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"

    if [[ ! -f "$zshrc" ]]; then
        test_fail ".zshrc not found" "Plugin will not be loaded"
        return
    fi

    if grep -qF "zsh-edit-select" "$zshrc" 2>/dev/null; then
        test_pass "Plugin configured in .zshrc"
    elif [[ "$DETECTED_PLUGIN_MANAGER" == "sheldon" ]]; then
        # Sheldon stores config in plugins.toml, not .zshrc
        local sheldon_config="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
        if [[ -f "$sheldon_config" ]] && grep -qF "zsh-edit-select" "$sheldon_config" 2>/dev/null; then
            test_pass "Plugin configured in Sheldon plugins.toml"
        else
            test_fail "Plugin not found in Sheldon config" "Add plugin to plugins.toml manually"
        fi
    else
        test_fail "Plugin not found in .zshrc" "Add plugin to .zshrc manually"
    fi
}


verify_dependencies() {
    print_step "Verifying dependencies..."

    local prebuilt_expected=0
    local arch
    arch=$(uname -m 2>/dev/null)
    if [[ "$DETECTED_OS" == "macos" || "$DETECTED_OS" == "wsl" || "$arch" == "x86_64" || "$arch" == "amd64" || "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        prebuilt_expected=1
    fi

    # Compiler
    if command_exists gcc || command_exists clang; then
        test_pass "C compiler available"
    elif [[ $prebuilt_expected -eq 1 ]]; then
        test_pass "C compiler bypassed (using pre-built agents)"
    else
        test_fail "C compiler not found" "Install gcc or clang"
    fi

    # Make
    if command_exists make; then
        test_pass "Make build system available"
    elif [[ $prebuilt_expected -eq 1 ]]; then
        test_pass "Make bypassed (using pre-built agents)"
    else
        test_fail "Make not found" "Install make"
    fi

    # pkg-config
    if command_exists pkg-config; then
        test_pass "pkg-config available"
    elif [[ $prebuilt_expected -eq 1 ]]; then
        test_pass "pkg-config bypassed (using pre-built agents)"
    else
        test_warning "pkg-config not found" "May affect build process"
    fi

    # Display server tools
    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        if command_exists xclip; then
            test_pass "xclip available (fallback clipboard tool)"
        elif [[ $prebuilt_expected -eq 1 ]]; then
            test_pass "xclip bypassed (using pre-built custom agent)"
        else
            test_warning "xclip not found" "Custom agent will be required"
        fi
    elif [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        if command_exists wl-copy && command_exists wl-paste; then
            test_pass "wl-clipboard available (fallback clipboard tool)"
        elif [[ $prebuilt_expected -eq 1 ]]; then
            test_pass "wl-clipboard bypassed (using pre-built custom agent)"
        else
            test_warning "wl-clipboard not found" "Custom agent will be required"
        fi
    fi

    # Zsh
    if command_exists zsh; then
        local zsh_version
        zsh_version=$(zsh --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        test_pass "Zsh available (version ${zsh_version:-unknown})"
    else
        test_fail "Zsh not found" "Install zsh"
    fi

    # Git
    if command_exists git; then
        test_pass "Git available"
    else
        test_fail "Git not found" "Install git"
    fi

    # Python3 (optional, for robust VS Code config)
    if command_exists python3; then
        test_pass "Python3 available (preferred for JSON config)"
    else
        test_warning "Python3 not available" "Using shell fallback for JSON config (less robust)"
    fi
}


verify_monitor_daemons() {
    print_step "Verifying agents..."

    local runtime_impl
    runtime_impl="$(_zes_detect_runtime_impl)"

    case "$runtime_impl" in
    x11)
        local x11_binary="$PLUGIN_INSTALL_DIR/impl-x11/backends/x11/zes-x11-selection-agent"
        if [[ -s "$x11_binary" ]]; then
            test_pass "X11 agent binary installed"
        else
            test_fail "X11 agent binary missing" "Expected: $x11_binary"
        fi
        ;;

    wayland)
        local wayland_binary="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent"
        local xwayland_binary="$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland/zes-xwayland-agent"
        local desktop="${XDG_CURRENT_DESKTOP:-}"
        local prefer_xwayland=0
        local has_runtime_monitor=0

        case "$desktop" in
        *GNOME* | *gnome* | *Cinnamon* | *cinnamon* | *Pantheon* | *pantheon*)
            prefer_xwayland=1
            ;;
        esac

        if [[ $prefer_xwayland -eq 1 ]] && [[ -n "${DISPLAY:-}" ]] && [[ -s "$xwayland_binary" ]]; then
            test_pass "XWayland monitor binary installed (desktop-preferred path)"
            has_runtime_monitor=1
        elif [[ -s "$wayland_binary" ]]; then
            test_pass "Wayland monitor binary installed"
            has_runtime_monitor=1
        elif [[ -s "$xwayland_binary" ]]; then
            test_pass "XWayland monitor binary installed"
            has_runtime_monitor=1
        fi

        if [[ $has_runtime_monitor -eq 0 ]]; then
            test_fail "No runnable Wayland/XWayland monitor binary found" "Check agent installation"
        fi
        ;;

    macos)
        local macos_binary="$PLUGIN_INSTALL_DIR/impl-macos/backends/macos/zes-macos-clipboard-agent"
        if [[ -s "$macos_binary" ]]; then
            test_pass "macOS monitor binary installed"
        else
            test_fail "macOS monitor binary missing" "Expected: $macos_binary"
        fi
        ;;

    wsl)
        local wsl_binary="$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-selection-agent"
        local wsl_helper="$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-clipboard-helper.exe"
        local wsl_xwayland="$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland/zes-xwayland-agent"

        if [[ -s "$wsl_binary" ]]; then
            test_pass "WSL selection agent installed"
        else
            test_fail "WSL selection agent missing" "Expected: $wsl_binary"
        fi

        if [[ -s "$wsl_helper" ]]; then
            test_pass "WSL clipboard helper installed"
        else
            test_fail "WSL clipboard helper missing" "Expected: $wsl_helper"
        fi

        if [[ -n "${DISPLAY:-}" ]]; then
            if [[ -s "$wsl_xwayland" ]]; then
                test_pass "WSL XWayland monitor binary installed"
            else
                test_warning "WSL XWayland monitor binary missing" "Optional if Wayland monitor path is used"
            fi
        fi
        ;;
    esac

    local cache_dir
    cache_dir="$(_zes_agent_cache_dir "$runtime_impl")"
    local pid_file="$cache_dir/agent.pid"
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            test_pass "Agent daemon is running (PID $pid)"
        else
            test_warning "Agent daemon PID file is stale" "Installer attempted to start the daemon automatically"
        fi
    else
        test_warning "Agent daemon PID file not found" "Installer attempted to start the daemon automatically"
    fi
}


verify_terminal_config() {
    print_step "Verifying terminal configurations..."

    local -a terminals_to_verify=()
    if [[ ${#TERMINALS_SELECTED_FOR_CONFIG[@]} -gt 0 ]]; then
        terminals_to_verify=("${TERMINALS_SELECTED_FOR_CONFIG[@]}")
    else
        print_info "Skipping terminal config warnings for terminals not selected during configuration."
        return
    fi

    for terminal in "${terminals_to_verify[@]}"; do
        case "$terminal" in
        kitty)
            local config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
            if [[ -f "$config" ]] && grep -qF "Zsh Edit-Select" "$config"; then
                test_pass "Kitty configured"
            else
                test_warning "Kitty config not updated" "May need manual setup"
            fi
            ;;
        alacritty)
            local toml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
            local yml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
            if ([[ -f "$toml" ]] && grep -qF "Zsh Edit-Select" "$toml") ||
                ([[ -f "$yml" ]] && grep -qF "Zsh Edit-Select" "$yml"); then
                test_pass "Alacritty configured"
            else
                test_warning "Alacritty config not updated" "May need manual setup"
            fi
            ;;
        wezterm)
            local wez_config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
            local wez_alt="$HOME/.wezterm.lua"
            if ([[ -f "$wez_config" ]] && grep -qF "Zsh Edit-Select" "$wez_config" 2>/dev/null) ||
                ([[ -f "$wez_alt" ]] && grep -qF "Zsh Edit-Select" "$wez_alt" 2>/dev/null); then
                test_pass "WezTerm configured"
            else
                test_warning "WezTerm config not updated" "May need manual setup"
            fi
            ;;
        foot)
            local config="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
            if [[ -f "$config" ]] && grep -qF "Zsh Edit-Select" "$config"; then
                test_pass "Foot configured"
            else
                test_warning "Foot config not updated" "May need manual setup"
            fi
            ;;
        ghostty)
            local config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
            if [[ -f "$config" ]] && grep -qF "Zsh Edit-Select" "$config"; then
                test_pass "Ghostty configured"
            else
                test_warning "Ghostty config not updated" "May need manual setup"
            fi
            ;;
        code | vscode)
            # VS Code JSON has no comment syntax, so we cannot embed a
            # "Zsh Edit-Select" marker.  Instead detect any of the
            # escape sequences configure_vscode() always writes:
            #   90;6u  = Ctrl+Shift+Z redo  (always present in common_bindings)
            #   67;6u  = Ctrl+Shift+C copy  (present in default mode)
            #   1;2D   = Shift+Left         (always present in common_bindings)
            local vscode_found=0
                local kb
                if declare -f _zes_vscode_keybindings_candidates >/dev/null 2>&1; then
                    while IFS= read -r kb; do
                        [[ -z "$kb" ]] && continue
                        if [[ -f "$kb" ]] &&
                            grep -qE '(90;6u|67;6u|1;2D)' "$kb" 2>/dev/null; then
                            test_pass "VS Code configured"
                            vscode_found=1
                            break
                        fi
                    done < <(_zes_vscode_keybindings_candidates)
                else
                    local vscode_dir
                    for vscode_dir in \
                        "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" \
                        "$HOME/.config/Code/User" \
                        "$HOME/.config/Code - OSS/User" \
                        "$HOME/.config/Code - Insiders/User"; do
                        kb="$vscode_dir/keybindings.json"
                        if [[ -f "$kb" ]] &&
                            grep -qE '(90;6u|67;6u|1;2D)' "$kb" 2>/dev/null; then
                            test_pass "VS Code configured"
                            vscode_found=1
                            break
                        fi
                    done
                fi
            if [[ $vscode_found -eq 0 ]]; then
                test_warning "VS Code keybindings not updated" "May need manual setup"
            fi
            ;;
        windows-terminal)
            local config="${WT_SETTINGS_PATH:-}"
            if [[ -n "$config" ]] && [[ -f "$config" ]]; then
                if grep -q "\"_zes_configured\": true" "$config" 2>/dev/null; then
                    test_pass "Windows Terminal configured"
                else
                    test_warning "Windows Terminal config not updated" "May need manual setup"
                fi
            else
                test_warning "Windows Terminal config missing" "Setup required"
            fi
            ;;
        esac
    done
}


verify_plugin_loads() {
    print_step "Testing plugin loading in Zsh..."

    if ! command_exists zsh; then
        test_warning "Zsh not found, skipping load test" "Install Zsh first"
        return
    fi

    # Create a temporary test script that sources zshrc and checks for plugin
    local test_script
    test_script=$(mktemp /tmp/test-zsh-plugin-XXXXXX) || {
        test_warning "Could not create temp file for plugin load test" "Skipping"
        return
    }
    cat >"$test_script" <<EOF
#!/usr/bin/env zsh
# Set options for clean test environment
setopt NO_GLOBAL_RCS
export HOME="$HOME"
export ZDOTDIR="${ZDOTDIR:-$HOME}"

# Source .zshrc
if [[ -f "\${ZDOTDIR:-\$HOME}/.zshrc" ]]; then
    source "\${ZDOTDIR:-\$HOME}/.zshrc"
else
    exit 1
fi

# Check if plugin is loaded by checking for its functions
if typeset -f edit-select::select-all &>/dev/null || \\
   typeset -f edit-select::copy-region &>/dev/null || \\
   [[ -n "\${functions[edit-select::select-all]:-}" ]] || \\
   [[ -n "\${functions[edit-select::copy-region]:-}" ]]; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x "$test_script"

    # Disable terminal focus-tracking before running the zsh subprocess.
    # Kitty (and other terminals) inject ESC[I / ESC[O focus events into stdin
    # when a child process changes focus state.  Without this, those sequences
    # (displayed as ^[[I) leak into the output of the very next echo/print call.
    printf '\033[?1004l' 2>/dev/null || true # disable focus tracking
    flush_stdin                              # drain any already-queued events

    # Run the test in a subprocess with timeout
    local _load_ok=0
    if command_exists timeout; then
        timeout 10 zsh "$test_script" &>/dev/null && _load_ok=1
    else
        zsh "$test_script" &>/dev/null && _load_ok=1
    fi

    # Drain any focus events the subprocess may have triggered.
    # We do NOT re-enable focus tracking — this installer never requested it,
    # and re-enabling it would cause further ESC[I / ESC[O leaks.
    sleep 0.3 2>/dev/null || true
    flush_stdin

    if [[ $_load_ok -eq 1 ]]; then
        test_pass "Plugin successfully loads in Zsh"
        rm -f "$test_script"
        return 0
    fi

    rm -f "$test_script"
    test_warning "Could not verify plugin loads in Zsh" "Manual test recommended: restart terminal and test selection"
}


verify_terminal_capabilities() {
    print_step "Checking terminal capabilities..."

    # Only run this test if we're in an interactive terminal
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        test_warning "Not running in interactive terminal, skipping capability test" "Test manually after installation"
        return
    fi

    # Identify the terminal we are currently running in.
    # Different terminals expose themselves through different env vars:
    #   Kitty      → KITTY_WINDOW_ID / TERM=xterm-kitty
    #   Alacritty  → ALACRITTY_WINDOW_ID / TERM=alacritty
    #   WezTerm    → TERM_PROGRAM=WezTerm / WEZTERM_EXECUTABLE
    #   Ghostty    → TERM=xterm-ghostty / TERM_PROGRAM=ghostty
    #   Foot       → TERM=foot / TERM=foot-*
    #   VS Code    → VSCODE_INJECTION / TERM_PROGRAM=vscode
    #   VTE-based  → VTE_VERSION (GNOME Terminal, xfce4-terminal, tilix, terminator)
    #   Konsole    → KONSOLE_DBUS_SESSION

    local current_terminal=""
    local term="${TERM:-}"
    local term_program="${TERM_PROGRAM:-}"

    if [[ -n "${KITTY_WINDOW_ID:-}" ]] || [[ "$term" == "xterm-kitty" ]]; then
        current_terminal="kitty"
    elif [[ -n "${ALACRITTY_WINDOW_ID:-}" ]] || [[ "$term" == "alacritty" ]]; then
        current_terminal="alacritty"
    elif [[ "$term_program" == "WezTerm" ]] || [[ -n "${WEZTERM_EXECUTABLE:-}" ]]; then
        current_terminal="wezterm"
    elif [[ "$term" == "xterm-ghostty" ]] || [[ "$term_program" == "ghostty" ]] ||
        [[ -n "${GHOSTTY_BIN_DIR:-}" ]] || [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
        current_terminal="ghostty"
    elif [[ "$term" == "foot" ]] || [[ "$term" == foot-* ]]; then
        current_terminal="foot"
    elif [[ -n "${VSCODE_INJECTION:-}" ]] || [[ "$term_program" == "vscode" ]]; then
        current_terminal="vscode"
    elif [[ -n "${VTE_VERSION:-}" ]]; then
        current_terminal="vte-based"
    elif [[ -n "${KONSOLE_DBUS_SESSION:-}" ]]; then
        current_terminal="konsole"
    fi

    # Terminals known to support all required escape sequences (CSI u, Shift+Arrow, etc.)
    local -A supported_map=(
        [kitty]=1 [alacritty]=1 [wezterm]=1 [ghostty]=1 [foot]=1 [vscode]=1
        [konsole]=1 [vte-based]=1
    )

    if [[ -n "$current_terminal" ]] && [[ -n "${supported_map[$current_terminal]:-}" ]]; then
        test_pass "Terminal appears to support required features ($current_terminal)"
        return
    fi

    # Fallback: check if any terminal we detected and configured is the one
    # we're likely running in.  This handles the case where we can't identify
    # the current terminal via env vars but we configured it anyway.
    if [[ ${#DETECTED_TERMINALS[@]} -gt 0 ]]; then
        for t in "${DETECTED_TERMINALS[@]}"; do
            if [[ -n "${supported_map[$t]:-}" ]]; then
                test_pass "Terminal configuration applied (configured ${#DETECTED_TERMINALS[@]} terminal(s))"
                return
            fi
        done
    fi

    # We could not identify the current terminal or it's not in our supported list
    local hint="unknown terminal"
    [[ -n "$term" ]] && hint="TERM=$term"
    [[ -n "$term_program" ]] && hint="TERM_PROGRAM=$term_program"
    test_warning "Could not identify current terminal ($hint)" "Configure your terminal manually if Shift+Arrow keys don't work"
    print_info "  If selection doesn't work, see README.md for terminal setup instructions"
}

# Summary Report
