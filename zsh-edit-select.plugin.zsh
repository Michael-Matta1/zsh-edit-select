#!/bin/zsh
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
# Version: 0.7.00

# zsh-edit-select — Unified platform loader
# One-time detection, zero forks, sources correct implementation.

# Prevent recursive or repeated loading.  The temporary guard is cleared on
# validation failures so correcting the environment and re-sourcing can retry.
(( ${+_ZES_LOADER_LOADING} || ${+_ZES_LOADER_LOADED} )) && return 0
typeset -gi _ZES_LOADER_LOADING=1

# Absolute directory of this loader script; base path for locating impl-*/ trees.
typeset -g _zes_dir="${${(%):-%x}:A:h}"

# Will hold the detected implementation ("x11", "wayland", "wsl", or "macos") and a
# human-readable reason string (e.g. "XDG_SESSION_TYPE=wayland").
typeset -g _zes_impl="" _zes_reason=""

# Detection priority order:
#   1. ZES_FORCE_IMPL — explicit user override, bypasses all autodetection.
#   2. macOS — route to the native accessibility/clipboard implementation.
#   3. WSL — route to dedicated impl-wsl to keep Linux impls untouched.
#   4. XDG_SESSION_TYPE=wayland — most reliable session-level indicator.
#   5. WAYLAND_DISPLAY — set by the compositor; present even from within tmux.
#   6. DISPLAY — X11 running.
#   7. wl-paste in PATH — Wayland tools installed, WAYLAND_DISPLAY just unset.
#   8. Fallback to x11 — safe default; xclip is widely available.
if [[ -n "${ZES_FORCE_IMPL:-}" ]]; then
  case "$ZES_FORCE_IMPL" in
    x11|wayland|wsl|macos) _zes_impl="$ZES_FORCE_IMPL"; _zes_reason="forced via ZES_FORCE_IMPL" ;;
    *) unset _ZES_LOADER_LOADING; print -u2 "zsh-edit-select: invalid ZES_FORCE_IMPL='$ZES_FORCE_IMPL' (use x11, wayland, wsl, or macos)"; return 1 ;;
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
  unset _ZES_LOADER_LOADING
  print -u2 "zsh-edit-select: implementation not found: $_zes_plugin"
  print -u2 "zsh-edit-select: detection: $_zes_reason"
  return 1
fi

typeset -gri _ZES_LOADER_LOADED=1
unset _ZES_LOADER_LOADING

# Ensure native agents are present.
#
# Strategy (per binary, checked on every shell start via [[ ! -x ]]):
#   1. Binary already exists → nothing to do, zero cost.
#   2. Binary missing → source assets/fetch-agents.zsh and attempt to
#      download a pre-built binary from the latest GitHub Release.
#   3. Download unavailable or failed → fall back to `make` from source,
#      exactly as before (developer / offline path, unchanged).
#   4. Both failed → print a diagnostic with the required package names.
#
# WSL uses impl-wsl/loader-build.wsl.zsh, which provisions both required
# artifacts (Linux ELF + Windows .exe) using the same download-first strategy.
# Run it here so WSL users have binaries ready before the impl-wsl plugin loads.
#
# When git hooks are installed (.zes-hooks-installed marker present), the
# post-merge hook handles binary provisioning and .zwc recompilation after
# pulls — so we skip all these checks at startup for zero overhead.
# When the marker is absent (first install, non-git, or hooks not yet set up),
# the full provisioning path runs as before.
#
# Every best-effort command in this block -- binary fetches, the WSL artifact
# build, and the .zwc compilations -- is trailed by `|| true`.  This loader does
# not `emulate zsh`, so a user who has set err_return/err_exit would otherwise
# have the first failing best-effort command abort the whole load: a broken
# plugin for an option the user set for their own scripts, not for this one.
# The `|| true` suppresses only that spurious abort; genuine failures stay
# visible through the per-binary `make` fallbacks, the WSL flag-set's
# independent artifact check, and the diagnostics printed above, so nothing is
# masked and the non-err_return path is byte-identical.
if [[ ! -f "${_zes_dir}/.zes-hooks-installed" ]]; then

if [[ $_zes_impl == "wayland" ]]; then

  # 'local' is a no-op at script scope — these are plain assignments, cleaned
  # up by the unset block at the bottom of this file.
  _wl="${_zes_dir}/impl-wayland/backends/wayland/zes-wl-selection-agent"
  _xwl="${_zes_dir}/impl-wayland/backends/xwayland/zes-xwayland-agent"

  if [[ ! -x "$_wl" ]] || [[ ! -x "$_xwl" ]]; then
    # Source lazily: only pays the source cost when at least one binary is absent.
    source "${_zes_dir}/assets/fetch-agents.zsh" 2>/dev/null || true
  fi

  # Pure-Wayland agent
  if [[ ! -x "$_wl" ]]; then
    _zes_fetch_binary "$(_zes_asset_name wayland zes-wl-selection-agent)" "$_wl" \
      || { [[ -f "${_wl:h}/Makefile" ]] && ( cd "${_wl:h}" && make >/dev/null 2>&1 ); } || true
    [[ ! -x "$_wl" ]] \
      && print -u2 "zsh-edit-select: Wayland agent unavailable. Install: libwayland-dev wayland-protocols"
  fi

  # XWayland agent
  if [[ ! -x "$_xwl" ]]; then
    _zes_fetch_binary "$(_zes_asset_name wayland zes-xwayland-agent)" "$_xwl" \
      || { [[ -f "${_xwl:h}/Makefile" ]] && ( cd "${_xwl:h}" && make >/dev/null 2>&1 ); } || true
    [[ ! -x "$_xwl" ]] \
      && print -u2 "zsh-edit-select: XWayland agent unavailable. Install: libx11-dev libxfixes-dev"
  fi

elif [[ $_zes_impl == "x11" ]]; then

  _x11="${_zes_dir}/impl-x11/backends/x11/zes-x11-selection-agent"

  if [[ ! -x "$_x11" ]]; then
    source "${_zes_dir}/assets/fetch-agents.zsh" 2>/dev/null || true
    _zes_fetch_binary "$(_zes_asset_name x11 zes-x11-selection-agent)" "$_x11" \
      || { [[ -f "${_x11:h}/Makefile" ]] && ( cd "${_x11:h}" && make >/dev/null 2>&1 ); } || true
    [[ ! -x "$_x11" ]] \
      && print -u2 "zsh-edit-select: X11 agent unavailable. Install: libx11-dev libxfixes-dev"
  fi

elif [[ $_zes_impl == "macos" ]]; then

  _macos="${_zes_dir}/impl-macos/backends/macos/zes-macos-clipboard-agent"

  if [[ ! -x "$_macos" ]]; then
    source "${_zes_dir}/assets/fetch-agents.zsh" 2>/dev/null || true
    _zes_fetch_binary "$(_zes_asset_name macos zes-macos-clipboard-agent)" "$_macos" \
      || { [[ -f "${_macos:h}/Makefile" ]] && ( cd "${_macos:h}" && make >/dev/null 2>&1 ); } || true
    [[ ! -x "$_macos" ]] \
      && print -u2 "zsh-edit-select: macOS agent unavailable. Run: xcode-select --install"
  fi

elif [[ $_zes_impl == "wsl" ]]; then

  _wsl_root="${_zes_dir}/impl-wsl"
  _wsl_agent="${_wsl_root}/backends/wsl/zes-wsl-selection-agent"
  _wsl_helper="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.exe"
  _wsl_helper_src="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.c"
  _wsl_agent_src="${_wsl_root}/backends/wsl/zes-wsl-selection-agent.c"

  if [[ ! -x "$_wsl_agent" ]] || [[ ! -s "$_wsl_helper" ]] || \
     { [[ -f "$_wsl_helper_src" ]] && [[ "$_wsl_helper_src" -nt "$_wsl_helper" ]]; } || \
     { [[ -f "$_wsl_agent_src" ]] && [[ "$_wsl_agent_src" -nt "$_wsl_agent" ]]; }; then
    if [[ -r "${_wsl_root}/loader-build.wsl.zsh" ]]; then
      # Compile first (if stale/missing) so a stale .zwc never serves outdated
      # bytecode this startup; the tail compile further below is then a no-op.
      _zes_f="${_wsl_root}/loader-build.wsl.zsh"
      [[ ! -f "${_zes_f}.zwc" || "$_zes_f" -nt "${_zes_f}.zwc" ]] && zcompile -U "$_zes_f" 2>/dev/null || true
      source "${_wsl_root}/loader-build.wsl.zsh" 2>/dev/null || true
      if (( ${+functions[_zes_loader_build_wsl_artifacts]} )); then
        _zes_loader_build_wsl_artifacts "$_wsl_root" || true
        unfunction _zes_loader_build_wsl_artifacts _zes_loader_build_if_missing 2>/dev/null || true
      fi
    fi
  fi

fi

# Lazily compile the plugin .zsh files to bytecode on first load.
# This is done after platform detection so we only compile the files
# for the selected implementation.  Subsequent loads hit the .zwc cache.
# Recompile when the .zwc is missing OR older than its source: after an
# in-place update (git pull / manual edit) the old .zwc lingers and zsh
# silently falls back to parsing the slower .zsh on every start — the
# `-nt` guard refreshes it once so later loads hit fresh bytecode again.
#
# Each file is guarded INDEPENDENTLY (its own missing-or-stale `-nt` test)
# rather than nesting the backend loop under the plugin's staleness: a pull
# that touches only a backend .zsh (leaving the plugin file unchanged) must
# still refresh that backend's .zwc.  The glob+stat sweep is a handful of
# files and only runs on this no-hooks path (the whole block is skipped once
# .zes-hooks-installed exists), so the extra checks are negligible.
fi

# Bytecode compilation is gated SEPARATELY from binary provisioning above.
# Sharing the marker gate made .zwc absence permanent: once the hook marker
# exists the whole block is skipped, so a wiped cache (documented `find -name
# '*.zwc' -delete`), a platform switch that compiled a different impl, or an
# install where --setup never ran all leave ~1500 lines parsing from source on
# every start, forever.  Bytecode is worth ~9.4 ms/shell here, an order of
# magnitude more than the marker fast path itself saves, so it gets its own
# one-stat condition.  Widening the marker gate instead would re-enable the
# provisioning block — including its network fetch — on any shell whose .zwc
# happens to be missing; keeping them separate avoids that entirely.
if [[ ! -f "${_zes_plugin}.zwc" || ! -f "${_zes_dir}/.zes-hooks-installed" ]]; then

# `zcompile -U` on every compile below: zcompile expands aliases at PARSE time
# and freezes the result, and this block runs in the user's own interactive
# shell where their aliases are live.  With `alias rm='rm -iv'` /
# `alias mkdir='mkdir -pv'` set, the cached backend becomes `rm -iv -f …` /
# `mkdir -pv -p …`, which prints removal lines to stdout at every startup and —
# with an rm replacement that rejects -f — silently skips the stale-cache
# cleanup that stops a dead daemon's seq being read as ready.  -U is the
# documented flag for exactly this ("aliases are not expanded when compiling
# the named files"); it affects compilation only, needs no option juggling, and
# leaves the emitted bytecode unchanged when no alias applies.
[[ ! -f "${_zes_plugin}.zwc" || "$_zes_plugin" -nt "${_zes_plugin}.zwc" ]] && zcompile -U "$_zes_plugin" 2>/dev/null || true
for _zes_f in "${_zes_dir}/impl-${_zes_impl}"/backends/**/*.zsh(N); do
  [[ ! -f "${_zes_f}.zwc" || "$_zes_f" -nt "${_zes_f}.zwc" ]] && zcompile -U "$_zes_f" 2>/dev/null || true
done
# WSL sources its tailored variant chain (dispatcher plugin → tailored plugin
# → tailored backend) instead of backends/wsl-backend.zsh whenever the tailored
# files are present, which is the normal WSL case.  The impl-${impl}/backends
# glob above only reaches the fallback backend, so compile the tailored tree
# too; otherwise the ~2000 lines that actually run on WSL would be parsed from
# source on every startup on this no-hooks path.  nullglob (N) makes this a
# no-op on a shallow checkout where the tailored dir is absent.  This mirrors
# the post-pull checker's tailored-variants glob so both paths stay in sync.
if [[ $_zes_impl == "wsl" ]]; then
  for _zes_f in "${_zes_dir}/impl-wsl/tailored-variants"/**/*.zsh(N); do
    [[ ! -f "${_zes_f}.zwc" || "$_zes_f" -nt "${_zes_f}.zwc" ]] && zcompile -U "$_zes_f" 2>/dev/null || true
  done
  # WSL artifact builder: runtime-sourced by this loader (WSL branch, above) and
  # by the impl-wsl dispatcher plugin, but it sits directly at impl-wsl/ — not
  # under backends/ or tailored-variants/ — so neither glob reaches it.  Compile
  # it directly, mirroring the post-pull checker so both paths stay in sync.
  _zes_f="${_zes_dir}/impl-wsl/loader-build.wsl.zsh"
  [[ -f "$_zes_f" && ( ! -f "${_zes_f}.zwc" || "$_zes_f" -nt "${_zes_f}.zwc" ) ]] && zcompile -U "$_zes_f" 2>/dev/null || true
fi

fi

# Internal one-session guard used by impl-wsl plugin to avoid duplicate
# provisioning when this top-level loader already completed it.
#
# Hoisted OUTSIDE the .zes-hooks-installed marker-wrap above: on the fast path
# that whole binary-provisioning block is skipped, so the guard would otherwise
# never be set and the impl-wsl plugin would redundantly re-run its own
# loader-build provisioning on every startup (~0.6 ms of avoidable work).
# This block re-derives its own paths (the wrapped `elif wsl` assignments do
# not run on the fast path) and is gated on the SAME verified filesystem
# post-condition as before — agent -x, helper -s, and neither source -nt its
# binary.  It tests actual artifact presence/currency, NOT "did the build run":
# so if a binary is genuinely missing or a build failed, the condition is false
# and the flag stays unset, leaving impl-wsl's own self-heal path intact
# (byte-identical to the pre-hoist behavior on every WSL path).
if [[ $_zes_impl == "wsl" ]]; then
  _wsl_root="${_zes_dir}/impl-wsl"
  _wsl_agent="${_wsl_root}/backends/wsl/zes-wsl-selection-agent"
  _wsl_helper="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.exe"
  _wsl_helper_src="${_wsl_root}/backends/wsl/zes-wsl-clipboard-helper.c"
  _wsl_agent_src="${_wsl_root}/backends/wsl/zes-wsl-selection-agent.c"
  if [[ -x "$_wsl_agent" && -s "$_wsl_helper" ]] && \
     { [[ ! -f "$_wsl_helper_src" ]] || [[ ! "$_wsl_helper_src" -nt "$_wsl_helper" ]]; } && \
     { [[ ! -f "$_wsl_agent_src" ]]  || [[ ! "$_wsl_agent_src" -nt "$_wsl_agent" ]]; }; then
    typeset -g _ZES_WSL_ARTIFACTS_BOOTSTRAPPED_ROOT="$_wsl_root"
  fi
fi

# Source the platform-specific plugin, which defines all ZLE widgets
# and keybindings.  The trailing `|| true` mirrors the err_return/err_exit
# hardening on the provisioning path above (item 76): this loader does not
# `emulate zsh`, so a user who has set err_return/err_exit would otherwise
# have the first bare failing command inside an impl plugin's load path
# (e.g. _zes_start_monitor execing a missing agent) abort the whole load —
# a broken plugin for an option the user set for their own scripts, not this
# one.  `source ... || true` suppresses err_return/err_exit not only within
# the sourced file but also in nested bare sources, so this single guard
# covers all five impls, including WSL's dispatcher -> tailored -> backend
# chain.  Non-err_return loads are byte-identical: a nonzero plugin return
# already left the loader continuing to the exports below.
source "$_zes_plugin" || true

# Export read-only variables so user scripts can inspect which implementation
# was chosen and why, without being able to accidentally reassign them.
typeset -gr ZES_ACTIVE_IMPL="$_zes_impl"
typeset -gr ZES_DETECTION_REASON="$_zes_reason"
typeset -gr ZES_IMPL_PATH="${_zes_dir}/impl-${_zes_impl}"

# Compile this loader file itself to bytecode for faster subsequent loads.
# Same missing-or-stale guard as the impl files above so an updated loader
# is recompiled instead of falling back to parsing the source every start.
if [[ ! -f "${_zes_dir}/.zes-hooks-installed" ]]; then
    [[ ! -f "${_zes_dir}/zsh-edit-select.plugin.zsh.zwc" || "${_zes_dir}/zsh-edit-select.plugin.zsh" -nt "${_zes_dir}/zsh-edit-select.plugin.zsh.zwc" ]] && zcompile -U "${_zes_dir}/zsh-edit-select.plugin.zsh" 2>/dev/null || true
fi

# --- Post-pull hook management ---
#
# Silent bootstrap: runs at most once, ever, on shell startup — only when
# .zes-hooks-installed is absent AND .zes-hooks-bootstrap-done is also absent
# AND the hooks/ directory exists in the repo.  Sets core.hooksPath, chmods
# hook files, and writes .zes-hooks-installed ONLY when the post-merge hook is
# verifiably executable afterwards.  No network, no recompile, no prompt,
# no output — completely silent, even on collision.  The bootstrap-done marker
# is written unconditionally after the attempt so this never re-runs.
#
# Marker invariant: ".zes-hooks-installed present" MUST imply "the hook can
# actually fire on the next pull".  git config succeeding is necessary but NOT
# sufficient — there are TWO independent ways it can succeed yet the hook never
# fire, and a bare `[[ -x hooks/post-merge ]]` test catches neither:
#   (1) WSL DrvFs (no metadata): git's checkout and our chmod +x are silent
#       no-ops, so hooks/post-merge is present but not executable.
#   (2) git older than 2.9: `git config` is SCHEMA-LESS and stores
#       core.hooksPath on ANY git version (verified: it even accepts a
#       made-up core.* key), so the value reads back as "hooks" and the file
#       stays executable — but git <2.9 never READS core.hooksPath and runs
#       .git/hooks/ instead, so our hook never fires.
# If we wrote the marker in either case, startup would take the fast path (skip
# binary/.zwc provisioning) forever while no hook ever fires — a strictly worse
# regression than today, because the current loader self-heals stale
# binaries/.zwc at startup and that self-heal would be permanently disabled with
# nothing replacing it.  So the marker is gated on `git rev-parse --git-path
# hooks/post-merge` resolving to our actual hooks/ file AND that file being
# executable: --git-path returns our hooks/ path ONLY when git honors
# core.hooksPath (it resolves into .git/hooks/… otherwise), and the `-x` test on
# the resolved path then also covers the DrvFs exec-bit case.  One probe, both
# failure modes.  Where the hook can't fire, no marker is written, startup keeps
# its exact current full-checks/self-heal behavior (zero drift for that user),
# and they simply don't receive the startup optimization they fundamentally
# cannot benefit from.  (Conservative note: git 2.9–2.30 honors core.hooksPath
# at runtime but its --git-path does NOT reflect it — special-casing was added
# in 2.31 — so those users are also skipped.  That is a missed optimization,
# never a regression: hooks still fire and prompt, startup just stays on the
# full-checks path.  The probe NEVER over-claims.)
#
# Concurrency-safe: all operations (git config, chmod, touch) are idempotent —
# multiple terminals racing through this simultaneously have no side effects.
# Read-only install directory: if touch fails, bootstrap harmlessly re-runs
# on every future startup (no output, no prompt, a few cheap local calls).
if [[ ! -f "${_zes_dir}/.zes-hooks-installed" ]] && \
   [[ ! -f "${_zes_dir}/.zes-hooks-bootstrap-done" ]] && \
   [[ -d "${_zes_dir}/hooks" ]]; then
    # Silent mechanical bootstrap — no output, no network, no prompt.
    {
        # _zes_cur_hooks / _zes_hook_eff are plain temp vars (not local — we're
        # at script scope, where local is a no-op).  Both are added to the unset
        # cleanup block at the bottom of this file alongside _zes_dir, _zes_impl.
        _zes_git_top=$(git -C "${_zes_dir}" rev-parse --show-toplevel 2>/dev/null) || _zes_git_top=""
        [[ -n "$_zes_git_top" ]] && _zes_git_top="${_zes_git_top:A}"

        # A relative hooksPath is rooted at the repository top level.  Only a
        # standalone plugin repository can therefore use this tracked hooks/
        # directory; a vendored/archive copy must not modify its parent repo.
        if [[ "$_zes_git_top" == "${_zes_dir:A}" ]]; then
            _zes_cur_hooks=$(git -C "${_zes_dir}" config --get core.hooksPath 2>/dev/null) || _zes_cur_hooks=""

            # Set core.hooksPath only when it is currently unset.  If it is already
            # set to a DIFFERENT value that is a real collision (the user's own hooks
            # dir), do NOT overwrite — the marker gate below will then correctly
            # decline to write the marker because the resolved hook won't be ours.
            # git config writes through .git/config.lock, so a concurrent shell
            # racing this very line can fail with "could not lock config file"; we
            # ignore the rc (2>/dev/null) and RE-READ the value below, because
            # whichever racer wins the lock sets the same idempotent "hooks".
            if [[ -z "$_zes_cur_hooks" ]]; then
                git -C "${_zes_dir}" config core.hooksPath hooks 2>/dev/null || true
                _zes_cur_hooks=$(git -C "${_zes_dir}" config --get core.hooksPath 2>/dev/null) || _zes_cur_hooks=""
            fi

        # Write .zes-hooks-installed ONLY when git will actually resolve AND run
        # OUR post-merge hook (the marker invariant — see the note above).  The
        # gate is `git rev-parse --git-path hooks/post-merge` resolving to our
        # file AND that file being executable, NOT a bare `[[ -x hooks/post-merge
        # ]]`: the latter passes on git <2.9 (which stores but never reads
        # core.hooksPath) and would wrongly write the marker.  --git-path returns
        # a repo-relative path; prefix it with the plugin dir before the -x test.
        #
        # Because the marker is derived from this OBSERVABLE post-condition (not
        # from assuming our own `git config` succeeded), it is correct under
        # concurrency and on weak-consistency filesystems (NFS): a shell writes
        # the marker only if it can itself observe git resolving+exec'ing the
        # hook, regardless of which racer set the config.  It also self-heals the
        # "core.hooksPath already 'hooks' but marker deleted by `git clean`" case
        # — cur is "hooks", so we re-chmod, re-probe, and re-touch the marker.
            if [[ "$_zes_cur_hooks" == "hooks" ]]; then
                chmod +x "${_zes_dir}/hooks/post-merge" \
                         "${_zes_dir}/hooks/post-rewrite" \
                         "${_zes_dir}/hooks/manage-hooks.sh" 2>/dev/null || true
                _zes_hook_eff=$(git -C "${_zes_dir}" rev-parse --git-path hooks/post-merge 2>/dev/null) || true
                [[ -n "$_zes_hook_eff" && "$_zes_hook_eff" != /* ]] && \
                    _zes_hook_eff="${_zes_dir}/${_zes_hook_eff}"
                [[ -n "$_zes_hook_eff" && -x "$_zes_hook_eff" ]] && \
                    touch "${_zes_dir}/.zes-hooks-installed" 2>/dev/null || true
            fi
        fi
    } always {
        # Write bootstrap-done unconditionally (success or failure/collision)
        # so this check never re-runs on a future startup.
        touch "${_zes_dir}/.zes-hooks-bootstrap-done" 2>/dev/null || true
    }
fi

# Hook management functions — platform-independent, called at runtime via
# 'edit-select setup-hooks' / 'edit-select remove-hooks'.  These are the
# explicit verbose commands (print status/warnings).  The silent bootstrap
# above does NOT use these — it inlines the minimal mechanical setup.
# Uses ZES_IMPL_PATH (typeset -gr, survives the unset block below).
function edit-select::setup-hooks() {
    sh "${ZES_IMPL_PATH:h}/hooks/manage-hooks.sh" install "${ZES_IMPL_PATH:h}"
}
function edit-select::remove-hooks() {
    sh "${ZES_IMPL_PATH:h}/hooks/manage-hooks.sh" remove "${ZES_IMPL_PATH:h}"
}

# Clean up all loader-local variables so they do not leak into the shell
# environment.  The exported ZES_* variables above are the only public API.
# _zes_fetch_binary and _zes_asset_name are functions (not variables), so
# unfunction is used — but only if fetch-agents.zsh was actually sourced
# this session (i.e. at least one binary was absent on this load).
unset _zes_dir _zes_impl _zes_reason _zes_plugin _zes_f _wl _xwl _x11 _macos _zes_cur_hooks _zes_hook_eff _zes_git_top
unset _wsl_root _wsl_agent _wsl_helper _wsl_helper_src _wsl_agent_src
# NOTE: _ZES_WSL_ARTIFACTS_BOOTSTRAPPED_ROOT is intentionally NOT unset here.
# It is a one-session guard read by impl-wsl/zsh-edit-select-wsl.plugin.zsh to
# skip duplicate provisioning when this loader already completed it successfully.
(( ${+functions[_zes_fetch_binary]} )) && unfunction _zes_fetch_binary _zes_asset_name

return 0
