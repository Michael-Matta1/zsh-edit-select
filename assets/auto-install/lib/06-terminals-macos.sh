#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: macOS terminal configuration helpers
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_TERMINALS_MACOS_LOADED:-}" ]] && return 0
readonly _ZES_MOD_TERMINALS_MACOS_LOADED=1

configure_kitty_macos() {
    print_step "Configuring Kitty (macOS)..."

    local config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
    local config_dir
    config_dir="$(dirname "$config")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Kitty config directory: $config_dir"
        return 1
    fi

    [[ ! -f "$config" ]] && touch "$config"
    backup_config "$config"

    local -a config_lines=(
        "# Cmd editing shortcuts"
        "map cmd+a send_text all \\x1b[97;9u"
        "map cmd+c send_text all \\x1b[99;9u"
        "map cmd+v send_text all \\x1b[118;9u"
        "map cmd+x send_text all \\x1b[120;9u"
        "map cmd+shift+z send_text all \\x1b[122;10u"
    )

    local all_exist=1
    local line
    for line in "${config_lines[@]}"; do
        [[ "$line" == "#"* ]] && continue
        if ! config_line_exists "$config" "$line"; then
            all_exist=0
            break
        fi
    done

    if [[ $all_exist -eq 1 ]] && grep -qF "# Zsh Edit-Select (macOS)" "$config" 2>/dev/null; then
        print_info "Kitty already fully configured for zsh-edit-select on macOS"
        return 0
    fi

    local config_was_modified=0
    if ! config_line_exists "$config" "# Zsh Edit-Select (macOS)"; then
        echo "" >>"$config"
        echo "# Zsh Edit-Select (macOS)" >>"$config"
        config_was_modified=1
    fi

    for line in "${config_lines[@]}"; do
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
        sleep 0.4 2>/dev/null || true
        flush_stdin
        print_success "Kitty configured successfully" "kitty_config"
    else
        print_info "Kitty already fully configured for zsh-edit-select on macOS"
    fi
}


_zes_set_alacritty_selection_clipboard_true() {
    local config="$1"

    if grep -qE '^[[:space:]]*save_to_clipboard[[:space:]]*=' "$config" 2>/dev/null; then
        sed_inplace 's/^[[:space:]]*save_to_clipboard[[:space:]]*=.*/save_to_clipboard = true/' "$config"
        return 0
    fi

    if grep -qE '^[[:space:]]*\[selection\][[:space:]]*$' "$config" 2>/dev/null; then
        local tmpfile
        local line
        local inserted=0

        tmpfile=$(mktemp 2>/dev/null) || return 1

        while IFS= read -r line || [[ -n "$line" ]]; do
            printf '%s\n' "$line" >>"$tmpfile"
            if [[ $inserted -eq 0 ]] && [[ "$line" =~ ^[[:space:]]*\[selection\][[:space:]]*$ ]]; then
                echo "save_to_clipboard = true" >>"$tmpfile"
                inserted=1
            fi
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
    fi

    {
        echo ""
        echo "[selection]"
        echo "save_to_clipboard = true"
    } >>"$config"
    return 0
}


_zes_upsert_alacritty_macos_toml_block() {
    local config="$1"
    local tmpfile
    local line
    local stripped
    local in_managed_block=0
    local in_legacy_block=0

    [[ -f "$config" ]] || return 1

    tmpfile=$(mktemp 2>/dev/null) || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        stripped="${stripped%"${stripped##*[![:space:]]}"}"

        if [[ "$stripped" == "# Zsh Edit-Select (macOS) BEGIN" ]]; then
            in_managed_block=1
            continue
        fi

        if [[ $in_managed_block -eq 1 ]]; then
            if [[ "$stripped" == "# Zsh Edit-Select (macOS) END" ]]; then
                in_managed_block=0
            fi
            continue
        fi

        if [[ "$stripped" == "# Zsh Edit-Select (macOS)" ]]; then
            in_legacy_block=1
            continue
        fi

        if [[ $in_legacy_block -eq 1 ]]; then
            if [[ -z "$stripped" ]] ||
                [[ "$stripped" == "# Cmd editing shortcuts" ]] ||
                [[ "$stripped" == "[[keyboard.bindings]]" ]] ||
                [[ "$stripped" =~ ^(key|mods|chars)[[:space:]]*= ]] ||
                [[ "$stripped" == "[selection]" ]] ||
                [[ "$stripped" =~ ^save_to_clipboard[[:space:]]*= ]]; then
                continue
            fi
            in_legacy_block=0
        fi

        printf '%s\n' "$line" >>"$tmpfile"
    done <"$config"

    cat >>"$tmpfile" <<'ALACRITTY_MACOS_TOML'

# Zsh Edit-Select (macOS) BEGIN
# Cmd editing shortcuts
[[keyboard.bindings]]
key = "A"
mods = "Command"
chars = "\u001b[97;9u"

[[keyboard.bindings]]
key = "C"
mods = "Command"
chars = "\u001b[99;9u"

[[keyboard.bindings]]
key = "V"
mods = "Command"
chars = "\u001b[118;9u"

[[keyboard.bindings]]
key = "X"
mods = "Command"
chars = "\u001b[120;9u"

[[keyboard.bindings]]
key = "Z"
mods = "Command"
chars = "\u001b[122;9u"

[[keyboard.bindings]]
key = "Z"
mods = "Command|Shift"
chars = "\u001b[122;10u"
# Zsh Edit-Select (macOS) END
ALACRITTY_MACOS_TOML

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


configure_alacritty_macos() {
    print_step "Configuring Alacritty (macOS)..."

    local config_toml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.toml"
    local config_yml="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty/alacritty.yml"
    local config_dir
    config_dir="$(dirname "$config_toml")"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Alacritty config directory: $config_dir"
        return 1
    fi

    local config=""
    if [[ -f "$config_toml" ]]; then
        config="$config_toml"
    elif [[ -f "$config_yml" ]]; then
        config="$config_yml"
    else
        config="$config_toml"
        touch "$config"
    fi

    backup_config "$config"

    if [[ "$config" == *.yml ]]; then
        if grep -qF "Zsh Edit-Select (macOS)" "$config" 2>/dev/null; then
            print_info "Alacritty (YAML) already configured for zsh-edit-select on macOS"
            return 0
        fi

        cat >>"$config" <<'ALACRITTY_MACOS_YAML'

# Zsh Edit-Select (macOS)
key_bindings:
  - { key: A, mods: Command, chars: "\x1b[97;9u" }
  - { key: C, mods: Command, chars: "\x1b[99;9u" }
  - { key: V, mods: Command, chars: "\x1b[118;9u" }
  - { key: X, mods: Command, chars: "\x1b[120;9u" }
  - { key: Z, mods: Command, chars: "\x1b[122;9u" }
  - { key: Z, mods: Command|Shift, chars: "\x1b[122;10u" }

selection:
  save_to_clipboard: true
ALACRITTY_MACOS_YAML

        print_success "Alacritty (YAML) configured successfully" "alacritty_config"
        return 0
    fi

    local before_hash=""
    local after_hash=""

    before_hash=$(cksum "$config" 2>/dev/null || true)

    if ! _zes_upsert_alacritty_macos_toml_block "$config"; then
        print_error "Failed to update Alacritty TOML config"
        return 1
    fi

    if ! _zes_set_alacritty_selection_clipboard_true "$config"; then
        print_warning "Could not set [selection].save_to_clipboard = true automatically"
    fi

    after_hash=$(cksum "$config" 2>/dev/null || true)

    if [[ -n "$before_hash" ]] && [[ "$before_hash" == "$after_hash" ]]; then
        print_info "Alacritty already fully configured for zsh-edit-select on macOS"
    else
        print_success "Alacritty configured successfully" "alacritty_config"
    fi
}


configure_wezterm_macos() {
    print_step "Configuring WezTerm (macOS)..."

    local config="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
    local config_alt="$HOME/.wezterm.lua"
    local config_dir

    if [[ -f "$config" ]]; then
        :
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

    if grep -qF "Zsh Edit-Select (macOS)" "$config" 2>/dev/null; then
        print_info "WezTerm already configured for zsh-edit-select on macOS"
        return 0
    fi

    local config_block
    config_block=$(
        cat <<'WEZTERM_MACOS'
-- Zsh Edit-Select (macOS)
local zes_wezterm = require 'wezterm'
local zes_act = zes_wezterm.action
config.keys = config.keys or {}
config.mouse_bindings = config.mouse_bindings or {}

local zes_macos_keys = {
  { key = 'a', mods = 'CMD', action = zes_act.SendString '\x1b[97;9u' },
  { key = 'v', mods = 'CMD', action = zes_act.SendString '\x1b[118;9u' },
  { key = 'x', mods = 'CMD', action = zes_act.SendString '\x1b[120;9u' },
  { key = 'z', mods = 'CMD', action = zes_act.SendString '\x1b[122;9u' },
  { key = 'z', mods = 'CMD|SHIFT', action = zes_act.SendString '\x1b[122;10u' },
  {
    key = 'c',
    mods = 'CMD',
    action = zes_wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel ~= '' then
        window:perform_action(zes_act.CopyTo 'Clipboard', pane)
      else
        window:perform_action(zes_act.SendString '\x1b[99;9u', pane)
      end
    end),
  },
  { key = 'LeftArrow', mods = 'CMD', action = zes_act.SendString '\x1b[1;9D' },
  { key = 'RightArrow', mods = 'CMD', action = zes_act.SendString '\x1b[1;9C' },
  { key = 'LeftArrow', mods = 'CMD|SHIFT', action = zes_act.SendString '\x1b[1;10D' },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = zes_act.SendString '\x1b[1;10C' },
  { key = 'UpArrow', mods = 'CMD|SHIFT', action = zes_act.SendString '\x1b[1;10A' },
  { key = 'DownArrow', mods = 'CMD|SHIFT', action = zes_act.SendString '\x1b[1;10B' },
}
for _, binding in ipairs(zes_macos_keys) do table.insert(config.keys, binding) end

local zes_macos_mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = zes_wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel ~= '' then
        pane:send_text('\x1b[>62300u')
      end
      window:perform_action(zes_act.ClearSelection, pane)
      window:perform_action(zes_act.SelectTextAtMouseCursor 'Cell', pane)
    end),
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = zes_wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel == '' then
        window:perform_action(zes_act.OpenLinkAtMouseCursor, pane)
      end
    end),
  },
  {
    event = { Up = { streak = 2, button = 'Left' } },
    mods = 'NONE',
    action = zes_act.Nop,
  },
  {
    event = { Up = { streak = 3, button = 'Left' } },
    mods = 'NONE',
    action = zes_act.Nop,
  },
}
for _, binding in ipairs(zes_macos_mouse_bindings) do table.insert(config.mouse_bindings, binding) end
WEZTERM_MACOS
    )

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
        MANUAL_STEPS+=("WezTerm (macOS): add zsh-edit-select bindings manually in wezterm.lua (see README.md)")
        return 1
    fi

    print_success "WezTerm configured successfully" "wezterm_config"
}


configure_ghostty_macos() {
    print_step "Configuring Ghostty (macOS)..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
    local config="$config_dir/config"

    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Failed to create Ghostty config directory: $config_dir"
        return 1
    fi

    [[ ! -f "$config" ]] && touch "$config"
    backup_config "$config"

    local -a config_lines=(
        "# Cmd editing shortcuts"
        "keybind = cmd+a=csi:97;9u"
        "keybind = cmd+c=csi:99;9u"
        "keybind = cmd+x=csi:120;9u"
        "keybind = cmd+z=csi:122;9u"
        "keybind = cmd+shift+z=csi:122;10u"
        ""
        "# Shift selection shortcuts"
        "keybind = shift+up=csi:1;2A"
        "keybind = shift+down=csi:1;2B"
        ""
        "# Cmd+Shift+Up/Down select to buffer boundaries"
        "keybind = cmd+shift+up=csi:1;10A"
        "keybind = cmd+shift+down=csi:1;10B"
        ""
        "# Needed for mouse integration"
        "copy-on-select = clipboard"
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

    if [[ $all_exist -eq 1 ]] && grep -qF "# Zsh Edit-Select (macOS)" "$config" 2>/dev/null; then
        print_info "Ghostty already fully configured for zsh-edit-select on macOS"
        return 0
    fi

    local config_was_modified=0
    if ! config_line_exists "$config" "# Zsh Edit-Select (macOS)"; then
        echo "" >>"$config"
        echo "# Zsh Edit-Select (macOS)" >>"$config"
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
        print_info "Ghostty already fully configured for zsh-edit-select on macOS"
    fi
}


_zes_iterm2_upsert_binding() {
    local plist_path="$1"
    local plist_buddy="$2"
    local key="$3"
    local action="$4"
    local text="$5"
    local label="$6"
    local path=":GlobalKeyMap:${key}"

    "$plist_buddy" -c "Delete ${path}" "$plist_path" 2>/dev/null || true
    "$plist_buddy" -c "Add ${path} dict" "$plist_path" || return 1
    "$plist_buddy" -c "Add ${path}:Action integer ${action}" "$plist_path" || return 1
    "$plist_buddy" -c "Add ${path}:Text string ${text}" "$plist_path" || return 1
    print_substep "Applied iTerm2 mapping: $label -> ESC${text}"
}


_zes_apply_iterm2_auto_config() {
    local plist_path="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
    local plist_buddy="/usr/libexec/PlistBuddy"
    local send_esc=10
    local backup_path="${plist_path}.backup-$(date +%Y%m%d-%H%M%S)"
    local i

    if [[ "$(uname -s 2>/dev/null)" != "Darwin" ]]; then
        print_warning "Automatic iTerm2 plist update is only supported on macOS."
        return 1
    fi

    if [[ ! -x "$plist_buddy" ]]; then
        print_warning "PlistBuddy not found at $plist_buddy; cannot auto-configure iTerm2."
        return 1
    fi

    if [[ ! -f "$plist_path" ]]; then
        print_warning "iTerm2 plist not found at $plist_path; cannot auto-configure iTerm2."
        return 1
    fi

    backup_file "$plist_path"
    if cp "$plist_path" "$backup_path" 2>/dev/null; then
        print_substep "Created iTerm2 plist backup: $backup_path"
    else
        print_warning "Could not create a local iTerm2 plist backup at $backup_path"
    fi

    if command_exists pgrep && pgrep -x "iTerm2" >/dev/null 2>&1; then
        print_substep "Closing iTerm2 before plist update..."
        if command_exists osascript; then
            osascript -e 'tell application "iTerm2" to quit' >/dev/null 2>&1 || true
        fi

        for i in {1..10}; do
            pgrep -x "iTerm2" >/dev/null 2>&1 || break
            sleep 1
        done

        if pgrep -x "iTerm2" >/dev/null 2>&1; then
            if command_exists pkill; then
                print_substep "iTerm2 is still running; force-closing..."
                pkill -x "iTerm2" >/dev/null 2>&1 || true
                sleep 1
            else
                print_warning "Could not force-close iTerm2 (pkill unavailable)."
            fi
        fi
    fi

    "$plist_buddy" -c "Add :GlobalKeyMap dict" "$plist_path" 2>/dev/null || true

    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0x61-0x100000" "$send_esc" "[97;9u" "Cmd+A (Select All)" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0x63-0x100000" "$send_esc" "[99;9u" "Cmd+C (Copy)" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0x78-0x100000" "$send_esc" "[120;9u" "Cmd+X (Cut)" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0x7a-0x100000" "$send_esc" "[122;9u" "Cmd+Z (Undo)" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0x5a-0x120000" "$send_esc" "[122;10u" "Cmd+Shift+Z (Redo)" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf702-0x300000" "$send_esc" "[1;9D" "Cmd+Left" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf703-0x300000" "$send_esc" "[1;9C" "Cmd+Right" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf702-0x320000" "$send_esc" "[1;10D" "Cmd+Shift+Left" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf703-0x320000" "$send_esc" "[1;10C" "Cmd+Shift+Right" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf700-0x320000" "$send_esc" "[1;10A" "Cmd+Shift+Up" || return 1
    _zes_iterm2_upsert_binding "$plist_path" "$plist_buddy" "0xf701-0x320000" "$send_esc" "[1;10B" "Cmd+Shift+Down" || return 1

    "$plist_buddy" -c "Delete :CopySelection" "$plist_path" 2>/dev/null || true
    "$plist_buddy" -c "Add :CopySelection bool false" "$plist_path" || return 1

    if command_exists killall; then
        killall cfprefsd >/dev/null 2>&1 || true
    fi

    print_success "iTerm2 plist updated via built-in installer automation" "iterm2_config"
    return 0
}


configure_iterm2_macos() {
    print_step "Configuring iTerm2 (macOS)..."

    print_info "Recommended: configure iTerm2 manually in the GUI."
    print_info "Automatic plist patching is available via this installer's built-in advanced mode, but can be risky in some setups."
    print_info "Open iTerm2 -> Settings -> Keys -> Key Bindings and add:"
    print_info "  Cmd+C -> Send Escape Sequence: [99;9u"
    print_info "  Cmd+A -> Send Escape Sequence: [97;9u"
    print_info "  Cmd+X -> Send Escape Sequence: [120;9u"
    print_info "  Cmd+Z -> Send Escape Sequence: [122;9u"
    print_info "  Cmd+Shift+Z -> Send Escape Sequence: [122;10u"
    print_info "  Cmd+Left -> Send Escape Sequence: [1;9D"
    print_info "  Cmd+Right -> Send Escape Sequence: [1;9C"
    print_info "  Cmd+Shift+Left -> Send Escape Sequence: [1;10D"
    print_info "  Cmd+Shift+Right -> Send Escape Sequence: [1;10C"
    print_info "  Cmd+Shift+Up -> Send Escape Sequence: [1;10A"
    print_info "  Cmd+Shift+Down -> Send Escape Sequence: [1;10B"

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_info "Non-interactive mode: skipping optional automatic iTerm2 plist update."
        print_success "iTerm2 manual configuration guidance provided" "iterm2_config"
        return 0
    fi

    if ! ask_yes_no "Apply iTerm2 settings automatically using built-in installer automation? (not recommended)" "n"; then
        print_success "iTerm2 manual configuration guidance provided" "iterm2_config"
        return 0
    fi

    print_warning "iTerm2 must be closed before running - macOS will overwrite plist changes if the app is open on exit. The installer automation quits it automatically, but double-check."

    if ! ask_yes_no "Proceed with automatic iTerm2 plist update now?" "n"; then
        print_info "Skipped automatic iTerm2 plist update. Manual GUI setup remains recommended."
        print_success "iTerm2 manual configuration guidance provided" "iterm2_config"
        return 0
    fi

    _zes_apply_iterm2_auto_config
}
