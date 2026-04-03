# Zsh Edit-Select

Zsh plugin that lets you edit your command line like a text editor. Select text with Shift + Arrow keys or the
mouse, type or paste to replace selections, use standard editing shortcuts (copy, cut, paste, undo, redo,
select all), and customize keybindings through an interactive wizard — with full Linux, macOS and WSL
support.


[demo video](https://github.com/user-attachments/assets/a024e609-1de1-4608-a7c3-e17264162904)


---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Auto Installation](#auto-installation)
- [Manual Installation](#manual-installation)
- [Configuration Wizard](#configuration-wizard)
>
>---
>
- [Famous Terminals Configurations](#famous-terminals-configurations)
- [WSL Support](#wsl-support)
- [SSH Support (Headless Linux Box)](#ssh-support-headless-linux-box)
>
>---
>
- [Default Key Bindings Reference](#default-key-bindings-reference)
- [Troubleshooting](#troubleshooting)
- [Manual Agents Build (optional)](#manual-agents-build-optional)



---

## Overview

**Zsh Edit-Select** brings familiar text editor behaviors to your Zsh command line:

- ✅ **Shift selection** — Select text using Shift + Arrow keys
- ✅ **Type-to-replace** — Type over selected text to replace it
- ✅ **Paste-to-replace** — Paste clipboard content over selections
- ✅ **Mouse integration** — Works with text selected by mouse
- ✅ **Clipboard integration** — Works natively with X11, Wayland, WSL, and macOS
- ✅ **Standard shortcuts** — Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V, Ctrl+Z
  Ctrl+Shift+Z
  (on **macOS**, the Ctrl key is replaced with the **Command (Cmd)** key)

> **Customization:** The plugin works after installation with editor-like defaults. Use the command
> `edit-select config` to customize mouse behavior and keybindings.

---

## Features

### Keyboard Selection

Select text using familiar keyboard shortcuts:

| Shortcut | Action |
| -------- | ------ |
| **Shift + ←/→** | Select character by character |
| **Shift + ↑/↓** | Select line by line |
| **Shift + Home/End** | Select to line start/end |
| **Shift + Ctrl + ←/→** | Select word by word |
| **Shift + Ctrl + Home/End** | Select to buffer start/end |
| **Ctrl + A** | Select all text (including multi-line commands) |

> **macOS:** Replace `Ctrl` with `Cmd` for whole-line/all-text shortcuts, and with `Option` for word-by-word selection.

For the full keybindings check the [Default Key Bindings Reference](#default-key-bindings-reference).


### Mouse Selection Integration

The plugin intelligently integrates mouse selections:

**When Mouse Replacement is Enabled (default):**

- ✅ Copy mouse selections with Ctrl+C (or Ctrl+Shift+C if configured, Cmd+C on macOS)
- ✅ Cut mouse selections with Ctrl+X (Cmd+X on macOS)
- ✅ Type to replace mouse selections
- ✅ Delete mouse selections with Backspace/Delete
- ✅ Paste over mouse selections with Ctrl+V (Cmd+V on macOS)

**When Mouse Replacement is Disabled:**

- ✅ Copy mouse selections with Ctrl+C (or Ctrl+Shift+C if configured, Cmd+C on macOS)
- ✅ Replacement/Deletion work with keyboard selections

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 1

### Type-to-Replace and Paste-to-Replace

Type or paste while text is selected to replace it automatically.

Works with both keyboard and mouse selections (when mouse replacement is enabled).


### Copy, Cut, and Paste

Standard editing shortcuts:

- **Ctrl + C** (or Ctrl+Shift+C if configured) (Cmd+C on macOS): Copy selected text
- **Ctrl + X** (Cmd+X on macOS): Cut selected text
- **Ctrl + V** (Cmd+V on macOS): Paste (replaces selection if any)

> **Clipboard Managers Compatibility Note:** The plugin is fully compatible with clipboard history managers
> like **CopyQ**, **GPaste**, **Maccy**, and others. If you use a clipboard manager (like CopyQ, GPaste, Maccy, etc.), the plugin will integrate with it automatically since it uses standard clipboard protocols on X11, Wayland, and macOS.

### Undo and Redo

Navigate through your command line editing history:

- **Ctrl + Z** (Cmd+Z on macOS): Undo last edit
- **Ctrl + Shift + Z** (Cmd+Shift+Z on macOS): Redo last undone edit

> **Note:** The Ctrl+Z keybinding works seamlessly alongside the traditional suspend process functionality
> (Ctrl+Z suspends a running foreground process to background). The plugin intelligently handles undo
> operations for command line editing while preserving the ability to suspend processes when needed.


### Clipboard Integration

The plugin includes purpose-built clipboard agents that replace external tools entirely:

**Clipboard Integration Agents:** Small compiled programs built specifically for this plugin to handle all
clipboard and selection operations:

The agents handle copy, paste, and clipboard operations directly through native protocols.
No external tools are needed. The plugin is designed to be fully self-contained. The agents communicate with the plugin through a fast in-memory cache,
giving you instant clipboard response.

> See [Performance-Optimized Architecture](#performance-optimized-architecture) for benchmarks and implementation details.

---

## Auto Installation

> **Recommendation:** If you are comfortable editing dotfiles and prefer full control over your system
> configuration, [Manual Installation](#manual-installation) is the recommended approach.

> macOS auto installation will be available soon.

Installation consists of two straightforward steps:

1. install the plugin to your plugin manager
2. configure your terminal

Each documented with exact commands and copy-paste configurations.

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
| **Dependencies**   | - Installs system packages (`git`, `zsh`, `xclip`/`wl-clipboard`), and interactively asks to optionally install build tools (`gcc`, `make`, `clang`) for compiling the agents locally<br>- Detects your system (macOS, Debian, Fedora, Arch, etc.) and uses the correct package manager (`brew`, `port`, `apt`, `dnf`, `pacman`)                                                                                                                                                                                                                                                                        |
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
> [Famous Terminals Configurations](#famous-terminals-configurations) guides below.

---

## Manual Installation

The process consists of two steps:

1. **Install the plugin** — Clone the repository with your plugin manager and add one line to your `.zshrc`.
2. **Configure your terminal** — Add a few keybinding entries to your terminal's config file.

> **Pre-built Agents:** The plugin includes portable binaries generated via GitHub workflows. These binaries are automatically downloaded on the first load, which may take a few seconds in the first load only. You may also need to restart your terminal after the initial setup.
>
> For a manual build and an optimized experience tailored to your specific hardware (e.g., using `-march=native -mtune=native`), refer to [Manual Agents Build (optional)](#manual-agents-build-optional).
>
In some cases, delays may occur due to temporary issues with GitHub infrastructure. If the first load takes longer than expected, please wait a few minutes and try again once the GitHub services are fully operational.

> If you run into any difficulty at any step, please
> [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) and it will be addressed.




### 1. Install the Plugin

Expand your plugin manager:

<details>
<summary><b>Oh My Zsh</b></summary>

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

### 2. Configure Your Terminal

Some terminals need configuration to support selection and others need only configuration to support editing. See [Famous Terminals Configurations](#famous-terminals-configurations) for
details.

**WSL users:** For WSL, go directly to [WSL Support](#wsl-support)


### 2.5 Enable Mouse Integration (macOS only)

If you are using macOS you will need an extra step to enable mouse integration.

<details>
<summary><b>Click to expand</b></summary>

To enable the mouse integration run the following command:

```bash
edit-select setup-ax
```

then grant Accessibility permission for your terminal application in **System Settings → Privacy & Security → Accessibility**.

> Enable the toggle for the terminal application you are running (e.g., **iTerm2**).

Then restart your terminal. You may need to restart your device for the full integration to take effect.


**Terminal Compatibility for Mouse Selection**

- Terminals with Accessibility (AX) support provide the most reliable mouse integration. In this category, iTerm2 is the recommended option.

- Among GPU-accelerated terminals, Kitty offers the most reliable and consistent behavior for mouse integration.

- Other GPU-based terminals use custom rendering pipelines, where mouse integration currently relies on a reactive `Cmd+C` mechanism. As a result, behavior may vary depending on the terminal version and runtime conditions, and support should be considered experimental.

If you face any issue with mouse integration, disable it from the configuration wizard

#### tmux on macOS

If clipboard operations fail inside tmux, install `reattach-to-user-namespace`:
  ```bash
  brew install reattach-to-user-namespace
  ```

</details>


### 3. Restart Your Shell

```bash
source ~/.zshrc
```

> **Important:** You may need to fully close and reopen your terminal (not just source ~/.zshrc) for all
> features to work correctly, especially in some terminal emulators.




### 4. (Optional) Customize Settings

The plugin works immediately with sensible defaults, but you can customize:

- Mouse replacement behavior
- Keybindings (Ctrl/Cmd+A, Ctrl/Cmd+V, Ctrl/Cmd+X, Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z)

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

All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions. You can also view or edit this file manually at any time.

<details>
<summary><b>Mouse Replacement Safeguard</b></summary>

The plugin includes a smart safety feature to prevent accidental edits when using the mouse. If you select text with your mouse and the plugin detects multiple identical occurrences of that text in your command buffer, it will pause and show the message:

**"Duplicate text: place cursor inside the occurrence you want to modify"**

**Why is this a feature?**
When text is selected via mouse, terminal emulators don't report the exact screen coordinates to the shell. If the same word appears twice, this protective safeguard ensures you don't accidentally replace the wrong occurrence.

When prompted, simply place your cursor inside the specific occurrence you want to edit, then select and replace it.

- **Keyboard selection bypass:** This safeguard is only needed for mouse selections. Using `Shift+Arrow keys` provides exact cursor positions, avoiding this ambiguity entirely.
- **Under development:** A custom mouse-tracking path is already implemented in the WSL version to resolve the exact selected range without prompting. This will be integrated across all platforms as it matures.
- **Reporting & Options:** If you encounter any unexpected behavior with mouse replacement, please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues). You can also disable mouse replacement entirely in the Configuration Wizard below if you prefer strict keyboard-only editing.

</details>

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

- **Ctrl + A** (Cmd+A on macOS) — Select all
- **Ctrl + V** (Cmd+V on macOS) — Paste
- **Ctrl + X** (Cmd+X on macOS) — Cut
- **Ctrl + Shift + C** (Cmd+C on macOS) — Copy
- **Ctrl + Z** (Cmd+Z on macOS) — Undo
- **Ctrl + Shift + Z** (Cmd+Shift+Z on macOS) — Redo
- **Ctrl + ←** (Option+Left on macOS) — Word left
- **Ctrl + →** (Option+Right on macOS) — Word right

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

## Famous Terminals Configurations

> [Open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) if you need help with a terminal
> that is not covered.

> For WSL users on Windows Terminal, follow the dedicated manual at [WSL Support](#wsl-support)
> then return here only if you need additional terminal mappings.




This section provides complete, ready-to-paste configurations for each supported terminal. Find your terminal below, then expand the section for your operating system to get the full config block you can integrate with yours.

**CRITICAL:** While adding these mappings, remove or comment out any existing conflicting bindings


**Note:** Comments inside each configuration block provide inline guidance. Some options are included but commented out — uncomment them to switch to an alternative behaviour. For example, by default the copy shortcut is `Ctrl+Shift+C` in linux (the traditional terminal convention, where `Ctrl+C` sends an interrupt signal); if you prefer GUI-style behaviour where `Ctrl+C` copies and `Ctrl+Shift+C` sends the interrupt, simply follow the instructions in the comments to swap to that option instead.

**Note (macOS):** Almost all macOS terminal emulators intercept `Cmd` keys by default, so explicit mappings are required. If you cannot or do not want to modify your terminal's bindings, run `edit-select config` and choose Ctrl fallback presets for **Cut** (`Ctrl+X`), **Paste** (`Ctrl+V`), **Undo** (`Ctrl+Z`), and **Select All** (`Ctrl+A`) — these work without any terminal configuration.


<details>
<summary><b>How to Find Escape Sequences (Optional: For Manual Customization)</b></summary>

**To find the escape sequence for any key combination:**

1. Run `cat` (without arguments) in your terminal
2. Press the key combination
3. The terminal will display the escape sequence
4. Use this sequence in your configuration

</details>

---

#### Kitty

<details>
<summary><b>Linux configuration</b></summary>

Add the following to `kitty.conf`:

```conf
# ── zsh-edit-select copying shortcut ───────────────────────
# IMPORTANT: Remove or comment out any existing ctrl+shift+c mapping, e.g.:
#   map ctrl+shift+c copy_to_clipboard

# Option A (Default): Ctrl+Shift+C = copy
map ctrl+shift+c send_text all \x1b[67;6u

# Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
# Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
# To use this option: comment out the Option A line above, then uncomment both lines below.
# map ctrl+c send_text all \x1b[67;6u
# map ctrl+shift+c send_text all \x03

# ── zsh-edit-select undo / redo ─────────────────────────
map ctrl+shift+z send_text all \x1b[90;6u

# ── zsh-edit-select selection shortcuts ─────────────────────
# Pass Shift and Ctrl+Shift keys through to Zsh for selection.
# These override any default or custom Kitty mappings on these keys.
map shift+left        no_op
map shift+right       no_op
map shift+up          no_op
map shift+down        no_op
map shift+home        no_op
map shift+end         no_op
# Ctrl+Shift+Left/Right default to previous_tab/next_tab in Kitty — disable them:
map ctrl+shift+left   no_op
map ctrl+shift+right  no_op
# Ctrl+Shift+Home/End default to scroll_home/scroll_end in Kitty — disable them:
map ctrl+shift+home   no_op
map ctrl+shift+end    no_op
```

</details>

<details>
<summary><b>macOS configuration</b></summary>

Add all of the following to `kitty.conf`:

```conf
# ── zsh-edit-select Cmd editing shortcuts ───
# Override Kitty's built-in clipboard actions so the plugin receives them.
map cmd+a send_text all \x1b[97;9u
map cmd+c send_text all \x1b[99;9u
map cmd+v send_text all \x1b[118;9u
map cmd+x send_text all \x1b[120;9u
map cmd+shift+z send_text all \x1b[122;10u
```

</details>

---

#### WezTerm

<details>
<summary><b>Linux configuration</b></summary>

Add the following to `wezterm.lua`:

```lua
return {
  keys = {

    -- ── zsh-edit-select copying shortcut ───────────────
    -- Option A (Default): Ctrl+Shift+C = copy
    {
      key = 'C',
      mods = 'CTRL|SHIFT',
      action = wezterm.action_callback(function(window, pane)
        local sel = window:get_selection_text_for_pane(pane)
        if sel ~= "" then
          window:perform_action(wezterm.action.CopyTo "Clipboard", pane)
        else
          window:perform_action(wezterm.action.SendString '\x1b[67;6u', pane)
        end
      end),
    },
    -- Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
    -- Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
    -- To use this option: remove the Option A entry above and uncomment both entries below.
    -- {
    --   key = 'c',
    --   mods = 'CTRL',
    --   action = wezterm.action_callback(function(window, pane)
    --     local sel = window:get_selection_text_for_pane(pane)
    --     if sel ~= "" then
    --       window:perform_action(wezterm.action.CopyTo "Clipboard", pane)
    --     else
    --       window:perform_action(wezterm.action.SendString '\x1b[67;6u', pane)
    --     end
    --   end),
    -- },
    -- {
    --   key = 'C',
    --   mods = 'CTRL|SHIFT',
    --   action = wezterm.action.SendString '\x03',
    -- },

    -- ── zsh-edit-select undo / redo ─────────────────
    {
      key = 'Z',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.SendString '\x1b[90;6u',
    },

    -- ── zsh-edit-select selection shortcuts ─────────────
    -- Disable WezTerm's default Ctrl+Shift+Arrow/Home/End assignments so
    -- the keys pass through to Zsh for word and line selection.
    { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'RightArrow', mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'Home',       mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },
    { key = 'End',        mods = 'CTRL|SHIFT', action = wezterm.action.DisableDefaultAssignment },

  },

  mouse_bindings = {

    -- ── zsh-edit-select mouse selection ──────
    -- On left click, notify the shell if a selection is active
    {
      event = { Down = { streak = 1, button = "Left" } },
      mods = "NONE",
      action = wezterm.action_callback(function(window, pane)
        local sel = window:get_selection_text_for_pane(pane)
        if sel ~= "" then
          pane:send_text("\x1b[>62300u")
        end
        window:perform_action(wezterm.action.ClearSelection, pane)
        window:perform_action(wezterm.action.SelectTextAtMouseCursor("Cell"), pane)
      end),
    },

    -- Complete the selection into PrimarySelection on mouse-up
    {
      event = { Up = { streak = 1, button = "Left" } },
      mods = "NONE",
      action = wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor "PrimarySelection",
    },
    {
      event = { Up = { streak = 2, button = "Left" } },
      mods = "NONE",
      action = wezterm.action.CompleteSelection "PrimarySelection",
    },
    {
      event = { Up = { streak = 3, button = "Left" } },
      mods = "NONE",
      action = wezterm.action.CompleteSelection "PrimarySelection",
    },

  },
}
```

</details>

<details>
<summary><b>macOS configuration</b></summary>

Add all of the following to `wezterm.lua`. All entries go inside the `keys` table of your returned config:

```lua
local wezterm = require 'wezterm'
local act     = wezterm.action
local config  = wezterm.config_builder()

-- ── Prevent copy-on-select to system clipboard ──────────────────
config.mouse_bindings = {

  -- On left-click Down: send deselect signal to ZLE if something was selected.
  -- This prevents phantom replacement of the old selection on the next keypress.
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods  = "NONE",
    action = wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel ~= "" then
        pane:send_text("\x1b[>62300u")
      end
      window:perform_action(act.ClearSelection, pane)
      window:perform_action(act.SelectTextAtMouseCursor("Cell"), pane)
    end),
  },

  -- streak=1: open links on bare click, do NOT copy to clipboard on drag.
  {
    event  = { Up = { streak = 1, button = "Left" } },
    mods   = "NONE",
    action = wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel == "" then
        window:perform_action(act.OpenLinkAtMouseCursor, pane)
      end
      -- If selection exists: do nothing (don't copy). Agent handles capture.
    end),
  },

  -- streak=2: double-click word select. No clipboard copy.
  {
    event  = { Up = { streak = 2, button = "Left" } },
    mods   = "NONE",
    action = act.Nop,
  },

  -- streak=3: triple-click line select. No clipboard copy.
  {
    event  = { Up = { streak = 3, button = "Left" } },
    mods   = "NONE",
    action = act.Nop,
  },
}

-- ── zsh-edit-select Cmd editing shortcuts ───
config.keys = {
  { key = 'a', mods = 'CMD',       action = act.SendString '\x1b[97;9u'  },
  { key = 'v', mods = 'CMD',       action = act.SendString '\x1b[118;9u' },
  { key = 'x', mods = 'CMD',       action = act.SendString '\x1b[120;9u' },
  { key = 'z', mods = 'CMD',       action = act.SendString '\x1b[122;9u' },
  { key = 'z', mods = 'CMD|SHIFT', action = act.SendString '\x1b[122;10u'},

  -- Cmd+C: if there is an active WezTerm selection, copy it to clipboard.
  -- Otherwise send the plugin's escape sequence (Cmd+C CSI-u) to ZLE.
  {
    key  = 'c',
    mods = 'CMD',
    action = wezterm.action_callback(function(window, pane)
      local sel = window:get_selection_text_for_pane(pane)
      if sel ~= "" then
        window:perform_action(act.CopyTo "Clipboard", pane)
      else
        window:perform_action(act.SendString '\x1b[99;9u', pane)
      end
    end),
  },

  -- ── zsh-edit-select navigation (non-selecting) ───────────────────────────────────
  { key = 'LeftArrow',  mods = 'CMD',       action = act.SendString '\x1b[1;9D'  },
  { key = 'RightArrow', mods = 'CMD',       action = act.SendString '\x1b[1;9C'  },

  -- ── zsh-edit-select Shift selection keys ───
  { key = 'LeftArrow',  mods = 'CMD|SHIFT', action = act.SendString '\x1b[1;10D' },
  { key = 'RightArrow', mods = 'CMD|SHIFT', action = act.SendString '\x1b[1;10C' },
  { key = 'UpArrow',    mods = 'CMD|SHIFT', action = act.SendString '\x1b[1;10A' },
  { key = 'DownArrow',  mods = 'CMD|SHIFT', action = act.SendString '\x1b[1;10B' },
}

return config
```

</details>

---

#### Alacritty

<details>
<summary><b>Linux configuration</b></summary>

<details>
<summary><i>TOML format — <code>alacritty.toml</code> (current, Alacritty v0.13+)</i></summary>

Add the following to `alacritty.toml`:

```toml
# ── zsh-edit-select copying shortcut ───────────────────────
# Option A (Default): Ctrl+Shift+C = copy
[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
chars = "\u001b[67;6u"

# Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
# Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
# To use this option: remove the Option A entry above and uncomment both entries below.
# [[keyboard.bindings]]
# key = "C"
# mods = "Control"
# chars = "\u001b[67;6u"
#
# [[keyboard.bindings]]
# key = "C"
# mods = "Control|Shift"
# chars = "\u0003"

# ── zsh-edit-select undo / redo ─────────────────────────
[[keyboard.bindings]]
key = "Z"
mods = "Control|Shift"
chars = "\u001b[90;6u"

# ── zsh-edit-select selection shortcuts ─────────────────────
# Alacritty intercepts Shift+Home (ScrollToTop) and Shift+End (ScrollToBottom)
# by default. Override them so the keys pass through to Zsh for selection.
# All other Shift/Ctrl+Shift arrow keys pass through to Zsh natively.
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
<summary><i>Legacy YAML format — <code>alacritty.yml</code> (deprecated since Alacritty v0.13)</i></summary>

Add the following to `alacritty.yml`:

```yaml
key_bindings:
  # ── zsh-edit-select copying shortcut ─────────────────────
  # Option A (Default): Ctrl+Shift+C = copy
  - { key: C, mods: Control|Shift, chars: "\x1b[67;6u" }

  # Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
  # Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
  # To use this option: remove the Option A line above and uncomment both lines below.
  # - { key: C, mods: Control,       chars: "\x1b[67;6u" }
  # - { key: C, mods: Control|Shift, chars: "\x03" }

  # ── zsh-edit-select undo / redo ───────────────────────
  - { key: Z, mods: Control|Shift, chars: "\x1b[90;6u" }

  # ── zsh-edit-select selection shortcuts ───────────────────
  # Alacritty intercepts Shift+Home (ScrollToTop) and Shift+End (ScrollToBottom)
  # by default. Override them so the keys pass through to Zsh for selection.
  # All other Shift/Ctrl+Shift arrow keys pass through to Zsh natively.
  - { key: Home, mods: Shift, action: ReceiveChar }
  - { key: End,  mods: Shift, action: ReceiveChar }
```

</details>

</details>

<details>
<summary><b>macOS configuration</b></summary>

Add all of the following to `alacritty.toml`:

```toml
# ── zsh-edit-select Cmd editing shortcuts ───
# Override Alacritty's default macOS shortcuts so the plugin receives them.
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

# Needed for mouse integration
[selection]
save_to_clipboard = true
```

</details>

---

#### Ghostty

<details>
<summary><b>Linux configuration</b></summary>

Ghostty passes Shift+Arrow keys through to the terminal natively — **no additional configuration is needed for basic Shift selection.**

Add the following to your Ghostty config file (`~/.config/ghostty/config`):

```
# ── zsh-edit-select copying shortcut ───────────────────────
# Option A (Default): Ctrl+Shift+C = copy
keybind = ctrl+shift+c=csi:67;6u

# Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
# Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
# To use this option: remove the Option A line above and uncomment both lines below.
# keybind = ctrl+c=csi:67;6u
# keybind = ctrl+shift+c=text:\x03

# ── zsh-edit-select undo / redo ─────────────────────────
keybind = ctrl+shift+z=csi:90;6u

# ── zsh-edit-select selection shortcuts ─────────────────────
# Pass Ctrl+Shift+Left/Right through to Zsh for word selection
keybind = ctrl+shift+left=unbind
keybind = ctrl+shift+right=unbind
# Pass Ctrl+Shift+Home/End through to Zsh for line selection
keybind = ctrl+shift+home=unbind
keybind = ctrl+shift+end=unbind
```

</details>

<details>
<summary><b>macOS configuration</b></summary>

Add all of the following to `~/.config/ghostty/config`:

```
# ── zsh-edit-select bindings ──
# Overrides Ghostty's built-in clipboard actions (cmd+c, cmd+v, cmd+a) so the
# plugin receives them instead.
keybind = cmd+a=csi:97;9u
keybind = cmd+c=csi:99;9u
keybind = cmd+x=csi:120;9u
keybind = cmd+z=csi:122;9u
keybind = cmd+shift+z=csi:122;10u

# Shift+Up/Down
keybind = shift+up=csi:1;2A
keybind = shift+down=csi:1;2B

# Cmd+Shift+Up/Down: select to buffer start/end
keybind = cmd+shift+up=csi:1;10A
keybind = cmd+shift+down=csi:1;10B

# Needed for mouse integration
copy-on-select = clipboard
```

</details>

---

#### VS Code Terminal

<details>
<summary><b>Linux configuration</b></summary>

Add the following to `keybindings.json` (usually located at `~/.config/Code/User/keybindings.json`):

```json
[
  // ── zsh-edit-select copying shortcut ────────────────────
  // Option A (Default): Ctrl+Shift+C = copy
  {
    "key": "ctrl+shift+c",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[67;6u" },
    "when": "terminalFocus"
  },

  // Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
  // Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
  // To use this option: remove the Option A entry above and uncomment both entries below.
  // {
  //   "key": "ctrl+c",
  //   "command": "workbench.action.terminal.sendSequence",
  //   "args": { "text": "\u001b[67;6u" },
  //   "when": "terminalFocus"
  // },
  // {
  //   "key": "ctrl+shift+c",
  //   "command": "workbench.action.terminal.sendSequence",
  //   "args": { "text": "\u0003" },
  //   "when": "terminalFocus"
  // },

  // ── zsh-edit-select undo / redo ──────────────────────
  // Note: Ctrl+Z works alongside the traditional suspend-process functionality.
  // The plugin intelligently handles undo for command-line editing while
  // preserving the ability to suspend foreground processes when needed.
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
  },

  // ── zsh-edit-select selection shortcuts ──────────────────
  // VS Code intercepts Shift and Ctrl+Shift arrow keys by default.
  // These bindings forward the correct escape sequences to the terminal
  // so Zsh can handle selection.
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
<summary><b>macOS configuration</b></summary>

VS Code intercepts `Cmd+C`, `Cmd+V`, and `Cmd+A` for its own editor actions. The bindings below are scoped to `terminalFocus` so they only apply when the integrated terminal is active.

Open `keybindings.json` via `⇧⌘P` → **"Preferences: Open Keyboard Shortcuts (JSON)"**, then add the following entries. If you already have a `[...]` array in the file, merge these entries into it rather than creating a second array.

> **Note:** `sendSequence` requires `\u001b`-format Unicode escapes — `\x1b` is **not** valid in this context. VS Code uses `alt` for the Option key — `opt` is not a valid modifier here.

```json
[
  // ── zsh-edit-select editing shortcuts ────────────
  // Scoped to terminalFocus so VS Code's editor shortcuts are unaffected.
  {
    "key": "cmd+a",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[97;9u" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+c",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[99;9u" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+v",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[118;9u" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+x",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[120;9u" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+z",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[122;9u" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+shift+z",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[122;10u" },
    "when": "terminalFocus && isMac"
  },

  // ── zsh-edit-select navigation keys ─
  {
    "key": "cmd+left",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;9D" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+right",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;9C" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "alt+left",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;3D" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "alt+right",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;3C" },
    "when": "terminalFocus && isMac"
  },

  // ── zsh-edit-select selection shortcuts ─────────────
  // Basic Shift+Arrow keys must also be explicitly mapped in VS Code's terminal
  // because VS Code intercepts them for editor selection before they reach the shell.
  {
    "key": "shift+left",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;2D" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "shift+right",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;2C" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "shift+up",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;2A" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "shift+down",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;2B" },
    "when": "terminalFocus && isMac"
  },
  // Cmd+Shift+Left/Right: select to line start/end
  {
    "key": "cmd+shift+left",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;10D" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+shift+right",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;10C" },
    "when": "terminalFocus && isMac"
  },
  // alt+shift = Option+Shift in VS Code modifier syntax
  // Option+Shift+Left/Right: select word by word
  {
    "key": "alt+shift+left",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;4D" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "alt+shift+right",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;4C" },
    "when": "terminalFocus && isMac"
  },
  // Cmd+Shift+Up/Down: select to buffer start/end
  {
    "key": "cmd+shift+up",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;10A" },
    "when": "terminalFocus && isMac"
  },
  {
    "key": "cmd+shift+down",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "\u001b[1;10B" },
    "when": "terminalFocus && isMac"
  }

  // ── zsh-edit-select ctrl fallback for redo (optional) ──────────────────────────────────────
  // Only needed if you use Ctrl+Shift+Z as a Redo fallback instead of Cmd+Shift+Z.
  // Configure the fallback via: edit-select config → Key Bindings → Redo
  // Uncomment the block below to enable it:
  //
  // {
  //   "key": "ctrl+shift+z",
  //   "command": "workbench.action.terminal.sendSequence",
  //   "args": { "text": "\u001b[90;6u" },
  //   "when": "terminalFocus && isMac"
  // }
]
```

</details>

---

#### Foot *(Linux only)*

<details>
<summary><b>Linux configuration</b></summary>

Foot uses `[key-bindings]` to disable built-in actions and `[text-bindings]` to send custom escape sequences to the shell. Two built-in bindings must be unbound before adding the plugin's sequences:

- `clipboard-copy` (defaults to `Control+Shift+c`) — must be unbound so the copy escape sequence reaches the shell instead of triggering Foot's clipboard action.
- `prompt-prev` (defaults to `Control+Shift+z`) — must be unbound so the undo escape sequence reaches the shell instead of triggering Foot's prompt navigation.
- Foot does not  reliably follow the primary-selection protocol: it does not release PRIMARY when you click to deselect text, so mouse replacement can stay latched to an old selection. That is a Foot-side limitation, not a plugin bug. For Foot, keep mouse replacement disabled in the Configuration Wizard (`edit-select config` → Option 1 → Disabled) and use keyboard selection instead.

Foot passes Shift+Arrow keys through to the terminal natively — **no additional configuration is needed for Shift selection.**

Add the following to `foot.ini`, merging into any existing `[key-bindings]` and `[text-bindings]` sections (do not create duplicate section headers):

```ini
[key-bindings]
# Unbind Foot's built-in clipboard-copy so the escape sequence reaches the shell
clipboard-copy=none
# Unbind Foot's built-in prompt-prev so the undo escape sequence reaches the shell
prompt-prev=none

[text-bindings]
# ── zsh-edit-select copying shortcut ───────────────────────
# Option A (Default): Ctrl+Shift+C = copy
\x1b[67;6u = Control+Shift+c

# Option B (Reversed): Ctrl+C = copy, Ctrl+Shift+C = interrupt
# Use this if you prefer GUI-style copy behavior (like in regular desktop apps).
# To use this option: replace the Option A line above with both lines below.
# \x1b[67;6u = Control+c
# \x03 = Control+Shift+c

# ── zsh-edit-select undo / redo ─────────────────────────
\x1b[90;6u = Control+Shift+z
```

</details>

---

#### iTerm2 *(macOS only)*

<details>
<summary><b>macOS configuration</b></summary>

iTerm2 is configured through its GUI rather than a config file. Follow the steps below to add all required key bindings.

### Step 1 — Open the Key Bindings panel

1. Open iTerm2 **Settings** (`Cmd+,`)
2. Go to the **Keys** tab at the top
3. Select the **Key Bindings** sub-tab

> Use the top-level **Keys** tab, **not** Profiles → Keys. This makes the bindings apply globally to all sessions.

### Step 2 — Add each binding

For every row in the tables below: click the **+** button, press the keyboard shortcut shown, set the **Action** to **"Send Escape Sequence"**, and enter the value exactly as shown.

iTerm2 prepends `ESC` (`\x1b`) automatically — so entering `[99;9u` correctly produces `\x1b[99;9u`.

---

#### zsh-edit-select Editing Shortcuts

| Keyboard Shortcut | Action | Value | Description |
|---|---|---|---|
| `Cmd+A` | Send Escape Sequence | `[97;9u` | Select All |
| `Cmd+C` | Send Escape Sequence | `[99;9u` | Copy |
| `Cmd+X` | Send Escape Sequence | `[120;9u` | Cut |
| `Cmd+Z` | Send Escape Sequence | `[122;9u` | Undo |
| `Cmd+Shift+Z` | Send Escape Sequence | `[122;10u` | Redo |

---

#### zsh-edit-select Navigation Keys

| Keyboard Shortcut | Action | Value | Description |
|---|---|---|---|
| `Cmd+←` | Send Escape Sequence | `[1;9D` | Move to line start |
| `Cmd+→` | Send Escape Sequence | `[1;9C` | Move to line end |

---

#### zsh-edit-select Selection Shortcuts

Basic `Shift+Arrow` keys (`↑ ↓ ← →`) pass through to the shell natively in iTerm2 — no configuration is needed for character-by-character and line-by-line selection.

Add the following for the macOS-specific extended selection combinations:

| Keyboard Shortcut | Action | Value | Description |
|---|---|---|---|
| `Cmd+Shift+←` | Send Escape Sequence | `[1;10D` | Select to line start |
| `Cmd+Shift+→` | Send Escape Sequence | `[1;10C` | Select to line end |
| `Cmd+Shift+↑` | Send Escape Sequence | `[1;10A` | Select to buffer start |
| `Cmd+Shift+↓` | Send Escape Sequence | `[1;10B` | Select to buffer end |

---

> **iTerm2 recommended setting:** iTerm2 has a built-in setting **"Copy to pasteboard on selection"** (Settings → General → Selection) that is **enabled by default**. When enabled, every mouse drag in iTerm2 automatically copies the selected text to the clipboard. This does not affect the AX-only implementation's correctness — our daemon does not monitor the clipboard, so no spurious events occur. However, it does mean every mouse drag overwrites your clipboard, even if you only intend to highlight to replace with a keystroke. For zero clipboard pollution on mouse highlights, disable this setting: **Settings → General → Selection → uncheck "Copy to pasteboard on selection" (or "Copy to clipboard on selection")**. With it disabled, mouse highlights are handled exclusively by the plugin's Accessibility path and never touch the clipboard.

</details>

---

#### Optional: Ctrl Key Remaps *(macOS only)*

These are optional remaps for users who prefer `Ctrl` key fallbacks over `Cmd`. Neither is required for normal plugin operation — configure only what you need.

<details>
<summary><b>macOS configuration</b></summary>

### Ctrl+C → Copy (CSI-u approach)

If you want to use `Ctrl+C` for copy instead of `Cmd+C`, configure your terminal to send the CSI-u sequence for `Ctrl+C` and move the interrupt signal to `Ctrl+Shift+C`. Then in the plugin wizard (`edit-select config` → Key Bindings → Copy), choose **"Ctrl+C via CSI-u"**.

**iTerm2** — Add in **Preferences → Profiles → Keys → Key Mappings**:

| Keyboard Shortcut | Action | Value | Notes |
|---|---|---|---|
| `Ctrl+C` | Send Escape Sequence | `[67;6u` | Reassigns Ctrl+C to Copy |
| `Ctrl+Shift+C` | Send Hex Code | `0x03` | Restores interrupt (SIGINT) |

**Kitty** — Add to `kitty.conf`:

```conf
map ctrl+c send_text all \x1b[67;6u
map ctrl+shift+c send_text all \x03
```

**WezTerm** — Add to the `keys` table in `wezterm.lua`:

```lua
{ key = 'c', mods = 'CTRL',       action = act.SendString '\x1b[67;6u' },
{ key = 'c', mods = 'CTRL|SHIFT', action = act.SendString '\x03'        },
```

**Ghostty** — Add to `~/.config/ghostty/config`:

```
keybind = ctrl+c=csi:67;6u
keybind = ctrl+shift+c=text:\x03
```

**VS Code** — Add to `keybindings.json`:

```json
{
  "key": "ctrl+c",
  "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u001b[67;6u" },
  "when": "terminalFocus && isMac"
},
{
  "key": "ctrl+shift+c",
  "command": "workbench.action.terminal.sendSequence",
  "args": { "text": "\u0003" },
  "when": "terminalFocus && isMac"
}
```

---

### Ctrl+Shift+Z → Redo fallback

If you prefer `Ctrl+Shift+Z` as your Redo key instead of `Cmd+Shift+Z`, configure the fallback via `edit-select config` → Key Bindings → Redo, then add the binding for your terminal below.

**iTerm2** — Add in **Preferences → Profiles → Keys → Key Mappings** (note: Profiles → Keys, not the global Keys tab):

| Keyboard Shortcut | Action | Value |
|---|---|---|
| `Ctrl+Shift+Z` | Send Escape Sequence | `[90;6u` |

**Kitty** — Add to `kitty.conf`:

```conf
map ctrl+shift+z send_text all \x1b[90;6u
```

**WezTerm** — Add to the `keys` table in `wezterm.lua`:

```lua
{ key = 'Z', mods = 'CTRL|SHIFT', action = act.SendString '\x1b[90;6u' },
```

**Ghostty** — Add to `~/.config/ghostty/config`:

```
keybind = ctrl+shift+z=csi:90;6u
```

**VS Code** — Uncomment the block already included at the bottom of the `keybindings.json` snippet above.

</details>


---

---

## WSL Support

WSL is fully supported, including mouse selection integration, custom tracking modes, and a tailored clipboard agent architecture designed for seamless interaction between Windows Terminal and WSL-native shells.


<details>
<summary><b>Installation and Terminal Configuration</b></summary>

1. Install the plugin using [Manual Installation](#manual-installation).
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

Save `settings.json`, restart the profile, and run `source ~/.zshrc`. `Ctrl+Shift+C` will send `0x1D` (`Ctrl+]`), which `stty`
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

Switching between modes is automatic and seamless: click anywhere outside the current command buffer to temporarily enter `free selection` mode and interact with the terminal natively. Mouse tracking resumes automatically as soon as you return to the command buffer by typing, moving using ketboard arrows, or doing a keyboard selection.

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



## SSH Support (Headless Linux Box)

If you are SSH-ing into a headless Linux box, the plugin **automatically detects the SSH environment** and switches clipboard operations to use **OSC 52** — a terminal escape sequence that tunnels clipboard writes back to your local terminal through the SSH connection, without needing any additional tools or manual configuration.

---

### How It Works

When `$SSH_CLIENT`, `$SSH_TTY`, or `$SSH_CONNECTION` is set (standard variables present in any SSH session), the plugin replaces its native clipboard backend with an OSC 52 write. This means:

- **Copy / Cut** — text is written directly to your local clipboard via OSC 52.
- **Paste** — must be triggered using your terminal's native paste keybinding (e.g. Cmd+V in iTerm2/Ghostty, Ctrl+V in Windows Terminal). The plugin cannot read the clipboard back over SSH.
- **Text selection** (Shift+Arrow etc.) — works identically to a local session.
- **Mouse selection** — the background daemon will not start (no display server on a headless box); mouse selection is disabled automatically.

No `~/.zshrc` changes are needed on the Linux box. Just install the plugin normally.

---

### Opt Out

If you do not want the automatic SSH behaviour (e.g. you are SSH-ing between Linux machines and have `xclip` available via X11 forwarding), add this to your `~/.zshrc` on the remote machine **before** the plugin loads:

```zsh
ZES_SSH_CLIPBOARD=0
```

---

### Terminal Requirements

Your terminal must support OSC 52 clipboard writes and have clipboard access enabled. Most modern terminals support this out of the box.

| Terminal | OSC 52 write | Notes |
|---|---|---|
| iTerm2 | ✅ | Enable "Applications in terminal may access clipboard" in Settings → General → Selection |
| Ghostty | ✅ | Add `clipboard-write = allow` to `~/.config/ghostty/config` |
| Kitty | ✅ | Works out of the box |
| WezTerm | ✅ | Works out of the box |
| Alacritty | ✅ | Works out of the box |
| Windows Terminal | ✅ | Works out of the box; `Ctrl+V` pastes natively |
| Terminal.app | ✅ | Works out of the box |

**tmux / GNU Screen:** If you are using tmux or GNU Screen inside your SSH session, the plugin automatically wraps OSC 52 writes in the correct DCS passthrough sequence — no extra configuration needed. For tmux versions older than 3.3a, you may also need to add `set -g allow-passthrough on` to your `~/.tmux.conf`.

A paste keybinding must be configured at the terminal level so that your local clipboard content can be inserted into the SSH session. If your terminal already has one (e.g. Windows Terminal's `Ctrl+V`, or macOS terminals' `Cmd+V`), no additional setup is needed.

If you need to add one manually:

- **Kitty:** add `map ctrl+v paste_from_clipboard` to `~/.config/kitty/kitty.conf`
- **Ghostty:** add `keybind = ctrl+v=paste_from_clipboard` to `~/.config/ghostty/config`

---

### macOS to Linux — Cmd/Option Key Auto-Remapping

If you are SSH-ing from a macOS terminal (iTerm2, Ghostty, Kitty, WezTerm, Alacritty), the plugin **automatically maps your macOS Cmd/Option key sequences** to the corresponding Linux actions. No extra configuration is needed on the remote Linux box — Cmd+C copies, Cmd+X cuts, Cmd+A selects all, Cmd+Z undoes, Option+Arrow moves by word, etc.

**Prerequisite:** Your macOS terminal must be configured to forward Cmd key sequences as CSI-u escape codes (e.g., `Cmd+C` → `\e[99;9u`). If you already configured your terminal for the plugin locally on macOS (following the **macOS Keybindings** section above), those same settings will work transparently over SSH.

> **Note:** `Cmd+V` (Paste) is handled by your macOS terminal natively — it pastes directly into the SSH session. The plugin does not intercept it.

---

### Windows Terminal — Enable Ctrl+C Copy

If you are SSH-ing from Windows Terminal, the Linux TTY intercepts `Ctrl+C` as an interrupt signal (`SIGINT`) by default, preventing the plugin from copying text.

To enable `Ctrl+C` copying, run this one-liner to append the necessary bindings to your **remote** `~/.zshrc`:

```bash
cat >> ~/.zshrc << 'EOF'

# zsh-edit-select: Enable Ctrl+C copy over SSH from Windows Terminal
stty intr ^]
bindkey -M emacs '^C' edit-select::copy-region
bindkey -M edit-select '^C' edit-select::copy-region
EOF

source ~/.zshrc
```

> **Warning:** This tells the Linux box to use `Ctrl+]` for interrupts instead of `Ctrl+C`. `Ctrl+C` will now *always* copy text. You can no longer use `Ctrl+C` to stop runaway programs or clear the current prompt — **you must press `Ctrl+]` to interrupt programs.**

<details>
<summary><b>Make Ctrl+Shift+C send Interrupt</b></summary>

To use `Ctrl+Shift+C` for interrupt (`SIGINT`), add one entry to `"actions"` and one to `"keybindings"` in the Windows Terminal `settings.json`:

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
"keybindings": [
  ...existing keybindings...,
  {
    "id": "User.sendIntr",
    "keys": "ctrl+shift+c"
  }
]
```

Save `settings.json`, restart the profile, and run `source ~/.zshrc`. `Ctrl+Shift+C` will send `0x1D` (`Ctrl+]`), which `stty` treats as interrupt.

</details>

---


**Ghostty terminfo on the remote Linux box:** If your distro does not ship Ghostty's terminfo entry (e.g. Ubuntu Server), commands like `clear` may fail and backspace may not work correctly. Fix it by running this on the remote server:

```bash
echo '[[ "$TERM" == "xterm-ghostty" ]] && export TERM=xterm-256color' >> ~/.zshrc
source ~/.zshrc
```

This was tested on Ubuntu Server 24.04. Your experience may differ depending on your Linux distro.

---

**iTerm2 — Clipboard Access**

Navigate to **iTerm2 → Settings → General → Selection**, ensure **"Applications in terminal may access clipboard"** is checked, and set **"Allow sending of clipboard contents?"** to **Always**.

---
---

## Default Key Bindings Reference

### Linux

#### Navigation Keys
| Key Combination | Action |
| --------------- | ------ |
| **Ctrl + ←** | Move cursor one word left |
| **Ctrl + →** | Move cursor one word right |
| **Home** | Move to line start |
| **End** | Move to line end |

#### Selection Keys
| Key Combination | Action |
| --------------- | ------ |
| **Shift + ←** | Select one character left |
| **Shift + →** | Select one character right |
| **Shift + ↑** | Select one line up |
| **Shift + ↓** | Select one line down |
| **Shift + Home** | Select to line start |
| **Shift + End** | Select to line end |
| **Shift + Ctrl + ←** | Select to word start |
| **Shift + Ctrl + →** | Select to word end |
| **Shift + Ctrl + Home** | Select to buffer start |
| **Shift + Ctrl + End** | Select to buffer end |
| **Ctrl + A** | Select all text |

#### Editing Keys
| Key Combination | Action |
| --------------- | ------ |
| **Ctrl + C** | Copy selected text |
| **Ctrl + X** | Cut selected text |
| **Ctrl + V** | Paste (replaces selection if any) |
| **Ctrl + Z** | Undo last edit |
| **Ctrl + Shift + Z** | Redo last undone edit |
| **Delete/Backspace** | Delete selected text |
| **Any character** | Replace selected text if any |

---

### macOS

#### Navigation Keys
| Key Combination | Action |
| --------------- | ------ |
| **Option + ←** | Move cursor one word left |
| **Option + →** | Move cursor one word right |
| **Cmd + ←** | Move to line start |
| **Cmd + →** | Move to line end |

#### Selection Keys
| Key Combination | Action |
| --------------- | ------ |
| **Shift + ←** | Select one character left |
| **Shift + →** | Select one character right |
| **Shift + ↑** | Select one line up |
| **Shift + ↓** | Select one line down |
| **Cmd + Shift + ←** | Select to line start |
| **Cmd + Shift + →** | Select to line end |
| **Option + Shift + ←** | Select to word start |
| **Option + Shift + →** | Select to word end |
| **Cmd + Shift + ↑** | Select to buffer start |
| **Cmd + Shift + ↓** | Select to buffer end |
| **Cmd + A** | Select all text |

#### Editing Keys
| Key Combination | Action |
| --------------- | ------ |
| **Cmd + C** | Copy selected text |
| **Cmd + X** | Cut selected text |
| **Cmd + V** | Paste (replaces selection if any) |
| **Cmd + Z** | Undo last edit |
| **Cmd + Shift + Z** | Redo last undone edit |
| **Delete/Backspace** | Delete selected text |
| **Any character** | Replace selected text if any |

---

## Troubleshooting

<details>
<summary><b>Shift selection doesn't work</b></summary>

**Solution:** Configure your terminal to pass Shift key sequences. See [Famous Terminals Configurations](#famous-terminals-configurations).

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
PRIMARY selection. See [Performance-Optimized Architecture](#performance-optimized-architecture) for more details.

</details>

<details>
<summary><b>Ctrl+C / Cmd+C doesn't copy</b></summary>

**Solution:** On Windows/Linux, configure your terminal to remap Ctrl+C. See the
[Famous Terminals Configurations](#famous-terminals-configurations) section.
On macOS, verify you have enabled CSI-u / kitty keyboard protocol support in your terminal to use Cmd+C. See [Famous Terminals Configurations](#famous-terminals-configurations).

**Alternative:** Use Ctrl+Shift+C for copying (or configuring a fallback via `edit-select config` for macOS Terminal.app), or configure a custom keybinding with `edit-select config`, or
use the 'Without Terminal Remapping' method if your terminal doesn't support key remapping.

</details>

<details>
<summary><b>Configuration wizard doesn't launch</b></summary>

**Symptoms:** Running `edit-select config` shows "file not found" error

**Solution:**

1. Check the plugin was installed correctly
2. Verify the wizard file exists in the plugin directory:
   - X11: `edit-select-wizard-x11.zsh`
   - Wayland: `edit-select-wizard-wayland.zsh`
   - macOS: `edit-select-wizard-macos.zsh`
3. Ensure the file has read permissions:
   ```bash
   # X11:
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-x11/edit-select-wizard-x11.zsh
   # Wayland:
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-wayland/edit-select-wizard-wayland.zsh
   # macOS:
   chmod +r ~/.oh-my-zsh/custom/plugins/zsh-edit-select/impl-macos/edit-select-wizard-macos.zsh
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
<summary><b>WSL Helper Binaries Missing</b></summary>

**Symptoms:** Plugin loads but clipboard operations fail or `edit-select config` shows errors about missing helpers

**Solution:** The WSL helper binaries (`zes-wsl-clipboard-helper.exe` and `zes-wsl-selection-agent`) are
downloaded automatically on first use. If they fail to download or execute:

1. **Check your network connection** during the first plugin load.
2. **Download or build manually:** You can compile the binaries yourself. See the [Manual Agents Build (optional)](#manual-agents-build-optional) section.

**Fallback:** If helpers cannot be loaded, the plugin falls back to `powershell.exe Get-Clipboard` for clipboard
operations, which works but is slower. Keyboard selection features are unaffected.

</details>




---

---

## Performance-Optimized Architecture

The plugin architecture is built around compiled native C agents that run as persistent background processes.
Each agent tracks selection changes via display server events, writes updates to a RAM-backed cache.
Backend detection, agent startup, and configuration loading occur once at plugin load; all subsequent
operations use the cached results directly.

### Platform & Feature Coverage

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
- ✅ Mouse selection replacement (where PRIMARY selection is available)

On **macOS**, the same features are available via the Cmd equivalents
(`Cmd+A`, `Cmd+C`, `Cmd+X`, `Cmd+V`, `Cmd+Z`, `Cmd+Shift+Z`) after
[terminal configuration](#famous-terminals-configurations), or via
Ctrl fallbacks set through `edit-select config`.

> **Note on WSL:** All keyboard selection features listed above work identically on WSL. Mouse selection replacement also works on WSL with Windows Terminal when using the tailored tracking modes. See [WSL Support](#wsl-support) for Windows Terminal configuration details.

**Mouse Selection Replacement** is supported across all platforms:

- **macOS** — True PRIMARY selection via Accessibility API (`AXUIElement`); zero clipboard contamination
- **X11 / XWayland** — Complete PRIMARY selection support via XFixes extension; XWayland bridge for mixed environments
- **Native Wayland** — Direct protocol support on wlroots compositors (Sway, Hyprland, River, Wayfire), KDE Plasma, and GNOME/Mutter; when XWayland is unavailable, the native agent uses `zwp_primary_selection_v1` directly and may show a small surface in the dock/taskbar on GNOME/Mutter
- **WSL** — Full mouse selection replacement with custom tracking modes on Windows Terminal

If mouse selection replacement doesn't work:
1. Verify native Wayland or XWayland support is available
2. Check that your compositor supports PRIMARY selection protocols
3. Disable mouse replacement if needed: `edit-select config` → Option 1
4. Report issues on [GitHub](https://github.com/Michael-Matta1/zsh-edit-select/issues)

This plugin has been thoroughly tested on **Kitty Terminal** and briefly on other popular terminals. If you encounter issues, please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with your terminal name, OS, and display server.

### Core Architectural Properties

- **Single-pass initialization** — Backend detection, agent startup, and configuration loading occur at plugin
  load time. The results are cached in shell variables and reused for the entire session.
- **Event-driven selection tracking** — X11 XFixes events and Wayland compositor events drive cache updates;
  all agents sleep in `poll()` between events, consuming no CPU while idle.
- **Compiled C agents** — Direct system calls compiled with aggressive optimization flags
  (`-O3 -march=native -flto -fipa-pta` and link-time dead code elimination); no interpreter overhead.
- **RAM-backed cache** — Cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions),
  with `TMPDIR` or `/tmp` as fallback. On standard systemd-based systems, all cache I/O remains in memory.
- **Wayland protocol path** — Native Wayland uses direct compositor protocols for PRIMARY selection and CLIPBOARD, avoiding `wl-copy`/`wl-paste` subprocesses and keeping clipboard operations inside the persistent agent process.
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

## Manual Agents Build (optional)

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

The plugin naturally uses pre-built portable binaries. If you prefer to compile native agents yourself for an optimized build (`-march=native -mtune=native`), install the required build tools and libraries for your platform:

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

After installing dependencies, you can run `make` inside the respective implementation directory manually.

```bash
# Replace with your actual plugin directory path
# Common locations:
#   Oh My Zsh:  ~/.oh-my-zsh/custom/plugins/zsh-edit-select
#   Zinit:      ~/.local/share/zinit/plugins/Michael-Matta1---zsh-edit-select
PLUGIN_DIR=~/.oh-my-zsh/custom/plugins/zsh-edit-select  # ← change this

# For X11
cd "$PLUGIN_DIR/impl-x11/backends/x11" && make

# For Wayland
cd "$PLUGIN_DIR/impl-wayland/backends/wayland" && make

# For macOS
cd "$PLUGIN_DIR/impl-macos/backends/macos" && make

# For WSL
cd "$PLUGIN_DIR/impl-wsl/backends/wsl" && make
```

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
