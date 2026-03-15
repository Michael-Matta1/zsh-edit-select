#!/bin/zsh
# Copyright (c) 2025 Michael Matta
# Version: 0.6.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# zsh-edit-select — Unified platform loader
# One-time detection, zero forks, sources correct implementation.

# Prevent double-loading when the file is sourced more than once (e.g. if
# the user calls `source ~/.zshrc` to reload their config mid-session).
(( ${+_ZES_LOADER_LOADED} )) && return 0
typeset -gri _ZES_LOADER_LOADED=1

# Absolute directory of this loader script; base path for locating impl-*/ trees.
typeset -g _zes_dir="${0:A:h}"

# Will hold the detected implementation ("x11", "wayland", or "wsl") and a
# human-readable reason string (e.g. "XDG_SESSION_TYPE=wayland").
typeset -g _zes_impl="" _zes_reason=""

# Detection priority order:
#   1. ZES_FORCE_IMPL — explicit user override, bypasses all autodetection.
#   2. macOS — always X11 (XQuartz); there is no native Wayland compositor.
#   3. WSL — route to dedicated impl-wsl to keep Linux impls untouched.
#   4. XDG_SESSION_TYPE=wayland — most reliable session-level indicator.
#   5. WAYLAND_DISPLAY — set by the compositor; present even from within tmux.
#   6. DISPLAY — X11 running.
#   7. wl-paste in PATH — Wayland tools installed, WAYLAND_DISPLAY just unset.
#   8. Fallback to x11 — safe default; xclip is widely available.
if [[ -n "${ZES_FORCE_IMPL:-}" ]]; then
  case "$ZES_FORCE_IMPL" in
    x11|wayland|wsl|macos) _zes_impl="$ZES_FORCE_IMPL"; _zes_reason="forced via ZES_FORCE_IMPL" ;;
    *) print -u2 "zsh-edit-select: invalid ZES_FORCE_IMPL='$ZES_FORCE_IMPL' (use x11, wayland, wsl, or macos)"; return 1 ;;
  esac
elif [[ "$OSTYPE" == darwin* ]]; then
  _zes_impl=macos; _zes_reason="macOS ($OSTYPE)"
elif [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
  _zes_impl=wsl; _zes_reason="WSL detected"
elif [[ "${XDG_SESSION_TYPE:-}" == wayland ]]; then
  _zes_impl=wayland; _zes_reason="XDG_SESSION_TYPE=wayland"
elif (( ${+WAYLAND_DISPLAY} )); then
  _zes_impl=wayland; _zes_reason="WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
elif (( ${+DISPLAY} )); then
  _zes_impl=x11; _zes_reason="DISPLAY=$DISPLAY"
elif (( ${+commands[wl-paste]} )); then
  _zes_impl=wayland; _zes_reason="wl-paste found in PATH"
else
  _zes_impl=x11; _zes_reason="no display server detected, defaulting to x11"
fi

# Full path to the platform-specific plugin .zsh file about to be sourced.
typeset -g _zes_plugin="${_zes_dir}/impl-${_zes_impl}/zsh-edit-select-${_zes_impl}.plugin.zsh"

# Abort with a diagnostic message if the resolved implementation file is missing.
if [[ ! -r "$_zes_plugin" ]]; then
  print -u2 "zsh-edit-select: implementation not found: $_zes_plugin"
  print -u2 "zsh-edit-select: detection: $_zes_reason"
  return 1
fi

# Compile native agents on first use if the binary is missing.
# Each agent is built by running `make` in its source directory.
if [[ $_zes_impl == "wayland" ]]; then
  local _wl="${_zes_dir}/impl-wayland/backends/wayland/zes-wl-selection-agent"
  local _xwl="${_zes_dir}/impl-wayland/backends/xwayland/zes-xwayland-agent"
  # Build the pure-Wayland agent from source if the binary is missing.
  if [[ ! -x "$_wl" ]] && [[ -f "${_wl:h}/Makefile" ]]; then
    ( cd "${_wl:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_wl" ]] && print -u2 "zsh-edit-select: Wayland agent build failed. Install: libwayland-dev wayland-protocols"
  fi
  # Build the XWayland agent from source if the binary is missing.
  if [[ ! -x "$_xwl" ]] && [[ -f "${_xwl:h}/Makefile" ]]; then
    ( cd "${_xwl:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_xwl" ]] && print -u2 "zsh-edit-select: XWayland agent build failed. Install: libx11-dev libxfixes-dev"
  fi
elif [[ $_zes_impl == "x11" ]]; then
  # Build the X11 selection agent from source if the binary is missing.
  local _x11="${_zes_dir}/impl-x11/backends/x11/zes-x11-selection-agent"
  if [[ ! -x "$_x11" ]] && [[ -f "${_x11:h}/Makefile" ]]; then
    ( cd "${_x11:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_x11" ]] && print -u2 "zsh-edit-select: X11 agent build failed. Install: libx11-dev libxfixes-dev"
  fi
elif [[ $_zes_impl == "macos" ]]; then
  # Build the macOS pasteboard agent from source if the binary is missing.
  local _macos="${_zes_dir}/impl-macos/backends/macos/zes-macos-clipboard-agent"
  if [[ ! -x "$_macos" ]] && [[ -f "${_macos:h}/Makefile" ]]; then
    ( cd "${_macos:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_macos" ]] && print -u2 "zsh-edit-select: macOS agent build failed. Run: xcode-select --install"
  fi
fi

# Lazily compile the plugin .zsh files to bytecode on first load.
# This is done after platform detection so we only compile the files
# for the selected implementation.  Subsequent loads hit the .zwc cache.
if [[ ! -f "${_zes_plugin}.zwc" ]]; then
  zcompile "$_zes_plugin" 2>/dev/null
  local _zes_f
  for _zes_f in "${_zes_dir}/impl-${_zes_impl}"/backends/**/*.zsh(N); do
    [[ ! -f "${_zes_f}.zwc" ]] && zcompile "$_zes_f" 2>/dev/null
  done
fi

# Source the platform-specific plugin, which defines all ZLE widgets
# and keybindings.
source "$_zes_plugin"

# Export read-only variables so user scripts can inspect which implementation
# was chosen and why, without being able to accidentally reassign them.
typeset -gr ZES_ACTIVE_IMPL="$_zes_impl"
typeset -gr ZES_DETECTION_REASON="$_zes_reason"
typeset -gr ZES_IMPL_PATH="${_zes_dir}/impl-${_zes_impl}"

# Compile this loader file itself to bytecode for faster subsequent loads.
[[ ! -f "${_zes_dir}/zsh-edit-select.plugin.zsh.zwc" ]] && zcompile "${_zes_dir}/zsh-edit-select.plugin.zsh" 2>/dev/null

# Clean up all loader-local variables so they do not leak into the shell
# environment.  The exported ZES_* variables above are the only public API.
unset _zes_dir _zes_impl _zes_reason _zes_plugin _zes_f _wl _xwl _x11 _macos

return 0
