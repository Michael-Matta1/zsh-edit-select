# Zsh Edit-Select

Zsh plugin that lets you edit your command line like a text editor. Select text with Shift + Arrow keys or the
mouse, type or paste to replace selections, use standard editing shortcuts (copy, cut, paste, undo, redo,
select all), and customize keybindings through an interactive wizard — with full X11, Wayland, and WSL
support.


[demo video](https://github.com/user-attachments/assets/a024e609-1de1-4608-a7c3-e17264162904)

<details>
<summary><b>If the demo video is unavailable, click here to view the GIF.</b></summary>

![Demo](assets/demo.gif)

</details>

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
- [WSL Support](#wsl-support)
- [Default Key Bindings Reference](#default-key-bindings-reference)
- [Troubleshooting](#troubleshooting)
- [Platform Compatibility](#platform-compatibility)
- [Performance-Optimized Architecture](#performance-optimized-architecture)
- [Contributing](#contributing)
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
- ✅ **Clipboard integration** — Works with X11, Wayland, and WSL
- ✅ **Standard shortcuts** — Ctrl+A (select all), Ctrl+C (copy), Ctrl+X (cut), Ctrl+V (paste), Ctrl+Z (undo),
  Ctrl+Shift+Z (redo)

> **Customization:** The plugin works after installation with editor-like defaults. Use the command
> `edit-select config` to customize mouse behavior and keybindings.

---

## Features

### Keyboard Selection

Select text using familiar keyboard shortcuts:

| Shortcut                    | Action                                          |
| --------------------------- | ----------------------------------------------- |
| **Shift + ←/→**             | Select character by character                   |
| **Shift + ↑/↓**             | Select line by line                             |
| **Shift + Home/End**        | Select to line start/end                        |
| **Shift + Ctrl + ←/→**      | Select word by word                             |
| **Shift + Ctrl + Home/End** | Select to buffer start/end                      |
| **Ctrl + A**                | Select all text (including multi-line commands) |

### Mouse Selection Integration

The plugin intelligently integrates mouse selections:

**When Mouse Replacement is Enabled (default):**

- ✅ Copy mouse selections with Ctrl+C (or Ctrl+Shift+C if configured)
- ✅ Cut mouse selections with Ctrl+X
- ✅ Type to replace mouse selections
- ✅ Delete mouse selections with Backspace/Delete
- ✅ Paste over mouse selections with Ctrl+V

**When Mouse Replacement is Disabled:**

- ✅ Copy mouse selections with Ctrl+C (or Ctrl+Shift+C if configured)
- ✅ Replacement/Deletion work with keyboard selections

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 1

### Type-to-Replace and Paste-to-Replace

Type or paste while text is selected to replace it automatically.

Works with both keyboard and mouse selections (when mouse replacement is enabled).

<details>
<summary><b>⚠️ Mouse Replacement Note (Safeguard Prompt)</b></summary>

If you see the message **"Duplicate text: place cursor inside the occurrence you want to modify"**, the plugin has detected multiple identical occurrences of the selected text within your command buffer.

**When does this appear?** This message only appears in a rare edge case when **all three** of the following conditions are met simultaneously:

- The selection was made with the mouse, **AND**
- The exact same text appears more than once in the buffer, **AND**
- You attempt to replace the selected text by typing or pasting

This is a protective safeguard: when text is selected via mouse and the plugin cannot reliably distinguish between multiple identical occurrences, so it prompts you and prevents accidental edits.

When prompted, place the cursor inside the specific occurrence you want to edit, then
retry the operation (select it and type or paste to replace).

**Note:** This safeguard applies only to mouse selections. Using `Shift+Arrow keys` to select text avoids this ambiguity entirely and works without any extra prompting.


**Under development:** A custom mouse-tracking path is planned that will resolve the exact selected range and eliminate the safeguard prompt altogether. This is already implemented in the WSL version of the plugin and will be integrated across all versions once it has matured sufficiently.

---

</details>

### Copy, Cut, and Paste

Standard editing shortcuts:

- **Ctrl + C** (or Ctrl+Shift+C if configured): Copy selected text
- **Ctrl + X**: Cut selected text
- **Ctrl + V**: Paste (replaces selection if any)

> **Clipboard Managers Compatibility Note:** The plugin is fully compatible with clipboard history managers
> like **CopyQ**, **GPaste**, and others. Since it uses standard X11 and Wayland clipboard protocols, all
> copied text is automatically captured by your clipboard manager.

### Undo and Redo

Navigate through your command line editing history:

- **Ctrl + Z**: Undo last edit
- **Ctrl + Shift + Z**: Redo last undone edit

> **Note:** The Ctrl+Z keybinding works seamlessly alongside the traditional suspend process functionality
> (Ctrl+Z suspends a running foreground process to background). The plugin intelligently handles undo
> operations for command line editing while preserving the ability to suspend processes when needed.

> **Note:** The Copy and the Redo keybinding (Ctrl+Shift+Z) requires terminal configuration to send the
> correct escape sequence. See [Terminal Setup](#terminal-setup) for manual configuration instructions, or use
> the [Auto Installation](#auto-installation) script to configure this automatically.

### Clipboard Integration

The plugin includes purpose-built clipboard agents that replace external tools entirely:

**Clipboard Integration Agents:** Small compiled programs built specifically for this plugin handle all
clipboard and selection operations:

| Display Server | Agent                     | Protocol                                                                                                | Performance vs. External Tool |
| -------------- | ------------------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------- |
| **X11**        | `zes-x11-selection-agent` | XFixes extension + CLIPBOARD atom                                                                       | **44.6% faster than xclip**   |
| **Wayland**    | `zes-wl-selection-agent`  | `zwp_primary_selection_unstable_v1` + `ext_data_control_v1` / `zwlr_data_control_v1` / `wl_data_device` | **96.4% faster than wl-copy** |
| **XWayland**   | `zes-xwayland-agent`      | X11 XFixes through XWayland                                                                             | XWayland compatibility layer  |

**External Tools (Fallback Only):**

| Display Server | Tool                   | When Used                 |
| -------------- | ---------------------- | ------------------------- |
| **X11**        | `xclip`                | Only if agent unavailable |
| **Wayland**    | `wl-copy` / `wl-paste` | Only if agent unavailable |

> The agents handle copy, paste, and clipboard operations directly through native protocols—no external tools
> needed. They run as background processes and communicate with the plugin through a fast in-memory cache,
> giving you instant clipboard response with zero subprocess overhead.

> See [Performance-Optimized Architecture](#performance-optimized-architecture) for benchmarks and implementation details.

---

## Auto Installation

> **Recommendation:** If you are comfortable editing dotfiles and prefer full control over your system
> configuration, [Manual Installation](#manual-installation) is the recommended approach.

Installation consists of three straightforward steps:

1. install dependencies
2. plugin to your plugin manager
3. configure your terminal

Each documented with exact commands and copy-paste configurations.

- Completing all three steps should take no longer than **8 minutes** on a first install.
- All instructions are organized in collapsed sections so you can expand only what applies to your specific
  setup and platform.

The auto-installer is provided as a convenience for users who are less comfortable with terminal configuration
or who prefer a fully guided, hands-off setup. It detects your environment (X11, Wayland, XWayland, or WSL),
installs dependencies, sets up the plugin, and configures your terminal in a single run. It has been tested
across multiple distributions using Docker containers and virtual machines, and handles the most common
configurations — but not every edge case can be guaranteed. If you encounter an issue, please
[report it](https://github.com/Michael-Matta1/zsh-edit-select/issues) so it can be addressed.

To use the auto-installer, simply run:

```bash
curl -fsSL https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install.sh -o install.sh && chmod +x install.sh && bash install.sh
```

Or

```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install.sh && chmod +x /tmp/install.sh && bash /tmp/install.sh
```

### Key Features

<details>
<summary><b>Click to expand</b></summary>

The installer is designed for reliability and system safety:

- **Idempotency**: The script checks your configuration files before making changes. It can be run multiple
  times without creating duplicate entries or corrupting files.
- **System Safety**: Creates timestamped backups of every file before modification. Implements standard signal
  trapping (INT, TERM, EXIT) to ensure clean rollbacks even if interrupted.
- **Universal Compatibility**: Supports 11 different package managers (including `apt`, `dnf`, `pacman`,
  `zypper`, `apk`, and `nix`) across X11, Wayland, XWayland, and WSL environments.
- **Robust Pre-flight Checks**: Validates **network connectivity**, **disk space**, and **package manager
  health** before starting. Also proactively detects and reports broken repositories (e.g., problematic apt
  sources) to prevent installation failures.

### Automated Capabilities

The script handles the end-to-end setup process:

| Category           | Automated Actions                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| :----------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Dependencies**   | - Installs system packages (`git`, `zsh`, `gcc`, `make`, `xclip`/`wl-clipboard`)<br>- Detects your OS (Debian, Fedora, Arch, etc.) and uses the correct package manager (`apt`, `dnf`, `pacman`)                                                                                                                                                                                                                                                                        |
| **Plugin Manager** | - **Detects** your existing manager (Oh My Zsh, Zinit, Antigen, Sheldon, etc.)<br>- **Offers to install Oh My Zsh** if you don't have a plugin manager. You can refuse if you prefer manual installation<br>- _Note: The installer detects and installs the plugin for other managers such as Zinit or Antigen, but it does not install those managers themselves. If you prefer using them instead of OMZ, make sure they are installed before running the installer._ |
| **Terminal Setup** | - Configures **Kitty**, **Alacritty**, **WezTerm**, **Foot**, and **VS Code** to support keybindings<br>- Backs up existing config files before making changes                                                                                                                                                                                                                                                                                                          |
| **Safeguards**     | - Checks for conflicting keybindings in your `.zshrc` and terminal configuration files (Kitty, Alacritty, WezTerm, Foot, VS Code)<br>- Verifies the installation with a self-test suite                                                                                                                                                                                                                                                                                 |

</details>

### Interactive Menu

When run without arguments, the installer provides an interactive menu with the following options:

1. **Full Installation (Recommended)**: The complete setup process. **Required for first-time installations.**
2. **Configure Terminals Only**: Only detects and configures your terminal emulators.
3. **Check for Conflicts Only**: Scans your configuration files for conflicting keybindings.
4. **Update Plugin**: Pulls the latest changes from the repository.
5. **Build Agents Only**: Rebuild clipboard agents for your display server.
6. **Uninstall**: Remove the plugin, configuration entries, and agents.

<details>
<summary><b>Advanced Usage & Options</b></summary>

You can customize the installation behavior with command-line flags. To use them, download the script first or
pass them to bash:

| Option              | Description                                                                  |
| :------------------ | :--------------------------------------------------------------------------- |
| `--non-interactive` | Run in headless mode without user prompts (accepts all defaults)             |
| `--skip-deps`       | Skip installing system dependencies (useful if you manage packages manually) |
| `--skip-conflicts`  | Skip the configuration conflict detection phase                              |
| `--skip-verify`     | Skip the post-installation verification tests                                |
| `--test-mode`       | Allow running as root (for testing only)                                     |
| `--help`            | Show the help message and exit                                               |

**Example: Non-interactive installation (CI/CD friendly)**

```bash
bash auto-install.sh --non-interactive
```

</details>

### Installation Output

The script provides detailed, color-coded feedback for every step:

- **✅ Success**: Step completed successfully
- **⚠️ Warning**: Non-critical issue (e.g., optional component missing)
- **❌ Error**: Critical failure that requires attention

At the end, you'll receive a **Summary Report** listing all installed components and any manual steps
required. A detailed log is also saved to `~/.zsh-edit-select-install.log`.

> **Troubleshooting / Manual Preference:** If the automated installation fails or if you prefer to configure
> everything yourself, you can follow the comprehensive [Manual Installation](#manual-installation) and
> [Terminal Setup](#terminal-setup) guides below.

---

## Manual Installation

Manual installation is the recommended approach if you are comfortable with dotfiles and want complete
visibility and control over every change made to your system. The process consists of three steps:

1. **Install build dependencies** — A one-line command for your distribution.
2. **Install the plugin** — Clone the repository with your plugin manager and add one line to your `.zshrc`.
3. **Configure your terminal** — Add a few keybinding entries to your terminal's config file.

All steps are fully documented with exact commands and copy-paste configuration snippets. The instructions are
organized in collapsed sections labeled by distribution and terminal — expand only what applies to your setup.

> If you prefer an automated setup, the [Auto Installation](#auto-installation) script can handle all of these
> steps for you. If you run into any difficulty at any step, please
> [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) and it will be addressed.




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

The plugin automatically compiles native agents on first use. Install the required build tools and libraries
for your platform:

### For X11 Users

<details>
<summary><b>Debian/Ubuntu</b></summary>

```bash
sudo apt install build-essential libx11-dev libxfixes-dev pkg-config xclip
```

</details>

<details>
<summary><b>Arch Linux</b></summary>

```bash
sudo pacman -S --needed base-devel libx11 libxfixes pkgconf xclip
```

</details>

<details>
<summary><b>Fedora</b></summary>

```bash
sudo dnf install gcc make libX11-devel libXfixes-devel pkgconfig xclip
```

</details>

### For Wayland & WSL Users

<details>
<summary><b>Debian/Ubuntu</b></summary>

```bash
sudo apt install build-essential libx11-dev libxfixes-dev libwayland-dev wayland-protocols pkg-config wl-clipboard
```

</details>

<details>
<summary><b>Arch Linux</b></summary>

```bash
sudo pacman -S --needed base-devel libx11 libxfixes wayland wayland-protocols pkgconf wl-clipboard
```

</details>

<details>
<summary><b>Fedora</b></summary>

```bash
sudo dnf install gcc make libX11-devel libXfixes-devel wayland-devel wayland-protocols-devel pkgconfig wl-clipboard
```

</details>

---

### 2. Install the Plugin

> **Important:** Before installing, ensure you have the required
> [Build Dependencies](#1-prerequisites-build-dependencies) installed.
>
> You may use the [Auto Installation](#auto-installation) script to perform this step automatically, or
> [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) if you run into any difficulty.

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
<summary><b>zinit</b></summary>

```bash
zinit light Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>zplug</b></summary>

```bash
zplug "Michael-Matta1/zsh-edit-select"
```

</details>

<details>
<summary><b>antigen</b></summary>

```bash
antigen bundle Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>antibody</b> <sub>(deprecated)</sub></summary>

> **Note:** antibody has been archived since May 2022. Consider migrating to
> [antidote](https://github.com/mattmc3/antidote), a drop-in replacement.

```bash
antibody bundle Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>zgen</b> <sub>(unmaintained)</sub></summary>

> **Note:** zgen is no longer maintained. Consider migrating to [zgenom](https://github.com/jandamm/zgenom),
> its maintained successor.

```bash
zgen load Michael-Matta1/zsh-edit-select
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

> **WSL users:** For WSL, go directly to [WSL Support](#wsl-support).

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
2. **Key Bindings** — Customize Copy, Cut, Paste, Select All, Undo, Redo, and Word Navigation shortcuts
3. **View Full Configuration** — See current settings
4. **Reset to Defaults** — Restore factory settings
5. **Exit Wizard** — Close the wizard

All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions.

<details>
<summary><b> Mouse Replacement Modes </b></summary>

Configure how the plugin handles mouse selections:

**Enabled (default):**

- Full integration: type, paste, cut, and delete work with mouse selections
- Best for users who want seamless mouse+keyboard workflow

**Disabled:**

- Mouse selections can be copied with Ctrl+C (or Ctrl+Shift+C if configured)
- Typing, pasting, cutting, and deleting only work with keyboard selections
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

- **Ctrl + A** — Select all
- **Ctrl + V** — Paste
- **Ctrl + X** — Cut
- **Ctrl + Shift + C** — Copy
- **Ctrl + Z** — Undo
- **Ctrl + Shift + Z** — Redo
- **Ctrl + ←** — Word left
- **Ctrl + →** — Word right

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

Add to `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "X"
mods = "Control|Shift"
chars = "\u001b[88;6u"
```

<details>
<summary><i>Legacy YAML format (deprecated since Alacritty v0.13)</i></summary>

```yaml
key_bindings:
  - { key: X, mods: Control|Shift, chars: "\x1b[88;6u" }
```

</details>

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json` (usually at `~/.config/Code/User/`):

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

> The [Auto Installation](#auto-installation) script can configure supported terminals (Kitty, WezTerm,
> Alacritty, Foot, VS Code) automatically.
> If you prefer to configure manually follow the steps below.
> [Open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) if you need help with a terminal
> that is not covered.

>For WSL users on Windows Terminal, follow the dedicated manual at [WSL Support](#wsl-support)
> then return here only if you need additional terminal mappings.

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

Add to `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
chars = "\u001b[67;6u"
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying and Ctrl+Shift+C for interrupt:

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

<details>
<summary><i>Legacy YAML format (deprecated since Alacritty v0.13)</i></summary>

**Default (Ctrl+Shift+C):**

```yaml
key_bindings:
  - { key: C, mods: Control|Shift, chars: "\x1b[67;6u" }
```

**Reversed (Ctrl+C for copy):**

```yaml
key_bindings:
  - { key: C, mods: Control, chars: "\x1b[67;6u" }
  - { key: C, mods: Control|Shift, chars: "\x03" }
```

</details>

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

### Using Ctrl+Shift+C (Default)

To use Ctrl+Shift+C for copying, add the following to `keybindings.json` (usually at `~/.config/Code/User/`):

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
<summary><b>Foot</b></summary>

### Using Ctrl+Shift+C (Default)

Add the following to `foot.ini`. The default `clipboard-copy` binding must be unbound first so the escape
sequence reaches the shell:

```ini
[key-bindings]
clipboard-copy=none

[text-bindings]
\x1b[67;6u = Control+Shift+c
```

### Using Ctrl+C for Copying (Reversed)

If you prefer to use Ctrl+C for copying and Ctrl+Shift+C for interrupt:

```ini
[key-bindings]
clipboard-copy=none

[text-bindings]
\x1b[67;6u = Control+c
\x03 = Control+Shift+c
```

> **Note:** Foot uses the `[text-bindings]` section to send custom escape sequences to the shell. The default
> `clipboard-copy=Control+Shift+c` must be unbound first, otherwise Foot intercepts the key for its own
> clipboard action and the plugin never receives it. If you follow both Step 1 and Step 2, merge the
> `[key-bindings]` and `[text-bindings]` entries into single sections.

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

Add to `alacritty.toml`:

```toml
[[keyboard.bindings]]
key = "Z"
mods = "Control|Shift"
chars = "\u001b[90;6u"
```

<details>
<summary><i>Legacy YAML format (deprecated since Alacritty v0.13)</i></summary>

```yaml
key_bindings:
  - { key: Z, mods: Control|Shift, chars: "\x1b[90;6u" }
```

</details>

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json` (usually at `~/.config/Code/User/`):

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

<details>
<summary><b>Foot</b></summary>

Add the following to `foot.ini`. The default `prompt-prev` binding must be unbound first because Foot maps
Ctrl+Shift+Z to prompt navigation by default:

```ini
[key-bindings]
prompt-prev=none

[text-bindings]
\x1b[90;6u = Control+Shift+z
```

> **Note:** If you already configured Foot for Step 1 (Copy), merge these entries into the existing
> `[key-bindings]` and `[text-bindings]` sections rather than creating duplicates.

</details>

---

### Step 3: Enable Shift Selection Keys

Some terminals intercept Shift key combinations by default. Here's how to configure popular terminals:

<details>
<summary><b>Kitty</b></summary>

Add to `kitty.conf`:

```conf
# Pass Shift and Ctrl+Shift keys through to Zsh for selection
# (overrides any default or custom Kitty mappings on these keys)
map shift+left        no_op
map shift+right       no_op
map shift+up          no_op
map shift+down        no_op
map shift+home        no_op
map shift+end         no_op
# Ctrl+Shift+Left/Right default to previous_tab/next_tab in Kitty
map ctrl+shift+left   no_op
map ctrl+shift+right  no_op
# Ctrl+Shift+Home/End default to scroll_home/scroll_end in Kitty
map ctrl+shift+home   no_op
map ctrl+shift+end    no_op
```

</details>

<details>
<summary><b>WezTerm</b></summary>

Add to `wezterm.lua`:

```lua
return {
  keys = {
    { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'Home', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'End', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
  },
}
```

</details>

<details>
<summary><b>VS Code Terminal</b></summary>

Add to `keybindings.json` (usually at `~/.config/Code/User/`):

```json
[
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
]
```

</details>

<details>
<summary><b>Alacritty</b></summary>

Alacritty's defaults intercept **Shift+Home** (`ScrollToTop`) and **Shift+End** (`ScrollToBottom`). Add to
your Alacritty configuration to pass them through for selection:

<details>
<summary>TOML (<code>alacritty.toml</code>)</summary>

```toml
# Pass Shift+Home/End through for selection
# (overrides Alacritty defaults: ScrollToTop / ScrollToBottom)
[[keyboard.bindings]]
key = "Home"
mods = "Shift"
action = "ReceiveChar"

[[keyboard.bindings]]
key = "End"
mods = "Shift"
action = "ReceiveChar"
```

</details>

<details>
<summary>Legacy YAML format (<code>alacritty.yml</code>, deprecated since Alacritty v0.13)</summary>

```yaml
key_bindings:
  # Pass Shift+Home/End through for selection
  - { key: Home, mods: Shift, action: ReceiveChar }
  - { key: End, mods: Shift, action: ReceiveChar }
```

</details>

All other Shift / Ctrl+Shift arrow keys pass through to Zsh natively.

</details>

<details>
<summary><b>Foot</b></summary>

Foot passes Shift+Arrow keys through to the terminal natively — no additional configuration is needed for
Shift selection.

</details>

> **Configurations in practice:** The [dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles)
> repository includes working setups for **Kitty** (`kitty.conf`) and **VS Code** (`keybindings.json`) that
> demonstrate that this plugin can be seamlessly integrated alongside other tools and configurations.

---

## Wayland Support

> The [Auto Installation](#auto-installation) script automatically detects your display server and selects the
> correct agent. For manual setup, follow the Wayland-specific instructions in
> [Manual Installation](#manual-installation).

Wayland is fully supported with native protocol implementation. The plugin automatically detects your Wayland
setup and uses the optimal clipboard agent:

**Clipboard Agent Priority (automatically selected):**

1. **`zes-wl-selection-agent` (Native Wayland)** — Clipboard integration with direct Wayland protocol support
   - Handles PRIMARY selection and CLIPBOARD using native Wayland protocols
   - Works on all compositors with protocol support (Sway, Hyprland, KDE Plasma, River, Wayfire)
   - Full mouse selection replacement — no external tools needed
   - Sub-2.2ms clipboard latency (96.4% faster than `wl-copy`)

2. **`zes-xwayland-agent` (XWayland)** — XWayland compatibility layer (used when `DISPLAY` is available)
   - Uses X11 XFixes via XWayland for clipboard integration
   - Seamless support for mixed X11/Wayland environments
   - Complements the native Wayland agent for maximum compatibility

> The native Wayland implementation connects directly to Wayland protocols, eliminating reliance on
> `wl-copy`/`wl-paste`. All clipboard operations happen within the persistent agent process — zero subprocess
> overhead.
>
> **Architecture:** The clipboard agents (`zes-wl-selection-agent`, `zes-xwayland-agent`,
> `zes-x11-selection-agent`) are lightweight background processes that integrate with display server clipboard
> protocols. Updates are written to a fast in-memory cache (typically on `XDG_RUNTIME_DIR` or `/dev/shm`). The
> shell reads this cache via a single `stat()` call per keypress — no forks, no pipes, no latency.

<details>
<summary><b>Native Wayland Protocol Support (Fully Implemented)</b></summary>

`zes-wl-selection-agent` provides complete clipboard and selection support on all Wayland compositors with
protocol implementation:

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

`zes-xwayland-agent` uses XWayland (if available) for an extra X11 compatibility layer for clipboard
integration. XWayland provides:

- Seamless fallback for hybrid X11/Wayland environments
- Support for legacy applications running under XWayland
- Alternative PRIMARY selection detection when native Wayland protocols unavailable

</details>

<details>
<summary><b>Enabling XWayland (Recommended)</b></summary>

`zes-xwayland-agent` uses XWayland for clipboard integration — it requires XWayland to be available. XWayland
provides an X11 compatibility layer on top of Wayland, allowing the agent to use X11's XFixes extension —
completely invisible: no windows, no dock entries, no compositor artifacts.

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

**Without XWayland:** The plugin uses `zes-wl-selection-agent` directly, which uses
`zwp_primary_selection_v1`. This works on wlroots-based compositors (Sway, Hyprland) and KDE Plasma, but may
show a small surface in the dock/taskbar on GNOME/Mutter.

</details>

---

## WSL Support

WSL is fully supported, including mouse selection integration, custom tracking modes, and a tailored clipboard agent architecture designed for seamless interaction between Windows Terminal and WSL-native shells.


<details>
<summary><b>Installation and Terminal Configuration (WSL Quick Path)</b></summary>

1. Install the plugin using [Auto Installation](#auto-installation) or [Manual Installation](#manual-installation).
2. Configure terminal behavior using the Windows Terminal steps below.
3. Reload your shell and run `edit-select config` for optional keybinding and mouse behavior customization.

</details>

<details>
<summary><b>How to Open Windows Terminal settings.json</b></summary>

Use one of the following methods:

- With Windows Terminal open, press `Ctrl+Shift+,`
- In the UI: click the dropdown arrow next to the `+` tab button, select **Settings**, then click
  **Open JSON file** at the bottom-left
- Open directly from File Explorer:

```text
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

</details>

<details>
<summary><b>Recommended Windows Terminal Baseline</b></summary>

In the Terminal settings.json: Ensure that you have `"copyOnSelect"` set to `fasle` (which is the default value). If it wasn't then Set Windows Terminal to:

```json
"copyOnSelect": false
```

This is the recommended baseline for WSL because it preserves normal terminal selection behavior while the
plugin's tailored tracking mode handles mouse integration consistently in the command buffer. This avoids the
disruption of automatic copying on every selection and allows the custom modes to work as expected.

</details>

<details>
<summary><b>Reversed Copy Mode (Ctrl+C copy, Ctrl+Shift+C interrupt)</b></summary>

To use `Ctrl+Shift+C` for interrupt (SIGINT) Add one entry to `"actions"` and one to `"keybindings"` in the Windows Terminal settings.json :

```json
"actions": [
  ...existing actions...,
  {
    "command": {
      "action": "sendInput",
      "input": "\u001d"
    },
    "id": "User.sendIntr"
  }
],
```

```json
"keybindings": [
  ...existing keybindings...,
  {
    "id": "User.sendIntr",
    "keys": "ctrl+shift+c"
  }
],
```

Then add in `~/.zshrc`:

```zsh
stty intr ^]
```

Save `settings.json`, restart the profile, and `Ctrl+Shift+C` will send `0x1D` (`Ctrl+]`), which `stty`
treats as interrupt.

</details>

<details>
<summary><b>Ensure Ctrl+C is Bound to Copy</b></summary>

Windows Terminal usually defaults to `Ctrl+C` for copy. If your profile does not, add (or update) the
following entries.

Into `"actions"`:

```json
{
  "command": {
    "action": "copy",
    "singleLine": false
  },
  "id": "User.copy.644BA8F2"
},
```

Into `"keybindings"`:

```json
{
  "id": "User.copy.644BA8F2",
  "keys": "ctrl+c"
},
```

If these entries already exist, update their current values to match the above.

</details>

<details>
<summary><b>Custom Mouse Tracking and Mode Toggle</b></summary>


The WSL implementation includes a custom mouse-tracking mechanism that enables full mouse integration.

**New:** The tailored WSL mouse-tracking path resolves the exact selected range directly, eliminating the need for the Safeguard Prompt entirely.

---

**Mode Toggle via Free Selection**

To deliver full mouse integration in WSL, the plugin operates in two modes:

- **`mouse tracking` mode** — The plugin intercepts mouse input, allowing you to select and edit text within the command buffer.
- **`free selection` mode** — Restores native Windows Terminal behavior, letting you freely select any visible text on screen and access the right-click context menu as usual.

Switching between modes is automatic and seamless: click anywhere outside the current command buffer to temporarily enter `free selection` mode and interact with the terminal natively. Mouse tracking resumes automatically as soon as you return to the command buffer by typing.

</details>

<details>
<summary><b>Detection, Tailored Variants, and WSL Architecture</b></summary>

**Platform Detection:**

The plugin detects WSL via the `WSL_DISTRO_NAME` or `WSL_INTEROP` environment variables, which are set by both
WSL1 and WSL2. This unified detection ensures the plugin works seamlessly regardless of your WSL version.

**WSL1 vs WSL2 Support:**

Both WSL1 and WSL2 are supported through the same plugin path:

- **WSL2 (current)** — Uses Wayland clipboard interop for native Windows clipboard access
- **WSL1 (legacy)** — Falls back to the Windows side clipboard helper for clipboard operations

On both versions, the tailored implementation at `impl-wsl/tailored-variants/impl-wayland-wsl/` provides
consistent mouse tracking behavior and clipboard integration.

**Build Artifacts and Fallback:**

- **Preferred path** — `impl-wsl/tailored-variants/impl-wayland-wsl/` (optimized for WSL)
- **Legacy fallback** — `impl-wsl/zsh-edit-select-wsl.plugin.zsh` (loaded if tailored files are unavailable)
- **On-demand compilation** — Build artifacts are generated automatically if missing

**Helper Binaries:**

The plugin includes two compiled helpers to handle clipboard operations across the WSL boundary:

- **`zes-wsl-clipboard-helper.exe`** — Windows-side helper that reads from and writes to the Windows clipboard
  via the Windows API. It monitors clipboard changes, retrieves clipboard text (UTF-8), and sets clipboard
  content from the Linux side.

- **`zes-wsl-selection-agent`** — Linux-side agent that communicates with the Windows helper via pipes and
  manages a fast cache of clipboard contents on the native Linux filesystem. The cache uses `/dev/shm`
  (in-memory tmpfs) to minimize latency on keyboard events.

Together, these helpers provide transparent clipboard access: operations in the plugin appear instant because
the cache is memory-resident, while the agent syncs changes from Windows in the background.

</details>


---

## Default Key Bindings Reference

### Navigation Keys

| Key Combination | Action                     |
| --------------- | -------------------------- |
| **Ctrl + ←**    | Move cursor one word left  |
| **Ctrl + →**    | Move cursor one word right |

### Selection Keys

| Key Combination         | Action                     |
| ----------------------- | -------------------------- |
| **Shift + ←**           | Select one character left  |
| **Shift + →**           | Select one character right |
| **Shift + ↑**           | Select one line up         |
| **Shift + ↓**           | Select one line down       |
| **Shift + Home**        | Select to line start       |
| **Shift + End**         | Select to line end         |
| **Shift + Ctrl + ←**    | Select to word start       |
| **Shift + Ctrl + →**    | Select to word end         |
| **Shift + Ctrl + Home** | Select to buffer start     |
| **Shift + Ctrl + End**  | Select to buffer end       |
| **Ctrl + A**            | Select all text            |

### Editing Keys

| Key Combination      | Action                            |
| -------------------- | --------------------------------- |
| **Ctrl + C**         | Copy selected text                |
| **Ctrl + X**         | Cut selected text                 |
| **Ctrl + V**         | Paste (replaces selection if any) |
| **Ctrl + Z**         | Undo last edit                    |
| **Ctrl + Shift + Z** | Redo last undone edit             |
| **Delete/Backspace** | Delete selected text              |
| **Any character**    | Replace selected text if any      |

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

**Solution:** Configure your terminal to remap Ctrl+C. See
[Step 1: Configure Copy Shortcut](#step-1-configure-copy-shortcut) at the [Terminal Setup](#terminal-setup)
section.

**Alternative:** Use Ctrl+Shift+C for copying, or configure a custom keybinding with `edit-select config`, or
use the 'Without Terminal Remapping' method if your terminal doesn't support key remapping.

</details>

<details>
<summary><b>Configuration wizard doesn't launch</b></summary>

**Symptoms:** Running `edit-select config` shows "file not found" error

**Solution:**

1. Check the plugin was installed correctly
2. Verify the wizard file exists in the plugin directory (`edit-select-wizard-x11.zsh` on X11, or
   `edit-select-wizard-wayland.zsh` on Wayland)
3. Ensure the file has read permissions:
   ```bash
   # X11:
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-x11/edit-select-wizard-x11.zsh
   # Wayland:
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-wayland/edit-select-wizard-wayland.zsh
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
<summary><b>Mouse selection replaces text in a different pane (tmux users)</b></summary>

**Symptoms:** When using tmux with multiple panes, selecting text with the mouse in one pane and then
switching to another pane causes typed text to unexpectedly replace the previously selected text from the
other pane.

**Solution:** Enable focus events in tmux. The plugin uses terminal focus reporting (DECSET 1004) to
distinguish between selections made in the active pane versus other panes.

Add this line to your `~/.tmux.conf`:

```bash
set-option -g focus-events on
```

Then reload your tmux configuration:

```bash
tmux source-file ~/.tmux.conf
```

> **Note:** `focus-events on` has been the default since tmux 3.3a (released April 2023). If you're running an
> older version of tmux, either upgrade or add the line above to your configuration.

**Alternative:** If you cannot enable focus events, you can disable mouse replacement entirely with
`edit-select config` → Option 1 → Disable. This will preserve keyboard selection functionality while
preventing cross-pane mouse selection issues.

</details>

<details>
<summary><b>WSL Helper Binaries Not Building</b></summary>

**Symptoms:** Plugin loads but clipboard operations fail or `edit-select config` shows errors about missing helpers

**Solution:** The WSL helper binaries (`zes-wsl-clipboard-helper.exe` and `zes-wsl-selection-agent`) are
compiled automatically on first use. If they fail to build:

1. **Check your build tools:**
   ```bash
   # Ensure you have the build toolchain (gcc, make, mingw32 for Windows helper)
   apt update && apt install -y build-essential mingw-w64
   ```

2. **Rebuild the helpers manually:**
   ```bash
   # Replace with your actual plugin directory path
   cd ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-wsl/backends/wsl/
   make clean
   make
   ```

3. **Verify the binaries are executable:**
   ```bash
   ls -la ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-wsl/backends/wsl/
   # Should show: zes-wsl-clipboard-helper.exe and zes-wsl-selection-agent
   ```

4. **If build still fails:** Check the full build output for error messages naming missing dependencies, then
   install those packages and retry.

**Fallback:** If helpers cannot be built, the plugin falls back to `powershell.exe Get-Clipboard` for clipboard
operations, which works but is slower. Keyboard selection features are unaffected.

</details>

<details>
<summary><b>Manual Build (Optional)</b></summary>

The plugin compiles agents automatically on first use. To manually build them, first locate your plugin
directory — this depends on your plugin manager:

```bash
# Common locations (adjust to wherever you installed the plugin):
#   Oh My Zsh:  ~/.oh-my-zsh/custom/plugins/zsh-edit-select
#   Zinit:      ~/.local/share/zinit/plugins/Michael-Matta1---zsh-edit-select
#   Sheldon:    ~/.local/share/sheldon/repos/github.com/Michael-Matta1/zsh-edit-select
#   Manual:     wherever you ran: git clone https://github.com/Michael-Matta1/zsh-edit-select
PLUGIN_DIR=~/.oh-my-zsh/custom/plugins/zsh-edit-select  # ← change this to your path
```

**X11 Agent:**

```bash
cd "$PLUGIN_DIR/impl-x11/backends/x11"
make
```

**Wayland Agent:**

```bash
cd "$PLUGIN_DIR/impl-wayland/backends/wayland"
make
```

**XWayland Agent:**

```bash
cd "$PLUGIN_DIR/impl-wayland/backends/xwayland"
make
```

To clean/rebuild:

```bash
make clean && make
```

> **Note:** The plugin will automatically detect your display server and compile the appropriate agent on
> first shell startup. The Makefiles require:
>
> - **X11 builds:** `libX11` and `libXfixes` development headers/libraries
> - **Wayland builds:** `wayland-client` development headers, `wayland-scanner`, and `wayland-protocols`
>
> If compilation fails, the plugin will fall back to using external clipboard tools (`xclip` for X11,
> `wl-clipboard` for Wayland).

**Build Optimization:**

The default Makefiles compile with aggressive optimization flags for maximum runtime performance:

| Flag                                  | Purpose                                              |
| ------------------------------------- | ---------------------------------------------------- |
| `-O3`                                 | Maximum compiler optimization level                  |
| `-march=native`                       | CPU-specific instruction set (SSE, AVX, etc.)        |
| `-mtune=native`                       | CPU-specific scheduling optimizations                |
| `-flto`                               | Link-time optimization across compilation units      |
| `-ffunction-sections -fdata-sections` | Granular dead code elimination                       |
| `-Wl,--gc-sections`                   | Remove unused functions/data at link time            |
| `-Wl,--as-needed`                     | Skip linking unused shared libraries                 |
| `-Wl,-z,now`                          | Resolve all symbols at load time (security + perf)   |
| `-Wl,-z,relro`                        | Read-only relocations after startup                  |
| `-Wl,-z,noexecstack`                  | Mark stack non-executable (security hardening)       |
| `-Wl,-O1`                             | Linker-level optimization pass                       |
| `-Wl,--hash-style=gnu`                | Faster symbol lookup with GNU hash tables            |
| `-Wl,--build-id=none`                 | Omit build-id section for smaller binaries           |
| `-fomit-frame-pointer`                | Free up a register for better performance            |
| `-fno-plt`                            | Eliminate PLT indirection for faster library calls   |
| `-fno-semantic-interposition`         | Enable inlining across translation units             |
| `-fno-strict-aliasing`                | Permit type-punning casts in X11 agents (X11 only)   |
| `-fno-asynchronous-unwind-tables`     | Omit async unwind info not needed by signal handlers |
| `-fno-unwind-tables`                  | Omit synchronous unwind tables (no C++ exceptions)   |
| `-fmerge-all-constants`               | Deduplicate identical constants across units         |
| `-fipa-pta`                           | Interprocedural pointer analysis for better inlining |
| `-fno-ident`                          | Omit compiler identification string from binary      |
| `-fno-stack-protector`                | Remove stack-canary overhead (local-only agents)     |
| `-DNDEBUG`                            | Disable assertions in release builds                 |
| `-funroll-loops`                      | Unroll small loops for throughput                    |
| `-s`                                  | Strip symbols for smaller production binaries        |

> **Important:** `-march=native` produces binaries optimized for the CPU you're building on. These binaries
> may not run correctly on different CPU architectures. For distributed builds, replace
> `-march=native -mtune=native` with a portable baseline like `-march=x86-64-v2`.

</details>


---

## Platform Compatibility

<details>
<summary><b>Mouse Selection Replacement Feature</b></summary>

The **Mouse Selection Replacement** feature (automatically detecting and replacing mouse-selected text) has
comprehensive support across platforms via our custom agent implementations:

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

### Performance on Wayland

The native Wayland agent (`zes-wl-selection-agent`) provides:

- ✅ Direct protocol access (no `wl-copy`/`wl-paste` subprocess overhead)
- ✅ Zero typing lag with instant selection detection
- ✅ Event-driven architecture
- ✅ Superior responsiveness compared to standard clipboard tools

### If Selection Replacement Doesn't Work

1. Verify native Wayland or XWayland support is available
2. Check that your compositor supports PRIMARY selection protocols
3. Disable mouse replacement if needed: `edit-select config` → Option 1
4. Report issues with your compositor on [GitHub](https://github.com/Michael-Matta1/zsh-edit-select/issues)

</details>

<details>
<summary><b>WSL (Windows Subsystem for Linux)</b></summary>

### ✅ Fully Supported

**Both WSL1 and WSL2** are fully supported with comprehensive mouse selection integration:

- **Windows Terminal** — Full mouse selection replacement support with custom tracking modes
- **Clipboard operations** — Seamless access to Windows clipboard from the Linux shell
- **Custom tracking modes** — Out-of-the-box support for command-buffer aware mouse selection (`tracking` mode)
  and native terminal selection (`terminal` mode)
- **Auto mode** — Automatic mode selection derived from Windows Terminal `copyOnSelect` setting

### Performance on WSL

The WSL implementation includes:

- ✅ Fast in-memory clipboard cache (uses `/dev/shm` tmpfs on WSL2)
- ✅ Seamless clipboard bridge to Windows via compiled helper binaries
- ✅ Zero-lag mouse selection detection
- ✅ Unified behavior across both WSL versions

### WSL Specifics

- **WSL1 and WSL2** — Both are detected via `WSL_DISTRO_NAME` or `WSL_INTEROP` environment variables
- **Windows Terminal** — Recommended; use the dedicated [WSL Support](#wsl-support) section for configuration
- **Other terminals on WSL** — Keyboard selection features work universally; mouse selection replacement requires
  PRIMARY selection support (available in most modern terminals)

For detailed setup instructions, see [WSL Support](#wsl-support).

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

These features work universally on X11, Wayland, XWayland, and WSL:

- ✅ Shift+Arrow keys for text selection
- ✅ Ctrl+A to select all
- ✅ Ctrl+Shift+C to copy (or Ctrl+C in reversed mode)
- ✅ Ctrl+X to cut keyboard selection
- ✅ Ctrl+V to paste
- ✅ Ctrl+Z to undo
- ✅ Ctrl+Shift+Z to redo
- ✅ Delete/Backspace to remove keyboard selection
- ✅ Type or paste to replace keyboard selection
- ✅ Mouse selection replacement (where PRIMARY selection available)

> **Note on WSL:** All keyboard selection features listed above work identically on WSL. Mouse selection replacement also works on WSL with Windows Terminal when using the tailored tracking modes. See [WSL Support](#wsl-support) for Windows Terminal configuration details.


</details>

---

## Performance-Optimized Architecture

The plugin architecture is built around compiled native C agents that run as persistent background processes.
Each agent tracks selection changes via display server events, writes updates to a RAM-backed cache, and the
shell reads that cache using a single `zstat` call per keypress — zero process forks during normal typing.
Backend detection, agent startup, and configuration loading occur once at plugin load; all subsequent
operations use the cached results directly.

Core architectural properties:

- **Single-pass initialization** — Backend detection, agent startup, and configuration loading occur at plugin
  load time. The results are cached in shell variables and reused for the entire session.
- **Event-driven selection tracking** — X11 XFixes events and Wayland compositor events drive cache updates;
  all agents sleep in `poll()` between events, consuming no CPU while idle.
- **Compiled C agents** — Direct system calls compiled with aggressive optimization flags
  (`-O3 -march=native -flto -fipa-pta` and link-time dead code elimination); no interpreter overhead.
- **RAM-backed cache** — Cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions),
  with `TMPDIR` or `/tmp` as fallback. On standard systemd-based systems, all cache I/O remains in memory.
- **Graceful fallback** — If the compiled agents are unavailable, the plugin falls back to standard clipboard
  tools (`xclip`, `wl-paste`/`wl-copy`) transparently. No functionality is lost.

### Optimization Techniques

<details>
<summary><b>Startup & Initialization</b></summary>

**Backend Detection**

- Platform detection runs once at plugin load time by inspecting `ZES_FORCE_IMPL`, `WSL_DISTRO_NAME`/`WSL_INTEROP`,
  `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, and `DISPLAY` in priority order
- The detected backend (`x11`, `wayland`, or `wsl`) is stored in read-only shell variables (`ZES_ACTIVE_IMPL`,
  `ZES_DETECTION_REASON`, `ZES_IMPL_PATH`) and reused for the entire session
- WSL detection (via `WSL_DISTRO_NAME` or `WSL_INTEROP` environment variables) takes priority over X11/Wayland
  detection, ensuring the tailored WSL implementation is used when running in WSL
- A double-load guard (`_ZES_LOADER_LOADED`) prevents re-execution when `.zshrc` is re-sourced mid-session

**Lazy Backend Loading**

- Only the implementation matching the detected platform (X11, Wayland, or WSL) is sourced
- The other implementations are never loaded into memory, reducing both startup time and memory footprint
- The configuration wizard is also lazy-loaded — its file is only sourced when the user explicitly runs
  `edit-select config`

**Zsh Bytecode Compilation**

- Plugin files and all backend `.zsh` files are compiled to `.zwc` (Zsh wordcode bytecode) on first load via
  `zcompile`
- The bytecode is reused on subsequent sessions, bypassing source parsing entirely
- A file-existence guard (`[[ ! -f "${file}.zwc" ]]`) prevents redundant recompilation

**Agent Auto-Compilation**

- If the compiled agent binary is missing but its `Makefile` is present, the loader runs `make` automatically
  in a subshell
- Build errors produce stderr diagnostics naming the required `-dev` packages for the user's distribution

**Configuration Loading**

- The configuration file (`~/.config/zsh-edit-select/config`) is read once at startup and its values are
  stored in shell variables
- No configuration file I/O occurs during individual plugin operations

**Configuration Wizard**

The wizard file is lazy-loaded — sourced only when the user explicitly invokes `edit-select config`,
adding zero overhead to normal shell sessions. All wizard operations are implemented entirely as Zsh
built-in operations with no subprocess spawning:

- Config reads use `while IFS= read -r` loops; config writes use `print -r --` with Zsh array filtering
  (`${(@)array:#KEY=*}`) — no `sed` or `grep` forks at any point in the config I/O path
- Screen redraws use inline ANSI escape sequences (`printf '\033[2J\033[3J\033[H'`) instead of the
  `clear` command; this also clears the scrollback buffer in a single `write()` call rather than a fork
- The color gradient used in the wizard UI is computed once and cached in `$_ZESW_GRADIENT_CACHE` on
  first invocation; subsequent calls within the same shell session reuse the cached values directly
- Keybinding changes applied through the wizard take effect immediately in the current shell session via
  direct `bindkey` calls — no shell restart or `.zshrc` re-source is required

**Agent Startup & Readiness**

- Before launching a new agent instance, the backend removes any leftover `seq` and `primary` cache files
  from a previous session (`rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE"`). This prevents the
  shell from treating stale data written by the previous daemon as a new selection event immediately after
  startup.
- The agent is launched inside a subshell using the pattern `( agent_binary "$cache_dir" &>/dev/null & ; disown )`.
  The wrapping subshell isolates job control: the agent process does not appear in the shell's `jobs` list,
  does not receive `SIGHUP` when the terminal closes, and does not trigger Zsh background-job notifications.
- The plugin polls for the agent's readiness signal (the `seq` cache file appearing) with a maximum wait of
  1 second (40 × 25 ms intervals), rather than using a fixed sleep — the poll exits as soon as the file
  appears, so startup overhead matches actual agent initialization time.
- If a running agent is already present (PID file exists and `kill -0` succeeds), it is reused without
  restart.
- After the readiness poll completes, the plugin reads the initial `seq` file mtime and sets
  `_EDIT_SELECT_EVENT_FIRED_FOR_MTIME=1`. This marks the startup mtime as already-seen, preventing the first
  observed value from being treated as a new selection event on the first ZLE callback.

</details>

<details>
<summary><b>Runtime Execution</b></summary>

**mtime-Based Selection Detection**

The typing hot path is designed around a single `stat()` syscall per keypress:

1. The background agent writes selection content to a `primary` cache file, then updates a `seq` file
2. The shell detects changes by reading the `seq` file's modification time via `zstat` (the Zsh builtin,
   which performs a direct `stat()` syscall — no process fork)
3. If the mtime matches the cached value, the function returns immediately with no further work
4. If the mtime has changed, the `primary` file content is read via `$(<file)` (Zsh builtin read — also
   zero forks) and stored in a shell variable

Under normal typing conditions with no selection changes, the entire detection path costs one `stat()` syscall
and an integer comparison per keypress.

**Write-Ordering Guarantee**

The agent always writes the `primary` content file before updating the `seq` file. Since the shell uses the
`seq` file's mtime as its change signal, this ordering guarantees the shell never reads a half-written
`primary` file.

**In-Memory State Caching**

- The last-known selection state is held in shell variables (`_EDIT_SELECT_LAST_PRIMARY`,
  `_EDIT_SELECT_LAST_MTIME`)
- `_zes_sync_selection_state()` returns immediately if the cache file mtime is unchanged
- An event-fired gate (`_EDIT_SELECT_EVENT_FIRED_FOR_MTIME`) prevents the same mtime from triggering
  redundant processing across multiple ZLE callbacks within the same redraw cycle
- Keyboard selections bypass the mouse-detection path entirely
- State is invalidated only when the agent writes a new cache entry
- Widget handlers call `zle -c` (flush pending typeahead) rather than `zle -Rc` (flush + force full
  redraw); this avoids an unnecessary redraw cycle on every keypress that does not modify the display
- After each paste or cut operation, `_zes_sync_after_paste()` re-reads the current `seq` file mtime and
  `primary` file content directly from the daemon cache and updates `_EDIT_SELECT_LAST_MTIME` and
  `_EDIT_SELECT_LAST_PRIMARY`. This resets the detection baseline to the post-operation state, preventing the
  mtime written during the operation from being re-detected as a new selection event on the next ZLE callback.

**Direct Buffer Manipulation**

Paste and replace-selection operations compute the selection bounds and splice `BUFFER` directly using Zsh
string indexing (`${BUFFER:0:$start}${replacement}${BUFFER:$((start+len))}`), bypassing `zle kill-region`.
This prevents these operations from writing to ZLE's kill buffer, which would interfere with subsequent yank
(`Ctrl+Y`) operations. Mouse-selection deletion widgets use the same direct-splice approach. Cut operations
(`Ctrl+X`) intentionally retain `kill-region` so the deleted text remains available for yank.

**Cut Operation Ordering**

Cut copies the selected text to the clipboard before deleting it from the buffer. By performing the copy
first, the clipboard server begins serving the content to other applications immediately while the subsequent
buffer deletion completes — a single in-memory string splice with no external I/O.

**Agent Health Monitoring**

- Agent liveness is checked via `kill(pid, 0)` at 30-second intervals (amortized via `EPOCHSECONDS`
  comparison)
- If the agent process has exited, it is restarted transparently
- Health checks are not issued on individual keypress operations

**Event-Driven Detection**

- **X11 / XWayland**: The agent subscribes to XFixes `XFixesSetSelectionOwnerNotifyMask` events; it wakes only
  on selection owner changes. The main loop uses `poll()` with a 1-second timeout used solely for clean
  `SIGTERM` shutdown — no periodic work is performed on timeout
- **Wayland**: The compositor delivers primary selection events on owner change via
  `zwp_primary_selection_unstable_v1`. A 50 ms `poll()` timeout provides a secondary detection path for
  content changes within the same selection owner (e.g., the user extending a terminal text selection without
  releasing the mouse button — which changes content without changing the selection owner)
- All agents sleep in `poll()` between events, consuming no CPU during idle periods

</details>

<details>
<summary><b>C Agent Internals</b></summary>

**Compilation & Binary Optimization**

Agents are compiled with aggressive optimization flags to minimize binary size and maximize runtime
performance:

- `-O3 -march=native -mtune=native` — Full optimization with CPU-specific instruction scheduling
- `-flto` (Link-Time Optimization) — Whole-program optimization across all translation units
- `-fipa-pta` — Interprocedural pointer analysis for better alias resolution
- `-fomit-frame-pointer` — Frees a general-purpose register by omitting the frame pointer
- `-funroll-loops` — Unrolls loops to reduce branch overhead in tight event-handling paths
- `-fmerge-all-constants` — Merges identical constants across translation units, reducing `.rodata` size
- `-ffunction-sections -fdata-sections` + `-Wl,--gc-sections` — Dead code elimination: each function and data
  object is placed in its own section; the linker discards unreferenced sections
- `-fno-plt -fno-semantic-interposition` — Direct function calls without PLT indirection; allows the compiler
  to inline across translation units without interposition checks
- `-fno-asynchronous-unwind-tables -fno-unwind-tables` — Removes `.eh_frame` exception unwind sections
  (unnecessary for C agents that do not use C++ exceptions), reducing binary size
- `-DNDEBUG` — Disables all `assert()` checks in release builds, removing debug overhead
- `-Wl,--as-needed` — Only links libraries that are actually referenced
- `-Wl,-O1` — Linker optimization pass for symbol resolution and relocation processing
- `-Wl,-z,now -Wl,-z,relro` — Full RELRO: the Global Offset Table is resolved and marked read-only at load
  time
- `-Wl,-z,noexecstack` — Non-executable stack
- `-Wl,--hash-style=gnu` — GNU hash table for faster dynamic symbol lookup
- `-s -Wl,--build-id=none -fno-ident` — Strips all symbols, build-id, and compiler version strings from the
  binary
- `-fno-strict-aliasing` _(X11 and XWayland agents only)_ — Permits the type-punning pointer casts required
  by Xlib's event structures without aliasing-rule violations; not applied to the Wayland agent, which does
  not cast between unrelated pointer types
- `-fno-stack-protector` — Removes stack-canary instrumentation overhead; the agents run locally as
  unprivileged user daemons with no network-facing attack surface
- System libraries (`libwayland-client`, `libX11`, `libXfixes`) are the only runtime dependencies

**Operation Modes**

Each agent binary supports five operation modes within a single executable, eliminating the need for separate
per-mode binaries:

| Mode | CLI Flag | Behavior |
| --- | --- | --- |
| **Daemon** | _(default)_ | Persistent PRIMARY selection monitoring with event-driven cache updates |
| **Oneshot** | `--oneshot` | Print current PRIMARY selection to stdout and exit |
| **Get clipboard** | `--get-clipboard` | Print current CLIPBOARD contents to stdout and exit |
| **Copy clipboard** | `--copy-clipboard` | Read stdin, take clipboard ownership, fork a background server |
| **Clear primary** | `--clear-primary` | Clear the PRIMARY selection and exit |

**Persistent File Descriptor Architecture**

All three agents open the cache file descriptors (`fd_primary`, `fd_seq`) once at daemon startup and hold them
open for the entire agent lifetime. Cache writes use `pwrite()` (atomic positional write — no preceding
`lseek()`) followed by `ftruncate()` to trim the file to the exact written length, preventing stale trailing
bytes from longer previous entries. This reduces each cache update to 2 syscalls per file, compared to the
`open()`/`write()`/`fsync()`/`close()` pattern (4 syscalls per file) used by conventional approaches.

**Content Deduplication** _(Wayland agent)_

The Wayland agent's `check_and_update_primary()` and `ps_device_handle_selection()` compare incoming selection
content against a cached copy (`last_known_content`) using `memcmp()` before writing. When the content is
unchanged — common during static selections or repeated compositor events — the cache write is skipped
entirely, avoiding unnecessary disk I/O. When new content does arrive, buffer ownership is transferred by
nulling the source pointer (`sel = NULL`) after assigning it to `last_known_content`, rather than
duplicating the buffer — eliminating one `malloc` + `memcpy` per selection event.

The X11 and XWayland agents intentionally skip deduplication: they always increment the sequence counter and
write, because a re-selection of identical text (e.g., deselect then re-select the same word) must still
fire a new event in the shell for correct mouse-selection tracking.

**Descriptor Safety**

`O_CLOEXEC` is applied to every file descriptor: all `open()`, `pipe2()`, and `memfd_create()` calls include
the close-on-exec flag. This prevents file descriptor leaks if the agent forks a clipboard server child
process.

**Sequence Counter Design**

The sequence counter is seeded from `time(NULL)` at daemon startup. This provides monotonic ordering across
agent restarts — a newly started agent will always produce sequence values higher than those from the previous
instance, preventing the shell from misinterpreting a restart as "no change." The daemon writes the initial
sequence value to the `seq` file before the shell begins polling, closing the startup race window.

**X11 Atom Handling**

- The native X11 agent (`zes-x11-selection-agent`) uses private atom names (`ZES_SEL`, `ZES_CLIP`) as
  selection conversion properties. This avoids collisions with properties written by other applications on a
  shared X server.
- The XWayland agent (`zes-xwayland-agent`) reuses the standard `PRIMARY` and `CLIPBOARD` atoms directly as
  property names, which is safe because XWayland provides an isolated per-session X server where no other
  clients compete for property names.
- Both agents intern all atom handles once at startup and reuse them for the agent's lifetime — no per-event
  `XInternAtom()` round-trips to the X server.

**Clipboard Server Lifecycle**

When the shell copies text to the clipboard (`--copy-clipboard`), the agent forks a background child process
that becomes the clipboard owner and serves paste requests to other applications:

- The parent process exits immediately, returning control to the shell
- The child calls `setsid()` to create a new session and ignores `SIGHUP` to survive terminal closure.
  The Wayland agent additionally ignores `SIGPIPE` because paste requestors may close their pipe
  mid-transfer
- **X11 / XWayland**: The server advertises `TARGETS`, `UTF8_STRING`, and `XA_STRING`, and serves
  `SelectionRequest` events in a `poll()` loop with 100 ms timeout. It exits when another application takes
  clipboard ownership (`SelectionClear`) or after approximately 50 seconds of idle time
- **Wayland**: The server creates a `wl_data_source` offering multiple MIME types
  (`text/plain;charset=utf-8`, `text/plain`, `UTF8_STRING`, `STRING`) and responds to `send` callbacks. It
  exits when the compositor signals ownership loss via the `cancelled` callback

**Adaptive Poll Timeouts** _(selection retrieval)_

When reading selection content after a conversion request, the agents use adaptive timeouts to balance
responsiveness against syscall frequency:

- **X11 / XWayland**: 5 ms polls for the first 20 ms (catching common fast responses), then 20 ms polls
  thereafter to reduce syscall rate during slow responses
- **Wayland**: 500 ms initial timeout covers the IPC round-trip; subsequent read chunks use a 100 ms timeout
  to detect EOF quickly

**Non-Blocking Clipboard Reads** _(Wayland agent)_

Clipboard read pipes are created with `pipe2(O_CLOEXEC)` and configured with `fcntl(fd, F_SETFL, O_NONBLOCK)`
directly — without a preceding `F_GETFL` read — then read via `poll()` + `read()` in a loop with exponential
buffer growth (capped at 1 MB for PRIMARY, 4 MB for CLIPBOARD).

</details>

<details>
<summary><b>Protocol & Compositor Compatibility</b></summary>

**Wayland Protocol Integration**

The Wayland agent connects directly to the compositor via `wl_display_connect()` and negotiates protocol
support through the registry. It handles three distinct compositor architectures:

PRIMARY selection is managed via `zwp_primary_selection_unstable_v1`, which is the standard unstable protocol
supported by all major compositors.

Clipboard operations use a three-mechanism priority chain, selected based on compositor capabilities:

1. **`ext_data_control_v1`** (preferred) — The standardized successor to the wlroots data-control protocol.
   Supports clipboard read and write without requiring keyboard focus. The agent prefers this over `zwlr` when
   both are advertised.
2. **`zwlr_data_control_unstable_v1`** — The wlroots-originated data-control protocol, serving as fallback
   when `ext_data_control_v1` is not available. Same capabilities.
3. **`wl_data_device`** — Core Wayland protocol fallback for compositors without any data-control extension
   (primarily GNOME/Mutter versions before 47). Requires a valid keyboard focus serial, which the agent
   obtains by creating a visible surface.

An additional **OSC 52** path is available for clipboard writes — a fire-and-forget terminal escape sequence
written in a single `write()` call to `/dev/tty`, requiring no Wayland protocol involvement.

**Mutter/GNOME Compatibility**

Mutter only delivers PRIMARY selection events to Wayland clients that have a mapped surface. The daemon creates
a permanent 1×1 pixel transparent `xdg_toplevel` surface with an **empty input region** (so it cannot receive
input focus or interfere with user interaction). The surface pixel is a fully transparent ARGB value, rendered
via a SHM buffer created with `memfd_create()` (or `shm_open()` on systems without `memfd_create`).

For `--copy-clipboard` on compositors requiring a keyboard focus serial (`wl_data_device` path), a separate
surface without an empty input region is created to receive `wl_keyboard.enter` events that carry the serial
needed by `wl_data_device.set_selection()`.

The `xdg_wm_base` ping/pong handler responds to compositor ping requests — failure to respond causes the
compositor to mark the client as unresponsive and stop delivering events.

**X11 XFixes Integration**

- The X11 agents use `XFixesSelectSelectionInput()` to subscribe to `SetSelectionOwnerNotifyMask` on the root
  window
- Events are delivered by the X server on selection owner changes — no polling is required
- The main loop uses `poll()` on the X connection file descriptor instead of blocking `XNextEvent()`, because
  with glibc's `signal()` (which sets `SA_RESTART`), a blocking `XNextEvent` cannot be interrupted by
  `SIGTERM`. After `poll()` returns, `XPending()` is called to drain Xlib's internal buffer — data may have
  arrived during a previous `read()` that filled the internal buffer with multiple events.

**XWayland Agent Selection**

On Wayland sessions where `DISPLAY` is also set (XWayland available), the plugin selects `zes-xwayland-agent`
over `zes-wl-selection-agent`. The XWayland agent reads selection state through X11 atoms via the XWayland
bridge, bypassing the Wayland protocol stack entirely. This provides lower latency, avoids the Mutter surface
requirement, and offers broader compositor compatibility.

</details>

<details>
<summary><b>Selection Detection Architecture</b></summary>

**Shell-Side Detection Path**

The `_zes_sync_selection_state()` function is called by every widget before acting. Its execution path:

1. `zstat -A stat_info +mtime "$SEQ_FILE"` — reads the sequence cache file's mtime via a single `stat()`
   syscall (Zsh builtin, zero forks)
2. If the mtime matches `_EDIT_SELECT_LAST_MTIME`, the function returns immediately
3. If the mtime has changed, the `primary` file is read via `$(<file)` (Zsh builtin) and
   `_EDIT_SELECT_NEW_SELECTION_EVENT` is set to 1
4. The new mtime and an event-fired gate (`_EDIT_SELECT_EVENT_FIRED_FOR_MTIME`) are updated to prevent the
   same mtime from re-triggering across multiple ZLE callbacks

**ZLE Pre-Redraw Hook**

The `edit-select::zle-line-pre-redraw` hook is registered via `add-zle-hook-widget` and runs before every
prompt redraw. It performs:

1. **Amortized liveness probe**: Checks `kill -0 $pid` only if `EPOCHSECONDS > _ZES_LAST_PID_CHECK + 30`.
   If the agent has died, restarts it transparently.
2. **Mtime check**: Same `zstat` path as `_zes_sync_selection_state()` — one `stat()` syscall per redraw. On
   mtime change, reads the `primary` file and sets the event flag.

**Cache File Protocol**

- The agent writes primary content first, then increments and writes the sequence number — this ordering
  guarantee prevents the shell from reading a partially updated `primary` file
- The shell reads only the sequence file's mtime as the change signal
- Full content is read only when a change is confirmed
- The sequence counter starts from `time(NULL)`, providing monotonic ordering even across agent restarts

**Early Return Conditions**

- Unchanged mtime → immediate return before any selection comparison
- Mouse replacement disabled → `_zes_detect_mouse_selection()` returns immediately
- Active keyboard selection → mouse detection path is never entered
- Stale selection state → invalidated on mtime change, not on a timer

</details>

<details>
<summary><b>Terminal Focus & Multi-Pane Isolation</b></summary>

**DECSET 1004 Focus Tracking**

Terminal focus tracking is enabled at startup via `printf '\e[?1004h' >/dev/tty`. The escape sequence is
written to `/dev/tty` rather than stdout to avoid triggering Powerlevel10k instant-prompt console-output
warnings. Terminals that do not support DECSET 1004 silently ignore the request; the plugin's behavior is
unchanged.

**Focus-In Handler**

When the terminal pane receives focus (`CSI I` escape sequence), the `_zes_terminal_focus_in` handler:

1. Records the current `seq` file mtime as already-seen (`_EDIT_SELECT_LAST_MTIME`)
2. Sets `_EDIT_SELECT_EVENT_FIRED_FOR_MTIME = 1`
3. Clears `_EDIT_SELECT_NEW_SELECTION_EVENT`, `_EDIT_SELECT_ACTIVE_SELECTION`, and
   `_EDIT_SELECT_PENDING_SELECTION`

This ensures that selection events written by another pane to the shared cache while this pane was unfocused
are not mistakenly treated as new mouse selections. Focus events are bound in all keymaps (`emacs`,
`edit-select`, and `main`).

**Independent Selection State**

Each terminal pane maintains its own selection state in independent shell variables. PRIMARY selection is
cleared after each cut/paste operation to prevent a subsequent pane's detection from reading a stale value.

</details>

<details>
<summary><b>Resource Behavior</b></summary>

- All detection and configuration reads use in-memory cached values — no file I/O during normal typing
- Selection state changes are detected via one `stat()` syscall per keypress; file content is read only when
  the mtime has changed
- Agent liveness verification runs at 30-second intervals; it is not issued on individual keystroke operations
- C agents operate with direct system calls only; no interpreter or scripting runtime is involved at runtime
- Zsh plugin scripts are compiled to `.zwc` bytecode on first load; source parsing is skipped on all
  subsequent sessions
- Cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions), `TMPDIR`, or `/tmp`; on
  standard systemd-based systems, no disk I/O occurs
- Integer state flags (`_EDIT_SELECT_DAEMON_ACTIVE`, `_EDIT_SELECT_NEW_SELECTION_EVENT`, etc.) enable fast
  arithmetic checks without string comparison
- `EPOCHSECONDS` and `EPOCHREALTIME` (from `zsh/datetime`) provide second-resolution and
  microsecond-resolution timestamps for liveness probes and selection timing respectively — no `date` forks
- The cache holds only the current selection state; stale entries are not accumulated

</details>

<details>
<summary><b>Clipboard Operation Responsiveness</b></summary>

The following tables document clipboard operation latency for the custom agent, measured with
`clock_gettime(CLOCK_MONOTONIC)` across multiple payload sizes and iteration counts. All measurements include
full end-to-end time: from operation initiation through data availability.

**X11 Clipboard Latency:**

| Test Scenario                          | xclip Avg    | Custom Avg   | Improvement      |
| -------------------------------------- | ------------ | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 4.025 ms     | 2.258 ms     | **43.9% faster** |
| Medium text (500 chars, 50 iterations) | 4.307 ms     | 2.211 ms     | **48.7% faster** |
| Large text (5KB, 25 iterations)        | 3.949 ms     | 2.310 ms     | **41.5% faster** |
| Very large (50KB, 10 iterations)       | 4.451 ms     | 2.499 ms     | **43.9% faster** |
| Rapid consecutive (200 iterations)     | 4.206 ms     | 2.321 ms     | **44.8% faster** |
| **Overall Average**                    | **4.187 ms** | **2.320 ms** | **44.6% faster** |

**Wayland Clipboard Latency:**

| Test Scenario                          | wl-copy Avg   | Custom Avg   | Improvement      |
| -------------------------------------- | ------------- | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 57.073 ms     | 1.966 ms     | **96.6% faster** |
| Medium text (500 chars, 50 iterations) | 60.382 ms     | 2.441 ms     | **96.0% faster** |
| Large text (5KB, 25 iterations)        | 63.020 ms     | 1.809 ms     | **97.1% faster** |
| Very large (50KB, 10 iterations)       | 58.343 ms     | 2.907 ms     | **95.0% faster** |
| Rapid consecutive (200 iterations)     | 58.860 ms     | 1.546 ms     | **97.4% faster** |
| **Overall Average**                    | **59.535 ms** | **2.134 ms** | **96.4% faster** |

**Observed Latency:**

- **X11:** 2.320 ms average; 2.211 ms minimum across all payload sizes
- **Wayland:** 2.134 ms average; 1.546 ms minimum under rapid consecutive operations
- Latency is consistent across payload sizes from 50 bytes to 50 KB
- Paste operations retrieve data directly from the in-memory agent cache

**Why the Wayland improvement is larger than X11:**

`wl-copy` forks a new process for every clipboard operation, adding approximately 60 ms of `fork()+exec()`
and IPC overhead regardless of payload size. `xclip` also forks per operation, but its overhead is
approximately 4.2 ms — one order of magnitude lower. The persistent agent eliminates the process spawn cost
on both platforms; the remaining latency is the native protocol IPC round-trip time.

**Clipboard Server Behavior:**

- The agent maintains clipboard ownership and responds to paste requests internally, without involving the
  shell process
- On X11/XWayland, the clipboard server exits when another application takes clipboard ownership
  (`SelectionClear` event) or after approximately 50 seconds of inactivity (whichever comes first)
- On Wayland, the clipboard server exits when the compositor signals ownership loss via the `cancelled`
  callback
- If the compiled agents are unavailable, the plugin falls back to `xclip` (X11) or `wl-copy`/`wl-paste`
  (Wayland) — all functionality is preserved

> **Benchmark Methodology:** Tests conducted using purpose-built C benchmarking tools with
> `clock_gettime(CLOCK_MONOTONIC)` for nanosecond accuracy. Each iteration measures the full end-to-end path
> including process spawn, IPC, and data transfer. The benchmark suite is available in
> [`assets/benchmarks/`](assets/benchmarks/).

</details>

> Operations complete faster than the
> [human perception threshold](https://www.tobii.com/resource-center/learn-articles/speed-of-human-visual-perception).


---

## Contributing

Contributions, suggestions, and recommendations are welcome. If you encounter a bug or unexpected behavior,
please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with a clear description and
steps to reproduce. Pull requests are open for any meaningful improvement — bug fixes, new features, or
compatibility with additional environments.

If you have ideas for enhancements, feature requests, or recommendations to improve the plugin's functionality
or documentation, feel free to share them. Your feedback helps shape the direction of the project and ensures
it meets the needs of the community.

**A note on development:** This plugin is developed and tested privately over an extended period before any
public release. After every change — whether a fix, enhancement, or new feature — the plugin is heavily tested
to validate stability and catch regressions under real conditions. New features are typically accompanied by
new edge cases; each one is identified and resolved before the code is released. The goal is to ship complete,
reliable increments rather than incremental works-in-progress. As a result, public commits tend to represent
significant, well-tested milestones rather than a continuous stream of small changes.

If something does not work as expected, please report it — every issue report directly improves the plugin's
reliability for everyone.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- #### This project began as a fork ([Michael-Matta1/zsh-shift-select](https://github.com/Michael-Matta1/zsh-shift-select)) of [jirutka/zsh-shift-select](https://github.com/jirutka/zsh-shift-select)
  - The fork was started to add the ability to copy selected text, because the jirutka/zsh-shift-select plugin
    only supported deleting selected text and did not offer copying by default. Since then, the project has
    evolved with its own new features, enhancements, bug fixes, design improvements, and a fully changed
    codebase, and it now provides a full editor-like experience.

- #### Wayland Protocol Specifications

  The bundled Wayland protocol XML files and their `wayland-scanner`-generated C bindings are covered by their
  respective copyright and license terms:
  - [`primary-selection-unstable-v1.xml`](impl-wayland/backends/wayland/primary-selection-unstable-v1.xml) —
    Copyright © 2015, 2016 Red Hat (MIT License)
  - [`wlr-data-control-unstable-v1.xml`](impl-wayland/backends/wayland/wlr-data-control-unstable-v1.xml) —
    Copyright © 2018 Simon Ser, © 2019 Ivan Molodetskikh (MIT-like License)
  - [`ext-data-control-v1.xml`](impl-wayland/backends/wayland/ext-data-control-v1.xml) — Copyright © 2018
    Simon Ser, © 2019 Ivan Molodetskikh, © 2024 Neal Gompa (MIT-like License)

  The `xdg-shell` binding files follow the same pattern, generated from the `xdg-shell.xml` specification in
  the wayland-protocols repository.

---

## References

- [Michael-Matta1/dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) — Dotfiles showcasing the
  plugin with Kitty, VS Code, and Zsh.

- [Zsh ZLE shift selection — StackOverflow](https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection)
  — Q&A on Shift-based selection in ZLE.

- [Zsh Line Editor Documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html) — Official ZLE
  widgets and keybindings reference.
