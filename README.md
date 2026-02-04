# Zsh Edit-Select

Modern text selection and editing for Zsh command line. Select text with **Shift + Arrow keys**,
type-to-replace, paste-to-replace, mouse selection integration, and clipboard integration for copy/cut/paste
like in GUI text editors.

![Demo](media/demo.gif)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration Wizard](#configuration-wizard)
- [Terminal Setup](#terminal-setup)
  - [Step 1: Configure Copy Shortcut](#step-1-configure-copy-shortcut)
  - [Step 2: Configure Undo and Redo Shortcut](#step-2-configure-undo-and-redo-shortcut)
  - [Step 3: Enable Shift Selection Keys](#step-3-enable-shift-selection-keys)
- [Platform Compatibility](#platform-compatibility)
- [Default Key Bindings Reference](#default-key-bindings-reference)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Acknowledgments](#acknowledgments)
- [References](#references)

---

## Overview

**Zsh Edit-Select** brings familiar text editor behaviors to your Zsh command line:

- ✅ **Shift selection** — Select text using Shift + Arrow keys
- ✅ **Type-to-replace** — Type over selected text to replace it
- ✅ **Paste-to-replace** — Paste clipboard content over selections
- ✅ **Mouse integration** — Works with text selected by mouse
- ✅ **Clipboard integration** — Works with X11 and Wayland
- ✅ **Standard shortcuts** — Ctrl+A (select all), Ctrl+C (copy), Ctrl+X (cut), Ctrl+V (paste), Ctrl+Z (undo),
  Ctrl+Shift+Z (redo)

> **Customization:** The plugin works after installation with editor-like defaults. Use the command
> `edit-select config` to customize clipboard backend, mouse behavior, and keybindings.
>
> **Example Setup:** Check out [dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) to see how this
> plugin is integrated into a complete real-world environment (Kitty + Zsh + VS Code).

---

## Features

### Keyboard Selection

Select text using familiar keyboard shortcuts:

| Shortcut               | Action                                          |
| ---------------------- | ----------------------------------------------- |
| **Shift + ←/→**        | Select character by character                   |
| **Shift + ↑/↓**        | Select line by line                             |
| **Shift + Home/End**   | Select to line start/end                        |
| **Shift + Ctrl + ←/→** | Select word by word                             |
| **Ctrl + A**           | Select all text (including multi-line commands) |

### Mouse Selection Integration

The plugin intelligently integrates mouse selections:

**When Mouse Replacement is Enabled (default):**

- ✅ Copy mouse selections with Ctrl+C
- ✅ Cut mouse selections with Ctrl+X
- ✅ Type to replace mouse selections
- ✅ Delete mouse selections with Backspace/Delete
- ✅ Paste over mouse selections with Ctrl+V

**When Mouse Replacement is Disabled:**

- ✅ Copy mouse selections with Ctrl+C _(still works)_
- ✅ Replacement/Deletion work with keyboard selections

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 2

### Type-to-Replace and Paste-to-Replace

Type or paste while text is selected to replace it automatically.

Works with both keyboard and mouse selections (when mouse replacement is enabled).

<details>
<summary><b>⚠️ Mouse Replacement Note (Safeguard Prompt)</b></summary>

If you see the message **"Duplicate text: place cursor inside the occurrence you want to modify"**, the plugin
has detected multiple identical occurrences of the selected text in your command buffer.

**When does this appear?** This message only appears when:

- The selection was made with the mouse, AND
- The exact same text occurs more than once in the buffer, AND
- You try to replace the selected text by either typing or pasting

**Why does this happen?** This is a protective safeguard for the plugin's mouse-selection workaround. Since
mouse replacement is not enabled by default, the implemented workaround cannot automatically distinguish
between multiple occurrences of identical text. This prompt prevents accidental edits to the wrong occurrence
when using mouse-based selection.

**What should you do?** When prompted, place the cursor inside the specific occurrence you want to edit, then
retry the operation (select it and type or paste to replace).

**Note:** This safeguard is only for mouse selections. Using `Shift+Arrow keys` doesn't require caret
replacement and works directly without ambiguity or extra prompting.

</details>

### Copy, Cut, and Paste

Standard editing shortcuts:

- **Ctrl + C** (or Ctrl+Shift+C): Copy selected text
- **Ctrl + X**: Cut selected text
- **Ctrl + V**: Paste (replaces selection if any)

### Undo and Redo

Navigate through your command line editing history:

- **Ctrl + Z**: Undo last edit
- **Ctrl + Shift + Z**: Redo last undone edit

> **Note:** The Ctrl+Z keybinding works seamlessly alongside the traditional suspend process functionality
> (Ctrl+Z suspends a running foreground process to background). The plugin intelligently handles undo
> operations for command line editing while preserving the ability to suspend processes when needed.

> **Note:** The Copy and the Redo keybinding (Ctrl+Shift+Z) requires terminal configuration to send the
> correct escape sequence. See [Terminal Setup](#terminal-setup) for configuration instructions.

### Automatic Clipboard Detection

The plugin automatically detects your display server:

| Display Server | Tools Used             |
| -------------- | ---------------------- |
| **Wayland**    | `wl-copy` / `wl-paste` |
| **X11**        | `xclip`                |
| **macOS**      | `pbcopy` / `pbpaste`   |

> **Recommendation:** X11 is recommended for the best experience with all plugin features, especially mouse
> selection replacement.

---

## Quick Start

### 1. Install the Plugin

**Oh My Zsh:** (for other plugin managers check [Installation](#installation))

```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select
```

Add to your `.zshrc`:

```bash
plugins=(... zsh-edit-select)
```

**Manual:**

```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ~/.local/share/zsh/plugins/zsh-edit-select

# Add to ~/.zshrc:
source ~/.local/share/zsh/plugins/zsh-edit-select/zsh-edit-select.plugin.zsh
```

### 2. Install Clipboard Tools

<details>
<summary><b>How to check if you're using X11 or Wayland</b></summary>

Run this command in your terminal:

```bash
echo $XDG_SESSION_TYPE
```

- If it returns `x11` → You're using X11
- If it returns `wayland` → You're using Wayland

> **Note:** Most users are on X11 by default, especially on older distributions or systems with NVIDIA GPUs.

> **Recommendation:** X11 is recommended for the best experience with all plugin features, especially mouse
> selection replacement.

</details>

<details>
<summary><b>Wayland</b></summary>

**Debian/Ubuntu:**

```bash
sudo apt install wl-clipboard
```

**Arch Linux:**

```bash
sudo pacman -S wl-clipboard
```

**Fedora:**

```bash
sudo dnf install wl-clipboard
```

</details>

<details>
<summary><b>X11</b> (Most common)</summary>

**Debian/Ubuntu:**

```bash
sudo apt install xclip
```

**Arch Linux:**

```bash
sudo pacman -S xclip
```

**Fedora:**

```bash
sudo dnf install xclip
```

</details>

### 3. Configure Your Terminal

Some terminals need configuration to support Shift selection. See [Terminal Setup](#terminal-setup) for
details.

### 4. Restart Your Shell

```bash
source ~/.zshrc
```

> **Important:** You may need to fully close and reopen your terminal (not just source ~/.zshrc) for all
> features to work correctly, especially in some terminal emulators.

**You're ready!** Try selecting text with Shift + Arrow keys.

### 5. (Optional) Customize Settings

The plugin works immediately with sensible defaults, but you can customize:

- Clipboard backend (Wayland/X11/auto-detect)
- Mouse replacement behavior
- Keybindings (Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z)

Run the interactive configuration wizard:

```bash
edit-select config
```

---

## Installation

<details>
<summary><b>Oh My Zsh</b></summary>

1. Clone the repository:

```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select
```

2. Add to your `.zshrc`:

```bash
plugins=(
  # ... other plugins
  zsh-edit-select
)
```

3. Restart your terminal or run:

```bash
source ~/.zshrc
```

</details>

<details>
<summary><b>zgenom</b></summary>

Add to your `.zshrc`:

```bash
zgenom load Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>sheldon</b></summary>

Run:

```bash
sheldon add zsh-edit-select --github Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>Manual Installation</b></summary>

1. Clone the repository:

```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ~/.local/share/zsh/plugins/zsh-edit-select
```

2. Add to your `.zshrc`:

```bash
source ~/.local/share/zsh/plugins/zsh-edit-select/zsh-edit-select.plugin.zsh
```

3. Restart your terminal or run:

```bash
source ~/.zshrc
```

</details>

---

## Configuration Wizard

Launch the interactive configuration wizard:

```bash
edit-select config
```

The wizard provides:

1. **Clipboard Integration** — Choose Wayland, X11, or auto-detect
2. **Mouse Replacement** — Enable/disable mouse selection integration
3. **Key Bindings** — Customize Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z shortcuts
4. **View Configuration** — See current settings
5. **Reset to Defaults** — Restore factory settings

All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions.

</details>

<details>
<summary><b> Mouse Replacement Modes </b></summary>

Configure how the plugin handles mouse selections:

**Enabled (default):**

- Full integration: type, paste, cut, and delete work with mouse selections
- Best for users who want seamless mouse+keyboard workflow

**Disabled:**

- Mouse selections can be copied with Ctrl+C
- Typing, pasting, cutting, and deleting only work with keyboard selections
- Best for users who prefer strict keyboard-only editing

Change the mode:

```bash
edit-select config  # → Option 2: Mouse Replacement
```

> **Note:** On some systems, the mouse-replacement feature may cause performance issues and make some
> operations slower, especially with long multi-line commands(typically more than 10 lines). If you notice
> this behavior, you can disable mouse replacement using the wizard.

</details>

<details>
<summary><b> Clipboard Integration </b></summary>

The plugin auto-detects your clipboard backend, but you can override it:

**Auto-detect (recommended):** Automatically uses the right tool for your display server.

> **Note:** If no clipboard tool is detected, the plugin will still work for text selection and keyboard-based
> operations, but copy/cut/paste will be disabled.

**Manual configuration:**

```bash
edit-select config  # → Option 1: Clipboard Integration
```

Choose:

- **Wayland** — Uses `wl-copy`/`wl-paste`
- **X11** — Uses `xclip`
</details>

<details>
<summary><b> Keybinding Customization </b></summary>

Customize the main editing shortcuts:

```bash
edit-select config  # → Option 3: Key Bindings
```

**Default bindings:**

> **Tip:** If you’re unsure how keybindings integrate with your shell or terminal, take a look at the
> [dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) repository for a working reference
> implementation.

- **Ctrl + A** — Select all
- **Ctrl + V** — Paste
- **Ctrl + X** — Cut
- **Ctrl + Z** — Undo
- **Ctrl + Shift + Z** — Redo

</details>

<details>
<summary><b>Custom Keybinding Notes (Terminal Configuration)</b></summary>

> **⚠️ Important:** When using custom keybindings (especially with Shift modifiers), you may need to configure
> your terminal emulator to send the correct escape sequences.

**To find the escape sequence for any key combination:**

1. Run `cat` (without arguments) in your terminal
2. Press the key combination
3. The terminal will display the escape sequence
4. Use this sequence in your configuration

For example, if you want to use `Ctrl + Shift + X` for cut add the following to your terminal dotfile:

<details>
<summary><b>Kitty</b></summary>

Add to `kitty.conf`:

```conf
map ctrl+shift+x send_text all \x1b[88;6u
```

</details>

<details>
<summary><b>WezTerm</b></summary>

Add to `wezterm.lua`:

```lua
return {
  keys = {
    {
      key = 'X',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.SendString '\x1b[88;6u',
    },
  },
}
```

</details>

<details>
<summary><b>Alacritty</b></summary>

Add to `alacritty.yml`:

```yaml
key_bindings:
  - { key: X, mods: Control|Shift, chars: "\x1b[88;6u" }
```

Or for `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "X"
mods = "Control|Shift"
chars = "\u001b[88;6u"
```

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json`:

```json
[
  {
    "key": "ctrl+shift+x",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[88;6u" },
    "when": "terminalFocus"
  }
]
```

</details>

</details>

---

## Terminal Setup

<details>
<summary><b>How to Find Escape Sequences</b></summary>

**To find the escape sequence for any key combination:**

1. Run `cat` (without arguments) in your terminal
2. Press the key combination
3. The terminal will display the escape sequence
4. Use this sequence in your configuration

</details>

### Step 1: Configure Copy Shortcut

> **⚠️ CRITICAL:** Before adding these mappings, you **MUST** remove or comment out any existing
> `ctrl+shift+c` mappings in your terminal config (such as `map ctrl+shift+c copy_to_clipboard` in Kitty).
> These will conflict and prevent the plugin from working correctly.

<details>
<summary><b>Kitty</b></summary>

### Using Ctrl+Shift+C (Default)

To use Ctrl+Shift+C for copying, add the following to `kitty.conf`:

```conf
map ctrl+shift+c send_text all \x1b[67;6u
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying (like in GUI applications) and Ctrl+Shift+C for interrupt:

```conf
# Ctrl+C sends the escape sequence for copying
map ctrl+c send_text all \x1b[67;6u

# Ctrl+Shift+C sends interrupt (default behavior)
map ctrl+shift+c send_text all \x03
```

</details>

<details>
<summary><b>WezTerm</b></summary>

### Using Ctrl+Shift+C (Default)

To use Ctrl+Shift+C for copying, add the following to `wezterm.lua`:

```lua
return {
  keys = {
    {
      key = 'C',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.SendString '\x1b[67;6u',
    },
  },
}
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying and Ctrl+Shift+C for interrupt:

```lua
return {
  keys = {
    {
      -- Ctrl+C sends the escape sequence for copying
      key = 'c',
      mods = 'CTRL',
      action = wezterm.action.SendString '\x1b[67;6u',
    },
    {
      -- Ctrl+Shift+C sends interrupt signal
      key = 'C',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.SendString '\x03',
    },
  },
}
```

</details>

<details>
<summary><b>Alacritty</b></summary>

### Using Ctrl+Shift+C (Default)

To use Ctrl+Shift+C for copying, add the following to `alacritty.yml`:

```yaml
key_bindings:
  - { key: C, mods: Control|Shift, chars: "\x1b[67;6u" }
```

Or for `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
chars = "\u001b[67;6u"
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying and Ctrl+Shift+C for interrupt:

**For `alacritty.yml`:**

```yaml
key_bindings:
  # Ctrl+C sends the escape sequence for copying
  - { key: C, mods: Control, chars: "\x1b[67;6u" }

  # Ctrl+Shift+C sends interrupt signal
  - { key: C, mods: Control|Shift, chars: "\x03" }
```

**For `alacritty.toml`:**

```toml
# Ctrl+C sends the escape sequence for copying
[[keyboard.bindings]]
key = "C"
mods = "Control"
chars = "\u001b[67;6u"

# Ctrl+Shift+C sends interrupt signal
[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
chars = "\u0003"
```

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

### Using Ctrl+Shift+C (Default)

To use Ctrl+Shift+C for copying, add the following to `keybindings.json`:

```json
[
  {
    "key": "ctrl+shift+c",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[67;6u" },
    "when": "terminalFocus"
  }
]
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying and Ctrl+Shift+C for interrupt:

```json
[
  {
    // Ctrl+C sends copy sequence to terminal
    "key": "ctrl+c",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[67;6u" },
    "when": "terminalFocus"
  },
  {
    // Ctrl+Shift+C sends interrupt signal
    "key": "ctrl+shift+c",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u0003" },
    "when": "terminalFocus"
  }
]
```

</details>

<details>
<summary><b>Alternative: Without Terminal Remapping</b></summary>

If your terminal doesn't support key remapping, you can add the following to your `~/.zshrc` to use **Ctrl +
/** for copying:

```sh
x-copy-selection () {
  if [[ $MARK -ne $CURSOR ]]; then
    local start=$(( MARK < CURSOR ? MARK : CURSOR ))
    local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
    local selected="${BUFFER:$start:$length}"
    print -rn "$selected" | xclip -selection clipboard
  fi
}
zle -N x-copy-selection
bindkey '^_' x-copy-selection
```

You can change the keybinding to any key you prefer. For example, to use **Ctrl + K**:

```sh
bindkey '^K' x-copy-selection
```

> **Note:** The `^_` sequence represents Ctrl + / (Ctrl + Slash), and `^K` represents Ctrl + K. You can find
> other key sequences by running `cat` in your terminal and pressing the desired key combination.

> **Bonus Feature:** If no text is selected, this manual keybinding will copy the entire current line to the
> clipboard.

</details>

---

### Step 2: Configure Undo and Redo Shortcut

<details>
<summary><b>Kitty</b></summary>

Add to `kitty.conf`:

```conf
map ctrl+shift+z send_text all \x1b[90;6u
```

</details>

<details>
<summary><b>WezTerm</b></summary>

Add to `wezterm.lua`:

```lua
return {
  keys = {
    {
      key = 'Z',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.SendString '\x1b[90;6u',
    },
  },
}
```

</details>

<details>
<summary><b>Alacritty</b></summary>

Add to `alacritty.yml`:

```yaml
key_bindings:
  - { key: Z, mods: Control|Shift, chars: "\x1b[90;6u" }
```

Or for `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "Z"
mods = "Control|Shift"
chars = "\u001b[90;6u"
```

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json`:

```json
[
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
  }
]
```

> **Note:** The Ctrl+Z keybinding works seamlessly alongside the traditional suspend process functionality
> (Ctrl+Z suspends a running foreground process to background). The plugin intelligently handles undo
> operations for command line editing while preserving the ability to suspend processes when needed.

</details>

---

### Step 3: Enable Shift Selection Keys

Some terminals intercept Shift key combinations by default. Here's how to configure popular terminals:

<details>
<summary><b>Kitty</b></summary>

Add to `kitty.conf`:

```conf
# Enable Shift selection
map ctrl+shift+left no_op
map ctrl+shift+right no_op
map ctrl+shift+home no_op
map ctrl+shift+end no_op
```

</details>

> **Looking for a reference?** The [dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) repository
> contains ready-to-use configurations for **Kitty** (`kitty.conf`) and **VS Code** (`keybindings.json`) that
> act as a great starting point for integrating this plugin.

<details>
<summary><b>WezTerm</b></summary>

Add to `wezterm.lua`:

```lua
return {
  keys = {
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  },
}
```

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json`:

```json
[
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
  }
]
```

</details>

<details>
<summary><b>Alacritty</b></summary>

Alacritty doesn't need a tweak to enable Shift/Shift+Ctrl selection, but you will need to configure the copy
shortcuts for the clipboard the same as the other terminals.

</details>

---

## Platform Compatibility

<details>
<summary><b>Mouse Selection Replacement Feature</b></summary>

The **Mouse Selection Replacement** feature (automatically detecting and replacing mouse-selected text) has
varying support across platforms:

### ✅ Fully Supported

- **X11** - Complete PRIMARY selection support (recommended for best experience)
- **wlroots-based Wayland compositors** - Sway, Hyprland, River, Wayfire
- **KDE Plasma Wayland** - Full PRIMARY selection support

### ⚠️ Limited/No Support

- **GNOME Wayland (Mutter)** - No PRIMARY selection support
- **macOS** - No PRIMARY selection concept in the system
- **Other Wayland compositors** - Support varies

### Recommendation

For the most stable and robust experience with all plugin features, **X11 is recommended**. While Wayland
support is improving, PRIMARY selection implementation is inconsistent across compositors.

If Mouse Selection Replacement doesn't work on your platform, disable it with `edit-select config` → Option 2.

</details>

<details>
<summary><b>Testing Coverage</b></summary>

This plugin has been thoroughly and heavily tested on **Kitty Terminal** on X11 and briefly on other popular
terminals.

If you encounter issues on other terminals or platforms, please
[open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with your terminal name, OS, and
display server.

</details>

<details>
<summary><b>Core Features (Available on All Platforms)</b></summary>

These features work universally regardless of platform:

- ✅ Shift+Arrow keys for text selection
- ✅ Ctrl+A (Cmd+A) to select all
- ✅ Ctrl+C (Cmd+C) to copy
- ✅ Ctrl+X (Cmd+X) to cut keyboard selection
- ✅ Ctrl+V (Cmd+V) to paste
- ✅ Ctrl+Z (Cmd+Z) to undo
- ✅ Ctrl+Shift+Z (Cmd+Shift+Z) to redo
- ✅ Delete/Backspace to remove keyboard selection
- ✅ Type or paste to replace keyboard selection

</details>

---

## Default Key Bindings Reference

### Selection Keys

| Key Combination      | Action                     |
| -------------------- | -------------------------- |
| **Shift + ←**        | Select one character left  |
| **Shift + →**        | Select one character right |
| **Shift + ↑**        | Select one line up         |
| **Shift + ↓**        | Select one line down       |
| **Shift + Home**     | Select to line start       |
| **Shift + End**      | Select to line end         |
| **Shift + Ctrl + ←** | Select to word start       |
| **Shift + Ctrl + →** | Select to word end         |
| **Ctrl + A**         | Select all text            |

> **macOS:** Use **Shift + Option** instead of **Shift + Ctrl** for word navigation

### Editing Keys (for Selected Text)

| Key Combination      | Action                            |
| -------------------- | --------------------------------- |
| **Ctrl + C**         | Copy selected text                |
| **Ctrl + X**         | Cut selected text                 |
| **Ctrl + V**         | Paste (replaces selection if any) |
| **Ctrl + Z**         | Undo last edit                    |
| **Ctrl + Shift + Z** | Redo last undone edit             |
| **Delete/Backspace** | Delete selected text              |
| **Any character**    | Replace selected text             |

---

## Troubleshooting

<details>
<summary><b>Shift selection doesn't work</b></summary>

**Solution:** Configure your terminal to pass Shift key sequences. See [Terminal Setup](#terminal-setup).

**Verify:** Run `cat` and press Shift+Left. You should see an escape sequence like `^[[1;2D`.

</details>

<details>
<summary><b>Clipboard operations don't work</b></summary>

**Solution:** Install the required clipboard tool:

- Wayland: `wl-clipboard`
- X11: `xclip`

**Verify:** Run `wl-copy <<< "test"` or `xclip -i <<< "test"` to check if the tool works.

</details>

<details>
<summary><b>Mouse replacement not working</b></summary>

**Solution:**

1. Check if mouse replacement is enabled: `edit-select config` → View Configuration
2. Ensure your terminal supports mouse selection (most do)
3. Try selecting text with your mouse, then typing—it should replace the selection

If this does not work for you, it is often due to platform limitations or compatibility issues with the
PRIMARY selection (which is unavailable on macOS). See [Platform Compatibility](#platform-compatibility) for
more details.

</details>

<details>
<summary><b>Ctrl+C doesn't copy</b></summary>

**Solution:** Configure your terminal to remap Ctrl+C. See [Kitty](#kitty) or
[VS Code Terminal](#vs-code-terminal) sections.

**Alternative:** Use Ctrl+Shift+C for copying, or configure a custom keybinding with `edit-select config`, or
use the 'Without Terminal Remapping' method if your terminal doesn't support key remapping.

</details>

<details>
<summary><b>Configuration wizard doesn't launch</b></summary>

**Symptoms:** Running `edit-select config` shows "file not found" error

**Solution:**

1. Check the plugin was installed correctly
2. Verify `edit-select-wizard.zsh` exists in the plugin directory
3. Ensure the file has read permissions:
   ```bash
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/edit-select-wizard.zsh
   ```
4. Try sourcing your `.zshrc` again: `source ~/.zshrc`
5. Fully close and reopen your terminal

</details>

<details>
<summary><b>Delete key not removing mouse-selected text</b></summary>

If the `Delete` key does not remove mouse-selected text, ensure your `~/.zshrc` does not contain a line that
forces the Delete key to the default handler such as:

```bash
bindkey '^[[3~' delete-char
```

That line will override the plugin's binding for the Delete key and prevent `zsh-edit-select` from handling
mouse selections correctly.

**Solution:** Remove or comment out that line and reload your shell:

```bash
source ~/.zshrc
```

</details>

---

## License

This project is licensed under the [MIT License](http://opensource.org/licenses/MIT/).

---

## Acknowledgments

Began as a fork ([Michael-Matta1/zsh-shift-select](https://github.com/Michael-Matta1/zsh-shift-select)) of
[jirutka/zsh-shift-select](https://github.com/jirutka/zsh-shift-select) to add the ability to copy selected
text, because the jirutka/zsh-shift-select plugin only supported deleting selected text and did not offer
copying by default.

This feature was frequently requested by the community, as shown in
[issue #8](https://github.com/jirutka/zsh-shift-select/issues/8) and
[issue #10](https://github.com/jirutka/zsh-shift-select/issues/10).

Since then, the project has evolved with its own new features, enhancements, bug fixes, design improvements,
and a fully changed codebase, and it now provides a full editor-like experience.

---

## References

- [Michael-Matta1/dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) — Example dotfiles
  demonstrating the plugin in action with Kitty terminal, VS Code, and Zsh integration.

- [Zsh zle shift selection — StackOverflow](https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection)

- [Zsh Line Editor Documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
