#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: User interface output and prompts
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh — do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard — prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_UI_LOADED:-}" ]] && return 0
readonly _ZES_MOD_UI_LOADED=1

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
    echo -e "${BORDER}║$(rgb 255 100 200)                              Version $SCRIPT_VERSION                               ${NC}${BORDER}║${NC}"
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

zes_center_text() {
    local width="$1"
    local text="${2:-}"
    local text_len left_pad right_pad

    [[ "$width" =~ ^[0-9]+$ ]] || width=0
    ((width < 0)) && width=0

    text_len=${#text}
    if ((text_len > width)); then
        text="${text:0:width}"
        text_len=$width
    fi

    left_pad=$(((width - text_len) / 2))
    right_pad=$((width - text_len - left_pad))
    printf '%*s%s%*s' "$left_pad" '' "$text" "$right_pad" ''
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
