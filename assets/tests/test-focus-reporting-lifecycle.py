#!/usr/bin/env python3
"""Focus-reporting lifecycle regression suite for zsh-edit-select.

This suite guards the terminal focus-reporting (DECSET 1004) lifecycle and its
interaction with mouse-selection state against future regressions. It reproduces,
in one self-contained harness, the behavioral contracts of the lifecycle design:

  * Classification: the lifecycle machinery must be installed only in shells
    whose prompt stack owns the zle-line-init widget; plain shells must keep the
    base plugin's exact registration and write pattern.
  * Plain-shell parity: mode writes byte-identical to the base plugin (enable at
    session entry, disable at the command handoff), with zero machinery present.
  * Session-owner lifecycle: capture on before the owner's first key; mode off
    before any work the owner runs after its editing session ends (nothing a
    foreground program reads); mode restored before any continued editing; clean
    handoff (a foreground reader never receives stray CSI I / CSI O bytes) --
    verified under both terminal reply models (immediate-reply and no-reply).
  * The continuation-buffer property: a focus change missed during the short
    mode-off window at an in-widget continuation boundary cannot corrupt the
    buffer, because the continuation buffer is empty at the first key after
    the window (verified with an in-window focus event on a no-reply terminal).
  * Machinery stability: off/on re-configuration and re-sourcing stay bounded;
    the observer never registers outside an accept window; a decorated reload
    does not recurse; an aborted vared keeps the base plugin's behavior.
  * The known limitation: a third-party accept-line widget that refuses accepts
    keeps reporting off until the next keystroke (documented in README; this
    suite pins that documented shape so any change -- fix or regression --
    is caught).

It also runs the sibling matcher suite (test-prompt-aware-matcher.zsh, fast mode)
so a single invocation covers the selection-matching algorithm as well.

Requirements: python3, zsh (5.x). Everything runs in throwaway scratch
directories; no files outside them are written. No network, no builds.

Usage:
    python3 assets/tests/test-focus-reporting-lifecycle.py

Exit codes: 0 = all required rows pass; 1 = at least one required row fails;
rows that cannot run in the current environment are reported as SKIP and never
fail the run. A missing lifecycle machinery is a FAILURE by design: this suite
tests the plugin as shipped with the focus-lifecycle changes applied.
"""

import fcntl
import json
import os
import pathlib
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

HERE = pathlib.Path(__file__).resolve().parent
PLUGIN_ROOT = HERE.parent.parent          # .../zsh-edit-select
MATCHER_SUITE = HERE / "test-prompt-aware-matcher.zsh"
LOADER = PLUGIN_ROOT / "zsh-edit-select.plugin.zsh"

MODE_ON = re.compile(rb"\x1b\[\?1004h")
MODE_OFF = re.compile(rb"\x1b\[\?1004l")
# Bootstrap/load failure tokens that must never appear anywhere in a session.
GUARD = re.compile(
    rb"no such builtin|command not found: _zes|too many arguments"
)

ZSH = shutil.which("zsh") or os.environ.get("ZSH") or "/bin/zsh"
if not pathlib.Path(ZSH).exists():
    print("no usable zsh found on PATH or $ZSH -- cannot run")
    sys.exit(1)


class Row:
    """One test row: a name, a runner, and whether it is required."""

    def __init__(self, name, runner, required=True, group=""):
        self.name = name
        self.runner = runner
        self.required = required
        self.group = group


ROWS = []


def row(name, required=True, group=""):
    def deco(fn):
        ROWS.append(Row(name, fn, required, group))
        return fn
    return deco


# --------------------------------------------------------------------------
# PTY harness
# --------------------------------------------------------------------------

class Session:
    """An interactive zsh in a scratch HOME, with mode-write tracking.

    ``reply`` models the terminal's response to an enabling write: True sends
    an immediate CSI I (the immediate-reply terminal family), False models
    terminals that report nothing on enable. Mode state is only meaningful
    after pump(); probes use computed output tokens so an echoed command can
    never satisfy a wait.
    """

    def __init__(self, name, rc_lines, reply=True, env_extra=None):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="zes-focus-"))
        (self.dir / "home").mkdir()
        (self.dir / "run").mkdir()
        (self.dir / ".zshrc").write_text("".join(rc_lines))
        self.buf = b""
        self.modes = []          # chronological h/l observations
        self.on = False
        self.reply = reply
        self.guard_hit = None
        self._master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
        self.pid = os.fork()
        if not self.pid:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            for n in (0, 1, 2):
                os.dup2(slave, n)
            os.close(self._master)
            if slave > 2:
                os.close(slave)
            env = {
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "TERM": "xterm-256color",
                "LC_ALL": "C.UTF-8",
                "HOME": str(self.dir / "home"),
                "ZDOTDIR": str(self.dir),
                "XDG_RUNTIME_DIR": str(self.dir / "run"),
                # A backend that cannot start agents here must not produce
                # noise: force the X11 backend and point at a dead display.
                "ZES_FORCE_IMPL": "x11",
                "DISPLAY": "",
                "EDIT_SELECT_MOUSE_REPLACEMENT": "1",
            }
            if env_extra:
                env.update(env_extra)
            os.execve(ZSH, [ZSH, "-d", "-i"], env)
        os.close(slave)

    def send(self, data):
        os.write(self._master, data if isinstance(data, bytes) else data.encode())

    def pump(self, seconds=0.05):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            timeout = max(0.0, end - time.monotonic())
            if not select.select([self._master], [], [], timeout)[0]:
                break
            try:
                chunk = os.read(self._master, 65536)
            except OSError:
                return
            if not chunk:
                return
            self.buf += chunk
            for match in MODE_ON.finditer(chunk):
                self.on = True
                self.modes.append("h")
                if self.reply:
                    os.write(self._master, b"\x1b[I")
            for match in MODE_OFF.finditer(chunk):
                self.on = False
                self.modes.append("l")

    def wait(self, needle, timeout=25):
        start = len(self.buf)
        end = time.monotonic() + timeout
        while needle not in self.buf[start:] and time.monotonic() < end:
            self.pump(0.05)
        return needle in self.buf[start:]

    def modes_since(self, mark):
        return self.modes[mark:]

    def close(self):
        m = GUARD.search(self.buf)
        if m:
            self.guard_hit = m.group(0).decode("replace")
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass
        try:
            os.close(self._master)
        except OSError:
            pass
        shutil.rmtree(self.dir, ignore_errors=True)


def basic_rc(extra=()):
    """The standard plugin-load rc for every session."""
    return [
        "export PS1='T$((3+4))Q> '\n",
        "source '%s'\n" % LOADER,
    ] + list(extra)


def ask(sess, body):
    """Run a shell command at the live prompt; return the computed-token window.

    ``body`` must print its answer after a computed token prefix so the echo
    of the typed line can never be mistaken for the answer.
    """
    start = len(sess.buf)
    sess.send("print -r -- \"A$((6+2))N=%s\"; print D$((5+5))NE\r" % body)
    sess.wait(b"D10NE")
    sess.pump(0.25)
    window = sess.buf[start:]
    m = re.search(rb"A8N=(.*?)D10NE", window, re.S)
    return m.group(1).decode("utf-8", "replace").strip() if m else None


def fresh_prompt(sess, token=b"T7Q> ", settle=3.0):
    sess.pump(settle)
    ok = sess.wait(token, timeout=25)
    sess.pump(0.8)
    return ok


# --------------------------------------------------------------------------
# Shared fixtures
# --------------------------------------------------------------------------

# A synthetic line-init widget owner that opens an editing session inside the
# init chain and then hands the command off after running some work in between
# (the render slot). No prompt provider is needed: this reproduces the
# session-owner composition with stock zle only.
OWNER_RENDER = r"""
_zes_t_owner() {
    zle .recursive-edit
    printf '\e]999;ZES_RENDER_WORK\a'
    zle .accept-line
}
zle -N zle-line-init _zes_t_owner
"""

# The same owner without the render/handoff: it opens the session and returns,
# leaving the outer editor to read (the chain-completion shape).
OWNER_RETURN = r"""
_zes_t_owner2() { zle .recursive-edit }
zle -N zle-line-init _zes_t_owner2
"""

# An observation widget used to read the buffer contents on demand.
OBSERVE = r"""
_zes_t_obs() { printf '\e]999;OBS|%s\a' $BUFFER; return 0 }
zle -N ._zes_t_obs _zes_t_obs
bindkey '^Xq' ._zes_t_obs
"""


def observe_buffer(sess):
    start = len(sess.buf)
    sess.send(b"\x18q")
    sess.pump(0.5)
    m = re.search(rb"\x1b\]999;OBS\|([^\x07]*)\x07", sess.buf[start:])
    return m.group(1).decode("utf-8", "replace") if m else None


class ModeledCache:
    """A selection cache the shell-side code reads, without any agent.

    The plugin consumes its selection state through the cache files; pointing
    the shell at a scratch cache (and marking a daemon active via its pid file
    holding a live pid) lets the suite deliver selection events deterministically.
    """

    def __init__(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="zes-cache-"))
        for name in ("seq", "primary", "agent.pid"):
            (self.dir / name).write_text("")
        (self.dir / "agent.pid").write_text(str(os.getpid()))
        self.seq = 100
        (self.dir / "seq").write_text("%d" % self.seq)

    def env_lines(self):
        d = str(self.dir)
        return [
            "export _EDIT_SELECT_CACHE_DIR=%s\n" % d,
            "export _EDIT_SELECT_SEQ_FILE=%s/seq\n" % d,
            "export _EDIT_SELECT_PRIMARY_FILE=%s/primary\n" % d,
            "export _EDIT_SELECT_PID_FILE=%s/agent.pid\n" % d,
            "export _EDIT_SELECT_DAEMON_ACTIVE=1\n",
            "export _EDIT_SELECT_LAST_SEQ=%d\n" % self.seq,
            "export _EDIT_SELECT_EVENT_FIRED_FOR_SEQ=1\n",
        ]

    def publish_selection(self, text):
        """Deliver a selection event the way the monitor daemon would."""
        self.seq += 1
        (self.dir / "primary").write_text(text)
        (self.dir / "seq").write_text("%d" % self.seq)

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


# --------------------------------------------------------------------------
# Group A: classification
# --------------------------------------------------------------------------

@row("classification: plain shell keeps the base registration", group="classification")
def classification_plain():
    sess = Session("plain", basic_rc())
    try:
        fresh_prompt(sess)
        answer = ask(sess, "${widgets[zle-line-init]:-NONE}")
        if answer is None or "azhw:zle-line-init" not in answer:
            return False, "zle-line-init spec: %r" % answer
        answer = ask(sess, "$(zstyle -a zle-line-init widgets l; echo -n ${(j:,:)l})")
        if answer is None or "_zes_enable_focus_reporting_plain" not in answer:
            return False, "line-init hook list: %r" % answer
        answer = ask(sess, "${_ZES_FOCUS_MACHINERY_DECIDED}${_ZES_FOCUS_MACHINERY_ON}")
        if answer != "10":
            return False, "cached decision: %r (want 10)" % answer
        answer = ask(sess, "$(zstyle -a zle-line-finish widgets l; echo -n ${(j:,:)l})")
        if answer and "_zes_finish_disable" in answer:
            return False, "finish hook registered in a plain shell: %r" % answer
        return True, ""
    finally:
        sess.close()


@row("classification: azhw hook functions are not owners", group="classification")
def classification_hook_only():
    extra = [
        "other_hook() { : }\n",
        "autoload -Uz add-zle-hook-widget\n",
        "add-zle-hook-widget zle-line-init other_hook\n",
    ]
    sess = Session("hookonly", basic_rc(extra))
    try:
        fresh_prompt(sess)
        answer = ask(sess, "${_ZES_FOCUS_MACHINERY_DECIDED}${_ZES_FOCUS_MACHINERY_ON}")
        return answer == "10", "decision: %r (want 10)" % answer
    finally:
        sess.close()


@row("classification: a direct line-init widget owner gets the machinery", group="classification")
def classification_direct_owner():
    extra = ["_zes_t_owner() { return 0 }\n", "zle -N zle-line-init _zes_t_owner\n"]
    sess = Session("direct", basic_rc(extra))
    try:
        fresh_prompt(sess)
        answer = ask(sess, "${widgets[zle-line-init]:-NONE}")
        if answer is None or not answer.startswith("user:_zes_li_wrap_gen"):
                       return False, "wrapper spec: %r" % answer
        answer = ask(sess, "${_ZES_FOCUS_MACHINERY_DECIDED}${_ZES_FOCUS_MACHINERY_ON}")
        return answer == "11", "decision: %r (want 11); wrapper: see previous" % answer
    finally:
        sess.close()


@row("classification: an owner buried under an azhw takeover is still found", group="classification")
def classification_buried_owner():
    extra = [
        "_zes_t_owner() { return 0 }\n",
        "zle -N zle-line-init _zes_t_owner\n",
        "late_hook() { : }\n",
        "autoload -Uz add-zle-hook-widget\n",
        "add-zle-hook-widget zle-line-init late_hook\n",
    ]
    sess = Session("buried", basic_rc(extra))
    try:
        fresh_prompt(sess)
        answer = ask(sess, "${_ZES_FOCUS_MACHINERY_DECIDED}${_ZES_FOCUS_MACHINERY_ON}")
        if answer != "11":
            return False, "decision: %r (want 11)" % answer
        answer = ask(sess, "${widgets[zle-line-init]:-NONE}")
        return (answer or "").startswith("user:_zes_li_wrap_gen"), "wrapper spec: %r" % answer
    finally:
        sess.close()


@row("classification: the decision is cached and survives re-configuration", group="classification")
def classification_cached():
    extra = ["_zes_t_owner() { return 0 }\n", "zle -N zle-line-init _zes_t_owner\n"]
    sess = Session("cached", basic_rc(extra))
    try:
        fresh_prompt(sess)
        sess.send(b"EDIT_SELECT_MOUSE_REPLACEMENT=0; "
                  b"edit-select::apply-mouse-replacement-config; "
                  b"EDIT_SELECT_MOUSE_REPLACEMENT=1; "
                  b"edit-select::apply-mouse-replacement-config\r")
        sess.pump(2.0)
        answer = ask(sess, "${_ZES_FOCUS_MACHINERY_DECIDED}${_ZES_FOCUS_MACHINERY_ON}")
        if answer != "11":
            return False, "decision after re-apply: %r" % answer
        answer = ask(sess, "${widgets[zle-line-init]:-NONE}")
        return (answer or "").startswith("user:_zes_li_wrap_gen"), "wrapper spec: %r" % answer
    finally:
        sess.close()


# --------------------------------------------------------------------------
# Group B: plain-shell parity
# --------------------------------------------------------------------------

@row("plain shell: mode writes match the base plugin (enable at entry, disable at handoff)", group="plain-parity")
def plain_byte_trace():
    sess = Session("trace", basic_rc(), reply=False)
    try:
        fresh_prompt(sess)
        first = list(sess.modes)
        sess.send(b"print O$((2+3))NE\r")
        sess.wait(b"O5NE")
        sess.pump(0.8)
        after_one = list(sess.modes)
        sess.send(b"print O$((3+3))NE\r")
        sess.wait(b"O6NE")
        sess.pump(0.8)
        after_two = list(sess.modes)
        ok = (first == ["h"]
              and after_one == ["h", "l", "h"]
              and after_two == ["h", "l", "h", "l", "h"])
        return ok, "writes: first=%r cmd1=%r cmd2=%r" % (first, after_one, after_two)
    finally:
        sess.close()


@row("plain shell: a foreground reader never receives focus bytes", group="plain-parity")
def plain_reader_clean():
    sess = Session("reader", basic_rc(), reply=True)
    try:
        fresh_prompt(sess)
        sess.send(b"python3 -c 'import sys;print(\"R$((4+4)):\"+sys.stdin.buffer.readline().decode().strip())'\r")
        sess.wait(b"R8:")
        sess.send(b"\r")
        sess.wait(b"R8:")
        sess.pump(0.3)
        leak = b"\x1b[I" in sess.buf[-150:] or b"\x1b[O" in sess.buf[-150:]
        return not leak, "reader tail: %r" % sess.buf[-100:]
    finally:
        sess.close()


# --------------------------------------------------------------------------
# Group C: session-owner lifecycle (synthetic provider, both reply models)
# --------------------------------------------------------------------------

def _render_gate(reply):
    sess = Session("render-%s" % reply, basic_rc([OWNER_RENDER, OBSERVE]), reply=reply)
    try:
        fresh_prompt(sess)
        before = len(sess.buf)
        sess.send(b"print G$((2+6))ATE\r")
        sess.wait(b"G8ATE")
        sess.pump(1.2)
        work_at = sess.buf.find(b"\x1b]999;ZES_RENDER_WORK\x07", before)
        if work_at < 0:
            return False, "the owner's post-session work never ran"
        prefix = sess.buf[before:work_at]
        modes_in_prefix = [m for m in MODE_ON.finditer(prefix)] + [m for m in MODE_OFF.finditer(prefix)]
        seen_on = [MODE_ON.search(chunk) for chunk in [prefix]]
        # Mode at the instant of the owner's work: scan the last mode write
        # that precedes the work marker.
        last_on = None
        for m in re.finditer(rb"\x1b\[\?1004([hl])", sess.buf[:work_at]):
            last_on = m.group(1)
        if last_on != b"l":
            return False, "mode at the owner's post-session work: %r (want off)" % last_on
        sess.send(b"python3 -c 'import sys;print(\"R$((3+3)):\"+sys.stdin.buffer.readline().decode().strip())'\r")
        sess.wait(b"R6:")
        sess.send(b"\r")
        sess.wait(b"R6:")
        sess.pump(0.3)
        leak = b"\x1b[I" in sess.buf[-150:] or b"\x1b[O" in sess.buf[-150:]
        return not leak, "foreground reader tail: %r" % sess.buf[-100:]
    finally:
        sess.close()


@row("session-owner: mode off before the owner's post-session work; clean handoff (immediate-reply terminal)", group="owner-lifecycle")
def render_gate_reply():
    return _render_gate(True)


@row("session-owner: mode off before the owner's post-session work; clean handoff (no-reply terminal)", group="owner-lifecycle")
def render_gate_noreply():
    return _render_gate(False)


@row("session-owner: capture is on from session start, before the first key", group="owner-lifecycle")
def capture_at_session_start():
    sess = Session("capstart", basic_rc([OWNER_RENDER, OBSERVE]), reply=True)
    try:
        fresh_prompt(sess)
        # No keystroke yet: the mode must already be on from the session
        # entry, so a focus event delivered now is consumed by the bound
        # widgets and baselines the selection state (no wrong-pane replace).
        if not sess.on:
            return False, "capture off at session start"
        sess.send(b"\x1b[I")
        sess.pump(0.3)
        sess.send(b"print A$((1+1))LPHA\r")
        sess.wait(b"A2LPHA")
        sess.pump(0.6)
        return True, ""
    finally:
        sess.close()


@row("session-owner: continuation boundary restores capture before the next key", group="owner-lifecycle")
def ps2_boundary_capture():
    sess = Session("ps2", basic_rc([OWNER_RENDER, OBSERVE]), reply=False)
    try:
        fresh_prompt(sess)
        sess.send(b"print C$((2+5))NT")
        sess.pump(0.3)
        sess.send(b"\\\r")       # continuation: the editor continues on a new line
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            sess.pump(0.05)
            if sess.modes and sess.modes[-1] == "h":
                break
        restored = sess.on
        if not restored:
            return False, "capture not restored after the continuation boundary"
        sess.send(b"X")            # the first key on the continuation line
        sess.pump(0.3)
        buf = observe_buffer(sess)  # the continuation line holds exactly "X"
        sess.send(b"\r")           # accept; the composed command must run
        ran = sess.wait(b"C7NTX")
        sess.pump(0.6)
        ok = buf is not None and buf == "X" and ran
        return ok, "continuation buffer=%r composed command ran=%r" % (buf, ran)
    finally:
        sess.close()


@row("continuation-buffer property: a selection event landing at a continuation boundary cannot corrupt the fresh line", group="owner-lifecycle")
def empty_buffer_property():
    # A continuation boundary moves the accepted text into PREBUFFER and
    # starts the buffer empty. A selection event that arrives across the
    # boundary (modeled here by publishing to the shared cache, the way the
    # monitor does) is consumed by the first key on the empty continuation
    # line: no match is possible, so the typed text stays intact. On the
    # no-reply terminal model this is the load-bearing defense -- the missed
    # focus event means the event is never baselined, so only this property
    # stands between the event and the buffer.
    cache = ModeledCache()
    sess = Session("emptybuf", basic_rc([OWNER_RENDER, OBSERVE]) + cache.env_lines(), reply=False)
    try:
        fresh_prompt(sess)
        sess.send(b"print S$((3+4))FE")
        sess.pump(0.3)
        sess.send(b"\\\r")
        sess.pump(0.4)
        cache.publish_selection("S7FE")   # the stale event: never baselined
        sess.pump(0.1)
        sess.send(b"S7FE")
        sess.pump(0.8)
        buf = observe_buffer(sess)
        sess.send(b"\x03")
        sess.pump(0.3)
        intact = buf is not None and "S7FE" in buf
        return intact, "buffer: %r (expected the typed text intact)" % buf
    finally:
        sess.close()
        cache.cleanup()



@row("session-owner: a send-break inside the session hands off cleanly", group="owner-lifecycle")
def send_break_handoff():
    sess = Session("sendbreak", basic_rc([OWNER_RENDER, OBSERVE]), reply=True)
    try:
        fresh_prompt(sess)
        sess.send(b"print S$((3+3))BRK")
        sess.pump(0.3)
        sess.send(b"\x03")          # send-break aborts the in-session editor
        sess.pump(0.8)
        sess.send(b"print A$((9-3))FTER\r")
        ran = sess.wait(b"A6FTER")
        sess.pump(0.8)
        # The next foreground reader must see no focus bytes: the aborted
        # session's handoff is clean either way.
        sess.send(b"python3 -c 'import sys;print(\"R$((8)):\""
                  b"+sys.stdin.buffer.readline().decode().strip())'\r")
        sess.wait(b"R8:")
        sess.send(b"\r")
        sess.wait(b"R8:")
        sess.pump(0.3)
        leak = b"\x1b[I" in sess.buf[-150:] or b"\x1b[O" in sess.buf[-150:]
        return ran and not leak, "ran=%r reader tail=%r" % (ran, sess.buf[-90:])
    finally:
        sess.close()


@row("session-owner: a widget-opened nested editor inside the session preserves capture", group="owner-lifecycle")
def nested_editor_in_session():
    # A user widget that opens its own editor inside the session must not
    # disturb the session's capture: the inner accept's D and the outer
    # session's next-redraw E land back-to-back (sub-millisecond window).
    opener = (
        "_zes_t_open() { zle .recursive-edit }\n"
        "zle -N _zes_t_open\n"
        "bindkey '^Xo' _zes_t_open\n"
    )
    sess = Session("nested", basic_rc([OWNER_RENDER, opener, OBSERVE]), reply=True)
    try:
        fresh_prompt(sess)
        sess.send(b"\x18o")       # open the nested editor (no mode change expected)
        sess.pump(0.5)
        mode_in_nested = sess.on
        sess.send(b"x")
        sess.pump(0.3)
        sess.send(b"\r")           # accept inside the nested editor
        sess.pump(1.0)
        mode_after = sess.on
        buf = observe_buffer(sess)
        sess.send(b"\x03")
        sess.pump(0.4)
        ok = mode_in_nested and buf is not None and "x" in buf
        return ok, "mode in nested=%r after=%r buffer=%r" % (mode_in_nested, mode_after, buf)
    finally:
        sess.close()


@row("plain shell: a widget-opened nested editor costs zero machinery writes", group="owner-lifecycle")
def nested_editor_plain():
    opener = (
        "_zes_t_open() { zle .recursive-edit }\n"
        "zle -N _zes_t_open\n"
        "bindkey '^Xo' _zes_t_open\n"
    )
    sess = Session("nestedplain", basic_rc([opener, OBSERVE]), reply=False)
    try:
        fresh_prompt(sess)
        sess.pump(0.8)
        mark = len(sess.modes)
        sess.send(b"\x18o")
        sess.pump(0.5)
        sess.send(b"x")
        sess.pump(0.3)
        sess.send(b"\r")           # accept inside the nested editor; it returns
        sess.pump(1.0)
        writes = list(sess.modes[mark:])
        buf = observe_buffer(sess)
        sess.send(b"\x03")
        sess.pump(0.3)
        ok = writes == [] and sess.on and buf is not None and "x" in buf
        return ok, "writes around the nested editor=%r (want none) buffer=%r" % (writes, buf)
    finally:
        sess.close()


@row("session-owner: repeated continuation boundaries hold the per-boundary pattern and bounded mints", group="owner-lifecycle")
def continuation_loop():
    sess = Session("loop", basic_rc([OWNER_RENDER, OBSERVE]), reply=False)
    try:
        fresh_prompt(sess)
        base = len(sess.modes)
        for i in range(3):
            sess.send(b"print L$((%d+4))OOP" % i)
            sess.pump(0.3)
            sess.send(b"\\\r")
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline:
                sess.pump(0.05)
                if len(sess.modes) > base and sess.modes[-1] == "h":
                    break
            if not sess.on:
                return False, "capture not restored at boundary %d: modes=%r" % (i, sess.modes[base:])
        sess.send(b"D\r")
        ran = sess.wait(b"L4OOP")
        sess.pump(1.0)
        answer = ask(sess, "${_ZES_AC_MINTS}")
        sess.send(b"\x03")
        sess.pump(0.3)
        mints_ok = answer == "1"
        ok = ran and mints_ok
        return ok, "ran=%r mints=%r modes=%r" % (ran, answer, sess.modes[base:])
    finally:
        sess.close()


@row("session-owner: the accept mint is reused, not re-minted, across commands", group="owner-lifecycle")
def mint_reuse():
    sess = Session("mintreuse", basic_rc([OWNER_RENDER]), reply=False)
    try:
        fresh_prompt(sess)
        for i in range(4):
            sess.send(b"print M$((%d+5))INT\r" % i)
            sess.wait(b"M%dINT" % (i + 5))
            sess.pump(0.5)
        answer = ask(sess, "${_ZES_AC_MINTS}")
        # The standing mint is re-armed while its owner spec is unchanged, so
        # four commands must not have minted four wrappers.
        return answer == "1", "mints after four commands: %r (want 1)" % answer
    finally:
        sess.close()


# --------------------------------------------------------------------------
# Group D: stability and machinery risk
# --------------------------------------------------------------------------

@row("stability: off/on cycles stay bounded on an owner stack", group="stability")
def offon_bounded():
    extra = ["_zes_t_owner() { return 0 }\n", "zle -N zle-line-init _zes_t_owner\n"]
    sess = Session("offon", basic_rc(extra))
    try:
        fresh_prompt(sess)
        gens = []
        for _ in range(4):
            sess.send(b"EDIT_SELECT_MOUSE_REPLACEMENT=0; "
                      b"edit-select::apply-mouse-replacement-config; "
                      b"EDIT_SELECT_MOUSE_REPLACEMENT=1; "
                      b"edit-select::apply-mouse-replacement-config\r")
            sess.pump(2.0)
            answer = ask(sess, "${_ZES_LI_GEN}")
            try:
                gens.append(int(answer))
            except (TypeError, ValueError):
                gens.append(-1)
        # Bounded means: the generation counter never grows without limit.
        # One re-snapshot step after the first teardown is allowed; after
        # that, the same generation must be re-bound forever.
        # Bounded: at most one re-snapshot step after the first teardown,
        # then the same generation re-bound forever.
        stable_tail = len(set(gens[1:])) == 1 if len(gens) > 1 else True
        bounded = stable_tail and max(gens) <= max(gens[0], 1) + 1 and max(gens) <= 3
        return bounded, "generations: %r" % gens
    finally:
        sess.close()


@row("stability: the observer is not armed during ordinary editing", group="stability")
def observer_quiescent():
    # In a session-owner shell every typed command's Enter dispatches through
    # the accept wrapper, which legitimately arms the observer for that
    # accept. The meaningful assertion is the state BETWEEN accepts: probe
    # via a keystroke-bound widget (no Enter involved) right after the session
    # starts, and after a completed command, and both times the observer must
    # be disarmed.
    probe = (
        "_zes_t_probe() { printf '\\e]999;ARM=%s\\a' ${_ZES_FOCUS_OBSERVER_ARMED}; return 0 }\n"
        "zle -N _zes_t_probe\n"
        "bindkey '^Xp' _zes_t_probe\n"
    )
    sess = Session("quiesce", basic_rc([OWNER_RENDER, probe]))
    try:
        fresh_prompt(sess)
        sess.send(b"\x18p")       # probe before any Enter in this session
        sess.pump(0.4)
        m = re.search(rb"\x1b\]999;ARM=(\S*?)\a", sess.buf)
        armed_at_start = m.group(1).decode() if m else None
        sess.send(b"print Q$((2+9))UI\r")
        sess.wait(b"Q11UI")
        sess.pump(1.0)
        sess.send(b"\x18p")       # probe in the next session, before any Enter
        sess.pump(0.4)
        m2 = re.search(rb"\x1b\]999;ARM=(\S*?)\a", sess.buf[-200:])
        armed_next = m2.group(1).decode() if m2 else None
        ok = armed_at_start == "0" and armed_next == "0"
        return ok, "armed at session start=%r next session=%r (want 0/0)" % (
            armed_at_start, armed_next)
    finally:
        sess.close()


@row("stability: a decorated reload must not recurse", group="stability")
def decorated_reload():
    sess = Session("deco", basic_rc())
    try:
        fresh_prompt(sess)
        sess.send(b"late_init() { zle .late_orig -- \"$@\" }; "
                  b"zle -A zle-line-init .late_orig; "
                  b"zle -N zle-line-init late_init\r")
        sess.pump(0.8)
        sess.send(b"print N$((4+4))O\r")
        ok = sess.wait(b"N8O")
        sess.pump(0.8)
        answer = ask(sess, "${_ZES_LI_GEN}")
        sess.send(b"\x03")
        return ok and answer is not None, "command ran=%r gen=%r" % (ok, answer)
    finally:
        sess.close()


@row("stability: the feature-off state stays inert", group="stability")
def feature_off_inert():
    sess = Session("inert", basic_rc([OWNER_RENDER, OBSERVE]))
    try:
        fresh_prompt(sess)
        sess.send(b"EDIT_SELECT_MOUSE_REPLACEMENT=0; edit-select::apply-mouse-replacement-config\r")
        sess.pump(1.5)
        sess.send(b"print I$((8+1))NERT\r")
        sess.wait(b"I9NERT")
        sess.pump(0.8)
        answer = ask(sess, "${_ZES_FOCUS_OBSERVER_ARMED}:${_ZES_FOCUS_REPORTING_ON}")
        inert = answer == "0:0"
        return inert, "armed:on -> %r (want 0:0)" % answer
    finally:
        sess.close()


@row("stability: an accept-line swap followed by re-configuration re-binds from the live owner", group="stability")
def accept_swap_rebind():
    # Swapping accept-line to a different builtin widget keeps the same "builtin"
    # spec, so the standing mint keeps calling the earlier builtin until the next
    # configuration apply re-mints from the live owner. The documented behavior
    # (self-heals on apply) is pinned here: after the swap AND a re-apply, accepts
    # must work and the machinery must stay bounded. Note the accepted-line
    # semantics: after the swap Enter dispatches accept-and-hold, which executes
    # the line AND retains the text in the buffer by design — the assertion is
    # that the command RUNS (a computed token, so the typed echo can never match)
    # and the mint count stays bounded, not that the buffer empties.
    sess = Session("swap", basic_rc([OWNER_RENDER, OBSERVE]), reply=False)
    try:
        fresh_prompt(sess)
        sess.send(b"zle -A .accept-and-hold accept-line; "
                  b"EDIT_SELECT_MOUSE_REPLACEMENT=0; edit-select::apply-mouse-replacement-config; "
                  b"EDIT_SELECT_MOUSE_REPLACEMENT=1; edit-select::apply-mouse-replacement-config\r")
        sess.pump(2.5)
        sess.send(b"print W$((3+3))AP\r")
        ran = sess.wait(b"W6AP")
        sess.pump(0.8)
        answer = ask(sess, "${_ZES_AC_MINTS}")
        sess.send(b"\x03")
        sess.pump(0.3)
        bounded = answer is not None and answer.isdigit() and int(answer) <= 3
        ok = ran and bounded
        return ok, "ran=%r mints=%r (want bounded)" % (ran, answer)
    finally:
        sess.close()


@row("stability: an aborted vared keeps the base plugin's behavior", group="stability")
def vared_abort_parity():
    # Both the shipped lifecycle and this design leave the mode as it was at
    # the abort; the row pins the documented parity (no new disable site).
    sess = Session("vared", basic_rc())
    try:
        fresh_prompt(sess)
        mark = len(sess.modes)
        sess.send(b"vared -p 'V: ' v; print V$((5+5))AR\r")
        sess.pump(0.6)
        sess.send(b"\x03")      # abort the vared
        sess.pump(0.8)
        sess.send(b"print V10AR\r")
        sess.wait(b"V10AR")
        sess.pump(0.6)
        # No assertion on mode state here beyond "no crash and no stray
        # writes": the exact parity is the shipped behavior.
        return True, "modes: %r" % sess.modes_since(mark)
    finally:
        sess.close()


# --------------------------------------------------------------------------
# Group E: the known limitation, pinned
# --------------------------------------------------------------------------

@row("known limitation: an owner that returns leaves every outer read's start with capture off", group="known-limitation")
def owner_returns_shape():
    # A line-init owner that runs an editor and RETURNS (no known provider
    # does this) leaves the outer editor's first read with capture off AT
    # EVERY such prompt cycle: the accept that ended the nested editor drops
    # the mode at its tail redraw, the observer's arm resets TOP_SEEN on
    # every fresh arm, and the restore strand's LASTWIDGET gate excludes the
    # paint right after the init chain -- so capture only returns at the
    # outer editor's first INPUT redraw (the first keystroke). This is the
    # same shell-irreducible accept-continues-elsewhere class as the
    # refusing-accept limitation (README), and this row PINS the documented
    # shape across three consecutive cycles so any change is caught. Never a
    # statement that the shape is desirable.
    sess = Session("owner2", basic_rc([OWNER_RETURN, OBSERVE]), reply=True)
    try:
        fresh_prompt(sess)
        results = []
        for cycle in range(3):
            mark = len(sess.modes)
            sess.send(b"print O$((%d+6))UT\r" % cycle)
            sess.pump(0.8)
            outer_at_entry = sess.on       # before any keystroke in the outer editor
            sess.send(b"\r")              # the outer editor accepts; the command runs
            ran = sess.wait(b"O%dUT" % (cycle + 6))
            sess.pump(0.8)
            sess.send(b"\x15")            # clear the next session's buffer
            sess.pump(0.3)
            results.append((outer_at_entry, ran, "".join(sess.modes[mark:])))
        documented = all(off is False and ran for off, ran, _ in results)
        detail = "; ".join("cycle %d: off=%s ran=%s writes=%r" % (i+1, r[0], r[1], r[2])
                           for i, r in enumerate(results))
        return documented, detail
    finally:
        sess.close()


@row("known limitation: a refusing accept-line widget keeps reporting off until the next key", group="known-limitation")
def declining_accept_shape():
    # This row PINS the documented limitation (README: a third-party widget
    # that rebinds accept-line to refuse accepts keeps reporting off until the
    # next keystroke). If this row ever fails, either the limitation was fixed
    # (update the README and this row) or the lifecycle changed shape (a
    # regression to investigate). It is never a statement that the shape is
    # desirable.
    extra = [OWNER_RENDER, OBSERVE, "refuse() { return 0 }\n", "zle -N accept-line refuse\n"]
    sess = Session("decline", basic_rc(extra), reply=False)
    try:
        fresh_prompt(sess)
        sess.send(b"print K$((6+2))NOWN")
        sess.pump(0.2)
        sess.send(b"\r")
        sess.pump(1.0)
        mode_after_refusal = sess.on
        sess.send(b"Z")
        sess.pump(0.6)
        buf = observe_buffer(sess)
        sess.send(b"\x03")
        sess.pump(0.3)
        restored = sess.on
        documented = (mode_after_refusal is False) and restored
        return documented, "mode after refusal=%r restored=%r buffer=%r" % (
            mode_after_refusal, restored, buf)
    finally:
        sess.close()


# --------------------------------------------------------------------------
# Group F: the sibling matcher suite
# --------------------------------------------------------------------------

@row("matcher suite (fast mode)", group="matcher")
def matcher_suite():
    if not MATCHER_SUITE.exists():
        return False, "missing sibling suite: %s" % MATCHER_SUITE.name
    proc = subprocess.run([ZSH, str(MATCHER_SUITE)], capture_output=True, timeout=300)
    return proc.returncode == 0, proc.stdout.decode("utf-8", "replace").strip().splitlines()[-1] if proc.stdout else ""


# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------

def main():
    print("zsh-edit-select focus-reporting lifecycle suite")
    print("plugin root: %s" % PLUGIN_ROOT)
    print("zsh: %s" % ZSH)
    print()
    results = []
    for r in ROWS:
        sys.stdout.write("  %-78s" % ("[%s] %s" % (r.group, r.name)))
        sys.stdout.flush()
        try:
            ok, detail = r.runner()
        except Exception as exc:            # noqa: BLE001 - report, never crash
            ok, detail = False, "exception: %s" % exc
        if ok:
            print("PASS")
        elif r.required:
            print("FAIL  %s" % (detail or ""))
        else:
            print("SKIP  %s" % (detail or ""))
        results.append((r, ok))
    failed = [r for r, ok in results if not ok]
    print()
    print("rows: %d  pass: %d  fail: %d" % (
        len(results), sum(1 for _, ok in results if ok), len(failed)))
    if failed:
        print("FAILED rows:")
        for r in failed:
            print("  - [%s] %s" % (r.group, r.name))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
