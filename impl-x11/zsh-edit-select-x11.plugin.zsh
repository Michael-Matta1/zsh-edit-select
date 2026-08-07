# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# X11-only text selection and editing for Zsh command line.

# Load zsh/datetime for EPOCHSECONDS used in the liveness probe.
# (zsh/stat was previously loaded for zstat-based mtime detection;
# detection now uses the fork-free $(<seq) builtin instead.)
zmodload zsh/datetime 2>/dev/null

# Selection tracking state.
# LAST_PRIMARY: last text written to the agent cache (used for change detection).
# ACTIVE_SELECTION: the selection text currently matched in BUFFER (deletion pending).
# PENDING_SELECTION: ambiguous selection awaiting cursor disambiguation.
typeset -g _EDIT_SELECT_LAST_PRIMARY=""
typeset -g _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g _EDIT_SELECT_PENDING_SELECTION=""
# Public config: 1 enables mouse-selection-aware typing (type-to-replace); 0 disables.
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
# Public config: 1 enables prefix-pruning for instant cut-key dispatch; 0 preserves
# all prefix key chords and disables pruning (default, no regression behavior).
typeset -gi EDIT_SELECT_INSTANT_CUT=0
# Path to the user's persistent configuration file (sourced at startup).
typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
# Absolute directory of this plugin file; used to locate backend scripts.
typeset -g _EDIT_SELECT_PLUGIN_DIR="${${(%):-%x}:A:h}"
# Last-observed content of the seq file; compared (as an opaque string) on each
# ZLE callback to detect agent writes.  Content comparison catches intra-second
# events that integer-second mtime would alias, and is faster (no stat syscall).
typeset -g _EDIT_SELECT_LAST_SEQ=""
# Agent / detection state flags.
# DAEMON_ACTIVE: set when the selection agent process is confirmed running.
# NEW_SELECTION_EVENT: pulsed to 1 when a new seq value is detected; cleared after
#   one ZLE callback so the same change cannot fire the selection twice.
# EVENT_FIRED_FOR_SEQ: gate to avoid re-triggering on the same seq content.
# LAST_PID_CHECK: epoch seconds of the last kill -0 liveness probe.
typeset -gi _EDIT_SELECT_DAEMON_ACTIVE=0
typeset -gi _EDIT_SELECT_NEW_SELECTION_EVENT=0
typeset -gi _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=0
typeset -gi _ZES_LAST_PID_CHECK=0
# Cache directory and file paths written by the selection agent.
# XDG_RUNTIME_DIR is preferred (tmpfs, private to UID on systemd systems);
# TMPDIR is a fallback for environments that do not set it.
typeset -g _EDIT_SELECT_CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-${UID}"
typeset -g _EDIT_SELECT_SEQ_FILE="$_EDIT_SELECT_CACHE_DIR/seq"
typeset -g _EDIT_SELECT_PRIMARY_FILE="$_EDIT_SELECT_CACHE_DIR/primary"
typeset -g _EDIT_SELECT_PID_FILE="$_EDIT_SELECT_CACHE_DIR/agent.pid"

# Default key sequences (read-only).
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^V'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^X'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_COPY+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_COPY='^[[67;6u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_LEFT='^[[1;5D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT='^[[1;5C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT+x} ]]  && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT='^[[1;6D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT='^[[1;6C'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_START+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_START='^[[1;6H'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_END+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_END='^[[1;6F'

# Source user config and apply compiled-in defaults for any key not explicitly
# set. Defaults are declared read-only above so they cannot be overridden by
# the config file; user values shadow them via the :- operator.
function edit-select::apply-key-defaults() {
    EDIT_SELECT_INSTANT_CUT="${EDIT_SELECT_INSTANT_CUT:-0}"
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

function edit-select::load-config() {
    # || true: a failing config source (malformed hand-edit, transient read
    # error) must not abort this function under inherited err_return/err_exit —
    # the abort would skip apply-key-defaults and cascade out of the plugin
    # load.  The rc is unobserved; behaviour is unchanged under normal options.
    [[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null || true
    edit-select::apply-key-defaults
}

# Clear all in-flight selection state after a paste or cut operation.
# Clearing LAST_PRIMARY prevents the just-consumed selection from being
# re-detected on the next ZLE callback.  _zes_clear_primary instructs the
# agent to wipe the PRIMARY cache so a subsequent selection starts fresh.
function _zes_sync_after_paste() {
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_LAST_PRIMARY=""
    _zes_clear_primary
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

# Refine a single-line trimmer candidate: if it appears exactly once in BUFFER
# and stripping its boundary whitespace reveals >=2 occurrences, prefer the
# stripped form.  This prevents a boundary space (left by prompt-prefix or
# status-suffix trimming) from collapsing two identical tokens into one
# occurrence and bypassing cursor-based duplicate disambiguation.
# Sets REPLY; caller must have set BUFFER.
function _zes_refine_trim_candidate() {
    setopt localoptions extendedglob
    local cand="$1"
    # Occurrence counts use the C-level pattern-strip idiom (left-to-right,
    # non-overlapping matches) — identical counts to a per-character substring
    # walk, without the O(buffer^2) cost on large multibyte buffers.
    local -i clen=${#cand} cnt=0 idx=0
    local buf="$BUFFER"
    while [[ "$buf" == *"$cand"* ]]; do
        local prefix="${buf%%"$cand"*}"
        idx=$((idx + ${#prefix} + clen))
        # `|| true`: a bare `(( cnt++ ))` yields the PRE-increment value, so the
        # first iteration evaluates to 0 and the statement reports failure.  A
        # user with err_return/err_exit set would abort this function there —
        # on the common path, since the first hit always has cnt == 0.
        (( cnt++ )) || true
        # The only consumer is `(( cnt == 1 ))` below, so a second hit already
        # settles the answer — stop instead of counting the whole buffer.
        (( cnt > 1 )) && break
        buf="${BUFFER:$idx}"
    done
    if (( cnt == 1 )); then
        local stripped="${cand##[[:space:]]#}"
        stripped="${stripped%%[[:space:]]#}"
        local -i slen=${#stripped}
        if [[ -n "$stripped" && slen -lt clen ]]; then
            local -i cnt2=0
            idx=0
            buf="$BUFFER"
            while [[ "$buf" == *"$stripped"* ]]; do
                prefix="${buf%%"$stripped"*}"
                idx=$((idx + ${#prefix} + slen))
                # Same pre-increment rc caveat as the cnt loop above.
                (( cnt2++ )) || true
                # The only consumer is `(( cnt2 >= 2 ))` — stop at two.
                (( cnt2 >= 2 )) && break
                buf="${BUFFER:$idx}"
            done
            (( cnt2 >= 2 )) && { REPLY="$stripped"; return; }
        fi
    fi
    REPLY="$cand"
}

# Best trimmed-overlap matcher against BUFFER. Used to exclude prompt and
# terminal padding noise from mouse selections. Returns 0 with the matched
# substring in REPLY (X11/Wayland) or prints it to stdout (macOS, preserving
# the existing $() call-site contract).
function _zes_match_selection_in_buffer() {
    REPLY=""
    local source="$1"
    [[ -z "$source" ]] && return 1
    # Compute lengths once and reuse for the exact-match guard, reverse-
    # containment, and trim bounds.
    local -i source_len=${#source} buf_len=${#BUFFER} min_len=1
    (( buf_len == 0 )) && return 1

    # Length-guarded exact match: skip the BUFFER scan when source is longer
    # than BUFFER and therefore cannot fit (the prompt-including case).  ~10x
    # cheaper on that path.
    if (( source_len <= buf_len )) && [[ "$BUFFER" == *"$source"* ]]; then
        REPLY="$source"
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
        REPLY="$BUFFER"
        return 0
    fi

    # Interior-newline gate.  A source that still contains a newline after
    # dropping at most one trailing terminator is a decorated MULTILINE selection
    # with interior noise the end-trimmer cannot remove.  X11/Wayland WIRING:
    # return the resolver result directly — success (clean block) or fail closed.
    # The end/both trimmer never runs on a multiline source here (running it would
    # return partial, wrong text — a correct-or-nothing violation).
    if [[ "${source%$'\n'}" == *$'\n'* ]]; then
        _zes_resolve_multiline "$source"
        return $?
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
                return 0
            fi
        done
    fi
    return 1
}

# Determine whether a mouse text selection is currently active and populate
# _EDIT_SELECT_ACTIVE_SELECTION if so.  Returns 0 when a selection is active.
#
# State machine:
#   is_new_selection=1  A NEW_SELECTION_EVENT arrived; the selection is matched
#                       against BUFFER and recorded as ACTIVE if found.
#   PENDING_SELECTION   The selection text appears more than once in BUFFER;
#                       the cursor position will disambiguate which occurrence
#                       the user intends to modify.
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
            # ${var:+x} keeps the test itself O(1): the bare `[[ -z "$var" ]]`
            # form materialises the whole cached selection, which can be the
            # full raw scrollback drag when the matcher did not resolve it.
            [[ -z "${_EDIT_SELECT_LAST_PRIMARY:+x}" ]] && return 1
        fi
    else
        return 1
    fi

    if ((is_new_selection)); then
        if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            zle -M ""
            zle -R
        fi
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_ACTIVE_SELECTION=""
        # Prompt-aware match: resolve the raw platform selection (which may carry
        # a prompt prefix, a right-aligned status suffix, or decorated multiline
        # rows) down to the editable command text present in BUFFER.  On success
        # set BOTH ACTIVE and LAST_PRIMARY to the MATCHED editable text: the dedup
        # fast path at the top of this function compares LAST_PRIMARY ==
        # ACTIVE_SELECTION, so leaving LAST_PRIMARY holding the raw prompt-
        # including source would silently invalidate the still-valid active match
        # on the next non-event keypress.  Keep the raw source in the local
        # `mouse_sel` only; never write it to the cache.  Fail closed (no
        # PENDING_SELECTION) when unresolvable — the existing Linux behavior.
        if [[ -n "$mouse_sel" ]] && _zes_match_selection_in_buffer "$mouse_sel"; then
            _EDIT_SELECT_ACTIVE_SELECTION="$REPLY"
            _EDIT_SELECT_LAST_PRIMARY="$REPLY"
            return 0
        fi
        return 1
    fi

    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        local sel="$_EDIT_SELECT_PENDING_SELECTION" sel_len=${#_EDIT_SELECT_PENDING_SELECTION}
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
                    return 0
                fi
                # Occurrences are found left to right, so once one starts past
                # the cursor no later occurrence can contain it either — stop
                # scanning instead of walking the rest of the buffer.
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
    fi

    return 1
}

# Called by ZLE widgets before acting on a keypress.
# Reads the seq file's content via the fork-free $(<file) builtin to detect
# whether the agent has written a new PRIMARY selection since the last check.
# EVENT_FIRED_FOR_SEQ prevents the same seq value from triggering more than
# once: the first ZLE callback fires the selection event; subsequent callbacks
# at the same seq content suppress it until the next real agent write.
function _zes_sync_selection_state() {
    ((!_EDIT_SELECT_DAEMON_ACTIVE)) && return

    # Read the seq file's content via the fork-free, redirect-free $(<file)
    # builtin and compare as an opaque string.  The [[ -r ]] gate stands in for
    # stderr suppression (no 2>/dev/null fd cost on this hot path), the same
    # idiom the PID-file read already uses.  The agent writes "%lu\n" to seq on
    # every primary-selection change; content comparison is exact and catches
    # intra-second events that integer-second mtime would alias.
    local current_seq
    # Trailing `|| true`: the `[[ -r ]] &&` list only escapes err_return when the
    # TEST fails.  When the test passes and the read then fails — the daemon
    # unlinking seq between the two, the same TOCTOU the if-form read below
    # guards — the failing right-hand side aborts this function under a user's
    # inherited err_return, stranding LAST_SEQ and skipping the event handling.
    # A simple command (not a brace group) keeps the trailing guard effective in
    # every caller context, so this stays on the fd-cost-free guarded-bare form
    # (no 2>/dev/null on the hot path).  Byte-identical in every file state.
    [[ -r "$_EDIT_SELECT_SEQ_FILE" ]] && current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
    [[ -z "$current_seq" ]] && return

    if [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
        # New seq: agent wrote a new primary value.  Read and record it.
        _EDIT_SELECT_LAST_SEQ="$current_seq"
        _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=0
        # The $(<primary) read stays in the brace-group form: it runs only on
        # this rare change-detected path (not every redraw), and the brace group
        # always declares new_primary (empty on failure) so the assignment below
        # is safe even under a user's `setopt nounset`.
        { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null
        _EDIT_SELECT_LAST_PRIMARY="$new_primary"

        if [[ -n "$new_primary" ]]; then
            _EDIT_SELECT_NEW_SELECTION_EVENT=1
            _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
        else
            # Empty primary: selection was cleared (e.g. after paste).
            # Clear the "Duplicate text" prompt too when one is showing.  Every
            # other `zle -M ""` site is gated on PENDING_SELECTION being
            # non-empty, and blanking PENDING below removes that gate — so
            # without this the message would stay on screen with no code path
            # left able to clear it.  The guard keeps this free on the hot path
            # (PENDING is empty on all ordinary keystrokes) and makes sure we
            # never blank a message this plugin does not own.  Same shape as
            # _zes_clear_mouse_selection_prompt_state; mirrors the shipped
            # macOS `_zes_clear_duplicate_prompt` call in the same branch.
            if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
                zle -M ""
                zle -R
            fi
            _EDIT_SELECT_ACTIVE_SELECTION=""
            _EDIT_SELECT_PENDING_SELECTION=""
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
        fi
    else
        if ((_EDIT_SELECT_EVENT_FIRED_FOR_SEQ)); then
            # Same seq: event already fired; suppress until next agent write.
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
            fi
        fi
    fi
}

# Remove the active mouse selection from BUFFER at the occurrence closest to
# CURSOR.  If the text appears exactly once it is deleted unconditionally.
# If it appears multiple times, the occurrence that contains CURSOR is deleted;
# if no occurrence contains the cursor, PENDING_SELECTION is set and the user
# is prompted to position the cursor inside their intended occurrence.
function _zes_delete_mouse_selection() {
    [[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1

    local sel="$_EDIT_SELECT_ACTIVE_SELECTION" sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
    ((sel_len > ${#BUFFER})) && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
        return 1
    }
    [[ "$BUFFER" != *"$sel"* ]] && {
        _EDIT_SELECT_ACTIVE_SELECTION=""
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
        _EDIT_SELECT_ACTIVE_SELECTION=""
        _EDIT_SELECT_PENDING_SELECTION=""
        _EDIT_SELECT_LAST_PRIMARY=""
        _zes_clear_primary
        return 0
    fi

    zle -M "Duplicate text: place cursor inside the occurrence you want to modify"
    _EDIT_SELECT_PENDING_SELECTION="$_EDIT_SELECT_ACTIVE_SELECTION"
    _EDIT_SELECT_ACTIVE_SELECTION=""
    return 1
}

# Clear transient mouse-selection prompt/state when keyboard selection takes
# over.  This stays inside ZLE state and does not touch the X PRIMARY.
function _zes_clear_mouse_selection_prompt_state() {
    if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
        zle -M ""
        zle -R
    fi
    _EDIT_SELECT_ACTIVE_SELECTION=""
    _EDIT_SELECT_PENDING_SELECTION=""
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
}

# Select the entire command-line buffer and activate the edit-select keymap.
function edit-select::select-all() {
    _zes_clear_mouse_selection_prompt_state
    MARK=0
    CURSOR=${#BUFFER}
    REGION_ACTIVE=1
    zle -K edit-select
}
# Register select-all as a ZLE widget.
zle -N edit-select::select-all

# Kill the active ZLE region and return to the main keymap.
function _zes_delete_selected_region() {
    zle kill-region -w
    zle -K main
}
# Register kill-region widget backed by _zes_delete_selected_region.
zle -N edit-select::kill-region _zes_delete_selected_region

# Backspace handler: delete mouse selection if active, else backward-delete-char.
function edit-select::delete-mouse-or-backspace() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle backward-delete-char -w
}
# Register as ZLE widget for binding to Backspace.
zle -N edit-select::delete-mouse-or-backspace

# Delete-key handler: delete mouse selection if active, else delete-char.
function edit-select::delete-mouse-or-delete() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
            return
        elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
            return
        fi
    fi
    zle delete-char -w
}
# Register as ZLE widget for binding to Delete.
zle -N edit-select::delete-mouse-or-delete

# Self-insert override: delete active mouse selection then insert the typed
# character (type-to-replace).  Blocks input during pending disambiguation.
function edit-select::handle-char() {
    # Dismiss any active completion menu before processing the keypress.
    zle -c
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        _zes_sync_selection_state

        if _zes_detect_mouse_selection; then
            if _zes_delete_mouse_selection; then
                zle self-insert -w
                return
            fi
            # Block typing on failure (e.g. disambiguation pending).
            return
        fi
    fi
    zle self-insert -w
}
# Register as ZLE widget; bound to printable chars in emacs keymap.
zle -N edit-select::handle-char

# Deactivate the ZLE region, return to main keymap, and replay the
# triggering keystrokes.
function _zes_cancel_region_and_replay_keys() {
    zle deactivate-region -w
    zle -K main
    zle -U -- "$KEYS"
}
# Register deselect-and-input as default handler in edit-select keymap.
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

# If a keyboard region is selected, delete it and insert the typed char;
# else self-insert.
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
# Register as ZLE widget; bound to printable chars in edit-select keymap.
zle -N edit-select::replace-selection

# Copy the active keyboard region (or PRIMARY selection) to the system
# clipboard, then deselect.
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
# Register copy-region as a ZLE widget (Ctrl+Shift+C).
zle -N edit-select::copy-region

# Copy the active keyboard/mouse selection to clipboard and delete it.
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
            _zes_copy_to_clipboard "$sel" && _zes_delete_mouse_selection
        fi
    fi
}
# Register cut-region as a ZLE widget (Ctrl+X).
zle -N edit-select::cut-region

# Paste system clipboard into BUFFER; replaces active selection first if present.
function edit-select::paste-clipboard() {
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
            _zes_delete_mouse_selection || return
        fi
    fi
    local clipboard_content
    clipboard_content=$(_zes_get_clipboard) || return
    [[ -n "$clipboard_content" ]] && LBUFFER="${LBUFFER}${clipboard_content}"
    _zes_sync_after_paste
}
# Register paste-clipboard as a ZLE widget (Ctrl+V).
zle -N edit-select::paste-clipboard

# Handle bracketed-paste: replace active selection then insert pasted text.
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
            _zes_delete_mouse_selection || return
        fi
    fi
    # Invoke the built-in .bracketed-paste (dot-prefix bypasses user overrides).
    zle .bracketed-paste
    _zes_sync_after_paste
}
# Register bracketed-paste-replace as a ZLE widget.
zle -N edit-select::bracketed-paste-replace

# Lightweight movement widgets: move cursor to absolute buffer boundaries.
# Used by nav_bind so that _zes_activate_region_and_dispatch can dispatch
# them by name, the same way it dispatches built-in widgets like
# beginning-of-line or forward-word.
function _zes_beginning_of_buffer() { CURSOR=0 }
zle -N beginning-of-buffer _zes_beginning_of_buffer

function _zes_end_of_buffer() { CURSOR=${#BUFFER} }
zle -N end-of-buffer _zes_end_of_buffer

# Wrapper for shift-arrow navigation: start a selection if none, switch to
# edit-select keymap, dispatch the cursor-movement widget.
function _zes_activate_region_and_dispatch() {
    # Dismiss any active completion menu before starting selection.
    zle -c
    _zes_clear_mouse_selection_prompt_state
    if ((!REGION_ACTIVE)); then
        zle set-mark-command -w
        zle -K edit-select
    fi
    zle "${WIDGET#edit-select::}" -w
}

# Terminal focus-in handler: when this pane gains focus, snapshot the seq-file
# content as "already seen" so that selection events from other panes are
# not mistakenly treated as new.  Requires the terminal (or tmux with
# `focus-events on`) to send CSI I / CSI O focus sequences.  Terminals
# that do not support DECSET 1004 silently ignore the enable request and
# these widgets simply never fire — no regression in that case.
function _zes_terminal_focus_in() {
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        local current_seq
        # || true: the read's status is unobserved, and unlike the pre-redraw
        # and widget-sync reads nothing after it re-derives state from the
        # filesystem — the two state clears below are the whole point of this
        # widget.  If a dying daemon unlinks seq between DAEMON_ACTIVE being 1
        # and this read, an inherited err_return/err_exit would abort before
        # them and leave a stale ACTIVE_SELECTION alive across the pane switch.
        { current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true } 2>/dev/null
        if [[ -n "$current_seq" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"
            _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
        fi
    fi
    _EDIT_SELECT_NEW_SELECTION_EVENT=0
    _EDIT_SELECT_ACTIVE_SELECTION=""
}
zle -N _zes_terminal_focus_in

# Terminal focus-out handler: no-op widget that consumes the CSI O
# escape sequence so it is not interpreted as keystrokes.
function _zes_terminal_focus_out() { : }
zle -N _zes_terminal_focus_out

# ── WezTerm click-to-deselect handler ─────────────────────────────────────
# WezTerm sends \e[>62300u via pane:send_text() on mouse-Down when it has
# an active selection.  This widget clears the stale NEW_SELECTION_EVENT
# before the user types, preventing phantom deletion of the old selection.
# Unlike _zes_terminal_focus_in, this does NOT touch EVENT_FIRED_FOR_SEQ
# so a subsequent drag will still be processed normally by zle-line-pre-redraw.
function _zes_wezterm_mousedown_clear() {
    # A mouse-Down in WezTerm cancels any in-flight disambiguation; clear the
    # "Duplicate text" prompt too (matches macOS item 60), not just the state.
    # _zes_clear_mouse_selection_prompt_state does not touch EVENT_FIRED_FOR_SEQ,
    # so a subsequent drag is still processed normally by zle-line-pre-redraw.
    _zes_clear_mouse_selection_prompt_state
}
zle -N _zes_wezterm_mousedown_clear
bindkey -M emacs '\e[>62300u' _zes_wezterm_mousedown_clear
bindkey '\e[>62300u' _zes_wezterm_mousedown_clear

# ZLE hook: called before every prompt redraw.  Must be fast — no forks.
# Detects PRIMARY selection changes via the seq file's content.
# Daemon liveness is checked at most once every 30 s to avoid a kill -0 on
# every keypress; if the agent has died it is restarted automatically.
function edit-select::zle-line-pre-redraw() {
    ((!EDIT_SELECT_MOUSE_REPLACEMENT)) && return

    # Fast path: daemon is running, use content-based change detection
    if ((_EDIT_SELECT_DAEMON_ACTIVE)); then
        # Liveness probe: at most once every 30 s to amortise syscall overhead.
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

        # Read seq content via the fork-free, redirect-free $(<file) builtin.
        # The [[ -r ]] gate doubles as the daemon-liveness check: an unreadable
        # seq means the daemon is gone, so we drop DAEMON_ACTIVE and bail —
        # exactly the former `zstat || { DAEMON_ACTIVE=0; return; }` behaviour.
        local current_seq
        # `|| true` on the read: the [[ -r ]] test and the read are not atomic,
        # so a daemon that unlinks seq in between leaves a failing command
        # substitution.  `local` is on a prior line, so it cannot mask that rc,
        # and this hook's status IS observed (zsh-syntax-highlighting wraps
        # widgets as `builtin zle "$@" && _zsh_highlight`) — under inherited
        # err_return the whole hook aborted, stranding LAST_SEQ and skipping the
        # highlight for that redraw.  An empty current_seq then flows into the
        # existing != comparison exactly as it does without err_return.
        if [[ -r "$_EDIT_SELECT_SEQ_FILE" ]]; then
            current_seq=$(<"$_EDIT_SELECT_SEQ_FILE") || true
        else
            _EDIT_SELECT_DAEMON_ACTIVE=0
            return
        fi

        # New seq content: agent wrote a selection change.  Read the primary and signal it.
        if [[ "$current_seq" != "$_EDIT_SELECT_LAST_SEQ" ]]; then
            _EDIT_SELECT_LAST_SEQ="$current_seq"
            { local new_primary=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null
            _EDIT_SELECT_LAST_PRIMARY="$new_primary"
            if [[ -n "$new_primary" ]]; then
                # Signal the event but leave EVENT_FIRED_FOR_SEQ alone.  Clearing the
                # latch here re-arms an already-consumed selection: a click that clears
                # the selection emits cursor-movement keys (one redraw each) but no agent
                # event, so this branch cannot distinguish "still selected" from "cleared
                # by that click" — the cache and every state flag are identical.  Leaving
                # the latch set lets the widget sync suppress the stale event, which is
                # what keeps a visually-cleared selection from being deleted or replaced
                # on the next keypress (invariants 3, 4, 6, 7).
                _EDIT_SELECT_NEW_SELECTION_EVENT=1
            else
                # Empty primary: the selection was cleared (click-deselect, paste, or an
                # external clear).  Drop any stale ACTIVE so a later keypress cannot delete
                # text that is no longer selected (phantom deletion).  Matches the widget
                # sync (_zes_sync_selection_state) and the Wayland/macOS pre-redraw hooks.
                # Clear the "Duplicate text" prompt in the same breath when one is
                # showing: blanking PENDING below removes the gate every other
                # `zle -M ""` site tests, so the message would otherwise stay on
                # screen with nothing left able to clear it.  Guarded, so ordinary
                # keystrokes (PENDING empty) pay nothing and a message this plugin
                # does not own is never blanked — the shipped macOS pre-redraw does
                # exactly this via `_zes_clear_duplicate_prompt`.
                if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
                    zle -M ""
                    zle -R
                fi
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
                _EDIT_SELECT_NEW_SELECTION_EVENT=0
            fi
        else
            # Same seq: no new agent write.  Clear any active selection so
            # stale highlights don't persist across multiple keystrokes.
            _EDIT_SELECT_NEW_SELECTION_EVENT=0
            if [[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]]; then
                _EDIT_SELECT_ACTIVE_SELECTION=""
                _EDIT_SELECT_PENDING_SELECTION=""
            fi
        fi
        return
    fi
}

# Re-enable DECSET 1004 on every new prompt so focus events are captured
# by the bound ZLE widgets.  Persistent (not one-shot) because
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

# Apply keybindings and ZLE hook registration to reflect the current value of
# EDIT_SELECT_MOUSE_REPLACEMENT.  Called once at startup and again when the
# configuration wizard changes the setting.  When the feature is disabled,
# all custom bindings are reverted to their ZLE defaults.
function edit-select::apply-mouse-replacement-config() {
    autoload -Uz add-zle-hook-widget
    if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
        bindkey -M emacs '\e[>62300u' _zes_wezterm_mousedown_clear
        bindkey '\e[>62300u' _zes_wezterm_mousedown_clear
        bindkey -M emacs -R ' '-'~' edit-select::handle-char
        bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
        bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" edit-select::delete-mouse-or-delete
        bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
        if [[ -n "$EDIT_SELECT_KEY_PASTE" ]]; then
            bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
            bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
        fi
        _zes_start_monitor || true
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
        add-zle-hook-widget -d line-pre-redraw edit-select::zle-line-pre-redraw 2>/dev/null
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
        _EDIT_SELECT_PENDING_SELECTION=""
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
        local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard-x11.zsh"
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
        print "edit-select - Text selection and clipboard management for Zsh"
        print "\nUsage: edit-select <subcommand>"
        print "\nSubcommands:"
        print "  conf, config    Launch interactive configuration wizard"
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

# Load the X11-specific clipboard backend (agent start/stop,
# get/set primary/clipboard).
source "$_EDIT_SELECT_PLUGIN_DIR/backends/x11/x11.zsh"

# Read user config and populate all dynamic key bindings (loads exactly once)
edit-select::load-config

# Establish the edit-select keymap and all related bindings inside an anonymous
# function so that the local loop variables do not pollute the global scope.
# nav_bind entries are triples: terminfo-key, fallback-escape, widget-name.
# terminfo is preferred so the correct sequences are used for each terminal;
# the hardcoded fallback handles terminals that do not report via terminfo.
# NOTE: Requires edit-select::load-config to have run first.
function { emulate -L zsh
    # Create a new "edit-select" keymap for active-selection mode.
    bindkey -N edit-select
    # Default: any control character deselects and replays into main keymap.
    bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
    # Any printable character replaces the current selection.
    bindkey -M edit-select -R ' '-'~' edit-select::replace-selection

    local -a nav_bind=(
        'kLFT' '^[[1;2D' 'backward-char'
        'kRIT' '^[[1;2C' 'forward-char'
        'kri' '^[[1;2A' 'up-line'
        'kind' '^[[1;2B' 'down-line'
        'kHOM' '^[[1;2H' 'beginning-of-line'
        'kEND' '^[[1;2F' 'end-of-line'
        # Ctrl+Shift modified keys for extended selection.
        # Ctrl+Shift+Home / End  → beginning / end-of-buffer
        # Ctrl+Shift+Left / Right  → backward / forward-word
        '' "$EDIT_SELECT_KEY_BUFFER_START" 'beginning-of-buffer'
        '' "$EDIT_SELECT_KEY_BUFFER_END" 'end-of-buffer'
        '' "$EDIT_SELECT_KEY_SEL_WORD_LEFT" 'backward-word'
        '' "$EDIT_SELECT_KEY_SEL_WORD_RIGHT" 'forward-word'
    )

    local i ti esc wid seq
    for ((i = 1; i <= ${#nav_bind}; i += 3)); do
        ti=${nav_bind[i]}
        esc=${nav_bind[i + 1]}
        wid=${nav_bind[i + 2]}
        [[ -z "$esc" ]] && continue
        seq=${terminfo[$ti]:-$esc}
        zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
        bindkey -M emacs "$seq" "edit-select::${wid}"
        bindkey -M edit-select "$seq" "edit-select::${wid}"
    done

    local -a dest_bind=(
        'kdch1' '^[[3~' 'edit-select::kill-region'
        'bs' '^?' 'edit-select::kill-region'
    )
    for ((i = 1; i <= ${#dest_bind}; i += 3)); do
        seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i + 1]}}
        bindkey -M edit-select "$seq" "${dest_bind[i + 2]}"
    done

    # Dynamic keybindings based on configuration
    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    [[ -n "$EDIT_SELECT_KEY_CUT" ]] && bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    bindkey -M edit-select '^[[200~' edit-select::bracketed-paste-replace

    [[ -n "$EDIT_SELECT_KEY_SELECT_ALL" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
    [[ -n "$EDIT_SELECT_KEY_COPY" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
    if [[ -n "$EDIT_SELECT_KEY_CUT" ]]; then
        if ((EDIT_SELECT_INSTANT_CUT)); then
            bindkey -M emacs -rp "$EDIT_SELECT_KEY_CUT" 2>/dev/null
            bindkey -rp "$EDIT_SELECT_KEY_CUT" 2>/dev/null
        fi
        bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
        bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
    fi

    [[ -n "$EDIT_SELECT_KEY_WORD_LEFT" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_LEFT" backward-word
    [[ -n "$EDIT_SELECT_KEY_WORD_RIGHT" ]] && bindkey -M emacs "$EDIT_SELECT_KEY_WORD_RIGHT" forward-word

    # Home / End → move to line start / end (plain navigation, no selection).
    # Provide broad defaults covering normal, application, and rxvt/xterm modes.
    local _zes_k
    for _zes_k in "${terminfo[khome]:-^[[H}" '^[[H' '^[OH' '^[[1~' '^[[7~'; do
        bindkey -M emacs "$_zes_k" beginning-of-line
    done
    for _zes_k in "${terminfo[kend]:-^[[F}" '^[[F' '^[OF' '^[[4~' '^[[8~'; do
        bindkey -M emacs "$_zes_k" end-of-line
    done

    # Terminal focus events in edit-select keymap — suppress stale
    # cross-pane selection events.
    bindkey -M edit-select '\e[I' _zes_terminal_focus_in
    bindkey -M edit-select '\e[O' _zes_terminal_focus_out
}

# Apply user-configured or default undo/redo keybindings in both
# emacs and main keymaps.
if [[ -n "$EDIT_SELECT_KEY_UNDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
    bindkey "$EDIT_SELECT_KEY_UNDO" undo
fi
if [[ -n "$EDIT_SELECT_KEY_REDO" ]]; then
    bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
    bindkey "$EDIT_SELECT_KEY_REDO" redo
fi

# ── macOS SSH key remapping ──────────────────────────────────────────
# When SSH mode is active, also bind macOS Cmd/Option CSI-u sequences
# to the Linux widgets. This allows macOS terminal users (iTerm2,
# Ghostty, Kitty, WezTerm) to SSH into this Linux box and have their
# Cmd+C, Cmd+X, Option+Arrow, etc. work transparently — provided
# the terminal is configured to forward Cmd sequences as CSI-u.
# These are additive bindings — they do not overwrite any existing keys.
# The ((_ZES_SSH_MODE)) guard ensures zero overhead on non-SSH sessions.
if ((_ZES_SSH_MODE)); then
    # Clipboard operations (Cmd = modifier 9 in CSI-u)
    bindkey -M emacs       '^[[99;9u'  edit-select::copy-region     # Cmd+C
    bindkey -M edit-select '^[[99;9u'  edit-select::copy-region
    bindkey -M emacs       '^[[120;9u' edit-select::cut-region      # Cmd+X
    bindkey -M edit-select '^[[120;9u' edit-select::cut-region
    bindkey -M emacs       '^[[97;9u'  edit-select::select-all      # Cmd+A
    bindkey -M edit-select '^[[97;9u'  edit-select::select-all
    # Undo/Redo (Cmd+Z = modifier 9, Cmd+Shift+Z = modifier 10)
    bindkey -M emacs       '^[[122;9u'  undo                        # Cmd+Z
    bindkey                '^[[122;9u'  undo
    bindkey -M emacs       '^[[122;10u' redo                        # Cmd+Shift+Z
    bindkey                '^[[122;10u' redo
    # Line / buffer navigation (Cmd = modifier 9)
    bindkey -M emacs       '^[[1;9D' beginning-of-line              # Cmd+Left
    bindkey -M emacs       '^[[1;9C' end-of-line                    # Cmd+Right
    bindkey -M emacs       '^[[1;9A' beginning-of-buffer-or-history # Cmd+Up
    bindkey -M emacs       '^[[1;9B' end-of-buffer-or-history       # Cmd+Down
    # Word navigation (Option = modifier 3)
    bindkey -M emacs       '^[[1;3D' backward-word                  # Option+Left
    bindkey -M emacs       '^[[1;3C' forward-word                   # Option+Right
    # Line / buffer selection (Cmd+Shift = modifier 10)
    bindkey -M emacs       '^[[1;10D' edit-select::beginning-of-line   # Cmd+Shift+Left
    bindkey -M edit-select '^[[1;10D' edit-select::beginning-of-line
    bindkey -M emacs       '^[[1;10C' edit-select::end-of-line         # Cmd+Shift+Right
    bindkey -M edit-select '^[[1;10C' edit-select::end-of-line
    bindkey -M emacs       '^[[1;10A' edit-select::beginning-of-buffer # Cmd+Shift+Up
    bindkey -M edit-select '^[[1;10A' edit-select::beginning-of-buffer
    bindkey -M emacs       '^[[1;10B' edit-select::end-of-buffer       # Cmd+Shift+Down
    bindkey -M edit-select '^[[1;10B' edit-select::end-of-buffer
    # Word selection (Option+Shift = modifier 4)
    bindkey -M emacs       '^[[1;4D' edit-select::backward-word     # Option+Shift+Left
    bindkey -M edit-select '^[[1;4D' edit-select::backward-word
    bindkey -M emacs       '^[[1;4C' edit-select::forward-word      # Option+Shift+Right
    bindkey -M edit-select '^[[1;4C' edit-select::forward-word
fi

# Normalise any residual string value that may still be in the live env.
case $EDIT_SELECT_MOUSE_REPLACEMENT in
enabled | 1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
disabled | 0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

# Pre-populate LAST_PRIMARY and LAST_SEQ before the first ZLE callback fires
# so the initial redraw does not see a spurious empty-to-non-empty transition.
if ((EDIT_SELECT_MOUSE_REPLACEMENT)); then
    _zes_start_monitor || true
    if ((_EDIT_SELECT_DAEMON_ACTIVE)) && [[ -f "$_EDIT_SELECT_PRIMARY_FILE" ]]; then
        { _EDIT_SELECT_LAST_PRIMARY=$(<"$_EDIT_SELECT_PRIMARY_FILE") } 2>/dev/null || true
        { _EDIT_SELECT_LAST_SEQ=$(<"$_EDIT_SELECT_SEQ_FILE") } 2>/dev/null || true
        _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1
    fi
fi

# Activate or deactivate mouse-replacement bindings based on the final
# normalised setting.
edit-select::apply-mouse-replacement-config
