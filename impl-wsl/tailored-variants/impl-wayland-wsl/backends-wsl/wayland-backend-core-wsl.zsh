# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# Wayland backend — auto-detects XWayland (invisible) vs pure Wayland monitor.
# Daemon writes to cache files; shell reads via builtins (zero forks during typing).

# XWayland is preferred over pure Wayland when $DISPLAY is set, because the
# XWayland agent skips the Wayland protocol stack entirely and reads selection
# state directly through X11 atoms.  This is simpler and avoids the surface
# mapping requirement that Mutter imposes on Wayland clients.
# The pure-Wayland fallback agent is reused from the impl-wayland backend
# tree (outside tailored-variants/) so it shares the existing build targets.
typeset -g _ZES_TAILORED_BACKEND_REAL_DIR="${${(%):-%x}:A:h}/../../../../impl-wayland/backends"
typeset -g _ZES_WSL_XWAYLAND_AGENT_DIR="${${(%):-%x}:A:h}/xwayland"
typeset -g _ZES_WSL_HELPER_EXE="${${(%):-%N}:A:h:h:h:h}/backends/wsl/zes-wsl-clipboard-helper.exe"

# Binary detection uses -s (non-empty file) instead of -x because on WSL2's
# DrvFs mounts (/mnt/c/…) the POSIX execute bit may not be set even though
# the kernel can still exec ELF binaries. A chmod +x acts as a best-effort fix.
#
# Provisioning strategy (same download-first pattern as the top-level loader):
#   1. Binary already present → nothing to do.
#   2. Download prebuilt from the latest GitHub Release via fetch-agents.zsh.
#      The release asset is named zes-wsl-xwayland-agent (distinct from the
#      generic zes-xwayland-agent) to make it clear this binary carries WSLg
#      clipboard-bridging support (--monitor-clipboard).
#   3. Download failed or offline → compile from source with `make`.
#   4. Both failed → fall back silently to pure-Wayland monitor below.
if [[ -n "${DISPLAY:-}" ]] && \
   [[ ! -s "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" ]]; then

  # Resolve plugin root: this file lives at
  #   impl-wsl/tailored-variants/impl-wayland-wsl/backends-wsl/wayland-backend-core-wsl.zsh
  # Five :h steps reach the plugin root where assets/ lives (backends-wsl →
  # impl-wayland-wsl → tailored-variants → impl-wsl → plugin root).
  local _zes_wsl_root="${${(%):-%N}:A:h:h:h:h:h}"

  # Source the shared fetch helper if not already loaded (it may have been
  # sourced earlier by loader-build.wsl.zsh for the main WSL agents).
  if ! (( ${+functions[_zes_fetch_binary]} )); then
    # || true: inherited err_return/err_exit would abort the load on a fetch
    # failure; the make fallback below handles a genuine failure.
    source "${_zes_wsl_root}/assets/fetch-agents.zsh" 2>/dev/null || true
  fi

  # Try download first.
  if (( ${+functions[_zes_fetch_binary]} )); then
    _zes_fetch_binary "zes-wsl-xwayland-agent" \
      "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" 2>/dev/null || true
  fi

  # Fallback: compile from source (developer / offline path).
  if [[ ! -s "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" ]] && \
     [[ -f "$_ZES_WSL_XWAYLAND_AGENT_DIR/Makefile" ]] && \
     [[ -w "$_ZES_WSL_XWAYLAND_AGENT_DIR" ]]; then
    ( cd "$_ZES_WSL_XWAYLAND_AGENT_DIR" && make ) >/dev/null 2>&1 || true
  fi

  # Ensure the execute bit is set regardless of how the binary arrived.
  [[ -f "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" ]] && \
    chmod +x "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" 2>/dev/null || true

  unset _zes_wsl_root
fi
if [[ -n "${DISPLAY:-}" ]] && [[ -s "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" ]]; then
    [[ ! -x "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" ]] && chmod +x "$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent" 2>/dev/null || true
    # Pass --monitor-clipboard for the WSL XWayland agent to track Windows Terminal clipboard
    typeset -g _ZES_MONITOR_BINARY="$_ZES_WSL_XWAYLAND_AGENT_DIR/zes-xwayland-agent"
    typeset -g _ZES_MONITOR_BINARY_ARGS="--monitor-clipboard"
    typeset -g _ZES_MONITOR_TYPE="x11"
elif [[ -s "$_ZES_TAILORED_BACKEND_REAL_DIR/wayland/zes-wl-selection-agent" ]]; then
    chmod +x "$_ZES_TAILORED_BACKEND_REAL_DIR/wayland/zes-wl-selection-agent" 2>/dev/null || true
    typeset -g _ZES_MONITOR_BINARY="$_ZES_TAILORED_BACKEND_REAL_DIR/wayland/zes-wl-selection-agent"
    typeset -g _ZES_MONITOR_BINARY_ARGS=""
    typeset -g _ZES_MONITOR_TYPE="wayland"
else
    # Neither display-server agent was found.
    # Fall back to the WSL-native helper pair under impl-wsl/backends/wsl:
    #   zes-wsl-selection-agent      (Linux ELF)
    #   zes-wsl-clipboard-helper.exe (Windows PE)
    local _zes_wsl_root="${${(%):-%N}:A:h:h:h:h}"
    local _zes_wsl_helpers_dir="$_zes_wsl_root/backends/wsl"
    local _zes_wsl_agent="$_zes_wsl_helpers_dir/zes-wsl-selection-agent"

    # If the WSL agent is missing, provision artifacts now.
    if [[ ! -s "$_zes_wsl_agent" ]]; then
        local _zes_wsl_loader="$_zes_wsl_root/loader-build.wsl.zsh"
        if [[ -r "$_zes_wsl_loader" ]]; then
            # `|| true` on the source/build/unfunction below: an inherited
            # err_return/err_exit would otherwise abort the load here on a
            # best-effort failure; the agent-presence check gating this block
            # is the real test.
            source "$_zes_wsl_loader" 2>/dev/null || true
            _zes_loader_build_wsl_artifacts "$_zes_wsl_root" 2>/dev/null || true
            unfunction _zes_loader_build_wsl_artifacts _zes_loader_build_if_missing 2>/dev/null || true
        fi
    fi

    [[ -f "$_zes_wsl_agent" && ! -x "$_zes_wsl_agent" ]] && chmod +x "$_zes_wsl_agent" 2>/dev/null || true

    if [[ -s "$_zes_wsl_agent" ]]; then
        typeset -g _ZES_MONITOR_BINARY="$_zes_wsl_agent"
        typeset -g _ZES_MONITOR_BINARY_ARGS=""
        typeset -g _ZES_MONITOR_TYPE="wsl"
    else
        # All agents unavailable — clipboard functions will fall back to
        # clip.exe / powershell.exe.
        typeset -g _ZES_MONITOR_BINARY=""
        typeset -g _ZES_MONITOR_BINARY_ARGS=""
        typeset -g _ZES_MONITOR_TYPE=""
    fi

    unset _zes_wsl_root _zes_wsl_helpers_dir _zes_wsl_agent _zes_wsl_loader
fi

# Self-write suppression for WSL CLIPBOARD monitoring.  When the plugin
# copies text to the clipboard (Ctrl+C / Ctrl+X), the WSLg bridge causes
# a round-trip CLIPBOARD event.  This variable records the content of the
# last self-initiated copy so the selection detector can suppress it.
typeset -g _ZES_SELF_WRITE_CONTENT=""

# Detect whether running on WSL for clipboard fallback behavior.
typeset -gi _ZES_ON_WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    _ZES_ON_WSL=1
elif [[ -r /proc/version ]]; then
    { _zes_proc_version="$(</proc/version)" } 2>/dev/null
    if [[ "$_zes_proc_version" == *[Mm]icrosoft* ]] || [[ "$_zes_proc_version" == *[Ww][Ss][Ll]* ]]; then
        _ZES_ON_WSL=1
    fi
    unset _zes_proc_version
fi

# SSH mode flag — detected once at load time for zero per-call overhead.
# 1 = SSH session detected and OSC 52 clipboard passthrough is active.
# 0 = native clipboard backend in use (local session or user opt-out).
# ZES_SSH_CLIPBOARD=0 in ~/.zshrc before plugin load disables SSH mode.
typeset -gi _ZES_SSH_MODE=0
[[ "${ZES_SSH_CLIPBOARD:-1}" != "0" ]] && \
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" || -n "${SSH_CONNECTION:-}" ]] && \
    _ZES_SSH_MODE=1

# Detect VS Code terminal. VS Code's xterm.js clears visible selections when
# mouse tracking is toggled back on, but it preserves native selection when
# Shift is held. The VS Code path therefore uses a helper-side Shift override
# instead of DECSET off/on toggling, keeping tracking ready immediately.
typeset -gi _ZES_IS_VSCODE=0
[[ "${TERM_PROGRAM:-}" == "vscode" || -n "${VSCODE_INJECTION:-}" ]] && _ZES_IS_VSCODE=1

# Start the background selection agent and wait until it signals readiness.
# The agent writes an initial seq file on startup, before daemonising; waiting
# for that file avoids a fixed sleep and verifies the agent is live.
# Sets _EDIT_SELECT_DAEMON_ACTIVE=1 on success, 0 on failure.
function _zes_start_monitor() {
    # Ensure the cache directory exists (created once per session).
    # || true on the three best-effort filesystem commands below: their status is
    # unobserved (the checks that follow re-derive state from the filesystem), so
    # under inherited err_return/err_exit a failure must not abort before the
    # readiness resolution at the end — that would strand a stale
    # _EDIT_SELECT_DAEMON_ACTIVE=1 with no daemon running.
    [[ -d "$_EDIT_SELECT_CACHE_DIR" ]] || mkdir -p -m 0700 "$_EDIT_SELECT_CACHE_DIR" >/dev/null 2>&1 || true

    if [[ -z "$_ZES_MONITOR_BINARY" ]] || [[ ! -s "$_ZES_MONITOR_BINARY" ]]; then
        # No agent binary available — clipboard ops fall back to
        # powershell.exe (WSL) or wl-paste / wl-copy (non-WSL).
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi

    if [[ -f "$_EDIT_SELECT_PID_FILE" ]]; then
        local pid
        { pid=$(<"$_EDIT_SELECT_PID_FILE") || true } 2>/dev/null
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Daemon already running; reuse it.
            _EDIT_SELECT_DAEMON_ACTIVE=1
            return 0
        fi
        # Stale PID file from a crashed or killed daemon.
        rm -f "$_EDIT_SELECT_PID_FILE" 2>/dev/null || true
    fi

    # Remove stale cache files so the readiness check below cannot succeed
    # on data written by a previous daemon instance.
    rm -f "$_EDIT_SELECT_SEQ_FILE" "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true

    # Launch the agent in a disowned background subshell so it survives
    # shell exit and does not generate job-control noise.
    (
        if [[ -n "${_ZES_MONITOR_BINARY_ARGS:-}" ]]; then
            "$_ZES_MONITOR_BINARY" "$_EDIT_SELECT_CACHE_DIR" ${=_ZES_MONITOR_BINARY_ARGS} &>/dev/null &
        else
            "$_ZES_MONITOR_BINARY" "$_EDIT_SELECT_CACHE_DIR" &>/dev/null &
        fi
        disown 2>/dev/null || true
    )

    # Poll for the seq file to appear (agent readiness signal); give up
    # after 1 s (40 × 25 ms).
    local wait_count=0
    while [[ ! -f "$_EDIT_SELECT_SEQ_FILE" ]] && ((wait_count < 40)); do
        sleep 0.025
        ((++wait_count))
    done

    if [[ -f "$_EDIT_SELECT_SEQ_FILE" ]]; then
        _EDIT_SELECT_DAEMON_ACTIVE=1
        return 0
    else
        _EDIT_SELECT_DAEMON_ACTIVE=0
        return 1
    fi
}

# Return the current PRIMARY selection text to stdout.
# Three-level priority:
#   1. Daemon cache file — zero forks, optimal hot path during typing.
#   2. Agent --oneshot mode — used when daemon is off but the binary exists;
#      on Mutter the agent briefly maps a tiny unfocused surface so the
#      compositor delivers the selection to it.
#   3. powershell.exe (WSL) / wl-paste (non-WSL) — last resort when
#      no agent binary is available.
function _zes_get_primary() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        local primary_data
        { primary_data=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        [[ -n "$primary_data" ]] && printf '%s' "$primary_data" && return 0
        return 1
    fi

    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -s "$_ZES_MONITOR_BINARY" ]]; then
        if "$_ZES_MONITOR_BINARY" --oneshot 2>/dev/null; then
            return 0
        fi
    fi

    if ((_ZES_ON_WSL)); then
        powershell.exe -NoProfile -Command 'Get-Clipboard' 2>/dev/null
    else
        wl-paste --primary --no-newline 2>/dev/null
    fi
}

# Return the current clipboard (CLIPBOARD selection) text to stdout.
# In SSH mode (_ZES_SSH_MODE=1), returns 1 — paste via terminal native keybinding.
function _zes_get_clipboard() {
    ((_ZES_SSH_MODE)) && return 1
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -s "$_ZES_MONITOR_BINARY" ]]; then
        if "$_ZES_MONITOR_BINARY" --get-clipboard 2>/dev/null; then
            return 0
        fi
    fi

    if ((_ZES_ON_WSL)); then
        powershell.exe -NoProfile -Command 'Get-Clipboard' 2>/dev/null
    else
        wl-paste --no-newline 2>/dev/null
    fi
}

# Place $1 into the clipboard.  The agent forks a background child that serves
# paste requests until another application takes ownership, returning immediately
# so the shell is never blocked waiting for a paste to occur.
# On WSL, also records the written content for self-write suppression.
# In SSH mode (_ZES_SSH_MODE=1), uses OSC 52 to tunnel the write to the local terminal.
# NOTE: _ZES_SELF_WRITE_CONTENT is intentionally NOT set in SSH mode — the write
# goes via OSC 52 and never reaches the Windows clipboard, so there is nothing to
# suppress. Setting it would cause the suppression logic in _zes_sync_selection_state
# to incorrectly swallow the next real mouse selection event.
function _zes_copy_to_clipboard() {
    [[ -z "$1" ]] && return 1
    if ((_ZES_SSH_MODE)); then
        local _zes_encoded _zes_copy_rc
        # -w 0: suppress GNU base64 line-wrapping (default is 76 chars).
        # Embedded newlines in the encoded output would corrupt the OSC 52 sequence.
        _zes_encoded=$(printf '%s' "$1" | base64 -w 0) || return $?
        if [[ -n "${TMUX:-}" ]]; then
            # tmux requires DCS passthrough wrapping with doubled inner ESC.
            printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        elif [[ -n "${STY:-}" ]]; then
            # GNU Screen requires DCS passthrough wrapping.
            printf '\033P\033]52;c;%s\a\033\\' "$_zes_encoded" > /dev/tty
        else
            printf '\033]52;c;%s\a' "$_zes_encoded" > /dev/tty
        fi
        # Propagate the tty-write status so a failed OSC 52 copy surfaces as a
        # nonzero rc to the cut widget (which gates deletion on it) instead of
        # deleting text that was never copied.  No change on the success path.
        _zes_copy_rc=$?
        return $_zes_copy_rc
    fi
    ((_ZES_ON_WSL)) && _ZES_SELF_WRITE_CONTENT="$1"
    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -s "$_ZES_MONITOR_BINARY" ]]; then
        if printf '%s' "$1" | "$_ZES_MONITOR_BINARY" --copy-clipboard 2>/dev/null; then
            return 0
        fi
    fi

    if ((_ZES_ON_WSL)); then
        # Capture the failure status in the OR-branch rather than from a
        # following `$?` read: under inherited err_return/err_exit a failing
        # pipeline aborts the function at that point, skipping the marker
        # rollback below.  The `=0` initialiser is load-bearing — the success
        # path never enters the OR-branch, and a bare `return $_zes_copy_rc`
        # with an unset value would report failure after a successful copy.
        local _zes_copy_rc=0
        printf '%s' "$1" | clip.exe 2>/dev/null || _zes_copy_rc=$?
        # Roll back the self-write marker if the copy failed; otherwise a failed copy would
        # leave the marker set and suppress the next REAL mouse selection of the same text
        # (the WSLg round-trip that would have justified suppression never happened).
        (( _zes_copy_rc )) && _ZES_SELF_WRITE_CONTENT=""
        return $_zes_copy_rc
    else
        printf '%s' "$1" | wl-copy 2>/dev/null
    fi
}

# Clear the PRIMARY selection.  Called after a mouse-selected region is
# consumed to prevent accidental reuse of the highlighted text.
#
# WSL-native monitor: clear only the primary cache locally.  The daemon must
#   remain the sole owner of seq progression; advancing seq in a short-lived
#   process can collide with its in-memory counter and hide the next event.
#
# XWayland / Wayland agents (--clear-primary): only clear the compositor's
#   selection state (X11 or Wayland) without touching cache files.  Local
#   truncate is needed to prevent stale reads before the next event arrives.
function _zes_clear_primary() {
    if [[ "$_ZES_MONITOR_TYPE" == "wsl" ]]; then
        [[ -n "${_EDIT_SELECT_PRIMARY_FILE:-}" ]] && \
            : > "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true
        return 0
    fi

    if [[ -n "$_ZES_MONITOR_BINARY" ]] && [[ -s "$_ZES_MONITOR_BINARY" ]]; then
        "$_ZES_MONITOR_BINARY" --clear-primary 2>/dev/null || true
    else
        printf '' | wl-copy --primary 2>/dev/null || true
    fi

    # Clear local cache immediately so the next keypress cannot re-read
    # stale repeated text before async agent/compositor updates arrive.
    [[ -n "${_EDIT_SELECT_PRIMARY_FILE:-}" ]] && : > "$_EDIT_SELECT_PRIMARY_FILE" 2>/dev/null || true
}

# Check copyOnSelect in Windows Terminal settings. Returns 0 only when
# explicitly enabled, and 1 when disabled or not detectable. On WSL,
# copyOnSelect=false is the recommended mode because it preserves normal
# terminal selection behavior while the plugin provides integrated tracking.
function _zes_wsl_find_terminal_settings_path() {
    ((!_ZES_ON_WSL)) && return 1

    local preferred="/mnt/c/Users/${USER}/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
    if [[ -r "$preferred" ]]; then
        REPLY="$preferred"
        return 0
    fi

    local -a matches=(/mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json(N))
    (( ${#matches[@]} )) || return 1
    REPLY="${matches[1]}"
    return 0
}

function _zes_wsl_check_copyonselect() {
    ((!_ZES_ON_WSL)) && return 1
    local settings_path
    _zes_wsl_find_terminal_settings_path || return 1
    settings_path="$REPLY"
    # Zero-fork check: read the settings file line-by-line using a builtin
    # to avoid forking grep, but ensure we only check the true/false value
    # on the exact line containing "copyOnSelect".
    setopt localoptions extendedglob
    local line trimmed
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Windows Terminal's settings.json is JSONC and permits // comments.
        # Skip commented lines so a commented-out example (e.g.
        # `// "copyOnSelect": true`) is not misread as an active setting.
        trimmed="${line##[[:space:]]#}"
        [[ "$trimmed" == '//'* ]] && continue
        if [[ "$line" == *'"copyOnSelect"'*':'* ]]; then
            [[ "$line" == *true* ]] && return 0
            return 1
        fi
    done < "$settings_path" 2>/dev/null
    return 1
}

# ======================================================================
# WSL ZSH Mouse Tracking
# ======================================================================
#
# On WSL2, Windows Terminal does not set X11 PRIMARY on mouse selection.
# Instead of relying on copyOnSelect (which changes terminal behavior),
# native ZSH mouse tracking is implemented using SGR extended mouse mode.
#
# When enabled, the terminal forwards mouse events to ZSH as escape
# sequences instead of doing its own selection. These events are parsed,
# map screen coordinates to BUFFER positions, and use ZLE's native
# REGION_ACTIVE / MARK / CURSOR mechanism for selection.  This integrates
# seamlessly with the existing edit-select keymap (type-to-replace, cut,
# copy, delete).
#
# The mouse tracking is ONLY enabled on WSL — native Linux terminals
# use X11 PRIMARY which works without intervention.
# ======================================================================

# Global state for mouse tracking.
typeset -gi _ZES_MOUSE_TRACKING=0          # 1 when mouse tracking is active
typeset -gi _ZES_MOUSE_PROMPT_BASE_ROW=0   # screen row where BUFFER starts (1-based)
typeset -gi _ZES_MOUSE_PROMPT_WIDTH=0      # visible columns of last prompt line
typeset -gi _ZES_MOUSE_SELECTING=0         # 1 during click-drag
typeset -gi _ZES_MOUSE_ANCHOR=-1           # BUFFER pos of initial click
typeset -gi _ZES_MOUSE_AUTOSUSPENDED=0     # 1 when tracking was suspended for free selection
typeset -g _ZES_MOUSE_LAST_HIT_REGION="inside" # inside|above|below|left|outside
typeset -g _ZES_WSL_MOUSE_MODE="tracking" # tracking | terminal | disabled
# Multi-click detection (double-click = word, triple-click = line).
typeset -gi _ZES_MOUSE_CLICK_COUNT=0       # consecutive click count
typeset -gF _ZES_MOUSE_LAST_CLICK_TIME=0  # EPOCHREALTIME of last press
typeset -gi _ZES_MOUSE_LAST_CLICK_POS=-1  # BUFFER pos of last press
typeset -gF _ZES_MOUSE_MULTI_CLICK_THRESHOLD=0.4  # seconds
typeset -gi _ZES_WSL_HELPER_HANDOFF_READY=-1      # -1 unknown, 0 no, 1 yes
typeset -gi _ZES_WSL_HELPER_HANDOFF_REBUILD_TRIED=0
typeset -g _ZES_WSL_HELPER_HANDOFF_MODE=""       # "" | atomic | legacy (helper handoff API)
typeset -gi _ZES_WSL_HELPER_VSCODE_HANDOFF_READY=-1
typeset -gi _ZES_WSL_HELPER_VSCODE_HANDOFF_REBUILD_TRIED=0

# Select the WSL mouse strategy.
# WSL mouse strategy:
# - ZES_WSL_MOUSE_MODE=terminal  -> force native terminal selection mode
# - ZES_WSL_MOUSE_MODE=tracking  -> force ZLE tracking mode
# - unset (default)              -> auto (recommended: tracking when
#                                   copyOnSelect=false; terminal when true)

function _zes_refresh_wsl_mouse_mode() {
    if ((!_ZES_ON_WSL)); then
        _ZES_WSL_MOUSE_MODE="disabled"
    elif [[ "${ZES_WSL_MOUSE_MODE:-}" == "tracking" ]]; then
        _ZES_WSL_MOUSE_MODE="tracking"
    elif [[ "${ZES_WSL_MOUSE_MODE:-}" == "terminal" ]]; then
        _ZES_WSL_MOUSE_MODE="terminal"
    elif _zes_wsl_check_copyonselect; then
        _ZES_WSL_MOUSE_MODE="terminal"
    else
        _ZES_WSL_MOUSE_MODE="tracking"
    fi
}

# Calculate the visible width of the last line of the prompt.
# Strips ANSI CSI/OSC escape sequences using ZSH extended glob.
function _zes_calc_prompt_width() {
    emulate -L zsh
    setopt extended_glob
    local exp=${(%%)PROMPT}
    # Multiline prompt: take only the last line
    local last=${exp##*$'\n'}
    # Strip CSI sequences: \e[ ... <letter>
    last=${last//$'\e'\[[^a-zA-Z]#[a-zA-Z]/}
    # Strip OSC sequences: \e] ... BEL
    last=${last//$'\e'\][^$'\a']#$'\a'/}
    # Strip OSC sequences: \e] ... ST (ESC backslash) — e.g. OSC 8 hyperlinks
    last=${last//$'\e'\][^$'\e']#$'\e\\'/}
    # Strip remaining lone escapes
    last=${last//$'\e'/}
    _ZES_MOUSE_PROMPT_WIDTH=${#last}
}

# precmd hook: before the prompt is drawn, compute prompt metrics.
# This lets us map screen coordinates to BUFFER positions.
function _zes_mouse_precmd() {
    ((_ZES_MOUSE_TRACKING)) || return
    # Calculate prompt metrics (width of the last line)
    _zes_calc_prompt_width
}

# Query the current cursor position via DSR and return the prompt's base row.
# This runs only during mouse interaction, so the response can be consumed
# synchronously without leaking into subsequent shell input.
function _zes_refresh_mouse_prompt_base_row() {
    local -i tw=$COLUMNS
    ((tw < 1)) && tw=1
    local -i pw=$_ZES_MOUSE_PROMPT_WIDTH

    # Compute cursor row offset from prompt base using O(rows) chunking
    # instead of O(CURSOR) character-by-character iteration.
    local -i cursor_rel_row=0
    local -i cursor_col=$((pw + 1))
    while ((cursor_col > tw)); do
        ((++cursor_rel_row))
        ((cursor_col -= tw))
    done

    local -i cur=$CURSOR
    local -i blen=${#BUFFER}
    ((cur < 0)) && cur=0
    ((cur > blen)) && cur=$blen

    local -i i=0 rem_len nl_idx
    local segment prefix
    local -i start_col=$cursor_col
    while ((i < cur)); do
        rem_len=$((tw - start_col + 1))
        ((rem_len > cur - i)) && rem_len=$((cur - i))
        segment="${BUFFER:$i:$rem_len}"

        if [[ "$segment" == *$'\n'* ]]; then
            prefix="${segment%%$'\n'*}"
            nl_idx=${#prefix}
            ((++cursor_rel_row))
            start_col=1
            i=$((i + nl_idx + 1))
        elif ((i + rem_len >= cur)); then
            # Reached the cursor position within this row
            break
        else
            # Full row consumed — wrap
            ((++cursor_rel_row))
            start_col=1
            i=$((i + rem_len))
        fi
    done

    local response="" char=""
    local tty_fd
    exec {tty_fd}<>/dev/tty 2>/dev/null || {
        _ZES_MOUSE_PROMPT_BASE_ROW=$((LINES - cursor_rel_row))
        ((_ZES_MOUSE_PROMPT_BASE_ROW < 1)) && _ZES_MOUSE_PROMPT_BASE_ROW=1
        return 1
    }

    printf '\e[6n' >&$tty_fd 2>/dev/null || {
        exec {tty_fd}>&-
        _ZES_MOUSE_PROMPT_BASE_ROW=$((LINES - cursor_rel_row))
        ((_ZES_MOUSE_PROMPT_BASE_ROW < 1)) && _ZES_MOUSE_PROMPT_BASE_ROW=1
        return 1
    }

    while read -ru $tty_fd -sk 1 -t 0.1 char; do
        response+="$char"
        [[ "$char" == 'R' ]] && break
    done
    exec {tty_fd}>&-

    if [[ "$response" == $'\e['*'R' ]]; then
        local payload=${response#$'\e['}
        payload=${payload%R}
        local -a cpr_parts=("${(@s:;:)payload}")
        if [[ -n ${cpr_parts[1]:-} ]] && [[ ${cpr_parts[1]} == <-> ]]; then
            local -i cursor_row=${cpr_parts[1]}
            _ZES_MOUSE_PROMPT_BASE_ROW=$((cursor_row - cursor_rel_row))
            ((_ZES_MOUSE_PROMPT_BASE_ROW < 1)) && _ZES_MOUSE_PROMPT_BASE_ROW=1
            return 0
        fi
    fi

    _ZES_MOUSE_PROMPT_BASE_ROW=$((LINES - cursor_rel_row))
    ((_ZES_MOUSE_PROMPT_BASE_ROW < 1)) && _ZES_MOUSE_PROMPT_BASE_ROW=1
    return 1
}

# Convert screen coordinates (1-based) to BUFFER position (0-based).
# Uses the prompt base row captured at mouse-press time from a synchronous
# cursor-position query, so it remains correct even when the prompt is not on
# the terminal's bottom row. Handles explicit newlines and wrapped rows.
# Returns result in REPLY; -1 if outside the buffer area.
function _zes_screen_to_buffer_pos() {
    local -i sx=$1 sy=$2
    local -i tw=$COLUMNS
    ((tw < 1)) && tw=1
    local -i base_row=$_ZES_MOUSE_PROMPT_BASE_ROW
    ((base_row < 1)) && base_row=1

    _ZES_MOUSE_LAST_HIT_REGION="outside"

    # Compute first editable cell (prompt may itself wrap).
    local -i first_row=$base_row
    local -i first_col=$((_ZES_MOUSE_PROMPT_WIDTH + 1))
    while ((first_col > tw)); do
        ((first_row++))
        ((first_col -= tw))
    done

    local -i buf_len=${#BUFFER}
    local -a row_start_idx row_end_idx row_start_col
    local -i row_count=0

    if ((buf_len == 0)); then
        row_count=1
        row_start_idx[1]=0
        row_end_idx[1]=0
        row_start_col[1]=$first_col
    else
        local -i start_idx=0
        local -i start_col=$first_col
        local -i i=0
        local -i rem_len
        local segment prefix
        local -i nl_idx

        # Optimized O(rows) chunking instead of O(N) character iteration
        while (( i < buf_len )); do
            rem_len=$(( tw - start_col + 1 ))
            segment="${BUFFER:$i:$rem_len}"

            if [[ "$segment" == *$'\n'* ]]; then
                prefix="${segment%%$'\n'*}"
                nl_idx=${#prefix}

                ((++row_count))
                row_start_idx[$row_count]=$start_idx
                row_end_idx[$row_count]=$(( i + nl_idx ))
                row_start_col[$row_count]=$start_col

                start_col=1
                i=$(( i + nl_idx + 1 ))
                start_idx=$i
            elif (( i + rem_len <= buf_len )); then
                ((++row_count))
                row_start_idx[$row_count]=$start_idx
                row_end_idx[$row_count]=$(( i + rem_len ))
                row_start_col[$row_count]=$start_col

                start_col=1
                i=$(( i + rem_len ))
                start_idx=$i
            else
                break
            fi
        done

        ((++row_count))
        row_start_idx[$row_count]=$start_idx
        row_end_idx[$row_count]=$buf_len
        row_start_col[$row_count]=$start_col
    fi

    local -i row_index=$((sy - first_row + 1))
    if ((row_index < 1 || row_index > row_count)); then
        if ((row_index < 1)); then
            _ZES_MOUSE_LAST_HIT_REGION="above"
        else
            _ZES_MOUSE_LAST_HIT_REGION="below"
        fi
        REPLY=-1
        return
    fi

    local -i start=${row_start_idx[$row_index]}
    local -i end=${row_end_idx[$row_index]}
    local -i min_col=${row_start_col[$row_index]}

    # Left of the editable region (prompt gutter on first row).
    if ((sx < min_col)); then
        _ZES_MOUSE_LAST_HIT_REGION="left"
        REPLY=-1
        return
    fi

    local -i offset=$((sx - min_col))
    local -i max_offset=$((end - start))
    ((offset > max_offset)) && offset=$max_offset

    _ZES_MOUSE_LAST_HIT_REGION="inside"
    REPLY=$((start + offset))
}

# ZLE widget: handle SGR mouse events.
# Triggered by binding \e[< — reads the rest of the SGR sequence from
# the terminal input to get button/column/row/press-or-release.
function _zes_mouse_event_handler() {
    local buf="" c=""
    local MATCH
    local -a match mbegin mend
    # Read until obtaining M (press/motion) or m (release).
    # The SGR bytes are pre-buffered in ZLE's unget queue so read
    # returns immediately; -t 0.5 is a safety-net for broken sequences.
    while read -rsk 1 -t 0.5 c; do
        if [[ "$c" == 'M' || "$c" == 'm' ]]; then
            break
        fi
        buf+="$c"
    done
    [[ -z "$c" || ( "$c" != 'M' && "$c" != 'm' ) ]] && return

    # Parse: button;column;row
    local -a parts=("${(@s:;:)buf}")
    local -i button=${parts[1]:-0}
    local -i mx=${parts[2]:-1}     # 1-based column
    local -i my=${parts[3]:-1}     # 1-based row
    local event_type="$c"          # M=press/motion, m=release

    # Button codes in SGR mode:
    #   0 = left press,  1 = middle press,  2 = right press
    #  32 = left drag,  64 = scroll up,    65 = scroll down
    local -i base_button=$((button & 3))      # 0=left, 1=mid, 2=right, 3=release
    local -i is_motion=$((button & 32))       # 32 = motion event
    local -i is_scroll=$(((button & 64) ? 1 : 0))

    # Ignore motion-without-button events if the terminal emits them.
    if ((is_motion)) && ((base_button == 3)); then
        return
    fi

    # Mouse wheel: scroll up/down navigates command history.
    if ((is_scroll)); then
        if ((button == 64)); then
            zle up-line-or-history
        elif ((button == 65)); then
            zle down-line-or-history
        fi
        return
    fi

    # Non-left clicks: when tracking mode is active, suspend it immediately
    # so the terminal can handle native right-click context menu on the next
    # click without requiring a prior left-click toggle.
    if ((base_button != 0)); then
        if [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]]; then
            _zes_disable_mouse_tracking
            _ZES_MOUSE_AUTOSUSPENDED=1
        fi
        return
    fi

    if [[ "$event_type" == 'M' ]] && ((!is_motion)); then
        _zes_refresh_mouse_prompt_base_row

        # Convert screen coords to buffer position using the prompt row derived
        # from the live cursor position.
        _zes_screen_to_buffer_pos $mx $my
        local -i buf_pos=$REPLY
        if ((buf_pos < 0)); then
            # Below-buffer clicks should place cursor at the end of BUFFER
            # without suspending tracking.
            if [[ "$_ZES_MOUSE_LAST_HIT_REGION" == "below" ]]; then
                CURSOR=${#BUFFER}
                REGION_ACTIVE=0
                _ZES_MOUSE_SELECTION_START=-1
                _ZES_MOUSE_SELECTION_LEN=0
                zle -K main
                zle -R
                return
            fi

            # Above-buffer click/drag (scrollback): hand off to the native
            # terminal selection flow and re-arm tracking on button release.
            if [[ "$_ZES_MOUSE_LAST_HIT_REGION" == "above" ]]; then
                if [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]]; then
                    _zes_handoff_to_native_scrollback
                fi
                return
            fi

            # Click outside editable BUFFER area (prompt gutter / scrollback).
            if [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]]; then
                if ((REGION_ACTIVE)) || [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                    # An active ZLE or daemon selection exists: the user intends
                    # to DESELECT (not start a free scrollback selection).  Clear
                    # the selection state but stay in tracking mode so the next
                    # double-click inside the buffer is processed by ZLE and
                    # type-to-replace continues to work correctly.
                    _zes_clear_selection_state
                else
                    # No active selection: user wants to make a free selection in
                    # the scrollback or prompt area.  Suspend tracking so the
                    # terminal can handle native selection on the next drag.
                    _zes_disable_mouse_tracking
                    _ZES_MOUSE_AUTOSUSPENDED=1
                fi
            fi
            return
        fi

        # Left button PRESS — detect multi-click (double/triple).
        local -F now=$EPOCHREALTIME
        local -F elapsed=$((now - _ZES_MOUSE_LAST_CLICK_TIME))
        if ((elapsed < _ZES_MOUSE_MULTI_CLICK_THRESHOLD && buf_pos == _ZES_MOUSE_LAST_CLICK_POS)); then
            ((++_ZES_MOUSE_CLICK_COUNT))
        else
            _ZES_MOUSE_CLICK_COUNT=1
        fi
        _ZES_MOUSE_LAST_CLICK_TIME=$now
        _ZES_MOUSE_LAST_CLICK_POS=$buf_pos

        if ((_ZES_MOUSE_CLICK_COUNT == 2)); then
            # DOUBLE-CLICK: select the word under the cursor.
            _ZES_MOUSE_SELECTING=0
            local -i wstart=$buf_pos wend=$buf_pos
            local left_str="${BUFFER:0:$buf_pos}"
            local right_str="${BUFFER:$buf_pos}"

            # Efficient backward word matching using zsh pattern matching
            if [[ "$left_str" =~ ([a-zA-Z0-9_]+)$ ]]; then
                wstart=$((buf_pos - ${#MATCH}))
            fi

            # Efficient forward word matching using zsh pattern matching
            if [[ "$right_str" =~ ^([a-zA-Z0-9_]+) ]]; then
                wend=$((buf_pos + ${#MATCH}))
            fi

            if ((wstart != wend)); then
                MARK=$wstart
                CURSOR=$wend
                REGION_ACTIVE=1
                zle -K edit-select
                local sel_text="${BUFFER:$wstart:$((wend - wstart))}"
                _EDIT_SELECT_ACTIVE_SELECTION="$sel_text"
                _ZES_MOUSE_SELECTION_START=$wstart
                _ZES_MOUSE_SELECTION_LEN=$((wend - wstart))
                _EDIT_SELECT_LAST_PRIMARY="$sel_text"
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
                _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
            fi
            zle -R
            return
        elif ((_ZES_MOUSE_CLICK_COUNT >= 3)); then
            # TRIPLE-CLICK: select the entire BUFFER line containing the cursor.
            _ZES_MOUSE_SELECTING=0
            _ZES_MOUSE_CLICK_COUNT=0   # reset so next click is single

            local -i lstart lend blen=${#BUFFER}
            local left_part="${BUFFER:0:$buf_pos}"
            local right_part="${BUFFER:$buf_pos}"

            # Find the start of the line (after the last newline in left_part)
            if [[ "$left_part" == *$'\n'* ]]; then
                local last_nl_prefix="${left_part%$'\n'*}"
                lstart=$((${#last_nl_prefix} + 1))
            else
                lstart=0
            fi

            # Find the end of the line (before the first newline in right_part)
            if [[ "$right_part" == *$'\n'* ]]; then
                local first_nl_suffix="${right_part#*$'\n'}"
                lend=$((buf_pos + ${#right_part} - ${#first_nl_suffix} - 1))
            else
                lend=$blen
            fi
            MARK=$lstart
            CURSOR=$lend
            REGION_ACTIVE=1
            zle -K edit-select
            local sel_text="${BUFFER:$lstart:$((lend - lstart))}"
            _EDIT_SELECT_ACTIVE_SELECTION="$sel_text"
            _ZES_MOUSE_SELECTION_START=$lstart
            _ZES_MOUSE_SELECTION_LEN=$((lend - lstart))
            _EDIT_SELECT_LAST_PRIMARY="$sel_text"
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
            zle -R
            return
        fi

        # Single click: start a new selection
        _ZES_MOUSE_SELECTING=1
        _ZES_MOUSE_ANCHOR=$buf_pos
        CURSOR=$buf_pos
        # Clear any existing mouse selection state
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
        _ZES_MOUSE_SELECTION_START=-1
        _ZES_MOUSE_SELECTION_LEN=0
        REGION_ACTIVE=0
        zle -K main
        zle -R   # redraw
    elif [[ "$event_type" == 'M' ]] && ((is_motion)); then
        _zes_screen_to_buffer_pos $mx $my
        local -i buf_pos=$REPLY
        ((buf_pos < 0)) && return

        # Left button DRAG: extend selection.
        # If a double/triple-click selected a word/line, drag should NOT
        # override it — only single-click drag creates freeform selections.
        if ((_ZES_MOUSE_SELECTING)); then
            MARK=$_ZES_MOUSE_ANCHOR
            CURSOR=$buf_pos
            if ((MARK != CURSOR)); then
                REGION_ACTIVE=1
                zle -K edit-select
            else
                REGION_ACTIVE=0
            fi
            zle -R   # redraw
        fi
    elif [[ "$event_type" == 'm' ]]; then
        _zes_screen_to_buffer_pos $mx $my
        local -i buf_pos=$REPLY
        ((buf_pos < 0)) && return

        # Left button RELEASE: finalise selection
        if ((_ZES_MOUSE_SELECTING)); then
            _ZES_MOUSE_SELECTING=0
            if ((REGION_ACTIVE)) && ((MARK != CURSOR)); then
                # Extract selected text and set ACTIVE_SELECTION
                local -i start=$((MARK < CURSOR ? MARK : CURSOR))
                local -i len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
                local sel_text="${BUFFER:$start:$len}"
                _EDIT_SELECT_ACTIVE_SELECTION="$sel_text"
                _ZES_MOUSE_SELECTION_START=$start
                _ZES_MOUSE_SELECTION_LEN=$len
                _EDIT_SELECT_LAST_PRIMARY="$sel_text"
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
                _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
            else
                # Click without drag: just position cursor
                CURSOR=$buf_pos
                REGION_ACTIVE=0
                _ZES_MOUSE_SELECTION_START=-1
                _ZES_MOUSE_SELECTION_LEN=0
                zle -K main
            fi
            zle -R   # redraw
        fi
    fi
}
zle -N _zes_mouse_event_handler

# Enable WSL mouse tracking: install precmd hook and mouse keybinding.
# Called from edit-select::apply-mouse-replacement-config when on WSL.
function _zes_enable_mouse_tracking() {
    ((_ZES_MOUSE_TRACKING)) && return   # already enabled
    _ZES_MOUSE_TRACKING=1
    _ZES_MOUSE_AUTOSUSPENDED=0
    # Install precmd hook for cursor position tracking
    # Install hooks for cursor tracking and command suspension
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _zes_mouse_precmd
    add-zsh-hook preexec _zes_mouse_preexec
    # Bind SGR mouse prefix in emacs and edit-select keymaps
    bindkey -M emacs '\e[<' _zes_mouse_event_handler
    bindkey -M edit-select '\e[<' _zes_mouse_event_handler
    bindkey '\e[<' _zes_mouse_event_handler
    # Enable SGR extended mouse mode (written to /dev/tty to avoid
    # interfering with instant-prompt or other output capturing).
    # 1000 = basic mouse events, 1002 = button-event tracking (drag),
    # 1006 = SGR extended format (allows coordinates > 223).
    printf '\e[?1000h\e[?1002h\e[?1006h' > /dev/tty 2>/dev/null || true
}

# Disable WSL mouse tracking: remove hooks and restore terminal.
function _zes_disable_mouse_tracking() {
    ((!_ZES_MOUSE_TRACKING)) && return
    _ZES_MOUSE_TRACKING=0
    autoload -Uz add-zsh-hook
    add-zsh-hook -d precmd _zes_mouse_precmd 2>/dev/null
    add-zsh-hook -d preexec _zes_mouse_preexec 2>/dev/null
    bindkey -M emacs -r '\e[<' 2>/dev/null
    bindkey -M edit-select -r '\e[<' 2>/dev/null
    bindkey -r '\e[<' 2>/dev/null
    # Disable mouse tracking mode
    printf '\e[?1000l\e[?1002l\e[?1006l' > /dev/tty 2>/dev/null || true
    _ZES_MOUSE_SELECTING=0
    _ZES_MOUSE_ANCHOR=-1
    _ZES_MOUSE_PROMPT_BASE_ROW=0
    _ZES_MOUSE_SELECTION_START=-1
    _ZES_MOUSE_SELECTION_LEN=0
    REGION_ACTIVE=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
    # `|| true` on both: outside ZLE these return 1 ("widgets can only be called
    # when ZLE is active"), and every caller is a preexec/handoff path that runs
    # outside it.  No call site inspects this function's status, but under a
    # user's inherited err_return the first failure aborted the function AND
    # propagated to the caller, whose next statement is
    # `_ZES_MOUSE_AUTOSUSPENDED=1`.  Losing that flag leaves
    # `_zes_resume_tracking_if_needed` with nothing to resume, so mouse tracking
    # never came back after the command finished.
    zle deactivate-region -w 2>/dev/null || true
    zle -K main 2>/dev/null || true
}

# Action-based native scrollback handoff:
# 1) disable terminal mouse reporting,
# 2) inject left-button down so the same user drag continues natively,
# 3) on physical release, inject matching left-button up,
# 4) re-enable reporting.
function _zes_wsl_helper_supports_scrollback_handoff() {
    [[ -s "$_ZES_WSL_HELPER_EXE" ]] || return 1
    local helper_help=""
    helper_help=$("$_ZES_WSL_HELPER_EXE" --help 2>&1) || true

    if [[ "$helper_help" == *"--handoff-scrollback"* ]]; then
        _ZES_WSL_HELPER_HANDOFF_MODE="atomic"
        return 0
    fi

    [[ "$helper_help" == *"--inject-left-down"* ]] || return 1
    [[ "$helper_help" == *"--inject-left-up"* ]] || return 1
    [[ "$helper_help" == *"--wait-left-up"* ]] || return 1
    _ZES_WSL_HELPER_HANDOFF_MODE="legacy"
    return 0
}

function _zes_prepare_wsl_scrollback_handoff_helper() {
    if ((_ZES_WSL_HELPER_HANDOFF_READY == 1)) && [[ -n "$_ZES_WSL_HELPER_HANDOFF_MODE" ]]; then
        return 0
    fi

    if _zes_wsl_helper_supports_scrollback_handoff; then
        _ZES_WSL_HELPER_HANDOFF_READY=1
        return 0
    fi

    if ((!_ZES_WSL_HELPER_HANDOFF_REBUILD_TRIED)); then
        _ZES_WSL_HELPER_HANDOFF_REBUILD_TRIED=1
        local helper_dir="${_ZES_WSL_HELPER_EXE:h}"
        if [[ -f "$helper_dir/Makefile" ]] && [[ -w "$helper_dir" ]]; then
            # `|| true`: the build's status is deliberately unobserved — the
            # capability re-check below is the real test, and a helper that
            # rebuilt fine despite a nonzero make (e.g. a warning-as-error in an
            # unrelated target) must still be detected.  Under a user's inherited
            # err_return the bare subshell aborted this function before that
            # re-check, reporting the helper incapable and permanently disabling
            # the scrollback handoff for the session.
            ( cd "$helper_dir" && make >/dev/null 2>&1 ) || true
            if _zes_wsl_helper_supports_scrollback_handoff; then
                _ZES_WSL_HELPER_HANDOFF_READY=1
                return 0
            fi
        fi
    fi

    _ZES_WSL_HELPER_HANDOFF_READY=0
    return 1
}

# VS Code-specific capability check. The new helper mode is intentionally
# separate from --handoff-scrollback so the Windows Terminal replay path keeps
# using its existing code and timing unchanged.
function _zes_wsl_helper_supports_vscode_shift_handoff() {
    [[ -s "$_ZES_WSL_HELPER_EXE" ]] || return 1
    local helper_help=""
    helper_help=$("$_ZES_WSL_HELPER_EXE" --help 2>&1) || true
    [[ "$helper_help" == *"--handoff-scrollback-vscode-shift"* ]]
}

# VS Code needs the helper mode that holds Shift around the replayed click.
# If an installed helper is older, rebuild only this helper binary from the
# local source and leave the Windows Terminal handoff mode selection untouched.
function _zes_prepare_wsl_vscode_scrollback_handoff_helper() {
    if ((_ZES_WSL_HELPER_VSCODE_HANDOFF_READY == 1)); then
        return 0
    fi

    if _zes_wsl_helper_supports_vscode_shift_handoff; then
        _ZES_WSL_HELPER_VSCODE_HANDOFF_READY=1
        return 0
    fi

    if ((!_ZES_WSL_HELPER_VSCODE_HANDOFF_REBUILD_TRIED)); then
        _ZES_WSL_HELPER_VSCODE_HANDOFF_REBUILD_TRIED=1
        local helper_dir="${_ZES_WSL_HELPER_EXE:h}"
        if [[ -f "$helper_dir/Makefile" ]] && [[ -w "$helper_dir" ]]; then
            # `|| true` for the same reason as the scrollback rebuild above:
            # the re-check that follows is the real test, and an inherited
            # err_return must not abort before it.
            ( cd "$helper_dir" && make zes-wsl-clipboard-helper.exe >/dev/null 2>&1 ) || true
            if _zes_wsl_helper_supports_vscode_shift_handoff; then
                _ZES_WSL_HELPER_VSCODE_HANDOFF_READY=1
                return 0
            fi
        fi
    fi

    _ZES_WSL_HELPER_VSCODE_HANDOFF_READY=0
    return 1
}

# VS Code/xterm.js treats Shift+mouse as a native terminal selection override
# even while application mouse tracking remains enabled. Using that override
# avoids the xterm.js selection-clear side effect caused by DECSET re-enable,
# so tracking is still active immediately after the scrollback gesture.
function _zes_handoff_to_native_scrollback_vscode() {
    _ZES_MOUSE_SELECTING=0
    _ZES_MOUSE_ANCHOR=-1
    _ZES_MOUSE_AUTOSUSPENDED=0

    if _zes_prepare_wsl_vscode_scrollback_handoff_helper; then
        "$_ZES_WSL_HELPER_EXE" --handoff-scrollback-vscode-shift >/dev/null 2>&1 &!
        return
    fi

    # Last-resort compatibility path for an old or unavailable helper: give
    # native selection control to VS Code on the next gesture rather than risk
    # replaying a stuck mouse button into the terminal.
    _zes_disable_mouse_tracking
    _ZES_MOUSE_AUTOSUSPENDED=1
}

function _zes_handoff_to_native_scrollback() {
    ((_ZES_MOUSE_TRACKING)) || return

    if ((_ZES_IS_VSCODE)); then
        _zes_handoff_to_native_scrollback_vscode
        return
    fi

    # Gate synthetic handoff on helper capability to avoid sticky drag state
    # with older helper builds that lack --inject-left-up.
    if ! _zes_prepare_wsl_scrollback_handoff_helper; then
        _zes_disable_mouse_tracking
        _ZES_MOUSE_AUTOSUSPENDED=1
        return
    fi

    # Turn off terminal reporting only; keep hooks/bindings intact.
    printf '\e[?1000l\e[?1002l\e[?1006l' > /dev/tty 2>/dev/null || true
    _ZES_MOUSE_SELECTING=0
    _ZES_MOUSE_ANCHOR=-1
    _ZES_MOUSE_AUTOSUSPENDED=1

    # ── Windows Terminal (and VS Code pipe-setup-failed fallback) ──────────
    if [[ "$_ZES_WSL_HELPER_HANDOFF_MODE" == "atomic" ]]; then
        (
            if ! "$_ZES_WSL_HELPER_EXE" --handoff-scrollback >/dev/null 2>&1; then
                # Atomic handoff unavailable — fall back to the inject/wait API.
                "$_ZES_WSL_HELPER_EXE" --inject-left-down >/dev/null 2>&1 || return
                "$_ZES_WSL_HELPER_EXE" --wait-left-up >/dev/null 2>&1
                "$_ZES_WSL_HELPER_EXE" --inject-left-up >/dev/null 2>&1
            fi
            [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]] || return
            ((_ZES_MOUSE_TRACKING)) || return
            printf '\e[?1000h\e[?1002h\e[?1006h' > /dev/tty 2>/dev/null
        ) &!
        return
    fi

    "$_ZES_WSL_HELPER_EXE" --inject-left-down >/dev/null 2>&1 || {
        _zes_disable_mouse_tracking
        _ZES_MOUSE_AUTOSUSPENDED=1
        return
    }

    # Re-arm tracking as soon as the physical left button is released.
    (
        "$_ZES_WSL_HELPER_EXE" --wait-left-up >/dev/null 2>&1
        # Always release the injected synthetic DOWN to avoid sticky drag.
        "$_ZES_WSL_HELPER_EXE" --inject-left-up >/dev/null 2>&1
        [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]] || return
        ((_ZES_MOUSE_TRACKING)) || return
        printf '\e[?1000h\e[?1002h\e[?1006h' > /dev/tty 2>/dev/null
    ) &!
}

# Zsh preexec hook: suspend mouse tracking before any command runs so that
# interactive programs (nano, vim, wizard) or native terminal selection
# can operate freely.
function _zes_mouse_preexec() {
    if ((_ZES_MOUSE_TRACKING)); then
        _zes_disable_mouse_tracking
        _ZES_MOUSE_AUTOSUSPENDED=1
    fi
}

# Resume tracking automatically after an auto-suspend event when the user
# returns to editing actions.
function _zes_resume_tracking_if_needed() {
    # `return 0` on all four guards, not bare `return`: a bare `return` yields
    # the PRECEDING test's status, so every "nothing to resume" exit reported
    # failure — rc 1 on all eight WSL terminal-mode states and on tracking mode
    # with nothing autosuspended.  All nine call sites invoke this bare as a
    # widget's first statement and none inspects the status, so under a user's
    # inherited err_return the widget aborted before its body ran: typing,
    # backspace, delete, copy, cut, paste and the region dispatch became no-ops
    # in terminal mode.  Normalizing here fixes all nine callers at once and
    # makes the contract honest; `_zes_enable_mouse_tracking` already returns 0,
    # so the resume path is unchanged.
    ((!_ZES_ON_WSL)) && return 0
    [[ "$_ZES_WSL_MOUSE_MODE" == "tracking" ]] || return 0
    ((_ZES_MOUSE_TRACKING)) && return 0
    ((_ZES_MOUSE_AUTOSUSPENDED)) || return 0
    _zes_enable_mouse_tracking
}
