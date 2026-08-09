# Zsh Edit-Select

Zsh plugin that lets you edit your command line like a text editor. Select text with Shift + Arrow keys or the
mouse, type or paste to replace selections, use standard editing shortcuts (copy, cut, paste, undo, redo,
select all), and customize keybindings through an interactive wizard — with full Linux, macOS and WSL
support.

[demo video](https://github.com/user-attachments/assets/a024e609-1de1-4608-a7c3-e17264162904)

> If the video doesn't load after waiting for a few seconds, try refreshing the page. You can also access it directly [here](https://drive.google.com/file/d/1nsLfIbyLnNWPkUkmMttfTfip4yXCvayA/view?usp=sharing)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Mouse Selection Integrated Features](#mouse-selection-integrated-features)

>
> ---
>

- [Auto Installation](#auto-installation)
- [Manual Installation](#manual-installation)
- [Configuration Wizard](#configuration-wizard)

>
> ---
>

- [Popular Terminals Configurations](#popular-terminals-configurations)
- [SSH Support](#ssh-support)

>
> ---
>

- [Commands Reference](#commands-reference)
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
- ✅ **Standard shortcuts** — Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V, Ctrl+Z, Ctrl+Shift+Z
  (on **macOS**, Ctrl is replaced by **Command (Cmd)**)

> [!NOTE]
> **Customization:** The plugin works with editor-like defaults after installation. Use the command `edit-select config` to customize mouse behavior and keybindings.

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

> **macOS:** Replace `Ctrl` with `Cmd` for whole-line/all-text shortcuts, and with `Option` for word-by-word selection.

> [!TIP]
>
> For the full keybindings, check the [Default Key Bindings Reference](#default-key-bindings-reference).

### Mouse Selection Integration

The plugin integrates mouse selections, but you can disable it using the [Configuration Wizard](#configuration-wizard):

**When Mouse Replacement is Enabled (default):**

- ✅ Copy mouse selections with Ctrl+C
- ✅ Cut mouse selections with Ctrl+X
- ✅ Type to replace mouse selections
- ✅ Delete mouse selections with Backspace/Delete
- ✅ Paste over mouse selections with Ctrl+V

**When Mouse Replacement is Disabled:**

- ✅ Copy mouse selections with Ctrl+C
- ✅ Replacement/Deletion work with keyboard selections only.

> **Note:** Configure mouse behavior with the command `edit-select config` → Option 1
>
> On macOS, Cmd replaces Ctrl, and all keybindings can be customized to match your preferences.

### Type-to-Replace and Paste-to-Replace

Type or paste while text is selected to replace it automatically.

Works with both keyboard and mouse selections (when mouse replacement is enabled).

### Copy, Cut, and Paste

Standard editing shortcuts:

- **Ctrl + C** (or Ctrl+Shift+C if configured): Copy selected text
- **Ctrl + X**: Cut selected text
- **Ctrl + V**: Paste (replaces selection if any)

On macOS, Cmd is used instead of Ctrl for these bindings.

> **Clipboard Managers Compatibility Note:** The plugin is fully compatible with clipboard history managers
> such as **CopyQ**, **GPaste**, and **Maccy**. Because it uses the standard clipboard protocols on X11, Wayland, and macOS, it integrates with them automatically.

### Undo and Redo

Navigate through your command line editing history:

- **Ctrl + Z**: Undo last edit
- **Ctrl + Shift + Z**: Redo last undone edit

> **Note:** The `Ctrl+Z` keybinding works seamlessly alongside the traditional suspend process functionality
> (Ctrl+Z suspends a running foreground process to background). The plugin intelligently handles undo
> operations for command line editing while preserving the ability to suspend processes when needed.
>
> Also, `Ctrl+X` works seamlessly for multi-key chords where it acts as a prefix key (for example, `Ctrl+X Ctrl+E`) in ZLE/Emacs keymaps

On macOS, these bindings are `Cmd+Z` for Undo and `Cmd+Shift+Z` for Redo.

### Clipboard Integration

The plugin includes purpose-built clipboard agents that replace external tools entirely:

**Clipboard Integration Agents:** small compiled programs built specifically for this plugin to handle all
clipboard and selection operations.

The agents handle copy, paste, and clipboard operations directly through native protocols, so no external
tools are needed and the plugin remains fully self-contained. They communicate with the plugin through a fast
in-memory cache, giving you instant clipboard response.

> See [Performance-Optimized Architecture](#performance-optimized-architecture) for benchmarks and implementation details.

---

## Mouse Selection Integrated Features

Beyond basic mouse selection, the plugin ships four mouse-selection-aware features:

- **Mouse Replacement** — enables keyboard-style edit operations (cut, delete, type-over, paste-over) on text selected with the mouse, with an enable/disable toggle and two operating modes.
- **Mouse Replacement Safeguard** — disambiguates mouse selections when the same text appears more than once in your command buffer, so an edit never lands on the wrong occurrence.
- **Prompt-Aware Mouse Selection Matching** — automatically trims prompt prefix and status-suffix noise from mouse drags that include it, so edit actions target the command you actually typed.
- **Clearing a Selection by Clicking** — how the plugin delivers the deselect signal to the shell in each terminal, and what happens when you clear a mouse selection by clicking elsewhere.

These features are transparent to the user: they activate automatically whenever the mouse-selection path is active and require no per-terminal configuration. Keyboard selections bypass them entirely. Together, they keep mouse-driven edits correct and predictable.

**Click any of the following sections to expand it for more details:**

<details>
<summary><h3 id="mouse-replacement">Mouse Replacement</h3></summary>

**Mouse Replacement** is the bridge between mouse-driven text selection and the plugin's keyboard-style editing model. When enabled, the plugin treats a live mouse selection the same way it treats a keyboard (`Shift+Arrow`) selection, so the standard keyboard edit actions operate on it directly:

- **Cut** — Cut the selected text with `Ctrl+X` (or `Cmd+X` on macOS). The text is removed from the command line and copied to the clipboard.
- **Delete** — Delete the selected text with `Backspace`/`Delete`.
- **Type to replace** — Start typing and the new text replaces the current mouse selection in place.
- **Paste to replace** — Paste with `Ctrl+V` (or `Cmd+V` on macOS) and the clipboard content is inserted in place of the mouse selection.

You can enable or disable Mouse Replacement at any time through the configuration wizard:

```bash
edit-select config   # → Option 1: Mouse Replacement
```

When **enabled** (the default), all four operations above work with mouse selections as well as keyboard selections. When **disabled**, the plugin stops treating live mouse selections as editable regions — typing, pasting, cutting, and deleting only act on keyboard selections — but mouse selections can still be **copied** with `Ctrl+C` (or `Ctrl+Shift+C` where configured). Copy is the one operation that always works with a mouse selection regardless of the Mouse Replacement toggle.

> **macOS:** `Cmd` replaces `Ctrl` for all of the above (`Cmd+X`, `Cmd+V`, etc.).

---

</details>

<details>
<summary><h3 id="mouse-replacement-safeguard">Mouse Replacement Safeguard</h3></summary>

The plugin includes a safety feature to prevent accidental edits when using the mouse. If you select text with your mouse and the plugin detects multiple identical occurrences of that text in your command buffer, it will pause and show the message:

**"Duplicate text: place cursor inside the occurrence you want to modify"**

<details>
<summary><b>Demo (Click to expand)</b></summary>

[demo video](https://github.com/user-attachments/assets/e3aaaa56-1bc7-4194-a87b-1c7556ab8049)

> If the video doesn't load after waiting for a few seconds, try refreshing the page. You can also access it directly [here](https://drive.google.com/file/d/1YUmxh7CMdQMMiQaSHHhkZzOQx1PnmElf/view?usp=sharing)

</details>

**Why this feature?**
When text is selected via mouse, terminal emulators don't report the exact screen coordinates to the shell. If the same word appears twice, this protective safeguard ensures you don't accidentally replace the wrong occurrence.

When prompted, simply place your cursor inside the specific occurrence you want to edit, then select and replace it.

> **Note:** A terminal with shell integration (such as Kitty or Ghostty) is recommended, because it lets you move the cursor using a single mouse click with no extra keys pressed. If your terminal supports shell integration but does not enable it by default, enable it.

<p align="center">
  <strong>✦ ───────── ✦</strong>
</p>

**Exception:** If you are using **Ghostty** on **Linux**, text selected with a **double-click** can be deleted or replaced **without prompting**. This happens because Ghostty automatically moves the cursor to the selected word when you double-click it.

<details>
<summary><b>Demo (Click to expand)</b></summary>

[demo video](https://github.com/user-attachments/assets/35d72bed-0d3c-4b4c-876a-8ddf705f9fc2)

> If the video doesn't load after waiting for a few seconds, try refreshing the page. You can also access it directly [here](https://drive.google.com/file/d/1L6Ga4tsZOQurR8BmLLW2ZHGbMjfmLnnC/view?usp=sharing)

</details>


- The WSL implementation also provides a custom mouse-tracking path that resolves the exact selected range without prompting.

<p align="center">
  <strong>✦ ───────── ✦</strong>
</p>

**Keyboard selection bypass:** This safeguard is only needed for mouse selections. Using `Shift+Arrow keys` provides exact cursor positions, avoiding this ambiguity entirely.

If you prefer strict keyboard-only editing, you can also disable mouse replacement entirely, as described in the [Mouse Replacement](#mouse-replacement) section.

---

</details>

<details>
<summary><h3>Prompt-Aware Mouse Selection Matching</h3></summary>

When a mouse drag captures the prompt prefix (e.g. `user@host:~$` or a Powerlevel10k breadcrumb) or a right-aligned status suffix along with the command text, the plugin automatically resolves the selection down to the editable command text — so cut, type-over, paste-over, and delete act correctly on the command you typed, ignoring the rest of the raw highlight. Decorated multi-line selections (left prompt on row 1 and/or right-aligned status, clean continuation rows) are likewise resolved to the underlying multi-line command. Ambiguous, non-aligning, or partial selections are rejected rather than guessed.

>
> Expand the following section for a demo video showing it in action.
>

<details>
<summary><b>Demo (Click to expand)</b></summary>

[demo video](https://github.com/user-attachments/assets/818251f6-389f-4dcf-b2c1-f96493cb83ca)

> If the video doesn't load after waiting for a few seconds, try refreshing the page. You can also access it directly [here](https://drive.google.com/file/d/1cOeCNU2TbMXjyAFWTK1nrHcqOJ-tw_tS/view?usp=sharing)

</details>

>

**Net behavior** (X11 / Wayland / macOS):

- A selection that starts on the prompt line and spans part or all of the command resolves to the clean command text — cut, type-over, paste-over, and delete operate on the matched command, not the raw highlight.
- A decorated multi-line selection (left prompt on row 1 and/or right-aligned status, clean continuation rows) resolves to the underlying multi-line command.
- Ambiguous selections that cannot be matched to a unique editable region are **rejected**, and handled by the duplicate-disambiguation prompt described in the [Mouse Replacement Safeguard](#mouse-replacement-safeguard) section above.
- Copy is not affected: you can still copy a whole visible line, decorations and all, including the prompt prefix and any right-aligned suffix. The resolver applies only to the actions that edit the command-line buffer — delete, cut, type-to-replace, and paste-to-replace.

There is nothing to configure and no per-terminal setup; the resolver runs automatically whenever the mouse-selection path is active. Keyboard selections bypass it entirely.

**Designed for zero-overhead editing.** The matcher is carefully designed with optimized layered algorithms so that the common case is free and the fallback work is bounded and kept strictly off the hot path. An exact match (when neither the left prefix nor the right suffix is involved) costs essentially nothing beyond the pre-feature behavior and has zero additional cost.

---

</details>

<details>
<summary><h3 id="clearing-a-selection-by-clicking">Clearing a Selection by Clicking (Linux only)</h3></summary>

This section explains how the plugin handles the clearing of mouse selections when you click elsewhere in the terminal, and what you can do to ensure that your edits land where you expect. It applies to Linux terminals only; macOS terminals handle this automatically, and nothing is required beyond the settings in the [Popular Terminals Configurations](#popular-terminals-configurations) section.

When you select text with the mouse, then decide not to apply any operation to that selection and click elsewhere to clear it, the terminal drops its on-screen highlight — but most terminals do **not** tell the shell about that click. The plugin therefore still has no way to tell if the selected text is live or not, so the next edit (typing, pasting, cutting, deleting) can land on the now-invisible selection instead of inserting at the cursor. This is not a bug in the plugin; it is a quirk of how `PRIMARY` selection broadcasting works — a terminal keeps `PRIMARY` set until either the user explicitly copies something else or the terminal itself reports a clear. Some terminals signal the click, others do not.

What the plugin does for each terminal, and what you can do about it:

- **Kitty & Ghostty** — enable shell integration (usually enabled by default); nothing else is needed. These are the most recommended terminals for the plugin, because their shell integration lets it handle mouse selections and clicks natively.
  + Ghostty handles clicks that reposition the cursor, covering almost all cases. The only remaining case occurs rarely, and you can simply undo it (Ctrl+Z) if you encounter it. It occurs when text is selected by dragging (not by double- or triple-clicking) **and** the typing cursor is at the right **end** of the command line, **and** the click lands in the empty space **to the right** of the command. All three conditions must be **met at the same time** for this case to occur, and if any of the three is not met, the selection is cleared successfully.
  + The Ghostty developers plan to add configurable mouse-button bindings, once added by Ghostty developers in the future, will allow this case to be covered as well.
  + For now, make sure you haven't disabled shell integration or `cursor-click-to-move`, both of which are enabled by default. Also, make sure their equivalent settings in Kitty are not disabled (Unlike Ghostty, Kitty covers all cases.).

- **WezTerm** — handled by a mouse-bindings snippet in the WezTerm config; see [Popular Terminals Configurations](#popular-terminals-configurations).
- **Alacritty** — handled by a mouse-bindings snippet in the Alacritty config; see [Popular Terminals Configurations](#popular-terminals-configurations).
- **Foot** — there is no way to hook a plain left-click without taking over the mouse binding that selection itself needs, so this cannot currently be solved from configuration. **What to do:** either disable mouse replacement and use keyboard selection for edits, or keep mouse replacement enabled and adopt whichever of the **common workarounds** below suits your workflow.
- **VS Code** — a click within the terminal pane to clear a selection is silently ignored by the integrated terminal.
    - **What already works:** clicking into a different VS Code pane, into any area of the VS Code window outside the terminal pane, or into another application window clears the selection automatically.
    - **Workaround for the remaining within-pane case:** to abandon a selection without acting on it, click once anywhere outside the terminal pane instead of clicking inside it.

**Common workarounds** that work on **any** terminal: in a terminal with no automatic fix (such as VS Code and Foot), you can clear the selection by any of the following:

- pressing any arrow key (←/→/↑/↓);
- clicking into a different pane or area outside the terminal;
- applying any operation to the selection — copying it is enough if you don't want to perform an edit.

or:
- just immediately undo the edit with `Ctrl+Z` if it happens to be applied to a stale selection (which is already uncommon in most workflows).
- You can also disable mouse replacement and use only keyboard selection for edits if you prefer.

This is a design limitation of VS Code and Foot, not a plugin bug. VS Code's `keybindings.json` and `settings.json` expose no hook for a plain left-click, and its extension API has no terminal mousedown event to subscribe to.


---

</details>

---
---

## Auto Installation

> [!NOTE]
> If you are comfortable editing dotfiles and prefer full control over your system configuration, [Manual Installation](#manual-installation) is the recommended approach.

The installation consists of two main steps:

1. **Install the plugin** — Clone the repository with your plugin manager and add one line to your `.zshrc`.
2. **Configure your terminal** — Add a few keybinding entries to your terminal's config file.

Each step is documented with exact commands and copy-paste configurations.

- All instructions are organized in collapsed sections so you can expand only what applies to your specific
  setup and platform.

The auto-installer is not recommended for complex setups or heavily customized config files. It is
provided as a convenience for users who prefer a fully guided, hands-off setup or are less comfortable with
terminal configuration. It has been tested across multiple environments using virtual machines and Docker
containers and handles the most common configurations, but not every edge case can be guaranteed. If you
encounter an issue, please
[report it](https://github.com/Michael-Matta1/zsh-edit-select/issues) so it can be addressed.

The auto-installer detects your environment, installs dependencies, sets up the plugin, and configures your
terminals in a single run.

To use it, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install/install.sh)
```

Or

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install/install.sh)
```

<details>
<summary><h3>Demo (Click to expand)</h3></summary>

The installer detects your environment up front and guides you through the installation, dynamically showing only the prompts and options relevant to your detected setup at each step, so you're presented only with choices that apply to your environment.

[demo video](https://github.com/user-attachments/assets/a5539e7c-179e-45a6-8cd4-324b0de7d98a)

> If the video doesn't load after waiting for a few seconds, try refreshing the page. You can also access it directly [here](https://drive.google.com/file/d/1R54T8klE-B_zAMn3FoE3OsYm_ExS0GCa/view?usp=sharing)

The script provides detailed, color-coded feedback for every step, and at the end you receive a **Summary Report** listing all installed components and any manual steps
required.

A detailed log is also saved to `~/.zsh-edit-select-install.log`.

</details>

<details>
<summary><h3>Key Features & Options (Click to expand)</h3></summary>

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
| **Dependencies**   | - Installs system packages like (`git`, `zsh`), and interactively asks to optionally install build tools (`gcc`, `make`, `clang`) and dependencies for compiling the agents locally<br>- Detects your system (macOS, Debian, Fedora, Arch, etc.) and uses the correct package manager (`brew`, `port`, `apt`, `dnf`, `pacman`)                                                                                                                                          |
| **Plugin Manager** | - **Detects** your existing manager (Oh My Zsh, Zinit, Antigen, Sheldon, etc.)<br>- **Offers to install Oh My Zsh** if you don't have a plugin manager. You can refuse if you prefer manual installation<br>- _Note: The installer detects and installs the plugin for other managers such as Zinit or Antigen, but it does not install those managers themselves. If you prefer using them instead of OMZ, make sure they are installed before running the installer._ |
| **Terminal Setup** | - Configures **Kitty**, **Alacritty**, **WezTerm**, **Foot** (Linux), **Ghostty**, **iTerm2** (macOS), **VS Code**, and **Windows Terminal** (WSL) to support keybindings<br>- Backs up existing config files before making changes                                                                                                                                                                                                                                     |
| **Safeguards**     | - Checks for conflicting keybindings in your `.zshrc` and terminal configuration files (Kitty, Alacritty, WezTerm, Foot, Ghostty, iTerm2, VS Code, Windows Terminal)<br>- Verifies the installation with a self-test suite                                                                                                                                                                                                                                              |

>

<details>
<summary><h3>Advanced Usage & Options & CI/CD (Click to expand)</h3></summary>

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
bash <(curl -fsSL https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install/install.sh) --non-interactive
```

</details>

</details>

---

## Manual Installation

The process consists of two main steps:

1. **Install the plugin** — Clone the repository with your plugin manager and add one line to your `.zshrc`.
2. **Configure your terminal** — Add a few keybinding entries to your terminal's config file.

> **Pre-built Agents:** The plugin includes portable binaries generated via GitHub workflows. These binaries are automatically downloaded on first load, which may take a few seconds. You may also need to restart your terminal after the initial setup.
>
> For a manual build and an optimized experience tailored to your specific hardware (e.g., using `-march=native -mtune=native`), refer to [Manual Agents Build (optional)](#manual-agents-build-optional).
>
> In some cases, the **first** shell load may be delayed by temporary GitHub infrastructure issues that slow the agent download. This affects **only** the **first** post-installation load. If that **first** startup takes longer than expected, wait a few minutes and try again once GitHub services are fully operational.

### 1. Install the Plugin

Expand the section for your plugin manager:

<details>
<summary><b>Oh My Zsh</b></summary>

```bash
git clone --depth=1 https://github.com/Michael-Matta1/zsh-edit-select.git \
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

**One-liner:**

```bash
zinit depth"1" light-mode for Michael-Matta1/zsh-edit-select
```

**Or with explicit `ice`:**

```bash
zinit ice depth"1"; zinit light Michael-Matta1/zsh-edit-select
```

</details>

<details>
<summary><b>zplug</b></summary>

```bash
zplug "Michael-Matta1/zsh-edit-select", depth:1
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

**Via CLI:**

```bash
sheldon add zsh-edit-select --github Michael-Matta1/zsh-edit-select
```

**Or manually in `~/.config/sheldon/plugins.toml`:**

```toml
[plugins.zsh-edit-select]
github = "Michael-Matta1/zsh-edit-select"
```

</details>


Or:
<details>
<summary><b>Without a Plugin Manager</b></summary>

```bash
git clone --depth=1 https://github.com/Michael-Matta1/zsh-edit-select.git \
  ~/.local/share/zsh/plugins/zsh-edit-select

# Add to ~/.zshrc:
source ~/.local/share/zsh/plugins/zsh-edit-select/zsh-edit-select.plugin.zsh
```

</details>

<p align="center">
  <strong>────────── ✦ ──────────</strong>
</p>

### 2. Configure Your Terminal

Some terminals require configuration for selection support, while others require only editing-related mappings. See [Popular Terminals Configurations](#popular-terminals-configurations) for
details.

<p align="center">
  <strong>────────── ✦ ──────────</strong>
</p>

### 3. Restart Your Shell

```bash
source ~/.zshrc
```

**Important:** You may need to **fully close and reopen your terminal** (not just source ~/.zshrc) for all
features to work correctly, especially in some terminal emulators.

> [!IMPORTANT]
>
> #### **(Wayland Users only)**
>
> <details>
> <summary><b>Click to expand</b></summary>
>
> If you are using Wayland on **GNOME**, **Cinnamon**, or **Pantheon**, XWayland is required for the plugin to function correctly under Wayland.
>
> XWayland is **enabled by default** on most systems, so **no action is needed** unless you have explicitly disabled it.
>
> **Important:** Desktop environments expose Wayland in different ways. The plugin supports all Wayland compositors by shipping multiple Wayland and XWayland backends and supporting multiple protocols. In rare cases, auto-detection may pick the wrong backend for your setup. If you encounter issues — such as being unable to copy from the scrollback, or a blank or non-focusable window appearing in your taskbar when you copy text — please [report it](https://github.com/Michael-Matta1/zsh-edit-select/issues), including your desktop environment, compositor, and terminal, whether XWayland is enabled, and the detected platform shown when you run `edit-select config`. This lets us point you to the correct protocol or backend (native Wayland or XWayland) for your setup.
>
> </details>

<p align="center">
  <strong>* * *</strong>
</p>

### 3.5 Enable Mouse Integration **(macOS only)**

If you are using macOS, you will need an extra step to enable mouse integration.

<details>
<summary><b>Click to expand</b></summary>

To enable mouse integration on macOS, open your terminal and run the following command:

```bash
edit-select setup-ax
```

then grant Accessibility permission for your terminal application in **System Settings → Privacy & Security → Accessibility**.

> Enable the toggle for the terminal application(s) you are running (e.g., **iTerm2**, **WezTerm**, **Ghostty**, **Kitty**, ...).

Please grant permission for all terminal applications you use with the plugin.

Then restart your terminal. You may need to restart your device for the full integration to take effect.

Without Accessibility permission, mouse operations behave unexpectedly on macOS.

Keyboard selection and keyboard-driven clipboard operations continue to work, so the permission is not needed if you only use keyboard selection or do not want mouse integration.

If you don't want [mouse replacement](#mouse-selection-integrated-features), you can disable it from the configuration wizard. But Accessibility permission is still recommended for the best experience and for the plugin to work as expected (e.g. **copying** text selected with the mouse).

**Terminal Compatibility for Mouse Selection**

- Terminals with Accessibility (AX) support provide the most reliable mouse integration. In this category, **iTerm2** and **Kitty** are the recommended options — both expose the system Accessibility `kAXSelectedTextAttribute`.

- Other GPU-based terminals (Alacritty, WezTerm, Ghostty) generally do not expose
  `kAXSelectedTextAttribute`, so mouse integration for them uses a reactive `Cmd+C` mechanism. Behavior may therefore vary with the terminal version and runtime conditions, and mouse
  integration for these terminals is currently experimental.
  These terminals still require Accessibility permission for the plugin to handle mouse selections using `CGEventTap`.


##### tmux on macOS

If clipboard operations fail inside tmux, install `reattach-to-user-namespace`:

```bash
brew install reattach-to-user-namespace
```

</details>

<p align="center">
  <strong>────────── ✦ ──────────</strong>
</p>

### 4. Customize Settings **(Optional)**

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

> [!TIP]
> For a full command list (including maintenance and platform-specific commands), see [Commands Reference](#commands-reference).

The wizard provides:

1. **Mouse Replacement** — Enable/disable mouse selection integration
2. **Instant Cut** — Optional Ctrl+X prefix-pruning for instant mouse-selection cut
3. **Key Bindings** — Customize Copy, Cut, Paste, Select All, Undo, Redo, and Word Navigation shortcuts
4. **View Full Configuration** — See current settings
5. **Reset to Defaults** — Restore factory settings
6. **Exit Wizard** — Close the wizard

- All changes are saved to `~/.config/zsh-edit-select/config` and persist across sessions. You can also view or edit this file manually at any time.

**Click on any of the following sections to expand it:**

<details>
<summary><h3> Mouse Replacement Modes </h3></summary>

Configure how the plugin handles mouse selections. See [Mouse Replacement](#mouse-replacement) for a description of what the toggle controls (cut, delete, type-to-replace, paste-to-replace on mouse selections, plus copy which always works).

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

---

</details>

<details>
<summary><h3>Instant Cut (Mouse Selection Cut)</h3></summary>

Instant Cut is an optional compatibility/performance toggle focused on **mouse-selection cut when the cut key is Ctrl+X**.

- **Why this option exists:** In ZLE/Emacs keymaps, `Ctrl+X` acts as a prefix key for multi-key chords (for example, `Ctrl+X Ctrl+E`). During a mouse-selection cut, ZLE may briefly wait to determine whether another key will follow before executing the cut action, which introduces a delay of a few milliseconds. That latency is usually unnoticeable in most workflows, but if you don't use multi-key chords and prefer instant cuts, this option removes it.
- **Keyboard-selection cut:** Already instant. This option is not required for keyboard-selection cut behavior.
- **Default:** Disabled (safe default that preserves all existing prefix chords).
- **When enabled:** The plugin prunes bindings that share the cut-key prefix, so `Ctrl+X` cut dispatches immediately for mouse selections.
- **Trade-off:** Prefix chords that begin with the cut key (for example, `Ctrl+X Ctrl+E`) are unavailable while the option is enabled. You can disable it again at any time and you will regain the ability to use the prefix chords after you restart your terminal.
- **Only relevant for prefix keys such as Ctrl+X:** If you remap Cut to a non-prefix escape sequence such as `Ctrl+Shift+X` (`^[[88;6u`), the cut is already instant without enabling Instant Cut, because ZLE does not need prefix disambiguation for that sequence.
- **Scope:** This setting affects mouse-selection cut behavior only; keyboard-selection cut is unchanged.

Enable or disable it from the wizard:

```bash
edit-select config  # → Option 2: Instant Cut
```

---

</details>

<details>
<summary><h3>Custom/Manual Keybinding Notes (Terminal Configuration)</h3></summary>

> **⚠️ Important:** When using custom keybindings (especially with Shift modifiers), you may need to configure
> your terminal emulator to send the correct escape sequences.

**To find the escape sequence for any key combination:**

1. Run `cat` (without arguments) in your terminal
2. Press the key combination
3. The terminal will display the escape sequence
4. Use this sequence in your configuration

For example, if you want to use `Ctrl + Shift + X` for cut, add the following to your terminal dotfile:

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

---

</details>

---
---

## Popular Terminals Configurations

> The current documentation covers Kitty, WezTerm, Ghostty, Foot (Linux only), iTerm2 (macOS only), VS Code Terminal, and Windows Terminal (WSL only).
>
> Instructions for **tmux** integration are also included.

> [Open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) if you need help with a terminal
> that is not covered.

This section provides complete, ready-to-paste configurations for each supported terminal. Find your terminal below, then expand the section for your operating system to get the full config block to merge into your own.

**CRITICAL:** While adding these mappings, remove or comment out any existing conflicting bindings.

> [!IMPORTANT]
> Comments inside each configuration block provide inline guidance. Some options are included but commented out; uncomment them to switch to an alternative behavior.
>
> For example, by default the copy shortcut is `Ctrl+Shift+C` on Linux (the traditional terminal convention, where `Ctrl+C` sends an interrupt signal). If you prefer **GUI-style** behavior where `Ctrl+C` **copies** and `Ctrl+Shift+C` sends the interrupt, follow the instructions in the comments to switch to that option.

> [!TIP]
> A terminal with shell integration (such as Kitty or Ghostty) is recommended: it lets you move the cursor
> using a single mouse click with no extra keys pressed. And it also enables clearing a mouse selection by clicking to behave natively for Linux (see the [dedicated section](#clearing-a-selection-by-clicking) at [Mouse Selection Integrated Features](#mouse-selection-integrated-features) for more details).
>
> Shell integration is usually enabled by default. If it is not enabled for you, it is recommended to enable it for the best experience.

**Note (macOS):** Almost all macOS terminals intercept `Cmd` keys by default, so explicit terminal configuration is required for them. The Ctrl-based shortcuts work on macOS without any terminal configuration.

<details>
<summary><b>How to Find Escape Sequences (Optional: For Manual Customization)</b></summary>

**To find the escape sequence for any key combination:**

1. Run `cat` (without arguments) in your terminal
2. Press the key combination
3. The terminal will display the escape sequence
4. Use this sequence in your configuration

</details>

---

### Terminals Configurations:

#### Windows Terminal (WSL only)

<details> <summary> <b> Click to expand </b></summary>

To use the reversed mode (copy with Ctrl+C and interrupt Ctrl+Shift+C) in Windows Terminal, you will need to edit the Windows Terminal settings. Expand the following guide to learn how to access the settings file:

<details>
<summary><b>How to Open Windows Terminal settings.json </b></summary>

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
<summary><b>Disable copyOnSelect for optimal mouse integration</b></summary>

By default, `"copyOnSelect"` is set to `false`. If you previously enabled `"copyOnSelect"`, it is recommended that you disable it for the best mouse integration experience. To verify this setting, search for the following entry in your terminal settings:

```json
"copyOnSelect": false
```

</details>

<details>
<summary><b>Reversed Copy Mode (Ctrl+C copy, Ctrl+Shift+C interrupt)</b></summary>

To use `Ctrl+Shift+C` for interrupt (SIGINT), add one entry to `"actions"` and one to `"keybindings"` in the Windows Terminal settings.json:

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

Then add the following to your `~/.zshrc` file on the Linux side:

```zsh
stty intr ^]
```

Save `settings.json`, restart the profile, and run `source ~/.zshrc`. `Ctrl+Shift+C` will now send `0x1D` (`Ctrl+]`), which `stty` will treat as an interrupt signal.

</details>

<details>
<summary><b> How to Verify Ctrl+C is set to Copy </b></summary>

Windows Terminal defaults to `Ctrl+C` for copy. If you have ever changed it, add (or update) the
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

**Note:** Mouse integration is currently most compatible with Windows Terminal and the VS Code terminal. If you use another terminal or encounter issues, you can **disable mouse integration and restore your terminal's default behavior** by turning off mouse replacement through the configuration wizard (`edit-select config`), then choosing the first option to configure mouse behavior.

> Known Limitation in VS Code: With Mouse integration enabled, **Extremely** fast VS Code scrollback drags may still show a very small startup offset due to the currently unavoidable shell/helper handoff latency (planned to be optimized in future releases).

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
        -- Skip the signal while a full-screen application (vim, nano, less)
        -- owns the alternate screen; it would arrive there as raw input.
        if sel ~= "" and not pane:is_alt_screen_active() then
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
      -- Skip the signal while a full-screen application (vim, nano, less)
      -- owns the alternate screen; it would arrive there as raw input.
      if sel ~= "" and not pane:is_alt_screen_active() then
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
<summary><b>Resolving the two placeholder paths in the config (Click to expand)</b></summary>

>

Each of the two configuration blocks below ends with a click-to-deselect entry (a `[[mouse.bindings]]` block in TOML, a `mouse_bindings:` entry in YAML). That entry is needed **only if you want Mouse Replacement enabled**; if you keep Mouse Replacement disabled, you can skip it entirely. In both formats it contains the same two placeholders, which you must replace with absolute paths for your system. Pick the format that matches your Alacritty version (use TOML if you are unsure), and apply the substitution to whichever block you use.

**The one command that resolves both placeholders:**


```zsh
print -r -- "<plugin-root> = ${ZES_IMPL_PATH:h}"
print -r -- "<cache-dir>   = ${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${UID}"
```

Note: Please ensure that the plugin is installed and loaded and that you are in a Zsh session before running these commands.

<p align="center">
  <strong>✦ ───────── ✦</strong>
</p>


In most cases, the above commands will work for you.
If you face any issues with the above commands, you can also locate the plugin root and cache directory manually as follows:

`ZES_IMPL_PATH` only exists once the plugin has been sourced. If the first command prints just `.` or an empty value, the plugin isn't loaded in that shell — open a fresh terminal, or locate the plugin directly:

To print your `<plugin-root>`:
```zsh
# Find the directory that holds zsh-edit-select.plugin.zsh anywhere under $HOME
print -rl -- ${^${(f)"$(find "$HOME" -name zsh-edit-select.plugin.zsh -not -path '*/before-*' 2>/dev/null)"}:h}
```

POSIX-sh equivalent, if you are not in Zsh:
```sh
find "$HOME" -name zsh-edit-select.plugin.zsh 2>/dev/null | while read -r f; do dirname "$f"; done
```

For `<cache-dir>`, the plugin uses `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-<your-uid>`, so to print it run:
```sh
printf '%s/zsh-edit-select-%s\n' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" "$(id -u)"
```

> **Tip — automatic configuration:** `edit-select integrate` can write the mouse-binding block into your `alacritty.toml` / `alacritty.yml` for you, with the correct absolute paths already resolved — it detects your plugin root the same way, so it works with any plugin manager. This is convenient for a fresh install, but **not yet recommended if you already have a complex config file** — review the diff afterward. For manual setup, use the commands above.

---

</details>

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

# ── zsh-edit-select click-to-deselect ────────────────────────
# On every Left-press in a non-alt-screen pane a tiny helper clears the
# compositor's selection through the plugin's own agent.  The running
# daemon notices the change and signals the shell-side hook to forget
# the stale selection, so the next keystroke inserts normally instead
# of replacing an invisible selection.
#
# Replace <plugin-root> and <cache-dir> with absolute paths on your
# system — see "Resolving the two placeholder paths in the config"
# above the TOML/YAML blocks (or run `edit-select integrate` to have
# the installer wire this in automatically with the correct paths).
[[mouse.bindings]]
mouse = "Left"
mode = "~Alt"
command = { program = "<plugin-root>/assets/helpers/zes-alacritty-click-clear.sh", args = ["<cache-dir>"] }
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
    - { key: End, mods: Shift, action: ReceiveChar }

# ── zsh-edit-select click-to-deselect ─────────────────────────
# Mirror of the TOML block above.  `mouse_bindings` is its own top-level key,
# so keep it flush with the left margin: indented under `key_bindings:` the
# file stops being valid YAML and Alacritty discards the whole config.
# Replace <plugin-root> and <cache-dir> with absolute paths on your system —
# see "Resolving the two placeholder paths in the config" above the TOML/YAML
# blocks (or run `edit-select integrate` for automatic setup).
mouse_bindings:
    - {
          mouse: Left,
          mode: "~Alt",
          command:
              {
                  program: "<plugin-root>/assets/helpers/zes-alacritty-click-clear.sh",
                  args: ["<cache-dir>"],
              },
      }
```

> If your `alacritty.yml` already has a top-level `key_bindings:` or
> `mouse_bindings:` key, merge the entries into the list you already have
> instead of adding a second key with the same name — a duplicate top-level key
> makes Alacritty reject the entire file and fall back to its built-in defaults.

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

VS Code intercepts `Cmd+C` and `Cmd+A` for its own editor actions. The bindings below are scoped to `terminalFocus` so they only apply when the integrated terminal is active.

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
        "when": "terminalFocus && isMac && !terminalTextSelected"
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

#### Foot _(Linux only)_

<details>
<summary><b>Linux configuration</b></summary>

Foot uses `[key-bindings]` to disable built-in actions and `[text-bindings]` to send custom escape sequences to the shell. Two built-in bindings must be unbound before adding the plugin's sequences:

- `clipboard-copy` (defaults to `Control+Shift+c`) — must be unbound so the copy escape sequence reaches the shell instead of triggering Foot's clipboard action.
- `prompt-prev` (defaults to `Control+Shift+z`) — must be unbound so the undo escape sequence reaches the shell instead of triggering Foot's prompt navigation.

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

#### iTerm2 _(macOS only)_

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

**Editing Shortcuts**

| Keyboard Shortcut | Action               | Value      | Description |
| ----------------- | -------------------- | ---------- | ----------- |
| `Cmd+A`           | Send Escape Sequence | `[97;9u`   | Select All  |
| `Cmd+C`           | Send Escape Sequence | `[99;9u`   | Copy        |
| `Cmd+X`           | Send Escape Sequence | `[120;9u`  | Cut         |
| `Cmd+Z`           | Send Escape Sequence | `[122;9u`  | Undo        |
| `Cmd+Shift+Z`     | Send Escape Sequence | `[122;10u` | Redo        |

**Navigation Keys**

| Keyboard Shortcut | Action               | Value   | Description        |
| ----------------- | -------------------- | ------- | ------------------ |
| `Cmd+←`           | Send Escape Sequence | `[1;9D` | Move to line start |
| `Cmd+→`           | Send Escape Sequence | `[1;9C` | Move to line end   |

**Selection Shortcuts**

Basic `Shift+Arrow` keys (`↑ ↓ ← →`) pass through to the shell natively in iTerm2 — no configuration is needed for character-by-character and line-by-line selection.

Add the following for the macOS-specific extended selection combinations:

| Keyboard Shortcut | Action               | Value    | Description            |
| ----------------- | -------------------- | -------- | ---------------------- |
| `Cmd+Shift+←`     | Send Escape Sequence | `[1;10D` | Select to line start   |
| `Cmd+Shift+→`     | Send Escape Sequence | `[1;10C` | Select to line end     |
| `Cmd+Shift+↑`     | Send Escape Sequence | `[1;10A` | Select to buffer start |
| `Cmd+Shift+↓`     | Send Escape Sequence | `[1;10B` | Select to buffer end   |

---

> **iTerm2 recommended setting:** iTerm2 has a built-in setting, **"Copy to pasteboard on selection"** (Settings → General → Selection), that is **enabled by default**. When it is on, every mouse drag in iTerm2 automatically copies the selected text to the clipboard. This does not affect the correctness of the implementation — but it means that every mouse drag overwrites your clipboard, even when you only meant to highlight text in order to replace it with a keystroke or something that was previously copied. To avoid that, disable the setting: **Settings → General → Selection → uncheck "Copy to pasteboard on selection"** (labeled "Copy to clipboard on selection" in some versions). With it disabled, mouse highlights are handled exclusively by the plugin's Accessibility path and never touch the clipboard.

</details>

---

#### Tmux integration & reversed copy mode (Linux)

<details> <summary> <b> Click to expand </b></summary>

If you use tmux and run the plugin in **reversed copy mode** (`Ctrl+C` copies, `Ctrl+Shift+C` interrupts), add
this block to `~/.tmux.conf`:

```tmux
set -g default-terminal tmux-256color
set -g xterm-keys on
set -g extended-keys on
set -as terminal-overrides ",*:extkeys"

# Remove any existing root bindings
unbind -n C-c
unbind -n C-S-c

# Hard-forward keys to pane:
# Ctrl+C -> plugin copy sequence
bind -n C-c send-keys C-c

# Ctrl+Shift+C -> real SIGINT (^C)
bind -n C-S-c send-keys -l "\033[67;6u"
```

And reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

</details>

---

#### Optional: Ctrl Key Remaps _(macOS only)_

These are optional remaps for users who prefer `Ctrl` key fallbacks over `Cmd`. Neither is required for normal plugin operation — configure only what you need.

<details>
<summary><b>macOS configuration</b></summary>

### Ctrl+C → Copy (CSI-u approach)

If you want to use `Ctrl+C` for copy instead of `Cmd+C`, configure your terminal to send the CSI-u sequence for `Ctrl+C` and move the interrupt signal to `Ctrl+Shift+C`. Then in the plugin wizard (`edit-select config` → Key Bindings → Copy), choose **"Ctrl+C via CSI-u"**.

**iTerm2** — Add in **Preferences → Profiles → Keys → Key Mappings**:

| Keyboard Shortcut | Action               | Value    | Notes                       |
| ----------------- | -------------------- | -------- | --------------------------- |
| `Ctrl+C`          | Send Escape Sequence | `[67;6u` | Reassigns Ctrl+C to Copy    |
| `Ctrl+Shift+C`    | Send Hex Code        | `0x03`   | Restores interrupt (SIGINT) |

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

| Keyboard Shortcut | Action               | Value    |
| ----------------- | -------------------- | -------- |
| `Ctrl+Shift+Z`    | Send Escape Sequence | `[90;6u` |

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

## SSH Support

If you are SSH-ing into a remote machine — Linux, WSL, or macOS — the plugin **automatically detects the SSH environment** and switches clipboard operations to use **OSC 52**, a terminal escape sequence that tunnels clipboard writes back to your local terminal through the SSH connection, with no extra tools or manual setup. The same detection also enables **cross-platform key remapping** so your local keyboard shortcuts keep working on the remote host — see the **macOS to Linux** and **Linux to macOS** subsections below.

<details>
<summary><b>How It Works</b></summary>

<br>

When **any** of `$SSH_CLIENT`, `$SSH_TTY`, or `$SSH_CONNECTION` is set (standard variables present in any SSH session), the plugin replaces its native clipboard backend with an OSC 52 write. This means:

- **Copy / Cut** — text is written directly to your **local** clipboard via OSC 52 (tunnelled through the SSH connection back to the terminal running on your local machine).
- **Paste** — must be triggered using your terminal's **native paste keybinding** (e.g. `Cmd+V` in iTerm2/Ghostty, `Ctrl+V` in Windows Terminal/Alacritty). The plugin cannot read the clipboard back over SSH — paste is intentionally left to the terminal so the local clipboard content is inserted via bracketed paste.
- **Text selection** (Shift+Arrow etc.) — works identically to a local session.
- **Mouse selection** — on a headless box (no display server) the background daemon does not start, so mouse selection is disabled automatically.

> **Note for WSL users:** If you SSH into a WSL machine, copy/cut/paste target the clipboard of your **local** machine (the one you are SSH-ing from) rather than the WSL host's Windows clipboard. This is the expected SSH behavior — the plugin follows your SSH session, not the remote desktop.

No `~/.zshrc` changes are needed on the remote box. Just install the plugin normally.

</details>

<details>
<summary><b>Opt Out</b></summary>

<br>

If you do not want the automatic SSH behavior (e.g. you are SSH-ing between Linux machines and have `xclip` available via X11 forwarding), add this to your `~/.zshrc` on the remote machine **before** the plugin loads:

```zsh
ZES_SSH_CLIPBOARD=0
```

</details>

<details>
<summary><b>Terminal Requirements</b></summary>

<br>

Your terminal must support OSC 52 clipboard writes and have clipboard access enabled. Most modern terminals support this out of the box.

| Terminal         | OSC 52 write | Notes                                                                                    |
| ---------------- | ------------ | ---------------------------------------------------------------------------------------- |
| iTerm2           | ✅           | Enable "Applications in terminal may access clipboard" in Settings → General → Selection |
| Ghostty          | ✅           | Add `clipboard-write = allow` to `~/.config/ghostty/config`                              |
| Kitty            | ✅           | Works out of the box                                                                     |
| WezTerm          | ✅           | Works out of the box                                                                     |
| Alacritty        | ✅           | Works out of the box                                                                     |
| Windows Terminal | ✅           | Works out of the box; `Ctrl+V` pastes natively                                           |
| Terminal.app     | ✅           | Works out of the box                                                                     |

**tmux / GNU Screen:** If you are using tmux or GNU Screen inside your SSH session, the plugin automatically wraps OSC 52 writes in the correct DCS passthrough sequence — no extra configuration needed. For tmux versions older than 3.3a, you may also need to add `set -g allow-passthrough on` to your `~/.tmux.conf`.

A paste keybinding must be configured at the terminal level so that your local clipboard content can be inserted into the SSH session. If your terminal already has one (e.g. Windows Terminal's `Ctrl+V`, or macOS terminals' `Cmd+V`), no additional setup is needed.

If you need to add one manually:

- **Kitty:** add `map ctrl+v paste_from_clipboard` to `~/.config/kitty/kitty.conf`
- **Ghostty:** add `keybind = ctrl+v=paste_from_clipboard` to `~/.config/ghostty/config`

**Note:** If possible, it is recommended to configure the terminal on both the host and the guest according to the appropriate section in [Popular Terminal Configurations](#popular-terminals-configurations), and install the plugin on both systems. This helps ensure that everything works correctly and minimizes the chance of encountering any issues.

</details>

<details>
<summary><b>macOS to Linux — Cmd/Option Key Auto-Remapping</b></summary>

<br>

If you are SSH-ing **from** a macOS terminal (iTerm2, Ghostty, Kitty, WezTerm, Alacritty) **into** a Linux or WSL box, the plugin **automatically maps your macOS Cmd/Option key sequences** to the corresponding Linux/WSL actions. No extra configuration is needed on the remote host — `Cmd+C` copies, `Cmd+X` cuts, `Cmd+A` selects all, `Cmd+Z` undoes, `Option+Arrow` moves by word, etc.

**Prerequisite:** Your macOS terminal must be configured to forward Cmd key sequences as CSI-u escape codes (e.g., `Cmd+C` → `\e[99;9u`). If you already configured your terminal for the plugin locally on macOS (following the [Popular Terminals Configurations](#popular-terminals-configurations) section above), those same settings will work transparently over SSH.

> **Note:** `Cmd+V` (Paste) is handled by your macOS terminal natively — it pastes directly into the SSH session. The plugin does not intercept it.

</details>

<details>
<summary><b>Linux to macOS — Ctrl Key Auto-Remapping</b></summary>

<br>

If you are SSH-ing **from** a Linux or WSL terminal (gnome-terminal, Kitty, WezTerm, Ghostty, Alacritty, Windows Terminal) **into** a macOS box, the plugin **automatically maps your Linux keys** to the corresponding macOS actions, so the remote macOS session behaves exactly like your local Linux one. No extra configuration is needed on the remote host:

| Key                                  | Action                          |
| ------------------------------------ | ------------------------------- |
| `Ctrl+Shift+C`                       | Copy selection                  |
| `Ctrl+X`                             | Cut selection                   |
| `Ctrl+A`                             | Select all                      |
| `Ctrl+Z`                             | Undo                            |
| `Ctrl+Shift+Z`                       | Redo                            |
| `Ctrl+←` / `Ctrl+→`                  | Move by word                    |
| `Ctrl+Shift+←` / `Ctrl+Shift+→`      | Extend selection by word        |
| `Ctrl+Shift+Home` / `Ctrl+Shift+End` | Extend selection to start / end |
| `Home` / `End`                       | Move to line start / end        |

These are **additive** bindings — they do not overwrite the macOS `Cmd` CSI-u defaults, so a local macOS user pressing `Cmd+C` still copies as usual. The remapping engages only when SSH mode is detected (`SSH_CLIENT`/`SSH_TTY`/`SSH_CONNECTION` set), so it adds **zero overhead** on non-SSH sessions.

**Notes on 2 special keys**

| Key      | Why                                                                                                                                                                                                                                                                                                | What to use instead                                                                                                                                                                                                                                                                                                                                                          |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Ctrl+C` | If `Ctrl+C` does not copy for you, the terminal driver is most likely claiming it as the interrupt signal (`SIGINT`) before the shell ever sees it and you have not set it up as a copy key already using the [Popular Terminals Configurations](#popular-terminals-configurations) section. | Ensure your terminal is configured according to [Popular Terminals Configurations](#popular-terminals-configurations); that alone should resolve it. If the issue persists, remap the interrupt with `stty intr ^]` in your `~/.zshrc` on the macOS host — see **Windows Terminal — Enable Ctrl+C Copy** below for the same approach on the Linux side. |
| `Ctrl+V` | Paste cannot work over SSH — the plugin has no way to read the remote clipboard back through the connection.                                                                                                                                                                                        | Use your terminal's native paste.                                                                                                                                                                                                                                                                                                                                            |

</details>

<details>
<summary><b>Windows Terminal — Enable Ctrl+C Copy</b></summary>

<br>

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

> **Warning:** This tells the Linux box to use `Ctrl+]` for interrupts instead of `Ctrl+C`. `Ctrl+C` will now copy text, and **`Ctrl+]` will interrupt programs**. To use `Ctrl+Shift+C` for interrupt instead, expand the following section.

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

</details>

<details>
<summary><b>Terminal rendering issues over SSH</b></summary>

<br>

If your terminal uses a custom `TERM` value (e.g. `xterm-ghostty` or `xterm-kitty`) that is not available on the remote machine, you may see corrupted output, broken colors, or `clear` not working correctly.

You can fix this in one of the following ways:

**Option 1:** Fall back to `xterm-256color` on the remote machine.

```bash
echo '[[ "$TERM" == "xterm-ghostty" ]] && export TERM=xterm-256color' >> ~/.zshrc
source ~/.zshrc
```

Replace `xterm-ghostty` with your terminal's `TERM` value.

**Option 2:** Override `TERM` for a single SSH session.

```bash
TERM=xterm-256color ssh user@host
```

**Option 3:** Override `TERM` for all SSH sessions by adding the following to your local `~/.ssh/config`:

```sshconfig
Host your-host
    SetEnv TERM=xterm-256color
```

**Option 4 (Recommended):** Install your terminal's terminfo entry on the remote machine to preserve all terminal features.

</details>

<details>
<summary><b>iTerm2 — Clipboard Access</b></summary>

<br>

Navigate to **iTerm2 → Settings → General → Selection**, ensure **"Applications in terminal may access clipboard"** is checked, and set **"Allow sending of clipboard contents?"** to **Always**.

</details>

---

## Commands Reference

| Command                    | Description                                                                                                                                                 |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `edit-select config`       | Launch the interactive configuration wizard to configure mouse behavior and keybindings.                                                                    |
| `edit-select integrate`    | Run installer terminal-integration mode to configure supported terminal keybindings.                                                                        |
| `edit-select conflicts`    | Run installer conflict-scan mode and print remediation guidance for detected overlaps.                                                                      |
| `edit-select update`       | Pull latest plugin changes from git, then fetch agent binaries from GitHub workflow-published releases and re-initialize agent runtime.                     |
| `edit-select build`        | Build/rebuild agent binaries from source for the active runtime implementation, then re-initialize runtime agents.                                          |
| `edit-select uninstall`    | Run uninstall mode with prompts to remove plugin files and clean integration/config entries.                                                                |
| `edit-select setup-ax`     | macOS only: request Accessibility permission required for mouse integration.                                                                                |
| `edit-select setup-hooks`  | Install git hooks so you're reminded to run `edit-select update` after a `git pull`. Set up automatically on install — you rarely need to run this by hand. |
| `edit-select remove-hooks` | Remove the git hooks installed by `edit-select setup-hooks`.                                                                                                |

**Note on Updates:** Use `edit-select update` command to update the plugin and agents, rather than running a simple `pull` manually or via the plugin manager. The `update` command re-initializes the agent runtime to ensure all agent binaries are refreshed from the latest releases.

**Automatic update notifications:** After you install, a lightweight git hook is set up for you automatically — the first time you open a shell after installing. After an interactive `git pull` (directly or through a plugin manager that executes Git hooks), the hook refreshes the agent binaries and bytecode cache, then prompts you to run `edit-select update` and offers to run it. A detached or automated pull without a controlling terminal cannot run that interactive refresh; it prints a reminder to run `edit-select update` instead. This reminder fires only on an actual pull, never during normal shell startup, so it adds zero cost to opening a terminal. You can manage it yourself with `edit-select setup-hooks` and `edit-select remove-hooks`. See the [Troubleshooting](#troubleshooting) section if you don't see the notification after a pull.

**Note on `edit-select integrate`:** This mode is **experimental** and not recommended for complex setups with heavily customized terminal config files. It may interfere with existing keybinding configurations. Use the [Popular Terminals Configurations](#popular-terminals-configurations) section instead.

**Note on `edit-select conflicts`:** This command should be treated as an indicator and a helper tool for detecting **potential** conflicts in your configuration. However, it may produce false positives, especially in configuration files with more structurally complex formats, such as `wezterm.lua`.

## Default Key Bindings Reference

### Linux

#### Navigation Keys

| Key Combination | Action                     |
| --------------- | -------------------------- |
| **Ctrl + ←**    | Move cursor one word left  |
| **Ctrl + →**    | Move cursor one word right |
| **Home**        | Move to line start         |
| **End**         | Move to line end           |

#### Selection Keys

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

#### Editing Keys

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

### macOS

#### Navigation Keys

| Key Combination | Action                     |
| --------------- | -------------------------- |
| **Option + ←**  | Move cursor one word left  |
| **Option + →**  | Move cursor one word right |
| **Cmd + ←**     | Move to line start         |
| **Cmd + →**     | Move to line end           |

#### Selection Keys

| Key Combination        | Action                     |
| ---------------------- | -------------------------- |
| **Shift + ←**          | Select one character left  |
| **Shift + →**          | Select one character right |
| **Shift + ↑**          | Select one line up         |
| **Shift + ↓**          | Select one line down       |
| **Cmd + Shift + ←**    | Select to line start       |
| **Cmd + Shift + →**    | Select to line end         |
| **Option + Shift + ←** | Select to word start       |
| **Option + Shift + →** | Select to word end         |
| **Cmd + Shift + ↑**    | Select to buffer start     |
| **Cmd + Shift + ↓**    | Select to buffer end       |
| **Cmd + A**            | Select all text            |

#### Editing Keys

| Key Combination      | Action                            |
| -------------------- | --------------------------------- |
| **Cmd + C**          | Copy selected text                |
| **Cmd + X**          | Cut selected text                 |
| **Cmd + V**          | Paste (replaces selection if any) |
| **Cmd + Z**          | Undo last edit                    |
| **Cmd + Shift + Z**  | Redo last undone edit             |
| **Delete/Backspace** | Delete selected text              |
| **Any character**    | Replace selected text if any      |

---

## Troubleshooting

If you encounter any issues, first run `edit-select update`. If the problem persists and none of the cases below apply, please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with a clear description of your setup and environment.

<details>
<summary><b>No update notification after git pull</b></summary>

This can happen in a few scenarios:

- **Plugin installed on a DrvFs mount (WSL):** If your plugin directory is on a Windows-mounted filesystem (e.g. `/mnt/c/...`) without metadata support, git hooks may not fire because the executable bit cannot be set. Run `edit-select update` manually after pulls, or install the plugin to the native Linux filesystem (e.g. `~/.local/share/zsh/plugins/zsh-edit-select`).

- **Using Sheldon:** Sheldon uses libgit2 (not the git CLI) for updates, which does not execute git hooks. Run `edit-select update` manually after `sheldon lock --update`.

- **Detached or automated pull:** A pull without a controlling terminal cannot run the interactive provisioning and prompt. The hook prints a reminder instead; run `edit-select update` manually afterward.

- **core.hooksPath already set:** If you already use `core.hooksPath` for another tool, our hooks cannot be installed automatically (the plugin never overwrites an existing `core.hooksPath` value). In that case you simply stay on the regular startup path — the full agent/runtime checks run on each shell start, which still works correctly. To opt in to the hooks, either place `post-merge` and `post-rewrite` hooks (calling our `hooks/zes-post-pull`) into your existing hooks directory, or temporarily clear `core.hooksPath` and run `edit-select setup-hooks`; the marker will then be written and the fast path will resume.

</details>

<details>
<summary><b>Shift selection doesn't work</b></summary>

**Solution:** Configure your terminal to pass Shift key sequences. See [Popular Terminals Configurations](#popular-terminals-configurations).

**Verify:** Run `cat` and press Shift+Left. You should see an escape sequence like `^[[1;2D`.

</details>

<details>
<summary><b>Mouse replacement not working</b></summary>

**Solution:**

1. Check whether mouse replacement is enabled: `edit-select config` → View Configuration
2. Ensure your terminal supports mouse selection (most do)
3. Try selecting text with your mouse, then typing — it should replace the selection

If this does not work for you, it is usually due to platform limitations or compatibility issues with the
PRIMARY selection. Please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with a clear description of your setup and environment.

</details>

<details>
<summary><b>Ctrl+C / Cmd+C doesn't copy</b></summary>

**Solution:** On Windows/Linux, configure your terminal to remap Ctrl+C. See the
[Popular Terminals Configurations](#popular-terminals-configurations) section.
On macOS, verify that CSI-u / kitty keyboard protocol support is enabled in your terminal so Cmd+C can be used. See [Popular Terminals Configurations](#popular-terminals-configurations).

**Alternative:** Use Ctrl+Shift+C to copy, configure a fallback via `edit-select config` for macOS Terminal.app, set a custom keybinding with `edit-select config`, or
use the "Without Terminal Remapping" method if your terminal does not support key remapping.

</details>

<details>
<summary><b>Configuration wizard doesn't launch</b></summary>

**Symptoms:** Running `edit-select config` shows a "file not found" error.

**Solution:**

1. Check that the plugin was installed correctly
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
forces the Delete key back to the default handler, such as:

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
switching to another pane causes typed text to unexpectedly replace the text previously selected in the
other pane.

**Solution:** Enable focus events in tmux. The plugin uses terminal focus reporting (DECSET 1004) to
distinguish between selections made in the active pane and selections in other panes.

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
`edit-select config` → Option 1 → Disable. This preserves keyboard selection functionality while
preventing cross-pane mouse selection issues.

</details>

---

## Performance-Optimized Architecture

The plugin architecture is built around compiled native C agents that run as persistent background processes.

The system is designed with a strong focus on run-time performance, resource management efficiency, and long-term maintainability. Design decisions across the entire stack—from compilation flags and build settings to event handling, caching, and process management strategies—are made with these goals in mind.

The plugin uses native C agents to overcome the limitations of shell scripts, enabling direct interaction with display-server protocols and operating-system interfaces while providing the level of control required for efficient event handling, low latency, and minimal resource consumption.

This also makes the plugin fully self-contained with no runtime dependencies and no external tools required for operation.

<details>
<summary><b>Core Architectural Properties</b></summary>

- **Single-pass initialization** — Backend detection, agent startup, and configuration loading occur at plugin
  load time. The results are cached in shell variables and reused for the entire session.
- **Event-driven selection tracking** — X11 XFixes events, Wayland compositor events, macOS CGEventTap
  events, and Win32 clipboard-format notifications drive cache updates. Each agent blocks in its native
  event-dispatch primitive (`poll()` on Linux, `CFRunLoopRun()` on macOS, `GetMessageA` in the WSL
  helper) and consumes no CPU between events.
- **Compiled native agents** — Direct system calls compiled with aggressive optimization flags
  (`-O3 -march=native -flto -fipa-pta` on Linux; `-Os -fobjc-arc` on macOS) and link-time dead code
  elimination; no interpreter overhead.
- **RAM-backed cache** — The daemon's cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions),
  with `TMPDIR` or `/tmp` as the shell-side fallback. The agent's short-lived modes (`--oneshot`,
  `--copy-clipboard`, `--clear-primary`) do their own resolution when invoked without an explicit cache
  directory: `XDG_RUNTIME_DIR` → `/dev/shm` → `$HOME/.cache` on Linux, `$TMPDIR` → `/tmp` on macOS. On
  standard systemd-based systems, all cache I/O remains in memory. The cache directory is tightened to
  `0700` at agent startup (or by the daemon entry point on macOS), so the cached `primary`/`seq` files
  (mode `0644`) are only accessible from their owner — other users on a shared `/tmp` or `/dev/shm`
  cannot traverse into the per-UID cache to read selected text.
- **Wayland protocol path** — Native Wayland uses direct compositor protocols for PRIMARY selection and CLIPBOARD, avoiding `wl-copy`/`wl-paste` subprocesses and keeping clipboard operations inside the persistent agent process.
- **Graceful fallback** — If the compiled agents are unavailable, the plugin falls back to standard
  platform clipboard tools transparently: `xclip` (X11), `wl-paste`/`wl-copy` (Wayland),
  `pbpaste`/`pbcopy` (macOS), `powershell.exe`/`clip.exe` (WSL). No functionality is lost.

<details>
<summary>WSL-Specific Architecture</summary>

The plugin provides tailored support for Windows Subsystem for Linux (WSL) with seamless interoperability between the Linux shell and Windows clipboard.

**Platform Detection**

WSL detection occurs at plugin load time through inspection of environment variables set by the WSL runtime:

- `WSL_DISTRO_NAME` or `WSL_INTEROP` — uniformly present in both WSL1 and WSL2
- Detection takes priority over X11/Wayland detection, ensuring the optimized WSL implementation is used
- A unified detection mechanism ensures the plugin works seamlessly across both WSL versions

**Dual-Generation Support**

The plugin supports both WSL1 and WSL2 through a single implementation path:

- **WSL2 (Current)** — Uses Wayland clipboard interoperability for native Windows clipboard access
- **WSL1 (Legacy)** — Falls back to the Windows-side clipboard helper for clipboard operations
- A tailored implementation at `impl-wsl/tailored-variants/impl-wayland-wsl/` provides consistent mouse tracking behavior, atomic scrollback delegation to the native Windows Terminal host, and clipboard integration across both generations

**Atomic Scrollback Delegation**

A key WSL optimization is **Atomic Scrollback Delegation**. In typical terminal applications, enabling mouse reporting confines mouse drags to the shell's buffer. The plugin overcomes this limitation by seamlessly delegating active mouse drags that leave the editor buffer directly to the native Windows Terminal host. Low-level synthetic mouse hooks via `zes-wsl-clipboard-helper.exe` ensure drags in the scrollback buffer feel completely native without latency or "sticking."

**Build Artifacts and Fallback Mechanism**

The implementation uses a tiered artifact strategy:

- **Primary path** — `impl-wsl/tailored-variants/impl-wayland-wsl/` (optimized for WSL)
- **Legacy fallback** — `impl-wsl/zsh-edit-select-wsl.plugin.zsh` (loaded if tailored files are unavailable)
- **On-demand compilation** — Build artifacts are generated automatically during plugin initialization if missing

**Cross-Boundary Helper Process Architecture**

Clipboard operations across the WSL-to-Windows boundary are handled by two purpose-built compiled helpers:

- **`zes-wsl-clipboard-helper.exe`** — Windows-side process that reads from and writes to the Windows clipboard via the Windows API. It monitors clipboard changes, retrieves UTF-8 clipboard text, and accepts clipboard content from the Linux side via inter-process communication.

- **`zes-wsl-selection-agent`** — Linux-side daemon that communicates with the Windows helper through anonymous pipes (the helper's stdout is redirected to a `pipe()` the agent reads; on `--copy-clipboard` the agent writes to a pipe wired to the helper's stdin) and maintains a high-performance cache of clipboard contents on the native Linux filesystem. The cache resides in `XDG_RUNTIME_DIR` (in-memory tmpfs on systemd systems), with `TMPDIR` or `/tmp` as fallback, minimizing latency on keyboard events and selection operations.

**Line Protocol Across the Boundary**

The helper emits exactly four line types on its stdout — `READY` once at startup, then `CLIPBOARD <seq> <len>`
(followed by the payload bytes), `EMPTY <seq>`, and `HEARTBEAT` — and the agent parses exactly those four
prefixes, so neither side carries an orphan producer or consumer. Two properties make the stream robust:

- **No line-length desync is possible.** The helper clamps each line to 255 bytes, and both of the agent's
  read sites use a 256-byte buffer, so the longest line the helper can emit always fits whole.
- **Unknown lines are ignored rather than fatal.** A line matching none of the three message prefixes is
  skipped and the stream stays aligned, so a newer helper paired with an older agent degrades to "messages it
  understands" instead of desynchronizing. Only `CLIPBOARD` and `EMPTY` publish a cache event and advance the
  sequence counter; `HEARTBEAT` and unknown lines advance nothing.

The Windows-side sequence number in `CLIPBOARD`/`EMPTY` is framing only — the agent matches it without storing
it, keeping the published `seq` under the sole ownership of the agent's own counter.

**Transparent Clipboard Access**

Together, these helper processes provide transparent clipboard semantics: plugin operations appear instantaneous because the Linux-side cache resides in memory, while the agent synchronizes clipboard changes from Windows asynchronously in the background. This architecture eliminates the latency and complexity of spawning external utilities (`wl-paste`, `wl-copy`, or Windows-native clipboard tools) on each clipboard operation.

</details>

</details>

### Optimization Techniques

<details>
<summary><b>Startup & Initialization</b></summary>

**Backend Detection**

- Platform detection runs once at plugin load time in a fixed priority order:
    1. `ZES_FORCE_IMPL` — explicit user override (`x11`, `wayland`, `wsl`, or `macos`)
    2. macOS — `OSTYPE == darwin*` routes to the native Accessibility / NSPasteboard implementation
    3. WSL — `WSL_DISTRO_NAME` or `WSL_INTEROP` present (takes priority over X11/Wayland detection,
       ensuring the tailored WSL implementation is used in both WSL1 and WSL2)
    4. `XDG_SESSION_TYPE == wayland` — most reliable session-level indicator
    5. `WAYLAND_DISPLAY` set — present even from within tmux
    6. `DISPLAY` set — X11
    7. `wl-paste` in `PATH` — Wayland tools installed, `WAYLAND_DISPLAY` just unset
    8. Fallback to `x11` — safe default; `xclip` is widely available
- The detected backend (`x11`, `wayland`, `wsl`, or `macos`) is stored in read-only shell variables
  (`ZES_ACTIVE_IMPL`, `ZES_DETECTION_REASON`, `ZES_IMPL_PATH`) and reused for the entire session
- A two-phase load guard prevents both re-entrancy and accidental partial initialization: a temporary
  `_ZES_LOADER_LOADING` flag is set first and cleared on any validation failure (invalid `ZES_FORCE_IMPL`
  or missing implementation file) so a corrected re-source initializes normally; the read-only
  `_ZES_LOADER_LOADED` is only published after the implementation file has been validated, making
  re-entrant loads a true one-shot
- The root loader, every backend plugin, and both WSL dispatcher paths resolve their own sourced file
  path via `${${(%):-%x}:A:h}` instead of `$0`/`${0:A:h}`. With `unsetopt functionargzero`, zsh sets
  `$0` to `zsh` inside sourced files, so the old `${0:A:h}` form resolved to the caller's CWD and
  nested backend sources failed silently (masked by the loader's `source … || true`). `%x` remains
  the source filename under both option states and through adjacent `.zwc` loading, so the plugin now
  loads correctly with `NO_FUNCTION_ARGZERO` set
- The Wayland backend resolves that directory **once** into a local and reuses it for all six agent-binary
  and helper paths it builds, instead of re-running the `:A` absolute-path expansion per path. `:A` is not a
  pure string operation — it resolves symlinks, so each use is filesystem work at load time

**Lazy Backend Loading**

- Only the implementation matching the detected platform (X11, Wayland, WSL, or macOS) is sourced
- The other implementations are never loaded into memory, reducing both startup time and memory footprint
- The configuration wizard is also lazy-loaded — its file is only sourced when the user explicitly runs
  `edit-select config`
- Installer maintenance subcommands (`edit-select integrate`, `edit-select conflicts`, `edit-select update`,
  `edit-select build`, `edit-select uninstall`) are lazy-triggered and spawn the installer only when invoked,
  adding zero overhead to normal shell startup and typing paths

**Zsh Bytecode Compilation**

- Plugin files and all backend `.zsh` files are compiled to `.zwc` (Zsh wordcode bytecode) on first load via
  `zcompile -U` (`-U` is load-bearing — `zcompile` expands aliases at parse time, so without `-U` a user
  alias defined in `.zshenv` such as `alias rm='rm -iv'` would be baked into the cached bytecode and replayed
  on every subsequent load)
- The bytecode is reused on subsequent sessions, bypassing source parsing entirely
- Recompilation is guarded by the staleness predicate `[[ ! -f file.zwc || src -nt file.zwc ]]` — a bare
  existence check would never create an absent `.zwc` (in zsh, `[[ src -nt target ]]` is **false** when
  `target` is missing, the opposite of `test`/coreutils), so the `! -f` prefix is load-bearing, not just
  an equal-mtime nicety
- When the post-pull git hook is installed (the common case — see "Update notifications" under
  [Manual Installation](#manual-installation)), the loader skips its startup **binary-provisioning** sweep
  entirely: a marker file (`.zes-hooks-installed`) replaces ~5–10 per-startup stats with one, and
  `hooks/zes-post-pull` runs the same `zcompile -U` recompile after each interactive `git pull` with a
  controlling terminal. The hook's `-U` is load-bearing here, not cosmetic: the hook runs as `zsh <script>`
  from a post-merge/post-rewrite invocation, so `~/.zshenv` is sourced and any aliases there are live —
  without `-U`, an alias like `alias rm='rm -iv'` would be baked into the cached bytecode and replayed on
  every subsequent load, and on the hooks fast path that hook-written bytecode is the bytecode users
  actually run. Detached or automated pulls print a reminder and require `edit-select update`
- **Bytecode compilation is gated separately from binary provisioning**, and the distinction is
  load-bearing. Sharing one marker gate made `.zwc` absence _permanent_: once the hook marker existed the
  whole block was skipped, so a wiped cache (the documented `find . -name '*.zwc' -delete`), a platform
  switch that had compiled a different implementation, or an install where `--setup` never ran would leave
  ~1500 lines parsing from source on every start, forever. The compile block therefore has its own
  one-stat condition (`[[ ! -f "${plugin}.zwc" || ! -f .zes-hooks-installed ]]`) and self-heals in a single
  load. Widening the shared marker gate instead would have re-enabled the provisioning block — including
  its network fetch — on any shell whose `.zwc` merely happened to be missing; keeping the two gates
  separate avoids that entirely. Measured: 17.3 ms per load with the bytecode absent versus 7.9 ms with it
  present — the ~9.4 ms/shell that makes this gate worth its one extra stat, an order of magnitude more than
  the marker fast path itself saves. Steady state is unchanged at ~10 ms / 172 syscalls
- The hook setup that enables this fast path is scoped to the plugin's own repository. Both the silent
  bootstrap and the explicit `edit-select setup-hooks` path require the plugin directory to be the canonical
  Git top level before touching `core.hooksPath`, so an archive or vendored copy nested inside another
  repository can never reconfigure its host. Collision scanning and legacy `post-merge`/`post-rewrite`
  chaining resolve through `git rev-parse --git-common-dir`, which is identical to `--git-dir` for ordinary
  clones and submodules but correctly points at the shared hook directory in a linked worktree — the one
  `core.hooksPath` actually displaces. An existing `core.hooksPath` is never overwritten; the plugin simply
  stays on the regular startup path

**Agent Auto-Compilation**

- If the compiled agent binary is missing, the loader first attempts to download a pre-built portable
  binary from the latest GitHub Release (via `assets/fetch-agents.zsh`, SHA256-verified and atomic-rename)
- If the download is unavailable or fails (offline / build-from-source / non-release-arch case) and the
  `Makefile` is present, the loader runs `make` automatically in a subshell
- Build errors produce stderr diagnostics naming the required `-dev` packages for the user's distribution
  (e.g. `libx11-dev`/`libxfixes-dev` on X11, `libwayland-dev`/`wayland-protocols` on Wayland)

**Configuration Loading**

- The configuration file (`~/.config/zsh-edit-select/config`) is read once at startup and its values are
  stored in shell variables
- No configuration file I/O occurs during individual plugin operations

**Configuration Wizard**

The wizard file is lazy-loaded — sourced only when the user explicitly invokes `edit-select config`,
adding zero overhead to normal shell sessions. All wizard operations are implemented entirely as Zsh
built-in operations with no subprocess spawning:

- Config reads use `$(<file)` Zsh builtin reads; config writes use `printf` with Zsh array filtering
  (`${(@)array:#KEY=*}`) — no `sed` or `grep` forks at any point in the config I/O path
- Screen redraws use inline ANSI escape sequences (`printf '\033[2J\033[3J\033[H'`) instead of the
  `clear` command; this also clears the scrollback buffer in a single `write()` call rather than a fork
- The color gradient used in the wizard UI is emitted as inline 24-bit ANSI escape sequences baked
  directly into the banner routine — no `tput`, no color-lookup subprocess, and no per-character math
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
- The plugin polls for the `seq` cache file to appear with a maximum wait of 1 second (40 × 25 ms intervals),
  rather than using a fixed sleep — the poll exits as soon as the file appears, so startup overhead matches
  actual initialization time. Precisely, this file signals that the agent's **pre-daemon cache
  initialization** has run, not that the daemon is fully up: daemonization, PID publication, and display-server
  event setup continue afterward. That is deliberate and sufficient — the cache the shell reads exists from
  this point on, so no widget can observe a missing file, and the amortized liveness probe covers the rest.
- If a running agent is already present (PID file exists and `kill -0` succeeds), it is reused without
  restart — this check runs _before_ any cleanup or launch, so a live daemon is always adopted rather than
  duplicated.
- **X11 only:** if `DISPLAY` is unset, `_zes_start_monitor` resolves the failure itself instead of launching
  and waiting. The agent's very first statement is `if (!getenv("DISPLAY")) return 1`, so it exits before
  creating any cache file and the readiness poll could only ever run out its full 1-second budget. The early
  return reaches an identical end state (`_EDIT_SELECT_DAEMON_ACTIVE=0`, no cache files, clipboard operations
  falling back to `xclip`) in **0.004 s instead of 1.109 s** — measured. The live-daemon reuse path above
  still returns first, so an already-running agent is unaffected.
- After the readiness poll completes, the plugin reads the initial `seq` file content and stores it as the
  detection baseline. The X11, Wayland, and WSL backends record it via `_EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1`
  (marking the startup value as already-seen, preventing the first observed value from being treated as a new
  selection event on the first ZLE callback); macOS stores it directly in `_EDIT_SELECT_LAST_SEQ` — its
  content-comparison scheme does not need the event-fired latch

</details>

<details>
<summary><b>Runtime Execution</b></summary>

**Content-Based Selection Detection**

The typing hot path is designed around a single fork-free file read per keypress:

1. The background agent writes selection content to a `primary` cache file, then writes a monotonic counter
   to a `seq` file
2. The shell detects changes by reading the `seq` file's content via the `$(<file)` builtin (a Zsh-optimized
   read — no process fork), guarded by a `[[ -r ]]` test that also serves as the daemon-liveness check
3. If the content matches the cached value, the function returns immediately with no further work
4. If the content has changed, the `primary` file content is read (also fork-free) and stored in a shell
   variable

Under normal typing conditions with no selection changes, the entire detection path costs one small file
read and a string comparison per keypress. Comparing `seq` content (rather than its modification time) makes
detection exact: `zstat +mtime` exposes only integer-second resolution, so two selection changes within the
same second would share an mtime and the second would be missed; a monotonic counter never aliases.

> **Fork discipline (load-bearing for the hot path):** Only the bare `$(<file)` form is fork-free in zsh
> (`ZSH_SUBSHELL` stays at 0 — it is a builtin, faster than `zstat +mtime`). A redirect _inside_ the
> construct — `$(<file 2>/dev/null)` — **re-introduces `fork()`** (the redirect forces a subshell). The
> plugin uses two read shapes accordingly: the **hot path** (per-keypress sync, per-redraw hook) uses the
> guarded-bare form `[[ -r f ]] && x=$(<f) || true` (~11.6 µs, zero forks — deliberately _without_
> `2>/dev/null`, since the `[[ -r ]]` test already stands in for stderr suppression); the **cold paths**
> (focus-in, paste-reseed, startup pre-populate) use the brace-grouped form `{ x=$(<f) || true } 2>/dev/null`
> (~21 µs — the `2>/dev/null` fd save/restore is the cost, but it is on a non-keystroke path so it doesn't
> matter).
>
> **Guard placement matters under `err_return`.** When `err_return` is active, a failing right-hand side
> of an AND-list (e.g. the read inside `[[ -r f ]] && x=$(<f)`) aborts the enclosing function exactly like
> a bare command — the AND-list does _not_ mask it the way it masks a failing _left_ test. Worse, a
> trailing `|| true` placed _outside_ a brace group (`{ x=$(<f) } 2>/dev/null || true`) is **defeated**
> once a caller observes the function's status — and that observation is routine: `zsh-syntax-highlighting`
> wraps every widget as `builtin zle "$@" && _zsh_highlight`, so each widget's return code is inspected on
> every keystroke when it is loaded. Three shapes are therefore used deliberately, and which one is correct
> depends on scope: the **in-brace** form (`{ x=$(<f) || true } 2>/dev/null`) wherever a caller may observe
> the enclosing function's status; the **trailing** form on a _simple_ command (`[[ -r f ]] && x=$(<f) || true`),
> which unlike a brace group holds in every caller context and so keeps the hot path free of `2>/dev/null`;
> and the **outside** form (`{ x=$(<f) } 2>/dev/null || true`) only at file scope — the startup
> pre-populate — where the rc reaches nothing but the `source … || true` shield in the root loader. A fourth
> case needs no guard at all: `{ local x=$(<f) } 2>/dev/null` with `local` on the _same_ line, because the
> `local` builtin's own success masks the substitution's failure. The same discipline extends past cache
> reads to every status-ignored best-effort statement on these paths — daemon `disown`, wait-loop increments
> (`((++n))`, pre-increment because the post-increment form yields 0 and would itself report failure),
> cache-file cleanups, PRIMARY clears, and incidental terminal writes — so a user's `err_return` set for
> their own scripts cannot abort a widget midway and strand selection state.

**Write-Ordering Guarantee**

The agent always writes the `primary` content file before updating the `seq` file. Since the shell uses the
`seq` file's content as its change signal, this ordering guarantees the shell never reads a half-written
`primary` file.

**In-Memory State Caching**

- The last-known selection state is held in shell variables (`_EDIT_SELECT_LAST_PRIMARY`,
  `_EDIT_SELECT_LAST_SEQ`)
- `_zes_sync_selection_state()` returns immediately if the `seq` content is unchanged
- An event-fired gate (`_EDIT_SELECT_EVENT_FIRED_FOR_SEQ`) marks each new `seq` value as already-processed so
  the same value cannot trigger the selection twice across multiple ZLE callbacks. It is set to `1` when a new
  `seq` is observed, and is deliberately **not** cleared again inside the pre-redraw hook: clearing it there
  would re-arm an already-consumed selection, so a selection the user had visually cleared by clicking
  elsewhere (the click emits `\e[C`/`\e[D` cursor keys, but the agent publishes no new event) would be deleted
  or replaced on the next keypress. The latch therefore stays set until the next genuine agent write, which is
  what keeps a cleared selection from being treated as live.
  macOS omits the gate entirely — its content-comparison scheme already deduplicates, so the dead state
  variable was removed there
- Keyboard selections bypass the mouse-detection path entirely
- On the **no-event keystroke** — the hottest path, where nothing is selected and the agent published nothing —
  `_zes_detect_mouse_selection()` tests the cached selection for emptiness _in place_ via
  `[[ -z "${_EDIT_SELECT_LAST_PRIMARY:+x}" ]]` instead of first copying it into a local. The copy was
  O(selection-size) on every keystroke and the local was only ever read by that one emptiness test, and
  `${var:+x}` keeps the test itself O(1) — the plain `[[ -z "$var" ]]` form would materialize the whole
  cached value, which can be an entire raw scrollback drag when the matcher did not resolve it. This is a
  deliberate trade rather than a free win: measured with Callgrind, the `:+x` expansion costs ~772
  instructions more at a 1-byte cached selection, breaks even near 40 bytes, and saves ~1816 at 128 bytes —
  a worst case of +0.058 µs per keystroke, against a 200 KB selection dropping from ~450 µs to ~1.2 µs. The
  pathological case is the one a user would actually feel while typing, so the trade is taken deliberately
- State is invalidated only when the agent writes a new cache entry
- Widget handlers call `zle -c` (flush pending typeahead) rather than `zle -Rc` (flush + force full
  redraw); this avoids an unnecessary redraw cycle on every keypress that does not modify the display
- After each paste or cut operation, `_zes_sync_after_paste()` resets the detection baseline to the
  post-operation state, so the `seq` value written during the operation is not re-detected as a new selection
  event on the next ZLE callback. Two shapes exist, and the difference is intentional rather than an
  oversight: **Wayland, macOS, and both WSL backends** re-read the current `seq` and `primary` content from
  the daemon cache into `_EDIT_SELECT_LAST_SEQ` / `_EDIT_SELECT_LAST_PRIMARY`, while **X11** performs no
  cache read at all — it clears the three state variables and calls `_zes_clear_primary`, which is sufficient
  there because clearing `LAST_PRIMARY` already prevents the just-consumed selection from re-matching.
  Wayland and tailored-WSL additionally reseed from `_zes_get_primary` when the daemon is not running.

**Direct Buffer Manipulation**

Paste and replace-selection operations compute the selection bounds and splice `BUFFER` directly using Zsh
string indexing (`${BUFFER:0:$start}${replacement}${BUFFER:$((start+len))}`), bypassing `zle kill-region`.
This prevents these operations from writing to ZLE's kill buffer, which would interfere with subsequent yank
(`Ctrl+Y`) operations. Mouse-selection deletion widgets use the same direct-splice approach. Cut operations
(`Ctrl+X`) intentionally retain `kill-region` so the deleted text remains available for yank.

**Cut Operation Ordering**

Cut copies the selected text to the clipboard before deleting it from the buffer. By performing the copy
first, the clipboard server begins serving the content to other applications immediately while the subsequent
buffer deletion completes — a single in-memory string splice with no external I/O. The ordering is also what
lets the deletion be gated on the copy's exit status, so a clipboard failure cannot destroy text that was
never captured (see the OSC 52 discussion under "Protocol & Compositor Compatibility" below).

The one deliberate exception is **macOS cut from a mouse selection**, which deletes first and then copies
asynchronously. There the local copy is a non-blocking `&!` hand-off, so copy-first would mean waiting on a
spawned process before the region visibly disappears; the keyboard-region path on macOS keeps the standard
copy-first, status-gated order.

**Agent Health Monitoring**

- Agent liveness is checked via `kill(pid, 0)` at 30-second intervals (amortized via `EPOCHSECONDS`
  comparison)
- If the agent process has exited, it is restarted transparently
- Health checks are not issued on individual keypress operations

**Prompt-Aware Selection Resolution** _(X11 / Wayland / macOS)_

Mouse selections reported by the terminal carry the raw highlighted region, which may include the prompt
prefix and/or a right-aligned status suffix that is not part of the editable command buffer. The plugin runs a
prompt-aware resolver (`_zes_match_selection_in_buffer`) on every new mouse-selection event before any copy /
cut / type-over / paste / delete action:

1. **Length-guarded exact match** against the command buffer — the fast path for the common case where the
   raw highlight equals an editable region verbatim.
2. **Reverse-containment fallback** — when the selection is a strict superset of an editable region (the
   prompt-prefixed or status-suffixed case), bounded by a `max_trim` budget (currently 512 chars) so an
   absurdly long prompt can never be silently "matched."
3. **Multi-line resolver** (`_zes_resolve_multiline`) — strips one trailing terminator, splits by `(@f)`
   (preserving empty lines), then aligns rows in descending order of confidence:
    - **Exact whole-row alignment** — row 1 CONTAINMENT of the buffer's first line, rows 2…N matching the
      buffer's continuation lines exactly, contiguous, no padding gaps.
    - **Trailing-whitespace-insensitive whole-row alignment (macOS only)** — the same alignment with trailing
      whitespace removed from both row arrays, splicing the emitted block from the **untrimmed** buffer rows so
      the result stays a verbatim buffer substring.
    - **Partial-first-line alignment** — for selections that started mid-line, matching the longest prefix of
      source row 1 that is a suffix of a buffer row, with rows 2…N still exact.

    The ordering is load-bearing rather than incidental. Whole-row alignment is strictly stronger evidence
    than a partial-row suffix slide, and the tolerant pass accepts a superset of the exact pass's offsets, so
    running it earlier could turn a unique exact match into a fail-closed ambiguity. Each pass keeps the same
    guard: two distinct aligning blocks fail closed rather than guess. Within a pass, row alignment is tested
    before the row-1 search, because alignment is N−1 string compares that reject nearly every offset whereas
    the row-1 search is a descending scan over the row's length; both tests are pure, so the order affects only
    how much work a rejected offset costs.

4. **Single-line trimmed fallback** — binary search over a trim budget to catch single-line drags that
   include transient terminal decorations but do not split cleanly into rows.
5. **Fail-closed** (X11/Wayland): an unmatched selection is rejected; `_EDIT_SELECT_ACTIVE_SELECTION` is
   left empty, no copy/cut/replace happens (correct-or-nothing). On macOS, an unmatched multi-line
   selection falls through to the single-line trimmer rather than failing closed, preserving the platform's
   pre-existing single-line behavior.

**Why trailing whitespace needs its own pass, and why only macOS has one.** A terminal cannot distinguish a
trailing blank cell the user typed from screen padding, so a captured row and its buffer row can disagree on
trailing whitespace in _either_ direction: GPU right-edge padding **adds** it (Alacritty, WezTerm, Ghostty),
while copy-time trimming **removes** it (iTerm2, kitty's `strip_trailing_spaces`, Terminal.app). When a row is
desynced this way, the resolver does not simply fail — the partial-row pass can succeed on a degenerate
one-character overlap, returning a real but wrong buffer range that no later fallback can correct, because the
resolver reported success.

The X11 and Wayland resolvers are byte-identical to each other and carry no tolerant pass, yet they are not
affected, for a reason worth stating precisely: on those platforms an unresolved multi-line selection is
returned directly to the caller, which fails closed. macOS instead falls through to the single-line trimmer
(preserving the behavior it had before the resolver existed), so there the same desynced row turned a
fail-closed into an edit on the wrong range. macOS is also the only implementation whose capture path strips
trailing whitespace per line — which is what makes prompt-decorated scrollback rows resolve, but is destructive
when that whitespace is real command text. Both facts are macOS-specific, so the tolerant pass is too; the
Linux resolvers are deliberately left alone rather than changed for parity.

On the macOS capture side, the new-selection path therefore matches **two** candidates — the per-line-stripped
text and a byte-faithful copy with only the overall trailing pad removed — and keeps the strictly longer
result, defaulting to the stripped form on ties and misses. The second match is computed only when the two
candidates differ, once per mouse-up, never per keystroke or redraw. Both macOS capture paths (Accessibility
and reactive `Cmd+C`) share one `primary` cache file, so a single site covers both. The two mechanisms are
complementary rather than redundant: the dual candidate recovers the case where the terminal *preserved* the
whitespace, and the tolerant resolver pass recovers the case where it *trimmed* it, which no capture-side
candidate can reach.

The dedup fast path at the top of `_zes_detect_mouse_selection()` compares `_EDIT_SELECT_LAST_PRIMARY` against
`_EDIT_SELECT_ACTIVE_SELECTION`, and what those two hold differs by platform for a deliberate reason. On X11
and Wayland both are set to the **matched** editable text on a successful resolution: because those platforms
fail closed, a resolution either produces a match or produces nothing, so leaving `LAST_PRIMARY` holding the raw
prompt-including source would silently invalidate the still-valid active match on the next non-event keypress.
The raw source stays in a local variable and is never written to the cache.

macOS instead records the captured text (normalized, per-line stripped) rather than the match, which is
consistent with its fall-through resolver: a capture that the resolver cannot resolve is still the thing the
next keypress must recognize as "already seen." This also keeps every downstream consumer — the dedup fast
path, pending resolution, and the occurrence-at-cursor scan — seeing a single value shape even though the
new-selection path evaluates two candidates internally.

Neither WSL implementation carries the resolver. The tailored variant — the one real WSL users load — does not
need it, because its own SGR mouse tracking (DECSET 1000/1002/1006, read via a `\e[<` binding) reports button
coordinates directly and
resolves the exact buffer range from them, leaving no prompt decoration to strip. The generic fallback, reached
only when the tailored variant's prerequisites are absent, uses the cached selection text as-is.

**Occurrence Scanning** _(duplicate-selection disambiguation)_

Once a selection is resolved, the plugin must find _where_ in the buffer it occurs — to pick the occurrence
under the cursor, and to decide whether the
[Mouse Replacement Safeguard](#mouse-replacement-safeguard) prompt is needed. The scan is
built on Zsh's C-level pattern-strip idiom rather than a shell-level character walk: `${buf%%"$sel"*}`
strips everything from the first match onward, so the match offset is just the length of what remains, and
`buf="${BUFFER:$idx}"` advances past it. Each step is one C-level operation inside the shell rather than an
interpreted loop iteration, which removes the O(buffer²) behaviour a per-character substring walk has on
large multi-byte buffers. Measured on an 11 KB buffer: **1090 ms → 1.74 ms (626×)**, across the 12 scan
loops in the X11, Wayland, and macOS plugins (four each), and proven to produce byte-identical matches to
the walk it replaced.

Each loop also stops as soon as its answer is fixed rather than scanning to the end of the buffer, because
occurrences are produced strictly left to right:

- The delete/replace scan breaks when the cursor falls inside the occurrence just found, or when a second
  occurrence already starts _past_ the cursor — no later one can contain it either.
- The two occurrence-**count** loops exist only to answer `== 1` and `>= 2`, so they stop at two hits
  instead of counting every match in the buffer.

Both prunes are pure early exits: the value each loop reports is unchanged, only the work to reach it is
smaller.

A related skip applies to the **pending-resolution** path on macOS. When a keypress arrives with a pending
disambiguation recorded, that pending text is normally re-matched against the buffer, because the buffer may
have changed since it was recorded. The re-match is skipped when *this same keypress* is what set the pending
value: the only way to reach that point is for the matcher to have already failed on exactly that string
against exactly that buffer, so re-running it would fork a second time for a provably identical empty result.
A pending value left by an *earlier* keypress still takes the re-match.

**Event-Driven Detection**

- **X11 / XWayland**: The agent subscribes to XFixes `XFixesSetSelectionOwnerNotifyMask` events; it wakes only
  on selection owner changes. The main loop uses `poll()` with a 1-second timeout used solely for clean
  `SIGTERM` shutdown — no periodic work is performed on timeout
- **Wayland**: The compositor delivers primary selection events on owner change via
  `zwp_primary_selection_unstable_v1`. The daemon loop's `poll()` timeout is adaptive: 1 second when a
  data-control manager (`ext_data_control_v1` or `zwlr_data_control_unstable_v1`) is active (the common
  case on modern compositors — no per-timeout work is done); 50 ms otherwise (the `wl_data_device` path
  used on GNOME/Mutter pre-47), where each timeout expiration re-reads the current offer to catch content
  changes made without a selection-owner flip — e.g. the user extending a terminal text selection without
  releasing the mouse button
- All Linux/X11-family agents sleep in `poll()` between events, consuming no CPU during idle periods
- **macOS**: The daemon runs a `CFRunLoop` driving a CGEventTap (mouse-down/drag/up); on each relevant mouse-up
  it synchronously reads the focused element's `kAXSelectedTextAttribute` from the Accessibility API rather than
  installing a long-lived `AXObserver`. The loop is fully event-driven and consumes no CPU while idle. The
  short-lived modes (`--get-clipboard`, `--copy-clipboard`) deliberately skip
  `[NSApplication sharedApplication]` initialization — `NSPasteboard` is a Foundation-level API that needs no
  running `NSApplication`, so dropping the AppKit init saves ~70 ms per paste-retry call (3.4× faster on the
  paste retry loop)
- **WSL**: The Linux-side agent sleeps on `poll()` waiting for clipboard-notification lines from the
  helper; the helper.exe sleeps in its Win32 `GetMessageA` loop until the OS delivers a clipboard-format
  change notification

</details>

<details>
<summary><b>Native Agent Internals</b></summary>

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
- `-fno-strict-aliasing` _(all Linux agents except the native Wayland agent)_ — Permits the type-punning
  pointer casts required by Xlib's event structures (X11, native XWayland, WSL-tailored XWayland) without
  aliasing-rule violations; also retained by the WSL `zes-wsl-selection-agent` which uses `memcpy`-based
  buffer moves rather than casts, keeping the policy uniform across the X-family. The native Wayland agent
  is the only agent that never casts between unrelated pointer types, so it does not need the flag
- `-fno-stack-protector` — Removes stack-canary instrumentation overhead; the agents run locally as
  unprivileged user daemons with no network-facing attack surface
- System libraries (`libwayland-client`, `libX11`, `libXfixes`) are the only runtime dependencies

**macOS compilation differs:** the macOS agent uses Apple clang with `-Os` (size-optimized), `-fobjc-arc`
(Automatic Reference Counting for Objective-C), `-Wl,-dead_strip` (ld64's equivalent of `--gc-sections`),
and links against `AppKit`, `ApplicationServices`, and `CoreGraphics` frameworks. Apple clang does not
support `-march=native`, `-fipa-pta`, `-fno-plt`, or `-fno-semantic-interposition` — these GCC-specific
flags are Linux-only. The build also runs `strip` after linking rather than passing `-s` to the linker.

**Operation Modes**

Each agent binary supports the same five core operation modes within a single executable, eliminating the need
for separate per-mode binaries. (The macOS agent adds four platform-specific flags on top of these —
`--check-ax` and `--request-ax` for Accessibility permission state, `--status` for diagnostics, and the
internal `--_daemon-child` used by its `posix_spawn` re-exec — but the five below are the cross-platform
contract the shell backends actually drive.)

| Mode               | CLI Flag           | Behavior                                                                                                                                                    |
| ------------------ | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Daemon**         | _(default)_        | Persistent PRIMARY selection monitoring with event-driven cache updates; CLIPBOARD content is fetched on demand by `--get-clipboard` (never watched/cached) |
| **Oneshot**        | `--oneshot`        | Print current selection to stdout and exit                                                                                                                  |
| **Get clipboard**  | `--get-clipboard`  | Print current CLIPBOARD contents to stdout and exit                                                                                                         |
| **Copy clipboard** | `--copy-clipboard` | Read stdin, take clipboard ownership, fork a background server                                                                                              |
| **Clear primary**  | `--clear-primary`  | Clear the PRIMARY selection and exit                                                                                                                        |

Platform-specific notes:

- **Daemon** — Linux X11/Wayland/XWayland agents and the WSL Linux-side agent block on `poll()` (1 s
  timeout, solely for clean `SIGTERM` shutdown); the macOS daemon blocks in `CFRunLoopRun()` driving a
  CGEventTap + on-demand `kAXSelectedTextAttribute` read; the WSL helper.exe blocks in a Win32 `GetMessageA` loop until the OS
  delivers a clipboard-format change notification
- **Oneshot** — X11/XWayland/Wayland read the PRIMARY selection; WSL/macOS read the CLIPBOARD (neither
  platform has a PRIMARY selection), and `--get-clipboard` is an alias for `--oneshot` on both WSL and
  macOS (they share a CLIPBOARD-only model, so the two flags collapse to the same code path)
- **Copy clipboard** — X11/XWayland/Wayland fork a background server that holds clipboard ownership and
  serves paste requests (the child calls `setsid()` and ignores `SIGHUP` to survive terminal closure);
  WSL pipes stdin to `zes-wsl-clipboard-helper.exe` (a short-lived Win32 process, no persistent server);
  macOS writes directly to `NSPasteboard` and returns without forking
- **Clear primary** — the flag exists in every agent, but two platforms deliberately never invoke it from
  the shell. On **macOS** and on **WSL** (both the generic backend and the tailored backend's WSL-native
  route) `_zes_clear_primary` truncates the local `primary` cache file directly, leaving the system
  pasteboard / Windows clipboard untouched. On WSL this is a correctness requirement, not just an
  optimization: the short-lived agent's `--clear-primary` re-reads `seq` from the file and increments it,
  while the daemon keeps its own in-memory counter — so the daemon's next event could re-emit a value the
  shell had already consumed, making an identical re-selection invisible. Truncating locally keeps `seq`
  progression owned solely by the daemon. The X11, Wayland, and the tailored WSL XWayland/Wayland routes do
  invoke the flag, because there a real display-server PRIMARY selection has to be released before the local
  cache is truncated

**Selection-dismissed notification** _(`SIGUSR1`, native Wayland daemon only)_

The native Wayland daemon additionally accepts `SIGUSR1` as a "the user dismissed the on-screen selection"
notification. On receipt it publishes an empty `primary` with a fresh `seq` — the same pair it writes when a
selection genuinely disappears — and resets its dedup cache so re-selecting the identical text afterwards
still registers as a change. The handler itself only assigns to a `volatile sig_atomic_t`; the cache write
happens at the top of the daemon loop, keeping the handler async-signal-safe.

This exists because on native Wayland _clearing_ PRIMARY is the wrong instrument, for two independent
reasons. First, `zwp_primary_selection_device_v1.set_selection(NULL)` is honored only for a client holding
keyboard focus, and a click helper spawned detached has neither surface nor focus — the request is accepted
by libwayland and silently dropped. Second, on KDE Plasma the clipboard manager treats an emptied PRIMARY as
something to restore and refills it from its own history within about a second, so a client-side clear comes
back as a _new_ selection carrying unrelated text. Any client-side clear hits this, `wl-copy --primary
--clear` included, since it issues the identical protocol request.

Signalling the daemon asks nothing of the compositor, so no clipboard manager has anything to react to, and
it is protocol-agnostic — no `ext` / `wlr` / `zwp` branch. One deliberate behavioral consequence: on native
Wayland the compositor's PRIMARY now _retains_ its text after a dismissal, so a selection made in another
application stays middle-click pasteable. X11 and XWayland keep using `--clear-primary`, where
`XSetSelectionOwner(None)` genuinely releases ownership and nothing restores it.

**Persistent File Descriptor Architecture**

The Linux agents (X11, Wayland, XWayland, WSL) and the macOS daemon open the cache file descriptors
(`fd_primary`/`g_fd_primary`, `fd_seq`/`g_fd_seq`) once at daemon startup and hold them open for the entire
agent lifetime. Cache writes use `pwrite()` (atomic positional write — no preceding
`lseek()`) followed by `ftruncate()` to trim the file to the exact written length, preventing stale trailing
bytes from longer previous entries. This reduces each cache update to 2 syscalls per file, compared to the
`open()`/`write()`/`fsync()`/`close()` pattern (4 syscalls per file) used by conventional approaches. On the
Linux agents, if either persistent open fails at startup the successfully-opened half is closed and both
globals are reset to `-1` (the hot branch already requires both descriptors, so a half-open one would otherwise
be retained for the daemon lifetime without ever being used); macOS is exempt because its descriptors are
independently useful and the failure path keeps working through the pathname fallback.

**Content Deduplication** _(Wayland agent)_

The Wayland agent's `process_primary_update()` (invoked from `ps_device_handle_selection()` and the
data-control offer callbacks) compares incoming selection content against a cached copy
(`last_known_content`) using `memcmp()` before writing. When the content is unchanged — common during static
selections or repeated compositor events — the cache write is skipped entirely, avoiding unnecessary disk
I/O. When new content does arrive, buffer ownership is transferred by nulling the source pointer (`sel = NULL`)
after assigning it to `last_known_content`, rather than duplicating the buffer — eliminating one `malloc` +
`memcpy` per selection event.

The X11 and XWayland agents (native XWayland and the WSL-tailored XWayland fork) intentionally skip
deduplication: their `check_and_update_primary()` always increments the sequence counter and writes
unconditionally, because a re-selection of identical text (e.g., deselect then re-select the same word) must
still fire a new event in the shell for correct mouse-selection tracking.

**Descriptor Safety**

`O_CLOEXEC` is applied to every file descriptor: all `open()`, `pipe2()`, and `memfd_create()` calls include
the close-on-exec flag. This prevents file descriptor leaks if the agent forks a clipboard server child
process. The WSL clipboard helper applies the same discipline to its Win32 GUI objects: its single
`RegisterClassA` is balanced by an `UnregisterClassA` on **every** exit path out of the daemon routine — after
each of the four `DestroyWindow` calls, plus once more on the window-creation failure path, where no window
exists to destroy. Windows would reclaim the class at process exit regardless; releasing it explicitly keeps
the named GUI object from outliving its use inside a process that is still running.

**Sequence Counter Design**

The sequence counter is seeded from `time(NULL)` at startup and incremented once per published selection
event. Within a single daemon's lifetime that makes every event's value distinct, so two selection changes
inside the same wall-clock second can never alias — the failure mode that ruled out `zstat +mtime`, whose
resolution is one integer second.

Across a **restart** the value is best understood as an opaque **comparison token**, not a numerically
monotonic counter. The shell compares `seq` for _inequality_ (`[[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]`),
never for order, so all that is required is that a fresh daemon's token differ from the one the shell last
observed — which time-seeding delivers in practice. Strict numeric monotonicity is deliberately _not_
claimed: a long-lived daemon can increment past the current wall clock, so its successor's `time(NULL)` seed
may legitimately be lower. The backends close the residual window structurally rather than arithmetically,
by deleting the stale `seq`/`primary` files before launching a replacement, so a new daemon's first token is
never compared against a dead one's last.

The initial `seq` value is written by the pre-daemon process, before `daemon()`/`posix_spawn`, so the file
exists by the time the shell begins polling.

On macOS the parent process writes the `agent.pid` file **before** writing the readiness `seq` value. The child
that becomes the daemon performs its AppKit initialization (`[NSApplication sharedApplication]`) only after
`posix_spawn`, which takes ~70 ms; if the parent wrote `seq` first the shell's readiness poll could observe `seq`
present while `agent.pid` was still absent, and a second `_zes_start_monitor` invocation (configuration apply) would
conclude no daemon was running and spawn a duplicate event-tap daemon. Writing the pid first in the spawning
process guarantees `pid-on-disk` happens-before `seq-on-disk`, so any shell that sees a readiness `seq` value
also sees a resolvable pid — the pid analogue of the "SEQ IS WRITTEN LAST" invariant. The Linux/X11/Wayland/WSL
agents instead write both files from the daemonised child after `daemon()`/`fork()`, which is acceptable because
their startup cost is sub-millisecond and the readiness poll loop covers the gap.

**X11 Atom Handling**

- The native X11 agent (`zes-x11-selection-agent`) uses private atom names (`ZES_SEL`, `ZES_CLIP`) as
  selection conversion properties. This avoids collisions with properties written by other applications on a
  shared X server.
- The XWayland agent (`zes-xwayland-agent`) and the WSL-tailored XWayland agent reuse the standard `PRIMARY`
  and `CLIPBOARD` atoms directly as property names, which is safe because XWayland provides an isolated
  per-session X server where no other clients compete for property names.
- All three X-family agents intern their atoms once at startup via a single batched `XInternAtoms()` call
  (six names on X11, four on each XWayland variant) and reuse them for the agent's lifetime — `XInternAtom`
  is synchronous, so each non-batched call would flush the X request buffer and wait for its own reply; the
  batched form pipelines all names in one request and waits once, which is the difference that matters for the
  short-lived `--get-clipboard` / `--copy-clipboard` / `--clear-primary` modes the shell forks per clipboard
  operation.
- `XFlush()` is issued only where a reply is genuinely needed and nothing else would force the buffer out.
  Exactly three survive per agent: after `XConvertSelection` (the request must reach the server before the
  agent polls for `SelectionNotify`), after the XFixes subscription, and after the `SelectionRequest`
  response. Flushes after a synchronous `XGetSelectionOwner` verification — which already round-trips, and so
  has necessarily flushed — and in `--clear-primary` immediately before `XCloseDisplay`'s own final sync were
  removed as pure duplication. The response flush is the one that cannot be dropped: the clipboard child exits
  via `_exit()`, which does not drain Xlib's buffer, so without it a queued reply can be discarded after
  `SelectionClear` and the requesting application sees an empty paste.

**Clipboard Server Lifecycle** _(X11 / XWayland / Wayland)_

When the shell copies text to the clipboard (`--copy-clipboard`) on X11/XWayland/Wayland, the agent forks a
background child process that becomes the clipboard owner and serves paste requests to other applications:

- The parent process exits immediately, returning control to the shell
- The child calls `setsid()` to create a new session and ignores `SIGHUP` to survive terminal closure.
  The Wayland agent additionally ignores `SIGPIPE` because paste requestors may close their pipe
  mid-transfer
- **X11 / XWayland**: The server advertises `TARGETS`, `UTF8_STRING`, and `XA_STRING`, and serves
  `SelectionRequest` events in a `poll()` loop with a 100 ms timeout (500 iterations = 50 s). It exits when
  another application takes clipboard ownership (`SelectionClear`), or after ~50 s if it was **never asked for
  the selection at all**. A `selection_served` latch switches the timeout off permanently once the first
  request has been answered, so copied text does not expire out from under the user 50 seconds later — from
  that point the child lives until another client takes ownership. This is deliberate on X11, where CLIPBOARD
  content only survives as long as its owner process does
- **Wayland**: The server creates a `wl_data_source` offering multiple MIME types
  (`text/plain;charset=utf-8`, `text/plain`, `UTF8_STRING`, `STRING`) and responds to `send` callbacks. It
  exits when the compositor signals ownership loss via the `cancelled` callback
- **macOS / WSL**: No background server is spawned. macOS writes directly to `NSPasteboard` (system-wide
  clipboard service) and returns; WSL pipes stdin to the helper.exe which writes to the Windows clipboard
  and exits — both rely on the OS clipboard service to serve subsequent paste requests from other apps

**Adaptive Poll Timeouts** _(selection retrieval)_

When reading selection content after a conversion request, the agents use adaptive timeouts to balance
responsiveness against syscall frequency:

- **X11 / XWayland**: 5 ms polls for the first 20 ms (catching common fast responses), then 20 ms polls
  thereafter to reduce syscall rate during slow responses
- **Wayland**: 500 ms initial timeout covers the IPC round-trip; subsequent read chunks use a 100 ms timeout
  to detect EOF quickly
- **macOS (Path B / GPU terminals)**: The reactive `Cmd+C` watcher polls the clipboard via a GCD timer at
  1 ms granularity for the first 75 ms (`ESCALATION_TICK`), then injects `Cmd+C` and continues polling until
  the candidate selection is stable for 25 ms (`SETTLE_TICKS`) or the 700 ms safety cap is reached
  (`MAX_POLL_TICKS`)
- **WSL**: Selection content arrives asynchronously via the helper.exe's pipe — the Linux-side agent simply
  reads complete lines as they arrive; no adaptive polling is performed

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

**Registry bind version capping.** Every `wl_registry_bind` in the agent caps the requested interface
version at the highest version the agent actually uses (`wl_data_device_manager` ≤ 3, `wl_compositor` ≤ 4,
`zwlr_data_control_manager_v1` ≤ 2, `wl_seat` ≤ 2). The `wl_seat` bind is load-bearing here: the agent issues
only `wl_seat.get_keyboard` / `.destroy` (both available since v1) and installs no `wl_seat` listener, so it
consumes none of the v2-only `name` event — but requesting a version the compositor does _not_ advertise is
a protocol error that kills the client. Capping with `version < N ? version : N` strictly removes that
failure mode (it differs from a hard `N` only at advertised=1, where the old code would have requested an
unavailable version) and changes nothing on every real compositor, all of which advertise `wl_seat` ≥ 5.

An additional **OSC 52** clipboard-write path is shared by **all five backends** (X11, Wayland, WSL-generic,
WSL-tailored, macOS) — a terminal escape sequence written in a single `write()` call to `/dev/tty` that
requires no display-server protocol involvement. Activated whenever `$SSH_CLIENT`/`$SSH_TTY`/`$SSH_CONNECTION`
indicates an SSH session (see [SSH Support](#ssh-support) for the user-facing details), it tunnels the
selection back to the user's local terminal through the SSH channel. The base64 encoder uses `-w 0` on
Linux/WSL and `-b 0` on macOS (suppress line-wrapping that would corrupt the OSC 52 sequence), and both the
encoder and the `/dev/tty` write propagate their return code — the encoder via `|| return $?` before any
escape byte is emitted, so a failed encode can never write a truncated payload. tmux and GNU Screen DCS
passthrough wrapping is handled inside the same code path.

That propagated status is what makes **cut** safe over SSH: every backend's keyboard-region cut gates
deletion on the copy succeeding (`_zes_copy_to_clipboard … || { zle -M "Cut failed: clipboard unavailable"; return; }`),
so a failed OSC 52 write leaves the region intact and reports the failure instead of destroying text that was
never copied. Two deliberate asymmetries are worth knowing:

- **Copy** does _not_ gate on it on X11, Wayland, macOS, and WSL-generic — those `_zes_copy_to_clipboard`
  calls end in `|| true`, so a failed copy still deactivates the region silently. Only the WSL-tailored
  plugin surfaces a `Copy failed: clipboard unavailable` message. Copy is non-destructive (the buffer is
  unchanged, the text is still on screen), which is why the stricter treatment was applied to cut first.
- **macOS mouse-selection cut** deletes _before_ copying, by design: the local copy path hands off
  asynchronously via `&!` (background + disown — no subshell fork, no job-table entry), and the comment at
  that branch marks the ordering as deliberate for instant visual feedback. Gating it would convert a
  non-blocking hand-off into a blocking wait on every local mouse cut.

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

**XWayland Agent Selection** _(desktop-environment aware, not `DISPLAY`-driven)_

On a Wayland session the backend can drive selections either through `zes-wl-selection-agent` (native Wayland
protocols) or through `zes-xwayland-agent` (X11 atoms via the XWayland bridge). The choice is made from
`XDG_CURRENT_DESKTOP`, not from the mere presence of `DISPLAY`:

- **Mutter-family desktops** (GNOME and its forks — Cinnamon, Pantheon) restrict background Wayland clients
  from reading PRIMARY, but faithfully mirror it to XWayland. There the XWayland agent is selected (when
  `DISPLAY` is set and the binary is present): it reads through X11 atoms, bypassing the Wayland protocol
  stack, which avoids the Mutter surface requirement and also covers GNOME < 47, where no data-control
  protocol exists for the native agent to use.
- **Everywhere else** (KDE/KWin, wlroots compositors) PRIMARY is not bridged to X11 but data-control
  protocols are available, so the native Wayland agent is selected.

**PRIMARY and CLIPBOARD are chosen by the same rule, and that matters.** Keying the clipboard choice off
`DISPLAY` alone selects the XWayland agent on effectively every Wayland session, because KDE and wlroots
sessions all run XWayland too. The X11 CLIPBOARD atom is not the Wayland clipboard: KWin bridges Wayland → X11
lazily, only when an XWayland client actually asks, so an atom read returns whatever last _wrote_ that atom —
in practice the plugin's own previous copy, since the plugin was the last client to take X11 CLIPBOARD
ownership. Copying in another application and pasting in the terminal then silently produced the earlier
terminal text. Both binaries are therefore gated on the same desktop-environment test, so the clipboard is
always read through the same stack that owns PRIMARY.

> When diagnosing, note that the monitor type reported by `edit-select config` reflects the **PRIMARY**
> backend only. Inspect `$_ZES_CLIPBOARD_BINARY` directly if clipboard behavior is in question.

If neither agent binary is available, clipboard operations fall back to `wl-paste`/`wl-copy`, which read the
real Wayland clipboard.

</details>

<details>
<summary><b>Selection Detection Architecture</b></summary>

**Shell-Side Detection Path**

The `_zes_sync_selection_state()` function is called by every widget before acting. Its execution path:

1. `[[ -r "$SEQ_FILE" ]] && current_seq=$(<"$SEQ_FILE")` — reads the sequence cache file's content via the
   `$(<file)` builtin (Zsh-optimized, zero forks); the `[[ -r ]]` guard doubles as the daemon-liveness check
2. If the content matches `_EDIT_SELECT_LAST_SEQ`, the function returns immediately
3. If the content has changed, the `primary` file is read via `$(<file)` (Zsh builtin) and
   `_EDIT_SELECT_NEW_SELECTION_EVENT` is set to 1
4. The new `seq` value is recorded and the event-fired gate (`_EDIT_SELECT_EVENT_FIRED_FOR_SEQ`) is set, so the
   same value cannot re-trigger the selection across later ZLE callbacks. On a subsequent callback that sees an
   unchanged `seq`, this gate is what suppresses the stale event and drops any leftover active selection — the
   mechanism that prevents an operation from landing on a selection the user has already cleared. (macOS omits
   this gate — its content-comparison scheme already deduplicates, so the latch is vestigial there and was
   removed.)

**ZLE Pre-Redraw Hook**

The `edit-select::zle-line-pre-redraw` hook and the `zle-line-init` focus-reporting hook are both registered
via `add-zle-hook-widget`. Registration is **deferred to the first precmd** by a one-shot helper
(`_zes_register_redraw_hook`) rather than performed at plugin load time. This avoids interacting with
user-widget wrappers that other plugins (notably `zsh-syntax-highlighting`) install at their own load time:
registering at load would make `zle-line-pre-redraw` a user widget that gets wrapped, forcing a redundant
re-highlight pass on every ZLE redraw. That cost is concentrated exactly where it is most visible: a
click-to-move-cursor in a GPU terminal arrives as a _burst_ of `\e[C`/`\e[D` arrows, one redraw each, so a
wrapped hook adds roughly **2 ms per arrow** and the cursor visibly crawls across a long buffer. Deferring
registration takes `_zsh_highlight` from **3.45 calls/arrow back to 1.25 — identical to running with no
plugin loaded at all**. Because `precmd` fires after `~/.zshrc` finishes, the widget does not exist when those
plugins do their one-time load-time wrap and is never wrapped. The event order `precmd → line-init →
pre-redraw` guarantees the hooks are active before any prompt redraw, so the deferral has no behavioral cost.
The literal `CSI I` / `CSI O` focus bindings stay immediate at load (only the `zle-line-init` **registration**
moves), so cross-pane focus isolation is unaffected. The hook runs before every prompt redraw and performs:

1. **Amortized liveness probe**: Checks `kill -0 $pid` only if `EPOCHSECONDS > _ZES_LAST_PID_CHECK + 30`.
   If the agent has died, restarts it transparently.
2. **Content check**: Same `$(<seq)` path as `_zes_sync_selection_state()` — one small file read per redraw.
   On content change, reads the `primary` file and sets the event flag. The hook does **not** touch
   `_EDIT_SELECT_EVENT_FIRED_FOR_SEQ`: a click that clears a mouse selection emits `\e[C`/`\e[D` cursor keys
   (one redraw each) but publishes no agent event, so the hook cannot distinguish "still selected" from
   "cleared by that click" — the cache and every state flag are identical. Leaving the latch set lets the
   widget sync suppress the stale event on the next keypress, which is what keeps a visually-cleared selection
   from being deleted or replaced.

**Empty-Primary Branch (selection cleared)**

When a new `seq` arrives with an empty `primary` — a click-deselect, a post-operation clear, or an external
clear — both the widget sync and the pre-redraw hook drop the stale active selection so a later keypress
cannot delete text that is no longer selected. Each of those four branches first clears a showing
[Mouse Replacement Safeguard](#mouse-replacement-safeguard) prompt, under a guard on
`_EDIT_SELECT_PENDING_SELECTION` being non-empty. The guard is what makes the ordering correct: every other
`zle -M ""` site in the plugin is gated on that same variable, and the branch blanks it immediately
afterwards, so clearing the message here is the last opportunity to do so — otherwise the prompt would remain
on screen with no code path left able to remove it. The guard also keeps the plugin from blanking a message it
does not own (an unrelated completion prompt, for instance), and costs nothing on the hot path, since
`PENDING` is empty on every ordinary keystroke. macOS reaches the same end state through
`_zes_clear_duplicate_prompt`, which additionally resets its `_EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE` flag.

**Cache File Protocol**

- The agent writes primary content first, then increments and writes the sequence number — this ordering
  guarantee prevents the shell from reading a partially updated `primary` file
- The shell reads only the sequence file's content as the change signal
- Full `primary` content is read only when a change is confirmed
- The sequence counter starts from `time(NULL)` and increments per event, so distinct changes within one
  daemon's lifetime always produce distinct `seq` values, including within the same second. Across restarts
  the value is a comparison token rather than a numerically ordered counter — the shell tests it for
  inequality, not order (see "Sequence Counter Design")

**Early Return Conditions**

- Unchanged `seq` content → immediate return before any selection comparison
- Mouse replacement disabled → `_zes_detect_mouse_selection()` returns immediately
- Active keyboard selection → mouse detection path is never entered
- Stale selection state → invalidated on `seq` content change, not on a timer

</details>

<details>
<summary><b>Terminal Focus & Multi-Pane Isolation</b></summary>

**DECSET 1004 Focus Tracking**

Focus tracking is not a one-shot startup write. It is re-enabled on **every new prompt** by
`_zes_enable_focus_reporting` (registered as a `zle-line-init` hook) and disabled again by
`_zes_disable_focus_reporting` on `preexec`, before any foreground command runs — otherwise a program running
while the pane gains or loses focus would receive the raw `CSI I` / `CSI O` sequences as stray input. Each
write is `print -n '\e[?1004h' >$TTY || true` (`\e[?1004l` to disable): the sequence goes to `$TTY` rather
than stdout so it cannot trigger Powerlevel10k instant-prompt console-output warnings, and the trailing guard
keeps a failed write — a closed or redirected tty — from aborting the widget under a user's inherited
`err_return`. Terminals that do not support DECSET 1004 silently ignore the request; the plugin's behavior is
unchanged.

**Focus-In Handler**

When the terminal pane receives focus (`CSI I` escape sequence), the `_zes_terminal_focus_in` handler:

1. Records the current `seq` file content as already-seen (`_EDIT_SELECT_LAST_SEQ`)
2. Sets `_EDIT_SELECT_EVENT_FIRED_FOR_SEQ = 1`
3. Clears `_EDIT_SELECT_NEW_SELECTION_EVENT` and `_EDIT_SELECT_ACTIVE_SELECTION`

This ensures that selection events written by another pane to the shared cache while this pane was unfocused
are not mistakenly treated as new mouse selections. Focus events are bound in all keymaps (`emacs`,
`edit-select`, and `main`).

**`_EDIT_SELECT_PENDING_SELECTION` deliberately survives a focus round-trip** on X11, Wayland, and
WSL-generic. An in-flight duplicate-occurrence prompt (see
[Mouse Replacement Safeguard](#mouse-replacement-safeguard)) is exactly the state a user is
about to resolve by clicking to move the cursor — and on many terminals that click is itself a focus event.
Clearing `PENDING` here would drop the disambiguation while its `zle -M` message stayed on screen, stranding
a prompt that no longer gates anything. Instead the pending-resolution path inside
`_zes_detect_mouse_selection()` owns the teardown, clearing the flag and the message together once the
cursor identifies an occurrence. The WSL-tailored variant does clear `PENDING` on focus-in, because its
authoritative SGR mouse tracking re-derives the exact range on the next gesture and has no ambiguity to
preserve; macOS routes focus-in through `_zes_reset_mouse_selection_state`, which clears `PENDING` _and_ the
prompt message atomically, reaching the same end state by a different route.

**Independent Selection State**

Each terminal pane maintains its own selection state in independent shell variables. PRIMARY selection is
cleared after each cut/paste operation to prevent a subsequent pane's detection from reading a stale value.

</details>

<details>
<summary><b>Resource Behavior</b></summary>

- Configuration and key-binding values are resolved once at load time into shell variables — no config file is
  ever re-read while typing, and no clipboard utility is ever forked on the keystroke path
- The only file touched during normal typing is `seq`: one small fork-free read per keypress, on a tmpfs-backed
  path. `primary` is read only when that value has actually changed
- Agent liveness verification runs at 30-second intervals; it is not issued on individual keystroke operations
- Native agents operate with direct system calls only; no shell interpreter or script parsing is involved
  at runtime (macOS links against the Objective-C runtime system framework — also not shell-level overhead)
- Zsh plugin scripts are compiled to `.zwc` bytecode on first load; source parsing is skipped on all
  subsequent sessions
- Cache files reside in `XDG_RUNTIME_DIR` (tmpfs on most Linux distributions), `TMPDIR`, or `/tmp` on the
  shell side (which passes the resolved path to the daemon as its first argv); on standard systemd-based
  systems, no disk I/O occurs. The C agent's own cache-directory resolution (used only by short-lived modes
  invoked without an explicit cache dir argument) falls back to `/dev/shm` then `$HOME/.cache` on Linux,
  and `$TMPDIR` → `/tmp` on macOS
- Integer state flags (`_EDIT_SELECT_DAEMON_ACTIVE`, `_EDIT_SELECT_NEW_SELECTION_EVENT`, etc.) enable fast
  arithmetic checks without string comparison
- Timestamps come from `zsh/datetime` rather than a `date` fork. Every implementation uses `EPOCHSECONDS`
  for the amortized liveness probe; macOS additionally uses microsecond-resolution `EPOCHREALTIME` to bound
  its reactive-capture wait
- The cache holds only the current selection state; stale entries are not accumulated

</details>

<details>
<summary><b>Clipboard Operation Responsiveness</b></summary>

The following tables document clipboard operation latency for the plugin's custom agents, measured with
`clock_gettime(CLOCK_MONOTONIC)` across multiple payload sizes and iteration counts. These benchmarks compare standard clipboard tools (xclip and wl-copy) against the plugin's custom agents. All measurements include
full end-to-end time: from operation initiation through data availability.

**X11 Clipboard Latency:**

| Test Scenario                          | xclip Avg    | Plugin Avg   | Improvement      |
| -------------------------------------- | ------------ | ------------ | ---------------- |
| Small text (50 chars, 100 iterations)  | 4.025 ms     | 2.258 ms     | **43.9% faster** |
| Medium text (500 chars, 50 iterations) | 4.307 ms     | 2.211 ms     | **48.7% faster** |
| Large text (5KB, 25 iterations)        | 3.949 ms     | 2.310 ms     | **41.5% faster** |
| Very large (50KB, 10 iterations)       | 4.451 ms     | 2.499 ms     | **43.9% faster** |
| Rapid consecutive (200 iterations)     | 4.206 ms     | 2.321 ms     | **44.8% faster** |
| **Overall Average**                    | **4.187 ms** | **2.320 ms** | **44.6% faster** |

**Wayland Clipboard Latency:**

| Test Scenario                          | wl-copy Avg   | Plugin Avg   | Improvement      |
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

`wl-copy` forks a new process for every clipboard operation, adding approximately 60 ms of `fork()+exec()`
and IPC overhead regardless of payload size. `xclip` also forks per operation, but its overhead is
approximately 4.2 ms — one order of magnitude lower. The persistent agent eliminates the process spawn cost
on both platforms; the remaining latency is the native protocol IPC round-trip time.

**Clipboard Server Behavior:**

- The agent maintains clipboard ownership and responds to paste requests internally, without involving the
  shell process
- On X11/XWayland, the clipboard server exits when another application takes clipboard ownership
  (`SelectionClear` event), or after approximately 50 seconds if the selection was never requested; once it
  has served a paste the idle timeout is latched off and the content stays available until ownership changes
- On Wayland, the clipboard server exits when the compositor signals ownership loss via the `cancelled`
  callback
- If the compiled agents are unavailable, the plugin falls back to standard platform clipboard
  tools — `xclip` (X11), `wl-paste`/`wl-copy` (Wayland), `pbpaste`/`pbcopy` (macOS),
  `powershell.exe Get-Clipboard`/`clip.exe` (WSL) — all functionality is preserved

> **Benchmark Methodology:** Tests conducted using purpose-built C benchmarking tools with
> `clock_gettime(CLOCK_MONOTONIC)` for nanosecond accuracy. Each iteration measures the full end-to-end path
> including process spawn, IPC, and data transfer. The benchmark suite is available in
> [`assets/benchmarks/`](assets/benchmarks/).

</details>

---

## Manual Agents Build (optional)

The plugin uses pre-built portable binaries by default. If you prefer to compile native agents yourself for an optimized build (`-march=native -mtune=native`), this section provides guidance on how to do so.

> [!TIP]
> You can build agents from source and automatically install missing build dependencies with:
>
> ```bash
> edit-select build
> ```

<details>
<summary><b>How to check if you're using X11 or Wayland</b></summary>

Run this command in your terminal:

```bash
echo $XDG_SESSION_TYPE
```

- If it returns `x11` → you are using X11
- If it returns `wayland` → you are using Wayland

> **Note:** The plugin automatically detects your display server and loads the appropriate implementation.


</details>

<details>
<summary><b>Display Server Override</b></summary>

> **Use case:** Force a specific implementation if auto-detection fails or if you want to use a different
> display server intentionally.

### Environment Variables

```bash
# Force a specific implementation (overrides auto-detection)
export ZES_FORCE_IMPL=x11    # Force X11 implementation
export ZES_FORCE_IMPL=wayland # Force Wayland implementation
```

Or:

```bash
env -u DISPLAY ZES_FORCE_IMPL=x11 zsh # Force X11 implementation
env -u DISPLAY ZES_FORCE_IMPL=wayland zsh # Force Wayland implementation
```

</details>

Install the required build tools and libraries for your platform:

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

### For macOS Users

<details>
<summary><b>macOS</b></summary>

```bash
xcode-select --install
```

The macOS agent is built with Apple Command Line Tools (`clang` + SDK frameworks). No Homebrew build packages are required for agent compilation.

</details>

### For WSL Users

<details>
<summary><b>Debian/Ubuntu (WSL)</b></summary>

```bash
sudo apt install build-essential gcc-mingw-w64-x86-64
```

Also install Wayland dependencies:

```bash
sudo apt install libx11-dev libxfixes-dev libwayland-dev wayland-protocols pkg-config wl-clipboard
```

</details>

<details>
<summary><b>Other WSL distros</b></summary>

Install the equivalent packages for:

- Native Linux build toolchain (`gcc`, `make`)
- MinGW x86_64 cross-compiler providing `x86_64-w64-mingw32-gcc`
- XWayland headers (`libx11` + `libxfixes` development packages)
- Wayland build dependencies (`libwayland` development package + `wayland-protocols` + `wl-clipboard`)
- `pkg-config`

</details>

WSL source builds compile two binaries from `impl-wsl/backends/wsl`:

- `zes-wsl-selection-agent` (Linux ELF)
- `zes-wsl-clipboard-helper.exe` (Windows PE via MinGW x86_64 cross-compiler)

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

Contributions and suggestions are welcome. If you encounter a bug or unexpected behavior,
please [open an issue](https://github.com/Michael-Matta1/zsh-edit-select/issues) with a clear description and
steps to reproduce.

Pull requests are open for any meaningful improvement — bug fixes, new features, or compatibility with additional environments.

If you have ideas for enhancements, feature requests, or documentation improvements, feel free to share them.

Your feedback helps shape the direction of the project and ensures it meets the needs of the community. If
something does not work as expected, please report it — every issue report directly improves the plugin's
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
