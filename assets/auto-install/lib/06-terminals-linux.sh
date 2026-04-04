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
            if sel ~= '' then
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
            if sel ~= '' then
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

    # Foot-specific note from terminals-configs.md:
    # it can keep a stale PRIMARY selection after click-to-deselect,
    # so mouse replacement should be disabled for reliable behavior.
    if _zes_is_running_in_foot; then
        print_warning "Foot may keep stale PRIMARY selection after click-to-deselect."
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
