#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Core utilities, traps, and lock management
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_UTILS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_UTILS_LOADED=1

cleanup() {
    local exit_code=$?
    rm -rf "${ZES_INSTALL_TMPDIR:-}" 2>/dev/null
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
                        # Check if the process command line contains our installer script name.
                        # Accept both legacy monolithic and modular entrypoint names.
                        if grep -Eq "auto-install\.sh|assets/auto-install/install\.sh|install\.sh" "/proc/$pid/cmdline" 2>/dev/null; then
                            is_our_script=1
                        fi
                    else
                        # Fallback: use ps to check command
                        if ps -p "$pid" -o command= 2>/dev/null | grep -Eq "auto-install\.sh|assets/auto-install/install\.sh|install\.sh"; then
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
    if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
        orig_perms=$(stat -f '%OLp' "$file" 2>/dev/null)
    else
        orig_perms=$(stat -c '%a' "$file" 2>/dev/null)
    fi

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

copy_file_permissions() {
    local source_file="$1"
    local target_file="$2"

    local source_perms=""
    if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
        source_perms=$(stat -f '%OLp' "$source_file" 2>/dev/null)
    else
        source_perms=$(stat -c '%a' "$source_file" 2>/dev/null)
    fi

    if [[ -n "$source_perms" ]]; then
        chmod "$source_perms" "$target_file" 2>/dev/null || true
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
        if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
            file_size=$(stat -f '%z' "$file" 2>/dev/null || echo 0)
        else
            file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        fi
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
