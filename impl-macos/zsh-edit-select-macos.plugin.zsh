# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# macOS-native text selection and editing for Zsh command line.
#
# PRIMARY SELECTION (two paths):
# Path A (AX): mouse selections in Terminal.app, iTerm2, kitty, and AppKit apps detected
#   via CGEventTap + kAXSelectedTextAttribute. Zero clipboard side-effects.
# Path B (Cmd+C): terminals without AX selection support (for example, WezTerm,
#   Alacritty, and Ghostty) detected
#   via CGEventTap + synthetic Cmd+C + reactive changeCount watcher.
# NSPasteboard is NEVER polled. Plugin copy/cut writes produce zero daemon events.
#
# Structure: x11 source order + WSL behavioral patterns for sync functions.

zmodload zsh/datetime 2>/dev/null

# ── Selection tracking state ───────────────────────────────────────────
typeset -g  _EDIT_SELECT_LAST_PRIMARY=""
typeset -g  _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g  _EDIT_SELECT_PENDING_SELECTION=""
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
typeset -g  _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
# ${${(%):-%x}:A:h} resolves the sourced file path, then takes its parent directory.
# For impl-macos/zsh-edit-select-macos.plugin.zsh → impl-macos/
typeset -g  _EDIT_SELECT_PLUGIN_DIR="${${(%):-%x}:A:h}"
typeset -g _EDIT_SELECT_LAST_SEQ=""
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
typeset -gi _ZES_LAST_PID_CHECK=0
typeset -gi _ZES_LAST_MONITOR_RESTART=0

# ── Cache directory and file paths ────────────────────────────────────
# macOS: $TMPDIR set by launchd to per-user directory (APFS, fast).
# XDG_RUNTIME_DIR is not set on macOS. /dev/shm does not exist on macOS.
typeset -g _EDIT_SELECT_CACHE_DIR="${TMPDIR:-/tmp}/zsh-edit-select-${UID}"
typeset -g _EDIT_SELECT_SEQ_FILE="$_EDIT_SELECT_CACHE_DIR/seq"
typeset -g _EDIT_SELECT_PRIMARY_FILE="$_EDIT_SELECT_CACHE_DIR/primary"
typeset -g _EDIT_SELECT_PID_FILE="$_EDIT_SELECT_CACHE_DIR/agent.pid"
# Path B (reactive Cmd+C) capture marker (daemon creates/deletes this file).
typeset -g _EDIT_SELECT_PENDING_FILE="$_EDIT_SELECT_CACHE_DIR/pending"

# ── Default key sequences (macOS-native) ─────────────────────────────
# Clipboard: Cmd key via CSI-u / kitty keyboard protocol.
# Requires a terminal that forwards Cmd sequences (iTerm2 with CSI-u enabled,
# WezTerm, Ghostty, Kitty). Terminal.app intercepts Cmd at the OS level and
# cannot forward these sequences — use 'edit-select config' to set fallbacks.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^[[97;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]]       && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^[[118;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]]         && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^[[120;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_COPY+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_COPY='^[[99;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^[[122;9u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]]        && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[122;10u'

# Word navigation: Option+Left / Option+Right (xterm modifier form, modifier 3 = Alt/Option).
# Terminal.app users who have "Use Option as Meta Key" enabled receive \eb / \ef instead.
# Both forms are bound — see the secondary alias registration in the anonymous keybinding function.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT+x} ]]      && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_LEFT='^[[1;3D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT+x} ]]     && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT='^[[1;3C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT+x} ]]  && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT='^[[1;4D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT='^[[1;4C'

# Buffer navigation: Cmd+Shift+Up / Cmd+Shift+Down selects to start/end of buffer.
# This replaces the non-native Shift+Ctrl+Home / Shift+Ctrl+End used on Linux.
# Modifier 10 = Super(8) + Shift(1) + 1 in xterm encoding.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_START+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_START='^[[1;10A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_END+x} ]]   && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_END='^[[1;10B'

# ─────────────────────────────────────────────────────────────────────
# edit-select::apply-key-defaults
# Apply default key sequences if not already set by user config.
# ─────────────────────────────────────────────────────────────────────
function edit-select::apply-key-defaults() {
    EDIT_SELECT_KEY_SELECT_ALL="${EDIT_SELECT_KEY_SELECT_ALL:-$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL}"
    EDIT_SELECT_KEY_PASTE="${EDIT_SELECT_KEY_PASTE:-$_EDIT_SELECT_DEFAULT_KEY_PASTE}"
    EDIT_SELECT_KEY_CUT="${EDIT_SELECT_KEY_CUT:-$_EDIT_SELECT_DEFAULT_KEY_CUT}"
    EDIT_SELECT_KEY_COPY="${EDIT_SELECT_KEY_COPY:-$_EDIT_SELECT_DEFAULT_KEY_COPY}"
    EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
    EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
    EDIT_SELECT_KEY_WORD_LEFT="${EDIT_SELECT_KEY_WORD_LEFT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT}"
    EDIT_SELECT_KEY_WORD_RIGHT="${EDIT_SELECT_KEY_WORD_RIGHT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT}"
    EDIT_SELECT_KEY_SEL_WORD_LEFT="${EDIT_SELECT_KEY_SEL_WORD_LEFT:-$_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT}"
    EDIT_SELECT_KEY_SEL_WORD_RIGHT="${EDIT_SELECT_KEY_SEL_WORD_RIGHT:-$_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT}"
    EDIT_SELECT_KEY_BUFFER_START="${EDIT_SELECT_KEY_BUFFER_START:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START}"
    EDIT_SELECT_KEY_BUFFER_END="${EDIT_SELECT_KEY_BUFFER_END:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END}"
}

# ─────────────────────────────────────────────────────────────────────
# edit-select::load-config
# Source user config and apply defaults for unset keys.
# ─────────────────────────────────────────────────────────────────────
function edit-select::load-config() {
    # || true: a failing config source (malformed hand-edit, transient read
    # error) must not abort this function under inherited err_return/err_exit —
    # the abort would skip apply-key-defaults and cascade out of the plugin
    # load.  The rc is unobserved; behaviour is unchanged under normal options.
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null || true
    edit-select::apply-key-defaults
}

# ─────────────────────────────────────────────────────────────────────
# _zes_sync_after_paste
# Reset selection state after paste or cut, with cache re-read.
# Re-reading LAST_PRIMARY and LAST_SEQ is critical: without it, two
# consecutive copies of the same text produce no detectable seq change
# and a spurious event fires after every paste.
# ─────────────────────────────────────────────────────────────────────
function _zes_sync_after_paste() {
    _zes_clear_duplicate_prompt
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_LAST_PRIMARY=""
    _zes_clear_primary
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Guards go INSIDE the brace groups.  A trailing `|| true` on a brace
        # group stops suppressing an inherited err_return abort as soon as any
        # enclosing frame's status is observed, and that is the case here:
        # `_zes_delete_mouse_selection` calls this mid-body and is itself invoked
        # as `if _zes_delete_mouse_selection; then`.  With the outside form a
        # daemon that unlinked its cache made this function abort, so the delete
        # helper returned FAILURE after having already mutated BUFFER — verified
        # in a real ZLE widget: the region was removed but the caller took its
        # failure branch, so `handle-char` skipped `zle self-insert` and the
        # typed character was LOST (type-to-replace deleted without replacing);
        # the delete/backspace widgets fell through to
        # `_zes_reset_mouse_selection_state` instead of returning clean.  The
        # keymap itself is fine — the abort lands after this function's own
        # callers reset it — so this is a lost-keystroke bug, not a stuck-keymap
        # one.  Both reads are best-effort re-baselining and their own status is
        # never inspected.
        { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
        { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
    fi
}

# Clear the duplicate-disambiguation message only when this plugin owns it.
function _zes_clear_duplicate_prompt() {
    if ((_EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE)); then
        zle -M ""
        zle -R
        _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
    fi
}

# Centralized reset for transient mouse-selection operation state.
function _zes_reset_mouse_selection_state() {
    # If the "Duplicate text" disambiguation prompt is on screen, clear it here too.
    # handle-char never consults _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE, so a prompt left
    # showing would strand on screen after a focus round-trip (PENDING is cleared below,
    # removing the only gate handle-char checks).  Mirrors the prompt-clear in
    # _zes_clear_mouse_selection_prompt_state; the flag reset also drops any lingering
    # stale flag left by a detect pending-resolution path.
    _zes_clear_duplicate_prompt
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
}

# Clear transient mouse-selection prompt/state when keyboard selection takes
# over.  This stays inside ZLE state and does not touch the macOS pasteboard.
function _zes_clear_mouse_selection_prompt_state() {
    if ((!_EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE)) && [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        zle -M ""
        zle -R
    fi
    _zes_clear_duplicate_prompt
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
}

# Best-effort monitor self-heal so mouse operations recover without a terminal restart.
function _zes_try_restart_monitor() {
    (( EPOCHSECONDS <= _ZES_LAST_MONITOR_RESTART + 1 )) && return 1
    _ZES_LAST_MONITOR_RESTART=$EPOCHSECONDS

    _zes_start_monitor || true
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return 1

    # `|| true` INSIDE both brace groups: an AND-list does NOT exempt these from
    # err_return.  The list only escapes the abort when the LEFT test fails; when
    # `[[ -r ]]` passes and the read then fails (the daemon unlinking its cache
    # between the test and the read — the same TOCTOU the if-form reads guard),
    # the failing right-hand side aborts this function.  That would skip every
    # state clear below, leaving a stale ACTIVE/PENDING selection and a stranded
    # "Duplicate text" prompt while this function reports success.  The trailing
    # form is not enough here: both callers observe the status
    # (`_zes_try_restart_monitor || return`).  Values and rc are unchanged.
    [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
    [[ -r "$_EDIT_SELECT_PRIMARY_FILE" ]] && { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") || true } 2>/dev/null
    _zes_clear_duplicate_prompt
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    return 0
}

# ─────────────────────────────────────────────────────────────────────
# _zes_wait_for_reactive_capture
# Block until the reactive Cmd+C watcher has finished publishing selection
# state (pending marker removed). This avoids proceeding with stale/empty
# selection state when the user types immediately after a mouse drag.
#
# If capture does not complete (dead daemon or stuck marker), fail closed
# by disabling daemon-backed handling for this cycle and resetting transient
# mouse-selection state.
# ─────────────────────────────────────────────────────────────────────
function _zes_wait_for_reactive_capture() {
    [[ ! -f "$_EDIT_SELECT_PENDING_FILE" ]] && return 0

    local _zes_pid _zes_start=$EPOCHREALTIME
    while [[ -f "$_EDIT_SELECT_PENDING_FILE" ]]; do
        if (( EPOCHREALTIME - _zes_start > 1.0 )); then
            _EDIT_SELECT_DAEMON_ACTIVE=0
            rm -f "$_EDIT_SELECT_PENDING_FILE" 2>/dev/null
            _zes_reset_mouse_selection_state
            _zes_try_restart_monitor >/dev/null 2>&1
            return 1
        fi

        _zes_pid=""
        # `|| true` inside the group for the same reason as the reads in
        # _zes_try_restart_monitor: `[[ -r ]] &&` only skips the read when the
        # test fails.  A daemon that unlinks its pid file between the test and
        # the read would otherwise abort this loop under inherited err_return —
        # and this function's status IS observed
        # (`_zes_wait_for_reactive_capture || return`), so the abort would also
        # skip the caller's own seq handling for that keypress.
        [[ -r "$_EDIT_SELECT_PID_FILE" ]] && { _zes_pid=$(<"$_EDIT_SELECT_PID_FILE") || true } 2>/dev/null
        if [[ -n "$_zes_pid" ]] && ! kill -0 "$_zes_pid" 2>/dev/null; then
            _EDIT_SELECT_DAEMON_ACTIVE=0
            rm -f "$_EDIT_SELECT_PENDING_FILE" 2>/dev/null
            _zes_reset_mouse_selection_state
            _zes_try_restart_monitor >/dev/null 2>&1
            return 1
        fi
    done

    return 0
}

# ─────────────────────────────────────────────────────────────────────
# _zes_sync_selection_state
# Called by ZLE widgets before acting on a keypress.
# Reads seq value and primary snapshot from cache files.
# On seq change: reads primary file, sets NEW_SELECTION_EVENT.
# On unchanged seq: preserves state so a published selection cannot be
# consumed before the action widget (delete/type/paste/cut) processes it.
#
# No _ZES_SELF_WRITE_CONTENT suppression is needed: the daemon watches
# mouse button releases only, and plugin clipboard writes do not emit
# daemon selection events.
# ─────────────────────────────────────────────────────────────────────
function _zes_sync_selection_state() {
    if ((!_EDIT_SELECT_DAEMON_ACTIVE)); then
        _zes_try_restart_monitor || return
    fi

    # For reactive Cmd+C capture, do not continue until agent publish/restore
    # has completed. This removes timing-dependent keypress behavior.
    _zes_wait_for_reactive_capture || return

    # Hot path (per keypress): read seq via the fork-free, redirect-free
    # $(<file) builtin.  The [[ -r ]] gate stands in for stderr suppression, so
    # this avoids the 2>/dev/null fd save/restore cost the brace-group form
    # pays — the same guarded-bare idiom the X11/Wayland hot paths use.  The
    # separate `local` declaration keeps current_seq defined (empty) when the
    # file is unreadable, so the `[[ -z ]]` guard below is nounset-safe.
    local current_seq
    # Trailing `|| true`: the `[[ -r ]] &&` list only escapes err_return when the
    # TEST fails.  When the test passes and the read then fails — the daemon
    # unlinking seq between the two — the failing right-hand side aborts this
    # function under a user's inherited err_return, stranding LAST_SEQ and
    # skipping the event handling for that keypress.  A simple command (not a
    # brace group) keeps the trailing guard effective in every caller context,
    # so this stays on the fd-cost-free guarded-bare form (no 2>/dev/null on the
    # hot path).  Byte-identical in every file state.
    [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
    [[ -z "$current_seq" ]] && return

    if [[ -n "$_EDIT_SELECT_LAST_SEQ" ]] && [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
        _EDIT_SELECT_LAST_SEQ="$current_seq"
        { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY="$new_primary"

        if [[ -n "$new_primary" ]]; then
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
        else
            # Empty primary: selection cleared (e.g. after paste/click-deselect).
            _zes_clear_duplicate_prompt
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
        fi
    elif [[ -z "$_EDIT_SELECT_LAST_SEQ" ]]; then
        _EDIT_SELECT_LAST_SEQ="$current_seq"
    fi
}

# Predicate for the hybrid matcher's binary-search phase: does any trimmed
# candidate at total trim `t` occur in BUFFER?  Relies on zsh dynamic scope to
# read the caller's `source`, `source_len`, `buf_len`, and `max_trim` locals.
function _zes_any_match_at_total_trim() {
    local -i t=$1 left_min left_max len left
    left_min=$(( t - max_trim > 0 ? t - max_trim : 0 ))
    left_max=$(( max_trim < t ? max_trim : t ))
    len=$(( source_len - t ))
    (( len > buf_len )) && return 1
    for (( left = left_min; left <= left_max; left++ )); do
        [[ "$BUFFER" == *"${source:$left:$len}"* ]] && return 0
    done
    return 1
}

# Line-structured resolver for decorated multiline whole-line selections: the
# first row may carry a left prompt breadcrumb and/or a right-aligned status
# segment (interior noise no end-trimmer can remove); continuation rows must be
# the command's own lines exactly.  Returns the clean contiguous BUFFER block in
# REPLY on success, or fails closed on non-alignment / two distinct aligning
# blocks.  Occurrence selection stays downstream in _zes_delete_mouse_selection.

function _zes_resolve_multiline() {
    # extendedglob is required by the phase-1b trailing-whitespace strips below.
    setopt localoptions extendedglob
    # Drop at most one trailing line-terminator (the row terminator a whole-line
    # selection appends), NOT interior decoration.
    local src="${1%$'\n'}"
    local -a _sl _bl
    _sl=("${(@f)src}")
    _bl=("${(@f)BUFFER}")
    local -i m=${#_sl} n=${#_bl} i k aligned
    (( m < 2 || m > n )) && return 1
    local matched_content content
    local -i have=0
    # Phase 1: forward containment — row 1 of source contains the whole buffer row
    # (absorbs prompt prefix + right-prompt/status suffix on both sides).
    for (( i = 1; i <= n - m + 1; i++ )); do
        [[ "${_sl[1]}" == *"${_bl[i]}"* ]] || continue
        aligned=1
        for (( k = 2; k <= m; k++ )); do
            [[ "${_sl[k]}" != "${_bl[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
        content="${(pj:\n:)_bl[i,i+m-1]}"
        if (( ! have )); then
            matched_content="$content"; have=1
        elif [[ "$content" != "$matched_content" ]]; then
            return 1   # two DISTINCT aligning blocks -> ambiguous -> fail closed
        fi
    done
    if (( have )); then REPLY="$matched_content"; return 0; fi
    # Phase 1b: trailing-whitespace-insensitive WHOLE-ROW alignment.  A terminal
    # cannot distinguish a trailing blank cell the user typed from screen
    # padding, so a captured row and its BUFFER row can disagree on trailing
    # whitespace in EITHER direction: GPU right-edge padding adds it, and
    # copy-time trimming (plus the macOS caller's own per-line strip) removes
    # it.  Compare rows with trailing whitespace removed, but splice the emitted
    # block from the BUFFER rows verbatim, so the result stays a real BUFFER
    # substring and correct-or-nothing still holds.  Placed AFTER exact phase 1
    # (which keeps priority) and BEFORE the partial-row phases 2/3: whole-row
    # alignment is strictly stronger evidence than a partial-row suffix/prefix
    # slide, which can otherwise latch onto a degenerate one-character overlap
    # when trailing whitespace is what desynchronised the rows.
    local -a _slc _blc
    _slc=("${(@)_sl%%[[:space:]]#}")
    _blc=("${(@)_bl%%[[:space:]]#}")
    for (( i = 1; i <= n - m + 1; i++ )); do
        [[ "${_slc[1]}" == *"${_blc[i]}"* ]] || continue
        aligned=1
        for (( k = 2; k <= m; k++ )); do
            [[ "${_slc[k]}" != "${_blc[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
        content="${(pj:\n:)_bl[i,i+m-1]}"
        if (( ! have )); then
            matched_content="$content"; have=1
        elif [[ "$content" != "$matched_content" ]]; then
            return 1   # two DISTINCT aligning blocks -> ambiguous -> fail closed
        fi
    done
    if (( have )); then REPLY="$matched_content"; return 0; fi
    # Phase 2: partial-first-line — selection started mid-line, so source row 1 is
    # <tail-of-buffer-row-1><right-prompt/status suffix>.  Find the longest prefix
    # of _sl[1] that is a suffix of _bl[i]; rows 2..m still require exact equality.
    local row1_content
    for (( i = 1; i <= n - m + 1; i++ )); do
        # Test row alignment first: it is m-1 string compares and rejects
        # nearly every offset, whereas the row-1 suffix search below is a
        # descending scan over the row length.  Both tests are pure, so
        # reordering them cannot change which offsets are accepted.
        aligned=1
        for (( k = 2; k <= m; k++ )); do
            [[ "${_sl[k]}" != "${_bl[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
        local -i sl1len=${#_sl[1]} bl1len=${#_bl[i]}
        local -i maxk=$(( sl1len < bl1len ? sl1len : bl1len ))
        local -i found=0
        for (( k = maxk; k >= 1; k-- )); do
            if [[ "${_bl[i]}" == *"${_sl[1]:0:$k}" ]]; then
                row1_content="${_sl[1]:0:$k}"; found=1; break
            fi
        done
        (( found )) || continue
        content="${row1_content}"$'\n'"${(pj:\n:)_bl[i+1,i+m-1]}"
        if (( ! have )); then
            matched_content="$content"; have=1
        elif [[ "$content" != "$matched_content" ]]; then
            return 1
        fi
    done
    if (( have )); then REPLY="$matched_content"; return 0; fi
    # Phase 3: partial-LAST-line — selection ended mid-line, so source row m is a
    # non-empty strict prefix of buffer row m.  Row 1 uses forward-containment OR
    # the partial-first suffix match; interior rows 2..m-1 require exact equality.
    for (( i = 1; i <= n - m + 1; i++ )); do
        # Interior-row alignment and the last-row prefix test are cheap and
        # reject nearly every offset; run them before resolving row 1.  All
        # three tests are pure, so the accepted offsets are unchanged.
        aligned=1
        for (( k = 2; k <= m - 1; k++ )); do
            [[ "${_sl[k]}" != "${_bl[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
        local lastrow="${_bl[i+m-1]}"
        [[ -n "${_sl[m]}" && ${#_sl[m]} -lt ${#lastrow} && "$lastrow" == "${_sl[m]}"* ]] || continue
        if [[ "${_sl[1]}" == *"${_bl[i]}"* ]]; then
            row1_content="${_bl[i]}"
        else
            local -i sl1len=${#_sl[1]} bl1len=${#_bl[i]}
            local -i maxk=$(( sl1len < bl1len ? sl1len : bl1len ))
            local -i found=0
            for (( k = maxk; k >= 1; k-- )); do
                if [[ "${_bl[i]}" == *"${_sl[1]:0:$k}" ]]; then
                    row1_content="${_sl[1]:0:$k}"; found=1; break
                fi
            done
            (( found )) || continue
        fi
        if (( m == 2 )); then
            content="${row1_content}"$'\n'"${_sl[m]}"
        else
            content="${row1_content}"$'\n'"${(pj:\n:)_bl[i+1,i+m-2]}"$'\n'"${_sl[m]}"
        fi
        if (( ! have )); then
            matched_content="$content"; have=1
        elif [[ "$content" != "$matched_content" ]]; then
            return 1
        fi
    done
    (( have )) || return 1
    REPLY="$matched_content"
    return 0
}

# Refine a trimmer candidate: if it is unique in BUFFER but stripping its
# boundary whitespace reveals >=2 occurrences, return the stripped form so the
# duplicate-disambiguation prompt fires correctly.  Sets REPLY.
function _zes_refine_trim_candidate() {
    local cand="$1"
    REPLY="$cand"
    setopt localoptions extendedglob
    # Occurrence counts use the C-level pattern-strip idiom (left-to-right,
    # non-overlapping matches) — identical counts to a per-character substring
    # walk, without the O(buffer^2) cost on large multibyte buffers.
    local -i clen=${#cand} cnt=0 idx=0
    local buf="$BUFFER"
    while [[ "$buf" == *"$cand"* ]]; do
        local prefix="${buf%%"$cand"*}"
        idx=$((idx + ${#prefix} + clen))
        # || true / return 0: this function is called bare and its status is
        # never read (both call sites print $REPLY immediately afterwards), but
        # a post-increment from 0 evaluates to 0 — rc 1 — and a bare `return`
        # propagates the failed guard's status.  Under inherited err_return
        # either one aborts the CALLER (_zes_match_selection_in_buffer), which
        # then reports "no match" for any selection needing the trimmer.
        (( cnt++ )) || true
        # The only consumer is `(( cnt == 1 ))`, so a second hit already
        # settles the answer — stop instead of counting the whole buffer.
        (( cnt > 1 )) && break
        buf="${BUFFER:$idx}"
    done
    (( cnt == 1 )) || return 0
    local stripped="${cand##[[:space:]]#}"
    stripped="${stripped%%[[:space:]]#}"
    local -i slen=${#stripped}
    [[ -n "$stripped" && slen -lt clen ]] || return 0
    local -i cnt2=0
    idx=0
    buf="$BUFFER"
    while [[ "$buf" == *"$stripped"* ]]; do
        prefix="${buf%%"$stripped"*}"
        idx=$((idx + ${#prefix} + slen))
        (( cnt2++ )) || true
        # The only consumer is `(( cnt2 >= 2 ))` — stop at two.
        (( cnt2 >= 2 )) && break
        buf="${BUFFER:$idx}"
    done
    (( cnt2 >= 2 )) && REPLY="$stripped"
    return 0
}

# Best trimmed-overlap matcher against BUFFER. Used to exclude prompt and
# terminal padding noise from mouse selections. Returns 0 with the matched
# substring in REPLY (X11/Wayland) or prints it to stdout (macOS, preserving
# the existing $() call-site contract).
function _zes_match_selection_in_buffer() {
    local source="$1"
    [[ -z "$source" ]] && return 1
    # Compute lengths once and reuse for the exact-match guard, reverse-
    # containment, and trim bounds (under a multibyte locale ${#x} is an O(n)
    # scan, so recomputing inline would repeat work).
    local -i source_len=${#source} buf_len=${#BUFFER} min_len=1
    (( buf_len == 0 )) && return 1

    # Length-guarded exact match: skip the BUFFER scan when source is longer
    # than BUFFER and therefore cannot fit (the prompt-including case).  ~10x
    # cheaper on that path.
    if (( source_len <= buf_len )) && [[ "$BUFFER" == *"$source"* ]]; then
        print -r -- "$source"
        return 0
    fi

    local -i max_trim=512
    (( max_trim > source_len - min_len )) && max_trim=$((source_len - min_len))

    # Reverse-containment fast path: the whole typed command (BUFFER) sits inside
    # a decorated whole-line selection.  Guard MUST be `source_len - buf_len <=
    # max_trim` (not 2*max_trim) for soundness, and `buf_len < source_len` (at
    # equal length the exact-match glob already rejected equality)
    if (( buf_len < source_len && source_len - buf_len <= max_trim )) \
       && [[ "$source" == *"$BUFFER"* ]]; then
        print -r -- "$BUFFER"
        return 0
    fi

    # Interior-newline gate (SHARED with X11/Wayland; only the on-failure wiring
    # differs).  A source that still contains a newline after dropping at most
    # one trailing terminator is a decorated MULTILINE selection with interior
    # noise the end-trimmer cannot remove.  macOS WIRING: on resolver success
    # print the clean block and return; on resolver FAILURE fall through to the
    # trimmer (macOS ran the trimmer on multiline sources before this feature, so
    # fail-closing here would regress current behavior).
    if [[ "${source%$'\n'}" == *$'\n'* ]]; then
        if _zes_resolve_multiline "$source"; then
            print -r -- "$REPLY"
            return 0
        fi
        # NO return here — fall through to the trimmer (preserves current macOS behavior).
    fi

    # --- Single-line trimmed fallback (hybrid ordered + binary search) ---
    local -i min_total=0
    (( source_len > buf_len )) && min_total=$((source_len - buf_len))
    local -i max_total=$(( 2 * max_trim ))
    (( max_total > source_len - min_len )) && max_total=$((source_len - min_len))
    (( min_total > max_total )) && return 1

    local -i ordered_budget=256
    # Skip the provably-empty first trim total when source_len - buf_len <=
    # max_trim: at that total every candidate has length buf_len and would have
    # to EQUAL BUFFER, which the exact-match / reverse-containment globs already
    # disproved.  Under source_len - buf_len > max_trim reverse-containment
    # short-circuited without its glob, so that total is not pre-tested — run it.
    local -i t=$min_total
    (( source_len - buf_len <= max_trim )) && t+=1

    local -i checks_used=0 candidate_count left_min left_max len left
    local candidate
    while (( t <= max_total )); do
        left_min=$(( t - max_trim > 0 ? t - max_trim : 0 ))
        left_max=$(( max_trim < t ? max_trim : t ))
        candidate_count=$(( left_min > left_max ? 0 : left_max - left_min + 1 ))
        # The first executed total (checks_used == 0) is never budget-skipped.
        (( checks_used > 0 && checks_used + candidate_count > ordered_budget )) && break
        len=$(( source_len - t ))
        if (( len >= min_len && len <= buf_len )); then
            for (( left = left_min; left <= left_max; left++ )); do
                candidate="${source:$left:$len}"
                if [[ "$BUFFER" == *"$candidate"* ]]; then
                    _zes_refine_trim_candidate "$candidate"
                    print -r -- "$REPLY"
                    return 0
                fi
            done
        fi
        checks_used=$(( checks_used + candidate_count ))
        t+=1
    done

    # Binary search for the smallest matching total trim, then a final left-
    # ascending scan at that total to preserve the smallest-left tie behavior.
    local -i lo=$t hi=$max_total mid
    (( lo > hi )) && return 1
    _zes_any_match_at_total_trim $hi || return 1
    while (( lo < hi )); do
        mid=$(( (lo + hi) / 2 ))
        if _zes_any_match_at_total_trim $mid; then hi=$mid; else lo=$(( mid + 1 )); fi
    done
    left_min=$(( lo - max_trim > 0 ? lo - max_trim : 0 ))
    left_max=$(( max_trim < lo ? max_trim : lo ))
    len=$(( source_len - lo ))
    if (( len >= min_len && len <= buf_len )); then
        for (( left = left_min; left <= left_max; left++ )); do
            candidate="${source:$left:$len}"
            if [[ "$BUFFER" == *"$candidate"* ]]; then
                _zes_refine_trim_candidate "$candidate"
                print -r -- "$REPLY"
                return 0
            fi
        done
    fi
    return 1
}

# ─────────────────────────────────────────────────────────────────────
# _zes_detect_mouse_selection
# Determine whether a selection is active (AX or Cmd+C capture path).
# Returns 0 when active, sets _EDIT_SELECT_ACTIVE_SELECTION.  Includes
# macOS-specific whitespace normalization and buffer matching for GPU
# terminal drags that pad selections to the right screen edge.
# ─────────────────────────────────────────────────────────────────────
function _zes_detect_mouse_selection() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return 1

    if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
        if ((!_EDIT_SELECT_NEW_SELECTION_EVENT)); then
            if [[ -n "$_EDIT_SELECT_LAST_PRIMARY" ]] && \
               [[ "$_EDIT_SELECT_LAST_PRIMARY" == "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && \
               [[ "$BUFFER" == *"$_EDIT_SELECT_ACTIVE_SELECTION"* ]]; then
                return 0
            fi
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            return 1
        fi
        return 0
    fi

    local mouse_sel
    local is_new_selection=0

    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        if ((_EDIT_SELECT_NEW_SELECTION_EVENT)); then
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            is_new_selection=1
            mouse_sel="$_EDIT_SELECT_LAST_PRIMARY"
            [[ -z "$mouse_sel" ]] && return 1
        else
            # No new selection event: the matcher below runs only under
            # is_new_selection=1, so mouse_sel is unused here.  Check the
            # emptiness guard directly against the cached primary instead of
            # copying it into mouse_sel first (avoids an O(selection-size)
            # copy on every no-event keystroke — the hottest path).
            # ${var:+x} keeps the test itself O(1) too: `[[ -z "$var" ]]`
            # materialises the whole value before testing it, which is
            # measurable once a stale raw selection is large.
            [[ -z "${_EDIT_SELECT_LAST_PRIMARY:+x}" ]] && return 1
        fi
    else
        return 1
    fi

    if ((is_new_selection)); then
        setopt localoptions extendedglob

        # 1. Normalize CR to LF (defensive no-op on real data — tested terminals produce
        #    LF-separated AX selections with zero CR — but guards against \r-producing paths).
        # Route the replacement through a variable: in a double-quoted expansion
        # the RHS $'\n' is NOT ANSI-C-expanded (it inserts the literal bytes
        # $ ' \ n '), so the one-liner ${mouse_sel//$'\r'/$'\n'} does not produce
        # a real newline.  A CR-delimited whole-command selection would then never
        # trip the interior-newline gate and would mis-resolve to a wrong partial
        # (a correct-or-nothing violation).
        local nl=$'\n'
        mouse_sel="${mouse_sel//$'\r'/$nl}"

        # GPU terminal selections: strip trailing whitespace padding.
        # GPU terminals (Alacritty, WezTerm, Ghostty) often append spaces out to the right
        # edge of the screen when dragging across multiple lines. This prevents exact matching.
        local -a lines
        lines=("${(@f)mouse_sel}")
        local i
        for ((i = 1; i <= ${#lines[@]}; i++)); do
            # Standard zsh extendedglob to strip trailing spaces per line
            lines[i]="${lines[i]%%[[:space:]]#}"
        done
        # Rejoin with newlines
        local clean_sel="${(F)lines}"
        # Finally strip overall terminal padding
        clean_sel="${clean_sel%%[[:space:]]#}"

        # Byte-faithful parallel candidate: strip only the overall trailing pad,
        # leaving interior trailing whitespace intact.  The per-line loop above
        # destroys interior trailing whitespace on purpose for scrollback
        # decoration, but a real command line ending in a space (Path-A AX
        # capture or Path-B Cmd+C) then fails exact-buffer-match, the
        # resolver's exact-interior-row check then fails too, and the trimmer
        # falls back to a shorter substring — deleting/replacing the wrong
        # region.  Both candidates below are matched independently; see the
        # length arbitration further down.
        local plain_sel="${mouse_sel%%[[:space:]]#}"

        # macOS paths sometimes add leading prompts or trailing UI garbage in drags.
        # If the exact unpadded string matches, accept it. otherwise, attempt to slide
        # prefixes/suffixes to find true overlap.

        _EDIT_SELECT_LAST_PRIMARY="$clean_sel"
        if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            zle -M ""
            zle -R
            _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_ACTIVE_SELECTION=""

        local matched_sel=""
        local plain_match=""
        # || true on the matcher command substitutions below: the matcher's rc is
        # deliberately unused here (macOS keys entirely on whether the printed
        # text is empty), but the assignment inherits it, so a no-match rc 1
        # would abort this widget under inherited err_return before the
        # fail-closed PENDING/prompt handling runs.
        if [[ -n "$clean_sel" ]]; then
            matched_sel="$(_zes_match_selection_in_buffer "$clean_sel")" || true
        fi
        if [[ -n "$plain_sel" && "$plain_sel" != "$clean_sel" ]]; then
            plain_match="$(_zes_match_selection_in_buffer "$plain_sel")" || true
        fi

        # Longest-match arbitration (strip-vs-plain): when both candidates match,
        # keep the longer result.  Per-line stripping destroys interior trailing
        # whitespace (turning a real "echo hello \n" + "ls" selection into plain
        # "echo hello\nls", which then fails to match the buffer literally), so
        # when the plain candidate wins it is strictly longer than the strip
        # result and is the correct byte-faithful block.  When only the strip
        # candidate matches (scrollback decoration, padded short rows, single-line
        # exact-equal collapse) or when results tie, keep the strip result —
        # identical to today.
        if [[ -n "$plain_match" && ( -z "$matched_sel" || ${#plain_match} -gt ${#matched_sel} ) ]]; then
            matched_sel="$plain_match"
        fi

        # Visual-wrap fallback (unchanged): terminal may insert \n for wrapped
        # display while BUFFER keeps a single logical line.
        if [[ -z "$matched_sel" && -n "$clean_sel" && "$clean_sel" == *$'\n'* ]]; then
            local nowrap_sel="${clean_sel//$'\n'/}"
            if [[ -n "$nowrap_sel" ]]; then
                matched_sel="$(_zes_match_selection_in_buffer "$nowrap_sel")" || true
            fi
        fi

        if [[ -n "$matched_sel" ]]; then
            _EDIT_SELECT_ACTIVE_SELECTION="$matched_sel"
            return 0
        fi

        # Fail closed for this keypress when a fresh selection cannot be
        # resolved yet. This prevents immediate fallback key behavior from
        # clearing visual selection state in GPU terminals.
        _EDIT_SELECT_PENDING_SELECTION="$clean_sel"

        # Do not return yet. Attempt pending-resolution immediately in this
        # same keypress so type-to-replace does not require a second try.
    fi

    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        local sel="$_EDIT_SELECT_PENDING_SELECTION"
        # Skip the re-match when this keypress just set PENDING itself: the
        # branch above only reaches here after the matcher already failed on
        # exactly this string against this BUFFER, so re-running it would fork
        # a second time for a provably identical empty result.  A PENDING left
        # by an earlier keypress (is_new_selection=0) still needs the re-match,
        # because BUFFER may have changed since it was recorded.
        if ((!is_new_selection)) && [[ "$BUFFER" != *"$sel"* ]]; then
            local resolved_sel
            resolved_sel="$(_zes_match_selection_in_buffer "$sel")" || true
            [[ -n "$resolved_sel" ]] && sel="$resolved_sel"
        fi

        local sel_len=${#sel}
        if [[ "$BUFFER" == *"$sel"* ]]; then
            local buf="$BUFFER" idx=0
            while [[ "$buf" == *"$sel"* ]]; do
                local prefix="${buf%%"$sel"*}"
                idx=$((idx + ${#prefix}))
                local end_pos=$((idx + sel_len))
                if ((CURSOR >= idx && CURSOR <= end_pos)); then
                    _EDIT_SELECT_ACTIVE_SELECTION="$sel"
                    _EDIT_SELECT_PENDING_SELECTION=""
                    zle -M ""
                    zle -R
                    _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
                    return 0
                fi
                # Occurrences ascend, so once one starts past the cursor no
                # later occurrence can contain it either — stop scanning.
                ((idx > CURSOR)) && break
                idx=$((idx + sel_len))
                buf="${BUFFER:$idx}"
            done
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_LAST_PRIMARY=""
        _zes_clear_primary
        zle -M ""
        zle -R
        _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
    fi

    return 1
}

# ─────────────────────────────────────────────────────────────────────
# _zes_delete_mouse_selection
# Remove active selection from BUFFER at occurrence closest to CURSOR.
# Uses complete ZLE state cleanup (WSL pattern):
#   REGION_ACTIVE=0, _zes_sync_after_paste, deactivate-region, -K main.
# ─────────────────────────────────────────────────────────────────────
function _zes_delete_mouse_selection() {
    [[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1

    local sel="$_EDIT_SELECT_ACTIVE_SELECTION" \
          sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
    ((sel_len > ${#BUFFER})) && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
        return 1
    }
    [[ "$BUFFER" != *"$sel"* ]] && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
        return 1
    }

    # Occurrences are produced left to right, so the scan can stop as soon as
    # the answer is fixed: either the cursor falls inside the occurrence just
    # found, or a second occurrence already starts past the cursor (no later
    # one can contain it either).  first_pos covers the single-occurrence case,
    # which is deleted unconditionally.
    local buf="$BUFFER" idx=0
    local -i num_occurrences=0 first_pos=-1 target_pos=-1
    while [[ "$buf" == *"$sel"* ]]; do
        local prefix="${buf%%"$sel"*}"
        idx=$((idx + ${#prefix}))
        (( ++num_occurrences == 1 )) && first_pos=$idx
        if ((CURSOR >= idx && CURSOR <= idx + sel_len)); then
            target_pos=$idx
            break
        fi
        (( num_occurrences > 1 && idx > CURSOR )) && break
        idx=$((idx + sel_len))
        buf="${BUFFER:$idx}"
    done
    (( target_pos < 0 && num_occurrences == 1 )) && target_pos=$first_pos

    if ((target_pos >= 0)); then
        BUFFER="${BUFFER:0:$target_pos}${BUFFER:$((target_pos + sel_len))}"
        CURSOR=$target_pos
        REGION_ACTIVE=0
        # WSL pattern: full ZLE state cleanup.
        _zes_sync_after_paste
        _EDIT_SELECT_NEW_SELECTION_EVENT=0
        zle deactivate-region -w 2>/dev/null
        zle -K main 2>/dev/null
        return 0
    fi

    zle -M "Duplicate text: place cursor inside the occurrence you want to modify"
    _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=1
    _EDIT_SELECT_PENDING_SELECTION="$_EDIT_SELECT_ACTIVE_SELECTION"
    _EDIT_SELECT_ACTIVE_SELECTION=""
    return 1
}

# ── ZLE Widgets ───────────────────────────────────────────────────────

function edit-select::select-all() {
    _zes_clear_mouse_selection_prompt_state
    MARK=0
    CURSOR=${#BUFFER}
    REGION_ACTIVE=1
    zle -K edit-select
}
zle -N edit-select::select-all

function _zes_delete_selected_region() {
    zle kill-region -w
    zle -K main
}
zle -N edit-select::kill-region _zes_delete_selected_region

function edit-select::delete-mouse-or-backspace() {
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                return
            fi
            [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
            _zes_reset_mouse_selection_state
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle backward-delete-char -w
}
zle -N edit-select::delete-mouse-or-backspace

function edit-select::delete-mouse-or-delete() {
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                return
            fi
            [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
            _zes_reset_mouse_selection_state
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle delete-char -w
}
zle -N edit-select::delete-mouse-or-delete

function edit-select::handle-char() {
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w
                return
            fi
            # Block typing on failure (disambiguation pending).
            [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
            _zes_reset_mouse_selection_state
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle self-insert -w
}
zle -N edit-select::handle-char

function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w
    zle -K main
    zle -U -- "$KEYS"
}
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

function edit-select::replace-selection() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
        zle self-insert -w
        return
    fi
    zle self-insert -w
}
zle -N edit-select::replace-selection

function edit-select::copy-region() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}" || true
        _zes_sync_after_paste
        zle deactivate-region -w
        zle -K main
    else
        local primary_sel
        primary_sel=$(_zes_get_primary) || return
        _zes_copy_to_clipboard "$primary_sel" || true
        _zes_sync_after_paste
    fi
}
zle -N edit-select::copy-region

function edit-select::cut-region() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local length=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        _zes_copy_to_clipboard "${BUFFER:$start:$length}" || { zle -M "Cut failed: clipboard unavailable"; return; }
        _zes_sync_after_paste
        zle kill-region -w
        zle -K main
    else
        ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            local sel="$_EDIT_SELECT_ACTIVE_SELECTION"
            # Delete FIRST for instant visual feedback, THEN copy async.
            if _zes_delete_mouse_selection; then
                _zes_copy_to_clipboard "$sel"
                return
            fi
            [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
            _zes_reset_mouse_selection_state
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
}
zle -N edit-select::cut-region

# Read clipboard for paste operations with a short bounded retry window.
# When avoid_value is provided, prefer a value different from avoid_value
# during retries (helps avoid transient copy-on-select races).
# In SSH mode (_ZES_SSH_MODE=1), _zes_get_clipboard always returns 1, so the
# retry loop would spin ~200 ms of sleeps only to abort. Short-circuit to the
# same rc=1 instantly (event-driven, no time-based stall).
function _zes_get_clipboard_for_paste() {
    ((_ZES_SSH_MODE)) && return 1
    local avoid_value="$1"
    local content
    local -i attempt

    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        # || true: the retry loop keys on the CONTENT being non-empty, never on
        # the read's status (SSH mode is short-circuited above, so a nonzero rc
        # here just means "nothing on the pasteboard yet").  The assignment
        # inherits that rc, and under inherited err_return it would abort the
        # widget on the first empty attempt — collapsing the bounded retry
        # window Path B relies on after a synthetic Cmd+C.
        content="$(_zes_get_clipboard 2>/dev/null)" || true
        if [[ -n "$content" ]]; then
            if [[ -n "$avoid_value" && "$content" == "$avoid_value" ]] && (( attempt < 20 )); then
                sleep 0.01
                continue
            fi
            print -r -- "$content"
            return 0
        fi
        (( attempt < 20 )) && sleep 0.01
    done

    return 1
}

function edit-select::paste-clipboard() {
    local pre_buffer="$BUFFER"
    local pre_cursor=$CURSOR
    local pre_mark=$MARK
    local pre_region=$REGION_ACTIVE
    local -i did_delete=0
    local -i did_mouse_delete=0
    local deleted_sel=""

    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
        did_delete=1
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            deleted_sel="$_EDIT_SELECT_ACTIVE_SELECTION"
            if _zes_delete_mouse_selection; then
                :  # deletion succeeded; fall through to paste
                did_delete=1
                did_mouse_delete=1
            else
                [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
                _zes_reset_mouse_selection_state
                return  # disambiguation pending; abort paste
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi

    local clipboard_content
    local clipboard_avoid=""
    if ((did_mouse_delete)) && [[ -n "$deleted_sel" ]]; then
        clipboard_avoid="$deleted_sel"
    fi

    if ! clipboard_content=$(_zes_get_clipboard_for_paste "$clipboard_avoid"); then
        if ((did_delete)); then
            BUFFER="$pre_buffer"
            CURSOR=$pre_cursor
            MARK=$pre_mark
            REGION_ACTIVE=$pre_region
            zle -R
        fi
        return
    fi

    LBUFFER="${LBUFFER}${clipboard_content}"
    _zes_sync_after_paste
}
zle -N edit-select::paste-clipboard

# Consume an incoming bracketed paste block without mutating BUFFER.
function _zes_discard_bracketed_paste_payload() {
    local saved_buffer="$BUFFER"
    local saved_cursor=$CURSOR
    local saved_mark=$MARK
    local saved_region=$REGION_ACTIVE

    zle .bracketed-paste

    BUFFER="$saved_buffer"
    CURSOR=$saved_cursor
    MARK=$saved_mark
    REGION_ACTIVE=$saved_region
    zle -R
}

function edit-select::bracketed-paste-replace() {
    if ((REGION_ACTIVE)); then
        local start=$((MARK < CURSOR ? MARK : CURSOR))
        local len=$((MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK))
        BUFFER="${BUFFER:0:$start}${BUFFER:$((start + len))}"
        CURSOR=$start
        REGION_ACTIVE=0
        zle -K main
    elif ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state
        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                :
            else
                _zes_discard_bracketed_paste_payload
                [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]] && return
                _zes_reset_mouse_selection_state
                return
            fi
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            _zes_discard_bracketed_paste_payload
            return
        fi
    fi
    zle .bracketed-paste
    _zes_sync_after_paste
}
zle -N edit-select::bracketed-paste-replace

function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

function _zes_up_line_or_history_reset() {
    _zes_reset_mouse_selection_state
    REGION_ACTIVE=0
    zle deactivate-region -w 2>/dev/null
    zle .up-line-or-history -w
}
zle -N up-line-or-history _zes_up_line_or_history_reset

function _zes_down_line_or_history_reset() {
    _zes_reset_mouse_selection_state
    REGION_ACTIVE=0
    zle deactivate-region -w 2>/dev/null
    zle .down-line-or-history -w
}
zle -N down-line-or-history _zes_down_line_or_history_reset

function _zes_activate_region_and_dispatch() {
    _zes_clear_mouse_selection_prompt_state
    if ((!REGION_ACTIVE)); then
        zle set-mark-command -w
        zle -K edit-select
    fi
    zle "${WIDGET#edit-select::}" -w
}

function _zes_terminal_focus_in() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        { local current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") } 2>/dev/null
        if [[ -n "$current_seq" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"
        fi
    fi
    _zes_reset_mouse_selection_state
}
zle -N _zes_terminal_focus_in

function _zes_terminal_focus_out() {
    _zes_reset_mouse_selection_state
}
zle -N _zes_terminal_focus_out

# ─────────────────────────────────────────────────────────────────────
# _zes_wezterm_mousedown_clear
# WezTerm (and compatible terminals) send \e[>62300u via
# pane:send_text() on mouse-Down when an active selection exists.
# This widget clears the stale NEW_SELECTION_EVENT before the user
# can type, preventing phantom deletion of the old selection.
# Add to WezTerm config:
#   { Down = { streak = 1, button = "Left" } }
#   action = wezterm.action_callback(function(window, pane)
#     local sel = window:get_selection_text_for_pane(pane)
#     if sel ~= "" then pane:send_text("\x1b[>62300u") end
#     window:perform_action(act.ClearSelection, pane)
#     window:perform_action(act.SelectTextAtMouseCursor("Cell"), pane)
#   end)
# ─────────────────────────────────────────────────────────────────────
function _zes_wezterm_mousedown_clear() {
    _zes_reset_mouse_selection_state
}
zle -N _zes_wezterm_mousedown_clear
bindkey -M emacs '\e[>62300u' _zes_wezterm_mousedown_clear
bindkey '\e[>62300u' _zes_wezterm_mousedown_clear

# ─────────────────────────────────────────────────────────────────────
# edit-select::zle-line-pre-redraw
# ZLE hook: fires AFTER every widget, BEFORE the display redraws.
# Must be fast — no forks.  Detects selection changes by comparing the
# seq file's content (zsh's $(<file) builtin — no fork, faster than zstat
# +mtime on macOS).  Daemon liveness checked at most once every 30s.
# ─────────────────────────────────────────────────────────────────────
function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return

    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Liveness probe: at most once every 30s (amortised).
        if ((EPOCHSECONDS > _ZES_LAST_PID_CHECK + 30)); then
            _ZES_LAST_PID_CHECK=$EPOCHSECONDS
            local pid
            # Trailing `|| true`: `[[ -r ]] &&` only escapes err_return when the
            # TEST fails.  The agent unlinks its pid file on SIGTERM, so a death
            # landing between this test and the read makes the read fail and
            # aborts the hook — BEFORE the dead-daemon branch below runs, so
            # _EDIT_SELECT_DAEMON_ACTIVE stays a stale 1, the restart never
            # fires, and zsh-syntax-highlighting is skipped for that redraw
            # (it wraps widgets as `builtin zle "$@" && _zsh_highlight`).
            # `local pid` is on the prior line and cannot mask the rc.  Values
            # are unchanged in every file state; only the ignored rc differs.
            [[ -r "$_EDIT_SELECT_PID_FILE" ]] && pid=$(<"$_EDIT_SELECT_PID_FILE") || true
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                _EDIT_SELECT_DAEMON_ACTIVE=0
                _zes_start_monitor
                return
            fi
        fi

        # Hot path (every redraw): read seq via the fork-free, redirect-free
        # $(<file) builtin.  The [[ -r ]] gate stands in for stderr suppression
        # (no 2>/dev/null fd save/restore on this per-redraw path), mirroring
        # the X11/Wayland pre-redraw hooks.  The separate `local` declaration
        # keeps current_seq defined (empty) on an unreadable file so the
        # `[[ -z ]]` guard below stays nounset-safe.
        local current_seq
        # Trailing `|| true`: same TOCTOU as the sync-state read — `[[ -r ]] &&`
        # only escapes err_return when the TEST fails, so a seq unlinked between
        # the test and the read would abort this hook instead of taking the
        # dead-daemon branch below.  The abort also skips zsh-syntax-
        # highlighting, which wraps widgets as `builtin zle "$@" && _zsh_highlight`.
        [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
        if [[ -z "$current_seq" ]]; then
            _EDIT_SELECT_DAEMON_ACTIVE=0
            return
        fi

        if [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"
            { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null

            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then
                _EDIT_SELECT_NEW_SELECTION_EVENT=1
            else
                # Empty primary: selection was cleared (click-deselect, paste).
                _zes_clear_duplicate_prompt
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
            fi
        fi
    fi
}

# Lazy installer launcher for maintenance modes.  This path is only touched
# when the user explicitly invokes these subcommands, so normal shell startup
# cost remains unchanged.
function edit-select::run-installer-mode() {
    local mode="$1"
    local installer="$_EDIT_SELECT_PLUGIN_DIR/../assets/auto-install/install.sh"

    if ! (( ${+commands[bash]} )); then
        print -u2 "Error: bash is required to run installer modes."
        return 1
    fi
    if [[ ! -r "$installer" ]]; then
        print -u2 "Error: Installer not found at: $installer"
        return 1
    fi

    command bash "$installer" --local --mode "$mode"
}

# Public CLI entry-point.
function edit-select() {
    case "$1" in
    conf | config)
        local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard-macos.zsh"
        if [[ -f "$wizard_file" ]]; then
            source "$wizard_file" 2>/dev/null || {
                print -u2 "Error: Failed to load configuration wizard"
                return 1
            }
            edit-select::config-wizard
        else
            print -u2 "Error: Configuration wizard not found at: $wizard_file"
            return 1
        fi
        ;;
    setup-ax)
        if [[ -x "$_EDIT_SELECT_MONITOR_BIN" ]]; then
            print "Requesting Accessibility permission for mouse selection..."
            print "A system dialog will appear. Click 'Open System Settings',"
            print "then enable the toggle next to your terminal application."
            if "$_EDIT_SELECT_MONITOR_BIN" --request-ax 2>/dev/null; then
                print "✓ Accessibility permission granted. Mouse selection is now active."
                print "  Restart the daemon: source ~/.zshrc"
            else
                print "⚠ Permission not yet granted."
                print "  Open: System Settings → Privacy & Security → Accessibility"
                print "  Enable the toggle for your terminal application."
                print "  Then restart: source ~/.zshrc"
            fi
        else
            print -u2 "Error: agent binary not found."
            print -u2 "Build it: cd <plugin-dir>/impl-macos/backends/macos && make"
            return 1
        fi
        ;;
    conflicts)
        edit-select::run-installer-mode conflicts
        ;;
    integrate)
        edit-select::run-installer-mode integrate
        ;;
    update)
        edit-select::run-installer-mode update
        ;;
    build)
        edit-select::run-installer-mode build
        ;;
    uninstall)
        edit-select::run-installer-mode uninstall
        ;;
    setup-hooks)
        edit-select::setup-hooks
        ;;
    remove-hooks)
        edit-select::remove-hooks
        ;;
    *)
        print "edit-select - Text selection and clipboard management for Zsh (macOS)"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
        print "  setup-ax        Grant Accessibility permission for mouse selection"
        print "  conflicts       Run installer conflict detection mode"
        print "  integrate       Run installer terminal configuration mode"
        print "  update          Run installer update mode"
        print "  build           Run installer build-agents mode"
        print "  uninstall       Run installer uninstall mode"
        print "  setup-hooks     Install git hooks for automatic update notifications"
        print "  remove-hooks    Remove git hooks"
        ;;
    esac
}

# Source backend
source "$_EDIT_SELECT_PLUGIN_DIR/backends/macos/macos-backend.zsh"

# Read user config
edit-select::load-config

# Establish keymap. NOTE: Requires edit-select::load-config to have run first.
function { emulate -L zsh
    bindkey -N edit-select
    bindkey -M edit-select -R '^@'-'^Z' edit-select::deselect-and-input
    bindkey -M edit-select -R '^\'-'^?' edit-select::deselect-and-input
    bindkey -M edit-select -R ' '-'~'   edit-select::replace-selection

    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char'
        'kRIT' '^[[1;2C' 'forward-char'
        'kri'  '^[[1;2A' 'up-line'
        'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line'
        'kEND' '^[[1;2F' 'end-of-line'
        ''     '^[[1;10D' 'beginning-of-line'
        ''     '^[[1;10C' 'end-of-line'
        ''     "$EDIT_SELECT_KEY_BUFFER_START" 'beginning-of-buffer'
        ''     "$EDIT_SELECT_KEY_BUFFER_END"   'end-of-buffer'
        ''     "$EDIT_SELECT_KEY_SEL_WORD_LEFT" 'backward-word'
        ''     "$EDIT_SELECT_KEY_SEL_WORD_RIGHT" 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}
        esc=${nav_bind[i + 1]}
        wid=${nav_bind[i + 2]}
        [[ -z "$esc" ]] && continue
        seq=${terminfo[$ti]:-$esc}
        zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs       "$seq" "edit-select::${wid}"
        bindkey -M edit-select "$seq" "edit-select::${wid}"
    done

    # Standard macOS movement bindings (non-selecting): Cmd+Left/Right moves to line start/end.
    bindkey -M emacs       '^[[1;9D' beginning-of-line
    bindkey -M emacs       '^[[1;9C' end-of-line
    bindkey -M edit-select '^[[1;9D' beginning-of-line
    bindkey -M edit-select '^[[1;9C' end-of-line

    # Secondary Option+Left / Option+Right aliases for Terminal.app "Use Option as Meta Key" mode.
    # Intentionally hardcoded (not user-configurable) — Terminal.app-specific alternate encoding.
    bindkey -M emacs '\eb' backward-word
    bindkey -M emacs '\ef' forward-word

    local -a dest_bind=(
        'kdch1' '^[[3~' 'edit-select::kill-region'
        'bs'    '^?'    'edit-select::kill-region'
    )
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}
        bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    [[ -n "$EDIT_SELECT_KEY_CUT" ]]  && bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    bindkey -M edit-select '^[[200~'  edit-select::bracketed-paste-replace

    [[ -n "$EDIT_SELECT_KEY_SELECT_ALL" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
    [[ -n "$EDIT_SELECT_KEY_COPY" ]]       && bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    if [[ -n "$EDIT_SELECT_KEY_CUT" ]]; then
        bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
        bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    fi

    [[ -n "$EDIT_SELECT_KEY_WORD_LEFT" ]]  && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_LEFT" backward-word
    [[ -n "$EDIT_SELECT_KEY_WORD_RIGHT" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_RIGHT" forward-word
    bindkey -M edit-select '\e[I'     _zes_terminal_focus_in
    bindkey -M edit-select '\e[O'     _zes_terminal_focus_out
}

# Undo/redo
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# ── Linux SSH key remapping ──────────────────────────────────────────
# When SSH mode is active, also bind the Linux Ctrl-key sequences to the
# macOS widgets. This lets a Linux terminal user (gnome-terminal, Kitty,
# WezTerm, Ghostty, Alacritty) SSH into this macOS box and keep the exact
# keys the Linux build binds locally — Ctrl+Shift+C (copy), Ctrl+X (cut),
# Ctrl+A (select all), Ctrl+Z (undo), Ctrl+Shift+Z (redo), Ctrl+Arrow
# (word nav), Ctrl+Shift+Arrow/Home/End (extend selection). The bindings
# mirror the Linux plugin's own defaults so behavior is identical to a
# local Linux session.
#
# These are additive — they do not overwrite the macOS Cmd CSI-u defaults,
# and the ((_ZES_SSH_MODE)) guard means zero overhead on non-SSH sessions.
#
# Notes on the keys that behave specially (identical to the Linux build):
#   • Ctrl+Z → undo:  at the prompt ZLE owns the keystroke and undoes; while
#     a foreground job runs, ZLE is inactive and the tty suspends as usual.
#   • Ctrl+X → cut:   zsh keeps ^X as the emacs prefix and only fires cut
#     after KEYTIMEOUT, so ^X^E / ^X^F etc. still work.
#   • Ctrl+A → select all:  overrides emacs beginning-of-line, so plain Home
#     is bound to beginning-of-line below to keep line-start reachable — the
#     same pairing the Linux build ships.
# NOT bound: Ctrl+C (tty SIGINT — copy is Ctrl+Shift+C) and Ctrl+V (paste
# can't read the clipboard back over SSH; use the terminal's native paste).
if ((_ZES_SSH_MODE)); then
    # Copy (Ctrl+Shift+C — the Linux COPY default; ^C stays as SIGINT)
    bindkey -M emacs       '^[[67;6u' edit-select::copy-region
    bindkey -M edit-select '^[[67;6u' edit-select::copy-region
    # Cut (Ctrl+X — emacs prefix preserved)
    bindkey -M emacs       '^X' edit-select::cut-region
    bindkey                '^X' edit-select::cut-region
    bindkey -M edit-select '^X' edit-select::cut-region
    # Select all (Ctrl+A — overrides beginning-of-line; Home restores it below)
    bindkey -M emacs       '^A' edit-select::select-all
    # Undo / redo (Ctrl+Z at the prompt; Ctrl+Shift+Z CSI-u for redo)
    bindkey -M emacs       '^Z' undo
    bindkey                '^Z' undo
    bindkey -M emacs       '^[[90;6u' redo
    bindkey                '^[[90;6u' redo
    # Line start / end via plain Home/End (keeps line-start after ^A override).
    # Broad defaults covering normal, application, and rxvt/xterm modes —
    # mirrors the Linux build's Home/End fallback set.
    bindkey -M emacs       '^[[H' beginning-of-line
    bindkey -M emacs       '^[OH' beginning-of-line
    bindkey -M emacs       '^[[1~' beginning-of-line
    bindkey -M emacs       '^[[7~' beginning-of-line
    bindkey -M emacs       '^[[F' end-of-line
    bindkey -M emacs       '^[OF' end-of-line
    bindkey -M emacs       '^[[4~' end-of-line
    bindkey -M emacs       '^[[8~' end-of-line
    # Word navigation (non-selecting — Ctrl+Left / Ctrl+Right)
    bindkey -M emacs       '^[[1;5D' backward-word
    bindkey -M emacs       '^[[1;5C' forward-word
    # Word selection (Ctrl+Shift+Left/Right — region-activating)
    bindkey -M emacs       '^[[1;6D' edit-select::backward-word
    bindkey -M edit-select '^[[1;6D' edit-select::backward-word
    bindkey -M emacs       '^[[1;6C' edit-select::forward-word
    bindkey -M edit-select '^[[1;6C' edit-select::forward-word
    # Buffer selection (Ctrl+Shift+Home/End — region-activating)
    bindkey -M emacs       '^[[1;6H' edit-select::beginning-of-buffer
    bindkey -M edit-select '^[[1;6H' edit-select::beginning-of-buffer
    bindkey -M emacs       '^[[1;6F' edit-select::end-of-buffer
    bindkey -M edit-select '^[[1;6F' edit-select::end-of-buffer
fi

# Normalize MOUSE_REPLACEMENT
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1)  EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*)            EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# Start capture in both mouse-replacement modes.  Disabling replacement affects
# buffer mutation only; Ctrl+C must still be able to copy a mouse selection.
_zes_start_monitor || true
if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
    { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null || true
    { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") } 2>/dev/null || true
fi

# Apply config
# Re-enable DECSET 1004 on every new prompt so focus events are captured
# by the bound ZLE widgets.  Must be persistent (not one-shot) because
# _zes_disable_focus_reporting suppresses it before every command.
function _zes_enable_focus_reporting() {
    print -n '\e[?1004h' >$TTY || true
}
zle -N _zes_enable_focus_reporting

# Disable DECSET 1004 before command execution so focus-in/out
# escape sequences (\e[I / \e[O) are not printed as raw text
# while a foreground process is running.
function _zes_disable_focus_reporting() {
    print -n '\e[?1004l' >$TTY || true
}

# One-shot precmd that registers the deferred ZLE hooks, then removes itself.
# Registration is deferred to the first precmd (which runs only after the whole
# ~/.zshrc has finished sourcing) so these widgets are created AFTER other
# plugins have done their one-time ZLE widget binding.  In particular
# zsh-syntax-highlighting (on zsh < 5.9, or its legacy code path) wraps every
# pre-existing user widget at load time; a wrapped zle-line-pre-redraw makes
# _zsh_highlight run a full re-highlight on EVERY redraw (every cursor step of a
# click-to-move burst — the visible mouse-repositioning slowdown), and a wrapped
# zle-line-init adds redundant re-highlight passes on every prompt (proven to
# produce byte-identical region_highlight, i.e. pure waste).  Deferring means
# z-sy-h never sees either widget to wrap.  Both hooks still become active before
# the first prompt is drawn (precmd precedes line-init and line-pre-redraw), so
# selection detection and focus reporting are unchanged.
function _zes_register_redraw_hook() {
    autoload -Uz add-zle-hook-widget add-zsh-hook
    add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
    # Enable terminal focus reporting (DECSET 1004) and bind focus event
    # handlers so cross-pane selection changes are suppressed.  Registered here
    # (deferred) so the terminal's immediate CSI I reply is consumed by the
    # already-bound widgets instead of printing as raw ^[[I on VTE terminals.
    add-zle-hook-widget zle-line-init _zes_enable_focus_reporting
    add-zsh-hook -d precmd _zes_register_redraw_hook
}

function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    # Capture is independent of replacement: disabled mode still supports
    # copying mouse selections with the configured copy binding.
    _zes_start_monitor || true
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" \
            edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        # Register the pre-redraw + line-init (focus-reporting) hooks on the first
        # precmd (see _zes_register_redraw_hook) so zsh-syntax-highlighting cannot
        # wrap our dispatcher widgets and re-highlight redundantly.
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _zes_register_redraw_hook
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _zes_disable_focus_reporting
        bindkey -M emacs '\e[I' _zes_terminal_focus_in
        bindkey -M emacs '\e[O' _zes_terminal_focus_out
        bindkey '\e[I' _zes_terminal_focus_in
        bindkey '\e[O' _zes_terminal_focus_out
        bindkey -M emacs '\e[>62300u' _zes_wezterm_mousedown_clear
        bindkey '\e[>62300u' _zes_wezterm_mousedown_clear
    else
        bindkey -M emacs -R ' '-'~' self-insert
        bindkey -M emacs '^?' backward-delete-char
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
        bindkey -M emacs '^[[200~' bracketed-paste
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        autoload -Uz add-zsh-hook
        add-zsh-hook -d precmd _zes_register_redraw_hook 2>/dev/null
        add-zle-hook-widget -d line-pre-redraw \
            edit-select::zle-line-pre-redraw 2>/dev/null
        add-zle-hook-widget -d zle-line-init _zes_enable_focus_reporting 2>/dev/null
        autoload -Uz add-zsh-hook
        add-zsh-hook -d preexec _zes_disable_focus_reporting 2>/dev/null
        print -n '\e[?1004l' >$TTY || true
        bindkey -M emacs -r '\e[I' 2>/dev/null
        bindkey -M emacs -r '\e[O' 2>/dev/null
        bindkey -r '\e[I' 2>/dev/null
        bindkey -r '\e[O' 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_DUPLICATE_PROMPT_ACTIVE=0
        _EDIT_SELECT_PENDING_SELECTION=""
    fi
}
edit-select::apply-mouse-replacement-config
