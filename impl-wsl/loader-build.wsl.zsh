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
  local _wsl_helper_src="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.c"
  local _wsl_agent_src="${_wsl_root}/backends/wsl/zes-wsl-selection-agent.c"

  # Best-effort fix for copied/extracted ELF binaries that lost +x.
  [[ -f "$_wsl_agent" && ! -x "$_wsl_agent" ]] && chmod +x "$_wsl_agent" 2>/dev/null

  # Fast path: both artifacts are usable and no source files are newer than their binaries.
  if [[ -x "$_wsl_agent" && -s "$_wsl_helper" ]] && \
     { [[ ! -f "$_wsl_helper_src" ]] || [[ ! "$_wsl_helper_src" -nt "$_wsl_helper" ]]; } && \
     { [[ ! -f "$_wsl_agent_src" ]]  || [[ ! "$_wsl_agent_src" -nt "$_wsl_agent" ]]; }; then
    return 0
  fi

  # Source the shared fetch helper from assets/.
  # _wsl_root is impl-wsl/; its parent is the plugin root where assets/ lives.
  local _zes_root="${_wsl_root:h}"
  if { [[ ! -x "$_wsl_agent" ]] || [[ ! -s "$_wsl_helper" ]]; } && ! (( ${+functions[_zes_fetch_binary]} )); then
    source "${_zes_root}/assets/fetch-agents.zsh" 2>/dev/null
  fi

  # ── WSL Linux agent (ELF) ────────────────────────────────────────────────
  # Check: binary must exist AND be executable.
  if [[ ! -x "$_wsl_agent" ]]; then
    local _agent_asset=""
    local -i _try_agent_fetch=0
    local _agent_arch
    _agent_arch=$(uname -m 2>/dev/null)

    # Release workflow publishes WSL Linux-agent prebuilds only for x86_64.
    # Skip fetch attempts on other arches to avoid guaranteed 404 round-trips.
    case "$_agent_arch" in
      x86_64|amd64)
        _agent_asset="zes-wsl-selection-agent"
        _try_agent_fetch=1
        ;;
      *)
        _try_agent_fetch=0
        ;;
    esac

    if ((_try_agent_fetch)) && (( ${+functions[_zes_fetch_binary]} )); then
      _zes_fetch_binary "$_agent_asset" "$_wsl_agent" || true
    fi

    # Download unavailable/unsupported/failed — fall back to compiling from source.
    [[ ! -x "$_wsl_agent" ]] && _zes_loader_build_if_missing "$_wsl_agent" "gcc make" "WSL agent"

    # Final diagnostic: if still missing after both paths, tell the user.
    [[ ! -x "$_wsl_agent" ]] \
      && print -u2 "zsh-edit-select: WSL agent unavailable. Install: gcc make (or check network)"
  elif [[ -f "$_wsl_agent" && -f "$_wsl_agent_src" && "$_wsl_agent_src" -nt "$_wsl_agent" ]]; then
    ( cd "${_wsl_agent:h}" && make >/dev/null 2>&1 )
  fi

  # ── WSL Windows helper (.exe) ────────────────────────────────────────────
  # Check: file must exist; exec bit is not meaningful for a Windows PE binary.
  # If source is newer than binary, prefer a local rebuild to pick up changes.
  if [[ -s "$_wsl_helper" && -f "$_wsl_helper_src" && "$_wsl_helper_src" -nt "$_wsl_helper" ]]; then
    ( cd "${_wsl_helper:h}" && make >/dev/null 2>&1 )
  fi

  if [[ ! -s "$_wsl_helper" ]]; then
    if ! (( ${+functions[_zes_fetch_binary]} )) \
         || ! _zes_fetch_binary "zes-wsl-clipboard-helper.exe" "$_wsl_helper"; then
      _zes_loader_build_if_missing "$_wsl_helper" "gcc-mingw-w64-x86-64" "WSL helper"
    fi

    [[ ! -s "$_wsl_helper" ]] \
      && print -u2 "zsh-edit-select: WSL helper unavailable. Install: gcc-mingw-w64-x86-64 (or check network)"
  fi

  # Ensure the Linux ELF is executable in case it was placed without the bit
  # set (e.g. downloaded by some tools, or extracted from an archive).
  # The .exe guard uses -f because the exec bit on a Windows PE is meaningless.
  [[ -f "$_wsl_agent"  && ! -x "$_wsl_agent"  ]] && chmod +x "$_wsl_agent"  2>/dev/null
}
