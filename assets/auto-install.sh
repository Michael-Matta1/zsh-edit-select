#!/usr/bin/env bash

# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# Ensure bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This script must be run with bash, not sh or zsh."
    echo "Usage: bash auto-install.sh"
    exit 1
fi

# Check bash version
if [[ -z "${BASH_VERSINFO[0]}" ]] || [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: Bash 4.0 or higher is required (found ${BASH_VERSION:-unknown})"
    echo "This script uses associative arrays which require Bash 4.0+"
    echo ""
    echo "Your distribution should have bash 4+ by default."
    echo "Try: sudo apt install bash  (or equivalent for your distro)"
    exit 1
fi

# Zsh Edit-Select — Automated Installation Script

# Complete automated installation with intelligent detection and configuration
#
# Usage:
#   bash auto-install.sh [options]
#
# Options:
#   --help              Show this help message
#   --non-interactive   Run without user prompts (use defaults)
#   --skip-deps         Skip dependency installation
#   --skip-verify       Skip verification steps
#   --skip-conflicts    Skip conflict detection
#   --test-mode         Allow running as root (for testing only)
#
# Examples:
#   bash auto-install.sh
#   bash auto-install.sh --non-interactive
#   bash auto-install.sh --skip-deps --skip-verify
#
# This script will:
# - Auto-detect your environment (display server, distro, plugin manager)
# - Install all required dependencies
# - Install and configure the plugin
# - Configure your terminal emulator(s)
# - Build agents
# - Check for configuration conflicts
# - Verify the installation
# - Provide a detailed summary

# set -euo pipefail (Disabled to prevent crashes on non-critical errors)

# Global Configuration

readonly SCRIPT_VERSION="0.6.1"

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
declare -A CONFLICTS
declare -i TOTAL_CONFLICTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -i WARNING_TESTS=0

# Detection results
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
NON_INTERACTIVE=0
TEST_MODE=0

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
readonly BACKUP_DIR="${BASE_HOME}/.zsh-edit-select-backup-$(date +%Y%m%d_%H%M%S)"

# Lock file for preventing concurrent installations
# Note: Not readonly because acquire_lock() may update this path
LOCK_FILE="/tmp/zsh-edit-select-install-${USER:-root}.lock"

# Cleanup and Error Handling

cleanup() {
    local exit_code=$?
    release_lock # Release lock file
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Installation interrupted or failed!${NC}" | tee -a "$LOG_FILE"
        echo -e "${YELLOW}Log file saved to: $LOG_FILE${NC}"
        if [[ -d "$BACKUP_DIR" ]]; then
            echo -e "${YELLOW}Backups saved to: $BACKUP_DIR${NC}"
        fi
    fi
    # Restore cursor if hidden? (optional)
}

trap cleanup EXIT
trap 'echo -e "\n${RED}Installation interrupted by user${NC}"; exit 130' INT
trap 'echo -e "\n${RED}Installation terminated${NC}"; exit 143' TERM
trap 'echo -e "\n${RED}Hangup detected${NC}"; exit 129' HUP
trap 'echo -e "\n${RED}Quit detected${NC}"; exit 131' QUIT

log_message() {
    local message="$1"
    # Attempt to write to log file, fallback to stderr if it fails
    if ! echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >>"$LOG_FILE" 2>/dev/null; then
        # If log write fails, output to stderr as fallback
        echo "[LOG] $message" >&2
    fi
}

backup_file() {
    local file="$1"
    # Only backup if user enabled it or if it's a critical safety backup
    if [[ "${CREATE_BACKUPS:-y}" == "y" ]] && [[ -f "$file" ]]; then
        if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
            print_warning "Cannot create backup directory: $BACKUP_DIR"
            print_warning "Skipping backup of $(basename "$file")"
            log_message "BACKUP FAILED: Cannot create directory $BACKUP_DIR"
            return 1
        fi
        local backup_path="$BACKUP_DIR/$(basename "$file").backup"
        if cp "$file" "$backup_path" 2>/dev/null; then
            print_info "Backed up $file to $backup_path"
            log_message "BACKUP: $file -> $backup_path"
            return 0
        else
            print_warning "Failed to backup $file"
            log_message "BACKUP FAILED: $file"
            return 1
        fi
    fi
    return 0
}

check_write_permission() {
    local file="$1"
    if [[ -e "$file" && ! -w "$file" ]]; then
        print_error "No write permission for $file"
        return 1
    fi
    # If file doesn't exist, check dir permission
    if [[ ! -e "$file" ]]; then
        local dir
        dir="$(dirname "$file")"
        if [[ -d "$dir" && ! -w "$dir" ]]; then
            print_error "No write permission for directory $dir"
            return 1
        fi
    fi
    return 0
}

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

# Identify and report broken apt repositories
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

acquire_lock() {
    local lock_dir="/tmp/zsh-edit-select-install-${USER:-root}.lock.d"
    local max_attempts=3
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        # Try to create lock directory atomically (mkdir is atomic)
        if mkdir "$lock_dir" 2>/dev/null; then
            # Successfully acquired lock
            echo "$$" >"$lock_dir/pid" 2>/dev/null || true
            log_message "LOCK_ACQUIRED: Created lock with PID $$"
            # Update LOCK_FILE to point to the directory for cleanup
            LOCK_FILE="$lock_dir"
            return 0
        fi

        # Lock exists, check if it's stale
        if [[ -d "$lock_dir" ]]; then
            local pid
            pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "unknown")

            if [[ "$pid" != "unknown" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
                # Check if process exists
                if kill -0 "$pid" 2>/dev/null; then
                    # Process exists, now verify it's actually our installer script
                    local is_our_script=0
                    if [[ -f "/proc/$pid/cmdline" ]]; then
                        # Check if the process command line contains our script name
                        if grep -q "auto-install.sh" "/proc/$pid/cmdline" 2>/dev/null; then
                            is_our_script=1
                        fi
                    else
                        # Fallback: use ps to check command
                        if ps -p "$pid" -o command= 2>/dev/null | grep -q "auto-install.sh"; then
                            is_our_script=1
                        fi
                    fi

                    if [[ $is_our_script -eq 1 ]]; then
                        # Confirmed: another instance of this script is running
                        if [[ $attempt -eq $((max_attempts - 1)) ]]; then
                            echo -e "${RED}ERROR: Another installation is running (PID $pid)${NC}"
                            echo "If this is incorrect, remove the lock directory: $lock_dir"
                            log_message "LOCK_ERROR: Installation already running with PID $pid"
                            exit 1
                        fi
                        # Wait and retry
                        echo -e "${YELLOW}Another installation in progress (PID $pid), waiting...${NC}"
                        sleep 2
                        ((attempt++))
                        continue
                    else
                        # Process exists but isn't our script - stale lock
                        echo -e "${YELLOW}Removing stale lock (PID $pid is not installer)${NC}"
                        rm -rf "$lock_dir" 2>/dev/null || true
                        log_message "LOCK_STALE: Removed stale lock (PID $pid not installer)"
                    fi
                else
                    # Stale lock - process not running
                    echo -e "${YELLOW}WARNING: Removing stale lock (PID $pid not running)${NC}"
                    log_message "LOCK_CLEANUP: Removed stale lock for PID $pid"
                    rm -rf "$lock_dir" 2>/dev/null || true
                fi
            else
                # Invalid PID
                echo -e "${YELLOW}WARNING: Removing invalid lock${NC}"
                log_message "LOCK_CLEANUP: Removed lock with invalid PID: $pid"
                rm -rf "$lock_dir" 2>/dev/null || true
            fi
        fi

        ((attempt++))
    done

    # If we get here, couldn't acquire lock after retries
    echo -e "${YELLOW}WARNING: Could not acquire lock after $max_attempts attempts${NC}"
    log_message "LOCK_WARNING: Failed to acquire lock after $max_attempts attempts"
    # Continue anyway - lock is best-effort
    return 0
}

release_lock() {
    if [[ -d "$LOCK_FILE" ]]; then
        rm -rf "$LOCK_FILE" 2>/dev/null || true
        log_message "LOCK_RELEASED: Removed lock directory"
    elif [[ -f "$LOCK_FILE" ]]; then
        # Fallback for old-style file lock
        rm -f "$LOCK_FILE" 2>/dev/null || true
        log_message "LOCK_RELEASED: Removed lock file"
    fi
}

check_disk_space() {
    local required_mb=100
    local available_mb

    # Get available space in MB for HOME or current directory
    available_mb=$(df -m "${HOME:-.}" 2>/dev/null | tail -1 | awk '{print $4}')

    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        print_warning "Could not check disk space"
        return 0 # Continue anyway
    fi

    if [[ "$available_mb" -lt "$required_mb" ]]; then
        print_error "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
        return 1
    fi

    print_success "Disk space check passed (${available_mb}MB available)"
    return 0
}

print_banner() {
    # clear - avoid clear in non-interactive
    [[ $NON_INTERACTIVE -eq 0 ]] && clear
    # Start new log
    echo "" >>"$LOG_FILE"
    echo "--- Installation Started: $(date) ---" >>"$LOG_FILE"
    log_message "Version: $SCRIPT_VERSION"

    # RGB Color function
    rgb() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }

    local BORDER='\033[38;2;100;150;255m' # Light blue border

    echo -e "${BORDER}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BORDER}║${NC}                                                                           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 255 255)           ███████╗███████╗██╗  ██╗    ███████╗██████╗ ██╗████████╗        ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 230 255)           ╚══███╔╝██╔════╝██║  ██║    ██╔════╝██╔══██╗██║╚══██╔══╝        ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 200 255)             ███╔╝ ███████╗███████║    █████╗  ██║  ██║██║   ██║           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 170 255)            ███╔╝  ╚════██║██╔══██║    ██╔══╝  ██║  ██║██║   ██║           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 140 255)           ███████╗███████║██║  ██║    ███████╗██████╔╝██║   ██║           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 0 110 255)           ╚══════╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚═════╝ ╚═╝   ╚═╝           ${BORDER}║${NC}"
    echo -e "${BORDER}║${NC}                                                                           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 255 100)              ███████╗███████╗██╗     ███████╗ ██████╗████████╗            ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 255 150)              ██╔════╝██╔════╝██║     ██╔════╝██╔════╝╚══██╔══╝            ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 230 200)              ███████╗█████╗  ██║     █████╗  ██║        ██║               ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 200 230)              ╚════██║██╔══╝  ██║     ██╔══╝  ██║        ██║               ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 170 255)              ███████║███████╗███████╗███████╗╚██████╗   ██║               ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 100 140 255)              ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝               ${BORDER}║${NC}"
    echo -e "${BORDER}║${NC}                                                                           ${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 255 200 100)${BOLD}                       Automated Installation Script                       ${NC}${BORDER}║${NC}"
    echo -e "${BORDER}║$(rgb 255 100 200)                              Version $SCRIPT_VERSION                                ${NC}${BORDER}║${NC}"
    echo -e "${BORDER}║${NC}                                                                           ${BORDER}║${NC}"
    echo -e "${BORDER}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    unset -f rgb
}

print_header() {
    local title="$1"
    # Cap at (term_width - 2) to guarantee the separator never reaches the last
    # terminal column, which would trigger auto-wrap and add a spurious blank line
    # that shifts all subsequent output by one line.
    local term_width
    term_width=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
    [[ "$term_width" -lt 20 ]] && term_width=20
    [[ "$term_width" -gt 80 ]] && term_width=80
    term_width=$((term_width - 2))
    local sep
    sep=$(printf '━%.0s' $(seq 1 "$term_width"))
    # printf '\033[0m' resets any stray color/bold state that might have been left
    # by a previous print_conflict call (where echo -e with \x1b data corrupts state)
    printf '\033[0m'
    echo -e "\n${BOLD}${CYAN}${sep}${NC}"
    echo -e "${BOLD}${CYAN}  ${title}${NC}"
    echo -e "${BOLD}${CYAN}${sep}${NC}"
    echo ""
    log_message "HEADER: $title"
}

print_step() {
    echo -e "${BOLD}${BLUE}▶${NC} ${BOLD}$1${NC}"
    log_message "STEP: $1"
}

print_substep() {
    echo -e "  ${DIM}${BLUE}→${NC} $1"
    log_message "  → $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log_message "SUCCESS: $1"
    [[ -n "${2:-}" ]] && INSTALLATION_LOG["$2"]="SUCCESS"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log_message "ERROR: $1"
    [[ -n "${2:-}" ]] && FAILED_STEPS["$2"]="$1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log_message "WARNING: $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log_message "INFO: $1"
}

print_conflict() {
    local file="$1"
    local existing="$2"
    local new="$3"

    # Sanitize strings to remove control characters and escape sequences.
    # IMPORTANT: also strip literal \xNN sequences (e.g. \x1b from kitty config
    # lines like "send_text all \x1b[67;6u"). If these survive into an echo -e
    # call, echo -e interprets \x1b as ESC and injects a CSI sequence (ESC[67;6u)
    # which many terminals decode as "Restore Cursor" (ESC[u), jumping the cursor
    # back to a saved position and causing all subsequent output to overwrite
    # already-rendered lines — producing the visible text corruption.
    existing=$(printf '%s\n' "$existing" | tr -d '\r\n\t' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\\x[0-9a-fA-F][0-9a-fA-F][^[:space:]]*/[esc]/g' | tr -cd '[:print:] ')
    new=$(printf '%s\n' "$new" | tr -d '\r\n\t' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\\x[0-9a-fA-F][0-9a-fA-F][^[:space:]]*/[esc]/g' | tr -cd '[:print:] ')

    # Trim leading/trailing whitespace from sanitized strings
    existing="${existing#"${existing%%[![:space:]]*}"}"
    existing="${existing%"${existing##*[![:space:]]}"}"
    new="${new#"${new%%[![:space:]]*}"}"
    new="${new%"${new##*[![:space:]]}"}"

    # Ensure output starts on a new line and is visually distinct.
    # Use printf '%s\n' (NOT echo -e) for lines that display $existing/$new so
    # that no backslash interpretation happens on the sanitized content.
    printf '\033[0m'
    echo ""
    echo -e "  ${RED}┌─ CONFLICT in ${BOLD}$file${NC}"
    printf '  \033[0;31m│\033[0m  \033[1;33mExisting:\033[0m %s\n' "$existing"
    printf '  \033[0;31m│\033[0m  \033[1;33mIssue:\033[0m    %s\n' "$new"
    echo -e "  ${RED}│${NC}  ${DIM}Action:   Remove or comment out the existing line to avoid conflicts.${NC}"
    echo -e "  ${RED}└──────────────────────────────────────────────────${NC}"

    CONFLICTS["$file"]="${CONFLICTS[$file]:-}${existing}|${new};"
    ((TOTAL_CONFLICTS++))

    log_message "CONFLICT: $file - Existing: $existing | Issue: $new"
}

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED_TESTS++))
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    echo -e "  ${YELLOW}→${NC} $2"
    ((FAILED_TESTS++))
}

test_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
    echo -e "  ${CYAN}→${NC} $2"
    ((WARNING_TESTS++))
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer
    local max_attempts=3
    local attempt=0

    # Check if we're in non-interactive mode or stdin is not a TTY
    if [[ $NON_INTERACTIVE -eq 1 ]] || [[ ! -t 0 ]]; then
        echo -e "${YELLOW}?${NC} $question ${BOLD}[${default}]${NC} (non-interactive mode)"
        log_message "NON_INTERACTIVE_DECISION: $question -> $default"
        [[ "$default" == "y" ]]
        return
    fi

    # Flush stdin before reading to prevent buffering issues
    flush_stdin

    while [[ $attempt -lt $max_attempts ]]; do
        if [[ "$default" == "y" ]]; then
            echo -ne "${YELLOW}?${NC} $question ${BOLD}[Y/n]${NC}: "
        else
            echo -ne "${YELLOW}?${NC} $question ${BOLD}[y/N]${NC}: "
        fi

        # Brief delay to ensure terminal has rendered the prompt
        sleep 0.1

        # Read with timeout to prevent hanging, use /dev/tty if available
        if [[ -r /dev/tty ]]; then
            if ! read -r -t 120 answer </dev/tty 2>/dev/null; then
                echo -e "\n${YELLOW}Input timeout, using default: $default${NC}"
                answer="$default"
                break
            fi
        elif ! read -r -t 120 answer 2>/dev/null; then
            echo -e "\n${YELLOW}Input timeout, using default: $default${NC}"
            answer="$default"
            break
        fi

        # Sanitize input - remove special characters and whitespace
        answer=$(echo "$answer" | tr -d '\n\r\t' | tr -cd 'A-Za-z')
        answer="${answer,,}" # Convert to lowercase

        # Validate input
        if [[ -z "$answer" ]]; then
            answer="$default"
            break
        elif [[ "$answer" =~ ^(y|yes|n|no)$ ]]; then
            break
        else
            ((attempt++))
            if [[ $attempt -lt $max_attempts ]]; then
                echo -e "${RED}Invalid input. Please enter y/yes or n/no.${NC}"
            else
                echo -e "${YELLOW}Too many invalid attempts, using default: $default${NC}"
                answer="$default"
            fi
        fi
    done

    log_message "USER_DECISION: $question -> $answer"
    [[ "$answer" == "y" || "$answer" == "yes" ]]
}

flush_stdin() {
    # Flush any pending input in stdin buffer
    # This prevents issues where previous commands leave data in the buffer
    if [[ -t 0 ]]; then
        # Multiple passes to ensure buffer is completely clear
        local i
        for i in {1..5}; do
            read -r -t 0.01 -n 10000 2>/dev/null && continue || break
        done
    fi
}

ask_choice() {
    local question="$1"
    shift
    local options=("$@")
    local choice
    local max_attempts=3
    local attempt=0

    # Check if we're in non-interactive mode or stdin is not a TTY
    if [[ $NON_INTERACTIVE -eq 1 ]] || [[ ! -t 0 ]]; then
        echo -e "${YELLOW}?${NC} $question ${BOLD}[1]${NC} (non-interactive mode)"
        log_message "NON_INTERACTIVE_CHOICE: $question -> 1"
        CHOICE_RESULT="1"
        return 0
    fi

    # Flush stdin before reading to prevent buffering issues
    flush_stdin

    while [[ $attempt -lt $max_attempts ]]; do
        echo -e "\n${BOLD}${question}${NC}"
        for i in "${!options[@]}"; do
            echo "  $((i + 1))) ${options[$i]}"
        done
        echo -ne "\n${YELLOW}?${NC} Enter choice [1-${#options[@]}]: "

        # Brief delay to ensure terminal has rendered the prompt
        sleep 0.1

        # Read directly from /dev/tty if available, otherwise use stdin
        if [[ -r /dev/tty ]]; then
            if ! read -r -t 120 choice </dev/tty 2>/dev/null; then
                echo -e "\n${YELLOW}Input timeout, using default: 1${NC}"
                CHOICE_RESULT="1"
                return 0
            fi
        elif ! read -r -t 120 choice 2>/dev/null; then
            echo -e "\n${YELLOW}Input timeout, using default: 1${NC}"
            CHOICE_RESULT="1"
            return 0
        fi

        # Validate: must be a number in range
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            log_message "USER_CHOICE: $question -> $choice"
            CHOICE_RESULT="$choice"
            return 0
        fi

        ((attempt++))
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#options[@]}.${NC}"
        else
            echo -e "${YELLOW}Too many invalid attempts, using default: 1${NC}"
            CHOICE_RESULT="1"
            return 0
        fi
    done
}

command_exists() {
    command -v "$1" &>/dev/null
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

# Portable sed in-place replacement using temp file
sed_inplace() {
    local pattern="$1"
    local file="$2"
    local tmp_file

    # Create temp file with error checking
    tmp_file=$(mktemp "${file}.XXXXXX" 2>/dev/null) || {
        print_error "Failed to create temporary file for editing: $file"
        return 1
    }

    # Preserve original file permissions
    local orig_perms
    orig_perms=$(stat -c '%a' "$file" 2>/dev/null)

    if sed "$pattern" "$file" >"$tmp_file" 2>/dev/null; then
        # Ensure mv succeeds before claiming success
        if mv "$tmp_file" "$file" 2>/dev/null; then
            [[ -n "$orig_perms" ]] && chmod "$orig_perms" "$file" 2>/dev/null
            return 0
        else
            print_error "Failed to update file: $file (mv failed)"
            rm -f "$tmp_file"
            return 1
        fi
    else
        print_error "Failed to apply sed pattern to: $file"
        rm -f "$tmp_file"
        return 1
    fi
}

get_full_path() {
    local cmd="$1"
    command -v "$cmd" 2>/dev/null || which "$cmd" 2>/dev/null || echo ""
}

# Strip comments and whitespace (improved to handle tabs and normalize whitespace)
strip_line() {
    local line="$1"
    # Remove control characters (carriage returns, ANSI codes, etc.)
    line=$(echo "$line" | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g')

    # Trim leading/trailing whitespace first
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # If line starts with #, preserve it as a comment line (don't strip it)
    if [[ "$line" == "#"* ]]; then
        echo "$line"
        return
    fi

    # For non-comment lines, remove inline comments
    line="${line%%#*}"
    # Convert tabs to spaces
    line="${line//$'\t'/ }"
    # Remove leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # Remove trailing whitespace
    line="${line%"${line##*[![:space:]]}"}"
    # Normalize multiple spaces to single space using parameter expansion instead of tr
    local prev_line=""
    while [[ "$line" != "$prev_line" ]]; do
        prev_line="$line"
        line="${line//  / }"
    done
    # Normalize spaces around = signs to make "key=value" and "key = value" equivalent
    line="${line// = /=}"
    line="${line// =/=}"
    line="${line//= /=}"
    echo "$line"
}

# Check if a configuration line already exists in a file (ignoring comments/whitespace)
config_line_exists() {
    local file="$1"
    local line="$2"

    [[ ! -f "$file" ]] && return 1

    # Validate file is readable and not too large (prevent hanging on huge files)
    if [[ ! -r "$file" ]]; then
        log_message "CONFIG_CHECK_WARNING: File not readable: $file"
        return 1
    fi

    # Safety check: skip files larger than 10MB to prevent performance issues
    if command_exists stat; then
        local file_size
        file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        if [[ $file_size -gt 10485760 ]]; then # 10MB
            log_message "CONFIG_CHECK_WARNING: File too large, skipping: $file ($file_size bytes)"
            return 1
        fi
    fi

    # Special handling for comment-only lines (lines that start with #)
    # We need to preserve comments for marker lines like "# Zsh Edit-Select"
    local target_trimmed="${line#"${line%%[![:space:]]*}"}"
    target_trimmed="${target_trimmed%"${target_trimmed##*[![:space:]]}"}"

    if [[ "$target_trimmed" == "#"* ]]; then
        # For comment lines, do exact match after trimming whitespace
        while IFS= read -r existing_line || [[ -n "$existing_line" ]]; do
            local existing_trimmed="${existing_line#"${existing_line%%[![:space:]]*}"}"
            existing_trimmed="${existing_trimmed%"${existing_trimmed##*[![:space:]]}"}"

            if [[ "$existing_trimmed" == "$target_trimmed" ]]; then
                return 0
            fi
        done <"$file"
        return 1
    fi

    # For non-comment lines, use the stripping logic
    local stripped_target
    stripped_target="$(strip_line "$line")"
    [[ -z "$stripped_target" ]] && return 1

    while IFS= read -r existing_line || [[ -n "$existing_line" ]]; do
        local stripped_existing
        stripped_existing="$(strip_line "$existing_line")"
        # Skip empty lines in file
        [[ -z "$stripped_existing" ]] && continue

        if [[ "$stripped_existing" == "$stripped_target" ]]; then
            return 0
        fi
    done <"$file"

    return 1
}

find_windows_terminal_settings() {
    # Only applicable on WSL
    if [[ -z "${WSL_DISTRO_NAME:-}" ]] && [[ -z "${WSL_INTEROP:-}" ]]; then
        return 1
    fi

    # Try to get Windows username
    local win_user
    if command_exists cmd.exe; then
        win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    fi

    if [[ -z "$win_user" ]]; then
        return 1
    fi

    local wt_path="/mnt/c/Users/${win_user}/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
    
    if [[ -f "$wt_path" ]]; then
        WT_SETTINGS_PATH="$wt_path"
        echo "$wt_path"
        return 0
    fi

    return 1
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
        print_error "zsh is not installed!"
        echo ""
        echo -e "${RED}This plugin requires zsh to be installed.${NC}"
        echo -e "${YELLOW}Please install zsh first:${NC}"
        echo "  Debian/Ubuntu:  sudo apt-get install zsh"
        echo "  Fedora:         sudo dnf install zsh"
        echo "  Arch:           sudo pacman -S zsh"
        echo "  openSUSE:       sudo zypper install zsh"
        echo "  Alpine:         sudo apk add zsh"
        echo ""
        echo -e "${YELLOW}Recommended: Make zsh your default shell${NC}"
        echo "  chsh -s \$(which zsh)"
        echo "  Then log out and log back in for changes to take effect"
        echo ""
        log_message "FATAL: zsh not installed"
        exit 1
    fi

    local zsh_version
    zsh_version=$(zsh --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    print_success "zsh is installed (version ${zsh_version:-unknown})" "zsh_check"
    log_message "ZSH_VERSION: $zsh_version"
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

# System Detection Functions

detect_display_server() {
    print_step "Detecting display server..."

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

detect_plugin_manager() {
    print_step "Detecting Zsh plugin manager..."

    # Check for Oh My Zsh (directory + env var)
    if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
        # Verify it's actually Oh My Zsh
        if [[ -f "${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh" ]]; then
            DETECTED_PLUGIN_MANAGER="oh-my-zsh"
            PLUGIN_INSTALL_DIR="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-edit-select"
            print_success "Detected: Oh My Zsh" "plugin_manager"
            return
        else
            log_message "DETECTION_WARNING: Directory ${ZSH:-$HOME/.oh-my-zsh} exists but doesn't contain oh-my-zsh.sh"
        fi
    fi

    # Check for Zinit (directory or env var)
    if [[ -d "${ZINIT_HOME:-}" ]] || [[ -d "$HOME/.zinit" ]] || [[ -d "$HOME/.local/share/zinit" ]] ||
        [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit" ]]; then
        DETECTED_PLUGIN_MANAGER="zinit"
        PLUGIN_INSTALL_DIR="${ZINIT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/zinit}/plugins/zsh-edit-select"
        print_success "Detected: Zinit" "plugin_manager"
        return
    fi

    # Check for Zplug
    if [[ -d "${ZPLUG_HOME:-$HOME/.zplug}" ]] || command_exists zplug; then
        DETECTED_PLUGIN_MANAGER="zplug"
        PLUGIN_INSTALL_DIR="${ZPLUG_HOME:-$HOME/.zplug}/repos/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Zplug" "plugin_manager"
        return
    fi

    # Check for Antigen
    if [[ -f "$HOME/.antigen.zsh" ]] || [[ -d "$HOME/.antigen" ]] || command_exists antigen; then
        DETECTED_PLUGIN_MANAGER="antigen"
        PLUGIN_INSTALL_DIR="$HOME/.antigen/bundles/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Antigen" "plugin_manager"
        return
    fi

    # Check for Antibody (deprecated — succeeded by Antidote)
    if command_exists antibody; then
        DETECTED_PLUGIN_MANAGER="antibody"
        PLUGIN_INSTALL_DIR="$HOME/.cache/antibody/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Antibody" "plugin_manager"
        print_warning "Antibody is archived and no longer maintained. Consider migrating to Antidote: https://github.com/mattmc3/antidote"
        return
    fi

    # Check for Zgenom (check before Zgen — Zgenom is the maintained successor)
    if [[ -d "${ZGENOM_DIR:-$HOME/.zgenom}" ]] || command_exists zgenom; then
        DETECTED_PLUGIN_MANAGER="zgenom"
        PLUGIN_INSTALL_DIR="${ZGENOM_DIR:-$HOME/.zgenom}/Michael-Matta1/zsh-edit-select-master"
        print_success "Detected: Zgenom" "plugin_manager"
        return
    fi

    # Check for Zgen (deprecated — succeeded by Zgenom)
    if [[ -d "${ZGEN_DIR:-$HOME/.zgen}" ]] || command_exists zgen; then
        DETECTED_PLUGIN_MANAGER="zgen"
        PLUGIN_INSTALL_DIR="${ZGEN_DIR:-$HOME/.zgen}/Michael-Matta1/zsh-edit-select-master"
        print_success "Detected: Zgen" "plugin_manager"
        print_warning "Zgen is no longer maintained. Consider migrating to Zgenom: https://github.com/jandamm/zgenom"
        return
    fi

    # Check for Sheldon
    if command_exists sheldon || [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml" ]]; then
        DETECTED_PLUGIN_MANAGER="sheldon"
        PLUGIN_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon/repos/github.com/Michael-Matta1/zsh-edit-select"
        print_success "Detected: Sheldon" "plugin_manager"
        return
    fi

    # Check .zshrc for plugin manager signatures
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    if [[ -f "$zshrc" ]]; then
        local zshrc_content
        zshrc_content=$(cat "$zshrc" 2>/dev/null || true)

        if echo "$zshrc_content" | grep -qE "zinit|zi " 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zinit"
            PLUGIN_INSTALL_DIR="${ZINIT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/zinit}/plugins/zsh-edit-select"
            print_success "Detected: Zinit (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "antigen" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="antigen"
            PLUGIN_INSTALL_DIR="$HOME/.antigen/bundles/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Antigen (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zplug" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zplug"
            PLUGIN_INSTALL_DIR="${ZPLUG_HOME:-$HOME/.zplug}/repos/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Zplug (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "antibody" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="antibody"
            PLUGIN_INSTALL_DIR="$HOME/.cache/antibody/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Antibody (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zgenom" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zgenom"
            PLUGIN_INSTALL_DIR="${ZGENOM_DIR:-$HOME/.zgenom}/Michael-Matta1/zsh-edit-select-master"
            print_success "Detected: Zgenom (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "zgen" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="zgen"
            PLUGIN_INSTALL_DIR="${ZGEN_DIR:-$HOME/.zgen}/Michael-Matta1/zsh-edit-select-master"
            print_success "Detected: Zgen (via .zshrc)" "plugin_manager"
            return
        elif echo "$zshrc_content" | grep -q "sheldon" 2>/dev/null; then
            DETECTED_PLUGIN_MANAGER="sheldon"
            PLUGIN_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon/repos/github.com/Michael-Matta1/zsh-edit-select"
            print_success "Detected: Sheldon (via .zshrc)" "plugin_manager"
            return
        fi
    fi

    # No plugin manager detected — offer to install Oh My Zsh
    print_warning "No Zsh plugin manager detected"

    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        echo ""
        print_info "I noticed you don't have a zsh plugin manager installed."
        if ask_yes_no "Would you like me to install oh-my-zsh? This will enable better plugin management and is recommended for beginners (You can refuse if you prefer manual installation)" "y"; then
            install_oh_my_zsh
            if [[ -d "$HOME/.oh-my-zsh" ]] && [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
                DETECTED_PLUGIN_MANAGER="oh-my-zsh"
                PLUGIN_INSTALL_DIR="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-edit-select"
            fi
        else
            # Fallback to manual choice
            ask_choice "How would you like to install the plugin instead?" \
                "Manual installation (~/.local/share/zsh/plugins)" \
                "Custom path (you will be prompted)"

            local choice="$CHOICE_RESULT"

            case "$choice" in
            1)
                DETECTED_PLUGIN_MANAGER="manual"
                PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                ;;
            2)
                echo -ne "${YELLOW}?${NC} Enter custom installation path: "
                local custom_path
                read -r custom_path

                # Validate custom path
                if [[ -z "$custom_path" ]]; then
                    print_error "Empty path provided, using default"
                    DETECTED_PLUGIN_MANAGER="manual"
                    PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                elif [[ "$custom_path" == "/" ]] || [[ "$custom_path" == "/bin" ]] ||
                    [[ "$custom_path" == "/usr" ]] || [[ "$custom_path" == "/etc" ]]; then
                    print_error "Invalid system path provided, using default"
                    log_message "SECURITY: Rejected invalid path: $custom_path"
                    DETECTED_PLUGIN_MANAGER="manual"
                    PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                else
                    DETECTED_PLUGIN_MANAGER="manual"
                    # Expand ~ to HOME and escape for safety
                    custom_path="${custom_path/#\~/$HOME}"
                    # Basic sanitization - remove multiple slashes, trailing slashes
                    custom_path=$(printf '%s\n' "$custom_path" | sed 's#//*#/#g' | sed 's#/$##')
                    PLUGIN_INSTALL_DIR="${custom_path}/zsh-edit-select"
                    print_info "Using custom path: $PLUGIN_INSTALL_DIR"
                    log_message "CUSTOM_PATH: $PLUGIN_INSTALL_DIR"
                fi
                ;;
            *)
                DETECTED_PLUGIN_MANAGER="manual"
                PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                ;;
            esac
        fi
    else
        print_info "Installing as standalone plugin (non-interactive mode)"
        DETECTED_PLUGIN_MANAGER="manual"
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
    fi

    print_info "Plugin will be installed to: $PLUGIN_INSTALL_DIR"
}

install_oh_my_zsh() {
    print_step "Installing Oh My Zsh..."

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        print_info "Oh My Zsh is already installed"
        return
    fi

    # Check if git is installed (required by Oh My Zsh installer)
    if ! command_exists git; then
        print_warning "Git is required for Oh My Zsh installation"

        if [[ $SUDO_AVAILABLE -eq 1 ]] && [[ "$DETECTED_PACKAGE_MANAGER" != "unknown" ]]; then
            print_step "Attempting to install git..."

            # Install git based on package manager
            local git_install_success=0
            case "$DETECTED_PACKAGE_MANAGER" in
            apt)
                if run_with_sudo apt-get install -y -qq git; then
                    git_install_success=1
                fi
                ;;
            dnf)
                if run_with_sudo dnf install -y -q git; then
                    git_install_success=1
                fi
                ;;
            yum)
                if run_with_sudo yum install -y -q git; then
                    git_install_success=1
                fi
                ;;
            pacman)
                if run_with_sudo pacman -S --noconfirm --needed git; then
                    git_install_success=1
                fi
                ;;
            zypper)
                if run_with_sudo zypper install -y git; then
                    git_install_success=1
                fi
                ;;
            emerge)
                if run_with_sudo emerge --ask=n dev-vcs/git; then
                    git_install_success=1
                fi
                ;;
            apk)
                if run_with_sudo apk add git; then
                    git_install_success=1
                fi
                ;;
            xbps)
                if run_with_sudo xbps-install -y git; then
                    git_install_success=1
                fi
                ;;
            eopkg)
                if run_with_sudo eopkg install -y git; then
                    git_install_success=1
                fi
                ;;
            *)
                print_warning "Cannot auto-install git for $DETECTED_PACKAGE_MANAGER"
                ;;
            esac

            # Verify git installation succeeded
            if [[ $git_install_success -eq 1 ]] && command_exists git; then
                print_success "Git installed" "git_install"
            else
                print_error "Failed to install git" "git_install"
                print_info "Falling back to manual plugin installation mode"
                DETECTED_PLUGIN_MANAGER="manual"
                PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
                MANUAL_STEPS+=("Install git, then optionally install Oh My Zsh: https://ohmyz.sh/")
                return
            fi
        else
            print_error "Cannot install git without sudo privileges" "git_install"
            print_info "Falling back to manual plugin installation mode"
            DETECTED_PLUGIN_MANAGER="manual"
            PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
            MANUAL_STEPS+=("Install git: sudo <package-manager> install git")
            MANUAL_STEPS+=("Then optionally install Oh My Zsh: https://ohmyz.sh/")
            return
        fi
    fi

    if command_exists curl; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    elif command_exists wget; then
        sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        print_error "Neither curl nor wget found. Cannot install Oh My Zsh." "omz_install"
        MANUAL_STEPS+=("Install Oh My Zsh manually: https://ohmyz.sh/")
        DETECTED_PLUGIN_MANAGER="manual"
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
        return
    fi

    # Verify Oh My Zsh installation succeeded
    if [[ ! -d "$HOME/.oh-my-zsh" ]] || [[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
        print_error "Oh My Zsh installation failed" "omz_install"
        print_info "Falling back to manual plugin installation mode"
        DETECTED_PLUGIN_MANAGER="manual"
        PLUGIN_INSTALL_DIR="$HOME/.local/share/zsh/plugins/zsh-edit-select"
        MANUAL_STEPS+=("Install Oh My Zsh manually: https://ohmyz.sh/")
        return
    fi

    # Flush stdin after installation to prevent buffering issues
    flush_stdin

    print_success "Oh My Zsh installed" "omz_install"
}

detect_terminals() {
    print_step "Detecting terminal emulators..."

    DETECTED_TERMINALS=()

    # Check via command lookup
    local term
    local terminals=(
        "kitty"
        "alacritty"
        "wezterm"
        "foot"
        "konsole"
        "gnome-terminal"
        "xfce4-terminal"
        "terminator"
        "tilix"
        "urxvt"
        "st"
        "termite"
        "hyper"
        "xterm"
    )

    for term in "${terminals[@]}"; do
        if command_exists "$term"; then
            DETECTED_TERMINALS+=("$term")
            print_substep "Found: $term ($(get_full_path "$term"))"
        fi
    done

    # Check via environment variables (terminal currently running in)
    if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
            DETECTED_TERMINALS+=("kitty")
            print_substep "Found: kitty (via KITTY_WINDOW_ID)"
        fi
    fi

    if [[ -n "${ALACRITTY_WINDOW_ID:-}" ]] || [[ -n "${ALACRITTY_LOG:-}" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " alacritty " ]]; then
            DETECTED_TERMINALS+=("alacritty")
            local _alacritty_hint="ALACRITTY_WINDOW_ID"
            [[ -z "${ALACRITTY_WINDOW_ID:-}" ]] && _alacritty_hint="ALACRITTY_LOG"
            print_substep "Found: alacritty (via $_alacritty_hint)"
        fi
    fi

    if [[ -n "${WEZTERM_EXECUTABLE:-}" ]]; then
        # Validate that WEZTERM_EXECUTABLE actually points to wezterm
        if [[ -x "$WEZTERM_EXECUTABLE" ]] && [[ -f "$WEZTERM_EXECUTABLE" ]]; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " wezterm " ]]; then
                DETECTED_TERMINALS+=("wezterm")
                print_substep "Found: wezterm (via WEZTERM_EXECUTABLE: $WEZTERM_EXECUTABLE)"
            fi
        else
            print_warning "WEZTERM_EXECUTABLE is set but not a valid executable: $WEZTERM_EXECUTABLE"
            log_message "WEZTERM_INVALID: WEZTERM_EXECUTABLE=$WEZTERM_EXECUTABLE not valid"
        fi
    fi

    if [[ "${TERM:-}" == "foot" ]] || [[ "${TERM:-}" == foot-* ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " foot " ]]; then
            DETECTED_TERMINALS+=("foot")
            print_substep "Found: foot (via TERM)"
        fi
    fi

    # VS Code terminal
    if command_exists code || command_exists code-insiders ||
        [[ -n "${VSCODE_INJECTION:-}" ]] || [[ "${TERM_PROGRAM:-}" == "vscode" ]]; then
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " vscode " ]]; then
            DETECTED_TERMINALS+=("vscode")
            print_substep "Found: VS Code (integrated terminal)"
        fi
    fi

    # Windows Terminal (specifically on WSL)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]]; then
        if find_windows_terminal_settings >/dev/null; then
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " windows-terminal " ]]; then
                DETECTED_TERMINALS+=("windows-terminal")
                print_substep "Found: Windows Terminal (via WSL interop)"
            fi
        fi
    fi

    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_warning "No known terminal emulators detected"
        print_info "Terminal configuration will need to be done manually"
        MANUAL_STEPS+=("Configure your terminal emulator manually (see README.md)")
    else
        print_success "Detected ${#DETECTED_TERMINALS[@]} terminal(s)" "terminals"
    fi
}

install_kitty() {
    print_step "Installing Kitty terminal..."
    if [[ $SUDO_AVAILABLE -eq 0 ]]; then
        print_error "Cannot install Kitty without sudo"
        return 1
    fi

    local cmd=""
    case "$DETECTED_PACKAGE_MANAGER" in
    apt) cmd="apt-get install -y -qq kitty" ;;
    dnf) cmd="dnf install -y -q kitty" ;;
    yum) cmd="yum install -y -q kitty" ;;
    pacman) cmd="pacman -S --noconfirm --needed kitty" ;;
    zypper) cmd="zypper install -y kitty" ;;
    emerge) cmd="emerge --ask=n gui-apps/kitty" ;;
    apk) cmd="apk add kitty" ;;
    xbps) cmd="xbps-install -y kitty" ;;
    eopkg) cmd="eopkg install -y kitty" ;;
    nix) cmd="nix-env -iA nixos.kitty" ;;      # approximated
    swupd) cmd="swupd bundle-add terminals" ;; # might be broad
    *)
        print_warning "Cannot auto-install Kitty for $DETECTED_PACKAGE_MANAGER"
        return 1
        ;;
    esac

    if ! is_package_available "kitty"; then
        print_warning "Kitty package not found in repositories"
        return 1
    fi

    # shellcheck disable=SC2086 # Intentional word splitting
    if run_with_sudo $cmd; then
        # Flush stdin after package installation to prevent buffering issues
        flush_stdin
        print_success "Kitty installed" "kitty_install"
        # Add to detected terminals if not already there
        if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
            DETECTED_TERMINALS+=("kitty")
        fi
        KITTY_FRESHLY_INSTALLED=1
        return 0
    else
        print_error "Failed to install Kitty" "kitty_install"
        return 1
    fi
}

apply_kitty_downloaded_config() {
    local config_url="https://raw.githubusercontent.com/Michael-Matta1/dev-dotfiles/main/kitty.conf"
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    local config_dir
    config_dir="$(dirname "$config_file")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create config directory: $config_dir"
        return 1
    fi
    backup_file "$config_file"

    print_step "Downloading recommended Kitty config..."
    local download_success=0

    if command_exists curl; then
        if curl -fsSL -o "$config_file" "$config_url"; then
            download_success=1
        fi
    elif command_exists wget; then
        if wget -q -O "$config_file" "$config_url"; then
            download_success=1
        fi
    else
        print_error "Cannot download config: neither curl nor wget is installed"
        print_info "Please install curl or wget using your package manager"
        return 1
    fi

    if [[ $download_success -eq 0 ]] || [[ ! -f "$config_file" ]]; then
        print_error "Download failed: could not fetch $config_url"
        print_info "Please check your internet connection and try again"
        print_info "Or manually download from: $config_url"
        return 1
    fi
    print_success "Config downloaded" "kitty_dl"

    # Check for background_image configuration and warn user
    if grep -q "^background_image" "$config_file" 2>/dev/null; then
        echo ""
        print_warning "═══════════════════════════════════════════════════════════════"
        print_warning "IMPORTANT: The downloaded kitty.conf contains a background_image setting!"
        print_warning ""
        print_warning "The line looks like:"
        print_warning "  background_image  <path_to_your_kitty_background_image>"
        print_warning ""
        print_warning "You need to either:"
        print_warning "  1. Replace it with the actual path to your background image"
        print_warning "  2. Comment it out (add # at the start) if you don't want a background"
        print_warning "  3. Delete the line entirely"
        print_warning ""
        print_warning "If you added a path to a background image, uncomment the line:"
        print_warning "  background_opacity        0.1"
        print_warning "to make it transparent."
        print_warning ""
        print_warning "Edit: $config_file"
        print_warning "═══════════════════════════════════════════════════════════════"
        echo ""
    fi

    # Flush stdin after download and messages to prevent buffering issues
    flush_stdin
    # Give terminal time to settle after all the output
    sleep 0.5

    echo ""
    print_info "Note: This configuration uses a reversed copy/paste style where:"
    print_info "  - Ctrl+C = Copy (instead of interrupt)"
    print_info "  - Ctrl+Shift+C = Interrupt/Kill (SIGINT)"
    echo ""

    # Additional flush and sleep before interactive prompt to ensure clean stdin
    flush_stdin
    sleep 0.3

    # Call ask_choice - it sets CHOICE_RESULT global variable
    ask_choice "Would you like to keep this reversed style, or would you prefer the traditional keyboard shortcuts?" \
        "Keep reversed style (Ctrl+C for copy)" \
        "Use traditional style (Ctrl+Shift+C for copy)"

    local choice="$CHOICE_RESULT"

    if [[ "$choice" == "2" ]]; then
        print_substep "Applying traditional mappings..."
        # Apply traditional mappings: Ctrl+Shift+C sends escape sequence for plugin copy
        sed_inplace 's/map ctrl+shift+c.*send_text all .*/map ctrl+shift+c send_text all \\x1b[67;6u/' "$config_file"
        sed_inplace 's/map ctrl+c.*send_text all .*/map ctrl+c send_text all \\x03/' "$config_file"
        print_success "Reverted to traditional shortcuts" "kitty_keybinds"
    else
        print_info "Keeping reversed shortcuts"
    fi
}

offer_kitty_installation() {
    # Offer Kitty installation after dependencies are set up,
    # so package manager is ready and sudo is confirmed.
    # Only offer in interactive mode.
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        return
    fi

    # Skip if kitty is already detected
    if command_exists kitty || [[ " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
        return
    fi

    echo ""
    print_info "Optional: For maximum compatibility with the zsh plugin, I recommend installing the Kitty terminal emulator."
    if ask_yes_no "Would you like me to install it? (This is an optional step)" "y"; then
        if install_kitty; then
            # Add to detected terminals if not already there
            if [[ ! " ${DETECTED_TERMINALS[*]:-} " =~ " kitty " ]]; then
                DETECTED_TERMINALS+=("kitty")
            fi
        fi
    fi
}

ask_kitty_configuration() {
    # Only show this prompt if:
    # 1. Kitty was just installed by this script (KITTY_FRESHLY_INSTALLED=1)
    # 2. We're in interactive mode (user can respond to prompts)
    if [[ $KITTY_FRESHLY_INSTALLED -ne 1 ]]; then
        return 0 # Skip if kitty wasn't freshly installed
    fi

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        return 0 # Skip in non-interactive mode
    fi

    echo ""
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║         OPTIONAL: Enhanced Kitty Configuration                ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}⚠ THIS IS COMPLETELY OPTIONAL AND NOT REQUIRED! ⚠${NC}"
    echo ""
    print_info "${BOLD}${GREEN}The zsh-edit-select plugin is ALREADY FULLY FUNCTIONAL!${NC}"
    print_info "You can start using it right away without any additional configuration."
    echo ""
    print_info "However, since you just installed Kitty terminal, there's an ${BOLD}optional${NC}"
    print_info "enhanced configuration available that includes:"
    echo ""
    print_info "  ${GREEN}•${NC} Optimized aesthetics and visual features"
    print_info "  ${GREEN}•${NC} Additional convenience settings"
    print_info "  ${GREEN}•${NC} Full compatibility with zsh-edit-select"
    echo ""
    print_info "${BOLD}Source:${NC} https://github.com/Michael-Matta1/dev-dotfiles/blob/main/kitty.conf"
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "${BOLD}Important:${NC} You can ${GREEN}safely skip${NC} this step."
    print_info "The plugin works ${BOLD}perfectly fine${NC} with Kitty's default configuration!"
    echo ""

    if ask_yes_no "Would you like to download this optional enhanced configuration?" "n"; then
        apply_kitty_downloaded_config
    else
        print_info "Skipped optional Kitty configuration."
        print_success "The plugin is ready to use with your current Kitty setup!"
    fi
}

# Dependency Installation Functions

install_dependencies() {
    if [[ $SKIP_DEPS -eq 1 ]]; then
        print_info "Skipping dependency installation (--skip-deps flag)"
        return
    fi

    print_step "Installing dependencies..."

    if [[ $SUDO_AVAILABLE -eq 0 ]]; then
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
    *)
        print_warning "Unknown package manager: $DETECTED_PACKAGE_MANAGER"
        print_info "Please install dependencies manually:"
        print_info "  - C compiler toolchain (gcc, make)"
        if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
            print_info "  - libx11-dev libxfixes-dev (X11 libraries)"
            print_info "  - xclip (clipboard tool, optional)"
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
}

ask_xwayland_deps() {
    # Always install X11 dev headers for Wayland users (XWayland compatibility)
    if [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        return 0 # yes
    fi
    return 1 # no
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

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
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

# User Preference Questions

ask_user_preferences() {
    print_header "Phase 2.5: User Preferences"

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

# Plugin Installation Functions

install_plugin() {
    print_step "Installing zsh-edit-select plugin..."

    # Validate that PLUGIN_INSTALL_DIR is set
    if [[ -z "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin installation directory not set" "plugin_install"
        print_error "This usually means plugin manager detection failed"
        FAILED_STEPS["plugin_install"]="Plugin directory not configured"
        return 1
    fi

    # Clone or update the repository
    if [[ -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_substep "Plugin directory already exists, checking status..."

        # Check if it's a git repository
        if [[ -d "$PLUGIN_INSTALL_DIR/.git" ]]; then
            print_substep "Updating existing plugin..."
            if (cd "$PLUGIN_INSTALL_DIR" && git pull --quiet 2>/dev/null); then
                print_success "Plugin updated" "plugin_install"
            else
                print_warning "Could not update plugin, attempting to re-clone..."
                # Extensive validation before removing to prevent accidental deletion
                if [[ -z "$PLUGIN_INSTALL_DIR" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "$HOME" ]] || [[ "$PLUGIN_INSTALL_DIR" == "$HOME/" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "/usr" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/etc" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "/var" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/tmp" ]] ||
                    [[ ! "$PLUGIN_INSTALL_DIR" =~ zsh-edit-select ]] || [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
                    print_error "Invalid or unsafe plugin directory path, refusing to delete: $PLUGIN_INSTALL_DIR"
                    FAILED_STEPS["plugin_install"]="Invalid plugin directory"
                    return 1
                fi
                # Additional safety: check if directory contains expected plugin files
                if [[ ! -f "$PLUGIN_INSTALL_DIR/zsh-edit-select.plugin.zsh" ]] &&
                    [[ ! -f "$PLUGIN_INSTALL_DIR/README.md" ]]; then
                    print_error "Directory doesn't appear to be zsh-edit-select plugin, refusing to delete: $PLUGIN_INSTALL_DIR"
                    FAILED_STEPS["plugin_install"]="Directory validation failed"
                    return 1
                fi
                rm -rf "$PLUGIN_INSTALL_DIR"
                clone_plugin
            fi
        else
            # Directory exists but is not a git repo
            print_warning "Plugin directory exists but is not a git repository"
            # Check if it looks like the plugin (has the main file)
            if [[ -f "$PLUGIN_INSTALL_DIR/zsh-edit-select.plugin.zsh" ]]; then
                print_info "Plugin files found, skipping clone"
                print_success "Using existing plugin installation" "plugin_install"
            else
                print_warning "Plugin files not found in directory, will re-clone"
                # Safety validation before deletion
                if [[ -z "$PLUGIN_INSTALL_DIR" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "$HOME" ]] || [[ "$PLUGIN_INSTALL_DIR" == "$HOME/" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "/usr" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/etc" ]] ||
                    [[ "$PLUGIN_INSTALL_DIR" == "/var" ]] || [[ "$PLUGIN_INSTALL_DIR" == "/tmp" ]] ||
                    [[ ! "$PLUGIN_INSTALL_DIR" =~ zsh-edit-select ]]; then
                    print_error "Invalid or unsafe plugin directory path, refusing to delete: $PLUGIN_INSTALL_DIR"
                    FAILED_STEPS["plugin_install"]="Invalid plugin directory"
                    return 1
                fi
                rm -rf "$PLUGIN_INSTALL_DIR"
                clone_plugin
            fi
        fi
    else
        clone_plugin
    fi

    # Verify installation
    if [[ ! -f "$PLUGIN_INSTALL_DIR/zsh-edit-select.plugin.zsh" ]]; then
        print_error "Plugin installation verification failed: main file not found"
        FAILED_STEPS["plugin_install"]="Plugin file missing after installation"
        return 1
    fi

    # Configure .zshrc
    configure_zshrc
}

clone_plugin() {
    # Verify git is installed before attempting clone
    if ! command_exists git; then
        print_error "git is not installed, cannot clone plugin" "plugin_install"
        print_info "Install git using your package manager:"
        case "$DETECTED_PACKAGE_MANAGER" in
        apt) print_info "  sudo apt-get install git" ;;
        dnf) print_info "  sudo dnf install git" ;;
        yum) print_info "  sudo yum install git" ;;
        pacman) print_info "  sudo pacman -S git" ;;
        zypper) print_info "  sudo zypper install git" ;;
        apk) print_info "  sudo apk add git" ;;
        *) print_info "  Install git using your package manager" ;;
        esac
        MANUAL_STEPS+=("Install git and clone the plugin: git clone $REPO_URL $PLUGIN_INSTALL_DIR")
        return 1
    fi

    # Check network connectivity before attempting clone
    if ! check_network_connectivity; then
        print_error "No network connectivity - cannot clone plugin" "plugin_install"
        MANUAL_STEPS+=("Establish network connection and clone: git clone $REPO_URL $PLUGIN_INSTALL_DIR")
        return 1
    fi

    local parent_dir
    parent_dir="$(dirname "$PLUGIN_INSTALL_DIR")"

    if ! mkdir -p "$parent_dir" 2>/dev/null; then
        print_error "Failed to create plugin directory: $parent_dir" "plugin_install"
        print_error "Please check permissions and disk space"
        log_message "MKDIR_FAILED: Cannot create $parent_dir"
        return 1
    fi

    # Verify directory was actually created and is writable
    if [[ ! -d "$parent_dir" ]] || [[ ! -w "$parent_dir" ]]; then
        print_error "Plugin directory exists but is not writable: $parent_dir" "plugin_install"
        log_message "PERMISSION_ERROR: $parent_dir not writable"
        return 1
    fi

    if clone_with_retry "$REPO_URL" "$PLUGIN_INSTALL_DIR"; then
        # Flush stdin after clone to prevent buffering issues
        flush_stdin
        print_success "Plugin cloned to $PLUGIN_INSTALL_DIR" "plugin_install"
    else
        print_error "Failed to clone plugin repository" "plugin_install"
        print_info "Ensure git is installed and $REPO_URL is accessible"
        MANUAL_STEPS+=("Clone the plugin manually: git clone $REPO_URL $PLUGIN_INSTALL_DIR")
        return 1
    fi
}

clone_with_retry() {
    local url="$1"
    local dest="$2"
    local retries=3
    local timeout=300 # 5 minutes

    # Validate URL format
    if [[ ! "$url" =~ ^https?:// ]] && [[ ! "$url" =~ ^git@ ]]; then
        print_error "Invalid git URL format: $url"
        log_message "GIT_CLONE_ERROR: Invalid URL format $url"
        return 1
    fi

    # Validate destination path
    if [[ -z "$dest" ]] || [[ "$dest" == "/" ]] || [[ "$dest" == "$HOME" ]]; then
        print_error "Invalid clone destination: $dest"
        log_message "GIT_CLONE_ERROR: Invalid destination $dest"
        return 1
    fi

    for ((i = 1; i <= retries; i++)); do
        print_info "Cloning repository (attempt $i/$retries)..."

        # Use timeout if available
        if command_exists timeout; then
            if timeout "$timeout" git clone --depth 1 "$url" "$dest" >>"$LOG_FILE" 2>&1; then
                # Verify .git directory exists
                if [[ -d "$dest/.git" ]]; then
                    log_message "GIT_CLONE_SUCCESS: Cloned $url to $dest"
                    return 0
                else
                    print_warning "Clone succeeded but .git directory not found"
                    log_message "GIT_CLONE_WARNING: No .git directory in $dest"
                fi
            fi
        else
            if git clone --depth 1 "$url" "$dest" >>"$LOG_FILE" 2>&1; then
                # Verify .git directory exists
                if [[ -d "$dest/.git" ]]; then
                    log_message "GIT_CLONE_SUCCESS: Cloned $url to $dest"
                    return 0
                else
                    print_warning "Clone succeeded but .git directory not found"
                    log_message "GIT_CLONE_WARNING: No .git directory in $dest"
                fi
            fi
        fi

        print_warning "Clone attempt $i failed"
        # Clean up failed clone attempt before retry (or on final failure)
        if [[ -n "$dest" ]] && [[ "$dest" != "/" ]] &&
            [[ "$dest" != "$HOME" ]] && [[ -e "$dest" ]]; then
            [[ $i -lt $retries ]] && sleep 5
            rm -rf "$dest"
        fi
    done

    log_message "GIT_CLONE_FAILED: All attempts failed for $url"
    return 1
}

configure_zshrc() {
    print_step "Configuring .zshrc..."

    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    check_write_permission "$zshrc" || return 1

    # Create .zshrc if it doesn't exist
    if [[ ! -f "$zshrc" ]]; then
        touch "$zshrc"
        print_info "Created new .zshrc"
    fi

    # Backup .zshrc using the centralized backup system
    backup_file "$zshrc"

    # Check if already installed by this script (idempotency check)
    local marker="# zsh-edit-select auto-installer"
    if grep -Fq "$marker" "$zshrc" 2>/dev/null; then
        print_info "Plugin already configured in .zshrc (marker found)"
        return
    fi

    # Fallback check for manual installs
    if grep -qF "zsh-edit-select" "$zshrc" 2>/dev/null; then
        print_info "Plugin already configured in .zshrc"
        return
    fi

    # Add plugin configuration based on detected plugin manager
    case "$DETECTED_PLUGIN_MANAGER" in
    oh-my-zsh)
        # Add to plugins list
        # Check if it's a single-line plugins array
        if grep -q "^plugins=([^)]*)[[:space:]]*$" "$zshrc" 2>/dev/null; then
            # Single-line array format: plugins=(git vim docker)
            local tmp_zshrc
            tmp_zshrc=$(mktemp) || {
                print_error "Failed to create temporary file"
                return 1
            }
            if awk '{
                    if ($0 ~ /^plugins=\(/ && $0 !~ /zsh-edit-select/) {
                        sub(/^plugins=\(/, "plugins=(zsh-edit-select ", $0)
                    }
                    print
                }' "$zshrc" >"$tmp_zshrc" && {
                chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null
                mv "$tmp_zshrc" "$zshrc"
            }; then
                echo "$marker" >>"$zshrc"
                print_success "Added zsh-edit-select to Oh My Zsh plugins" "zshrc_config"
            else
                rm -f "$tmp_zshrc"
                print_error "Failed to update plugins array in .zshrc"
                return 1
            fi
        else
            # Either no plugins array, or multi-line array - use plugins+=
            # Insert BEFORE 'source $ZSH/oh-my-zsh.sh' so OMZ sees the plugin
            local insert_block
            insert_block=$(printf '%s\n%s\n%s' "$marker" "# Zsh Edit-Select plugin" "plugins+=(zsh-edit-select)")
            if grep -q 'source.*\$ZSH/oh-my-zsh\.sh' "$zshrc" 2>/dev/null; then
                local tmp_zshrc
                tmp_zshrc=$(mktemp) || {
                    print_error "Failed to create temporary file"
                    return 1
                }
                if awk -v block="$insert_block" '
                    /source.*\$ZSH\/oh-my-zsh\.sh/ && !done {
                        print ""
                        n = split(block, lines, "\n")
                        for (i = 1; i <= n; i++) print lines[i]
                        done = 1
                    }
                    { print }
                ' "$zshrc" >"$tmp_zshrc" && {
                    chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null
                    mv "$tmp_zshrc" "$zshrc"
                }; then
                    print_success "Added plugins+=(zsh-edit-select) to .zshrc (before oh-my-zsh source)" "zshrc_config"
                else
                    rm -f "$tmp_zshrc"
                    print_error "Failed to insert plugin config into .zshrc"
                    return 1
                fi
            else
                # No source line found - append at end as fallback
                echo "" >>"$zshrc"
                echo "$marker" >>"$zshrc"
                echo "# Zsh Edit-Select plugin" >>"$zshrc"
                echo "plugins+=(zsh-edit-select)" >>"$zshrc"
                print_success "Added plugins+=(zsh-edit-select) to .zshrc" "zshrc_config"
            fi
        fi
        ;;

    zinit)
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "zinit light Michael-Matta1/zsh-edit-select"
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added Zinit configuration to .zshrc" "zshrc_config"
        ;;

    zplug)
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "zplug \"Michael-Matta1/zsh-edit-select\""
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added Zplug configuration to .zshrc" "zshrc_config"
        ;;

    antigen)
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "antigen bundle Michael-Matta1/zsh-edit-select"
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added Antigen configuration to .zshrc" "zshrc_config"
        ;;

    antibody)
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "antibody bundle Michael-Matta1/zsh-edit-select"
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added Antibody configuration to .zshrc" "zshrc_config"
        ;;

    zgen | zgenom)
        local cmd="$DETECTED_PLUGIN_MANAGER"
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "$cmd load Michael-Matta1/zsh-edit-select"
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added $cmd configuration to .zshrc" "zshrc_config"
        ;;

    sheldon)
        local sheldon_config="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
        if [[ -f "$sheldon_config" ]]; then
            if ! grep -qF "zsh-edit-select" "$sheldon_config" 2>/dev/null; then
                cat >>"$sheldon_config" <<'SHELDON'

[plugins.zsh-edit-select]
github = "Michael-Matta1/zsh-edit-select"
SHELDON
                print_success "Added Sheldon plugin configuration" "zshrc_config"
            else
                print_info "Plugin already configured in Sheldon"
            fi
        else
            print_warning "Sheldon config not found"
            MANUAL_STEPS+=("Add zsh-edit-select to your Sheldon configuration")
        fi
        ;;

    manual | *)
        local -a lines=(
            ""
            "$marker"
            "# Zsh Edit-Select"
            "source \"$PLUGIN_INSTALL_DIR/zsh-edit-select.plugin.zsh\""
        )
        for line in "${lines[@]}"; do
            echo "$line" >>"$zshrc"
        done
        print_success "Added manual source to .zshrc" "zshrc_config"
        ;;
    esac
}

# Agent Build Functions

build_monitor_daemons() {
    print_header "Phase 4: Building Agents"

    if [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory not found: $PLUGIN_INSTALL_DIR" "monitor_build"
        return
    fi

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        build_x11_monitor
    elif [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        build_wayland_monitor
        # Only build XWayland monitor if DISPLAY is set (XWayland available)
        if [[ -n "${DISPLAY:-}" ]]; then
            build_xwayland_monitor
        fi
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
        return
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-x11/backends/x11"

    if [[ ! -d "$build_dir" ]]; then
        print_error "X11 backend source directory not found: $build_dir" "x11_monitor_build"
        print_info "Expected location per README: impl-x11/backends/x11"
        return
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "x11_monitor_build"
        MANUAL_STEPS+=("Build X11 agent manually")
        return
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-x11-selection-agent" ]]; then
            print_success "X11 clipboard agent built successfully" "x11_monitor_build"
        else
            print_warning "Build reported success but binary not found" "x11_monitor_build"
            MANUAL_STEPS+=("Verify X11 agent binary in $build_dir")
        fi
    else
        print_error "Failed to build X11 clipboard agent" "x11_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build X11 agent: cd $build_dir && make")
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
        return
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland"

    if [[ ! -d "$build_dir" ]]; then
        print_error "Wayland backend source directory not found: $build_dir" "wayland_monitor_build"
        print_info "Expected location per README: impl-wayland/backends/wayland"
        return
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "wayland_monitor_build"
        MANUAL_STEPS+=("Build Wayland agent manually")
        return
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-wl-selection-agent" ]]; then
            print_success "Wayland clipboard agent built successfully" "wayland_monitor_build"
        else
            print_warning "Build reported success but binary not found" "wayland_monitor_build"
            MANUAL_STEPS+=("Verify Wayland agent binary in $build_dir")
        fi
    else
        print_error "Failed to build Wayland clipboard agent" "wayland_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build Wayland agent: cd $build_dir && make")
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
        return
    fi

    local build_dir="$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland"

    if [[ ! -d "$build_dir" ]]; then
        print_info "XWayland backend source directory not found (optional component)"
        print_info "Expected location per README: impl-wayland/backends/xwayland"
        return
    fi

    if [[ ! -f "$build_dir/Makefile" ]]; then
        print_warning "No Makefile found in $build_dir" "xwayland_monitor_build"
        MANUAL_STEPS+=("Build XWayland agent manually")
        return
    fi

    local build_output
    if build_output=$(
        cd "$build_dir" && { make clean 2>/dev/null || true; } && make 2>&1
    ); then
        # Verify the binary was actually created
        if [[ -f "$build_dir/zes-xwayland-agent" ]]; then
            print_success "XWayland clipboard agent built successfully" "xwayland_monitor_build"
        else
            print_warning "Build reported success but binary not found" "xwayland_monitor_build"
            MANUAL_STEPS+=("Verify XWayland agent binary in $build_dir")
        fi
    else
        print_error "Failed to build XWayland clipboard agent" "xwayland_monitor_build"
        print_info "Build output (last 10 lines):"
        echo "$build_output" | tail -10 | sed 's/^/    /' | tee -a "$LOG_FILE"
        MANUAL_STEPS+=("Build XWayland agent: cd $build_dir && make")
    fi
}

# Terminal Configuration Functions

configure_terminals() {
    print_header "Phase 5: Terminal Configuration"

    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_info "No terminals to configure"
        return
    fi

    # Pre-check write permissions for all terminal configs
    print_substep "Checking configuration file permissions..."
    local permission_issues=()
    local terminal
    local issue

    for terminal in "${DETECTED_TERMINALS[@]}"; do
        local config=""
        case "$terminal" in
        kitty) config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf" ;;
        alacritty)
            if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml" ]]; then
                config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
            else
                config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
            fi
            ;;
        wezterm) config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua" ;;
        foot) config="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini" ;;
        vscode)
            # VSCode has a different config location
            if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ]]; then
                config="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
            elif [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User" ]]; then
                config="${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/keybindings.json"
            fi
            ;;
        windows-terminal) config="${WT_SETTINGS_PATH:-}" ;;
        esac

        if [[ -n "$config" ]]; then
            local config_dir
            config_dir="$(dirname "$config")"

            # Check directory write permission
            if [[ ! -d "$config_dir" ]]; then
                # Try to create it
                if ! mkdir -p "$config_dir" 2>/dev/null; then
                    permission_issues+=("$terminal: Cannot create config directory $config_dir")
                fi
            fi

            # Check file write permission if it exists
            if [[ -f "$config" ]] && [[ ! -w "$config" ]]; then
                permission_issues+=("$terminal: Config file $config is not writable")
            fi
        fi
    done

    if [[ ${#permission_issues[@]} -gt 0 ]]; then
        print_warning "Permission issues detected for some terminal configs:"
        for issue in "${permission_issues[@]}"; do
            print_warning "  • $issue"
        done
        print_info "Continuing with terminals that have writable configs..."
    fi

    for terminal in "${DETECTED_TERMINALS[@]}"; do
        case "$terminal" in
        kitty) configure_kitty ;;
        alacritty) configure_alacritty ;;
        wezterm) configure_wezterm ;;
        foot) configure_foot ;;
        vscode) configure_vscode ;;
        windows-terminal) configure_windows_terminal ;;
        konsole | gnome-terminal | xfce4-terminal | terminator | tilix)
            print_info "$terminal: Uses default keybindings, no configuration needed"
            ;;
        *)
            print_info "$terminal: Manual configuration may be required (see README.md)"
            ;;
        esac
    done
}

backup_config() {
    backup_file "$1"
}

configure_kitty() {
    print_step "Configuring Kitty..."

    local config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    local config_dir
    config_dir="$(dirname "$config")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Kitty config directory: $config_dir"
        return 1
    fi
    [[ ! -f "$config" ]] && touch "$config"
    backup_config "$config"

    local -a config_lines=()

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_lines+=(
            "# Ctrl+C sends the escape sequence for copying"
            "map ctrl+c send_text all \\x1b[67;6u"
            "# Ctrl+Shift+C sends interrupt (default behavior)"
            "map ctrl+shift+c send_text all \\x03"
        )
    else
        config_lines+=(
            "# Copy with Ctrl+Shift+C"
            "map ctrl+shift+c send_text all \\x1b[67;6u"
        )
    fi

    config_lines+=(
        "# Redo with Ctrl+Shift+Z"
        "map ctrl+shift+z send_text all \\x1b[90;6u"
        ""
        "# Disable Kitty handling of Shift+Arrow so Zsh can use them for selection"
        "map shift+left       no_op"
        "map shift+right      no_op"
        "map shift+up         no_op"
        "map shift+down       no_op"
        "map shift+home       no_op"
        "map shift+end        no_op"
        "map ctrl+shift+left  no_op"
        "map ctrl+shift+right no_op"
        "map ctrl+shift+home  no_op"
        "map ctrl+shift+end   no_op"
    )

    # Check if already fully configured (all non-empty, non-comment lines exist)
    local all_exist=1
    for line in "${config_lines[@]}"; do
        # Skip empty/comment lines for the existence check
        [[ -z "${line// /}" ]] && continue
        [[ "$line" == "#"* ]] && continue
        if ! config_line_exists "$config" "$line"; then
            all_exist=0
            break
        fi
    done

    if [[ $all_exist -eq 1 ]] && grep -qF "# Zsh Edit-Select" "$config" 2>/dev/null; then
        print_info "Kitty already fully configured for zsh-edit-select"
        return 0
    fi

    # Write config as a block for clean formatting
    # First add each non-duplicate line individually
    local config_was_modified=0

    # Ensure the marker comment exists
    if ! config_line_exists "$config" "# Zsh Edit-Select"; then
        echo "" >>"$config"
        echo "# Zsh Edit-Select" >>"$config"
        config_was_modified=1
    fi

    for line in "${config_lines[@]}"; do
        # Write empty lines as-is for formatting (only when we're adding new config)
        if [[ -z "${line// /}" ]]; then
            if [[ $config_was_modified -eq 1 ]]; then
                echo "" >>"$config"
            fi
            continue
        fi
        # Skip comment-only lines if they already exist
        if [[ "$line" == "#"* ]]; then
            if ! config_line_exists "$config" "$line"; then
                echo "$line" >>"$config"
                config_was_modified=1
            fi
            continue
        fi
        if ! config_line_exists "$config" "$line"; then
            echo "$line" >>"$config"
            config_was_modified=1
        fi
    done

    if [[ $config_was_modified -eq 1 ]]; then
        # Kitty auto-reloads kitty.conf via inotify. Give it a moment to process
        # the reload so it doesn't inject notification escape sequences into stdin
        # mid-output (which appears as garbled text in subsequent print_header lines).
        sleep 0.4 2>/dev/null || true
        flush_stdin
        print_success "Kitty configured successfully" "kitty_config"
    else
        print_info "Kitty already fully configured for zsh-edit-select"
    fi
}

configure_alacritty() {
    print_step "Configuring Alacritty..."

    # Determine config format (TOML is preferred for newer versions)
    local config_toml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
    local config_yml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
    local config_dir
    config_dir="$(dirname "$config_toml")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Alacritty config directory: $config_dir"
        return 1
    fi

    if [[ -f "$config_toml" ]]; then
        configure_alacritty_toml "$config_toml"
    elif [[ -f "$config_yml" ]]; then
        configure_alacritty_yml "$config_yml"
    else
        # Default to TOML for new installations
        touch "$config_toml"
        configure_alacritty_toml "$config_toml"
    fi
}

configure_alacritty_toml() {
    local config="$1"
    backup_config "$config"

    # Check if we need to add any configuration
    local needs_config=0

    # Check if the configuration marker exists
    if ! grep -qF "Zsh Edit-Select" "$config" 2>/dev/null; then
        needs_config=1
    fi

    local config_block=""

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_block=$'\n# Zsh Edit-Select\n# Ctrl+C sends the escape sequence for copying\n[[keyboard.bindings]]\nkey = "C"\nmods = "Control"\nchars = "\\u001b[67;6u"\n\n# Ctrl+Shift+C sends interrupt signal\n[[keyboard.bindings]]\nkey = "C"\nmods = "Control|Shift"\nchars = "\\u0003"'
    else
        config_block=$'\n# Zsh Edit-Select\n# Copy with Ctrl+Shift+C\n[[keyboard.bindings]]\nkey = "C"\nmods = "Control|Shift"\nchars = "\\u001b[67;6u"'
    fi

    # Redo with Ctrl+Shift+Z
    config_block+=$'\n\n# Redo with Ctrl+Shift+Z\n[[keyboard.bindings]]\nkey = "Z"\nmods = "Control|Shift"\nchars = "\\u001b[90;6u"'

    # Pass Shift+Home/End through for selection
    # (Alacritty defaults: Shift+Home=ScrollToTop, Shift+End=ScrollToBottom)
    config_block+=$'\n\n# Pass Shift+Home/End through for selection\n# (overrides Alacritty defaults: ScrollToTop / ScrollToBottom)\n[[keyboard.bindings]]\nkey = "Home"\nmods = "Shift"\naction = "ReceiveChar"\n\n[[keyboard.bindings]]\nkey = "End"\nmods = "Shift"\naction = "ReceiveChar"'

    # Only append if configuration is missing
    if [[ $needs_config -eq 1 ]]; then
        echo "$config_block" >>"$config"
        print_success "Alacritty (TOML) configured successfully" "alacritty_config"
    else
        print_info "Alacritty (TOML) already configured for zsh-edit-select"
    fi
}

configure_alacritty_yml() {
    local config="$1"
    backup_config "$config"

    # Check if we need to add any configuration
    local needs_config=0

    # Check if the configuration marker exists
    if ! grep -qF "Zsh Edit-Select" "$config" 2>/dev/null; then
        needs_config=1
    fi

    local config_block=""

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_block=$'\n# Zsh Edit-Select\nkey_bindings:\n  # Ctrl+C sends the escape sequence for copying\n  - { key: C, mods: Control, chars: "\\x1b[67;6u" }\n  # Ctrl+Shift+C sends interrupt signal\n  - { key: C, mods: Control|Shift, chars: "\\x03" }\n  # Redo with Ctrl+Shift+Z\n  - { key: Z, mods: Control|Shift, chars: "\\x1b[90;6u" }\n  # Pass Shift+Home/End through for selection\n  - { key: Home, mods: Shift, action: ReceiveChar }\n  - { key: End, mods: Shift, action: ReceiveChar }'
    else
        config_block=$'\n# Zsh Edit-Select\nkey_bindings:\n  # Copy with Ctrl+Shift+C\n  - { key: C, mods: Control|Shift, chars: "\\x1b[67;6u" }\n  # Redo with Ctrl+Shift+Z\n  - { key: Z, mods: Control|Shift, chars: "\\x1b[90;6u" }\n  # Pass Shift+Home/End through for selection\n  - { key: Home, mods: Shift, action: ReceiveChar }\n  - { key: End, mods: Shift, action: ReceiveChar }'
    fi

    # Only append if configuration is missing
    if [[ $needs_config -eq 1 ]]; then
        echo "$config_block" >>"$config"
        print_success "Alacritty (YAML) configured successfully" "alacritty_config"
    else
        print_info "Alacritty (YAML) already configured for zsh-edit-select"
    fi
}

configure_wezterm() {
    print_step "Configuring WezTerm..."

    local config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
    local config_alt="$HOME/.wezterm.lua"
    local config_dir

    # WezTerm checks XDG path first, then ~/.wezterm.lua
    # Use whichever one already exists; default to XDG for new installs
    if [[ -f "$config" ]]; then
        : # use XDG path
    elif [[ -f "$config_alt" ]]; then
        config="$config_alt"
    fi

    config_dir="$(dirname "$config")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create WezTerm config directory: $config_dir"
        return 1
    fi

    if [[ ! -f "$config" ]]; then
        # Create default WezTerm config
        cat >"$config" <<'WEZTERM_DEFAULT'
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Zsh Edit-Select keybindings will be added below

return config
WEZTERM_DEFAULT
        print_substep "Created default wezterm.lua"
    else
        backup_config "$config"
    fi

    # Check if we need to add configuration
    local needs_config=0
    if ! grep -qF "Zsh Edit-Select" "$config" 2>/dev/null; then
        needs_config=1
    fi

    # If already configured, skip
    if [[ $needs_config -eq 0 ]]; then
        print_info "WezTerm already configured for zsh-edit-select"
        return
    fi

    # Build config block
    local config_block=""

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_block=$(
            cat <<'WEZTERM_REVERSED'

-- Zsh Edit-Select
config.keys = config.keys or {}
local zes_keys = {
  { key = 'c', mods = 'CTRL', action = wezterm.action.SendString '\x1b[67;6u' },
  { key = 'C', mods = 'CTRL|SHIFT', action = wezterm.action.SendString '\x03' },
  { key = 'Z', mods = 'CTRL|SHIFT', action = wezterm.action.SendString '\x1b[90;6u' },
  -- Disable Ctrl+Shift+Arrow so Zsh can use them for word selection
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  -- Disable Ctrl+Shift+Home/End so Zsh can use them for buffer selection
  { key = 'Home', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  { key = 'End', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
}
for _, k in ipairs(zes_keys) do table.insert(config.keys, k) end
WEZTERM_REVERSED
        )
    else
        config_block=$(
            cat <<'WEZTERM_DEFAULT_KEYS'

-- Zsh Edit-Select
config.keys = config.keys or {}
local zes_keys = {
  { key = 'C', mods = 'CTRL|SHIFT', action = wezterm.action.SendString '\x1b[67;6u' },
  { key = 'Z', mods = 'CTRL|SHIFT', action = wezterm.action.SendString '\x1b[90;6u' },
  -- Disable Ctrl+Shift+Arrow so Zsh can use them for word selection
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  -- Disable Ctrl+Shift+Home/End so Zsh can use them for buffer selection
  { key = 'Home', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  { key = 'End', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
}
for _, k in ipairs(zes_keys) do table.insert(config.keys, k) end
WEZTERM_DEFAULT_KEYS
        )
    fi

    # Insert before 'return config' or 'return' if present, otherwise append
    if grep -qE '^return' "$config"; then
        # Use a temp file to safely insert the block before the return statement
        local tmpfile
        tmpfile=$(mktemp 2>/dev/null) || {
            print_error "Failed to create temporary file for WezTerm config"
            # Fallback: try to append at end
            echo "$config_block" >>"$config" && {
                print_success "WezTerm configured (appended to end)" "wezterm_config"
                return 0
            } || {
                print_error "Failed to update WezTerm config"
                return 1
            }
        }

        local inserted=0
        local line_count=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_count++))
            if [[ $inserted -eq 0 ]] && [[ "$line" =~ ^return[[:space:]]+config ]]; then
                echo "$config_block" >>"$tmpfile"
                echo "" >>"$tmpfile"
                inserted=1
            fi
            echo "$line" >>"$tmpfile"
        done <"$config"

        # Verify temp file is not empty and has reasonable content
        if [[ ! -s "$tmpfile" ]]; then
            print_error "Generated temp file is empty"
            rm -f "$tmpfile"
            return 1
        fi

        local tmp_line_count
        tmp_line_count=$(wc -l <"$tmpfile" 2>/dev/null || echo 0)
        if [[ $tmp_line_count -lt $line_count ]]; then
            print_error "Temp file has fewer lines than original, aborting"
            rm -f "$tmpfile"
            return 1
        fi

        chmod --reference="$config" "$tmpfile" 2>/dev/null
        if mv "$tmpfile" "$config" 2>/dev/null; then
            : # Success
        else
            # mv failed, try copy as fallback
            if cp "$tmpfile" "$config" 2>/dev/null; then
                rm -f "$tmpfile"
                print_success "WezTerm configured (using cp)" "wezterm_config"
                return 0
            else
                print_error "Failed to update WezTerm config (both mv and cp failed)"
                rm -f "$tmpfile"
                return 1
            fi
        fi
    else
        # No return statement, just append
        if echo "$config_block" >>"$config" 2>/dev/null; then
            : # Success
        else
            print_error "Failed to append to WezTerm config"
            return 1
        fi
    fi

    print_success "WezTerm configured successfully" "wezterm_config"
}

configure_foot() {
    print_step "Configuring Foot..."

    local config="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
    local config_dir
    config_dir="$(dirname "$config")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Foot config directory: $config_dir"
        return 1
    fi
    [[ ! -f "$config" ]] && touch "$config"
    backup_config "$config"

    if grep -qF "Zsh Edit-Select" "$config" 2>/dev/null; then
        print_info "Foot already configured for zsh-edit-select"
        return
    fi

    # Build [key-bindings] entries: unbind defaults that conflict with the plugin
    local kb_block=""
    kb_block+=$'\n# Zsh Edit-Select'
    kb_block+=$'\nclipboard-copy=none'
    kb_block+=$'\nprompt-prev=none'

    # Build [text-bindings] entries: send escape sequences to the shell
    local tb_block=""
    tb_block+=$'\n# Zsh Edit-Select'
    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        tb_block+=$'\n\\x1b[67;6u = Control+c'
        tb_block+=$'\n\\x03 = Control+Shift+c'
    else
        tb_block+=$'\n\\x1b[67;6u = Control+Shift+c'
    fi
    tb_block+=$'\n\\x1b[90;6u = Control+Shift+z'

    # Process the config file: insert into existing sections or append new ones
    local tmpfile
    tmpfile=$(mktemp 2>/dev/null) || {
        print_error "Failed to create temporary file for Foot config"
        print_warning "Please add keybindings manually to foot.ini"
        MANUAL_STEPS+=("Add zsh-edit-select keybindings and text-bindings to foot.ini")
        return 1
    }

    local kb_inserted=0
    local tb_inserted=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        echo "$line" >>"$tmpfile"
        if [[ $kb_inserted -eq 0 ]] && [[ "$line" == "[key-bindings]" ]]; then
            echo "$kb_block" >>"$tmpfile"
            kb_inserted=1
        fi
        if [[ $tb_inserted -eq 0 ]] && [[ "$line" == "[text-bindings]" ]]; then
            echo "$tb_block" >>"$tmpfile"
            tb_inserted=1
        fi
    done <"$config"

    # Append any sections that weren't found in the existing file
    if [[ $kb_inserted -eq 0 ]]; then
        {
            echo ""
            echo "[key-bindings]"
            echo "$kb_block"
        } >>"$tmpfile"
    fi
    if [[ $tb_inserted -eq 0 ]]; then
        {
            echo ""
            echo "[text-bindings]"
            echo "$tb_block"
        } >>"$tmpfile"
    fi

    # Verify temp file has content
    if [[ ! -s "$tmpfile" ]]; then
        print_error "Generated temp file is empty"
        rm -f "$tmpfile"
        return 1
    fi

    chmod --reference="$config" "$tmpfile" 2>/dev/null || chmod 644 "$tmpfile" 2>/dev/null
    if mv "$tmpfile" "$config" 2>/dev/null; then
        print_success "Foot configured successfully" "foot_config"
    else
        # mv failed, try copy as fallback
        if cp "$tmpfile" "$config" 2>/dev/null; then
            rm -f "$tmpfile"
            print_success "Foot configured (using cp)" "foot_config"
        else
            print_error "Failed to update Foot config (both mv and cp failed)"
            rm -f "$tmpfile"
            return 1
        fi
    fi
}

configure_vscode() {
    print_step "Configuring VS Code..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
    local config="$config_dir/keybindings.json"

    # Check for VS Code Insiders or alternative paths if default doesn't exist
    if [[ ! -d "$config_dir" ]]; then
        if [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User" ]]; then
            config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User"
            config="$config_dir/keybindings.json"
        fi
    fi

    if [[ ! -d "$config_dir" ]]; then
        print_info "VS Code configuration directory not found."
        MANUAL_STEPS+=("Configure VS Code keybindings manually (see README)")
        return
    fi

    # Create file if it doesn't exist
    if [[ ! -f "$config" ]]; then
        echo "[]" >"$config"
        print_substep "Created new keybindings.json"
    else
        backup_config "$config"
    fi

    # Check if already configured (look for our specific escape sequences)
    if grep -q "u001b\[90;6u" "$config" 2>/dev/null; then
        print_info "VS Code already configured for zsh-edit-select"
        return
    fi

    # Define keybindings content based on user preference
    local common_bindings
    common_bindings=$(
        cat <<EOF
    {
        "key": "ctrl+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001a" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+z",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[90;6u" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2D" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2C" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+up",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2A" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+down",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2B" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+home",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2H" },
        "when": "terminalFocus"
    },
    {
        "key": "shift+end",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;2F" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+left",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6D" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+right",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6C" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+home",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6H" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+end",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[1;6F" },
        "when": "terminalFocus"
    }
EOF
    )

    local copy_bindings
    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        copy_bindings=$(
            cat <<EOF
    {
        "key": "ctrl+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[67;6u" },
        "when": "terminalFocus"
    },
    {
        "key": "ctrl+shift+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u0003" },
        "when": "terminalFocus"
    }
EOF
        )
    else
        copy_bindings=$(
            cat <<EOF
    {
        "key": "ctrl+shift+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[67;6u" },
        "when": "terminalFocus"
    }
EOF
        )
    fi

    # Use python3 to merge JSON if available (standard on most linux distros)
    if command_exists python3; then
        # Write new bindings to a temp file to avoid shell injection issues
        local bindings_tmpfile
        bindings_tmpfile=$(mktemp 2>/dev/null) || {
            print_warning "Failed to create temp file for VS Code config, using shell fallback"
            bindings_tmpfile=""
        }

        if [[ -n "$bindings_tmpfile" ]]; then
            echo "[$common_bindings, $copy_bindings]" >"$bindings_tmpfile"

            local result
            # Pass filepaths as arguments to Python instead of embedding in code
            result=$(
                python3 - "$config" "$bindings_tmpfile" <<'PYTHON_SCRIPT'
import json, sys

config_file = sys.argv[1]
bindings_file = sys.argv[2]

try:
    with open(config_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = []

    if not isinstance(data, list):
        data = []

    with open(bindings_file, 'r') as f:
        new_bindings = json.load(f)

    data.extend(new_bindings)

    with open(config_file, 'w') as f:
        json.dump(data, f, indent=4)

    print('OK')
except Exception as e:
    print('ERROR: ' + str(e))
PYTHON_SCRIPT
                2>&1
            )
            rm -f "$bindings_tmpfile"

            if [[ "$result" == *"OK"* ]]; then
                print_success "VS Code configured successfully (via Python)" "vscode_config"
                return 0
            else
                print_warning "Python update failed: $result"
                print_warning "Falling back to shell method..."
            fi
        fi
    fi

    # Shell fallback (if Python not available or Python method failed)
    print_info "Using shell fallback for JSON update"

    # Shell fallback (sed/echo)
    if grep -q "^[[:space:]]*\[[[:space:]]*\][[:space:]]*$" "$config" 2>/dev/null; then
        # Empty array - replace with our bindings
        echo "[$common_bindings, $copy_bindings]" >"$config" || {
            print_error "Failed to write VS Code config"
            return 1
        }
    else
        # Non-empty array - need to insert before the closing bracket
        local tmpfile
        tmpfile=$(mktemp 2>/dev/null) || {
            print_error "Cannot create temp file for VS Code config"
            return 1
        }

        local found_closing=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Check if this line contains the closing bracket (possibly with whitespace)
            if [[ "$line" =~ ^[[:space:]]*\][[:space:]]*$ ]] && [[ $found_closing -eq 0 ]]; then
                # Insert comma + new bindings before the closing bracket
                echo ",$common_bindings," >>"$tmpfile"
                echo "$copy_bindings" >>"$tmpfile"
                echo "$line" >>"$tmpfile"
                found_closing=1
            else
                echo "$line" >>"$tmpfile"
            fi
        done <"$config"

        if [[ -f "$tmpfile" ]] && [[ -s "$tmpfile" ]] && [[ $found_closing -eq 1 ]]; then
            mv "$tmpfile" "$config" 2>/dev/null || {
                print_error "Failed to update VS Code config with shell fallback"
                rm -f "$tmpfile"
                return 1
            }
        else
            rm -f "$tmpfile"
            print_warning "Could not properly insert into JSON. Please add bindings manually."
            MANUAL_STEPS+=("Add zsh-edit-select keybindings to VS Code keybindings.json (see README)")
            return 1
        fi
    fi
    print_success "VS Code configured successfully (via Shell fallback)" "vscode_config"
}

configure_windows_terminal() {
    print_step "Configuring Windows Terminal..."

    local config="${WT_SETTINGS_PATH:-}"
    if [[ -z "$config" ]] || [[ ! -f "$config" ]]; then
        if find_windows_terminal_settings >/dev/null; then
            config="$WT_SETTINGS_PATH"
        else
            print_error "Cannot find Windows Terminal settings.json"
            return 1
        fi
    fi

    backup_config "$config"

    # Use Python for robust JSON parsing on WSL
    if ! command_exists python3; then
        print_error "Python 3 is required to modify Windows Terminal settings.json"
        MANUAL_STEPS+=("Add zsh-edit-select settings to Windows Terminal manually (see README)")
        return 1
    fi

    local reversed_copy="False"
    [[ "$USER_WANTS_REVERSED_COPY" == "y" ]] && reversed_copy="True"

    # Python script to update settings.json atomically and format safely
    local update_script
    update_script=$(cat << 'EOF'
import json
import sys
import os
import shutil
import tempfile

def update_json(file_path, reversed_copy):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        # Check if already fully configured
        if data.get('_zes_configured') == True:
            # Need to double check if mode matches preference
            is_reversed = any(a.get('id') == 'User.sendIntr' for a in data.get('actions', []))
            if is_reversed == reversed_copy:
                print("ALREADY_CONFIGURED")
                return 0

        # Mark as configured
        data['_zes_configured'] = True

        # 1. Update copyOnSelect
        data['copyOnSelect'] = False

        # 2. Add/update actions
        if 'actions' not in data:
            data['actions'] = []
            
        actions = data['actions']
        # Remove any existing zsh-edit-select actions
        actions = [a for a in actions if a.get('id') not in ('User.copy.644BA8F2', 'User.sendIntr')]
        
        # Add basic copy action
        actions.append({"command": {"action": "copy", "singleLine": False}, "id": "User.copy.644BA8F2"})
        
        # Add reversed mode action if requested
        if reversed_copy:
            actions.append({"command": {"action": "sendInput", "input": "\u001d"}, "id": "User.sendIntr"})
            
        data['actions'] = actions

        # 3. Add/update keybindings
        if 'keybindings' not in data:
            data['keybindings'] = []
            
        keybindings = data['keybindings']
        # Remove existing zsh-edit-select config keybindings
        keybindings = [k for k in keybindings if k.get('id') not in ('User.copy.644BA8F2', 'User.sendIntr')]
        
        # Add bindings based on mode
        keybindings.append({"id": "User.copy.644BA8F2", "keys": "ctrl+c"})
        if reversed_copy:
            keybindings.append({"id": "User.sendIntr", "keys": "ctrl+shift+c"})
            
        data['keybindings'] = keybindings

        # Write safely to temp file, then replace
        fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(file_path))
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            # Indent handles multiline pretty-printing
            json.dump(data, f, indent=4, ensure_ascii=False)
            
        shutil.move(temp_path, file_path)
        print("SUCCESS")
        return 0
        
    except Exception as e:
        print(f"ERROR: {str(e)}", file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(update_json(sys.argv[1], sys.argv[2] == "True"))
EOF
)

    local result
    result=$(python3 -c "$update_script" "$config" "$reversed_copy" 2>&1)
    local py_status=$?

    if [[ $py_status -ne 0 ]]; then
        print_error "Failed to modify Windows Terminal config."
        log_message "WT_CONFIG_ERROR: $result"
        MANUAL_STEPS+=("Add zsh-edit-select settings to Windows Terminal manually (see README)")
        return 1
    fi

    if [[ "$result" == *"ALREADY_CONFIGURED"* ]]; then
        print_info "Windows Terminal already configured for zsh-edit-select"
    else
        # If successfully configured and reversed copy enabled, ensure stty is in .zshrc
        if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
            local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
            if [[ -f "$zshrc" ]] && ! grep -q "stty intr \^\]" "$zshrc" 2>/dev/null; then
                backup_file "$zshrc"
                echo "" >> "$zshrc"
                echo "# Zsh Edit-Select: Required for WSL reversed copy mode (Ctrl+C to copy, Ctrl+Shift+C to interrupt)" >> "$zshrc"
                echo "stty intr ^]" >> "$zshrc"
                print_substep "Added 'stty intr ^]' to .zshrc for Windows Terminal reversed copy mode"
            fi
        fi
        print_success "Windows Terminal configured successfully" "windows_terminal_config"
    fi
}

# Conflict Detection Functions

check_conflicts() {
    if [[ $SKIP_CONFLICTS -eq 1 ]]; then
        print_info "Skipping conflict detection (--skip-conflicts flag)"
        return
    fi

    print_header "Phase 6: Configuration Conflict Detection"

    print_step "Checking for Zsh keybinding conflicts..."
    check_zsh_conflicts

    print_step "Checking for terminal configuration conflicts..."
    check_terminal_conflicts

    if [[ $TOTAL_CONFLICTS -gt 0 ]]; then
        echo ""
        echo ""
        sleep 0.1

        # Use terminal width for the box (cap 42–78) so it never overflows
        local term_cols box_width
        term_cols=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
        [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80
        [[ "$term_cols" -lt 42 ]] && term_cols=42
        [[ "$term_cols" -gt 78 ]] && term_cols=78
        box_width=$((term_cols - 2)) # -2 for the ║ on each side
        # Use [!] instead of ⚠ (U+26A0): ⚠ is ambiguous-width and renders as
        # 2 columns in many terminals, causing printf padding to be off by 1
        # and the closing ║ to visually overlap the next output line.
        local conflict_msg="  [!] Found $TOTAL_CONFLICTS potential configuration conflict(s)"
        local padded_msg
        padded_msg=$(printf "%-${box_width}s" "$conflict_msg")
        echo -e "${BOLD}${YELLOW}╔$(printf '═%.0s' $(seq 1 $box_width))╗${NC}"
        echo -e "${BOLD}${YELLOW}║${padded_msg}║${NC}"
        echo -e "${BOLD}${YELLOW}╚$(printf '═%.0s' $(seq 1 $box_width))╝${NC}"
        echo ""
        echo -e "${BOLD}Conflict Resolution Guide:${NC}"
        echo ""
        echo -e "  ${CYAN}1.${NC} Review each conflict listed above"
        echo -e "  ${CYAN}2.${NC} Open the affected configuration file(s):"
        for file in "${!CONFLICTS[@]}"; do
            echo -e "     ${BOLD}→${NC} $file"
        done
        echo -e "  ${CYAN}3.${NC} For each conflict, either:"
        echo -e "     • ${GREEN}Remove${NC} the old binding (recommended)"
        echo -e "     • ${GREEN}Comment out${NC} the old binding (add # at the start)"
        echo -e "     • ${GREEN}Remap${NC} the old binding to a different key"
        echo -e "  ${CYAN}4.${NC} Keep the zsh-edit-select bindings for the best experience"
        echo ""
        echo -e "  ${DIM}The zsh-edit-select bindings were already added to your config."
        echo -e "  Conflicting bindings may override them if not resolved.${NC}"
        echo ""
    else
        print_success "No configuration conflicts detected" "conflicts_check"
    fi
}

check_zsh_conflicts() {
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"

    if [[ ! -f "$zshrc" ]]; then
        print_warning ".zshrc not found, skipping Zsh conflict check"
        return
    fi

    # Keybinding patterns that may conflict with zsh-edit-select
    local -a conflict_patterns=(
        'bindkey.*["'"'"']\^C["'"'"']'
        'bindkey.*["'"'"']\^X["'"'"']'
        'bindkey.*["'"'"']\^V["'"'"']'
        'bindkey.*["'"'"']\^Z["'"'"']'
        'bindkey.*["'"'"']\^\[\[3~["'"'"'].*delete-char'
        'bindkey.*["'"'"']\^\[\[1;2["'"'"']'
        'bindkey.*["'"'"']\^\[\[1;5["'"'"']'
        'bindkey.*["'"'"']\^\[\[1;6["'"'"']'
    )

    local found_conflicts=0
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"

        # Skip empty lines and comments
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" =~ ^# ]] && continue

        # Skip lines that are part of zsh-edit-select itself
        [[ "$stripped" =~ zsh-edit-select ]] && continue

        for pattern in "${conflict_patterns[@]}"; do
            if [[ "$stripped" =~ $pattern ]]; then
                print_conflict ".zshrc:$line_num" "$stripped" "zsh-edit-select uses this key"
                found_conflicts=1
            fi
        done
    done <"$zshrc"

    if [[ $found_conflicts -eq 0 ]]; then
        print_success "No Zsh keybinding conflicts found"
    fi
}

check_terminal_conflicts() {
    for terminal in "${DETECTED_TERMINALS[@]}"; do
        local config=""
        case "$terminal" in
        kitty)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
            [[ -f "$config" ]] && check_kitty_conflicts "$config"
            ;;
        alacritty)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
            [[ ! -f "$config" ]] && config="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
            [[ -f "$config" ]] && check_alacritty_conflicts "$config"
            ;;
        wezterm)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
            [[ ! -f "$config" ]] && config="$HOME/.wezterm.lua"
            [[ -f "$config" ]] && check_wezterm_conflicts "$config"
            ;;
        foot)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
            [[ -f "$config" ]] && check_foot_conflicts "$config"
            ;;
        vscode)
            config="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
            [[ ! -f "$config" ]] && config="${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/keybindings.json"
            [[ -f "$config" ]] && check_vscode_conflicts "$config"
            ;;
        windows-terminal)
            check_windows_terminal_conflicts
            ;;
        esac
    done
}

check_kitty_conflicts() {
    local config="$1"
    local line_num=0
    # Track whether we are inside the block our installer wrote.
    # The block starts at the "# Zsh Edit-Select" comment and may contain
    # blank lines, comments, and map directives spread across several
    # paragraphs.  We stay in the section as long as lines are blank,
    # comments, or map directives; anything else means we have left it.
    local in_zes_section=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Detect our section marker
        if [[ "$line" == *"Zsh Edit-Select"* ]]; then
            in_zes_section=1
            continue
        fi

        # If inside our section, stay there for blank lines, comments,
        # and map directives we wrote.  Anything else exits the section.
        if [[ $in_zes_section -eq 1 ]]; then
            local stripped_sec
            stripped_sec="$(strip_line "$line")"
            if [[ -z "${line//[[:space:]]/}" ]] ||
                [[ "$stripped_sec" =~ ^# ]] ||
                [[ "$stripped_sec" =~ ^map ]]; then
                continue
            fi
            in_zes_section=0
        fi

        # Skip blank lines outside our section
        [[ -z "${line//[[:space:]]/}" ]] && continue

        local stripped
        stripped="$(strip_line "$line")"

        # Skip lines that don't look like valid config (length check)
        [[ ${#stripped} -lt 3 || ${#stripped} -gt 200 ]] && continue

        # Skip comment lines
        [[ "$stripped" =~ ^# ]] && continue

        # Flag map lines that conflict with our bindings, but only if they are
        # NOT inside a block we wrote
        if [[ "$stripped" =~ ^map.*(ctrl\+c|ctrl\+shift\+c|ctrl\+shift\+z|ctrl\+shift\+left|ctrl\+shift\+right|ctrl\+shift\+home|ctrl\+shift\+end|shift\+left|shift\+right|shift\+up|shift\+down|shift\+home|shift\+end) ]]; then
            print_conflict "kitty.conf:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
        fi
    done <"$config"
}

check_alacritty_conflicts() {
    local config="$1"
    local is_yaml=0
    [[ "$config" == *.yml ]] && is_yaml=1

    if [[ $is_yaml -eq 1 ]]; then
        # YAML format: look for key-binding lines like  - { key: C, mods: Control|Shift, ... }
        if grep -qE '(key:[[:space:]]*(C|Z|Home|End),)' "$config" 2>/dev/null; then
            local our_section=0
            local line_num=0

            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_num++))
                if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                    our_section=1
                    continue
                fi
                if [[ $our_section -eq 1 ]]; then
                    local stripped
                    stripped="${line#"${line%%[![:space:]]*}"}"
                    stripped="${stripped%"${stripped##*[![:space:]]}"}"
                    # Stay in our section for blank lines, comments, and YAML
                    # binding entries we wrote
                    if [[ -z "$stripped" ]] ||
                        [[ "$stripped" == "#"* ]] ||
                        [[ "$stripped" == "key_bindings:"* ]] ||
                        [[ "$stripped" == "- {"* ]]; then
                        continue
                    fi
                    # Anything else means we've left our section
                    our_section=0
                fi
                if [[ $our_section -eq 0 ]] && [[ "$line" =~ key:[[:space:]]*(C|Z|Home|End), ]]; then
                    print_conflict "alacritty config:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            done <"$config"
        fi
    else
        # TOML format: look for key = "C" or key = "Z" or key = "Home" or key = "End" entries
        if grep -qE 'key.*=.*"(C|Z|Home|End)"' "$config" 2>/dev/null; then
            local our_section=0
            local line_num=0

            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_num++))
                if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                    our_section=1
                    continue
                fi
                if [[ $our_section -eq 1 ]]; then
                    local stripped
                    stripped="${line#"${line%%[![:space:]]*}"}"
                    stripped="${stripped%"${stripped##*[![:space:]]}"}"
                    # Stay in our section for blank lines, comments, and common
                    # TOML keyboard binding entries we wrote
                    if [[ -z "$stripped" ]] ||
                        [[ "$stripped" == "#"* ]] ||
                        [[ "$stripped" == "[[keyboard.bindings]]" ]] ||
                        [[ "$stripped" =~ ^(key|mods|chars|action)[[:space:]]*= ]]; then
                        continue
                    fi
                    # Anything else means we've left our section
                    our_section=0
                fi
                if [[ $our_section -eq 0 ]] && [[ "$line" =~ key.*=.*\"(C|Z|Home|End)\" ]]; then
                    print_conflict "alacritty config:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            done <"$config"
        fi
    fi
}

check_wezterm_conflicts() {
    local config="$1"

    # Check for conflicting WezTerm keybindings (Lua format)
    # Our bindings use key = 'C'/'Z'/'c' with CTRL|SHIFT or CTRL modifiers,
    # and LeftArrow/RightArrow with DisableDefaultAssignment
    if grep -qE "(key.*=.*['\"][CZcz]['\"]|DisableDefaultAssignment)" "$config" 2>/dev/null; then
        local our_section=0
        local line_num=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_num++))
            if [[ "$line" =~ "Zsh Edit-Select" ]]; then
                our_section=1
                continue
            fi
            if [[ $our_section -eq 1 ]]; then
                local stripped
                stripped="${line#"${line%%[![:space:]]*}"}"
                stripped="${stripped%"${stripped##*[![:space:]]}"}"
                # Stay in our section for blank lines, comments, and Lua
                # keybinding entries we wrote
                if [[ -z "$stripped" ]] ||
                    [[ "$stripped" == "--"* ]] ||
                    [[ "$stripped" == "config.keys"* ]] ||
                    [[ "$stripped" == "local zes_keys"* ]] ||
                    [[ "$stripped" == "{"* ]] ||
                    [[ "$stripped" == "}"* ]] ||
                    [[ "$stripped" == "for "* ]] ||
                    [[ "$stripped" == "end" ]]; then
                    continue
                fi
                # Anything else means we've left our section
                our_section=0
            fi
            if [[ $our_section -eq 0 ]]; then
                # Check for key bindings that conflict with ours (C/Z with Ctrl modifiers)
                if [[ "$line" =~ key.*=.*[\'\"](C|c|Z|z)[\'\"].*CTRL ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]LeftArrow[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]RightArrow[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]Home[\'\"].*CTRL.*SHIFT ]] ||
                    [[ "$line" =~ key.*=.*[\'\"]End[\'\"].*CTRL.*SHIFT ]]; then
                    print_conflict "wezterm.lua:$line_num" "$(strip_line "$line")" "May conflict with zsh-edit-select bindings"
                fi
            fi
        done <"$config"
    fi
}

check_foot_conflicts() {
    local config="$1"

    # Check for conflicting key-bindings and text-bindings section entries
    local in_keybindings=0
    local in_textbindings=0
    local line_num=0
    local our_section=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue

        if [[ "$stripped" == *"Zsh Edit-Select"* ]]; then
            our_section=1
            continue
        fi
        if [[ $our_section -eq 1 ]] && [[ "$stripped" =~ ^\[ ]]; then
            our_section=0
        fi

        if [[ "$stripped" == "[key-bindings]" ]]; then
            in_keybindings=1
            in_textbindings=0
            continue
        fi
        if [[ "$stripped" == "[text-bindings]" ]]; then
            in_textbindings=1
            in_keybindings=0
            continue
        fi
        if [[ "$stripped" =~ ^\[ ]] && [[ "$stripped" != "[key-bindings]" ]] && [[ "$stripped" != "[text-bindings]" ]]; then
            in_keybindings=0
            in_textbindings=0
        fi

        if [[ $our_section -eq 0 ]]; then
            if [[ $in_keybindings -eq 1 ]]; then
                if [[ "$stripped" =~ ^(clipboard-copy|prompt-prev)= ]]; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select bindings"
                fi
            fi
            if [[ $in_textbindings -eq 1 ]]; then
                if [[ "$stripped" == *"Control+Shift+c"* ]] || [[ "$stripped" == *"Control+Shift+z"* ]]; then
                    print_conflict "foot.ini:$line_num" "$stripped" "May conflict with zsh-edit-select text-bindings"
                fi
            fi
        fi
    done <"$config"
}

check_vscode_conflicts() {
    local config="$1"
    local line_num=0

    # VS Code keybindings.json is a JSON array of objects.
    # Each object spans multiple lines: { "key": ..., "command": ..., "args": ..., "when": ... }
    # We collect each object's lines, then check the full object to decide
    # whether it belongs to us (contains "Zsh Edit-Select" or our escape
    # sequences) BEFORE flagging any "key" line as a conflict.
    local -a obj_lines=()
    local -a obj_line_nums=()
    local brace_depth=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local stripped
        stripped="$(strip_line "$line")"
        [[ -z "$stripped" ]] && continue

        # Track JSON object boundaries
        if [[ "$stripped" == "{"* ]]; then
            ((brace_depth++))
            obj_lines=()
            obj_line_nums=()
        fi

        if [[ $brace_depth -gt 0 ]]; then
            obj_lines+=("$stripped")
            obj_line_nums+=("$line_num")
        fi

        if [[ "$stripped" == *"}"* ]] && [[ $brace_depth -gt 0 ]]; then
            ((brace_depth--))
            if [[ $brace_depth -eq 0 ]]; then
                # We have a complete JSON object — check it
                local obj_text="${obj_lines[*]}"

                # Skip objects that belong to our installer.
                # configure_vscode() writes sendSequence bindings with specific
                # ZES escape sequences.  VS Code JSON has no comment syntax, so
                # we identify our objects by their "text" payload.  We require
                # BOTH "sendSequence" (so a binding to the right key but the
                # wrong command is still flagged) AND one of our known sequences.
                local skip_obj=0
                if [[ "$obj_text" == *"Zsh Edit-Select"* ]]; then
                    skip_obj=1
                elif [[ "$obj_text" == *"sendSequence"* ]]; then
                    # Each sequence below corresponds to a value written by configure_vscode():
                    #   67;6u  → Ctrl+Shift+C copy (CSI u)
                    #   90;6u  → Ctrl+Shift+Z redo (CSI u)
                    #   1;2D/C/A/B → Shift+Left/Right/Up/Down
                    #   1;2H/F → Shift+Home/End
                    #   1;6D/C → Ctrl+Shift+Left/Right
                    #   1;6H/F → Ctrl+Shift+Home/End
                    #   u001a  → Ctrl+Z undo (\u001a)
                    #   u0003  → Ctrl+C interrupt (\u0003)
                    if [[ "$obj_text" == *"67;6u"* ]] ||
                        [[ "$obj_text" == *"90;6u"* ]] ||
                        [[ "$obj_text" == *"1;2D"* ]] ||
                        [[ "$obj_text" == *"1;2C"* ]] ||
                        [[ "$obj_text" == *"1;2A"* ]] ||
                        [[ "$obj_text" == *"1;2B"* ]] ||
                        [[ "$obj_text" == *"1;2H"* ]] ||
                        [[ "$obj_text" == *"1;2F"* ]] ||
                        [[ "$obj_text" == *"1;6D"* ]] ||
                        [[ "$obj_text" == *"1;6C"* ]] ||
                        [[ "$obj_text" == *"1;6H"* ]] ||
                        [[ "$obj_text" == *"1;6F"* ]] ||
                        [[ "$obj_text" == *"u001a"* ]] ||
                        [[ "$obj_text" == *"u0003"* ]]; then
                        skip_obj=1
                    fi
                fi
                if [[ $skip_obj -eq 1 ]]; then
                    obj_lines=()
                    obj_line_nums=()
                    continue
                fi

                # Check if any line in this object has a conflicting "key"
                local idx
                for idx in "${!obj_lines[@]}"; do
                    local obj_stripped="${obj_lines[$idx]}"
                    if [[ "$obj_stripped" =~ \"key\" ]]; then
                        local lower_obj="${obj_stripped,,}"
                        if [[ "$lower_obj" == *"ctrl+shift+c"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+z"* ]] ||
                            [[ "$lower_obj" == *"ctrl+z"* ]] ||
                            [[ "$lower_obj" == *"shift+left"* ]] ||
                            [[ "$lower_obj" == *"shift+right"* ]] ||
                            [[ "$lower_obj" == *"shift+up"* ]] ||
                            [[ "$lower_obj" == *"shift+down"* ]] ||
                            [[ "$lower_obj" == *"shift+home"* ]] ||
                            [[ "$lower_obj" == *"shift+end"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+left"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+right"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+home"* ]] ||
                            [[ "$lower_obj" == *"ctrl+shift+end"* ]]; then
                            print_conflict "keybindings.json:${obj_line_nums[$idx]}" "$obj_stripped" "May conflict with zsh-edit-select bindings"
                        fi
                    fi
                done
                obj_lines=()
                obj_line_nums=()
            fi
        fi
    done <"$config"
}

check_windows_terminal_conflicts() {
    local config="$WT_SETTINGS_PATH"
    if [[ -z "$config" ]] || [[ ! -f "$config" ]]; then
        return
    fi
    
    # Conflict: if they already have ctrl+c mapped to something else that we didn't add
    if grep -qi "\"keys\":.*\"ctrl+c\"" "$config" 2>/dev/null; then
        if ! grep -q "\"id\":.*\"User.copy.644BA8F2\"" "$config" 2>/dev/null; then
            # This isn't perfect since JSON is multi-line, but grep works for basic sanity
            print_conflict "Windows Terminal" "ctrl+c binding" "Custom ctrl+c binding found that may conflict with zsh-edit-select's copy action"
        fi
    fi
    
    # Check for other terminal copy shortcuts that might conflict with reversed mode
    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        if grep -qi "\"keys\":.*\"ctrl+shift+c\"" "$config" 2>/dev/null; then
            if ! grep -q "\"id\":.*\"User.sendIntr\"" "$config" 2>/dev/null; then
                print_conflict "Windows Terminal" "ctrl+shift+c binding" "Existing ctrl+shift+c binding conflicts with reversed copy interrupt mode"
            fi
        fi
    fi
}

# Verification Functions

verify_installation() {
    if [[ $SKIP_VERIFY -eq 1 ]]; then
        print_info "Skipping post-installation verification (--skip-verify flag)"
        return
    fi

    print_header "Phase 7: Installation Verification"

    verify_plugin_files
    verify_zshrc_config
    verify_dependencies
    verify_monitor_daemons
    verify_terminal_config
    verify_plugin_loads          # Test that plugin actually loads
    verify_terminal_capabilities # Test terminal supports required escape sequences

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

    # Compiler
    if command_exists gcc || command_exists clang; then
        test_pass "C compiler available"
    else
        test_fail "C compiler not found" "Install gcc or clang"
    fi

    # Make
    if command_exists make; then
        test_pass "Make build system available"
    else
        test_fail "Make not found" "Install make"
    fi

    # pkg-config
    if command_exists pkg-config; then
        test_pass "pkg-config available"
    else
        test_warning "pkg-config not found" "May affect build process"
    fi

    # Display server tools
    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        if command_exists xclip; then
            test_pass "xclip available (fallback clipboard tool)"
        else
            test_warning "xclip not found" "Custom agent will be required"
        fi
    elif [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        if command_exists wl-copy && command_exists wl-paste; then
            test_pass "wl-clipboard available (fallback clipboard tool)"
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

    if [[ "$DETECTED_DISPLAY_SERVER" == "x11" ]]; then
        local monitor_binary="$PLUGIN_INSTALL_DIR/impl-x11/backends/x11/zes-x11-selection-agent"

        if [[ -x "$monitor_binary" ]]; then
            test_pass "X11 agent built and executable"
        else
            test_fail "X11 agent not found or not executable" "Check build process"
        fi
    elif [[ "$DETECTED_DISPLAY_SERVER" == "wayland" ]]; then
        local monitor_binary="$PLUGIN_INSTALL_DIR/impl-wayland/backends/wayland/zes-wl-selection-agent"

        if [[ -x "$monitor_binary" ]]; then
            test_pass "Wayland agent built and executable"
        else
            test_fail "Wayland agent not found or not executable" "Check build process"
        fi

        local xwayland_binary="$PLUGIN_INSTALL_DIR/impl-wayland/backends/xwayland/zes-xwayland-agent"
        if [[ -x "$xwayland_binary" ]]; then
            test_pass "XWayland clipboard agent built (optional)"
        else
            test_warning "XWayland agent not built" "Optional component"
        fi
    fi
}

verify_terminal_config() {
    print_step "Verifying terminal configurations..."

    for terminal in "${DETECTED_TERMINALS[@]}"; do
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
        code | vscode)
            # VS Code JSON has no comment syntax, so we cannot embed a
            # "Zsh Edit-Select" marker.  Instead detect any of the
            # escape sequences configure_vscode() always writes:
            #   90;6u  = Ctrl+Shift+Z redo  (always present in common_bindings)
            #   67;6u  = Ctrl+Shift+C copy  (present in default mode)
            #   1;2D   = Shift+Left         (always present in common_bindings)
            local vscode_found=0
            local vscode_dir
            for vscode_dir in \
                "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" \
                "$HOME/.config/Code/User" \
                "$HOME/.config/Code - OSS/User" \
                "$HOME/.config/Code - Insiders/User"; do
                local kb="$vscode_dir/keybindings.json"
                if [[ -f "$kb" ]] &&
                    grep -qE '(90;6u|67;6u|1;2D)' "$kb" 2>/dev/null; then
                    test_pass "VS Code configured"
                    vscode_found=1
                    break
                fi
            done
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
        [kitty]=1 [alacritty]=1 [wezterm]=1 [foot]=1 [vscode]=1
        [konsole]=1 [vte - based]=1
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
    echo -e "     • Press ${CYAN}Ctrl+C${NC} (or ${CYAN}Ctrl+Shift+C${NC}) to copy"
    echo ""
    echo -e "  ${BOLD}3. Customize settings (optional)${NC}"
    echo -e "     Run: ${CYAN}edit-select config${NC}"
    echo ""
    echo -e "  ${BOLD}4. View full documentation${NC}"
    echo -e "     See: $PLUGIN_INSTALL_DIR/README.md"
    echo -e "     Or visit: https://github.com/Michael-Matta1/zsh-edit-select"
    echo ""

    echo -e "${BOLD}${CYAN}Installation Statistics:${NC}"
    echo "  • Time elapsed:    ${duration}s"
    echo "  • Tests passed:    $PASSED_TESTS"
    echo "  • Tests failed:    $FAILED_TESTS"
    echo "  • Warnings:        $WARNING_TESTS"
    echo ""

    if [[ ${#FAILED_STEPS[@]} -eq 0 ]] && [[ ${#MANUAL_STEPS[@]} -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}  ║                                                        ║${NC}"
        echo -e "${GREEN}${BOLD}  ║    ✓ Installation Completed Successfully!              ║${NC}"
        echo -e "${GREEN}${BOLD}  ║                                                        ║${NC}"
        echo -e "${GREEN}${BOLD}  ║    Enjoy modern text editing in your shell!            ║${NC}"
        echo -e "${GREEN}${BOLD}  ║                                                        ║${NC}"
        echo -e "${GREEN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
        echo ""

        print_info "IMPORTANT: Please restart your terminal session for changes to take effect."
        print_info "If issues persist, a system reboot may be required."
    else
        echo ""
        echo -e "${YELLOW}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}${BOLD}  ║                                                        ║${NC}"
        echo -e "${YELLOW}${BOLD}  ║    ⚠ Installation Completed with Warnings              ║${NC}"
        echo -e "${YELLOW}${BOLD}  ║                                                        ║${NC}"
        echo -e "${YELLOW}${BOLD}  ║    Please review the manual steps above.               ║${NC}"
        echo -e "${YELLOW}${BOLD}  ║                                                        ║${NC}"
        echo -e "${YELLOW}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
        echo ""

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
        --help | -h)
            cat <<EOF
Zsh Edit-Select — Automated Installation Script v$SCRIPT_VERSION

Usage: bash auto-install.sh [OPTIONS]

Options:
  --skip-deps         Skip dependency installation
  --skip-verify       Skip post-installation verification
  --skip-conflicts    Skip conflict detection
  --non-interactive   Run without user prompts (use defaults)
  --test-mode         Allow running as root (for testing only)
  --help, -h          Show this help message

Examples:
  bash auto-install.sh
      Run standard interactive installation

  bash auto-install.sh --non-interactive
      Run completely automated installation using defaults

  bash auto-install.sh --skip-deps --skip-verify
      Install plugin only, skipping system dependencies and verification

  bash auto-install.sh --skip-conflicts
      Install but do not check for keybinding conflicts

This script will:
  • Detect your system environment automatically
  • Install required dependencies
  • Install and configure the plugin
  • Configure your terminal emulator(s)
  • Build agents
  • Check for configuration conflicts
  • Verify the installation
  • Provide a detailed summary
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
    detect_display_server
    detect_linux_distro
    detect_plugin_manager
    detect_terminals

    # Phase 2: Dependencies
    print_header "Phase 2: Dependency Installation"
    install_dependencies

    # Phase 2.1: Offer Kitty installation (after deps, before terminal config)
    offer_kitty_installation

    # Phase 2.5: User Preferences
    ask_user_preferences
    ask_backup_preference

    # Phase 3: Plugin Installation
    print_header "Phase 3: Plugin Installation"
    install_plugin

    # Phase 4: Agents
    build_monitor_daemons

    # Phase 5: Terminal Configuration
    configure_terminals

    # Phase 6: Conflict Detection
    check_conflicts

    # Phase 7: Verification
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
    check_zsh_installed
    check_essential_commands
    acquire_lock

    # Detection
    print_header "Phase 1: System Detection"
    detect_display_server
    detect_linux_distro
    detect_terminals

    # If no terminals detected, inform user
    if [[ ${#DETECTED_TERMINALS[@]} -eq 0 ]]; then
        print_warning "No terminal emulators detected"
        print_info "Please ensure you have a supported terminal installed"
        generate_summary
        return
    fi

    # User preferences
    print_header "Phase 2: Configuration Preferences"
    ask_user_preferences
    ask_backup_preference

    # Terminal configuration
    print_header "Phase 3: Terminal Configuration"
    configure_terminals

    # Conflict detection - helpful to see if configuration was successful
    print_header "Phase 4: Configuration Verification"
    check_conflicts

    generate_summary
}

run_conflict_check_only() {
    print_header "Conflict Detection Mode"

    # Init checks
    check_zsh_installed
    check_essential_commands

    # Detection
    print_header "Phase 1: System Detection"
    detect_display_server
    detect_linux_distro
    detect_plugin_manager # Helps identify plugin files to exclude from conflict checks
    detect_terminals

    # Conflict checking
    print_header "Phase 2: Conflict Detection"
    check_conflicts

    # Summary
    generate_summary
}

run_plugin_update() {
    print_header "Plugin Update Mode"

    # Init
    check_essential_commands
    acquire_lock

    # Detect plugin location
    print_step "Detecting plugin installation..."
    detect_plugin_manager

    if [[ -z "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Could not determine plugin installation directory"
        print_info "Plugin manager detection failed. Please run Full Install first."
        generate_summary
        return
    fi

    if [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory does not exist: $PLUGIN_INSTALL_DIR"
        print_info "Please run Full Install to install the plugin first."
        generate_summary
        return
    fi

    # Check if it's a git repository
    if [[ ! -d "$PLUGIN_INSTALL_DIR/.git" ]]; then
        print_error "Plugin directory is not a git repository: $PLUGIN_INSTALL_DIR"
        print_info "The plugin may have been installed manually or is corrupted."
        print_info "Recommendation: Run Full Install to reinstall from git."
        generate_summary
        return
    fi

    # Update the plugin
    print_step "Updating plugin at $PLUGIN_INSTALL_DIR..."

    # Check for network connectivity before attempting pull
    if ! check_network_connectivity; then
        print_error "No network connectivity - cannot update plugin"
        print_info "Please check your internet connection and try again."
        generate_summary
        return
    fi

    # Stash any local changes to prevent merge conflicts
    local had_changes=0
    # git diff --quiet returns 0 (success) if there are NO changes
    # Returns non-zero if there ARE changes
    if git -C "$PLUGIN_INSTALL_DIR" diff --quiet 2>/dev/null &&
        git -C "$PLUGIN_INSTALL_DIR" diff --cached --quiet 2>/dev/null; then
        : # No changes - both diff commands succeeded (returned 0)
    else
        had_changes=1
        print_warning "Local changes detected, stashing them before update..."
        git -C "$PLUGIN_INSTALL_DIR" stash push -m "Auto-stash before installer update" 2>&1 | tee -a "$LOG_FILE"
    fi

    # Perform the update (capture output to avoid tee masking git exit status)
    local pull_output
    if pull_output=$(git -C "$PLUGIN_INSTALL_DIR" pull --rebase 2>&1); then
        echo "$pull_output" | tee -a "$LOG_FILE"
        print_success "Plugin updated successfully" "plugin_update"

        # Restore stashed changes if any
        if [[ $had_changes -eq 1 ]]; then
            print_info "Restoring local changes..."
            local stash_output
            if stash_output=$(git -C "$PLUGIN_INSTALL_DIR" stash pop 2>&1); then
                echo "$stash_output" | tee -a "$LOG_FILE"
                print_success "Local changes restored"
            else
                echo "$stash_output" | tee -a "$LOG_FILE"
                print_warning "Could not restore local changes automatically"
                print_info "Your changes are saved in stash: git -C $PLUGIN_INSTALL_DIR stash list"
            fi
        fi

        # Detect display server for monitor builds
        detect_display_server

        # Re-build monitors in case C code changed
        print_header "Rebuilding Agents"
        build_monitor_daemons
    else
        echo "$pull_output" | tee -a "$LOG_FILE"
        print_error "Failed to update plugin" "plugin_update"
        print_info "Check the log file for details: $LOG_FILE"

        # Try to recover from failed pull
        print_info "Attempting to reset to remote state..."
        local fetch_output reset_output
        local default_branch
        default_branch=$(git -C "$PLUGIN_INSTALL_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        default_branch="${default_branch:-main}"
        if fetch_output=$(git -C "$PLUGIN_INSTALL_DIR" fetch origin 2>&1) &&
            reset_output=$(git -C "$PLUGIN_INSTALL_DIR" reset --hard "origin/$default_branch" 2>&1); then
            echo "$fetch_output" | tee -a "$LOG_FILE"
            echo "$reset_output" | tee -a "$LOG_FILE"
            print_success "Reset to remote state successful"

            # Re-build monitors
            detect_display_server
            build_monitor_daemons
        else
            [[ -n "${fetch_output:-}" ]] && echo "$fetch_output" | tee -a "$LOG_FILE"
            [[ -n "${reset_output:-}" ]] && echo "$reset_output" | tee -a "$LOG_FILE"
            print_error "Could not recover from failed update"
            print_info "Manual intervention required. Consider reinstalling the plugin."
        fi
    fi

    generate_summary
}

run_build_agents_only() {
    print_header "Build Agents Mode"

    # Init
    check_essential_commands
    acquire_lock

    # Detection
    print_header "Phase 1: System Detection"
    detect_display_server
    detect_linux_distro
    detect_plugin_manager

    if [[ -z "$PLUGIN_INSTALL_DIR" ]] || [[ ! -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin directory not found: ${PLUGIN_INSTALL_DIR:-<not set>}"
        print_info "Please run Full Install first to install the plugin."
        generate_summary
        return
    fi

    # Check for build tools
    print_header "Phase 2: Checking Build Tools"
    local missing=()
    if ! command_exists gcc && ! command_exists clang; then missing+=("gcc/clang"); fi
    if ! command_exists make; then missing+=("make"); fi
    if ! command_exists pkg-config; then missing+=("pkg-config"); fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing build tools: ${missing[*]}"
        print_info "Install them using your package manager before building agents."
        FAILED_STEPS["build_tools"]="Missing: ${missing[*]}"
        generate_summary
        return
    fi

    # Build agents
    print_header "Phase 3: Building Agents"
    build_monitor_daemons

    generate_summary
}

run_uninstall() {
    print_header "Uninstall Mode"
    acquire_lock
    echo ""
    print_warning "This will remove zsh-edit-select from your system."
    echo ""

    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        if ! ask_yes_no "Are you sure you want to uninstall zsh-edit-select?" "n"; then
            print_info "Uninstall cancelled."
            return
        fi
    fi

    # Detect where the plugin is installed
    print_step "Detecting plugin installation..."
    detect_plugin_manager

    local uninstall_success=0

    # Step 1: Kill running agents
    print_step "Stopping running agents..."
    local agents=("zes-x11-selection-agent" "zes-wl-selection-agent" "zes-xwayland-agent")
    for agent in "${agents[@]}"; do
        if pgrep -f "$agent" &>/dev/null; then
            pkill -f "$agent" 2>/dev/null && print_success "Stopped $agent" || print_warning "Could not stop $agent"
        fi
    done

    # Step 2: Remove plugin directory
    if [[ -n "$PLUGIN_INSTALL_DIR" ]] && [[ -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_step "Removing plugin directory: $PLUGIN_INSTALL_DIR"

        # Safety checks
        if [[ "$PLUGIN_INSTALL_DIR" == "/" ]] || [[ "$PLUGIN_INSTALL_DIR" == "$HOME" ]] ||
            [[ "$PLUGIN_INSTALL_DIR" == "$HOME/" ]] || [[ ! "$PLUGIN_INSTALL_DIR" == *"zsh-edit-select"* ]]; then
            print_error "Refusing to remove unsafe path: $PLUGIN_INSTALL_DIR"
        else
            if ask_yes_no "Remove plugin directory $PLUGIN_INSTALL_DIR?" "y"; then
                if rm -rf "$PLUGIN_INSTALL_DIR" 2>/dev/null; then
                    print_success "Plugin directory removed" "uninstall_plugin_dir"
                    ((uninstall_success++))
                else
                    print_error "Failed to remove plugin directory"
                    FAILED_STEPS["uninstall_plugin_dir"]="Could not remove $PLUGIN_INSTALL_DIR"
                fi
            else
                print_info "Skipped removing plugin directory"
            fi
        fi
    else
        print_warning "Plugin directory not found or not set"
    fi

    # Step 3: Remove zshrc entries
    local zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    if [[ -f "$zshrc" ]]; then
        print_step "Cleaning .zshrc..."

        if grep -qF "zsh-edit-select" "$zshrc" 2>/dev/null; then
            backup_file "$zshrc"

            # First: clean the Oh My Zsh plugins array (remove just the plugin name, keep the line)
            if grep -q "plugins=.*zsh-edit-select" "$zshrc" 2>/dev/null; then
                sed_inplace '/^[[:space:]]*plugins=/s/[[:space:]]zsh-edit-select[[:space:]]/ /g; /^[[:space:]]*plugins=/s/(zsh-edit-select[[:space:]]/(/' "$zshrc"
                # Clean up extra spaces in plugins array (only on plugins= lines)
                sed_inplace '/^[[:space:]]*plugins=/s/  */ /g' "$zshrc"
                # Clean up "( " or " )" left by removed plugin name (only on plugins= lines)
                sed_inplace '/^[[:space:]]*plugins=/s/( /(/g; /^[[:space:]]*plugins=/s/ )/)/g' "$zshrc"
                print_success "Removed from Oh My Zsh plugins array"
            fi

            # Second: remove standalone lines referencing zsh-edit-select
            # (source lines, zinit/antigen lines, comments, etc.)
            # But NOT the plugins=(...) line which we already cleaned above
            local tmp_zshrc
            tmp_zshrc=$(mktemp) || {
                print_error "Failed to create temp file for .zshrc cleanup"
                FAILED_STEPS["uninstall_zshrc"]="Temp file creation failed"
            }

            if [[ -n "$tmp_zshrc" ]]; then
                while IFS= read -r line || [[ -n "$line" ]]; do
                    # Keep lines that are part of the plugins=(…) array
                    if [[ "$line" =~ ^[[:space:]]*plugins= ]]; then
                        echo "$line" >>"$tmp_zshrc"
                        continue
                    fi
                    # Skip lines that reference zsh-edit-select (source, zinit, etc.)
                    if [[ "$line" == *"zsh-edit-select"* ]]; then
                        continue
                    fi
                    # Skip orphan "# Zsh Edit-Select" comments (with or without suffix)
                    if [[ "$line" == "# Zsh Edit-Select"* ]]; then
                        continue
                    fi
                    echo "$line" >>"$tmp_zshrc"
                done <"$zshrc"

                chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null
                if mv "$tmp_zshrc" "$zshrc" 2>/dev/null; then
                    print_success "Removed plugin entries from .zshrc" "uninstall_zshrc"
                    ((uninstall_success++))
                else
                    print_error "Failed to update .zshrc"
                    rm -f "$tmp_zshrc"
                    FAILED_STEPS["uninstall_zshrc"]="Could not write to $zshrc"
                fi
            fi
        else
            print_info "No zsh-edit-select entries found in .zshrc"
        fi
    fi

    # Step 4: Remove terminal config entries
    print_step "Cleaning terminal configurations..."
    local -a terminal_configs=(
        "${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
        "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
        "${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
        "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
        "$HOME/.wezterm.lua"
        "${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
    )

    for config_file in "${terminal_configs[@]}"; do
        if [[ -f "$config_file" ]] && grep -qF "Zsh Edit-Select" "$config_file" 2>/dev/null; then
            local basename_file
            basename_file=$(basename "$config_file")
            if ask_yes_no "Remove zsh-edit-select config from $basename_file?" "y"; then
                backup_file "$config_file"

                # Remove the block between "# Zsh Edit-Select" / "-- Zsh Edit-Select" marker
                # and the next empty line or section marker
                local tmp_config
                tmp_config=$(mktemp) || {
                    print_error "Failed to create temp file for $basename_file"
                    continue
                }

                local in_our_section=0
                local empty_line_buffer=""
                while IFS= read -r line || [[ -n "$line" ]]; do
                    if [[ "$line" == *"Zsh Edit-Select"* ]]; then
                        in_our_section=1
                        empty_line_buffer=""
                        continue
                    fi
                    if [[ $in_our_section -eq 1 ]]; then
                        local stripped
                        stripped="$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

                        # Buffer empty lines instead of skipping them outright
                        if [[ -z "$stripped" ]]; then
                            empty_line_buffer+=$'\n'
                            continue
                        fi

                        # Check if it looks like a line we added
                        if [[ "$stripped" == "map "* ]] || [[ "$stripped" == "# Copy"* ]] ||
                            [[ "$stripped" == "# Ctrl+"* ]] || [[ "$stripped" == "# Redo"* ]] ||
                            [[ "$stripped" == "# Disable"* ]] || [[ "$stripped" == "# Pass"* ]] ||
                            [[ "$stripped" == "# (overrides"* ]] ||
                            [[ "$stripped" == "map ctrl+"* ]] ||
                            [[ "$stripped" == "map shift+"* ]] || [[ "$stripped" == "[[keyboard"* ]] ||
                            [[ "$stripped" == "key ="* ]] || [[ "$stripped" == "mods ="* ]] ||
                            [[ "$stripped" == "chars ="* ]] || [[ "$stripped" == "action ="* ]] ||
                            [[ "$stripped" == "key_bindings:"* ]] ||
                            [[ "$stripped" == "- {"* ]] || [[ "$stripped" == "config.keys"* ]] ||
                            [[ "$stripped" == "local zes_keys"* ]] || [[ "$stripped" == "for _, k"* ]] ||
                            [[ "$stripped" == "{"* && "$stripped" == *"SendString"* ]] ||
                            [[ "$stripped" == "{"* && "$stripped" == *"DisableDefault"* ]] ||
                            [[ "$stripped" == "}" ]] || [[ "$stripped" == "end" ]] ||
                            [[ "$stripped" == "-- "* ]] ||
                            [[ "$stripped" == "clipboard-copy="* ]] ||
                            [[ "$stripped" == "prompt-prev="* ]] ||
                            [[ "$stripped" == "\\x1b["* ]] ||
                            [[ "$stripped" == "\\x03"* ]]; then
                            # Still our config — discard buffered empty lines and skip
                            empty_line_buffer=""
                            continue
                        fi

                        # Not our line — output buffered empty lines and exit section
                        in_our_section=0
                        if [[ -n "$empty_line_buffer" ]]; then
                            printf '%s' "$empty_line_buffer" >>"$tmp_config"
                        fi
                        empty_line_buffer=""
                        echo "$line" >>"$tmp_config"
                    else
                        echo "$line" >>"$tmp_config"
                    fi
                done <"$config_file"

                chmod --reference="$config_file" "$tmp_config" 2>/dev/null
                if mv "$tmp_config" "$config_file" 2>/dev/null; then
                    print_success "Cleaned $basename_file" "uninstall_$basename_file"
                    ((uninstall_success++))
                else
                    print_error "Failed to update $basename_file"
                    rm -f "$tmp_config"
                fi
            fi
        fi
    done

    # Step 5: VS Code keybindings (special handling for JSON)
    local vscode_config="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/keybindings.json"
    if [[ ! -f "$vscode_config" ]]; then
        vscode_config="${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/keybindings.json"
    fi
    if [[ -f "$vscode_config" ]] && grep -q "Zsh Edit-Select\|90;6u\|67;6u" "$vscode_config" 2>/dev/null; then
        backup_file "$vscode_config"
        # Try auto-removal with Python (same approach as configure_vscode)
        if command_exists python3; then
            local result
            result=$(
                python3 - "$vscode_config" <<'PYTHON_UNINSTALL'
import json, sys

config_file = sys.argv[1]
try:
    with open(config_file, 'r') as f:
        data = json.load(f)

    if not isinstance(data, list):
        print('SKIP')
        sys.exit(0)

    # Remove entries that contain our escape sequences or marker
    markers = ['67;6u', '90;6u', 'Zsh Edit-Select']
    filtered = []
    for entry in data:
        entry_str = json.dumps(entry)
        if not any(m in entry_str for m in markers):
            filtered.append(entry)

    removed = len(data) - len(filtered)
    if removed > 0:
        with open(config_file, 'w') as f:
            json.dump(filtered, f, indent=4)
        print('REMOVED:' + str(removed))
    else:
        print('NONE')
except Exception as e:
    print('ERROR:' + str(e))
PYTHON_UNINSTALL
                2>&1
            )
            if [[ "$result" == REMOVED:* ]]; then
                local count="${result#REMOVED:}"
                print_success "Removed $count VS Code keybinding(s)" "uninstall_vscode"
                ((uninstall_success++))
            elif [[ "$result" == "NONE" ]] || [[ "$result" == "SKIP" ]]; then
                print_info "No zsh-edit-select VS Code keybindings found to remove"
            else
                print_warning "Auto-removal failed: $result"
                print_info "Please remove entries manually from: $vscode_config"
                MANUAL_STEPS+=("Remove zsh-edit-select keybindings from VS Code: $vscode_config")
            fi
        else
            print_info "VS Code keybindings contain zsh-edit-select entries."
            print_info "Please remove them manually from: $vscode_config"
            print_info "Look for entries containing '67;6u' or '90;6u' escape sequences."
            MANUAL_STEPS+=("Remove zsh-edit-select keybindings from VS Code: $vscode_config")
        fi
    fi

    # Step 6: Remove config directory
    local plugin_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select"
    if [[ -d "$plugin_config_dir" ]]; then
        if ask_yes_no "Remove plugin configuration directory ($plugin_config_dir)?" "y"; then
            rm -rf "$plugin_config_dir" 2>/dev/null && {
                print_success "Plugin config directory removed" "uninstall_config_dir"
                ((uninstall_success++))
            } || {
                print_error "Failed to remove plugin config directory"
            }
        fi
    fi

    # Step 7: Remove Sheldon config entry if applicable
    local sheldon_config="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
    if [[ -f "$sheldon_config" ]] && grep -qF "zsh-edit-select" "$sheldon_config" 2>/dev/null; then
        backup_file "$sheldon_config"
        # Remove the plugin section
        local tmp_sheldon
        tmp_sheldon=$(mktemp) || true
        if [[ -n "$tmp_sheldon" ]]; then
            local in_section=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" == "[plugins.zsh-edit-select]" ]]; then
                    in_section=1
                    continue
                fi
                if [[ $in_section -eq 1 ]]; then
                    if [[ "$line" == "["* ]] && [[ "$line" != "[plugins.zsh-edit-select]" ]]; then
                        in_section=0
                        echo "$line" >>"$tmp_sheldon"
                    fi
                    continue
                fi
                echo "$line" >>"$tmp_sheldon"
            done <"$sheldon_config"
            chmod --reference="$sheldon_config" "$tmp_sheldon" 2>/dev/null
            if mv "$tmp_sheldon" "$sheldon_config" 2>/dev/null; then
                print_success "Cleaned Sheldon config" "uninstall_sheldon"
                ((uninstall_success++))
            else
                print_error "Failed to update Sheldon config"
                rm -f "$tmp_sheldon"
            fi
        fi
    fi

    # Summary
    echo ""
    if [[ $uninstall_success -gt 0 ]]; then
        echo -e "${GREEN}${BOLD}Uninstall completed.${NC}"
    else
        echo -e "${YELLOW}${BOLD}Uninstall completed with warnings.${NC}"
    fi
    echo ""
    print_info "Please restart your terminal for changes to take effect."

    generate_summary
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
        "Build Agents Only (Rebuild clipboard agents for your display server)" \
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
        echo -e "  ${BOLD}bash auto-install.sh${NC}"
        echo ""
        echo "The script will ask for sudo password when needed for system tasks."
        exit 1
    fi

    # If non-interactive, default to full install
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        run_full_install
    else
        show_main_menu
    fi
}

# Run main function only if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
