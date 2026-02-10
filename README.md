# Zsh Edit-Select

Zsh plugin for Modern text selection and editing for Zsh command line. Select text with **Shift + Arrow keys**,
type-to-replace, paste-to-replace, mouse selection integration, and clipboard integration for copy/cut/paste
like in GUI text editors.

https://github.com/user-attachments/assets/1a3f0e29-0e20-450b-b1b2-6186bd064a11

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Auto Installation](#auto-installation)
- [Manual Installation](#manual-installation)
- [Configuration Wizard](#configuration-wizard)
- [Terminal Setup](#terminal-setup)
  - [Step 1: Configure Copy Shortcut](#step-1-configure-copy-shortcut)
  - [Step 2: Configure Undo and Redo Shortcut](#step-2-configure-undo-and-redo-shortcut)
  - [Step 3: Enable Shift Selection Keys](#step-3-enable-shift-selection-keys)
- [Wayland Support](#wayland-support)
- [Platform Compatibility](#platform-compatibility)
- [Performance & Optimization](#performance--optimization)
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
> `edit-select config` to customize mouse behavior and keybindings.
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

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 1

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

### Selection Monitoring & Clipboard Integration

The plugin uses a high-performance custom C daemon architecture for all clipboard operations:

**Custom Monitor Daemons (All Operations):** Lightweight C programs handle both selection monitoring and
clipboard operations:

| Display Server | Monitor Daemon              | Protocol                                               | Performance Gain              |
| -------------- | --------------------------- | ------------------------------------------------------ | ----------------------------- |
| **X11**        | `zes-x11-selection-monitor` | XFixes extension + CLIPBOARD atom                      | **44.6% faster than xclip**   |
| **Wayland**    | `zes-wl-selection-monitor`  | `zwp_primary_selection_unstable_v1` + `wl_data_device` | **96.4% faster than wl-copy** |
| **XWayland**   | `zes-xwayland-monitor`      | X11 XFixes through XWayland                            | **Enhance Wayland behaviour**       |

**External Tools (Fallback Only):**

| Display Server | Tool                   | When Used                          |
| -------------- | ---------------------- | ---------------------------------- |
| **X11**        | `xclip`                | Only if custom monitor unavailable |
| **Wayland**    | `wl-copy` / `wl-paste` | Only if custom monitor unavailable |

> **Performance Achievement:** The custom daemon monitors eliminate external tool dependencies entirely. All
> clipboard operations (copy, paste, clear) are handled by persistent background processes using direct
> protocol access—delivering **44.6% faster operations** on X11 and **96.4% faster operations** on Wayland
> with **zero subprocess overhead**.

> **Architecture:** These monitors run as lightweight background daemons that automatically start when the
> plugin loads. They use event-driven protocols (XFixes, Wayland native events) for instant selection change
> notification and cache data in memory-mapped files for sub-millisecond access times.

---

---

## Auto Installation

The easiest way to install **Zsh Edit-Select** is using the automated installation script. This intelligent script detects your environment (X11, Wayland, or XWayland), installs necessary dependencies, configures the plugin, and even sets up your terminal emulator.

To install, simply run:

```bash
curl -fsSL https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install.sh -o install.sh && chmod +x install.sh && bash install.sh
```

### Key Features

The installer is designed for reliability and system safety:

- **Idempotency**: The script checks your configuration files before making changes. It can be run multiple times without creating duplicate entries or corrupting files.
- **System Safety**: Creates timestamped backups of every file before modification. Implements standard signal trapping (INT, TERM, EXIT) to ensure cleanups even if interrupted.
- **optimized Compilation**: Builds the monitoring daemons locally using `-O3 -march=native -flto`, ensuring the binary is tailored specifically to your CPU architecture for minimum latency.
- **Universal Compatibility**: specific support for 11 different package managers (including `apt`, `dnf`, `pacman`, `zypper`, `apk`, and `nix`) across X11 and Wayland environments.

### Automated Capabilities

The script handles the end-to-end setup process:

| Category | Automated Actions |
| :--- | :--- |
| **Dependencies** | - Installs system packages (`git`, `zsh`, `gcc`, `make`, `xclip`/`wl-clipboard`)<br>- Detects your OS (Debian, Fedora, Arch, etc.) and uses the correct package manager (`apt`, `dnf`, `pacman`) |
| **Plugin Manager** | - **Detects** your existing manager (Oh My Zsh, Zinit, Antigen, Sheldon, etc.)<br>- **Installs Oh My Zsh** automatically if you don't have a plugin manager<br>- *Note: It does not install other managers like Zinit/Antigen; install those first if you prefer them over OMZ.* |
| **Compilation** | - Downloads and **compiles** the custom C monitor daemons (`zes-x11-monitor` / `zes-wl-monitor`)<br>- Optimizes binaries for your specific architecture |
| **Terminal Setup** | - Configures **Kitty**, **Alacritty**, **WezTerm**, **Foot**, and **VS Code** to support keybindings<br>- Backs up existing config files before making changes |
| **Safeguards** | - Checks for conflicting keybindings in your `.zshrc`<br>- Verifies the installation with a self-test suite |


<details>
<summary><b>Advanced Usage & Options</b></summary>

You can customize the installation behavior with command-line flags. To use them, download the script first or pass them to bash:

| Option | Description |
| :--- | :--- |
| `--non-interactive` | Run in headless mode without user prompts (accepts all defaults) |
| `--skip-deps` | Skip installing system dependencies (useful if you manage packages manually) |
| `--skip-conflicts` | Skip the configuration conflict detection phase |
| `--skip-verify` | Skip the post-installation verification tests |
| `--help` | Show the help message and exit |

**Example: Non-interactive installation (CI/CD friendly)**
```bash
bash auto-install.sh --non-interactive
```

</details>


<details>
<summary><b>Installation Output</b></summary>

The script provides detailed, color-coded feedback for every step:
- **✅ Success**: Step completed successfully
- **⚠️ Warning**: Non-critical issue (e.g., optional component missing)
- **❌ Error**: Critical failure that requires attention

At the end, you'll receive a **Summary Report** listing all installed components and any manual steps required. A detailed log is also saved to `~/.zsh-edit-select-install.log`.

</details>

> **Troubleshooting / Manual Preference:** If the automated installation fails or if you prefer to configure everything yourself, you can follow the comprehensive [Manual Installation](#manual-installation) and [Terminal Setup](#terminal-setup) guides below.

---

## Manual Installation

> **Tip:** The [Auto Installation](#auto-installation) script handles all these steps automatically (dependencies, plugin installation, compiling custom monitor daemons). You only need this section if you prefer full manual control or if the auto-installer fails.

### 1. Prerequisites (Build Dependencies)

<details>
<summary><b>How to check if you're using X11 or Wayland</b></summary>

Run this command in your terminal:

```bash
echo $XDG_SESSION_TYPE
```

- If it returns `x11` → You're using X11
- If it returns `wayland` → You're using Wayland

> **Note:** The plugin automatically detects your display server and loads the appropriate implementation.

</details>

The plugin automatically compiles native monitor daemons on first use. Install the required build tools and libraries for your platform:

### For X11 Users

<details>
<summary><b>Debian/Ubuntu</b></summary>

The plugin includes a native X11 monitor daemon with full clipboard support. External clipboard tools are optional:

```bash
sudo apt install build-essential libx11-dev libxfixes-dev pkg-config xclip
```

> **Note:** The `zes-x11-selection-monitor` daemon provides **44.6% faster** clipboard operations compared to `xclip` and does not require external tools for core functionality.

</details>

<details>
<summary><b>Arch Linux</b></summary>

The plugin includes a native X11 monitor daemon with full clipboard support. External clipboard tools are optional:

```bash
sudo pacman -S --needed base-devel libx11 libxfixes pkgconf xclip
```

> **Note:** The `zes-x11-selection-monitor` daemon provides **44.6% faster** clipboard operations compared to `xclip` and does not require external tools for core functionality.

</details>

<details>
<summary><b>Fedora</b></summary>

The plugin includes a native X11 monitor daemon with full clipboard support. External clipboard tools are optional:

```bash
sudo dnf install gcc make libX11-devel libXfixes-devel pkgconfig xclip
```

> **Note:** The `zes-x11-selection-monitor` daemon provides **44.6% faster** clipboard operations compared to `xclip` and does not require external tools for core functionality.

</details>

### For Wayland Users

<details>
<summary><b>Debian/Ubuntu</b></summary>

The plugin includes a native Wayland monitor daemon with full PRIMARY selection support. External clipboard tools are optional:

```bash
sudo apt install build-essential libwayland-dev wayland-protocols pkg-config wl-clipboard
```

> **Note:** The `zes-wl-selection-monitor` daemon uses native Wayland protocols directly and does not require these tools for core functionality.

</details>

<details>
<summary><b>Arch Linux</b></summary>

The plugin includes a native Wayland monitor daemon with full PRIMARY selection support. External clipboard tools are optional:

```bash
sudo pacman -S --needed base-devel wayland wayland-protocols pkgconf wl-clipboard
```

> **Note:** The `zes-wl-selection-monitor` daemon uses native Wayland protocols directly and does not require these tools for core functionality.

</details>

<details>
<summary><b>Fedora</b></summary>

The plugin includes a native Wayland monitor daemon with full PRIMARY selection support. External clipboard tools are optional:

```bash
sudo dnf install gcc make wayland-devel wayland-protocols-devel pkgconfig wl-clipboard
```

> **Note:** The `zes-wl-selection-monitor` daemon uses native Wayland protocols directly and does not require these tools for core functionality.

</details>

### For XWayland Users

If you're running Wayland but need X11 compatibility (XWayland) and enhance the behaviour, install both X11 and Wayland dependencies.

<details>
<summary><b>Debian/Ubuntu</b></summary>

```bash
sudo apt install build-essential libx11-dev libxfixes-dev libwayland-dev wayland-protocols pkg-config
```

</details>

<details>
<summary><b>Arch Linux</b></summary>

```bash
sudo pacman -S --needed base-devel libx11 libxfixes wayland wayland-protocols pkgconf
```

</details>

<details>
<summary><b>Fedora</b></summary>

```bash
sudo dnf install gcc make libX11-devel libXfixes-devel wayland-devel wayland-protocols-devel pkgconfig
```

</details>

---

### 2. Install the Plugin


> **Important:** Before installing, please ensure you have the required [Build Dependencies](#1-prerequisites-build-dependencies) installed.

<details>
<summary><b>Oh My Zsh</b></summary>

Expand your plugin manager:


```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select
```

Add to your `.zshrc`:

```bash
plugins=(... zsh-edit-select)
```

</details>

<details>
<summary><b>zgenom</b></summary>

```bash
zgenom load Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>sheldon</b></summary>

```bash
sheldon add zsh-edit-select --github Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>Manual Installation</b></summary>

```bash
git clone https://github.com/Michael-Matta1/zsh-edit-select.git \
  ~/.local/share/zsh/plugins/zsh-edit-select

# Add to ~/.zshrc:
source ~/.local/share/zsh/plugins/zsh-edit-select/zsh-edit-select.plugin.zsh
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

- Mouse replacement behavior
- Keybindings (Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z)

Run the interactive configuration wizard:

```bash
edit-select config
```

---

## Configuration Wizard

Launch the interactive configuration wizard:

```bash
edit-select config
```

The wizard provides:

1. **Mouse Replacement** — Enable/disable mouse selection integration
2. **Key Bindings** — Customize Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z shortcuts
3. **View Configuration** — See current settings
4. **Reset to Defaults** — Restore factory settings

All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions.


<details>
<summary><b> Mouse Replacement Modes </b></summary>

Configure how the plugin handles mouse selections:

**Enabled (default):**

- Full integration: type, paste, cut, and delete work with mouse selections
- Best for users who want seamless mouse+keyboard workflow
- A lightweight background daemon monitors PRIMARY selection changes for instant mouse selection detection

**Disabled:**

- Mouse selections can be copied with Ctrl+C
- Typing, pasting, cutting, and deleting only work with keyboard selections
- The background daemon is still running but mouse replacement actions are disabled
- Best for users who prefer strict keyboard-only editing

Change the mode:

```bash
edit-select config  # → Option 1: Mouse Replacement
```

</details>

<details>
<summary><b> Keybinding Customization </b></summary>

Customize the main editing shortcuts:

```bash
edit-select config  # → Option 2: Key Bindings
```

**Default bindings:**

> **Tip:** If you're unsure how keybindings integrate with your shell or terminal, take a look at the
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

<details>
<summary><b>Display Server Override</b></summary>

> **Note:** The plugin automatically uses the correct implementation (X11 or Wayland) based on your system.


### Environment Variables

```bash
# Force a specific implementation (overrides auto-detection)
export ZES_FORCE_IMPL=x11    # Force X11 implementation
export ZES_FORCE_IMPL=wayland # Force Wayland implementation
```

> **Use case:** Force a specific implementation if auto-detection fails or if you want to use a different
> display server intentionally.

</details>

---

## Terminal Setup

> **Tip:** The [Auto Installation](#auto-installation) script can automatically configure supported terminals (Kitty, WezTerm, Alacritty, Foot, VS Code) for you.

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

## Wayland Support

> **Tip:** The [Auto Installation](#auto-installation) script automatically detects your environment and builds the correct optimized monitor daemon.

Wayland is fully supported with native protocol implementation. The plugin automatically detects your Wayland
setup and uses the optimal selection monitor:

**Selection Monitor Priority (automatically selected):**

1. **`zes-wl-selection-monitor` (Native Wayland)** — Custom C daemon with direct Wayland protocol support
   - Uses `zwp_primary_selection_unstable_v1` for PRIMARY selection
   - Uses `wl_data_device` for CLIPBOARD operations
   - Works on all Wayland compositors with protocol support (Sway, Hyprland, KDE Plasma, River, Wayfire)
   - Provides full mouse selection replacement feature
   - Best performance with zero external tool overhead

2. **`zes-xwayland-monitor` (XWayland)** — Recommended X11 compatibility layer
   - Uses XWayland's X11 XFixes extension when available
   - Provides seamless support for mixed X11/Wayland environments
   - Recommended for maximum compatibility with older applications

> **Technical Achievement:** The native Wayland implementation eliminates reliance on external clipboard tools
> (`wl-copy`/`wl-paste`). Our custom C daemon connects directly to Wayland protocols, providing instant
> PRIMARY selection monitoring with zero process-spawn overhead. This architecture delivers superior
> performance and responsiveness compared to traditional clipboard utility approaches.
>
> **Architecture:** The selection monitor daemons (`zes-wl-selection-monitor`, `zes-xwayland-monitor`,
> `zes-x11-selection-monitor`) are lightweight background processes that monitor selection changes via
> event-driven protocols and write updates to cache files. This zero-fork design ensures instant
> responsiveness without performance overhead during typing.

<details>
<summary><b>Native Wayland Protocol Support (Fully Implemented)</b></summary>

Our `zes-wl-selection-monitor` daemon provides complete PRIMARY selection support on all Wayland compositors
with protocol implementation:

**Supported Compositors:**

- ✅ **wlroots-based compositors** — Sway, Hyprland, River, Wayfire (full PRIMARY support)
- ✅ **KDE Plasma Wayland** — Full PRIMARY selection via `zwp_primary_selection_unstable_v1`
- ✅ **GNOME Wayland (Mutter)** — Native Wayland implementation provides PRIMARY selection support\*

\*Note: GNOME's PRIMARY selection support depends on compositor configuration. If unavailable, XWayland bridge
provides seamless fallback.

**Performance Advantage:** Direct Wayland protocol access means:

- No subprocess spawning for clipboard operations
- No `wl-copy`/`wl-paste` process overhead
- Native event-driven architecture
- Instant response to selection changes
- Zero typing lag even with frequent selections

</details>

<details>
<summary><b>XWayland Bridge (Recommended, for Enhanced Compatibility)</b></summary>

The plugin includes a recommended XWayland bridge for environments where native Wayland protocol support
is limited. XWayland provides:

- Seamless fallback for hybrid X11/Wayland environments
- Support for legacy applications running under XWayland
- Alternative PRIMARY selection detection when native Wayland protocols unavailable


</details>

<details>
<summary><b>Enabling XWayland (Recommended)</b></summary>

The recommended selection monitor (`zes-xwayland-monitor`) requires XWayland. XWayland provides an X11
compatibility layer on top of Wayland, allowing the monitor to use X11's XFixes extension for completely
invisible PRIMARY selection tracking — no windows, no dock entries, no compositor artifacts.

**Check if XWayland is already running:**

```bash
echo $DISPLAY
```

If this prints something like `:0` or `:1`, XWayland is already available.

**If `DISPLAY` is empty, enable XWayland on your compositor:**

<details>
<summary><b>GNOME (Mutter)</b></summary>

XWayland is enabled by default on GNOME. If it was disabled:

```bash
# Re-enable XWayland (requires logout/login)
gsettings reset org.gnome.mutter experimental-features
```

Or add `Xwayland` to the experimental features if using a custom list. On GNOME 47+, XWayland starts on demand
when any X11 app connects.

</details>

<details>
<summary><b>KDE Plasma</b></summary>

XWayland is enabled by default. If disabled, re-enable it in:

**System Settings → Display and Monitor → Compositor → Allow XWayland applications**

</details>

<details>
<summary><b>Sway</b></summary>

XWayland is enabled by default. If disabled, add to your Sway config:

```
xwayland enable
```

Then reload Sway (`$mod+Shift+C`).

</details>

<details>
<summary><b>Hyprland</b></summary>

Add to your Hyprland config:

```
xwayland {
  force_zero_scaling = true
}
```

XWayland is enabled by default in Hyprland.

</details>

**Without XWayland:** The plugin falls back to the pure Wayland monitor (`zes-wl-selection-monitor`), which
uses `zwp_primary_selection_v1`. This works on wlroots-based compositors (Sway, Hyprland) and KDE Plasma, but
may show a small surface in the dock/taskbar on GNOME/Mutter.
</details>


---

## Platform Compatibility

<details>
<summary><b>Mouse Selection Replacement Feature</b></summary>

The **Mouse Selection Replacement** feature (automatically detecting and replacing mouse-selected text) has
comprehensive support across platforms via our custom daemon implementations:

### ✅ Fully Supported

**X11 & XWayland:**

- **X11** - Complete PRIMARY selection support via XFixes extension
- **XWayland bridge** - Full compatibility layer for mixed environments

**Native Wayland (Direct Protocol Implementation):**

- **wlroots-based compositors** — Sway, Hyprland, River, Wayfire with `zwp_primary_selection_unstable_v1`
- **KDE Plasma Wayland** - Full PRIMARY selection support via native protocols
- **GNOME Wayland (Mutter)** - Native Wayland implementation provides PRIMARY selection support where
  available
- **Other Wayland compositors** - Full support for any compositor implementing PRIMARY selection protocols

### Performance Advantage on Wayland

Our native Wayland implementation (`zes-wl-selection-monitor`) provides:

- ✅ Direct protocol access (no `wl-copy`/`wl-paste` subprocess overhead)
- ✅ Zero typing lag with instant selection detection
- ✅ Event-driven architecture (no polling)
- ✅ Superior responsiveness compared to standard clipboard tools

### If Selection Replacement Doesn't Work

1. Verify native Wayland or XWayland support is available
2. Check that your compositor supports PRIMARY selection protocols
3. Disable mouse replacement if needed: `edit-select config` → Option 2
4. Report issues with your compositor on [GitHub](https://github.com/Michael-Matta1/zsh-edit-select/issues)

</details>

<details>
<summary><b>Testing Coverage</b></summary>

This plugin has been thoroughly and heavily tested on **Kitty Terminal** and briefly on other popular
terminals.

If you encounter issues on other terminals or platforms, please
[open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with your terminal name, OS, and
display server.

</details>

<details>
<summary><b>Core Features (Universal)</b></summary>

These features work universally on X11, Wayland, and XWayland:

- ✅ Shift+Arrow keys for text selection
- ✅ Ctrl+A to select all
- ✅ Ctrl+C to copy
- ✅ Ctrl+X to cut keyboard selection
- ✅ Ctrl+V to paste
- ✅ Ctrl+Z to undo
- ✅ Ctrl+Shift+Z to redo
- ✅ Delete/Backspace to remove keyboard selection
- ✅ Type or paste to replace keyboard selection
- ✅ Mouse selection replacement (where PRIMARY selection available)

**Wayland Advantage:** Native implementation provides these features with zero subprocess overhead, delivering
instant responsiveness and zero typing lag.

</details>

---

## Performance & Optimization

This plugin is engineered for **maximum performance and responsiveness**, ensuring **zero lag** even during
intensive text editing operations. The architecture prioritizes both **startup efficiency** and **runtime
speed** with careful attention to minimize overhead at every level.

### Performance-First Design

**Zero Runtime Overhead:**

- ✅ All operations execute instantly without processing delays
- ✅ Near-zero latency response to user interactions
- ✅ No background polling or inefficient loops

**One-Time Initialization:**

- ✅ Plugin loads once at shell startup with optimized initialization
- ✅ Backend detection happens a single time, not on every operation
- ✅ Subsequent operations have zero initialization cost

**Minimized Load Cost:**

- ✅ Startup overhead is optimized and amortized across the shell session
- ✅ Plugin files are automatically compiled to `.zwc` (Zsh bytecode) on first load for faster execution
- ✅ One-time daemon startup eliminates repeated process creation

**Minimized Runtime Cost:**

- ✅ Operations execute with near-zero latency
- ✅ File-based caching avoids expensive system calls for every operation
- ✅ Direct protocol access eliminates subprocess overhead

**Maximized Speed and Responsiveness:**

- ✅ Instant feedback for all user interactions
- ✅ No lag between typing and completion
- ✅ Seamless clipboard operations without delays

---

### Optimization Techniques

<details>
<summary><b>Startup & Initialization Optimizations</b></summary>

**One-Time Backend Detection**

- Platform detection runs once at plugin load time
- Environment variables checked: `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, `DISPLAY`
- Result cached and reused for entire shell session
- Eliminates decision-making overhead on every operation

**Lazy Backend Loading**

- Only the relevant implementation (X11 or Wayland) is loaded
- Unnecessary code paths not loaded into memory
- Reduces memory footprint and initialization time

**Zsh Bytecode Compilation**

- Plugin files automatically compiled to `.zwc` (Zsh bytecode) on first load
- Bytecode cached and reused on subsequent shell sessions
- Faster parsing and execution compared to raw Zsh scripts
- Compilation happens in background, doesn't block shell startup

**One-Time Configuration Loading**

- Configuration read once at startup
- No repeated file I/O on every operation
- Settings applied globally and cached

**Single Daemon Initialization**

- Selection monitor daemon started once when plugin loads
- Remains active for entire shell session
- Eliminates daemon startup overhead on subsequent operations

</details>

<details>
<summary><b>Runtime Execution Optimizations</b></summary>

**File-Based Caching with mtime Detection**

- Background daemon writes selection data to cache files
- Shell detects changes via file modification times (mtime)
- Only one `stat()` syscall needed, no file content reads
- mtime comparisons are instant memory comparisons
- Eliminates expensive clipboard access on every check

**Direct State Caching**

- Selection state stored in memory variables
- Avoids repeated clipboard queries for unchanged selections
- Early return checks prevent re-detection of active selections
- State invalidation only when actual changes detected

**Periodic Health Checks (30-second interval)**

- Daemon PID checked only every 30 seconds, not on every operation
- Reduces syscall frequency
- Graceful fallback if daemon dies detected quickly anyway
- Balances responsiveness with minimal overhead

**Fast Path Execution**

- Optimized code paths for common scenarios
- Mtime-based detection faster than content comparison
- Skips expensive operations when conditions don't apply
- Early returns eliminate unnecessary processing

**No Polling Architecture**

- Event-driven instead of polling-based
- Wayland: Uses native event loops from Wayland display
- X11: Uses XFixes extension events for instant notifications
- Eliminates busy-waiting and wasted CPU cycles

</details>

<details>
<summary><b>Custom C Daemon Architecture</b></summary>

**Compiled Native Code Performance**

- Custom C daemons compiled with aggressive optimization flags (`-O3`, `-march=native`, `-flto`)
- Direct system calls without Zsh interpreter overhead
- No subprocess spawning on clipboard operations
- Minimal dependencies (only system libraries)

**Event-Driven Monitoring**

- Wayland daemon: Connects to Wayland display server directly
  - Uses `zwp_primary_selection_unstable_v1` protocol for PRIMARY selection events
  - Uses `wl_data_device` protocol for clipboard events
  - Listens to server events instead of polling
- X11 daemon: Uses XFixes extension for selection change notifications
  - Instant event notification on PRIMARY selection changes
  - No polling loops or busy-waiting

**Efficient Cache Updates**

- Daemon writes only when selection actually changes
- File writes ordered: primary content first, then sequence number
- Shell detects only the mtime update of sequence file
- Prevents redundant updates and wasted disk I/O

**Non-Blocking I/O with Timeout**

- Clipboard reads use non-blocking I/O with poll timeout
- Prevents hanging on unavailable clipboard data -Efficient resource usage during read operations

**Daemon Mode Efficiency**

- Single daemon supports multiple operation modes:
  - Daemon mode: Continuous monitoring with periodic updates
  - Oneshot mode: Single selection read without persistence
  - Clipboard operations: Direct clipboard access
- Eliminates need for multiple processes

</details>

<details>
<summary><b>Protocol & System Call Optimizations</b></summary>

**Direct Protocol Access (Wayland)**

- Connects directly to Wayland server, no subprocess spawning
- Replaces `wl-copy`/`wl-paste` with direct protocol communication
- Native protocol access orders of magnitude faster than subprocess overhead
- Eliminates process creation, IPC, and shell parsing

**XFixes Extension (X11)**

- Uses native X11 XFixes extension for selection change notifications
- Hardware-level event notification instead of polling
- Instant response to selection changes
- Minimal overhead compared to repeated `xclip` invocations

**Single stat() Syscall Pattern**

- Uses `zstat` to get file mtime
- Single filesystem call instead of full file read
- Mtime check happens in memory
- Reduces kernel context switches

**Minimal File I/O**

- Cache files used only for synchronization signals
- Primary selection data passed directly, not through multiple files
- Reduces disk I/O and buffer cache pressure

</details>

<details>
<summary><b>Platform-Specific Optimizations</b></summary>

**X11-Specific**

- Uses `xclip` for copy operations (already optimized)
- XFixes extension for instant selection notifications
- No polling loops
- Direct X11 server connection

**Wayland-Specific**

- Native Wayland event loop for efficient monitoring
- Dual protocol support:
  - PRIMARY selection via `zwp_primary_selection_unstable_v1`
  - Clipboard via `wl_data_device` standard protocol
- XWayland compatibility layer for hybrid environments
- Invisible daemon surface only when needed (Mutter/GNOME)

**XWayland Bridge**

- Seamless Wayland + XWayland application handling
- Transparent fallback to X11 protocols when needed
- No performance penalty for mixed application environments

</details>

<details>
<summary><b>What Was Eliminated</b></summary>

**Eliminated Process Spawning**

- ✅ No subprocess creation on clipboard operations
- ✅ No shell overhead from executing external commands
- ✅ No IPC overhead for inter-process communication
- ✅ No repeated daemon startup cycles

**Eliminated Polling Loops**

- ✅ Event-driven architecture replaces polling
- ✅ No busy-waiting or CPU spinning
- ✅ No wasted cycles checking conditions repeatedly
- ✅ Instant response to actual changes

**Eliminated Repeated System Calls**

- ✅ File mtime compared in memory, not repeated stat calls
- ✅ Backend detection happens once, not per-operation decision-making
- ✅ Configuration loaded once, no repeated file reads
- ✅ PID checks throttled to 30-second intervals

**Eliminated Unnecessary Overhead**

- ✅ No unnecessary selection re-detection with early returns
- ✅ No redundant state checks when conditions unchanged
- ✅ No repeated clipboard queries for same selection
- ✅ No parsing or interpretation overhead in compiled C code

**Eliminated Interpreter Overhead**

- ✅ Custom C daemons have no scripting language overhead
- ✅ Zsh scripts compiled to bytecode for faster execution
- ✅ Direct system calls without wrapper overhead
- ✅ Minimal dependency chain

**Multi-Pane & Multi-Window Resilience**

- ✅ Handles multiple panes (splits) within the same terminal window seamlessly
- ✅ Works correctly across multiple terminal windows without conflicts
- ✅ Manages multiple independent terminal instances reliably
- ✅ Maintains independent selection state per pane and window
- ✅ Resilient against edge cases and complex multi-terminal scenarios

</details>

<details>
<summary><b>Advanced Features & Bug Fixes</b></summary>

**Multi-Pane Selection Independence**

- Terminal pane isolation: Each pane maintains independent selection state
- PRIMARY selection clearing after operations prevents cross-pane leakage
- State variables invalidated when selection completed
- Early return checks prevent re-detection of stale selections across panes
- Result: Selecting in Pane 1 no longer affects Pane 2

**Intelligent Duplicate Occurrence Handling**

- Detects when selected text appears multiple times in buffer
- Shows protective prompt: "Duplicate text: place cursor inside the occurrence you want to modify"
- Prevents accidental replacement of wrong occurrence
- Only applies to mouse selections (keyboard selection is unambiguous)
- Result: Safe replacement even with repeated text patterns

**Message & Display Integrity**

- Proper message clearing prevents persistence between operations
- Display refresh forces correct screen state after state changes
- No message overlap or visual artifacts
- Result: Clean, responsive UI with clear feedback

**Configuration Persistence**

- Settings saved to `~/.config/zsh-edit-select/config`
- Configuration loaded once at startup, cached for session
- Changes persist across shell sessions
- Reset option restores factory defaults
- Result: User preferences maintained reliably

**Environment Variable Override**

- `ZES_FORCE_IMPL` environment variable forces specific backend (x11 or wayland)
- Overrides automatic detection when needed
- Useful for debugging or forcing compatibility
- Result: Full control over implementation selection

</details>

<details>
<summary><b>Memory Management & State Efficiency</b></summary>

**Minimal Memory Footprint**

- ✅ State variables use efficient types (integers for flags, strings for selections)
- ✅ Only active implementation loaded (X11 or Wayland, not both)
- ✅ Lazy daemon initialization (only started when needed)
- ✅ Cache files use temporary directory (XDG_RUNTIME_DIR, typically in RAM on modern systems)
- ✅ No memory leaks from repeated operations

**State Variable Efficiency**

- ✅ Reused state variables across all operations
- ✅ State validated before use to prevent stale data
- ✅ Efficient string operations for selection detection
- ✅ Integer flags for fast boolean checks (DAEMON_ACTIVE, NEW_SELECTION_EVENT)
- ✅ Floating-point for precise timing (`EPOCHREALTIME` for selection timestamps)

**Caching Strategy**

- ✅ mtime-based detection avoids reading full file contents
- ✅ Memory caching of last known selections
- ✅ Invalidation on actual changes only
- ✅ No cache bloat from accumulating old data

</details>

<details>
<summary><b>Custom C Performance Layer</b></summary>

Unlike standard clipboard utilities, **zsh-edit-select** uses custom-built C programs specifically optimized
for this plugin, providing **measurable performance improvements** across all platforms.

**Architecture Overview:**

- **Selection Monitoring** — Custom C daemons track PRIMARY selection changes using native protocols
- **Clipboard Operations** — Direct protocol implementation replaces external tools (`xclip`, `wl-copy`,
  `wl-paste`)
- **File-Based Caching** — Background monitors cache selection data, eliminating subprocess overhead
- **Event-Driven Design** — Native event loops replace polling for instant responsiveness
- **Zero Typing Lag** — All operations execute without process-spawn delays

**Custom Daemon Monitors:**

| Monitor                     | Platform | Protocol                                               | Features                                  |
| --------------------------- | -------- | ------------------------------------------------------ | ----------------------------------------- |
| `zes-x11-selection-monitor` | X11      | XFixes extension                                       | PRIMARY monitoring + clipboard operations |
| `zes-wl-selection-monitor`  | Wayland  | `zwp_primary_selection_unstable_v1` + `wl_data_device` | Native Wayland protocols                  |
| `zes-xwayland-monitor`      | XWayland | X11 via XWayland bridge                                | Hybrid environment support + clipboard    |

**Key Performance Features:**

- ✅ **No External Dependencies** — Custom monitors eliminate need for `xclip` or `wl-copy`/`wl-paste`
- ✅ **Direct Protocol Access** — Native Wayland and X11 communication without subprocess overhead
- ✅ **File-Based Synchronization** — Cached data read via fast file I/O instead of process spawning
- ✅ **Compiled Optimization** — C code compiled with aggressive `-O3` + LTO flags for maximum performance
- ✅ **Event-Driven Architecture** — Instant notification of selection changes, zero polling

</details>

<details>
<summary><b>Clipboard Operation Performance Benchmarks</b></summary>

Our custom clipboard implementations deliver **exceptional performance improvements** over standard tools,
verified through comprehensive benchmarking with real-world measurements.

**X11 Performance (Custom Monitor vs xclip):**

| Test Scenario                          | xclip Avg    | Custom Avg   | Improvement      |
| -------------------------------------- | ------------ | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 4.025 ms     | 2.258 ms     | **43.9% faster** |
| Medium text (500 chars, 50 iterations) | 4.307 ms     | 2.211 ms     | **48.7% faster** |
| Large text (5KB, 25 iterations)        | 3.949 ms     | 2.310 ms     | **41.5% faster** |
| Very large (50KB, 10 iterations)       | 4.451 ms     | 2.499 ms     | **43.9% faster** |
| Rapid consecutive (200 iterations)     | 4.206 ms     | 2.321 ms     | **44.8% faster** |
| **Overall Average**                    | **4.187 ms** | **2.320 ms** | **44.6% faster** |

**Wayland Performance (Custom Monitor vs wl-copy):**

| Test Scenario                          | wl-copy Avg   | Custom Avg   | Improvement      |
| -------------------------------------- | ------------- | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 57.073 ms     | 1.966 ms     | **96.6% faster** |
| Medium text (500 chars, 50 iterations) | 60.382 ms     | 2.441 ms     | **96.0% faster** |
| Large text (5KB, 25 iterations)        | 63.020 ms     | 1.809 ms     | **97.1% faster** |
| Very large (50KB, 10 iterations)       | 58.343 ms     | 2.907 ms     | **95.0% faster** |
| Rapid consecutive (200 iterations)     | 58.860 ms     | 1.546 ms     | **97.4% faster** |
| **Overall Average**                    | **59.535 ms** | **2.134 ms** | **96.4% faster** |

**Performance Summary:**

- **X11 Improvement:** Custom daemon **44.6% faster** than xclip (2.320ms vs 4.187ms)
- **Wayland Improvement:** Custom daemon **96.4% faster** than wl-copy (2.134ms vs 59.535ms)
- **Best-case Latency:**
  - X11: 2.211ms minimum (48.7% better than xclip's 4.307ms)
  - Wayland: 1.152ms minimum (97.7% better than wl-copy's 49.066ms)
- **Consistency:** Performance maintained across all payload sizes (50 bytes to 50KB)
- **Memory:** Equal or better footprint than external tools

**Real-World Impact:**

- **X11 Operations:** Sub-2.5ms average latency means instant clipboard operations
- **Wayland Operations:** Sub-2.2ms average latency (27x faster than wl-copy)
- **Paste Operations:** Immediate data retrieval from daemon cache
- **Selection Detection:** Near-zero latency for mouse selection changes
- **High-Frequency Usage:** No performance degradation during rapid copy/paste workflows

**Why Wayland Shows Exceptional Gains:**

- wl-copy's high process spawn overhead (~60ms per operation) makes subprocess-based approaches extremely slow
- Our persistent daemon architecture eliminates all subprocess calls
- Direct Wayland protocol access provides native performance
- Result: **96.4% improvement** (27x performance multiplier) on Wayland vs **44.6% improvement** on X11

**Technical Implementation:**

- Custom monitors implement full clipboard protocol support
- Background server maintains clipboard ownership (auto-cleanup after 50 seconds)
- Graceful fallback to standard tools if custom monitors unavailable
- X11 achieves 44.6% performance gains, Wayland achieves 96.4% performance gains

> **Benchmark Methodology:** Tests conducted using high-precision C benchmarking tools with
> `clock_gettime(CLOCK_MONOTONIC)` for nanosecond accuracy. All measurements include real-world overhead
> (process spawning, IPC, wait time). Results represent actual wall-clock time improvements users experience
> during interactive use.

> **Run Benchmarks Yourself:** You can verify these performance claims by running the benchmark suite
> yourself. See the [`assets/benchmarks/`](assets/benchmarks/) directory for comprehensive C-based benchmarking tools and
> detailed instructions. The suite compares our custom implementations against standard tools (`xclip`,
> `wl-copy`/`wl-paste`) with precise timing and multiple test scenarios.

</details>

<details>
<summary><b>Selection Detection Optimizations</b></summary>

**Eliminated Subprocess Overhead:**

Traditional clipboard tools spawn a new process for every selection query. Our architecture eliminates this
entirely:

**Before (Traditional Approach):**

```
Every mouse selection detection:
  1. Fork subprocess for xclip/wl-paste → ~4.3ms overhead
  2. Parse output
  3. Clean up process

Total: Multiple subprocess calls per operation
```

**After (Custom C Daemon):**

```
One-time daemon startup:
  1. Daemon monitors selection changes → 0ms per check
  2. Writes updates to cache file
  3. Shell reads cached data via file I/O → <0.1ms

Total: Zero subprocess calls during normal operation
```

**Performance Impact:**

- **Traditional:** ~4.3ms per clipboard query (subprocess overhead)
- **Custom Daemon:** ~0.1ms per check (file mtime comparison)
- **Improvement:** ~97% reduction in selection detection latency

**Additional Optimizations:**

- ✅ `_zes_sync_selection_state()` — Reads daemon cache before selection detection
- ✅ Early return checks — Avoids redundant operations when selection unchanged
- ✅ Memory caching — Previous selection cached in memory variables
- ✅ mtime-based detection — Single `stat()` call instead of full file reads

**Cut Operation Optimization:**

Recent optimization reversed operation order in `edit-select::cut-region()`:

- **Old:** Delete text → Copy to clipboard (perceived as slow)
- **New:** Copy to clipboard → Delete text (feels instant)

Users perceive the operation complete when data enters clipboard, making the operation feel instant even
though total execution time is unchanged.

</details>

<details>
<summary><b>Platform-Specific Implementation Details</b></summary>

**X11 Implementation:**

- **Monitor:** `zes-x11-selection-monitor` with full clipboard support
- **Protocols:** XFixes extension for events, X11 CLIPBOARD atom
- **Operations:** `--get-clipboard`, `--copy-clipboard`, `--clear-primary`
- **Performance:** 44.6% faster than `xclip` across all operations
- **Fallback:** Graceful degradation to `xclip` if monitor unavailable

**Native Wayland Implementation:**

- **Monitor:** `zes-wl-selection-monitor` with native protocol support
- **Protocols:**
  - PRIMARY: `zwp_primary_selection_unstable_v1`
  - Clipboard: `wl_data_device` standard protocol
- **Operations:** Direct protocol calls, no external tools needed
- **Performance:** Zero subprocess overhead, instant responsiveness
- **Fallback:** Optional `wl-copy`/`wl-paste` if monitor unavailable

**XWayland Implementation:**

- **Monitor:** `zes-xwayland-monitor` for hybrid environments
- **Protocols:** X11 XFixes through XWayland bridge
- **Operations:** Full clipboard support matching X11 performance
- **Performance:** Unified architecture with X11-level optimizations
- **Compatibility:** Seamless support for mixed X11/Wayland applications

**Unified Performance:**

All platforms now achieve:

- ✅ Zero external tool dependencies for core functionality
- ✅ 44.6% faster on X11, 96.4% faster on Wayland vs standard clipboard tools
- ✅ Consistent sub-2.5ms latency for clipboard operations (X11: 2.3ms avg, Wayland: 2.1ms avg)
- ✅ Event-driven selection monitoring with instant notification

</details>

### Performance Benefits Summary

- ✅ **X11: 44.6% faster** — Custom daemon (2.320ms) vs xclip (4.187ms)
- ✅ **Wayland: 96.4% faster** — Custom daemon (2.134ms) vs wl-copy (59.535ms)
- ✅ **97% reduction in selection detection latency** — Eliminated subprocess overhead
- ✅ **Zero typing lag** — No process spawning during normal editing operations
- ✅ **Sub-2.5ms clipboard latency** — Operations complete faster than human perception threshold
- ✅ **Consistent performance** — Maintained across all payload sizes and platforms
- ✅ **Scalable architecture** — No degradation during high-frequency usage
- ✅ **Minimal startup overhead** — One-time initialization, zero per-operation cost
- ✅ **Event-driven responsiveness** — Instant reaction to selection changes

> **Technical Excellence:** Every component optimized for maximum performance—from compiler flags (`-O3`,
> `-march=native`, `-flto`) to protocol selection to operation ordering. The result is a plugin that feels
> instant and responsive in every interaction, with measurable proof of performance superiority.

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
PRIMARY selection. See [Platform Compatibility](#platform-compatibility) for more details.

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

<details>
<summary><b>Manual Build (Optional)</b></summary>

The plugin compiles monitors automatically on first use. To manually build them:

**X11 Monitor:**
```bash
cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select/impl-x11/backends/x11
make
```

**Wayland Monitor:**
```bash
cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select/impl-wayland/backends/wayland
make
```

**XWayland Monitor:**
```bash
cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-edit-select/impl-wayland/backends/x11
make
```

To clean/rebuild:
```bash
make clean && make
```

> **Note:** The plugin will automatically detect your display server and compile the appropriate monitor daemon on first shell startup. The Makefiles require:
>
> - **X11 builds:** `libX11` and `libXfixes` development headers/libraries
> - **Wayland builds:** `wayland-client` development headers, `wayland-scanner`, and `wayland-protocols`
>
> If compilation fails, the plugin will fall back to using external clipboard tools (`xclip` for X11, `wl-clipboard` for Wayland).

**Build Optimization:**

The default Makefiles already compile with aggressive optimization flags for maximum runtime performance:

| Flag | Purpose |
|------|---------|
| `-O3` | Maximum compiler optimization level |
| `-march=native` | CPU-specific instruction set (SSE, AVX, etc.) |
| `-mtune=native` | CPU-specific scheduling optimizations |
| `-flto` | Link-time optimization across compilation units |
| `-ffunction-sections -fdata-sections` | Granular dead code elimination |
| `-Wl,--gc-sections` | Remove unused functions/data at link time |
| `-fomit-frame-pointer` | Free up a register for better performance |
| `-fno-plt` | Eliminate PLT indirection for faster library calls |
| `-s` | Strip symbols for smaller production binaries |

> **Important:** `-march=native` produces binaries optimized for the CPU you're building on.
> These binaries may not run correctly on different CPU architectures. For distributed builds,
> replace `-march=native -mtune=native` with a portable baseline like `-march=x86-64-v2`.

</details>

---

## License

This project is licensed under the [MIT License](http://opensource.org/licenses/MIT/).

---

## Acknowledgments

- #### This project Began as a fork ([Michael-Matta1/zsh-shift-select](https://github.com/Michael-Matta1/zsh-shift-select)) of [jirutka/zsh-shift-select](https://github.com/jirutka/zsh-shift-select)
  + The fork was started to add the ability to copy selected text, because the jirutka/zsh-shift-select plugin only supported deleting selected text and did not offer copying by default. This feature was frequently requested by the community, as shown in
[issue #8](https://github.com/jirutka/zsh-shift-select/issues/8) and
[issue #10](https://github.com/jirutka/zsh-shift-select/issues/10).

  + Since then, the project has evolved with its own new features, enhancements, bug fixes, design improvements,
and a fully changed codebase, and it now provides a full editor-like experience.


- #### The [primary-selection-unstable-v1.xml](impl-wayland/backends/wayland/primary-selection-unstable-v1.xml) protocol definition is Copyright © 2015, 2016 Red Hat.

---

## References

- [Michael-Matta1/dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) — Example dotfiles
  demonstrating the plugin in action with Kitty terminal, VS Code, and Zsh integration.

- [Zsh zle shift selection — StackOverflow](https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection)

- [Zsh Line Editor Documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
