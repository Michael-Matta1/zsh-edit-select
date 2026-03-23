# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# impl-wsl/loader-build.wsl.zsh — WSL artifact provisioner
#
# Sourced by the impl-wsl plugin so the top-level loader remains minimal.
# Ensures the two WSL binaries are present by trying, in order:
#   1. Download a pre-built binary from the latest GitHub Release
#   2. Compile from source with `make` (developer / offline fallback)
#
# Path relationships (this file lives at impl-wsl/loader-build.wsl.zsh):
#   _wsl_root          = impl-wsl/
#   _wsl_root:h        = plugin root  (where assets/ lives)
#   _wsl_root/backends/wsl/  = Makefile + source for both WSL artifacts

# ---------------------------------------------------------------------------
# _zes_loader_build_if_missing <target_path> <dep_hint> <label>
#
# Compile <target_path> from source by running `make` in its directory.
# No-ops if <target_path> already exists.
# Skips silently if no Makefile is present (non-developer clone is fine;
# the download path should have already placed the binary).
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# _zes_loader_build_wsl_artifacts [wsl_root]
#
# Ensure both WSL artifacts are present:
#   zes-wsl-selection-agent      — Linux ELF; must be executable
#   zes-wsl-clipboard-helper.exe — Windows PE; only needs to exist as a file
#                                   (Linux exec bit is irrelevant for a PE
#                                    binary invoked by cmd.exe on the Win side)
#
# Called by the WSL plugin with no argument; the default expression resolves
# to the directory this file itself lives in (impl-wsl/).
# ---------------------------------------------------------------------------
function _zes_loader_build_wsl_artifacts() {
  local _wsl_root="${1:-${${(%):-%N}:A:h}}"
  local _wsl_agent="${_wsl_root}/backends/wsl/zes-wsl-selection-agent"
  local _wsl_helper="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.exe"

  # Source the shared fetch helper from assets/.
  # _wsl_root is impl-wsl/; its parent is the plugin root where assets/ lives.
  local _zes_root="${_wsl_root:h}"
  if ! (( ${+functions[_zes_fetch_binary]} )); then
    source "${_zes_root}/assets/fetch-agents.zsh" 2>/dev/null
  fi

  # ── WSL Linux agent (ELF) ────────────────────────────────────────────────
  # Check: binary must exist AND be executable.
  if [[ ! -x "$_wsl_agent" ]]; then
    local _agent_asset
    if (( ${+functions[_zes_asset_name]} )); then
      # WSL always runs on x86_64, so this will always resolve to the bare name
      # with no arch suffix.  The function call is kept for correctness and so
      # that future arch support only needs a change in _zes_asset_name.
      _agent_asset=$(_zes_asset_name wsl zes-wsl-selection-agent)
    else
      # fetch-agents.zsh failed to load (offline system with no curl/wget?).
      # Hard-code the x86_64 asset name as a safe fallback.
      _agent_asset="zes-wsl-selection-agent"
    fi

    if ! (( ${+functions[_zes_fetch_binary]} )) \
         || ! _zes_fetch_binary "$_agent_asset" "$_wsl_agent"; then
      # Download unavailable or failed — fall back to compiling from source.
      _zes_loader_build_if_missing "$_wsl_agent" "gcc make" "WSL agent"
    fi

    # Final diagnostic: if still missing after both paths, tell the user.
    [[ ! -x "$_wsl_agent" ]] \
      && print -u2 "zsh-edit-select: WSL agent unavailable. Install: gcc make (or check network)"
  fi

  # ── WSL Windows helper (.exe) ────────────────────────────────────────────
  # Check: file must exist; exec bit is not meaningful for a Windows PE binary.
  if [[ ! -f "$_wsl_helper" ]]; then
    if ! (( ${+functions[_zes_fetch_binary]} )) \
         || ! _zes_fetch_binary "zes-wsl-clipboard-helper.exe" "$_wsl_helper"; then
      _zes_loader_build_if_missing "$_wsl_helper" "gcc-mingw-w64-x86-64" "WSL helper"
    fi

    [[ ! -f "$_wsl_helper" ]] \
      && print -u2 "zsh-edit-select: WSL helper unavailable. Install: gcc-mingw-w64-x86-64 (or check network)"
  fi

  # Ensure the Linux ELF is executable in case it was placed without the bit
  # set (e.g. downloaded by some tools, or extracted from an archive).
  # The .exe guard uses -f because the exec bit on a Windows PE is meaningless.
  [[ -f "$_wsl_agent"  && ! -x "$_wsl_agent"  ]] && chmod +x "$_wsl_agent"  2>/dev/null
}
