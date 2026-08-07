#!/usr/bin/env zsh
# Unit + differential tests for the prompt-aware mouse-selection matcher.
#
# Covers:
#   - Single-line trimmer equivalence vs the nested-loop reference oracle
#   - Ordered-budget invariance (budget is a pure performance knob)
#   - Reverse-containment fast path soundness (`S - B <= max_trim`, `B < S`)
#   - Multiline whole-line resolution correctness (fail-closed fixtures)
#
# The matcher under test is a standalone copy of the X11/Wayland inlined body
# (REPLY convention). It is verified byte-identical in behavior to the copies
# inlined in the platform plugin files; this test file exists so the algorithm
# can be exercised without sourcing a full platform plugin (which starts agents,
# probes the display server, etc.). Run: zsh assets/tests/test-prompt-aware-matcher.zsh
#
# By default runs the fast fixture suite. Pass --full for the exhaustive
# differential sweeps (several minutes).

emulate -L zsh
setopt no_unset

# REPLY is the matcher's intentional return channel;
# pre-declare it global so the assignments inside the matcher are clean under any option set.
typeset -g REPLY=""
typeset -gi FAILS=0 CHECKS=0

_check() {
    # _check <desc> <expected-rc> <expected-reply> <actual-rc> <actual-reply>
    (( CHECKS++ ))
    if [[ "$2" != "$4" || "$3" != "$5" ]]; then
        (( FAILS++ ))
        print -r -- "FAIL [$1]: expected ($2,[$3]) got ($4,[$5])"
    fi
}

# ── Reference nested-loop matcher (the pre-feature macOS oracle), REPLY out ──
typeset -gi REF_MAX_TRIM=512
ref_match() {
    REPLY=""
    local source="$1"
    [[ -z "$source" ]] && return 1
    (( ${#BUFFER} == 0 )) && return 1
    if [[ "$BUFFER" == *"$source"* ]]; then
        REPLY="$source"; return 0
    fi
    local source_len=${#source} buf_len=${#BUFFER} min_len=1
    local max_trim=$REF_MAX_TRIM min_total_trim=0
    (( max_trim > source_len - min_len )) && max_trim=$((source_len - min_len))
    (( max_trim < 0 )) && return 1
    (( source_len > buf_len )) && min_total_trim=$((source_len - buf_len))
    (( min_total_trim > (2 * max_trim) )) && return 1
    local best="" candidate
    local -i best_len=0 left right len total_trim
    for ((left = 0; left <= max_trim; left++)); do
        for ((right = 0; right <= max_trim; right++)); do
            total_trim=$((left + right))
            (( total_trim < min_total_trim )) && continue
            len=$((source_len - left - right))
            ((len <= best_len || len < min_len)) && break
            candidate="${source:$left:$len}"
            if [[ "$BUFFER" == *"$candidate"* ]]; then
                best="$candidate"; best_len=$len
                ((best_len == source_len || best_len == buf_len)) && { REPLY="$best"; return 0; }
            fi
        done
    done
    [[ -n "$best" ]] || return 1
    REPLY="$best"; return 0
}

# ── Candidate matcher: standalone copy of the X11/Wayland inlined body ──
typeset -gi TEST_MAX_TRIM=512 TEST_ORDERED_BUDGET=256
_zes_test_any_match_at() {
    local -i t=$1 left_min left_max len left
    left_min=$(( t - _mt > 0 ? t - _mt : 0 ))
    left_max=$(( _mt < t ? _mt : t ))
    len=$(( _S - t ))
    (( len < 1 )) && return 1
    (( len > _B )) && return 1
    for (( left = left_min; left <= left_max; left++ )); do
        [[ "$BUFFER" == *"${_src:$left:$len}"* ]] && return 0
    done
    return 1
}
_zes_test_resolve_multiline() {
    local src="${1%$'\n'}"
    local -a _sl _bl
    _sl=("${(@f)src}")
    _bl=("${(@f)BUFFER}")
    local -i m=${#_sl} n=${#_bl} i k aligned
    (( m < 2 || m > n )) && return 1
    local matched_content content
    local -i have=0
    # Phase 1: forward containment (whole buffer row inside decorated source row).
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
            return 1
        fi
    done
    if (( have )); then REPLY="$matched_content"; return 0; fi
    # Phase 2: partial-first-line (only when phase 1 found nothing). Source row 1 =
    # <tail-of-buffer-row-1><status suffix>; find the longest prefix of _sl[1] that
    # is a suffix of _bl[i], rows 2..m require exact equality.
    local row1_content
    for (( i = 1; i <= n - m + 1; i++ )); do
        local -i sl1len=${#_sl[1]} bl1len=${#_bl[i]}
        local -i maxk=$(( sl1len < bl1len ? sl1len : bl1len ))
        local -i found=0
        for (( k = maxk; k >= 1; k-- )); do
            if [[ "${_bl[i]}" == *"${_sl[1]:0:$k}" ]]; then
                row1_content="${_sl[1]:0:$k}"; found=1; break
            fi
        done
        (( found )) || continue
        aligned=1
        for (( k = 2; k <= m; k++ )); do
            [[ "${_sl[k]}" != "${_bl[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
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
        aligned=1
        for (( k = 2; k <= m - 1; k++ )); do
            [[ "${_sl[k]}" != "${_bl[i + k - 1]}" ]] && { aligned=0; break; }
        done
        (( aligned )) || continue
        local lastrow="${_bl[i+m-1]}"
        [[ -n "${_sl[m]}" && ${#_sl[m]} -lt ${#lastrow} && "$lastrow" == "${_sl[m]}"* ]] || continue
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
# Standalone copy of the plugin's _zes_refine_trim_candidate (byte-identical
# body). Kept here so the suite exercises the boundary-whitespace refinement
# that the ordered-scan and binary-search match sites now apply.
_zes_test_refine_trim_candidate() {
    setopt localoptions extendedglob
    local cand="$1"
    local -i blen=${#BUFFER} clen=${#cand} cnt=0 idx=0
    while (( idx <= blen - clen )); do
        if [[ "${BUFFER:$idx:$clen}" == "$cand" ]]; then (( cnt++ )); (( idx += clen ))
        else (( idx++ )); fi
    done
    if (( cnt == 1 )); then
        local stripped="${cand##[[:space:]]#}"
        stripped="${stripped%%[[:space:]]#}"
        local -i slen=${#stripped}
        if [[ -n "$stripped" && slen -lt clen ]]; then
            local -i cnt2=0 idx2=0
            while (( idx2 <= blen - slen )); do
                if [[ "${BUFFER:$idx2:$slen}" == "$stripped" ]]; then (( cnt2++ )); (( idx2 += slen ))
                else (( idx2++ )); fi
            done
            (( cnt2 >= 2 )) && { REPLY="$stripped"; return; }
        fi
    fi
    REPLY="$cand"
}
cand_match() {
    REPLY=""
    local _src="$1"
    [[ -z "$_src" ]] && return 1
    local -i _S=${#_src} _B=${#BUFFER}
    (( _B == 0 )) && return 1
    if (( _S <= _B )) && [[ "$BUFFER" == *"$_src"* ]]; then
        REPLY="$_src"; return 0
    fi
    local -i _mt=$TEST_MAX_TRIM
    (( _mt > _S - 1 )) && _mt=$(( _S - 1 ))
    (( _mt < 0 )) && return 1
    if (( _B < _S && _S - _B <= _mt )) && [[ "$_src" == *"$BUFFER"* ]]; then
        REPLY="$BUFFER"; return 0
    fi
    if [[ "${_src%$'\n'}" == *$'\n'* ]]; then
        _zes_test_resolve_multiline "$_src"
        return $?
    fi
    local -i min_total=0
    (( _S > _B )) && min_total=$(( _S - _B ))
    local -i max_total=$(( 2 * _mt ))
    (( max_total > _S - 1 )) && max_total=$(( _S - 1 ))
    (( min_total > max_total )) && return 1
    local -i t=$min_total
    (( _S - _B <= _mt )) && t+=1
    local -i checks_used=0 cc left_min left_max len left
    while (( t <= max_total )); do
        left_min=$(( t - _mt > 0 ? t - _mt : 0 ))
        left_max=$(( _mt < t ? _mt : t ))
        cc=$(( left_min > left_max ? 0 : left_max - left_min + 1 ))
        (( checks_used > 0 && checks_used + cc > TEST_ORDERED_BUDGET )) && break
        len=$(( _S - t ))
        if (( len >= 1 && len <= _B )); then
            for (( left = left_min; left <= left_max; left++ )); do
                if [[ "$BUFFER" == *"${_src:$left:$len}"* ]]; then
                    _zes_test_refine_trim_candidate "${_src:$left:$len}"; return 0
                fi
            done
        fi
        checks_used=$(( checks_used + cc ))
        t+=1
    done
    local -i lo=$t hi=$max_total mid
    (( lo > hi )) && return 1
    _zes_test_any_match_at $hi || return 1
    while (( lo < hi )); do
        mid=$(( (lo + hi) / 2 ))
        if _zes_test_any_match_at $mid; then hi=$mid; else lo=$(( mid + 1 )); fi
    done
    left_min=$(( lo - _mt > 0 ? lo - _mt : 0 ))
    left_max=$(( _mt < lo ? _mt : lo ))
    len=$(( _S - lo ))
    if (( len >= 1 && len <= _B )); then
        for (( left = left_min; left <= left_max; left++ )); do
            if [[ "$BUFFER" == *"${_src:$left:$len}"* ]]; then
                _zes_test_refine_trim_candidate "${_src:$left:$len}"; return 0
            fi
        done
    fi
    return 1
}

# ─────────────────────── Fixture suite (fast) ───────────────────────
print -r -- "== fixture suite =="

# Empty source / empty buffer.
BUFFER="echo hello"; cand_match "";        _check "empty source"  1 "" $? "$REPLY"
BUFFER="";           cand_match "echo";     _check "empty buffer"  1 "" $? "$REPLY"

# Exact match returns source.
BUFFER="echo hello"; cand_match "echo hello"; _check "exact" 0 "echo hello" $? "$REPLY"
BUFFER="echo hello"; cand_match "hello";      _check "exact substr" 0 "hello" $? "$REPLY"

# Prefix prompt trim.
BUFFER="git status"; cand_match "~/dir git status"; _check "prefix trim" 0 "git status" $? "$REPLY"
# Suffix padding trim.
BUFFER="git status"; cand_match "git status   ok"; _check "suffix trim" 0 "git status" $? "$REPLY"
# Prefix + suffix trim.
BUFFER="git status"; cand_match "% git status ✓"; _check "both trim" 0 "git status" $? "$REPLY"

# No match fails.
BUFFER="echo hello"; cand_match "xyz"; _check "no match" 1 "" $? "$REPLY"
# Prompt-only text with zero character overlap fails.
BUFFER="echo hello"; cand_match "XYZ#@"; _check "prompt only" 1 "" $? "$REPLY"

# Reverse-containment whole-line (headline P10k case).
BUFFER="git commit"; cand_match "  ~  git commit                    ✔"; \
    _check "reverse-containment" 0 "git commit" $? "$REPLY"

# Tie case: smallest-left among equal-length. BUFFER contains "ab" once; source
# has two length-2 windows "ab" (left=1) — first-left wins.
BUFFER="ab"; cand_match "xabx"; _check "tie smallest-left" 0 "ab" $? "$REPLY"

# Multiline exact.
BUFFER=$'line1\nline2\nline3'; cand_match $'line1\nline2\nline3'; \
    _check "multiline exact" 0 $'line1\nline2\nline3' $? "$REPLY"

# Decorated multiline whole-line: interior status on row 1.
BUFFER=$'line1\nline2\nline3'
cand_match $'  ~  line1        \xe2\x9c\x94\nline2\nline3'; \
    _check "decorated 3row" 0 $'line1\nline2\nline3' $? "$REPLY"
cand_match $'  ~  line1        \xe2\x9c\x94\nline2\nline3\n'; \
    _check "decorated 3row+nl" 0 $'line1\nline2\nline3' $? "$REPLY"

# Left-prompt-only multiline resolves via reverse-containment.
BUFFER=$'line1\nline2\nline3'; cand_match $'  ~  line1\nline2\nline3'; \
    _check "left-prompt multiline" 0 $'line1\nline2\nline3' $? "$REPLY"

# Single-line drag ending in a trailing newline routes to the trimmer (NOT the
# resolver, which would fail closed). Regression guard for the interior gate.
BUFFER="echo hello"; cand_match $'~/dir echo hel\n'; \
    _check "single-line trailing-nl" 0 "echo hel" $? "$REPLY"

# Fail-closed multiline fixtures.
BUFFER=$'line1\nline2\nline3'
cand_match $'  ~  line1  \xe2\x9c\x94\nline2        '; _check "padded cont row" 1 "" $? "$REPLY"
# Partial last row: source row 2 "lin" is a non-empty STRICT prefix of buffer row
# "line2" -> phase 3 resolves to line1 + the partial "lin" (a real BUFFER substring).
cand_match $'  ~  line1  \xe2\x9c\x94\nlin';           _check "partial last row" 0 $'line1\nlin' $? "$REPLY"

# Indentation preserved on continuation rows.
BUFFER=$'if true; then\n    echo hi\nfi'
cand_match $'  ~  if true; then  \xe2\x9c\x94\n    echo hi\nfi'; \
    _check "indent preserve" 0 $'if true; then\n    echo hi\nfi' $? "$REPLY"

# Content-ambiguity: two DISTINCT aligning blocks -> fail closed. Row 1 "a b"
# contains both "a" (window 1 -> "a\nz") and "b" (window 3 -> "b\nz"); the two
# windows share continuation row "z" but differ in content, so the resolver
# cannot pick one and must fail closed.
BUFFER=$'a\nz\nb\nz'
cand_match $'a b\nz'; _check "content-ambiguous" 1 "" $? "$REPLY"

# ── Partial-first-line multiline (regression guard for the phase-2 resolver) ──
# When the selection starts mid-line (prefix excluded) and the right-prompt/status
# suffix is included, the forward-containment gate fails.  Phase 2 finds the
# longest prefix of source-row-1 that is a suffix of buffer-row-1.

BUF3=$'line1start line1middle line1end\nline2start line2middle line2end\nline3start line3middle line3end'
BUFFER="$BUF3"

# Partial row 1 + full rows 2+3.
cand_match $'line1middle line1end  \xe2\x9c\x94\nline2start line2middle line2end\nline3start line3middle line3end'; \
    _check "partial-row1+lines2+3" 0 \
    $'line1middle line1end\nline2start line2middle line2end\nline3start line3middle line3end' $? "$REPLY"

# Partial row 1 + full row 2 only.
cand_match $'line1middle line1end  \xe2\x9c\x94\nline2start line2middle line2end'; \
    _check "partial-row1+line2" 0 \
    $'line1middle line1end\nline2start line2middle line2end' $? "$REPLY"

# Partial row 1 + partial row 2: source row 1 is a partial-first (tail+status),
# source row 2 "line2start line2middle " is a non-empty STRICT prefix of buffer
# row 2 -> phase 3 resolves to the partial-first tail + the partial last row.
# The trailing space is genuinely part of the BUFFER substring, so it is kept
# (correct-or-nothing).
cand_match $'line1middle line1end  \xe2\x9c\x94\nline2start line2middle '; \
    _check "partial-row1+partial-row2" 0 $'line1middle line1end\nline2start line2middle ' $? "$REPLY"

# Partial row 1 + full mid + partial last (3-row) -> phase 3 resolves. Source row
# 3 "line3start line3middle " is a strict prefix of buffer row 3; interior row 2
# is exact.  The kept trailing space is a real BUFFER substring (correct-or-nothing).
cand_match $'line1middle line1end  \xe2\x9c\x94\nline2start line2middle line2end\nline3start line3middle '; \
    _check "partial-row1+full-mid+partial-last" 0 \
    $'line1middle line1end\nline2start line2middle line2end\nline3start line3middle ' $? "$REPLY"

# Whole row 1 (decorated) + partial last (2-row) -> phase 3 via forward-containment
# on row 1 and strict-prefix on row 2.
cand_match $'  ~  line1start line1middle line1end  \xe2\x9c\x94\nline2start line2middle '; \
    _check "whole-row1+partial-last" 0 \
    $'line1start line1middle line1end\nline2start line2middle ' $? "$REPLY"

# Whole row 1 (with prefix+suffix) must still work — phase 1 regression guard.
cand_match $'  ~  line1start line1middle line1end  \xe2\x9c\x94\nline2start line2middle line2end'; \
    _check "whole-row1+line2 regression" 0 \
    $'line1start line1middle line1end\nline2start line2middle line2end' $? "$REPLY"

# ── Boundary-whitespace refinement (regression guard for the trim-candidate refiner) ──
# A prompt-prefix/status-suffix trim can leave a boundary space that collapses two
# identical tokens into a single BUFFER occurrence, defeating cursor-based duplicate
# disambiguation. The refiner strips that boundary space when doing so reveals >=2
# occurrences, so the caller sees a genuinely-ambiguous (duplicated) candidate.

# Trimmer lands on " foo" (leading space, 1 occurrence); stripping to "foo" reveals
# 2 occurrences -> refined.
BUFFER="foo foo"; cand_match "x foo"; _check "refine leading-space dup" 0 "foo" $? "$REPLY"

# Trailing-space variant: candidate "foo " occurs once, "foo" occurs twice -> refined.
BUFFER="foo foo"; cand_match "foo x"; _check "refine trailing-space dup" 0 "foo" $? "$REPLY"

# Refiner must NOT fire when the stripped form is still unique (single occurrence):
# stripping changes the count from 1 to 1, so the spaced candidate is kept as-is.
BUFFER="a foo b"; cand_match "z foo"; _check "refine no-op unique" 0 " foo" $? "$REPLY"

# Refiner must NOT fire when the candidate has no boundary whitespace to strip.
BUFFER="foo foo"; cand_match "xfoo"; _check "refine no-op no-space" 0 "foo" $? "$REPLY"

# Stripping to empty (all-whitespace candidate) is guarded: keep original, never
# return "". Here " " appears once in BUFFER; stripped is empty so no refine.
BUFFER="a b c"; cand_match "z b"; _check "refine no-op empty-strip" 0 " b" $? "$REPLY"

print -r -- "fixtures: checks=$CHECKS fails=$FAILS"

# ─────────────────────── Exhaustive sweeps (--full) ───────────────────────
if [[ "${1:-}" == "--full" ]]; then
    print -r -- "== exhaustive differential sweeps (this takes several minutes) =="
    _gen() {
        local -i L=$1; shift
        local -a alpha=("$@") out cur next
        local s c
        cur=(""); out=()
        for (( len=1; len<=L; len++ )); do
            next=()
            for s in "${cur[@]}"; do for c in "${alpha[@]}"; do next+=("$s$c"); done; done
            out+=("${next[@]}"); cur=("${next[@]}")
        done
        print -rl -- "${out[@]}"
    }
    # Single-line equivalence over {a,b,c}: cand == ref (gate never fires — no \n).
    typeset -a B4 S5
    B4=("${(@f)$(_gen 4 a b c)}")
    S5=("${(@f)$(_gen 5 a b c)}")
    integer smis=0 stot=0 mt
    for mt in 1 2 3 4 512; do
        REF_MAX_TRIM=$mt; TEST_MAX_TRIM=$mt; TEST_ORDERED_BUDGET=256
        for buf in "${B4[@]}"; do
            BUFFER="$buf"
            for src in "${S5[@]}"; do
                (( stot++ ))
                ref_match "$src"; local rr=$? pr="$REPLY"
                cand_match "$src"; local rc=$? pc="$REPLY"
                [[ $rr -ne $rc || "$pr" != "$pc" ]] && (( smis++ ))
            done
        done
    done
    print -r -- "single-line equivalence: total=$stot mismatches=$smis (expect 0)"
    (( smis )) && (( FAILS++ ))
fi

if (( FAILS )); then
    print -r -- "RESULT: FAIL ($FAILS failures)"
    exit 1
fi
print -r -- "RESULT: PASS"
exit 0
