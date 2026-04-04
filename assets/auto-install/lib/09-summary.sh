#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Summary reporting
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_SUMMARY_LOADED:-}" ]] && return 0
readonly _ZES_MOD_SUMMARY_LOADED=1

generate_summary() {
    local script_end_time
    script_end_time=$(date +%s)
    local duration=$((script_end_time - SCRIPT_START_TIME))

    print_header "Installation Summary"

    echo -e "${BOLD}${CYAN}System Information:${NC}"
    if [[ -n "$DETECTED_DISTRO_NAME" ]]; then
        local distro_info="$DETECTED_DISTRO_NAME ${DETECTED_DISTRO_VERSION:-} (ID: ${DETECTED_DISTRO_ID:-N/A})"
        [[ -n "$DETECTED_DISTRO_CODENAME" ]] && distro_info+=", $DETECTED_DISTRO_CODENAME"
        echo "  • Distribution:    $distro_info"
    fi
    [[ -n "$DETECTED_PACKAGE_MANAGER" ]] && echo "  • Package Manager: $DETECTED_PACKAGE_MANAGER"
    [[ -n "$DETECTED_DISPLAY_SERVER" ]] && echo "  • Display Server:  $DETECTED_DISPLAY_SERVER"
    [[ -n "$DETECTED_PLUGIN_MANAGER" ]] && echo "  • Plugin Manager:  $DETECTED_PLUGIN_MANAGER"
    [[ -n "$PLUGIN_INSTALL_DIR" ]] && echo "  • Plugin Location: $PLUGIN_INSTALL_DIR"
    echo "  • Terminals Found: ${#DETECTED_TERMINALS[@]}"
    for term in "${DETECTED_TERMINALS[@]}"; do
        echo "    - $term"
    done
    echo ""

    echo -e "${BOLD}${GREEN}✓ Completed Successfully:${NC}"
    for step in "${!INSTALLATION_LOG[@]}"; do
        if [[ "${INSTALLATION_LOG[$step]}" == "SUCCESS" ]]; then
            echo "  ✓ $step"
        fi
    done
    echo ""

    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        echo -e "${BOLD}${RED}✗ Failed Steps:${NC}"
        for step in "${!FAILED_STEPS[@]}"; do
            echo "  ✗ $step: ${FAILED_STEPS[$step]}"
        done
        echo ""
    fi

    if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
        echo -e "${BOLD}${YELLOW}⚠ Manual Intervention Required:${NC}"
        for i in "${!MANUAL_STEPS[@]}"; do
            echo "  $((i + 1)). ${MANUAL_STEPS[$i]}"
        done
        echo ""
    fi

    if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
        echo -e "${BOLD}${YELLOW}⚠ Configuration Conflicts Detected:${NC}"
        echo "  • Total conflicts: $TOTAL_CONFLICTS"
        echo "  • Review the conflicts reported above"
        echo "  • Scroll up to Phase 6 to see the full conflict report and exact fixes"
        echo "  • Edit config files to remove or remap old bindings"
        echo "  • Keep zsh-edit-select bindings for best experience"
        echo ""
    fi

    echo -e "${BOLD}${CYAN}Next Steps:${NC}"
    echo -e "  ${BOLD}1. Restart your terminal${NC}"
    echo -e "     Run: ${CYAN}exec zsh${NC} or close and reopen your terminal"
    echo ""
    echo -e "  ${BOLD}2. Test text selection${NC}"
    echo -e "     • Press ${CYAN}Shift + Arrow keys${NC} to select text"
    echo -e "     • Type to replace selected text"
    if [[ "$DETECTED_OS" == "macos" ]]; then
        echo -e "     • Press ${CYAN}Cmd+C${NC} to copy"
    else
        echo -e "     • Press ${CYAN}Ctrl+C${NC} (or ${CYAN}Ctrl+Shift+C${NC}) to copy"
    fi
    echo ""
    echo -e "  ${BOLD}3. Customize settings (optional)${NC}"
    echo -e "     Run: ${CYAN}edit-select config${NC}"
    echo ""
    echo -e "  ${BOLD}4. View full documentation${NC}"
    echo -e "     See: $PLUGIN_INSTALL_DIR/README.md"
    echo -e "     Or visit: https://github.com/Michael-Matta1/zsh-edit-select"
    echo ""

    if [[ "$DETECTED_OS" == "macos" ]]; then
        echo -e "  ${YELLOW}${BOLD}5. [Warning] Enable mouse integration (optional, macOS)${NC}"
        echo -e "     Run: ${CYAN}edit-select setup-ax${NC}"
        echo "     Then allow Accessibility permission in:"
        echo "       System Settings -> Privacy & Security -> Accessibility"
        echo "     Enable the toggle for your terminal app (for example: iTerm2, Terminal, Ghostty, Kitty, WezTerm, Alacritty)."
        echo "     After completing these steps, restart your device to fully enable mouse integration."
        echo ""
    fi

    echo -e "${BOLD}${CYAN}Installation Statistics:${NC}"
    echo "  • Time elapsed:    ${duration}s"
    echo "  • Tests passed:    $PASSED_TESTS"
    echo "  • Tests failed:    $FAILED_TESTS"
    echo "  • Warnings:        $WARNING_TESTS"
    echo ""

    local status_box_width=56
    local status_box_rule
    local status_box_blank
    status_box_rule=$(printf '═%.0s' $(seq 1 "$status_box_width"))
    status_box_blank=$(printf "%${status_box_width}s" "")

    if [[ ${#FAILED_STEPS[@]} -eq 0 ]] && [[ ${#MANUAL_STEPS[@]} -eq 0 ]] && [[ $WARNING_TESTS -eq 0 ]] && [[ $TOTAL_CONFLICTS -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}  ╔${status_box_rule}╗${NC}"
        echo -e "${GREEN}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${GREEN}${BOLD}  ║$(zes_center_text "$status_box_width" "✓ Installation Completed Successfully!")║${NC}"
        echo -e "${GREEN}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${GREEN}${BOLD}  ║$(zes_center_text "$status_box_width" "Enjoy modern text editing in your shell!")║${NC}"
        echo -e "${GREEN}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${GREEN}${BOLD}  ╚${status_box_rule}╝${NC}"
        echo ""

        print_info "IMPORTANT: Please restart your terminal session for changes to take effect."
        print_info "If issues persist, a system reboot may be required."
    elif [[ ${#FAILED_STEPS[@]} -eq 0 ]] && [[ ${#MANUAL_STEPS[@]} -gt 0 ]] && [[ $WARNING_TESTS -eq 0 ]] && [[ $TOTAL_CONFLICTS -eq 0 ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}  ╔${status_box_rule}╗${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║$(zes_center_text "$status_box_width" "[!] Installation Completed with Manual Steps")║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║$(zes_center_text "$status_box_width" "Please review the manual steps above.")║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ╚${status_box_rule}╝${NC}"
        echo ""

        print_info "Please complete the manual steps listed above."
        print_info "After completing them, restart your terminal session to apply changes."
    else
        echo ""
        echo -e "${YELLOW}${BOLD}  ╔${status_box_rule}╗${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║$(zes_center_text "$status_box_width" "[!] Installation Completed with Warnings")║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║$(zes_center_text "$status_box_width" "Please review the manual steps above.")║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${status_box_blank}║${NC}"
        echo -e "${YELLOW}${BOLD}  ╚${status_box_rule}╝${NC}"
        echo ""

        if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
            print_info "Scroll up to Phase 6 to review the conflict report and follow the listed fixes."
        fi
        print_info "Please address the issues listed above."
        print_info "After resolving issues, restart your terminal session to apply changes."
    fi

    # Cleanup prompts
    echo ""
    if [[ -d "$BACKUP_DIR" ]]; then
        if ask_yes_no "Delete backup directory ($BACKUP_DIR)?" "n"; then
            # Validate BACKUP_DIR before deletion to prevent accidents
            # Multiple layers of validation for safety

            # Resolve symlinks to get real path
            local real_backup_dir=""
            if command_exists realpath; then
                real_backup_dir="$(realpath "$BACKUP_DIR" 2>/dev/null || echo "$BACKUP_DIR")"
            else
                # Fallback for systems without realpath
                real_backup_dir="$BACKUP_DIR"
            fi

            # Comprehensive validation checks
            if [[ -n "$real_backup_dir" ]] && [[ "$real_backup_dir" != "/" ]] &&
                [[ "$real_backup_dir" != "$HOME" ]] && [[ "$real_backup_dir" != "$HOME/" ]] &&
                [[ "$real_backup_dir" != "/tmp" ]] && [[ "$real_backup_dir" != "/var" ]] &&
                [[ "$real_backup_dir" != "/home" ]] && [[ "$real_backup_dir" != "/root" ]] &&
                [[ -d "$real_backup_dir" ]] &&
                [[ "$real_backup_dir" == *".zsh-edit-select-backup-"* ]] &&
                # Ensure it's under user's home or /tmp
                [[ "$real_backup_dir" == "$HOME"* || "$real_backup_dir" == "/tmp/"* ]]; then
                rm -rf "$real_backup_dir"
                print_info "Backups deleted"
                log_message "BACKUP_DELETED: $real_backup_dir"
            else
                print_error "Invalid backup directory path, refusing to delete: $BACKUP_DIR"
                print_error "Resolved path: $real_backup_dir"
                log_message "SECURITY: Refused to delete suspicious backup path: $BACKUP_DIR -> $real_backup_dir"
            fi
        else
            print_info "Backups kept at: $BACKUP_DIR"
        fi
    fi

    if ask_yes_no "Delete installation log file ($LOG_FILE)?" "n"; then
        rm -f "$LOG_FILE"
        print_info "Log file deleted"
    else
        print_info "Log file kept at: $LOG_FILE"
    fi
}

# Main Installation Flow
