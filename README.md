# Zsh Edit-Select

Zsh plugin that lets you edit your command line like a text editor. Select text with Shift + Arrow keys or the
mouse, type or paste to replace selections, use standard editing shortcuts (copy, cut, paste, undo, redo,
select all), and customize keybindings through an interactive wizard — with full X11 and Wayland clipboard
support.

[demo video](https://github.com/user-attachments/assets/fa2a84f4-bce5-44c8-9783-76332d9b6243)

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
- [Platform Compatibility](#platform-compatibility)
- [Performance & Optimization](#performance--optimization)
- [Default Key Bindings Reference](#default-key-bindings-reference)
- [Troubleshooting](#troubleshooting)
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
- ✅ **Clipboard integration** — Works with X11 and Wayland
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

| Display Server | Agent                     | Protocol                                               | Performance vs. External Tool |
| -------------- | ------------------------- | ------------------------------------------------------ | ----------------------------- |
| **X11**        | `zes-x11-selection-agent` | XFixes extension + CLIPBOARD atom                      | **44.6% faster than xclip**   |
| **Wayland**    | `zes-wl-selection-agent`  | `zwp_primary_selection_unstable_v1` + `wl_data_device` | **96.4% faster than wl-copy** |
| **XWayland**   | `zes-xwayland-agent`      | X11 XFixes through XWayland                            | XWayland compatibility layer  |

**External Tools (Fallback Only):**

| Display Server | Tool                   | When Used                 |
| -------------- | ---------------------- | ------------------------- |
| **X11**        | `xclip`                | Only if agent unavailable |
| **Wayland**    | `wl-copy` / `wl-paste` | Only if agent unavailable |

> The agents handle copy, paste, and clipboard operations directly through native protocols—no external tools
> needed. They run as background processes and communicate with the plugin through a fast in-memory cache,
> giving you instant clipboard response with zero subprocess overhead.

> See [Performance & Optimization](#performance--optimization) for benchmarks and implementation details.

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
or who prefer a fully guided, hands-off setup. It detects your environment (X11, Wayland, or XWayland),
installs dependencies, sets up the plugin, and configures your terminal in a single run. It has been tested
across multiple distributions using Docker containers and virtual machines, and handles the most common
configurations — but not every edge case can be guaranteed. If you encounter an issue, please
[report it](https://github.com/Michael-Matta1/zsh-edit-select/issues) so it can be addressed.

To use the auto-installer, simply run:

```bash
curl -fsSL https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install.sh -o install.sh && chmod +x install.sh && bash install.sh
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
  `zypper`, `apk`, and `nix`) across X11, Wayland, and XWayland environments.
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

### For Wayland Users


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
> Alacritty, Foot, VS Code) automatically. If you prefer to configure manually follow the steps below.
> [Open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) if you need help with a terminal
> that is not covered.

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

> **Configurations in practice:** The [dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) repository
> includes working setups for **Kitty** (`kitty.conf`) and **VS Code** (`keybindings.json`) that demonstrate
> that this plugin can be seamlessly integrated alongside other tools and configurations.

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

### Performance Advantage on Wayland

The native Wayland agent (`zes-wl-selection-agent`) provides:

- ✅ Direct protocol access (no `wl-copy`/`wl-paste` subprocess overhead)
- ✅ Zero typing lag with instant selection detection
- ✅ Event-driven architecture (no polling)
- ✅ Superior responsiveness compared to standard clipboard tools

### If Selection Replacement Doesn't Work

1. Verify native Wayland or XWayland support is available
2. Check that your compositor supports PRIMARY selection protocols
3. Disable mouse replacement if needed: `edit-select config` → Option 1
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
- ✅ Ctrl+Shift+C to copy (or Ctrl+C in reversed mode)
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

The plugin architecture is built around a compiled native C agent that runs as a persistent background
process. The agent tracks selection changes via display server events, writes updates to a RAM-backed cache
file, and the shell reads that cache using a single `zstat` call per keypress. Backend detection, agent
startup, and configuration loading occur once at plugin load; all subsequent operations use the results
directly.

Core architectural properties:

- **Single-pass initialization** — Backend detection, agent startup, and configuration loading occur at plugin
  load time. The results are cached in shell variables and reused for the entire session.
- **Event-driven selection tracking** — X11 XFixes events and Wayland compositor events drive cache updates;
  both agents sleep in `poll()` between events.
- **Compiled C agents** — Direct system calls with compiler optimization flags
  (`-O3 -march=native -flto -fipa-pta`); no interpreter overhead.
- **RAM-backed cache** — Agents write to `XDG_RUNTIME_DIR` (tmpfs) with `/dev/shm` as fallback; all I/O
  remains in memory.

### Optimization Techniques

<details>
<summary><b>Startup & Initialization</b></summary>

**Backend Detection**

- Platform detection runs once at plugin load time by inspecting `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, and
  `DISPLAY`
- The detected backend is stored in shell variables and reused for the shell session

**Lazy Backend Loading**

- Only the implementation matching the detected display server (X11 or Wayland) is sourced
- The other implementation is never loaded into memory, reducing both startup time and memory footprint

**Zsh Bytecode Compilation**

- Plugin files are compiled to `.zwc` (Zsh bytecode) on first load
- The bytecode is reused on subsequent sessions, bypassing source parsing
- Compilation runs in the background and does not delay shell startup

**Configuration Loading**

- The configuration file is read once at startup and its values are stored in shell variables
- No file I/O occurs during individual plugin operations

**Agent Startup**

- The selection-tracking agent is started once when the plugin loads and remains active for the shell session

</details>

<details>
<summary><b>Runtime Execution</b></summary>

**mtime-Based Selection Detection**

- The background agent writes selection data to a cache file
- The shell detects changes by reading the file's modification time via `zstat`
- A single `stat()` syscall is sufficient per keypress; the file content is not read unless the mtime has
  changed

**In-Memory State Caching**

- The last-known selection state is held in shell variables
- `_zes_sync_selection_state()` returns immediately if the cache file mtime is unchanged
- Keyboard selections bypass the mouse-detection path entirely
- State is invalidated only when the agent writes a new cache entry

**Agent Health Monitoring**

- Agent liveness is checked via `kill(pid, 0)` at 30-second intervals
- If the agent process has exited, it is restarted transparently
- Health checks are not issued on individual keypress operations

**Event-Driven Detection**

- **X11**: The agent subscribes to XFixes `SelectionNotify` events; the agent wakes only on selection owner
  changes
- **Wayland**: The compositor delivers primary selection events on owner change; a 50 ms `poll()` fallback
  handles content changes within the same selection owner (e.g., extending a selection without releasing the
  mouse)
- Both agents sleep in `poll()` between events, consuming no CPU during idle periods

</details>

<details>
<summary><b>C Agent Architecture</b></summary>

**Compilation**

- Agents are compiled with `-O3`, `-march=native`, `-flto`, and `-fipa-pta`
- System libraries are the only runtime dependencies

**Event-Driven Design**

- Wayland agent connects directly to the Wayland display server:
  - Subscribes to `zwp_primary_selection_unstable_v1` for PRIMARY selection events
  - Subscribes to `wl_data_device` for clipboard events
  - Sleeps in `poll()` between server events; CPU usage is zero during idle periods
- X11 agent uses the XFixes extension for selection change notifications:
  - `poll()`-based main loop with a 1-second timeout used solely for clean `SIGTERM` shutdown

**Conditional Cache Writes**

- `write_primary()` compares incoming content against the current cache before writing
- Unchanged content is not written, avoiding approximately 80 superfluous write syscalls per second under
  rapid selection activity
- Writes are ordered: primary content first, then the sequence number file
- The shell keys off the sequence file's mtime, not the primary content file

**System-Call-Level Design**

Applied across all three agents:

- **Persistent file descriptors** — Cache file FDs are opened once at agent startup and held open for the
  session; no per-write `open()`/`close()` cycle
- **`pwrite()` for cache writes** — Performs an atomic positional write in a single syscall, without a
  preceding `lseek()`
- **`ftruncate()` after every write** — Truncates the cache file to the exact written length after each
  `pwrite()`, preventing stale bytes from longer previous entries
- **`O_CLOEXEC` on all file descriptors** — Applied to all `open()`, `pipe2()`, and `memfd_create()` calls to
  prevent fd inheritance across `exec()`
- **Conditional write skip** — `write_primary()` compares new and existing content; the write is skipped
  entirely when content is unchanged
- **`XInternAtom` result caching** _(X11 agent)_ — X11 atom handles are resolved once at startup and stored;
  they are not re-queried per event
- **`poll()` for all timed waits** — Provides accurate waits with immediate wake-up on fd activity
- **`/dev/shm` cache fallback** — Used when `XDG_RUNTIME_DIR` is unavailable, keeping cache files in RAM
- **Direct `F_SETFL O_NONBLOCK` on clipboard pipes** _(Wayland agent)_ — Clipboard read pipes are created with
  `pipe2(O_CLOEXEC)` and configured with `F_SETFL O_NONBLOCK` directly, without a preceding `F_GETFL` read

**Operation Modes**

The agent binary supports three operation modes within a single binary, eliminating the need for separate
per-mode processes:

- **Daemon mode** — Continuous selection tracking with event-driven cache updates
- **Oneshot mode** — Single selection read for non-persistent contexts
- **Clipboard mode** — Direct clipboard read or write

**Event Loop Design**

- **X11 daemon** — XFixes `SelectionNotify` events + `poll()` with a 1-second timeout for `SIGTERM` handling;
  no periodic work is performed on timeout
- **Wayland daemon** — Wayland event loop + `poll()` with a 50 ms timeout; on timeout,
  `check_and_update_primary()` checks for content changes within the current selection owner
- **Clipboard copy (X11)** — `poll()` 100 ms loop serving `SelectionRequest` events; `timeout_count` resets on
  each served paste and the process exits after 500 idle cycles (~50 seconds)
- **Clipboard copy (Wayland)** — Event loop exits immediately after the first successful paste
  (`copy_done = true`)

</details>

<details>
<summary><b>Protocol & System Call Design</b></summary>

**Wayland Protocol Integration**

- The agent connects directly to the Wayland server socket using the native protocol
- PRIMARY selection is managed via `zwp_primary_selection_unstable_v1`
- Clipboard is managed via `wl_data_device`

**X11 XFixes Integration**

- The X11 agent uses the XFixes extension to receive `SelectionNotify` events
- Events are delivered by the X server on selection owner changes; no polling is required

**mtime-Based Cache Reads**

- The shell uses `zstat` to read the sequence file's mtime
- The mtime value is compared in-memory to the last-known value; a full file read occurs only when the mtime
  differs
- This keeps the common-case path (no selection change) to a single `stat()` syscall

**Cache File Structure**

- Cache files serve as synchronization signals, not data transfer channels
- The sequence file's mtime carries the change signal; content reads are conditional on a mtime change

</details>

<details>
<summary><b>Platform-Specific Design</b></summary>

**X11**

- `zes-x11-selection-agent` manages all copy/paste operations natively
- XFixes extension delivers hardware-level event notification for selection owner changes
- `poll()`-based main loop; X11 atom handles cached at startup

**Wayland**

- Native Wayland event loop for selection and clipboard monitoring
- Dual protocol support:
  - PRIMARY selection via `zwp_primary_selection_unstable_v1`
  - Clipboard via `wl_data_device`
- A permanent 1×1 transparent `xdg_toplevel` surface with an empty input region is created at startup; this is
  required for Mutter/GNOME to deliver PRIMARY selection events and is harmless on wlroots-based compositors
  and KDE

**XWayland Bridge**

- `zes-xwayland-agent` handles clipboard integration for applications running under XWayland
- Operates via the X11 XFixes protocol through the XWayland compatibility layer

</details>

<details>
<summary><b>Resource Overhead Properties</b></summary>

The following describes the resource behavior of the current implementation:

- Clipboard operations are performed within the agent process; no fork/exec is issued per clipboard action
- Backend detection and configuration are loaded at startup; subsequent operations read from in-memory cached
  values only
- Selection state changes are detected via a single `stat()` call on the cache file's mtime; the file content
  is not read unless the mtime has changed
- Agent liveness verification uses `kill(pid, 0)` at 30-second intervals; it is not issued on individual
  keystroke operations
- `_zes_sync_selection_state()` returns without further processing when the cache mtime is unchanged,
  preventing redundant detection work
- C agents operate exclusively with direct system calls; no interpreter or scripting runtime is involved
- Zsh plugin scripts are compiled to `.zwc` bytecode on first load; source parsing does not occur on
  subsequent sessions
- Each terminal pane maintains independent selection state, preventing cross-pane interference

</details>

<details>
<summary><b>Advanced Features</b></summary>

**Multi-Pane Selection Independence**

- Each terminal pane maintains its own selection state in independent shell variables
- PRIMARY selection is cleared after each operation to prevent a subsequent pane's detection from reading a
  stale value
- Early return checks in `_zes_sync_selection_state()` skip re-detection when the cached state is still valid

**Duplicate Occurrence Handling**

- When the mouse-selected text appears more than once in the command buffer, the plugin displays a warning
  prompt: "Duplicate text: place cursor inside the occurrence you want to modify"
- This prevents silent replacement of the wrong occurrence
- The check applies only to mouse selections; keyboard selections are unambiguous by construction

**Display State Integrity**

- Status messages are explicitly cleared after each operation
- A display refresh is issued after state changes to maintain consistent screen output

**Configuration Persistence**

- Settings are written to `~/.config/zsh-edit-select/config`
- The file is read once at startup and the values are cached for the session
- A reset command restores all values to their compiled-in defaults

**Backend Override**

- The `ZES_FORCE_IMPL` environment variable accepts `x11` or `wayland` to bypass automatic detection
- Intended for debugging and compatibility testing

</details>

<details>
<summary><b>Memory Management & State Efficiency</b></summary>

**Memory Footprint**

- State variables use integer flags and string values
- Only the implementation for the active display server is loaded
- Cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions); no spinning-disk I/O

**State Variable Design**

- Integer flags (`DAEMON_ACTIVE`, `NEW_SELECTION_EVENT`) enable fast boolean checks
- `EPOCHREALTIME` provides sub-second timestamps for selection timing
- State variables are reused across operations

**Cache Invalidation**

- The cached mtime value is updated only when the sequence file mtime changes
- The cached selection content is updated only when the primary cache file content differs from the stored
  value
- The cache holds only the current selection state; stale entries are not accumulated

</details>

<details>
<summary><b>Clipboard Operation Latency</b></summary>

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

- **X11:** 2.320ms average; 2.211ms minimum across all payload sizes
- **Wayland:** 2.134ms average; 1.546ms minimum under rapid consecutive operations
- Latency is consistent across payload sizes from 50 bytes to 50KB
- Paste operations retrieve data directly from the in-memory agent cache

**Wayland Latency Characteristics:**

The Wayland agent's sub-2.2ms average latency reflects the persistent-agent architecture. The agent holds an
active connection to the Wayland server and completes clipboard operations within its own process.
Per-operation latency is dominated by Wayland IPC round-trip time.

**Agent Implementation Notes:**

- The agent maintains clipboard ownership and responds to `SelectionRequest` events internally
- Clipboard ownership is released automatically after approximately 50 seconds without a paste request
- If the custom agents are unavailable, the plugin falls back to `xclip` (X11) or `wl-copy`/`wl-paste`
  (Wayland)

> **Benchmark Methodology:** Tests conducted using high-precision C benchmarking tools with
> `clock_gettime(CLOCK_MONOTONIC)` for nanosecond accuracy. All measurements include end-to-end overhead (IPC,
> wait time). The benchmark suite is available in [`assets/benchmarks/`](assets/benchmarks/).

</details>

<details>
<summary><b>Selection Detection Architecture</b></summary>

**Selection State Detection**

The shell-side detection path (`_zes_sync_selection_state()`) operates as follows:

1. `zstat` reads the sequence cache file's mtime
2. If the mtime matches the cached value, the function returns immediately with no further work
3. If the mtime has changed, the primary cache file content is read and stored in a shell variable
4. The new mtime is recorded for use in the next check

Under normal typing conditions with no selection changes, the path costs one `stat()` syscall and an integer
comparison per keypress.

**Cache File Protocol**

- The agent writes primary content to a dedicated cache file, then increments the sequence number file
- The shell reads only the sequence number's mtime as the change signal
- Full content is read only when a change is confirmed

**Cut Operation**

The cut operation (`edit-select::cut-region()`) copies the selected text to the clipboard before removing it
from the buffer. This ordering ensures the data is available in the clipboard at the point the user perceives
the operation as complete.

**Early Return Conditions**

- Unchanged mtime → immediate return before any selection comparison
- Active keyboard selection → mouse detection path skipped entirely
- Stale selection state → invalidated on mtime change, not on a timer

</details>

### Performance Summary

- **X11 average clipboard latency:** 2.320ms (2.211ms minimum)
- **Wayland average clipboard latency:** 2.134ms (1.546ms minimum under rapid consecutive operations)
- **Selection detection cost:** one `stat()` syscall per keypress when no selection change is present; full
  content read only when the cache file mtime has changed
- **Agent health check interval:** 30 seconds; not issued per operation
- **Initialization cost:** single-pass at plugin load; per-operation overhead is limited to cached variable
  reads and a single `stat()` call
- **Cache storage:** `XDG_RUNTIME_DIR` (tmpfs) with `/dev/shm` fallback

> **Benchmark Methodology:** Measurements use `clock_gettime(CLOCK_MONOTONIC)` for nanosecond-resolution
> timing. The full benchmark suite is available in [`assets/benchmarks/`](assets/benchmarks/).

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
| `-fomit-frame-pointer`                | Free up a register for better performance            |
| `-fno-plt`                            | Eliminate PLT indirection for faster library calls   |
| `-fno-semantic-interposition`         | Enable inlining across translation units             |
| `-fno-strict-aliasing`                | Avoid aliasing-related missed optimizations          |
| `-fno-asynchronous-unwind-tables`     | Omit unwind info not needed for signal handlers      |
| `-fmerge-all-constants`               | Deduplicate identical constants across units         |
| `-fipa-pta`                           | Interprocedural pointer analysis for better inlining |
| `-DNDEBUG`                            | Disable assertions in release builds                 |
| `-funroll-loops`                      | Unroll small loops for throughput                    |
| `-s`                                  | Strip symbols for smaller production binaries        |

> **Important:** `-march=native` produces binaries optimized for the CPU you're building on. These binaries
> may not run correctly on different CPU architectures. For distributed builds, replace
> `-march=native -mtune=native` with a portable baseline like `-march=x86-64-v2`.

</details>

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
    only supported deleting selected text and did not offer copying by default. Since then, the project has evolved with its own new features, enhancements, bug fixes, design improvements, and a fully changed codebase, and it now provides a full editor-like experience.

- #### Wayland Primary Selection Protocol
  The [`primary-selection-unstable-v1.xml`](impl-wayland/backends/wayland/primary-selection-unstable-v1.xml)
  Wayland protocol specification is Copyright © 2015, 2016 Red Hat, distributed under the MIT License. The
  bundled C binding files (`primary-selection-unstable-v1-protocol.c` and
  `primary-selection-unstable-v1-client-protocol.h`) are generated directly from this XML definition via
  `wayland-scanner` and are covered by the same copyright and license terms. The `xdg-shell` binding files
  follow the same pattern, generated from the `xdg-shell.xml` specification in the wayland-protocols
  repository.

---

## References

- [Michael-Matta1/dev-dotfiles](https://github.com/Michael-Matta1/dev-dotfiles) — Dotfiles showcasing the
  plugin with Kitty, VS Code, and Zsh.

- [Zsh ZLE shift selection — StackOverflow](https://stackoverflow.com/questions/5407916/zsh-zle-shift-selection)
  — Q&A on Shift-based selection in ZLE.

- [Zsh Line Editor Documentation](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html) — Official ZLE
  widgets and keybindings reference.
