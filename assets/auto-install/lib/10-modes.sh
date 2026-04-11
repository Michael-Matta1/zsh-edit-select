#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: installation modes and main entry point
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_MODES_LOADED:-}" ]] && return 0
readonly _ZES_MOD_MODES_LOADED=1

_zes_warn_if_zsh_missing_for_mode() {
    if ! command_exists zsh; then
        print_warning "zsh is not installed. This mode can still run, but zsh-specific checks may be limited."
    fi
}

_zes_get_log_file_size_bytes() {
    if [[ "$LOG_FILE" == "/dev/null" ]] || [[ -z "${LOG_FILE:-}" ]] || [[ ! -f "$LOG_FILE" ]]; then
        echo "0"
        return 0
    fi

    local size_bytes
    size_bytes=$(wc -c <"$LOG_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
        echo "$size_bytes"
    else
        echo "0"
    fi
}

_zes_prompt_delete_mode_logs() {
    local mode_label="$1"
    local size_before="${2:-0}"

    if [[ "$LOG_FILE" == "/dev/null" ]]; then
        return 0
    fi

    if [[ ! "$size_before" =~ ^[0-9]+$ ]]; then
        size_before=0
    fi

    local size_after
    size_after="$(_zes_get_log_file_size_bytes)"
    if [[ ! "$size_after" =~ ^[0-9]+$ ]] || ((size_after <= size_before)); then
        return 0
    fi

    local added_bytes=$((size_after - size_before))
    local question
    question="Delete logs created during ${mode_label}? (${added_bytes} bytes at $LOG_FILE)"
    if ask_yes_no "$question" "n"; then
        if rm -f "$LOG_FILE" 2>/dev/null; then
            # Avoid trap-time logging from re-creating the file.
            ZES_DELETE_LOG_ON_EXIT=1
            print_success "Deleted log file: $LOG_FILE"
        else
            print_warning "Could not delete log file: $LOG_FILE"
        fi
    fi
}

_zes_normalize_mode() {
    local raw_mode="${1:-}"
    local mode_lc="${raw_mode,,}"

    case "$mode_lc" in
    full | install)
        echo "full"
        ;;
    integrate | terminals | terminal | terminal-config)
        echo "integrate"
        ;;
    conflicts | conflict | conflict-check)
        echo "conflicts"
        ;;
    update)
        echo "update"
        ;;
    build-agents | agents | build)
        echo "build-agents"
        ;;
    uninstall | remove)
        echo "uninstall"
        ;;
    *)
        return 1
        ;;
    esac
}

_zes_run_selected_mode() {
    local selected_mode="${1:-}"
    case "$selected_mode" in
    full)
        run_full_install
        ;;
    integrate)
        run_terminal_config_only
        ;;
    conflicts)
        run_conflict_check_only
        ;;
    update)
        run_plugin_update
        ;;
    build-agents)
        run_build_agents_only
        ;;
    uninstall)
        run_uninstall
        ;;
    *)
        return 1
        ;;
    esac
}

_zes_print_mode_completion() {
    local mode_label="$1"
    local mode_status="${2:-success}"

    # Keep completion status consistent with collected mode outcomes.
    if [[ "$mode_status" == "success" ]]; then
        if [[ ${#FAILED_STEPS[@]} -gt 0 ]] || [[ ${#MANUAL_STEPS[@]} -gt 0 ]] || [[ $TOTAL_CONFLICTS -gt 0 ]]; then
            mode_status="warning"
        fi
    fi

    echo ""
    case "$mode_status" in
    success)
        print_success "${mode_label} completed."
        ;;
    warning)
        print_warning "${mode_label} completed with warnings."
        ;;
    error)
        print_error "${mode_label} failed."
        ;;
    *)
        print_success "${mode_label} completed."
        ;;
    esac

    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        print_warning "Some steps failed in this mode:"
        local failed_step
        for failed_step in "${!FAILED_STEPS[@]}"; do
            echo "  - $failed_step: ${FAILED_STEPS[$failed_step]}"
        done
    fi

    if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
        print_warning "Detected $TOTAL_CONFLICTS configuration conflict(s). Review the conflict report above."
    fi

    if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
        print_warning "Manual steps were recorded during this mode:"
        local idx=1
        local step
        for step in "${MANUAL_STEPS[@]}"; do
            echo "  $idx. $step"
            ((idx++))
        done
    fi

    print_info "Log file: $LOG_FILE"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --skip-deps)
            SKIP_DEPS=1
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=1
            shift
            ;;
        --skip-conflicts)
            SKIP_CONFLICTS=1
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --test-mode)
            TEST_MODE=1
            shift
            ;;
        --mode)
            if [[ $# -lt 2 ]] || [[ -z "$2" ]]; then
                print_error "--mode requires a value"
                echo "Valid values: full, integrate, conflicts, update, build-agents (or build), uninstall"
                exit 1
            fi
            RUN_MODE="$2"
            shift 2
            ;;
        --mode=*)
            RUN_MODE="${1#--mode=}"
            if [[ -z "$RUN_MODE" ]]; then
                print_error "--mode requires a value"
                echo "Valid values: full, integrate, conflicts, update, build-agents (or build), uninstall"
                exit 1
            fi
            shift
            ;;
        --help | -h)
            cat <<EOF
Zsh Edit-Select — Automated Installation Script v$SCRIPT_VERSION

Usage: bash install.sh [OPTIONS]

Options:
  --skip-deps         Skip dependency installation
  --skip-verify       Skip post-installation verification
  --skip-conflicts    Skip conflict detection
  --non-interactive   Run without user prompts (use defaults)
  --test-mode         Allow running as root (for testing only)
  --mode <name>       Run a specific mode directly
  --help, -h          Show this help message

Examples:
  bash install.sh
      Run standard interactive installation

  bash install.sh --non-interactive
      Run completely automated installation using defaults

  bash install.sh --skip-deps --skip-verify
      Install plugin only, skipping system dependencies and verification

  bash install.sh --skip-conflicts
      Install but do not check for keybinding conflicts

  bash install.sh --mode integrate
      Run terminal configuration mode directly

  bash install.sh --mode build
      Build agents from source using Makefiles, then restart and warm up runtime

Mode values for --mode:
  full, integrate, conflicts, update, build-agents, build, uninstall

This script will:
    - Detect your system environment automatically
    - Install required dependencies
    - Install and configure the plugin
    - Configure your terminal emulator(s)
    - Install and initialize agent binaries
    - Check for configuration conflicts
    - Verify the installation
    - Provide a detailed summary
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        esac
    done
}

run_full_install() {
    print_banner
    echo -e "${CYAN}Starting automated installation...${NC}\n"

    # Phase 0: Sudo Check & Init
    check_sudo
    check_zsh_installed
    check_essential_commands
    check_disk_space || print_warning "Low disk space detected, proceeding anyway..."
    acquire_lock
    echo ""

    # Phase 1: System Detection
    print_header "Phase 1: System Detection"
    detect_os
    detect_display_server
    detect_linux_distro
    detect_plugin_manager "bootstrap"
    detect_terminals

    # Phase 2: Dependencies
    print_header "Phase 2: Dependency Installation"
    install_dependencies

    # Phase 2.1: Offer Kitty installation (after deps, before terminal config)
    offer_kitty_installation

    # Phase 2.5: User Preferences
    ask_user_preferences "full-install"
    ask_backup_preference

    # Phase 3: Plugin Installation
    print_header "Phase 3: Plugin Installation"
    install_plugin

    # Phase 4: Agents
    # Install binaries now, optionally compile, then initialize runtime.
    print_header "Phase 4: Agents"
    build_monitor_daemons

    # Phase 5: Terminal Configuration
    print_header "Phase 5: Terminal Configuration"
    configure_terminals

    # Phase 6: Conflict Detection
    print_header "Phase 6: Configuration Conflict Detection"
    check_conflicts "post-config"

    # Phase 7: Verification
    print_header "Phase 7: Installation Verification"
    verify_installation

    # Phase 8: Optional Extras
    ask_kitty_configuration

    # Phase 9: Summary
    generate_summary
}

run_terminal_config_only() {
    print_header "Terminal Configuration Mode"

    # Init checks
    check_sudo
    _zes_warn_if_zsh_missing_for_mode
    check_essential_commands
    acquire_lock

    # Detection
    print_header "Phase 1: System Detection"
    detect_os
    detect_display_server
    detect_linux_distro
    detect_terminals

    # If no terminals detected, inform user
    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_warning "No terminal emulators detected"
        print_info "Please ensure you have a supported terminal installed"
        _zes_print_mode_completion "Terminal configuration mode"
        return
    fi

    # User preferences
    print_header "Phase 2: Configuration Preferences"
    ask_user_preferences "terminal-config"
    ask_backup_preference

    # Terminal configuration
    print_header "Phase 3: Terminal Configuration"
    configure_terminals

    # Conflict detection - helpful to see if configuration was successful
    print_header "Phase 4: Configuration Conflict Detection"
    check_conflicts "post-config"

    _zes_print_mode_completion "Terminal configuration mode"
}

run_conflict_check_only() {
    print_header "Conflict Detection Mode"

    # Init checks
    _zes_warn_if_zsh_missing_for_mode
    check_essential_commands

    # Detection
    print_header "Phase 1: System Detection"
    detect_os
    detect_display_server
    detect_linux_distro
    detect_terminals

    # Conflict checking
    print_header "Phase 2: Configuration Conflict Detection"
    check_conflicts "scan-only"

    _zes_print_mode_completion "Conflict detection mode"
}

run_build_agents_only() {
    print_header "Build Agents Mode"

    # Init
    check_sudo
    check_essential_commands
    acquire_lock

    local mode_log_size_before=0
    mode_log_size_before="$(_zes_get_log_file_size_bytes)"

    # Detection
    print_header "Phase 1: System Detection"
    detect_os
    detect_display_server
    detect_linux_distro
    detect_plugin_manager "passive"

    local runtime_impl
    runtime_impl="$(_zes_detect_runtime_impl)"

    if [[ -z "$PLUGIN_INSTALL_DIR" ]] || [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory not found: ${PLUGIN_INSTALL_DIR:-<not set>}"
        print_info "Please run Full Install first to install the plugin."
        print_info "Log file: $LOG_FILE"
        _zes_prompt_delete_mode_logs "build mode" "$mode_log_size_before"
        return
    fi

    # Rebuild agents from source and refresh runtime so old binaries/processes are replaced safely.
    local mode_status="success"
    print_header "Phase 2: Source Build and Runtime Refresh"
    if ! refresh_agents_runtime_from_source "$runtime_impl"; then
        mode_status="warning"
    fi

    _zes_print_mode_completion "Build agents mode" "$mode_status"
    _zes_prompt_delete_mode_logs "build mode" "$mode_log_size_before"
}

show_main_menu() {
    print_banner
    echo -e "${CYAN}Welcome to Zsh Edit-Select Installer${NC}"
    echo ""

    ask_choice "What would you like to do?" \
        "Full Installation (Recommended - Complete setup with all features)" \
        "Configure Terminals Only (Configure terminal keybindings for existing plugin)" \
        "Check for Conflicts Only (Scan your setup for configuration conflicts)" \
        "Update Plugin (Pull latest changes from repository)" \
        "Build Agents Only (Build from source via Makefiles, then restart agents)" \
        "Uninstall (Remove plugin, config entries, and agents)"

    case "$CHOICE_RESULT" in
    1) run_full_install ;;
    2) run_terminal_config_only ;;
    3) run_conflict_check_only ;;
    4) run_plugin_update ;;
    5) run_build_agents_only ;;
    6) run_uninstall ;;
    *)
        print_info "Installation cancelled by user"
        exit 0
        ;;
    esac
}

main() {
    parse_arguments "$@"

    # Safety check: Don't run as root
    if [[ $TEST_MODE -eq 0 ]] && ([[ $EUID -eq 0 ]] || [[ "$(id -u)" -eq 0 ]]); then
        echo -e "${RED}${BOLD}ERROR: This script should NOT be run as root!${NC}"
        echo ""
        echo "Running package installations with sudo is safe, but running"
        echo "the entire script as root can cause permission issues and"
        echo "install files to root's home directory instead of yours."
        echo ""
        echo "Please run as a normal user:"
        echo -e "  ${BOLD}bash install.sh${NC}"
        echo ""
        echo "The script will ask for sudo password when needed for system tasks."
        exit 1
    fi

    # Direct mode invocation (used by plugin command wrappers)
    if [[ -n "$RUN_MODE" ]]; then
        local normalized_mode
        if ! normalized_mode="$(_zes_normalize_mode "$RUN_MODE")"; then
            print_error "Unknown mode: $RUN_MODE"
            echo "Valid values: full, integrate, conflicts, update, build-agents (or build), uninstall"
            exit 1
        fi
        _zes_run_selected_mode "$normalized_mode" || {
            print_error "Failed to run mode: $normalized_mode"
            exit 1
        }
        return
    fi

    # If non-interactive, default to full install
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        run_full_install
    else
        show_main_menu
    fi
}
