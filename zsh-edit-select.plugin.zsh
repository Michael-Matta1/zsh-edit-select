#!/bin/zsh
# Copyright (c) 2025 Michael Matta
# Version: 0.5.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# zsh-edit-select — Unified platform loader
# One-time detection, zero forks, sources correct implementation.

(( ${+_ZES_LOADER_LOADED} )) && return 0
typeset -gri _ZES_LOADER_LOADED=1

typeset -g _zes_dir="${0:A:h}"
typeset -g _zes_impl="" _zes_reason=""

if [[ -n "${ZES_FORCE_IMPL:-}" ]]; then
  case "$ZES_FORCE_IMPL" in
    x11|wayland) _zes_impl="$ZES_FORCE_IMPL"; _zes_reason="forced via ZES_FORCE_IMPL" ;;
    *) print -u2 "zsh-edit-select: invalid ZES_FORCE_IMPL='$ZES_FORCE_IMPL' (use x11 or wayland)"; return 1 ;;
  esac
elif [[ "$OSTYPE" == darwin* ]]; then
  _zes_impl=x11; _zes_reason="macOS ($OSTYPE)"
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

typeset -g _zes_plugin="${_zes_dir}/impl-${_zes_impl}/zsh-edit-select-${_zes_impl}.plugin.zsh"

if [[ ! -r "$_zes_plugin" ]]; then
  print -u2 "zsh-edit-select: implementation not found: $_zes_plugin"
  print -u2 "zsh-edit-select: detection: $_zes_reason"
  return 1
fi

# Auto-compile native monitors if missing (self-healing, silent on success)
if [[ $_zes_impl == "wayland" ]]; then
  local _wl="${_zes_dir}/impl-wayland/backends/wayland/zes-wl-selection-monitor"
  local _xwl="${_zes_dir}/impl-wayland/backends/x11/zes-xwayland-monitor"
  if [[ ! -x "$_wl" ]] && [[ -f "${_wl:h}/Makefile" ]]; then
    ( cd "${_wl:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_wl" ]] && print -u2 "zsh-edit-select: Wayland monitor build failed. Install: libwayland-dev wayland-protocols"
  fi
  if [[ ! -x "$_xwl" ]] && [[ -f "${_xwl:h}/Makefile" ]]; then
    ( cd "${_xwl:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_xwl" ]] && print -u2 "zsh-edit-select: XWayland monitor build failed. Install: libx11-dev libxfixes-dev"
  fi
elif [[ $_zes_impl == "x11" ]]; then
  local _x11="${_zes_dir}/impl-x11/backends/x11/zes-x11-selection-monitor"
  if [[ ! -x "$_x11" ]] && [[ -f "${_x11:h}/Makefile" ]]; then
    ( cd "${_x11:h}" && make >/dev/null 2>&1 )
    [[ ! -x "$_x11" ]] && print -u2 "zsh-edit-select: X11 monitor build failed. Install: libx11-dev libxfixes-dev"
  fi
fi

if [[ ! -f "${_zes_plugin}.zwc" ]]; then
  zcompile "$_zes_plugin" 2>/dev/null
  local _zes_f
  for _zes_f in "${_zes_dir}/impl-${_zes_impl}"/backends/**/*.zsh(N); do
    [[ ! -f "${_zes_f}.zwc" ]] && zcompile "$_zes_f" 2>/dev/null
  done
fi

source "$_zes_plugin"

typeset -gr ZES_ACTIVE_IMPL="$_zes_impl"
typeset -gr ZES_DETECTION_REASON="$_zes_reason"
typeset -gr ZES_IMPL_PATH="${_zes_dir}/impl-${_zes_impl}"

[[ ! -f "${_zes_dir}/zsh-edit-select.plugin.zsh.zwc" ]] && zcompile "${_zes_dir}/zsh-edit-select.plugin.zsh" 2>/dev/null

unset _zes_dir _zes_impl _zes_reason _zes_plugin _zes_f _wl _xwl _x11

return 0
