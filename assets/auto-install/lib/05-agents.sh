#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Agent provisioning (release install + build fallback)
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_AGENTS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_AGENTS_LOADED=1

build_monitor_daemons() {
    if [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory not found: $PLUGIN_INSTALL_DIR" "monitor_build"
        return
    fi

    local runtime_impl
    runtime_impl="${1:-}"
    if [[ -z "$runtime_impl" ]]; then
        runtime_impl="$(_zes_detect_runtime_impl)"
    fi

    print_step "Installing pre-built agent binaries from GitHub Releases..."
    if _zes_release_agent_provision "$runtime_impl"; then
        print_success "Required agent binaries are installed" "agent_release_install"
    else
        print_warning "Some agent binaries could not be installed automatically" "agent_release_install"
    fi

    # Keep source builds available as an optional advanced path.
    if [[ $NON_INTERACTIVE -eq 0 ]] && [[ "${_ZES_USER_SKIPPED_DEPS:-1}" -eq 0 ]]; then
        echo ""
        if ask_yes_no "Compile the agent binaries from source as well? (optional)" "n"; then
            _zes_build_source_agents_for_impl "$runtime_impl"
        fi
    fi

    _zes_start_runtime_agent "$runtime_impl"
    _zes_warmup_plugin_load "$runtime_impl"
}

refresh_agents_runtime() {
    local runtime_impl="${1:-}"
    if [[ -z "$runtime_impl" ]]; then
        runtime_impl="$(_zes_detect_runtime_impl)"
    fi

    print_step "Stopping old agent processes..."
    _zes_stop_agent_processes

    print_step "Clearing old agent cache/runtime files..."
    _zes_clear_agent_runtime_cache "$runtime_impl"

    print_step "Deleting previously installed agent binaries..."
    _zes_remove_agent_binaries "$runtime_impl"

    print_step "Resetting compiled plugin cache (.zwc) before warm-up..."
    _zes_remove_plugin_zwc_files

    print_step "Re-installing, activating, and warming up agents..."
    build_monitor_daemons "$runtime_impl"
}

_zes_install_build_dependencies_for_source_mode() {
    if [[ $SKIP_DEPS -eq 1 ]]; then
        print_warning "Cannot auto-install build dependencies because --skip-deps is set"
        MANUAL_STEPS+=("Re-run without --skip-deps to install build dependencies for source builds")
        return 1
    fi

    local had_force_flag=0
    local previous_force_value=""
    if [[ "${_ZES_FORCE_BUILD_DEPS_INSTALL+x}" == "x" ]]; then
        had_force_flag=1
        previous_force_value="${_ZES_FORCE_BUILD_DEPS_INSTALL}"
    fi

    _ZES_FORCE_BUILD_DEPS_INSTALL=1
    install_dependencies
    local install_status=$?

    if [[ $had_force_flag -eq 1 ]]; then
        _ZES_FORCE_BUILD_DEPS_INSTALL="$previous_force_value"
    else
        unset _ZES_FORCE_BUILD_DEPS_INSTALL
    fi

    return "$install_status"
}

_zes_build_source_agents_with_dependency_retry() {
    local runtime_impl="$1"

    if _zes_build_source_agents_for_impl "$runtime_impl"; then
        return 0
    fi

    print_warning "Source build failed or build dependencies are missing." "agent_source_build"

    if [[ $SKIP_DEPS -eq 1 ]]; then
        MANUAL_STEPS+=("Install source-build dependencies manually and run: edit-select build")
        return 1
    fi

    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        echo ""
        if ! ask_yes_no "Install missing build dependencies now and retry source build?" "y"; then
            MANUAL_STEPS+=("Install source-build dependencies manually and run: edit-select build")
            return 1
        fi
    else
        print_info "Non-interactive mode: attempting dependency installation and retrying source build."
    fi

    if ! _zes_install_build_dependencies_for_source_mode; then
        print_warning "Build dependency installation did not fully complete; retrying source build anyway."
    fi

    print_step "Retrying source build after dependency installation..."
    _zes_build_source_agents_for_impl "$runtime_impl"
}

refresh_agents_runtime_from_source() {
    local runtime_impl="${1:-}"
    if [[ -z "$runtime_impl" ]]; then
        runtime_impl="$(_zes_detect_runtime_impl)"
    fi

    print_step "Stopping old agent processes..."
    _zes_stop_agent_processes

    print_step "Clearing old agent cache/runtime files..."
    _zes_clear_agent_runtime_cache "$runtime_impl"

    print_step "Deleting previously installed agent binaries..."
    _zes_remove_agent_binaries "$runtime_impl"

    print_step "Resetting compiled plugin cache (.zwc) before warm-up..."
    _zes_remove_plugin_zwc_files

    print_step "Building agent binaries from source using runtime-specific Makefile targets..."
    if ! _zes_build_source_agents_with_dependency_retry "$runtime_impl"; then
        print_error "Failed to build required agent binaries from source for runtime: $runtime_impl" "agent_source_build"
        return 1
    fi

    local status=0

    print_step "Starting rebuilt runtime agents..."
    if ! _zes_start_runtime_agent "$runtime_impl"; then
        status=1
    fi

    if ! _zes_warmup_plugin_load "$runtime_impl"; then
        status=1
    fi

    return $status
}

reinstall_agents_after_update() {
    refresh_agents_runtime "$@"
}

_zes_stop_agent_processes() {
    local -a agent_patterns=(
        "zes-macos-clipboard-agent"
        "zes-x11-selection-agent"
        "zes-wl-selection-agent"
        "zes-xwayland-agent"
        "zes-wsl-selection-agent"
        "zes-wsl-clipboard-helper.exe"
        "zes-wsl-xwayland-agent"
    )

    if ! command_exists pkill; then
        print_warning "pkill is not available; cannot force-stop old agents automatically"
        MANUAL_STEPS+=("Stop old zsh-edit-select agent processes manually before re-running build/update")
        return
    fi

    local stopped_any=0
    local pattern
    for pattern in "${agent_patterns[@]}"; do
        if command_exists pgrep && ! pgrep -f "$pattern" >/dev/null 2>&1; then
            continue
        fi

        pkill -f "$pattern" 2>/dev/null || true
        sleep 0.05

        if command_exists pgrep && pgrep -f "$pattern" >/dev/null 2>&1; then
            pkill -9 -f "$pattern" 2>/dev/null || true
            sleep 0.05
        fi

        if ! command_exists pgrep || ! pgrep -f "$pattern" >/dev/null 2>&1; then
            print_substep "Stopped processes matching: $pattern"
            stopped_any=1
        fi
    done

    if [[ $stopped_any -eq 0 ]]; then
        print_substep "No old agent processes were running"
    fi
}

_zes_clear_agent_runtime_cache() {
    local runtime_impl="$1"
    local uid="${UID:-$(id -u 2>/dev/null || echo 0)}"
    local primary_cache
    primary_cache="$(_zes_agent_cache_dir "$runtime_impl")"

    local -a cache_paths=("$primary_cache")
    local tmp_cache="${TMPDIR:-/tmp}/zsh-edit-select-${uid}"
    if [[ "$tmp_cache" != "$primary_cache" ]]; then
        cache_paths+=("$tmp_cache")
    fi

    local removed_any=0
    local cache_path
    for cache_path in "${cache_paths[@]}"; do
        [[ -z "$cache_path" ]] && continue
        if [[ "$cache_path" == */zsh-edit-select-"${uid}" ]] && [[ -e "$cache_path" ]]; then
            rm -rf "$cache_path" 2>/dev/null || true
            if [[ ! -e "$cache_path" ]]; then
                print_substep "Removed cache directory: $cache_path"
                removed_any=1
            fi
        fi
    done

    if [[ $removed_any -eq 0 ]]; then
        print_substep "No existing cache directories found"
    fi
}

_zes_remove_agent_binaries() {
    local runtime_impl="$1"
    local -a binary_paths=(
        "$PLUGIN_INSTALL_DIR/impl-macos/backends/macos/zes-macos-clipboard-agent"
        "$PLUGIN_INSTALL_DIR/impl-x11/backends/x11/zes-x11-selection-agent"
        "$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent"
        "$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland/zes-xwayland-agent"
        "$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-selection-agent"
        "$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-clipboard-helper.exe"
        "$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland/zes-xwayland-agent"
        "$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland/zes-wsl-xwayland-agent"
    )

    local removed_any=0
    local binary_path
    for binary_path in "${binary_paths[@]}"; do
        [[ -z "$binary_path" ]] && continue
        if [[ "$binary_path" == "$PLUGIN_INSTALL_DIR/"* ]] && [[ -e "$binary_path" ]]; then
            rm -f "$binary_path" 2>/dev/null || true
            if [[ ! -e "$binary_path" ]]; then
                print_substep "Deleted binary: $binary_path"
                removed_any=1
            fi
        fi
    done

    if [[ $removed_any -eq 0 ]]; then
        print_substep "No existing managed binaries found"
    else
        print_substep "Binary refresh prepared for runtime: $runtime_impl"
    fi
}

_zes_remove_plugin_zwc_files() {
    if [[ -z "$PLUGIN_INSTALL_DIR" ]] || [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        return
    fi

    if ! command_exists find; then
        print_substep "Skipping .zwc cleanup (find not available)"
        return
    fi

    local removed_count=0
    local zwc_file
    while IFS= read -r zwc_file; do
        [[ -z "$zwc_file" ]] && continue
        rm -f "$zwc_file" 2>/dev/null || true
        if [[ ! -e "$zwc_file" ]]; then
            ((removed_count++))
        fi
    done < <(find "$PLUGIN_INSTALL_DIR" -type f -name '*.zwc' 2>/dev/null)

    if [[ $removed_count -gt 0 ]]; then
        print_substep "Deleted $removed_count .zwc file(s); warm-up will regenerate them"
    else
        print_substep "No .zwc files found"
    fi
}

_zes_detect_runtime_impl() {
    case "${DETECTED_OS:-}" in
    macos)
        echo "macos"
        return 0
        ;;
    wsl)
        echo "wsl"
        return 0
        ;;
    esac

    if [[ "${DETECTED_DISPLAY_SERVER:-}" == "wayland" ]]; then
        echo "wayland"
    else
        echo "x11"
    fi
}

_zes_agent_cache_dir() {
    local impl="$1"
    local uid="${UID:-$(id -u 2>/dev/null || echo 0)}"
    if [[ "$impl" == "macos" ]]; then
        echo "${TMPDIR:-/tmp}/zsh-edit-select-${uid}"
    else
        echo "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${uid}"
    fi
}

_zes_agent_path_ready() {
    local path="$1"
    local mode="${2:-binary}"

    [[ -s "$path" ]] || return 1
    if [[ "$mode" != "file" ]]; then
        chmod +x "$path" 2>/dev/null || true
    fi
    return 0
}

_zes_fetch_release_binary() {
    local impl="$1"
    local base_name="$2"
    local destination="$3"
    local fetch_helper="$PLUGIN_INSTALL_DIR/assets/fetch-agents.zsh"

    [[ -r "$fetch_helper" ]] || return 1
    command_exists zsh || return 1

    local destination_dir
    destination_dir="$(dirname "$destination")"
    mkdir -p "$destination_dir" 2>/dev/null || return 1

    zsh -c '
        impl="$1"
        base_name="$2"
        destination="$3"
        helper="$4"

        source "$helper" 2>/dev/null || exit 1
        asset_name=$(_zes_asset_name "$impl" "$base_name") || exit 1
        _zes_fetch_binary "$asset_name" "$destination"
    ' _ "$impl" "$base_name" "$destination" "$fetch_helper" >/dev/null 2>&1
}

_zes_ensure_release_or_build() {
    local impl="$1"
    local base_name="$2"
    local destination="$3"
    local label="$4"
    local fallback_builder="$5"
    local mode="${6:-binary}"

    if _zes_agent_path_ready "$destination" "$mode"; then
        print_success "$label already present" "agent_release_install"
        return 0
    fi

    if _zes_fetch_release_binary "$impl" "$base_name" "$destination" && _zes_agent_path_ready "$destination" "$mode"; then
        print_success "$label downloaded from GitHub Releases" "agent_release_install"
        return 0
    fi

    if [[ -n "$fallback_builder" ]] && declare -F "$fallback_builder" >/dev/null; then
        "$fallback_builder"
    fi

    if _zes_agent_path_ready "$destination" "$mode"; then
        print_success "$label built from source fallback" "agent_release_install"
        return 0
    fi

    print_error "$label is unavailable after download/build attempts" "agent_release_install"
    MANUAL_STEPS+=("Install/build $label manually at $destination")
    return 1
}

_zes_release_agent_provision() {
    local runtime_impl="$1"
    local failures=0

    case "$runtime_impl" in
    macos)
        _zes_ensure_release_or_build "macos" \
            "zes-macos-clipboard-agent" \
            "$PLUGIN_INSTALL_DIR/impl-macos/backends/macos/zes-macos-clipboard-agent" \
            "macOS clipboard agent" \
            "build_macos_agent" || ((failures++))
        ;;

    x11)
        _zes_ensure_release_or_build "x11" \
            "zes-x11-selection-agent" \
            "$PLUGIN_INSTALL_DIR/impl-x11/backends/x11/zes-x11-selection-agent" \
            "X11 selection agent" \
            "build_x11_monitor" || ((failures++))
        ;;

    wayland)
        _zes_ensure_release_or_build "wayland" \
            "zes-wl-selection-agent" \
            "$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent" \
            "Wayland selection agent" \
            "build_wayland_monitor" || ((failures++))

        if [[ -n "${DISPLAY:-}" ]]; then
            _zes_ensure_release_or_build "wayland" \
                "zes-xwayland-agent" \
                "$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland/zes-xwayland-agent" \
                "XWayland selection agent" \
                "build_xwayland_monitor" || ((failures++))
        fi
        ;;

    wsl)
        _zes_ensure_release_or_build "wsl" \
            "zes-wsl-selection-agent" \
            "$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-selection-agent" \
            "WSL selection agent" \
            "build_wsl_agents" || ((failures++))

        _zes_ensure_release_or_build "wsl" \
            "zes-wsl-clipboard-helper.exe" \
            "$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-clipboard-helper.exe" \
            "WSL clipboard helper" \
            "build_wsl_agents" \
            "file" || ((failures++))

        if [[ -n "${DISPLAY:-}" ]]; then
            _zes_ensure_release_or_build "wsl" \
                "zes-wsl-xwayland-agent" \
                "$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland/zes-xwayland-agent" \
                "WSL XWayland selection agent" \
                "build_wsl_xwayland_monitor" || ((failures++))
        fi

        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            _zes_ensure_release_or_build "wayland" \
                "zes-wl-selection-agent" \
                "$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent" \
                "Wayland selection agent" \
                "build_wayland_monitor" || ((failures++))
        fi
        ;;
    esac

    [[ $failures -eq 0 ]]
}

_zes_run_optional_source_build() {
    local runtime_impl="$1"
    local component_label="$2"
    local build_fn="$3"

    if [[ -z "$build_fn" ]] || ! declare -F "$build_fn" >/dev/null; then
        print_warning "Optional component builder is unavailable: ${component_label} ($build_fn)"
        return 0
    fi

    if "$build_fn"; then
        return 0
    fi

    print_warning "Optional source build failed for ${component_label}; continuing with required runtime agents for ${runtime_impl}."
    return 0
}

_zes_build_source_agents_for_impl() {
    local runtime_impl="$1"
    local build_status=0

    case "$runtime_impl" in
    macos)
        build_macos_agent || build_status=1
        ;;
    x11)
        build_x11_monitor || build_status=1
        ;;
    wayland)
        build_wayland_monitor || build_status=1
        if [[ -n "${DISPLAY:-}" ]]; then
            # XWayland build is a best-effort optional companion on Wayland.
            _zes_run_optional_source_build "$runtime_impl" "XWayland companion" "build_xwayland_monitor"
        fi
        ;;
    wsl)
        build_wsl_agents || build_status=1
        if [[ -n "${DISPLAY:-}" ]]; then
            # Optional on WSL: runtime can fall back to the main WSL agent.
            _zes_run_optional_source_build "$runtime_impl" "WSL XWayland companion" "build_wsl_xwayland_monitor"
        fi
        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            # Optional on WSL: runtime can fall back to the main WSL agent.
            _zes_run_optional_source_build "$runtime_impl" "Wayland companion" "build_wayland_monitor"
        fi
        ;;
    *)
        print_error "Unsupported runtime implementation for source build: $runtime_impl" "agent_source_build"
        return 1
        ;;
    esac

    return $build_status
}

_zes_start_agent_daemon_binary() {
    local monitor_bin="$1"
    local cache_dir="$2"
    shift 2
    local -a monitor_args=("$@")

    local pid_file="$cache_dir/agent.pid"
    local seq_file="$cache_dir/seq"
    local primary_file="$cache_dir/primary"

    mkdir -p "$cache_dir" 2>/dev/null || return 1

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            print_success "Agent daemon already running (PID $pid)" "agent_runtime"
            return 0
        fi
        rm -f "$pid_file" 2>/dev/null
    fi

    rm -f "$seq_file" "$primary_file" 2>/dev/null

    nohup "$monitor_bin" "$cache_dir" "${monitor_args[@]}" >/dev/null 2>&1 &

    local wait_count=0
    while [[ ! -f "$seq_file" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((wait_count++))
    done

    if [[ -f "$seq_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            print_success "Agent daemon started (PID $pid)" "agent_runtime"
        else
            print_success "Agent daemon started" "agent_runtime"
        fi
        return 0
    fi

    print_warning "Agent daemon did not signal readiness" "agent_runtime"
    return 1
}

_zes_start_runtime_agent() {
    local runtime_impl="$1"
    local cache_dir
    cache_dir="$(_zes_agent_cache_dir "$runtime_impl")"

    local monitor_bin=""
    local -a monitor_args=()

    case "$runtime_impl" in
    x11)
        monitor_bin="$PLUGIN_INSTALL_DIR/impl-x11/backends/x11/zes-x11-selection-agent"
        ;;

    wayland)
        local wayland_bin="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent"
        local xwayland_bin="$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland/zes-xwayland-agent"
        local desktop="${XDG_CURRENT_DESKTOP:-}"
        local prefers_xwayland=0

        case "$desktop" in
        *GNOME* | *gnome* | *Cinnamon* | *cinnamon* | *Pantheon* | *pantheon*)
            prefers_xwayland=1
            ;;
        esac

        if [[ $prefers_xwayland -eq 1 ]] && [[ -n "${DISPLAY:-}" ]] && [[ -s "$xwayland_bin" ]]; then
            monitor_bin="$xwayland_bin"
        elif [[ -s "$wayland_bin" ]]; then
            monitor_bin="$wayland_bin"
        elif [[ -s "$xwayland_bin" ]]; then
            monitor_bin="$xwayland_bin"
        fi
        ;;

    macos)
        monitor_bin="$PLUGIN_INSTALL_DIR/impl-macos/backends/macos/zes-macos-clipboard-agent"
        ;;

    wsl)
        local wsl_main="$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl/zes-wsl-selection-agent"
        local wsl_xwayland="$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland/zes-xwayland-agent"
        local wayland_bin="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent"

        # Align with the active WSL tailored runtime path:
        #   1) WSLg XWayland monitor when DISPLAY is present
        #   2) Wayland monitor when WAYLAND_DISPLAY is present
        #   3) Legacy WSL monitor as a compatibility fallback
        if [[ -n "${DISPLAY:-}" ]] && [[ -s "$wsl_xwayland" ]]; then
            monitor_bin="$wsl_xwayland"
            monitor_args+=("--monitor-clipboard")
        elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -s "$wayland_bin" ]]; then
            monitor_bin="$wayland_bin"
        elif [[ -s "$wsl_main" ]]; then
            monitor_bin="$wsl_main"
        fi
        ;;
    esac

    if [[ -z "$monitor_bin" ]] || [[ ! -s "$monitor_bin" ]]; then
        print_warning "No runnable monitor binary found for runtime implementation: $runtime_impl" "agent_runtime"
        return 1
    fi

    chmod +x "$monitor_bin" 2>/dev/null || true
    _zes_start_agent_daemon_binary "$monitor_bin" "$cache_dir" "${monitor_args[@]}"
}

_zes_warmup_plugin_load() {
    local runtime_impl="$1"
    local plugin_loader="$PLUGIN_INSTALL_DIR/zsh-edit-select.plugin.zsh"

    if [[ ! -r "$plugin_loader" ]]; then
        print_warning "Plugin loader not found for warm-up: $plugin_loader" "plugin_warmup"
        return 1
    fi

    if ! command_exists zsh; then
        print_warning "zsh is unavailable; skipping plugin warm-up" "plugin_warmup"
        return 1
    fi

    print_step "Running first-time plugin initialization (.zwc + runtime warm-up)..."

    if command_exists timeout; then
        if timeout 20 env ZES_FORCE_IMPL="$runtime_impl" ZES_PLUGIN_LOADER="$plugin_loader" \
            zsh -f -c 'source "$ZES_PLUGIN_LOADER" >/dev/null 2>&1' >/dev/null 2>&1; then
            print_success "Plugin warm-up completed" "plugin_warmup"
            return 0
        fi
    else
        if env ZES_FORCE_IMPL="$runtime_impl" ZES_PLUGIN_LOADER="$plugin_loader" \
            zsh -f -c 'source "$ZES_PLUGIN_LOADER" >/dev/null 2>&1' >/dev/null 2>&1; then
            print_success "Plugin warm-up completed" "plugin_warmup"
            return 0
        fi
    fi

    print_warning "Plugin warm-up returned a non-zero status" "plugin_warmup"
    MANUAL_STEPS+=("Run once in zsh to finish initialization: source \"$plugin_loader\"")
    return 1
}

build_wsl_agents() {
    print_step "Building WSL agents from source (fallback)..."

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wsl/backends/wsl"
    if [[ ! -d "$build_dir" ]]; then
        print_warning "WSL backend source not found: $build_dir" "wsl_build"
        return 1
    fi
    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "wsl_build"
        return 1
    fi

    local missing_tools=()
    if ! command_exists gcc && ! command_exists clang; then
        missing_tools+=("gcc or clang")
    fi
    if ! command_exists make; then
        missing_tools+=("make")
    fi
    if ! command_exists x86_64-w64-mingw32-gcc && ! command_exists mingw-w64-gcc; then
        missing_tools+=("x86_64-w64-mingw32-gcc (MinGW)")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing fallback build requirements for WSL agents: ${missing_tools[*]}" "wsl_build"
        if [[ "${DETECTED_PACKAGE_MANAGER:-}" == "apt" ]]; then
            print_info "Install WSL build deps: sudo apt-get install build-essential gcc-mingw-w64-x86-64 libx11-dev libxfixes-dev pkg-config"
        else
            print_info "WSL source build also requires a MinGW x86_64 cross-compiler (x86_64-w64-mingw32-gcc)."
        fi
        return 1
    fi

    local build_output
    if build_output=$(cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1); then
        if [[ -s "$build_dir/zes-wsl-selection-agent" ]] && [[ -s "$build_dir/zes-wsl-clipboard-helper.exe" ]]; then
            chmod +x "$build_dir/zes-wsl-selection-agent" 2>/dev/null || true
            print_success "WSL agents built successfully" "wsl_build"
            return 0
        fi

        print_warning "WSL build completed but one or more binaries are missing" "wsl_build"
        return 1
    fi

    print_warning "Failed to build WSL agents from source" "wsl_build"
    echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
}

build_wsl_xwayland_monitor() {
    print_step "Building WSL XWayland agent from source (fallback)..."

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/xwayland"
    if [[ ! -d "$build_dir" ]]; then
        print_warning "WSL XWayland source not found: $build_dir" "wsl_xwayland_build"
        return 1
    fi
    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "wsl_xwayland_build"
        return 1
    fi

    local missing_tools=()
    if ! command_exists gcc && ! command_exists clang; then
        missing_tools+=("gcc or clang")
    fi
    if ! command_exists make; then
        missing_tools+=("make")
    fi
    if ! command_exists pkg-config; then
        missing_tools+=("pkg-config")
    fi
    if ! pkg-config --exists x11 2>/dev/null; then
        missing_tools+=("libx11-dev")
    fi
    if ! pkg-config --exists xfixes 2>/dev/null; then
        missing_tools+=("libxfixes-dev")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing fallback build requirements for WSL XWayland agent: ${missing_tools[*]}" "wsl_xwayland_build"
        if [[ "${DETECTED_PACKAGE_MANAGER:-}" == "apt" ]]; then
            print_info "Install WSL build deps: sudo apt-get install build-essential gcc-mingw-w64-x86-64 libx11-dev libxfixes-dev pkg-config"
        fi
        return 1
    fi

    local build_output
    if build_output=$(cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1); then
        if [[ -s "$build_dir/zes-xwayland-agent" ]]; then
            chmod +x "$build_dir/zes-xwayland-agent" 2>/dev/null || true
            print_success "WSL XWayland agent built successfully" "wsl_xwayland_build"
            return 0
        fi

        print_warning "WSL XWayland build completed but binary is missing" "wsl_xwayland_build"
        return 1
    fi

    print_warning "Failed to build WSL XWayland agent from source" "wsl_xwayland_build"
    echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
    return 1
}

build_macos_agent() {
    print_step "Building macOS clipboard agent..."

    local build_dir="$PLUGIN_INSTALL_DIR/impl-macos/backends/macos"
    if [[ ! -d "$build_dir" ]]; then
        print_warning "macOS agent source not found: $build_dir" "macos_build"
        print_info "Install-time download/build fallback could not find local source files."
        return 1
    fi
    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "macos_build"
        return 1
    fi

    local missing_tools=()
    if ! command_exists clang && ! command_exists gcc; then
        missing_tools+=("clang (from Xcode Command Line Tools)")
    fi
    if ! command_exists make; then
        missing_tools+=("make (from Xcode Command Line Tools)")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing build tools: ${missing_tools[*]}" "macos_build"
        print_info "Run: xcode-select --install"
        MANUAL_STEPS+=("Install Xcode CLT then rebuild: cd $build_dir && make")
        return 1
    fi

    local build_output
    if build_output=$(cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1); then
        local agent_bin="$build_dir/zes-macos-clipboard-agent"
        if [[ -x "$agent_bin" ]]; then
            print_success "macOS clipboard agent built successfully" "macos_build"
            return 0
        else
            print_warning "Build reported success but binary not found" "macos_build"
            MANUAL_STEPS+=("Verify macOS agent binary in $build_dir")
            return 1
        fi
    else
        print_error "Failed to build macOS clipboard agent" "macos_build"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build macOS agent: cd $build_dir && make")
        return 1
    fi
}

build_x11_monitor() {
    print_step "Building X11 selection agent..."

    # Check for required build tools and headers
    local missing_tools=()
    if ! command_exists gcc && ! command_exists clang; then
        missing_tools+=("gcc or clang")
    fi
    if ! command_exists make; then
        missing_tools+=("make")
    fi
    if ! command_exists pkg-config; then
        missing_tools+=("pkg-config")
    fi

    # Check for X11 development headers
    if ! pkg-config --exists x11 2>/dev/null; then
        missing_tools+=("libx11-dev")
    fi
    if ! pkg-config --exists xfixes 2>/dev/null; then
        missing_tools+=("libxfixes-dev")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing build requirements: ${missing_tools[*]}" "x11_monitor_build"
        MANUAL_STEPS+=("Install build dependencies and build X11 monitor: ${missing_tools[*]}")
        return 1
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-x11/backends/x11"

    if [[ ! -d "$build_dir" ]]; then
        print_error "X11 backend source directory not found: $build_dir" "x11_monitor_build"
        print_info "Expected location per README: impl-x11/backends/x11"
        return 1
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "x11_monitor_build"
        MANUAL_STEPS+=("Build X11 agent manually")
        return 1
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-x11-selection-agent" ]]; then
            print_success "X11 clipboard agent built successfully" "x11_monitor_build"
            return 0
        else
            print_warning "Build reported success but binary not found" "x11_monitor_build"
            MANUAL_STEPS+=("Verify X11 agent binary in $build_dir")
            return 1
        fi
    else
        print_error "Failed to build X11 clipboard agent" "x11_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build X11 agent: cd $build_dir && make")
        return 1
    fi
}

build_wayland_monitor() {
    print_step "Building Wayland selection agent..."

    # Check for required build tools and headers
    local missing_tools=()
    if ! command_exists gcc && ! command_exists clang; then
        missing_tools+=("gcc or clang")
    fi
    if ! command_exists make; then
        missing_tools+=("make")
    fi
    if ! command_exists pkg-config; then
        missing_tools+=("pkg-config")
    fi

    # Check for Wayland development headers
    if ! pkg-config --exists wayland-client 2>/dev/null; then
        missing_tools+=("libwayland-dev")
    fi
    if ! pkg-config --exists wayland-protocols 2>/dev/null; then
        missing_tools+=("wayland-protocols")
    fi

    # Check for wayland-scanner (required for protocol generation)
    if ! command_exists "wayland-scanner"; then
        missing_tools+=("wayland-scanner")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing build requirements: ${missing_tools[*]}" "wayland_monitor_build"
        MANUAL_STEPS+=("Install build dependencies and build Wayland monitor: ${missing_tools[*]}")
        return 1
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland"

    if [[ ! -d "$build_dir" ]]; then
        print_error "Wayland backend source directory not found: $build_dir" "wayland_monitor_build"
        print_info "Expected location per README: impl-wayland/backends/wayland"
        return 1
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "wayland_monitor_build"
        MANUAL_STEPS+=("Build Wayland agent manually")
        return 1
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-wl-selection-agent" ]]; then
            print_success "Wayland clipboard agent built successfully" "wayland_monitor_build"
            return 0
        else
            print_warning "Build reported success but binary not found" "wayland_monitor_build"
            MANUAL_STEPS+=("Verify Wayland agent binary in $build_dir")
            return 1
        fi
    else
        print_error "Failed to build Wayland clipboard agent" "wayland_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build Wayland agent: cd $build_dir && make")
        return 1
    fi
}

build_xwayland_monitor() {
    print_step "Building XWayland agent (optional)..."

    # Check for required build tools and X11 headers (same as X11 monitor)
    local missing_tools=()
    if ! command_exists gcc && ! command_exists clang; then
        missing_tools+=("gcc or clang")
    fi
    if ! command_exists make; then
        missing_tools+=("make")
    fi
    if ! command_exists pkg-config; then
        missing_tools+=("pkg-config")
    fi

    # XWayland monitor requires X11 libraries (same as X11 monitor)
    if ! pkg-config --exists x11 2>/dev/null; then
        missing_tools+=("libx11-dev")
    fi
    if ! pkg-config --exists xfixes 2>/dev/null; then
        missing_tools+=("libxfixes-dev")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_warning "Missing build requirements for XWayland monitor (optional): ${missing_tools[*]}" "xwayland_monitor_build"
        MANUAL_STEPS+=("Install build dependencies for XWayland monitor: ${missing_tools[*]}")
        return 1
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland"

    if [[ ! -d "$build_dir" ]]; then
        print_info "XWayland backend source directory not found (optional component)"
        print_info "Expected location per README: impl-wayland/backends/xwayland"
        return 1
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "xwayland_monitor_build"
        MANUAL_STEPS+=("Build XWayland agent manually")
        return 1
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-xwayland-agent" ]]; then
            print_success "XWayland clipboard agent built successfully" "xwayland_monitor_build"
            return 0
        else
            print_warning "Build reported success but binary not found" "xwayland_monitor_build"
            MANUAL_STEPS+=("Verify XWayland agent binary in $build_dir")
            return 1
        fi
    else
        print_error "Failed to build XWayland clipboard agent" "xwayland_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build XWayland agent: cd $build_dir && make")
        return 1
    fi
}
