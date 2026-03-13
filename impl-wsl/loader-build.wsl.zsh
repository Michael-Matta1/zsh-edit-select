# WSL-only build helper: build WSL agent/helper artifacts on demand.
# Sourced by impl-wsl plugin so top-level loader remains minimal.

function _zes_loader_build_if_missing() {
  local _target="$1"
  local _hint="$2"
  local _label="$3"
  local _dir="${_target:h}"

  [[ -f "$_target" ]] && return 0
  [[ -f "${_dir}/Makefile" ]] || return 0

  if [[ ! -w "$_dir" ]]; then
    print -u2 "zsh-edit-select: ${_label} build skipped: no write permission for ${_dir}"
    return 1
  fi

  if ! ( cd "$_dir" && make >/dev/null 2>&1 ) || [[ ! -f "$_target" ]]; then
    print -u2 "zsh-edit-select: ${_label} build failed. Install: ${_hint}"
    return 1
  fi

  return 0
}

function _zes_loader_build_wsl_artifacts() {
  local _wsl_root="${1:-${${(%):-%N}:A:h}}"
  local _wsl_agent="${_wsl_root}/backends/wsl/zes-wsl-selection-agent"
  local _wsl_helper="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.exe"

  _zes_loader_build_if_missing "$_wsl_agent" "gcc make" "WSL agent"
  _zes_loader_build_if_missing "$_wsl_helper" "gcc-mingw-w64-x86-64" "WSL helper"

  [[ -f "$_wsl_agent" ]] && [[ ! -x "$_wsl_agent" ]] && chmod +x "$_wsl_agent" 2>/dev/null || true
  [[ -f "$_wsl_helper" ]] && [[ ! -x "$_wsl_helper" ]] && chmod +x "$_wsl_helper" 2>/dev/null || true
}
