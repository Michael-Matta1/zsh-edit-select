#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Linux terminal configuration helpers
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_TERMINALS_LINUX_LOADED:-}" ]] && return 0
readonly _ZES_MOD_TERMINALS_LINUX_LOADED=1

_zes_add_manual_step_once() {
    local step="$1"
    local existing
    for existing in "${MANUAL_STEPS[@]}"; do
        [[ "$existing" == "$step" ]] && return 0
    done
    MANUAL_STEPS+=("$step")
}

_zes_set_edit_select_mouse_replacement() {
    local value="${1:-0}"
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
    local config_dir
    local tmpfile
    local line

    config_dir="$(dirname "$config_file")"
    if ! mkdir -p "$config_dir" 2>/dev/null; then
        return 1
    fi

    tmpfile=$(mktemp 2>/dev/null) || return 1

    if [[ -f "$config_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*EDIT_SELECT_MOUSE_REPLACEMENT= ]]; then
                continue
            fi
            printf '%s\n' "$line" >>"$tmpfile"
        done <"$config_file"
    fi

    printf 'EDIT_SELECT_MOUSE_REPLACEMENT=%s\n' "$value" >>"$tmpfile"

    if [[ -f "$config_file" ]]; then
        copy_file_permissions "$config_file" "$tmpfile" 2>/dev/null || true
    else
        chmod 600 "$tmpfile" 2>/dev/null || true
    fi

    if mv "$tmpfile" "$config_file" 2>/dev/null; then
        return 0
    fi

    if cp "$tmpfile" "$config_file" 2>/dev/null; then
        rm -f "$tmpfile"
        return 0
    fi

    rm -f "$tmpfile"
    return 1
}

_zes_is_running_in_foot() {
    local term="${TERM:-}"
    [[ "$term" == "foot" ]] || [[ "$term" == foot-* ]]
}

configure_ghostty() {
    print_step "Configuring Ghostty..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    local config="$config_dir/config"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Ghostty config directory: $config_dir"
        return 1
    fi
    [[ ! -f "$config" ]] && touch "$config"
    backup_config "$config"

    local -a config_lines=()

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_lines+=(
            "# Ctrl+C sends the escape sequence for copying"
            "keybind = ctrl+c=csi:67;6u"
            "# Ctrl+Shift+C sends interrupt signal"
            "keybind = ctrl+shift+c=text:\\x03"
        )
    else
        config_lines+=(
            "# Copy with Ctrl+Shift+C"
            "keybind = ctrl+shift+c=csi:67;6u"
        )
    fi

    config_lines+=(
        "# Redo with Ctrl+Shift+Z"
        "keybind = ctrl+shift+z=csi:90;6u"
        ""
        "# Pass Ctrl+Shift navigation through to Zsh"
        "keybind = ctrl+shift+left=unbind"
        "keybind = ctrl+shift+right=unbind"
        "keybind = ctrl+shift+home=unbind"
        "keybind = ctrl+shift+end=unbind"
    )

    local all_exist=1
    local line
    for line in "${config_lines[@]}"; do
        [[ -z "${line// /}" ]] && continue
        [[ "$line" == "#"* ]] && continue
        if ! config_line_exists "$config" "$line"; then
            all_exist=0
            break
        fi
    done

    if [[ $all_exist -eq 1 ]] && grep -qF "# Zsh Edit-Select" "$config" 2>/dev/null; then
        print_info "Ghostty already fully configured for zsh-edit-select"
        return 0
    fi

    local config_was_modified=0
    if ! config_line_exists "$config" "# Zsh Edit-Select"; then
        echo "" >>"$config"
        echo "# Zsh Edit-Select" >>"$config"
        config_was_modified=1
    fi

    for line in "${config_lines[@]}"; do
        if [[ -z "${line// /}" ]]; then
            if [[ $config_was_modified -eq 1 ]]; then
                echo "" >>"$config"
            fi
            continue
        fi
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
        print_success "Ghostty configured successfully" "ghostty_config"
    else
        print_info "Ghostty already fully configured for zsh-edit-select"
    fi
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


# Compute the absolute path of this zsh-edit-select plugin tree.
# Walks up a few frames of BASH_SOURCE to find the top-level plugin dir,
# which holds assets/, impl-x11/, impl-wayland/, impl-wsl/, impl-macos/.
# Falls back to the runtime ${ZES_PLUGIN_ROOT} env var if set.
_zes_plugin_root() {
    # 1. The installer sets PLUGIN_INSTALL_DIR after detecting the plugin
    #    path (oh-my-zsh custom, zinit, zplug, standalone, etc). Use it
    #    first when present and actually valid — it is the most reliable
    #    signal because it survives the bootstrap's lib-copy to a temp dir.
    if [[ -n "${PLUGIN_INSTALL_DIR:-}" \
          && -d "${PLUGIN_INSTALL_DIR}/assets" \
          && -d "${PLUGIN_INSTALL_DIR}/impl-x11" ]]; then
        printf '%s' "$PLUGIN_INSTALL_DIR"
        return 0
    fi

    # 2. ZES_PLUGIN_DIR_HINT is exported by install.sh --local:
    #    `_zes_self_dir = dirname BASH_SOURCE[0]` then `cd lib/../../.. `
    #    resolves to the plugin root. Only the detection runs in modes
    #    that call detect_plugin_manager; --local always exports it, so
    #    integrate / conflicts / terminal modes also see it.
    if [[ -n "${ZES_PLUGIN_DIR_HINT:-}" \
          && -f "${ZES_PLUGIN_DIR_HINT}/zsh-edit-select.plugin.zsh" \
          && -d "${ZES_PLUGIN_DIR_HINT}/assets" ]]; then
        printf '%s' "$ZES_PLUGIN_DIR_HINT"
        return 0
    fi

    # 3. Walk BASH_SOURCE up to find a parent holding both assets/ and
    #    impl-x11/. Works for normal (non-bootstrap) sourcing from inside
    #    the plugin tree. The empty-string check is required because
    #    "${dir%/*}" on "/tmp" strips the only path segment and returns
    #    the empty string, which never matches "/" or "." and would spin
    #    forever without an explicit -n test.
    local src
    local dir
    for src in "${BASH_SOURCE[@]:1}" "${BASH_SOURCE[0]:-}"; do
        [[ -z "$src" ]] && continue
        dir="${src%/*}"
        [[ "$dir" == "$src" ]] && dir=.
        while [[ -n "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
            [[ -d "$dir/assets" && -d "$dir/impl-x11" ]] && { printf '%s' "$dir"; return 0; }
            dir="${dir%/*}"
        done
    done

    # 4. ZES_PLUGIN_ROOT env var — user-settable escape hatch.
    if [[ -n "${ZES_PLUGIN_ROOT:-}" && -d "${ZES_PLUGIN_ROOT}/assets" ]]; then
        printf '%s' "$ZES_PLUGIN_ROOT"
        return 0
    fi
    return 1
}

# Compute the daemon cache directory path the same way the plugin does at
# runtime (${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${UID}).  Used
# to write a literal cache-dir argument into the alacritty mouse binding so
# the click-to-deselect helper does not need to `id -u` on every invocation.
_zes_cache_dir() {
    printf '%s/zsh-edit-select-%s' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" "$(id -u)"
}

# Returns 0 if the alacritty click-to-deselect `[[mouse.bindings]]` block
# is already present in the config file passed as $1, 1 otherwise.  The
# marker we look for is the HELP_COMMENT_START string (a single-line
# comment that uniquely identifies the block we add); we do NOT key off
# the generic "Zsh Edit-Select" header because that is shared with the
# keyboard bindings.
_zes_alacritty_clear_binding_present() {
    local config="$1"
    grep -qF "click-to-deselect" "$config" 2>/dev/null
}

# Returns 0 when appending an `[[<table>.bindings]]` array-of-tables entry to
# the TOML config in $1 would produce a duplicate key.  TOML allows any number
# of `[[keyboard.bindings]]` / `[[mouse.bindings]]` entries, but it rejects the
# whole file if the same key is also defined some other way — and Alacritty
# then silently falls back to its built-in defaults, losing every setting the
# user had.  The three shapes that collide (verified against alacritty 0.17's
# own parser) are:
#   [keyboard.bindings]        <- plain table, not an array of tables
#   [keyboard]                 <- inline array under the parent table
#   bindings = [ ... ]
#   keyboard = { bindings = [ ... ] }   <- top-level inline table
# Anything else — including a `[mouse]` table that only sets scalars such as
# hide_when_typing — is safe to append to.
_zes_alacritty_toml_bindings_collide() {
    local config="$1"
    local table="$2"
    local line
    local current=""

    [[ -f "$config" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Array-of-tables header: records the table we are in, never collides.
        if [[ "$line" =~ ^\[\[[[:space:]]*([^]]*[^][:space:]])[[:space:]]*\]\] ]]; then
            current="${BASH_REMATCH[1]}"
            continue
        fi
        # Plain table header.
        if [[ "$line" =~ ^\[[[:space:]]*([^]]*[^][:space:]])[[:space:]]*\] ]]; then
            current="${BASH_REMATCH[1]}"
            [[ "$current" == "${table}.bindings" ]] && return 0
            continue
        fi
        # `bindings = [...]` inside the parent table.
        [[ "$current" == "$table" ]] && [[ "$line" =~ ^bindings[[:space:]]*= ]] && return 0
        # Top-level `keyboard = {...}` / `keyboard.bindings = [...]`.
        if [[ -z "$current" ]]; then
            [[ "$line" =~ ^${table}[[:space:]]*= ]] && return 0
            [[ "$line" =~ ^${table}\.bindings[[:space:]]*= ]] && return 0
        fi
    done <"$config"

    return 1
}

# Returns 0 when the YAML config in $1 already defines the top-level key $2.
# Appending a second one produces a duplicate mapping key: Alacritty >= 0.13
# rejects the file outright (serde_yaml 0.9) and older releases silently keep
# only the last occurrence, discarding whatever the user had written.  Only a
# column-0 match counts — an indented `mouse_bindings:` is nested under some
# other key and cannot collide with ours.
_zes_alacritty_yml_key_present() {
    local config="$1"
    local key="$2"
    grep -qE "^${key}[[:space:]]*:" "$config" 2>/dev/null
}

# Emit the TOML-formatted `[[mouse.bindings]]` block for click-to-deselect,
# writing the absolute paths discovered via _zes_plugin_root and _zes_cache_dir.
# Echoes the block on stdout (no trailing newline); caller appends it to the
# user's alacritty.toml.  Returns 1 if the plugin root cannot be resolved
# (caller should skip adding the block in that case).
_zes_alacritty_clear_binding_toml() {
    local root cache_dir helper
    root=$(_zes_plugin_root) || return 1
    cache_dir=$(_zes_cache_dir)
    helper="$root/assets/helpers/zes-alacritty-click-clear.sh"

    # Never write a binding that points at a program the user does not have:
    # alacritty would log a spawn failure on every Left-press.  A tree that is
    # missing the helper predates it, so fall back to the manual path.
    [[ -f "$helper" ]] || return 1
    # Alacritty execve()s this path directly, so the exec bit must be set.  Git
    # preserves it, but an archive download or a hand copy may not.
    [[ -x "$helper" ]] || chmod +x "$helper" 2>/dev/null || return 1

    # The command's program field is the helper script; args is the daemon
    # cache dir.  Both are absolute paths so alacritty does not depend on
    # the shell's $PATH or cwd.
    printf '\n\n# Zsh Edit-Select click-to-deselect\n# Each Left-press in a non-alt-screen pane clears PRIMARY via the\n# plugin'"'"'s own agent so the running daemon bumps its cache seq and\n# the shell-side pre-redraw hook forgets the now-stale selection.\n[[mouse.bindings]]\nmouse = "Left"\nmode = "~Alt"\ncommand = { program = "%s", args = ["%s"] }' \
        "$helper" "$cache_dir"
}

# Like _zes_alacritty_clear_binding_toml but emits the YAML equivalent for
# the legacy alacritty.yml config format.
_zes_alacritty_clear_binding_yml() {
    local root cache_dir helper
    root=$(_zes_plugin_root) || return 1
    cache_dir=$(_zes_cache_dir)
    helper="$root/assets/helpers/zes-alacritty-click-clear.sh"

    [[ -f "$helper" ]] || return 1
    [[ -x "$helper" ]] || chmod +x "$helper" 2>/dev/null || return 1

    printf '\n\n# Zsh Edit-Select click-to-deselect\n# Each Left-press in a non-alt-screen pane clears PRIMARY via the\n# plugin'"'"'s own agent so the running daemon bumps its cache seq and\n# the shell-side pre-redraw hook forgets the now-stale selection.\nmouse_bindings:\n  - { mouse: Left, mode: "~Alt", command: { program: "%s", args: ["%s"] } }' \
        "$helper" "$cache_dir"
}

# Resolves the user's alacritty version (major minor) on stdout, or empty
# on failure (alacritty not installed, version string unparseable, etc).
# Alacritty 0.13+ supports TOML natively; <0.13 supports only YAML.  When
# the version cannot be detected, the existing-config wins (TOML or YAML,
# whichever file the user already has), defaulting to TOML for fresh
# installs (since any Alacritty built in the last ~3 years speaks TOML).
_zes_alacritty_version() {
    local v
    v=$(command alacritty --version 2>/dev/null) || return 1
    # expected form: "alacritty 0.17.0" (or with distro suffix).  Capture
    # only the first two dotted integers, never trust the rest.
    [[ "$v" =~ alacritty[[:space:]]+([0-9]+)\.([0-9]+) ]] || return 1
    printf '%s %s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

# TRUE if the installed Alacritty supports TOML configs (>= 0.13).  When
# the version is undetectable (older binary, snap confinement, etc), we
# fall back to ``TRUE`` because every Alacritty version still in active
# distribution (0.13+ from 2022 onward) understands TOML.
_zes_alacritty_supports_toml() {
    local ver
    ver=$(_zes_alacritty_version) || return 0
    local major minor
    read -r major minor <<<"$ver"
    [[ "${major:-0}" -gt 0 || "${minor:-13}" -ge 13 ]]
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

    # 1) Existing-config-wins: if the user already has either format, keep
    #    using it.  A user with alacritty.yml on a v0.17 install almost
    #    certainly has hand-edited content they want preserved.
    if [[ -f "$config_toml" ]]; then
        configure_alacritty_toml "$config_toml"
    elif [[ -f "$config_yml" ]]; then
        configure_alacritty_yml "$config_yml"
    elif _zes_alacritty_supports_toml; then
        # New install on Alacritty 0.13+: write TOML.
        : >"$config_toml"  # create empty file (truncate; never existed before)
        configure_alacritty_toml "$config_toml"
    else
        # New install on a pre-0.13 Alacritty: write YAML.
        : >"$config_yml"
        configure_alacritty_yml "$config_yml"
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

    # A pre-existing `[keyboard.bindings]` plain table or inline `bindings = [..]`
    # array would turn our appended array-of-tables entries into a duplicate key,
    # which makes Alacritty reject the whole file and fall back to defaults.  Leave
    # such a config untouched and hand the user the manual path instead.
    if [[ $needs_config -eq 1 ]] && _zes_alacritty_toml_bindings_collide "$config" keyboard; then
        needs_config=0
        print_warning "Alacritty config already defines keyboard.bindings in a form that cannot be appended to."
        _zes_add_manual_step_once "Alacritty: add the zsh-edit-select keyboard bindings by hand (see README) — alacritty.toml already defines keyboard.bindings inline"
    fi

    if [[ $needs_config -eq 1 ]]; then
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
    fi

    # Click-to-deselect: spawn the plugin's own agent in --clear-primary mode
    # on every Left-press so the running daemon bumps its cache seq with empty
    # primary and the shell's pre-redraw hook clears _EDIT_SELECT_ACTIVE_SELECTION.
    # Gated on its OWN marker ("click-to-deselect"), independently of the generic
    # "Zsh Edit-Select" header above: a user who configured Alacritty before this
    # binding existed already has that header, so keying the append off it would
    # never deliver the mouse binding to them.
    local clear_block=""
    if ! _zes_alacritty_clear_binding_present "$config"; then
        if _zes_alacritty_toml_bindings_collide "$config" mouse; then
            print_warning "Alacritty config already defines mouse.bindings in a form that cannot be appended to."
            _zes_add_manual_step_once "Alacritty: add the click-to-deselect mouse binding by hand (see README) — alacritty.toml already defines mouse.bindings inline"
        else
            clear_block=$(_zes_alacritty_clear_binding_toml) || clear_block=""
            [[ -z "$clear_block" ]] && \
                _zes_add_manual_step_once "Alacritty: run 'edit-select integrate' to enable click-to-deselect (plugin root not auto-detected)"
        fi
    fi

    # Append whatever is genuinely missing.  Both branches write in one shot so
    # the fresh-install output is byte-identical to a single concatenated block.
    if [[ $needs_config -eq 1 ]]; then
        echo "${config_block}${clear_block}" >>"$config"
        print_success "Alacritty (TOML) configured successfully" "alacritty_config"
    elif [[ -n "$clear_block" ]]; then
        echo "$clear_block" >>"$config"
        print_success "Alacritty (TOML): added click-to-deselect mouse binding" "alacritty_config"
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

    # A second top-level `key_bindings:` is a duplicate mapping key: Alacritty
    # >= 0.13 rejects the file outright and older releases keep only the last
    # occurrence, silently dropping the user's own bindings.  Skip rather than
    # corrupt.
    if [[ $needs_config -eq 1 ]] && _zes_alacritty_yml_key_present "$config" key_bindings; then
        needs_config=0
        print_warning "Alacritty config already has a top-level key_bindings: key; not adding a duplicate."
        _zes_add_manual_step_once "Alacritty: merge the zsh-edit-select key_bindings entries into your existing key_bindings: list (see README)"
    fi

    if [[ $needs_config -eq 1 ]]; then
        if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
            config_block=$'\n# Zsh Edit-Select\nkey_bindings:\n  # Ctrl+C sends the escape sequence for copying\n  - { key: C, mods: Control, chars: "\\x1b[67;6u" }\n  # Ctrl+Shift+C sends interrupt signal\n  - { key: C, mods: Control|Shift, chars: "\\x03" }\n  # Redo with Ctrl+Shift+Z\n  - { key: Z, mods: Control|Shift, chars: "\\x1b[90;6u" }\n  # Pass Shift+Home/End through for selection\n  - { key: Home, mods: Shift, action: ReceiveChar }\n  - { key: End, mods: Shift, action: ReceiveChar }'
        else
            config_block=$'\n# Zsh Edit-Select\nkey_bindings:\n  # Copy with Ctrl+Shift+C\n  - { key: C, mods: Control|Shift, chars: "\\x1b[67;6u" }\n  # Redo with Ctrl+Shift+Z\n  - { key: Z, mods: Control|Shift, chars: "\\x1b[90;6u" }\n  # Pass Shift+Home/End through for selection\n  - { key: Home, mods: Shift, action: ReceiveChar }\n  - { key: End, mods: Shift, action: ReceiveChar }'
        fi
    fi

    # Click-to-deselect (YAML form): mirror of the TOML block added by
    # configure_alacritty_toml via _zes_alacritty_clear_binding_yml.  Same
    # independent-marker rule as the TOML branch, and the same duplicate-key
    # guard as key_bindings: above.
    local clear_block=""
    if ! _zes_alacritty_clear_binding_present "$config"; then
        if _zes_alacritty_yml_key_present "$config" mouse_bindings; then
            print_warning "Alacritty config already has a top-level mouse_bindings: key; not adding a duplicate."
            _zes_add_manual_step_once "Alacritty: merge the click-to-deselect entry into your existing mouse_bindings: list (see README)"
        else
            clear_block=$(_zes_alacritty_clear_binding_yml) || clear_block=""
            [[ -z "$clear_block" ]] && \
                _zes_add_manual_step_once "Alacritty: run 'edit-select integrate' to enable click-to-deselect (plugin root not auto-detected)"
        fi
    fi

    # Only append if configuration is missing
    if [[ $needs_config -eq 1 ]]; then
        echo "${config_block}${clear_block}" >>"$config"
        print_success "Alacritty (YAML) configured successfully" "alacritty_config"
    elif [[ -n "$clear_block" ]]; then
        echo "$clear_block" >>"$config"
        print_success "Alacritty (YAML): added click-to-deselect mouse binding" "alacritty_config"
    else
        print_info "Alacritty (YAML) already configured for zsh-edit-select"
    fi
}


_zes_wezterm_insert_before_return_config() {
    local config="$1"
    local block="$2"
    local tmpfile
    local line
    local inserted=0

    tmpfile=$(mktemp 2>/dev/null) || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $inserted -eq 0 ]] && [[ "$line" =~ ^[[:space:]]*return[[:space:]]+config([[:space:]]*--.*)?[[:space:]]*$ ]]; then
            printf '%s\n\n' "$block" >>"$tmpfile"
            inserted=1
        fi
        printf '%s\n' "$line" >>"$tmpfile"
    done <"$config"

    if [[ $inserted -eq 0 ]]; then
        rm -f "$tmpfile"
        return 1
    fi

    copy_file_permissions "$config" "$tmpfile" 2>/dev/null || true
    if mv "$tmpfile" "$config" 2>/dev/null; then
        return 0
    fi

    if cp "$tmpfile" "$config" 2>/dev/null; then
        rm -f "$tmpfile"
        return 0
    fi

    rm -f "$tmpfile"
    return 1
}


_zes_wezterm_convert_return_table_to_config() {
    local config="$1"
    local tmpfile
    local line
    local converted=0

    tmpfile=$(mktemp 2>/dev/null) || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $converted -eq 0 ]] && [[ "$line" =~ ^([[:space:]]*)return[[:space:]]*(\{.*)$ ]]; then
            printf '%slocal config = %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >>"$tmpfile"
            converted=1
        else
            printf '%s\n' "$line" >>"$tmpfile"
        fi
    done <"$config"

    if [[ $converted -eq 0 ]]; then
        rm -f "$tmpfile"
        return 1
    fi

    copy_file_permissions "$config" "$tmpfile" 2>/dev/null || true
    if mv "$tmpfile" "$config" 2>/dev/null; then
        return 0
    fi

    if cp "$tmpfile" "$config" 2>/dev/null; then
        rm -f "$tmpfile"
        return 0
    fi

    rm -f "$tmpfile"
    return 1
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
                cat >"$config" <<'WEZTERM_DEFAULT'
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

return config
WEZTERM_DEFAULT
                print_substep "Created default wezterm.lua"
        else
                backup_config "$config"
        fi

        if grep -qF "Zsh Edit-Select (Linux)" "$config" 2>/dev/null; then
        print_info "WezTerm already configured for zsh-edit-select"
        return
    fi

    local config_block=""

    if [[ "$USER_WANTS_REVERSED_COPY" == "y" ]]; then
        config_block=$(
                        cat <<'WEZTERM_REVERSED'
-- Zsh Edit-Select (Linux)
local zes_wezterm = require 'wezterm'
config.keys = config.keys or {}
config.mouse_bindings = config.mouse_bindings or {}

local zes_linux_keys = {
    {
        key = 'c',
        mods = 'CTRL',
        action = zes_wezterm.action_callback(function(window, pane)
            local sel = window:get_selection_text_for_pane(pane)
            if sel ~= '' then
                window:perform_action(zes_wezterm.action.CopyTo 'Clipboard', pane)
            else
                window:perform_action(zes_wezterm.action.SendString '\x1b[67;6u', pane)
            end
        end),
    },
    { key = 'C', mods = 'CTRL|SHIFT', action = zes_wezterm.action.SendString '\x03' },
    { key = 'Z', mods = 'CTRL|SHIFT', action = zes_wezterm.action.SendString '\x1b[90;6u' },
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'Home', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'End', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
}
for _, binding in ipairs(zes_linux_keys) do table.insert(config.keys, binding) end

local zes_linux_mouse_bindings = {
    {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action_callback(function(window, pane)
            local sel = window:get_selection_text_for_pane(pane)
            -- Skip the signal while a full-screen application (vim, nano, less)
            -- owns the alternate screen; it would arrive there as raw input.
            if sel ~= '' and not pane:is_alt_screen_active() then
                pane:send_text('\x1b[>62300u')
            end
            window:perform_action(zes_wezterm.action.ClearSelection, pane)
            window:perform_action(zes_wezterm.action.SelectTextAtMouseCursor 'Cell', pane)
        end),
    },
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor 'PrimarySelection',
    },
    {
        event = { Up = { streak = 2, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelection 'PrimarySelection',
    },
    {
        event = { Up = { streak = 3, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelection 'PrimarySelection',
    },
}
for _, binding in ipairs(zes_linux_mouse_bindings) do table.insert(config.mouse_bindings, binding) end
-- Zsh Edit-Select End
WEZTERM_REVERSED
        )
    else
        config_block=$(
            cat <<'WEZTERM_DEFAULT_KEYS'
-- Zsh Edit-Select (Linux)
local zes_wezterm = require 'wezterm'
config.keys = config.keys or {}
config.mouse_bindings = config.mouse_bindings or {}

local zes_linux_keys = {
    {
        key = 'C',
        mods = 'CTRL|SHIFT',
        action = zes_wezterm.action_callback(function(window, pane)
            local sel = window:get_selection_text_for_pane(pane)
            if sel ~= '' then
                window:perform_action(zes_wezterm.action.CopyTo 'Clipboard', pane)
            else
                window:perform_action(zes_wezterm.action.SendString '\x1b[67;6u', pane)
            end
        end),
    },
    { key = 'Z', mods = 'CTRL|SHIFT', action = zes_wezterm.action.SendString '\x1b[90;6u' },
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'Home', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
    { key = 'End', mods = 'CTRL|SHIFT', action = zes_wezterm.action.DisableDefaultAssignment },
}
for _, binding in ipairs(zes_linux_keys) do table.insert(config.keys, binding) end

local zes_linux_mouse_bindings = {
    {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action_callback(function(window, pane)
            local sel = window:get_selection_text_for_pane(pane)
            -- Skip the signal while a full-screen application (vim, nano, less)
            -- owns the alternate screen; it would arrive there as raw input.
            if sel ~= '' and not pane:is_alt_screen_active() then
                pane:send_text('\x1b[>62300u')
            end
            window:perform_action(zes_wezterm.action.ClearSelection, pane)
            window:perform_action(zes_wezterm.action.SelectTextAtMouseCursor 'Cell', pane)
        end),
    },
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor 'PrimarySelection',
    },
    {
        event = { Up = { streak = 2, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelection 'PrimarySelection',
    },
    {
        event = { Up = { streak = 3, button = 'Left' } },
        mods = 'NONE',
        action = zes_wezterm.action.CompleteSelection 'PrimarySelection',
    },
}
for _, binding in ipairs(zes_linux_mouse_bindings) do table.insert(config.mouse_bindings, binding) end
-- Zsh Edit-Select End
WEZTERM_DEFAULT_KEYS
        )
    fi

        if grep -qE '^[[:space:]]*return[[:space:]]+config([[:space:]]*--.*)?[[:space:]]*$' "$config"; then
                if ! _zes_wezterm_insert_before_return_config "$config" "$config_block"; then
                        print_error "Failed to update WezTerm config"
                        return 1
                fi
        elif grep -qE '^[[:space:]]*return[[:space:]]*\{' "$config"; then
                if ! _zes_wezterm_convert_return_table_to_config "$config"; then
                        print_error "Failed to normalize WezTerm config for zsh-edit-select"
                        return 1
                fi

                {
                        echo ""
                        printf '%s\n\n' "$config_block"
                        echo "return config"
                } >>"$config"
        else
                print_warning "Unsupported WezTerm config format; please merge zsh-edit-select bindings manually."
                MANUAL_STEPS+=("WezTerm: add zsh-edit-select bindings manually in wezterm.lua (see README.md)")
                return 1
        fi

    print_success "WezTerm configured successfully" "wezterm_config"
}


configure_foot() {
    print_step "Configuring Foot..."

    # Foot-specific note: Foot does not notify the shell when a click clears
    # the visual selection, so the plugin cannot detect the deselect. Mouse
    # replacement can then act on a stale (now invisible) selection. Foot's
    # config model allows only one action per mouse button and that slot is
    # needed to start a selection, so there is no config-side fix. Disable
    # mouse replacement for Foot by default; users may re-enable it at the
    # cost of this edge case.
    if _zes_is_running_in_foot; then
        print_warning "Foot does not notify the shell when you click to clear a selection, so mouse replacement can act on a stale (now invisible) selection."
        if _zes_set_edit_select_mouse_replacement "0"; then
            print_success "Set plugin config for Foot: EDIT_SELECT_MOUSE_REPLACEMENT=0" "foot_mouse_replacement"
        else
            print_warning "Could not update plugin config automatically for Foot."
            print_info "Run manually: edit-select config and set Mouse Replacement to Disabled."
            _zes_add_manual_step_once "Foot: disable mouse replacement in 'edit-select config' (Option 1 -> Disabled)"
        fi
    else
        print_info "Installer is not running inside Foot; leaving EDIT_SELECT_MOUSE_REPLACEMENT unchanged."
    fi

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

    copy_file_permissions "$config" "$tmpfile" 2>/dev/null || chmod 644 "$tmpfile" 2>/dev/null
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
