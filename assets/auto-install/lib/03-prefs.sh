#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: User preference questions
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_PREFS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_PREFS_LOADED=1

ask_user_preferences() {
    local prefs_context="${1:-full-install}"
    if [[ "$prefs_context" == "full-install" ]]; then
        print_header "Phase 2.5: User Preferences"
    fi

    if [[ "$DETECTED_OS" == "macos" ]]; then
        USER_WANTS_REVERSED_COPY="n"
        return
    fi

    # Reversed copy shortcuts
    print_step "Copy shortcut preference..."
    echo ""
    echo -e "  ${BOLD}Option 1 (Default):${NC}"
    echo "    Ctrl+Shift+C  →  Copy"
    echo "    Ctrl+C        →  Interrupt (standard)"
    echo ""
    echo -e "  ${BOLD}Option 2 (Reversed):${NC}"
    echo "    Ctrl+C        →  Copy"
    echo "    Ctrl+Shift+C  →  Interrupt"
    echo ""

    if ask_yes_no "Enable reversed copy shortcuts (Ctrl+C to copy)?" "n"; then
        USER_WANTS_REVERSED_COPY="y"
        print_info "Using reversed copy shortcuts"
    else
        USER_WANTS_REVERSED_COPY="n"
        print_info "Using default copy shortcuts"
    fi

}

ask_backup_preference() {
    echo ""
    print_step "Backup Configuration..."
    echo ""
    print_info "The script can backup existing configuration files before modifying them."
    print_info "Backups will be stored in: $BACKUP_DIR"
    echo ""

    if ask_yes_no "Enable backups?" "y"; then
        CREATE_BACKUPS="y"
        print_info "Backups enabled"
    else
        CREATE_BACKUPS="n"
        print_info "Backups disabled"
    fi
}
