# Zsh Edit-Select

Modern text selection and editing for Zsh command line. Select text with **Shift + Arrow keys**,
type-to-replace, paste-to-replace, mouse selection integration, and clipboard integration for copy/cut/paste
like in GUI text editors.

![Demo](media/demo.gif)

---

## Table of Contents

- [Zsh Edit-Select](#zsh-edit-select)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Features](#features)
    - [Keyboard Selection](#keyboard-selection)
    - [Mouse Selection Integration](#mouse-selection-integration)
    - [Type-to-Replace and Paste-to-Replace](#type-to-replace-and-paste-to-replace)
    - [Copy, Cut, and Paste](#copy-cut-and-paste)
    - [Automatic Clipboard Detection](#automatic-clipboard-detection)
  - [Quick Start](#quick-start)
    - [1. Install the Plugin](#1-install-the-plugin)
    - [2. Install Clipboard Tools](#2-install-clipboard-tools)
    - [3. Configure Your Terminal](#3-configure-your-terminal)
    - [4. Restart Your Shell](#4-restart-your-shell)
    - [5. (Optional) Customize Settings](#5-optional-customize-settings)
  - [Installation](#installation)
  - [Configuration](#configuration)
    - [Configuration Wizard](#configuration-wizard)
    - [Mouse Replacement Modes](#mouse-replacement-modes)
    - [Clipboard Integration](#clipboard-integration)
    - [Keybinding Customization](#keybinding-customization)
        - [Custom Keybinding Notes](#custom-keybinding-notes)
  - [Terminal Setup](#terminal-setup)
    - [Step 1: Configure Copy Shortcut](#step-1-configure-copy-shortcut)
      - [Using Ctrl+Shift+C (Default)](#using-ctrlshiftc-default)
      - [Using Ctrl+C for Copying (Reversed)](#using-ctrlc-for-copying-reversed)
      - [Alternative: Without Terminal Remapping](#alternative-without-terminal-remapping)
    - [Step 2: Enable Shift Selection Keys](#step-2-enable-shift-selection-keys)
      - [Kitty](#kitty)
      - [WezTerm](#wezterm)
      - [VS Code Terminal](#vs-code-terminal)
      - [Alacritty](#alacritty)
    - [Step 3: Verify Key Sequences](#step-3-verify-key-sequences)
  - [Platform Compatibility](#platform-compatibility)
    - [Mouse Selection Replacement Feature](#mouse-selection-replacement-feature)
      - [✅ Fully Supported](#-fully-supported)
      - [⚠️ Limited/No Support](#️-limitedno-support)
      - [Recommendation](#recommendation)
    - [Testing Coverage](#testing-coverage)
    - [Core Features (Available on All Platforms)](#core-features-available-on-all-platforms)
  - [Key Bindings Reference](#key-bindings-reference)
    - [Selection Keys](#selection-keys)
    - [Editing Keys](#editing-keys)
  - [Common Issues - Quick Fixes](#common-issues---quick-fixes)
  - [Troubleshooting](#troubleshooting)
    - [Shift selection doesn't work](#shift-selection-doesnt-work)
    - [Clipboard operations don't work](#clipboard-operations-dont-work)
    - [Mouse replacement not working](#mouse-replacement-not-working)
    - [Duplicate-text prompt](#duplicate-text-prompt)
    - [Ctrl+C doesn't copy](#ctrlc-doesnt-copy)
    - [Configuration wizard doesn't launch](#configuration-wizard-doesnt-launch)
  - [License](#license)
  - [Acknowledgments](#acknowledgments)
  - [References](#references)

---

## Overview

**Zsh Edit-Select** brings familiar text editor behaviors to your Zsh command line:

-   ✅ **Shift selection** — Select text using Shift + Arrow keys
-   ✅ **Type-to-replace** — Type over selected text to replace it
-   ✅ **Paste-to-replace** — Paste clipboard content over selections
-   ✅ **Mouse integration** — Works with text selected by mouse
-   ✅ **Clipboard integration** — Works with X11 and Wayland
-   ✅ **Standard shortcuts** — Ctrl+A (select all), Ctrl+C (copy), Ctrl+X (cut), Ctrl+V (paste)

> **Ready to Use:** The plugin works immediately after installation with sensible defaults. Use the command
> `edit-select config` to customize clipboard backend, mouse behavior, and keybindings.

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

-   ✅ Copy mouse selections with Ctrl+C
-   ✅ Cut mouse selections with Ctrl+X
-   ✅ Type to replace mouse selections
-   ✅ Delete mouse selections with Backspace/Delete
-   ✅ Paste over mouse selections with Ctrl+V

**When Mouse Replacement is Disabled:**

-   ✅ Copy mouse selections with Ctrl+C _(still works)_
-   ✅ Replacement/Deletion work with keyboard selections

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 2

### Type-to-Replace and Paste-to-Replace

Type or paste while text is selected to replace it automatically.

Works with both keyboard and mouse selections (when mouse replacement is enabled).

### Copy, Cut, and Paste

Standard editing shortcuts:

-   **Ctrl + C** (or Ctrl+Shift+C): Copy selected text
-   **Ctrl + X**: Cut selected text
-   **Ctrl + V**: Paste (replaces selection if any)

### Automatic Clipboard Detection

The plugin automatically detects your display server:

| Display Server | Tools Used             |
| -------------- | ---------------------- |
| **Wayland**    | `wl-copy` / `wl-paste` |
| **X11**        | `xclip`                |
| **macOS**      | `pbcopy` / `pbpaste`   |

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

**Wayland:**

```bash
# Debian/Ubuntu
sudo apt install wl-clipboard

# Arch Linux
sudo pacman -S wl-clipboard

# Fedora
sudo dnf install wl-clipboard
```

**X11:**

```bash
# Debian/Ubuntu
sudo apt install xclip

# Arch Linux
sudo pacman -S xclip

# Fedora
sudo dnf install xclip
```

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

-   Clipboard backend (Wayland/X11/auto-detect)
-   Mouse replacement behavior
-   Keybindings (Ctrl+A, Ctrl+V, Ctrl+X)

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

## Configuration

### Configuration Wizard

Launch the interactive configuration wizard:

```bash
edit-select config
```

The wizard provides:

1. **Clipboard Integration** — Choose Wayland, X11, or auto-detect
2. **Mouse Replacement** — Enable/disable mouse selection integration
3. **Key Bindings** — Customize Ctrl+A, Ctrl+V, Ctrl+X shortcuts
4. **View Configuration** — See current settings
5. **Reset to Defaults** — Restore factory settings

All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions.

### Mouse Replacement Modes

Configure how the plugin handles mouse selections:

**Enabled (default):**

-   Full integration: type, paste, cut, and delete work with mouse selections
-   Best for users who want seamless mouse+keyboard workflow

**Disabled:**

-   Mouse selections can be copied with Ctrl+C
-   Typing, pasting, cutting, and deleting only work with keyboard selections
-   Best for users who prefer strict keyboard-only editing

Change the mode:

```bash
edit-select config  # → Option 2: Mouse Replacement
```

> **Note:** If you have mouse replacement enabled, the repositioning of the text cursor (caret) when clicking
> with the mouse may become slower on some systems when working with long multi-line commands (typically more
> than 10 lines). If you care more about fast mouse-click cursor positioning than about the mouse-replacement
> feature, you can disable mouse replacement using the wizard.

### Clipboard Integration

The plugin auto-detects your clipboard backend, but you can override it:

**Auto-detect (recommended):** Automatically uses the right tool for your display server.

> **Note:** If no clipboard tool is detected, the plugin will still work for text selection and keyboard-based
> operations, but copy/cut/paste will be disabled.

**Manual configuration:**

```bash
edit-select config  # → Option 1: Clipboard Integration
```

Choose:

-   **Wayland** — Uses `wl-copy`/`wl-paste`
-   **X11** — Uses `xclip`

### Keybinding Customization

Customize the main editing shortcuts:

```bash
edit-select config  # → Option 3: Key Bindings
```

**Default bindings:**

-   **Ctrl + A** — Select all
-   **Ctrl + V** — Paste
-   **Ctrl + X** — Cut

**Alternative presets:**

-   **Ctrl + Shift + A/V/X** — For terminals with Kitty protocol
-   **Custom** — Enter your own key sequences

##### Custom Keybinding Notes

> **⚠️ Important:** When using custom keybindings (especially with Shift modifiers), you may need to configure
> your terminal emulator to send the correct escape sequences.

**For Kitty:**

If you want to use `Ctrl + Shift + X` for cut, add this to your `kitty.conf`:

```conf
map ctrl+shift+x send_text all \x1b[88;6u
```

**For Other Terminals:**

-   **WezTerm** — Use similar key remapping in `wezterm.lua`
-   **Alacritty** — Use key bindings in `alacritty.yml`
-   **VS Code Terminal** — Add to `keybindings.json`

---

## Terminal Setup

### Step 1: Configure Copy Shortcut

> **⚠️ CRITICAL:** Before adding these mappings, you **MUST** remove or comment out any existing
> `ctrl+shift+c` mappings in your terminal config (such as `map ctrl+shift+c copy_to_clipboard` in Kitty).
> These will conflict and prevent the plugin from working correctly.

#### Using Ctrl+Shift+C (Default)

To use Ctrl + Shift + C for copying, add the following to your kitty.conf:

```conf
map ctrl+shift+c send_text all \x1b[67;6u
```

#### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl + C for copying (like in GUI applications) and Ctrl + Shift + C for interrupt:

```conf
# Ctrl+C sends the escape sequence for copying
map ctrl+c send_text all \x1b[67;6u


# Ctrl+Shift+C sends interrupt (default behavior)
map ctrl+shift+c send_text all \x03
```

**For Other Terminals:**

-   **WezTerm** — Use similar key remapping in `wezterm.lua`
-   **Alacritty** — Use key bindings in `alacritty.yml`

#### Alternative: Without Terminal Remapping

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

---

### Step 2: Enable Shift Selection Keys

Some terminals intercept Shift key combinations by default. Here's how to configure popular terminals:

#### Kitty

Add to `kitty.conf`:

```conf
# Enable Shift selection
map ctrl+shift+left no_op
map ctrl+shift+right no_op
map ctrl+shift+home no_op
map ctrl+shift+end no_op
```

#### WezTerm

Add to `wezterm.lua`:

```lua
return {
  keys = {
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = 'DisableDefaultAssignment' },
  },
}
```

#### VS Code Terminal

The escape sequences used follow the ANSI/VT terminal protocol.

Add to **`keybindings.json`**:

```json
[
    {
        // Make Ctrl+C sends copy sequence to terminal (CSI 67 ; 6 u)
        "key": "ctrl+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u001b[67;6u" },
        "when": "terminalFocus"
    },
    {
        // Make Ctrl+Shift+C sends interrupt signal (ETX control character)
        // This is equivalent to the traditional Ctrl+C interrupt behavior
        "key": "ctrl+shift+c",
        "command": "workbench.action.terminal.sendSequence",
        "args": { "text": "\u0003" },
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
    }
]
```

#### Alacritty

Alacritty doesn't need a tweak to enable Shift/Shift+Ctrl selection, but you will need to configure the copy
shortcuts for the clipboard the same as the other terminals.

---

### Step 3: Verify Key Sequences

To check what your terminal sends:

1. Run `cat` (without arguments)
2. Press the key combination
3. The terminal will display the escape sequence

Use this sequence for custom keybindings in the configuration wizard and replace the "text" values in the
configuration of VS Code Terminal.

---

## Platform Compatibility

### Mouse Selection Replacement Feature

The **Mouse Selection Replacement** feature (automatically detecting and replacing mouse-selected text) has
varying support across platforms:

#### ✅ Fully Supported

-   **X11** - Complete PRIMARY selection support (recommended for best experience)
-   **wlroots-based Wayland compositors** - Sway, Hyprland, River, Wayfire
-   **KDE Plasma Wayland** - Full PRIMARY selection support

#### ⚠️ Limited/No Support

-   **GNOME Wayland (Mutter)** - No PRIMARY selection support
-   **macOS** - No PRIMARY selection concept in the system
-   **Other Wayland compositors** - Support varies

#### Recommendation

For the most stable and robust experience with all plugin features, **X11 is recommended**. While Wayland
support is improving, PRIMARY selection implementation is inconsistent across compositors.

If Mouse Selection Replacement doesn't work on your platform, disable it with `edit-select config` → Option 2.

### Testing Coverage

This plugin has been thoroughly and heavily tested on **Kitty Terminal** on X11 and briefly on other popular
terminals.

If you encounter issues on other terminals or platforms, please
[open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with your terminal name, OS, and
display server.

### Core Features (Available on All Platforms)

These features work universally regardless of platform:

-   ✅ Shift+Arrow keys for text selection
-   ✅ Ctrl+A (Cmd+A) to select all
-   ✅ Ctrl+C (Cmd+C) to copy
-   ✅ Ctrl+X (Cmd+X) to cut keyboard selection
-   ✅ Ctrl+V (Cmd+V) to paste
-   ✅ Delete/Backspace to remove keyboard selection
-   ✅ Type or paste to replace keyboard selection

---

## Key Bindings Reference

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

### Editing Keys

| Key Combination   | Action                                       |
| ----------------- | -------------------------------------------- |
| **Ctrl + C**      | Copy selected text                           |
| **Ctrl + X**      | Cut selected text                            |
| **Ctrl + V**      | Paste (replaces selection if any)            |
| **Delete**        | Delete selected text _(selection mode only)_ |
| **Backspace**     | Delete selected text _(selection mode only)_ |
| **Any character** | Replace selected text                        |

---

## Common Issues - Quick Fixes

| Problem                               | Quick Fix                                                       |
| ------------------------------------- | --------------------------------------------------------------- |
| Shift selection doesn't work          | Configure your terminal (see [Terminal Setup](#terminal-setup)) |
| Copy doesn't work                     | Install clipboard tool: `wl-clipboard` or `xclip`               |
| Mouse replacement slow                | Disable it: `edit-select config` → Option 2                     |
| Ctrl+C copies instead of interrupting | Remap in terminal to use Ctrl+Shift+C for copy                  |
| Can't paste with Ctrl+V               | Check terminal keybinding conflicts or use config wizard        |
| Configuration wizard doesn't launch   | Check plugin installation and file permissions                  |

---

**Important:** If the `Delete` key does not remove mouse-selected text, ensure your `~/.zshrc` does not contain a line that forces the Delete key to the default handler such as:

`bindkey '^[[3~' delete-char`

That line will override the plugin's binding for the Delete key and prevent `zsh-edit-select` from handling mouse selections correctly. Remove or comment out that line and reload your shell:

```bash
source ~/.zshrc
```


## Troubleshooting

### Shift selection doesn't work

**Solution:** Configure your terminal to pass Shift key sequences. See [Terminal Setup](#terminal-setup).

**Verify:** Run `cat` and press Shift+Left. You should see an escape sequence like `^[[1;2D`.

### Clipboard operations don't work

**Solution:** Install the required clipboard tool:

-   Wayland: `wl-clipboard`
-   X11: `xclip`

**Verify:** Run `wl-copy <<< "test"` or `xclip -i <<< "test"` to check if the tool works.

### Mouse replacement not working

**Solution:**

1. Check if mouse replacement is enabled: `edit-select config` → View Configuration
2. Ensure your terminal supports mouse selection (most do)
3. Try selecting text with your mouse, then typing—it should replace the selection

If Backspace (or Delete) does not remove a mouse-selected region, this is often due to platform limitations
with PRIMARY selection (or lack thereof on macOS). Try one of the following:

-   Disable Mouse Replacement: `edit-select config` → Option 2, or set
    `EDIT_SELECT_MOUSE_REPLACEMENT=disabled` in your config file.
-   Use Shift + Arrow keys for selection, which the plugin fully supports.

### Duplicate-text prompt

If you see the message "Duplicate text: place cursor inside the occurrence you want to modify", the plugin
has detected multiple identical occurrences of the selected text in your command buffer. Place the cursor
inside the specific occurrence you want to edit and retry the operation. If you prefer to avoid this prompt,
use Shift+Arrow keys to create an explicit keyboard selection, or edit the buffer manually to disambiguate
the occurrences before running the edit action.

This message only appears when the selection was made with the mouse and the selected text occurs more than
once in the buffer. It's a protective guard for the plugin's mouse-selection workaround: because mouse
replacement is not enabled by default, the prompt prevents accidental edits across ambiguous duplicate
occurrences when using the mouse-based selection flow.

### Ctrl+C doesn't copy

**Solution:** Configure your terminal to remap Ctrl+C. See [Kitty](#kitty) or
[VS Code Terminal](#vs-code-terminal) sections.

**Alternative:** Use Ctrl+Shift+C for copying, or configure a custom keybinding with `edit-select config`, or
use the 'Without Terminal Remapping' method if your terminal doesn't support key remapping.

### Configuration wizard doesn't launch

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

-   [Zsh zle shift selection — StackOverflow](https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection)

-   [Zsh Line Editor Documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
