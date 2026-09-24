#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Plugin installation and shell configuration
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_PLUGIN_LOADED:-}" ]] && return 0
readonly _ZES_MOD_PLUGIN_LOADED=1

install_plugin() {
    print_step "Installing zsh-edit-select plugin..."

    # Validate that PLUGIN_INSTALL_DIR is set
    if [[ -z "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "Plugin installation directory not set" "plugin_install"
        print_error "This usually means plugin manager detection failed"
        FAILED_STEPS["plugin_install"]="Plugin directory not configured"
        return 1
    fi

    # Make sure we can actually write to PLUGIN_INSTALL_DIR before doing
    # anything else. This covers every plugin manager and every custom
    # path uniformly, since they all resolve to this one variable --
    # e.g. a system-package oh-my-zsh install under /usr/share/oh-my-zsh
    # whose custom/ dir is root-owned.
    if ! ensure_plugin_dir_writable; then
        if [[ -z "${FAILED_STEPS[plugin_install]:-}" ]]; then
            FAILED_STEPS["plugin_install"]="Plugin installation directory is not writable"
        fi
        return 1
    fi

    # Clone or update the repository
    if [[ -d "$PLUGIN_INSTALL_DIR" ]]; then
        print_substep "Plugin directory already exists, checking status..."

        # Check if it's a git repository
        if [[ -d "$PLUGIN_INSTALL_DIR/.git" ]]; then
            print_substep "Updating existing plugin..."
            if (cd "$PLUGIN_INSTALL_DIR" && ZES_INTERNAL_PULL=1 git pull --quiet 2>/dev/null); then
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
                # If the directory is already empty (e.g. ensure_plugin_dir_writable()
                # just created it under a read-only parent), there's nothing to
                # remove -- and rm -rf would harmlessly fail trying to unlink the
                # directory itself from that still-root-owned parent. Only rm -rf
                # when there's actual stale content to clear.
                if _zes_directory_has_entries "$PLUGIN_INSTALL_DIR"; then
                    rm -rf "$PLUGIN_INSTALL_DIR"
                fi
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

    # Install git hooks for automatic update notifications.
    # Output is captured (not discarded) so warnings (e.g. active hooks in
    # .git/hooks/) are visible to the user.  Failure is non-fatal — hooks
    # are an enhancement, not a requirement.
    # The || hook_rc=$? pattern is safe under set -e (which the installer
    # does not currently use, but this is defensive).
    local hook_rc=0
    local hook_output
    hook_output=$(sh "$PLUGIN_INSTALL_DIR/hooks/manage-hooks.sh" install "$PLUGIN_INSTALL_DIR" 2>&1) || hook_rc=$?
    echo "$hook_output"
    if [[ $hook_rc -ne 0 ]]; then
        print_warning "Git hooks not installed (exit code $hook_rc)."
        print_info "You can install them later with: edit-select setup-hooks"
    fi

    # Configure .zshrc
    configure_zshrc
}


_zes_directory_has_entries() {
    local directory="$1"
    local entry

    # If the directory cannot be inspected, treat it as non-empty so callers
    # never mistake an unreadable directory for a safe empty one.
    if [[ ! -r "$directory" ]] || [[ ! -x "$directory" ]]; then
        return 0
    fi

    # These POSIX shell globs include ordinary and hidden entries while
    # excluding the special . and .. directory names. Avoid GNU-only find
    # options so the check works with macOS/BSD find environments too.
    for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
        if [[ -e "$entry" ]] || [[ -L "$entry" ]]; then
            return 0
        fi
    done

    return 1
}


ensure_plugin_dir_writable() {
    local failure_category="${1:-plugin_install}"
    local target="$PLUGIN_INSTALL_DIR"
    local check_dir="$target"
    local target_leaf="${target%/}"
    target_leaf="${target_leaf##*/}"

    if [[ -e "$target" ]] && [[ ! -d "$target" ]]; then
        print_error "Plugin installation path is not a directory: $target" "$failure_category"
        return 1
    fi

    # This helper can recursively chown its target. Keep that operation
    # limited to a path that is recognizably this plugin's leaf directory.
    if [[ -z "$target" ]] || [[ "$target" == "/" ]] || [[ "/$target/" == *"/../"* ]] || [[ "$target" == "$HOME" ]] ||
        [[ "$target" == "$HOME/" ]] ||
        {
            [[ "$target_leaf" != "zsh-edit-select" ]] &&
                [[ "$target_leaf" != "zsh-edit-select-master" ]] &&
                [[ "$target_leaf" != *-zsh-edit-select ]] &&
                [[ ! -f "$target/zsh-edit-select.plugin.zsh" ]]
        }; then
        print_error "Refusing to change permissions on an unsafe plugin directory: ${target:-<unset>}" "$failure_category"
        return 1
    fi

    # Do not recursively change ownership through a symlink. An already
    # writable symlink target needs no repair; otherwise leave it for manual
    # review rather than risk changing a different tree.
    if [[ -L "$target" ]]; then
        if [[ -e "$target" ]] && [[ -w "$target" ]] && [[ -x "$target" ]]; then
            return 0
        fi
        print_error "Refusing to change ownership through a symlinked plugin directory: $target" "$failure_category"
        return 1
    fi

    # Walk up to the nearest existing ancestor. That's what actually
    # governs whether we can create/write $target.
    while [[ ! -e "$check_dir" ]]; do
        local parent
        parent="$(dirname "$check_dir")"
        # Safety: stop if dirname stops making progress (e.g. reached "/").
        [[ "$parent" == "$check_dir" ]] && break
        check_dir="$parent"
    done

    # Already writable by us (existing dir we own, or a not-yet-created
    # path whose nearest existing parent we can write into) -- nothing to do.
    # Directories need search permission as well as write permission for
    # creating entries or accessing their contents.
    if [[ -w "$check_dir" ]] && [[ -x "$check_dir" ]]; then
        return 0
    fi

    # An existing non-writable directory must be verified as this plugin
    # before the recursive ownership repair below. A matching path name by
    # itself is not enough to justify changing ownership of arbitrary files.
    if [[ -d "$target" ]] && [[ ! -f "$target/zsh-edit-select.plugin.zsh" ]]; then
        print_error "Refusing to change ownership of an existing directory without the plugin entrypoint: $target" "$failure_category"
        return 1
    fi

    print_warning "Plugin directory is not writable by your user: $check_dir"
    print_info "This usually happens when your plugin manager was installed system-wide as a distro package (e.g. oh-my-zsh under /usr/share)."

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_warning "Non-interactive mode: skipping automatic sudo elevation for safety"
        MANUAL_STEPS+=("Make '$PLUGIN_INSTALL_DIR' writable by your user (e.g. sudo mkdir -p '$PLUGIN_INSTALL_DIR' && sudo chown -R \$(id -u):\$(id -g) '$PLUGIN_INSTALL_DIR'), or set ZSH_CUSTOM to a directory you own and re-run.")
        return 1
    fi

    # Check whether elevation is possible without authenticating yet. Ask for
    # consent before sudo can prompt or change ownership.
    if [[ $EUID -ne 0 ]] && [[ $SUDO_AVAILABLE -ne 1 ]] && ! command_exists sudo; then
        print_error "sudo is not available -- cannot fix permissions automatically" "$failure_category"
        MANUAL_STEPS+=("Make '$PLUGIN_INSTALL_DIR' writable by your user (e.g. sudo mkdir -p '$PLUGIN_INSTALL_DIR' && sudo chown -R \$(id -u):\$(id -g) '$PLUGIN_INSTALL_DIR'), or set ZSH_CUSTOM to a directory you own and re-run.")
        return 1
    fi

    if ! ask_yes_no "Use sudo to create '$PLUGIN_INSTALL_DIR' and hand ownership to your user ($(id -un)) so the installer can manage it normally afterwards?" "n"; then
        print_info "Skipping. Set ZSH_CUSTOM to a writable path and re-run, or fix permissions manually."
        MANUAL_STEPS+=("Make '$PLUGIN_INSTALL_DIR' writable by your user, or set ZSH_CUSTOM to a directory you own and re-run.")
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        SUDO_AVAILABLE=1
    fi

    if [[ $EUID -ne 0 ]] && [[ $SUDO_AVAILABLE -ne 1 ]]; then
        if ! sudo -v 2>/dev/null; then
            print_error "sudo authentication failed -- cannot fix permissions automatically" "$failure_category"
            MANUAL_STEPS+=("Make '$PLUGIN_INSTALL_DIR' writable by your user, or set ZSH_CUSTOM to a directory you own and re-run.")
            return 1
        fi
        SUDO_AVAILABLE=1
    fi

    if ! run_with_sudo mkdir -p "$PLUGIN_INSTALL_DIR" 2>/dev/null; then
        print_error "sudo mkdir -p failed for $PLUGIN_INSTALL_DIR" "$failure_category"
        log_message "SUDO_MKDIR_FAILED: $PLUGIN_INSTALL_DIR"
        return 1
    fi

    # Only take ownership of the plugin's own leaf directory, never its
    # parents -- other plugins/content under a shared custom/ dir may be
    # managed by the package manager or other users and must stay untouched.
    if ! run_with_sudo chown -R "$(id -u):$(id -g)" "$PLUGIN_INSTALL_DIR" 2>/dev/null; then
        print_error "sudo chown failed for $PLUGIN_INSTALL_DIR" "$failure_category"
        log_message "SUDO_CHOWN_FAILED: $PLUGIN_INSTALL_DIR"
        return 1
    fi

    if [[ ! -w "$PLUGIN_INSTALL_DIR" ]] || [[ ! -x "$PLUGIN_INSTALL_DIR" ]]; then
        print_error "$PLUGIN_INSTALL_DIR is still not writable after chown" "$failure_category"
        return 1
    fi

    print_success "Took ownership of $PLUGIN_INSTALL_DIR (now writable by $(id -un))" "$failure_category"
    log_message "SUDO_CHOWN_OK: $PLUGIN_INSTALL_DIR now owned by $(id -un)"
    return 0
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

    # If PLUGIN_INSTALL_DIR itself already exists and is writable, git can
    # clone straight into it (git supports cloning into an existing empty
    # directory) -- so skip the parent-directory checks below entirely.
    # This matters when ensure_plugin_dir_writable() already created and
    # chown'd this exact leaf directory while deliberately leaving its
    # parent untouched (e.g. a system-package oh-my-zsh install, where the
    # parent custom/plugins/ stays root-owned on purpose so we don't grant
    # broad write access to a directory shared with other plugins). In
    # that case the parent will never pass the writability check below,
    # but git doesn't need to create the directory itself here, only
    # populate the one we already prepared.
    if [[ ! -d "$PLUGIN_INSTALL_DIR" ]] || [[ ! -w "$PLUGIN_INSTALL_DIR" ]] || [[ ! -x "$PLUGIN_INSTALL_DIR" ]]; then
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
        # Clean up failed clone attempt before retry (or on final failure).
        # If dest sits inside a read-only parent (see clone_plugin()'s
        # pre-existing-writable-leaf case), rm -rf can still clear dest's
        # contents -- it just can't unlink dest itself, since that requires
        # write access to dest's parent, not dest. That partial failure is
        # expected and harmless there, so its stderr is suppressed. If
        # cleanup cannot remove all contents, the next clone attempt will
        # fail normally and the final clone error will be reported.
        if [[ -n "$dest" ]] && [[ "$dest" != "/" ]] &&
            [[ "$dest" != "$HOME" ]] && [[ -e "$dest" ]]; then
            [[ $i -lt $retries ]] && sleep 5
            rm -rf "$dest" 2>/dev/null
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
                copy_file_permissions "$zshrc" "$tmp_zshrc" 2>/dev/null
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
                    copy_file_permissions "$zshrc" "$tmp_zshrc" 2>/dev/null
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

