#!/bin/sh
# Alacritty click-to-deselect helper for zsh-edit-select.
#
# Wired into ~/.config/alacritty/alacritty.toml as a `command:` on a
# [[mouse.bindings]] block (mouse = "Left", mode = "~Alt").  Alacritty's
# spawn_daemon forks this script on every Left-press in a non-alt-screen
# pane, then setsid-detaches it with stdin/stdout/stderr set to null.  We
# never need the pty — our only job is to clear the X11/Wayland PRIMARY
# selection so the running zsh-edit-select daemon notices an ownership
# change and bumps its cache seq with empty primary.  The shell-side
# zle-line-pre-redraw hook then sees (new seq + empty primary) and clears
# _EDIT_SELECT_ACTIVE_SELECTION, killing the "stale invisible selection
# gets operated on" bug.
#
# Why the plugin's own agents (and not xclip / wl-clipboard):
#   - X11 agent --clear-primary:
#       XSetSelectionOwner(dpy, xa_primary, None, CurrentTime)
#       -> XFixes SelectionOwnerNotify fires on the running daemon
#       -> daemon bumps its own internal seq_counter atomically + writes
#          primary="" / seq=N+1 to its cache files.
#   - Wayland (native: KDE, wlroots) — SIGUSR1 to the running daemon:
#       the daemon publishes primary="" / seq=N+1 to its own cache.
#       PRIMARY itself is deliberately left alone; see the long note at
#       the dispatch site for why clearing it is wrong on KDE.
#   Both agents set the owner to None / pass a NULL source — they do NOT
#   take ownership themselves, so no client process has to stay alive to
#   serve the (empty) selection, and no compositor event ripples back to
#   alacritty (verified by hand: no flicker on the user's GNOME/X11 and
#   Wayland sessions).
#
# Dispatch: 0 forks before the agent exec
#   - PLUGIN_ROOT via POSIX parameter expansion on $0 (no dirname, no
#     readlink, no pwd — every common case is a single var substitution).
#   - Cache dir comes from $1 (the installer writes the literal user/run
#     path into alacritty.toml).  Soft-fallback to the standard
#     ${XDG_RUNTIME_DIR:-/tmp}/zsh-edit-select-<id -u> layout only if $1
#     was passed empty; this branch is never taken in practice.
#   - Display-server selection: pure env-variable string tests plus one
#     `case` glob, all shell builtins in dash (no fork, no `[` exec —
#     `/bin/sh`'s `[` is a builtin), and at most two `-x` stats.
#   - `exec` replaces the shell with the agent — saves one fork+exit
#     pair compared with calling the agent as a child and then exiting.
#
# Failure handling: every soft-failure path (implementation not resolvable
# from the environment, agent binary missing/not-executable) exits 0 without
# touching anything.  The daemon cache stays untouched on those paths — the
# plugin's pre-redraw hook sees no event, so behaviour for that one click
# falls back to the pre-fix state.  No data loss, no spurious event, no false
# trigger.  If the agent itself fails after the exec, its status is not
# observable to alacritty either: spawn_daemon double-forks and waits only on
# the intermediate child (which _exit(0)s immediately), so this process is
# already orphaned by the time the agent runs.
#
# Portability:
#   - This script is parser-portable to dash (Debian/Ubuntu /bin/sh),
#     busybox sh, ash, pdksh, mksh, bash, ksh93, and zsh emulating sh.
#     Avoids bash-isms: no `[[ ]]`, no `$UID`, no `$(<file)`.
#   - Every environment read uses ${VAR:-} so the script is also correct if
#     it is ever sourced into a shell running with `set -u`.
#   - Tested under dash (Pop!/Ubuntu default) and zsh -y (--emulate sh).

# ── PLUGIN_ROOT ──────────────────────────────────────────────────────────
# Resolve the plugin root (the `zsh-edit-select/` dir) from $0 using only
# POSIX parameter expansion — no `dirname`, no `pwd`, no `readlink` forks.
# Alacritty uses the absolute program path the installer wrote into
# alacritty.toml, so $0 is reliably
#   /<plugin>/assets/helpers/zes-alacritty-click-clear.sh
# Strip the script name, then `helpers`, then `assets` to reach PLUGIN_ROOT.
self=$0
dir=${self%/*}                          # /<plugin>/assets/helpers
[ "$dir" = "$self" ] && dir=.          # bare-filename fallback (cwd lookup)
PLUGIN_ROOT=${dir%/*}                  # /<plugin>/assets
PLUGIN_ROOT=${PLUGIN_ROOT%/*}          # /<plugin>

# ── Cache directory ──────────────────────────────────────────────────────
# First positional argument is the daemon cache directory, baked into the
# alacritty.toml `args = [...]` array by the installer.  This avoids a
# per-click `id -u` fork — the cache path is identical for every click of
# this user on this machine.
#
# The fallback (only when $1 is missing or empty, which the installer
# never does) reproduces the daemon's own canonical layout so the helper
# remains usable when invoked manually from a shell for testing.
if [ -n "${1:-}" ]; then
    CACHE_DIR=$1
else
    CACHE_DIR=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-edit-select-$(id -u)
fi

# ── Display-server dispatch ─────────────────────────────────────────────
# The agent we exec has to be the SAME one the running daemon is watching
# with, otherwise we clear a selection nobody is subscribed to: no
# ownership-change event → cache seq never bumps → the shell-side hook never
# fires → the "phantom selection" bug is back.  That agent is decided in two
# stages by the plugin, and both stages are mirrored below.
#
# Stage 1 — which implementation did the loader pick?
#   zsh-edit-select.plugin.zsh chooses impl-wayland when ZES_FORCE_IMPL says
#   so, or when XDG_SESSION_TYPE=wayland (the session-level indicator it
#   trusts first), or when WAYLAND_DISPLAY is set; impl-x11 when only DISPLAY
#   is.  Checking XDG_SESSION_TYPE matters: a Wayland session that hands
#   alacritty an XWayland connection can leave WAYLAND_DISPLAY unset in the
#   inherited environment, and keying only off WAYLAND_DISPLAY would send us
#   to impl-x11's agent while the daemon is impl-wayland's.
#   ZES_FORCE_IMPL only reaches us when it was exported into the session that
#   launched alacritty (~/.profile, systemd --user, the DE's session env); set
#   in ~/.zshrc it is invisible here, and stage 1 then falls through to the
#   same env detection the loader itself would have used.  Any other value —
#   wsl, macos, or something invalid the loader rejects outright — means no
#   daemon is watching PRIMARY on this display, so there is nothing to signal.
#
# Stage 2 — which agent did that implementation's backend pick?
#   impl-wayland/backends/wayland-backend.zsh:19-37.  Mutter-based desktops
#   (GNOME and its forks, Cinnamon, Pantheon) deny background Wayland clients
#   access to wp_primary_selection but faithfully sync it into the X11 PRIMARY
#   atom on XWayland, so the daemon there is the xwayland agent.  KDE/KWin and
#   wlroots compositors do the opposite — no PRIMARY bridge to X11, but they
#   do speak wlr-data-control — so the wl agent is correct.  Keep this branch
#   identical to wayland-backend.zsh's: if it ever gains a case, add it here
#   too (that divergence is exactly what broke click-to-deselect on pop:GNOME).
case "${ZES_FORCE_IMPL:-}" in
    x11)     _impl=x11 ;;
    wayland) _impl=wayland ;;
    '')
        if [ "${XDG_SESSION_TYPE:-}" = wayland ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            _impl=wayland
        elif [ -n "${DISPLAY:-}" ]; then
            _impl=x11
        else
            _impl=
        fi
        ;;
    *)  _impl= ;;
esac

AGENT=""
_native_wl=0
if [ "$_impl" = wayland ]; then
    _uses_xwl=0
    case "${XDG_CURRENT_DESKTOP:-}" in
        *GNOME*|*gnome*|*Cinnamon*|*cinnamon*|*Pantheon*|*pantheon*)
            _uses_xwl=1
            ;;
    esac
    if [ "$_uses_xwl" = 1 ] && [ -n "${DISPLAY:-}" ] \
       && [ -x "$PLUGIN_ROOT/impl-wayland/backends/xwayland/zes-xwayland-agent" ]; then
        AGENT=$PLUGIN_ROOT/impl-wayland/backends/xwayland/zes-xwayland-agent
    else
        # Native Wayland (KDE/KWin, wlroots).  Signals the daemon rather than
        # execing anything, so unlike every other branch it needs no agent
        # binary of its own — only the pid file.  Deliberately unconditional:
        # keying it off an -x test on the wl agent would silently fall through
        # to "do nothing" on a tree where that binary is missing, which is the
        # phantom-selection bug all over again.
        _native_wl=1
    fi
elif [ "$_impl" = x11 ]; then
    AGENT=$PLUGIN_ROOT/impl-x11/backends/x11/zes-x11-selection-agent
fi

# ── Native Wayland: notify the daemon instead of clearing PRIMARY ────────
# Clearing the compositor's PRIMARY is the wrong instrument here.  On KDE
# Plasma the clipboard manager treats an emptied selection as something to
# restore and refills it from its own history within about a second, so the
# clear comes back as a *new* selection carrying whatever was in that history
# (measured on Plasma 6 Wayland: a stale `file:///…` URI replacing the real
# selection, twice out of two attempts).  The shell then arms that text as the
# active mouse selection and edits land on it.  Any client-side clear hits
# this — wl-copy --primary --clear issues the identical data-control request —
# so the fix is not to clear at all.
#
# What actually has to happen is narrower: the shell must drop its cached
# selection.  SIGUSR1 tells the running daemon to publish the empty state to
# its cache directly, which is the same (new seq, empty primary) pair it
# already writes when a selection genuinely disappears.  Nothing is asked of
# the compositor, so no clipboard manager has anything to react to, and the
# real PRIMARY is left intact and still middle-click pasteable elsewhere.
#
# X11 and XWayland keep clearing PRIMARY for real: XSetSelectionOwner(None)
# leaves it genuinely unowned, nothing restores it, and that path is proven.
#
# Cost: `read`, `case` and `kill` are all shell builtins, so this branch
# forks nothing and execs nothing — cheaper than spawning the agent at all.
if [ "$_native_wl" = 1 ]; then
    _pid=
    [ -r "$CACHE_DIR/agent.pid" ] && read -r _pid < "$CACHE_DIR/agent.pid"
    # Reject anything that is not a plain number before it reaches kill.
    case "${_pid:-x}" in
        ''|*[!0-9]*) exit 0 ;;
    esac
    # Confirm the pid still belongs to our agent.  A stale pid file plus a
    # recycled pid would otherwise send SIGUSR1 to an unrelated process, whose
    # default disposition for that signal is to terminate.  /proc/<pid>/comm is
    # truncated to 15 bytes, hence the prefix match.
    _comm=
    [ -r "/proc/$_pid/comm" ] && read -r _comm < "/proc/$_pid/comm"
    case "$_comm" in
        zes-wl-selectio*) kill -USR1 "$_pid" 2>/dev/null ;;
    esac
    exit 0
fi

# ── Exec the agent (X11 / XWayland) ─────────────────────────────────────
# Replace the shell image with the agent so we pay exactly one fork+exec
# (alacritty already forked once to get us here).  The exec also means
# our RSS, page tables, and any residual fd state never linger — the
# process image becomes the agent.
[ -n "$AGENT" ] || exit 0
[ -x "$AGENT" ] || exit 0
exec "$AGENT" "$CACHE_DIR" --clear-primary
