#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: global variables and constants
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_GLOBALS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_GLOBALS_LOADED=1

# Global Configuration

readonly SCRIPT_VERSION="0.6.49"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# Global state variables
declare -A INSTALLATION_LOG
declare -A FAILED_STEPS
declare -a MANUAL_STEPS
declare -a DETECTED_TERMINALS
declare -a TERMINALS_SELECTED_FOR_CONFIG
declare -A CONFLICTS
declare -i TOTAL_CONFLICTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -i WARNING_TESTS=0
declare -i ZSH_INSTALLED_THIS_SESSION=0

# New/modified globals added by the modular plan
ZES_INSTALL_TMPDIR="${ZES_INSTALL_TMPDIR:-}"       # Exported by install.sh
CREATE_BACKUPS="y"                                 # User preference: whether to create backups
WT_SETTINGS_PATH=""                                # Windows Terminal settings path (detected)
NON_INTERACTIVE="${_ZES_FORCE_NON_INTERACTIVE:-0}" # Dynamic form; uses _ZES_FORCE_NON_INTERACTIVE from loader

# Detection results
DETECTED_OS="" # "linux" | "macos" | "wsl"
DETECTED_DISPLAY_SERVER=""
DETECTED_DISTRO_ID=""
DETECTED_DISTRO_NAME=""
DETECTED_DISTRO_VERSION=""
DETECTED_DISTRO_CODENAME=""
DETECTED_PACKAGE_MANAGER=""
DETECTED_PLUGIN_MANAGER=""
PLUGIN_INSTALL_DIR=""
USER_WANTS_REVERSED_COPY="n" # Default value
CHOICE_RESULT=""             # Global variable for ask_choice results to avoid subshell issues

# Script timing
SCRIPT_START_TIME=$(date +%s)

# Command line flags
SKIP_DEPS=0
SKIP_VERIFY=0
SKIP_CONFLICTS=0
TEST_MODE=0
RUN_MODE=""

# Opt-in install/build flags (set during interactive session)
_ZES_USER_SKIPPED_DEPS=1 # 1 = user declined deps (default), 0 = user accepted deps

# Installation State
KITTY_FRESHLY_INSTALLED=0

# Repository URL
readonly REPO_URL="https://github.com/Michael-Matta1/zsh-edit-select.git"

# Sudo check flag
SUDO_AVAILABLE=0

# Base HOME for paths
if [[ -z "${HOME:-}" ]]; then
    BASE_HOME="/tmp"
    echo "WARNING: HOME is not set, using /tmp as fallback (files may not persist across reboots)" >&2
else
    BASE_HOME="$HOME"
fi

# Log file setup
if [[ -n "${HOME:-}" ]] && [[ -w "${HOME}" ]]; then
    LOG_FILE="${HOME}/.zsh-edit-select-install.log"
elif [[ -w "/tmp" ]]; then
    LOG_FILE="/tmp/zsh-edit-select-install-${USER:-unknown}-$$.log"
else
    LOG_FILE="/dev/null"
    echo "WARNING: Cannot create log file, logging disabled" >&2
fi

# Verify log file is actually writable
if [[ "$LOG_FILE" != "/dev/null" ]] && ! touch "$LOG_FILE" 2>/dev/null; then
    echo "WARNING: Log file not writable, using /dev/null instead" >&2
    LOG_FILE="/dev/null"
fi

# Now make it readonly after validation
readonly LOG_FILE
BACKUP_DIR="${BASE_HOME}/.zsh-edit-select-backup-$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR

# Lock file for preventing concurrent installations
# Note: Not readonly because acquire_lock() may update this path
LOCK_FILE="/tmp/zsh-edit-select-install-${USER:-root}.lock"
