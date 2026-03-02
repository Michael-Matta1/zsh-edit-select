# Zsh Edit-Select

Zsh plugin that lets you edit your command line like a text editor. Select text with Shift + Arrow keys or the mouse, type or paste to replace selections, use familiar shortcuts like Ctrl+C, Ctrl+X, and Ctrl+V, and customize keybindings through an interactive wizard — with full X11 and Wayland clipboard support.

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
- All instructions are organized incollapsed sections so you can expand only what applies to your specific
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
| **Safeguards**     | - Checks for conflicting keybindings in your `.zshrc`<br>- Verifies the installation with a self-test suite                                                                                                                                                                                                                                                                                                                                                             |

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

The plugin includes a native X11 clipboard agent with full clipboard support. External clipboard tools are
optional:

```bash
sudo apt install build-essential libx11-dev libxfixes-dev pkg-config xclip
```

> **Note:** `zes-x11-selection-agent` provides **44.6% faster** clipboard operations compared to `xclip` and
> does not require external tools for core functionality.

</details>

<details>
<summary><b>Arch Linux</b></summary>

The plugin includes a native X11 clipboard agent with full clipboard support. External clipboard tools are
optional:

```bash
sudo pacman -S --needed base-devel libx11 libxfixes pkgconf xclip
```

> **Note:** `zes-x11-selection-agent` provides **44.6% faster** clipboard operations compared to `xclip` and
> does not require external tools for core functionality.

</details>

<details>
<summary><b>Fedora</b></summary>

The plugin includes a native X11 clipboard agent with full clipboard support. External clipboard tools are
optional:

```bash
sudo dnf install gcc make libX11-devel libXfixes-devel pkgconfig xclip
```

> **Note:** `zes-x11-selection-agent` provides **44.6% faster** clipboard operations compared to `xclip` and
> does not require external tools for core functionality.

</details>

### For Wayland Users

<details>
<summary><b>Debian/Ubuntu</b></summary>

The plugin includes a native Wayland clipboard agent with full PRIMARY selection support. External clipboard
tools are optional:

```bash
sudo apt install build-essential libwayland-dev wayland-protocols pkg-config wl-clipboard
```

> **Note:** `zes-wl-selection-agent` uses native Wayland protocols directly and does not require these tools
> for core functionality.

</details>

<details>
<summary><b>Arch Linux</b></summary>

The plugin includes a native Wayland clipboard agent with full PRIMARY selection support. External clipboard
tools are optional:

```bash
sudo pacman -S --needed base-devel wayland wayland-protocols pkgconf wl-clipboard
```

> **Note:** `zes-wl-selection-agent` uses native Wayland protocols directly and does not require these tools
> for core functionality.

</details>

<details>
<summary><b>Fedora</b></summary>

The plugin includes a native Wayland clipboard agent with full PRIMARY selection support. External clipboard
tools are optional:

```bash
sudo dnf install gcc make wayland-devel wayland-protocols-devel pkgconfig wl-clipboard
```

> **Note:** `zes-wl-selection-agent` uses native Wayland protocols directly and does not require these tools
> for core functionality.

</details>

### For XWayland Users

If you're running Wayland but need X11 compatibility (XWayland) and enhance the behaviour, install both X11
and Wayland dependencies.

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

**Disabled:**

- Mouse selections can be copied with Ctrl+C
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

Add to `keybindings.json` (usually at `~/.config/Code/User/`):

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

This plugin is engineered for maximum performance and responsiveness. The architecture eliminates subprocess
overhead at every level: a compiled native C agent tracks selections in the background, caches results to
RAM-backed files, and delivers data to the shell via a single `stat()` syscall — never by spawning an external
tool per keystroke.

Key design principles:

- **One-time cost, zero per-operation cost** — backend detection, agent startup, and config loading happen
  once at shell load; subsequent operations pay zero initialization overhead
- **Event-driven detection** — X11 XFixes events and Wayland compositor events trigger immediate cache
  updates; no busy-waiting
- **Compiled C agents** — direct system calls with aggressive compiler optimization
  (`-O3 -march=native -flto -fipa-pta`) eliminate interpreter overhead entirely
- **RAM-backed cache** — agents write to `XDG_RUNTIME_DIR` (tmpfs) with `/dev/shm` fallback; I/O stays in
  memory, never touches spinning disk

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

**Single Agent Initialization**

- Selection agent started once when plugin loads
- Remains active for entire shell session
- Eliminates agent startup overhead on subsequent operations

</details>

<details>
<summary><b>Runtime Execution Optimizations</b></summary>

**File-Based Caching with mtime Detection**

- Background agent writes selection data to cache files
- Shell detects changes via file modification times (mtime)
- Only one `stat()` syscall needed, no file content reads
- mtime comparisons are instant memory comparisons
- Eliminates expensive clipboard access on every check

**Direct State Caching**

- Selection state stored in memory variables
- Avoids repeated clipboard queries for unchanged selections
- Early return checks prevent re-detection of active selections
- State invalidation only when actual changes detected

**Periodic Agent Health Check (30-second interval)**

- Shell checks agent PID via `kill(pid, 0)` once every 30 seconds — not on every keystroke
- If the agent has exited unexpectedly it is transparently restarted
- Throttling keeps the liveness-check overhead negligible

**Early Return Checks**

- `_zes_sync_selection_state()` returns immediately if mtime is unchanged
- Keyboard selections skip the mouse detection path entirely
- State is invalidated only on confirmed changes

**Event-Driven Detection**

- **X11**: XFixes `SelectionNotify` events deliver instant PRIMARY selection change notification — no spin
  loop
- **Wayland**: Compositor sends primary selection events on owner change; a 50 ms poll fallback catches
  content changes within the same owner (e.g. user extends a selection without releasing the mouse)
- Neither agent busy-waits; both sleep in `poll()` until activity arrives

</details>

<details>
<summary><b>Custom C Agent Architecture</b></summary>

**Compiled Native Code Performance**

- Custom C agents compiled with aggressive optimization flags (`-O3`, `-march=native`, `-flto`)
- Direct system calls without Zsh interpreter overhead
- No subprocess spawning on clipboard operations
- Minimal dependencies (only system libraries)

**Event-Driven Architecture**

- Wayland agent: Connects to Wayland display server directly
  - Uses `zwp_primary_selection_unstable_v1` protocol for PRIMARY selection events
  - Uses `wl_data_device` protocol for clipboard events
  - Blocks on `poll()` for server events — zero CPU usage between events
- X11 agent: Uses XFixes extension for selection change notifications
  - Instant event notification on PRIMARY selection changes
  - `poll()`-based main loop; no spinning or busy-waiting

**Efficient Cache Updates**

- Agent writes only when selection content actually changes (conditional write skip)
- Skipping redundant writes saves ~80 write syscalls/sec under rapid selection activity
- File writes ordered: primary content first, then sequence number
- Shell detects only the mtime update of the sequence file, not full content reads
- Prevents redundant updates and wasted disk I/O

**Non-Blocking I/O**

- Clipboard reads use non-blocking I/O with `poll()` timeout
- `poll()` replaces `usleep()` — wakes immediately on fd activity, avoids over-sleeping
- Prevents hanging on unavailable clipboard data

**Operation Mode Efficiency**

- Single agent binary supports multiple operation modes:
  - Long-running mode: Continuous selection tracking with periodic cache updates
  - Oneshot mode: Single selection read without persistence
  - Clipboard operations: Direct clipboard read/write
- Eliminates need for separate per-mode processes

**C-Level Runtime Optimizations**

Specific low-level improvements applied across all three agents:

- **Persistent file descriptors** — Cache file FDs opened once and kept alive; eliminates `open()`/`close()`
  overhead on every selection write
- **`pwrite()` instead of `write()`** — Atomic positional write without a preceding `lseek()`; one syscall
  instead of two
- **`ftruncate()` after every write** — File is truncated to the exact written length after each `pwrite()`;
  without this, shrinking selections leave stale bytes from the previous (longer) content in the cache file
- **`O_CLOEXEC` everywhere** — All `open()`, `pipe2(O_CLOEXEC)`, and `memfd_create(MFD_CLOEXEC)` calls set
  `O_CLOEXEC` to prevent fd inheritance across `exec()`
- **Conditional write skip** — `write_primary()` compares new and existing content; skips the write entirely
  when unchanged
- **`XInternAtom` result caching** _(X11 agent)_ — X11 atom lookups performed once at startup and reused
  per-event, not re-queried on every selection notification
- **`poll()` replacing `usleep()`** — More accurate waits with immediate wake-up on fd activity; no wasted
  cycles on over-sleeping
- **`/dev/shm` cache fallback** — Falls back to `/dev/shm` when `XDG_RUNTIME_DIR` is unavailable, keeping
  cache in RAM
- **Eliminated redundant `fcntl(F_GETFL)`** _(Wayland agent)_ — Clipboard read pipes are created fresh with
  `pipe2(O_CLOEXEC)`; `F_SETFL O_NONBLOCK` is applied directly without a preceding `F_GETFL` read. Saves 1
  syscall per clipboard read operation

**Event Loop Design**

- **X11 daemon** — XFixes `SelectionNotify` events + `poll()` with 1-second timeout. The timeout exists solely
  for clean `SIGTERM` shutdown; no periodic work is done on timeout
- **Wayland daemon** — Wayland event loop + `poll()` with 50 ms timeout; on timeout calls
  `check_and_update_primary()` to catch content changes within the same selection owner
- **Clipboard copy (X11)** — `poll()` 100 ms loop serving `SelectionRequest` events; `timeout_count` resets to
  zero every time a paste is served — exits after 500 idle cycles (~50 seconds without any paste activity)
- **Clipboard copy (Wayland)** — Event loop exits immediately after the first successful paste
  (`copy_done = true`)

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

- `zes-x11-selection-agent` handles all copy/paste natively; `xclip` only used as fallback
- XFixes extension for instant selection notifications
- `poll()`-based main loop; no spinning or busy-waiting
- Direct X11 server connection with persistent atom caching

**Wayland-Specific**

- Native Wayland event loop for efficient monitoring
- Dual protocol support:
  - PRIMARY selection via `zwp_primary_selection_unstable_v1`
  - Clipboard via `wl_data_device` standard protocol
- XWayland compatibility layer for hybrid environments
- Permanent 1×1 transparent `xdg_toplevel` surface created at startup with an empty input region; required for
  Mutter/GNOME to deliver PRIMARY selection events, harmless on wlroots/KDE

**XWayland Bridge**

- Seamless Wayland + XWayland application handling
- Transparent fallback to X11 protocols when needed
- No performance penalty for mixed application environments

</details>

<details>
<summary><b>What Was Eliminated</b></summary>

- ✅ No subprocess creation on clipboard operations — no fork/exec overhead per action
- ✅ No shell overhead from executing external commands (`xclip`, `wl-copy`, etc.)
- ✅ No busy-waiting — event-driven detection throughout; Wayland's 50 ms fallback poll exists only to catch
  in-selection content changes, not as the primary detection method
- ✅ No repeated system calls — backend detection and configuration loaded once at startup
- ✅ File mtime compared in memory; no full file reads per selection check
- ✅ PID checks throttled to 30-second intervals, not per-operation
- ✅ No redundant selection re-detection — early return checks skip unchanged state
- ✅ No scripting language overhead in C agents — direct system calls only
- ✅ Zsh scripts compiled to `.zwc` bytecode; raw script parsing eliminated after first load
- ✅ Handles multiple panes and windows without cross-pane state leakage

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
- ✅ Lazy agent initialization (only started when needed)
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
<summary><b>Clipboard Operation Performance Benchmarks</b></summary>

Our custom clipboard implementations deliver **exceptional performance improvements** over standard tools,
verified through comprehensive benchmarking with real-world measurements.

**X11 Performance (Custom Agent vs xclip):**

| Test Scenario                          | xclip Avg    | Custom Avg   | Improvement      |
| -------------------------------------- | ------------ | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 4.025 ms     | 2.258 ms     | **43.9% faster** |
| Medium text (500 chars, 50 iterations) | 4.307 ms     | 2.211 ms     | **48.7% faster** |
| Large text (5KB, 25 iterations)        | 3.949 ms     | 2.310 ms     | **41.5% faster** |
| Very large (50KB, 10 iterations)       | 4.451 ms     | 2.499 ms     | **43.9% faster** |
| Rapid consecutive (200 iterations)     | 4.206 ms     | 2.321 ms     | **44.8% faster** |
| **Overall Average**                    | **4.187 ms** | **2.320 ms** | **44.6% faster** |

**Wayland Performance (Custom Agent vs wl-copy):**

| Test Scenario                          | wl-copy Avg   | Custom Avg   | Improvement      |
| -------------------------------------- | ------------- | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 57.073 ms     | 1.966 ms     | **96.6% faster** |
| Medium text (500 chars, 50 iterations) | 60.382 ms     | 2.441 ms     | **96.0% faster** |
| Large text (5KB, 25 iterations)        | 63.020 ms     | 1.809 ms     | **97.1% faster** |
| Very large (50KB, 10 iterations)       | 58.343 ms     | 2.907 ms     | **95.0% faster** |
| Rapid consecutive (200 iterations)     | 58.860 ms     | 1.546 ms     | **97.4% faster** |
| **Overall Average**                    | **59.535 ms** | **2.134 ms** | **96.4% faster** |

**Performance Summary:**

- **X11 Improvement:** Custom agent **44.6% faster** than xclip (2.320ms vs 4.187ms)
- **Wayland Improvement:** Custom agent **96.4% faster** than wl-copy (2.134ms vs 59.535ms)
- **Best-case Latency:**
  - X11: 2.211ms minimum (48.7% better than xclip's 4.307ms)
  - Wayland: 1.152ms minimum (97.7% better than wl-copy's 49.066ms)
- **Consistency:** Performance maintained across all payload sizes (50 bytes to 50KB)
- **Memory:** Equal or better footprint than external tools

**Real-World Impact:**

- **X11 Operations:** Sub-2.5ms average latency means instant clipboard operations
- **Wayland Operations:** Sub-2.2ms average latency (27x faster than wl-copy)
- **Paste Operations:** Immediate data retrieval from agent cache
- **Selection Detection:** Near-zero latency for mouse selection changes
- **High-Frequency Usage:** No performance degradation during rapid copy/paste workflows

**Why Wayland Shows Exceptional Gains:**

- wl-copy's high process spawn overhead (~60ms per operation) makes subprocess-based approaches extremely slow
- Our persistent agent architecture eliminates all subprocess calls
- Direct Wayland protocol access provides native performance
- Result: **96.4% improvement** (27x performance multiplier) on Wayland vs **44.6% improvement** on X11

**Technical Implementation:**

- Custom agents implement full clipboard protocol support
- Background server maintains clipboard ownership (auto-cleanup after 50 seconds)
- Graceful fallback to standard tools if custom agents unavailable
- X11 achieves 44.6% performance gains, Wayland achieves 96.4% performance gains

> **Benchmark Methodology:** Tests conducted using high-precision C benchmarking tools with
> `clock_gettime(CLOCK_MONOTONIC)` for nanosecond accuracy. All measurements include real-world overhead
> (process spawning, IPC, wait time). Results represent actual wall-clock time improvements users experience
> during interactive use.

> **Run Benchmarks Yourself:** You can verify these performance claims by running the benchmark suite
> yourself. See the [`assets/benchmarks/`](assets/benchmarks/) directory for comprehensive C-based
> benchmarking tools and detailed instructions. The suite compares our custom implementations against standard
> tools (`xclip`, `wl-copy`/`wl-paste`) with precise timing and multiple test scenarios.

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

**After (Custom C Agent):**

```
One-time agent startup:
  1. Agent tracks selection changes → 0ms per check
  2. Writes updates to cache file
  3. Shell reads cached data via file I/O → <0.1ms

Total: Zero subprocess calls during normal operation
```

**Performance Impact:**

- **Traditional:** ~4.3ms per clipboard query (subprocess overhead)
- **Custom Agent:** ~0.1ms per check (file mtime comparison)
- **Improvement:** ~97% reduction in selection detection latency

**Additional Optimizations:**

- ✅ `_zes_sync_selection_state()` — Reads agent cache before selection detection
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

### Performance Benefits Summary

- ✅ **X11: 44.6% faster** — Custom agent (2.320ms) vs xclip (4.187ms)
- ✅ **Wayland: 96.4% faster** — Custom agent (2.134ms) vs wl-copy (59.535ms)
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

### Navigation Keys

| Key Combination | Action                     |
| --------------- | -------------------------- |
| **Ctrl + ←**    | Move cursor one word left  |
| **Ctrl + →**    | Move cursor one word right |

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
public release. After every change — whether a fix, enhancement, or new feature — the plugin is heavy-tested
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

- #### This project Began as a fork ([Michael-Matta1/zsh-shift-select](https://github.com/Michael-Matta1/zsh-shift-select)) of [jirutka/zsh-shift-select](https://github.com/jirutka/zsh-shift-select)
  - The fork was started to add the ability to copy selected text, because the jirutka/zsh-shift-select plugin
    only supported deleting selected text and did not offer copying by default and this feature was frequently
    requested by the community.

  - Since then, the project has evolved with its own new features, enhancements, bug fixes, design
    improvements, and a fully changed codebase, and it now provides a full editor-like experience.

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
